#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# sway accepts arbitrary output scales (no Hyprland-style pixel-exact
# approximation needed), so the command steps through presets, applies the
# scale over swaymsg, and persists it for reloads.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
sway_log="$test_tmp/swaymsg.log"
scale_conf="$home_dir/.local/state/omarchy/toggles/sway/monitor-scale.conf"
scale_log="$home_dir/.local/state/omarchy/monitor-scaling.log"

mkdir -p "$stub_bin" "$home_dir"

cat >"$stub_bin/swaymsg" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-t" && ${2:-} == "get_outputs" ]]; then
  printf '[{"name":"eDP-1","focused":true,"scale":%s}]' "${OMARCHY_TEST_MONITOR_SCALE:-1}"
else
  printf '%s\n' "$*" >>"$OMARCHY_TEST_SWAY_LOG"
fi
SH
chmod +x "$stub_bin/swaymsg"

run_scaling() {
  : >"$sway_log"
  HOME="$home_dir" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_SWAY_LOG="$sway_log" \
    OMARCHY_TEST_MONITOR_SCALE="${OMARCHY_TEST_MONITOR_SCALE:-1}" \
    "$ROOT/bin/omarchy-hyprland-monitor-scaling" "$@"
}

OMARCHY_TEST_MONITOR_SCALE=2 run_scaling up
grep -Fx 'output eDP-1 scale 3' "$sway_log" >/dev/null || fail "monitor scaling up reaches 3x"
grep -Fx 'output eDP-1 scale 3' "$scale_conf" >/dev/null || fail "monitor scaling up persists 3x"
grep -F $'requested=up\tcurrent=2\tnew=3\tmonitor=eDP-1' "$scale_log" >/dev/null || fail "monitor scaling up writes audit log"
pass "monitor scaling up reaches 3x"

OMARCHY_TEST_MONITOR_SCALE=3 run_scaling down
grep -Fx 'output eDP-1 scale 2' "$sway_log" >/dev/null || fail "monitor scaling down recovers 3x to 2x"
grep -Fx 'output eDP-1 scale 2' "$scale_conf" >/dev/null || fail "monitor scaling down persists 2x from 3x"
pass "monitor scaling down recovers 3x to 2x"

# sway reports floating point scales, so stepping must snap to the nearest
# preset first or it gets stuck.
OMARCHY_TEST_MONITOR_SCALE=3.0000000000000004 run_scaling down
grep -Fx 'output eDP-1 scale 2' "$sway_log" >/dev/null || fail "monitor scaling down snaps floating point 3x to 2x"
pass "monitor scaling down snaps floating point 3x to 2x"

OMARCHY_TEST_MONITOR_SCALE=4 run_scaling up
grep -Fx 'output eDP-1 scale 4' "$sway_log" >/dev/null || fail "monitor scaling up stays at the top preset"
pass "monitor scaling up stays at the top preset"

OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.6
grep -Fx 'output eDP-1 scale 1.6' "$sway_log" >/dev/null || fail "monitor scaling explicit 1.6x remains available"
grep -Fx 'output eDP-1 scale 1.6' "$scale_conf" >/dev/null || fail "monitor scaling explicit 1.6x persists"
pass "monitor scaling explicit 1.6x remains available"

# Any scale between 1 and 4 is legal for sway, presets are just the step stops.
OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 1.75
grep -Fx 'output eDP-1 scale 1.75' "$sway_log" >/dev/null || fail "monitor scaling accepts arbitrary scales in range"
pass "monitor scaling accepts arbitrary scales in range"

if OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 5 2>/dev/null; then
  fail "monitor scaling rejects a scale outside 1-4"
fi
if OMARCHY_TEST_MONITOR_SCALE=2 run_scaling 'bogus' 2>/dev/null; then
  fail "monitor scaling rejects a non-numeric scale"
fi
pass "monitor scaling rejects out-of-range and malformed scales"

scale=$(OMARCHY_TEST_MONITOR_SCALE=3.0 run_scaling)
[[ $scale == "3" ]] || fail "monitor scaling reports a normalized current scale" "actual: $scale"
scale=$(OMARCHY_TEST_MONITOR_SCALE=3.2 run_scaling)
[[ $scale == "3.2" ]] || fail "monitor scaling reports the actual non-preset scale" "actual: $scale"
pass "monitor scaling reports the current scale"
