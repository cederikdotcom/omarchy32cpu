# Runbook: install omarchy32cpu on x86_64

The low-friction path, and the one most testers want. omarchy32cpu was built for a 2006 32-bit MacBook, but the thing that makes it interesting - a desktop that needs no GPU at all - is architecture-independent. On official Arch x86_64 the whole archlinux32 problem disappears: no override packages, no 32-bit EFI, no dependency drift.

Read [`../../TESTING.md`](../../TESTING.md) first. It says what is known broken and what to report.

Status: rehearsed end to end on 2026-08-31 in a QEMU VM with no GPU - the build below booted to a themed desktop with a working menu and terminal. Nobody has run it on real x86_64 hardware yet. That is what we are asking for. See "What was verified" at the end for exactly what that covers.

The rehearsal was originally run against the sway session this fork used before the pixman renderer for Hyprland existed. sway is now deleted, and the rehearsal was **repeated end to end on the Hyprland session on 2026-08-31**, from a root built by these steps. What that covers is in "What was verified" at the end.

## What differs from the i686 MacBook path

The procedure below is the [A1181 runbook](a1181-install.md) with four things removed. Everything else - the same package core, the same `omarchy-apply-system` flow, the same manual config seeding in place of `/etc/skel`, the same greetd session, the same pixman renderer - is unchanged.

| A1181 (i686) | x86_64 | Why |
|---|---|---|
| archlinux32 repos, `Architecture = i686` | official Arch, `Architecture = auto` | ordinary Arch |
| fontconfig + neatvnc override packages | none | Arch already carries fontconfig 2:2.18.3 and neatvnc 1.0.1 |
| GRUB `i386-efi` as `BOOTIA32.EFI` | GRUB `x86_64-efi` as `BOOTX64.EFI`, or systemd-boot | ordinary 64-bit UEFI |
| Apple hardware fixes (mbpfan, iSight, ath5k) | none, unless you have that hardware | DMI-guarded, they skip themselves |

`omarchy-refresh-grub` picks the right target from `uname -m`, so you do not need to think about it.

## Install

You need an Arch install medium and the standard Arch install knowledge. This is not an installer; it is a set of steps on top of a normal Arch install.

1. Boot the Arch ISO. Connect to the network (`iwctl` for wifi).

2. Partition. GPT, a 512 MB ESP (FAT32) mounted at `/boot`, and an ext4 root. Mount root at `/mnt` and the ESP at `/mnt/boot`.

3. Install the core:

   ```bash
   pacstrap -K /mnt $(grep -v '^#' /path/to/omarchy32cpu/install/omarchy-base.packages | grep -v '^$')
   ```

   That is the same 80-package list the MacBook uses. It pulls in roughly 250 packages with dependencies. If you have not cloned the repo yet, `pacstrap -K /mnt base linux linux-firmware git` first, then clone it inside the target and rerun `pacstrap` with the list.

4. The usual Arch system files, before anything else runs:

   ```bash
   genfstab -U /mnt >> /mnt/etc/fstab
   echo myhostname > /mnt/etc/hostname
   echo "KEYMAP=us" > /mnt/etc/vconsole.conf      # write this BEFORE mkinitcpio
   echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
   echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
   ln -sf /usr/share/zoneinfo/<Region>/<City> /mnt/etc/localtime
   arch-chroot /mnt locale-gen
   ```

   `omarchy-hyprland-launch` reads the keyboard layout out of `/etc/vconsole.conf`, so what you put there is what the desktop gets.

5. Put the repo where the session expects it, and create your user:

   ```bash
   git clone https://github.com/cederikdotcom/omarchy32cpu /mnt/usr/share/omarchy
   arch-chroot /mnt useradd -m -G wheel -s /bin/bash <user>
   arch-chroot /mnt passwd <user>
   ```

   `/usr/share/omarchy` is not negotiable: greetd's session command is an absolute path into it.

6. Run the system stage in the chroot:

   ```bash
   arch-chroot /mnt /usr/share/omarchy/bin/omarchy-apply-system --install-user <user> --first-install
   ```

   This does config, hardware detection, the greetd login config and post-install. It writes a log to `/var/log/omarchy-install.log`. The hardware scripts are all guarded and skip themselves on machines they do not match.

   ufw comes up enforcing deny-incoming. `ufw allow` anything you need once you have booted; rules cannot be added from inside a chroot.

