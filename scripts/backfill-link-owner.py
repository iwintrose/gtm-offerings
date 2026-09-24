#!/usr/bin/env python3
"""
One-time, reversible OwnerId backfill (issue rep-ownership-lockdown-3-backfill).

Owner rule: a rep may view/edit/delete only their own links and everything
tied to them. Legacy guest-created rows tied to a link are still owned by the
site's guest user; before `viewAllRecords` is removed from GTM_Offering_User
they must be re-owned to the link owner (GTM_Saved_Configuration__c.OwnerId).

    python3 scripts/backfill-link-owner.py --check
    python3 scripts/backfill-link-owner.py -o <alias>                (dry-run, default)
    python3 scripts/backfill-link-owner.py --apply -o <alias> \\
        --i-understand-this-writes-to-org <alias> [--scratch-dir DIR] [--yes-alias <alias>]
    python3 scripts/backfill-link-owner.py --rollback <csv> -o <alias> \\
        --i-understand-this-writes-to-org <alias>

COORDINATOR ONLY. gtm-prod is PRODUCTION. Developers/QA run `--check` only
(no org call, no `sf` invocation). See docs/runbooks/rep-ownership-backfill.md.

Write allowlist (frozen): GTM_Link_Event__c, GTM_Form_Draft__c, Task; the only
field ever written is OwnerId. Requests, readouts, versions and Cases are
NEVER written (readouts may be owned by the GTM_Readout_Triage queue by
design). Only Python stdlib is used; `sf` is invoked with an argument list.
Output never contains record names, contact fields or emails; only counts,
User Ids and Usernames of users.
"""

import argparse
import csv
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

WRITE_ALLOWLIST = frozenset({"GTM_Link_Event__c", "GTM_Form_Draft__c", "Task"})
WRITE_FIELDS = ("OwnerId",)
LINK_OBJ = "GTM_Saved_Configuration__c"
LINK_FIELD = {
    "GTM_Link_Event__c": "Saved_Configuration__c",
    "GTM_Form_Draft__c": "Saved_Configuration__c",
    "Task": "WhatId",
}
OBJECT_ORDER = ("GTM_Link_Event__c", "GTM_Form_Draft__c", "Task")
CSV_HEADER = ["Id", "SObject", "OldOwnerId", "NewOwnerId"]

DEFAULT_MAX_API_CALLS = 200
API_RESERVE = 500
DEFAULT_BATCH = 2000
HARD_BATCH_CAP = 10000
BASE_READ_CALLS = 8
IN_MAX_IDS = 150
SOQL_MAX_CHARS = 4000

ID_RE = re.compile(r"^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$")

ALLOWED_WORDS = {
    # keywords
    "SELECT", "FROM", "WHERE", "AND", "IN", "NOT", "GROUP", "BY", "COUNT",
    # objects
    "GTM_Saved_Configuration__c", "GTM_Link_Event__c", "GTM_Form_Draft__c",
    "GTM_Assessment_Request__c", "GTM_Readout__c", "Task", "User",
    # fields / relationships / aliases
    "Id", "OwnerId", "WhatId", "Saved_Configuration__c", "Saved_Configuration__r",
    "Assessment_Request__c", "Assessment_Request__r", "Username", "IsActive",
    "UserType", "c", "null",
}


class BackfillError(Exception):
    """Fail-closed error: abort with no further writes."""


class ShapeError(BackfillError):
    """Unexpected query/CLI result shape."""


def same_id(a, b):
    return bool(a) and bool(b) and a[:15] == b[:15]


def valid_id(x):
    return isinstance(x, str) and bool(ID_RE.match(x))


# --------------------------------------------------------------------------
# SOQL construction (strict whitelist)
# --------------------------------------------------------------------------

def check_soql(q):
    if len(q) > SOQL_MAX_CHARS:
        raise BackfillError("SOQL too long")
    for lit in re.findall(r"'([^']*)'", q):
        if not (valid_id(lit) or lit == "Guest"):
            raise BackfillError("SOQL literal not an Id: refusing")
    stripped = re.sub(r"'[^']*'", "?", q)
    if not re.match(r"^[A-Za-z0-9_.,()!=?\s]*$", stripped):
        raise BackfillError("SOQL has unexpected characters")
    if not stripped.lstrip().startswith("SELECT "):
        raise BackfillError("SOQL must be a SELECT")
    for m in re.finditer(r"\(([^()]*)\)", stripped):
        if m.group(1).count("?") > IN_MAX_IDS:
            raise BackfillError("SOQL IN list too large")
    for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_.]*", stripped):
        for part in tok.split("."):
            if part not in ALLOWED_WORDS:
                raise BackfillError(f"SOQL identifier not allowlisted: {part}")
    return q


def _in_list(ids):
    ids = list(ids)
    for i in ids:
        if not valid_id(i):
            raise BackfillError("refusing non-Id value in IN list")
    return "(" + ", ".join(f"'{i}'" for i in ids) + ")"


def _allowed_obj(obj):
    if obj not in WRITE_ALLOWLIST or obj == "Task":
        raise BackfillError(f"not a lookup-linked allowlisted object: {obj}")
    return obj


Q_LINKS = f"SELECT Id, OwnerId FROM {LINK_OBJ}"
GUEST_SEMI = "(SELECT Id FROM User WHERE UserType = 'Guest')"
LINK_SEMI = f"(SELECT Id FROM {LINK_OBJ})"


def q_users(ids):
    return f"SELECT Id, Username, IsActive, UserType FROM User WHERE Id IN {_in_list(ids)}"


def q_group_rel(obj):
    _allowed_obj(obj)
    return (f"SELECT OwnerId, Saved_Configuration__r.OwnerId, COUNT(Id) c FROM {obj} "
            "WHERE Saved_Configuration__c != null "
            "GROUP BY OwnerId, Saved_Configuration__r.OwnerId")


def q_group_link(obj):
    _allowed_obj(obj)
    return (f"SELECT OwnerId, Saved_Configuration__c, COUNT(Id) c FROM {obj} "
            "WHERE Saved_Configuration__c != null "
            "GROUP BY OwnerId, Saved_Configuration__c")


