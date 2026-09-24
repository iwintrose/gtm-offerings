#!/usr/bin/env python3
"""
Rename every custom metadata record whose DeveloperName contains two
consecutive underscores.

WHY THIS EXISTS
---------------
The assessment instrument names a migration pair after the two platforms it
joins: `hubspot__mcn`, `any__mcn`, `sfmc__mcn`, `eloqua__sfmc`, and the six
`GTM_Migration_Pair` records use the same spelling. Salesforce documents
DeveloperName as disallowing two consecutive underscores. Nothing in this repo
has ever been deployed to a real org, so the spelling is unproven in both
directions: the "existing GTM_Migration_Pair precedent" that
scripts/build-instrument.py points at was written in the same unverified batch
and proves nothing.

Being wrong costs a failed first deploy for whoever picks this up, so the fix
lives here, one command away, rather than in a paragraph of a runbook.

WHAT IT CHANGES
---------------
  instrument/<offering-key>/pairs/<a>__<b>.yaml
      -> pairs/<a>_to_<b>.yaml, and the `name:` line inside it, which is what
         build-instrument.py actually reads (the filename is only a filename)
  force-app/main/default/customMetadata/GTM_Migration_Pair.<a>__<b>.md-meta.xml
      -> GTM_Migration_Pair.<a>_to_<b>.md-meta.xml

and nothing else, because nothing else needs it:

  * The GTM_Assessment_Pair and GTM_Assessment_Dimension_Override records are
    GENERATED from the pair YAML filename. Renaming the YAML and re-running
    scripts/build-instrument.py regenerates every one of them, including the
    Pair__c value that ties an override to its pack.
  * Apex never constructs a pair key. GtmAssessmentInstrument reads
    DeveloperName off the row and hands it back; GtmMigrationPairs matches on
    Source_Key__c/Target_Key__c and never looks at DeveloperName at all. So a
    rename is a data rename, not a code change.
  * The Apex tests build their own in-memory pair rows with literal names.
    Those are fixtures, not references to these records, and they keep passing
    whatever these are called.

WHAT IT DOES NOT CHANGE, AND YOU SHOULD KNOW ABOUT
--------------------------------------------------
GTM_Assessment_Request__c.Instrument_Pair__c stores the pack name that scored a
given assessment. Rows scored before a rename keep the old name and will not
re-resolve their chain (GtmAssessmentInstrument.resolveStoredPack matches on
DeveloperName). In a fresh org there are no such rows, which is the case this
script is for. In an org with scored assessments already in it, decide
deliberately.

Usage:
    python3 scripts/rename-pair-keys.py            # show what would change
    python3 scripts/rename-pair-keys.py --apply    # do it
    python3 scripts/rename-pair-keys.py --apply --separator _x_

Then always:
    python3 scripts/build-instrument.py
    python3 scripts/check-references.py
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTRUMENT = os.path.join(ROOT, "instrument")
CMDT = os.path.join(ROOT, "force-app", "main", "default", "customMetadata")


def pair_dirs():
    """Every offering's pairs/ directory (ADR-0007 / ADR-0009).

    There is no single flat pairs/ directory and there has not been one since
    ADR-0007 split the instrument per offering: pairs live at
    instrument/<offering-key>/pairs/. This used to be hardcoded to one
    non-existent flat path, which plan()'s isdir guard turned into a silent
    "nothing to rename" -- the tool reported success while scanning nothing.
    Iterating the offering directories keeps it correct as offerings are added.
    """
    out = []
    if not os.path.isdir(INSTRUMENT):
        return out
    for name in sorted(os.listdir(INSTRUMENT)):
        pairs = os.path.join(INSTRUMENT, name, "pairs")
        if os.path.isdir(pairs):
            out.append(pairs)
    return out


def plan(sep):
    """Every rename this would do, as (old path, new path, old key, new key)."""
    moves = []
    for pairs in pair_dirs():
        for f in sorted(os.listdir(pairs)):
            if not f.endswith(".yaml"):
                continue
            key = f[:-5]
            if "__" not in key:
                continue
            new = key.replace("__", sep)
            moves.append((os.path.join(pairs, f),
                          os.path.join(pairs, new + ".yaml"), key, new))
    for f in sorted(os.listdir(CMDT)) if os.path.isdir(CMDT) else []:
        if not f.endswith(".md-meta.xml"):
            continue
        stem = f[: -len(".md-meta.xml")]
        if "." not in stem:
            continue
        type_name, dev = stem.split(".", 1)
        if "__" not in dev:
            continue
        # The generated types are rebuilt from YAML, not renamed in place --
        # renaming them here would leave the build to delete and recreate them
        # anyway, and would hide a stale file if the build were skipped.
        if type_name.startswith("GTM_Assessment_"):
            continue
        new = dev.replace("__", sep)
        moves.append((os.path.join(CMDT, f),
                      os.path.join(CMDT, "%s.%s.md-meta.xml" % (type_name, new)),
                      dev, new))
    return moves


def git_mv(old, new):
    """Use git mv where the file is tracked, so history follows the rename."""
    try:
        subprocess.run(["git", "mv", old, new], cwd=ROOT, check=True,
                       capture_output=True)
        return
    except (subprocess.CalledProcessError, FileNotFoundError):
        os.rename(old, new)


def main():
    ap = argparse.ArgumentParser(
        description="Rename pair DeveloperNames that use two consecutive "
                    "underscores, which Salesforce documents as illegal.")
    ap.add_argument("--apply", action="store_true",
                    help="perform the renames (default is to print them only)")
    ap.add_argument("--separator", default="_to_",
                    help="what to replace '__' with (default: _to_)")
    args = ap.parse_args()

    if not re.match(r"^_[A-Za-z0-9]+_$|^_$", args.separator) or "__" in args.separator:
        print("A separator that itself contains '__', or that would leave a "
              "trailing underscore, defeats the point.", file=sys.stderr)
        return 2

    moves = plan(args.separator)
    if not moves:
        print("Nothing to rename: no DeveloperName in source contains '__'.")
        return 0

    for old, new, okey, nkey in moves:
        if os.path.exists(new):
            print("x %s already exists -- refusing to overwrite it"
                  % os.path.relpath(new, ROOT), file=sys.stderr)
            return 1
        print("  %-22s -> %-22s   (%s)"
              % (okey, nkey, os.path.relpath(os.path.dirname(old), ROOT)))

    if not args.apply:
        print("\n%d renames. Nothing changed -- re-run with --apply." % len(moves))
        return 0

    for old, new, okey, nkey in moves:
        git_mv(old, new)
        if new.endswith(".yaml"):
            # The filename is cosmetic; build-instrument.py names the pack from
            # the `name:` key inside the document. Renaming only the file would
            # look like it worked and change nothing.
            with open(new, encoding="utf-8") as fh:
                body = fh.read()
            patched = re.sub(r"(?m)^name:\s*%s\s*$" % re.escape(okey),
                             "name: %s" % nkey, body)
            if patched == body:
                print("x %s has no `name: %s` line to rewrite -- stopping "
                      "before this gets half-done"
                      % (os.path.relpath(new, ROOT), okey), file=sys.stderr)
                return 1
            with open(new, "w", encoding="utf-8") as fh:
                fh.write(patched)

    print("\n%d renamed. Now run, in this order:" % len(moves))
    print("    python3 scripts/build-instrument.py     # regenerates every")
    print("                                            # GTM_Assessment_* record")
    print("                                            # under the new names")
    print("    python3 scripts/check-references.py     # confirms nothing dangles")
    print("    npx sfdx-lwc-jest")
    print("\nThe generated GTM_Assessment_Pair / GTM_Assessment_Dimension_Override")
    print("files still on disk under the OLD names are now stale. The build")
    print("writes the new ones; delete the old ones it no longer lists.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
