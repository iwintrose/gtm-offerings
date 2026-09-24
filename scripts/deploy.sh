#!/usr/bin/env bash
#
# Deploys GTM Offerings (this repo's force-app/ tree) to any Salesforce
# org you're already authenticated to with the Salesforce CLI (`sf`).
#
# This repo is standard Salesforce DX source format -- nothing here is tied
# to any one org. Moving to a new org (a fresh dev org, a sandbox, whoever's
# instance) is: authenticate the CLI to it, then run this script.
#
# Usage:
#   ./scripts/deploy.sh <org-alias-or-username> [--run-tests] [--with-agent]
#
# Examples:
#   ./scripts/deploy.sh my-new-org
#   ./scripts/deploy.sh my-new-org --run-tests
#   ./scripts/deploy.sh my-new-org --run-tests --with-agent
#
# Options:
#   --run-tests   run local Apex tests as part of Pass 1
#   --with-agent  also deploy bots/ and genAiPlugins/ (OFF by default: they
#                 need Agentforce provisioned on the org and fail outright
#                 when it is not -- see the EXCLUDE_DIRS note below, which
#                 this flag drives under the hood)
#
# Prerequisites:
#   - Salesforce CLI installed (`npm install -g @salesforce/cli` or see
#     https://developer.salesforce.com/tools/salesforcecli)
#   - Authenticated to the target org, e.g.:
#       sf org login web --alias my-new-org
#     or, for a JWT/CI flow:
#       sf org login jwt --client-id <consumer-key> --jwt-key-file <path> \
#         --username <username> --alias my-new-org
#
set -euo pipefail

TARGET_ORG="${1:-}"
shift || true

RUN_TESTS=0; WITH_AGENT=0
for arg in "$@"; do
  case "$arg" in
    --run-tests)  RUN_TESTS=1 ;;
    --with-agent) WITH_AGENT=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET_ORG" ]; then
  echo "Usage: $0 <org-alias-or-username> [--run-tests] [--with-agent]"
  echo ""
  echo "No org alias given, and no default is assumed on purpose --"
  echo "deploying to the wrong org silently is the one mistake this"
  echo "script should never make possible."
  exit 1
fi

cd "$(dirname "$0")/.."

# Pass 1's --source-dir list is built from whatever top-level folders
# actually exist under force-app/main/default/ (minus customMetadata, which
# is its own pass -- see below), instead of a hand-maintained list. A fixed
# list silently drifts as the repo grows -- it did: flexipages, flows,
# bots, genAiPlugins, labels, profiles, and remoteSiteSettings had all been
# added to the repo without ever being added here, so a from-scratch deploy
# would have silently skipped every flow, record page, and remote site
# setting the org actually needs.
#
# EXCLUDE_DIRS (optional env var, comma-separated top-level folder names)
# is the one deliberate escape hatch from that everything-by-default rule,
# for a directory whose CONTENT the org cannot accept at all -- not a
# validation error, a hard "this feature is not provisioned here". Confirmed
# against gtm-prod: bots/ and genAiPlugins/ (the GTM Configurator Assistant
# Agentforce action) fail deploy with "Not available for deploy for this
# organization" -- Agentforce/Bots is not provisioned on this org, confirmed
# separately by `SELECT ... FROM BotDefinition` itself failing with
# INVALID_TYPE. That is an edition/licensing fact about one org, not a
# defect in the source, so the fix is not to remove bots/genAiPlugins from
# the repo -- another instance with Agentforce provisioned needs them.
#
# --with-agent (OFF by default, mirroring deploy-fresh-org.sh) is the
# dedicated opt-in for exactly those two directories: when absent, it feeds
# bots,genAiPlugins into the same EXCLUDE_DIRS mechanism below rather than
# duplicating a second skip list. EXCLUDE_DIRS itself remains a free-standing
# escape hatch for any other directory an org can't accept, e.g.:
#   EXCLUDE_DIRS=someOtherDir ./scripts/deploy.sh my-org
_AGENT_EXCLUDE=""
if [ "$WITH_AGENT" -eq 0 ]; then
  _AGENT_EXCLUDE="bots,genAiPlugins"
fi
_ALL_EXCLUDES="${EXCLUDE_DIRS:-}"
if [ -n "$_AGENT_EXCLUDE" ]; then
  if [ -n "$_ALL_EXCLUDES" ]; then
    _ALL_EXCLUDES="${_ALL_EXCLUDES},${_AGENT_EXCLUDE}"
  else
    _ALL_EXCLUDES="$_AGENT_EXCLUDE"
  fi
fi
# gtm-prod is treated as PRODUCTION (CLAUDE.md section 1). Matched on the alias
# as typed; a raw username for that org would not match, so use the alias.
# NOTE: test-fixtures/ (Test Offering) is a separate packageDirectory and is
# never listed here, so this script cannot ship it.
IS_PROD_ALIAS=0
case "$(printf '%s' "$TARGET_ORG" | tr '[:upper:]' '[:lower:]')" in
  # TODO: drop gtm-dev once the owner confirms the old alias is gone.
  gtm-prod|gtm-dev) IS_PROD_ALIAS=1 ;;
