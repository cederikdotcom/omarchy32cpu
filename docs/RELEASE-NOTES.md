# omarchy32cpu release notes

**Omarchy CPU, 32-bit** ("omarchy32cpu"): pure CPU-bound Omarchy on
archlinux32 i686. Based on upstream Omarchy v4.0.1 "Quattro". First
target hardware: 2006 Apple MacBook1,1 (A1181, EMC 2092).

Status: pre-release, mid-migration. Everything below reflects the state
validated on the cloud test bench on 2026-08-30, plus the x86_64
bring-up on 2026-08-31. The port has not yet touched the real MacBook,
or any real hardware at all.

**The compositor changed after those validations.** See "Hyprland
replaces sway" immediately below: every session-level result recorded
further down was obtained with sway.

**Re-obtained on Hyprland for x86_64 on 2026-08-31, and again with the
Quickshell desktop on 2026-09-01.** A VM installed from this tree by the
x86_64 runbook boots, greetd starts the session itself, and `hyprctl
systeminfo` reports `Renderer: pixman (software)` and `Backend: drm`
against a `-vga std` framebuffer with no GPU. The Quickshell bar, the
Omarchy menu on `Super+Space`, the shell's own wallpaper, its
notifications and live theme switching all work, and the shell's process
maps no Mesa driver and holds no `/dev/dri` descriptor. Screenshot:
`docs/pixman-renderer/x86_64-hyprland.png`. The i686 session is the same
exercise on the harder architecture and has not been run yet; nothing
below about i686 or real hardware has changed.

The CPU-only core is architecture-independent, and x86_64 is where most
testing will happen: see `TESTING.md` and
`docs/runbooks/install-x86_64.md`.

## What this release is

The full Omarchy workflow with every pixel drawn by the CPU:

- upstream Hyprland, on this fork's pixman (CPU) renderer, with every
  effect it cannot draw turned off
- the upstream Quickshell desktop, unmodified, drawn by Qt Quick's
  software scenegraph (`QT_QUICK_BACKEND=software`) on top of that
  renderer - bar, menu, notifications, OSD, wallpaper, lock screen,
  tray and the plugin system
- greetd + tuigreet replace SDDM (with upstream-style autologin into
  the session)
- GRUB i386-efi as BOOTIA32.EFI replaces limine + 64-bit UKI
- archlinux32 i686 repos replace Arch x86_64 + pkgs.omarchy.org
- No preinstalled applications: an 80-package core, the user installs
  their own apps
- Kept unchanged: the 24-color theme engine, the bash environment, the
  omarchy CLI router, keybinding philosophy, zram/oomd memory tuning
- New in the fork: `omarchy-remote-view` (menu: Trigger > Toggle >
  Remote View) serves the live session over VNC via wayvnc/wlroots
  screencopy - fully CPU-side, ideal for the cloud-hosted use case.
  Localhost-only; reach it with `ssh -L 5901:127.0.0.1:5901 user@host`

## Hyprland replaces sway (2026-08-31)

sway was only ever a stand-in for a compositor that needed a GPU. It is
gone. This fork's Hyprland (`cederikdotcom/Hyprland`, branch
`pixman-renderer`, base v0.56.2) and aquamarine
(`cederikdotcom/aquamarine`, branch `cpu-backend`, base v0.15.0) add a
pixman software renderer, proven headless, nested and on a real DRM
display in the i686 VM at 0.05 % idle CPU (see
`docs/pixman-renderer/PROGRESS.md`). Carrying a substituted compositor
was permanent repo drift against upstream; this ends it.

What came back, verbatim from upstream: `config/hypr/` and
`default/hypr/` (the whole Lua config layer, 58 files),
`default/themed/hyprland.lua.tpl` and the five per-theme
`hyprland.lua` files, `bin/omarchy-refresh-hyprland`,
`bin/omarchy-restart-hyprctl`, the two Hyprland reload pacman hooks,
`default/uwsm/` and `migrations/1787618700.sh`. What the fork still
owns:

- **Flat mode.** `default/hypr/looknfeel.lua` sets
  `animations.enabled = false`; upstream already had rounding 0 and
  blur and shadows off, so that is the whole flat-mode diff. The
  renderer logs a warning naming any of these left on.
- **Session entry.** `bin/omarchy-hyprland-launch` (replacing
  `omarchy-hyprland-launch`) exports `HYPRLAND_RENDERER=pixman`,
  `AQ_FORCE_ALLOCATOR=dumb` and `QT_QUICK_BACKEND=software`, sources upstream's own
  `default/uwsm/env.d/10-omarchy` for the OMARCHY_PATH/PATH/TERMINAL
  bootstrap, maps `/etc/vconsole.conf` onto `XKB_DEFAULT_*`, and pins
  the systemd user bus. uwsm itself does not come back: it is not
  packaged for archlinux32, and this fork logs in through greetd
  rather than SDDM.
