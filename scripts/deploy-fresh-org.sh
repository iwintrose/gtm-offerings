#!/usr/bin/env bash
#
# Install the GTM Offerings framework (and, opt-in, offering packs) in an org
# that has never seen it.
#
# scripts/deploy.sh is the incremental one: it pushes the eleven directories
# that change day to day into an org that already has the rest. This script is
# the other job -- the one the expiring dev org made necessary. It deploys
# EVERY directory under force-app/, in an order chosen so that nothing is ever
# asked to resolve a reference to something that has not been deployed yet, and
# it stops at the first pass that fails rather than carrying on and leaving a
# half-built org that is harder to diagnose than an empty one.
#
# The default install is the FRAMEWORK ONLY: no offering, no instrument, no
# records (docs/architecture/blank-install.md). Offering content is opt-in via
# --with-offering <key>, driven by scripts/offerings/<key>.manifest.
#
# It cannot do the whole job. The Experience Cloud site shell (Digital
# Experiences setting in pass 8; Network + CustomSite + ExperienceBundle in ONE
# combined deployment in pass 9) IS deployed here. The guest profile's
# permission assignment and queue membership are
# org state, not metadata, and they are listed -- all of them, in the order they
# must happen -- in docs/runbooks/fresh-org-deploy.md and
# docs/runbooks/gtm-offerings-install.md. This script is one step of those.
#
# Usage:
#   ./scripts/deploy-fresh-org.sh <org-alias> [options]
#
# Options:
#   --run-tests      run all local Apex tests after the last pass
#   --check-only     validate the deploy against the org, change nothing
#   --with-profiles  also deploy force-app/main/default/profiles/ (OFF by
#                    default: those are STANDARD profiles that the target
#                    org's own users already sit on, and deploying them
#                    changes access for people who have nothing to do with
#                    this solution. Use a permission set instead unless you
#                    know you want this.)
#   --with-agent     also deploy bots/ and genAiPlugins/ (OFF by default:
#                    they need Agentforce provisioned on the org and fail
#                    outright when it is not)
#   --with-offering <key>
#                    install an offering pack (repeatable). <key> names
#                    scripts/offerings/<key>.manifest. Known packs:
#                    migration-accelerator, test-offering.
#   --with-demo-data load the synthetic demo records (scripts/seed-synthetic-data.py
#                    --load). Separate from any offering pack. Not run with
#                    --check-only.
#
# Environment:
#   GTM_SITE_SENDER_EMAIL  optional override for the Network's emailSenderAddress
#                    (pass 9). Default: the email of the authorized user in the
#                    target org (one org-info call plus one query). If neither
#                    yields an address and stdin is a terminal you are prompted
#                    (input hidden); otherwise the script stops. The value is
#                    only ever shown masked, and is never written into the repo.
#                    Salesforce may email a verification link to it.
#
set -euo pipefail

TARGET_ORG="${1:-}"
shift || true

RUN_TESTS=0; CHECK_ONLY=0; WITH_PROFILES=0; WITH_AGENT=0; WITH_DEMO=0
OFFERINGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --run-tests)     RUN_TESTS=1 ;;
    --check-only)    CHECK_ONLY=1 ;;
    --with-profiles) WITH_PROFILES=1 ;;
    --with-agent)    WITH_AGENT=1 ;;
    --with-demo-data) WITH_DEMO=1 ;;
    --with-offering)
      if [ $# -lt 2 ]; then echo "--with-offering needs a <key>" >&2; exit 2; fi
      OFFERINGS+=("$2"); shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$TARGET_ORG" ]; then
  cat >&2 <<'USAGE'
Usage: scripts/deploy-fresh-org.sh <org-alias> [--run-tests] [--check-only]
                                   [--with-profiles] [--with-agent]
                                   [--with-offering <key>]... [--with-demo-data]

No org alias is assumed on purpose. Deploying a whole solution into the wrong
org is the one mistake this script must never make possible.
USAGE
  exit 1
fi

cd "$(dirname "$0")/.."
SRC=force-app/main/default
DRY=""
[ "$CHECK_ONLY" -eq 1 ] && DRY="--dry-run"

# Validate every requested offering pack up front, before anything is deployed.
for key in ${OFFERINGS[@]+"${OFFERINGS[@]}"}; do
  case "$key" in
    *[!a-z0-9-]*|"") echo "invalid offering key: $key" >&2; exit 2 ;;
  esac
  if [ ! -f "scripts/offerings/$key.manifest" ]; then
    echo "unknown offering '$key': scripts/offerings/$key.manifest not found" >&2
    exit 2
  fi
