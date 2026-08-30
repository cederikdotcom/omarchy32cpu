#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/run"
touch "$test_dir/run/wayland-1" "$test_dir/run/wayland-1.lock"

# The shim recovers WAYLAND_DISPLAY before routing, so stub a routed target
# (notifications dismiss execs omarchy-notification-dismiss) to observe it.
cat >"$test_dir/bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash
echo "display=[$WAYLAND_DISPLAY]"
STUB
chmod +x "$test_dir/bin/omarchy-notification-dismiss"

export PATH="$test_dir/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$test_dir/run"

# Callers from a stripped environment have no WAYLAND_DISPLAY, and the mako
# and sway sockets both live under the display the compositor owns.
output=$(env -u WAYLAND_DISPLAY "$ROOT/bin/omarchy-shell" notifications dismiss)
[[ $output == "display=[wayland-1]" ]] || fail "shell ipc recovers a missing display" "$output"
pass "shell ipc recovers a missing display"

output=$(WAYLAND_DISPLAY=wayland-9 "$ROOT/bin/omarchy-shell" notifications dismiss)
[[ $output == "display=[wayland-9]" ]] || fail "shell ipc keeps an existing display" "$output"
pass "shell ipc keeps an existing display"
