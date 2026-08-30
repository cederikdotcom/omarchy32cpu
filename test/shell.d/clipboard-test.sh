#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Omarchy CPU has no Quickshell clipboard panel; history capture moved to
# cliphist. The paste/open helpers remain and still read a history file, so
# they are tested standalone here.

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home/.local/state/omarchy"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
cat >"$WL_COPY_OUT"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/omarchy-launch-browser" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$BROWSER_OUT"
SH

cat >"$TMPDIR/bin/omarchy-launch-editor" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$EDITOR_PATH_OUT"
cat "$1" >"$EDITOR_TEXT_OUT"
SH

cat >"$TMPDIR/bin/tensaku-edit" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$TENSAKU_OUT"
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/omarchy-launch-browser" "$TMPDIR/bin/omarchy-launch-editor" "$TMPDIR/bin/tensaku-edit"

jq -n --arg text "$(printf 'large block line 1\nlarge block line 2\n')" '[{type:"text", text:"ignored"}, {type:"text", text:$text}]' >"$TMPDIR/home/.local/state/omarchy/clipboard-history.json"

WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-text" --shift-insert --history-index 1

[[ $(<"$TMPDIR/copied") == "$(printf 'large block line 1\nlarge block line 2')" ]] || fail "clipboard paste helper copies history entry text"
pass "clipboard paste helper copies history entry text"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "clipboard paste helper pastes history entries with shift insert"
pass "clipboard paste helper pastes history entries with shift insert"

rm -f "$TMPDIR/wtype"
WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-text" --copy-only --history-index 1

[[ $(<"$TMPDIR/copied") == "$(printf 'large block line 1\nlarge block line 2')" ]] || fail "clipboard paste helper copy-only copies history entry text"
pass "clipboard paste helper copy-only copies history entry text"

[[ ! -e "$TMPDIR/wtype" ]] || fail "clipboard paste helper copy-only skips typing"
pass "clipboard paste helper copy-only skips typing"

printf 'image-data' >"$TMPDIR/image.png"
rm -f "$TMPDIR/wtype"
WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-file" --copy-only image/png "$TMPDIR/image.png"

[[ $(<"$TMPDIR/copied") == "image-data" ]] || fail "clipboard file paste helper copy-only copies file content"
pass "clipboard file paste helper copy-only copies file content"

[[ ! -e "$TMPDIR/wtype" ]] || fail "clipboard file paste helper copy-only skips paste keystroke"
pass "clipboard file paste helper copy-only skips paste keystroke"

jq -n --arg url 'https://example.com/docs' --arg text "$(printf 'plain text\nsecond line')" --arg image "$TMPDIR/image.png" \
  '[{type:"text", text:$url}, {type:"text", text:$text}, {type:"image", mime:"image/png", path:$image}]' >"$TMPDIR/home/.local/state/omarchy/clipboard-history.json"

BROWSER_OUT="$TMPDIR/browser" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-open" --history-index 0

[[ $(<"$TMPDIR/browser") == "https://example.com/docs" ]] || fail "clipboard open helper opens URL entries in browser"
pass "clipboard open helper opens URL entries in browser"

EDITOR_PATH_OUT="$TMPDIR/editor-path" EDITOR_TEXT_OUT="$TMPDIR/editor-text" HOME="$TMPDIR/home" XDG_STATE_HOME="$TMPDIR/state" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-open" --history-index 1

[[ $(<"$TMPDIR/editor-text") == "$(printf 'plain text\nsecond line')" ]] || fail "clipboard open helper opens text entries in editor"
pass "clipboard open helper opens text entries in editor"

[[ $(<"$TMPDIR/editor-path") == "$TMPDIR"/state/omarchy/clipboard-open/clipboard.*.txt ]] || fail "clipboard open helper writes text entries to a temporary file"
pass "clipboard open helper writes text entries to a temporary file"

TENSAKU_OUT="$TMPDIR/tensaku" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-open" --history-index 2

[[ $(<"$TMPDIR/tensaku") == "$TMPDIR/image.png" ]] || fail "clipboard open helper opens image entries in Tensaku"
pass "clipboard open helper opens image entries in Tensaku"

# The clipboard menu falls back gracefully when cliphist is not installed, so
# the keybinding never errors on a Lite install without it.
fallback_bin="$TMPDIR/fallback-bin"
mkdir -p "$fallback_bin"
cat >"$fallback_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$fallback_bin/omarchy-cmd-present"

menu_output=$(PATH="$fallback_bin:$PATH" "$ROOT/bin/omarchy-menu-clipboard" 2>&1) ||
  fail "clipboard menu succeeds without cliphist" "$menu_output"
[[ $menu_output == *"install cliphist"* ]] || fail "clipboard menu says how to get history" "$menu_output"
pass "clipboard menu degrades gracefully without cliphist"
