#!/usr/bin/env python3
"""Add the GTM related lists to a standard-object layout retrieved from an org.

Inserts ONLY two <relatedLists> blocks (Assessment Requests, Engagement Links)
into a Layout XML that was retrieved from the TARGET org, so a later deploy of
that file changes nothing else. Contract: docs/architecture/gtm-related-lists.md.

Usage:
  python3 scripts/patch-related-lists-layouts.py --object Account LAYOUT.xml [--in-place | --out FILE]
  (--object may be omitted when the file name starts with Account-/Contact-/Opportunity-)

Stdlib only. Idempotent: a list already present (same <relatedList> value) is
left alone and not duplicated. Prints a unified diff. Refuses (exit 2, nothing
written) unless every changed line in the diff is an addition belonging to the
two blocks. Exit 0 = patched or already up to date, 2 = refused / bad input.
Retrieve into a scratch dir OUTSIDE the repo; never commit full standard layouts.
"""
import argparse
import difflib
import os
import re
import sys

AR_COLS = ["NAME", "Status__c", "Assessment_Tier__c", "Assessment_Score__c", "Submitted_At__c"]
SC_COLS = ["NAME", "Offering__c", "Presentation_Stage__c", "Active__c"]
OBJECTS = ("Account", "Contact", "Opportunity")

# Layout children that sort after relatedLists (Metadata API alphabetical order).
_AFTER = ["relatedObjects", "runAssignmentRulesDefault", "showEmailCheckbox",
          "showHighlightsPanel", "showInteractionLogPanel", "showKnowledgeComponent",
          "showRunAssignmentRulesCheckbox", "showSolutionSection",
          "showSubmitAndAttachButton", "summaryLayout"]


def wanted(obj):
    return [("GTM_Assessment_Request__c.%s__c" % obj, AR_COLS),
            ("GTM_Saved_Configuration__c.%s__c" % obj, SC_COLS)]


def block(rel, cols, nl):
    lines = ["    <relatedLists>"]
    lines += ["        <fields>%s</fields>" % c for c in cols]
    lines += ["        <relatedList>%s</relatedList>" % rel, "    </relatedLists>"]
    return nl.join(lines) + nl


def patch(text, obj):
    """Return patched text. Only inserts whole blocks; never edits existing lines."""
    nl = "\r\n" if "\r\n" in text else "\n"
    # Top-level blocks only: <miniLayout> can hold its own (8-space) <relatedLists>.
    present = set()
    for b in re.findall(r"^    <relatedLists>.*?^    </relatedLists>", text, re.M | re.S):
        present.update(re.findall(r"<relatedList>\s*([^<\s]+)\s*</relatedList>", b))
    new = "".join(block(r, c, nl) for r, c in wanted(obj) if r not in present)
    if not new:
        return text
    m = re.search(r"^    <relatedLists>", text, re.M)
    if not m:
        for tag in _AFTER:
            m = re.search(r"^    <%s>" % tag, text, re.M)
            if m:
                break
    if not m:
        m = re.search(r"^</Layout>", text, re.M)
    if not m:
        raise ValueError("not a Layout XML (no </Layout>)")
    return text[:m.start()] + new + text[m.start():]


def verify(old, new, obj):
    """Diff must contain only added lines that make up the two blocks."""
    nl = "\r\n" if "\r\n" in old else "\n"
    a, b = old.splitlines(), new.splitlines()
    allowed = set()
    for r, c in wanted(obj):
        allowed.update(block(r, c, "\n").splitlines())
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "equal":
            continue
        if op != "insert":
            return "non-additive change at old lines %d-%d" % (i1 + 1, i2)
        for ln in b[j1:j2]:
            if ln not in allowed:
                return "unexpected added line: %r" % ln
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("layout")
    ap.add_argument("--object", choices=OBJECTS)
    ap.add_argument("--in-place", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--check", action="store_true", help="exit 1 if a patch is needed; write nothing")
    args = ap.parse_args(argv)
    obj = args.object or os.path.basename(args.layout).split("-", 1)[0]
    if obj not in OBJECTS:
        print("cannot infer object from file name; pass --object %s" % "|".join(OBJECTS), file=sys.stderr)
        return 2
    with open(args.layout, newline="", encoding="utf-8") as f:
        old = f.read()
    try:
        new = patch(old, obj)
    except ValueError as e:
        print("refused: %s" % e, file=sys.stderr)
        return 2
    bad = verify(old, new, obj)
    if bad:
        print("refused: %s" % bad, file=sys.stderr)
        return 2
    if new == old:
        print("already up to date: %s (no change)" % args.layout)
        return 0
    sys.stdout.writelines(difflib.unified_diff(
        old.splitlines(True), new.splitlines(True), "retrieved", "patched"))
    if args.check:
        return 1
    dest = args.layout if args.in_place else args.out
    if dest:
        with open(dest, "w", newline="", encoding="utf-8") as f:
            f.write(new)
        print("wrote %s" % dest)
    else:
        print("(dry: pass --in-place or --out to write)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
