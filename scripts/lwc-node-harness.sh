#!/usr/bin/env bash
# Runs a node script against the LWC JS modules with 'c/...' imports resolvable.
# Node resolves bare specifiers from the *real* path of a file, so the modules
# are copied rather than linked. Regenerated on every run: it is a scratch
# mirror, never a source of truth.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${LWC_HARNESS_DIR:-${TMPDIR:-/tmp}/lwc-harness}"
rm -rf "$DEST"; mkdir -p "$DEST/node_modules/c"
printf '{ "name": "c", "type": "module", "exports": { "./*": "./*.js" } }\n' > "$DEST/node_modules/c/package.json"
printf '{ "type": "module" }\n' > "$DEST/package.json"
for d in "$ROOT"/force-app/main/default/lwc/*/; do
  n="$(basename "$d")"
  [ -f "$d$n.js" ] && cp "$d$n.js" "$DEST/node_modules/c/$n.js"
done
# Scripts that import 'c/...' have to live here too: node resolves bare
# specifiers from a file's real path, not from the directory it was invoked in.
cp "$ROOT"/scripts/*.mjs "$DEST"/ 2>/dev/null || true
echo "$DEST"
