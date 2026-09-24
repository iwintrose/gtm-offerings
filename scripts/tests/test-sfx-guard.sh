#!/usr/bin/env bash
# Offline self-test for scripts/lib/sfx. A stub `sf` first on PATH records its
# argv; the stub log is the oracle for "no sf call happened". No org, no network.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SFX="$ROOT/scripts/lib/sfx"
T="$(mktemp -d "${TMPDIR:-/tmp}/sfx-test.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home"
LOG="$T/sf.log"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 0\n' "$LOG" > "$T/bin/sf"; chmod +x "$T/bin/sf"
export SFX_SELFTEST=1 PATH="$T/bin:$PATH" HOME="$T/home" TMPDIR="$T"
unset SF_TARGET_ORG SF_GUARD_COUNT_FILE SF_GUARD_SFX SF_GUARD_ALLOW_FLAG GTM_ALLOW_PRODUCTION SF_GUARD_WARN_AT SF_HOME SF_GUARD_PROD_ALIASES

pass=0; failn=0
ok() { pass=$((pass+1)); }
bad() { failn=$((failn+1)); echo "FAIL: $1"; }
calls() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
reset() { rm -f "$LOG"; }
# run <name> <expect: ok|refuse> <expected stub calls> -- sfx args...
t() {
  name="$1"; want="$2"; n="$3"; shift 3; reset
  out="$("$@" 2>&1)"; rc=$?
  if [ "$want" = ok ] && [ "$rc" -ne 0 ]; then bad "$name (rc=$rc): $out"; return; fi
  if [ "$want" = refuse ] && [ "$rc" -eq 0 ]; then bad "$name (expected refusal)"; return; fi
  [ "$(calls)" = "$n" ] || { bad "$name (stub calls $(calls), want $n)"; return; }
  ok; LAST="$out"
}
S() { "$SFX" --session -- "$SFX" "$@"; }

t "gtm-dev refused" refuse 0 S project deploy start -o gtm-dev
t "GTM-DEV refused" refuse 0 S project deploy start -o GTM-DEV
t "Gtm-Dev refused" refuse 0 S project deploy start --target-org Gtm-Dev
t "--target-org= refused" refuse 0 S project deploy start --target-org=gtm-dev
t "-ogtm-dev refused" refuse 0 S project deploy start -ogtm-dev
t "flag only refused" refuse 0 "$SFX" --session --allow-production -- "$SFX" project deploy start -o gtm-dev
GTM_ALLOW_PRODUCTION=1 t "env only refused" refuse 0 S project deploy start -o gtm-dev
GTM_ALLOW_PRODUCTION=1 t "flag and env accepted" ok 1 "$SFX" --session --allow-production -- "$SFX" project deploy start -o gtm-dev
t "staging accepted" ok 1 S project deploy start -o gtm-staging
t "raw username refused" refuse 0 S data query -o someone@example.invalid
case "$LAST" in *someone@example.invalid*) bad "username leaked in output" ;; *) ok ;; esac
t "no org refused" refuse 0 S project deploy start
SF_TARGET_ORG=gtm-staging t "env org accepted" ok 1 S data query
SF_TARGET_ORG=gtm-dev t "env org gtm-dev refused" refuse 0 S data query
SF_GUARD_PROD_ALIASES=other-prod t "extra prod alias refused" refuse 0 S data query -o other-prod

mkdir -p "$T/home/.sf"
echo '{"orgs":{"gtm-dev":"fake@example.invalid","alias2":"fake@example.invalid","fine":"other@example.invalid"}}' > "$T/home/.sf/alias.json"
t "alias-file alias refused" refuse 0 S data query -o alias2
t "alias-file other alias ok" ok 1 S data query -o fine
rm -f "$T/home/.sf/alias.json"

# Exempt commands do run sf (stub sees 1 call) but are not counted.
t "local: project convert" ok 1 S project convert source
case "$LAST" in *"sf calls this run: 0"*) ok ;; *) bad "convert was counted: $LAST" ;; esac
t "local: --version" ok 1 S --version
case "$LAST" in *"sf calls this run: 0"*) ok ;; *) bad "--version was counted: $LAST" ;; esac

t "three calls counted" ok 3 "$SFX" --session -- bash -c "\"\$SF_GUARD_SFX\" data query -o gtm-staging; \"\$SF_GUARD_SFX\" data query -o gtm-staging; \"\$SF_GUARD_SFX\" project deploy start -o gtm-staging"
case "$LAST" in *"sf calls this run: 3"*) ok ;; *) bad "count summary: $LAST" ;; esac
case "$LAST" in *gtm-staging*) bad "summary leaked args" ;; *) ok ;; esac
case "$LAST" in *WARNING*) bad "unexpected warning at 3" ;; *) ok ;; esac
SF_GUARD_WARN_AT=2 t "warn over budget" ok 3 "$SFX" --session -- bash -c "for i in 1 2 3; do \"\$SF_GUARD_SFX\" data query -o gtm-staging; done"
case "$LAST" in *WARNING*) ok ;; *) bad "no warning at 3 > 2" ;; esac
SF_GUARD_WARN_AT=2 t "no warn at budget" ok 2 "$SFX" --session -- bash -c "for i in 1 2; do \"\$SF_GUARD_SFX\" data query -o gtm-staging; done"
case "$LAST" in *WARNING*) bad "warned at 2" ;; *) ok ;; esac
SF_GUARD_WARN_AT=abc t "bad WARN_AT fails closed" refuse 0 S data query -o gtm-staging
SF_GUARD_WARN_AT=abc "$SFX" --session -- true >/dev/null 2>&1; [ $? -eq 70 ] && ok || bad "WARN_AT=abc not exit 70"

# Fail closed
t "no session" refuse 0 "$SFX" project deploy start -o gtm-staging
"$SFX" project deploy start -o gtm-staging >/dev/null 2>&1; [ $? -eq 70 ] && ok || bad "no session not exit 70"
reset; ro="$T/ro-count"; : > "$ro"; chmod 444 "$ro"
SF_GUARD_COUNT_FILE="$ro" SF_GUARD_SFX="$SFX" "$SFX" project deploy start -o gtm-staging >/dev/null 2>&1; rc=$?
if [ "$(id -u)" = "0" ]; then ok; else { [ $rc -eq 70 ] && [ "$(calls)" = 0 ] && ok || bad "read-only counter (rc=$rc)"; }; fi

# Entry scripts (stub sf only; refusals happen before any call)
reset
"$ROOT/scripts/check-all.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok || bad "check-all no args not exit 2"
"$ROOT/scripts/check-all.sh" --org gtm-dev --static >/dev/null 2>&1
[ "$(calls)" = 0 ] && ok || bad "check-all --static made sf calls"
mkdir -p "$T/scratch/scripts"; cp "$ROOT/scripts/check-all.sh" "$T/scratch/scripts/"
"$T/scratch/scripts/check-all.sh" --static >/dev/null 2>&1; [ $? -eq 70 ] && ok || bad "missing sfx not exit 70"
SF_GUARD_COUNT_FILE= "$ROOT/scripts/lib/sfx" --session -- "$SFX" data query -o gtm-dev >/dev/null 2>&1; [ "$(calls)" = 0 ] && ok || bad "stub called for gtm-dev"

echo "sfx guard self-test: $pass passed, $failn failed"
[ "$failn" = 0 ]
