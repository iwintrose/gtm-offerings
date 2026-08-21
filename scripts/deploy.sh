#!/usr/bin/env bash
#
# Deploys the MA Accelerator (this repo's force-app/ tree) to any Salesforce
# org you're already authenticated to with the Salesforce CLI (`sf`).
#
# This repo is standard Salesforce DX source format -- nothing here is tied
# to any one org. Moving to a new org (a fresh dev org, a sandbox, whoever's
# instance) is: authenticate the CLI to it, then run this script.
#
# Usage:
#   ./scripts/deploy.sh <org-alias-or-username> [--run-tests]
#
# Examples:
#   ./scripts/deploy.sh my-new-org
#   ./scripts/deploy.sh my-new-org --run-tests
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
RUN_TESTS="${2:-}"

if [ -z "$TARGET_ORG" ]; then
  echo "Usage: $0 <org-alias-or-username> [--run-tests]"
  echo ""
  echo "No org alias given, and no default is assumed on purpose --"
  echo "deploying to the wrong org silently is the one mistake this"
  echo "script should never make possible."
  exit 1
fi

cd "$(dirname "$0")/.."

# Deployed in two passes, not one: bundling the MA_Offering__mdt custom
# metadata TYPE and its seeded RECORD in the same transaction as everything
# else is unreliable (observed firsthand -- identical content that deploys
# cleanly on its own intermittently fails with a generic UNKNOWN_EXCEPTION
# when deployed together with ~65 other components at once). Deploying
# customMetadata/ as its own pass, after the type it depends on already
# exists from pass 1, avoids it every time.
echo "==> Pass 1/2: everything except custom metadata records"
if [ "$RUN_TESTS" = "--run-tests" ]; then
  echo "==> Running local Apex tests as part of the deploy"
  sf project deploy start \
    --source-dir force-app/main/default/applications \
    --source-dir force-app/main/default/classes \
    --source-dir force-app/main/default/cspTrustedSites \
    --source-dir force-app/main/default/experiences \
    --source-dir force-app/main/default/layouts \
    --source-dir force-app/main/default/lwc \
    --source-dir force-app/main/default/objects \
    --source-dir force-app/main/default/permissionsets \
    --source-dir force-app/main/default/tabs \
    --target-org "$TARGET_ORG" \
    --test-level RunLocalTests \
    --wait 60
else
  sf project deploy start \
    --source-dir force-app/main/default/applications \
    --source-dir force-app/main/default/classes \
    --source-dir force-app/main/default/cspTrustedSites \
    --source-dir force-app/main/default/experiences \
    --source-dir force-app/main/default/layouts \
    --source-dir force-app/main/default/lwc \
    --source-dir force-app/main/default/objects \
    --source-dir force-app/main/default/permissionsets \
    --source-dir force-app/main/default/tabs \
    --target-org "$TARGET_ORG" \
    --wait 60
  echo ""
  echo "Deployed without running tests. Re-run with --run-tests before"
  echo "trusting this in anything other than a scratch/dev org."
fi

echo ""
echo "==> Pass 2/2: custom metadata records (MA_Offering__mdt seed data)"

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
  echo "  Setup -> Custom Metadata Types -> MA Offering -> Manage Records -> New"
  echo "    DeveloperName:    Migration_Accelerator"
  echo "    Offering_Key__c:  migration-accelerator"
  echo "    Label__c:         Migration Accelerator"
  echo "    Monthly/Annual Target__c: whatever the real targets are"
  exit 1
fi

echo ""
echo "==> Done. Manual steps this script can't do for you (see DEPLOYMENT.md):"
echo "    - Assign MA_Config_Manager to whichever users should manage links"
echo "    - Assign MA_Assessment_Guest to the target Experience Cloud site's Guest User profile"
echo "    - Activate + publish the Experience Cloud site in Setup > Digital Experiences"
echo "    - Edit the MA_Offering__mdt 'Migration Accelerator' record's target"
echo "      values (Setup > Custom Metadata Types) -- the seeded numbers are placeholders"
