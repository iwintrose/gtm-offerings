#!/usr/bin/env python3
"""
Compiles the instrument authoring files into Salesforce custom metadata.

    instrument/<offering-key>/dimensions.yaml    the 8-slot frame
    instrument/<offering-key>/complexity.yaml    the 6-dimension frame
    instrument/<offering-key>/gates.yaml         tier qualifiers
    instrument/<offering-key>/supplements/*.yaml layer-4 question sets
    instrument/<offering-key>/pairs/*.yaml       one file per pair

        ->  force-app/main/default/customMetadata/GTM_Assessment_Pair.*.md-meta.xml
            force-app/main/default/customMetadata/GTM_Assessment_Dimension_Override.*.md-meta.xml
            force-app/main/default/customMetadata/GTM_Assessment_Supplement.*.md-meta.xml
            force-app/main/default/customMetadata/GTM_Assessment_Gate.*.md-meta.xml

ONE DIRECTORY PER OFFERING (ADR-0007). Every immediate subdirectory of
`instrument/` that contains a dimensions.yaml is an INDEPENDENT offering: all
14 rules below run WITHIN one offering directory and never across two, and
every emitted record is stamped with Offering_Key__c = the directory name.
A second offering's instrument therefore has to hold together on its own
terms, and cannot be validated against -- or accidentally satisfied by --
Migration Accelerator's content. An offering's pairs/ and supplements/
directories are optional; an offering wanting no adaptive layer authors a
single pairs/base.yaml (source "*", target "*") and nothing else.

WHY A BUILD STEP AT ALL. The generated XML is what deploys, but nobody can
review it: a pair is ~15 files of <values><field>...</field></values> and the
one thing a reviewer must be able to see -- that the frame still holds -- is
invisible in that shape. The YAML is the reviewable artifact and the XML is a
build output, committed so `sf project deploy` needs no toolchain.

The checks below are the load-bearing part. Each one exists because the
corresponding mistake is silent: it produces an instrument that still runs and
still prints a number, and the number is wrong or incomparable.

  1. Exactly 8 active slots resolve for EVERY pair, in positions 1-8.
     This is the invariant that keeps the total out of 32 and the four bands
     meaningful. A pair that resolves to 7 slots still scores; it just scores
     out of 28 while telling the prospect it scored out of 32.
  2. Every option set has exactly 4 options, values 1,2,3,4, no gaps, no
     duplicates. A missing 3 renumbers everything after it and changes what
     every already-stored answer meant.
  3. A substitution requires a non-empty rationale AND a substitutable slot.
     Slots 1 and 8 are pinned; swapping one out is what makes two prospects'
     24s stop describing the same eight things.
  4. A ceiling renders. max_attainable requires a ceiling_reason and a full
     four-option set, so the excluded option can be shown greyed with the
     reason beside it rather than silently dropped. A prospect who can see the
     4 was not on offer can argue with the instrument; one who cannot has been
     quietly marked down.
  5. Every rationale's cited file path exists. Rationale that cannot be traced
     is how an instrument becomes folklore.
  6. A supplement key never collides with a dimension key. Layer 4 sits
     outside the 32 by construction, not by intention.
  7. A gate predicate only references declared fields. A gate keyed on a typo
     never fires, and never firing looks exactly like not applying.
  8. A show_when predicate references only `source`, `target`, or a slot at a
     STRICTLY LOWER position. Branching then resolves in one pass, in position
     order, with no fixpoint and no cycle -- which is the only reason the
     questionnaire (branching as it goes) and the server (branching from the
     finished answer map) are guaranteed to agree.
  9. Every slot has exactly one DEFAULT question -- the row with no show_when --
     and every variant declares a unique variant_key. This is the invariant that
     survives branching: a variant SUBSTITUTES for the default, so the slot is
     filled whatever the answers were, and eight slots are always answered.
 10. Authored option points bottom out at 1, top out at 4, and never descend.
     Points may make a scale non-linear; they may not make it longer or shorter.
     Every branch path therefore still maxes at 32 and the four band edges
     (14/20/26), which were calibrated against 32, still mean what they say.
 11. Every authored variant is REACHABLE and no two slots can ever resolve to
     the same key. A variant shadowed by an earlier one is a question nobody
     will ever be asked, which looks exactly like a question that works; two
     slots sharing a key is two answers overwriting each other in one storage
     slot.
 12. THE SECOND AXIS, held to the same standard as the first. Exactly 6 active
     complexity dimensions resolve for EVERY pair, in positions 1-6; every
     complexity option set is exactly 1,2,3; no complexity dimension is
     unreachable (an override that never wins a field on any pair is a question
     nobody will ever be asked); and no complexity override declares a ceiling,
     because a cap on "how many workflows do you have" is the instrument
     refusing to hear a number. The frame's band edges are checked against
     GtmEstateComplexity's, which are the ones that actually run.
 13. Prospect-facing text uses an em dash, not "--". YAML-sourced copy rendered
     "live in HubSpot today -- active workflows" beside metadata-sourced copy
     that used a proper dash, on the same screen, for months. Nobody notices
     their own typography; a build does.
 14. Every emitted string fits the field it is written into. Evidence_Prompt__c
     was Text(255) and held 413 characters -- a deploy failure that nothing in
     this repo could have caught, because nothing had ever been deployed.

Usage:  python3 scripts/build-instrument.py [--check]
        --check   validate and diff only; write nothing (CI mode)
Exit:   0 = clean, 1 = a rule was violated or output is stale
"""
import argparse
import glob
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INSTRUMENT = os.path.join(ROOT, "instrument")
CMD_DIR = os.path.join(ROOT, "force-app", "main", "default", "customMetadata")
QUESTION_GLOB = "GTM_Assessment_Question."

NS = "http://soap.sforce.com/2006/04/metadata"
POSTURE_RANK = {"interview_only": 0, "assisted": 1, "instrumented": 2}
LAYERS = ("reword", "recalibrate", "substitute")
INSTRUMENT_READINESS = "Readiness"
INSTRUMENT_COMPLEXITY = "Complexity"
# ---------------------------------------------------------------------------
# MIGRATION ACCELERATOR'S FRAME, STILL GLOBAL. See the "open call" in
# docs/agent-artifacts/per-offering-instrument-plan.md section 1.2 and
# ADR-0007 section 2 / Consequences.
#
# The four constants below -- and the literal 8 / 1-8 slot checks and the
# expect_max=4 readiness scale in main()'s validation body -- are Migration
# Accelerator's frame, not the framework's. They are STILL GLOBAL PYTHON
# CONSTANTS after the per-offering split, applied identically to every
# offering directory. That is correct today, because migration-accelerator is
# the only offering that exists and its shape is exactly these numbers.
#
# A SECOND offering with a different slot count or answer scale needs them
# read per-offering-directory instead -- most naturally from that offering's
# own dimensions.yaml/complexity.yaml (the slots/dimensions list length, and
# each option set's own expect_max, all already present in the YAML), with
# GTM_Assessment_Frame__mdt as the actual source of truth once a record for
# that offering exists. That generalisation was DELIBERATELY NOT attempted
# here: doing it speculatively means guessing at a shape, where doing it when
# a real second offering is authored means proving it against an actual case.
# Whoever opens the second offering directory: this is the change, and this
# is why it was left for you.
# ---------------------------------------------------------------------------
# The complexity scale, mirrored from GtmEstateComplexity. Typed here rather than
# derived because this is the check: if the two disagree, one of them is wrong
# and the build is the place to find out.
COMPLEXITY_MAX_ANSWER = 3
COMPLEXITY_DIMENSION_COUNT = 6
COMPLEXITY_BANDS = (("Light", 6, 9), ("Moderate", 10, 13), ("Heavy", 14, 18))
APEX_COMPLEXITY = os.path.join("force-app", "main", "default", "classes",
                               "GtmEstateComplexity.cls")
OPS = ("eq", "ne", "lt", "lte", "gt", "gte", "in", "not_in")
ANY = "*"
DEFAULT_VARIANT = "default"
# Reachability (rule 11) enumerates the answers a predicate could see. Every
# scored slot is 1-4, so the space is 4**(fields referenced). Refusing to
# enumerate past this many fields is cheaper than a build that takes a minute;
# a predicate over seven other slots is not a branch, it is a scoring model.
MAX_REACHABILITY_FIELDS = 6

errors = []
warnings = []

# Which offering directory the validation body is currently inside. Prefixed
# onto every fail()/warn() location so a failure is traceable to the right
# offering without touching the ~120 call sites that pass a file-relative
# `where`.
_offering_prefix = ""


def fail(where, msg):
    errors.append("%s%s: %s" % (_offering_prefix, where, msg))


def warn(where, msg):
    warnings.append("%s%s: %s" % (_offering_prefix, where, msg))


