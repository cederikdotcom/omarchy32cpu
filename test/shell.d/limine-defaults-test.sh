#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

packaged_defaults="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"

if [[ ! -f $packaged_defaults && -f $ROOT/bin/omarchy-refresh-grub ]]; then
  pass "GRUB fork has no packaged Limine defaults to validate"
  exit 0
fi

grep -Fq 'KERNEL_CMDLINE[default]+=" initramfs_async=0"' "$packaged_defaults" ||
  fail "the packaged Limine defaults still unpack the initramfs synchronously"
pass "packaged Limine defaults keep Plymouth alive at the LUKS prompt"
