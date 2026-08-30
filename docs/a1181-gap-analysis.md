# Omarchy CPU: pure CPU-bound Omarchy, 32-bit first

Identity: this fork is **Omarchy CPU** - the Omarchy experience with no
GPU dependence at all, and no preinstalled applications. Every pixel is
drawn by the CPU: sway compositing via the wlroots pixman renderer,
foot (CPU-rasterized terminal), waybar/fuzzel/mako/swaylock (cairo),
tuigreet (TTY). Mesa ships only so GL apps the user installs can fall
back to llvmpipe.

The fork has two layers:

1. **The CPU core** (architecture-independent): the compositor swap
   (Hyprland -> sway/pixman), the shell swap (Quickshell -> waybar/
   fuzzel/mako/swaylock shims), the swaymsg IPC port, the theme
   templates, the Lite package set. This layer also serves x86_64
   machines stock Omarchy cannot: VMs without GPU passthrough, cloud
   desktops, thin clients, old or broken graphics.
2. **The 32-bit target layer**: archlinux32 i686 pacman configs, GRUB
   i386-efi boot (BOOTIA32.EFI), and the A1181 hardware fixes, for the
   first and most hostile target: the 2006 MacBook1,1 (EMC 2092,
   32-bit Core Duo, 2 GB RAM, GMA 950, 32-bit Apple EFI).

This branch is based on the upstream v4.0.1 "Quattro" tag. Analysis
date: 2026-08-30, updated the same day after chroot and VM validation
on the cloud test bench. The Lite core is about 45 packages; the user
installs their own applications.

## Verdict

Stock Omarchy cannot run on the MacBook1,1 for three reasons: the CPU is
32-bit only (Core Duo "Yonah"), the GPU (GMA 950) cannot serve the GLES3
compositor stack (Hyprland, Quickshell, the SDDM greeter), and the 32-bit
Apple EFI cannot execute the limine 64-bit UKI.

All three have working adaptations on archlinux32:

1. **CPU:** archlinux32 i686 carries the entire Lite core (verified on the
   mirrors and installed in a test chroot 2026-08-30): sway 1:1.8 with
   wlroots 0.16.1 (pixman renderer included), swaylock, swayidle, waybar
   0.9.15, foot, fuzzel, mako, greetd-tuigreet, mesa 1:24.0.4 plus
   mesa-amber 21.3.9, kernel 6.19, networkmanager 1.56, pipewire.
2. **GPU:** sway with `WLR_RENDERER=pixman` (pure-CPU compositing, needs
   only KMS; i915 KMS on i945 is mature in-kernel). VALIDATED 2026-08-30:
   sway 1.8/pixman runs and answers IPC on i686 in the test chroot. The
   GMA 950 KMS path itself still needs the on-hardware spike.
3. **Boot:** a 32-bit kernel boots natively from the 32-bit Apple EFI via
   GRUB `--target=i386-efi` as `BOOTIA32.EFI`. No mixed mode, no UKI.
   Apple's CSM/BIOS path is the fallback.

What Omarchy loses: animations, blur, portal screen sharing (pixman does
not support screencast), hardware video decode, Vulkan. What survives:
the theming engine, keybinding philosophy, bash environment, CLI router,
and the zram/oomd memory tuning, which fits a 2 GB machine well.

## Gap matrix

Severity: **blocker** = stock Omarchy does not start. **major** = works
but defeats the machine or the fork. **minor** = degraded or wasteful.