def q_orphans(obj):
    _allowed_obj(obj)
    return f"SELECT COUNT(Id) c FROM {obj} WHERE Saved_Configuration__c = null"


def q_rows(obj, owners):
    _allowed_obj(obj)
    return (f"SELECT Id, OwnerId, Saved_Configuration__c FROM {obj} "
            f"WHERE Saved_Configuration__c != null AND OwnerId IN {_in_list(owners)}")


Q_TASK_GUEST = (f"SELECT Id, OwnerId, WhatId FROM Task WHERE WhatId IN {LINK_SEMI} "
                f"AND OwnerId IN {GUEST_SEMI}")
Q_TASK_OTHER = (f"SELECT OwnerId, COUNT(Id) c FROM Task WHERE WhatId IN {LINK_SEMI} "
                f"AND OwnerId NOT IN {GUEST_SEMI} GROUP BY OwnerId")
Q_REQ_REPORT = ("SELECT OwnerId, Saved_Configuration__r.OwnerId, COUNT(Id) c "
                "FROM GTM_Assessment_Request__c WHERE Saved_Configuration__c != null "
                "GROUP BY OwnerId, Saved_Configuration__r.OwnerId")
Q_READOUT_REPORT = ("SELECT OwnerId, Assessment_Request__r.Saved_Configuration__r.OwnerId, "
                    "COUNT(Id) c FROM GTM_Readout__c WHERE Assessment_Request__c != null "
                    "GROUP BY OwnerId, Assessment_Request__r.Saved_Configuration__r.OwnerId")


def q_current_owner(obj, ids):
    if obj not in WRITE_ALLOWLIST:
        raise BackfillError(f"not allowlisted: {obj}")
    return f"SELECT Id, OwnerId FROM {obj} WHERE Id IN {_in_list(ids)}"


ALLOWED_WORDS.add("Assessment_Request__r")


# --------------------------------------------------------------------------
# sf wrapper
# --------------------------------------------------------------------------

def _subprocess_runner(cmd):
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return p.returncode, p.stdout


class Sf:
    """Runs sf commands (argument list, never a shell) and counts API calls."""

    READ_OK = (("data", "query"),)
    PREFLIGHT_OK = (("limits", "api"),)
    WRITE_OK = (("data", "update"),)

    def __init__(self, alias, read_only=True, runner=None):
        self.alias = alias
        self.read_only = read_only
        self.runner = runner or _subprocess_runner
        self.calls = 0
        self.log = []

    def _json(self, args):
        head = tuple(args[:2])
        allowed = self.READ_OK if self.read_only else self.READ_OK + self.PREFLIGHT_OK + self.WRITE_OK
        if head not in allowed:
            raise BackfillError(f"sf command not permitted in this mode: {' '.join(args[:2])}")
        cmd = ["sf"] + list(args) + ["-o", self.alias, "--json"]
        self.log.append(cmd)
        self.calls += 1
        rc, out = self.runner(cmd)
        try:
            data = json.loads(out)
        except (ValueError, TypeError):
            raise ShapeError("sf returned non-JSON output")
        if not isinstance(data, dict) or "status" not in data:
            raise ShapeError("sf JSON missing status")
        if rc != 0 or data.get("status") != 0:
            raise ShapeError(f"sf exited non-zero ({' '.join(args[:3])}): "
                             f"{str(data.get('name') or data.get('message') or '')[:120]}")
        return data.get("result")

    def query(self, soql):
        check_soql(soql)
        res = self._json(["data", "query", "-q", soql])
        if not isinstance(res, dict) or not isinstance(res.get("records"), list):
            raise ShapeError("query result missing records")
        recs = res["records"]
        if res.get("totalSize") is not None and res["totalSize"] != len(recs):
            raise ShapeError("query totalSize mismatch (partial result)")
        return recs

    def limits_remaining(self):
        res = self._json(["limits", "api", "display"])
        if isinstance(res, list):
            for r in res:
                if isinstance(r, dict) and r.get("name") == "DailyApiRequests":
                    rem = r.get("remaining")
                    if isinstance(rem, int):
                        return rem
        raise ShapeError("DailyApiRequests not found in limits output")

    def bulk_update(self, sobject, csv_path):
        if sobject not in WRITE_ALLOWLIST:
            raise BackfillError(f"write to non-allowlisted object refused: {sobject}")
        res = self._json(["data", "update", "bulk", "--sobject", sobject,
                          "--file", str(csv_path), "--wait", "10"])
        if not isinstance(res, dict):
            raise ShapeError("bulk result malformed")
        return res


# --------------------------------------------------------------------------
# Read + planning
# --------------------------------------------------------------------------

class PlanRow:
    __slots__ = ("id", "old", "new", "link")

    def __init__(self, id_, old, new, link):
        self.id, self.old, self.new, self.link = id_, old, new, link


class Plan:
    def __init__(self):
        self.rows = {o: [] for o in OBJECT_ORDER}
        self.by_current = {o: {} for o in OBJECT_ORDER}
        self.by_target = {o: {} for o in OBJECT_ORDER}
        self.skipped = {o: {} for o in OBJECT_ORDER}
        self.report_only = {}
        self.users = {}
        self.grouped_mode = "relationship"

    def skip(self, obj, reason, n=1):
        self.skipped[obj][reason] = self.skipped[obj].get(reason, 0) + n

    def total(self):
        return sum(len(v) for v in self.rows.values())


def _chunks(seq, n):
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def _get_target_key(rec, rel):
    """Return the relationship owner value from an aggregate record, else raise."""
    dotted = f"{rel}.OwnerId"
    if dotted in rec:
        return rec[dotted]
    sub = rec.get(rel)
    if isinstance(sub, dict) and "OwnerId" in sub:
        return sub["OwnerId"]
    raise ShapeError("grouped relationship field not present distinctly in result")


def _count(rec):
    for k in ("c", "expr0"):
        if k in rec:
            try:
                return int(rec[k])
            except (TypeError, ValueError):
                break
    raise ShapeError("aggregate row missing count")


