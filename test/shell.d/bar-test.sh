#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Omarchy CPU replaces the Quickshell bar with waybar. omarchy-bar is now a
# lifecycle shim (start/stop/restart/reload/toggle/status) and absorbs the
# legacy Quickshell layout verbs, which migrations and the menu still call.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/calls.log"
running_flag="$test_tmp/waybar-running"
mkdir -p "$stub_bin"
touch "$log_file"

cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
[[ -e $OMARCHY_TEST_RUNNING_FLAG ]]
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$OMARCHY_TEST_LOG"
[[ -e $OMARCHY_TEST_RUNNING_FLAG ]] || exit 1
[[ $* == "-x waybar" ]] && rm -f "$OMARCHY_TEST_RUNNING_FLAG"
exit 0
SH

cat >"$stub_bin/setsid" <<'SH'
#!/bin/bash
printf 'setsid %s\n' "$*" >>"$OMARCHY_TEST_LOG"
touch "$OMARCHY_TEST_RUNNING_FLAG"
SH

# A real waybar on PATH satisfies the shim's omarchy-cmd-present check.
cat >"$stub_bin/waybar" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin"/*

run_bar() {
  OMARCHY_TEST_LOG="$log_file" OMARCHY_TEST_RUNNING_FLAG="$running_flag" \
    PATH="$stub_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-bar" "$@"
}

if run_bar status >/dev/null 2>&1; then
  fail "bar status reports a stopped waybar with a non-zero exit"
fi
pass "bar status reports a stopped waybar with a non-zero exit"

run_bar start
grep -Fqx 'setsid -f waybar' "$log_file" || fail "bar start launches waybar detached" "$(cat "$log_file")"
pass "bar start launches waybar detached"

run_bar status >/dev/null || fail "bar status sees the started waybar"
pass "bar status sees the started waybar"

run_bar start
[[ $(grep -Fcx 'setsid -f waybar' "$log_file") == 1 ]] ||
  fail "bar start leaves a running waybar alone" "$(cat "$log_file")"
pass "bar start leaves a running waybar alone"

run_bar reload
grep -Fqx 'pkill -SIGUSR2 -x waybar' "$log_file" || fail "bar reload signals waybar to re-read its config" "$(cat "$log_file")"
pass "bar reload signals waybar to re-read its config"

run_bar toggle
grep -Fqx 'pkill -SIGUSR1 -x waybar' "$log_file" || fail "bar toggle flips visibility on a running waybar" "$(cat "$log_file")"
pass "bar toggle flips visibility on a running waybar"

run_bar stop
grep -Fqx 'pkill -x waybar' "$log_file" || fail "bar stop kills waybar" "$(cat "$log_file")"
if run_bar status >/dev/null 2>&1; then
  fail "bar stop leaves waybar stopped"
fi
pass "bar stop kills waybar"

run_bar toggle
[[ $(grep -Fcx 'setsid -f waybar' "$log_file") == 2 ]] ||
  fail "bar toggle starts waybar when it is not running" "$(cat "$log_file")"
pass "bar toggle starts waybar when it is not running"

# Migration 1786279107 and the style menu still call the Quickshell-era layout
# verbs; the shim must absorb them without failing those callers.
for verb in use reset defaults position transparent put move set; do
  run_bar "$verb" some-arg 2>/dev/null ||
    fail "bar absorbs the legacy '$verb' verb for old callers"
done
pass "bar absorbs the legacy Quickshell layout verbs"

if run_bar frobnicate 2>/dev/null; then
  fail "bar rejects unknown verbs"
fi
pass "bar rejects unknown verbs"
