#!/usr/bin/env python3
"""
Refuse to deploy metadata the org knows more about than this branch does.

Two branches deploy to one org here, so the org — not git — is where they
meet. A deploy of a shared file silently replaces whatever the other branch
put there: that is how the "+ New Prospect Page" button was removed, and how
MaSavedConfigurationController would lose half its methods if this branch's
copy were ever deployed.

This retrieves the org's current version of each named component and compares
it to the local one. It does not care about formatting or ordering; it cares
about one thing: does the org contain something this branch does not?

    scripts/check-org-drift.py ApexClass:MaSavedConfigurationController ...
    scripts/check-org-drift.py --changed          # everything git says changed

Exit 0 = safe to deploy. Exit 1 = the org has content you would destroy.
"""
import os
import re
import subprocess
import sys
import tempfile

ORG = os.environ.get("SF_TARGET_ORG", "gtm-dev")

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
    subprocess.run(
        ["sf", "project", "retrieve", "start", "--target-org", ORG,
         "--target-metadata-dir", into]
        + sum([["-m", c] for c in components], []),
        cwd=ROOT, capture_output=True, text=True, timeout=600)
    zips = [f for f in os.listdir(into) if f.endswith(".zip")]
    if not zips:
        return False
    subprocess.run(["unzip", "-oq", zips[0]], cwd=into, capture_output=True)
    return True


def meaningful(text):
    """Comparable content: identifiers, not whitespace or attribute order."""
    return set(t for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", text))


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 0
    components = changed_components() if args[0] == "--changed" else args
    components = [c for c in components if c.split(":")[0] in KINDS]
    if not components:
        print("Nothing to check.")
        return 0

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
