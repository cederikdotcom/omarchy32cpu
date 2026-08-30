#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# Omarchy CPU renders the Omarchy menu with fuzzel --dmenu. The tree still
# comes from default/omarchy/omarchy-menu.jsonc overlaid by the user's
# extensions file, with when/checked guards and pruned Quickshell-only rows.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
menu_home="$test_tmp/home"
rows_out="$test_tmp/rows"
action_log="$test_tmp/actions"
mkdir -p "$stub_bin" "$menu_home/.config/omarchy/extensions"

# fuzzel records the rows it was shown; FUZZEL_PICK selects one by index, an
# unset pick is the user pressing escape.
cat >"$stub_bin/fuzzel" <<'SH'
#!/bin/bash
cat >"$FUZZEL_ROWS_OUT"
[[ -n ${FUZZEL_PICK:-} ]] || exit 1
printf '%s\n' "$FUZZEL_PICK"
SH

cat >"$stub_bin/setsid" <<'SH'
#!/bin/bash
[[ ${1:-} == "-f" ]] && shift
printf '%s\n' "$*" >>"$ACTION_LOG"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/hello-cmd" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin"/*

run_menu() {
  HOME="$menu_home" OMARCHY_PATH="$ROOT" ACTION_LOG="$action_log" \
    FUZZEL_ROWS_OUT="$rows_out" PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-menu" "$@"
}

: >"$rows_out"
run_menu summon root
for label in Style Setup System Update; do
  grep -q "$label" "$rows_out" || fail "root menu lists $label" "$(cat "$rows_out")"
done
pass "root menu lists the top-level sections"

# Quickshell-only branches are pruned: the bar layout submenu and the plugin
# manager have no fuzzel equivalent.
: >"$rows_out"
run_menu summon style
grep -q "Menu Bar" "$rows_out" && fail "style menu prunes the Quickshell bar submenu" "$(cat "$rows_out")"
pass "style menu prunes the Quickshell bar submenu"

: >"$rows_out"
run_menu summon setup
grep -qi "plugin" "$rows_out" && fail "setup menu prunes the Quickshell plugin manager" "$(cat "$rows_out")"
pass "setup menu prunes the Quickshell plugin manager"

# Aliases still route: power-menu is the established name for the system menu.
: >"$rows_out"
run_menu summon power-menu
grep -q "Shutdown" "$rows_out" || fail "power-menu alias routes to the system menu" "$(cat "$rows_out")"
pass "power-menu alias routes to the system menu"

# The user overlay overrides defaults and adds new entries; when hides a row
# and checked appends a tick.
cat >"$menu_home/.config/omarchy/extensions/omarchy-menu.jsonc" <<'JSONC'
{
  // user overlay for the menu test
  "system.lock": {"icon":"","label":"Lockdown","action":"omarchy-system-lock"},
  "ztest": {"label":"Ztest"},
  "ztest.hello": {"label":"Hello","action":"hello-cmd greet"},
  "ztest.hidden": {"label":"Hidden","when":"false","action":"hello-cmd hidden"},
  "ztest.ticked": {"label":"Ticked","checked":"true","action":"hello-cmd tick"},
  "ztest.missing": {"label":"Missing","action":"no-such-command-anywhere"},
}
JSONC

: >"$rows_out"
run_menu summon system
grep -q "Lockdown" "$rows_out" || fail "user overlay overrides a default entry label" "$(cat "$rows_out")"
pass "user overlay overrides a default entry label"

: >"$rows_out"
run_menu summon ztest
grep -q "Hello" "$rows_out" || fail "user overlay adds new submenu rows" "$(cat "$rows_out")"
grep -q "Hidden" "$rows_out" && fail "a failing when guard hides its row" "$(cat "$rows_out")"
pass "a failing when guard hides its row"
grep -q "Ticked ✓" "$rows_out" || fail "a passing checked guard appends a tick" "$(cat "$rows_out")"
pass "a passing checked guard appends a tick"
grep -q "Missing" "$rows_out" && fail "an action whose command is absent is hidden" "$(cat "$rows_out")"
pass "an action whose command is absent is hidden"

# Row 0 of a non-root menu is Back; Hello is the first entry after it.
: >"$rows_out" && : >"$action_log"
FUZZEL_PICK=1 run_menu summon ztest
grep -Fq 'bash -c hello-cmd greet' "$action_log" ||
  fail "selecting an action row runs it detached" "$(cat "$action_log")"
pass "selecting an action row runs it detached"

# Summoning an action id directly runs it without opening fuzzel.
: >"$rows_out" && : >"$action_log"
run_menu summon ztest.hello
grep -Fq 'bash -c hello-cmd greet' "$action_log" ||
  fail "summoning an action route runs the action directly" "$(cat "$action_log")"
[[ ! -s $rows_out ]] || fail "a direct action route never opens the picker" "$(cat "$rows_out")"
pass "summoning an action route runs the action directly"

run_menu close || fail "menu close succeeds with no menu open"
pass "menu close succeeds with no menu open"

if run_menu frobnicate 2>/dev/null; then
  fail "menu rejects unknown verbs"
fi
pass "menu rejects unknown verbs"

# The branded glyphs the menu still uses ship in the Omarchy icon font.
if command -v fc-query >/dev/null; then
  font_charset=$(fc-query --format='%{charset}' "$ROOT/default/fonts/omarchy/omarchy.ttf")
  [[ $font_charset == *"e900-e907"* ]] || fail "Omarchy icon font includes every custom menu glyph"
  pass "Omarchy icon font includes the official agent marks"
else
  pass "no fc-query; skipping icon font glyph check"
fi
