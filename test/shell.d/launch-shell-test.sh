#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The Quickshell supervisor is gone: the Omarchy CPU shell is waybar plus
# mako, and the launcher's job is to bring both up idempotently for
# omarchy-restart-shell and recovery paths.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-bar" <<'SH'
#!/bin/bash
printf 'bar %s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$fake_bin/pgrep" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-x" && ${2:-} == "mako" ]]; then
  [[ ${OMARCHY_TEST_MAKO_RUNNING:-0} == 1 ]] && exit 0
  exit 1
fi
exit 1
SH

cat >"$fake_bin/setsid" <<'SH'
#!/bin/bash
printf 'setsid %s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$fake_bin"/*

launch_log="$test_tmp/launch.log"

: >"$launch_log"
PATH="$fake_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" OMARCHY_TEST_MAKO_RUNNING=0 \
  "$ROOT/bin/omarchy-launch-shell" || fail "the shell launcher succeeds"
grep -Fqx 'bar start' "$launch_log" || fail "the launcher starts the bar"
grep -Fqx 'setsid -f mako' "$launch_log" || fail "the launcher spawns mako detached"
pass "the launcher brings up waybar and mako"

: >"$launch_log"
PATH="$fake_bin:$PATH" OMARCHY_TEST_LOG="$launch_log" OMARCHY_TEST_MAKO_RUNNING=1 \
  "$ROOT/bin/omarchy-launch-shell" || fail "the shell launcher succeeds with mako running"
grep -Fqx 'bar start' "$launch_log" || fail "the launcher still starts the bar"
if grep -Fq 'setsid -f mako' "$launch_log"; then
  fail "the launcher does not spawn a duplicate mako"
fi
pass "the launcher leaves a running mako alone"
