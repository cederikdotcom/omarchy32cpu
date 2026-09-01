# omarchy32cpu

**Pure CPU-bound Omarchy.** The full Omarchy workflow - tiling,
workspaces, keybindings, the 24-color theme engine, the menu system
and the CLI tooling - with no GPU dependence at all and no
preinstalled applications. Every pixel is drawn by the CPU.

It runs where stock Omarchy cannot: VMs without GPU passthrough,
cloud desktops, thin clients, and old hardware. The first and most
hostile target: **archlinux32 i686 on the 2006 Apple MacBook A1181**
(32-bit Core Duo, GMA 950, 32-bit Apple EFI). This branch is based on
upstream Omarchy v4.0.1 "Quattro".

## Try it

This is pre-release software that has never run on real hardware. It is
looking for testers, and **a hardware report is the most useful thing
you can send** - what your machine is, and what did or did not come up.

1. **Look at it first**, in a browser, no install:
   [omarchy32.cederik.com/vnc.html](https://omarchy32.cederik.com/vnc.html),
   password `omarchy32view`. That is a live session on the dev bench, so
   it is sometimes down.
2. **Read [`TESTING.md`](TESTING.md)** - what is validated, what is
   known broken or permanently absent (do not report those), what to
   test, and the exact diagnostics to gather.
3. **Install it.** x86_64 is the easy path and the one most testers
   want: [`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md),
   including a copy-pasteable QEMU line for a VM with no GPU. The
   32-bit MacBook path is
   [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md).
4. **Report** with the
   [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml).

## What changed

| Upstream | This fork | Why |
|---|---|---|
| Hyprland on GLES 3.0+ | the same Hyprland on a pixman (CPU) renderer | zero-GPU compositing |
| Quickshell desktop | waybar, fuzzel, mako, swaylock behind shims | no Qt GL |
| SDDM greeter | greetd + tuigreet, autologin session | no GL at login |
| limine + 64-bit UKI | GRUB i386-efi as BOOTIA32.EFI | 32-bit Apple EFI |
| Arch x86_64 + pkgs.omarchy.org | archlinux32 i686 + fork overrides | 32-bit CPU |
| 147-package app fleet | 78-package core, bring your own apps | 2 GB RAM |

The compositor is real Hyprland, not a substitute: this fork's
[Hyprland](https://github.com/cederikdotcom/Hyprland/tree/pixman-renderer)
and [aquamarine](https://github.com/cederikdotcom/aquamarine/tree/cpu-backend)
branches add a pixman software renderer, selected with
`HYPRLAND_RENDERER=pixman`. It renders flat: no animations, blur, shadows
or rounded corners. The Hyprland and aquamarine binaries come from that
fork build until a fork package repo exists; everything else installs from
the distribution repos.

Kept unchanged: the Hyprland config layer (`config/hypr`, `default/hypr`),
the theme engine, the bash environment, the omarchy CLI router, keybinding
philosophy, zram/oomd memory tuning. New: `omarchy-remote-view` serves the
live session over VNC (wayvnc, CPU-side screencopy) for cloud and headless
use.

## Status

Pre-release, and mid-migration. The fork shipped a sway substitute until
the pixman renderer for Hyprland worked; sway is now deleted and the
upstream Hyprland session is back. **Every install-level validation below
was done on the sway session and has to be redone on Hyprland.**

Proven on the pixman renderer itself (see
[`docs/pixman-renderer/PROGRESS.md`](docs/pixman-renderer/PROGRESS.md)):
Hyprland composites headless, nested, and on a real DRM display inside the
i686 VM, damage-driven, at 0.05 % idle CPU.

Proven end to end:

- **i686**, on a bench that mimics the MacBook1,1 (32-bit CPU model,
  2 GB RAM, IA32 UEFI firmware): the fork's own installer builds a
  system that boots to a themed desktop with zero failed units. Proven
  on the sway session and pending a rerun on Hyprland + Quickshell.
- **x86_64**, in a VM with no GPU: the same procedure boots to the
  Quickshell desktop with the pixman renderer, greetd starting the
  session itself, and Qt Quick on its software scenegraph. Screenshot:
  [`docs/pixman-renderer/x86_64-hyprland.png`](docs/pixman-renderer/x86_64-hyprland.png).

Not yet run on the physical MacBook (the GMA 950 render floor is the open
hardware question), nor on any real x86_64 machine.

## Documentation

- [`TESTING.md`](TESTING.md) - the tester's contract: what works, what
  is knowingly broken, what to test, how to report
- [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md) - the honest
  contract: what is validated, every bug found and fixed during
  validation, what is missing, and what this stack can never do
  (screen sharing, animations, shader effects)
- [`docs/a1181-gap-analysis.md`](docs/a1181-gap-analysis.md) - the
  verified gap matrix and the worklist that drove the port
- [`docs/runbooks/install-x86_64.md`](docs/runbooks/install-x86_64.md) -
  the x86_64 quick start, plus the QEMU and cloud test targets
- [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md) -
  the i686 install procedure, including the manual ISO-layer duties and
  the override packages
- [`docs/runbooks/testbench.md`](docs/runbooks/testbench.md) - the
  cloud test bench (i686 chroot, IA32-UEFI QEMU VM, browser view)

## Caveats, honestly

No screen sharing ever (pixman has no screencast path). No hardware
video decode, no Vulkan, no animations or blur. Four `MultiEffect` uses
in the shell render unembellished, because the software scenegraph has
no shaders. Updates do not track
upstream; on i686 the fork carries its own package overrides
(fontconfig, neatvnc) because archlinux32 has real dependency drift -
x86_64 needs neither. See the release notes for the full list.

---

Upstream README below.

# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## The Omarchy Manual

The manual lives in [`manual/`](manual/), which is its authoritative source. It's
mirrored to [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual), where
its screenshots are also hosted.

- [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md)

**The Basics**

- [Getting Started](manual/02-getting-started.md)
- [Coming From Mac or Windows](manual/03-coming-from-mac-or-windows.md)
- [Navigation](manual/04-navigation.md)
- [The top bar](manual/05-the-top-bar.md)
- [Themes](manual/06-themes.md)
- [Hotkeys](manual/07-hotkeys.md)
- [Unified Clipboard & History](manual/08-unified-clipboard-history.md)
- [Reminders](manual/09-reminders.md)
- [Notices](manual/10-notices.md)
- [Text Extraction & Dictation](manual/11-text-extraction-dictation.md)
- [Screenshots & Recording](manual/12-screenshots-recording.md)
- [Toggles, idle & screensaver](manual/13-toggles-idle-screensaver.md)
- [Omarchy CLI](manual/14-omarchy-cli.md)

**The Applications**

- [Terminal](manual/15-terminal.md)
- [Neovim](manual/16-neovim.md)
- [AI](manual/17-ai.md)
- [Development Tools](manual/18-development-tools.md)
- [Shell Tools](manual/19-shell-tools.md)
- [Shell Functions](manual/20-shell-functions.md)
- [TUIs](manual/21-tuis.md)
- [GUIs](manual/22-guis.md)
- [Browsers](manual/23-browsers.md)
- [Commercial apps/services](manual/24-commercial-apps-services.md)
- [Web Apps](manual/25-web-apps.md)
- [Gaming](manual/26-gaming.md)
- [Filling out PDFs](manual/27-filling-out-pdfs.md)
- [Windows VM](manual/28-windows-vm.md)
- [Other Packages](manual/29-other-packages.md)

**Configuration**

- [Updates](manual/30-updates.md)
- [Dotfiles](manual/31-dotfiles.md)
- [Shell plugins](manual/32-shell-plugins.md)
- [Monitors](manual/33-monitors.md)
- [Keyboard, Mouse, Trackpad](manual/34-keyboard-mouse-trackpad.md)
- [Networking](manual/35-networking.md)
- [System sleep](manual/36-system-sleep.md)
- [Hardware authentication](manual/37-hardware-authentication.md)
- [Fonts](manual/38-fonts.md)
- [Backgrounds](manual/39-backgrounds.md)
- [Prompt](manual/40-prompt.md)
- [Branding](manual/41-branding.md)
- [Common tweaks](manual/42-common-tweaks.md)
- [Making your own theme](manual/43-making-your-own-theme.md)

**The Rest**

- [Mac support](manual/44-mac-support.md)
- [Troubleshooting](manual/45-troubleshooting.md)
- [FAQ](manual/46-faq.md)
- [System snapshots](manual/47-system-snapshots.md)
- [Security](manual/48-security.md)
- [Omarchy on...](manual/49-omarchy-on.md)
- [Dual Boot Install](manual/50-dual-boot-install.md)
- [Unattended Installs](manual/51-unattended-installs.md)

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