- **Autostart.** `default/hypr/autostart.lua` now differs from upstream
  by one omission: udiskie, which the Lite package set does not carry.
  The swaybg and swayidle stand-ins are gone (see "Quickshell returns").
- **No preinstalled-app bindings.** `config/hypr/hyprland.lua` sets
  upstream's own `omarchy_preinstalled_bindings = false`.
- **Packages.** Hyprland and aquamarine are not in
  `install/omarchy-base.packages`: they come from the fork build until
  a fork package repo exists. The list carries the shared runtime they
  link instead. On archlinux32 their hypr* dependencies and lua 5.5
  have to be built too.

## Quickshell returns, and the shim desktop is retired (2026-09-01)

waybar + fuzzel + mako + swaybg + swaylock are gone. `shell/` is back
from upstream **byte-identical, all 175 files**, and the omarchy-* shims
that faked its IPC over those programs are upstream's scripts again.

This was possible because Qt Quick has a CPU scenegraph, and the spike on
issue #2 proved the real upstream shell runs on it over this fork's pixman
Hyprland with **zero QML changes**: it loads with no QML errors, all 37
plugins register, 20 IPC targets come up, and `Quickshell.Hyprland` needs
nothing. Restoring the compositor first is what made the shell free -
the planned port from `Quickshell.Hyprland` to `Quickshell.I3` was never
needed.

**The environment variable is `QT_QUICK_BACKEND=software`, and only that.**
`QSG_RHI_BACKEND=software` is not a Qt value: that variable selects an RHI
graphics API (`opengl`/`vulkan`/`d3d11`/`metal`/`null`), and Qt answers
`Unknown key "software" for QSG_RHI_BACKEND, falling back to default
backend`. On any machine with Mesa the default then succeeds through
llvmpipe, so the desktop comes up looking correct while costing about
250 MB more RSS. **A working shell is not evidence of CPU rendering.**
Verify with `QSG_INFO=1` and look for `Loading backend software` and no GL
context. `bin/omarchy-hyprland-launch` sets the variable for the whole
session and carries that warning in a comment.

What came back verbatim from upstream: all of `shell/` (175 files);
`bin/omarchy-shell`, `-bar`, `-bar-text-color`, `-menu`, the nine
`omarchy-menu-*` scripts, the four `omarchy-notification-*` scripts,
`-osd`, `-system-lock`, `-launch-shell`, `-restart-shell` and
`-toggle-bar` (20 scripts); `etc/sudoers.d/omarchy-tzupdate`; and 50 test
files. `bin/omarchy-shell-config` and `bin/omarchy-plugin-catalog` were
already upstream's and simply started working again once `shell/` existed.

The plugin system is therefore live again, which was the other half of
issue #2: `omarchy-menu-plugin` is upstream's real implementation rather
than a stub, and `omarchy-plugin-add/enable/clone/remove` have something
to render into.

What the fork still owns here:

- **Packages.** `quickshell` is not in `install/omarchy-base.packages`,
  for the same reason Hyprland is not: it exists in neither official Arch
  nor archlinux32. It is the fork's **second** unpackageable component and
  is built from source per the runbooks. Its runtime dependencies (the
  `qt6-*` set, `jemalloc`, `glib2`, `libxcb`, `wayland`) are in the list
  and verified on both arches.
- **i686 build flags.** `-DSERVICE_PIPEWIRE=OFF` (archlinux32's pipewire
  0.3.65 predates the API Quickshell's audio service needs, so 32-bit has
  no `omarchy.audio` until a newer pipewire is built) and
  `-DCRASH_HANDLER=OFF` (`cpptrace` is absent on archlinux32; kept off on
  x86_64 too so both arches share one recipe). i686 also needs the
  `icu75` legacy package, because its `qt6-base` 6.7.2 links
  `libicui18n.so.75` against a repo `icu` of 78 - the same drift class as
  the fontconfig and libxml2 problems.
- **Four `MultiEffect` uses** are the only shader-dependent QML in the
  tree (tray icon colorization, lock blur, and two masked reveals in
  Background and ImagePicker). The software backend cannot run them. All
  four are cosmetic and three are effects flat mode disables anyway.
  There is no `ShaderEffect` and no particle system anywhere in `shell/`,
  so that is the complete list.

