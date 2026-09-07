#!/usr/bin/env bash
# Every static and live check, in one command.
#
# The static checks read the repo; the live ones ask the org, and are skipped
# with --static when there is no org to ask (CI on a pull request, say).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${SF_TARGET_ORG:-gtm-dev}"
STATIC_ONLY=0
[ "${1:-}" = "--static" ] && STATIC_ONLY=1

fails=0
run() { echo; echo "── $1 ─────────────────────────────────"; shift; "$@" || fails=$((fails+1)); }

run "seed content contract"  python3 "$ROOT/scripts/check-content-contract.py"
run "component references"   python3 "$ROOT/scripts/check-references.py"

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