7. Run the user stage. Upstream's omarchy package seeds `/etc/skel`; this fork has no package, so seed the config by hand:

   ```bash
   arch-chroot /mnt sudo -u <user> bash -c '
     mkdir -p ~/.config
     cp -r /usr/share/omarchy/config/* ~/.config/
     OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH \
       omarchy-provision-user --first-install --force'
   ```

8. Bootloader:

   ```bash
   arch-chroot /mnt /usr/share/omarchy/bin/omarchy-refresh-grub
   ```

   On a first run this installs GRUB as `/boot/EFI/BOOT/BOOTX64.EFI` in the removable fallback path (`--removable --no-nvram`, so it needs no NVRAM write and works in a VM or on a machine with a hostile firmware), then writes `grub.cfg`. Run it again after every kernel update.

   If you would rather use systemd-boot, install it the usual way and skip this step. Nothing in the fork depends on GRUB except this command.

9. **Install the compositor.** `install/omarchy-base.packages` deliberately does not carry Hyprland: the session needs this fork's build, which adds the pixman (CPU) renderer that upstream Hyprland does not have.

   ```bash
   # cederikdotcom/Hyprland   branch pixman-renderer  (base v0.56.2)
   # cederikdotcom/aquamarine branch cpu-backend      (base v0.15.0)
   ```

   First install the hypr* libraries the fork binaries link. On x86_64 official Arch carries all of them at the versions Hyprland 0.56 wants, so they are the one part of the compositor you do not have to build:

   ```bash
   arch-chroot /mnt pacman -S --needed hyprutils hyprlang hyprcursor hyprgraphics hyprwire
   ```

   They are deliberately absent from `install/omarchy-base.packages`, which has to name only packages that exist on both arches, and archlinux32 has these either missing or far too old. `hyprwayland-scanner` is a build-time dependency and belongs in the build environment, not the target.

   Then build aquamarine, then Hyprland against it, and install both into the target. A stock `pacman -S hyprland` will install and then fail on the missing GLES 3.0; it is not a substitute. Until a fork package repo exists this step is manual.

   The Hyprland build installs its own `hyprland.desktop` and `hyprland-uwsm.desktop` into `/usr/local/share/wayland-sessions/`. Neither sets `HYPRLAND_RENDERER=pixman`, so picking either one in the greeter gives you a black screen on a machine with no GPU. The installer puts the working entry at `/usr/share/wayland-sessions/omarchy.desktop`; delete upstream's two if you do not want them offered.

10. **Install the shell.** The Omarchy desktop is Quickshell: the bar, the menu, notifications, the OSD, the wallpaper, the lock screen, the tray and the whole plugin system are QML under `shell/`. Quickshell is in neither official Arch nor archlinux32 (upstream installs it from `pkgs.omarchy.org`), so this is the second thing the fork cannot yet package, and it is built from source exactly like the compositor.

    Its runtime dependencies are already in `install/omarchy-base.packages`. Its build-only dependencies are not, because they belong on the build host rather than on the target:

    ```bash
    arch-chroot /mnt pacman -S --needed --asdeps \
      cmake ninja pkgconf git cli11 qt6-shadertools spirv-tools \
      wayland-protocols vulkan-headers
    ```

    `vulkan-headers` is headers only. Quickshell needs it to compile its screencopy support; there is no runtime Vulkan requirement, and nothing here asks the GPU for anything.

    ```bash
    git clone --depth 1 --branch v0.3.1 \
      https://github.com/quickshell-mirror/quickshell /mnt/opt/quickshell
    arch-chroot /mnt bash -c 'cd /opt/quickshell &&
      cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
        -DDISTRIBUTOR="omarchy32cpu" \
        -DCRASH_HANDLER=OFF \
        -DINSTALL_QML_PREFIX=lib/qt6/qml &&
      ninja -C build &&
      ninja -C build install'
    ```

    About five minutes at `-j8`. `-DCRASH_HANDLER=OFF` is deliberate: the handler needs `cpptrace`, which archlinux32 does not carry, and keeping one build recipe for both arches is worth more here than the crash reporter. On x86_64 you may drop that flag if you also install `cpptrace`.

    **Quickshell links private Qt APIs.** It must be rebuilt whenever `qt6-base` or `qt6-declarative` is upgraded, or it dies on an ABI mismatch. If you are not prepared to rebuild it, pin those two packages.

    Verify before rebooting:

    ```bash
    arch-chroot /mnt quickshell --version    # Quickshell 0.3.1 ... distributed by omarchy32cpu
    ```

