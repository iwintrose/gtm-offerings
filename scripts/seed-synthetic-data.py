#!/usr/bin/env python3
"""
Synthetic/demo data layer for UI exploration and stakeholder walkthroughs
(issue synthetic-seed-data).

    data/seed/synthetic-demo.plan.json           sf-data-tree import plan,
                                                  child-before-parent load
                                                  order (Account -> Contact ->
                                                  Opportunity ->
                                                  GTM_Saved_Configuration__c ->
                                                  GTM_Assessment_Request__c ->
                                                  GTM_Readout__c ->
                                                  GTM_Readout_Version__c ->
                                                  GTM_Link_Event__c ->
                                                  GTM_Form_Draft__c)
    data/seed/synthetic-demo.*.json              the sf-data-tree record
                                                  files the plan points at,
                                                  same attributes.type /
                                                  referenceId convention as
                                                  data/seed/migration-accelerator.*

WHY A SEPARATE TAGGING MECHANISM AT ALL. gtm-dev is the only org and is
treated as production (CLAUDE.md SS1) -- every record this script inserts
lands directly alongside live prospect data. Two independent tags, per the
BA/Architect's explicit decision (docs/agent-artifacts/task-scope-synthetic-seed-data.md
SS4):

    1. Is_Synthetic__c = true -- the AUTHORITATIVE, queryable flag. Added to
       the 5 custom objects this script seeds (GTM_Saved_Configuration__c,
       GTM_Assessment_Request__c, GTM_Link_Event__c, GTM_Form_Draft__c,
       GTM_Readout__c). --teardown deletes strictly by this filter and
       nothing else.
    2. A "[DEMO] " prefix on every human-readable name/title field touched
       -- a visual-inspection backstop for list views and reports, never
       itself the authority for a delete.

STANDARD OBJECTS (Account / Contact / Opportunity) DELIBERATELY DO NOT GET AN
Is_Synthetic__c FIELD. The BA flagged this as an open question for the
Architect (mirroring the field onto standard objects); this script resolves
it by NOT touching standard-object schema at all, which keeps the blast
radius of this issue to the 5 objects the BA's checklist actually approved
(task-scope SS2) and avoids a broad, unrelated-surface-area schema change for
a demo-data issue. Instead, teardown discovers which Account/Contact/
Opportunity rows are synthetic by walking the lookups on the already-tagged
GTM_Saved_Configuration__c rows (WHERE Is_Synthetic__c = true) BEFORE
deleting those rows, and deletes only that exact, previously-collected set of
Ids. A real prospect's Account can never appear in that set: the only way an
Id lands in it is by being referenced from a row this script itself flagged
Is_Synthetic__c = true. This is at least as safe as adding the field, and
narrower in scope. See build_teardown_plan() below.

GTM_Readout_Version__c is master-detail to GTM_Readout__c (required,
non-nullable parent -- see the field-meta.xml comment on
GTM_Readout_Version__c.Readout__c) and every seeded version is created
through a seeded Readout, so it doesn't get its own Is_Synthetic__c field
either (also outside the BA's approved 5-field list); it is instead deleted
via the parent-traversal filter `Readout__r.Is_Synthetic__c = true`, which is
exactly as strict a filter, and cannot be non-empty for a real readout for
the same "only via a synthetic parent" reason.

HARD SAFETY RULE ENFORCED THROUGHOUT THIS FILE: every DELETE this script can
ever construct is filtered by Is_Synthetic__c = true (directly, or by
traversing a master-detail parent that itself carries that filter, or by an
explicit Id IN (...) allowlist collected from those rows). There is no code
path that can build an unfiltered query or DML statement -- see
build_teardown_plan() and its accompanying unit-style self-check
(assert_teardown_plan_is_safe()), which is exercised by --check without any
org call.

*** THIS SCRIPT HAS NEVER BEEN RUN AGAINST gtm-dev BY THIS ISSUE'S AGENTS. ***
Per the Architect Addendum in task-scope-synthetic-seed-data.md SS5, this
issue's Definition of Done is BUILD + LOCAL VALIDATION ONLY. --load and
--teardown are real, usable code paths (so this script is not vaporware once
a human decides to run it) but neither this script's own tests nor any
agent in this issue's roster (BA/Architect/Developer/QA) may invoke them
against gtm-dev. Only --check (and --check-teardown, its teardown-logic-only
counterpart) are in scope for this issue, and neither ever calls `sf` or
opens a network connection.

FILTER COVERAGE (issue demo-seed-fix). Every option below returns a different,
predictable row set from the seeded data. `--coverage` prints the full list
with referenceIds and `--self-test` asserts these counts, so this table cannot
drift. Pages universe = 16 links (cfg1 Draft and cfg2 Rep_Direct are excluded by
the app on purpose); Assessments universe = 12 requests:
6 linked (one per link, cfg13-18: req1, 3, 5, 7, 9, 11) and 6 direct/unlinked
(req2, 4, 6, 8, 10, 12: no Saved_Configuration__c, Source "Direct", each on its
own "Direct Inquiry (no link)" Opportunity opp9-14 with no Engagement_Link__c).
Links cfg1-12 have no assessment yet (prospect has not submitted); cfg13-18 are
stage Assessment.

  Pages / Funnel stage (GtmLinkStageService; cumulative, so counts nest)
    sent 16 (cfg3-18) | engaged 12 (cfg7-18) | started 9 (cfg10-18)
    submitted 6 (cfg13-18) | Went quiet 3 (cfg10, 11, 12) | Came back 2 (cfg7, 10)
    not opened 4 (cfg3-6)
      cfg3-6   no events (cfg6 also inactive)
      cfg7-9   Page View only ("engaged"); cfg7 has a second session (Came back)
      cfg10    Page View + Form Opened + a second Page View session (quiet AND Came back)
      cfg11    Page View + Form Opened + Drop-off (quiet); cfg12 Page View + Form Resumed (quiet)
      cfg13-18 Page View + Form Submitted and exactly 1 request each (submitted)
    "Went quiet" has no time component in the Apex (started and not submitted);
    "Came back" needs 2+ Page View sessions AND a visit in the last 48h. Events
    get CreatedDate = load time, so Came back is true for 48h after --load.
  Pages / Offering:      migration-accelerator 11 | test-offering 5 (cfg5, 8, 11, 15, 17)
  Pages / Industry:      NOT seeded. Links carry no Industry__c (industries are
                         user-entered via the in-app Add industry flow; filter
                         options come from defined industries).
  Pages / Deal stage:    Proposal/Price Quote 3 | Qualification 3 | Needs Analysis 2 |
                         Prospecting 2 | Value Proposition 2 | Closed Won 2 | Negotiation/Review 2
  Pages / Link status:   Active 13 | Inactive 3 (cfg6, 12, 18)
  Pages / Account (7), Contact (11): one option per seeded account/contact.
  NOT seedable, so those filters cannot split the demo rows: Sent and Last visit
  (CreatedDate is system-set at load, so every link is "just now"), Owner
  (one loading user; do not fabricate users).

  Assessments / Status:  New 3 | Contacted 2 | Scheduled 2 | Completed 3 | No Show 2
  Assessments / Tier:    Fast-Track 3 (req1, 5, 12) | Accelerator-Ready 3 (3, 8, 10) |
                         Prep Required 3 (2, 6, 7) | Discovery First 3 (4, 9, 11)
  Assessments / Ready to book (New AND Fast-Track/Accelerator-Ready): 2 (req1, req3)
  Assessments / Readout: none 5 | Draft 2 | Waiting on approval 1 | Approved, not sent 1 |
                         Published 2 | Approved-and-sent 1 (req8: matches NO option, by
                         design of the app today; see the tie audit)
  Assessments / Submitted (Submitted_At__c, rendered from $DAYS_AGO tokens at load):
                         last 7 days 2 | last 30 days 6 | last 90 days 9 | older than 90 days 3
                         (req submitted 2, 5, 8, 12, 20, 28, 40, 60, 75, 100, 130, 160 days ago)
  Assessments / Offering: migration-accelerator 8 | test-offering 4
  Assessments / Account (6), Contact (12): one option per seeded account/contact.

RELATIVE DATES. A DateTime field may hold "$DAYS_AGO:<n>"; it is rendered to
"<today - n days>T12:00:00.000Z" (UTC) by --check and, on --load, into a temp
copy of the plan (never written back into data/seed), so the windows above hold
whenever the set is loaded.

Usage:
    python3 scripts/seed-synthetic-data.py --check
        Validates every data/seed/synthetic-demo.*.json file and the plan
        that orders them: JSON shape, required fields, picklist values
        (parsed live from force-app/main/default/objects/*/fields so this
        can't silently drift from the schema), Is_Synthetic__c = true on
        every record of the 5 tagged objects, "[DEMO] " prefix on every
        designated name/title field, and that referenceId chain only ever
        points BACKWARD in plan order (no forward reference, i.e. the load
        order in the plan really is a valid dependency order). Exit 0 if
        clean. No org call, ever.

    python3 scripts/seed-synthetic-data.py --check-teardown
        Builds the teardown plan (see build_teardown_plan()) and asserts
        every step in it is safe per the hard rule above. No org call.

    python3 scripts/seed-synthetic-data.py --coverage
        Offline: prints which seeded records feed which filter option and
        the expected row counts (the table above, with referenceIds).

    python3 scripts/seed-synthetic-data.py --self-test
        Offline: injects one defect at a time into the seed and asserts
        --check catches it, and exercises --preflight/--teardown against a
        stubbed `sf`. No org call.

    python3 scripts/seed-synthetic-data.py --preflight -o <org-alias>
        Read-only: `sf sobject describe` of the 9 plan objects; verifies
        every seeded field exists and is createable, restricted picklist
        values are active and required fields are written. Writes nothing.

    python3 scripts/seed-synthetic-data.py --load -o <org-alias>
        (Runs --check, --preflight and an already-loaded guard first; never
        auto-deletes on failure. Refuses the gtm-dev alias outright.) Loads data/seed/synthetic-demo.plan.json via `sf data import tree`.
        NOT to be run against gtm-dev without an explicit, separate human/
        coordinator decision -- see the module docstring above and
        task-scope-synthetic-seed-data.md SS5. Requires
        --i-understand-this-writes-to-org <org-alias> (must match -o
        exactly) as a deliberate extra confirmation step.

    python3 scripts/seed-synthetic-data.py --teardown -o <org-alias> --dry-run
        Read-only: prints counts and Ids of exactly what --teardown would
        delete (flagged rows, then the orphan sweep), no DML. The sweep queries
        by exact seed Name / LastName+Email+Account.Name (SOQL cannot filter
        on Description) and verifies the script's Description marker in Python.

    python3 scripts/seed-synthetic-data.py --teardown -o <org-alias>
        Deletes every synthetic row this script can find, in the order
        build_teardown_plan() returns, and is idempotent (a second run
        with nothing left to delete is a clean no-op, not an error). Same
        --i-understand-this-writes-to-org guard as --load.
"""
import argparse
import copy
import datetime
import functools
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED_DIR = os.path.join(ROOT, "data", "seed")
OBJECTS_DIR = os.path.join(ROOT, "force-app", "main", "default", "objects")
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
# The plan lives in scripts/, not data/seed/, so that scripts/check-references.py's
# "every data/seed/*.json is an sf-data-tree {records:[...]} file" scan (section
# 10) doesn't choke on the plan's different (top-level array) shape.
PLAN_PATH = os.path.join(SCRIPTS_DIR, "synthetic-demo.plan.json")
NS = "{http://soap.sforce.com/2006/04/metadata}"

# ---------------------------------------------------------------------------
# Schema-facing constants. Kept here, explicit and small, rather than fully
# re-derived from metadata, so a reviewer can see at a glance exactly which
# fields this script treats as load-bearing for safety -- required fields
# and the Is_Synthetic__c / [DEMO]-prefix tagging contract are read here;
# picklist LEGAL values are still parsed live from field-meta.xml below so
# a value list can never silently drift out of sync with the schema.
# ---------------------------------------------------------------------------

