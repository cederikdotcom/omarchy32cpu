# Testing omarchy32cpu

This fork is pre-release. It has been validated in VMs and chroots and has never run on the physical MacBook1,1 it was built for, nor on any other real machine we know of. **The single most useful thing you can give this project is a hardware report** - one message saying what your machine is and what did or did not come up. That data does not exist yet.

File it with the [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml).

## See it before you install it

A live omarchy32cpu session runs in a browser here:

**https://omarchy32.cederik.com/vnc.html** - password `omarchy32view`

That is the target experience: Hyprland on the pixman (CPU) renderer, the Quickshell desktop on Qt's software scenegraph, the Omarchy theme engine, every pixel drawn by the CPU. It is a development bench, so it may be down or mid-rebuild when you look. Do not report the demo being offline as a bug.

## Read this first: the compositor changed

Until now this fork substituted sway for Hyprland, because Hyprland needs GLES 3.0 and the target has no GPU. That reason is gone: this fork's [Hyprland](https://github.com/cederikdotcom/Hyprland/tree/pixman-renderer) and [aquamarine](https://github.com/cederikdotcom/aquamarine/tree/cpu-backend) branches add a pixman (CPU) renderer, and it composites headless, nested, and on a real DRM display in the i686 VM at 0.05 % idle CPU. So sway is deleted and the upstream Hyprland session is back.

**"What works today" below was proven on the sway session.** On **x86_64 it has been proven again on Hyprland**, on 2026-08-31, and a third time with the real Quickshell desktop on 2026-09-01: a VM installed from this tree boots, greetd starts the session itself, `hyprctl systeminfo` says `Renderer: pixman (software)`, and the Quickshell bar, the Omarchy menu on a real `Super+Space`, notifications and theme switching all work with Qt on its software scenegraph.

**On i686 the greetd login works as of 2026-09-02.** A fresh image built by following [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md) literally boots under 32-bit UEFI at 2048 MB and greetd puts you on the desktop with no hand-holding: bar, tray, clock, theme wallpaper, foot on `Super+Return` and the Omarchy menu on `Super+Space`, `Renderer: pixman (software)` on `Backend: drm`, zero failed units, 491 MB of the 2 GB in use, and five cold boots out of five landing on the desktop. Screenshot: [`docs/pixman-renderer/i686-greetd-desktop.png`](docs/pixman-renderer/i686-greetd-desktop.png).

Until that day the same install crashed on **every** login. The cause was one line of configuration, `input:numlock_by_default`, which the fork now ships off: turning numlock on at startup makes Hyprland build a second xkb state per keyboard, and on i686 that path corrupts the heap, so the abort landed in a pixman region `realloc` and every backtrace pointed at the renderer. The bisect ran one setting per variant on a fresh install - the whole fork config died 0 of 5, that line alone died 0 of 4, and the whole config with it off came back 4 of 5. **The renderer bug itself is not fixed**: the hand-start harness still lost about one start in five, so a login that lands on the greeter is possible. Log in again. The full table is in the runbook under "The i686 login crash". Nothing on i686 has been proven on hardware.

The renderer needs two environment variables, both set by `omarchy-hyprland-launch`: `HYPRLAND_RENDERER=pixman` picks the software renderer and `AQ_FORCE_ALLOCATOR=dumb` makes aquamarine allocate DRM dumb buffers. A stock Hyprland ignores both and then dies on the missing GLES 3.0, so the Hyprland and aquamarine binaries have to come from the fork build.

## The shell is Quickshell again

The waybar + fuzzel + mako + swaybg + swaylock stand-in is gone. The bar,
menu, notifications, OSD, wallpaper, lock screen, tray and plugin system
are the real upstream Omarchy shell (`shell/`, 175 files of QML,
byte-identical to upstream), drawn by Qt Quick's **software** scenegraph
on top of the pixman compositor. No GPU is involved at any layer.

**On x86_64 you have to build two things from source**, because neither
is in any repo: this fork's Hyprland/aquamarine, and Quickshell 0.3.1.
[`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md)
steps 9 and 10 give the exact commands, and it is about five minutes of
compiling on a modern machine.

**On i686 you install them, prebuilt.** The recipe there is seventeen
components, `cmake` and `meson` from pip and a patch to
wayland-protocols, which is a day of compiling on a Core Duo and not a
sensible thing to ask of anyone at a MacBook. So the whole stack is
published as one i686 tarball,
`omarchy32cpu-stack-i686-20260902.tar.zst` on
[release `i686-20260902`](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/i686-20260902),
and step 7 of
[`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md)
extracts it. That release also carries the two override packages, and it
supersedes `overrides-i686-20260831` - take the new one; the old one's
`neatvnc-0.8.1-3` cannot be installed at all. The build recipe is still
in that runbook, at the end, for anyone who wants to rebuild it.

