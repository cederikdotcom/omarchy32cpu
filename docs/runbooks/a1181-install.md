# Runbook: install Omarchy CPU (32-bit) on the MacBook1,1

Status: REHEARSED END TO END 2026-08-30 in the test-bench VM (32-bit
UEFI firmware -> BOOTIA32.EFI -> GRUB -> i686 kernel -> greetd -> a
session with the pixman renderer on screen). See
docs/a1181-gap-analysis.md for the plan and testbench.md for the VM.

MID-MIGRATION WARNING: that rehearsal ran the sway session this fork
used before the pixman renderer for Hyprland existed. sway is now
deleted and the session is upstream Hyprland on the pixman renderer, so
step 5b below is new and the rehearsal has not been repeated. The i686
compositor build is also the hardest part of this runbook: archlinux32
carries no aquamarine, hyprcursor or hyprgraphics, its hyprutils and
hyprlang are far too old, and its newest lua is 5.4 while Hyprland 0.56
requires 5.5. All of those have to be built for i686 alongside the two
override packages below. Open items: that build, and the on-hardware
GPU spike.

The Quickshell desktop is back as well, so step 5c is new too: the shell
under `shell/` is the real upstream QML again, drawn by Qt Quick's
software scenegraph on top of the pixman compositor. It builds and runs
on i686, with two features switched off (audio and the crash handler)
for want of new enough archlinux32 packages. Its cost on a 2 GB machine
is the one number nobody has measured yet.

Rehearsal lessons now baked into the steps below:
- Set `Architecture = i686` in /etc/pacman.conf of the installed system
  (the default `auto` misdetects in chroots) and write a real
  mirrorlist; pacstrap -M does not copy one.
- Write /etc/vconsole.conf (e.g. `KEYMAP=us`) before mkinitcpio runs or
  the image build errors out.
- greetd: both sessions launch
  `/usr/share/omarchy/bin/omarchy-hyprland-launch` (the `[initial_session]`
  boots straight into the desktop, matching upstream's autologin UX).
  The wrapper sets `HYPRLAND_RENDERER=pixman`, `AQ_FORCE_ALLOCATOR=dumb`,
  OMARCHY_PATH and the systemd user bus; never wrap the session in
  dbus-run-session (its private bus splits notifications and user units
  apart).
- grub-install for i386-efi with `--removable --no-nvram` needs no
  efibootmgr and no NVRAM access; it just places BOOTIA32.EFI.

## Scope

- Target: MacBook1,1 (early 2006 Core Duo, A1181, EMC 2092) on
  archlinux32 i686. 2 GB RAM cap; max it (2x1 GB).
- Omarchy Lite: no preinstalled applications. The 80-package core is
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
   "archlinux32 findings"). If installs abort on "marginal trust"
   signatures, run
   `pacman-key --lsign-key 80EC18799E8BCD375C6E64ABE4D41569196B1160`
   (the TasosSah packaging key).
4. `pacstrap` base, linux, linux-firmware, then the Lite core from
   `install/omarchy-base.packages` on this branch.
5. Install the two i686 override packages (see "Override packages"
   below). fontconfig is mandatory: without it the desktop's text
   stack does not start.
5b. Build and install the compositor. `install/omarchy-base.packages`
   deliberately does not carry Hyprland: the session needs this fork's
   build, which adds the pixman (CPU) renderer.

   - cederikdotcom/Hyprland, branch `pixman-renderer` (base v0.56.2)
   - cederikdotcom/aquamarine, branch `cpu-backend` (base v0.15.0)

   On i686 their dependencies have to be built too: aquamarine,
   hyprcursor and hyprgraphics are absent from archlinux32, hyprutils
   (0.2.6) and hyprlang (0.5.2) are far below what Hyprland 0.56 needs,
   and lua 5.5 (required, `lua>=5.5 lua<5.6`) is absent - archlinux32's
   newest is 5.4.7. Everything else Hyprland links (pixman, cairo,
   pango, libdrm, libinput, libxkbcommon, libei, lcms2, muparser, re2,
   tomlplusplus, mesa, xorg-xwayland) is in the repos and in the core
   package list. Until a fork package repo exists this step is
   manual.
