#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
xdg_decoy="$tmpdir/xdg-decoy"
log_file="$tmpdir/swaymsg.log"
marker="$tmpdir/marker"
mkdir -p "$stub_dir" "$home_dir" "$xdg_decoy"

state_dir="$home_dir/.local/state/omarchy/toggles/sway"
name_file="$state_dir/touchpad-disabled-name"

cat >"$stub_dir/swaymsg" <<'EOF'
#!/bin/bash
if [[ ${1:-} == "reload" ]]; then
  printf 'reload\n' >>"$SWAYMSG_LOG"
else
  printf '%s\n' "$*" >>"$SWAYMSG_LOG"
fi
EOF
chmod +x "$stub_dir/swaymsg"

cat >"$stub_dir/omarchy-osd" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-osd"

stub_device() {
  local kind=$1
  local name=$2
  cat >"$stub_dir/omarchy-hw-$kind" <<EOF
#!/bin/bash
printf '%s\n' '$name'
EOF
  chmod +x "$stub_dir/omarchy-hw-$kind"
}

# XDG_STATE_HOME deliberately points away from HOME everywhere below: the
# input-device state is hardcoded to ~/.local/state like the sibling toggle
# tools and the migration, so nothing may read or write the XDG directory.
run_toggle() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$xdg_decoy" \
    SWAYMSG_LOG="$log_file" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-toggle-input-device" "$@"
}

assert_decoy_untouched() {
  [[ -z $(find "$xdg_decoy" -mindepth 1 -print -quit 2>/dev/null) ]] ||
    fail "input-device state must ignore XDG_STATE_HOME"
}

: >"$log_file"
stub_device touchpad 'elan-touchpad'

run_toggle touchpad off
[[ $(<"$name_file") == "elan-touchpad" ]] || fail "touchpad disable stores the device name as data"
grep -Fx -- '-- input elan-touchpad events disabled' "$log_file" >/dev/null ||
  fail "touchpad disable passes the device name to sway as an argument"
assert_decoy_untouched
pass "touchpad disable persists the device name as data"

: >"$log_file"
run_toggle touchpad on
[[ ! -e $name_file ]] || fail "touchpad enable clears the persisted device name"
grep -Fx -- '-- input elan-touchpad events enabled' "$log_file" >/dev/null ||
  fail "touchpad enable passes the device name to sway as an argument"
pass "touchpad enable clears persisted disable state"

run_toggle touchpad
[[ -f $name_file ]] || fail "default toggle action disables an enabled touchpad"
run_toggle touchpad
[[ ! -e $name_file ]] || fail "default toggle action enables a disabled touchpad"
pass "default toggle action flips the persisted state"

: >"$log_file"
stub_device touchscreen 'wacom-hid-52eb-finger'
ts_name_file="$state_dir/touchscreen-disabled-name"

run_toggle touchscreen off
[[ $(<"$ts_name_file") == "wacom-hid-52eb-finger" ]] ||
  fail "touchscreen disable stores the device name as data"
run_toggle touchscreen on
[[ ! -e $ts_name_file ]] || fail "touchscreen enable clears the persisted device name"
pass "touchscreen routes through the same persisted-name state"

# USB device names are attacker-controlled: they must reach sway only as an
# argv element and the state file only as data, never through a shell.
: >"$log_file"
rm -f "$marker"
stub_device touchpad 'touchpad"; touch '"$marker"'; echo "'

run_toggle touchpad off
[[ ! -e $marker ]] || fail "touchpad disable does not execute metacharacters in the device name"
[[ $(<"$name_file") == 'touchpad"; touch '"$marker"'; echo "' ]] ||
  fail "a hostile device name is stored only as data"
grep -F -- '-- input touchpad"; touch ' "$log_file" >/dev/null ||
  fail "a hostile device name reaches sway as a single argument" "$(<"$log_file")"
pass "touchpad disable treats USB device names as data"