def offering_dirs():
    """Every immediate subdirectory of INSTRUMENT that is an offering.

    Keyed on the presence of a dimensions.yaml rather than on "is a directory",
    so a stray file or a non-offering folder left at the old flat location is
    never mistaken for an offering and silently validated as an empty one.
    """
    out = []
    if not os.path.isdir(INSTRUMENT):
        return out
    for name in sorted(os.listdir(INSTRUMENT)):
        path = os.path.join(INSTRUMENT, name)
        if os.path.isdir(path) and os.path.exists(os.path.join(path, "dimensions.yaml")):
            out.append((name, path))
    return out


OFFERING_GLOB = "GTM_Offering.*.md-meta.xml"


def offering_keys_from_cmdt():
    """Every Offering_Key__c on a committed GTM_Offering__mdt record.

    Source of truth for the PRE-FLIGHT cross-check in main(): an instrument
    directory must correspond to an offering that actually exists. Reads the
    committed XML only -- no org connection, no `sf` CLI, no DML -- so it
    behaves identically in CI and on a laptop with no authenticated org.

    Returns (keys, record_count). A record_count of 0 means the offering
    source itself is missing, which is a different failure from a directory
    that does not match any offering, and main() reports it as such.
    """
    keys = set()
    files = sorted(glob.glob(os.path.join(CMD_DIR, OFFERING_GLOB)))
    for path in files:
        try:
            tree = ET.parse(path)
        except ET.ParseError as exc:
            fail(os.path.relpath(path, ROOT),
                 "is not parseable XML, so its offering key cannot be read: %s" % exc)
            continue
        for values in tree.getroot().findall("{%s}values" % NS):
            field = values.find("{%s}field" % NS)
            value = values.find("{%s}value" % NS)
            if field is not None and (field.text or "").strip() == "Offering_Key__c":
                if value is not None and (value.text or "").strip():
                    keys.add(value.text.strip())
    return keys, len(files)


def check_offerings_exist(offerings):
    """PRE-FLIGHT, not a 15th rule.

    offering_dirs() admits a directory on filesystem evidence alone -- a
    dimensions.yaml is enough -- so a directory named for an offering that has
    no GTM_Offering__mdt record behind it would compile and stamp
    Offering_Key__c onto a full scored instrument for an offering the app does
    not have. That is a precondition on the inputs rather than a property of
    an instrument's contents, which is why it runs once, here, and not inside
    build_offering() (which deliberately cannot see outside its own directory).
    """
    keys, record_count = offering_keys_from_cmdt()
    if record_count == 0:
        # ONE error, naming the missing source. Emitting one per offering
        # directory would bury the actual cause under a cascade.
        fail(os.path.relpath(CMD_DIR, ROOT),
             "no GTM_Offering__mdt records found (no %s). Every instrument "
             "directory is cross-checked against the committed offering "
             "records, so the offering source cannot be absent." % OFFERING_GLOB)
        return
    for name, _path in offerings:
        if name not in keys:
            fail("instrument/%s/" % name,
                 "no GTM_Offering__mdt record has Offering_Key__c = '%s'. An "
                 "instrument directory must correspond to a committed "
                 "offering. Add force-app/main/default/customMetadata/"
                 "GTM_Offering.<Name>.md-meta.xml with Offering_Key__c = "
                 "'%s', or rename the directory to an existing offering key "
                 "(known keys: %s)."
                 % (name, name, ", ".join(sorted(keys)) or "none"))


# --------------------------------------------------------------- source root

def source_root():
    """Where the cited rationale paths live (the ma-migrator working copy)."""
    for cand in [
        os.environ.get("MA_MIGRATOR_ROOT"),
        os.path.join(os.path.dirname(ROOT), "ma-migrator"),
        "/home/user/ma-migrator",
    ]:
        if cand and os.path.isdir(cand):
            return cand
    return None


PATH_RE = re.compile(r"(?<![\w/.-])((?:[\w.-]+/)+[\w.-]+\.(?:md|ya?ml|json|py|cls))")


def check_rationale(where, text, root, allow_missing_root):
    """Rule 5. Every path-looking token in a rationale must resolve."""
    if not text or not str(text).strip():
        return
    for path in PATH_RE.findall(str(text)):
        if os.path.exists(os.path.join(ROOT, path)):
            continue
        if root and os.path.exists(os.path.join(root, path)):
            continue
        if root is None:
            if not allow_missing_root:
                fail(where, "cannot verify cited path %r -- no ma-migrator working copy "
                            "found. Set MA_MIGRATOR_ROOT, or pass "
                            "--allow-missing-source-root to skip." % path)
            continue
        fail(where, "cited path does not exist in this repo or in %s: %r" % (root, path))


# ------------------------------------------------------------------ loading

