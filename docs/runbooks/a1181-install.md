# Runbook: install Omarchy CPU (32-bit) on the MacBook1,1

Status: REHEARSED END TO END 2026-08-30 in the test-bench VM (32-bit
UEFI firmware -> BOOTIA32.EFI -> GRUB -> i686 kernel -> greetd -> a
session with the pixman renderer on screen). See
docs/a1181-gap-analysis.md for the plan and testbench.md for the VM.

STATE ON 2026-09-02: steps 5b and 5c below were rebuilt from the current
fork HEADs and installed into the i686 VM, and **the full Quickshell
desktop runs on i686 in 2048 MB**: the bar, the tray, the clock and the
theme wallpaper on the pixman compositor with Qt's software scenegraph,
at 1280x800 on the VM's own DRM display. Screenshot evidence and the
memory series are in step 5c. The i686 compositor build is still the
hardest part of this runbook: archlinux32 carries no aquamarine,
hyprcursor or hyprgraphics, its hyprutils and hyprlang are far too old,
and its newest lua is 5.4 while Hyprland 0.56 requires 5.5. All of those
have to be built for i686 alongside the two override packages below.

**One thing still blocks an unattended i686 login, and you will meet it.**
Started by greetd, the session reaches the compositor and the shell and
then Hyprland aborts with `malloc(): invalid size (unsorted)`. It is
heap corruption inside the render pass, it is i686-only so far, and it
did not happen in every run: bringing the compositor and the shell up by
hand succeeded on the second try and then stayed up for the whole
measurement session. Details, backtrace and the workaround are under
"Troubleshooting" below. Expect to fight it on the first login.