| # | Component | Omarchy requires | MacBook1,1 reality | Severity | Adaptation |
|---|-----------|------------------|--------------------|----------|------------|
| 1 | CPU / userland | Arch x86_64 + pkgs.omarchy.org | 32-bit Core Duo | blocker | archlinux32 i686 repos; rebuild omarchy-own packages for i686 |
| 2 | Hyprland | GLES 3.0+ | GMA 950 caps at GL 2.1 | blocker | sway 1.8 + pixman renderer (validated i686, chroot) |
| 3 | Quickshell | Qt6 Quick GL + Hyprland IPC | No GL, no Hyprland | blocker | waybar + fuzzel + mako + swaylock behind omarchy-shell/bar/menu/osd shims |
| 4 | SDDM greeter | Hyprland + QML | Same GPU wall | blocker | greetd + tuigreet, or getty autologin |
| 5 | limine + 64-bit UKI | 64-bit UEFI | 32-bit Apple EFI | blocker | GRUB i386-efi as BOOTIA32.EFI, plain kernel+initramfs, ENABLE_UKI=no |
| 6 | Mesa for gen3 | Accelerated Mesa assumed | Needs i915g or mesa-amber | minor | Both on archlinux32; pixman path does not depend on GL |
| 7 | hyprctl in bin/ | ~53 of 441 scripts call hyprctl | Dead without Hyprland | major | Port 24 omarchy-hyprland-* to swaymsg; omarchy-compositor-ctl shim for the rest |
| 8 | Update channel | Tracks upstream x86_64 packages | Would reinstall Hyprland/limine | major | Fork repo or override packages; pin/fork migrations/; delete the 2 Hyprland libalpm hooks |
| 9 | Theme templates | 5 of 22 themes ship hyprland.lua | Targets a dropped compositor | minor | Add sway.tpl + waybar/mako templates; the 24-color engine is portable |
| 10 | btrfs + snapper | btrfs root, snapshot boot entries | Slow 2006 disk; boot entries need limine | minor | ext4 default; guard snapper.sh; drop hibernation-setup |
| 11 | LUKS argon2id cost | iter-time 2000, memory-hard | Seconds to tens of seconds on 2 GB | minor | Lower cost or make FDE opt-in |
| 12 | Hardware-detect false positives | vulkan.sh on any Intel VGA; sof-firmware.sh on any Intel audio | ANV needs Gen7+; ICH7 is snd_hda_intel | minor | Guard both against i945 (PCI 8086:27a2) |
| 13 | A1181 enablement | None exists upstream | iSight needs extracted firmware; fans need mbpfan; ath5k powersave drops | minor | New DMI-guarded install/hardware/apple/fix-a1181.sh |
| 14 | Screen capture | gpu-screen-recorder (VAAPI) | No encoder; no screencast under pixman | minor | grim stays; wf-recorder (CPU x264) for short clips |
| 15 | Plymouth | Boot splash | Costs boot time and RAM | minor | Drop; boot to tty into greetd |

Deleted by the Lite scope (no preinstalled apps): the 147-package app
fleet gap, the Chromium/webapps gap, voxtype/OCR/transcode, hibernation.

## archlinux32 findings from the test bench (2026-08-30)

Verified in a real i686 chroot (see docs/runbooks/testbench.md):

- The full Lite desktop core installs and sway runs (pixman, headless).
- **Broken pair found:** pango 1:1.57.1 needs fontconfig >= 2.16 but the
  repo ships 2:2.14.1; sway dies with `undefined symbol:
  FcConfigSetDefaultSubstitute`. Same in the pentium4 tree. Fix:
  rebuild fontconfig 2.18.3 from the Arch PKGBUILD with docs disabled
  (docbook DTDs missing) and meson >= 1.11 from pip (repo meson is
  1.4.0). The rebuilt package is the fork's first repo-hosted override.
- One stale package signature on the mirror (libvterm). Expect
  occasional signature and dependency drift; this is a small volunteer
  project. Budget for a handful of self-rebuilt packages.
- Repo browsers are ancient (chromium 90, firefox 114). Lite ships none.
  If a browser is wanted, use Mozilla's official i686 Firefox tarball
  (verify glibc compatibility first).
- pentium4 vs i686 trees carry the same versions; either works on the
  Core Duo (it has SSE3). The fork uses i686.

## Recommended build

**Keep unchanged:** `default/bash`, the 24-color theme engine and all
non-hypr theme assets, foot/tmux/nvim/starship configs, the `bin/` CLI
router and its compositor-agnostic scripts, the migrations framework,
zram-generator (`zram-size=ram`, zstd), systemd-oomd, zswap-off, sysctl
and logind drop-ins, `fix-fkeys.sh`, and the LUKS provisioning flow
(retune argon2id cost).

**Swap:** Hyprland -> sway/pixman; Quickshell -> waybar/fuzzel/mako/
swaylock shims; SDDM -> greetd/tuigreet; limine+UKI -> GRUB i386-efi;
hyprctl -> swaymsg; hyprland.lua.tpl -> sway/waybar/mako templates;
gpu-screen-recorder -> wf-recorder; btrfs -> ext4; hyprsunset ->
wlsunset; xdg-desktop-portal-hyprland -> xdg-desktop-portal-wlr.

**Drop:** every preinstalled application, plymouth, hibernation, the
nvidia/vulkan/SOF/T2 hardware stacks.

**Add:** isight-firmware-tools, mbpfan, grub, the rebuilt fontconfig,
and `install/hardware/apple/fix-a1181.sh`.

**Lite core (~45 packages):**

- System: base, linux, linux-firmware, grub, efibootmgr, networkmanager,
  pipewire, wireplumber, pipewire-pulse, polkit, brightnessctl,
  zram-generator, greetd, greetd-tuigreet, seatd
- Desktop: sway, swaybg, swaylock, swayidle, waybar, fuzzel, mako,
  wlsunset, grim, slurp, wl-clipboard, xdg-desktop-portal-wlr, foot
- CLI: git, starship, tmux, neovim, fzf, ripgrep, fd, bat, btop,
  fastfetch