cat >"$stub_dir/omarchy-hw-touchpad" <<'EOF'
#!/bin/bash
printf 'evil\nname\n'
EOF
chmod +x "$stub_dir/omarchy-hw-touchpad"

rm -f "$name_file"
set +e
run_toggle touchpad off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "disable rejects a device name with a newline"
[[ ! -e $name_file ]] || fail "a rejected device name is not persisted"
pass "disable rejects control characters in a device name"

printf 'elan-touchpad\n' >"$name_file"
set +e
run_toggle touchpad on >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "enable still reports an invalid device name"
[[ ! -e $name_file ]] || fail "enable clears persisted state even with an invalid device name"
pass "a bad device name cannot wedge the persisted disable"

cat >"$stub_dir/omarchy-hw-touchpad" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-hw-touchpad"

set +e
run_toggle touchpad off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "disable errors when no device is found"
[[ ! -e $name_file ]] || fail "no state is written when no device is found"
pass "disable errors when no device is found"

# The sway session re-applies persisted disables on start and reload, so a
# disabled device stays disabled across logins.
grep -E 'exec_always.*toggles/sway.*-disabled-name.*events disabled' "$ROOT/default/sway/config" >/dev/null ||
  fail "the default sway config re-applies persisted input-device disables"
pass "the sway session re-applies persisted disables"

# The migration recovers legacy Hyprland state into the sway toggles dir: a
# plain name is kept as data, hostile generated Lua is discarded unread.
legacy_dir="$home_dir/.local/state/omarchy/toggles/hypr"

run_migration() {
  HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" SWAYMSG_LOG="$log_file" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    bash -euo pipefail "$ROOT/migrations/1787618700.sh" >/dev/null
}

mkdir -p "$legacy_dir"
rm -f "$name_file" "$ts_name_file"
printf 'hl.device({ name = "synps/2-synaptics-touchpad", enabled = false })\n' >"$legacy_dir/touchpad-disabled.lua"
printf 'hl.device({ name = "hostile\\"")", enabled = false })\n' >"$legacy_dir/touchscreen-disabled.lua"

: >"$log_file"
run_migration
[[ $(<"$name_file") == "synps/2-synaptics-touchpad" ]] ||
  fail "migration recovers a device name containing a slash into sway state"
[[ ! -e $legacy_dir/touchpad-disabled.lua ]] || fail "migration deletes the generated touchpad Lua"
[[ ! -e $ts_name_file ]] ||
  fail "migration does not copy a hostile name out of generated Lua"
[[ ! -e $legacy_dir/touchscreen-disabled.lua ]] ||
  fail "migration deletes hostile generated Lua even when no name is recovered"
assert_decoy_untouched
grep -Fx 'reload' "$log_file" >/dev/null ||
  fail "migration reloads sway so the recovered disable applies to this session"
pass "migration recovers plain names and discards hostile generated Lua"

printf 'kept-name\n' >"$name_file"
printf 'hl.device({ name = "other-touchpad", enabled = false })\n' >"$legacy_dir/touchpad-disabled.lua"
run_migration
[[ $(<"$name_file") == "kept-name" ]] || fail "migration keeps an existing device-name file"
[[ ! -e $legacy_dir/touchpad-disabled.lua ]] || fail "migration still deletes the generated Lua"
pass "migration is idempotent over an existing device-name file"

rm -f "$name_file"
printf 'garbage\n' >"$legacy_dir/touchpad-disabled.lua"
chmod 000 "$legacy_dir/touchpad-disabled.lua"
run_migration
[[ ! -e $legacy_dir/touchpad-disabled.lua ]] || fail "migration removes an unreadable generated Lua"
[[ ! -e $name_file ]] || fail "no name is recovered from an unreadable file"
pass "an unreadable state file does not wedge the migration"

: >"$log_file"
run_migration
[[ ! -s $log_file ]] || fail "migration with nothing to migrate does not reload"
pass "migration no-ops with nothing left to migrate"