done

TMP_PKG=""
cleanup() { [ -n "$TMP_PKG" ] && rm -rf "$TMP_PKG"; return 0; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Preflight. Every problem this catches is one that would otherwise surface as
# a Salesforce error four passes in, with the org half-built.
# ---------------------------------------------------------------------------
echo "==> Preflight: static reference and deployability audit"
if ! python3 scripts/check-references.py > /tmp/ma-preflight.$$ 2>&1; then
  sed -n '/WOULD-NOT-DEPLOY/,/DEPLOYS, BUT/p' /tmp/ma-preflight.$$
  rm -f /tmp/ma-preflight.$$
  echo ""
  echo "Preflight found problems that would fail this deploy. Fix them first,"
  echo "or re-read them above and decide deliberately -- do not just re-run."
  exit 1
fi
rm -f /tmp/ma-preflight.$$
echo "    clean"

if ! command -v sf > /dev/null 2>&1; then
  echo "The Salesforce CLI (sf) is not installed. See" >&2
  echo "https://developer.salesforce.com/tools/salesforcecli" >&2
  exit 1
fi

deploy() {
  local label="$1"; shift
  local dirs=()
  for d in "$@"; do
    [ -d "$SRC/$d" ] && dirs+=(--source-dir "$SRC/$d")
  done
  if [ ${#dirs[@]} -eq 0 ]; then
    echo "==> $label: nothing to deploy, skipping"
    return 0
  fi
  echo ""
  echo "==> $label"
  sf project deploy start "${dirs[@]}" --target-org "$TARGET_ORG" --wait 60 $DRY
}

# ---------------------------------------------------------------------------
# The order. Each pass exists because something in it is referenced by a later
# pass and would not resolve if it ran the other way round.
# ---------------------------------------------------------------------------

# 1. Schema first: every later pass grants on, writes to, lays out or reads
#    from these. Custom metadata TYPES live here too (objects/*__mdt), and the
#    records in pass 3 cannot deploy until their type exists.
deploy "Pass 1/9  schema (objects, fields, custom settings, platform events, CMDT types)" \
  objects

# 2. Callout and CSP allow-lists, and custom labels. Apex that calls out will
#    compile without the allow-lists but fail at runtime; Apex/LWC that
#    references System.Label.X or {i18n}X compiles without labels existing
#    but is wrong at runtime. None of the three depend on anything else.
deploy "Pass 2/9  callout allow-lists + custom labels (remote sites, CSP trusted sites, labels)" \
  remoteSiteSettings cspTrustedSites labels

# 3. Code. Apex compiles against the schema from pass 1; the trigger compiles
#    against the classes beside it; LWCs import the @AuraEnabled methods.
deploy "Pass 3/9  code (Apex classes, triggers, Lightning web components)" \
  classes triggers lwc

# 4. Custom metadata records, FRAMEWORK ONLY. The single framework record is
#    GTM_Assessment_Config.Default. Every offering's records (the offering
#    itself, instrument, platforms, pairs) come from an offering pack after
#    pass 9 (--with-offering). Deployed on their own, after their types, and
#    retried: bundling records with ~65 other components has been observed to
#    fail with a generic UNKNOWN_EXCEPTION on content that deploys cleanly by
#    itself. That is why this is its own pass rather than part of pass 1.
deploy_records() {
  # deploy_records <label> <file>...   (files or globs already expanded)
  local label="$1"; shift
  local args=()
  for f in "$@"; do args+=(--source-dir "$f"); done
  echo ""
  echo "==> $label"
  local ok=0 i log
  log="$(mktemp)"
  for i in 1 2 3 4; do
    echo "    attempt $i/4..."
    # pipefail (set above) makes this pipeline fail when sf fails, not tee.
    if sf project deploy start "${args[@]}" \
         --target-org "$TARGET_ORG" --wait 30 $DRY 2>&1 | tee "$log"; then
      ok=1; break
    fi
    sleep 10
  done
  if [ "$ok" -ne 1 ]; then
    echo ""
    echo "Custom metadata records failed after 4 attempts. Read the error above"
    echo "before doing anything else; a bare retry only helps with a generic"
    echo "UNKNOWN_EXCEPTION."
    if grep -qiE "DeveloperName|consecutive underscore|invalid.*developer" "$log"; then
      echo ""
      echo "The error mentions a DeveloperName, so this may be the consecutive-"
      echo "underscore risk documented in docs/runbooks/fresh-org-deploy.md"
      echo "section 9 (python3 scripts/rename-pair-keys.py --apply, then"
      echo "python3 scripts/build-instrument.py, then rerun)."
    else
      echo "The error does not mention a DeveloperName, so the rename in"
      echo "fresh-org-deploy.md section 9 will NOT help. Typical causes: an XML"
      echo "parse error in a record, a field or type that does not exist, or a"
      echo "missing earlier pass. Fix the named file and rerun."
    fi
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}
deploy_records "Pass 4/9  custom metadata records (framework only: Assessment_Config.Default)" \
  "$SRC/customMetadata/GTM_Assessment_Config.Default.md-meta.xml"

# 5. UI surfaces. FlexiPages draw the LWCs from pass 3 and sit on the objects
#    from pass 1; tabs point at FlexiPages and LWCs; apps list tabs. Strictly
#    in that order.
deploy "Pass 5/9  UI (managed content types, flexipages, tabs, apps, layouts)" \
  managedContentTypes flexipages tabs applications layouts

# 6. Automation. The approval process names three field updates by name; those
#    field updates live in workflows/ and must exist first or the approval
#    process is rejected. The queue owns GTM_Readout__c and Case records, so it
#    needs pass 1.
deploy "Pass 6/9  automation (workflow field updates, approval process, queue, flows)" \
  workflows approvalProcesses queues flows

# 7. Access. Permission sets grant on classes (pass 3), objects and fields
#    (pass 1), CMDT types (pass 1), tabs and apps (pass 5) -- so they are last
#    of the required passes, not first.
if [ "$WITH_PROFILES" -eq 1 ]; then
  deploy "Pass 7/9  access (permission sets, profiles)" permissionsets profiles
else
  deploy "Pass 7/9  access (permission sets)" permissionsets
  echo "    profiles/ skipped. Pass --with-profiles only if you have read the"
  echo "    note at the top of this script and want standard profiles changed."
fi

# 8. Site settings, ALONE, in one deploy: CommunitiesSettings (Digital
#    Experiences on) and ExperienceBundleSettings (enableExperienceBundleMetadata;
#    without it pass 9 is rejected with "ExperienceBundle isn't enabled for Aura
#    sites"). Both must be on and settled before a Network or bundle can deploy,
#    so this finishes before pass 9 starts. Directory: $SRC/settings.
deploy "Pass 8/9  site settings (Digital Experiences + ExperienceBundle metadata)" \
  settings

# 9. The site shell and its content, in ONE combined deployment. The three
#    pieces are mutually dependent on a fresh org: Network GTM needs the
#    SiteDotCom that ExperienceBundle GTM1 creates (picassoSite), and the
#    bundle needs Network GTM. Neither deploys alone (proven on gtm-staging,
#    see docs/architecture/site-shell-metadata.md section 3), so they go in one
#    metadata-API package: Network:GTM + CustomSite:GTM + ExperienceBundle:GTM1.
#
#    Source directories converted into that package: $SRC/networks (GTM),
#    $SRC/sites (GTM) and $SRC/experiences (GTM1).
#
#    The Network also refuses to create without emailSenderAddress, which is an
#    email address and so is never committed. The package is built in a temp
#    directory (removed on exit) from a source convert, and the address is
#    injected (see "Sender address precedence" below) into the TEMP copy only.
#
#    NOT YET PROVEN against a live org: this combined-deploy pattern for the
#    Aura site shell has to be validated with --check-only before it is trusted.
#    The fallback ladder is in the architecture doc.
echo ""
echo "==> Pass 9/9  site shell + content (Network GTM + CustomSite GTM + ExperienceBundle GTM1, one deployment)"
# Sender address precedence (never printed in full, never written to the repo):
#   1. env GTM_SITE_SENDER_EMAIL, if set
#   2. the email of the authorized user in the target org: ONE `sf org display`
#      for the username (only the username is read from it; the access token in
#      that output is never printed or stored) and ONE SOQL query for the email
#   3. a hidden prompt, only if stdin is a terminal
#   4. otherwise stop
SENDER="${GTM_SITE_SENDER_EMAIL:-}"
SENDER_SRC="GTM_SITE_SENDER_EMAIL"
mask_email() {
  python3 -c 'import sys
a=sys.argv[1]; u,_,d=a.partition("@")
print((u[:1]+"***@"+d) if d else "***")' "$1"
}
if [ -z "$SENDER" ]; then
  SENDER_SRC="authorized user in $TARGET_ORG"
  AUTH_USER="$(sf org display --target-org "$TARGET_ORG" --json 2>/dev/null \
    | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin)["result"]["username"])
except Exception:
    pass' || true)"
  case "$AUTH_USER" in
    ""|*[!A-Za-z0-9._%+@-]*) AUTH_USER="" ;;
  esac
  if [ -n "$AUTH_USER" ]; then
    SENDER="$(sf data query --target-org "$TARGET_ORG" \
      --query "SELECT Email FROM User WHERE Username = '$AUTH_USER' LIMIT 1" --json 2>/dev/null \
      | python3 -c 'import sys,json
try:
    r=json.load(sys.stdin)["result"]["records"]
    print(r[0]["Email"] if r else "")
except Exception:
    pass' || true)"
  fi
fi
if [ -z "$SENDER" ] && [ -t 0 ]; then
  SENDER_SRC="prompt"
  printf "    Could not determine a sender address. Enter one (input hidden): " >&2
  IFS= read -r -s SENDER || true
  printf "\n" >&2
fi
if [ -z "$SENDER" ]; then
  echo "Pass 9 needs the Network's emailSenderAddress and none could be found." >&2
  echo "Set GTM_SITE_SENDER_EMAIL, or make sure the authorized user has an email" >&2
  echo "in $TARGET_ORG, or run from a terminal to be prompted. It is never" >&2
  echo "committed or logged." >&2
  exit 1
fi
case "$SENDER" in
  *@*.*) ;;
  *) echo "The sender address (from $SENDER_SRC) does not look like an email address." >&2; exit 1 ;;
