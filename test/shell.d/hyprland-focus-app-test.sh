#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/swaymsg" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-t" && ${2:-} == "get_tree" ]]; then
  printf '%s\n' "$OMARCHY_TEST_TREE_JSON"
else
  printf '%s\n' "$*" >>"$OMARCHY_TEST_FOCUS_DISPATCH"
fi
SH
chmod +x "$mock_bin/swaymsg"

dispatch_log="$test_tmp/dispatch"
tree_json='{"type":"root","nodes":[{"type":"con","pid":100,"id":7,"app_id":"chromium","name":"Inbox"}]}'
PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_TREE_JSON="$tree_json" \
  OMARCHY_TEST_FOCUS_DISPATCH="$dispatch_log" \
  bash "$ROOT/bin/omarchy-hyprland-focus-app" '^chromium$'

grep -F '[con_id=7] focus' "$dispatch_log" >/dev/null || \
  fail "app focus uses the sway con_id focus command"

pass "app focus follows windows across workspaces"

tree_json='{"type":"root","nodes":[
  {"type":"con","pid":101,"id":11,"app_id":"com.viber.Viber","name":"Viber"},
  {"type":"con","pid":102,"id":12,"app_id":"org.omarchy.agent","name":"kitty"}
]}'
PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_TREE_JSON="$tree_json" \
  OMARCHY_TEST_FOCUS_DISPATCH="$dispatch_log" \
  bash "$ROOT/bin/omarchy-hyprland-focus-app" kitty

grep -F '[con_id=12] focus' "$dispatch_log" >/dev/null || \
  fail "app focus falls back to the agent window title"

pass "app focus finds terminals launched under a shared agent class"

tree_json='{"type":"root","nodes":[
  {"type":"con","pid":103,"id":21,"app_id":"chromium","name":"Mail settings"}
]}'
rm -f "$dispatch_log"
if PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_TREE_JSON="$tree_json" \
  OMARCHY_TEST_FOCUS_DISPATCH="$dispatch_log" \
  bash "$ROOT/bin/omarchy-hyprland-focus-app" Mail; then
  fail "app focus rejects title matches from non-agent windows"
fi

[[ ! -e $dispatch_log ]] || fail "app focus leaves focus unchanged for unrelated title matches"

pass "app focus restricts title matching to agent terminals"
