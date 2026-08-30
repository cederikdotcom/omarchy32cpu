#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The Omarchy CPU shell is waybar plus mako. A restart stops both, respawns
# them through sway (so they inherit the session environment, not the
# caller's), and only reports success once the bar answers again.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
mkdir -p "$fake_bin" "$runtime_dir"

cat >"$fake_bin/omarchy-bar" <<'SH'
#!/bin/bash
printf 'bar %s\n' "$*" >>"$OMARCHY_TEST_LOG"
if [[ ${1:-} == "status" ]]; then
  [[ ${OMARCHY_TEST_BAR_COMES_BACK:-1} == 1 ]] || exit 1
fi
exit 0
SH

cat >"$fake_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$fake_bin/swaymsg" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_COMPOSITOR_GONE:-0} == 1 ]] && exit 1
printf 'swaymsg [%s] %s\n' "${SWAYSOCK:-}" "$*" >>"$OMARCHY_TEST_LOG"
SH

cat >"$fake_bin/omarchy-launch-shell" <<'SH'
#!/bin/bash
printf 'launch-shell direct\n' >>"$OMARCHY_TEST_LOG"
SH

chmod +x "$fake_bin"/*

restart_log="$test_tmp/restart.log"

run_restart() {
  PATH="$fake_bin:$PATH" \
  OMARCHY_TEST_LOG="$restart_log" \
  XDG_RUNTIME_DIR="$runtime_dir" \
    "$@"
}

# A caller from outside the session (ssh, TTY) has no SWAYSOCK; the restart
# derives it from the newest sway IPC socket in the runtime dir.
touch "$runtime_dir/sway-ipc.1000.4242.sock"

: >"$restart_log"
run_restart env -u SWAYSOCK "$ROOT/bin/omarchy-restart-shell" ||
  fail "restart succeeds when the bar comes back"
grep -Fqx 'bar stop' "$restart_log" || fail "restart stops the bar"
grep -Fq 'pkill -x mako' "$restart_log" || fail "restart stops mako"
grep -Fq "swaymsg [$runtime_dir/sway-ipc.1000.4242.sock] exec omarchy-launch-shell" "$restart_log" ||
  fail "restart relaunches the shell through sway with the recovered socket" "$(<"$restart_log")"
grep -Fqx 'bar status' "$restart_log" || fail "restart waits for the bar to answer"
if grep -Fqx 'launch-shell direct' "$restart_log"; then
  fail "restart prefers the compositor spawn over a direct launch"
fi
pass "restart replaces the shell through the compositor"

# Without a compositor to spawn from, the restart still brings the shell up.
: >"$restart_log"
run_restart env OMARCHY_TEST_COMPOSITOR_GONE=1 "$ROOT/bin/omarchy-restart-shell" ||
  fail "restart succeeds without a compositor"
grep -Fqx 'launch-shell direct' "$restart_log" ||
  fail "restart falls back to a direct launch without a compositor"
pass "restart falls back to a direct launch without a compositor"

# A bar that never answers again is a failed restart, said out loud.
: >"$restart_log"
restart_error=$(run_restart env OMARCHY_TEST_BAR_COMES_BACK=0 \
  timeout 30 "$ROOT/bin/omarchy-restart-shell" 2>&1) &&
  fail "restart fails when the bar never comes back"
[[ $restart_error == "Omarchy shell did not become ready after restart." ]] ||
  fail "a failed restart explains itself" "$restart_error"
pass "restart reports a shell that did not come back"