esac
echo "    Network sender: $(mask_email "$SENDER") (from $SENDER_SRC)."
echo "    Salesforce may email a verification link to that address; the admin"
echo "    may need to click it before the sender becomes active."
TMP_PKG="$(mktemp -d)"
sf project convert source \
  --metadata Network:GTM --metadata CustomSite:GTM --metadata ExperienceBundle:GTM1 \
  --output-dir "$TMP_PKG"
NETWORK_FILE="$(find "$TMP_PKG" -name 'GTM.network' -type f | head -n 1)"
if [ -z "$NETWORK_FILE" ]; then
  echo "Converted package has no GTM.network; cannot inject the sender address." >&2
  exit 1
fi
GTM_INJECT_SENDER="$SENDER" python3 - "$NETWORK_FILE" <<'PYINJECT'
import os, sys
from xml.sax.saxutils import escape
path = sys.argv[1]
val = escape(os.environ["GTM_INJECT_SENDER"])
with open(path, encoding="utf-8") as fh:
    body = fh.read()
if "<emailSenderAddress>" in body:
    sys.exit("committed Network already carries emailSenderAddress; remove it from source")
if "</Network>" not in body:
    sys.exit("unexpected Network XML: no closing tag")
body = body.replace("</Network>",
                    "    <emailSenderAddress>%s</emailSenderAddress>\n</Network>" % val, 1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(body)
PYINJECT
unset SENDER
sf project deploy start --metadata-dir "$TMP_PKG" --target-org "$TARGET_ORG" \
  --wait 60 $DRY

# ---------------------------------------------------------------------------
# Seed access. Seed imports write GTM_Page_Section__c / GTM_Page_Content__c, and
# a deploying admin holds none of the GTM permission sets, so the import dies
# with "FlsError: you don't have access to Label__c" (seen on a real deploy).
# So, before the FIRST seed of a run, assign GTM_Offering_Admin and
# GTM_Content_Admin to the AUTHORIZED USER ONLY (sf assigns to that user by
# default; no --on-behalf-of, so no one else, and never a guest profile).
# Idempotent: sets the user already holds are skipped. Must run after pass 7
# (which deploys the permission sets) and never under --check-only.
# ---------------------------------------------------------------------------
SEED_ACCESS_OK=0
ensure_seed_access() {
  [ "$SEED_ACCESS_OK" -eq 1 ] && return 0
  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "ERROR: ensure_seed_access called under --check-only" >&2; exit 1
  fi
  local user="${AUTH_USER:-}" have="" missing=() ps
  if [ -z "$user" ]; then
    user="$(sf org display --target-org "$TARGET_ORG" --json 2>/dev/null \
      | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin)["result"]["username"])
except Exception:
    pass' || true)"
    case "$user" in ""|*[!A-Za-z0-9._%+@-]*) user="" ;; esac
  fi
  echo ""
  echo "==> Seed access: permission sets for the authorized user of $TARGET_ORG"
  if [ -z "$user" ]; then
    echo "    could not determine the authorized user; not assigning anything." >&2
    echo "    Assign GTM_Offering_Admin and GTM_Content_Admin by hand, then rerun." >&2
    exit 1
  fi
  have="$(sf data query --target-org "$TARGET_ORG" --json --query \
    "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = '$user' AND PermissionSet.Name IN ('GTM_Offering_Admin','GTM_Content_Admin')" \
    2>/dev/null | python3 -c 'import sys,json
try:
    print(" ".join(r["PermissionSet"]["Name"] for r in json.load(sys.stdin)["result"]["records"]))
except Exception:
    pass' || true)"
  for ps in GTM_Offering_Admin GTM_Content_Admin; do
    case " $have " in
      *" $ps "*) echo "    $ps: already assigned, skipping" ;;
      *) missing+=("$ps") ;;
    esac
  done
  for ps in ${missing[@]+"${missing[@]}"}; do
    echo "    assigning $ps to the authorized user"
    sf org assign permset --name "$ps" --target-org "$TARGET_ORG"
  done
  SEED_ACCESS_OK=1
}