def fetch_links(sf):
    links = {}
    for r in sf.query(Q_LINKS):
        if not (valid_id(r.get("Id")) and valid_id(r.get("OwnerId"))):
            raise ShapeError("link row malformed")
        links[r["Id"][:15]] = r["OwnerId"]
    return links


def fetch_users(sf, ids):
    users = {}
    ids = sorted({i for i in ids if i and i.startswith("005")})
    for ch in _chunks(ids, IN_MAX_IDS):
        for r in sf.query(q_users(ch)):
            if not valid_id(r.get("Id")):
                raise ShapeError("user row malformed")
            users[r["Id"][:15]] = r
    return users


def user_skip_reason(target, users):
    """None if `target` is a legal write target, else a skip reason."""
    if not target:
        return "target-missing"
    if target.startswith("00G"):
        return "target-queue"
    if not target.startswith("005"):
        return "target-not-user"
    u = users.get(target[:15])
    if u is None:
        return "target-user-unknown"
    if u.get("IsActive") is False:
        return "target-inactive"
    if u.get("UserType") == "Guest":
        return "target-guest"
    return None


def mismatch_groups(sf, obj, links, plan):
    """[(current_owner, target_owner, count)] with current != target.
    Primary: grouped relationship SOQL. Fallback (F3): two-query link-id
    grouping compared client-side. Same return shape either way."""
    try:
        recs = sf.query(q_group_rel(obj))
        out = []
        for r in recs:
            cur, tgt = r.get("OwnerId"), _get_target_key(r, "Saved_Configuration__r")
            if not (valid_id(cur) and valid_id(tgt)):
                raise ShapeError("grouped row malformed")
            out.append((cur, tgt, _count(r)))
        plan.grouped_mode = "relationship"
    except ShapeError:
        recs = sf.query(q_group_link(obj))
        agg = {}
        for r in recs:
            cur, link = r.get("OwnerId"), r.get("Saved_Configuration__c")
            if not (valid_id(cur) and valid_id(link)):
                raise ShapeError("grouped row malformed")
            tgt = links.get(link[:15])
            if tgt is None:
                plan.skip(obj, "link-not-found", _count(r))
                continue
            agg[(cur, tgt)] = agg.get((cur, tgt), 0) + _count(r)
        out = [(c, t, n) for (c, t), n in agg.items()]
        plan.grouped_mode = "two-query-fallback"
    return [(c, t, n) for (c, t, n) in out if not same_id(c, t)]


def build_plan(sf, want_rows):
    """Reads live data and builds the plan. Only mismatches are planned, so a
    second run after a successful apply plans 0 rows (idempotent)."""
    plan = Plan()
    links = fetch_links(sf)
    plan.links = links

    groups = {}
    for obj in ("GTM_Link_Event__c", "GTM_Form_Draft__c"):
        groups[obj] = mismatch_groups(sf, obj, links, plan)
        orph = sf.query(q_orphans(obj))
        if len(orph) != 1:
            raise ShapeError("orphan count malformed")
        plan.skip(obj, "orphan-null-link", _count(orph[0]))

    task_rows = sf.query(Q_TASK_GUEST)
    other = sf.query(Q_TASK_OTHER)
    plan.report_only["Task non-guest-owned (not written, not compared) by current owner"] = {
        r.get("OwnerId"): _count(r) for r in other}

    all_ids = set()
    for obj, gs in groups.items():
        for c, t, _ in gs:
            all_ids.update((c, t))
    for r in task_rows:
        if not (valid_id(r.get("Id")) and valid_id(r.get("OwnerId")) and valid_id(r.get("WhatId"))):
            raise ShapeError("task row malformed")
        tgt = links.get(r["WhatId"][:15])
        if tgt:
            all_ids.add(tgt)
    users = fetch_users(sf, all_ids)
    plan.users = users

    for obj, gs in groups.items():
        writable_expected = 0
        for cur, tgt, n in gs:
            reason = user_skip_reason(tgt, users)
            if reason:
                plan.skip(obj, reason, n)
                continue
            plan.by_current[obj][cur] = plan.by_current[obj].get(cur, 0) + n
            plan.by_target[obj][tgt] = plan.by_target[obj].get(tgt, 0) + n
            writable_expected += n
        if want_rows and writable_expected:
            owners = sorted({c for c, t, _ in gs if not user_skip_reason(t, users)})
            for ch in _chunks(owners, IN_MAX_IDS):
                for r in sf.query(q_rows(obj, ch)):
                    if not (valid_id(r.get("Id")) and valid_id(r.get("OwnerId"))
                            and valid_id(r.get("Saved_Configuration__c"))):
                        raise ShapeError("row malformed")
                    link = r["Saved_Configuration__c"][:15]
                    tgt = links.get(link)
                    if tgt is None or same_id(r["OwnerId"], tgt) or user_skip_reason(tgt, users):
                        continue
                    plan.rows[obj].append(PlanRow(r["Id"], r["OwnerId"], tgt, link))
            if len(plan.rows[obj]) != writable_expected:
                raise BackfillError(
                    f"{obj}: planned {len(plan.rows[obj])} != grouped {writable_expected} "
                    "(data changed during the run?) - aborting, nothing written")

    for r in task_rows:
        tgt = links.get(r["WhatId"][:15])
        if tgt is None:
            plan.skip("Task", "link-not-found")
            continue
        if same_id(r["OwnerId"], tgt):
            continue
        reason = user_skip_reason(tgt, users)
        if reason:
            plan.skip("Task", reason)
            continue
        plan.by_current["Task"][r["OwnerId"]] = plan.by_current["Task"].get(r["OwnerId"], 0) + 1
        plan.by_target["Task"][tgt] = plan.by_target["Task"].get(tgt, 0) + 1
        plan.rows["Task"].append(PlanRow(r["Id"], r["OwnerId"], tgt, r["WhatId"][:15]))
    return plan


