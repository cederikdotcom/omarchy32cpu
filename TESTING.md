# Testing omarchy32cpu

This fork is pre-release. It has been validated in VMs and chroots and has never run on the physical MacBook1,1 it was built for, nor on any other real machine we know of. **The single most useful thing you can give this project is a hardware report** - one message saying what your machine is and what did or did not come up. That data does not exist yet.

File it with the [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml).

## See it before you install it

A live omarchy32cpu session runs in a browser here:

**https://omarchy32.cederik.com/vnc.html** - password `omarchy32view`

That is the target experience: Hyprland on the pixman (CPU) renderer, waybar, fuzzel, mako, the Omarchy theme engine, every pixel drawn by the CPU. It is a development bench, so it may be down or mid-rebuild when you look. Do not report the demo being offline as a bug.

## Read this first: the compositor changed

Until now this fork substituted sway for Hyprland, because Hyprland needs GLES 3.0 and the target has no GPU. That reason is gone: this fork's [Hyprland](https://github.com/cederikdotcom/Hyprland/tree/pixman-renderer) and [aquamarine](https://github.com/cederikdotcom/aquamarine/tree/cpu-backend) branches add a pixman (CPU) renderer, and it composites headless, nested, and on a real DRM display in the i686 VM at 0.05 % idle CPU. So sway is deleted and the upstream Hyprland session is back.

**"What works today" below was proven on the sway session.** On **x86_64 it has been proven again on Hyprland**, on 2026-08-31: a VM installed from this tree boots, greetd starts the session itself, and `hyprctl systeminfo` says `Renderer: pixman (software)`, with waybar, the menu, the keybindings and theme switching all working. **On i686 it has not been re-proven yet.** So on the MacBook path, treat the list as what the stack did rather than what it does, and a report that one of those items no longer works is especially useful.

The renderer needs two environment variables, both set by `omarchy-hyprland-launch`: `HYPRLAND_RENDERER=pixman` picks the software renderer and `AQ_FORCE_ALLOCATOR=dumb` makes aquamarine allocate DRM dumb buffers. A stock Hyprland ignores both and then dies on the missing GLES 3.0, so the Hyprland and aquamarine binaries have to come from the fork build.

## What works today

Everything in this list is evidence-backed. The detail, including every bug found and fixed while establishing it, is in [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md); the render-floor proofs and screenshots are in [`docs/pixman-renderer/`](docs/pixman-renderer/).

