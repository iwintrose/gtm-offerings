#!/usr/bin/env python3
"""
Whole-app reference audit.

Answers "what would break if I removed this?" across EVERY metadata type that
can reference a component, not just the obvious ones. Written after deleting
four LWC bundles on the strength of a grep that covered only *.html and *.js
inside force-app/main/default/lwc - which cannot see a Custom Tab, a
FlexiPage, an Experience Cloud view, an app's nav, or a permission set.

Reports, per Lightning component and Apex class:
  - every place that references it, by metadata type
  - anything referenced but missing from source (a dangling pointer)
  - anything defined but referenced nowhere (a genuine orphan)

Usage:  python3 scripts/check-references.py
Exit:   0 = no dangling references, 1 = something points at a missing thing
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "force-app", "main", "default")


def kebab(name):
    """gtmStory -> gtm-story, so c-gtm-story is findable."""
    return re.sub(r"(?<!^)(?=[A-Z])", "-", name).lower()


def walk(root):
    for base, _dirs, files in os.walk(root):
        for f in files:
            yield os.path.join(base, f)


def metadata_kind(path):
    rel = os.path.relpath(path, SRC)
    top = rel.split(os.sep)[0]
    return {
        "lwc": "LWC",
        "aura": "Aura",
        "classes": "Apex",
        "tabs": "CustomTab",
        "applications": "App",
        "flexipages": "FlexiPage",
        "experiences": "ExperienceSite",
        "permissionsets": "PermissionSet",
        "profiles": "Profile",
        "objects": "Object",
        "flows": "Flow",
        "customMetadata": "CustomMetadata",
        "genAiPlugins": "GenAiPlugin",
        "bots": "Bot",
        "layouts": "Layout",
    }.get(top, top)


def main():
    lwcs = sorted(
        d for d in os.listdir(os.path.join(SRC, "lwc"))
        if os.path.isdir(os.path.join(SRC, "lwc", d))
    ) if os.path.isdir(os.path.join(SRC, "lwc")) else []

    apex = sorted(
        f[:-4] for f in os.listdir(os.path.join(SRC, "classes"))
        if f.endswith(".cls")
    ) if os.path.isdir(os.path.join(SRC, "classes")) else []

    # Read every source file once.
    files = {}
    for path in walk(SRC):
        if path.endswith((".xml", ".json", ".js", ".html", ".cls", ".css")):
            try:
                with open(path, encoding="utf-8") as fh:
                    files[path] = fh.read()
            except (UnicodeDecodeError, OSError):
                pass

    def refs_to(patterns, own_dir=None):
        hits = {}
        for path, text in files.items():
            if own_dir and os.sep + own_dir + os.sep in path:
                continue  # a component referencing itself is not a dependant
            for pat in patterns:
                if pat in text:
                    hits.setdefault(metadata_kind(path), set()).add(
                        os.path.relpath(path, ROOT))
                    break
        return hits

    print("=" * 72)
    print("LIGHTNING COMPONENTS")
    print("=" * 72)
    orphans = []
    for name in lwcs:
        # Every form a reference can take. Missing one of these is how four
        # bundles got deleted on the strength of an audit that saw nothing:
        #   c-gtm-story         markup composition
        #   c/gtmStory          ES module import
        #   c:gtmStory          FlexiPage and Experience Cloud view JSON
        #   <lwcComponent>      Custom Tab
        hits = refs_to([f"c-{kebab(name)}", f"c/{name}", f"c:{name}",
                        f"<componentName>{name}</componentName>",
                        f"<lwcComponent>{name}</lwcComponent>"], own_dir=name)
        if hits:
            where = ", ".join(f"{k}({len(v)})" for k, v in sorted(hits.items()))
            print(f"  {name:<24} <- {where}")
        else:
            orphans.append(name)
            print(f"  {name:<24} <- NOTHING (orphan)")

    print()
    print("=" * 72)
    print("APEX CLASSES  (grants shown so a guest-facing class is obvious)")
    print("=" * 72)
    for name in apex:
        if name.endswith("Test"):
            continue
        # An Apex class called only by other Apex, or wired to an Agentforce
        # action, is not unreferenced. Counting only LWC imports and grants
        # reported MaContentAddress and the MaAgent* classes as dead.
        hits = refs_to([f"apex/{name}.", f"<apexClass>{name}</apexClass>",
                        f"{name}.", f"<invocationTarget>{name}</invocationTarget>"],
                       own_dir=None)
        where = ", ".join(f"{k}({len(v)})" for k, v in sorted(hits.items())) or "NOTHING"
        print(f"  {name:<32} <- {where}")

    # Dangling: something referenced that no longer exists in source.
    print()
    print("=" * 72)
    print("DANGLING REFERENCES")
    print("=" * 72)
    dangling = []
    known = set(lwcs)
    for path, text in files.items():
        for m in re.findall(r"<lwcComponent>(\w+)</lwcComponent>", text):
            if m not in known:
                dangling.append((os.path.relpath(path, ROOT), "lwcComponent", m))
        # Only quoted "c:name" counts. Bare c: also appears as the CSS
        # pseudo-class :hover and in HTML attributes, which are not references.
        for m in re.findall(r'"c:(\w+)"', text):
            if m not in known:
                dangling.append((os.path.relpath(path, ROOT), "c: reference", m))
        for m in re.findall(r"<apexClass>(\w+)</apexClass>", text):
            if m not in set(apex):
                dangling.append((os.path.relpath(path, ROOT), "apexClass", m))
    if dangling:
        for where, kind, what in dangling:
            print(f"  x {where} references missing {kind} '{what}'")
    else:
        print("  none")

    print()
    print(f"Orphaned components: {', '.join(orphans) if orphans else 'none'}")
    if orphans:
        # This scans the branch, and the branch is not the org. maAdminBar and
        # gtmAppShell both read as orphans here while the org had them placed
        # on live Experience Cloud pages -- the delete failed and said so.
        print()
        print("  These are unreferenced IN THIS BRANCH. Experience Builder keeps its")
        print("  own page layouts in the org, and a deploy of the site bundles does")
        print("  not always round-trip them. Before deleting any of these, confirm")
        print("  against the org:")
        print()
        print("      sf project retrieve start --metadata ExperienceBundle \\")
        print("        --target-metadata-dir /tmp/exp")
        print("      unzip -o /tmp/exp/unpackaged.zip -d /tmp/exp")
        print("      grep -rl '<NAME>' /tmp/exp/unpackaged/experiences/")
        print()
        print("  A destructive deploy also refuses and names the pages, which is the")
        print("  authoritative answer.")
    return 1 if dangling else 0


if __name__ == "__main__":
    sys.exit(main())
