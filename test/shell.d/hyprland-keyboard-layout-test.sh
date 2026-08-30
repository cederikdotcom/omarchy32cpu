#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# The Hyprland-era default/hypr/input.lua keyboard logic now lives in
# bin/omarchy-sway-launch, which exports XKB_DEFAULT_* before exec'ing sway.
# Stub sway to capture what the session hands the compositor.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sway" <<'SH'
#!/bin/bash
printf '[%s] [%s] [%s]\n' "$XKB_DEFAULT_LAYOUT" "$XKB_DEFAULT_VARIANT" "$XKB_DEFAULT_OPTIONS"
SH
chmod +x "$stub_bin/sway"

resolved_input() {
  local vconsole="${1-__missing__}"
  local conf="$test_tmp/vconsole.conf"

  if [[ $vconsole == "__missing__" ]]; then
    rm -f "$conf"
  else
    printf '%s' "$vconsole" >"$conf"
  fi

  PATH="$stub_bin:$PATH" OMARCHY_VCONSOLE_CONF="$conf" HOME="$test_tmp" \
    bash "$ROOT/bin/omarchy-sway-launch"
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
