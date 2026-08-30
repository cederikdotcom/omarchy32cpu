# Omarchy Quattro on the 2006 MacBook A1181: gap analysis

Target: Omarchy 4 "Quattro" (this branch is based on the v4.0.1 tag) on the
2006 Apple MacBook A1181. Analysis date: 2026-08-30. Every claim below was
checked against the repo tree and against primary sources, then adversarially
re-verified by independent review passes (0 refutations).

## Verdict

Stock Omarchy Quattro cannot run on any 2006 A1181. Three hard blockers:

1. **GPU.** Hyprland >= 0.50 requires OpenGL ES 3.0+ (the legacy GLES2
   renderer was removed in 0.50). The GMA 950 (Intel i945, gen3) tops out at
   GL 2.1 / GLES 2.0 via Mesa i915g, with no hardware vertex shaders and no
   shader software fallback. Quickshell (Qt6 Quick) and the SDDM greeter
   (which itself starts Hyprland) fail for the same reason. llvmpipe on a
   2.0 GHz Core 2 Duo is unusable.
2. **Boot.** Omarchy boots via limine with a 64-bit UKI
   (`ENABLE_UKI=yes`, `/boot/EFI/Linux/omarchy_linux.efi`). Both A1181
   models have 32-bit (IA32) Apple EFI 1.10, which cannot execute a 64-bit
   EFI binary.
3. **CPU, on the early model only.** The MacBook1,1 (early 2006, Core Duo
   "Yonah") is 32-bit only. It can never run Arch x86_64 or this repo.
   archlinux32 carries only a fossilized Hyprland 0.4.5 on wlroots 0.16.

The split by model is decisive:

- **MacBook2,1 (late 2006, Core 2 Duo "Merom"): feasible.** Merom is
  x86-64-v1 (SSSE3, no SSE4) and Arch's baseline is still generic v1, so
  official Arch runs. GRUB `--target=i386-efi` loading a 64-bit kernel via
  EFI mixed mode is documented working on this exact machine. About 60% of
  this repo (theming engine, bash environment, CLI router, zram/oomd tuning,
  migrations framework) is compositor-agnostic and carries over unchanged.
- **MacBook1,1: out of scope.** The honest path there is archlinux32 or
  Void i686 with i3/X11, built separately, not a fork of this repo.

**This fork therefore targets the MacBook2,1 (and later Core 2 Duo A1181s
through MacBook4,1).** The delivered experience is Omarchy's workflow,
theming, keybindings and CLI tooling on sway with pure-CPU compositing:
no animations, no blur, no screen sharing. The silicon could never draw
those anyway.

## Gap matrix

Severity: **blocker** = stock Omarchy does not start. **major** = works but
defeats the machine or the fork. **minor** = degraded or wasteful.
**cosmetic** = nice to trim.

| # | Component | Omarchy requires | A1181 reality | Severity |
|---|-----------|------------------|---------------|----------|
| 1 | CPU / userland | Arch x86_64 + pkgs.omarchy.org (x86_64 only) | MacBook1,1 is 32-bit only; MacBook2,1 meets x86-64-v1 | blocker (1,1 only) |
| 2 | Hyprland | GLES 3.0+, no software path | GMA 950 caps at GL 2.1 / GLES 2.0, partly CPU-emulated | blocker |
| 3 | Quickshell (bar, menu, OSD, lock) | Qt6 Quick with working GL RHI + Hyprland IPC | Fragile-to-broken GL; nothing to talk to without Hyprland | blocker |
| 4 | SDDM greeter | `CompositorCommand=start-hyprland` + QML theme | Greeter needs the same GLES3 stack; login fails before the desktop | blocker |
| 5 | limine + UKI boot | 64-bit UKI on 64-bit UEFI | IA32 Apple EFI cannot run it; GRUB i386-efi or CSM works | blocker |
| 6 | Mesa gen3 driver | Accelerated Mesa assumed | Needs i915g; current Arch mesa (1:26.2.1) ships it, so no mesa-amber needed. Treat GL as decoration only | major |
| 7 | Package set / RAM | 147 base packages incl. chromium, docker, kdenlive, obs, libreoffice, obsidian, dotnet; 4-8 GB floor | MacBook2,1 caps at ~3 GB usable on a 5400 rpm disk | major |
| 8 | hyprctl in bin/ | ~53 of 441 bin scripts call hyprctl (incl. 24 `omarchy-hyprland-*`) | All dead once Hyprland is replaced | major |
| 9 | Update channel | Migrations + hooks track upstream omarchy packages | Upstream updates would reinstall Hyprland/quickshell/limine | major |
| 10 | Chromium / webapps | Chromium with Wayland ozone as webapp runtime | GPU blocklisted on GMA 950; each webapp costs 300-500 MB; no VAAPI | major |
| 11 | Theme templates | 5 of 22 themes ship `hyprland.lua` via `default/themed/hyprland.lua.tpl` | Templates target a compositor the fork drops; the 24-color engine itself is portable | minor |
| 12 | btrfs + snapper + snapshot boot | btrfs root, snapper, limine-snapper-sync, btrfs-overlayfs hook | Slow on a 2006 disk; snapshot boot entries depend on the dropped limine path | minor |
| 13 | LUKS argon2id cost | `--pbkdf argon2id --iter-time 2000` | Many seconds per unlock on Merom with 3 GB | minor |
| 14 | Hardware-detect false positives | vulkan.sh fires on any Intel VGA; sof-firmware.sh on any Intel audio | ANV needs Gen7+; ICH7 audio uses snd_hda_intel, never SOF | minor |
| 15 | A1181 enablement | None exists for pre-2015 Macs | iSight needs isight-firmware-tools + blob extraction; fans need applesmc + mbpfan; ath9k wifi is fine but disable NM powersave | minor |
| 16 | Screen capture | grim/slurp + gpu-screen-recorder (VAAPI) | No encoder on GMA 950; portal screencast does not work under the pixman renderer at all | minor |
| 17 | Plymouth | Boot splash in initramfs | Works, but costs boot time and RAM | cosmetic |
| 18 | voxtype / OCR / transcode | Whisper dictation hook, tesseract, ffmpeg helpers | Run, but unusable at Merom speed | cosmetic |