11. Reboot. greetd starts `/usr/share/omarchy/bin/omarchy-hyprland-launch`, which sets `HYPRLAND_RENDERER=pixman`, `AQ_FORCE_ALLOCATOR=dumb` and `QT_QUICK_BACKEND=software`, and autologs `<user>` into Hyprland.

    That third variable is what makes Quickshell draw on the CPU, and it is easy to get wrong. `QT_QUICK_BACKEND=software` selects Qt Quick's software scenegraph. `QSG_RHI_BACKEND=software` does **not**: that variable picks a graphics API (`opengl`/`vulkan`/`d3d11`/`metal`/`null`), `software` is not one of its values, and Qt answers `Unknown key "software" for QSG_RHI_BACKEND, falling back to default backend`. On a machine with Mesa installed the default backend then succeeds through llvmpipe, so the desktop still comes up and looks right while costing about 440 MB more RSS - measured in this VM at 1280x800 with the same wallpaper, 234 MB software against 672 MB fresh and 698 MB settled through llvmpipe. A working shell is not by itself evidence of CPU rendering. Check it properly:

    ```bash
    QSG_INFO=1 quickshell -p /usr/share/omarchy/shell 2>&1 | grep -i backend
    # qt.scenegraph.general: Loading backend software
    ```

## Test target A: a QEMU VM with no GPU

The most reproducible tester setup there is, and the one closest to what the fork is for. `-vga std` gives the guest a bochs-drm framebuffer: real KMS, no GPU acceleration of any kind. That is exactly the render floor omarchy32cpu targets.

Create a disk and install into it from the Arch ISO with the steps above:

```bash
qemu-img create -f qcow2 omarchy-x86_64.qcow2 16G
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd ./OVMF_VARS.fd   # Arch host
# Debian/Ubuntu host: cp /usr/share/OVMF/OVMF_VARS_4M.fd ./OVMF_VARS.fd

qemu-system-x86_64 \
  -enable-kvm -machine q35 -cpu host -smp 2 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
  -drive file=omarchy-x86_64.qcow2,format=qcow2,if=none,id=hd0 \
  -device ich9-ahci,id=ahci -device ide-hd,drive=hd0,bus=ahci.0 \
  -cdrom archlinux-x86_64.iso \
  -vga std \
  -netdev user,id=n0 -device e1000,netdev=n0 \
  -display gtk
```

On the Debian/Ubuntu firmware path the code file is `/usr/share/OVMF/OVMF_CODE_4M.fd`. Drop `-cdrom` after the install. Drop `-enable-kvm -cpu host` if you have no KVM (it will be slow but it works).

Two notes from building this image on a bench:

- Keep the initramfs small. `MODULES=(ahci sd_mod ext4 bochs)` and `HOOKS=(base udev modconf block filesystems fsck)` in `/etc/mkinitcpio.conf` gives a small image; the default `kms` hook drags in every GPU firmware blob and costs you a 180 MB initramfs you do not need in a VM.
- Add `console=tty0 console=ttyS0,115200` to `GRUB_CMDLINE_LINUX_DEFAULT` and run QEMU with `-serial file:serial.log`. When the graphical side fails, the serial log is the only thing that tells you why.

## Test target B: a cloud instance

Any provider's smallest x86_64 instance works, and there is no GPU to worry about by definition. The catch is that most providers give you an image, not an install medium; you either need a rescue/netboot mode you can run the steps above from, or a provider that lets you attach an Arch ISO.

Once it boots, the desktop is reachable without a console:

```bash
omarchy-remote-view on          # or menu: Trigger > Toggle > Remote View
```

That starts wayvnc against the live session over wlroots screencopy - a path that works precisely because the renderer is CPU-side. It binds `127.0.0.1:5901` only, so from your machine:

```bash
ssh -L 5901:127.0.0.1:5901 <user>@<host>
```

then point any VNC client at `localhost:5901`. For a browser instead of a VNC client, put a websockify/noVNC in front of it locally; `docs/runbooks/testbench.md` describes that setup as it is used for the project's own demo.

Do not expose 5901 directly. The default ufw posture denies incoming anyway.

## What was verified, and what was not

Verified on 2026-08-31 against official Arch x86_64 (`core` and `extra` from `geo.mirror.pkgbuild.com`), on a Debian 13 build box with no KVM (so the VM ran under TCG emulation):

