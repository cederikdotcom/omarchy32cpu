#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# default/hypr/input.lua sets the keyboard layout through hyprctl, which is too
# late for a fresh install with a non-US keymap. bin/omarchy-hyprland-launch
# exports XKB_DEFAULT_* from /etc/vconsole.conf before exec'ing the compositor.
# Stub Hyprland to capture what the session hands it.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

> "$stub_bin/report" cat <<'SH'
#!/bin/bash
printf '[%s] [%s] [%s]\n' "$XKB_DEFAULT_LAYOUT" "$XKB_DEFAULT_VARIANT" "$XKB_DEFAULT_OPTIONS"
SH
chmod +x "$stub_bin/report"
# The launcher prefers the start-hyprland watchdog and falls back to Hyprland.
# Stub both, so the layout is asserted on whichever path the launcher takes and
# a machine with a real start-hyprland on PATH cannot change the result.
cp "$stub_bin/report" "$stub_bin/Hyprland"
cp "$stub_bin/report" "$stub_bin/start-hyprland"

resolved_input() {
  local vconsole="${1-__missing__}"
  local conf="$test_tmp/vconsole.conf"

  if [[ $vconsole == "__missing__" ]]; then
    rm -f "$conf"
  else
    printf '%s' "$vconsole" >"$conf"
  fi

  PATH="$stub_bin:$PATH" OMARCHY_VCONSOLE_CONF="$conf" HOME="$test_tmp" \
    bash "$ROOT/bin/omarchy-hyprland-launch" 2>/dev/null
}

assert_input() {
  local description="$1"
  local expected="$2"
  local actual

  if (( $# > 2 )); then
    actual=$(resolved_input "$3")
  else
    actual=$(resolved_input)
  fi

  [[ $actual == "$expected" ]] ||
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  pass "$description"
}

base_options="compose:caps,shift:both_capslock_cancel"
toggle_options="$base_options,grp:alts_toggle"

assert_input "missing vconsole.conf falls back to us" "[us] [] [$base_options]"
assert_input "us layout passes through" "[us] [intl] [$base_options]" 'XKBLAYOUT=us
XKBVARIANT=intl
'
assert_input "latin layouts are left alone" "[de] [nodeadkeys] [$base_options]" 'XKBLAYOUT=de
XKBVARIANT=nodeadkeys
'
assert_input "non-latin layout gains us in front" "[us,ara] [,] [$toggle_options]" 'XKBLAYOUT=ara
'
assert_input "prepended us keeps variants aligned" "[us,ru] [,phonetic] [$toggle_options]" 'XKBLAYOUT=ru
XKBVARIANT=phonetic
'
assert_input "non-latin layout in front gains us even when us trails" "[us,il,us] [,] [$toggle_options]" 'XKBLAYOUT=il,us
'
