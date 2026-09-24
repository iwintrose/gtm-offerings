#!/usr/bin/env python3
"""
ONE-TIME migration: instrument/<offering-key>/**/*.yaml (the YAML/CMDT
authoring path built by scripts/build-instrument.py) -> record data for the
new 01-schema instrument-definition objects (GTM_Instrument_Definition__c /
GTM_Instrument_Question_Definition__c / GTM_Instrument_Outcome_Range__c),
per docs/architecture/gtm-instrument-schema.md and
docs/agent-artifacts/task-scope-assessment-instrument-rebuild-03-rule-engine-migration.md.

THIS IS NOT A LOSSLESS DATA PORT. The legacy YAML/CMDT model
(GTM_Assessment_Pair__mdt / GTM_Assessment_Dimension_Override__mdt /
GTM_Assessment_Gate__mdt / GTM_Assessment_Supplement__mdt) expresses concepts
the new schema has no construct for at all:

  - per-source/target PAIR adaptive overrides (reword/recalibrate/substitute
    layers, resolution-chain merging) -- the new schema has one question list
    per instrument, not one per (source, target) pair.
  - answer CEILINGS (max_attainable / ceiling_reason) -- no field for this on
    GTM_Instrument_Question_Definition__c.
  - a second scored axis (Estate Complexity, 6 dimensions, 1-3 each) -- out of
    scope for the Outcome Mapping construct, which is one score -> one range.
  - GATE predicates ({"all"/"any": [{field, op, value}, ...]}) -- structurally
    different from Rules_JSON__c's {logic, conditions[], action, target} shape
    (see docs/architecture/gtm-instrument-schema.md §3.2): gates add a tier
    QUALIFIER without moving the score or hiding a question; Rules_JSON__c
    only ever SHOWs/HIDEs/requires/skips.
  - CALLOUTS (capability-gap narrative blocks) -- no field anywhere in the new
    schema.

So this script does exactly what the task scope asks and NO MORE: it
authors the base 8-slot Readiness frame (dimensions.yaml + the read-only
GTM_Assessment_Question__mdt base wording) as a new
GTM_Instrument_Definition__c + 8 GTM_Instrument_Question_Definition__c rows,
one per slot, Question_Key__c preserved verbatim from dimensions.yaml so any
Rules_JSON__c authored later under sub-issue 04 can reference the same slugs
existing readouts/branch-path history already uses. It also derives the four
score-band GTM_Instrument_Outcome_Range__c rows from
GtmAssessmentScoring.cls's compiled band edges (8-14 / 15-20 / 21-26 / 27-32),
since those are a straight, unambiguous port (§4 of the schema doc).

Everything this script CANNOT safely auto-convert (pair overrides, gates,
complexity axis, supplements, callouts) is enumerated, unconverted, in the
`unmigrated` section of the JSON output and the companion Markdown report --
flagged for a human content author to hand-build in sub-issue 04's editor,
per this sub-issue's scope doc §2 ("their fate ... should be flagged to the
human owner if unclear rather than guessed").

EXECUTION BOUNDARY (binding, do not relax without explicit sign-off):
  - This script only READS instrument/**/*.yaml and the committed
    GTM_Assessment_Question.*.md-meta.xml files, and only WRITES local output
    files under the path given by --out. It never calls `sf`, never opens a
    network connection, and never performs DML of any kind.
  - Turning its output into real gtm-staging records is a SEPARATE, later
    step (Bulk API / sf data import / Apex anonymous, run by a human or the
    coordinator with explicit go-ahead) -- not something this script, or any
    agent, executes on its own. See CLAUDE.md §5 promotion flow.

Usage:
    python3 scripts/migrate-instrument-yaml.py [--offering migration-accelerator] [--out scripts/migration-output]

Run with no org, no network -- pure local YAML/XML parsing, safe to run
repeatedly (idempotent: same inputs always produce the same output).
"""
import argparse
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

try:
    import yaml
except ImportError:  # pragma: no cover - matches build-instrument.py's own guard
    sys.stderr.write(
        "PyYAML is required (pip install pyyaml). This script never touches an "
        "org, so there is no sf/CLI dependency to install instead.\n"
    )
    raise

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTRUMENT_ROOT = os.path.join(REPO_ROOT, "instrument")
CMD_DIR = os.path.join(
    REPO_ROOT, "force-app", "main", "default", "customMetadata"
)
NS = "http://soap.sforce.com/2006/04/metadata"
QUESTION_GLOB = "GTM_Assessment_Question."