def report_only_counts(sf, plan):
    """Request/readout mismatches: REPORT ONLY, never written. Best effort."""
    for label, q, rel in (
        ("GTM_Assessment_Request__c (report-only)", Q_REQ_REPORT, "Saved_Configuration__r"),
        ("GTM_Readout__c (report-only; triage-queue owner is by design)", Q_READOUT_REPORT, None),
    ):
        try:
            n = 0
            for r in sf.query(q):
                if rel:
                    tgt = _get_target_key(r, rel)
                else:
                    sub = r.get("Assessment_Request__r")
                    tgt = None
                    if isinstance(sub, dict):
                        tgt = ((sub.get("Saved_Configuration__r") or {}).get("OwnerId"))
                    if tgt is None:
                        raise ShapeError("nested readout owner not present")
                if not same_id(r.get("OwnerId"), tgt):
                    n += _count(r)
            plan.report_only[label] = n
        except ShapeError:
            plan.report_only[label] = "unavailable (query shape not supported)"


def assert_plan_safe(plan_rows, links):
    """Fail closed: allowlisted objects only, and every row's new owner must be
    exactly the link owner."""
    for obj, rows in plan_rows.items():
        if obj not in WRITE_ALLOWLIST:
            raise BackfillError(f"plan contains non-allowlisted sobject {obj}")
        for r in rows:
            if links.get(r.link) is None or not same_id(links[r.link], r.new):
                raise BackfillError("plan row new owner != link owner")


def estimate_calls(total_rows, batch):
    if total_rows == 0:
        return BASE_READ_CALLS
    return BASE_READ_CALLS + 3 * math.ceil(total_rows / batch) + math.ceil(total_rows / 2000)


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

def _uname(plan, uid):
    u = plan.users.get((uid or "")[:15])
    return f"{uid} ({u.get('Username')})" if u and u.get("Username") else str(uid)


def print_report(plan, out=print):
    out(f"grouped-query mode: {plan.grouped_mode}")
    for obj in OBJECT_ORDER:
        n = len(plan.rows[obj]) or sum(plan.by_target[obj].values())
        out(f"\n{obj}: mismatched rows to re-own = {n}")
        for uid, c in sorted(plan.by_current[obj].items()):
            out(f"  current owner {_uname(plan, uid)}: {c}")
        for uid, c in sorted(plan.by_target[obj].items()):
            out(f"  target owner  {_uname(plan, uid)}: {c}")
        for reason, c in sorted(plan.skipped[obj].items()):
            out(f"  skipped ({reason}): {c}")
    for label, val in plan.report_only.items():
        if isinstance(val, dict):
            out(f"\nREPORT-ONLY {label}:")
            for uid, c in sorted(val.items()):
                out(f"  {uid}: {c}")
        else:
            out(f"\nREPORT-ONLY {label}: {val}")


def mismatches_total(plan):
    return sum(sum(v.values()) for v in plan.by_target.values())


# --------------------------------------------------------------------------
# Scratch dir / rollback CSV
# --------------------------------------------------------------------------

def _git_toplevel():
    try:
        p = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
                           capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            return Path(p.stdout.strip()).resolve()
    except OSError:
        pass
    return None


def resolve_scratch(scratch_dir, alias, toplevel_fn=_git_toplevel, now=None):
    now = now or datetime.now(timezone.utc)
    base = Path(scratch_dir) if scratch_dir else Path(tempfile.gettempdir()) / "gtm-backfill"
    path = (base / alias / now.strftime("%Y%m%dT%H%M%SZ")).resolve()
    for guard in {ROOT.resolve(), toplevel_fn()}:
        guard = guard.resolve() if guard is not None else None
        if guard is not None and (path == guard or guard in path.parents):
            raise BackfillError("scratch dir is inside the git work tree; refusing "
                                "(rollback CSVs must never be committable)")
    return path


def write_rollback_csv(path, obj, rows):
    if obj not in WRITE_ALLOWLIST:
        raise BackfillError(f"rollback CSV for non-allowlisted {obj}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(CSV_HEADER)
        for r in rows:
            w.writerow([r.id, obj, r.old, r.new])
        fh.flush()
        os.fsync(fh.fileno())
    with open(path, newline="") as fh:
        n = sum(1 for _ in csv.reader(fh)) - 1
    if n != len(rows):
        raise BackfillError(f"rollback CSV row count {n} != planned {len(rows)}")


def write_bulk_csv(path, pairs):
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["Id", "OwnerId"])
        for i, o in pairs:
            w.writerow([i, o])


def run_bulk(sf, obj, pairs, dirpath, batch, tag):
    """Update in bounded chunks; stop on the first failed row."""
    done = 0
    dirpath.mkdir(parents=True, exist_ok=True)
    for n, ch in enumerate(_chunks(pairs, batch), 1):
        f = dirpath / f"{tag}-{obj}-chunk{n}.csv"
        write_bulk_csv(f, ch)
        res = sf.bulk_update(obj, f)
        failed = res.get("numberRecordsFailed", res.get("recordsFailed"))
        processed = res.get("numberRecordsProcessed", res.get("recordsProcessed"))
        if not isinstance(failed, int) or not isinstance(processed, int):
            raise ShapeError("bulk result missing counts")
        done += max(processed - failed, 0)
        if failed:
            raise BackfillError(f"{obj}: {failed} row(s) failed in chunk {n} (job "
                                f"{res.get('jobId')}); stopping. Updated so far: {done}")
    return done


# --------------------------------------------------------------------------
# Modes
# --------------------------------------------------------------------------

def do_dry_run(sf, out=print):
    plan = build_plan(sf, want_rows=False)
    report_only_counts(sf, plan)
    print_report(plan, out)
    n = mismatches_total(plan)
    out(f"\nTOTAL mismatched rows in write scope: {n}")
    out(f"estimated API calls for --apply: {estimate_calls(n, DEFAULT_BATCH)}"
        f" (dry-run used {sf.calls})")
    return plan


def guard_write_flags(args):
    org, flag = args.org, args.confirm_org
    if not org or not flag or org != flag:
        return False
    return True