Affected files per gap are listed in the worklist below and in the commit
history of this branch as the work lands.

## Recommended path: "Omarchy Legacy" for the MacBook2,1

**Keep unchanged (~60% of the repo):** `default/bash`, the 24-color theme
engine and all non-hypr theme assets, foot/tmux/nvim/starship configs, the
`bin/` CLI router and its ~380 compositor-agnostic scripts, the migrations
framework, the pacman config structure, and the zram-generator
(`zram-size=ram`, zstd), systemd-oomd, zswap-off, sysctl and logind
drop-ins. Those memory drop-ins are exactly right for a 3 GB machine. Also
keep `fix-fkeys.sh` (hid_apple fnmode=2) and the LUKS provisioning flow (it
has no TPM assumption; only retune the argon2id cost).

**Swap:**

- Hyprland -> **sway with `WLR_RENDERER=pixman`** (pure-CPU compositing,
  needs only KMS; i915 KMS on i945 is mature). Note: sway/pixman on this
  exact chip has no public test report. Validate on hardware first. Since
  i915g exposes GLES 2.0, also try sway's default GLES2 renderer; it may
  even be hardware-accelerated. i3/X11 with the modesetting driver is the
  proven fallback if both disappoint.
- Quickshell -> **waybar + fuzzel + mako + swaylock + swayidle**, behind
  thin `omarchy-shell` / `omarchy-bar` / `omarchy-menu` / `omarchy-osd`
  shims so the existing bin/ callers keep working.
