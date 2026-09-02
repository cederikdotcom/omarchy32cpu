# Runbook: install Omarchy CPU (32-bit) on the MacBook1,1

Status: **rehearsed from scratch on 2026-09-02, and the i686 login crash is
fixed.** A fresh image was built by following the steps below in order, then
booted under 32-bit UEFI firmware with 2048 MB, the MacBook's own memory size.
Firmware -> `BOOTIA32.EFI` -> GRUB -> i686 kernel -> greetd -> **the desktop**,
with no hand-holding: the bar, the tray, the clock, the theme wallpaper, a
terminal on `Super+Return` and the Omarchy menu on `Super+Space`. `hyprctl
systeminfo` reports `Renderer: pixman (software)` and `Backend: drm`, the shell
holds no `/dev/dri` descriptor, zero systemd units failed, and 491 MB of the
2 GB is in use. Five cold boots out of five landed on the desktop.

Screenshot: [`../pixman-renderer/i686-greetd-desktop.png`](../pixman-renderer/i686-greetd-desktop.png).

The crash that used to end every i686 login turned out to be reachable from one
line of ordinary configuration, `input:numlock_by_default`, and the fork now
ships it off. The underlying renderer bug is still there. What that means for
you, and what to do if you meet it anyway, is under "The i686 login crash".

The remaining unknown is the hardware itself: see "At the machine" for the list
of things a VM cannot answer.

## Before you start: what you need in your hand

Five things. Download all of them before you begin, because the target has no
browser and archlinux32 carries none of them.

| What | Where | Needed for |
|---|---|---|
| archlinux32 i686 ISO, 2024.07.10 or later | `mirror.archlinux32.org/archisos/` | the install medium |
| `fontconfig-2.18.3-2-i686.pkg.tar.zst` | [overrides-i686-20260831](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/overrides-i686-20260831) | **mandatory**, the text stack |
| `neatvnc-0.8.1-4-i686.pkg.tar.zst` | the same release | optional, `omarchy-remote-view` |
| `omarchy32cpu-stack-i686-20260902.tar.zst` | the same release | **mandatory**, the compositor and the shell |
| this repository | `git clone https://github.com/cederikdotcom/omarchy32cpu` | `/usr/share/omarchy` |

The stack tarball is the compositor (this fork's Hyprland and aquamarine, with
the pixman renderer), the Quickshell desktop, and the fourteen dependencies
that archlinux32 has either missing or far too old. It is a prebuilt i686 tree
because building it is not a step, it is a project: seventeen components,
`cmake` and `meson` from pip, and a patch to wayland-protocols. On a 2006 Core
Duo that is a day of compiling. Build it yourself only if you have a reason to;
see "Rebuilding the stack" at the end.

**Take `neatvnc-0.8.1-4`, not `-3`.** The `-3` asset cannot be installed at
all: it was built without `provides=(libneatvnc.so)`, so pacman refuses it with
`installing neatvnc (0.8.1-3) breaks dependency 'libneatvnc.so=0-32' required
by wayvnc`.

## Scope

- Target: MacBook1,1 (early 2006 Core Duo, A1181, EMC 2092) on archlinux32
  i686. 2 GB RAM cap; max it (2x1 GB).
- Omarchy Lite: no preinstalled applications. The core is the 80-package list
  in `install/omarchy-base.packages`, which pulls about 464 packages in total.

## Prepare install media

1. Write the archlinux32 ISO to USB.
2. If the Apple EFI does not boot it, add a 32-bit GRUB to the USB EFI
   partition as `EFI/BOOT/BOOTIA32.EFI` (`grub-mkstandalone -O i386-efi`), or
   burn a CD and boot via CSM (hold Alt, pick the "Windows" entry).

## Install

Run every command below in the live ISO environment unless it says otherwise.
`/mnt` is the target root throughout.

### 1. Network and disk

Boot the media and connect wifi. ath5k is in-tree, so `iwctl` sees the card.

Partition GPT: a 512 MB ESP (FAT32) and an ext4 root. Mount root at `/mnt` and
the ESP at `/mnt/boot`. FDE is opt-in; if you use it, lower the argon2id cost
first, because the default is tuned for a machine thirty times faster.

### 2. Pacman on the installer

The ISO already runs `Architecture = i686` against archlinux32 with a populated
keyring, so there is nothing to do here on the real install. Two notes for
anyone rehearsing from a different environment:

- If you bootstrap from a 64-bit host, the host pacman has no archlinux32 keys.
  Use `SigLevel = Never` for the `pacstrap` only, and initialise the target's
  own keyring in step 4. Every transaction after that is signature-checked.