If you are checking whether the CPU path is really being taken, this is
the trap to know about: the variable is `QT_QUICK_BACKEND=software`.
`QSG_RHI_BACKEND=software` is **not** a valid Qt setting - Qt prints
`Unknown key "software"` and quietly falls back to the default backend,
which on any machine with Mesa is llvmpipe. The desktop then looks
perfectly correct while using about 440 MB more memory - 234 MB against
698 MB in this VM, on the same wallpaper. So a working shell does not
prove CPU rendering. Prove it with:

```bash
QSG_INFO=1 quickshell -p /usr/share/omarchy/shell 2>&1 | grep -i backend
# want: qt.scenegraph.general: Loading backend software
```

`omarchy-hyprland-launch` sets the variable for the whole session, so you
only need this when something looks suspicious.

One thing is switched off on i686 and is not a bug: the **crash
handler**, because `cpptrace` is absent from archlinux32. Audio used to
be on this list and no longer is: Quickshell's pipewire service builds
against archlinux32's pipewire 0.3.65 after a two-line patch that the
runbook gives you. Whether it works against that old a daemon is
unverified, and a report either way is useful.

Known cosmetic gaps on **both** arches: four `MultiEffect` uses cannot
run without shaders - tray icon colorization, the lock screen's blurred
wallpaper, and two masked reveals in the wallpaper and image pickers.
Everything still works; those four just render unembellished.

**Memory: the shell does not leak, but its size follows the
wallpaper.** Measured in the x86_64 VM at 1280x800 with
`QT_QUICK_BACKEND=software`. Idle is flat - 46 samples over 15 minutes
moved between 233.4 and 234.1 MB RSS and drifted no direction. What
moves the number is the background: the shell decodes it at its full
stored resolution and holds it, so

    RSS ~= 190 MB + the decoded size of the current wallpaper

and the wallpapers this repo ships decode to between 6 MB
(1536x1024) and 138 MB (10456x3455), median 32 MB. That gives
234 MB on the default theme, 350 MB on the largest shipped
background, and a 491 MB peak while a theme switch crossfades - the
old, incoming and base copies are resident at once. Switching away
releases all of it; four crossfade cycles landed within 140 kB of each
other, so there is nothing accumulating.

Against 96 MB for the shim stack it replaced, and that stack also had
no lock screen, idle daemon or notification server.

**On i686 in 2 GB it is cheaper, and it fits.** Measured 2026-09-02 in
the i686 VM held at 2048 MB, at 1280x800: the desktop idles at 489 MB of
system memory with 1466 MB left, the shell is 210 MB of that on the
default wallpaper, the compositor 61 MB, a foot terminal 16 MB. The
fixed part of the shell is about 135 MB on 32-bit rather than 190 MB on
64-bit, so the model is `RSS ~= 135 MB + the decoded wallpaper`. A
1.3 GB workload, browser-sized, ran on top of the idle desktop with
260 MB free and never touched zram. The full series is in
[`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md).

What is **not** settled on i686 is stability, not size: the compositor
still aborts on heap corruption during its first frames about one start
in five. The configuration line that made it every start is fixed. See
"The i686 login crash" in the runbook.

Worth knowing before you blame the software scenegraph for any of
this: the same shell in the same VM with `QT_QUICK_BACKEND` unset,
taking Qt's default path through llvmpipe, sits at 698 MB. CPU
rendering is not what costs the memory here, it is what saves it.

**Now measured on i686 too, and still never on real hardware.** A
hardware report carrying these numbers is worth more than any further VM
work. If RAM is tight on a 2 GB machine, the lever is the wallpaper, not
the plugin set.

## What works today

Everything in this list is evidence-backed. The detail, including every bug found and fixed while establishing it, is in [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md); the render-floor proofs and screenshots are in [`docs/pixman-renderer/`](docs/pixman-renderer/).

- **The x86_64 path boots to a working desktop in a QEMU VM with no GPU.** 64-bit UEFI -> GRUB -> kernel -> greetd -> the compositor with the pixman renderer, the Quickshell bar and wallpaper, the Omarchy menu on `Super+Space` and foot on `Super+Return`. Screenshot: [`docs/pixman-renderer/x86_64-hyprland.png`](docs/pixman-renderer/x86_64-hyprland.png). Details in [`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md).