Measured in the x86_64 VM (1280x800, TCG): the shell is 245 MB RSS at
0.1 % idle CPU, against 96 MB for the waybar+mako+swaybg stack it
replaces - but it also subsumes swaylock and swayidle, so the real delta
is about +150 MB. Menu open is 0.49 s end to end, of which 0.29 s is the
`quickshell ipc` client process starting, which a keybinding into the
running shell does not pay. Damage-limited animation costs 0.5 % in
Hyprland; a fullscreen alpha repaint every frame saturates one core, and
that is precisely the case flat mode already avoids.

**Validated end to end from this tree on 2026-09-01** (x86_64 VM, no
GPU): the repo was installed over `/usr/share/omarchy`, the install
stages re-run, and the machine rebooted so **greetd** started the session
through `initial_session`. What that session shows, in
`docs/pixman-renderer/x86_64-hyprland.png`: the Quickshell bar, the
Omarchy menu opened by a real `Super+Space` key event with its icons
drawn, a live notification from the shell's own server, and the shell's
own wallpaper. Switching themes retints bar, menu and wallpaper in both
directions. No `waybar`, `mako`, `swaybg`, `swayidle`, `swaylock` or
`fuzzel` process exists, and no systemd unit failed. The shell loads with
zero QML errors and `QSG_INFO=1` prints exactly one scenegraph line,
`Loading backend software`; its process maps no Mesa driver and holds no
`/dev/dri` descriptor. Fresh RSS on that boot was **264 MB** (PSS
238 MB), close to the spike's 245 MB and above it because the plugin set
is fully loaded rather than newly started.

**Not yet re-validated on i686, and never on real hardware.** The
245 MB figure on a 2 GB MacBook is the open question, and a hardware
report carrying it would be worth more than any further VM work.

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

### Caveat: `grim` is not a faithful instrument for this renderer

Read this before trusting any screenshot above. Under the pixman
renderer a `grim` capture comes from a mirror framebuffer that
`endRender` only refreshes while `needsACopyFB()` is true, and only
inside `finalDamage`. When normal frames stop, the mirror stops with
them and `grim` keeps handing back the last image it held. Captures were
observed byte-identical across steps that visibly changed the screen.

The reliable instrument is the QEMU monitor's `screendump`, which reads
the emulated display itself:

```bash
echo "screendump /opt/o64vm/shot.ppm" | socat - unix-connect:/opt/o64vm/mon.sock
```

Much of the M1-era renderer verification rests on `grim`, so those
results carry some risk and should be re-obtained with `screendump`
before they are treated as settled. The bench runbook
(`hyprdev/BENCH.md`) carries the same warning.

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
   greetd now launches `omarchy-hyprland-launch` for both sessions; the
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
15. Dependency-drift bug number three: archlinux32's wayvnc 0.8.0
   needs neatvnc 0.8 but the repo ships 0.5.4 (undefined symbol at
   startup). Fixed by a self-built neatvnc 0.8.1 i686 package - the
   fork repo's second override, alongside fontconfig.
16. Some archlinux32 packages are signed by a key the shipped keyring
   only marginally trusts (TasosSah packaging key); installs abort
   until `pacman-key --lsign-key 80EC18799E8BCD375C6E64ABE4D41569196B1160`.
   Documented in the install runbook.
17. The test triage across test/shell.d caught 7 more code
   regressions, fixed in commit b6659167 (focus-app matching,
   unported launch-shell/restart-shell, monitor-watch recovery,
   toggle-input-device state, two portable-awk bugs, an omarchy-menu
   field-separator bug that silently dropped menu guards).

## Fixed during the x86_64 bring-up (2026-08-31)

Found by running the same procedure on official Arch x86_64. All four
were fork-wide bugs, not x86_64-specific ones; the first three hit the
i686 install too.

18. `omarchy-provision-user` ended by hard-setting Chromium as the
   default browser and HEY as the mailto handler. This fork ships no
   applications, `xdg-settings` exits non-zero on a missing .desktop,
   and the script runs under `set -e` - so the documented user stage
   aborted before `omarchy-done mark finalize-user`. Both defaults are
   now conditional on the handler existing.
19. `Super+Return` did nothing. `omarchy-launch-terminal` execs
   `xdg-terminal-exec`, which is an AUR package and is in neither the
   core package set nor the archlinux32 repos. It now falls back to
   foot, which the core does ship, and `$TERMINAL` follows the same
   rule.
20. The core package list carried no fonts at all, so the menu, the bar
   and the notifications drew their glyphs as tofu boxes and foot could
   not find the `JetBrainsMono Nerd Font` its config asks for. Added
   `noto-fonts`, `noto-fonts-emoji` and `ttf-jetbrains-mono-nerd`; all
   three exist in both archlinux32 and official Arch. The Omarchy icon
   font (`default/fonts/omarchy/omarchy.ttf`) is a repo asset that
   upstream's package installs system-wide and the fork never installed
   anywhere; a new `install/user/fonts.sh` seeds it per user.
