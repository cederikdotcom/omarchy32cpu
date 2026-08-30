# omarchy32cpu release notes

**Omarchy CPU, 32-bit** ("omarchy32cpu"): pure CPU-bound Omarchy on
archlinux32 i686. Based on upstream Omarchy v4.0.1 "Quattro". First
target hardware: 2006 Apple MacBook1,1 (A1181, EMC 2092).

Status: pre-release. Everything below reflects the state validated on
the cloud test bench on 2026-08-30. The port has not yet touched the
real MacBook.

## What this release is

The full Omarchy workflow with every pixel drawn by the CPU:

- sway 1.8 with the wlroots pixman renderer replaces Hyprland
- waybar + fuzzel + mako + swaylock replace the Quickshell desktop,
  behind shims that keep the omarchy-* calling contracts
- greetd + tuigreet replace SDDM (with upstream-style autologin into
  the session)
- GRUB i386-efi as BOOTIA32.EFI replaces limine + 64-bit UKI
- archlinux32 i686 repos replace Arch x86_64 + pkgs.omarchy.org
- No preinstalled applications: a 46-package core, the user installs
  their own apps
- Kept unchanged: the 24-color theme engine, the bash environment, the
  omarchy CLI router, keybinding philosophy, zram/oomd memory tuning

## Validated (cloud bench: i686 chroot + QEMU with IA32 OVMF firmware)

- `omarchy-apply-system --install-user cederik --first-install` runs
  END TO END with exit 0 in the target chroot
