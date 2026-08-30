# Runbook: install the A1181 fork on a MacBook2,1

Status: pre-hardware-validation. Steps marked SPIKE are the first thing to
run on the real machine. See `docs/a1181-gap-analysis.md` for the why.

## Scope

The fork ships as Omarchy Lite: no preinstalled applications. Two tracks
(see docs/a1181-gap-analysis.md, "Scope decision"):

- Track A, branch `a1181-compat`: MacBook2,1 (late 2006 Core 2 Duo) and
  later Core 2 Duo A1181s, on official Arch x86_64. Max the RAM first
  (2x2 GB gives ~3 GB usable). This runbook describes Track A.
- Track B, branch `a1181-32` (planned): MacBook1,1 (early 2006 Core Duo,
  EMC 2092), on archlinux32 i686. Same steps apply with three changes:
  use the archlinux32 ISO and mirrors, skip the mixed-mode note (a 32-bit
  kernel boots natively on the 32-bit EFI), and expect the 2 GB RAM cap.

## Prepare install media

1. Write the stock Arch ISO to USB.
2. Apple's IA32 EFI cannot boot the ISO's 64-bit loader. Pick one:
   - Add an i386-efi GRUB to the USB EFI partition as
     `EFI/BOOT/BOOTIA32.EFI` (`grub-mkstandalone -O i386-efi`), pointing at
     the ISO's kernel and initramfs, or
   - Burn a CD and boot via the Mac's BIOS/CSM compatibility path
     (hold Alt at the chime, pick the "Windows" entry).

## SPIKE: validate the render floor first

Before porting anything, on a minimal Arch install:

1. Install `sway`, `foot`, `mesa`. Confirm `/usr/lib/dri/i915_dri.so`
   exists (present in mesa 1:26.2.1-1 and later).
2. Try plain `sway` (GLES2 renderer on i915g).
3. Try `WLR_RENDERER=pixman sway`.
4. If neither is usable at 1280x800, fall back to i3/X11 with the
   modesetting driver and adjust the fork plan (gap analysis, worklist
   items 4-7).

## Install

1. Boot the media, connect wifi (`iwctl`; ath9k works in-tree).
2. Partition: GPT with a 512 MB ESP (FAT32) and an ext4 root. Prefer ext4
   over btrfs on the 5400 rpm disk. FDE is opt-in; if used, lower the
   argon2id cost (see `bin/omarchy-drive-password` in the fork).
3. `pacstrap` base, linux, linux-firmware, then the fork package set from
   `install/omarchy-base.packages` (a1181 branch).
4. Bootloader, inside the chroot:
   - `grub-install --target=i386-efi --efi-directory=/boot --removable`
     (installs `BOOTIA32.EFI`)
   - Optional Apple boot picker entry: `grub-mkstandalone -O i386-efi -o
     /boot/System/Library/CoreServices/boot.efi` on an HFS+ blessed helper
     partition.
   - `grub-mkconfig -o /boot/grub/grub.cfg`
5. Run the fork's install-script path (`bin/omarchy-apply-system` sequence)
   for configs, theming, greetd and the hardware pass.
6. Reboot. greetd/tuigreet (or autologin) starts the sway session.

## Common operations

- Refresh boot entries after a kernel update: `omarchy-refresh-grub`
  (fork replacement for `omarchy-refresh-limine`).
- Theme switch: `omarchy-theme-set <name>` (renders sway/waybar/mako
  templates in the fork).
- Fan control: mbpfan runs as a service; temps via `sensors` (applesmc).

## Troubleshooting

- **Black screen on sway start:** try `WLR_RENDERER=pixman`; if already
  set, check `dmesg | grep i915` for KMS errors. Fall back to i3/X11.
- **Firmware boots to a folder-with-question-mark:** the EFI entry is
  lost. Boot the USB, chroot, rerun `grub-install --removable`, or bless
  the boot.efi helper from macOS.
- **Wifi drops on ath9k:** confirm NM powersave is off
  (`etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf` override from
  `install/hardware/apple/fix-a1181.sh`).
- **iSight webcam absent:** it needs a firmware blob Apple does not allow
  us to redistribute. Install `isight-firmware-tools` and run
  `ift-extract` against `AppleUSBVideoSupport` from a macOS install, then
  reload `uvcvideo`.
- **Screen sharing fails in calls:** permanent under the pixman renderer
  (xdg-desktop-portal-wlr does not support screencast there). Not a bug.
- **System thrashes:** zram (`zram-size=ram`, zstd) and systemd-oomd are
  configured upstream and kept in the fork. Close Chromium tabs; each
  webapp window costs 300-500 MB.
