# History: how the MacBook1,1 port became a working system

This record preserves the decisions, failed assumptions, measurements, and recovery lessons from the Omarchy Quattro 2006 Mac work between 2026-08-30 and 2026-09-05. It is historical evidence, not an installation procedure. Use [`../runbooks/a1181-install.md`](../runbooks/a1181-install.md) for the current procedure, [`../../TESTING.md`](../../TESTING.md) for the current acceptance contract, and [`../RELEASE-NOTES.md`](../RELEASE-NOTES.md) for the chronological technical record.

The target is the early-2006 white MacBook A1181, EMC 2092, reported by DMI as `MacBook1,1`: 32-bit Core Duo, Intel GMA 950, and Apple EFI32. The VM used 2 GB RAM, which is the machine's supported capacity. The later physical convergence audit found only `990688 kB` usable RAM, approximately 1 GB, on this installed machine.

## The result

The project began with the conclusion that the MacBook1,1 was permanently out of scope. That conclusion was wrong. By 2026-09-05 the physical machine was running ArchLinux32 kernel 6.19.11, greetd, Hyprland 0.56.2 on the fork's pixman renderer, and the upstream Quickshell desktop on Qt's software scenegraph. The built-in LVDS panel, keyboard, pointer motion, Wi-Fi, and SSH were working. Hyprland and Quickshell survived compositor-level synthetic pointer movement and clicks.

Physical button validation remained open at the end of this record. The internal USB device is `05ac:0217`; Linux exposes one `BTN_LEFT` signal rather than independent left and right buttons. libinput 1.29 did not list this product among its pre-2008 one-button Apple models, misclassified it as a clickpad, and suppressed a button-only press while waiting for a finger position. The installed `ModelAppleTouchpadOneButton=1` override corrects that classification. A physical press with no finger should be left-click; two fingers plus the physical press should be right-click.

## Assumptions that testing overturned

| Early claim | What evidence changed it | Lasting lesson |
|---|---|---|
| `A1181` identified the machine well enough | Apple used A1181 across several generations; EMC 2092 and DMI `MacBook1,1` established the 32-bit target | Detect and document the exact DMI, CPU flags, PCI IDs, and USB product IDs before designing compatibility work |
| MacBook1,1 could not run a modern Wayland desktop | ArchLinux32 carried a usable base; sway/pixman proved CPU compositing; the Hyprland and aquamarine forks then ran the real compositor on i686 | Treat ecosystem absence as a build and maintenance question, not proof of architectural impossibility |
| Replacing Hyprland and Quickshell was the practical permanent design | The sway/shim port deleted tens of thousands of upstream lines and created a large merge surface; narrow renderer and launch adaptations restored upstream Hyprland, Quickshell, and plugins | Preserve upstream application code and adapt the smallest stable seam first |
| A desktop appearing proved CPU rendering | Qt silently accepted an invalid `QSG_RHI_BACKEND=software` request by falling back to llvmpipe | Prove the selected path from logs, process environment, mapped libraries, and device descriptors; appearance is not provenance |
| Static validation was enough after a clean merge | The runtime gate found missing WebP support and completely blank image-picker thumbnails with no warning or QML error | Visually exercise the shipped feature through the real login and session path |
| A growing RSS sample proved a memory leak | The measurement coincided with a theme change; repeated controlled samples showed flat idle memory and wallpaper-sized allocations that were released | Correlate measurements with state changes and repeat load/unload cycles before naming a leak |
| Renderer backtraces proved a renderer root cause | The allocator reported damage later than the corruption; physical work exposed input-triggered failures, an incompatible dconf service, a shadowed libinput, and a missing device quirk | A crash site is evidence about detection, not necessarily origin; keep competing hypotheses until a controlled reproducer isolates one |
| Package presence in an ArchLinux32 mirror meant the dependency set was coherent | Pango/fontconfig, Qt/ICU, libxml2, neatvnc, PipeWire, dconf/glib, and libinput exposed version or ABI gaps | Validate the installed closure, not package names: package integrity, `ldd -r`, service startup, and actual API use are release gates |

## The validation ladder

Each layer answered a different question. No layer was allowed to inherit claims from the one below it.

1. **Repository and package audit:** establishes names, versions, architecture availability, ownership, hashes, and divergence. It does not prove linking or runtime behavior.
2. **Native i686 chroot:** provides the fast loop for package installation, building, `ldd -r`, configuration validation, and target-side setup. It does not exercise firmware, DRM scanout, login handoff, or hardware input.
3. **Core-Duo/2-GB EFI32 VM:** rehearses `BOOTIA32.EFI`, GRUB, the i686 kernel, memory pressure, greetd, and the desktop on a disposable disk. It does not reproduce Apple firmware, GMA 950, ath5k, appletouch, or the physical panel.
4. **x86_64 runtime VM:** cheaply exercises the current upstream merge, WebP decoding, Quickshell plugins, captive portal, and visual regressions. It must boot through greetd rather than hand-starting the compositor.
5. **Physical MacBook:** is the only proof for Apple EFI32, GMA 950 dumb-buffer scanout, the LVDS panel and backlight, ath5k, appletouch, keyboard state, audio, battery, fan behavior, and suspend/resume.