- `pacstrap -M` does not copy a mirrorlist into the target. Step 4 writes one.

### 3. pacstrap the core

```bash
pacstrap -c -G -M /mnt base linux linux-firmware \
  archlinux32-keyring libxml2-legacy icu75 \
  $(grep -v '^#' /path/to/omarchy32cpu/install/omarchy-base.packages | grep -v '^$')
```

Three packages are not in the core list and are not optional on i686:

- **`archlinux32-keyring`** for step 4.
- **`libxml2-legacy`**, which provides `libxml2.so.2`. The repo's `libxml2` is
  2.15 with soname `.16`, and both `Hyprland` and `libhyprgraphics` link
  `.so.2`. Without it the compositor does not start, and every pacman
  transaction ends with `gtk-query-immodules-3.0: libxml2.so.2: cannot open
  shared object file`.
- **`icu75`**, because archlinux32's `qt6-base` 6.7.2 was built against ICU 75
  and links `libicui18n.so.75` while the repo's `icu` is 78. Without it
  Quickshell will not start. archlinux32 carries the legacy package, so this
  needs no override of ours.

`mkinitcpio` arrives as a dependency of `linux`, and it runs during this
`pacstrap`. It **fails** here, with `==> ERROR: file not found:
'/etc/vconsole.conf'` and `==> WARNING: errors were encountered during the
build`. That is expected: there is no `/etc` yet. Step 5 writes the file and
rebuilds the image. Do not skip that, or you boot to nothing.

### 4. The target keyring, pacman.conf and mirrorlist

```bash
sed -i 's/^#\?Architecture *=.*/Architecture = i686/' /mnt/etc/pacman.conf
printf 'Server = https://mirror.archlinux32.org/i686/$repo\n' > /mnt/etc/pacman.d/mirrorlist

arch-chroot /mnt pacman-key --init
arch-chroot /mnt pacman-key --populate archlinux32
arch-chroot /mnt pacman-key --lsign-key 80EC18799E8BCD375C6E64ABE4D41569196B1160
```

The default `Architecture = auto` misdetects in a chroot, which is why it is
pinned. The `lsign` is the TasosSah packaging key: some archlinux32 packages
are signed by a key the shipped keyring only trusts marginally, and installs
abort on "marginal trust" until it is locally signed. Signing it is harmless if
you never hit the problem.

Verify before moving on:

```bash
arch-chroot /mnt pacman -Sy --noconfirm libxml2-legacy   # any package will do
```

Note for later: **step 8 overwrites `/etc/pacman.conf` and the mirrorlist** with
the fork's own copies (`default/pacman/pacman-stable.conf`, which pins
`Architecture = i686`, the archlinux32 mirror and an `IgnorePkg` line). Any
hand edit you make to pacman.conf before step 8 is lost. Make yours afterwards,
or change the shipped file in the repo.

### 5. System files

```bash
genfstab -U /mnt > /mnt/etc/fstab
echo 'en_US.UTF-8 UTF-8' > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo 'LANG=en_US.UTF-8' > /mnt/etc/locale.conf
echo 'KEYMAP=us' > /mnt/etc/vconsole.conf
echo myhostname > /mnt/etc/hostname
printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n' > /mnt/etc/hosts
ln -sf /usr/share/zoneinfo/<Region>/<City> /mnt/etc/localtime
arch-chroot /mnt passwd
```

`/etc/vconsole.conf` is not optional and it is not only for the console:
`omarchy-hyprland-launch` reads the keyboard layout out of it and maps it onto
`XKB_DEFAULT_*`, so what you put there is what the desktop gets.

Then the initramfs. `pacstrap` already tried and failed to build it, so this is
not optional:

```bash
# Real MacBook1,1 hardware. i915 is the GMA 950 KMS driver.
sed -i 's/^MODULES=.*/MODULES=(ahci sd_mod i915)/' /mnt/etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev modconf kms keyboard keymap consolefont block filesystems fsck)/' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P
```

In a QEMU rehearsal use `bochs` in place of `i915`; the emulated adapter is
bochs-drm and `i915` finds nothing. Keep `kms` in HOOKS on the Mac so the
console comes up on the panel early. It costs image size, because the hook
drags in every GPU firmware blob the kernel might want: about 180 MB against
27 MB without it. That is disk, not RAM, and on real hardware the early KMS is
worth it.

### 6. Override packages

Install these **after** the core list, never before. `fontconfig` is in
`install/omarchy-base.packages`, so `pacstrap` and any later `pacman -S
--needed` of the core list put the repo's 2:2.14.1 back over the override.

