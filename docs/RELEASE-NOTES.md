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
**440 MB more RSS** - measured in this VM, same wallpaper, same
1280x800: 234 MB on the software backend against 672 MB fresh and
698 MB settled through llvmpipe, which loads `libgallium` and
`libEGL_mesa` and still opens no `/dev/dri` descriptor. **A working
shell is not evidence of CPU rendering.**
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
- **i686 build flags.** `-DCRASH_HANDLER=OFF` (`cpptrace` is absent on
  archlinux32; kept off on x86_64 too so both arches share one recipe)
  and, on i686, `-DCMAKE_INSTALL_PREFIX=/usr` so the QML modules land
  beside the distro Qt. `-DSERVICE_PIPEWIRE` is
  **ON** on both arches since 2026-09-02: archlinux32's pipewire 0.3.65
  needs a two-line source patch, not a disabled service. See "The
  pipewire decision, reversed" below. i686 also needs the `icu75` legacy
  package, because its `qt6-base` 6.7.2 links `libicui18n.so.75` against
  a repo `icu` of 78 - the same drift class as the fontconfig and
  libxml2 problems.
- **Four `MultiEffect` uses** are the only shader-dependent QML in the
  tree (tray icon colorization, lock blur, and two masked reveals in
  Background and ImagePicker). The software backend cannot run them. All
  four are cosmetic and three are effects flat mode disables anyway.
  There is no `ShaderEffect` and no particle system anywhere in `shell/`,
  so that is the complete list.

Measured in the x86_64 VM (1280x800, TCG): the shell is 234 MB RSS
(208 MB PSS) on the default theme at 0.1 % idle CPU, against 96 MB for
the waybar+mako+swaybg stack it replaces - but it also subsumes
swaylock and swayidle, so the real delta is about +140 MB. That single
number is not the whole story; see "What the shell's memory actually
does" below. Menu open is 0.49 s end to end, of which 0.29 s is the
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
238 MB).

## What the shell's memory actually does

That boot was later read as a leak: the same process measured 469 MB
after fourteen minutes and a 650 MB `VmHWM`. It is not a leak. The
fourteen minutes are the giveaway - the shell started at 08:48:17 and
`~/.local/state/omarchy/current/theme.name` was rewritten at 09:02:42,
fourteen minutes and twenty-five seconds later. The number moved
because the theme changed, not because time passed.

Measured properly, on the software backend at 1280x800:

- **Idle does not grow.** 46 samples over 15 minutes: 233.4 to
  234.1 MB RSS, no direction, `VmHWM` never re-reached after startup,
  JS heap flat at 9.5 MB, mapping count flat at 1203.
- **The wallpaper is the variable**, and it is the whole variable.
  `shell/plugins/background/Background.qml:221` loads the background
  with no `sourceSize`, so Qt decodes it at its stored resolution and
  keeps it. Swapping a 1536x1024 background (6 MB decoded) for a
  10456x3455 one (138 MB decoded) moved RSS from 208.7 MB to 349.8 MB:
  a 141 MB step for a 138 MB image. The model is
  `RSS ~= 190 MB + the decoded size of the current wallpaper`.
- **It is released.** Four crossfade cycles between those two
  backgrounds returned 349752 / 349684 / 349820 / 349820 kB on the big
  one - a spread of 136 kB. Nothing accumulates.
- **Crossfade is the peak.** `VmHWM` reached 491 MB, because the base,
  outgoing and incoming copies are all resident during the transition.

- **CPU rendering is not what costs the memory - it is what saves it.**
  The same shell was run again in the same VM with `QT_QUICK_BACKEND`
  unset, so Qt took its default RHI path and Mesa fell through to
  llvmpipe (`libgallium` and `libEGL_mesa` mapped, still no `/dev/dri`
  descriptor). Idle plateaus on both. Everything else is worse on GL:

  | | software | llvmpipe |
  |---|---|---|
  | fresh start | 234 MB | 673 MB |
  | settled idle, default theme | 234 MB | 701 MB |
  | 6 MB wallpaper | 209 MB | 623 MB |
  | 138 MB wallpaper | 350 MB | 946 MB |
  | back to the 6 MB wallpaper | **209 MB** | **992 MB** |
  | peak `VmHWM` over three cycles | 491 MB | **1480 MB** |

  Two things separate the columns. The marginal cost of a wallpaper is
  1.04x its decoded pixels under the software scenegraph - one copy -
  and 2.39x under llvmpipe, which keeps the CPU-side image *and* a
  texture, and honours the `mipmap: true` that `Background.qml` asks
  for on the transition frames and the software backend ignores. And
  the software backend gives it *back*: swap the big background out and
  RSS returns to 208700 / 208700 / 214260 kB, while llvmpipe never
  comes down at all - 989612 / 995108 / 991876 kB for the same 6 MB
  wallpaper, within a few MB of its own peak, and its `VmHWM` climbs
  every cycle (1135, 1469, 1480 MB).

  So the software scenegraph is not a memory tax to be apologised for.
  On a 2 GB machine the GL path would take a third of RAM at idle and
  1.4 GB across a few theme switches; the software one is what makes
  the target viable. If anything here deserves the word leak, it is on
  the GL path, and it is not the path this fork ships.

