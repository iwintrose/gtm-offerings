#!/usr/bin/env python3
"""
Validates that a template component and its seed record set agree.

Catches the two defect classes that have actually bitten this project:

  1. A getter reads a content key that no record supplies (the page silently
     falls back to hardcoded DEFAULTS, so an edit in the Content Manager
     appears to save but changes nothing).
  2. A record's Field_Type__c disagrees with how the template renders it
     (a 'rich' row rendered as plain text shows raw &#39; entities; a 'text'
     row rendered through lightning-formatted-rich-text loses its markup).

Offering-agnostic by construction: nothing here knows about Migration
Accelerator. The contract is derived from the component source, so adding an
offering or a template means adding a TEMPLATES entry, not editing logic.

Usage:  python3 scripts/check-content-contract.py
Exit:   0 = contract holds, 1 = mismatch (suitable for CI)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# One entry per rendered template. Add offerings/templates here; the checks
# below never need to change.
TEMPLATES = [
    {
        "name": "story",
        "js": "force-app/main/default/lwc/maStory/maStory.js",
        "html": "force-app/main/default/lwc/maStory/maStory.html",
        "seed": "data/seed/migration-accelerator.story.records.json",
    },
]


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return fh.read()


def contract_from_component(js, html):
    """Derive {key: expected Field_Type__c} from the component source."""
    text_keys = set(re.findall(r"_ct\('([^']+)'\)", js))
    json_keys = set(re.findall(r"_cj\('([^']+)'\)", js))

    # Getter name -> content key, for every getter that resolves a _ct key.
    getter_to_key = dict(
        re.findall(r"get\s+(\w+)\s*\(\)\s*\{[^}]*?_ct\('([^']+)'\)", js, re.S)
    )
    # Getters piped through lightning-formatted-rich-text must be stored 'rich'.
    rich_getters = set(
        re.findall(r"<lightning-formatted-rich-text\s+value=\{(\w+)\}", html)
    )
    rich_keys = {getter_to_key[g] for g in rich_getters if g in getter_to_key}

    contract = {}
    for key in text_keys:
        contract[key] = "rich" if key in rich_keys else "text"
    for key in json_keys:
        contract[key] = "json"
    return contract


def types_from_seed(seed):
    out = {}
    for rec in json.loads(seed)["records"]:
        out["%s::%s" % (rec["Section_Key__c"], rec["Field_Key__c"])] = rec["Field_Type__c"]
    return out


def main():
    failures = []
    for tpl in TEMPLATES:
        name = tpl["name"]
        contract = contract_from_component(read(tpl["js"]), read(tpl["html"]))
        seeded = types_from_seed(read(tpl["seed"]))

        for key in sorted(set(contract) - set(seeded)):
            failures.append(
                "%s: '%s' is read by the component but no record supplies it "
                "(page will fall back to DEFAULTS)" % (name, key)
            )
        for key in sorted(set(seeded) - set(contract)):
            failures.append(
                "%s: '%s' has a record but nothing reads it (dead row)" % (name, key)
            )
        for key in sorted(set(contract) & set(seeded)):
            if contract[key] != seeded[key]:
                failures.append(
                    "%s: '%s' is stored as '%s' but the template renders it as '%s'"
                    % (name, key, seeded[key], contract[key])
                )

        print("%s: %d keys read, %d records seeded" % (name, len(contract), len(seeded)))

    if failures:
        print("\nCONTRACT VIOLATIONS (%d):" % len(failures))
        for f in failures:
            print("  x " + f)
        return 1

    print("\nContract holds: every key read has a record, every record is read, "
          "all types match how the template renders them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
