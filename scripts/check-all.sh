#!/usr/bin/env bash
# Every static and live check, in one command.
#
# The static checks read the repo; the live ones ask the org, and are skipped
# with --static when there is no org to ask (CI on a pull request, say).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Live checks go through the sfx guard (scripts/lib/sfx): there is NO default org.
SFX="$ROOT/scripts/lib/sfx"
[ -x "$SFX" ] || { echo "sfx guard helper missing: refusing to run" >&2; exit 70; }
[ -n "${SF_GUARD_COUNT_FILE:-}" ] || exec "$SFX" --session -- "$0" "$@"

ORG="${SF_TARGET_ORG:-}"
STATIC_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --static) STATIC_ONLY=1 ;;
    --allow-production) ;;  # consumed by the sfx session; a no-op here
    --org) shift; ORG="${1:-}" ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
if [ "$STATIC_ONLY" = "0" ] && [ -z "$ORG" ]; then
  echo "Usage: scripts/check-all.sh --static | --org <alias> [--allow-production]" >&2
  echo "No org given and no default: pass --org <alias> (or set SF_TARGET_ORG). Agent work uses gtm-staging." >&2
  exit 2
fi

fails=0
run() { echo; echo "── $1 ─────────────────────────────────"; shift; "$@" || fails=$((fails+1)); }

run "seed content contract"  python3 "$ROOT/scripts/check-content-contract.py"
run "component references"   python3 "$ROOT/scripts/check-references.py"
run "deploy.sh prod guard"     bash "$ROOT/scripts/check-deploy-prod-guard.sh"

# The self-tests call check-all.sh themselves; SFX_SELFTEST stops the recursion.
if [ -z "${SFX_SELFTEST:-}" ]; then
  run "sfx guard self-test"    env SFX_SELFTEST=1 bash "$ROOT/scripts/tests/test-sfx-guard.sh"
  run "sf_guard python tests"  env SFX_SELFTEST=1 python3 -m unittest discover -s "$ROOT/scripts/tests" -p "test_sf_guard.py"
fi

HARNESS="$("$ROOT/scripts/lwc-node-harness.sh")"
run "configurator bindings"  node "$HARNESS/check-configurator-bindings.mjs" "$ROOT"

if [ "$STATIC_ONLY" = "0" ]; then
  run "page + field order (every page)" node "$HARNESS/check-page-order.mjs" "$ROOT" "$ORG"

  for pair in "migration-accelerator configurator" "migration-accelerator story" \
              "migration-accelerator offerings-listing" "gtm offerings-page" "gtm industry-chooser"; do
    # shellcheck disable=SC2086
    run "live: $pair" node "$HARNESS/check-live-page-contract.mjs" $pair "$ORG"
  done
fi

echo
if [ "$fails" -gt 0 ]; then echo "FAILED: $fails check(s)"; exit 1; fi
echo "All checks passed."
