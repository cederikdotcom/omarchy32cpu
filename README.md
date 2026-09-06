# omarchy32cpu

**Pure CPU-bound Omarchy.** The full Omarchy workflow - tiling,
workspaces, keybindings, the 24-color theme engine, the menu system
and the CLI tooling - with no GPU dependence at all and no
preinstalled applications. Every pixel is drawn by the CPU.

It runs where stock Omarchy cannot: VMs without GPU passthrough, cloud desktops, thin clients, and old hardware. The first and most hostile target is **archlinux32 i686 on the 2006 Apple MacBook A1181** (32-bit Core Duo, GMA 950, 32-bit Apple EFI). The port began on upstream Omarchy v4.0.1 "Quattro" and now integrates the current `upstream/quattro` history.

## Try it

This is pre-release software. It now boots and runs the real Omarchy desktop on its physical MacBook1,1 target, but several hardware acceptance checks remain open. **A hardware report is still the most useful thing you can send** - what your machine is, what worked, and the exact point where it did not.

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
| Quickshell desktop on Qt GL | the same Quickshell on Qt's software scenegraph | no GPU for Qt either |
| SDDM greeter | greetd + tuigreet, autologin session | no GL at login |
| limine + 64-bit UKI | GRUB i386-efi as BOOTIA32.EFI | 32-bit Apple EFI |
| Arch x86_64 + pkgs.omarchy.org | archlinux32 i686 + fork overrides | 32-bit CPU |
| Upstream app fleet | Minimal core, bring your own apps | Physical target has about 1 GB usable RAM |