- Mac: mbpfan; isight-firmware-tools optional
- Fork overrides: fontconfig 2.18.3 (and successors as drift appears)

## Worklist

1. DONE 2026-08-30: cloud test bench up (i686 chroot + IA32-UEFI QEMU
   VM); Lite core installed; sway/pixman validated on i686; fontconfig
   override built.
2. DONE 2026-08-30: full boot-chain rehearsal in the QEMU VM. Built the
   disk per the runbook (GPT, ESP at /boot, pacstrap Lite core, GRUB
   i386-efi as BOOTIA32.EFI, greetd initial_session into sway/pixman).
   The 32-bit OVMF firmware booted BOOTIA32.EFI -> GRUB -> i686 kernel
   -> greetd -> sway rendering on the display. The whole software stack
   is proven; only the GMA 950 remains. Findings folded into the
   install runbook (Architecture=i686 in pacman.conf, mirrorlist,
   vconsole.conf before mkinitcpio, MODULES for the initramfs).
3-9. DONE 2026-08-30 (commit 960896d6): the full repo port. Packages,
   boot chain (omarchy-refresh-grub), sway configs (validated with
   sway 1.8 -C on i686), shell shims over waybar/fuzzel/mako/swaylock,
   all hyprctl callers ported to swaymsg (live-tested against sway in
   the chroot), theme templates (3 themes rendered and validated),
   greetd login, archlinux32 pacman configs, i945 guards and
   fix-a1181.sh. test/cli passes 116/116. Remaining from the original
   steps, now the open list:
   - Test suite triage: prune Quickshell/Hyprland-era shell.d tests,
     port the rest (in progress).
   - Provisioning flows (omarchy-provision-owner, factory-reset) still
     reference sddm/limine; rework when provisioning matters.
   - Migrations are upstream's (pinned by fork divergence); write fork
     migrations from here on.
   The original step texts follow for reference.
3. Package lists: rewrite install/omarchy-base.packages to the Lite core;
   empty omarchy-other.packages of the Mac-irrelevant firmware sets.
4. Boot chain in the repo: remove etc/limine-entry-tool.d/ and
   default/limine/; rewrite bin/omarchy-refresh-limine as
   omarchy-refresh-grub; trim etc/mkinitcpio.conf.d/omarchy_hooks.conf.
5. Write config/sway/ replacing config/hypr/ (bindings, rules,
   workspaces, autostart translated from the Lua configs); rewrite
   default/wayland-sessions/omarchy.desktop and the uwsm defaults to
   start sway with WLR_RENDERER=pixman.
6. Shell shim layer: reimplement bin/omarchy-shell, -bar, -menu, -osd,
   -notification-*, -system-lock over waybar/fuzzel/mako/swaylock;
   remove shell/ from the build.
7. IPC pass: port the 24 bin/omarchy-hyprland-* scripts to swaymsg;
   route incidental hyprctl calls through omarchy-compositor-ctl; delete
   the two Hyprland libalpm hooks.
8. Theme pipeline: add sway.tpl + waybar/mako color templates; verify
   omarchy-theme-set end to end on 3 themes (testable in the chroot).
9. Login: replace install/login/sddm.sh with greetd/tuigreet; remove
   etc/sddm.conf.d/ and default/sddm/; update
   install/config/enable-services.sh.
10. Pacman: point default/pacman configs and mirrorlists at archlinux32
    (Architecture = i686); stand up a small fork repo for the override
    packages (fontconfig first) and the omarchy-own i686 rebuilds.
11. Hardware pass: add install/hardware/apple/fix-a1181.sh; guard
    vulkan.sh and sof-firmware.sh against i945.
12. Storage/FDE: ext4 defaults, guard snapper.sh, drop
    hibernation-setup, retune omarchy-drive-password.
13. Repeat the full VM rehearsal (step 2) with the forked installer end
    to end.
14. On-hardware spike on the MacBook1,1: boot the archlinux32 ISO, test
    sway GLES2 vs pixman at 1280x800 on the real GMA 950, then run the
    validated install. i3/X11 with the modesetting driver is the
    fallback if the Wayland floor disappoints.

## Key sources

- Hyprland 0.50 legacy renderer removal / GLES3 requirement:
  hypr.land/news/update50, hyprwm/Hyprland#10408
- wlroots pixman renderer: swaywm/wlroots#2661; screencast limitation:
  emersion/xdg-desktop-portal-wlr#289
- archlinux32 mirrors: mirror.archlinux32.org (i686 and pentium4 trees)
- GRUB i386-efi on 32-bit Apple EFI: Arch wiki MacBook page
- Test-bench validation logs: this repo's runbooks and the omarchy32-test
  server (see docs/runbooks/testbench.md)