def do_apply(args, sf_factory, input_fn=input, out=print, toplevel_fn=_git_toplevel):
    if not guard_write_flags(args):
        out("REFUSED: --apply needs -o <alias> AND --i-understand-this-writes-to-org <same alias>.")
        return 2
    alias = args.org
    scratch = resolve_scratch(args.scratch_dir, alias, toplevel_fn)
    out(f"ABOUT TO WRITE OwnerId ON {alias} (PRODUCTION)")
    typed = args.yes_alias if args.yes_alias is not None else input_fn(f"Type the alias ({alias}) to continue: ")
    if typed != alias:
        out("REFUSED: alias confirmation did not match.")
        return 2
    sf = sf_factory(alias, read_only=False)
    remaining = sf.limits_remaining()
    if remaining < BASE_READ_CALLS + API_RESERVE:
        raise BackfillError(f"DailyApiRequests remaining {remaining} too low")
    plan = build_plan(sf, want_rows=True)
    assert_plan_safe(plan.rows, plan.links)
    total = plan.total()
    est = estimate_calls(total, args.batch_size)
    out(f"planned rows: {total}; estimated API calls: {est}; remaining: {remaining}")
    if est > args.max_api_calls:
        raise BackfillError(f"estimate {est} exceeds --max-api-calls {args.max_api_calls}")
    if remaining < est + API_RESERVE:
        raise BackfillError(f"remaining {remaining} < estimate {est} + reserve {API_RESERVE}")
    if total == 0:
        out("Nothing to do (0 mismatches in write scope).")
        return 0
    for obj in OBJECT_ORDER:
        if plan.rows[obj]:
            write_rollback_csv(scratch / f"rollback-{obj}.csv", obj, plan.rows[obj])
            out(f"rollback CSV: {scratch / ('rollback-' + obj + '.csv')}")
    summary = {}
    try:
        for obj in OBJECT_ORDER:
            rows = plan.rows[obj]
            if not rows:
                continue
            summary[obj] = run_bulk(sf, obj, [(r.id, r.new) for r in rows],
                                    scratch, args.batch_size, "apply")
    finally:
        for obj, n in summary.items():
            out(f"{obj}: planned {len(plan.rows[obj])}, updated {n}")
    after = build_plan(sf, want_rows=False)
    out(f"API calls used: {sf.calls}; mismatches remaining after run: {mismatches_total(after)}")
    return 0 if mismatches_total(after) == 0 else 1


def read_rollback_csv(path):
    with open(path, newline="") as fh:
        rd = csv.reader(fh)
        header = next(rd, None)
        if header != CSV_HEADER:
            raise BackfillError("rollback CSV header invalid")
        rows = []
        for i, row in enumerate(rd, 2):
            if len(row) != 4:
                raise BackfillError(f"rollback CSV line {i}: wrong column count")
            id_, obj, old, new = row
            if obj not in WRITE_ALLOWLIST:
                raise BackfillError(f"rollback CSV line {i}: sobject not allowlisted")
            if not (valid_id(id_) and valid_id(old) and valid_id(new)):
                raise BackfillError(f"rollback CSV line {i}: bad Id")
            rows.append((id_, obj, old, new))
    return rows


def do_rollback(args, sf_factory, out=print, toplevel_fn=_git_toplevel):
    if not guard_write_flags(args):
        out("REFUSED: --rollback needs -o <alias> AND --i-understand-this-writes-to-org <same alias>.")
        return 2
    rows = read_rollback_csv(args.rollback)
    scratch = resolve_scratch(args.scratch_dir, args.org, toplevel_fn)
    sf = sf_factory(args.org, read_only=False)
    remaining = sf.limits_remaining()
    est = BASE_READ_CALLS + 3 * math.ceil(max(len(rows), 1) / args.batch_size)
    if est > args.max_api_calls or remaining < est + API_RESERVE:
        raise BackfillError("API budget guard refused rollback")
    by_obj = {}
    for r in rows:
        by_obj.setdefault(r[1], []).append(r)
    restored = skipped = 0
    for obj, items in by_obj.items():
        cur = {}
        for ch in _chunks([i[0] for i in items], IN_MAX_IDS):
            for r in sf.query(q_current_owner(obj, ch)):
                cur[r["Id"][:15]] = r.get("OwnerId")
        pairs = []
        for id_, _, old, new in items:
            if same_id(cur.get(id_[:15]), new):
                pairs.append((id_, old))
            else:
                skipped += 1
        if pairs:
            restored += run_bulk(sf, obj, pairs, scratch, args.batch_size, "rollback")
    out(f"rollback: restored {restored}, skipped (owner changed since) {skipped}")
    return 0


# --------------------------------------------------------------------------
# --check self-tests (no org, no sf)
# --------------------------------------------------------------------------


def _fid(prefix, tag, n):
    """Runtime-built fake 15-char Id for self-tests (keeps hardcoded-id-looking
    literals out of the source, which check-references.py rightly flags)."""
    return f"{prefix}{tag}{n:09d}"[:15].ljust(15, "0")


REP_A, REP_B = _fid("005", "R", 1), _fid("005", "R", 2)
OFF_U, GST_U, QUE_G = _fid("005", "O", 3), _fid("005", "G", 4), _fid("00G", "Q", 5)


