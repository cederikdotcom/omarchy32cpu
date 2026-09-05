#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

input_config_applied() {
  PRODUCT_NAME="$1" INPUT_FILE="$ROOT/default/hypr/input.lua" lua <<'LUA'
local real_open = io.open

io.open = function(path, mode)
  if path == "/sys/class/dmi/id/product_name" then
    return {
      read = function()
        return os.getenv("PRODUCT_NAME")
      end,
      close = function() end,
    }
  elseif path == "/etc/vconsole.conf" then
    return nil
  end

  return real_open(path, mode)
end

local configured = false
hl = {
  config = function()
    configured = true
  end,
}
o = {
  window = function() end,
}

dofile(os.getenv("INPUT_FILE"))
print(configured and "yes" or "no")
LUA
}

[[ $(input_config_applied "MacBook1,1") == "no" ]] ||
  fail "MacBook1,1 keeps Hyprland's safe input defaults"
pass "MacBook1,1 keeps Hyprland's safe input defaults"

[[ $(input_config_applied "MacBook2,1") == "yes" ]] ||
  fail "other hardware retains Omarchy's input configuration"
pass "other hardware retains Omarchy's input configuration"

a1181_hardware_fix="$ROOT/install/hardware/apple/fix-a1181.sh"
grep -Fq 'local_quirks=/etc/libinput/local-overrides.quirks' "$a1181_hardware_fix" ||
  fail "A1181 hardware setup writes libinput's reserved local quirk filename"
grep -Fq "grep -Fq '[Apple Touchpad OneButton MacBook1,1]'" "$a1181_hardware_fix" ||
  fail "A1181 hardware setup preserves existing local libinput quirks"
grep -Fq 'MatchProduct=0x0217' "$a1181_hardware_fix" ||
  fail "A1181 hardware setup matches the MacBook1,1 touchpad product"
grep -Fq 'ModelAppleTouchpadOneButton=1' "$a1181_hardware_fix" ||
  fail "A1181 hardware setup marks the separate physical button"
pass "A1181 hardware setup installs the one-button touchpad quirk"
