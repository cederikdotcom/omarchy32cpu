#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/ufw" <<'STUB'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == status ]]; then
  echo 'Status: inactive'
fi
STUB

cat >"$stub_dir/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB

# The script flips ENABLED= in /etc/ufw/ufw.conf with sed -i; log the call
# instead of touching the host's real file.
cat >"$stub_dir/sed" <<'STUB'
#!/bin/bash
printf 'sed %s\n' "$*" >>"$TEST_LOG"
STUB

# The chroot-rerun guard must not trigger on the test host.
cat >"$stub_dir/systemd-detect-virt" <<'STUB'
#!/bin/bash
exit 1
STUB

chmod +x "$stub_dir"/*

export TEST_LOG="$stub_dir/firewall.log"
PATH="$stub_dir:$PATH" bash -eE -c 'source "$1"' bash "$ROOT/install/config/firewall.sh"

grep -q '^ufw default deny incoming$' "$TEST_LOG" || fail "inbound traffic is denied by default"
grep -q '^ufw default allow outgoing$' "$TEST_LOG" || fail "outbound traffic is allowed by default"
grep -q '^ufw allow 53317/udp$' "$TEST_LOG" || fail "LocalSend UDP port is allowed"
grep -q '^ufw allow 53317/tcp$' "$TEST_LOG" || fail "LocalSend TCP port is allowed"
grep -q '^systemctl enable ufw$' "$TEST_LOG" || fail "ufw is enabled for next boot"
grep -q '^sed -i s/\^ENABLED=\.\*/ENABLED=yes/ /etc/ufw/ufw.conf$' "$TEST_LOG" || fail "ufw.conf is marked enabled for next boot"

# The Docker-era rules left with Docker itself; a stray ufw-docker call would
# fail on the Lite package set.
if grep -q 'ufw-docker' "$TEST_LOG"; then
  fail "firewall config still installs Docker-era ufw rules"
fi

# Installs are followed by reboot: the live session's firewall must stay
# untouched, so nothing may call `ufw enable` directly.
if grep -q '^ufw enable$' "$TEST_LOG"; then
  fail "firewall config activated live UFW during install"
fi

pass "firewall config denies inbound, keeps LocalSend, and defers activation to next boot"