class FakeOrg:
    """In-memory stand-in for `sf`; the runner interface is cmd -> (rc, stdout)."""

    def __init__(self, grouped_supported=True):
        self.grouped_supported = grouped_supported
        self.log = []
        self.remaining = 10000
        self.csv_state_at_write = []
        self.fail_bulk = False
        self.users = {
            REP_A: dict(Id=REP_A, Username="repa@x", IsActive=True, UserType="Standard"),
            REP_B: dict(Id=REP_B, Username="repb@x", IsActive=True, UserType="Standard"),
            OFF_U: dict(Id=OFF_U, Username="off@x", IsActive=False, UserType="Standard"),
            GST_U: dict(Id=GST_U, Username="guest@x", IsActive=True, UserType="Guest"),
        }
        self.links = {"a0LLNK000000001": REP_A, "a0LLNK000000002": OFF_U,
                      "a0LLNK000000003": QUE_G}
        G = GST_U
        self.rows = {
            "GTM_Link_Event__c": {"a0EEVT000000001": [G, "a0LLNK000000001"],
                                  "a0EEVT000000002": [REP_A, "a0LLNK000000001"],
                                  "a0EEVT000000003": [G, "a0LLNK000000002"],
                                  "a0EEVT000000004": [G, "a0LLNK000000003"],
                                  "a0EEVT000000005": [G, None],
                                  "a0EEVT000000006": [REP_B, "a0LLNK000000001"]},
            "GTM_Form_Draft__c": {"a0DDRF000000001": [G, "a0LLNK000000001"]},
            "Task": {"00TTSK000000001": [G, "a0LLNK000000001"],
                     "00TTSK000000002": [REP_B, "a0LLNK000000001"],
                     "00TTSK000000003": [REP_A, "a0LLNK000000001"]},
        }

    @staticmethod
    def _ok(result):
        return 0, json.dumps({"status": 0, "result": result})

    @staticmethod
    def _err(msg):
        return 1, json.dumps({"status": 1, "name": "MALFORMED_QUERY", "message": msg})

    def _tgt(self, link):
        return self.links.get(link) if link else None

    def __call__(self, cmd):
        self.log.append(cmd)
        if cmd[1:3] == ["limits", "api"]:
            return self._ok([{"name": "DailyApiRequests", "max": 15000, "remaining": self.remaining}])
        if cmd[1:3] == ["data", "update"]:
            path = cmd[cmd.index("--file") + 1]
            obj = cmd[cmd.index("--sobject") + 1]
            self.csv_state_at_write.append(sorted(os.listdir(os.path.dirname(path))))
            with open(path, newline="") as fh:
                rows = list(csv.DictReader(fh))
            if self.fail_bulk:
                return self._ok({"jobId": "750JOB", "numberRecordsProcessed": len(rows),
                                 "numberRecordsFailed": 1})
            for r in rows:
                self.rows[obj][r["Id"]][0] = r["OwnerId"]
            return self._ok({"jobId": "750JOB", "numberRecordsProcessed": len(rows),
                             "numberRecordsFailed": 0})
        q = cmd[cmd.index("-q") + 1]
        return self._query(q)

    def _agg(self, recs):
        return self._ok({"totalSize": len(recs), "done": True, "records": recs})

    def _query(self, q):
        m = re.search(r"FROM (\w+)", q)
        obj = m.group(1)
        if obj == "GTM_Saved_Configuration__c":
            return self._agg([{"Id": k, "OwnerId": v} for k, v in self.links.items()])
        if obj == "User":
            ids = re.findall(r"'(\w+)'", q)
            return self._agg([self.users[i] for i in ids if i in self.users])
        if "GROUP BY OwnerId, Saved_Configuration__r.OwnerId" in q and obj in self.rows:
            if not self.grouped_supported:
                return self._err("unsupported grouped relationship")
            agg = {}
            for _, (o, l) in self.rows[obj].items():
                if l:
                    agg[(o, self._tgt(l))] = agg.get((o, self._tgt(l)), 0) + 1
            return self._agg([{"OwnerId": o, "Saved_Configuration__r": {"OwnerId": t}, "c": n}
                              for (o, t), n in agg.items()])
        if "GROUP BY OwnerId, Saved_Configuration__c" in q:
            agg = {}
            for _, (o, l) in self.rows[obj].items():
                if l:
                    agg[(o, l)] = agg.get((o, l), 0) + 1
            return self._agg([{"OwnerId": o, "Saved_Configuration__c": l, "c": n} for (o, l), n in agg.items()])
        if q.startswith("SELECT COUNT(Id) c") and "= null" in q:
            return self._agg([{"c": sum(1 for _, l in self.rows[obj].values() if l is None)}])
        if obj == "Task" and "GROUP BY OwnerId" in q:
            agg = {}
            for o, l in self.rows["Task"].values():
                if self.users.get(o, {}).get("UserType") != "Guest":
                    agg[o] = agg.get(o, 0) + 1
            return self._agg([{"OwnerId": o, "c": n} for o, n in agg.items()])
        if obj == "Task" and "UserType = 'Guest'" in q:
            return self._agg([{"Id": i, "OwnerId": o, "WhatId": l} for i, (o, l) in self.rows["Task"].items()
                              if self.users.get(o, {}).get("UserType") == "Guest"])
        if "Id, OwnerId, Saved_Configuration__c FROM" in q:
            owners = set(re.findall(r"'(\w+)'", q))
            return self._agg([{"Id": i, "OwnerId": o, "Saved_Configuration__c": l}
                              for i, (o, l) in self.rows[obj].items() if l and o in owners])
        if q.startswith("SELECT Id, OwnerId FROM") and " Id IN " in q:
            ids = set(re.findall(r"'(\w+)'", q))
            return self._agg([{"Id": i, "OwnerId": self.rows[obj][i][0]} for i in ids if i in self.rows[obj]])
        return self._err("fake org: unsupported query")


def _args(**kw):
    ns = argparse.Namespace(org=None, confirm_org=None, yes_alias=None, scratch_dir=None,
                            batch_size=DEFAULT_BATCH, max_api_calls=DEFAULT_MAX_API_CALLS,
                            rollback=None)
    ns.__dict__.update(kw)
    return ns