```bash
arch-chroot /mnt bash -c 'cd /root &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/fontconfig-2.18.3-2-i686.pkg.tar.zst &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/neatvnc-0.8.1-4-i686.pkg.tar.zst'
arch-chroot /mnt pacman -U --noconfirm /root/fontconfig-2.18.3-2-i686.pkg.tar.zst
arch-chroot /mnt pacman -U --noconfirm /root/neatvnc-0.8.1-4-i686.pkg.tar.zst
arch-chroot /mnt pacman -Q fontconfig neatvnc      # want 2:2.18.3-2 and 0.8.1-4
```

**Download first, install from the file.** `pacman -U <https URL>` does not
work on a system with a populated keyring: pacman fetches a detached `.sig`
beside every remote package, GitHub answers 404, and the whole transaction
fails with `error: failed retrieving file
'fontconfig-2.18.3-2-i686.pkg.tar.zst.sig' from github.com`. A local file goes
through `LocalFileSigLevel = Optional` and installs. This is the single most
common way to end up with a machine that boots and has no working text stack.

What each override is for:

- **fontconfig 2:2.18.3-2, mandatory.** archlinux32 ships 2:2.14.1 while its
  pango 1:1.57.1 needs >= 2.16. Without it the compositor itself has undefined
  symbols (`FcConfigSetDefaultSubstitute`, through `libpangoft2` and
  `libpangocairo`) and the session dies at startup.
- **neatvnc 0.8.1-4**, only for `omarchy-remote-view`. archlinux32 ships wayvnc
  0.8.0 against neatvnc 0.5.4, and wayvnc then dies with `undefined symbol:
  nvnc_client_get_auth_username`. Install `wayvnc` first (it is in the core
  list) and the override second: `pacman -S wayvnc` would pull the repo's
  0.5.4 back and clobber it.

Both carry a higher version than the repo package, so a later `pacman -Syu`
will not pull them back down.

### 7. The desktop stack

`install/omarchy-base.packages` deliberately carries neither Hyprland nor
Quickshell. The session needs this fork's compositor build, which adds the
pixman (CPU) renderer, and Quickshell is in neither official Arch nor
archlinux32.

```bash
arch-chroot /mnt bash -c 'cd /root &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/omarchy32cpu-stack-i686-20260902.tar.zst &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/overrides-i686-20260831/omarchy32cpu-stack-i686-20260902.tar.zst.sha256 &&
  sha256sum -c omarchy32cpu-stack-i686-20260902.tar.zst.sha256'
tar -C /mnt --zstd -xf /mnt/root/omarchy32cpu-stack-i686-20260902.tar.zst
arch-chroot /mnt ldconfig
```

What lands where:

- `/usr/local/bin` and `/usr/local/lib`: `Hyprland`, `start-hyprland`,
  `hyprctl`, `libaquamarine`, the five `hypr*` libraries, lua 5.5, glslang,
  libei, libdisplay-info, libspng.
- `/usr/bin/quickshell` and `/usr/lib/qt6/qml`: the shell, beside the distro
  Qt. Configured with `-DCMAKE_INSTALL_PREFIX=/usr` so the QML modules land
  where archlinux32's Qt looks for them.
- `/usr/lib/libinput.so.10.13.0`: **libinput 1.29, over the repo's 1.27.**
  Hyprland 0.56 needs the newer API and archlinux32 has not got it. This is the
  one file in the tarball that shadows a package.
- `/etc/ld.so.conf.d/00-usrlocal.conf`, because archlinux32's `ld.so` does not
  search `/usr/local/lib` by default. Run `ldconfig` after extracting or
  nothing links.

Check it before you go on:

```bash
arch-chroot /mnt ldd -r /usr/local/bin/Hyprland | grep -c 'undefined symbol'   # want 0
arch-chroot /mnt ldd -r /usr/bin/quickshell    | grep -c 'undefined symbol'   # want 0
arch-chroot /mnt quickshell --version    # Quickshell 0.3.1 ... distributed by omarchy32cpu
```

A non-zero count on `Hyprland` naming `FcConfigSetDefaultSubstitute` means step
6 did not take.

Because the tarball shadows `libinput`, and because Quickshell links private Qt
APIs and dies on an ABI mismatch, the fork's `pacman.conf` (installed in step 8)
carries `IgnorePkg = libinput qt6-base qt6-declarative`. Unpin them only when
you are ready to reinstall the stack.

### 8. The repo, the user, and the system stage