# Every seed import goes through this, so a seed can never run before the
# permission sets are assigned (scripts/check-references.py checks the same
# thing statically).
seed_import() {
  if [ "$SEED_ACCESS_OK" -ne 1 ]; then
    echo "ERROR: seed import attempted before ensure_seed_access" >&2; exit 1
  fi
  # Idempotent: `sf data import tree` cannot upsert, so ask the org first (one
  # query per file, scripts/seed-precheck.py) and skip rows that exist. Existing
  # rows are never overwritten, so a content manager's edits survive a re-run.
  local rc=0
  python3 scripts/seed-precheck.py "$1" "$TARGET_ORG" || rc=$?
  case "$rc" in
    0)  sf data import tree --files "$1" --target-org "$TARGET_ORG" ;;
    10) echo "    already loaded, skipping $1" ;;
    11) echo "    WARNING: $1 is only PARTLY loaded. Skipping it so nothing is" >&2
        echo "    duplicated; the missing rows were NOT created. Compare it with" >&2
        echo "    the org by hand (rows are keyed by Section_Address__c /" >&2
        echo "    Content_Address__c)." >&2
        SEED_PARTIAL=1 ;;
    *)  echo "ERROR: seed pre-check failed for $1 (exit $rc); not loading it." >&2
        exit 1 ;;
  esac
}
SEED_PARTIAL=0

