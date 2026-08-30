#!/bin/bash

source "$(dirname "$0")/base-test.sh"

# Hyprland's tiled-fullscreen (client fullscreen while the window stays tiled)
# has no sway equivalent; the toggle degrades to a plain fullscreen toggle
# through the compositor-neutral helper.

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/swaymsg" <<'BASH'
#!/bin/bash

printf '%s\n' "$*" >>"$SWAYMSG_LOG"
BASH
chmod +x "$tmpdir/swaymsg"

log="$tmpdir/swaymsg.log"
PATH="$tmpdir:$ROOT/bin:$PATH" SWAYMSG_LOG="$log" \
  "$ROOT/bin/omarchy-hyprland-window-tiled-fullscreen-toggle"

grep -Fqx 'fullscreen toggle' "$log" || \
  fail "tiled fullscreen toggles sway fullscreen on the focused window"
pass "tiled fullscreen toggles sway fullscreen on the focused window"