The compositor is real Hyprland, not a substitute: this fork's
[Hyprland](https://github.com/cederikdotcom/Hyprland/tree/pixman-renderer)
and [aquamarine](https://github.com/cederikdotcom/aquamarine/tree/cpu-backend)
branches add a pixman software renderer, selected with
`HYPRLAND_RENDERER=pixman`. It renders flat: no animations, blur, shadows
or rounded corners. The Hyprland and aquamarine binaries come from that
fork build until a fork package repo exists; everything else installs from
the distribution repos.

The upstream workflow and keybinding philosophy are retained, with hardware, package and session adaptations tracked in the [divergence registry](docs/divergence.md). New: `omarchy-remote-view` serves the live session over VNC (wayvnc, CPU-side screencopy) for cloud and headless use.

### Hyprland and aquamarine are separate forks

Omarchy's divergence totals cover this repository only. CPU composition is tracked in [Hyprland / `pixman-renderer`](https://github.com/cederikdotcom/Hyprland/blob/pixman-renderer/docs/divergence.md); CPU allocation and display presentation are tracked in [aquamarine / `cpu-backend`](https://github.com/cederikdotcom/aquamarine/blob/cpu-backend/docs/divergence.md). Those documents contain the detailed patch ownership, upstream backlog, limitations, validation gates and issue links. Each distinguishes custom patches against its pinned release baseline from its distance to current upstream main.

## Status

The physical convergence run now includes upstream `quattro` through `36e56f4f`. Linux reports approximately **1 GB usable RAM on the actual Mac**, unlike the 2 GB VM used for the older memory figures below. Recovered compatibility package recipes live in [`packages/`](packages/README.md).

Pre-release. The fork shipped a sway substitute until the pixman renderer
for Hyprland worked; sway is now deleted and the upstream Hyprland session
is back. **Both architectures have been revalidated on Hyprland +
Quickshell**, so nothing below rests on the sway session any more.

Proven on the pixman renderer itself (see
[`docs/pixman-renderer/PROGRESS.md`](docs/pixman-renderer/PROGRESS.md)):
Hyprland composites headless, nested, and on a real DRM display inside the
i686 VM, damage-driven, at 0.05 % idle CPU.

Proven end to end:

- **x86_64**, in a VM with no GPU: the fork's own installer boots to the
  Quickshell desktop with the pixman renderer, greetd starting the
  session itself, and Qt Quick on its software scenegraph. Screenshot:
  [`docs/pixman-renderer/x86_64-hyprland.png`](docs/pixman-renderer/x86_64-hyprland.png).
- **i686**, on a bench that mimics the MacBook1,1 (32-bit Core Duo model,
  2 GB RAM, IA32 UEFI firmware): a fresh image built by following
  [`docs/runbooks/a1181-install.md`](docs/runbooks/a1181-install.md)
  literally boots firmware -> `BOOTIA32.EFI` -> GRUB -> kernel -> greetd
  -> the desktop, with `Renderer: pixman (software)` on `Backend: drm`
  and zero failed units. Five cold boots out of five landed on the
  desktop. Screenshot:
  [`docs/pixman-renderer/i686-greetd-desktop.png`](docs/pixman-renderer/i686-greetd-desktop.png).
  The i686 compositor, shell and their unpackaged dependencies install
  prebuilt from
  [release `i686-20260902`](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/i686-20260902).

**The full desktop fits in 2 GB, with room for a browser.** Measured in
that i686 VM held at 2048 MB: idle it uses 489 MB and leaves 1466 MB
free, of which the shell is 210 MB on the default wallpaper, the
compositor 61 MB and a terminal 16 MB. A 1.3 GB workload ran on top of
it with 260 MB still free and zram never touching more than 1 MB. The
number that moves is the wallpaper, not the plugin set: shell RSS is
about `135 MB + the decoded background`, which spans 144 MB to 272 MB
across the wallpapers this repo ships.

The physical MacBook1,1 crossed the hardware boundary on 2026-09-04 and 2026-09-05. Apple EFI32 reached the ArchLinux32 live system through the documented rEFIt/split-GRUB bootstrap; the installed system then drove the built-in 1280x800 LVDS panel with the GMA 950, started greetd, Hyprland's pixman renderer, and the upstream Quickshell desktop, and remained reachable over ath5k Wi-Fi and key-only SSH. The built-in keyboard and pointer motion work. A compositor-level synthetic test also moved the cursor and focused two different windows with clicks.

The remaining input gate is physical button confirmation after the new libinput quirk. The internal `05ac:0217` device exposes one physical `BTN_LEFT` signal, but libinput did not classify this product as Apple's pre-2008 one-button model. The live machine now loads `ModelAppleTouchpadOneButton=1`; left-click and two-finger right-click still need a recorded hands-on pass. Trackpad enumeration has also intermittently required reloading `appletouch`, which reinitializes Geyser mode without restarting Hyprland.

The earlier “about one login in five” result remains useful historical evidence from the VM-era stack, but it is no longer an adequate description of the current machine. Later work found independently demonstrable package and input defects, including incompatible dconf/glib components, a libinput library shadowed by the stack tarball, and the missing `05ac:0217` quirk. The safe A1181 input configuration remains in place until the rebuilt package closure and physical input have been revalidated together. See [`docs/history/a1181-port-lessons.md`](docs/history/a1181-port-lessons.md) for the corrected chronology.

## Documentation

- [`TESTING.md`](TESTING.md) - the tester's contract: what works, what
  is knowingly broken, what to test, how to report
- [`docs/RELEASE-NOTES.md`](docs/RELEASE-NOTES.md) - the honest
  contract: what is validated, every bug found and fixed during
  validation, what is missing, and what this stack can never do
  (screen sharing, animations, shader effects)
- [`docs/a1181-gap-analysis.md`](docs/a1181-gap-analysis.md) - the
  verified gap matrix and the worklist that drove the port
- [`docs/history/a1181-port-lessons.md`](docs/history/a1181-port-lessons.md) - the historical record: incorrect assumptions, validation layers, measurement corrections, physical findings, and installer requirements
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
upstream; on i686 the fork carries package overrides because archlinux32 has real dependency and ABI drift. The physical baseline currently includes rebuilt fontconfig, neatvnc, libinput, and dconf components; the latter two are not yet published through a fork package repository. See the release notes and historical lessons for the exact status.

---

Upstream README below.

# Omarchy

Omarchy is a beautiful, fun & agentic Linux distribution by DHH.

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