- **The boot chain**, rehearsed end to end in a QEMU VM with 32-bit UEFI firmware: firmware -> `BOOTIA32.EFI` -> GRUB -> i686 kernel -> greetd -> the compositor on the display.
- **`omarchy-apply-system --install-user <user> --first-install`** runs to exit 0 in an i686 target chroot: config, hardware, greetd login and post-install phases.
- **A full desktop session** under greetd autologin: the compositor + the Quickshell shell with the pixman renderer and the systemd user bus, zero failed systemd units.
- **The theme engine.** All 22 themes render templates for the compositor and the shell. A live theme switch is confirmed to re-render every template, reload the compositor's colours, and change the wallpaper; the shell hot-reloads its own colours.
- **The CLI.** All 24 `omarchy-hyprland-*` scripts were live-tested against a running session. They are upstream's `hyprctl` versions again since the compositor swap; `omarchy-compositor-ctl`, the shim that stood between them and sway, is deleted.
- **`omarchy-remote-view`** (wayvnc over wlroots screencopy) serves the live session over VNC on `127.0.0.1:5901`. This is the CPU-only stack's remote path and the reason a cloud instance is a usable test target.

### Before you report a black screen

The session locks itself after five minutes idle - the shell's own idle plugin, at its 300 s default - and until you press a key the lock screen can look like a dead display. On a VM you are watching over VNC, or a machine you left alone while reading this, that is indistinguishable from a crash; it cost us an afternoon once already. Press a key first. If you are running unattended tests longer than five minutes, disable the idle lock rather than killing the locker: killing a locker that holds the session lock leaves Hyprland on its "crashed lockscreen" page, which then reads as a renderer failure. Clear that state with `hyprctl eval "hl.clear_crashed_lockscreen()"`.

What has **not** been proven: any real GPU, any real display panel, any real wifi/audio/battery/suspend hardware, and any x86_64 machine. That is the entire point of this document.

## What is expected to be broken or absent

**Do not report these.** They are known, documented in [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md), and in most cases permanent.

Permanently absent on this stack:

- No animations, blur, shadows, rounded corners or per-window opacity. The pixman renderer draws none of them.
- No portal screen sharing or screencast. `xdg-desktop-portal-wlr` does not support the pixman renderer, so screen sharing in a browser or a video call will fail. This will not be fixed.
- No hardware video decode and no Vulkan.
- Monitor mirroring is back with Hyprland but unverified on the pixman renderer; it was absent while the fork ran sway. Clamshell and output toggling do work.

Known broken or missing right now:

- **Screen recording is broken.** `omarchy-capture-screenrecording` still targets gpu-screen-recorder, which is not shipped. Screenshots (`grim`/`slurp`) do work.
- **No browser is preinstalled**, and no application of any kind is. This fork ships an 80-package core and you install your own. On i686 the repo browsers are ancient (chromium 90, firefox 114).
- **Optional capture and transcode tools are absent**: `omarchy-capture-qr` needs zbar, `omarchy-capture-text` needs tesseract, `omarchy-transcode*` needs ffmpeg and imagemagick. Those commands error until you install the tool.
- **`omarchy-debug` does not work**: it calls `inxi`, which is not in the core package set. Use the commands under "Diagnostics" below instead.
- **`omarchy-update` is untested and should be treated as broken.** The fork does not track upstream channels and has no package repo.
- Several commands are deliberate stubs that print a notice and exit 0 (window transparency toggle, cursor zoom, the plugin and bar-widget system, `omarchy-bar` config subcommands). The full list is in the release notes.
- `systemctl restart greetd` lands on the tuigreet greeter, not back in the autologin session. That is greetd semantics, not a bug. Reboot or log in through tuigreet.
- **A login notification says `hyprland-qtutils` is not installed.** It is not, and it is not in either repo. Hyprland uses it only for a few of its own dialogs. Cosmetic.
- **foot prints about 20 `deprecated: [colors]` lines on every launch on x86_64.** foot 1.27 wants `[colors-dark]` where foot 1.13 on archlinux32 requires `[colors]`, and one theme template has to serve both. The colours apply correctly.
- If you pick a session from the greeter's menu, pick **Omarchy**. The Hyprland build installs its own `Hyprland` entries that do not set the pixman renderer, and those give you a black screen on a machine with no GPU.
- On i686 only: no fan daemon (mbpfan) and no webcam (isight-firmware-tools); neither is in the archlinux32 repos.

## What to test and report

Work down this list. Partial reports are welcome - "it did not boot" is a useful report on its own.