# Ported verbatim from GtmAssessmentScoring.cls's compiled Migration
# Accelerator bands (DISCOVERY_FIRST_MAX=14, PREP_REQUIRED_MAX=20,
# ACCELERATOR_READY_MAX=26, MAX_TOTAL_SCORE=32) -- see that class's §"bands"
# for the source of truth this mirrors. A straight, unambiguous port: no
# per-pair band edges exist in the legacy model either (that is the whole
# point of the fixed frame), so there is nothing lossy about this piece.
MIGRATION_ACCELERATOR_BANDS = [
    {"Tier_Label__c": "Discovery First", "Min_Score__c": 8, "Max_Score__c": 14, "Sort_Order__c": 1},
    {"Tier_Label__c": "Prep Required", "Min_Score__c": 15, "Max_Score__c": 20, "Sort_Order__c": 2},
    {"Tier_Label__c": "Accelerator-Ready", "Min_Score__c": 21, "Max_Score__c": 26, "Sort_Order__c": 3},
    {"Tier_Label__c": "Fast-Track", "Min_Score__c": 27, "Max_Score__c": 32, "Sort_Order__c": 4},
]


def load_yaml(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def base_readiness_questions(offering_key):
    """Dimension_Key__c -> parsed field dict, from the hand-authored
    GTM_Assessment_Question.Readiness_*.md-meta.xml rows for this offering.

    These 14 records are the CLAUDE.md-documented exception: read-only for
    scripts/build-instrument.py, and read-only here too -- this script never
    writes CMDT, it only reads the base wording out of it the same way
    scripts/build-instrument.py's base_questions() does.
    """
    out = {}
    if not os.path.isdir(CMD_DIR):
        return out
    for name in sorted(os.listdir(CMD_DIR)):
        if not name.startswith(QUESTION_GLOB):
            continue
        tree = ET.parse(os.path.join(CMD_DIR, name))
        vals = {}
        for v in tree.getroot().findall("{%s}values" % NS):
            f = v.find("{%s}field" % NS).text
            node = v.find("{%s}value" % NS)
            vals[f] = None if node is None else node.text
        if (vals.get("Offering_Key__c") or "").strip() != offering_key:
            continue
        if (vals.get("Instrument__c") or "").strip() != "Readiness":
            continue
        key = (vals.get("Dimension_Key__c") or "").strip()
        if key:
            vals["__file"] = name
            out[key] = vals
    return out


def options_json_for(row):
    """Base CMDT question row -> new-schema Options_JSON__c array (§3.1).

    Points default to the option's own 1-4 value: the base CMDT rows carry no
    independent points field (only per-pair GTM_Assessment_Dimension_Override__mdt
    rows can author non-linear points), so a 1:1 value->points mapping is the
    only choice that does not fabricate data the legacy base pack never had.
    """
    options = []
    for n in (1, 2, 3, 4):
        label = row.get("Option_%d_Label__c" % n)
        if not label:
            continue
        options.append({"label": label, "value": str(n), "points": n})
    return options


def migrate_readiness_slots(offering_key, dims_doc):
    """dimensions.yaml's `slots` + base CMDT wording -> new-schema question rows."""
    wording = base_readiness_questions(offering_key)
    questions = []
    warnings = []
    for slot in dims_doc.get("slots", []):
        key = (slot.get("key") or "").strip()
        position = slot.get("position")
        if not key or position is None:
            warnings.append(
                "dimensions.yaml has a slot with no key/position and was skipped: %r" % slot
            )
            continue
        row = wording.get(key)
        if row is None:
            warnings.append(
                "No GTM_Assessment_Question.Readiness_%s CMDT row found for slot "
                "'%s' -- question authored with no text/options; must be filled "
                "in by hand in sub-issue 04's editor." % (key, key)
            )
        questions.append({
            "Question_Key__c": key,
            "Slot_Order__c": position,
            "Question_Text__c": (row or {}).get("Question_Text__c"),
            "Question_Type__c": "Single_Select",
            "Options_JSON__c": json.dumps(options_json_for(row or {})),
            "Rules_JSON__c": json.dumps([]),
            "Required__c": False,
            # Informative only, not written to any real field -- carried
            # through so a human author can see at a glance which slots were
            # the fixed spine (per dimensions.yaml's own substitutable flag).
            "__substitutable": slot.get("substitutable"),
            "__risk_theme": slot.get("risk_theme"),
            "__source_label": (row or {}).get("Dimension_Name__c"),
        })
    return questions, warnings


def unmigrated_summary(offering_dir):
    """Everything this script deliberately does NOT convert, enumerated so a
    human author knows exactly what sub-issue 04 still has to hand-build.
    Never raises on a missing optional file -- pairs/, supplements/,
    complexity.yaml, gates.yaml are all optional per offering.
    """
    summary = {
        "pairs": [],
        "gates": [],
        "complexity_dimensions": [],
        "supplement_sets": [],
    }

    pairs_dir = os.path.join(offering_dir, "pairs")
    if os.path.isdir(pairs_dir):
        for path in sorted(glob.glob(os.path.join(pairs_dir, "*.yaml"))):
            doc = load_yaml(path)
            summary["pairs"].append({
                "file": os.path.relpath(path, REPO_ROOT),
                "name": doc.get("name"),
                "source": doc.get("source"),
                "target": doc.get("target"),
                "override_count": len(doc.get("overrides") or []),
                "complexity_override_count": len(doc.get("complexity_overrides") or []),
                "callout_count": len(doc.get("callouts") or []),
                "note": (
                    "Per-pair adaptive content (reword/recalibrate/substitute "
                    "layers, ceilings, callouts) has no construct in the new "
                    "schema -- one question list per instrument, not per "
                    "(source, target) pair. Requires hand-authoring, or a "
                    "follow-on schema decision, before this pack's content can "
                    "be represented."
                ),
            })

    gates_path = os.path.join(offering_dir, "gates.yaml")
    if os.path.isfile(gates_path):
        doc = load_yaml(gates_path)
        for gate in doc.get("gates") or []:
            summary["gates"].append({
                "key": gate.get("key"),
                "tier_qualifier": gate.get("tier_qualifier"),
                "severity": gate.get("severity"),
                "note": (
                    "Gate predicates ({all/any: [{field, op, value}]}) are a "
                    "different shape from Rules_JSON__c ({logic, conditions[], "
                    "action, target}) and gates qualify a tier without moving "
                    "the score or hiding a question, which Rules_JSON__c's "
                    "SHOW/HIDE/SKIP_TO_SECTION/MAKE_REQUIRED actions cannot "
                    "express. Not converted."
                ),
            })

    complexity_path = os.path.join(offering_dir, "complexity.yaml")
    if os.path.isfile(complexity_path):
        doc = load_yaml(complexity_path)
        for dim in doc.get("dimensions") or []:
            summary["complexity_dimensions"].append({
                "key": dim.get("key"),
                "position": dim.get("position"),
                "note": (
                    "The second (Estate Complexity) scored axis has no home in "
                    "the new schema's single Outcome Mapping construct. Not "
                    "converted."
                ),
            })

    supplements_dir = os.path.join(offering_dir, "supplements")
    if os.path.isdir(supplements_dir):
        for path in sorted(glob.glob(os.path.join(supplements_dir, "*.yaml"))):
            doc = load_yaml(path)
            summary["supplement_sets"].append({
                "file": os.path.relpath(path, REPO_ROOT),
                "set_key": doc.get("set_key"),
                "question_count": len(doc.get("questions") or []),
                "note": (
                    "Layer-4 supplement questions (outside the 32, their own "
                    "named index) are not modeled by the new schema's flat "
                    "question list. Not converted."
                ),
            })

    return summary


def migrate_offering(offering_key):
    offering_dir = os.path.join(INSTRUMENT_ROOT, offering_key)
    dims_path = os.path.join(offering_dir, "dimensions.yaml")
    if not os.path.isfile(dims_path):
        raise SystemExit(
            "No dimensions.yaml found for offering '%s' under %s -- nothing to "
            "migrate." % (offering_key, offering_dir)
        )
    dims_doc = load_yaml(dims_path)
    questions, warnings = migrate_readiness_slots(offering_key, dims_doc)

    instrument_definition = {
        "Offering_Key__c": offering_key,
        "Status__c": "Draft",
        "Version__c": 1,
        "Theme_Key__c": None,
    }

    result = {
        "offering_key": offering_key,
        "source_version": dims_doc.get("version"),
        "instrument_definition": instrument_definition,
        "question_definitions": questions,
        "outcome_ranges": (
            MIGRATION_ACCELERATOR_BANDS
            if offering_key == "migration-accelerator"
            else []
        ),
        "warnings": warnings,
        "unmigrated": unmigrated_summary(offering_dir),
    }
    return result


def write_report(result, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    json_path = os.path.join(out_dir, "%s-instrument-migration.json" % result["offering_key"])
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, sort_keys=True)
        fh.write("\n")

    md_path = os.path.join(out_dir, "%s-instrument-migration.md" % result["offering_key"])
    lines = []
    lines.append("# Migration report: %s -> 01-schema instrument definition" % result["offering_key"])
    lines.append("")
    lines.append(
        "Generated by `scripts/migrate-instrument-yaml.py`. Local dry-run output "
        "only -- nothing here has been written to any org. See the script's "
        "module docstring for the execution boundary."
    )
    lines.append("")
    lines.append("## Migrated (%d question slots)" % len(result["question_definitions"]))
    lines.append("")
    lines.append("| Position | Question_Key__c | Question Text |")
    lines.append("|---|---|---|")
    for q in result["question_definitions"]:
        lines.append("| %s | `%s` | %s |" % (
            q["Slot_Order__c"], q["Question_Key__c"], (q["Question_Text__c"] or "_(missing)_")[:80]
        ))
    lines.append("")
    lines.append("## Outcome ranges (%d)" % len(result["outcome_ranges"]))
    lines.append("")
    for r in result["outcome_ranges"]:
        lines.append("- %s-%s: %s" % (r["Min_Score__c"], r["Max_Score__c"], r["Tier_Label__c"]))
    lines.append("")
    if result["warnings"]:
        lines.append("## Warnings")
        lines.append("")
        for w in result["warnings"]:
            lines.append("- %s" % w)
        lines.append("")
    lines.append("## NOT migrated (requires hand-authoring in sub-issue 04)")
    lines.append("")
    unmig = result["unmigrated"]
    lines.append("- Per-pair adaptive overrides: %d pair files" % len(unmig["pairs"]))
    for p in unmig["pairs"]:
        lines.append("  - `%s` (%s -> %s): %d overrides, %d callouts" % (
            p["file"], p["source"], p["target"], p["override_count"], p["callout_count"]
        ))
    lines.append("- Gates: %d" % len(unmig["gates"]))
    for g in unmig["gates"]:
        lines.append("  - `%s` (%s)" % (g["key"], g["tier_qualifier"]))
    lines.append("- Estate Complexity dimensions: %d" % len(unmig["complexity_dimensions"]))
    lines.append("- Supplement sets: %d" % len(unmig["supplement_sets"]))
    for s in unmig["supplement_sets"]:
        lines.append("  - `%s` (%d questions)" % (s["set_key"], s["question_count"]))
    lines.append("")

    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    return json_path, md_path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--offering", default="migration-accelerator",
        help="Offering key under instrument/ to migrate (default: migration-accelerator)."
    )
    parser.add_argument(
        "--out", default=os.path.join("scripts", "migration-output"),
        help="Local output directory for the JSON + Markdown report (default: scripts/migration-output)."
    )
    args = parser.parse_args()

    result = migrate_offering(args.offering)
    json_path, md_path = write_report(result, args.out)

    print("Migrated %d question slots for '%s'." % (
        len(result["question_definitions"]), args.offering
    ))
    if result["warnings"]:
        print("%d warning(s) -- see %s" % (len(result["warnings"]), md_path))
    print("Wrote %s" % json_path)
    print("Wrote %s" % md_path)
    print(
        "This is local output only. No org was contacted and no DML ran. "
        "Turning this into real gtm-staging records is a separate, later step."
    )


if __name__ == "__main__":
    main()
