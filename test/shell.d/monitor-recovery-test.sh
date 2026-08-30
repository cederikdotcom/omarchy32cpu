#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

monitor_watch="$ROOT/bin/omarchy-hyprland-monitor-watch"
monitor_internal="$ROOT/bin/omarchy-hyprland-monitor-internal"
monitor_mirror="$ROOT/bin/omarchy-hyprland-monitor-internal-mirror"
monitor_laptop="$ROOT/bin/omarchy-hyprland-monitor-laptop"
monitor_external_active="$ROOT/bin/omarchy-hyprland-monitor-external-active"
monitor_modeless="$ROOT/bin/omarchy-hyprland-monitor-modeless"
system_wake="$ROOT/bin/omarchy-system-wake"
clamshell="$ROOT/bin/omarchy-hyprland-monitor-clamshell"
hw_clamshell="$ROOT/bin/omarchy-hw-clamshell"
hw_laptop_closed="$ROOT/bin/omarchy-hw-laptop-closed"
sway_config="$ROOT/default/sway/config"

grep -F 'for delay in 1 3 7; do' "$monitor_watch" >/dev/null
grep -F 'flock -n 9' "$monitor_watch" >/dev/null
grep -F 'omarchy-hyprland-monitor-clamshell' "$monitor_watch" >/dev/null
pass "monitor watcher retries internal monitor recovery after removal"

# sway 1.8 exposes no output event over IPC, so the watcher polls the output
# topology and reconciles clamshell state when it changes.
grep -F 'sync_clamshell_after_monitor_change' "$monitor_watch" >/dev/null
grep -F 'swaymsg -t get_outputs' "$monitor_watch" >/dev/null
pass "monitor watcher reconciles clamshell state on topology changes"

grep -F 'omarchy-hw-laptop && omarchy-hyprland-monitor-external-active' "$monitor_watch" >/dev/null
pass "clamshell drift sync only runs on a docked laptop, not desktops or undocked laptops"

# Recovery costs a reload per attempt, so it must not run on a healthy machine,
# and only one loop may run across the changes that start it.
grep -F '(( state == 1 )) && break' "$monitor_watch" >/dev/null
grep -F 'delay = delay * 2 > 60 ? 60 : delay * 2' "$monitor_watch" >/dev/null
grep -F '9>"$MODELESS_LOCK"' "$monitor_watch" >/dev/null
grep -F 'flock -w 1 9 || exit 0' "$monitor_watch" >/dev/null
pass "modeless monitor recovery runs one backing-off loop while a monitor has no mode"

# Nothing fires an event for this state, so an unanswered query must not end
# recovery -- but a compositor that never answers has gone with the session.
grep -F '(( state == 2 )) && (( ++unanswered > 20 )) && break' "$monitor_watch" >/dev/null
pass "modeless recovery retries unanswered queries without waiting on a dead compositor"

# A reload can land an output at 0x0 without changing the topology the poll
# keys on, so the steady-state iteration checks the mode too.
grep -F '[[ $modeless == "true" ]] && recover_modeless' "$monitor_watch" >/dev/null
pass "modeless recovery also runs when a reload leaves the topology unchanged"

grep -F 'swaymsg -t get_outputs' "$monitor_modeless" >/dev/null
grep -F '.active == true and (((.current_mode.width // 0) == 0) or ((.current_mode.height // 0) == 0))' "$monitor_modeless" >/dev/null
pass "modeless helper ignores monitors disabled on purpose"

grep -F 'omarchy-hw-laptop-closed && omarchy-hw-external-monitors' "$hw_clamshell" >/dev/null
grep -F '/proc/acpi/button/lid/*/state' "$hw_laptop_closed" >/dev/null
pass "clamshell helper detects closed-lid external monitor state"

grep -F 'select(.name | test("^(eDP|LVDS|DSI)-") | not)' "$monitor_external_active" >/dev/null
grep -F 'select(.active == true)' "$monitor_external_active" >/dev/null
pass "active external monitor helper ignores monitors disabled on purpose"

grep -F 'omarchy-hyprland-monitor-internal recover >/dev/null 2>&1 || true' "$clamshell" >/dev/null
grep -F 'Refusing unsafe internal monitor name' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-toggle-enabled internal-monitor-disable' "$clamshell" >/dev/null
grep -F 'output $INTERNAL disable' "$clamshell" >/dev/null
grep -F 'output $INTERNAL enable' "$clamshell" >/dev/null
grep -F 'omarchy-hyprland-monitor-external-active' "$clamshell" >/dev/null
grep -F 'omarchy-hw-clamshell' "$clamshell" >/dev/null
pass "clamshell monitor sync disables laptop output and force-recovers it"

grep -F 'omarchy-hyprland-monitor-laptop' "$monitor_internal" >/dev/null
grep -F 'swaymsg -t get_outputs' "$monitor_laptop" >/dev/null
grep -F 'omarchy-hyprland-monitor-external-active' "$monitor_internal" >/dev/null
grep -F 'wake' "$monitor_internal" >/dev/null
grep -F 'omarchy-hyprland-toggle-enabled $TOGGLE || return 0' "$monitor_internal" >/dev/null
pass "internal monitor helper can re-enable disabled laptop displays"
pass "internal monitor recovery only wakes displays when it re-enables one"

# sway has no output mirroring; the mirror helper must say so and exit
# successfully so its callers (menu, clamshell paths) never break on it.
grep -F 'sway has no output mirroring' "$monitor_mirror" >/dev/null
"$monitor_mirror" recover 2>/dev/null || fail "mirror helper stays a successful no-op"
pass "internal mirror helper is a graceful no-op under sway"

grep -F 'bindswitch --locked lid:on exec omarchy-system-lid-close' "$sway_config" >/dev/null
grep -F 'bindswitch --locked lid:off exec omarchy-hyprland-monitor-clamshell' "$sway_config" >/dev/null
pass "lid switch bindings lock on close and reconcile clamshell display state"

grep -F 'omarchy-hyprland-monitor-clamshell >/dev/null 2>&1 || true' "$system_wake" >/dev/null
pass "system wake resyncs clamshell display state"