The same separation applies inside a booted system: Apple EFI, rEFIt, external GRUB, kernel/initramfs, live Arch, the installed system, greetd/tuigreet, Hyprland, and Quickshell are different layers. Reaching one never proves the next. In particular, tuigreet is a text program managed by greetd before Hyprland starts; a TTY and SSH remain available when the graphical session is broken.

## Findings that belong in every future installer

- Resolve disks by stable identity, refuse the installer USB as a target, show the proposed partition table, and require an explicit confirmation before the first destructive write.
- Preserve Macintosh HD, rEFIt, and `/efi/omarchy` until the internal `BOOTIA32.EFI` path has survived several cold boots. The verified live-media route is part of the recovery system, not disposable scaffolding.
- Make the installer resumable at package bootstrap, keyring, initramfs, override packages, desktop stack, system setup, user setup, and bootloader installation. Record completion and exact inputs on the target.
- Fetch immutable artifacts before installation, verify independent hashes, verify ELF architecture, and save the manifest with the install log. Never build the seventeen-component desktop stack on the Core Duo as part of a normal install.
- Validate the package closure after every package transaction. At minimum: `pacman -Qkk`, `ldd -r` for Hyprland and Quickshell, dconf service startup plus a real read/write/reset, and `libinput quirks validate` plus a device listing.
- Run networking and firewall mutation late. The VM gate proved that reloading UFW can cut the SSH control path before a later failure aborts setup. Keep a TTY or out-of-band console available and validate the persisted rules before enabling them.
- Reboot through the shipped bootloader and greetd entry. A compositor started by hand does not validate the installer, environment, PAM session, or session launcher.
- Test authentication and physical input as acceptance criteria: type credentials, open a terminal, move the pointer, left-click, right-click, and type on the built-in keyboard. A live process list is not a usable desktop.
- Capture logs before reinstalling. A failed attempt with the exact commit, packages, journal, kernel messages, device IDs, and observations is more valuable than a clean disk with no evidence.

## Concrete rehearsal and hardware findings

The EFI32 VM caught four requirements before hardware: set `Architecture = i686` explicitly, install a mirrorlist into the target, create `/etc/vconsole.conf` before rebuilding initramfs, and install GRUB with `--removable --no-nvram`. A later cross-architecture rehearsal found that target architecture must come from the target GRUB platform/modules rather than `uname -m` in the installer.

The physical Mac found what the VM could not:

- Apple's Option picker did not expose the tested USB layouts. rEFIt launched a small external i386-EFI GRUB, but GRUB could not reliably rediscover USB and a 137 MB EFI embedding kernel/initramfs failed to load. The working split loaded kernel and initramfs from Macintosh HD and the live filesystem from USB. See historical issues [#20](https://github.com/cederikdotcom/omarchy32cpu/issues/20) and [#21](https://github.com/cederikdotcom/omarchy32cpu/issues/21).
- Ethernet carrier on `enp1s0` did not mean packets reached the Deco network. ath5k Wi-Fi through iwd worked and later remained connected through NetworkManager with powersave disabled. See [#22](https://github.com/cederikdotcom/omarchy32cpu/issues/22).
- The first installed desktop proved GMA 950 scanout, greetd, the pixman compositor, Qt software rendering, and the upstream shell on the physical Core Duo.
- Input exposed additional failures after the desktop appeared. Reloading only `appletouch` initialized Geyser mode and restored motion without restarting Hyprland. libinput then needed the exact `05ac:0217` one-button model override at `/etc/libinput/local-overrides.quirks`; arbitrary filenames in `/etc/libinput` are ignored.
- The control path should start from the live or installed Arch system with key-only SSH. That made package rebuilding, driver reloads, log capture, and reversible session tests possible without depending on the graphical desktop.

## Package baseline established on the physical machine

The 2026-09-05 system was clean at repository commit `21d1f16ca36c37ae25a32dcba24484be7a5e9d32` and ran glib2 `2.80.0-2.0`, Qt `6.7.2`, libinput `1.29.1-1.1`, and dconf `0.49.0-1.1`. Hyprland and Quickshell were installed from the external stack rather than pacman packages.

The two locally rebuilt packages were present only in the target's pacman cache at the time of this record:

| Package | SHA-256 |
|---|---|
| `libinput-1.29.1-1.1-pentium4.pkg.tar.zst` | `0c0da2a57be39c13841449caa7a8217c596e3cfb13a731a6f55a82749df2201b` |
| `dconf-0.49.0-1.1-pentium4.pkg.tar.zst` | `dcb02727a8e3ce658c1716d1a483969bb088fd06f040a385b4ed149396e46130` |

Both passed `pacman -Qkk` with zero altered files. The rebuilt dconf passed its executed test suite and a real setting write/read/reset. These hashes document the tested machine; they are not a distribution channel. Publishing signed packages and their PKGBUILDs remains part of the guarded-installer work in [#24](https://github.com/cederikdotcom/omarchy32cpu/issues/24).

## Measurement and debugging discipline

- Pin the exact repository commit and package versions at the start of every run.
- Measure the process actually running on the host; chroot PID namespaces and stale screenshots previously produced convincing but false evidence.
- Use QEMU monitor `screendump` for VM display truth. `grim` can return a stale mirror buffer on this renderer.
- For Qt, require `QT_QUICK_BACKEND=software`, `QSG_INFO=1`, and the `Loading backend software` line. Also confirm no Mesa driver is mapped when proving the no-GPU path.
- Change one config variable at a time, repeat enough starts to observe intermittent failures, and keep the minimal known-good configuration as a control.
- Record irreplaceable human observations alongside commands: whether the panel lit, whether credentials were accepted, whether physical clicks registered, and how long menu and wallpaper actions took.

## Session continuity is part of the test system

The user reported that two working sessions appeared to be lost during the hardware effort. The surviving `omarchy` tmux pane had no useful scrollback because the full-screen client had used the terminal's alternate screen. Its history was recovered from the agent transcript and checked against repository state, target journals, and the package cache. Complete recovery of both missing sessions was not established. Empty tmux history did not mean the work had never happened.

Future sessions should not depend on a terminal window as the system of record:

- Start every hardware run by recording the target DMI, repository commit, package versions, artifact hashes, active services, and network address into a dated log on persistent storage.
- Stream long-running installer and session output through `tee` or the system journal. Copy the final report off the target before rebooting or changing the package set.
- At each handoff, write the last proven state, the current hypothesis, the next exact action, and the recovery path into the repository history or its linked ticket.
- When a UI session disappears, inspect tmux panes, agent transcripts, shell history, system journals, and the target's filesystem before reconstructing or repeating work. Repetition without first recovering evidence can overwrite the only useful failure state.
- Treat an IP address as a convenience, not identity. Confirm the SSH host key and DMI before acting, and keep the live-media/TTY recovery rung available if Wi-Fi, firewall rules, or the graphical session changes.

## Durable design conclusions

- The fork's identity is real Omarchy on a CPU renderer, not a replacement desktop.
- Sway was a valuable recovery rung and prototype, but removing upstream Hyprland and Quickshell was not a sustainable final architecture.
- `greetd + tuigreet` and GRUB `i386-efi` are permanent hardware adaptations. The pixman renderer and Qt software backend are narrow, testable substitutions beneath otherwise upstream code.
- The package repository and guarded installer are product requirements, not polish. A tarball shadowing packaged libraries can prove feasibility, but it cannot provide reliable upgrades or reproducible recovery.
- Hardware support is complete only when the built-in display, authentication, keyboard, pointer motion, clicks, networking, audio, battery, thermal behavior, and suspend/resume have each been observed.

## Related tickets

- [#1 — Hyprland software renderer](https://github.com/cederikdotcom/omarchy32cpu/issues/1)
- [#2 — Quickshell on Qt software rendering](https://github.com/cederikdotcom/omarchy32cpu/issues/2)
- [#12 — A1181/i945 hardware divergence](https://github.com/cederikdotcom/omarchy32cpu/issues/12)
- [#20 — USB installer absent from Apple picker; rEFIt bootstrap](https://github.com/cederikdotcom/omarchy32cpu/issues/20)
- [#21 — EFI32 GRUB and split bootstrap history](https://github.com/cederikdotcom/omarchy32cpu/issues/21)
- [#22 — Ethernet failure and Wi-Fi workaround history](https://github.com/cederikdotcom/omarchy32cpu/issues/22)
- [#23 — preserving Macintosh HD/rEFIt](https://github.com/cederikdotcom/omarchy32cpu/issues/23)
- [#24 — guarded one-command installer](https://github.com/cederikdotcom/omarchy32cpu/issues/24)
- [#25 — reproducible EFI32 bootstrap media](https://github.com/cederikdotcom/omarchy32cpu/issues/25)