So the honest figures for this VM are **234 MB steady on the default
theme, 350 MB on the largest background this repo ships, and 491 MB
peak across a theme switch**. The backgrounds under `themes/` decode to
between 6 and 138 MB, median 32 MB, and their format is irrelevant to
this: upstream's webp conversion (`a4219f8f`) kept every image's exact
pixel dimensions, so it saves disk and not one byte of RAM.

`jemalloc` is Quickshell's allocator, not glibc's - `malloc` resolves
into `libjemalloc.so.2`. That matters when reading a dump: `malloc_info`
reports an empty arena and `malloc_trim` frees nothing, which looks like
a glibc leak and is neither. Purging every jemalloc arena
(`mallctl("arena.4096.purge")`) released zero bytes, which is what
proves the resident pages are live image data rather than retained free
space.

## The i686 desktop, and the 2 GB answer (2026-09-02)

The whole stack was rebuilt for i686 from the current fork HEADs
(Hyprland `pixman-renderer` 63417a30, aquamarine `cpu-backend` 60a765d)
in the archlinux32 chroot, Quickshell 0.3.1 was built beside it,
everything was installed into the i686 VM, and the VM was held at
**2048 MB** on `-cpu coreduo -smp 2` so the numbers mean something for
the MacBook. The full
desktop came up on the VM's own DRM display at 1280x800: the bar, the
workspace pills, the clock, the tray and the theme wallpaper, on the
pixman compositor with Qt's software scenegraph. Screenshot (QEMU
`screendump`, not `grim`): `docs/pixman-renderer/i686-quickshell.png`.

**It fits, with room to spare.** Measured in that VM:

| | Quickshell RSS | system in use | left for apps |
|---|---|---|---|
| greeter, no session | - | 314 MB | 1641 MB |
| desktop idle, default wallpaper (78 MB decoded) | 210 MB | 489 MB | 1466 MB |
| plus a foot terminal | 210 MB | 503 MB | 1452 MB |
| largest shipped wallpaper (138 MB decoded) | 272 MB | 563 MB | 1392 MB |
| smallest shipped wallpaper (6 MB decoded) | 144 MB | 439 MB | 1516 MB |

The compositor is 61 MB of that (68 MB on the largest wallpaper),
Xwayland 45 MB, foot 16 MB. Peak `VmHWM` across the wallpaper swaps was
492 MB, the crossfade cost. Then a 1.3 GB workload, which is a browser
with a handful of tabs, was held resident on top of the idle desktop:
260 MB still free, zram never touched more than 1 MB, and the
compositor, the shell and the terminal all stayed up.

**The shell is smaller on i686 than on x86_64**, which was not the
expected direction. The fixed part drops from about 190 MB to about
135 MB on 32-bit pointers, and the wallpaper model is otherwise the
same:

    RSS ~= 135 MB + the decoded size of the current background

Fitted against four backgrounds in the same session: 6 MB -> 144 MB,
32 MB -> 206 MB, 78 MB -> 210 MB, 138 MB -> 272 MB, and back to 6 MB ->
144 MB, so it still releases. The lever, if a real machine turns out
tighter than the VM, is still the wallpaper: the smallest shipped
background is 66 MB below the default and 128 MB below the largest, and
none of that resolution is visible on a 1280x800 panel.

zram is a 1.9 GB device at priority 100 and never mattered in any of
this. Note that archlinux32's i686 kernel offers only `lzo-rle` and
`lzo` for zram, so the `zstd` in the config silently becomes `lzo-rle`:
about 2:1 rather than 3:1.

Verified on the same session: `QSG_INFO=1` prints `Loading backend
software` and the process holds no `/dev/dri` descriptor. On i686 the
process does map `swrast_dri.so` and `libEGL_mesa`, which x86_64 did
not - that is qtwayland probing for an EGL platform integration at
startup, not the scenegraph. The RSS settles the question either way:
llvmpipe rendering costs three times this.

### What is still broken on i686

**The session crashes on login, and this is the one thing to fix next.**
Started by greetd, the compositor and the shell both come up and then
Hyprland aborts with `malloc(): invalid size (unsorted)`. It is heap
corruption, so glibc reports it at whatever allocates next and the site
moves between runs (`wl_client_create` in one, a pixman region realloc
in another). A core taken from the VM puts the corruption on the DRM
page-flip path:

    CDRMBackend::dispatchEvents -> handlePageFlip
      -> CMonitorFrameScheduler::onFrame
      -> IHyprRenderer::renderMonitor
      -> CHyprPixmanRenderer::endRender
      -> CRenderPass::render -> CRenderPass::simplify
      -> Hyprutils::Math::CRegion::subtract
      -> pixman_region32_subtract -> realloc -> abort