- **Every name in `install/omarchy-base.packages` exists on official Arch x86_64 under exactly that name.** No renames, no substitutions, nothing missing. The list was checked package by package with `pacman -Si`, then resolved as a set, then really installed with `pacstrap` into a throwaway root.
- **No override package is needed.** Arch carries `fontconfig 2:2.18.3-2` - the same version the i686 path has to rebuild by hand - and `neatvnc 1.0.1-2` against `wayvnc 0.10.1-1`. Both of the archlinux32 dependency-drift bugs are simply absent here.
- **`omarchy-apply-system --install-user <user> --first-install` exits 0**, with every install phase logged as Completed, `display-manager.service` symlinked to `greetd.service`, and the expected `/etc/greetd/config.toml` including the `initial_session` autologin block.
- **`omarchy-provision-user --first-install --force` exits 0** and lands the Tokyo Night theme in `~/.local/state/omarchy/current/`.
- **`omarchy-refresh-grub` installs `BOOTX64.EFI`** and writes a grub.cfg with working kernel entries.
- **The whole chain boots**: 64-bit OVMF firmware -> `BOOTX64.EFI` -> GRUB -> kernel -> greetd -> the autologin session on the display, with `systemd` reaching `graphical.target`.
- **The desktop works.** The screenshot of that VM taken at the time showed the compositor, waybar, swaybg with the Tokyo Night background, two mako notifications, the fuzzel menu open on `Super+Space`, and a foot terminal opened with `Super+Return`. That was the shim desktop; `docs/pixman-renderer/x86_64-hyprland.png` now carries the Quickshell one instead (see the 2026-09-01 block below).

The renderer is worth restating: that is a full desktop drawn with the CPU, on a `-vga std` bochs framebuffer with no GPU acceleration available at all.

Re-verified on the Hyprland session on 2026-08-31, on the same bench and the same no-KVM TCG VM:

- **greetd starts the session itself.** `initial_session` autologs the install user in and the desktop comes up with no hand-launching; `journalctl -b -u greetd` shows one `session opened for user`. The process tree is `start-hyprland` → `Hyprland --watchdog-fd 4`.
- **The pixman renderer is the one running.** `hyprctl systeminfo` reports `Renderer: pixman (software)` and `Backend: drm` on `Virtual-1 1280x800`. This is worth checking rather than assuming: mesa's llvmpipe can supply GLES 3.0 in software, so a session that merely *renders* in a VM is not proof the CPU renderer was selected.
- **The session shell comes up**: waybar (with the `hyprland/workspaces` and `hyprland/submap` modules loading cleanly), mako, swaybg and swayidle.
- **The Lua config layer loads**: 414 keybindings, and waybar reserves its 26px at the top of the monitor.
- **Real key events work**, sent to the guest rather than dispatched over IPC: `Super+Return` opens foot, `Super+Space` opens the Omarchy menu, `Super+2` switches workspace and waybar follows.
- **Theme switching retints Hyprland.** `omarchy-theme-set Gruvbox` moves `general:col.active_border` from `ff7aa2f7` to `ff7daea3`, and the theme survives a reboot.

The package list, the boot chain, `omarchy-apply-system` and `omarchy-refresh-grub` were unaffected by the compositor swap and were re-run anyway as part of this.

Re-verified again on 2026-09-01, after the shim desktop was replaced by the real Quickshell shell, on the same VM. This run installed the tree over `/usr/share/omarchy`, re-ran step 6 and step 7, and rebooted, so everything below came up under greetd rather than by hand:

- **Every name in `install/omarchy-base.packages` was already present** in the target after the shim packages left the list and the `qt6-*` set joined it: 80 of 80 resolved, nothing to install.
- **greetd starts the Quickshell desktop.** The process tree is `Hyprland --watchdog-fd 4` and `quickshell -n -p /usr/share/omarchy/shell`, started by `default/hypr/autostart.lua` through `omarchy-launch-shell`. No `waybar`, `mako`, `swaybg`, `swayidle`, `swaylock` or `fuzzel` process exists, and `systemctl --failed` is empty.
- **The shell loads clean.** Zero QML errors. The only warnings are environmental in a VM: no `xdg-desktop-portal` settings interface, no `bluetoothd`, and one duplicate portal app-ID registration.
- **Qt is on the software scenegraph.** With `QSG_INFO=1` exported through `~/.config/omarchy/session-env`, the shell's journal carries exactly one scenegraph line, `qt.scenegraph.general: Loading backend software`, and no OpenGL or RHI line at all. `/proc/<shell>/maps` matches no Mesa driver, `libGL.so.*`, gallium, llvmpipe or Vulkan entry, and the process holds no `/dev/dri` descriptor.
- **Real key events reach the shell.** `Super+Space` (a QEMU `sendkey meta_l-spc`, not an IPC dispatch) opens the Omarchy menu, which renders its ten root rows with their icons.
- **Notifications work.** `omarchy-notification-send` renders a toast through the shell's own notification server, and `omarchy-shell notifications dismissAll` clears the stack.
- **Theme switching retints the shell in both directions.** `omarchy-theme-set "Catppuccin Latte"` turns the bar, the menu and the wallpaper light; `omarchy-theme-set "Tokyo Night"` turns them back.
- **Memory.** The shell is 234 MB RSS (208 MB PSS) on a 1280x800 session with the default theme, and it does not grow: 46 samples over 15 idle minutes stayed between 233.4 and 234.1 MB. What moves it is the wallpaper, which the shell holds at full decoded size, so `RSS ~= 190 MB + the decoded background`. See "What the shell's memory actually does" in [`docs/RELEASE-NOTES.md`](../RELEASE-NOTES.md) for the whole picture, including why the same session costs 698 MB through llvmpipe.
- **The plugin system is live**: `omarchy-plugin-catalog` enumerates the 37 first-party plugins.

