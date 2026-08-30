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
- `test/cli`: 116/116 pass; `test/shell`: 155/155 test files pass
  after the triage (39 Quickshell/Hyprland-era tests removed, 46
  ported to the sway/waybar stack)
- Full in-VM desktop battery: sway + waybar + mako + swayidle + swaybg
  all running under greetd autologin with the pixman renderer and the
  systemd user bus; live theme switching re-renders and reloads
  sway/waybar/mako/swaylock; windows spawn and are driven via
  `omarchy-compositor-ctl`; notifications deliver from any shell;
  zero failed systemd units

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
7. waybar links `libxml2.so.2` but the repo's libxml2 is 2.15 (soname
   .16); waybar dies at startup. Fixed by shipping `libxml2-legacy`
   (the second dependency-drift bug of this class; expect more).
8. A whole tier of runtime dependencies was missing from the package
   set and surfaced only when the desktop actually ran: `jq` (62
   scripts), `gum` (39), `xdg-user-dirs`, `xdg-utils`, `wtype` (emoji
   and paste injection), `psmisc` (killall in restart scripts),
   `libpulse` (the media-key volume scripts call pactl), `upower`
   (battery status), `qrencode` (wifi QR menu). All added; the core is
   now 54 packages.
9. The greetd session wrapped sway in `dbus-run-session`, whose
   private bus split notifications and systemd user units onto
   different buses (notifications from any non-session shell failed).
   greetd now launches `omarchy-sway-launch` for both sessions; the
   wrapper pins the systemd user bus and sets OMARCHY_PATH, PATH and
   the pixman renderer for all session children.
10. 28 scripts launch apps via `uwsm-app`, but the port dropped the
   uwsm session manager. A new `uwsm-app` shim (detached exec) keeps
   them all working.
11. `omarchy-refresh-grub` ran grub-mkconfig before grub-install, but
   only grub-install creates /boot/grub on a first run; the first boot
   landed on a bare grub prompt. Order swapped.
12. `omarchy-compositor-ctl` and `omarchy-capture-color` were committed
   without the executable bit.
13. The sway config's theme include glob (`theme/sway*`) also matched
   the rendered `swaylock.args`, so sway parsed swaylock flags as
   config and flagged errors on every theme switch. The rendered file
   is now `sway-colors` with a matching include glob.
14. foot 1.13 (the archlinux32 version) rejects the `[colors-dark]`
   section and `cursor=` inside `[colors]` that the foot template
   rendered; template moved to `[colors]` plus a `[cursor]` section.
15. The test triage across test/shell.d caught 7 more code
   regressions, fixed in commit b6659167 (focus-app matching,
   unported launch-shell/restart-shell, monitor-watch recovery,
   toggle-input-device state, two portable-awk bugs, an omarchy-menu
   field-separator bug that silently dropped menu guards).

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
- **Screen recording is currently broken**: `omarchy-capture-screenrecording`
  still targets gpu-screen-recorder (not shipped, and it has no
  encoder on this GPU anyway). The planned wf-recorder (CPU x264) swap
  has not happened yet.
- **Optional capture/transcode tools are not preinstalled**:
  `omarchy-capture-qr` needs zbar, `omarchy-capture-text` needs
  tesseract, `omarchy-transcode*` needs ffmpeg/imagemagick. The
  scripts error until the user installs them; consider guards or menu
  pruning later.
- **/etc/skel seeding**: upstream's omarchy package (omarchy-pkgs
  repo) populates /etc/skel and /usr/share/omarchy; the fork has no
  package yet, so a manual install copies `config/` into the user's
  ~/.config and runs `omarchy-provision-user --first-install` by hand
  (see the runbook).
- **greetd `initial_session` runs once per boot** (greetd semantics):
  a `systemctl restart greetd` lands on the tuigreet greeter, not
  back in the autologin session. Reboot, or log in via tuigreet.
- Leftover configs for unshipped apps (kitty, ghostty, alacritty,
  obsidian, chromium, hyprland-preview-share-picker) still sit in
  `config/`; harmless, prune later.
- Vestigial bins with no callers remain (omarchy-shell-config, the
  omarchy-plugin-* set, omarchy-install/remove-preinstalls which would
  try to install packages absent from archlinux32).

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