```bash
git clone https://github.com/cederikdotcom/omarchy32cpu /mnt/usr/share/omarchy
arch-chroot /mnt useradd -m -G wheel -s /bin/bash <user>
arch-chroot /mnt passwd <user>
arch-chroot /mnt /usr/share/omarchy/bin/omarchy-apply-system --install-user <user> --first-install
```

`/usr/share/omarchy` is not negotiable: greetd's session command is an absolute
path into it.

`omarchy-apply-system` runs config, hardware detection, the greetd login config
and post-install, and logs to `/var/log/omarchy-install.log`. It takes about
three seconds. The hardware scripts are all guarded and skip themselves on
machines they do not match; the Apple ones will fire on the MacBook.

ufw comes up enforcing deny-incoming, and you **can** add rules here.
`arch-chroot /mnt ufw allow 22/tcp` prints `ERROR: problem running` and exits
1, because it cannot load the rule into the kernel from a chroot, but it does
write the rule to `/etc/ufw/user.rules` and the rule is live after the reboot.
Check `grep 22 /mnt/etc/ufw/user.rules`, not the exit code.

### 9. The user stage

Upstream's omarchy package seeds `/etc/skel`. This fork has no package, so seed
the config by hand:

```bash
arch-chroot /mnt sudo -u <user> bash -c '
  mkdir -p ~/.config
  cp -r /usr/share/omarchy/config/* ~/.config/
  OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH \
    omarchy-provision-user --first-install --force'
```

It ends with `User finalization complete.` A stray `lspci: Unable to load
libkmod resources` on the way is a chroot artefact and harmless.

### 10. Bootloader

```bash
arch-chroot /mnt /usr/share/omarchy/bin/omarchy-refresh-grub
ls -la /mnt/boot/EFI/BOOT/         # want BOOTIA32.EFI
```

On a first run this installs GRUB into the removable fallback path
(`grub-install --target=i386-efi --efi-directory=/boot --removable --no-nvram`),
which needs no efibootmgr and no NVRAM write, then writes `grub.cfg`. A 32-bit
kernel boots natively from the 32-bit Apple EFI; there is no mixed mode. Run it
again after every kernel update.

The command picks `i386-efi` from the GRUB platform modules that are installed,
not from `uname -m`, so it also does the right thing when you chroot into an
i686 root from a 64-bit installer. Override with `OMARCHY_GRUB_TARGET` if you
ever need to.

Optional, for Apple's own boot picker: `grub-mkstandalone -O i386-efi -o
/boot/System/Library/CoreServices/boot.efi` on a blessed HFS+ helper partition.

### 11. Reboot

greetd's `initial_session` autologs `<user>` straight into the session through
`/usr/share/omarchy/bin/omarchy-hyprland-launch`, which sets
`HYPRLAND_RENDERER=pixman`, `AQ_FORCE_ALLOCATOR=dumb` and
`QT_QUICK_BACKEND=software`.

If you reach the desktop, prove the renderer rather than trusting the picture:

```bash
hyprctl systeminfo | grep -iE 'renderer|backend'   # Renderer: pixman (software)
```

If you reach the tuigreet greeter instead, read the next section.

## The i686 login crash

Read this even though the desktop now comes up. The bug behind it is still in
the renderer, and if you meet it on the hardware this section is what turns a
dead login into a useful report.

On the rehearsal image, before the fix, it fired on every attempt: nine greetd
logins and eight hand-started sessions, all of them.

What happens: the compositor starts, prints its banner, and about three seconds
later glibc aborts it with

```
malloc(): invalid size (unsorted)
```

`start-hyprland` then restarts it with `--safe-mode`, and the safe-mode dialog
is a second, unrelated crash: `CCompositor::openSafeModeBox` calls
`CAsyncDialogBox::open`, which segfaults because `hyprland-dialog` (from
`hyprland-qtutils`, absent on archlinux32) is not installed. So one render bug
becomes a login loop, and greetd drops you on tuigreet.

It is heap corruption, so glibc reports it at whatever allocates next and the
reported site moves between runs. A core taken from the VM puts the corruption
on the DRM page-flip path:

```
CDRMBackend::dispatchEvents -> handlePageFlip -> CMonitorFrameScheduler::onFrame
  -> IHyprRenderer::renderMonitor -> CHyprPixmanRenderer::endRender
  -> CRenderPass::render -> CRenderPass::simplify
  -> Hyprutils::Math::CRegion::subtract -> pixman_region32_subtract -> realloc