def load_yaml(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def base_questions(offering_key):
    """One offering's base slot wording, from the committed GTM_Assessment_Question rows.

    Base wording is NOT duplicated into the YAML: it stays in custom metadata so
    a consultant can still reword a base question in Setup and deploy nothing.
    This build step reads those rows so the option-shape rule (2) covers them
    too -- otherwise the one option set nobody authored in YAML is the one
    nobody validates.

    These rows are hand-authored per offering (this script only ever READS
    them; it does not own GTM_Assessment_Question__mdt and does not write it --
    see ADR-0007's second open call). The Offering_Key__c filter is what keeps
    one offering's frame from being validated against, or accidentally
    satisfied by, another offering's question rows: a row with no
    Offering_Key__c belongs to no offering and is deliberately invisible here,
    which surfaces as "slot X has no GTM_Assessment_Question row behind it"
    rather than as a silent cross-offering match.
    """
    out = {}
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
        key = (vals.get("Dimension_Key__c") or "").strip()
        if key:
            vals["__file"] = name
            out[key] = vals
    return out


# --------------------------------------------------------------- validation

def check_options(where, options, expect_max=4, required=True, allow_points=True):
    """Rules 2 and 10. Exactly N options, values 1..N, no gaps, no duplicates --
    and, where the author has set them, points that bottom out at 1, top out at
    N and never descend.

    Rule 10 is what keeps author-set scores from quietly breaking comparability.
    An author is allowed to say "these two middle answers are equally bad"
    (points 1/1/3/4); they are not allowed to say "the best answer here is worth
    3", because that is an instrument scored out of 31 wearing bands calibrated
    against 32. Non-descending is the other half: options render in ascending
    order and a respondent reads them as a scale, so an option that is worth
    less than the one above it is a scale that lies about itself.
    """
    if options is None:
        if required:
            fail(where, "no options declared")
        return
    if not isinstance(options, list):
        fail(where, "options must be a list")
        return
    values = []
    for o in options:
        if not isinstance(o, dict) or "value" not in o:
            fail(where, "option is not a {value, label} mapping: %r" % (o,))
            return
        if not str(o.get("label") or "").strip():
            fail(where, "option %r has no label" % o.get("value"))
        if "points" in o and not allow_points:
            fail(where, "option %r declares points, which only the scored 8-slot "
                        "frame supports -- a supplement index is derived from its "
                        "option count and must stay linear" % o.get("value"))
        values.append(o["value"])
    if sorted(values) != list(range(1, expect_max + 1)):
        fail(where, "option values are %r; expected exactly %r "
                    "(gaps and duplicates silently renumber every stored answer)"
             % (sorted(values), list(range(1, expect_max + 1))))
        return
    if not allow_points:
        return
    ordered = sorted(options, key=lambda o: o["value"])
    points = [option_points(o) for o in ordered]
    if any(not isinstance(p, int) or isinstance(p, bool) for p in points):
        fail(where, "option points are %r; every one must be a whole number" % (points,))
        return
    if min(points) != 1 or max(points) != expect_max:
        fail(where, "option points are %r, worth %d..%d; every slot must be worth "
                    "exactly 1..%d. Points make a scale non-linear, not longer or "
                    "shorter -- the band edges were calibrated against a %d-point "
                    "maximum and an instrument scored out of anything else is not "
                    "comparable to one scored out of that."
             % (points, min(points), max(points), expect_max, expect_max * 8))
    if any(b < a for a, b in zip(points, points[1:])):
        fail(where, "option points %r descend. Options render ascending and a "
                    "respondent reads them as a scale; an option worth less than "
                    "the one above it is a scale that lies about itself." % (points,))


# Rule 13. Every field whose value a PROSPECT reads. Rationales are excluded on
# purpose: they are authoring provenance, read by consultants and by the build,
# and holding them to prose typography would be busywork. Where the reader is a
# client, the dash is a dash.
def check_typography(where, value, field):
    """Rule 13. `--` in prospect-facing copy."""
    if value is None:
        return
    if isinstance(value, (list, tuple)):
        for v in value:
            check_typography(where, v, field)
        return
    if re.search(r"(?<=\s)--(?=\s|$)", str(value)):
        fail(where, "%s contains '--' where an em dash belongs. YAML-sourced copy "
                    "renders it literally, next to metadata-sourced copy that uses "
                    "a real dash, on the same screen." % field)


def check_respondent_hint(where, text):
    """A prospect-facing hint must be addressed TO the respondent.

    The fault this exists to prevent shipped for months: every readiness slot
    ended with an interviewer's note, written in the second person ABOUT the
    person reading it -- "Ask for five numbers, not an adjective", "Ask who logs
    into HubSpot who is not in marketing". They were authored as consultant
    guidance and nobody checked where they surfaced, which was the guest form.
    Evidence_Prompt__c is now consultant-only and unreachable from Lightning;
    this is its prospect-facing counterpart, and this check is the guard that
    stops the two being confused again by an author copying one into the other.
    """
    if not text:
        return
    body = " ".join(str(text).split())
    if re.match(r"(?i)^ask\b", body):
        fail(where, "respondent_hint starts with 'Ask' -- that is an instruction to "
                    "an interviewer, not a hint for the person filling the form in. "
                    "It belongs in evidence_prompt.")
    for phrase in ("ask them", "ask him", "ask her", "ask the client",
                   "ask the prospect", "ask for", "ask who", "ask whether"):
        if phrase in body.lower():
            fail(where, "respondent_hint contains %r, which addresses an interviewer "
                        "rather than the respondent. It belongs in evidence_prompt."
                 % phrase)


def option_points(option):
    """What one option is worth. Absent `points` means "worth its value", which
    is what every option was worth before points became authorable."""
    return option.get("points", option.get("value"))


def top_points(options, fallback=4):
    """The most a slot can be worth. Ceilings are deliberately ignored: a
    ceiling is a handicap on a hostile pair, not a smaller instrument."""
    if not options:
        return fallback
    return max(option_points(o) for o in options)


def eval_predicate(node, ctx):
    """A Python mirror of GtmPredicate.matches, used only to prove reachability
    (rule 11) at build time. It must agree with the Apex; the shared jest module
    force-app/main/default/lwc/gtmPredicate is the third implementation and the
    three are pinned to each other by GtmPredicateTest and gtmPredicate's own
    tests. A field with no value makes its clause false, here as there."""
    if not isinstance(node, dict):
        return False
    if "all" in node:
        return all(eval_predicate(c, ctx) for c in (node.get("all") or []))
    if "any" in node:
        return any(eval_predicate(c, ctx) for c in (node.get("any") or []))
    actual = ctx.get(node.get("field"))
    if actual is None:
        return False
    op, expected = node.get("op"), node.get("value")
    if op in ("in", "not_in"):
        found = any(_equalish(actual, c) for c in (expected or []))
        return found if op == "in" else not found
    if op == "eq":
        return _equalish(actual, expected)
    if op == "ne":
        return not _equalish(actual, expected)
    a, b = _as_number(actual), _as_number(expected)
    if a is None or b is None:
        return False
    return {"lt": a < b, "lte": a <= b, "gt": a > b, "gte": a >= b}.get(op, False)


def _as_number(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return v
    return None


def _equalish(a, b):
    na, nb = _as_number(a), _as_number(b)
    if na is not None and nb is not None:
        return na == nb
    return a is not None and b is not None and str(a).strip().lower() == str(b).strip().lower()


def collect_predicate_fields(node, where, out):
    """Walk a gate predicate, collecting referenced field names."""
    if isinstance(node, dict) and ("all" in node or "any" in node):
        for k in ("all", "any"):
            if k in node:
                if not isinstance(node[k], list):
                    fail(where, "%r must be a list of clauses" % k)
                    continue
                for child in node[k]:
                    collect_predicate_fields(child, where, out)
        return
    if not isinstance(node, dict) or "field" not in node:
        fail(where, "predicate clause is neither a group nor a {field, op, value}: %r" % (node,))
        return
    if node.get("op") not in OPS:
        fail(where, "unknown operator %r (allowed: %s)" % (node.get("op"), ", ".join(OPS)))
    if node.get("op") in ("in", "not_in") and not isinstance(node.get("value"), list):
        fail(where, "operator %r needs a list value" % node.get("op"))
    out.add(node["field"])


# ------------------------------------------------------------------ writing

def esc(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;"))


def value_block(field, value):
    if value is None or (isinstance(value, str) and not value.strip()):
        return ("    <values>\n        <field>%s</field>\n"
                "        <value xsi:nil=\"true\"/>\n    </values>\n" % field)
    if isinstance(value, bool):
        return ("    <values>\n        <field>%s</field>\n"
                "        <value xsi:type=\"xsd:boolean\">%s</value>\n    </values>\n"
                % (field, "true" if value else "false"))
    if isinstance(value, (int, float)):
        return ("    <values>\n        <field>%s</field>\n"
                "        <value xsi:type=\"xsd:double\">%s</value>\n    </values>\n"
                % (field, float(value)))
    return ("    <values>\n        <field>%s</field>\n"
            "        <value xsi:type=\"xsd:string\">%s</value>\n    </values>\n"
            % (field, esc(value)))


HEADER = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          "<!-- GENERATED by scripts/build-instrument.py from "
          "instrument/. Do not hand-edit: the next build "
          "overwrites it, and the YAML is the reviewable artifact. -->\n"
          "<CustomMetadata xmlns=\"http://soap.sforce.com/2006/04/metadata\" "
          "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
          # Every value_block() below emits xsi:type="xsd:string" /
          # "xsd:boolean" / "xsd:double" -- an xsi:type QName whose prefix
          # must resolve, which means the xsd: prefix has to be declared
          # here too, not just xsi:. Without it the file still parses as
          # well-formed XML (a naive parser never resolves the QName inside
          # an attribute VALUE), so this shipped for a long time looking
          # fine locally -- but Salesforce's Metadata API deploy pipeline
          # DOES resolve it, and an unresolvable prefix there is fatal.
          # Confirmed against gtm-dev: every customMetadata record missing
          # this declaration made ITS OWN deploy fail, individually or in
          # any batch, with a generic UNKNOWN_EXCEPTION carrying no field,
          # type or record name -- indistinguishable from a platform bug
          # until isolated one record at a time down to this.
          "xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n")


def safe_dev_name(name, max_len=40):
    """A CustomMetadata DeveloperName never exceeds Salesforce's 40-char limit.

    Dimension-override and supplement record names are built by
    concatenating a pair/set key with a dimension/question key, and several
    of those pairings are naturally longer than 40 characters -- confirmed
    against gtm-dev: Salesforce rejects the deploy with "Value too long for
    field: fullName maximum length is:40" per record, not a build-time
    warning, so this was never caught until the first real deploy.
    DeveloperName is a stable identifier only here (Apex resolves these
    records by their Pair__c / Dimension__c / Set_Key__c / Key__c fields,
    never by DeveloperName -- confirmed by grep), so truncating it is safe
    as long as it stays deterministic and collision-free. Deterministic
    truncation with a short content hash suffix gives both: a name over the
    limit keeps its first characters (still recognisable in Setup) and gets
    a 6-hex-char suffix derived from the full, untruncated name, so two
    different overlong names never collapse onto the same short one.
    """
    if len(name) <= max_len:
        return name
    digest = hashlib.sha1(name.encode("utf-8")).hexdigest()[:6]
    keep = max_len - 1 - len(digest)  # 1 for the separating underscore
    return "%s_%s" % (name[:keep].rstrip("_"), digest)


def record(label, fields):
    body = HEADER + "    <label>%s</label>\n    <protected>false</protected>\n" % esc(label)
    for f, v in fields:
        body += value_block(f, v)
    return body + "</CustomMetadata>\n"


def developer_name(where, name):
    if not re.match(r"^[A-Za-z][A-Za-z0-9_]*$", name) or name.endswith("_"):
        fail(where, "%r is not a usable DeveloperName" % name)
    if "__" in name:
        # Salesforce documents DeveloperName as disallowing two consecutive
        # underscores. This warning used to say the spelling "matches the
        # existing GTM_Migration_Pair naming", which read as reassurance and was
        # not: those six records were written in the same commit as these, into
        # a repo nothing has ever been deployed from. There is no precedent, in
        # either direction, and the first deploy is the first test.
        #
        # Still a warning rather than a failure, because the rule may well not
        # be enforced on custom metadata records and failing the build on an
        # unverified rule would be its own kind of wrong. The remedy is one
        # command, and it is named here so that whoever meets a rejected deploy
        # does not have to go looking for it.
        warn(where, "%r contains two consecutive underscores, which Salesforce "
                    "documents as illegal in a DeveloperName. UNVERIFIED: "
                    "nothing in this repo has been deployed to a real org, and "
                    "the GTM_Migration_Pair records with the same spelling were "
                    "written in the same unverified batch. If a deploy rejects "
                    "these, run scripts/rename-pair-keys.py --apply then rebuild "
                    "(see docs/runbooks/fresh-org-deploy.md section 9)." % name)


# ---------------------------------------------------------------------- main

def build_offering(offering_key, idir, args, root, out, owner):
    """Validate ONE offering directory and emit its records into `out`.

    Every one of the 14 rules runs inside this call, over this directory's YAML
    and this offering's GTM_Assessment_Question rows only. Nothing here can see
    another offering's content, which is the point: a second offering's
    instrument has to hold together on its own terms rather than borrowing
    Migration Accelerator's shape or being validated against it.

    `out` and `owner` are shared across offerings only so that two offerings
    emitting the same record filename is caught (see the emit section) rather
    than one silently overwriting the other -- a real hazard, since a
    CustomMetadata DeveloperName is unique org-wide, not per-offering.
    """
    global _offering_prefix
    _offering_prefix = "%s/" % offering_key
    before = len(errors)

    frame = load_yaml(os.path.join(idir, "dimensions.yaml"))
    slots = frame.get("slots") or []
    if len(slots) != 8:
        fail("dimensions.yaml", "the frame declares %d slots; it must declare 8" % len(slots))
    by_key = {s["key"]: s for s in slots}
    positions = sorted(s["position"] for s in slots)
    if positions != list(range(1, 9)):
        fail("dimensions.yaml", "slot positions are %r; expected 1-8" % positions)

    # ---- the second frame. Same shape, same reasons -- see complexity.yaml.
    cframe = load_yaml(os.path.join(idir, "complexity.yaml"))
    cdims = cframe.get("dimensions") or []
    if len(cdims) != COMPLEXITY_DIMENSION_COUNT:
        fail("complexity.yaml", "the frame declares %d dimensions; it must declare %d"
             % (len(cdims), COMPLEXITY_DIMENSION_COUNT))
    cby_key = {d["key"]: d for d in cdims}
    cpositions = sorted(d["position"] for d in cdims)
    if cpositions != list(range(1, COMPLEXITY_DIMENSION_COUNT + 1)):
        fail("complexity.yaml", "dimension positions are %r; expected 1-%d"
             % (cpositions, COMPLEXITY_DIMENSION_COUNT))
    # The band edges are GtmEstateComplexity's, not this file's. Checked rather
    # than imported because a YAML that quietly disagreed with the scorer would
    # print one band and store another.
    declared_bands = [(b.get("band"), b.get("min"), b.get("max"))
                      for b in (cframe.get("bands") or [])]
    if declared_bands != [list(b) and tuple(b) for b in COMPLEXITY_BANDS]:
        fail("complexity.yaml", "bands are %r; GtmEstateComplexity scores %r"
             % (declared_bands, [list(b) for b in COMPLEXITY_BANDS]))
    apex = os.path.join(ROOT, APEX_COMPLEXITY)
    if os.path.exists(apex):
        body = open(apex, encoding="utf-8").read()
        for name, hi in (("LIGHT_MAX", COMPLEXITY_BANDS[0][2]),
                         ("MODERATE_MAX", COMPLEXITY_BANDS[1][2])):
            if not re.search(r"%s\s*=\s*%d\b" % (name, hi), body):
                fail("complexity.yaml", "declares %s at %d, which %s does not"
                     % (name, hi, APEX_COMPLEXITY))
        if not re.search(r"MAX_ANSWER_VALUE\s*=\s*%d\b" % COMPLEXITY_MAX_ANSWER, body):
            fail("complexity.yaml", "the complexity scale is 1-%d here and something "
                                    "else in %s" % (COMPLEXITY_MAX_ANSWER, APEX_COMPLEXITY))
    check_rationale("complexity.yaml", cframe.get("rationale"), root,
                    args.allow_missing_source_root)

    questions = base_questions(offering_key)
    readiness_keys = {k for k, v in questions.items() if v.get("Instrument__c") == "Readiness"}
    complexity_keys = {k for k, v in questions.items() if v.get("Instrument__c") == "Complexity"}

    # The complexity frame and the base complexity wording must name the same six.
    for k in cby_key:
        if k not in complexity_keys:
            fail("complexity.yaml", "dimension %r has no GTM_Assessment_Question row "
                                    "behind it" % k)
    for k in complexity_keys - set(cby_key):
        fail("GTM_Assessment_Question", "complexity row %r is not a dimension in the "
                                       "frame" % k)

    # The frame and the base wording must name the same eight things.
    for k in by_key:
        if k not in readiness_keys:
            fail("dimensions.yaml", "slot %r has no GTM_Assessment_Question row behind it" % k)
    for k in readiness_keys - set(by_key):
        fail("GTM_Assessment_Question", "readiness row %r is not a slot in the frame" % k)

    # Rule 2 over the base wording, which lives in metadata rather than YAML.
    for k in sorted(readiness_keys):
        q = questions[k]
        labels = [q.get("Option_%d_Label__c" % i) for i in range(1, 5)]
        opts = [{"value": i + 1, "label": labels[i]} for i in range(4)]
        check_options("base question %s" % k, opts)
        if str(q.get("Max_Answer_Value__c") or "") not in ("4.0", "4"):
            fail("base question %s" % k,
                 "Max_Answer_Value__c is %r; the readiness scale is 1-4"
                 % q.get("Max_Answer_Value__c"))

    # The same over the base complexity wording, which nothing validated before
    # the second axis became adaptive: it was the one option set in the whole
    # instrument that no rule looked at.
    for k in sorted(complexity_keys):
        q = questions[k]
        labels = [q.get("Option_%d_Label__c" % i) for i in range(1, COMPLEXITY_MAX_ANSWER + 1)]
        opts = [{"value": i + 1, "label": labels[i]} for i in range(COMPLEXITY_MAX_ANSWER)]
        check_options("base complexity question %s" % k, opts,
                      expect_max=COMPLEXITY_MAX_ANSWER, allow_points=False)
        if str(q.get("Max_Answer_Value__c") or "") not in ("3.0", "3"):
            fail("base complexity question %s" % k,
                 "Max_Answer_Value__c is %r; the complexity scale is 1-%d"
                 % (q.get("Max_Answer_Value__c"), COMPLEXITY_MAX_ANSWER))
        if q.get("Option_4_Label__c"):
            fail("base complexity question %s" % k,
                 "declares a fourth option; the complexity scale is 1-%d and a "
                 "fourth answer would be collected and never scored"
                 % COMPLEXITY_MAX_ANSWER)

    # ---- supplements
    supp_dir = os.path.join(idir, "supplements")
    sets = {}
    supplement_keys = set()
    for name in sorted(os.listdir(supp_dir)) if os.path.isdir(supp_dir) else []:
        if not name.endswith((".yaml", ".yml")):
            continue
        doc = load_yaml(os.path.join(supp_dir, name))
        set_key = doc.get("set_key")
        where = "supplements/%s" % name
        if not set_key:
            fail(where, "no set_key")
            continue
        sets[set_key] = doc
        for q in doc.get("questions") or []:
            qwhere = "%s[%s]" % (where, q.get("key"))
            key = q.get("key")
            if not key:
                fail(qwhere, "no key")
                continue
            # Rule 6. A supplement that lands on a dimension key would quietly
            # enter the 32 -- the one thing layer 4 exists not to do.
            if key in readiness_keys or key in complexity_keys:
                fail(qwhere, "supplement key %r collides with a scored dimension key" % key)
            supplement_keys.add(key)
            if q.get("scored"):
                check_options(qwhere, q.get("options"), expect_max=3, allow_points=False)
                if not doc.get("index_key"):
                    fail(where, "has scored questions but declares no index_key")
            elif q.get("options"):
                fail(qwhere, "unscored probe declares options; drop them or mark it scored")
            check_rationale(qwhere, q.get("rationale"), root, args.allow_missing_source_root)
            check_typography(qwhere, q.get("question"), "question")
            check_typography(qwhere, [o.get("label") for o in (q.get("options") or [])],
                             "an option label")

    # ---- pairs
    pairs = {}
    pair_dir = os.path.join(idir, "pairs")
    # An offering may legitimately have no pairs/ at all -- it then resolves
    # to the base frame with no adaptive layer, which is exactly what
    # ADR-0007 section 2 means by "branching is offering-specific".
    for name in sorted(os.listdir(pair_dir)) if os.path.isdir(pair_dir) else []:
        if not name.endswith((".yaml", ".yml")):
            continue
        doc = load_yaml(os.path.join(pair_dir, name))
        where = "pairs/%s" % name
        pname = doc.get("name")
        if not pname:
            fail(where, "no name")
            continue
        developer_name(where, pname)
        pairs[pname] = (where, doc)

        src, tgt = doc.get("source"), doc.get("target")
        expected = 4 if (src == ANY and tgt == ANY) else 3 if src == ANY else 1
        # Family packs are declared by naming a Family_Key__c on the source side;
        # the YAML says so explicitly so the script need not read platform rows.
        if doc.get("source_is_family"):
            expected = 2
        if doc.get("specificity") != expected:
            fail(where, "specificity is %r but the keys (%r -> %r) make it %d"
                 % (doc.get("specificity"), src, tgt, expected))

        # Posture: the headline is always the weaker end. Anything else
        # overstates one of the two, and the weaker end is the one that costs
        # money when it is wrong.
        sp, tp, hp = doc.get("source_posture"), doc.get("target_posture"), doc.get("capability_posture")
        for label, v in (("source_posture", sp), ("target_posture", tp), ("capability_posture", hp)):
            if v not in POSTURE_RANK:
                fail(where, "%s is %r; expected one of %s" % (label, v, ", ".join(POSTURE_RANK)))
        if sp in POSTURE_RANK and tp in POSTURE_RANK and hp in POSTURE_RANK:
            weakest = sp if POSTURE_RANK[sp] <= POSTURE_RANK[tp] else tp
            if hp != weakest:
                fail(where, "capability_posture %r is not the weaker of %r and %r (%r)"
                     % (hp, sp, tp, weakest))
        if not str(doc.get("posture_statement") or "").strip():
            fail(where, "no posture_statement -- the above-the-fold sentence is not optional")
        for s in doc.get("supplement_sets") or []:
            if s not in sets:
                fail(where, "declares unknown supplement set %r" % s)
        check_rationale(where, doc.get("rationale"), root, args.allow_missing_source_root)

        for c in doc.get("callouts") or []:
            cwhere = "%s callout[%s]" % (where, c.get("pattern"))
            if not c.get("pattern"):
                fail(cwhere, "callout has no pattern")
            if c.get("status") not in (None, "supported", "partial", "unsupported"):
                fail(cwhere, "status %r is outside the capability schema enum" % c.get("status"))
            if c.get("severity") not in (None, "blocker", "major", "minor"):
                fail(cwhere, "severity %r is outside the capability schema enum" % c.get("severity"))
            check_rationale(cwhere, c.get("rationale"), root, args.allow_missing_source_root)

        by_dimension = {}
        for o in doc.get("overrides") or []:
            owhere = "%s override[%s]" % (where, o.get("dimension"))
            dim = o.get("dimension")
            if dim not in by_key:
                fail(owhere, "overrides %r, which is not a slot in the frame" % dim)
                continue
            by_dimension.setdefault(dim, []).append(o)

            # ---- Rule 8. A branch predicate may look BACKWARDS only.
            sw = o.get("show_when")
            if sw is not None:
                owhere = "%s override[%s/%s]" % (where, dim, o.get("variant_key") or "?")
                if not str(o.get("variant_key") or "").strip():
                    fail(owhere, "a branch variant needs a variant_key -- it is what "
                                 "Instrument_Branch_Path__c records, and a readout "
                                 "that cannot name the question it asked cannot "
                                 "explain itself a year later")
                refs = set()
                collect_predicate_fields(sw, owhere, refs)
                position = by_key[dim]["position"]
                earlier = {k for k, v in by_key.items() if v["position"] < position}
                for f in sorted(refs - ({"source", "target"} | earlier)):
                    if f in by_key:
                        fail(owhere, "show_when references %r, which is at position %d -- "
                                     "at or after this slot's own position %d. A branch may "
                                     "only depend on answers already given, or the "
                                     "questionnaire and the server can disagree about which "
                                     "question was asked."
                             % (f, by_key[f]["position"], position))
                    else:
                        fail(owhere, "show_when references %r, which is neither source, "
                                     "target, nor a slot before position %d. A predicate "
                                     "keyed on a name nothing supplies never matches, and "
                                     "never matching looks exactly like a branch that is "
                                     "simply not needed yet." % (f, position))
            if o.get("layer") not in LAYERS:
                fail(owhere, "layer %r is not one of %s" % (o.get("layer"), ", ".join(LAYERS)))
            # Rule 3.
            if o.get("layer") == "substitute":
                if not by_key[dim].get("substitutable"):
                    fail(owhere, "slot %r (position %d) is pinned and cannot be substituted -- "
                                 "the invariant spine is what keeps two prospects' totals "
                                 "describing the same eight things"
                         % (dim, by_key[dim]["position"]))
                if not str(o.get("rationale") or "").strip():
                    fail(owhere, "substitution has no rationale; it is the one edit that must "
                                 "justify itself in writing")
                if not o.get("new_key"):
                    fail(owhere, "substitution declares no new_key")
                if o.get("new_key") in readiness_keys and o.get("new_key") != dim:
                    fail(owhere, "new_key %r is already a base dimension key" % o.get("new_key"))
            elif o.get("new_key"):
                fail(owhere, "new_key is only meaningful for layer substitute")
            if o.get("options") is not None:
                check_options(owhere, o.get("options"))
            # Rule 4.
            cap = o.get("max_attainable")
            if cap is not None:
                if not isinstance(cap, int) or not 1 <= cap <= 4:
                    fail(owhere, "max_attainable %r is not 1-4" % cap)
                if not str(o.get("ceiling_reason") or "").strip():
                    fail(owhere, "max_attainable with no ceiling_reason -- a ceiling with no "
                                 "stated reason is indistinguishable from a rigged scale")
                if cap < 4 and o.get("options") is None:
                    fail(owhere, "max_attainable %d inherits its options, so the excluded "
                                 "option has no label to render greyed. Declare all four."
                         % cap)
            check_rationale(owhere, o.get("rationale"), root, args.allow_missing_source_root)
            check_respondent_hint(owhere, o.get("respondent_hint"))
            check_typography(owhere, o.get("question"), "question")
            check_typography(owhere, o.get("label"), "label")
            check_typography(owhere, o.get("respondent_hint"), "respondent_hint")
            check_typography(owhere, o.get("ceiling_reason"), "ceiling_reason")
            check_typography(owhere, [x.get("label") for x in (o.get("options") or [])],
                             "an option label")

        # ---- Rule 12. The second axis, held to the same standard.
        seen_cdims = set()
        for o in doc.get("complexity_overrides") or []:
            cwhere = "%s complexity[%s]" % (where, o.get("dimension"))
            dim = o.get("dimension")
            if dim not in cby_key:
                fail(cwhere, "overrides %r, which is not a dimension in the complexity "
                             "frame" % dim)
                continue
            if dim in seen_cdims:
                fail(cwhere, "declares two rows for one complexity dimension; whichever "
                             "the loop applied last would silently win")
            seen_cdims.add(dim)
            if o.get("show_when") is not None:
                fail(cwhere, "declares show_when. Complexity does not branch: it is a "
                             "size estimate re-measured post-scan against the same six "
                             "keys, and a dimension that changed with an earlier answer "
                             "could not be recomputed from an extract.")
            if o.get("max_attainable") is not None or o.get("ceiling_reason"):
                fail(cwhere, "declares a ceiling. A ceiling says a top answer is not "
                             "available on this move; a complexity option is a fact "
                             "about the client's own estate, so capping one is the "
                             "instrument refusing to hear a number.")
            if o.get("layer") not in LAYERS:
                fail(cwhere, "layer %r is not one of %s" % (o.get("layer"), ", ".join(LAYERS)))
            if o.get("layer") == "substitute":
                if not cby_key[dim].get("substitutable"):
                    fail(cwhere, "dimension %r is pinned and cannot be substituted" % dim)
                if not str(o.get("rationale") or "").strip():
                    fail(cwhere, "substitution has no rationale")
                if not o.get("new_key"):
                    fail(cwhere, "substitution declares no new_key")
                if o.get("new_key") in complexity_keys and o.get("new_key") != dim:
                    fail(cwhere, "new_key %r is already a base complexity key" % o.get("new_key"))
            elif o.get("new_key"):
                fail(cwhere, "new_key is only meaningful for layer substitute")
            if o.get("options") is not None:
                check_options(cwhere, o.get("options"),
                              expect_max=COMPLEXITY_MAX_ANSWER, allow_points=False)
            if not str(o.get("question") or "").strip():
                fail(cwhere, "no question. A complexity override with no question would "
                             "inherit the base wording, which is the target's vocabulary "
                             "asked of a source estate -- the fault this layer exists to "
                             "fix.")
            check_rationale(cwhere, o.get("rationale"), root, args.allow_missing_source_root)
            check_respondent_hint(cwhere, o.get("respondent_hint"))
            for field in ("question", "label", "measures", "respondent_hint"):
                check_typography(cwhere, o.get(field), field)
            check_typography(cwhere, [x.get("label") for x in (o.get("options") or [])],
                             "an option label")

        check_typography(where, doc.get("posture_statement"), "posture_statement")
        for c in doc.get("callouts") or []:
            for field in ("issue", "gloss", "workaround"):
                check_typography("%s callout[%s]" % (where, c.get("pattern")),
                                 c.get(field), field)
            check_typography("%s callout[%s]" % (where, c.get("pattern")),
                             c.get("manual_steps"), "a manual step")

        # ---- Rule 9. One default per slot, uniquely-named variants.
        for dim, rows in sorted(by_dimension.items()):
            defaults = [r for r in rows if r.get("show_when") is None]
            variants = [r for r in rows if r.get("show_when") is not None]
            dwhere = "%s override[%s]" % (where, dim)
            if len(defaults) > 1:
                fail(dwhere, "declares %d unconditional rows for one slot. Exactly one "
                             "question is the slot's default; two of them means whichever "
                             "the loop applied last silently wins." % len(defaults))
            keys = [str(v.get("variant_key") or "").strip() for v in variants]
            for k in sorted({k for k in keys if keys.count(k) > 1 and k}):
                fail(dwhere, "two branch variants share variant_key %r; the branch path "
                             "recorded on the request would be ambiguous" % k)
            if len(variants) > 1 and any(v.get("variant_order") is None for v in variants):
                fail(dwhere, "%d branch variants and at least one without a variant_order. "
                             "Two predicates can both be true, and 'whichever row the query "
                             "returned first' is not an answer an author can reason about."
                     % len(variants))
            orders = [v.get("variant_order") for v in variants if v.get("variant_order") is not None]
            if len(set(orders)) != len(orders):
                fail(dwhere, "two branch variants share a variant_order; evaluation order "
                             "would depend on the query, not on the author")

    # ---- Rules 1, 10 and 11: resolve every pair and walk every branch path.
    #
    # Rule 1 was always "does this pair resolve to eight slots". Branching turns
    # that into "does this pair resolve to eight slots ON EVERY PATH", which is
    # the whole hazard branching introduces: two respondents who answered
    # different numbers of questions produce totals that are not comparable. The
    # design makes that impossible by construction -- a variant SUBSTITUTES for
    # the slot's default rather than adding to or removing from the eight -- and
    # this is where that construction is checked rather than assumed.
    resolved_keys = {}
    base_option_sets = {}
    for k in readiness_keys:
        q = questions[k]
        base_option_sets[k] = [
            {"value": i + 1, "label": q.get("Option_%d_Label__c" % (i + 1))} for i in range(4)
        ]

    for pname, (where, doc) in sorted(pairs.items()):
        chain = resolution_chain(pairs, doc)
        merged = {}
        for sl in slots:
            merged[sl["key"]] = dict(
                sl,
                resolved_key=sl["key"],
                options=base_option_sets.get(sl["key"]) or [],
                variants=[],
            )
        for _, cdoc in chain:
            for o in cdoc.get("overrides") or []:
                slot = merged.get(o.get("dimension"))
                if slot is None:
                    continue
                if o.get("show_when") is not None:
                    slot["variants"].append(o)
                    continue
                if o.get("layer") == "substitute" and o.get("new_key"):
                    slot["resolved_key"] = o["new_key"]
                if o.get("max_attainable") is not None:
                    slot["max_attainable"] = o["max_attainable"]
                if o.get("options") is not None:
                    slot["options"] = o["options"]
        for slot in merged.values():
            slot["variants"].sort(key=lambda v: (v.get("variant_order") is None,
                                                 v.get("variant_order") or 0))

        ordered = [merged[sl["key"]] for sl in sorted(slots, key=lambda x: x["position"])]
        keys = [sl["resolved_key"] for sl in ordered]
        if len(keys) != 8 or len(set(keys)) != 8:
            fail(where, "resolves to %d slots (%d distinct); the frame is 8, and a pair that "
                        "resolves to fewer still prints 'out of 32'" % (len(keys), len(set(keys))))

        # Rule 11a: no two slots may ever resolve to the same key, on any path.
        # Two slots sharing a storage key is two answers overwriting each other,
        # and the total is then out of 32 while only seven questions counted.
        possible = {}
        for sl in ordered:
            here = {sl["resolved_key"]}
            for v in sl["variants"]:
                here.add(v.get("new_key") or sl["resolved_key"])
            possible[sl["key"]] = here
        for a in ordered:
            for b in ordered:
                if a["key"] >= b["key"]:
                    continue
                shared = possible[a["key"]] & possible[b["key"]]
                if shared:
                    fail(where, "slots %r (position %d) and %r (position %d) can both resolve "
                                "to %s. Two slots sharing a key is two answers landing in one "
                                "storage slot: the total still prints out of 32 while only "
                                "seven questions counted."
                         % (a["key"], a["position"], b["key"], b["position"],
                            ", ".join(sorted(shared))))

        # Rule 10 (per path) and rule 11b (every variant reachable).
        for sl in ordered:
            path_max = top_points(sl["options"])
            if path_max != 4:
                fail(where, "slot %r tops out at %d point(s) on its default path; every slot "
                            "must be worth 1-4 or the pair is scored out of something other "
                            "than 32" % (sl["key"], path_max))
            for v in sl["variants"]:
                vmax = top_points(v.get("options") if v.get("options") is not None
                                  else sl["options"])
                if vmax != 4:
                    fail(where, "branch variant %r of slot %r tops out at %d point(s). A "
                                "branch chooses WHICH question fills a slot; it may not "
                                "change what the slot is worth, or two respondents' totals "
                                "stop being out of the same number."
                         % (v.get("variant_key"), sl["key"], vmax))
            check_variant_reachability(where, sl, ordered, doc)

        resolved_keys[pname] = set(keys)
        for e in doc.get("emphasis_slots") or []:
            if e not in resolved_keys[pname] and not any(
                e in possible[k] for k in possible
            ):
                fail(where, "emphasis_slots names %r, which is not a slot this pair resolves to" % e)

    all_slot_keys = set(by_key)
    for ks in resolved_keys.values():
        all_slot_keys |= ks

    # ---- Rule 12, resolved. Exactly six complexity dimensions for every pair,
    # and every authored complexity override reachable.
    #
    # Reachability here is not the branch problem rule 11 solves; it is the
    # SHADOWING problem. Complexity overrides merge down the same chain the
    # readiness ones do, so a row on a target-only pack whose every field is
    # replaced by an exact pair, on every pair that reaches it, is a question
    # nobody will ever be asked -- and it looks exactly like a question that
    # works, because the file it lives in is perfectly valid.
    complexity_fields = ("layer", "label", "question", "measures", "options",
                         "respondent_hint", "evidence_prompt", "new_key")
    contributed = set()
    for pname, (where, doc) in sorted(pairs.items()):
        chain = resolution_chain(pairs, doc)
        merged = {}
        for d in cdims:
            merged[d["key"]] = dict(d, resolved_key=d["key"], options=None, winners={})
        for _, cdoc in chain:
            for o in cdoc.get("complexity_overrides") or []:
                dim = merged.get(o.get("dimension"))
                if dim is None:
                    continue
                if o.get("layer") == "substitute" and o.get("new_key"):
                    dim["resolved_key"] = o["new_key"]
                if o.get("options") is not None:
                    dim["options"] = o["options"]
                for f in complexity_fields:
                    if o.get(f) is not None:
                        dim["winners"][f] = cdoc.get("name")
        ckeys = [merged[d["key"]]["resolved_key"]
                 for d in sorted(cdims, key=lambda x: x["position"])]
        if len(ckeys) != COMPLEXITY_DIMENSION_COUNT or len(set(ckeys)) != COMPLEXITY_DIMENSION_COUNT:
            fail(where, "resolves to %d complexity dimensions (%d distinct); the second "
                        "axis is %d, and a pair that resolves to fewer still prints "
                        "'out of %d'"
                 % (len(ckeys), len(set(ckeys)), COMPLEXITY_DIMENSION_COUNT,
                    COMPLEXITY_DIMENSION_COUNT * COMPLEXITY_MAX_ANSWER))
        for d in cdims:
            opts = merged[d["key"]]["options"]
            if opts is not None:
                check_options("%s complexity[%s] resolved" % (where, d["key"]), opts,
                              expect_max=COMPLEXITY_MAX_ANSWER, allow_points=False)
            for f, winner in merged[d["key"]]["winners"].items():
                contributed.add((winner, d["key"]))
    for pname, (where, doc) in sorted(pairs.items()):
        for o in doc.get("complexity_overrides") or []:
            if (pname, o.get("dimension")) not in contributed:
                fail(where, "complexity override for %r never reaches a respondent: on "
                            "every pair whose chain includes this pack, a more specific "
                            "pack replaces all of it. A shadowed question looks exactly "
                            "like a question that works." % o.get("dimension"))

    # ---- gates (rule 7)
    gates = load_yaml(os.path.join(idir, "gates.yaml")).get("gates") or []
    declared = {"source", "target"} | all_slot_keys | supplement_keys
    for g in gates:
        gwhere = "gates.yaml[%s]" % g.get("key")
        if not g.get("key"):
            fail(gwhere, "gate has no key")
        refs = set()
        collect_predicate_fields(g.get("predicate"), gwhere, refs)
        for f in sorted(refs - declared):
            fail(gwhere, "predicate references %r, which is declared nowhere in the "
                         "instrument. A gate keyed on a typo never fires, and never "
                         "firing looks exactly like not applying." % f)
        if not str(g.get("tier_qualifier") or "").strip():
            fail(gwhere, "no tier_qualifier")
        if not str(g.get("readout_block") or "").strip():
            fail(gwhere, "no readout_block")
        if g.get("severity") not in ("blocker", "major", "minor"):
            fail(gwhere, "severity %r is outside blocker/major/minor" % g.get("severity"))
        check_rationale(gwhere, g.get("rationale"), root, args.allow_missing_source_root)
        check_typography(gwhere, g.get("readout_block"), "readout_block")
        check_typography(gwhere, g.get("tier_qualifier"), "tier_qualifier")

    # A directory that failed validation emits nothing: the emit path below
    # assumes the rules held. Other offerings are still validated (the caller
    # reports every offering's failures at once, not just the first).
    if len(errors) > before:
        return

    # ---- emit
    def emit(name, body):
        """Register one record file, refusing a cross-offering name collision.

        A CustomMetadata DeveloperName is unique ORG-WIDE, not per offering, so
        two offerings that both author a pair called `base`, or a gate called
        `no_core_platform`, would otherwise have one silently overwrite the
        other -- and the loser's absence would look exactly like content nobody
        had written yet.
        """
        if name in out and owner.get(name) != offering_key:
            fail(name, "record name is already emitted by offering %r. A "
                       "CustomMetadata DeveloperName is unique org-wide, so two "
                       "offerings cannot both author it; give this one an "
                       "offering-distinct key." % owner.get(name))
            return
        out[name] = body
        owner[name] = offering_key

    for pname, (_, doc) in sorted(pairs.items()):
        emit("GTM_Assessment_Pair.%s.md-meta.xml" % pname, record(pname, [
            ("Offering_Key__c", offering_key),
            ("Source_Key__c", doc.get("source")),
            ("Target_Key__c", doc.get("target")),
            ("Specificity__c", doc.get("specificity")),
            ("Capability_Posture__c", doc.get("capability_posture")),
            ("Source_Posture__c", doc.get("source_posture")),
            ("Target_Posture__c", doc.get("target_posture")),
            ("Posture_Statement__c", squash(doc.get("posture_statement"))),
            ("Emphasis_Slots__c", ";".join(doc.get("emphasis_slots") or []) or None),
            ("Supplement_Set__c", ";".join(doc.get("supplement_sets") or []) or None),
            ("Callouts_JSON__c", callouts_json(doc.get("callouts"))),
            ("Version__c", doc.get("version")),
            ("Rationale__c", squash(doc.get("rationale"))),
            ("Active__c", bool(doc.get("active", True))),
        ]))
        for o in doc.get("overrides") or []:
            # A slot may now carry a default row AND several branch variants, so
            # the DeveloperName has to name the variant too. The default keeps
            # the name it has always had, which is what stops this change from
            # rewriting every already-deployed record.
            dev = "%s_%s" % (pname, o["dimension"])
            if o.get("show_when") is not None:
                dev = "%s_%s" % (dev, o.get("variant_key"))
            dev = safe_dev_name(dev)
            emit("GTM_Assessment_Dimension_Override.%s.md-meta.xml" % dev, record(dev, [
                ("Offering_Key__c", offering_key),
                ("Pair__c", pname),
                ("Instrument__c", INSTRUMENT_READINESS),
                ("Dimension__c", o["dimension"]),
                ("Layer__c", o.get("layer")),
                ("New_Key__c", o.get("new_key")),
                ("Label__c", o.get("label")),
                ("Question__c", squash(o.get("question"))),
                ("Options_JSON__c",
                 json.dumps(o["options"], separators=(",", ":")) if o.get("options") else None),
                ("Max_Attainable__c", o.get("max_attainable")),
                ("Measures__c", squash(o.get("measures"))),
                ("Ceiling_Reason__c", squash(o.get("ceiling_reason"))),
                ("Evidence_Prompt__c", squash(o.get("evidence_prompt"))),
                ("Respondent_Hint__c", squash(o.get("respondent_hint"))),
                ("Show_When_JSON__c",
                 json.dumps(o["show_when"], separators=(",", ":"))
                 if o.get("show_when") is not None else None),
                ("Variant_Key__c", o.get("variant_key")),
                ("Variant_Order__c", o.get("variant_order")),
                ("Rationale__c", squash(o.get("rationale"))),
                ("Active__c", bool(o.get("active", True))),
            ]))
        # Complexity overrides share the table, distinguished by Instrument__c
        # rather than by a second custom metadata type. One merge path in
        # GtmAssessmentInstrument, one authoring shape, one set of rules --
        # a parallel object would have been a second thing to keep in step.
        for o in doc.get("complexity_overrides") or []:
            dev = safe_dev_name("%s_complexity_%s" % (pname, o["dimension"]))
            emit("GTM_Assessment_Dimension_Override.%s.md-meta.xml" % dev, record(dev, [
                ("Offering_Key__c", offering_key),
                ("Pair__c", pname),
                ("Instrument__c", INSTRUMENT_COMPLEXITY),
                ("Dimension__c", o["dimension"]),
                ("Layer__c", o.get("layer")),
                ("New_Key__c", o.get("new_key")),
                ("Label__c", o.get("label")),
                ("Question__c", squash(o.get("question"))),
                ("Measures__c", squash(o.get("measures"))),
                ("Options_JSON__c",
                 json.dumps(o["options"], separators=(",", ":")) if o.get("options") else None),
                ("Evidence_Prompt__c", squash(o.get("evidence_prompt"))),
                ("Respondent_Hint__c", squash(o.get("respondent_hint"))),
                ("Rationale__c", squash(o.get("rationale"))),
                ("Active__c", bool(o.get("active", True))),
            ]))
    for set_key, doc in sorted(sets.items()):
        for q in doc.get("questions") or []:
            dev = safe_dev_name("%s_%s" % (set_key, q["key"]))
            emit("GTM_Assessment_Supplement.%s.md-meta.xml" % dev, record(dev, [
                ("Offering_Key__c", offering_key),
                ("Set_Key__c", set_key),
                ("Sort_Order__c", q.get("sort_order")),
                ("Key__c", q["key"]),
                ("Question__c", squash(q.get("question"))),
                ("Options_JSON__c",
                 json.dumps(q["options"], separators=(",", ":")) if q.get("options") else None),
                ("Scored__c", bool(q.get("scored"))),
                ("Index_Key__c", doc.get("index_key") if q.get("scored") else None),
                ("Horizon_Driver__c", bool(q.get("horizon_driver"))),
                ("Rationale__c", squash(q.get("rationale"))),
                ("Active__c", bool(q.get("active", True))),
            ]))
    for g in gates:
        emit("GTM_Assessment_Gate.%s.md-meta.xml" % g["key"], record(g["key"], [
            ("Offering_Key__c", offering_key),
            ("Key__c", g["key"]),
            ("Predicate_JSON__c", json.dumps(g.get("predicate"), separators=(",", ":"))),
            ("Tier_Qualifier__c", squash(g.get("tier_qualifier"))),
            ("Readout_Block__c", squash(g.get("readout_block"))),
            ("Severity__c", g.get("severity")),
            ("Rationale__c", squash(g.get("rationale"))),
            ("Active__c", bool(g.get("active", True))),
        ]))


def main():
    global _offering_prefix
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate and diff only")
    ap.add_argument("--allow-missing-source-root", action="store_true",
                    help="skip rule 5 when no ma-migrator working copy is present")
    args = ap.parse_args()

    root = source_root()
    if root is None and not args.allow_missing_source_root:
        print("note: no ma-migrator working copy found; rule 5 (cited paths exist) "
              "cannot run. Set MA_MIGRATOR_ROOT or pass --allow-missing-source-root.")

    offerings = offering_dirs()
    if not offerings:
        _offering_prefix = ""
        fail("instrument/", "no offering directories found. Each offering is an "
                            "immediate subdirectory of instrument/ containing "
                            "a dimensions.yaml.")

    # ---- PRE-FLIGHT: every instrument directory names a real offering.
    # Runs before the build loop so a directory with no GTM_Offering__mdt
    # record behind it never gets as far as being compiled and stamped.
    _offering_prefix = ""
    check_offerings_exist(offerings)

    # A precondition failure ABORTS rather than accumulating. The build loop
    # below assumes a well-formed offering directory and will raise IOError on
    # a half-authored one, so continuing past a failed pre-flight would
    # replace a named, actionable error with a traceback.
    if errors:
        print("INSTRUMENT BUILD FAILED\n")
        for e in errors:
            print("  x " + e)
        for w in warnings:
            print("  ! " + w)
        return 1

    # ---- validate and emit, one offering at a time, in its own scope.
    out = {}
    owner = {}
    for offering_key, idir in offerings:
        build_offering(offering_key, idir, args, root, out, owner)
    _offering_prefix = ""

    if errors:
        print("INSTRUMENT BUILD FAILED\n")
        for e in errors:
            print("  x " + e)
        for w in warnings:
            print("  ! " + w)
        return 1

    # ---- Rule 14, which can only run once there is something to measure.
    for name, body in sorted(out.items()):
        check_capacity(name, body)
    if errors:
        print("INSTRUMENT BUILD FAILED\n")
        for e in errors:
            print("  x " + e)
        for w in warnings:
            print("  ! " + w)
        return 1

    # Stale-file cleanup spans ALL offerings deliberately: `out` is now every
    # offering's emitted records together, so a file that no longer appears in
    # it -- because its offering's YAML stopped emitting it, or because its
    # whole offering directory was deleted -- is still correctly stale. Scoping
    # this per offering would leave a deleted offering's records orphaned in
    # source and deployed in the org forever.
    stale, written = [], []
    existing = {n for n in os.listdir(CMD_DIR)
                if n.split(".")[0] in ("GTM_Assessment_Pair", "GTM_Assessment_Dimension_Override",
                                       "GTM_Assessment_Supplement", "GTM_Assessment_Gate")}
    for name in sorted(existing - set(out)):
        stale.append(name)
        if not args.check:
            os.remove(os.path.join(CMD_DIR, name))
    for name, body in sorted(out.items()):
        path = os.path.join(CMD_DIR, name)
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current == body:
            continue
        written.append(name)
        if not args.check:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(body)

    for w in warnings:
        print("  ! " + w)
    if args.check:
        if written or stale:
            print("STALE: %d record(s) would change, %d would be removed. "
                  "Run scripts/build-instrument.py." % (len(written), len(stale)))
            for n in written + stale:
                print("  - " + n)
            return 1
        print("Instrument up to date: %d records across %d offering(s) (%s), "
              "all 14 rules hold."
              % (len(out), len(offerings), ", ".join(k for k, _ in offerings)))
        return 0
    print("Instrument built: %d records across %d offering(s) (%s); %d written, "
          "%d removed. All 14 rules hold."
          % (len(out), len(offerings), ", ".join(k for k, _ in offerings),
             len(written), len(stale)))
    return 0


OBJECT_DIR = os.path.join(ROOT, "force-app", "main", "default", "objects")
_capacities = {}


def field_capacities(sobject):
    """field API name -> max length, read from the deploying field metadata.

    Typed nowhere: the numbers that matter are the ones in the .field-meta.xml
    files, and a check that carried its own copy of them would agree with itself
    while disagreeing with the org.
    """
    if sobject in _capacities:
        return _capacities[sobject]
    caps = {}
    fdir = os.path.join(OBJECT_DIR, sobject + "__mdt", "fields")
    if os.path.isdir(fdir):
        for fname in sorted(os.listdir(fdir)):
            if not fname.endswith(".field-meta.xml"):
                continue
            try:
                node = ET.parse(os.path.join(fdir, fname)).getroot()
            except ET.ParseError:
                continue
            api = node.findtext("{%s}fullName" % NS)
            length = node.findtext("{%s}length" % NS)
            if api and length and node.findtext("{%s}type" % NS) in ("Text", "LongTextArea"):
                caps[api] = int(length)
    _capacities[sobject] = caps
    return caps


def check_capacity(filename, body):
    """Rule 14. Evidence_Prompt__c was Text(255) and held 413 characters."""
    sobject = filename.split(".")[0]
    caps = field_capacities(sobject)
    if not caps:
        return
    try:
        node = ET.fromstring(body)
    except ET.ParseError:
        return
    for v in node.findall("{%s}values" % NS):
        field = v.findtext("{%s}field" % NS)
        text = v.findtext("{%s}value" % NS)
        cap = caps.get(field)
        if cap and text and len(text) > cap:
            fail(filename, "%s holds %d characters and the field is %d. The deploy is "
                           "where this would otherwise be discovered, and nothing in "
                           "this repo has ever been deployed."
                 % (field, len(text), cap))


def squash(text):
    """YAML block scalars keep their newlines; custom metadata strings read
    better as paragraphs. Blank lines become paragraph breaks, single newlines
    become spaces."""
    if text is None:
        return None
    parts = [" ".join(p.split()) for p in re.split(r"\n\s*\n", str(text).strip())]
    return "\n\n".join(p for p in parts if p)


def callouts_json(callouts):
    """Serialize callouts in the ma-migrator gap-pattern shape, verbatim.

    rationale is stripped out: it is authoring provenance, not something a
    client reads, and it would otherwise be the largest thing in the blob.
    """
    if not callouts:
        return None
    keep = ("pattern", "status", "severity", "category", "issue", "gloss",
            "workaround", "manual_steps", "verification_required")
    out = []
    for c in callouts:
        row = {}
        for k in keep:
            if c.get(k) is not None:
                row[k] = squash(c[k]) if isinstance(c[k], str) else c[k]
        out.append(row)
    return json.dumps(out, separators=(",", ":"))


def check_variant_reachability(where, slot, ordered, doc):
    """Rule 11b. Every authored variant must be the FIRST match for at least one
    set of answers a respondent could actually give.

    A variant that is never first is a question nobody will ever be asked --
    which, in a questionnaire, is indistinguishable from a question that works.
    The usual cause is a broader predicate authored above a narrower one
    (`gte 2` before `eq 4`), and it is exactly the kind of thing nobody notices
    until a client is looking at the screen.

    The search space is small on purpose: a predicate may only reference source,
    target and earlier slots (rule 8), each of which is answered 1-4, so
    enumerating the fields a slot's variants actually mention is enough to
    decide reachability outright rather than approximate it.
    """
    variants = slot["variants"]
    if not variants:
        return
    refs = set()
    for v in variants:
        collect_predicate_fields(v["show_when"], where, refs)
    answer_fields = sorted(f for f in refs if f not in ("source", "target"))
    if len(answer_fields) > MAX_REACHABILITY_FIELDS:
        warn(where, "slot %r branches on %d earlier answers; reachability was not "
                    "enumerated. A branch over that many answers is a scoring model "
                    "wearing a predicate." % (slot["key"], len(answer_fields)))
        return

    fixed = {"source": doc.get("source"), "target": doc.get("target")}
    reached = set()
    default_reached = False
    combos = 1
    for _ in answer_fields:
        combos *= 4
    for n in range(combos):
        ctx = dict(fixed)
        rest = n
        for f in answer_fields:
            ctx[f] = (rest % 4) + 1
            rest //= 4
        winner = None
        for v in variants:
            if eval_predicate(v["show_when"], ctx):
                winner = v.get("variant_key")
                break
        if winner is None:
            default_reached = True
        else:
            reached.add(winner)

    for v in variants:
        key = v.get("variant_key")
        if key not in reached:
            fail(where, "branch variant %r of slot %r is unreachable: no set of answers "
                        "makes it the first matching variant. Usually a broader predicate "
                        "sits above a narrower one -- check variant_order."
                 % (key, slot["key"]))
    if not default_reached:
        warn(where, "slot %r always takes a branch; its default question can never be "
                    "asked. Legal, but if that is deliberate the default is dead content "
                    "and should say so." % slot["key"])


def resolution_chain(pairs, doc):
    """Least specific first, so a later (more specific) pack overrides an
    earlier one. This is the same order GtmAssessmentInstrument.resolve() walks;
    if the two ever disagree, the build is validating an instrument nobody
    runs."""
    src, tgt = doc.get("source"), doc.get("target")
    chain = []
    for _, (w, cand) in sorted(pairs.items()):
        if cand.get("active", True) is False:
            continue
        cs, ct = cand.get("source"), cand.get("target")
        if ct not in (ANY, tgt):
            continue
        if cs not in (ANY, src) and not (cand.get("source_is_family") and
                                         cs == doc.get("source_family")):
            continue
        chain.append((cand.get("specificity", 4), cand))
    chain.sort(key=lambda x: -x[0])
    return chain


if __name__ == "__main__":
    sys.exit(main())
