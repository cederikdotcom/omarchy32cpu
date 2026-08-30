#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
watch_pid=""

# The watcher forks delayed clamshell retries and the recovery loop. Orphaning
# those would leave them running against a deleted test tree.
stop_watcher() {
  local child descendants

  if [[ -n $watch_pid ]]; then
    descendants=$(pgrep -P "$watch_pid" 2>/dev/null || true)
    for child in $descendants; do
      descendants+=" $(pgrep -P "$child" 2>/dev/null || true)"
    done

    kill -KILL "$watch_pid" 2>/dev/null || true
    wait "$watch_pid" 2>/dev/null || true
    for child in $descendants; do
      kill -KILL "$child" 2>/dev/null || true
    done
    watch_pid=""
  fi

  return 0
}

cleanup() {
  stop_watcher
  rm -rf "$test_tmp"
}
trap cleanup EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

monitors_file="$test_tmp/monitors.json"
reload_log="$test_tmp/reload.log"
recovered="$test_tmp/recovered.json"
swaymsg_fail="$test_tmp/swaymsg-fails"

# The monitor list lives in a file so a reload can "fix" it mid-run.
cat >"$fake_bin/swaymsg" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-t" && ${2:-} == "get_outputs" ]]; then
  [[ -f $OMARCHY_TEST_SWAYMSG_FAIL_FLAG ]] && exit 1
  cat "$OMARCHY_TEST_MONITORS_FILE"
elif [[ ${1:-} == "reload" ]]; then
  printf 'reload\n' >>"$OMARCHY_TEST_RELOAD_LOG"
  [[ -f $OMARCHY_TEST_RECOVERED_MONITORS ]] &&
    cp "$OMARCHY_TEST_RECOVERED_MONITORS" "$OMARCHY_TEST_MONITORS_FILE"
fi
SH

# A desktop, so the clamshell half of the watcher stays idle.
cat >"$fake_bin/omarchy-hw-laptop" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$fake_bin/omarchy-hyprland-monitor-external-active" <<'SH'
#!/bin/bash

exit 1
SH

cat >"$fake_bin/omarchy-hyprland-monitor-clamshell" <<'SH'
#!/bin/bash

exit 0
SH

chmod +x "$fake_bin"/*
ln -s "$ROOT/bin/omarchy-hyprland-monitor-modeless" "$fake_bin/omarchy-hyprland-monitor-modeless"

MODELESS=0
WORKING=1
UNDETERMINED=2

assert_state() {
  local expected="$1" actual=0

  printf '%s' "$2" >"$monitors_file"
  PATH="$fake_bin:$PATH" OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
  OMARCHY_TEST_SWAYMSG_FAIL_FLAG="$swaymsg_fail" \
    "$ROOT/bin/omarchy-hyprland-monitor-modeless" || actual=$?

  (( actual == expected )) || fail "$3" "expected exit $expected, got $actual"
  pass "$3"
}

reloads() {
  wc -l <"$reload_log" | tr -d ' '
}

# A monitor powered off at boot reports an EDID with no modes, so the
# compositor brings it up with no usable mode.
assert_state $MODELESS '[{"name":"DP-1","active":true}]' \
  "a monitor brought up with no mode is detected"

assert_state $MODELESS \
  '[{"name":"DP-1","active":true,"current_mode":{"width":2560,"height":1440}},{"name":"DP-2","active":true,"current_mode":{"width":0,"height":0}}]' \
  "one modeless monitor among working ones is detected"

assert_state $WORKING '[{"name":"DP-1","active":true,"current_mode":{"width":2560,"height":1440}}]' \
  "a working monitor is not reported as modeless"

# A monitor turned off on purpose has no mode either, and re-applying config
# would fight the user over it.
assert_state $WORKING '[{"name":"DP-1","active":false}]' \
  "a deliberately disabled monitor is not reported as modeless"

assert_state $WORKING '[]' "a session with no monitors is not reported as modeless"

# Nothing fires an event for this state, so taking an unanswered query for a
# healthy monitor would leave the screen black for good.
assert_state $UNDETERMINED 'not json' "an unreadable monitor payload cannot say"

printf '%s' '[{"name":"DP-1","active":true}]' >"$monitors_file"
touch "$swaymsg_fail"
unreachable=0
PATH="$fake_bin:$PATH" OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
OMARCHY_TEST_SWAYMSG_FAIL_FLAG="$swaymsg_fail" \
  "$ROOT/bin/omarchy-hyprland-monitor-modeless" || unreachable=$?
rm -f "$swaymsg_fail"
(( unreachable == UNDETERMINED )) || fail "an unreachable compositor cannot say" "got $unreachable"
pass "an unreachable compositor cannot say"

start_watcher() {
  : >"$reload_log"

  PATH="$fake_bin:$PATH" \
  XDG_RUNTIME_DIR="$test_tmp" \
  OMARCHY_TEST_MONITORS_FILE="$monitors_file" \
  OMARCHY_TEST_RELOAD_LOG="$reload_log" \
  OMARCHY_TEST_RECOVERED_MONITORS="$recovered" \
  OMARCHY_TEST_SWAYMSG_FAIL_FLAG="$swaymsg_fail" \
    "$ROOT/bin/omarchy-hyprland-monitor-watch" &
  watch_pid=$!
}

await_reloads() {
  local waited

  for (( waited = 0; waited < 240; waited++ )); do
    (( $(reloads) >= $1 )) && return 0
    sleep 0.05
  done

  return 1
}

# The watcher reloads until the monitor reports a mode, then stops. It has to
# stop on its own: powering the monitor on fires no event to stop it.
printf '%s' '[{"name":"DP-1","active":true}]' >"$monitors_file"
printf '%s' '[{"name":"DP-1","active":true,"current_mode":{"width":2560,"height":1440}}]' >"$recovered"
start_watcher

await_reloads 1 || fail "a monitor with no mode is reloaded at startup"
sleep 4
(( $(reloads) == 1 )) || fail "recovery stops once the monitor reports a mode" "$(<"$reload_log")"
pass "recovery reloads until the monitor comes back, then stops on its own"

# A reload can land a monitor at 0x0 without changing the {name, active}
# topology the poll keys on; the steady-state mode check has to catch it.
before=$(reloads)
printf '%s' '[{"name":"DP-1","active":true,"current_mode":{"width":0,"height":0}}]' >"$monitors_file"

await_reloads $((before + 1)) || fail "a monitor left at 0x0 with unchanged topology is recovered"
pass "a monitor left at 0x0 by a reload is recovered"

stop_watcher

# An unanswerable query is not a healthy monitor. Giving up on one would strand
# the screen, because nothing else will ask again.
printf '%s' '[{"name":"DP-1","active":true}]' >"$monitors_file"
rm -f "$recovered"
touch "$swaymsg_fail"
start_watcher

sleep 3
[[ ! -s $reload_log ]] || fail "an unanswerable query does not trigger a reload" "$(<"$reload_log")"
rm -f "$swaymsg_fail"

await_reloads 1 || fail "recovery keeps asking after the compositor could not answer"
pass "recovery keeps asking after the compositor could not answer"

stop_watcher

# Nothing to recover means nothing to run.
printf '%s' '[{"name":"DP-1","active":true,"current_mode":{"width":2560,"height":1440}}]' >"$monitors_file"
start_watcher

sleep 3
[[ ! -s $reload_log ]] || fail "a healthy machine is left alone" "$(<"$reload_log")"
pass "a healthy machine is never reloaded"

stop_watcher