1. **Does it boot?** Firmware -> bootloader -> kernel. If it stops, say where.
2. **Does greetd start?** You should reach either the desktop directly (autologin) or the tuigreet text greeter.
3. **Does the Hyprland session come up?** Bar, wallpaper, a terminal on `Super+Return`, the menu on `Super+Space`.
4. **Which renderer are you actually on, and does the other one work?** This is the most valuable single data point we can get from you, and we have none of it. See "The renderer question" below.
5. **Theme switching**: `omarchy-theme-set catppuccin`, then a few others. Do the window borders, the bar, notifications and the lock screen all follow?
6. **The menu**: `Super+Space`. Does it open, navigate, and launch things?
7. **Suspend and resume**: close the lid, or `systemctl suspend`. Does it come back with a working display and input?
8. **Wifi**: `nmtui` or the menu's wifi entry.
9. **Audio**: `pactl info`, then play something. Pipewire and wireplumber are in the core.
10. **Battery**: `upower -i $(upower -e | grep BAT)`. Does the bar show a battery?
11. **Brightness keys**: the `XF86MonBrightness*` keys, or `brightnessctl set 50%`.
12. **Webcam**: `ls /dev/video*`, then any v4l2 tool you have.

### The renderer question

The fork sets `HYPRLAND_RENDERER=pixman` in `omarchy-hyprland-launch` because its first target has a GPU that cannot serve GLES. On a machine with a normal GPU that is leaving performance on the floor - Hyprland's own GL renderer should work, be hardware-accelerated, and bring back animations, blur, shadows and rounded corners. **We have never tested that on this build, and we would like to know.**

If you have a real GPU, please try both:

```bash
# What you get by default:
HYPRLAND_RENDERER=pixman AQ_FORCE_ALLOCATOR=dumb Hyprland

# What we want to know about - Hyprland's GL renderer, hardware-accelerated:
HYPRLAND_RENDERER=gl Hyprland
```

Report which one you ran, whether the GL renderer came up at all, and whether it felt faster. If both fail and you fell back to i3 on X11 with the modesetting driver, say that too - it is the documented fallback and we want to know how often people need it.

## Diagnostics to attach

Run these and paste the output into the report. None of them need anything the core package set does not already install.

```bash
# Compositor and version
hyprctl version
hyprctl monitors
omarchy-version

# What the session environment actually is
env | grep -E 'HYPRLAND_|AQ_|WLR_|XDG_|WAYLAND'

# Graphics hardware, verbatim - this is the field we most need
lspci -nn | grep -i vga
ls -l /dev/dri/

# Login chain
journalctl -b -u greetd --no-pager | tail -50

# The compositor's own output. greetd sends the session through systemd-cat,
# so this is where a compositor that died at login says why. It is the first
# thing to attach when the desktop did not appear.
journalctl -b -t omarchy-session --no-pager | tail -200
ls -la ~/.cache/hyprland/ && cat ~/.cache/hyprland/hyprlandCrashReport*.txt

# The renderer the session actually selected. This is the important one:
# it should say "Renderer: pixman (software)". Do not grep the compositor's
# log file for this - Hyprland ships with debug:disable_logs on, so
# $XDG_RUNTIME_DIR/hypr/<sig>/hyprland.log is empty and tells you nothing.
hyprctl systeminfo | grep -iE 'renderer|backend|GPU'

# Kernel modesetting complaints
dmesg | grep -iE 'drm|i915|amdgpu|nouveau' | tail -30

# Failed units
systemctl --failed
systemctl --user --failed
```

If the desktop comes up at all but you are working over a network, `omarchy-remote-view on` starts wayvnc on `127.0.0.1:5901`; reach it with `ssh -L 5901:127.0.0.1:5901 <user>@<host>` and point a VNC client at `localhost:5901`. It binds localhost only, and the default ufw posture denies incoming anyway.

`hyprctl` is back, and everything in the wiki that uses it applies: this is real Hyprland, only with a different renderer.

## Install paths

- **x86_64** (VMs, cloud instances, thin clients, ordinary old laptops): [`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md). This is the low-friction path and the one most testers want. No override packages, ordinary UEFI.
- **i686 on the 2006 MacBook A1181**: [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md). Harder: archlinux32, 32-bit EFI, and three prebuilt downloads from [release `i686-20260902`](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/i686-20260902) - the desktop stack tarball and two override packages. Get them before you start; the target has no browser.

## How to report

Use the [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml). It is short on purpose.

One report per machine. If you tested the same machine in a VM and on bare metal, that is two reports.

This is a fork by one person, not a product. There is no support channel and no SLA. Reports are read; fixes happen when they happen.