One timing note for slow machines: `omarchy-theme-set` hardlinks the two wallpapers into `~/.cache/omarchy/background-transitions` and deletes them three seconds later, while the shell loads them asynchronously for the crossfade. Under TCG that window is occasionally too short and the shell logs `Cannot open .../next-<pid>.png`. Only the crossfade is lost: `Background.qml` applies the palette from a 300 ms fallback timer, so the retint itself still lands. It is upstream's own timing assumption and is left alone.

Not verified, and the reason this runbook exists:

- **No real x86_64 hardware.** Nothing here says anything about real graphics, wifi, audio, battery, suspend, brightness or a real display panel.
- **The steps as printed were not run as printed.** The VM was built by scripting the same operations against a mounted disk image rather than by typing them at an Arch ISO prompt. The commands are the same; the sequencing of a live install is not something this proves.
- **The GL renderer.** The session forces pixman. Nobody has run Hyprland's GL renderer here on hardware that could accelerate it.

Two known cosmetic issues on this path, both already understood:

- **foot prints deprecation warnings on every launch.** foot 1.27 (Arch) wants `[colors-dark]` where the fork's theme template writes `[colors]`, which is what foot 1.13 (archlinux32) requires. One static template cannot satisfy both, so the newer foot logs about 20 `deprecated:` lines per terminal. The colors themselves apply correctly. Do not report this.

## Troubleshooting

- **Black screen after greetd.** Ask the compositor what it picked: `hyprctl systeminfo | grep Renderer` should say `pixman (software)`. If it says anything else, the session did not get `HYPRLAND_RENDERER=pixman` - check `tr '\0' '\n' < /proc/$(pgrep -x Hyprland)/environ | grep -E 'HYPRLAND_RENDERER|AQ_'`. Then `dmesg | grep -i drm` for KMS errors; `journalctl -b -u greetd` has the login side. Note that Hyprland's own log at `$XDG_RUNTIME_DIR/hypr/<sig>/hyprland.log` is empty by default, because `debug:disable_logs` is on; `hyprctl systeminfo` is the reliable question to ask.
- **A session you picked from the greeter menu gives a black screen.** The Hyprland build installs `hyprland.desktop` and `hyprland-uwsm.desktop` into `/usr/local/share/wayland-sessions/`, and neither sets the pixman renderer. The entry that works is `Omarchy`, at `/usr/share/wayland-sessions/omarchy.desktop`. Delete upstream's two if you do not want them offered.
- **greetd shows the text greeter instead of autologging in.** `initial_session` runs once per boot; that is greetd semantics. A `systemctl restart greetd` always lands on tuigreet. Reboot, or log in through it.
- **You want to try the GPU.** The session forces `HYPRLAND_RENDERER=pixman` for the MacBook's sake. On real hardware, dropping that variable (and `AQ_FORCE_ALLOCATOR=dumb` with it) gives you Hyprland's normal GL path, which should be accelerated and faster, and nobody has tested it. Please do, and report it - see "The renderer question" in TESTING.md.
- **`pacman` wants to replace your pacman.conf.** It will not. The archlinux32 configs in `default/pacman/` are only applied when `uname -m` reports i686; on anything else the installer leaves your `/etc/pacman.conf` and mirrorlist alone.
- **Screen sharing fails.** Permanent under the pixman renderer, on every architecture. Not a bug.