21. `install/post-install/pacman.sh` unconditionally overwrote
   /etc/pacman.conf and the mirrorlist with the archlinux32 configs
   (`Architecture = i686`, mirror.archlinux32.org). On x86_64 that
   destroyed pacman. It now applies them only when `uname -m` reports
   i686. `omarchy-refresh-grub` had the same problem in the other
   direction - it hardcoded `--target=i386-efi` / `BOOTIA32.EFI` - and
   now picks the target from `uname -m`.

## Missing / open items

### Blocking a real MacBook install

- **Fork package repo does not exist yet.** The two overrides -
  fontconfig 2:2.18.3 (mandatory: the desktop's text stack will not
  start without it) and
  neatvnc 0.8.1 (needed by wayvnc remote view) - are now published as
  GitHub release assets and installed with `pacman -U` per the runbook:
  https://github.com/cederikdotcom/omarchy32cpu/releases/tag/overrides-i686-20260831
  That is a stopgap, not a repo. Future i686 rebuilds (mbpfan,
  isight-firmware-tools, drift fixes) still want a real hosted pacman
  repo wired into default/pacman/*.conf.
- **Two components cannot be packaged at all yet, and must be built from
  source by every tester.** This is the single biggest install-friction
  item in the fork:
  1. **Hyprland + aquamarine** (this fork's branches), because the pixman
     renderer exists nowhere else.
  2. **quickshell** 0.3.1, because it is in neither official Arch nor
     archlinux32 - upstream gets it from pkgs.omarchy.org, which serves
     x86_64 only. Exact build commands per arch are in
     `docs/runbooks/install-x86_64.md` (step 10) and
     `docs/runbooks/a1181-install.md` (step 5c). Note that Quickshell
     links private Qt APIs and has to be rebuilt on every `qt6-base` /
     `qt6-declarative` upgrade, so a fork repo needs to rebuild it in
     lockstep with Qt rather than merely host it once.
- **No install ISO.** The install path is: boot the archlinux32 ISO,
  partition, pacstrap the core list, put the repo at /usr/share/omarchy,
  create the user, run omarchy-apply-system. The ISO-layer duties are
  manual and documented in docs/runbooks/a1181-install.md: target
  pacman.conf (Architecture = i686 + mirrorlist), keyring init and
  populate, locale/vconsole/hostname/fstab, initramfs MODULES
  (ahci sd_mod i915 on the Mac), user creation. An IA32-bootable
  custom ISO is a later milestone.
- **GMA 950 render floor untested.** the pixman renderer is proven on
  i686 in QEMU, but the real i945 KMS path needs the on-hardware spike
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
- foot's colors section differs by version: foot 1.27 (Arch x86_64)
  wants `[colors-dark]` and deprecates `[colors]`; foot 1.13
  (archlinux32) rejects `[colors-dark]` outright. Fixed by probing the
  installed binary with `foot --check-config` after each theme render
  (`omarchy-theme-set-foot-section`) rather than pinning a version, so
  both arches get a clean, warning-free terminal.
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
  support the pixman renderer, and xdg-desktop-portal-hyprland is not
  in archlinux32); wf-recorder with CPU x264 works for short local
  clips
- Hardware video decode and Vulkan (the GPU never had them)

### Downgraded to stubs (print a notice, exit 0)

- `omarchy-hyprland-window-transparency-toggle` and
  `-single-square-aspect-toggle`

That is the whole list now. The Quickshell plugin and bar-widget system,
the panel apps (media source switch, speedtest, wifiqr, weather, idle
status), `omarchy-menu-plugin` and the `omarchy-bar` config subcommands
are all real again - see "Quickshell returns" above.
`omarchy-hyprland-monitor-internal-mirror` was already upstream's code
after the compositor swap; only its menu row was missing, and that is
back too.

The Hyprland-only bindings the sway port had to drop (pseudotile,
maximize, universal copy/paste key injection, cursor zoom) and monitor
mirroring all come back with the compositor; cursor zoom is the one
that will not, because the pixman renderer has no zoom stage.

### Behavioral differences from upstream

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

- `docs/runbooks/install-x86_64.md` - the x86_64 path: no override
  packages, ordinary UEFI, and a copy-pasteable QEMU line for a VM with
  no GPU. Rehearsed end to end 2026-08-31.
- `docs/runbooks/a1181-install.md` - the authoritative i686 procedure,
  including the manual ISO-layer duties above and the two override
  packages.
- `docs/runbooks/testbench.md` - the QEMU rehearsal environment.
- `TESTING.md` - what to test and how to report it.
