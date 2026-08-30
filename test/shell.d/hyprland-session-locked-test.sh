#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# swaylock holds sway's ext-session-lock for as long as the session is locked,
# so a live swaylock process IS the lock state. The Hyprland tri-state
# (locked/unlocked/cannot-say) collapsed to that binary.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/pgrep" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-x" && ${2:-} == "swaylock" ]]; then
  [[ ${OMARCHY_TEST_SWAYLOCK_RUNNING:-0} == 1 ]] && { echo 4242; exit 0; }
  exit 1
fi
exit 1
SH
chmod +x "$fake_bin/pgrep"

PATH="$fake_bin:$PATH" OMARCHY_TEST_SWAYLOCK_RUNNING=1 \
  "$ROOT/bin/omarchy-hyprland-session-locked" ||
  fail "a locked session is detected"
pass "a locked session is detected"

if PATH="$fake_bin:$PATH" OMARCHY_TEST_SWAYLOCK_RUNNING=0 \
  "$ROOT/bin/omarchy-hyprland-session-locked"; then
  fail "an unlocked session is reported as unlocked"
fi
pass "an unlocked session is reported as unlocked"