5c. Build and install the shell. The Omarchy desktop is Quickshell: the
   bar, menu, notifications, OSD, wallpaper, lock screen, tray and the
   whole plugin system are QML under `shell/`. Quickshell is in neither
   official Arch nor archlinux32 (upstream installs it from
   pkgs.omarchy.org), so it is the second thing the fork cannot package
   and is built from source like the compositor.

   Its runtime dependencies are in the core package list already. Its
   build-only dependencies are not, and all of them exist on
   archlinux32:

   ```bash
   pacman -S --needed --asdeps cmake ninja pkgconf git cli11 \
     qt6-shadertools spirv-tools wayland-protocols vulkan-headers
   ```

   `vulkan-headers` is headers only; there is no runtime Vulkan
   requirement, which matters on a machine whose GPU never had it.

   ```bash
   git clone --depth 1 --branch v0.3.1 \
     https://github.com/quickshell-mirror/quickshell /opt/quickshell
   cd /opt/quickshell
   cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
     -DDISTRIBUTOR="omarchy32cpu" \
     -DCRASH_HANDLER=OFF \
     -DSERVICE_PIPEWIRE=OFF \
     -DINSTALL_QML_PREFIX=lib/qt6/qml
   ninja -C build && ninja -C build install
   ```

   Two flags are i686-specific and both cost a feature:

   - `-DSERVICE_PIPEWIRE=OFF` because archlinux32 ships pipewire
     0.3.65 and Quickshell's pipewire service needs
     `pw_core_events.bound_props`, which is newer. Without it the
     build fails; with it `omarchy.audio` has no source and the bar
     has no volume control. Building a newer pipewire as a third i686
     override package is the way out, and has not been done.
   - `-DCRASH_HANDLER=OFF` because the handler needs `cpptrace`,
     which archlinux32 does not carry at all.

   **Also install the icu75 shim**, or Quickshell will not start:
   archlinux32's `qt6-base` 6.7.2 was built against ICU 75 and links
   `libicui18n.so.75`, while the repo's `icu` is 78. This is the same
   class of drift as the fontconfig and libxml2 problems below, but
   archlinux32 already carries the legacy package, so it needs no
   override of ours:

   ```bash
   pacman -S icu75
   ```

   **Quickshell links private Qt APIs** and must be rebuilt whenever
   `qt6-base` or `qt6-declarative` is upgraded, or it dies on an ABI
   mismatch. Pin those two if you are not prepared to rebuild.

   RAM is the open question on this machine, not correctness. The
   x86_64 spike measured the full shell at 245 MB RSS; the shim stack
   it replaces (waybar + mako + swaybg) was 96 MB, so expect roughly
   +150 MB on a 2 GB machine. zram makes that affordable but not free,
   and a good slice of it is image caching in the Background and
   ImagePicker plugins. If it is too much, trim the plugin set before
   giving up on the shell. **This has not been measured on the real
   MacBook** - it is exactly the kind of number a hardware report
   should carry.
6. Put the repo at /usr/share/omarchy, create the user, then run
   `omarchy-apply-system --install-user <user> --first-install` in the
   chroot (validated end to end: config, hardware, greetd login,
   post-install).
7. User stage (upstream's omarchy package seeds /etc/skel; the fork
   has no package yet, so do it by hand): as the user,
   `cp -r /usr/share/omarchy/config/* ~/.config/`, then
   `omarchy-provision-user --first-install --force` with
   OMARCHY_PATH=/usr/share/omarchy and the fork's bin on PATH.
8. Bootloader: `omarchy-refresh-grub` in the chroot. On a first run it
   installs GRUB as `BOOTIA32.EFI` in the removable fallback path
   (`grub-install --target=i386-efi --efi-directory=/boot --removable
   --no-nvram`, which needs no efibootmgr and no NVRAM access), then
   writes grub.cfg. A 32-bit kernel boots natively from the 32-bit
   Apple EFI; there is no mixed mode.
   Optional Apple boot picker entry: `grub-mkstandalone -O i386-efi -o
   /boot/System/Library/CoreServices/boot.efi` on a blessed HFS+ helper
   partition.