The remaining open item is unchanged: the on-hardware GMA 950 spike.

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

   # Two-line pipewire 0.3.65 compatibility patch, see below.
   sed -i '/^[[:space:]]*\.bound_props = nullptr,$/d' src/services/pipewire/core.cpp
   sed -i 's/SPA_KEY_NODE_DESCRIPTION/PW_KEY_NODE_DESCRIPTION/' src/services/pipewire/node.cpp

   cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_INSTALL_PREFIX=/usr \
     -DDISTRIBUTOR="omarchy32cpu" \
     -DCRASH_HANDLER=OFF \
     -DSERVICE_PIPEWIRE=ON \
     -DINSTALL_QML_PREFIX=lib/qt6/qml
   ninja -C build && ninja -C build install
   ```

   `-DCMAKE_INSTALL_PREFIX=/usr` puts the QML modules in
   `/usr/lib/qt6/qml`, beside archlinux32's own Qt. That is the layout
   the i686 desktop was verified on. The x86_64 runbook leaves the
   prefix at cmake's `/usr/local` default and works, so treat this as
   the tested choice rather than a proven requirement.

   `-DCRASH_HANDLER=OFF` because the handler needs `cpptrace`, which
   archlinux32 does not carry at all. That flag still costs a feature.

   **The pipewire service builds ON, with a two-line patch.** The
   previous recipe here said `-DSERVICE_PIPEWIRE=OFF` and gave up the
   bar's volume control with it. That was more than the problem needed.
   archlinux32 still ships pipewire 0.3.65, and exactly two symbols in
   Quickshell's pipewire service are newer than it:

   - `src/services/pipewire/core.cpp` sets `.bound_props = nullptr` in a
     designated initializer for `pw_core_events`. 0.3.65 has no such
     field. The line only writes a null pointer, and the listener
     already announces `PW_VERSION_CORE_EVENTS`, which is 0 on this
     pipewire, so the server never emits that event. Deleting the line
     changes nothing at run time.
   - `src/services/pipewire/node.cpp` reads `SPA_KEY_NODE_DESCRIPTION`,
     which 0.3.65's `spa/node/keys.h` does not define.
     `PW_KEY_NODE_DESCRIPTION` in `pipewire/keys.h` is the same string,
     `"node.description"`.

   Neither edit changes behaviour on a newer pipewire either, so there is
   one recipe for both arches. Verified on i686 2026-09-01: the build
   completes, `ldd -r /usr/bin/quickshell` reports no undefined symbol,
   and the binary links `libpipewire-0.3.so.0`. Whether the audio panel
   is fully functional against a 0.3.65 daemon is still unverified, and a
   hardware report saying so is welcome; what is verified is that it is
   present rather than absent.

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

   **RAM is no longer the open question: the desktop fits.** Measured
   2026-09-02 in the i686 VM cut down to 2048 MB, the same size as the
   MacBook, at the panel's 1280x800:

   | | Quickshell RSS | system in use | left for apps |
   |---|---|---|---|
   | greeter, no session | - | 314 MB | 1641 MB |
   | desktop idle, default wallpaper | 210 MB | 489 MB | 1466 MB |
   | plus a foot terminal | 210 MB | 503 MB | 1452 MB |
   | largest shipped wallpaper | 272 MB | 563 MB | 1392 MB |
   | smallest shipped wallpaper | 144 MB | 439 MB | 1516 MB |

   The compositor is 61 MB of that, Xwayland 45 MB and foot 16 MB. Peak
   `VmHWM` across the wallpaper swaps was 492 MB, because the outgoing,
   incoming and base copies are resident together during a crossfade.
   A 1.3 GB workload, which is a browser with a few tabs, ran on top of
   the idle desktop with 260 MB still free and never touched swap.

   The shell is **smaller on i686 than on x86_64**: 32-bit pointers take
   the fixed part from about 190 MB down to about 135 MB. The rest is
   the wallpaper, held at its full stored resolution:

       RSS ~= 135 MB + the decoded size of the current background

   The backgrounds under `themes/` decode to between 6 MB (1536x1024)
   and 138 MB (10456x3455), median 32 MB, and the default theme's
   default background is 78 MB (6016x3384). On a 1280x800 panel none of
   that resolution is visible, so **the wallpaper is still the lever if
   you want the memory back**: the smallest shipped background saves
   66 MB against the default and 128 MB against the largest.

   zram comes up on its own (see `install/config/memory-tuning.sh`) as a
   1.9 GB device at priority 100. Note that archlinux32's i686 kernel
   offers only `lzo-rle` and `lzo` for zram, so the `zstd` the config
   asks for silently becomes `lzo-rle`: expect about 2:1 rather than
   3:1. It made no difference to any measurement above, because nothing
   ever swapped.

   Do not drop `libvips`. Without it the image picker cannot build
   thumbnails and falls back to the full-resolution originals, which is
   how a single theme becomes several hundred MB. **None of this has
   been measured on the real MacBook** - the VM has no GMA 950 and a
   Core Duo is slower than the emulated one, so the timings will differ
   even where the megabytes do not.
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

The same applies to fontconfig, and it bites in a way that is easy to
miss: `fontconfig` is in `install/omarchy-base.packages`, so pacstrap
and any later `pacman -S --needed` of the core list put the repo's
2:2.14.1 back over the override. Install the override **after** the core
list, not before, and check with `pacman -Q fontconfig` that you still
have `2:2.18.3-2`. If a post-transaction hook prints `undefined symbol:
FcConfigSetDefaultSubstitute`, that is exactly what happened.

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

- **Hyprland aborts with `malloc(): invalid size (unsorted)` and greetd
  drops you on the tuigreet greeter.** This is the open i686 blocker.
  What you see in the journal is two crashes, and only the first one
  matters. The first is heap corruption: glibc aborts at whatever
  allocates next, so the reported site moves around, but a core taken
  from the VM puts it under
  `CHyprPixmanRenderer::endRender -> CRenderPass::render ->
  CRenderPass::simplify -> CRegion::subtract -> pixman_region32_subtract
  -> realloc`, on the DRM page-flip path. The second crash is
  `start-hyprland` restarting the compositor with `--safe-mode`, where
  `CCompositor::openSafeModeBox` calls `CAsyncDialogBox::open` and
  segfaults because `hyprland-dialog` (from `hyprland-qtutils`, absent
  on archlinux32) is not there. So one render bug turns into a login
  loop.

  It is not the CPU model (it reproduces on `-cpu max` as well as
  `-cpu coreduo`), not concurrency alone (it reproduces with one vCPU),
  and not the screencopy portal (it reproduces with
  `xdg-desktop-portal-wlr` masked). The headless i686 harness in the
  build chroot never hits it, which points at the DRM path rather than
  at the renderer's arithmetic in general.

  Until it is fixed, bring the session up by hand and retry: start the
  compositor, and when it survives its first frames start the shell
  against it. That worked on the second attempt and then ran for over an
  hour with a terminal and a 1.3 GB workload on top.

- **The session dies with a fontconfig symbol error:** the fork's
  fontconfig override is missing, or a later `pacman -S` of the core
  package list put the repo's 2:2.14.1 back over it. Reinstall the
  override (or rebuild fontconfig >= 2.16 from the Arch PKGBUILD with
  docs disabled and meson >= 1.11 from pip).
- **Hyprland dies at startup and the log ends with dconf warnings**
  (`failed to commit changes to dconf: Could not connect`): the
  compositor is writing the cursor theme into gsettings, and
  archlinux32's `dconf` is built against a newer glib2 than the repo
  ships, so `dconf-service` cannot start (`undefined symbol:
  g_variant_builder_init_static`). The fork turns that write off in
  `default/hypr/looknfeel.lua` with `cursor.sync_gsettings_theme =
  false`. If you are running an older config, set it yourself.
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
- **System thrashes:** zram (`zram-size=ram`) and systemd-oomd are
  installed and enabled by `install/config/memory-tuning.sh`. Check with
  `swapon --show`; you want a 1.9 GB `/dev/zram0` at priority 100. The
  config asks for zstd and the i686 kernel gives you `lzo-rle`, which is
  the only compressor its zram offers. On 2 GB the desktop itself leaves
  about 1.45 GB free, so one heavy app at a time is comfortable and two
  is where zram starts earning its keep.
