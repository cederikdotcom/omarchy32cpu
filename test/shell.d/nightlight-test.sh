#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Omarchy CPU drives the nightlight with wlsunset instead of hyprsunset.
# wlsunset has no IPC to query, so the toggle keeps a state file and a live
# process as the enabled state.

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home"
RUNNING="$TMPDIR/wlsunset-running"
LAUNCH_LOG="$TMPDIR/launch-log"
SHELL_LOG="$TMPDIR/omarchy-shell-log"
state_file="$TMPDIR/home/.local/state/omarchy/toggles/nightlight"

cat >"$TMPDIR/bin/pgrep" <<'SH'
#!/bin/bash
[[ -e $WLSUNSET_RUNNING ]]
SH

cat >"$TMPDIR/bin/pkill" <<'SH'
#!/bin/bash
[[ -e $WLSUNSET_RUNNING ]] || exit 1
rm -f "$WLSUNSET_RUNNING"
SH

cat >"$TMPDIR/bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$LAUNCH_LOG"
touch "$WLSUNSET_RUNNING"
SH

cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_SHELL_LOG"
SH

chmod +x "$TMPDIR/bin/pgrep" "$TMPDIR/bin/pkill" "$TMPDIR/bin/setsid" "$TMPDIR/bin/omarchy-shell"

nightlight_cli() {
  PATH="$TMPDIR/bin:$PATH" \
  HOME="$TMPDIR/home" \
  WLSUNSET_RUNNING="$RUNNING" \
  LAUNCH_LOG="$LAUNCH_LOG" \
  OMARCHY_SHELL_LOG="$SHELL_LOG" \
    "$ROOT/bin/omarchy-toggle-nightlight" "$@"
}

[[ $(nightlight_cli --status | jq -r .enabled) == "false" ]] || fail "nightlight status starts disabled"
pass "nightlight status starts disabled"

: >"$SHELL_LOG"
nightlight_cli >/dev/null
grep -q 'wlsunset -t 4000' "$LAUNCH_LOG" || fail "nightlight toggle launches wlsunset at the night temperature" "$(cat "$LAUNCH_LOG")"
pass "nightlight toggle launches wlsunset at the night temperature"

[[ -f $state_file ]] || fail "nightlight toggle records the enabled state"
pass "nightlight toggle records the enabled state"

grep -Fqx -- '-q nightlight refresh' "$SHELL_LOG" || fail "nightlight toggle nudges the shell nightlight service"
pass "nightlight toggle nudges the shell nightlight service"

status=$(nightlight_cli --status)
[[ $(jq -r .enabled <<<"$status") == "true" && $(jq -r .temperature <<<"$status") == "4000" ]] ||
  fail "nightlight status reports the running wlsunset as enabled" "$status"
pass "nightlight status reports the running wlsunset as enabled"

nightlight_cli >/dev/null
[[ ! -e $RUNNING ]] || fail "nightlight toggle kills wlsunset to restore daylight"
[[ ! -f $state_file ]] || fail "nightlight toggle clears the enabled state"
pass "nightlight toggle restores daylight from night light"

# A state file left behind by a crashed wlsunset must not read as enabled.
mkdir -p "$(dirname "$state_file")"
touch "$state_file"
rm -f "$RUNNING"
[[ $(nightlight_cli --status | jq -r .enabled) == "false" ]] ||
  fail "nightlight status treats a stale state file without a process as disabled"
rm -f "$state_file"
pass "nightlight status treats a stale state file without a process as disabled"