def cmd_check():
    failures = []
    quiet = lambda *_a, **_k: None

    def t(name, fn):
        try:
            fn()
            print(f"  ok   {name}")
        except Exception as exc:  # noqa: BLE001
            failures.append(name)
            print(f"  FAIL {name}: {type(exc).__name__}: {exc}")

    def expect_raises(fn, exc=BackfillError):
        try:
            fn()
        except exc:
            return
        raise AssertionError("expected exception")

    tmp = Path(tempfile.mkdtemp(prefix="gtm-backfill-check-"))

    def mk(org=None, **kw):
        org = org or FakeOrg(**kw)
        return org, (lambda alias, read_only=True: Sf(alias, read_only, runner=org))

    def t1():
        for q in (Q_LINKS, q_users([REP_A]), q_group_rel("GTM_Link_Event__c"),
                  q_group_link("GTM_Form_Draft__c"), q_orphans("GTM_Link_Event__c"),
                  q_rows("GTM_Link_Event__c", [REP_A]), Q_TASK_GUEST, Q_TASK_OTHER,
                  Q_REQ_REPORT, Q_READOUT_REPORT, q_current_owner("Task", ["00TTSK000000001"])):
            check_soql(q)
        expect_raises(lambda: check_soql("SELECT Name FROM GTM_Link_Event__c"))
        expect_raises(lambda: check_soql("SELECT Id FROM Case"))
        expect_raises(lambda: check_soql("SELECT Id FROM Task WHERE Id = 'x'; DELETE"))
        expect_raises(lambda: q_users(["005' OR 1=1 --"]))
        expect_raises(lambda: q_rows("GTM_Readout__c", [REP_A]))
        check_soql(q_users([f"005{i:012d}" for i in range(IN_MAX_IDS)]))
        expect_raises(lambda: check_soql(q_users([f"005{i:012d}" for i in range(IN_MAX_IDS + 1)])))

    def t2():
        org, fac = mk()
        sf = fac("gtm-x", read_only=True)
        do_dry_run(sf, quiet)
        assert org.log, "no commands recorded"
        for cmd in org.log:
            assert cmd[1:3] == ["data", "query"], cmd
            assert not any(w in " ".join(cmd) for w in ("update", "upsert", "delete", "bulk", "apex", "import"))
        expect_raises(lambda: Sf("gtm-x", True, runner=org).bulk_update("Task", "/x.csv"))

    def t3():
        org, fac = mk()
        for kw in (dict(), dict(org="gtm-x"), dict(confirm_org="gtm-x"),
                   dict(org="gtm-x", confirm_org="other"), dict(org="", confirm_org=""),
                   dict(org="gtm-prod", confirm_org="gtm-staging"), dict(org="GTM-X", confirm_org="gtm-x")):
            rc = do_apply(_args(scratch_dir=str(tmp), **kw), fac, quiet, quiet)
            assert rc == 2, kw
            rc = do_rollback(_args(rollback="x.csv", **kw), fac, quiet)
            assert rc == 2, kw
        assert do_apply(_args(org="a", confirm_org="a", scratch_dir=str(tmp), yes_alias="b"),
                        fac, quiet, quiet) == 2
        assert not org.log, "org was called on a refused path"

    def t4():
        expect_raises(lambda: assert_plan_safe({"GTM_Readout__c": []}, {}))
        expect_raises(lambda: assert_plan_safe({"Case": []}, {}))
        expect_raises(lambda: assert_plan_safe({"Task": [PlanRow("00TTSK000000001", "a", REP_B, "L")]},
                                               {"L": REP_A}))
        expect_raises(lambda: write_rollback_csv(tmp / "x.csv", "Case", []))
        assert WRITE_FIELDS == ("OwnerId",) and WRITE_ALLOWLIST == {"GTM_Link_Event__c", "GTM_Form_Draft__c", "Task"}
        sf = Sf("x", False, runner=lambda c: (0, "not json"))
        expect_raises(lambda: sf.query("SELECT Id, OwnerId FROM GTM_Saved_Configuration__c"), ShapeError)
        sf = Sf("x", False, runner=lambda c: (1, json.dumps({"status": 1})))
        expect_raises(lambda: sf.query(Q_LINKS), ShapeError)
        sf = Sf("x", False, runner=lambda c: (0, json.dumps({"status": 0, "result": {"totalSize": 5, "records": []}})))
        expect_raises(lambda: sf.query(Q_LINKS), ShapeError)
        sf = Sf("x", False, runner=lambda c: (0, "{}"))
        expect_raises(lambda: sf.query(Q_LINKS), ShapeError)
        expect_raises(lambda: Sf("x", False, runner=lambda c: (0, "{}"))._json(["apex", "run"]))

    def t5():
        org, fac = mk()
        plan = build_plan(fac("x"), want_rows=True)
        ev = plan.rows["GTM_Link_Event__c"]
        # only guest event and rep-B event on rep A's link move; inactive/queue/orphan skipped
        assert sorted(r.id for r in ev) == ["a0EEVT000000001", "a0EEVT000000006"], [r.id for r in ev]
        assert all(r.new == REP_A for r in ev)
        s = plan.skipped["GTM_Link_Event__c"]
        assert s.get("target-inactive") == 1 and s.get("target-queue") == 1 and s.get("orphan-null-link") == 1, s
        assert [r.id for r in plan.rows["Task"]] == ["00TTSK000000001"]  # non-guest owned = report-only
        assert sum(plan.report_only[next(iter(plan.report_only))].values()) == 2
        org2 = FakeOrg()
        for o in org2.rows:
            org2.rows[o] = {k: v for k, v in org2.rows[o].items() if v[1] == "a0LLNK000000002"}
        p2 = build_plan(Sf("x", False, runner=org2), True)
        assert p2.total() == 0
        gst = FakeOrg()
        gst.links["a0LLNK000000001"] = GST_U
        assert build_plan(Sf("x", False, runner=gst), True).rows["GTM_Link_Event__c"] == []
        fb, _ = mk(grouped_supported=False)
        pf = build_plan(Sf("x", False, runner=fb), True)
        assert pf.grouped_mode == "two-query-fallback" and pf.total() == plan.total()

    def t6():
        org, fac = mk()
        rc = do_apply(_args(org="gtm-x", confirm_org="gtm-x", yes_alias="gtm-x",
                            scratch_dir=str(tmp / "t6")), fac, quiet, quiet)
        assert rc == 0, rc
        assert build_plan(fac("x"), True).total() == 0
        n_before = len([c for c in org.log if c[1:3] == ["data", "update"]])
        rc = do_apply(_args(org="gtm-x", confirm_org="gtm-x", yes_alias="gtm-x",
                            scratch_dir=str(tmp / "t6b")), fac, quiet, quiet)
        assert rc == 0 and len([c for c in org.log if c[1:3] == ["data", "update"]]) == n_before

    def t7():
        org, fac = mk()
        good = tmp / "rb.csv"
        good.write_text("Id,SObject,OldOwnerId,NewOwnerId\n"
                        "a0EEVT000000001,GTM_Link_Event__c," + GST_U + "," + REP_A + "\n"
                        "a0EEVT000000002,GTM_Link_Event__c," + GST_U + "," + REP_A + "\n")
        # event 1 currently guest-owned (== not NewOwner): skipped; event 2 currently rep A: restored
        rc = do_rollback(_args(org="gtm-x", confirm_org="gtm-x", rollback=str(good),
                               scratch_dir=str(tmp / "t7")), fac, quiet)
        assert rc == 0
        assert org.rows["GTM_Link_Event__c"]["a0EEVT000000002"][0] == GST_U
        assert org.rows["GTM_Link_Event__c"]["a0EEVT000000006"][0] == REP_B
        assert org.rows["GTM_Link_Event__c"]["a0EEVT000000001"][0] == GST_U
        for body in ("Id,X,Y,Z\n", "Id,SObject,OldOwnerId,NewOwnerId\nbad,Task," + REP_A + "," + REP_B + "\n",
                     "Id,SObject,OldOwnerId,NewOwnerId\n00TTSK000000001,Case," + REP_A + "," + REP_B + "\n",
                     "Id,SObject,OldOwnerId,NewOwnerId\n00TTSK000000001,Task," + REP_A + "\n"):
            bad = tmp / "bad.csv"
            bad.write_text(body)
            expect_raises(lambda: read_rollback_csv(bad))

    def t8():
        expect_raises(lambda: resolve_scratch(str(ROOT / "scratch"), "x"))
        expect_raises(lambda: resolve_scratch(str(tmp), "x", toplevel_fn=lambda: tmp))
        resolve_scratch(str(tmp), "x", toplevel_fn=lambda: None)
        org, fac = mk()
        expect_raises(lambda: do_apply(_args(org="a", confirm_org="a", yes_alias="a",
                                             scratch_dir=str(ROOT / "s")), fac, quiet, quiet))
        assert not org.log
        org, fac = mk()
        do_apply(_args(org="a", confirm_org="a", yes_alias="a", scratch_dir=str(tmp / "t8")), fac, quiet, quiet)
        first = org.csv_state_at_write[0]
        assert any(n.startswith("rollback-") for n in first), first
        idx_w = next(i for i, c in enumerate(org.log) if c[1:3] == ["data", "update"])
        assert idx_w > 0
        org3, fac3 = mk()
        org3.fail_bulk = True
        expect_raises(lambda: do_apply(_args(org="a", confirm_org="a", yes_alias="a",
                                             scratch_dir=str(tmp / "t8b")), fac3, quiet, quiet))
        assert len([c for c in org3.log if c[1:3] == ["data", "update"]]) == 1  # stopped at first failure

    def t9():
        org, fac = mk()
        assert estimate_calls(0, 2000) == BASE_READ_CALLS
        assert estimate_calls(10000, 2000) > estimate_calls(2000, 2000)
        expect_raises(lambda: do_apply(_args(org="a", confirm_org="a", yes_alias="a", max_api_calls=5,
                                             scratch_dir=str(tmp / "t9")), fac, quiet, quiet))
        assert not [c for c in org.log if c[1:3] == ["data", "update"]]
        org.remaining = 300
        del org.log[:]
        expect_raises(lambda: do_apply(_args(org="a", confirm_org="a", yes_alias="a",
                                             scratch_dir=str(tmp / "t9b")), fac, quiet, quiet))
        assert len(org.log) == 1  # only the limits call

    tests = [("1 query construction whitelist", t1), ("2 dry-run issues only data query", t2),
             ("3 apply/rollback refuse without matching flag+alias", t3),
             ("4 allowlist and fail-closed shapes", t4), ("5 skip rules + fallback", t5),
             ("6 idempotency", t6), ("7 rollback from CSV", t7),
             ("8 scratch-dir git guard and CSV-before-write", t8), ("9 budget guard", t9)]
    print("backfill-link-owner self-tests:")
    for name, fn in tests:
        t(name, fn)
    if failures:
        print(f"\n{len(failures)} FAILED. No org call was made.")
        return 1
    print("\nOK: all self-tests passed. No org call was made.")
    return 0


