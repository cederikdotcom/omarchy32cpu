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
