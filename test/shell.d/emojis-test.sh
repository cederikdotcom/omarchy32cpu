#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The emoji dataset moved out of the Quickshell plugin tree with the fuzzel
# picker; omarchy-menu-emoji reads it from default/omarchy.
require_command jq

jq -e 'length > 1000 and all(.[]; has("e") and has("k"))' "$ROOT/default/omarchy/emojis.json" >/dev/null ||
  fail "emoji dataset parses with emoji and keyword fields"
pass "emoji dataset parses with emoji and keyword fields"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
args="$*"
target="$WL_COPY_OUT"
if [[ $args == "--type text/plain --sensitive --foreground" ]]; then
  target="$WL_COPY_EMOJI_OUT"
fi

printf '%s\n' "$args" >"$target.args"
cat >"$target"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_EMOJI_OUT="$TMPDIR/emoji" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/emoji") == "😀" ]] || fail "emoji insert helper copies emoji transiently"
pass "emoji insert helper copies emoji transiently"

[[ $(<"$TMPDIR/emoji.args") == "--type text/plain --sensitive --foreground" ]] || fail "emoji insert helper serves sensitive transient clipboard in foreground"
pass "emoji insert helper serves transient clipboard in foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "emoji insert helper pastes with shift insert"
pass "emoji insert helper pastes with shift insert"
