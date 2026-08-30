#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

template="$ROOT/default/snapper/root"
limine_notify_autostart="$ROOT/config/autostart/limine-snapper-notify.desktop"

grep -Fx 'NUMBER_CLEANUP="yes"' "$template" >/dev/null
grep -Fx 'NUMBER_LIMIT="5"' "$template" >/dev/null
grep -Fx 'TIMELINE_CREATE="no"' "$template" >/dev/null
! grep -Eq '^TIMELINE_(CLEANUP|LIMIT_)' "$template" || fail "Snapper template keeps timeline cleanup details out of the default config"
pass "Snapper retains update snapshots on number cleanup only"

grep -Fx '[Desktop Entry]' "$limine_notify_autostart" >/dev/null
grep -Fx 'Hidden=true' "$limine_notify_autostart" >/dev/null
pass "Limine Snapper warning notifier is disabled by default"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/snapper"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

notification_migration=$(grep -rl 'Disable Limine Snapper warning notifier' "$ROOT/migrations" | head -n 1 || true)
[[ -n $notification_migration ]] || fail "Limine Snapper warning notifier migration exists"
grep -F 'limine-snapper-notify.desktop' "$notification_migration" >/dev/null
grep -F 'systemctl --user daemon-reload' "$notification_migration" >/dev/null
grep -F "app-limine\\x2dsnapper\\x2dnotify@autostart.service" "$notification_migration" >/dev/null

migration_home="$test_tmp/migration-home"
mkdir -p "$migration_home"
TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
HOME="$migration_home" \
  bash -euo pipefail "$notification_migration" >/dev/null

cmp -s "$limine_notify_autostart" "$migration_home/.config/autostart/limine-snapper-notify.desktop" || fail "Limine Snapper warning notifier migration writes autostart override"
grep -Fx 'systemctl --user daemon-reload' "$test_tmp/calls.log" >/dev/null || fail "Limine Snapper warning notifier migration reloads user units"
grep -Fx 'systemctl --user stop app-limine\x2dsnapper\x2dnotify@autostart.service' "$test_tmp/calls.log" >/dev/null || fail "Limine Snapper warning notifier migration stops active watcher"
pass "Limine Snapper warning notifier migration disables existing user autostart"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_SNAPPER_CONFIGURE_TEST=1 \
OMARCHY_PATH="$ROOT" \
OMARCHY_SNAPPER_CONFIG_PATH="$test_tmp/etc/snapper/configs/root" \
OMARCHY_SNAPPER_CONF_PATH="$test_tmp/etc/conf.d/snapper" \
  bash -euo pipefail "$ROOT/install/config/snapper.sh" >/dev/null

cmp -s "$template" "$test_tmp/etc/snapper/configs/root" || fail "snapshot configure installs the Omarchy Snapper template"
grep -Fx 'SNAPPER_CONFIGS="root"' "$test_tmp/etc/conf.d/snapper" >/dev/null || fail "snapshot configure writes /etc/conf.d/snapper"
grep -Fx 'systemctl disable --now snapper-timeline.timer' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure disables timeline snapshots"
grep -Fx 'systemctl enable --now snapper-cleanup.timer' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure enables number cleanup"
pass "snapshot configure normalizes Snapper policy and services"

# Omarchy CPU defaults to ext4; the configure step is a guarded no-op unless
# the user chose btrfs and installed snapper themselves.
grep -F 'findmnt -no FSTYPE /' "$ROOT/install/config/snapper.sh" >/dev/null ||
  fail "snapshot configure is gated on a btrfs root"
pass "snapshot configure stays opt-in on non-btrfs roots"

setup_system="$ROOT/bin/omarchy-apply-system"
grep -F 'config/all.sh' "$setup_system" >/dev/null ||
  fail "system setup runs the config phase"
grep -F 'config/snapper.sh' "$ROOT/install/config/all.sh" >/dev/null ||
  fail "config phase normalizes Snapper"
pass "system setup normalizes Snapper during fresh installs"

migration=$(grep -rl 'Normalize Snapper snapshot services' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "Snapper service migration exists"
grep -F 'unit_active snapper-cleanup.timer' "$migration" >/dev/null
grep -F 'sudo "$@"' "$migration" >/dev/null
grep -F 'as_root env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"' "$migration" >/dev/null
! grep -F 'NUMBER_LIMIT="5"' "$migration" >/dev/null || fail "Snapper service migration does not overwrite working custom retention"
pass "Snapper service migration only repairs broken services idempotently"