- SDDM-on-Hyprland -> **greetd + tuigreet** (or getty autologin, which
  matches upstream's unlock-then-autologin UX).
- limine + UKI -> **GRUB i386-efi** installed as `BOOTIA32.EFI`, plus a
  blessed `grub-mkstandalone` `boot.efi` for the Apple boot picker.
  `ENABLE_UKI=no`. CSM/BIOS boot is the fallback.
- hyprctl -> **swaymsg** via a new `omarchy-compositor-ctl` shim.
- `hyprland.lua.tpl` -> sway/waybar/mako theme templates.
- gpu-screen-recorder -> wf-recorder (CPU x264, short clips only).
- btrfs + snapper -> ext4 by default.
- hyprsunset -> wlsunset; xdg-desktop-portal-hyprland -> xdg-desktop-portal-wlr.

**Drop:** quickshell, docker*, kdenlive, obs-studio, libreoffice-fresh,
obsidian, dotnet-runtime, moonlight-qt, voxtype, plymouth, hibernation, the
default webapp fleet, and the nvidia/vulkan/SOF/T2 hardware stacks.

**Add:** isight-firmware-tools, mbpfan, grub, wlsunset, wf-recorder,
greetd-tuigreet, and a DMI-guarded `install/hardware/apple/fix-a1181.sh`.

**Install approach for v1:** skip a custom ISO. Boot the stock Arch ISO
(add an i386-efi GRUB to the USB, or use CD/CSM), pacstrap, then run this
fork's install-script path. An IA32-bootable ISO is a later milestone.

**Updates:** pin or fork `migrations/`, delete the two Hyprland libalpm
hooks, and point the update channel at a fork repo (or ship override
packages with Conflicts/Provides on the omarchy desktop metapackages) so an
upstream update cannot reinstall Hyprland, quickshell or limine.

**Browser:** keep Chromium with `--disable-gpu` in `chromium-flags.conf` to
skip the doomed GPU process; document Firefox with software WebRender as
the daily browser. Expect roughly 480p video as the practical ceiling.

**Permanent limitations to state honestly in the README:** no animations,
no blur, no portal screen sharing (pixman does not support screencast), no
hardware video decode, no Vulkan.

## Worklist

0. Verify a MacBook2,1 with max RAM (2x2 GB, ~3 GB usable). Declare
   MacBook1,1 unsupported in the README.
1. **Spike the render floor on hardware before porting anything:** minimal
   Arch + sway at 1280x800, test both the GLES2 renderer and
   `WLR_RENDERER=pixman`. If neither is usable, pivot to i3/X11 +
   modesetting and adjust items 4-7.
2. Confirm `/usr/lib/dri/i915_dri.so` on the installed mesa (present in
   1:26.2.1-1). Set `QSG_RHI_BACKEND=software` in `default/environment.d/`
   and document `LIBGL_ALWAYS_SOFTWARE` as the per-app escape hatch.
3. Boot chain: `grub-install --target=i386-efi --removable` plus a blessed
   `boot.efi`; `ENABLE_UKI=no`; remove `etc/limine-entry-tool.d/` and
   `default/limine/`; rewrite `bin/omarchy-refresh-limine` as
   `omarchy-refresh-grub`; trim `etc/mkinitcpio.conf.d/omarchy_hooks.conf`
   (drop plymouth and btrfs-overlayfs).
4. Fork `install/omarchy-base.packages` / `omarchy-other.packages` per the
   swap/drop/add lists above. Keep foot as the blessed terminal.
5. Write `config/sway/` replacing `config/hypr/` (bindings, rules,
   workspaces, autostart translated from the Lua configs; `looknfeel.lua`
   has no equivalent and is omitted). Rewrite
   `default/wayland-sessions/omarchy.desktop` and the uwsm defaults.
6. Shell shim layer: reimplement `bin/omarchy-shell`, `-bar`, `-menu`,
   `-osd`, `-notification-*`, `-system-lock` over waybar/fuzzel/mako/
   swaylock. Remove `shell/` (175 Qt/QML files) from the fork's build.
7. IPC pass: port the 24 `bin/omarchy-hyprland-*` scripts to swaymsg and
   route the ~29 incidental hyprctl calls through `omarchy-compositor-ctl`.
   Delete the two Hyprland libalpm hooks.
8. Theme pipeline: add `sway.tpl` + waybar/mako color templates next to
   `default/themed/hyprland.lua.tpl`; verify `omarchy-theme-set` end to end
   on 3 themes.
9. Login: replace `install/login/sddm.sh` with greetd/tuigreet, remove
   `etc/sddm.conf.d/` and `default/sddm/`, update
   `install/config/enable-services.sh` (also drop docker.socket).
10. Hardware pass: add `install/hardware/apple/fix-a1181.sh` (DMI-guarded:
    isight-firmware-tools with an ift-extract prompt, mbpfan, ath wifi
    powersave off). Tighten `install/hardware/vulkan.sh` and
    `install/hardware/intel/sof-firmware.sh` to skip i945 (PCI 8086:27a2).
11. Storage/FDE: default the documented install to ext4, guard
    `install/config/snapper.sh` behind a btrfs check, drop
    `bin/omarchy-hibernation-setup`, retune `bin/omarchy-drive-password`
    argon2id cost.
12. Browser: `--disable-gpu` in `config/chromium-flags.conf`, prune the
    webapp list, document Firefox software WebRender.
13. Updates: fork repo or override packages; pin/fork `migrations/`; keep
    the update-guard hook on the fork channel.
14. Validate the full manual install on the MacBook2,1: boot, unlock,
    login, sway session, theming, bar/menu/lock shims, wifi, webcam, audio,
    suspend/resume. Only then consider an IA32-bootable ISO.

## Key sources

- Hyprland 0.50 legacy renderer removal / GLES3 requirement:
  hypr.land/news/update50, hyprwm/Hyprland#10408
- wlroots pixman renderer: swaywm/wlroots#2661; screencast limitation:
  emersion/xdg-desktop-portal-wlr#289
- Mesa gen3 status: docs.mesa3d.org/amber.html; Arch mesa file list
  (i915_dri.so present in 1:26.2.1-1)
- Arch x86_64 baseline still v1: Arch RFC 0002 (v3 is a proposed
  additional port, not a baseline raise)
- GRUB i386-efi booting 64-bit Arch on a real MacBook2,1: Arch wiki
  MacBook page and tinkerdifferent.com build thread