# The 5 custom objects this issue is scoped to seed and tag. Deliberately
# does NOT include GTM_Readout_Version__c (master-detail child of
# GTM_Readout__c, see module docstring) or any standard object.
IS_SYNTHETIC_OBJECTS = {
    "GTM_Saved_Configuration__c",
    "GTM_Assessment_Request__c",
    "GTM_Link_Event__c",
    "GTM_Form_Draft__c",
    "GTM_Readout__c",
}

REQUIRED_FIELDS = {
    "GTM_Saved_Configuration__c": ["Offering__c"],
    "GTM_Assessment_Request__c": [],
    "GTM_Link_Event__c": ["Event_Type__c"],
    "GTM_Form_Draft__c": ["Draft_Type__c", "Status__c"],
    "GTM_Readout__c": ["Offering_Key__c", "Status__c"],
    "GTM_Readout_Version__c": ["Readout__c"],
    "Account": ["Name"],
    "Contact": ["LastName"],
    "Opportunity": ["Name", "StageName", "CloseDate", "AccountId"],
}

DEMO_PREFIX = "[DEMO]"

# Field per object that must carry the [DEMO] prefix backstop. Only fields
# that are actually human-readable name/title text exist on these objects --
# GTM_Link_Event__c, GTM_Form_Draft__c and GTM_Readout_Version__c have none
# (their Name field is a system AutoNumber, e.g. "AL-0001", not something a
# rep types), so they are intentionally absent from this map and rely on
# Is_Synthetic__c alone. This is documented here rather than silently
# skipped, per the issue's "flag the gap explicitly" instruction.
NAME_PREFIX_FIELDS = {
    "Account": "Name",
    "Contact": "LastName",
    "Opportunity": "Name",
    "GTM_Saved_Configuration__c": "Company__c",
    "GTM_Assessment_Request__c": "Company__c",
}

STANDARD_OBJECTS = {"Account", "Contact", "Opportunity"}


# Standard-object fields the seed may write (explicit allowlist: standard
# object metadata is not tracked under force-app objects/, so writability
# cannot be derived; extend deliberately). Contract:
# docs/architecture/synthetic-seed-preflight.md SS3.
STANDARD_WRITABLE = {
    "Account": {"Name", "Industry", "Description", "Website", "Phone",
                "NumberOfEmployees", "BillingCity", "BillingState",
                "BillingCountry", "AnnualRevenue", "Type"},
    "Contact": {"AccountId", "FirstName", "LastName", "Email", "Phone",
                "Title", "Description", "Department"},
    "Opportunity": {"AccountId", "Name", "StageName", "CloseDate", "Amount",
                    "Description", "Probability", "Type", "LeadSource",
                    "NextStep"},
}

# Never writable by a seed, on any object (OwnerId denied on purpose: the
# load user owns seeded rows).
SYSTEM_FIELDS = {
    "Id", "CreatedDate", "CreatedById", "LastModifiedDate",
    "LastModifiedById", "SystemModstamp", "IsDeleted", "LastActivityDate",
    "OwnerId",
}


class CheckError(Exception):
    pass


# Standard-object lookup fields the seed writes -> the sobject they point at.
STANDARD_REF_TARGETS = {"AccountId": "Account"}

# The script's own Description marker on seeded standard records. The orphan
# sweep in --teardown keys on it (plus exact seed names), so --check asserts
# every seeded Account/Opportunity carries it.
DESC_MARKERS = {
    "Account": "Synthetic demo account seeded by scripts/seed-synthetic-data.py",
    "Opportunity": "Synthetic demo opportunity seeded by scripts/seed-synthetic-data.py",
}

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$")
_TEXT_TYPES = {"Text", "TextArea", "LongTextArea", "Html", "Email", "Url",
               "Phone", "Picklist", "EncryptedText"}


@functools.lru_cache(maxsize=None)
def _field_facts(objects_dir, sobject, field):
    path = os.path.join(objects_dir, sobject, "fields", field + ".field-meta.xml")
    if not os.path.isfile(path):
        return None
    root = ET.parse(path).getroot()

    def txt(tag):
        el = root.find(NS + tag)
        return el.text if el is not None else None

    ftype = txt("type") or ""
    return {
        "type": ftype,
        "formula": root.find(NS + "formula") is not None,
        "required": txt("required") == "true" or ftype == "MasterDetail",
        "length": int(txt("length")) if txt("length") else None,
        "precision": int(txt("precision")) if txt("precision") else None,
        "scale": int(txt("scale")) if txt("scale") else None,
        "referenceTo": txt("referenceTo"),
    }


def field_facts(sobject, field):
    """Facts parsed from force-app field-meta.xml (None if the field is not
    in source). Honours the OBJECTS_DIR override used by --self-test."""
    return _field_facts(OBJECTS_DIR, sobject, field)


def required_drift_problems():
    """The hand-maintained REQUIRED_FIELDS for the GTM objects must equal the
    set derived from metadata, so the two can never silently drift."""
    problems = []
    for sobject, hand in REQUIRED_FIELDS.items():
        if sobject in STANDARD_OBJECTS:
            continue
        fdir = os.path.join(OBJECTS_DIR, sobject, "fields")
        if not os.path.isdir(fdir):
            continue
        derived = set()
        for fn in os.listdir(fdir):
            fld = fn[: -len(".field-meta.xml")]
            facts = field_facts(sobject, fld)
            if facts and facts["required"]:
                derived.add(fld)
        if derived != set(hand):
            problems.append(
                f"REQUIRED_FIELDS[{sobject}] = {sorted(hand)} has drifted from "
                f"the metadata-derived required set {sorted(derived)}"
            )
    return problems


def shape_problem(sobject, field, val, defined_at):
    """Type/reference-shape check of one value, derived from metadata.
    Returns a reason string or None."""
    if sobject in STANDARD_OBJECTS:
        target = STANDARD_REF_TARGETS.get(field)
        facts = {"type": "Lookup", "referenceTo": target} if target else None
    else:
        facts = field_facts(sobject, field)
    if facts is None or val is None:
        return None
    t = facts["type"]
    if t in ("Lookup", "MasterDetail"):
        if facts["referenceTo"] == "User":
            return "User lookups are org-specific and not seedable"
        if not (isinstance(val, str) and val.startswith("@")):
            return ("lookup value must be an '@referenceId' to an earlier plan "
                    "record; a raw Id is org-specific")
        ref = val[1:]
        if ref in defined_at and defined_at[ref][0] != facts["referenceTo"]:
            return (f"references '{ref}' which is a {defined_at[ref][0]}, but "
                    f"the field points at {facts['referenceTo']}")
        return None
    if t == "Checkbox":
        return None if isinstance(val, bool) else "Checkbox requires true/false (JSON boolean)"
    if t in ("Number", "Currency", "Percent"):
        if isinstance(val, bool) or not isinstance(val, (int, float)):
            return f"{t} requires a JSON number"
        if facts["precision"] is not None:
            scale = facts["scale"] or 0
            text = repr(val) if isinstance(val, float) else str(val)
            whole, _, frac = text.lstrip("-").partition(".")
            frac = frac.rstrip("0") if isinstance(val, float) else frac
            if len(frac) > scale or len(whole.lstrip("0")) > facts["precision"] - scale:
                return f"{t}({facts['precision']},{scale}) cannot hold {val}"
        return None
    if t in _TEXT_TYPES:
        if not isinstance(val, str):
            return f"{t} requires a JSON string"
        if facts["length"] is not None and t != "Picklist" and len(val) > facts["length"]:
            return f"{t} value is {len(val)} chars, longer than {facts['length']}"
        if t == "Email" and not _EMAIL_RE.match(val):
            return "malformed email"
        return None
    if t == "Date":
        return None if isinstance(val, str) and _DATE_RE.match(val) else "Date requires YYYY-MM-DD"
    if t == "DateTime":
        return None if isinstance(val, str) and _DATETIME_RE.match(val) else "DateTime requires ISO-8601"
    return None


def writability_problem(sobject, field):
    """Return a reason string if a seed must not write `field` on
    `sobject`, else None. Reads force-app only (no org call)."""
    if field in SYSTEM_FIELDS:
        return "system-managed field, not writable"
    if sobject in STANDARD_OBJECTS:
        if field not in STANDARD_WRITABLE.get(sobject, set()):
            return "not on the STANDARD_WRITABLE allowlist for %s" % sobject
        return None
    obj_dir = os.path.join(OBJECTS_DIR, sobject)
    if not os.path.isdir(obj_dir):
        return "object %s does not exist in force-app" % sobject
    if field == "Name":
        om = os.path.join(obj_dir, sobject + ".object-meta.xml")
        if os.path.isfile(om):
            nf_type = ET.parse(om).getroot().find(f"{NS}nameField/{NS}type")
            if nf_type is not None and nf_type.text == "AutoNumber":
                return "auto-number Name, not writable"
        return None
    path = os.path.join(obj_dir, "fields", field + ".field-meta.xml")
    if not os.path.isfile(path):
        return "field does not exist in force-app"
    root = ET.parse(path).getroot()
    if root.find(NS + "formula") is not None:
        return "formula field, not writable"
    type_el = root.find(NS + "type")
    ftype = type_el.text if type_el is not None else ""
    if ftype == "Summary":
        return "roll-up summary field, not writable"
    if ftype == "AutoNumber":
        return "auto-number field, not writable"
    return None


def load_plan():
    with open(PLAN_PATH, encoding="utf-8") as fh:
        return json.load(fh)


# Relative dates. Seed JSON may hold "$DAYS_AGO:<n>" for any DateTime field;
# it is rendered to "<today - n days>T12:00:00.000Z" (UTC) at check/load time,
# so windows like "Last 30 days" stay predictable whenever the set is loaded.
# CreatedDate cannot be seeded, so only real DateTime fields use this.
_DAYS_AGO_RE = re.compile(r"^\$DAYS_AGO:(\d+)$")
NOW = None  # test seam: a fixed datetime.date-capable "today" (UTC)


def today_utc():
    return NOW or datetime.datetime.now(datetime.timezone.utc).date()


def render_value(val):
    if isinstance(val, str):
        m = _DAYS_AGO_RE.match(val)
        if m:
            day = today_utc() - datetime.timedelta(days=int(m.group(1)))
            return day.isoformat() + "T12:00:00.000Z"
    return val


def load_records(filename):
    # filename is relative to the plan file's own directory (scripts/),
    # matching sf data import tree's own path-resolution convention.
    path = os.path.normpath(os.path.join(SCRIPTS_DIR, filename))
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    recs = [{k: render_value(v) for k, v in r.items()} for r in data.get("records", [])]
    return recs, path


