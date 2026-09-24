#!/usr/bin/env bash
# Offline self-check: scripts/deploy.sh must set IS_PROD_ALIAS=1 for both
# gtm-prod and the legacy gtm-dev alias (case-insensitive), and 0 for gtm-staging.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Extract the alias case-block from deploy.sh and run it against each alias.
block="$(awk '/^IS_PROD_ALIAS=0/{f=1} f{print} /^esac/{if(f) exit}' "$ROOT/scripts/deploy.sh")"
[ -n "$block" ] || { echo "FAIL: prod guard block not found in deploy.sh"; exit 1; }
fail=0
check() {
  local got
  got="$(TARGET_ORG="$1" bash -c "$block"'; echo $IS_PROD_ALIAS')"
  if [ "$got" != "$2" ]; then echo "FAIL: $1 -> IS_PROD_ALIAS=$got (want $2)"; fail=1; fi
}
check gtm-prod 1; check GTM-PROD 1; check gtm-dev 1; check gtm-staging 0; check other 0
[ "$fail" = 0 ] && echo "deploy.sh prod guard OK"
exit "$fail"