```

What the 2026-09-02 rehearsal added, and this is the useful part. Every figure
below is the same binary, hand-started against the same `/dev/dri/card0`
through seatd, on a quiet machine, differing only in the config file:

| config | survived |
|---|---|
| minimal `hyprland-flat.conf` | **12 / 12** |
| `~/.config/hypr/hyprland.lua`, the fork's own | **0 / 5** |
| `helpers` + `envs` + `looknfeel` | **6 / 6** |
| the same plus `default.hypr.input` | **0 / 6** |
| the same plus `default.hypr.qconsole` | 5 / 6 |
| the same plus the pointer and touchpad block of `input.lua` | 3 / 4 |
| the same plus its DPMS block | 4 / 4 |
| the same plus its window rules | 4 / 4 |
| the same plus its `kb_options` alone | 4 / 4 |
| the same plus its **keyboard block** | **0 / 4** |
| the keyboard block split: `kb_layout`/`variant`/`model`/`rules` | 4 / 4 |
| the keyboard block split: `repeat_rate` + `repeat_delay` | 4 / 4 |
| the keyboard block split: **`numlock_by_default = true`** | **0 / 4** |
| the whole fork config with `numlock_by_default = false` | **4 / 5** |

One line. Turning numlock on at startup makes Hyprland build a second xkb state
for every keyboard it opens, and on i686 that path corrupts the heap. The abort
then lands wherever the next big allocation is, usually a pixman region
`realloc` on the page-flip path, which is why every backtrace pointed at the
renderer and none of them pointed here.

`default/hypr/input.lua` now ships `numlock_by_default = false`. The cost is a
keyboard that starts with numlock off, and the MacBook1,1 has no numpad.

With the line off, **five cold boots out of five put the desktop on screen**,
greetd's own autologin, no retries, nothing by hand.

Two things this does not mean. It does not mean the renderer is fixed: the
hand-start harness still lost about one start in five, visible in the 3/4, 5/6
and 4/5 rows above, so **a login that lands on the greeter is possible**. Log in
again. And it does not mean the trigger is understood: one config path reaches
it every time and has been closed, that is all.

If you turn `numlock_by_default` back on, this comes back. Do not.

**If the compositor still dies every time on the hardware**, fall back to a
reduced config. That is not expected any more, but it is the fastest way to
find out whether you are looking at this bug or at something the GMA 950 is
doing. Write this as `~/.config/hypr/hyprland-flat.conf`:

```
monitor = , preferred, auto, 1
animations { enabled = false }
decoration { rounding = 0
  blur { enabled = false }
  shadow { enabled = false } }
misc { disable_hyprland_logo = true
  disable_splash_rendering = true
  force_default_wallpaper = 0 }
