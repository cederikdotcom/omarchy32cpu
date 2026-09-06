#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/setsid"

cat >"$tmp_dir/omarchy-cmd-present" <<'SCRIPT'
#!/bin/bash
[[ ${TEST_TERMINAL:-xdg} == "xdg" ]]
SCRIPT
chmod +x "$tmp_dir/omarchy-cmd-present"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
pass "floating terminal launches Omarchy terminal"

TEST_TERMINAL=foot "$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"
launch=$(<"$TEST_LOG")
[[ $launch == *"foot --app-id=org.omarchy.terminal"* ]] || fail "lite floating terminal uses foot" "$launch"
[[ $launch == *"Command failed (exit %s)"* ]] || fail "failed commands have a visible failure prompt"
pass "lite floating terminal uses foot and preserves failure feedback"