# Offering packs (opt-in). Each pack is a manifest of customMetadata files and
# seed files. Records depend on schema only, and need pass 7 access to be useful,
# so they follow the last required pass. Seed imports cannot be dry-run, so
# --check-only validates the metadata and skips the data (and skips the
# permission-set assignment below).
for key in ${OFFERINGS[@]+"${OFFERINGS[@]}"}; do
  manifest="scripts/offerings/$key.manifest"
  records=(); seeds=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    kind="${line%%:*}"; val="${line#*:}"
    kind="$(echo "$kind" | tr -d '[:space:]')"
    val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$val" ] && continue
    case "$kind" in
      cmdt) matched=0
            for f in $val; do [ -f "$f" ] && { records+=("$f"); matched=1; }; done
            if [ "$matched" -eq 0 ]; then
              echo "$manifest: '$val' matches no file" >&2; exit 2
            fi ;;
      seed) [ -f "$val" ] || { echo "$manifest: seed file '$val' not found" >&2; exit 2; }
            seeds+=("$val") ;;
      *)    echo "$manifest: unknown line kind '$kind'" >&2; exit 2 ;;
    esac
  done < "$manifest"
  [ ${#records[@]} -gt 0 ] && \
    deploy_records "Offering pack '$key': custom metadata records (${#records[@]} files)" "${records[@]}"
  if [ "$CHECK_ONLY" -eq 0 ]; then
    [ ${#seeds[@]} -gt 0 ] && ensure_seed_access
    for sf_file in ${seeds[@]+"${seeds[@]}"}; do
      echo ""
      echo "==> Offering pack '$key': seed $sf_file"
      seed_import "$sf_file"
    done
  elif [ ${#seeds[@]} -gt 0 ]; then
    echo "    --check-only: ${#seeds[@]} seed file(s) for '$key' not imported"
  fi
done

if [ "$WITH_DEMO" -eq 1 ]; then
  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "    --check-only: demo data not loaded"
  else
    ensure_seed_access
    echo ""
    echo "==> Synthetic demo data"
    # Demo rows have no unique key; the Is_Synthetic__c tag is the marker.
    rc=0; python3 scripts/seed-precheck.py --synthetic "$TARGET_ORG" || rc=$?
    case "$rc" in
      0)  # --i-understand-this-writes-to-org is that script's own second
          # confirmation; passing --with-demo-data is the explicit opt-in.
          python3 scripts/seed-synthetic-data.py --load --org "$TARGET_ORG" \
            --i-understand-this-writes-to-org "$TARGET_ORG" ;;
      10) echo "    already loaded, skipping demo data (any existing synthetic" ;
          echo "    row counts; a partial demo set is not detected)" ;;
      *)  echo "ERROR: demo-data pre-check failed (exit $rc); not loading." >&2; exit 1 ;;
    esac
  fi
fi

if [ "$SEED_PARTIAL" -eq 1 ]; then
  echo ""
  echo "NOTE: at least one seed file was only partly loaded and was skipped (see the"
  echo "warning above). The install otherwise completed."
fi

if [ "$WITH_AGENT" -eq 1 ]; then
  deploy "Optional  Agentforce (bots, genAiPlugins) -- needs Agentforce provisioned" \
    bots genAiPlugins
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo ""
  echo "==> --check-only: validated against $TARGET_ORG, nothing was changed."
  exit 0
fi

if [ "$RUN_TESTS" -eq 1 ]; then
  echo ""
  echo "==> Running all local Apex tests"
  sf apex run test --target-org "$TARGET_ORG" --test-level RunLocalTests \
    --wait 30 --result-format human --code-coverage
fi

cat <<MANUAL

========================================================================
Deployed. Finish setup inside the app.
========================================================================
Open the GTM Offerings app > Settings tab > Setup. It checks this org,
shows what is done and what is left, and does what it can in one click.
Re-check re-reads the org. Nothing else needs to be done from here.

  - After any deploy that touches experiences/, publish the site:
    sf community publish -n "GTM" (a deploy updates the DRAFT only).
  - If you cannot see the Settings tab yet, your user needs a GTM
    permission set (docs/runbooks/gtm-offerings-install.md, section 6).
  - Offering packs: --with-offering <key> (optional).
  - API keys are optional; only the GUS chat assistant uses one.

Then walk docs/runbooks/fresh-org-deploy.md's verification checklist. It
is the only thing that proves any of this actually works.
MANUAL