general { border_size = 2 }
```

then start the session with it. At the tuigreet greeter, `F2` changes the
command; make it

```
systemd-cat -t omarchy-session env HYPRLAND_RENDERER=pixman AQ_FORCE_ALLOCATOR=dumb QT_QUICK_BACKEND=software Hyprland --config /home/<user>/hyprland-flat.conf
```

and start the shell yourself once the compositor is up
(`omarchy-launch-shell`). You lose the keybindings, the window rules and the
input tuning; you keep the compositor, the shell, the bar, the tray and the
theme. This config survived 12 starts out of 12 in the rehearsal, so it is a
useful control: if it dies on the MacBook too, the problem is the hardware and
not this bug, and that is worth reporting on its own.

Then reintroduce `~/.config/hypr/hyprland.lua` one `require` at a time. The
table above is where to start, and a report naming the line that brought the
crash back is worth more than any other single thing you could send.

## At the machine

Everything below is hardware, and none of it can be answered in a VM. Work down
the list and write down the answer even when it is "yes, fine". "If it fails:
what to capture" is the next section, and it applies to every item here.

### 1. Does the GMA 950 scan out at all (the big one)

This is the single largest unknown in the whole port. The pixman renderer asks
aquamarine for **DRM dumb buffers** (`AQ_FORCE_ALLOCATOR=dumb`) and writes
pixels into them with the CPU. That needs the i915 KMS driver to accept a dumb
buffer as a scanout framebuffer on an i945GM. It is a plain, old, well
supported path, and it has never been run.

```bash
dmesg | grep -i i915          # want "i915 ... registered", no "failed to..."
ls -l /dev/dri/               # want card0 and renderD128
hyprctl monitors              # want the panel at 1280x800
```

If the compositor exits complaining about GLES 3.0, the installed Hyprland is a
stock build and not the fork's: only the fork's branches carry the pixman
renderer. If you get a black screen with a live compositor, check
`HYPRLAND_RENDERER=pixman` and `AQ_FORCE_ALLOCATOR=dumb` actually reached it,
then `dmesg | grep -i drm`.

The documented fallback is i3 on X11 with the modesetting driver. Say so in the
report if you needed it.

### 2. Wifi (ath5k)

The AR5BXB63 is in-tree. `ip link` should show a `wl*` device without any
firmware install. Then `nmtui`.

Known issue: powersave makes ath5k drop the link.
`install/hardware/apple/fix-a1181.sh` writes the NetworkManager override that
turns it off. Confirm the file is there and the link survives ten idle minutes.

### 3. Fan control (mbpfan)

**Not installed, and it cannot be**: mbpfan is not in the archlinux32 repos and
the fork has no package for it yet. `fix-a1181.sh` skips it. So the MacBook runs
on the firmware's own fan curve, which on this model is lazy.

Watch the temperature under load before you trust it with a long build:

```bash
sensors            # applesmc; lm_sensors arrives as a mesa dependency
```

If it climbs past 85 C on an ordinary workload, say so. A fan daemon then goes
on the "must package" list rather than the "nice to have" one.

### 4. iSight webcam

**Expected absent.** It needs a firmware blob Apple does not allow us to
redistribute, and `isight-firmware-tools` is not in archlinux32 either. `ls
/dev/video*` will be empty. That is not a bug. If you want it, extract
`AppleUSBVideoSupport` from a macOS install with `ift-extract` on another
machine and reload `uvcvideo`.

### 5. Brightness keys

`brightnessctl` is in the core.

```bash
brightnessctl -l                 # is there a backlight device at all?
brightnessctl set 50%
```

Then the `XF86MonBrightnessUp` / `Down` keys through the compositor. On this
generation the backlight is driven through the `acpi_video` or the
`gmux`/`apple_bl` path and either can be missing. Report which device name you
got, or that there was none.

### 6. Suspend and resume

Close the lid, or `systemctl suspend`. This is where an old Intel graphics
stack usually breaks: the machine sleeps and comes back with a dead panel
because the KMS driver failed to restore the mode.

```bash
systemctl suspend
# then, after resume:
journalctl -b -k | grep -iE 'i915|drm' | tail -40
```

Report whether the display, the keyboard, the trackpad and wifi each came back.

### 7. Battery

```bash
upower -i $(upower -e | grep BAT)
```

A 2006 battery is very likely dead. Say what the bar shows either way.

### 8. Audio

pipewire on archlinux32 is 0.3.65, which is old. Quickshell's pipewire service
is compiled against it after a two-line patch, so the audio panel, the volume
OSD and the media widgets are present rather than absent. **Whether the service
actually talks to a 0.3.65 daemon has never been tested against a running
daemon**, and this is the best chance to find out.

```bash
pactl info
# play something, then check the bar's volume widget and the OSD
```

## If it fails: what to capture

A failed attempt is still a useful report if you bring these back. Capture what
you can; partial is fine.

**Start with the session's own output.** Hyprland's runtime log file is empty
by default (`debug:disable_logs`) and greetd sends the session's stdout
nowhere, so the fork's greetd config runs both sessions, the autologin one and
the one you get from tuigreet, through `systemd-cat`:

```bash
journalctl -b -t omarchy-session --no-pager | tail -200
```

That is where the compositor's banner, `malloc(): invalid size (unsorted)` and
the path of the crash report all appear. If this comes back empty, your
`/etc/greetd/config.toml` predates the change; add
`systemd-cat -t omarchy-session ` in front of both `command =` lines.

The rest, in order of usefulness:

```bash
# The compositor's own crash report, if it wrote one
ls -la ~/.cache/hyprland/
cat ~/.cache/hyprland/hyprlandCrashReport*.txt

# Where the boot stopped
journalctl -b -u greetd --no-pager | tail -60
systemctl --failed
systemctl --user --failed

# The shell
journalctl -b -t omarchy-shell --no-pager | tail -60

# Graphics, verbatim. This is the field we most need.
lspci -nn | grep -i vga
ls -l /dev/dri/
dmesg | grep -iE 'drm|i915' | tail -40

# The session environment and the renderer it chose
env | grep -E 'HYPRLAND_|AQ_|QT_QUICK|XDG_|WAYLAND'
hyprctl systeminfo | grep -iE 'renderer|backend|GPU'

# Memory, because the whole point is 2 GB
free -m
swapon --show          # want a 1.9 GB /dev/zram0 at priority 100