- Boot chain: 32-bit UEFI firmware -> BOOTIA32.EFI (installed by the
  fork's own `omarchy-refresh-grub`) -> GRUB -> i686 kernel -> greetd
  (config written by the fork's `install/login/greetd.sh`) -> sway
- sway configs validate with `sway -C` on sway 1.8/i686; a full
  session renders on the VM display with the pixman renderer
- All 24 former `omarchy-hyprland-*` scripts plus `omarchy-compositor-ctl`
  live-tested against a running sway session on i686
- Theme pipeline renders sway/waybar/mako/swaylock for 3 themes with
  zero unreplaced tokens; rendered sway files validate
- `test/cli`: 116/116 pass

## Fixed during validation (would have broken a real install)

1. `ufw` was missing from the package set; `install/config/firewall.sh`
   hard-fails without it. Added to the core.
2. `sudo` was missing; the hardware install phase and much of bin/
   depend on it. Added to the core.
3. `bluez`/`bluez-utils` were missing while `install/hardware/bluetooth.sh`
   enables bluetooth.service (and the A1181 has a working BCM2045).
   Added; the script now also skips cleanly when bluez is absent.
4. `plocate` was missing; `install/post-install/localdb.sh` runs
   updatedb unconditionally. Added to the core.
5. `install/config/firewall.sh` carried Docker-era rules and, worse,
   re-running it inside a chroot after UFW was enabled loads deny-all
   rules into the SHARED HOST KERNEL (it firewalled the build host off
   the network mid-validation). Docker rules removed; a chroot guard
   added. Treat this as a hard lesson for any chroot-side install work.
6. pango 1:1.57.1 on archlinux32 needs fontconfig >= 2.16 but the repo
   ships 2:2.14.1; sway dies with `undefined symbol:
   FcConfigSetDefaultSubstitute`. Fixed by a self-built fontconfig
   2:2.18.3 i686 package (docs disabled, meson >= 1.11 from pip). This
   override is currently installed BY HAND - see "Missing" below.

## Missing / open items

### Blocking a real MacBook install

- **Fork package repo does not exist yet.** The fontconfig 2.18.3
  override (mandatory - sway will not start without it) and future
  i686 rebuilds (mbpfan, isight-firmware-tools, drift fixes) need a
  hosted pacman repo wired into default/pacman/*.conf. Until then the
  override installs manually per the runbook.
- **No install ISO.** The install path is: boot the archlinux32 ISO,
  partition, pacstrap the core list, put the repo at /usr/share/omarchy,
  create the user, run omarchy-apply-system. The ISO-layer duties are
  manual and documented in docs/runbooks/a1181-install.md: target
  pacman.conf (Architecture = i686 + mirrorlist), keyring init and
  populate, locale/vconsole/hostname/fstab, initramfs MODULES
  (ahci sd_mod i915 on the Mac), user creation. An IA32-bootable
  custom ISO is a later milestone.
- **GMA 950 render floor untested.** sway/pixman is proven on i686 in
  QEMU, but the real i945 KMS path needs the on-hardware spike
  (worklist 14). i3/X11 with the modesetting driver is the fallback.
- **mbpfan and isight-firmware-tools** are not in archlinux32 repos;
  they must be built for the fork repo. Until then: no fan management
  daemon, no webcam. `install/hardware/apple/fix-a1181.sh` skips them
  gracefully.

### Not ported yet (deliberate deferrals)

- **Provisioning flows** (`omarchy-provision-owner`,
  `omarchy-system-factory-reset`/`-finish`) still reference SDDM
  autologin and limine. Irrelevant for a manual install; rework when
  provisioning matters.
- **Migrations** are upstream's x86_64/Hyprland-era set, effectively
  pinned by the fork's divergence. New fork migrations start fresh.
  `omarchy-update` against upstream channels is untested and should be
  considered broken until the fork repo and update-guard are wired.
- **Storage/FDE polish** (worklist 11): `omarchy-hibernation-setup`
  (btrfs swapfile) should be dropped; `omarchy-drive-password` argon2id
  cost is not yet retuned for a 2 GB Core Duo.
- **Test suite**: test/cli fully passes; the Quickshell/Hyprland-era
  test/shell.d suite is being triaged (obsolete tests pruned, portable
  ones rewritten, regressions fixed).

### Permanently absent on this stack (not bugs)

- Animations, blur, shadows, rounded corners, per-window opacity
  (pixman renders none of these)
- Portal screen sharing / screencast (xdg-desktop-portal-wlr does not
  support the pixman renderer); wf-recorder with CPU x264 works for
  short local clips
- Monitor mirroring (sway 1.8 has none); clamshell and output toggling
  work
- Hardware video decode and Vulkan (the GPU never had them)

### Downgraded to stubs (print a notice, exit 0)

- `omarchy-hyprland-window-transparency-toggle`,
  `-single-square-aspect-toggle`, `-monitor-internal-mirror`
- The Quickshell plugin/bar-widget system (`omarchy-menu-plugin`,
  bar widget IPC, panel apps: media source switch, speedtest, wifiqr,
  weather panels, idle status)
- Hyprland-only bindings with no sway 1.8 equivalent: pseudotile,
  maximize, universal copy/paste key injection, cursor zoom
- `omarchy-bar` Quickshell config subcommands (use/reset/position/...)

### Behavioral differences from upstream

- `omarchy-hyprland-monitor-watch` polls output topology every 2s
  (sway 1.8 IPC has no output event)
- Nightlight is wlsunset at a fixed 4000K toggle (hyprsunset had
  gradual control); state tracked in a file, wlsunset has no IPC
- The color picker is grim+slurp based (`omarchy-capture-color`)
- OSD is mako notifications with progress hints, not an overlay
- The menu is fuzzel dmenu (text), not the Quickshell panel
- greetd autologin replaces SDDM autologin; the tuigreet fallback
  greeter is text-mode
- No browser ships. For one: Mozilla's official i686 Firefox tarball
  (verify glibc compat), or archlinux32's dated packages at your own
  risk. Chromium-specific tooling (webapp launcher hosts, extensions)
  was removed.

## Install

See docs/runbooks/a1181-install.md (the authoritative procedure,
including the manual ISO-layer duties above) and
docs/runbooks/testbench.md for the QEMU rehearsal environment.
