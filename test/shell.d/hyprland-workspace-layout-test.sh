#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# sway keeps layout per container itself, so the old per-workspace state files
# and Hyprland workspace rules are gone: the toggle cycles the sway layout and
# reports where it landed.

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/swaymsg.log"
notify_log="$tmpdir/notify.log"
mkdir -p "$stub_dir"

cat >"$stub_dir/swaymsg" <<'EOF'
#!/bin/bash

if [[ ${1:-} == "-t" && ${2:-} == "get_tree" ]]; then
  printf '%s\n' "$OMARCHY_TEST_TREE_JSON"
else
  printf '%s\n' "$*" >>"$SWAYMSG_LOG"
fi
EOF
chmod +x "$stub_dir/swaymsg"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_NOTIFY_LOG"
EOF
chmod +x "$stub_dir/omarchy-notification-send"

tree='{"type":"root","nodes":[{"type":"con","layout":"tabbed","nodes":[{"type":"con","pid":7,"id":2,"focused":true,"nodes":[]}]}]}'
SWAYMSG_LOG="$log_file" OMARCHY_TEST_NOTIFY_LOG="$notify_log" \
  OMARCHY_TEST_TREE_JSON="$tree" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle"

grep -Fx 'layout toggle splith splitv tabbed' "$log_file" >/dev/null ||
  fail "workspace layout toggle cycles the sway container layout"
grep -F 'Workspace layout set to tabbed' "$notify_log" >/dev/null ||
  fail "workspace layout toggle reports the layout it landed on"
pass "workspace layout toggle cycles and reports the sway layout"

: >"$notify_log"
tree='{"type":"root","nodes":[]}'
SWAYMSG_LOG="$log_file" OMARCHY_TEST_NOTIFY_LOG="$notify_log" \
  OMARCHY_TEST_TREE_JSON="$tree" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-workspace-layout-toggle"

grep -F 'Workspace layout toggled' "$notify_log" >/dev/null ||
  fail "workspace layout toggle still reports without a focused window"
pass "workspace layout toggle tolerates a tree with no focused window"