# What actually got installed
pacman -Q fontconfig neatvnc icu75 libxml2-legacy qt6-base
quickshell --version
ldd -r /usr/local/bin/Hyprland | grep 'undefined symbol'
```

Two crash reports of zero bytes plus one full one is the normal shape of the
login crash: the abort kills the process before the first report is written, and
the full one is the safe-mode dialog segfault, which is a consequence and not
the cause. Send all of them anyway.

File it with the [hardware report
form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml).

## Memory: the 2 GB question is answered

Measured in the i686 VM held at 2048 MB, the MacBook's size, at 1280x800:

| | Quickshell RSS | system in use | left for apps |
|---|---|---|---|
| greeter, no session | - | 314 MB | 1641 MB |
| desktop idle, default wallpaper | 210 MB | 489 MB | 1466 MB |
| plus a foot terminal | 210 MB | 503 MB | 1452 MB |
| largest shipped wallpaper | 272 MB | 563 MB | 1392 MB |
| smallest shipped wallpaper | 144 MB | 439 MB | 1516 MB |

The compositor is 61 MB of that, Xwayland 45 MB and foot 16 MB. Peak `VmHWM`
across a wallpaper swap is 492 MB, because the outgoing, incoming and base
copies are resident together during a crossfade. A 1.3 GB workload, which is a
browser with a few tabs, ran on top of the idle desktop with 260 MB still free
and never touched swap.

The shell is **smaller on i686 than on x86_64**: 32-bit pointers take the fixed
part from about 190 MB down to about 135 MB. The rest is the wallpaper, held at
its full stored resolution:

    RSS ~= 135 MB + the decoded size of the current background

The backgrounds under `themes/` decode to between 6 MB (1536x1024) and 138 MB
(10456x3455), median 32 MB, and the default theme's default background is 78 MB
(6016x3384). On a 1280x800 panel none of that resolution is visible, so **the
wallpaper is the lever if you want the memory back**: the smallest shipped
background saves 66 MB against the default and 128 MB against the largest.

zram comes up on its own (`install/config/memory-tuning.sh`) as a 1.9 GB device
at priority 100. archlinux32's i686 kernel offers only `lzo-rle` and `lzo` for
zram, so the `zstd` the config asks for silently becomes `lzo-rle`: expect about
2:1 rather than 3:1. It made no difference to any measurement above, because
nothing ever swapped.

Do not drop `libvips`. Without it the image picker cannot build thumbnails and
falls back to the full-resolution originals, which is how a single theme becomes
several hundred MB.

None of this has been measured on the real MacBook. The VM has no GMA 950 and a
Core Duo is slower than the emulated one, so the timings will differ even where
the megabytes do not.

## Rebuilding the stack

Only if you have a reason. Build it in an archlinux32 i686 chroot on a fast
machine, not on the MacBook.

`cmake` 4.x and `meson` 1.12 come from pip (`pip install
--break-system-packages cmake meson jinja2`); the repo versions are too old.
Everything installs to `/usr/local` except libinput.

Source-built, because archlinux32 has them missing or far too old:

| Component | Version | Why |
|---|---|---|
| Hyprland (fork) | `pixman-renderer`, base v0.56.2 | the pixman renderer exists nowhere else |
| aquamarine (fork) | `cpu-backend`, base v0.15.0 | the CPU backend and dumb allocator |
| hyprwayland-scanner | v0.4.6 | not packaged |
| hyprutils | v0.14.1 | repo has 0.2.6 |
| hyprlang | v0.6.8 | repo has 0.5.2 |
| hyprcursor | v0.1.13 | not packaged |
| hyprgraphics | v0.5.1 | not packaged |
| hyprland-protocols | v0.7.0 | not packaged |
| hyprwire | v0.3.1 | new in Hyprland 0.56, easy to miss |
| wayland-protocols | 1.49 | repo has 1.48; needs the `--strict` drop, see `patches32/` |
| libinput | 1.29.0 | repo has 1.27; **install with `--prefix=/usr`** or the link resolves against the old one |
| libei | 1.5.0 | not packaged; needs pip `jinja2` |
| libdisplay-info | 0.2.0 | repo has 0.1.1; aquamarine needs the 0.2 API |
| glslang | 15.4.0 | repo has 11.13.0, whose C API predates `glslang_input_t.callbacks` |
| libspng | 0.7.4 | not packaged, pulled in by hyprgraphics |
| lua | 5.5.0 | not packaged; Hyprland 0.56 requires `lua>=5.5 lua<5.6` |

Chroot quirks that are not patches and have to be re-applied on a rebuild:
relax the `gobject-2.0 >= 2.82` and `harfbuzz >= 8.4.0` floors in
archlinux32's `pango*.pc` (the repo ships glib2 2.80 and harfbuzz 7.1 and it
works at run time); install `libxml2-legacy`; add `/usr/local/lib` to
`ld.so.conf.d` and run `ldconfig`; generate the `en_US.UTF-8` locale, because
foot aborts on a failed `setlocale()`.

Quickshell 0.3.1 (tag `v0.3.1`), with the two-line pipewire 0.3.65 patch:

```bash
git clone --depth 1 --branch v0.3.1 \
  https://github.com/quickshell-mirror/quickshell /opt/quickshell