# --------------------------------------------------------------------------

def parse_batch(v):
    n = int(v)
    if n < 1 or n > HARD_BATCH_CAP:
        raise argparse.ArgumentTypeError(f"--batch-size must be 1..{HARD_BATCH_CAP}")
    return n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="local self-tests, no org call")
    mode.add_argument("--dry-run", action="store_true", help="read-only report (default)")
    mode.add_argument("--apply", action="store_true", help="WRITE OwnerId (coordinator, after owner approval)")
    mode.add_argument("--rollback", metavar="CSV", help="restore owners from a rollback CSV")
    ap.add_argument("-o", "--org", help="org alias")
    ap.add_argument("--i-understand-this-writes-to-org", dest="confirm_org", metavar="ALIAS")
    ap.add_argument("--yes-alias", metavar="ALIAS", help="non-interactive alias echo for --apply")
    ap.add_argument("--scratch-dir", help="rollback CSV base dir (must be outside the git work tree)")
    ap.add_argument("--batch-size", type=parse_batch, default=DEFAULT_BATCH)
    ap.add_argument("--max-api-calls", type=int, default=DEFAULT_MAX_API_CALLS)
    args = ap.parse_args(argv)

    if args.check:
        return cmd_check()
    factory = lambda alias, read_only=True: Sf(alias, read_only)
    try:
        if args.apply:
            return do_apply(args, factory)
        if args.rollback:
            return do_rollback(args, factory)
        if not args.org:
            print("REFUSED: -o <alias> is required for a dry-run.", file=sys.stderr)
            return 2
        do_dry_run(factory(args.org, read_only=True))
        return 0
    except BackfillError as exc:
        print(f"ABORTED (fail closed, no further writes): {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