esac
SOURCE_DIRS=()
IFS=',' read -ra _EXCLUDED <<< "$_ALL_EXCLUDES"
for d in force-app/main/default/*/; do
  name="$(basename "$d")"
  if [ "$name" = "customMetadata" ]; then
    continue
  fi
  skip=0
  for x in "${_EXCLUDED[@]+"${_EXCLUDED[@]}"}"; do
    if [ "$name" = "$x" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" -eq 0 ] && [ "$name" = "layouts" ] && [ "$IS_PROD_ALIAS" -eq 1 ]; then
    # PRODUCTION GUARD. The four Opportunity-* layouts are complete layouts for
    # a STANDARD object: deploying them REPLACES the target org's own Opportunity
    # layouts. In this repo they have had five foreign fields (MainCompetitors__c
    # and friends) stripped so they deploy to fresh orgs, which would remove
    # those fields from gtm-prod's live layouts. So for gtm-prod they are never
    # deployed; every other layout still is. See
    # docs/runbooks/gtm-offerings-install.md (Production guard).
    echo "==> PRODUCTION GUARD ($TARGET_ORG): skipping the four Opportunity-* layouts"
    for lf in force-app/main/default/layouts/*; do
      case "$(basename "$lf")" in
        Opportunity-*) ;;
        *) SOURCE_DIRS+=(--source-dir "$lf") ;;
      esac
    done
  elif [ "$skip" -eq 0 ]; then
    SOURCE_DIRS+=(--source-dir "force-app/main/default/$name")
  fi
done
if [ -n "$_ALL_EXCLUDES" ]; then
  echo "==> Excluding from this deploy: ${_ALL_EXCLUDES}"
fi
if [ "$WITH_AGENT" -eq 0 ]; then
  echo "    (bots/genAiPlugins skipped by default -- pass --with-agent to include them)"
fi

# Deployed in two passes, not one: bundling the GTM_Offering__mdt custom
# metadata TYPE and its seeded RECORD in the same transaction as everything
# else is unreliable (observed firsthand -- identical content that deploys
# cleanly on its own intermittently fails with a generic UNKNOWN_EXCEPTION
# when deployed together with ~65 other components at once). Deploying
# customMetadata/ as its own pass, after the type it depends on already
# exists from pass 1, avoids it every time.
echo "==> Pass 1/2: everything except custom metadata records"
if [ "$RUN_TESTS" -eq 1 ]; then
  echo "==> Running local Apex tests as part of the deploy"
  sf project deploy start \
    "${SOURCE_DIRS[@]}" \
    --target-org "$TARGET_ORG" \
    --test-level RunLocalTests \
    --wait 60
else
  sf project deploy start \
    "${SOURCE_DIRS[@]}" \
    --target-org "$TARGET_ORG" \
    --wait 60
  echo ""
  echo "Deployed without running tests. Re-run with --run-tests before"
  echo "trusting this in anything other than a scratch/dev org."
fi

echo ""
echo "==> Pass 2/2: custom metadata records (GTM_Offering__mdt seed data)"

# This specific step has been observed failing intermittently with a
# generic UNKNOWN_EXCEPTION even on unchanged, previously-successful
# content -- every time it happened tonight, a bare retry cleared it within
# a couple of attempts. So: retry automatically instead of making a human
# notice a failure and re-run the command by hand. Only surface this as a
# real problem once retries are actually exhausted.
CMDT_ATTEMPTS=4
CMDT_OK=0
for i in $(seq 1 "$CMDT_ATTEMPTS"); do
  echo "    attempt $i/$CMDT_ATTEMPTS..."
  if sf project deploy start \
    --source-dir force-app/main/default/customMetadata \
    --target-org "$TARGET_ORG" \
    --wait 30; then
    CMDT_OK=1
    break
  fi
  sleep 10
done

if [ "$CMDT_OK" -ne 1 ]; then
  echo ""
  echo "Pass 2 failed after $CMDT_ATTEMPTS attempts. Pass 1 (everything else)"
  echo "already succeeded -- this is the only piece left, and it's one record"
  echo "with three fields, faster to create by hand than to keep retrying:"
  echo "  Setup -> Custom Metadata Types -> GTM Offering -> Manage Records -> New"
  echo "    DeveloperName:    Migration_Accelerator"
  echo "    Offering_Key__c:  migration-accelerator"
  echo "    Label__c:         Migration Accelerator"
  echo "    Monthly/Annual Target__c: whatever the real targets are"
  exit 1
fi

echo ""
echo "==> Done. Manual steps this script can't do for you (see DEPLOYMENT.md):"
echo "    - Assign GTM_Config_Manager to whichever users should manage links"
echo "    - Assign GTM_Assessment_Guest to the target Experience Cloud site's Guest User profile"
echo "    - Activate + publish the Experience Cloud site in Setup > Digital Experiences"
echo "    - Edit the GTM_Offering__mdt 'Migration Accelerator' record's target"
echo "      values (Setup > Custom Metadata Types) -- the seeded numbers are placeholders"
echo "    - Optional, later: the GUS chat assistant is the only thing needing an API"
echo "      key. Set it in the GTM Offerings app > Settings tab; never in source"
echo "    - If this is the first CustomNotificationType in this org, confirm"
echo "      Setup > Notification Builder > in-app/mobile notifications is"
echo "      enabled -- a metadata deploy does not turn this on by itself."
