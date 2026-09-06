#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
export HOME="$tmp/home" OMARCHY_PATH="$ROOT" TEST_LOG="$tmp/log"
export PATH="$tmp/bin:$ROOT/bin:$PATH"

cat >"$tmp/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 != xdg-terminal-exec ]]
SH
cat >"$tmp/bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ $1 == "${TEST_MISSING:-}" ]]
SH
cat >"$tmp/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
[[ ${TEST_NOTIFY_FAIL:-false} != true ]]
SH
cat >"$tmp/bin/setsid" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$TEST_LOG"
SH
cat >"$tmp/bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$tmp/bin/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$tmp/bin/"*

if TEST_MISSING=mise omarchy-default-agent codex >"$tmp/error" 2>&1; then fail "missing mise must fail"; fi
grep -q 'Agent installer unavailable' "$TEST_LOG" || fail "missing installer produces a notification"
[[ ! -e $HOME/.config/omarchy/defaults/agent ]] || fail "missing installer must not change default"
pass "missing installer is visible and leaves the default unchanged"

TEST_NOTIFY_FAIL=true TEST_MISSING=mise omarchy-default-agent codex >"$tmp/error" 2>&1
mapfile -d '' -t args <"$TEST_LOG"
[[ ${args[2]} == foot && ${args[*]} == *'omarchy-default-agent --install codex'* ]] || fail "missing notification server falls back to a visible terminal"
pass "missing notification server still exposes the installer error"

omarchy-launch-tui --app-id=test printf '%s' 'argument with spaces'
mapfile -d '' -t args <"$TEST_LOG"
[[ ${args[2]} == foot && ${args[7]} == 'argument with spaces' ]] || fail "TUI fallback preserves arguments" "${args[*]}"
pass "TUI uses foot and preserves argument boundaries"

: >"$TEST_LOG"
if TEST_MISSING=absent omarchy-launch-tui absent >"$tmp/error" 2>&1; then fail "missing TUI must fail"; fi
grep -q 'Cannot launch application' "$TEST_LOG" || fail "missing TUI produces a notification"
pass "missing TUI is visible before detaching"

for missing in ttfx socat; do
  : >"$TEST_LOG"
  if TEST_MISSING="$missing" omarchy-launch-screensaver force >"$tmp/error" 2>&1; then fail "screensaver requires $missing"; fi
  grep -q "Missing $missing" "$TEST_LOG" || fail "screensaver explains missing $missing"
done
pass "screensaver preflights both optional runtime dependencies"

if TEST_MISSING=ttfx timeout 2s omarchy-screensaver >"$tmp/error" 2>&1; then fail "missing effect executable must fail"; else status=$?; fi
[[ $status == 127 ]] || fail "missing effect must exit immediately, not spin" "$status"
pass "missing effect fails without a retry loop"

cat >"$tmp/bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == activewindow ]]; then echo '{"class":"org.omarchy.screensaver"}'; fi
SH
cat >"$tmp/bin/pkill" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$tmp/bin/stty" <<'SH'
#!/bin/bash
echo '40 100'
SH
cat >"$tmp/bin/ttfx" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
exit 7
SH
chmod +x "$tmp/bin/"*
: >"$TEST_LOG"
if timeout 3s omarchy-screensaver </dev/null >"$tmp/error" 2>&1; then fail "failed effect must fail"; else status=$?; fi
[[ $status == 1 ]] || fail "effect failure must stop rather than spin" "$status"
[[ $(wc -l <"$TEST_LOG") == 1 ]] || fail "failed effect must not restart"
grep -q -- "-i $ROOT/logo.txt" "$TEST_LOG" || fail "missing user artwork uses shipped logo"
pass "effect failure stops and missing artwork uses the shipped logo"
