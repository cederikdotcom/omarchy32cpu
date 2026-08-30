#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Monitor connector names are interpolated into swaymsg command strings, so
# every path that does it (internal toggle, clamshell sync, scaling) must
# refuse anything but a plain connector name.

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
monitors_json="$tmpdir/monitors.json"
flag_dir="$home_dir/.local/state/omarchy/toggles/sway"
sway_log="$tmpdir/swaymsg.log"
mkdir -p "$stub_dir" "$flag_dir"

make_stub() {
  local name=$1
  local body=$2
  printf '#!/bin/bash\n%s\n' "$body" >"$stub_dir/$name"
  chmod +x "$stub_dir/$name"
}

make_stub omarchy-notification-send ':'
make_stub omarchy-hyprland-monitor-external-active 'exit 0'
make_stub omarchy-hyprland-monitor-internal ':'
make_stub omarchy-hw-clamshell 'exit 0'
make_stub omarchy-hyprland-monitor-laptop 'printf "%s\n" "$LAPTOP_NAME"'
make_stub swaymsg 'if [[ ${1:-} == "-t" && ${2:-} == "get_outputs" ]]; then
  cat "$MONITORS_JSON"
else
  printf "%s\n" "$*" >>"$SWAY_LOG"
fi'

run_monitor() {
  local command=$1
  shift
  : >"$sway_log"
  HOME="$home_dir" \
    OMARCHY_PATH="$ROOT" \
    XDG_STATE_HOME="$home_dir/.local/state" \
    LAPTOP_NAME="${LAPTOP_NAME:-eDP-1}" \
    MONITORS_JSON="$monitors_json" \
    SWAY_LOG="$sway_log" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    "$ROOT/bin/$command" "$@"
}

printf '[{"name":"eDP-1","active":true},{"name":"DP-3","active":true}]\n' >"$monitors_json"

disable_flag="$flag_dir/internal-monitor-disable.conf"
run_monitor omarchy-hyprland-monitor-internal off
[[ -f $disable_flag ]] || fail "internal off records the disable toggle flag"
grep -Fx 'output eDP-1 disable' "$sway_log" >/dev/null ||
  fail "internal off disables the named connector"
pass "internal off accepts a plain connector name"

rm -f "$disable_flag"
set +e
LAPTOP_NAME='eDP-1 disable; exec calc; output DP-3' \
  run_monitor omarchy-hyprland-monitor-internal off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "internal off rejects a monitor name with command metacharacters"
[[ ! -e $disable_flag ]] || fail "an unsafe monitor name records no toggle flag"
if grep -F 'exec calc' "$sway_log" >/dev/null; then
  fail "an unsafe monitor name never reaches swaymsg"
fi
pass "internal off refuses an unsafe monitor name"

# The clamshell sync interpolates the internal-monitor name too.
printf '[{"name":"eDP-1","active":true},{"name":"DP-3","active":true}]\n' >"$monitors_json"
run_monitor omarchy-hyprland-monitor-clamshell
grep -Fx 'output eDP-1 disable' "$sway_log" >/dev/null ||
  fail "clamshell disables the named internal connector"
pass "clamshell disable accepts a plain connector name"

set +e
LAPTOP_NAME='eDP-1 disable; exec calc' \
  run_monitor omarchy-hyprland-monitor-clamshell >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "clamshell rejects a monitor name with command metacharacters"
[[ ! -s $sway_log ]] || fail "an unsafe internal monitor name never reaches swaymsg" "$(<"$sway_log")"
pass "clamshell refuses an unsafe internal monitor name"

# The scaling command interpolates the focused-monitor name.
printf '[{"name":"eDP-1","focused":true,"active":true,"scale":1.0}]\n' >"$monitors_json"
run_monitor omarchy-hyprland-monitor-scaling 1.6
grep -Fx 'output eDP-1 scale 1.6' "$sway_log" >/dev/null ||
  fail "scaling applies the focused connector name"
pass "scaling accepts a plain connector name"

printf '[{"name":"eDP-1 scale 1; exec calc","focused":true,"active":true,"scale":1.0}]\n' >"$monitors_json"
set +e
run_monitor omarchy-hyprland-monitor-scaling 1.6 >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "scaling rejects a focused monitor name with command metacharacters"
[[ ! -s $sway_log ]] || fail "an unsafe focused monitor name never reaches swaymsg" "$(<"$sway_log")"
pass "scaling refuses an unsafe focused monitor name"
