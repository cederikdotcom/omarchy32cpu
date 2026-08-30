# Runbook: install Omarchy 32-bit Lite on the MacBook1,1

Status: boot chain and desktop validated in the cloud test bench (see
testbench.md); the on-hardware GPU spike is still open. See
docs/a1181-gap-analysis.md for the full plan.

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
6. Run the fork's install-script path (`bin/omarchy-apply-system`
   sequence) for configs, theming, greetd and the hardware pass.
7. Reboot. greetd/tuigreet (or autologin) starts the sway session with
   `WLR_RENDERER=pixman`.

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