9. Reboot. greetd starts `/usr/share/omarchy/bin/omarchy-hyprland-launch`
   (autologin into Hyprland with the pixman renderer). Note ufw comes up
   enforcing deny-incoming; `ufw allow` for anything you need (rules
   cannot be added from inside a chroot).

## Override packages

archlinux32 ships two packages that are too old for other packages in
the same repo. Both overrides are plain Arch PKGBUILD rebuilds for
i686: no fork source change, no patches. They are published as GitHub
release assets on this repo, because the fork has no pacman repo of its
own (see RELEASE-NOTES, "Missing / open items").

Release: https://github.com/cederikdotcom/omarchy32cpu/releases/tag/overrides-i686-20260831

```bash
# fontconfig 2:2.18.3-2 - MANDATORY. archlinux32 ships 2:2.14.1 while its
# pango 1:1.57.1 needs >= 2.16; without this the desktop dies at startup
# with "undefined symbol: FcConfigSetDefaultSubstitute".
sudo pacman -U https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/fontconfig-2.18.3-2-i686.pkg.tar.zst

# neatvnc 0.8.1-3 - only needed for omarchy-remote-view. archlinux32 ships
# wayvnc 0.8.0 against neatvnc 0.5.4; without this wayvnc dies with
# "undefined symbol: nvnc_client_get_auth_username".
sudo pacman -U https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/neatvnc-0.8.1-3-i686.pkg.tar.zst
```

Order matters for neatvnc: `pacman -S wayvnc` pulls the repo's neatvnc
0.5.4 and clobbers the override, so install wayvnc first (it is in the
core package list) and the override second. Both overrides carry a
higher version than the repo package, so a later `pacman -Syu` will not
pull them back down.

Verified 2026-08-31 in an archlinux32 i686 chroot: after the neatvnc
override, `ldd -r /usr/bin/wayvnc` reports 0 undefined symbols and
`wayvnc --version` prints `v0.8.0-15d09b0 / neatvnc: v0.8.1-0708156`.

Rebuild them yourself if you would rather not trust a release asset:
take the Arch PKGBUILD for the package, and in an i686 chroot run
`makepkg -A --nocheck --skippgpcheck -d`. fontconfig needs
`-Ddoc=disabled` (the docbook DTDs are missing on archlinux32) and meson
>= 1.11 from pip. neatvnc needs `provides=(libneatvnc.so)` in the
PKGBUILD or pacman will refuse the install as breaking wayvnc's
`libneatvnc.so=0-32` dependency.

## Common operations

- Refresh boot entries after a kernel update: `omarchy-refresh-grub`.
- Theme switch: `omarchy-theme-set <name>` (renders the hyprland
  template and hands the palette to the running shell over IPC).
- Fan control: mbpfan as a service; temps via `sensors` (applesmc).
- Remote view: `omarchy-remote-view on` (or menu: Trigger > Toggle >
  Remote View) serves the session on 127.0.0.1:5901; from another
  machine: `ssh -L 5901:127.0.0.1:5901 <user>@<host>`, then VNC to
  localhost:5901.

## Troubleshooting

- **The session dies with a fontconfig symbol error:** the fork's
  fontconfig override is missing. Install it from the fork repo (or
  rebuild fontconfig >= 2.16 from the Arch PKGBUILD with docs disabled
  and meson >= 1.11 from pip).
- **Hyprland exits complaining about GLES 3.0:** the installed Hyprland
  or aquamarine is a stock build, not the fork's. Only the fork's
  branches carry the pixman renderer.
- **Black screen on session start:** confirm `HYPRLAND_RENDERER=pixman`
  and `AQ_FORCE_ALLOCATOR=dumb` reached the compositor (the log names
  the renderer it selected); check `dmesg | grep i915` for KMS errors.
  Fall back to i3/X11 with the modesetting driver.
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