cd /opt/quickshell
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

Both `sed` lines are no-ops at run time. `.bound_props` does not exist in
0.3.65's `pw_core_events`, and the listener announces `PW_VERSION_CORE_EVENTS`,
which is 0 there, so the server never emits that event.
`PW_KEY_NODE_DESCRIPTION` is the same string as the missing
`SPA_KEY_NODE_DESCRIPTION`, `"node.description"`. Neither edit changes
behaviour on a newer pipewire either, so both arches share one recipe.

`-DCRASH_HANDLER=OFF` stays: the handler needs `cpptrace`, which archlinux32
does not carry at all.

Rebuilding the two override packages: take the Arch PKGBUILD for the package
and run `makepkg -A --nocheck --skippgpcheck -d` in an i686 chroot. fontconfig
needs `-Ddoc=disabled` (the docbook DTDs are missing on archlinux32) and meson
>= 1.11 from pip. neatvnc needs `provides=(libneatvnc.so)` in the PKGBUILD, or
pacman refuses the install as breaking wayvnc's `libneatvnc.so=0-32`
dependency.

## Common operations

- Refresh boot entries after a kernel update: `omarchy-refresh-grub`.
- Theme switch: `omarchy-theme-set <name>` (renders the compositor template and
  hands the palette to the running shell over IPC).
- Remote view: `omarchy-remote-view on` (or menu: Trigger > Toggle > Remote
  View) serves the session on 127.0.0.1:5901; from another machine `ssh -L
  5901:127.0.0.1:5901 <user>@<host>`, then VNC to localhost:5901.

## Troubleshooting

- **The session dies with a fontconfig symbol error, or `ldd -r` on Hyprland
  names `FcConfigSetDefaultSubstitute`:** the fontconfig override is missing, or
  a later `pacman -S` of the core package list put the repo's 2:2.14.1 back over
  it. Reinstall it and check with `pacman -Q fontconfig`.
- **`pacman -U` of an override fails on a missing `.sig`:** you passed a URL.
  Download the file and install the file. See step 6.
- **`neatvnc ... breaks dependency 'libneatvnc.so=0-32'`:** you have the
  `0.8.1-3` asset. Take `0.8.1-4`.
- **Hyprland does not start and the log ends with dconf warnings** (`failed to
  commit changes to dconf: Could not connect`): the compositor is writing the
  cursor theme into gsettings, and archlinux32's `dconf` is built against a
  newer glib2 than the repo ships, so `dconf-service` cannot start (`undefined
  symbol: g_variant_builder_init_static`). The fork turns that write off in
  `default/hypr/looknfeel.lua` with `cursor.sync_gsettings_theme = false`. If
  you are running an older config, set it yourself.
- **Hyprland exits complaining about GLES 3.0:** the installed Hyprland or
  aquamarine is a stock build, not the fork's.
- **`grub-install: error: /usr/lib/grub/x86_64-efi/modinfo.sh doesn't exist`:**
  an old `omarchy-refresh-grub` that chose its target from `uname -m`. Update
  the repo, or run `OMARCHY_GRUB_TARGET=i386-efi omarchy-refresh-grub`.
- **Firmware boots to a folder-with-question-mark:** the EFI entry is lost.
  Boot the USB, chroot, rerun `grub-install --removable`, or bless the boot.efi
  helper from macOS.
- **Wifi drops on ath5k:** disable NetworkManager wifi powersave (the
  `fix-a1181.sh` override).
- **Screen sharing fails in calls:** permanent under the pixman renderer. Not a
  bug.
- **The screen goes flat and blank after five minutes:** that is the shell's
  own idle lock, not a crash. Press a key. For an unattended run turn it off
  with `omarchy-toggle-idle stay-awake` rather than killing the locker; killing
  a locker that holds the session lock leaves Hyprland on its "crashed
  lockscreen" page, which reads as a renderer failure. Clear that with
  `hyprctl eval "hl.clear_crashed_lockscreen()"`.
- **System thrashes:** check `swapon --show`; you want a 1.9 GB `/dev/zram0` at
  priority 100. On 2 GB the desktop leaves about 1.45 GB free, so one heavy app
  at a time is comfortable and two is where zram starts earning its keep.