`start-hyprland` then restarts the compositor with `--safe-mode`, and
the safe-mode dialog is a second, independent crash:
`CCompositor::openSafeModeBox` calls `CAsyncDialogBox::open`, which
segfaults because `hyprland-dialog` (from `hyprland-qtutils`, absent on
archlinux32) is not installed. So one render bug becomes a login loop.

Ruled out: the CPU model (reproduces on `-cpu max` as well as
`-cpu coreduo`, so this is not a Core Duo instruction-set problem),
concurrency alone (reproduces with one vCPU), library drift between the
build chroot and the VM (identical versions of pixman, cairo, pango,
glib2, libdrm, mesa, libxkbcommon, wayland, gcc-libs and glibc), and the
screencopy portal (reproduces with `xdg-desktop-portal-wlr` masked). The
headless i686 harness in the build chroot never hits it, which points at
the DRM path rather than at the renderer in general. Two fork sites are
worth reading first: `CPixmanTexture::writePixels`, which memcpys damage
rects into a `std::vector` sized `stride * height`, and
`CHyprPixmanRenderer::saveBufferForMirror`, which composites the full
mirror framebuffer out of the target image. A third, latent: 16 bpp
formats (`DRM_FORMAT_RGB565`) get `stride = width * 2` in both
`CPixmanTexture::allocate` and `CPixmanFramebuffer::internalAlloc`,
which is not the 4-byte-aligned stride pixman requires for an odd width.

Bringing the compositor and the shell up by hand works: the compositor
survived on the second attempt and then ran for over an hour under the
whole measurement series. That is how every number above was obtained.

### Two i686 bugs fixed on the way

22. **The cursor theme's gsettings write killed the compositor.**
    Hyprland's `cursor:sync_gsettings_theme` writes the cursor theme
    into gsettings so GTK apps follow it, and glib routes that through
    dconf. archlinux32 ships a `dconf` built against a newer glib2 than
    the repo has, so `dconf-service` cannot start at all (`undefined
    symbol: g_variant_builder_init_static`) and the write corrupts the
    compositor's heap. `default/hypr/looknfeel.lua` now sets
    `cursor.sync_gsettings_theme = false`. This is the fifth
    dependency-drift bug of the fontconfig / libxml2 / neatvnc / icu75
    class, and the first one that is fatal rather than cosmetic.
23. **The memory tuning was never installed.** `zram-generator.conf.d`,
    the oomd drop-ins, the reclaim sysctls and the zswap tmpfiles rule
    live in the tree and are quoted throughout these notes, but upstream
    ships them inside its pacman package and this fork has no package,
    so nothing ever copied them to `/etc`. A fresh install came up with
    **no swap device at all** and stock reclaim tuning while every
    document said otherwise. `install/config/memory-tuning.sh` now
    installs them, and the i686 VM comes up with a 1.9 GB zram at
    priority 100 and `vm.swappiness=150`.

### The pipewire decision, reversed

`-DSERVICE_PIPEWIRE=OFF` is gone. archlinux32 still ships pipewire
0.3.65, and the runbook was right that Quickshell 0.3.1 does not compile
against it, but the whole incompatibility is two symbols:

- `src/services/pipewire/core.cpp` initialises `.bound_props = nullptr`
  in a `pw_core_events` designated initializer. 0.3.65 has no such
  field. The line writes a null pointer and the listener announces
  `PW_VERSION_CORE_EVENTS`, which is 0 there, so the server never emits
  that event. Deleting the line is a no-op at run time.
- `src/services/pipewire/node.cpp` uses `SPA_KEY_NODE_DESCRIPTION`,
  absent from 0.3.65's `spa/node/keys.h`. `PW_KEY_NODE_DESCRIPTION` is
  the identical string `"node.description"`.

Two `sed` lines in the runbook, and `-DSERVICE_PIPEWIRE=ON` builds
clean. `ldd -r /usr/bin/quickshell` reports no undefined symbol and the
binary links `libpipewire-0.3.so.0`. So the four QML files that import
`Quickshell.Services.Pipewire` have their module, and neither the audio
panel, the volume OSD nor the media widgets are structurally missing on
32-bit any more. What is **not** yet proven is the service talking to a
0.3.65 daemon: the measurement bench had no pipewire running, so it only
showed the service loading and failing to connect. That is the next
thing a hardware report should say.

`-DCRASH_HANDLER=OFF` stays: `cpptrace` is absent from archlinux32
outright, and there is no two-line version of that.

One more recipe note: the i686 build was configured with
`-DCMAKE_INSTALL_PREFIX=/usr`, so the QML modules land in
`/usr/lib/qt6/qml` beside archlinux32's own Qt. The x86_64 runbook
leaves the prefix at cmake's `/usr/local` default and works, so this is
the tested layout rather than a proven requirement.

**Still never run on real hardware.** Every figure above is a QEMU VM
with an emulated framebuffer. The MacBook has a GMA 950 and a slower
Core Duo, so expect the timings to differ even where the megabytes do
not.

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