- **The x86_64 path boots to a working desktop in a QEMU VM with no GPU.** 64-bit UEFI -> GRUB -> kernel -> greetd -> the compositor with the pixman renderer, waybar, swaybg, mako, the fuzzel menu on `Super+Space` and foot on `Super+Return`. Screenshot: [`docs/pixman-renderer/x86_64-vm.png`](docs/pixman-renderer/x86_64-vm.png). Details in [`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md).

- **The boot chain**, rehearsed end to end in a QEMU VM with 32-bit UEFI firmware: firmware -> `BOOTIA32.EFI` -> GRUB -> i686 kernel -> greetd -> the compositor on the display.
- **`omarchy-apply-system --install-user <user> --first-install`** runs to exit 0 in an i686 target chroot: config, hardware, greetd login and post-install phases.
- **A full desktop session** under greetd autologin: the compositor + waybar + mako + swayidle + swaybg with the pixman renderer and the systemd user bus, zero failed systemd units.
- **The theme engine.** All 22 themes render the compositor, waybar, mako and swaylock. Live theme switching re-renders and reloads all four.
- **The CLI.** All 24 `omarchy-hyprland-*` scripts were live-tested against a running session. They are upstream's `hyprctl` versions again since the compositor swap; `omarchy-compositor-ctl`, the shim that stood between them and sway, is deleted.
- **`omarchy-remote-view`** (wayvnc over wlroots screencopy) serves the live session over VNC on `127.0.0.1:5901`. This is the CPU-only stack's remote path and the reason a cloud instance is a usable test target.

What has **not** been proven: any real GPU, any real display panel, any real wifi/audio/battery/suspend hardware, and any x86_64 machine. That is the entire point of this document.

## What is expected to be broken or absent

**Do not report these.** They are known, documented in [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md), and in most cases permanent.

Permanently absent on this stack:

- No animations, blur, shadows, rounded corners or per-window opacity. The pixman renderer draws none of them.
- No portal screen sharing or screencast. `xdg-desktop-portal-wlr` does not support the pixman renderer, so screen sharing in a browser or a video call will fail. This will not be fixed.
- No hardware video decode and no Vulkan.
- Monitor mirroring is back with Hyprland but unverified on the pixman renderer; it was absent while the fork ran sway. Clamshell and output toggling do work.
- No upstream plugin system. It is Quickshell QML; there is no Quickshell here.

Known broken or missing right now:

- **Screen recording is broken.** `omarchy-capture-screenrecording` still targets gpu-screen-recorder, which is not shipped. Screenshots (`grim`/`slurp`) do work.
- **No browser is preinstalled**, and no application of any kind is. This fork ships a 78-package core and you install your own. On i686 the repo browsers are ancient (chromium 90, firefox 114).
- **Optional capture and transcode tools are absent**: `omarchy-capture-qr` needs zbar, `omarchy-capture-text` needs tesseract, `omarchy-transcode*` needs ffmpeg and imagemagick. Those commands error until you install the tool.
- **`omarchy-debug` does not work**: it calls `inxi`, which is not in the core package set. Use the commands under "Diagnostics" below instead.
- **`omarchy-update` is untested and should be treated as broken.** The fork does not track upstream channels and has no package repo.
- Several commands are deliberate stubs that print a notice and exit 0 (window transparency toggle, cursor zoom, the plugin and bar-widget system, `omarchy-bar` config subcommands). The full list is in the release notes.
- `systemctl restart greetd` lands on the tuigreet greeter, not back in the autologin session. That is greetd semantics, not a bug. Reboot or log in through tuigreet.
- **A login notification says `hyprland-qtutils` is not installed.** It is not, on purpose: it is Qt6/QML and needs GL, the same blocker that keeps the Quickshell desktop out. Hyprland uses it only for a few of its own dialogs. Cosmetic.
- **foot prints about 20 `deprecated: [colors]` lines on every launch on x86_64.** foot 1.27 wants `[colors-dark]` where foot 1.13 on archlinux32 requires `[colors]`, and one theme template has to serve both. The colours apply correctly.
- If you pick a session from the greeter's menu, pick **Omarchy**. The Hyprland build installs its own `Hyprland` entries that do not set the pixman renderer, and those give you a black screen on a machine with no GPU.
- On i686 only: no fan daemon (mbpfan) and no webcam (isight-firmware-tools); neither is in the archlinux32 repos.

## What to test and report

Work down this list. Partial reports are welcome - "it did not boot" is a useful report on its own.

1. **Does it boot?** Firmware -> bootloader -> kernel. If it stops, say where.
2. **Does greetd start?** You should reach either the desktop directly (autologin) or the tuigreet text greeter.
3. **Does the Hyprland session come up?** Bar, wallpaper, a terminal on `Super+Return`, the menu on `Super+Space`.
4. **Which renderer are you actually on, and does the other one work?** This is the most valuable single data point we can get from you, and we have none of it. See "The renderer question" below.
5. **Theme switching**: `omarchy-theme-set catppuccin`, then a few others. Do the window borders, waybar, mako and the lock screen all follow?
6. **The menu**: `Super+Space`. Does it open, navigate, and launch things?
7. **Suspend and resume**: close the lid, or `systemctl suspend`. Does it come back with a working display and input?
8. **Wifi**: `nmtui` or the menu's wifi entry.
9. **Audio**: `pactl info`, then play something. Pipewire and wireplumber are in the core.
10. **Battery**: `upower -i $(upower -e | grep BAT)`. Does waybar show a battery?
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
- **i686 on the 2006 MacBook A1181**: [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md). Harder: archlinux32, two override packages, 32-bit EFI.

## How to report

Use the [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml). It is short on purpose.

One report per machine. If you tested the same machine in a VM and on bare metal, that is two reports.

This is a fork by one person, not a product. There is no support channel and no SLA. Reports are read; fixes happen when they happen.
