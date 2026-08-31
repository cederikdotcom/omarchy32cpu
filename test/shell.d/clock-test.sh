#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Omarchy CPU renders the clock as a waybar module instead of the Quickshell
# clock widget. The bar keeps the clock centered, and the alt format keeps the
# ISO week the old formatAlt carried.

waybar_config="$ROOT/config/waybar/config.jsonc"

# waybar config is JSONC; strip line comments before handing it to jq.
waybar_json=$(sed 's|^\s*//.*||' "$waybar_config")

jq -e '."modules-center" | index("clock") != null' <<<"$waybar_json" >/dev/null ||
  fail "waybar centers the clock module"
pass "waybar centers the clock module"

jq -e '.clock."format-alt" | test("%V")' <<<"$waybar_json" >/dev/null ||
  fail "waybar clock alt format keeps the ISO week"
pass "waybar clock alt format keeps the ISO week"

# The calendar hotkey survives: it routes through the omarchy-shell shim, which
# absorbs targets the Lite stack cannot serve instead of erroring the binding.
grep -q 'bindsym \$mod+Ctrl+Alt+d exec omarchy-shell shell toggle omarchy.clock' "$ROOT/default/sway/config" ||
  fail "SUPER+CTRL+ALT+D still routes the calendar toggle through the shell shim"
pass "SUPER+CTRL+ALT+D still routes the calendar toggle through the shell shim"

shim_output=$(PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-shell" shell toggle omarchy.clock 2>&1) ||
  fail "the shell shim absorbs the calendar toggle without failing the binding" "$shim_output"
pass "the shell shim absorbs the calendar toggle without failing the binding"
