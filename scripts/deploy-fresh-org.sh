#!/usr/bin/env bash
#
# Rebuild the whole Migration Accelerator solution in an org that has never
# seen it.
#
# scripts/deploy.sh is the incremental one: it pushes the eleven directories
# that change day to day into an org that already has the rest. This script is
# the other job -- the one the expiring dev org made necessary. It deploys
# EVERY directory under force-app/, in an order chosen so that nothing is ever
# asked to resolve a reference to something that has not been deployed yet, and
# it stops at the first pass that fails rather than carrying on and leaving a
# half-built org that is harder to diagnose than an empty one.
#
# It cannot do the whole job. Experience Cloud sites, guest profiles, queue
# membership, the API key and the CMS channel are org state, not metadata, and
# they are listed -- all of them, in the order they must happen -- in
# docs/runbooks/fresh-org-deploy.md. Read that first; this script is step 4 of
# it, not the whole thing.
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
#
set -euo pipefail

TARGET_ORG="${1:-}"
shift || true

RUN_TESTS=0; CHECK_ONLY=0; WITH_PROFILES=0; WITH_AGENT=0
for arg in "$@"; do
  case "$arg" in
    --run-tests)     RUN_TESTS=1 ;;
    --check-only)    CHECK_ONLY=1 ;;
    --with-profiles) WITH_PROFILES=1 ;;
    --with-agent)    WITH_AGENT=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET_ORG" ]; then
  cat >&2 <<'USAGE'
Usage: scripts/deploy-fresh-org.sh <org-alias> [--run-tests] [--check-only]
                                   [--with-profiles] [--with-agent]

No org alias is assumed on purpose. Deploying a whole solution into the wrong
org is the one mistake this script must never make possible.
USAGE
  exit 1
fi

cd "$(dirname "$0")/.."
SRC=force-app/main/default
DRY=""
[ "$CHECK_ONLY" -eq 1 ] && DRY="--dry-run"

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
deploy "Pass 1/8  schema (objects, fields, custom settings, platform events, CMDT types)" \
  objects

# 2. Callout and CSP allow-lists, and custom labels. Apex that calls out will
#    compile without the allow-lists but fail at runtime; Apex/LWC that
#    references System.Label.X or {i18n}X compiles without labels existing
#    but is wrong at runtime. None of the three depend on anything else.
deploy "Pass 2/8  callout allow-lists + custom labels (remote sites, CSP trusted sites, labels)" \
  remoteSiteSettings cspTrustedSites labels

# 3. Code. Apex compiles against the schema from pass 1; the trigger compiles
#    against the classes beside it; LWCs import the @AuraEnabled methods.
deploy "Pass 3/8  code (Apex classes, triggers, Lightning web components)" \
  classes triggers lwc

# 4. Custom metadata RECORDS. Deployed on their own, after their types, and
#    retried: bundling records with ~65 other components has been observed to
#    fail with a generic UNKNOWN_EXCEPTION on content that deploys cleanly by
#    itself. That is why this is its own pass rather than part of pass 1.
echo ""
echo "==> Pass 4/8  custom metadata records (the instrument, platforms, pairs, offering)"
CMDT_OK=0
for i in 1 2 3 4; do
  echo "    attempt $i/4..."
  if sf project deploy start --source-dir "$SRC/customMetadata" \
       --target-org "$TARGET_ORG" --wait 30 $DRY; then CMDT_OK=1; break; fi
  sleep 10
done
if [ "$CMDT_OK" -ne 1 ]; then
  cat <<'CMDTFAIL'

Pass 4 failed after 4 attempts. Read the error above before retrying: if it
names a DeveloperName rather than a field or a type, this is the consecutive-
underscore risk documented in docs/runbooks/fresh-org-deploy.md. The fix is:

    python3 scripts/rename-pair-keys.py --apply
    python3 scripts/build-instrument.py
    ./scripts/deploy-fresh-org.sh <org-alias>

CMDTFAIL
  exit 1
fi

# 5. UI surfaces. FlexiPages draw the LWCs from pass 3 and sit on the objects
#    from pass 1; tabs point at FlexiPages and LWCs; apps list tabs. Strictly
#    in that order.
deploy "Pass 5/8  UI (managed content types, flexipages, tabs, apps, layouts)" \
  managedContentTypes flexipages tabs applications layouts

# 6. Automation. The approval process names three field updates by name; those
#    field updates live in workflows/ and must exist first or the approval
#    process is rejected. The queue owns GTM_Readout__c and Case records, so it
#    needs pass 1.
deploy "Pass 6/8  automation (workflow field updates, approval process, queue, flows)" \
  workflows approvalProcesses queues flows

# 7. Access. Permission sets grant on classes (pass 3), objects and fields
#    (pass 1), CMDT types (pass 1), tabs and apps (pass 5) -- so they are last
#    of the required passes, not first.
if [ "$WITH_PROFILES" -eq 1 ]; then
  deploy "Pass 7/8  access (permission sets, profiles)" permissionsets profiles
else
  deploy "Pass 7/8  access (permission sets)" permissionsets
  echo "    profiles/ skipped. Pass --with-profiles only if you have read the"
  echo "    note at the top of this script and want standard profiles changed."
fi

# 8. Experience Cloud. LAST, and the one pass that can fail for a reason that
#    is not in this repo: an ExperienceBundle updates a site's draft, it does
#    not create the site. Both sites must already exist in the target org, by
#    exactly these names and URL prefixes, or this pass fails.
deploy "Pass 8/8  Experience Cloud site content (GTM_Accelerator1, GTM_Story1)" \
  experiences

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
Deployed. The org is NOT working yet.
========================================================================
Metadata is only half of this solution. The rest is org state, which no
deploy can carry. docs/runbooks/fresh-org-deploy.md has all of it in the
order it must happen; the short version is:

  - Publish both Experience Cloud sites. A deploy updates the DRAFT only.
    Nothing you just deployed is live on either site until you open
    Experience Builder and press Publish.
  - Activate both sites (Setup > Digital Experiences > All Sites).
  - Assign GTM_Assessment_Guest to the GTM Accelerator site's guest user
    profile, and GTM_Story_Guest to the GTM Story site's.
  - Assign GTM_Config_Manager to every rep, and GTM_Config_View_All to
    whoever should see everyone's links.
  - Put someone in the GTM_Readout_Triage queue, or unassigned readouts
    land where nobody sees them.
  - Set every rep's Manager field. The approval process routes to the
    owner's manager and a rep with no manager cannot submit at all.
  - Enable Page Access on the /readout and /assessment pages for the
    guest user (Experience Builder > Settings > ... > Public Access).
  - Put the Anthropic API key in Setup > Custom Settings > GTM Agent
    Settings > Manage > New (org default). It is not in this repo and
    never will be.
  - Point the two org-self-callout remote sites at THIS org's My Domain.
  - Run ./scripts/setup-cms-workspace.sh $TARGET_ORG, then set
    GTM_Offering__mdt.Migration_Accelerator.CMS_Channel_Id__c.

Then walk docs/runbooks/fresh-org-deploy.md's verification checklist. It
is the only thing that proves any of this actually works.
MANUAL
