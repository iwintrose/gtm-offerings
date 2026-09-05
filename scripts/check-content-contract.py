#!/usr/bin/env python3
"""
Validates that a page template, its section rows and its content rows agree.

The renderer resolves content keys dynamically (sectionKey + '::' + field), so
the contract lives in the LAYOUT_FIELDS map inside the component. This script
reads that map, crosses it with the seeded sections, and derives exactly which
content records must exist and what Field_Type__c each must carry.

Catches the defect classes that have actually bitten this project:
  1. A field a layout renders with no record behind it (page silently shows a
     built-in fallback, so an edit appears to save but changes nothing).
  2. A record whose type disagrees with how the template renders it (a 'rich'
     value rendered as plain text shows raw &#39;; a 'text' value rendered
     through lightning-formatted-rich-text loses its markup).
  3. A content row pointing at a section that does not exist, or a section
     whose layout type has no renderer.

Offering-agnostic: nothing here knows about Migration Accelerator. Adding an
offering or template means adding a TEMPLATES entry.

Usage:  python3 scripts/check-content-contract.py
Exit:   0 = contract holds, 1 = violation (suitable for CI)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The layout vocabulary is shared between the renderer and the editor, so the
# contract is read from the shared module rather than from either consumer.
LAYOUTS_JS = "force-app/main/default/lwc/gtmPageLayouts/gtmPageLayouts.js"

# The value buckets a layout may declare. Each is both the key in LAYOUT_FIELDS
# and the Field_Type__c the seeded record must carry, so adding a field type
# means adding it here and nowhere else in this script.
BUCKETS = ("text", "rich", "json", "icontext")

TEMPLATES = [
    {
        "name": "story",
        "js": LAYOUTS_JS,
        "html": "force-app/main/default/lwc/maStory/maStory.html",
        "sections": "data/seed/migration-accelerator.story.sections.json",
        "content": "data/seed/migration-accelerator.story.records.json",
    },
]


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return fh.read()


def parse_layout_fields(js):
    """Pull LAYOUT_FIELDS out of the component as {layout: {bucket: [fields]}}."""
    block = re.search(r"const LAYOUT_FIELDS = \{(.*?)\n\};", js, re.S)
    if not block:
        raise SystemExit(
            "LAYOUT_FIELDS not found in %s. The layout vocabulary moved to the "
            "shared c/gtmPageLayouts module; if it moved again, update "
            "LAYOUTS_JS in this script." % LAYOUTS_JS
        )
    out = {}
    for name, body in re.findall(r"'([\w-]+)':\s*\{(.*?)\}", block.group(1), re.S):
        spec = {}
        for bucket in BUCKETS:
            m = re.search(bucket + r":\s*\[(.*?)\]", body, re.S)
            spec[bucket] = re.findall(r"'([\w]+)'", m.group(1)) if m else []
        out[name] = spec
    return out


def parse_frame_layouts(js):
    """The layouts drawn outside the section loop, read from the same module.

    Page chrome — the masthead, the footer, the assistant — legitimately has no
    is<Layout> branch inside the sequence. Which layouts those are is already
    declared once in FRAME_LAYOUTS; hardcoding a second copy here is how the two
    drift, and the drift shows up as a false failure the day a layout is added.
    """
    m = re.search(r"const FRAME_LAYOUTS = \[(.*?)\];", js, re.S)
    if not m:
        raise SystemExit("FRAME_LAYOUTS not found in %s" % LAYOUTS_JS)
    return set(re.findall(r"'([\w-]+)'", m.group(1)))


def rendered_layouts(html):
    return set(re.findall(r"if:true=\{s\.is(\w+)\}", html))


def camel(layout):
    return "".join(p.capitalize() for p in layout.split("-"))


def main():
    failures = []
    for tpl in TEMPLATES:
        name = tpl["name"]
        js = read(tpl["js"])
        layouts = parse_layout_fields(js)
        non_sequence = parse_frame_layouts(js)
        drawn = rendered_layouts(read(tpl["html"]))
        sections = json.loads(read(tpl["sections"]))["records"]
        content = json.loads(read(tpl["content"]))["records"]

        seeded = {
            "%s::%s" % (r["Section_Key__c"], r["Field_Key__c"]): r["Field_Type__c"]
            for r in content
        }
        section_keys = {s["Section_Key__c"] for s in sections}

        expected = {}
        for sec in sections:
            layout = sec["Layout_Type__c"]
            if layout not in layouts:
                failures.append(
                    "%s: section '%s' has layout '%s', which LAYOUT_FIELDS does not define"
                    % (name, sec["Section_Key__c"], layout)
                )
                continue
            if layout not in non_sequence and camel(layout) not in drawn:
                failures.append(
                    "%s: layout '%s' is declared but no branch in the template draws it"
                    % (name, layout)
                )
            for bucket, field_type in ((b, b) for b in BUCKETS):
                for field in layouts[layout][bucket]:
                    expected["%s::%s" % (sec["Section_Key__c"], field)] = field_type

        for key in sorted(set(expected) - set(seeded)):
            failures.append(
                "%s: '%s' is rendered but has no record (falls back to a built-in default)"
                % (name, key)
            )
        for key in sorted(set(seeded) - set(expected)):
            sec_key = key.split("::")[0]
            why = ("its section '%s' is not in the section seed" % sec_key
                   if sec_key not in section_keys else "no layout renders it")
            failures.append("%s: '%s' has a record but %s (dead row)" % (name, key, why))
        for key in sorted(set(expected) & set(seeded)):
            if expected[key] != seeded[key]:
                failures.append(
                    "%s: '%s' is stored as '%s' but the template renders it as '%s'"
                    % (name, key, seeded[key], expected[key])
                )

        print("%s: %d sections, %d layouts, %d fields expected, %d records seeded"
              % (name, len(sections), len(layouts), len(expected), len(seeded)))

    if failures:
        print("\nCONTRACT VIOLATIONS (%d):" % len(failures))
        for f in failures:
            print("  x " + f)
        return 1

    print("\nContract holds: every rendered field has a record, every record is "
          "rendered, every layout has a branch, all types match.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
