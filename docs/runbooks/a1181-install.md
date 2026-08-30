# Runbook: install Omarchy CPU (32-bit) on the MacBook1,1

Status: REHEARSED END TO END 2026-08-30 in the test-bench VM (32-bit
UEFI firmware -> BOOTIA32.EFI -> GRUB -> i686 kernel -> greetd -> sway
with the pixman renderer on screen). Only the on-hardware GPU spike is
open. See docs/a1181-gap-analysis.md for the plan and testbench.md for
the VM.

Rehearsal lessons now baked into the steps below:
- Set `Architecture = i686` in /etc/pacman.conf of the installed system
  (the default `auto` misdetects in chroots) and write a real
  mirrorlist; pacstrap -M does not copy one.
- Write /etc/vconsole.conf (e.g. `KEYMAP=us`) before mkinitcpio runs or
  the image build errors out.
- greetd: both sessions launch
  `/usr/share/omarchy/bin/omarchy-sway-launch` (the `[initial_session]`
  boots straight into sway, matching upstream's autologin UX). The
  wrapper sets the pixman renderer, OMARCHY_PATH, and the systemd user
  bus; never wrap the session in dbus-run-session (its private bus
  splits notifications and user units apart).
- grub-install for i386-efi with `--removable --no-nvram` needs no
  efibootmgr and no NVRAM access; it just places BOOTIA32.EFI.

## Scope

- Target: MacBook1,1 (early 2006 Core Duo, A1181, EMC 2092) on
  archlinux32 i686. 2 GB RAM cap; max it (2x1 GB).
- Omarchy Lite: no preinstalled applications. The ~45-package core is
  listed in the gap analysis.

## Prepare install media

1. Write the archlinux32 ISO (archisos on mirror.archlinux32.org,
   2024.07.10 or later) to USB.
2. If the Apple EFI does not boot it, add a 32-bit GRUB to the USB EFI
   partition as `EFI/BOOT/BOOTIA32.EFI` (`grub-mkstandalone -O
   i386-efi`), or burn a CD and boot via CSM (hold Alt, pick the
   "Windows" entry).

## Install

1. Boot the media, connect wifi (ath5k works in-tree).
2. Partition: GPT with a 512 MB ESP (FAT32) and an ext4 root. FDE is
   opt-in; if used, lower the argon2id cost first.
3. Pacman setup: `Architecture = i686`, mirror
   `https://mirror.archlinux32.org/i686/$repo`, install
   archlinux32-keyring and populate it. Known rough edges: occasional
   stale package signatures and dependency drift (see gap analysis,
   "archlinux32 findings"); the fork repo carries rebuilt overrides,
   fontconfig 2.18.3 first. Without the override, sway fails with
   `undefined symbol: FcConfigSetDefaultSubstitute`.
4. `pacstrap` base, linux, linux-firmware, then the Lite core from
   `install/omarchy-base.packages` on this branch.
5. Bootloader, inside the chroot:
   - `grub-install --target=i386-efi --efi-directory=/boot --removable`
     (installs `BOOTIA32.EFI`; a 32-bit kernel boots natively, no mixed
     mode)
   - Optional Apple boot picker entry: `grub-mkstandalone -O i386-efi -o
     /boot/System/Library/CoreServices/boot.efi` on a blessed HFS+
     helper partition.
   - `grub-mkconfig -o /boot/grub/grub.cfg`
6. Put the repo at /usr/share/omarchy, create the user, then run
   `omarchy-apply-system --install-user <user> --first-install` in the
   chroot (validated end to end: config, hardware, greetd login,
   post-install).
7. User stage (upstream's omarchy package seeds /etc/skel; the fork
   has no package yet, so do it by hand): as the user,
   `cp -r /usr/share/omarchy/config/* ~/.config/`, then
   `omarchy-provision-user --first-install --force` with
   OMARCHY_PATH=/usr/share/omarchy and the fork's bin on PATH.
8. Bootloader: `omarchy-refresh-grub` in the chroot (installs
   BOOTIA32.EFI on first run, then writes grub.cfg).
9. Reboot. greetd starts `/usr/share/omarchy/bin/omarchy-sway-launch`
   (autologin into sway with the pixman renderer). Note ufw comes up
   enforcing deny-incoming; `ufw allow` for anything you need (rules
   cannot be added from inside a chroot).

## Common operations

- Refresh boot entries after a kernel update: `omarchy-refresh-grub`.
- Theme switch: `omarchy-theme-set <name>` (renders sway/waybar/mako
  templates).
- Fan control: mbpfan as a service; temps via `sensors` (applesmc).

## Troubleshooting

- **sway dies with a fontconfig symbol error:** the fork's fontconfig
  override is missing. Install it from the fork repo (or rebuild
  fontconfig >= 2.16 from the Arch PKGBUILD with docs disabled and
  meson >= 1.11 from pip).
- **Black screen on sway start:** confirm `WLR_RENDERER=pixman`; check
  `dmesg | grep i915` for KMS errors. Fall back to i3/X11 with the
  modesetting driver.
- **Firmware boots to a folder-with-question-mark:** the EFI entry is
  lost. Boot the USB, chroot, rerun `grub-install --removable`, or
  bless the boot.efi helper from macOS.
- **Wifi drops on ath5k:** disable NM wifi powersave (the
  `fix-a1181.sh` override).
- **iSight webcam absent:** it needs a firmware blob Apple does not
  allow us to redistribute. Install `isight-firmware-tools`, run
  `ift-extract` against `AppleUSBVideoSupport` from a macOS install,
  reload `uvcvideo`.
- **Screen sharing fails in calls:** permanent under the pixman
  renderer. Not a bug.
- **System thrashes:** zram (`zram-size=ram`, zstd) and systemd-oomd
  come configured. On 2 GB, keep heavy apps to one at a time.
