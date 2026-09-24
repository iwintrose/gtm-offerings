#!/usr/bin/env python3
"""
Idempotency pre-check for seed loading (used by scripts/deploy-fresh-org.sh).

`sf data import tree` cannot upsert: importing rows that already exist fails
with DUPLICATE_VALUE on the unique key. Rather than build a loader, ask the org
first, with ONE query per seed file, and let the caller skip a file whose rows
are already there. Existing rows are never touched, so edits made by content
managers survive a re-run.

    python3 scripts/seed-precheck.py <seed.json> <org-alias>
    python3 scripts/seed-precheck.py --synthetic <org-alias>

Exit codes (a query failure is exit 1; the caller must stop, not guess):
    0   none of the rows exist        -> load the file
    10  every row already exists      -> skip ("already loaded")
    11  only SOME rows exist          -> skip and warn; loading would either
                                         fail or duplicate
    1   the query failed, or the file's object has no known unique key
    2   usage

--synthetic checks the demo data instead. Demo rows have no unique key, but the
five custom objects carry Is_Synthetic__c (the authoritative tag), so any
Is_Synthetic__c = true saved configuration means the demo set was loaded.

Only the counts are printed. No usernames, tokens or values are printed.
"""
import json
import os
import subprocess
import sys

# sObject -> the unique field its seed rows are keyed by. scripts/check-
# references.py verifies every seeded object is listed here, that each row has
# the field, and that the field is unique in source.
UNIQUE_KEYS = {
    "GTM_Page_Section__c": "Section_Address__c",
    "GTM_Page_Content__c": "Content_Address__c",
}


def soql(org, query):
    out = subprocess.run(
        ["sf", "data", "query", "--target-org", org, "--query", query, "--json"],
        capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
        return data["result"]["records"]
    except Exception:
        print("seed pre-check: the existence query failed; not loading.",
              file=sys.stderr)
        sys.exit(1)


def lit(v):
    return "'" + str(v).replace("\\", "\\\\").replace("'", "\\'") + "'"


def main(argv):
    if len(argv) == 3 and argv[1] == "--synthetic":
        rows = soql(argv[2], "SELECT Id FROM GTM_Saved_Configuration__c "
                             "WHERE Is_Synthetic__c = true LIMIT 1")
        print("demo data: %s" % ("already present" if rows else "not present"))
        return 10 if rows else 0
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, org = argv[1], argv[2]
    with open(path, encoding="utf-8") as fh:
        records = json.load(fh).get("records", [])
    types = {r["attributes"]["type"] for r in records}
    if len(types) != 1 or next(iter(types)) not in UNIQUE_KEYS:
        print("seed pre-check: %s has no known unique key for %s; add it to "
              "UNIQUE_KEYS." % (os.path.basename(path), sorted(types)),
              file=sys.stderr)
        return 1
    obj = next(iter(types))
    key = UNIQUE_KEYS[obj]
    wanted = [r[key] for r in records]
    rows = soql(org, "SELECT %s FROM %s WHERE %s IN (%s)"
                % (key, obj, key, ",".join(lit(w) for w in wanted)))
    have = {r[key] for r in rows}
    n = len(set(wanted))
    print("%s: %d of %d rows already present" % (os.path.basename(path),
                                                len(have & set(wanted)), n))
    if not have:
        return 0
    return 10 if have >= set(wanted) else 11


if __name__ == "__main__":
    sys.exit(main(sys.argv))