def render_plan(tmpdir):
    """Write a rendered copy of the plan and its record files into tmpdir
    (relative dates resolved, paths flattened); returns the plan path."""
    plan = load_plan()
    out = []
    for step in plan:
        names = []
        for fn in step["files"]:
            recs, path = load_records(fn)
            name = os.path.basename(path)
            with open(os.path.join(tmpdir, name), "w", encoding="utf-8") as fh:
                json.dump({"records": recs}, fh, indent=2, ensure_ascii=False)
            names.append(name)
        out.append(dict(step, files=names))
    plan_path = os.path.join(tmpdir, "synthetic-demo.plan.json")
    with open(plan_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    return plan_path


def picklist_values(sobject, field):
    """Parse the legal values for a Picklist field straight out of the
    tracked field-meta.xml, so this can never silently drift from the real
    schema. Returns None if the field isn't a (restricted) Picklist -- i.e.
    "don't check this one", not "no values are legal"."""
    if sobject in STANDARD_OBJECTS:
        return None  # standard-object picklists aren't tracked in objects/
    path = os.path.join(OBJECTS_DIR, sobject, "fields", field + ".field-meta.xml")
    if not os.path.isfile(path):
        return None
    root = ET.parse(path).getroot()
    type_el = root.find(NS + "type")
    if type_el is None or type_el.text != "Picklist":
        return None
    restricted = root.find(f"{NS}valueSet/{NS}restricted")
    if restricted is None or restricted.text != "true":
        return None  # unrestricted picklist: any value is legal
    values = set()
    for v in root.iter(NS + "value"):
        full_name = v.find(NS + "fullName")
        if full_name is not None:
            values.add(full_name.text)
    return values


def check_seed_files():
    """The --check path: pure local validation, zero org calls. Returns a
    list of problem strings; empty means clean."""
    problems = list(required_drift_problems())
    plan = load_plan()

    # referenceId -> (sobject, plan_index) for every record, in plan order,
    # so we can tell a backward reference (fine: a real dependency) from a
    # forward one (a load-order bug the plan itself must not have).
    defined_at = {}
    all_records_by_type = {}

    for idx, step in enumerate(plan):
        sobject = step["sobject"]
        for filename in step["files"]:
            records, path = load_records(filename)
            all_records_by_type.setdefault(sobject, []).extend(records)
            for rec in records:
                attrs = rec.get("attributes", {})
                if attrs.get("type") != sobject:
                    problems.append(
                        f"{path}: record attributes.type '{attrs.get('type')}' "
                        f"does not match plan step sobject '{sobject}'"
                    )
                ref_id = attrs.get("referenceId")
                if not ref_id:
                    problems.append(f"{path}: record missing attributes.referenceId")
                elif ref_id in defined_at:
                    problems.append(f"{path}: duplicate referenceId '{ref_id}'")
                else:
                    defined_at[ref_id] = (sobject, idx)

                # Writability (formula / roll-up / auto-number / system /
                # nonexistent): the API rejects these with
                # INVALID_FIELD_FOR_INSERT_UPDATE mid-load.
                for field in rec:
                    if field == "attributes":
                        continue
                    why = writability_problem(sobject, field)
                    if not why:
                        why = shape_problem(sobject, field, rec[field], defined_at)
                        if why:
                            problems.append(
                                f"{path}: {sobject} record '{ref_id}' field "
                                f"{field}: {why}"
                            )
                        continue
                    problems.append(
                        f"{path}: {sobject} record '{ref_id}' writes "
                        f"{field}: {why}"
                    )

                # Description marker the orphan sweep relies on.
                marker = DESC_MARKERS.get(sobject)
                if marker and not str(rec.get("Description", "")).startswith(marker):
                    problems.append(
                        f"{path}: {sobject} record '{ref_id}' Description must "
                        f"start with '{marker}' (the --teardown orphan sweep "
                        f"keys on it)"
                    )

                # Required fields.
                for req in REQUIRED_FIELDS.get(sobject, []):
                    if not str(rec.get(req, "")).strip():
                        problems.append(
                            f"{path}: {sobject} record '{ref_id}' missing "
                            f"required field {req}"
                        )

                # Is_Synthetic__c must be true on every tagged object.
                if sobject in IS_SYNTHETIC_OBJECTS:
                    if rec.get("Is_Synthetic__c") is not True:
                        problems.append(
                            f"{path}: {sobject} record '{ref_id}' must set "
                            f"Is_Synthetic__c = true"
                        )

                # [DEMO] prefix backstop.
                prefix_field = NAME_PREFIX_FIELDS.get(sobject)
                if prefix_field:
                    val = str(rec.get(prefix_field, ""))
                    if not val.startswith(DEMO_PREFIX):
                        problems.append(
                            f"{path}: {sobject} record '{ref_id}' field "
                            f"{prefix_field} = '{val}' does not start with "
                            f"'{DEMO_PREFIX}'"
                        )

                # Picklist values.
                for field, val in rec.items():
                    if field == "attributes" or not isinstance(val, str):
                        continue
                    legal = picklist_values(sobject, field)
                    if legal is not None and val not in legal:
                        problems.append(
                            f"{path}: {sobject}.{field} = '{val}' is not one "
                            f"of {sorted(legal)}"
                        )

                # Cross-reference resolution + dependency-order check: every
                # "@ref" value must name a referenceId defined by a plan
                # step at or before this one (no forward reference).
                for field, val in rec.items():
                    if field == "attributes" or not isinstance(val, str):
                        continue
                    if val.startswith("@"):
                        ref = val[1:]
                        if ref not in defined_at:
                            problems.append(
                                f"{path}: {sobject}.{field} references "
                                f"'{ref}', which is not defined by any "
                                f"earlier-or-same plan step (forward "
                                f"reference or typo)"
                            )
                        elif defined_at[ref][1] > idx:
                            problems.append(
                                f"{path}: {sobject}.{field} references "
                                f"'{ref}' defined at a LATER plan step -- "
                                f"the plan's load order is not a valid "
                                f"dependency order"
                            )
    problems.extend(data_model_problems(all_records_by_type))
    return problems, all_records_by_type


# Demo data-model rules (ADR-0008: one submission per link). At least this many
# requests must be direct/unlinked (Saved_Configuration__c blank).
MIN_UNLINKED_REQUESTS = 4
POST_ASSESSMENT_STAGES = ("Assessment",)


def data_model_problems(records_by_type):
    """At most one request per link; enough unlinked requests whose Opportunity
    is not a link's; link Presentation_Stage__c consistent with having a request
    (with one: Assessment; without: an earlier stage); at least one link with
    no request."""
    out = []
    cfgs = records_by_type.get("GTM_Saved_Configuration__c", [])
    reqs = records_by_type.get("GTM_Assessment_Request__c", [])
    per_link = {}
    unlinked = []
    for r in reqs:
        link = r.get("Saved_Configuration__c")
        if link:
            per_link.setdefault(str(link)[1:], []).append(r["attributes"]["referenceId"])
        else:
            unlinked.append(r)
    for link, refs in sorted(per_link.items()):
        if len(refs) > 1:
            out.append(f"link {link} has {len(refs)} assessment requests {refs}; ADR-0008 allows at most one per link")
    if len(unlinked) < MIN_UNLINKED_REQUESTS:
        out.append(f"only {len(unlinked)} unlinked assessment requests; need at least {MIN_UNLINKED_REQUESTS}")
    link_opps = {str(c.get("Opportunity__c"))[1:] for c in cfgs}
    for r in unlinked:
        opp = str(r.get("Opportunity__c", ""))[1:]
        if opp in link_opps:
            out.append(f"unlinked request {r['attributes']['referenceId']} points at opportunity {opp}, which a link also uses")
    linkless = 0
    for c in cfgs:
        ref = c["attributes"]["referenceId"]
        has = ref in per_link
        stage = c.get("Presentation_Stage__c")
        if has and stage not in POST_ASSESSMENT_STAGES:
            out.append(f"link {ref} has a request but stage is {stage!r}, expected Assessment")
        if not has:
            linkless += 1
            if stage in POST_ASSESSMENT_STAGES:
                out.append(f"link {ref} is at stage {stage!r} but has no assessment request")
    if linkless == 0:
        out.append("no link without an assessment request is seeded")
    return out


SWEEP_NOTE = "ORPHAN SWEEP"

# Aliases this script refuses to touch at all (gtm-dev is treated as
# Production, CLAUDE.md SS1). Alias only; no org ID is committed.
REFUSED_ALIASES = {"gtm-dev", "gtm-prod"}  # gtm-dev = legacy alias; #250 renamed prod alias to gtm-prod

# Lookups on flagged custom rows that point at standard records.
LOOKUP_COLUMNS = {
    "GTM_Saved_Configuration__c": ["Account__c", "Contact__c", "Opportunity__c"],
    "GTM_Assessment_Request__c": ["Account__c", "Contact__c", "Opportunity__c"],
    "GTM_Readout__c": ["Opportunity__c"],
}
COLUMN_TARGET = {"Account__c": "Account", "Contact__c": "Contact",
                 "Opportunity__c": "Opportunity"}

# Order deletes run in: child before parent. Standard objects last.
CUSTOM_DELETE_ORDER = [
    "GTM_Link_Event__c", "GTM_Form_Draft__c", "GTM_Readout_Version__c",
    "GTM_Readout__c", "GTM_Assessment_Request__c", "GTM_Saved_Configuration__c",
]
STANDARD_DELETE_ORDER = ["Opportunity", "Contact", "Account"]
DELETABLE = set(CUSTOM_DELETE_ORDER) | set(STANDARD_DELETE_ORDER)

# SOQL cannot FILTER on these (it can still SELECT them): Long/Rich Text Area
# and Encrypted fields, and the standard Description fields. A WHERE that names
# one fails at the real org ("can not be filtered in a query call"), which
# --self-test could not see until assert_query_filterable existed.
NONFILTERABLE_STANDARD = {
    "Account": {"Description"},
    "Contact": {"Description"},
    "Opportunity": {"Description"},
}
NONFILTERABLE_TYPES = {"LongTextArea", "Html", "EncryptedText"}
_LITERAL_RE = re.compile(r"'(?:[^'\\]|\\.)*'")
_WHERE_FIELD_RE = re.compile(
    r"([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*(?:!=|<>|<=|>=|=|<|>|\s+NOT\s+IN\b|\s+IN\b|\s+LIKE\b)")
_ID_RE = re.compile(r"^[A-Za-z0-9]{15,18}$")


class SfError(Exception):
    pass


def soql_str(value):
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"


def soql_list(values):
    return "(" + ", ".join(soql_str(v) for v in values) + ")"


def seed_identity():
    """Exact identity of the seeded standard records, read from the seed
    files at run time (never typed by hand)."""
    ident = {"account_names": [], "opp_names": [], "contact_lastnames": [],
             "contact_emails": []}
    for step in load_plan():
        for fn in step["files"]:
            recs, _ = load_records(fn)
            for r in recs:
                if step["sobject"] == "Account":
                    ident["account_names"].append(r["Name"])
                elif step["sobject"] == "Opportunity":
                    ident["opp_names"].append(r["Name"])
                elif step["sobject"] == "Contact":
                    ident["contact_lastnames"].append(r["LastName"])
                    ident["contact_emails"].append(r["Email"])
    return ident


# ---------------------------------------------------------------------------
# Filter coverage (offline): which seeded records feed which filter option.
# Mirrors GtmLinkStageService (Pages funnel stage) and
# GtmAssessmentListController (Assessments readiness/readout/range) so QA can
# assert every option's expected rows. Printed by --coverage; golden counts
# are asserted by --self-test.
# ---------------------------------------------------------------------------

def _ref(rec):
    return rec["attributes"]["referenceId"]


def _days_ago(dt_text):
    day = datetime.date.fromisoformat(dt_text[:10])
    return (today_utc() - day).days


def compute_coverage(records_by_type):
    """Returns (universe, coverage): universe = {'pages': [refs], 'assessments':
    [refs]}; coverage = ordered {(tab, filter, option): [referenceIds]}."""
    cfgs = records_by_type["GTM_Saved_Configuration__c"]
    events = records_by_type["GTM_Link_Event__c"]
    reqs = records_by_type["GTM_Assessment_Request__c"]
    readouts = records_by_type["GTM_Readout__c"]
    opps = {_ref(o): o for o in records_by_type["Opportunity"]}
    accts = {_ref(a): a["Name"] for a in records_by_type["Account"]}
    conts = {_ref(c): c["LastName"] for c in records_by_type["Contact"]}

    universe = [c for c in cfgs
                if c.get("Presentation_Stage__c") not in (None, "", "Draft", "Rep_Direct")]
    cov = {}

    def put(tab, flt, opt, ref):
        cov.setdefault((tab, flt, str(opt)), []).append(ref)

    # ---- Pages: funnel stage, mirroring GtmLinkStageService.LinkFacts
    facts = {}
    for c in universe:
        facts[_ref(c)] = {"pv": 0, "sessions": set(), "nullpv": 0, "opened": False,
                          "submitted_evt": False, "request": False}
    for e in events:
        f = facts.get(str(e["Saved_Configuration__c"])[1:])
        if f is None:
            continue
        t = e["Event_Type__c"]
        if t == "Page View":
            f["pv"] += 1
            if e.get("Session_Id__c"):
                f["sessions"].add(e["Session_Id__c"])
            else:
                f["nullpv"] += 1
        if t in ("Form Opened", "Form Resumed"):
            f["opened"] = True
        if t == "Form Submitted":
            f["submitted_evt"] = True
    for r in reqs:
        f = facts.get(str(r.get("Saved_Configuration__c", ""))[1:])
        if f is not None:
            f["request"] = True
    for c in universe:
        ref = _ref(c)
        f = facts[ref]
        submitted = f["submitted_evt"] or f["request"]
        started = f["opened"] or submitted
        engaged = f["pv"] > 0 or started
        # "Came back" also needs the last visit within 48h; events are created
        # at load time, so it holds for 48h after --load.
        hot = (len(f["sessions"]) + f["nullpv"]) >= 2
        put("Pages", "Funnel stage", "sent", ref)
        if engaged:
            put("Pages", "Funnel stage", "engaged", ref)
        else:
            put("Pages", "Funnel stage", "not_opened", ref)
        if started:
            put("Pages", "Funnel stage", "started", ref)
        if submitted:
            put("Pages", "Funnel stage", "submitted", ref)
        if started and not submitted:
            put("Pages", "Funnel stage", "quiet", ref)
        if hot:
            put("Pages", "Funnel stage", "hot", ref)
        put("Pages", "Offering", c["Offering__c"], ref)
        put("Pages", "Deal stage", opps[str(c["Opportunity__c"])[1:]]["StageName"], ref)
        put("Pages", "Link status", "Active" if c.get("Active__c") else "Inactive", ref)
        put("Pages", "Account", accts[str(c["Account__c"])[1:]], ref)
        put("Pages", "Contact", conts[str(c["Contact__c"])[1:]], ref)

    # ---- Assessments
    rdo = {str(r["Assessment_Request__c"])[1:]: r for r in readouts}
    for r in reqs:
        ref = _ref(r)
        put("Assessments", "Status", r["Status__c"], ref)
        put("Assessments", "Readiness tier", r.get("Assessment_Tier__c", ""), ref)
        if r["Status__c"] == "New" and r.get("Assessment_Tier__c") in ("Fast-Track", "Accelerator-Ready"):
            put("Assessments", "Ready to book", "on", ref)
        ro = rdo.get(ref)
        if ro is None:
            key = "none"
        elif ro["Status__c"] == "Draft":
            key = "draft"
        elif ro["Status__c"] == "Pending Approval":
            key = "pending"
        elif ro["Status__c"] == "Published":
            key = "published"
        elif ro["Status__c"] == "Approved" and not ro.get("Notification_Sent_Date__c"):
            key = "approved-unsent"
        else:
            key = "(approved and sent: no option matches)"
        put("Assessments", "Readout", key, ref)
        days = _days_ago(r["Submitted_At__c"])
        for window in (7, 30, 90):
            if days <= window:
                put("Assessments", "Submitted", f"last {window} days", ref)
        if days > 90:
            put("Assessments", "Submitted", "older than 90 days", ref)
        put("Assessments", "Offering", r["Offering_Key__c"], ref)
        put("Assessments", "Account", accts[str(r["Account__c"])[1:]], ref)
        put("Assessments", "Contact", conts[str(r["Contact__c"])[1:]], ref)
    return ({"Pages": [_ref(c) for c in universe], "Assessments": [_ref(r) for r in reqs]}, cov)


# Golden expectations (tab, filter, option) -> row count. Asserted by
# --self-test so the seed and this table cannot drift apart.
EXPECTED_UNIVERSE = {"Pages": 16, "Assessments": 12}
EXPECTED_COVERAGE = {
    ("Assessments", "Status", "New"): 3,
    ("Assessments", "Readiness tier", "Fast-Track"): 3,
    ("Assessments", "Ready to book", "on"): 2,
    ("Assessments", "Readout", "none"): 5,
    ("Assessments", "Submitted", "last 7 days"): 2,
    ("Assessments", "Submitted", "last 30 days"): 6,
    ("Assessments", "Submitted", "last 90 days"): 9,
    ("Assessments", "Offering", "migration-accelerator"): 8,
    ("Assessments", "Status", "Contacted"): 2,
    ("Assessments", "Readiness tier", "Prep Required"): 3,
    ("Assessments", "Readout", "draft"): 2,
    ("Assessments", "Readiness tier", "Accelerator-Ready"): 3,
    ("Assessments", "Readout", "pending"): 1,
    ("Assessments", "Status", "Scheduled"): 2,
    ("Assessments", "Readiness tier", "Discovery First"): 3,
    ("Assessments", "Status", "Completed"): 3,
    ("Assessments", "Readout", "published"): 2,
    ("Assessments", "Offering", "test-offering"): 4,
    ("Assessments", "Status", "No Show"): 2,
    ("Assessments", "Submitted", "older than 90 days"): 3,
    ("Assessments", "Readout", "approved-unsent"): 1,
    ("Assessments", "Readout", "(approved and sent: no option matches)"): 1,
    ("Pages", "Funnel stage", "sent"): 16,
    ("Pages", "Funnel stage", "not_opened"): 4,
    ("Pages", "Offering", "migration-accelerator"): 11,
    ("Pages", "Deal stage", "Proposal/Price Quote"): 3,
    ("Pages", "Link status", "Active"): 13,
    ("Pages", "Deal stage", "Qualification"): 3,
    ("Pages", "Offering", "test-offering"): 5,
    ("Pages", "Deal stage", "Needs Analysis"): 2,
    ("Pages", "Deal stage", "Prospecting"): 2,
    ("Pages", "Link status", "Inactive"): 3,
    ("Pages", "Funnel stage", "engaged"): 12,
    ("Pages", "Funnel stage", "hot"): 2,
    ("Pages", "Deal stage", "Value Proposition"): 2,
    ("Pages", "Deal stage", "Closed Won"): 2,
    ("Pages", "Deal stage", "Negotiation/Review"): 2,
    ("Pages", "Funnel stage", "started"): 9,
    ("Pages", "Funnel stage", "quiet"): 3,
    ("Pages", "Funnel stage", "submitted"): 6,
}


def cmd_coverage(_args):
    problems, records = check_seed_files()
    if problems:
        print("Seed data fails --check; fix that first.", file=sys.stderr)
        return 1
    universe, cov = compute_coverage(records)
    print(f"Pages universe: {len(universe['Pages'])} links "
          f"(Draft and Rep_Direct links are excluded by the app); "
          f"Assessments universe: {len(universe['Assessments'])} requests")
    last = None
    grouped = sorted(cov.items(), key=lambda kv: (kv[0][0], list(dict.fromkeys(k[1] for k in cov)).index(kv[0][1])))
    for (tab, flt, opt), refs in grouped:
        if (tab, flt) != last:
            print(f"\n{tab} / {flt}")
            last = (tab, flt)
        print(f"  {opt:<40} {len(refs):>3}  {', '.join(refs)}")
    print("\nPages / Industry\n  (not seeded: links carry no industry; options come from defined industries)")
    return 0


def build_teardown_plan():
    """Returns an ordered list of (sobject, where_clause, note) describing
    exactly what --teardown will query/delete, child-before-parent. This is
    the single source of truth for both --teardown's real execution and
    --check-teardown's static safety assertion, so there is no way for the
    two to drift apart.

    Steps 1-9: (a) "Is_Synthetic__c = true", (b) a traversal to a parent
    carrying that filter, or (c) "Id IN (<ids>)" collected from flagged rows
    BEFORE they are deleted.

    Steps 10-12 (note starts with ORPHAN SWEEP): standard records left by a
    failed/partial load, matched ONLY by exact seed identity. SOQL cannot
    filter on Description (long text), so the query filters on the seed Name
    (Account/Opportunity) or seed LastName + Email + Account.Name (Contact),
    SELECTs Description/Email, and a row is a candidate only if sweep_row_verified()
    confirms the script's own Description marker (or a .invalid Email) in
    Python. At run time anything a non-synthetic row still references is skipped.
    """
    ident = seed_identity()
    acct = soql_list(ident["account_names"])
    return [
        ("GTM_Link_Event__c", "Is_Synthetic__c = true", "child of Saved_Configuration__c / Assessment_Request__c"),
        ("GTM_Form_Draft__c", "Is_Synthetic__c = true", "child of Saved_Configuration__c / Assessment_Request__c"),
        ("GTM_Readout_Version__c", "Readout__r.Is_Synthetic__c = true", "master-detail child of GTM_Readout__c; no field of its own by design"),
        ("GTM_Readout__c", "Is_Synthetic__c = true", "child of Assessment_Request__c / Opportunity"),
        ("GTM_Assessment_Request__c", "Is_Synthetic__c = true", "child of Saved_Configuration__c / Opportunity"),
        ("GTM_Saved_Configuration__c", "Is_Synthetic__c = true", "parent lookups (Account__c/Contact__c/Opportunity__c) collected here BEFORE delete, for the standard-object step below"),
        ("Opportunity", "Id IN (<ids collected from GTM_Saved_Configuration__c.Opportunity__c above>)", "standard object: no Is_Synthetic__c field, deleted only by an allowlist derived from an already-tagged synthetic row"),
        ("Contact", "Id IN (<ids collected from GTM_Saved_Configuration__c.Contact__c above>)", "standard object: same allowlist discipline as Opportunity"),
        ("Account", "Id IN (<ids collected from GTM_Saved_Configuration__c.Account__c above>)", "standard object: same allowlist discipline as Opportunity"),
        ("Opportunity",
         f"Name IN {soql_list(ident['opp_names'])}",
         SWEEP_NOTE + ": exact seed Name; Description marker verified in Python on the returned rows; skipped if a non-synthetic row references it"),
        ("Contact",
         f"LastName IN {soql_list(ident['contact_lastnames'])} AND Email IN {soql_list(ident['contact_emails'])} AND Account.Name IN {acct}",
         SWEEP_NOTE + ": exact seed LastName + Email + seed Account.Name; .invalid Email re-verified in Python; skipped if a non-synthetic row references it"),
        ("Account",
         f"Name IN {acct}",
         SWEEP_NOTE + ": exact seed Name; Description marker verified in Python on the returned rows; skipped if a non-synthetic row or a non-seed child references it"),
    ]


def assert_teardown_plan_is_safe(plan):
    """Unit-style self-check, run by --check-teardown with no org call:
    confirms no step in build_teardown_plan() can ever construct an
    unfiltered query. Raises CheckError on any violation."""
    if not plan:
        raise CheckError("teardown plan is empty")
    order = [step[0] for step in plan]
    expected_order = CUSTOM_DELETE_ORDER + STANDARD_DELETE_ORDER + STANDARD_DELETE_ORDER
    if order != expected_order:
        raise CheckError(f"teardown order changed unexpectedly: {order}")
    for sobject, where, note in plan:
        stripped = where.strip()
        if not stripped:
            raise CheckError(f"{sobject}: empty WHERE clause -- would be unfiltered")
        if note.startswith(SWEEP_NOTE):
            _assert_sweep_where(sobject, stripped)
            assert_query_filterable(f"SELECT Id FROM {sobject} WHERE {stripped}")
            continue
        safe = (
            "Is_Synthetic__c = true" in stripped
            or re.match(r"^Id IN \(", stripped)
        )
        if not safe:
            raise CheckError(
                f"{sobject}: WHERE clause '{where}' is neither an "
                f"Is_Synthetic__c = true filter nor an Id IN (...) "
                f"allowlist -- refusing as unsafe"
            )
        if sobject in STANDARD_OBJECTS and "Is_Synthetic__c" in stripped:
            raise CheckError(
                f"{sobject}: standard object must never be queried by "
                f"Is_Synthetic__c (that field does not exist on it by "
                f"design -- see module docstring)"
            )
        if not stripped.startswith("Id IN ("):
            assert_query_filterable(f"SELECT Id FROM {sobject} WHERE {stripped}")
    # Sweep candidates are only ever accepted after the Python-side marker
    # check, so the marker must exist for every object whose sweep cannot
    # filter on Description.
    for obj in ("Account", "Opportunity"):
        if not DESC_MARKERS.get(obj):
            raise CheckError(f"{obj}: no Description marker to verify sweep candidates with")
    return True


def _assert_sweep_where(sobject, where):
    if sobject not in STANDARD_OBJECTS:
        raise CheckError(f"orphan sweep on non-standard object {sobject}")
    if "Is_Synthetic__c" in where:
        raise CheckError(f"{sobject}: sweep must not use Is_Synthetic__c (not on standard objects)")
    if "Description" in where:
        raise CheckError(f"{sobject}: sweep must not filter on Description (not filterable); verify it in Python")
    literals = [x[1:-1].replace("\\'", "'").replace("\\\\", "\\") for x in _LITERAL_RE.findall(where)]
    stray = [v for v in literals if v not in seed_literals()]
    if stray or not literals:
        raise CheckError(f"{sobject}: sweep WHERE has a literal that is not seed identity: {stray[:1]}")
    if sobject == "Contact":
        needed = ["LastName IN ('", "Email IN ('", "Account.Name IN ('"]
        emails = re.search(r"Email IN \((.*?)\) AND Account\.Name", where)
        quoted = re.findall(r"'((?:[^'\\]|\\.)*)'", emails.group(1)) if emails else []
        if not quoted or not all(e.endswith(".invalid") for e in quoted):
            raise CheckError("Contact sweep: every Email in the list must end with .invalid")
    else:
        needed = ["Name IN ('"]
    for token in needed:
        if token not in where:
            raise CheckError(f"{sobject} orphan sweep WHERE lacks required marker {token!r}")


def teardown_command(org):
    return (f"python3 scripts/seed-synthetic-data.py --teardown -o {org} "
            f"--i-understand-this-writes-to-org {org}")


def refuse_alias(org):
    if org and org.strip().lower() in REFUSED_ALIASES:
        print(f"Refusing: '{org}' is the Production alias. This script only "
              f"targets a non-production test org.", file=sys.stderr)
        return True
    return False


# ---------------------------------------------------------------------------
# sf shell-outs. Everything that touches an org goes through run_sf_json (or
# run_sf for the one import), so --self-test can stub them.
# ---------------------------------------------------------------------------

def run_sf(args, org_alias):
    cmd = ["sf"] + args + ["-o", org_alias]
    print("running:", " ".join(cmd), file=sys.stderr)
    return subprocess.run(cmd, cwd=ROOT, check=True)


def run_sf_json(args, org_alias):
    """Run `sf <args> -o <org> --json`; return payload['result'] or raise
    SfError. Never prints record data."""
    cmd = ["sf"] + args + ["-o", org_alias, "--json"]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        raise SfError(f"sf {' '.join(args[:3])} returned non-JSON output "
                      f"(exit {proc.returncode}): {proc.stderr.strip()[:300]}")
    if proc.returncode != 0 or payload.get("status", 0) != 0:
        raise SfError(f"sf {' '.join(args[:3])} failed: "
                      f"{str(payload.get('message', 'unknown error'))[:400]}")
    result = payload.get("result")
    info = result.get("jobInfo", result) if isinstance(result, dict) else {}
    if isinstance(info, dict) and (info.get("numberRecordsFailed") or 0) > 0:
        raise SfError(f"sf {' '.join(args[:3])}: {info['numberRecordsFailed']} record(s) failed")
    return result


def _where_of(soql):
    if " WHERE " not in soql:
        return ""
    where = soql.split(" WHERE ", 1)[1]
    return re.split(r"\s+(?:LIMIT|ORDER\s+BY|GROUP\s+BY)\b", where)[0]


def where_field_paths(soql):
    """Field paths that appear as a filter operand in the WHERE clause
    (string literals stripped first, so a value can never be mistaken for a
    field)."""
    return _WHERE_FIELD_RE.findall(_LITERAL_RE.sub("''", _where_of(soql)))


def is_nonfilterable(sobject, path):
    """True if `path` (e.g. 'Description', 'Readout__r.Is_Synthetic__c',
    'Account.Description') resolves to a field SOQL cannot filter on."""
    parts = path.split(".")
    cur = sobject
    for rel in parts[:-1]:
        if rel.endswith("__r"):
            facts = field_facts(cur, rel[:-3] + "__c") if cur else None
            cur = facts["referenceTo"] if facts else None
        else:
            cur = rel  # standard relationship name equals the object name here
    last = parts[-1]
    if cur is None:
        return False
    if last in NONFILTERABLE_STANDARD.get(cur, set()):
        return True
    facts = field_facts(cur, last) if cur not in STANDARD_OBJECTS else None
    return bool(facts and facts["type"] in NONFILTERABLE_TYPES)


def assert_query_filterable(soql):
    """Raise CheckError if the WHERE names a field SOQL cannot filter on."""
    m = re.search(r"\bFROM\s+(\w+)", soql)
    if not m:
        raise CheckError(f"cannot find FROM in query: {soql[:100]}")
    for path in where_field_paths(soql):
        if is_nonfilterable(m.group(1), path):
            raise CheckError(
                f"{m.group(1)}: WHERE filters on '{path}', a field SOQL cannot "
                f"filter on (long/rich text, encrypted or Description); select "
                f"it and check it in Python instead: {soql[:120]}")


def seed_literals():
    ident = seed_identity()
    return set(ident["account_names"] + ident["opp_names"]
               + ident["contact_lastnames"] + ident["contact_emails"])


def assert_query_safe(soql):
    """Every query this script issues must (a) be filterable by the real API
    and (b) carry an identifying filter: Is_Synthetic__c on a custom object,
    an Id/AccountId allowlist, or -- on Account/Opportunity/Contact -- ONLY
    exact seed identity literals read from the seed files."""
    assert_query_filterable(soql)
    where = _where_of(soql)
    m = re.search(r"\bFROM\s+(\w+)", soql)
    obj = m.group(1) if m else ""
    if not where:
        raise CheckError(f"refusing query without a WHERE: {soql[:120]}")
    if obj not in STANDARD_OBJECTS:
        if "Is_Synthetic__c" not in where:
            raise CheckError(f"refusing query on {obj} without Is_Synthetic__c: {soql[:120]}")
        return
    if re.match(r"^AccountId IN \('", where) and obj in ("Contact", "Opportunity"):
        return
    if obj == "Contact":
        ok = all(t in where for t in ("LastName IN ('", "Email IN ('", "Account.Name IN ('"))
    else:
        ok = where.startswith("Name IN ('")
    if not ok:
        raise CheckError(f"refusing {obj} query without the exact seed-identity filters: {soql[:120]}")
    stray = [v for v in (x[1:-1].replace("\\'", "'").replace("\\\\", "\\")
                         for x in _LITERAL_RE.findall(where)) if v not in seed_literals()]
    if stray:
        raise CheckError(f"refusing {obj} query with a literal that is not seed identity: {stray[0]!r}")


def soql_query(org, soql):
    """Read-only query; refuses any statement that is not filterable by the
    real API or lacks the identifying filters."""
    assert_query_safe(soql)
    result = run_sf_json(["data", "query", "--query", soql], org)
    return (result or {}).get("records", [])


def delete_ids(org, sobject, ids):
    """Bulk-delete an explicit Id list (collected from marked rows)."""
    import tempfile
    if sobject not in DELETABLE:
        raise CheckError(f"refusing to delete from {sobject}")
    ids = sorted(set(ids))
    bad = [i for i in ids if not _ID_RE.match(i)]
    if bad or not ids:
        raise CheckError(f"refusing delete on {sobject}: empty or malformed Id list")
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as fh:
        fh.write("Id\n" + "\n".join(ids) + "\n")
        path = fh.name
    try:
        run_sf_json(["data", "delete", "bulk", "--sobject", sobject,
                     "--file", path, "--wait", "10"], org)
    finally:
        os.unlink(path)


def _chunks(seq, n=150):
    seq = sorted(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


# ---------------------------------------------------------------------------
# Preflight (read-only): describe the 9 plan objects
# ---------------------------------------------------------------------------

def preflight_problems(describes, records_by_type):
    """Pure check of the seed against org describes: field exists and is
    createable, restricted picklist values are active, and every required
    createable field is written. Returns a sorted list of problems."""
    problems = set()
    for obj, recs in records_by_type.items():
        d = describes.get(obj)
        if not d:
            problems.add(f"{obj}: no describe result")
            continue
        fields = {f["name"]: f for f in d.get("fields", [])}
        for rec in recs:
            for key, val in rec.items():
                if key == "attributes":
                    continue
                f = fields.get(key)
                if f is None:
                    problems.add(f"{obj}.{key}: field does not exist in the org")
                    continue
                if not f.get("createable"):
                    problems.add(f"{obj}.{key}: not createable in this org "
                                 f"(formula, auto-number, read-only, or no FLS for the loading user)")
                    continue
                if f.get("restrictedPicklist") and isinstance(val, str):
                    active = {p["value"] for p in f.get("picklistValues", [])
                              if p.get("active", True)}
                    if val not in active:
                        problems.add(f"{obj}.{key}: '{val}' is not an active picklist value in the org")
            for name, f in fields.items():
                if (f.get("createable") and not f.get("nillable", True)
                        and not f.get("defaultedOnCreate") and f.get("type") != "boolean"
                        and name not in rec):
                    problems.add(f"{obj}.{name}: required in the org but not written by the seed")
    return sorted(problems)


def preflight_org(org, records_by_type):
    describes = {}
    for obj in records_by_type:
        describes[obj] = run_sf_json(["sobject", "describe", "--sobject", obj], org)
    return preflight_problems(describes, records_by_type)


# ---------------------------------------------------------------------------
# Already-loaded guard
# ---------------------------------------------------------------------------

def sweep_row_verified(sobject, row):
    """Python-side identity check for a sweep candidate (SOQL cannot filter
    on Description): Account/Opportunity must carry the script's own
    Description marker; a Contact's Email must be a .invalid address."""
    if sobject == "Contact":
        return str(row.get("Email") or "").endswith(".invalid")
    return str(row.get("Description") or "").startswith(DESC_MARKERS[sobject])


def sweep_candidates(org, sobject, where):
    """(verified_ids, unverified_count) for one orphan-sweep step."""
    col = "Email" if sobject == "Contact" else "Description"
    rows = soql_query(org, f"SELECT Id, {col} FROM {sobject} WHERE {where}")
    good = [r["Id"] for r in rows if sweep_row_verified(sobject, r)]
    return good, len(rows) - len(good)


def find_existing(org):
    """Objects that already hold synthetic or orphan [DEMO] rows (read-only)."""
    found = []
    for sobject, where, note in build_teardown_plan():
        if where.startswith("Id IN ("):
            continue
        if note.startswith(SWEEP_NOTE):
            if sweep_candidates(org, sobject, where)[0]:
                found.append(sobject)
        elif soql_query(org, f"SELECT Id FROM {sobject} WHERE {where} LIMIT 1"):
            found.append(sobject)
    return found


# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------

def collect_targets(org):
    """Read-only. Returns {'custom': {obj: [ids]}, 'standard': {obj: [ids]},
    'skipped': {obj: [ids]}, 'sweep': {obj: n}}; all standard Ids are
    collected BEFORE anything is deleted."""
    plan = build_teardown_plan()
    custom, std = {}, {o: set() for o in STANDARD_DELETE_ORDER}
    sweep_found = {o: set() for o in STANDARD_DELETE_ORDER}
    unverified = {o: 0 for o in STANDARD_DELETE_ORDER}
    for sobject, where, note in plan:
        if note.startswith(SWEEP_NOTE):
            good, bad = sweep_candidates(org, sobject, where)
            unverified[sobject] = bad
            for i in good:
                sweep_found[sobject].add(i)
                std[sobject].add(i)
        elif sobject in CUSTOM_DELETE_ORDER:
            cols = ["Id"] + LOOKUP_COLUMNS.get(sobject, [])
            rows = soql_query(org, f"SELECT {', '.join(cols)} FROM {sobject} WHERE {where}")
            custom[sobject] = [r["Id"] for r in rows]
            for r in rows:
                for col, target in COLUMN_TARGET.items():
                    if r.get(col):
                        std[target].add(r[col])

    skipped = {o: set() for o in STANDARD_DELETE_ORDER}
    # Never delete a record a real (non-synthetic) row still points at.
    for holder, cols in LOOKUP_COLUMNS.items():
        for col in cols:
            target = COLUMN_TARGET[col]
            for chunk in _chunks(std[target]):
                rows = soql_query(
                    org, f"SELECT Id, {col} FROM {holder} WHERE "
                         f"Is_Synthetic__c != true AND {col} IN {soql_list(chunk)}")
                for r in rows:
                    skipped[target].add(r[col])
    for o in STANDARD_DELETE_ORDER:
        std[o] -= skipped[o]
    # Deleting an Account cascades to its Contacts/Opportunities: keep any
    # Account that still has a child we are not deleting.
    for child in ("Contact", "Opportunity"):
        for chunk in _chunks(std["Account"]):
            rows = soql_query(
                org, f"SELECT Id, AccountId FROM {child} WHERE "
                     f"AccountId IN {soql_list(chunk)}")
            for r in rows:
                if r["Id"] not in std[child]:
                    skipped["Account"].add(r["AccountId"])
    std["Account"] -= skipped["Account"]
    return {
        "custom": custom,
        "standard": {o: sorted(std[o]) for o in STANDARD_DELETE_ORDER},
        "skipped": {o: sorted(skipped[o]) for o in STANDARD_DELETE_ORDER},
        "sweep": {o: len(sweep_found[o] & std[o]) for o in STANDARD_DELETE_ORDER},
        "unverified": unverified,
    }


def print_targets(t):
    print("Teardown targets (counts and Ids only):")
    for o in CUSTOM_DELETE_ORDER:
        ids = t["custom"].get(o, [])
        print(f"  {o}: {len(ids)}" + (f"  {', '.join(ids)}" if ids else ""))
    for o in STANDARD_DELETE_ORDER:
        ids = t["standard"][o]
        print(f"  {o}: {len(ids)} (of which {t['sweep'][o]} found only by the "
              f"orphan sweep)" + (f"  {', '.join(ids)}" if ids else ""))
    for o in STANDARD_DELETE_ORDER:
        if t.get("unverified", {}).get(o):
            print(f"  LEFT ALONE {o}: {t['unverified'][o]} record(s) share a seed name but "
                  f"lack the script's marker (not seed data)")
    for o in STANDARD_DELETE_ORDER:
        if t["skipped"][o]:
            print(f"  SKIPPED {o} (still referenced by a non-synthetic row or "
                  f"child): {', '.join(t['skipped'][o])}")


def cmd_check(_args):
    problems, records_by_type = check_seed_files()
    for obj, recs in sorted(records_by_type.items()):
        print(f"  {obj}: {len(recs)} record(s)")
    if problems:
        print("\nPROBLEMS FOUND:")
        for p in problems:
            print(" -", p)
        print(f"\n{len(problems)} problem(s). No org call was made.")
        return 1
    print("\nOK: seed data is structurally valid. No org call was made.")
    return 0


def cmd_check_teardown(_args):
    plan = build_teardown_plan()
    try:
        assert_teardown_plan_is_safe(plan)
    except CheckError as exc:
        print("TEARDOWN PLAN UNSAFE:", exc)
        return 1
    print("Teardown plan, in execution order (no org call was made):")
    for sobject, where, note in plan:
        print(f"  DELETE FROM {sobject} WHERE {where}")
        print(f"      ({note})")
    print("\nOK: every step is filtered by Is_Synthetic__c = true, a "
          "traversal to a parent carrying that same filter, an Id IN "
          "(...) allowlist collected from such a filtered row, or (orphan "
          "sweep only) an exact seed-identity match. No step can construct "
          "an unfiltered delete.")
    return 0


def cmd_preflight(args):
    if refuse_alias(args.org):
        return 2
    problems, records_by_type = check_seed_files()
    if problems:
        print("Seed data fails --check; fix that first.", file=sys.stderr)
        return 1
    try:
        org_problems = preflight_org(args.org, records_by_type)
    except SfError as exc:
        print("PREFLIGHT could not read the org:", exc, file=sys.stderr)
        return 1
    if org_problems:
        print("PREFLIGHT FAILED (nothing was written):")
        for p in org_problems:
            print(" -", p)
        return 1
    print(f"PREFLIGHT OK: every seeded field exists, is createable, and "
          f"satisfies org picklists/required fields in '{args.org}'.")
    return 0


def cmd_load(args):
    if refuse_alias(args.org):
        return 2
    if args.i_understand_this_writes_to_org != args.org:
        print(
            "Refusing to --load: --i-understand-this-writes-to-org must "
            "repeat the -o/--org value exactly, as a deliberate second "
            "confirmation.",
            file=sys.stderr,
        )
        return 2
    problems, records_by_type = check_seed_files()
    if problems:
        print("Refusing to --load: seed data fails --check. Run --check "
              "for details.", file=sys.stderr)
        return 1
    try:
        org_problems = preflight_org(args.org, records_by_type)
        if org_problems:
            print("Refusing to --load: PREFLIGHT FAILED (nothing was written):", file=sys.stderr)
            for p in org_problems:
                print(" -", p, file=sys.stderr)
            return 1
        existing = find_existing(args.org)
    except SfError as exc:
        print("Refusing to --load: could not read the org:", exc, file=sys.stderr)
        return 1
    if existing:
        print(f"Refusing to --load: '{args.org}' already holds synthetic/[DEMO] "
              f"rows ({', '.join(existing)}). Loading again would duplicate "
              f"the standard records. Review, then run:\n  "
              f"{teardown_command(args.org)} --dry-run\n  {teardown_command(args.org)}",
              file=sys.stderr)
        return 1
    import shutil
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="synthetic-demo-")
    try:
        plan_path = render_plan(tmpdir)
        return run_sf(["data", "import", "tree", "--plan", plan_path], args.org).returncode
    except subprocess.CalledProcessError as exc:
        print(f"\nLOAD FAILED (exit {exc.returncode}). Partial load possible; "
              f"nothing was deleted automatically. Run: "
              f"{teardown_command(args.org)}", file=sys.stderr)
        return 1
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def cmd_teardown(args):
    if refuse_alias(args.org):
        return 2
    if not args.dry_run and args.i_understand_this_writes_to_org != args.org:
        print(
            "Refusing to --teardown: --i-understand-this-writes-to-org "
            "must repeat the -o/--org value exactly (or pass --dry-run to "
            "only print what would be deleted).",
            file=sys.stderr,
        )
        return 2
    assert_teardown_plan_is_safe(build_teardown_plan())
    try:
        t = collect_targets(args.org)
    except (SfError, CheckError) as exc:
        print("TEARDOWN aborted before any delete:", exc, file=sys.stderr)
        return 1
    print_targets(t)
    total = sum(len(v) for v in t["custom"].values()) + sum(len(v) for v in t["standard"].values())
    if args.dry_run:
        print(f"\nDRY RUN: {total} record(s) would be deleted. No DML was issued.")
        return 0
    if total == 0:
        print("\nNothing to delete (clean no-op).")
        return 0
    steps = [(o, t["custom"].get(o, [])) for o in CUSTOM_DELETE_ORDER] + \
            [(o, t["standard"][o]) for o in STANDARD_DELETE_ORDER]
    steps = [(o, ids) for o, ids in steps if ids]
    for i, (sobject, ids) in enumerate(steps):
        try:
            delete_ids(args.org, sobject, ids)
        except (SfError, CheckError) as exc:
            print(f"\nTEARDOWN FAILED on {sobject}: {exc}", file=sys.stderr)
            print("Not yet deleted: " + ", ".join(f"{o} ({len(x)})" for o, x in steps[i:]), file=sys.stderr)
            print(f"Safe to re-run: {teardown_command(args.org)}", file=sys.stderr)
            return 1
        print(f"  deleted {len(ids)} {sobject}")
    print(f"\nTeardown complete: {total} record(s) deleted.")
    return 0


# ---------------------------------------------------------------------------
# --self-test: offline. Mutation tests on --check, plus stubbed-sf tests of
# preflight and teardown. No org, no `sf`.
# ---------------------------------------------------------------------------

def _check_with(mutator, objects_dir=None):
    g = globals()
    orig_load, orig_dir = g["load_records"], g["OBJECTS_DIR"]

    def patched(filename):
        recs, path = orig_load(filename)
        recs = copy.deepcopy(recs)
        mutator(os.path.basename(filename), recs)
        return recs, path

    g["load_records"] = patched
    if objects_dir:
        g["OBJECTS_DIR"] = objects_dir
    try:
        return check_seed_files()[0]
    finally:
        g["load_records"], g["OBJECTS_DIR"] = orig_load, orig_dir


def _mk(prefix, n):
    return prefix + str(n).zfill(15 - len(prefix))


class _FakeOrg:
    """Stubbed `sf`: answers data query / data delete bulk from in-memory
    state, records every query and delete, mutates state on delete."""

    def __init__(self):
        c = lambda **kw: dict(kw)
        self.flagged = {
            "GTM_Link_Event__c": [c(Id=_mk("a01", 1))],
            "GTM_Form_Draft__c": [c(Id=_mk("a02", 1))],
            "GTM_Readout_Version__c": [c(Id=_mk("a03", 1))],
            "GTM_Readout__c": [c(Id=_mk("a04", 1), Opportunity__c=_mk("006", 1))],
            "GTM_Assessment_Request__c": [c(Id=_mk("a05", 1), Account__c=_mk("001", 1), Contact__c=_mk("003", 1), Opportunity__c=_mk("006", 1))],
            "GTM_Saved_Configuration__c": [c(Id=_mk("a06", 1), Account__c=_mk("001", 1), Contact__c=_mk("003", 1), Opportunity__c=_mk("006", 1))],
        }
        # Orphans found by the sweep: Account 9 is clean, Account 8 is
        # referenced by a real row, Account 7 has a real child Contact.
        marker = lambda o: DESC_MARKERS[o] + " (issue synthetic-seed-data)."
        # Account 6 is a REAL customer that happens to share a seed Name: no marker.
        self.orphans = {"Opportunity": [{"Id": _mk("006", 9), "Description": marker("Opportunity")}],
                        "Contact": [{"Id": _mk("003", 9), "Email": "demo.x@demo.example.invalid"}],
                        "Account": [{"Id": _mk("001", 9), "Description": marker("Account")},
                                    {"Id": _mk("001", 8), "Description": marker("Account")},
                                    {"Id": _mk("001", 7), "Description": marker("Account")},
                                    {"Id": _mk("001", 6), "Description": "Real customer, long-standing"}]}
        self.std = {"Account": {_mk("001", 1)}, "Contact": {_mk("003", 1)}, "Opportunity": {_mk("006", 1)}}
        self.real_refs = [("GTM_Saved_Configuration__c", "Account__c", _mk("001", 8))]
        self.children = [("Contact", _mk("003", 99), _mk("001", 7))]
        self.queries, self.deletes = [], []

    def _alive(self, sobject, i):
        return i in self.std.get(sobject, set()) or i in [o["Id"] for o in self.orphans.get(sobject, [])]

    def __call__(self, args, org):
        if args[:2] == ["data", "query"]:
            q = args[args.index("--query") + 1]
            self.queries.append(q)
            # The real org's rule, implemented independently of the script's
            # own check: long-text/Description fields cannot appear in WHERE.
            where = _LITERAL_RE.sub("''", q.split(" WHERE ", 1)[1]) if " WHERE " in q else ""
            bad = re.search(r"\b(Description|Readout_Data__c|Draft_JSON__c|Rep_Context_Notes__c|Config_Payload__c)\b", where)
            if bad:
                raise SfError(f"field '{bad.group(1)}' can not be filtered in a query call")
            obj = re.search(r"FROM (\w+)", q).group(1)
            ids = set(re.findall(r"'([A-Za-z0-9]{15})'", q))
            if "Is_Synthetic__c != true" in q:
                col = re.search(r"AND (\w+) IN", q).group(1)
                return {"records": [{"Id": _mk("a09", 1), col: v} for h, cl, v in self.real_refs
                                    if h == obj and cl == col and v in ids]}
            if "AccountId IN" in q:
                return {"records": [{"Id": i, "AccountId": a} for o, i, a in self.children
                                    if o == obj and a in ids]}
            if obj in self.orphans and ("Name IN (" in q):
                return {"records": [dict(r) for r in self.orphans[obj]]}
            if obj in self.flagged:
                return {"records": [dict(r) for r in self.flagged[obj]]}
            raise AssertionError("unexpected query " + q)
        if args[:3] == ["data", "delete", "bulk"]:
            sobject = args[args.index("--sobject") + 1]
            with open(args[args.index("--file") + 1]) as fh:
                ids = fh.read().split()[1:]
            self.deletes.append((sobject, ids))
            self.flagged[sobject] = [r for r in self.flagged.get(sobject, []) if r["Id"] not in ids]
            self.std.get(sobject, set()).difference_update(ids)
            if sobject in self.orphans:
                self.orphans[sobject] = [r for r in self.orphans[sobject] if r["Id"] not in ids]
            return {}
        raise AssertionError("unexpected sf call " + " ".join(args))


def cmd_self_test(_args):
    import io
    import contextlib
    import shutil
    import tempfile
    failures, passed = [], [0]

    def expect(name, cond, detail=""):
        if cond:
            passed[0] += 1
            print(f"  ok   {name}")
        else:
            failures.append(name)
            print(f"  FAIL {name} {detail}")

    def has(problems, *frags):
        return any(all(f in p for f in frags) for p in problems)

    def edit(fname, fn):
        return lambda name, recs: fn(recs) if name == fname else None

    SC, RD = "synthetic-demo.saved-configurations.json", "synthetic-demo.readouts.json"

    print("mutation tests on --check:")
    # 12 first: unmutated data is clean.
    expect("12 unmutated data has zero problems", _check_with(lambda n, r: None) == [], str(_check_with(lambda n, r: None)))
    expect("1 formula Industry_Label__c on Saved Configuration (regression)",
           has(_check_with(edit(SC, lambda r: r[0].update(Industry_Label__c="Retail"))), "Industry_Label__c", "formula"))
    expect("2 auto-number Name on GTM_Readout__c",
           has(_check_with(edit(RD, lambda r: r[0].update(Name="x"))), "Name", "auto-number"))
    expect("3 nonexistent Bogus__c",
           has(_check_with(edit(SC, lambda r: r[0].update(Bogus__c="x"))), "Bogus__c", "does not exist"))
    tmp = tempfile.mkdtemp()
    try:
        objs = os.path.join(tmp, "objects")
        shutil.copytree(OBJECTS_DIR, objs)
        fx = os.path.join(objs, "GTM_Saved_Configuration__c", "fields", "Rollup_Fixture__c.field-meta.xml")
        with open(fx, "w") as fh:
            fh.write(f'<?xml version="1.0"?><CustomField xmlns="{NS[1:-1]}">'
                     '<fullName>Rollup_Fixture__c</fullName><type>Summary</type></CustomField>')
        expect("4 roll-up summary field",
               has(_check_with(edit(SC, lambda r: r[0].update(Rollup_Fixture__c=1)), objs), "Rollup_Fixture__c", "roll-up"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    expect("5 OwnerId system field",
           has(_check_with(edit(SC, lambda r: r[0].update(OwnerId=_mk("005", 1) + "AAA"))), "OwnerId", "system-managed"))

    # 6: pick a restricted picklist the seed already uses.
    target = None
    for step in load_plan():
        for fn in step["files"]:
            recs, _ = load_records(fn)
            for rec in recs:
                for k, v in rec.items():
                    if k != "attributes" and isinstance(v, str) and picklist_values(step["sobject"], k):
                        target = target or (os.path.basename(fn), k)
    expect("6 restricted picklist value outside the set (a restricted picklist is in the seed)", target is not None)
    if target:
        expect("6 restricted picklist value outside the set",
               has(_check_with(edit(target[0], lambda r: r[0].update({target[1]: "__not_a_value__"}))), target[1], "is not one of"))
    expect("7 missing required Offering__c",
           has(_check_with(edit(SC, lambda r: r[0].pop("Offering__c"))), "missing required field Offering__c"))
    expect("8 @ref to the wrong sobject type",
           has(_check_with(edit(SC, lambda r: r[0].update(Account__c="@demoOpp1"))), "Account__c", "points at Account"))
    expect("9 raw 18-char Id in a lookup",
           has(_check_with(edit(SC, lambda r: r[0].update(Account__c=_mk("001", 1) + "AAA"))), "Account__c", "raw Id"))
    expect("10 string for a Checkbox",
           has(_check_with(edit(SC, lambda r: r[0].update(Is_Synthetic__c="true"))), "Is_Synthetic__c", "Checkbox"))
    acct = lambda r: r[0].update(Name="[DEMO] Renamed")
    expect("11 Name on Account is still allowed (negative control)",
           not has(_check_with(edit("synthetic-demo.accounts.json", acct)), "writes Name"))
    expect("12b Account without the Description marker is rejected",
           has(_check_with(edit("synthetic-demo.accounts.json", lambda r: r[0].update(Description="x"))), "Description must start with"))

    print("teardown plan safety:")
    plan = build_teardown_plan()
    ident = seed_identity()
    expect("plan passes assert_teardown_plan_is_safe", assert_teardown_plan_is_safe(plan) is True)
    sweep = "\n".join(w for _, w, n in plan if n.startswith(SWEEP_NOTE))
    everything = ident["account_names"] + ident["opp_names"] + ident["contact_lastnames"] + ident["contact_emails"]
    expect("sweep WHERE contains every seed Name/LastName/Email",
           all(soql_str(v)[1:-1] in sweep for v in everything))
    bad_plan = [list(x) for x in plan]
    bad_plan[-1][1] = "Name IN ('[DEMO] x')"
    try:
        assert_teardown_plan_is_safe([tuple(x) for x in bad_plan])
        expect("sweep WHERE with no Description marker is rejected", False)
    except CheckError:
        expect("sweep WHERE with no Description marker is rejected", True)
    bad_plan[-1][1] = "Id != null"
    try:
        assert_teardown_plan_is_safe([tuple(x) for x in bad_plan])
        expect("sweep WHERE with no marker at all is rejected", False)
    except CheckError:
        expect("sweep WHERE with no marker at all is rejected", True)
    try:
        soql_query("x", "SELECT Id FROM Account WHERE Name = 'Real Co'")
        expect("query without a marker is refused", False)
    except CheckError:
        expect("query without a marker is refused", True)
    def refused_by(fn, *a):
        try:
            fn(*a)
            return False
        except CheckError:
            return True

    print("non-filterable SOQL fields (the Description-in-WHERE class of bug):")
    expect("Description in an Account WHERE is refused",
           refused_by(assert_query_filterable, "SELECT Id FROM Account WHERE Name IN ('x') AND Description LIKE 'Synthetic%'"))
    expect("Description on Opportunity and Contact, and Account.Description via a Contact, are refused",
           refused_by(assert_query_filterable, "SELECT Id FROM Opportunity WHERE Description = 'x'")
           and refused_by(assert_query_filterable, "SELECT Id FROM Contact WHERE Description = 'x'")
           and refused_by(assert_query_filterable, "SELECT Id FROM Contact WHERE Account.Description = 'x'"))
    lta = next((f for f in ("Readout_Data__c", "Draft_JSON__c", "Rep_Context_Notes__c") if (field_facts("GTM_Readout__c", f) or {}).get("type") == "LongTextArea"), None)
    expect("a LongTextArea custom field (read from metadata) in a WHERE is refused",
           lta is not None and refused_by(assert_query_filterable, f"SELECT Id FROM GTM_Readout__c WHERE Is_Synthetic__c = true AND {lta} = 'x'"))
    expect("a long-text field reached through a relationship (__r) is refused",
           refused_by(assert_query_filterable, f"SELECT Id FROM GTM_Readout_Version__c WHERE Readout__r.{lta} = 'x'"))
    expect("the fields the script really filters on are allowed (checkbox, Name, LastName, Email, Account.Name, Readout__r.Is_Synthetic__c, AccountId)",
           not refused_by(assert_query_filterable, "SELECT Id FROM GTM_Readout_Version__c WHERE Readout__r.Is_Synthetic__c = true")
           and not refused_by(assert_query_filterable, "SELECT Id FROM GTM_Readout__c WHERE Is_Synthetic__c != true AND Opportunity__c IN ('%s')" % _mk("006", 1))
           and not refused_by(assert_query_filterable, "SELECT Id FROM Contact WHERE LastName IN ('a') AND Email IN ('b') AND Account.Name IN ('c')")
           and not refused_by(assert_query_filterable, "SELECT Id, AccountId FROM Opportunity WHERE AccountId IN ('%s')" % _mk("001", 1)))
    expect("a literal containing the word Description is not mistaken for a field",
           not refused_by(assert_query_filterable, "SELECT Id FROM Account WHERE Name IN ('Description = x')"))
    expect("a query with a Name literal that is not seed identity is refused",
           refused_by(soql_query, "stub", "SELECT Id FROM Account WHERE Name IN ('Real Co')"))
    expect("a query that filters on Description is refused before any sf call",
           refused_by(soql_query, "stub", "SELECT Id FROM Account WHERE Name IN ('%s') AND Description LIKE 'Synthetic demo%%'" % ident["account_names"][0]))
    expect("plan wheres contain no non-filterable field",
           all(not refused_by(assert_query_filterable, f"SELECT Id FROM {o} WHERE {w}") for o, w, _ in plan if not w.startswith("Id IN (")))
    with contextlib.redirect_stderr(io.StringIO()):
        refused = [refuse_alias(a) for a in ("gtm-dev", "GTM-Dev")] + [refuse_alias("gtm-staging")]
    expect("gtm-dev alias is refused (case-insensitive), other aliases are not", refused == [True, True, False])

    print("filter coverage:")
    _, records = check_seed_files()
    universe, cov = compute_coverage(records)
    got = {k: len(v) for k, v in cov.items() if k[1] not in ("Account", "Contact")}
    expect("universe sizes match the golden table",
           {k: len(v) for k, v in universe.items()} == EXPECTED_UNIVERSE)
    expect("every filter option's row count matches the golden coverage table", got == EXPECTED_COVERAGE,
           str({k: (got.get(k), EXPECTED_COVERAGE.get(k)) for k in set(got) | set(EXPECTED_COVERAGE) if got.get(k) != EXPECTED_COVERAGE.get(k)}))
    stage_sets = {opt: frozenset(v) for (tab, flt, opt), v in cov.items() if flt == "Funnel stage"}
    expect("all 7 funnel-stage options exist and return pairwise different row sets",
           len(stage_sets) == 7 and len(set(stage_sets.values())) == 7)
    groups = {}
    for (tab, flt, opt), v in cov.items():
        groups.setdefault((tab, flt), {})[opt] = frozenset(v)
    for (tab, flt), opts in sorted(groups.items()):
        if flt in ("Ready to book",):
            expect(f"{tab}/{flt} returns a non-empty strict subset", 0 < len(opts["on"]) < len(universe[tab]))
            continue
        real = {o: v for o, v in opts.items() if not o.startswith("(")}
        ok = len(real) >= 2 and len(set(real.values())) == len(real) and \
            all(v and (flt == "Funnel stage" or len(v) < len(universe[tab])) for v in real.values())
        expect(f"{tab}/{flt}: >=2 options, each non-empty, distinct, and (except 'sent') a strict subset", ok)
    expect("an Approved-and-sent readout, the unreachable state, is seeded",
           any("approved and sent" in o for (t, f, o) in cov if f == "Readout"))
    dm = data_model_problems(records)
    expect("data model: no link has more than one assessment request", not any("at most one" in x for x in dm), str(dm))
    expect(f"data model: at least {MIN_UNLINKED_REQUESTS} requests are unlinked, links stage-consistent, some links have no request",
           dm == [], str(dm))
    nreq = [r for r in records["GTM_Assessment_Request__c"] if not r.get("Saved_Configuration__c")]
    expect("data model: unlinked count is 6 and unlinked requests reference no link opportunity", len(nreq) == 6)
    dup = copy.deepcopy(records)
    dup["GTM_Assessment_Request__c"][1]["Saved_Configuration__c"] = dup["GTM_Assessment_Request__c"][0]["Saved_Configuration__c"] or "@demoCfg13"
    dup["GTM_Assessment_Request__c"][0]["Saved_Configuration__c"] = "@demoCfg13"
    expect("data model mutation: two requests on one link is caught", any("at most one" in x for x in data_model_problems(dup)))
    few = copy.deepcopy(records)
    for r in few["GTM_Assessment_Request__c"][:9]:
        r.setdefault("Saved_Configuration__c", "@demoCfg1")
    expect("data model mutation: too few unlinked requests is caught", any("unlinked assessment requests" in x for x in data_model_problems(few)))
    stg = copy.deepcopy(records)
    stg["GTM_Saved_Configuration__c"][3]["Presentation_Stage__c"] = "Assessment"
    expect("data model mutation: Assessment-stage link with no request is caught", any("no assessment request" in x for x in data_model_problems(stg)))
    expect("every standard record is reachable by teardown via a link or request lookup",
           {str(r.get(c))[1:] for h in ("GTM_Saved_Configuration__c", "GTM_Assessment_Request__c")
            for r in records[h] for c in LOOKUP_COLUMNS[h] if r.get(c)}
           >= {r["attributes"]["referenceId"] for o in ("Account", "Contact", "Opportunity") for r in records[o]})
    expect("at least one submitted-before-90-days request exists", ("Assessments", "Submitted", "older than 90 days") in cov)
    g = globals()
    orig_now = g["NOW"]
    try:
        g["NOW"] = datetime.date(2026, 9, 20)
        expect("$DAYS_AGO renders relative to today",
               render_value("$DAYS_AGO:2") == "2026-09-18T12:00:00.000Z" and render_value("plain") == "plain")
    finally:
        g["NOW"] = orig_now
    tmp2 = tempfile.mkdtemp()
    try:
        plan_path = render_plan(tmp2)
        text = "".join(open(os.path.join(tmp2, f), encoding="utf-8").read() for f in os.listdir(tmp2))
        expect("render_plan resolves every relative-date token and writes every plan file",
               "$DAYS_AGO" not in text and all(os.path.isfile(os.path.join(tmp2, fn))
                                              for st in json.load(open(plan_path)) for fn in st["files"]))
    finally:
        shutil.rmtree(tmp2, ignore_errors=True)

    print("stubbed-sf tests:")
    g = globals()
    orig_rsj = g["run_sf_json"]
    quiet = io.StringIO()
    try:
        # (a) preflight rejects createable:false on Industry_Label__c.
        _, recs_by_type = check_seed_files()
        recs = copy.deepcopy(recs_by_type)
        recs["GTM_Saved_Configuration__c"][0]["Industry_Label__c"] = "Retail"

        def describe(args, org):
            obj = args[args.index("--sobject") + 1]
            keys = {k for r in recs[obj] for k in r if k != "attributes"}
            fields = [{"name": k, "createable": k != "Industry_Label__c", "nillable": True,
                       "defaultedOnCreate": False, "type": "string", "restrictedPicklist": False}
                      for k in keys]
            if obj == "GTM_Readout__c":
                fields.append({"name": "Status__c", "createable": True, "nillable": True, "defaultedOnCreate": False,
                               "type": "picklist", "restrictedPicklist": True,
                               "picklistValues": [{"value": "Only_This", "active": True}]})
                fields.append({"name": "Needed__c", "createable": True, "nillable": False,
                               "defaultedOnCreate": False, "type": "string"})
            return {"fields": fields}

        g["run_sf_json"] = describe
        probs = preflight_org("stub", recs)
        expect("a preflight rejects Industry_Label__c createable:false", has(probs, "Industry_Label__c", "not createable"))
        expect("a preflight rejects a restricted picklist value not active in the org", has(probs, "GTM_Readout__c.Status__c", "not an active picklist"))
        expect("a preflight rejects a required org field the seed does not write", has(probs, "Needed__c", "required in the org"))
        clean = copy.deepcopy(recs_by_type)
        g["run_sf_json"] = lambda a, o: {"fields": [
            {"name": k, "createable": True, "nillable": True, "defaultedOnCreate": False, "type": "string"}
            for k in {k for r in clean[a[a.index("--sobject") + 1]] for k in r if k != "attributes"}]}
        expect("a preflight is clean when the org matches", preflight_org("stub", clean) == [])

        # The stub itself rejects a Description WHERE like the real org.
        probe = _FakeOrg()
        try:
            probe(["data", "query", "--query", "SELECT Id FROM Account WHERE Name IN ('x') AND Description LIKE 'S%'"], "stub")
            expect("stub rejects a Description filter like the real org", False)
        except SfError as exc:
            expect("stub rejects a Description filter like the real org", "can not be filtered" in str(exc))
        # ... and the old sweep shape (Description LIKE) would fail against it,
        # even with the script's own guard out of the way.
        orig_safe = g["assert_query_safe"]
        g["assert_query_safe"] = lambda q: None
        g["run_sf_json"] = probe
        try:
            soql_query("stub", "SELECT Id FROM Account WHERE Name IN ('x') AND Description LIKE 'Synthetic demo%'")
            expect("old Description-LIKE sweep fails the stub even if the script guard is bypassed", False)
        except SfError:
            expect("old Description-LIKE sweep fails the stub even if the script guard is bypassed", True)
        finally:
            g["assert_query_safe"] = orig_safe
        # The already-loaded guard and preflight queries go through the same stub.
        g["run_sf_json"] = _FakeOrg()
        existing = find_existing("stub")
        expect("already-loaded guard queries pass the filterability stub and find the seeded rows",
               "GTM_Saved_Configuration__c" in existing and "Account" in existing)
        # (b) teardown order and query safety; (c) idempotent second run.
        org = _FakeOrg()
        g["run_sf_json"] = org
        targs = argparse.Namespace(org="stub-org", i_understand_this_writes_to_org="stub-org", dry_run=True)
        with contextlib.redirect_stdout(quiet):
            rc_dry = cmd_teardown(targs)
        expect("b dry-run issues no delete", rc_dry == 0 and org.deletes == [])
        targs.dry_run = False
        with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            rc1 = cmd_teardown(targs)
        order = [o for o, _ in org.deletes]
        expect("b deletes run child-to-parent in plan order",
               rc1 == 0 and order == CUSTOM_DELETE_ORDER + STANDARD_DELETE_ORDER, str(order))
        deleted_std = {i for o, ids in org.deletes if o in STANDARD_DELETE_ORDER for i in ids}
        expect("b clean orphans are deleted", {_mk("001", 9), _mk("003", 9), _mk("006", 9)} <= deleted_std)
        expect("b orphan referenced by a real row is skipped", _mk("001", 8) not in deleted_std)
        expect("b orphan Account with a real child is skipped", _mk("001", 7) not in deleted_std)
        def _safe(q):
            try:
                assert_query_safe(q)
                return True
            except CheckError:
                return False
        expect("b every query the teardown built passes assert_query_safe (filterable and identified)",
               org.queries and all(_safe(q) for q in org.queries))
        expect("b the sweep queries never put Description in a WHERE and do select it",
               not any(re.search(r"\bDescription\b", q.split(" WHERE ", 1)[1]) for q in org.queries)
               and any(q.startswith("SELECT Id, Description FROM Account") for q in org.queries))
        expect("b a real Account sharing a seed Name but lacking the marker is left alone", _mk("001", 6) not in deleted_std)
        n = len(org.deletes)
        with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
            rc2 = cmd_teardown(targs)
        expect("c second run is a clean no-op", rc2 == 0 and len(org.deletes) == n)
        # Refusals never reach sf.
        g["run_sf_json"] = lambda a, o: (_ for _ in ()).throw(AssertionError("sf called"))
        with contextlib.redirect_stderr(quiet):
            expect("teardown refuses gtm-dev before any sf call",
                   cmd_teardown(argparse.Namespace(org="gtm-dev", i_understand_this_writes_to_org="gtm-dev", dry_run=False)) == 2)
            expect("teardown without the confirmation flag is refused",
                   cmd_teardown(argparse.Namespace(org="x", i_understand_this_writes_to_org=None, dry_run=False)) == 2)
    finally:
        g["run_sf_json"] = orig_rsj

    print(f"\n{passed[0]} passed, {len(failures)} failed. No org call was made.")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Validate seed data locally. No org call.")
    mode.add_argument("--check-teardown", action="store_true", help="Validate the teardown plan's safety locally. No org call.")
    mode.add_argument("--coverage", action="store_true", help="Print which seeded records feed which filter option, with expected row counts. Offline.")
    mode.add_argument("--self-test", action="store_true", help="Offline mutation + stubbed-sf tests. No org call.")
    mode.add_argument("--preflight", action="store_true", help="Read-only: describe the plan objects in -o org and verify the seed can load. Writes nothing.")
    mode.add_argument("--load", action="store_true", help="Import the seed data into a test org (never gtm-dev).")
    mode.add_argument("--teardown", action="store_true", help="Delete synthetic rows from a test org (never gtm-dev).")
    parser.add_argument("-o", "--org", dest="org", help="Target org alias (required for --preflight / --load / --teardown).")
    parser.add_argument(
        "--i-understand-this-writes-to-org",
        dest="i_understand_this_writes_to_org",
        default=None,
        help="Must exactly repeat -o/--org to confirm a live --load or --teardown run.",
    )
    parser.add_argument("--dry-run", action="store_true", help="With --teardown: query and print exactly what would be deleted (counts and Ids); issue no DML.")
    args = parser.parse_args()

    if args.check:
        return cmd_check(args)
    if args.check_teardown:
        return cmd_check_teardown(args)
    if args.self_test:
        return cmd_self_test(args)
    if args.coverage:
        return cmd_coverage(args)
    if args.dry_run and not args.teardown:
        parser.error("--dry-run only applies to --teardown")
    if not args.org:
        parser.error("--preflight / --load / --teardown require -o/--org")
    if args.preflight:
        return cmd_preflight(args)
    if args.load:
        return cmd_load(args)
    if args.teardown:
        return cmd_teardown(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
