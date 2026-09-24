#!/usr/bin/env python3
"""
Refuse to deploy metadata the org knows more about than this branch does.

Two branches deploy to one org here, so the org — not git — is where they
meet. A deploy of a shared file silently replaces whatever the other branch
put there: that is how the "+ New Prospect Page" button was removed, and how
GtmSavedConfigurationController would lose half its methods if this branch's
copy were ever deployed.

This retrieves the org's current version of each named component and compares
it to the local one. It does not care about formatting or ordering; it cares
about one thing: does the org contain something this branch does not?

    scripts/check-org-drift.py ApexClass:GtmSavedConfigurationController ...
    scripts/check-org-drift.py --changed          # everything git says changed

Exit 0 = safe to deploy. Exit 1 = the org has content you would destroy.
"""
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import sf_guard  # noqa: E402

# No default org: --org <alias> or SF_TARGET_ORG. gtm-dev is refused by scripts/lib/sfx.
ORG = os.environ.get("SF_TARGET_ORG", "")

# type -> (source directory, file suffix)
KINDS = {
    "ApexClass": ("classes", ".cls"),
    "PermissionSet": ("permissionsets", ".permissionset-meta.xml"),
    "Profile": ("profiles", ".profile-meta.xml"),
    "CustomApplication": ("applications", ".app-meta.xml"),
    "FlexiPage": ("flexipages", ".flexipage-meta.xml"),
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "force-app", "main", "default")


def changed_components():
    """Everything git reports as modified, mapped to metadata components."""
    out = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"], cwd=ROOT,
        capture_output=True, text=True).stdout
    found = []
    for path in out.splitlines():
        for kind, (folder, suffix) in KINDS.items():
            marker = "/%s/" % folder
            if marker in path and path.endswith(suffix):
                name = os.path.basename(path)[: -len(suffix)]
                found.append("%s:%s" % (kind, name))
    return sorted(set(found))


def retrieve(components, into):
    sf_guard.sf(
        ["project", "retrieve", "start", "--target-org", ORG,
         "--target-metadata-dir", into]
        + sum([["-m", c] for c in components], []),
        capture=True, cwd=ROOT, timeout=600)
    zips = [f for f in os.listdir(into) if f.endswith(".zip")]
    if not zips:
        return False
    subprocess.run(["unzip", "-oq", zips[0]], cwd=into, capture_output=True)
    return True


# Elements the platform adds to a retrieve whether or not the source declares
# them. They are not another branch's work, so flagging them is noise.
PLATFORM_NOISE = {
    "hasActivationRequired", "userLicense",
    "isNavTabPersistenceDisabled", "isOmniPinnedViewEnabled",
    "shouldOverrideOrgTheme", "isServiceCloudConsole",
}


def meaningful(text):
    """Comparable content: identifiers, not whitespace or attribute order."""
    return set(re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", text)) - PLATFORM_NOISE


def main():
    global ORG
    args = sys.argv[1:]
    args = [a for a in args if a != "--allow-production"]  # consumed by the sfx session
    if "--org" in args:
        i = args.index("--org")
        ORG = args[i + 1] if i + 1 < len(args) else ""
        del args[i:i + 2]
    if not args:
        print(__doc__)
        return 0
    components = changed_components() if args[0] == "--changed" else args
    components = [c for c in components if c.split(":")[0] in KINDS]
    if not components:
        print("Nothing to check.")
        return 0

    if not ORG:
        print("No explicit org: pass --org <alias> or set SF_TARGET_ORG (agent work uses gtm-staging).")
        return 2
    sf_guard.ensure_session()
    with tempfile.TemporaryDirectory() as tmp:
        if not retrieve(components, tmp):
            print("Could not retrieve from %s — check the deploy by hand." % ORG)
            return 1
        base = os.path.join(tmp, "unpackaged")
        problems = []
        for comp in components:
            kind, name = comp.split(":", 1)
            folder, suffix = KINDS[kind]
            org_suffix = ".cls" if kind == "ApexClass" else suffix.replace("-meta.xml", "")
            org_path = os.path.join(base, folder, name + org_suffix)
            local_path = os.path.join(SRC, folder, name + suffix)
            if not os.path.exists(org_path) or not os.path.exists(local_path):
                continue
            org_only = meaningful(open(org_path).read()) - meaningful(open(local_path).read())
            if org_only:
                problems.append((comp, sorted(org_only)[:12], len(org_only)))

        if not problems:
            print("Safe: the org has nothing these files would destroy.")
            return 0
        print("STOP — the org has content this branch does not:\n")
        for comp, sample, total in problems:
            print("  %s — %d identifiers only in the org" % (comp, total))
            print("     e.g. %s" % ", ".join(sample))
        print("\nAnother branch deployed this. Merge it before deploying these files.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
