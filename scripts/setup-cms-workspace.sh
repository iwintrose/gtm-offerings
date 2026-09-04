#!/usr/bin/env bash
#
# Creates the "GTM Offerings" Salesforce CMS Workspace that the
# ManagedContentType schema in force-app/main/default/managedContentTypes/
# is authored against (ma_industry_story, ma_faq_item, ma_story_setting).
#
# Why this is a separate script instead of part of deploy.sh: CMS Workspaces
# (ManagedContentSpace) have no Metadata API representation -- they aren't a
# deployable component type, so `sf project deploy start` can never create
# one. This uses the Connect REST API directly instead, the same way an
# admin creating a Workspace in Setup ultimately calls it under the hood.
# Idempotent: if a Workspace with this apiName already exists, it prints
# that Workspace's Id and exits 0 rather than creating a duplicate.
#
# Usage:
#   ./scripts/setup-cms-workspace.sh <org-alias-or-username>
#
# Prerequisites:
#   - Already authenticated to the target org (sf org login web --alias ...)
#   - The managedContentTypes/ metadata already deployed (run deploy.sh first)
#   - jq installed
#
set -euo pipefail

TARGET_ORG="${1:-}"
WORKSPACE_API_NAME="GTM_Offerings"
WORKSPACE_NAME="GTM Offerings"
WORKSPACE_DESCRIPTION="Editorial content for GTM Offerings public pages -- industry story blocks, FAQ, and per-offering site defaults."

if [ -z "$TARGET_ORG" ]; then
  echo "Usage: $0 <org-alias-or-username>"
  echo ""
  echo "No org alias given, and no default is assumed on purpose --"
  echo "creating this in the wrong org silently is the one mistake this"
  echo "script should never make possible."
  exit 1
fi

ORG_INFO=$(sf org display --target-org "$TARGET_ORG" --json)
INSTANCE_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')
API_VERSION=$(echo "$ORG_INFO" | jq -r '.result.apiVersion')
ACCESS_TOKEN=$(sf org auth show-access-token --target-org "$TARGET_ORG" --json | jq -r '.result.accessToken // .accessToken')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "Could not resolve an access token for $TARGET_ORG -- is it authenticated?"
  echo "  sf org login web --alias $TARGET_ORG"
  exit 1
fi

BASE_URL="$INSTANCE_URL/services/data/v$API_VERSION"

echo "==> Checking for an existing '$WORKSPACE_NAME' CMS Workspace..."
EXISTING_ID=$(curl -sS "$BASE_URL/connect/cms/spaces" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  | jq -r --arg name "$WORKSPACE_API_NAME" '.spaces[] | select(.apiName == $name) | .id' \
  | head -n1)

if [ -n "$EXISTING_ID" ]; then
  echo "Already exists: $EXISTING_ID -- nothing to do."
  exit 0
fi

echo "==> Not found. Creating it..."
CREATE_BODY=$(jq -n \
  --arg name "$WORKSPACE_NAME" \
  --arg apiName "$WORKSPACE_API_NAME" \
  --arg description "$WORKSPACE_DESCRIPTION" \
  '{name: $name, apiName: $apiName, description: $description, defaultLanguage: "en_US"}')

RESPONSE=$(curl -sS -X POST "$BASE_URL/connect/cms/spaces" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CREATE_BODY")

NEW_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$NEW_ID" ]; then
  echo "Creation failed:"
  echo "$RESPONSE" | jq .
  exit 1
fi

echo "==> Created: $NEW_ID"
echo ""
echo "The 3 GTM Offerings content types are usable in it immediately -- no"
echo "separate 'enable content type for this workspace' step exists (verified"
echo "by creating a test content record against it directly after creation)."
echo ""
echo "Manual step this script can't do for you: assign CMS Workspace access"
echo "(Contributor/Publisher) to whoever should author this content --"
echo "Setup > Digital Experiences > CMS Workspaces > $WORKSPACE_NAME > Access."
