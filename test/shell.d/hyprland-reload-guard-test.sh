#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# sway only reloads its config on an explicit `swaymsg reload`, so the guard
# that paused Hyprland's autoreload around package transactions is now a
# compatibility stub. The libalpm hooks and the modeless recovery loop still
# call it, so pin the stub's contract: pause/resume succeed quietly, and
# paused always answers "not paused".

"$ROOT/bin/omarchy-hyprland-reload-guard" pause ||
  fail "reload guard accepts pause as a no-op"
pass "reload guard accepts pause as a no-op"

"$ROOT/bin/omarchy-hyprland-reload-guard" resume ||
  fail "reload guard accepts resume as a no-op"
pass "reload guard accepts resume as a no-op"

if "$ROOT/bin/omarchy-hyprland-reload-guard" paused; then
  fail "reload guard never reports a paused transaction under sway"
fi
pass "reload guard never reports a paused transaction under sway"

if "$ROOT/bin/omarchy-hyprland-reload-guard" bogus 2>/dev/null; then
  fail "reload guard rejects unknown verbs"
fi
pass "reload guard rejects unknown verbs"
