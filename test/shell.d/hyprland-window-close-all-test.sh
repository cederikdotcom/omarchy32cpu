#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
swaymsg_log="$test_tmp/swaymsg.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/swaymsg" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-t" && ${2:-} == "get_tree" ]]; then
  printf '{"type":"root","nodes":[
    {"type":"con","pid":11,"id":5,"app_id":"foot"},
    {"type":"output","id":90,"nodes":[{"type":"floating_con","pid":12,"id":6,"app_id":"imv"}]}
  ]}\n'
else
  printf '%s\n' "$*" >>"$SWAYMSG_LOG"
fi
SH
chmod +x "$mock_bin/swaymsg"

PATH="$mock_bin:$PATH" SWAYMSG_LOG="$swaymsg_log" "$ROOT/bin/omarchy-hyprland-window-close-all"

expected_log="$test_tmp/expected.log"
cat >"$expected_log" <<'EOF'
[con_id=5] kill
[con_id=6] kill
workspace number 1
EOF

diff -u "$expected_log" "$swaymsg_log" || fail "close-all targets each window and returns to workspace 1"
pass "close-all targets each window and returns to workspace 1"
