# Runbook: install Omarchy CPU (32-bit) on the MacBook1,1

Status: **rehearsed from scratch on 2026-09-02; the physical MacBook1,1 reached
the ArchLinux32 live shell on 2026-09-03; installation is paused before writing
the internal disk.** A fresh image was built by following the steps below in order, then
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

The desktop and installed-system claims still come from the VM. What is now
proven on the physical MacBook is the bootstrap through rEFIt, a small external
i386-EFI GRUB, an i686 kernel and initramfs staged on Macintosh HD, and the USB
live filesystem, ending at `root@archiso`. The installation, internal GRUB and
desktop have not yet met the i945GM. See "At the machine: what to type, and what
to look at" for those remaining checks, and "Rollback and recovery" before
writing the disk.

**One thing that rehearsal does not cover, and it is new.** The i686 rehearsal was run at commit `0faf8483`, before this integration landed. At that commit every shipped background was a `.jpg` or `.png` and `qt6-imageformats` was not in the package list. On the branch this runbook pins, **79 of the 92 backgrounds are `.webp`** and the Qt WebP plugin is what decodes them. So the i686 desktop has never once drawn a WebP wallpaper: the whole image path - the wallpaper, the picker's thumbnails, the memory the decoded image costs - is proven on x86_64 only. Treat it as one of the hardware unknowns, alongside the GMA 950. Item 2 of "At the machine" is where to test it.

## What this runbook is pinned to

This file describes one exact tree and one exact set of downloads. Take anything else and the failure modes below may not apply to what you are looking at.

### The repository

The integration branch was merged and removed. Use `main`; the hardware session
started at `de1cf7a3`. The last commit in that tree that changes anything that
**runs** is `2f1378cc` ("Draw image picker thumbnails on the software backend").
Every commit between it and `de1cf7a3` is documentation, so that checkout
executes exactly the code the 2026-09-02 runtime gate validated.

The pin is that commit rather than the branch tip because a file cannot name the commit that contains it. Do not take the sentence on trust; the difference is checkable in three commands, and the first of them is something your report needs anyway:

```bash
git -C /usr/share/omarchy rev-parse HEAD                              # put this in the report
git -C /usr/share/omarchy merge-base --is-ancestor 2f1378cc HEAD && echo "runtime pin present"
git -C /usr/share/omarchy diff --stat 2f1378cc HEAD                   # want: paths under docs/ only
```

If the third command names a path outside `docs/`, you are not on the validated runtime tree and the pin is stale. Say so in the report rather than working around it.

Run those as **root**, or expect `detected dubious ownership in repository at '/usr/share/omarchy'`. The clone is made by root and git refuses a repository owned by somebody else. As your own user, either `sudo` them or tell git once that this one is fine:

```bash
git config --global --add safe.directory /usr/share/omarchy
```

### The downloads

Every checksum here was taken on **2026-09-02** by fetching the file fresh from the public URL in its own row and hashing what arrived. They are what a correct download looks like; a mismatch means the asset moved, the mirror is serving something else, or the transfer was damaged. In all three cases stop.

| File | From | sha256 |
|---|---|---|
| `archlinux32-2024.07.10-i686.iso` | `https://mirror.archlinux32.org/archisos/` | `5f16c0f006a096c62dedc7d33d24d4e7721e07d7e26b3be902bef77c8da3482b` |
| `fontconfig-2.18.3-2-i686.pkg.tar.zst` | [`i686-20260902`](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/i686-20260902) | `b2a55efe494658fd1ed04ec2d324d5d574f9dfb3e969b56d50912dca9050919f` |
| `neatvnc-0.8.1-4-i686.pkg.tar.zst` | the same release | `1c6426f0e745314d5a912f83fc94035feb564553ee2dc956ff2e033f97515f56` |
| `omarchy32cpu-stack-i686-20260902.tar.zst` | the same release | `076898faf348827de2916dbed0bef2d42428daea83f1786e055c84c37267f20f` |

Three things worth knowing about that table.

- **The two `.sha256` sidecars on the release agree with it.** `omarchy32cpu-stack-i686-20260902.tar.zst.sha256` and `neatvnc-0.8.1-4-i686.pkg.tar.zst.sha256` were downloaded and run through `sha256sum -c`: both pass. So for those two files the sidecar is a genuine second copy of the value, not a decoration.
- **`fontconfig-2.18.3-2-i686.pkg.tar.zst` has no sidecar.** The release does not publish one. The value in the table is the only pin that file has, so compare it by hand (step 6 shows how). This is the one download where a silent replacement would otherwise go unnoticed, and it is also the one that is mandatory.
- **The ISO is cross-checked against the mirror's own list.** archlinux32 publishes `sha512sums` beside the ISOs but no sha256. Our sha512 of the same fetch is `cd6d540691600bfd48d05826fbb87e7ac9a5b6ab8621c1c6ad82247a8cdc544f99e2f6491cdc4c5cec7b7437ed041cd732fed0add511ba9b1823d312fbefd683`, which is byte for byte the line the mirror's `sha512sums` carries for that filename. So the ISO can be checked two independent ways.

`2024.07.10` is the **newest** i686 ISO archlinux32 has: the `archisos/` directory ends there. This runbook used to say "2024.07.10 or later"; there is no later, and if one appears it is a different medium than the one described here.

What could not be pinned, stated rather than invented: the archlinux32 **repositories** move under you. `pacstrap` in step 3 resolves about 464 packages live, and no checksum here covers them. The versions this runbook depends on are named where they matter (`qt6-base 6.7.2`, `pipewire 0.3.65`, `libinput 1.27`, `fontconfig 2:2.14.1` before the override), and step 8 installs a `pacman.conf` that pins the architecture and the mirror. If archlinux32 moves one of them, the symptom will be in "Troubleshooting" or it will be new, and new is worth a report.

## Before you start: what you need in your hand

Five things. Download all of them before you begin, because the target has no
browser and archlinux32 carries none of them.

| What | Where | Needed for |
|---|---|---|
| `archlinux32-2024.07.10-i686.iso` (the newest there is) | `mirror.archlinux32.org/archisos/` | the install medium |
| `fontconfig-2.18.3-2-i686.pkg.tar.zst` | [i686-20260902](https://github.com/cederikdotcom/omarchy32cpu/releases/tag/i686-20260902) | **mandatory**, the text stack |
| `omarchy32cpu-stack-i686-20260902.tar.zst` (+ `.sha256`) | the same release | **mandatory**, the compositor and the shell |
| `neatvnc-0.8.1-4-i686.pkg.tar.zst` | the same release | optional, `omarchy-remote-view` |
| this repository, `main` (hardware-session baseline `de1cf7a3`) | `git clone https://github.com/cederikdotcom/omarchy32cpu` | `/usr/share/omarchy` |

Check every one of them against "The downloads" above before you carry them to the MacBook. Doing it on the machine you downloaded them with costs nothing; doing it after a failed install costs an afternoon.

The stack tarball is the compositor (this fork's Hyprland and aquamarine, with
the pixman renderer), the Quickshell desktop, and the fourteen dependencies
that archlinux32 has either missing or far too old. It is a prebuilt i686 tree
because building it is not a step, it is a project: seventeen components,
`cmake` and `meson` from pip, and a patch to wayland-protocols. On a 2006 Core
Duo that is a day of compiling. Build it yourself only if you have a reason to;
see "Rebuilding the stack" at the end.

**Take everything from `i686-20260902`.** The older
`overrides-i686-20260831` release is superseded and still carries a
`neatvnc-0.8.1-3` that cannot be installed at all: it was built without
`provides=(libneatvnc.so)`, so pacman refuses it with `installing neatvnc
(0.8.1-3) breaks dependency 'libneatvnc.so=0-32' required by wayvnc`. Its
`fontconfig` is the same file as the new one, so a stale link is only fatal for
neatvnc, and the stack tarball was never on it at all.

## Scope

- Target: MacBook1,1 (early 2006 Core Duo, A1181, EMC 2092) on archlinux32
  i686. 2 GB RAM cap; max it (2x1 GB).
- Omarchy Lite: no preinstalled applications. The core is the 82-package list
  in `install/omarchy-base.packages`, which pulls about 464 packages in total.

## Technology map: what each layer does

These names describe different stages. Reaching one does not imply the next
one works.

| Layer | Technology | Role in this installation | What physical testing proved |
|---|---|---|---|
| Firmware | Apple EFI32 | Runs at power-on and chooses an EFI application | Apple's own Option picker did not expose the Linux USB |
| Firmware boot menu | rEFIt 0.14 on Macintosh HD | Works around the Apple picker and launches external EFI32 programs | It exposed and launched `BOOTIA32.EFI` |
| Bootloader | GNU GRUB for `i386-efi` | Loads the Linux kernel and initramfs | USB discovery was unreliable; HFS+ loading from Macintosh HD worked |
| Kernel bootstrap | `vmlinuz-linux` + `initramfs-linux.img` | Starts Linux and finds the live filesystem | Loaded from `/efi/omarchy`; needed `noefi nomodeset` |
| Live environment | ArchLinux32 `archiso` | Provides the `root@archiso` shell used to install the target | Reached on the physical MacBook1,1 |
| Package installer | `pacstrap`, `pacman`, `arch-chroot` | Builds the permanent ArchLinux32 system on the target partition | Not yet run on physical hardware |
| Omarchy32 payload | This repository plus pinned i686 packages/stack | Adds the CPU-rendered compositor, shell, configuration and hardware fixes | Payload hashes passed; installed desktop remains untested on hardware |
| Installed bootloader | GRUB `i386-efi` at `EFI/BOOT/BOOTIA32.EFI` | Boots the finished internal system without rEFIt | VM-rehearsed only; preserve rEFIt until cold-boot proven |

The verified installation-media chain is therefore:

```text
Apple EFI32
  -> rEFIt on Macintosh HD
  -> small GNU GRUB i386-EFI loader on USB
  -> kernel + initramfs on Macintosh HD
  -> ArchLinux32 live filesystem on USB
  -> pacstrap/chroot installer
  -> Omarchy32 on the internal target partition
```

## Prepare install media

1. Verify the ISO, then write it to USB.

   ```bash
   sha256sum archlinux32-2024.07.10-i686.iso
   # want 5f16c0f006a096c62dedc7d33d24d4e7721e07d7e26b3be902bef77c8da3482b
   ```

   A wrong hash here is worth ten minutes of re-download and nothing else; a wrong hash discovered at step 7 looks like a hardware fault.

2. The physical MacBook1,1 did **not** expose any tested USB layout in Apple's
   Option/Alt picker: raw hybrid ISO, MBR with a separate ESP, GPT with a first
   ESP, and one active MBR FAT32 volume all failed to appear. Install rEFIt 0.14
   on Macintosh HD; it may take two restarts before its menu appears.

3. A normal external `BOOTIA32.EFI` starts under rEFIt, but GRUB on this firmware
   cannot reliably rediscover the USB by UUID or stable `(hdN,msdos1)` name.
   Loading GRUB's native USB modules also produces repeated `Unknown key 0xff
   detected`, and embedding the 9 MB kernel plus 128 MB initramfs makes a 137 MB
   EFI image that rEFIt rejects with `Load Error`.

4. The physically verified bootstrap is split across the disks:

   - copy the live medium's `vmlinuz-linux` and `initramfs-linux.img` to
     `/efi/omarchy/` on Macintosh HD;
   - let rEFIt launch a small external i386-EFI GRUB with HFS/HFS+ support;
   - have GRUB load those two files from Macintosh HD with `noefi nomodeset`;
   - let the initramfs find the ArchLinux32 live filesystem on USB.

   The session's small loader was 421,888 bytes, SHA-256
   `226221a46c4ce362dad488e46ee732db9ea30db10be942386bd2d398c3b4d3ea`,
   and reached `root@archiso`. The USB also carried
   `PREPARE-MACINTOSH-HD.command` to copy and compare the two files. Historical
   details and failed layouts are recorded in issues
   [#20](https://github.com/cederikdotcom/omarchy32cpu/issues/20) and
   [#21](https://github.com/cederikdotcom/omarchy32cpu/issues/21).

## Install

Run every command below in the live ISO environment unless it says otherwise.
`/mnt` is the target root throughout.

### 1. Network and disk

Boot the media and connect Wi-Fi. `ath5k` is in-tree, and `iwctl` connected the
physical machine successfully. On the test LAN, `enp1s0` reported carrier but
DHCP timed out; even a valid static `/22` address could not reach the Deco
gateway. Do not mistake carrier for working Ethernet. That session used Wi-Fi;
see historical issue
[#22](https://github.com/cederikdotcom/omarchy32cpu/issues/22).

With `noefi`, `efivars: fsopen not supported` is expected. The old TPM may also
report error 38 while attempting to supply random data; neither stopped the
live environment. `dmesg -n 1` quiets non-critical console messages during the
install.

Do **not** immediately erase all of the internal disk on this hardware. rEFIt
and `/efi/omarchy` are the only recovery path proven to boot the USB; optical
recovery is unavailable in the physical test. First use macOS Disk Utility to
shrink Macintosh HD, retain a 10-15 GB macOS/rEFIt recovery partition (or the
smallest safe size it permits), and create `OMARCHY-TARGET` in the remaining
space. Reformat only that target as ext4 and keep the existing ESP. Reclaim the
macOS partition only after the installed i386-EFI loader has survived repeated
cold boots. See historical issue
[#23](https://github.com/cederikdotcom/omarchy32cpu/issues/23).

Mount the new ext4 root at `/mnt` and the existing ESP at `/mnt/boot`. FDE is
opt-in; if you use it, lower the argon2id cost first, because the default is
tuned for a machine thirty times faster.

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

Two names in the core list are new in this integration and are load-bearing at run time, so check them rather than assume the `pacstrap` got them:

```bash
arch-chroot /mnt pacman -Q qt6-imageformats libvips
```

`qt6-imageformats` ships `/usr/lib/qt6/plugins/imageformats/libqwebp.so`, and **79 of the 92 backgrounds this repo carries are `.webp`**. Without it the wallpaper is blank and so is the image picker, with no error anywhere. `libvips` is what `bin/omarchy-menu-images` shells out to for the picker's thumbnails. Nothing else pulls either of them in.

archlinux32 has both, checked on 2026-09-02 against `mirror.archlinux32.org/i686/extra/`: `qt6-imageformats 6.7.2-1.1` and `libvips 8.11.3-1.0`. The first matters more than its version number suggests: it is 6.7.2, exactly the `qt6-base` archlinux32 ships, so the plugin and the Qt it loads into agree. If a later `pacman -Syu` ever moves `qt6-imageformats` while `qt6-base` stays pinned by the `IgnorePkg` line of step 8, expect the WebP plugin to stop loading and the wallpaper to go blank; `pacman -Q qt6-base qt6-imageformats` is the first thing to check before blaming the renderer.

`libvips 8.11.3` is old (Arch x86_64 is many releases ahead) and **whether its `vipsthumbnail` reads WebP on archlinux32 has not been tested**. It does not strictly have to: when no thumbnail exists, `shell/plugins/image-picker/list.sh` hands Qt the source file itself, and that fallback was exercised deliberately on x86_64 - Qt's own `libqwebp` decoded the 5000x3000 originals and the tiles rendered. It is slower and it costs memory, which on 2 GB is the part that matters. Say which path you got: `ls ~/.cache/omarchy/image-selector/*.jpg` finding files means `vipsthumbnail` worked, finding none means the fallback carried it.

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
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/i686-20260902/fontconfig-2.18.3-2-i686.pkg.tar.zst &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/i686-20260902/neatvnc-0.8.1-4-i686.pkg.tar.zst'

# Verify BEFORE installing. fontconfig has no .sha256 on the release, so this
# table is its only pin; neatvnc's sidecar is fetched and checked as well.
cat > /mnt/root/overrides.sha256 <<'EOF'
b2a55efe494658fd1ed04ec2d324d5d574f9dfb3e969b56d50912dca9050919f  fontconfig-2.18.3-2-i686.pkg.tar.zst
1c6426f0e745314d5a912f83fc94035feb564553ee2dc956ff2e033f97515f56  neatvnc-0.8.1-4-i686.pkg.tar.zst
EOF
arch-chroot /mnt bash -c 'cd /root && sha256sum -c overrides.sha256'   # want two OK lines

arch-chroot /mnt pacman -U --noconfirm /root/fontconfig-2.18.3-2-i686.pkg.tar.zst
arch-chroot /mnt pacman -U --noconfirm /root/neatvnc-0.8.1-4-i686.pkg.tar.zst
arch-chroot /mnt pacman -Q fontconfig neatvnc      # want 2:2.18.3-2 and 0.8.1-4
```

If either line says `FAILED`, do not install it. Delete the file and fetch it again; if the second fetch gives the same wrong hash, the published asset has changed since 2026-09-02 and that is a blocker to report, not something to work around.

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
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/i686-20260902/omarchy32cpu-stack-i686-20260902.tar.zst &&
  curl -fLO https://github.com/cederikdotcom/omarchy32cpu/releases/download/i686-20260902/omarchy32cpu-stack-i686-20260902.tar.zst.sha256 &&
  sha256sum -c omarchy32cpu-stack-i686-20260902.tar.zst.sha256 &&
  sha256sum omarchy32cpu-stack-i686-20260902.tar.zst'
# The sidecar must say OK, and the printed hash must be
#   076898faf348827de2916dbed0bef2d42428daea83f1786e055c84c37267f20f
# A sidecar that agrees with a replaced tarball would pass the first check and
# fail the second, which is why both are here.
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

# Prove you have the validated runtime tree before anything runs from it.
git -C /mnt/usr/share/omarchy rev-parse HEAD                                   # record this
git -C /mnt/usr/share/omarchy merge-base --is-ancestor 2f1378cc HEAD && echo ok
git -C /mnt/usr/share/omarchy diff --stat 2f1378cc HEAD                        # docs/ only

arch-chroot /mnt useradd -m -G wheel -s /bin/bash <user>
arch-chroot /mnt passwd <user>
arch-chroot /mnt /usr/share/omarchy/bin/omarchy-apply-system --install-user <user> --first-install
```

`/usr/share/omarchy` is not negotiable: greetd's session command is an absolute
path into it.

`main` contains the merged integration and is the checkout used for the hardware
session. Record its exact commit before running the system stage. If it no
longer contains runtime pin `2f1378cc`, or the diff from that pin includes
unexpected runtime paths, stop and reassess rather than silently testing a
different stack.

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

## Rollback and recovery

Read this before you start, not after something breaks. It is short and it is the difference between a failed attempt that produces a report and one that produces a brick.

**Keep the USB in your pocket.** There is no rescue partition and no second machine. The archlinux32 install medium is the recovery medium, and every recovery below starts by booting it. Getting back into a half-installed system is always the same handful of commands (`lsblk` first, to name your own partitions rather than mine):

```bash
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME
mount /dev/sda2 /mnt          # your ext4 root
mount /dev/sda1 /mnt/boot     # your 512 MB ESP
arch-chroot /mnt
```

**Nothing here is precious.** The install has no user data in it. When a step has gone sideways in a way you cannot name, wiping the root partition and starting at step 1 is a legitimate answer and usually the fast one. What is precious is the *evidence*: run the capture in "If it fails: what to capture" **before** you wipe, or the attempt taught nobody anything.

### Step by step: what a failure costs

| Step | If it fails partway | Safe to redo? | Getting back |
|---|---|---|---|
| 1 network and disk | Nothing is installed yet | Yes, completely | Re-partition and restart. This is the only destructive step, and only to the disk's previous contents |
| 3 `pacstrap` | A partial root under `/mnt` | Yes | Run the same `pacstrap` line again; it resumes and re-resolves. The `mkinitcpio` error at the end of it is expected, not a failure |
| 4 keyring | Keyring half-built, later `pacman` calls fail on signatures | Yes | `rm -rf /mnt/etc/pacman.d/gnupg`, then re-run the three `pacman-key` commands |
| 5 system files, initramfs | An initramfs that does not boot | Yes | `arch-chroot /mnt mkinitcpio -P` is idempotent. Before you regenerate a *working* one, `cp /mnt/boot/initramfs-linux.img /mnt/boot/initramfs-linux.img.bak`; if the new one dies, boot the USB, chroot and copy the backup back |
| 6 overrides | Wrong or missing `fontconfig` | Yes | `pacman -U` is atomic: a failed one changed nothing. To go back to the repo version, `arch-chroot /mnt pacman -S fontconfig` |
| 7 stack tarball | A half-extracted `/usr/local` | Yes | Re-extract the same tarball over the top and re-run `ldconfig`; tar overwrites. Then re-run both `ldd -r` checks - a zero from each is what says the extraction is whole. To undo the one file that shadows a package, `pacman -S libinput && ldconfig` |
| 8 `omarchy-apply-system` | **The dangerous one. See below** | Yes, and a re-run is cheap | Re-run the same command; the scripts are written to be re-runnable |
| 9 user stage | A partly seeded `~/.config` | Yes | Re-run it; `--force` is what makes it overwrite |
| 10 bootloader | A machine that will not boot | Yes | Boot the USB, chroot, run `omarchy-refresh-grub` again. Confirm `ls -la /mnt/boot/EFI/BOOT/BOOTIA32.EFI` before you reboot, every time |

### Step 8 is the one that fails quietly

`omarchy-apply-system` runs four stages in order: `config/`, hardware, `login/`, `post-install/`. It runs under `set -e`, and `install/config/firewall.sh` is the **last** entry in `install/config/all.sh`. So if anything in the config stage fails, the three stages after it never run at all - including `install/login/greetd.sh`, which is what writes the greetd config and the autologin. The 2026-09-02 x86_64 gate hit exactly this (a masked `ufw.service` in that VM) and the visible symptom was not an error, it was a machine that booted to a plain text login with no desktop offered.

Check it rather than trust the exit code:

```bash
grep -E 'Failed|Completed: ' /mnt/var/log/omarchy-install.log | tail -20
ls -l /mnt/etc/greetd/config.toml                       # must exist
grep -c initial_session /mnt/etc/greetd/config.toml     # want 1
```

If `config.toml` is missing, the stages after the failure were skipped. Fix the cause, then either re-run the whole command, or run just the skipped stages:

```bash
arch-chroot /mnt bash -c '
  export OMARCHY_PATH=/usr/share/omarchy
  export OMARCHY_INSTALL=$OMARCHY_PATH/install
  export OMARCHY_INSTALL_USER=<user>
  export OMARCHY_FIRST_INSTALL=1 OMARCHY_UPGRADE=0
  export OMARCHY_LOG_TO_STDOUT=1
  export PATH=$OMARCHY_PATH/bin:$PATH
  source $OMARCHY_INSTALL/helpers/logging.sh
  omarchy-apply-hardware --install-user "$OMARCHY_INSTALL_USER"
  source $OMARCHY_INSTALL/login/all.sh
  source $OMARCHY_INSTALL/post-install/all.sh'
```

That is the recovery the gate used on x86_64. It has not been run on i686, so if you need it, say whether it worked.

A full re-run of `omarchy-apply-system` is safe: `firewall.sh` detects a chroot with `ENABLED=yes` already written and exits immediately rather than loading deny rules into the live kernel a second time.

### It boots, but you never get a desktop

Four different things look identical from the chair: a flat, dark, unresponsive screen. Tell them apart before you diagnose.

**First, get a text console.** greetd owns `vt1`. `Ctrl+Alt+F2` gives you `tty2` and an ordinary login prompt, and everything in "If it fails: what to capture" is written to work from there. If `Ctrl+Alt+F2` gives you nothing either, reboot and stop the desktop from starting at all: at the GRUB menu press `e`, append to the `linux` line

```
systemd.unit=multi-user.target
```

and `Ctrl+X` to boot it. That boots the whole system with no display manager, which is a working machine you can log into and read logs on. It is not persistent; a normal reboot goes back to the desktop. To make it persistent while you work, `sudo systemctl disable greetd`, and `sudo systemctl enable greetd` when you are done.

If the **panel itself never lights at any point** - no GRUB menu, no kernel messages, nothing since the firmware chime - add `nomodeset` as well. You lose KMS and the pixman renderer with it, but you get a text console, and "text console with `nomodeset`, nothing without it" is itself the single most useful sentence you could put in the report about the GMA 950.

Now, in order of likelihood:

1. **The idle lock.** The session locks itself after 300 seconds idle, and this fork's lock screen is drawn by the shell as a flat theme-coloured fill. It looks exactly like a dead compositor. **Press a key first, before anything else.** This fork has no `swaylock` process to look for - the lock is inside Quickshell - so if you need to settle it from a TTY, `pgrep -x quickshell` and `pgrep -x Hyprland` both answering means the session is alive and you are looking at the locker. For an unattended run, turn idle off properly with `omarchy-toggle-idle stay-awake`. Do not kill the locker: killing a locker that holds the session lock leaves Hyprland on its "crashed lockscreen" page, which reads as a renderer failure and is not one. Clear that with `hyprctl eval "hl.clear_crashed_lockscreen()"`.

2. **The ~1-in-5 login crash. Log in again.** Roughly one login in five on this stack ends with the compositor dying and greetd dropping you back on tuigreet. Log in a second time; it usually takes. This is expected and it is not what you are testing, so do not spend the session on it - **but count it**. How many attempts you needed out of how many logins is a number the project wants. The whole story, including what changed and what it does not prove, is in "The i686 login crash" below.

3. **A login loop you cannot break out of.** greetd starts the session, the session dies, greetd offers the greeter, you log in, repeat. What makes it a loop rather than a crash is the second failure behind it: when the compositor dies, `start-hyprland` restarts it with `--safe-mode`, and the safe-mode dialog **segfaults** because it wants `hyprland-dialog` from `hyprland-qtutils`, which is not in archlinux32 and is not installed. So the recovery path is itself broken and the machine cannot help itself. Do not fight it from the greeter. Drop to `tty2` (or boot `systemd.unit=multi-user.target`), capture the logs, and then try the reduced config in "The i686 login crash". Log in there once first, so the journal has the failure in it.

4. **The shell is gone but the compositor is not.** A blank desktop with a working `hyprctl` is a Quickshell that exited. Bring it back with

   ```bash
   hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'
   ```

   Note the Lua syntax: `hyprctl dispatch exec <cmd>` is the old form and now answers `')' expected near ...`. Related trap, learned the expensive way: **do not use `omarchy-restart-shell` over ssh or from a TTY.** The old instance exits on the IPC request and the respawn does not always take, and what you get is a flat dark screen indistinguishable from both of the failures above. When the point is to test what greetd starts, reboot instead.

### What not to do

- Do not `rm -rf` anything under `/usr/local` to "clean up" the stack tarball. Re-extracting over it is the supported repair.
- Do not turn `input:numlock_by_default` back on. See below.
- Do not `pacman -Syu` to try to fix a broken session. The fork pins `libinput`, `qt6-base` and `qt6-declarative` for reasons that end in a shell that will not start.
- Do not reinstall from scratch before capturing logs. A wiped disk is a failed attempt that taught nobody anything.

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

**The 2026-09-04 physical install found the remaining hardware-specific trigger.** The first real MacBook1,1 session reached the complete Omarchy desktop and then aborted after about five minutes of physical input; the next lasted 47 seconds. One core stopped in libinput while processing an out-of-range `appletouch` coordinate, and another stopped while Hyprland updated keyboard modifier state. Both exposed the same heap corruption rather than two independent crashes. Leaving `numlock_by_default` off was therefore necessary but not sufficient on the actual A1181.

Skipping `default.hypr.input` only on DMI product `MacBook1,1` kept the rest of the Omarchy configuration intact: 207 bindings, the Quickshell panel and menu, theme, window rules and autostart all remained loaded. That session survived more than 30 minutes, synthetic and physical typing, and physical trackpad movement without another core. The installed `appletouch` driver initially enumerated without emitting events; unloading and reloading that one module initialized it in Geyser mode and restored movement without restarting Hyprland. The shipped guard now leaves this model on Hyprland's input defaults; every other model still receives Omarchy's input tuning.

Two things this does not mean. It does not mean the renderer is fixed: the
hand-start harness still lost about one start in five, visible in the 3/4, 5/6
and 4/5 rows above, so **a login that lands on the greeter is possible**. Log in
again. And it does not mean the trigger is understood: one config path reaches
it every time and has been closed, that is all.

If you turn `numlock_by_default` back on, this comes back. Do not.

**What the 2026-09-02 x86_64 runtime gate adds, and it is less than it looks.** Nine cold boots of the x86_64 VM on this branch gave nine first-attempt logins: `pam_unix(greetd:session): session opened`, both `Hyprland` and `quickshell` alive, no crash line under the `omarchy-session` journal tag, no failed unit. Five of those nine were a scripted run made specifically to hunt this crash. It did not appear once. That is **not** evidence the crash is gone: at a true one-in-five rate, nine clean boots in a row happens about 13% of the time by chance, and the bug was only ever bisected on i686 in the first place. Treat the paragraph above as current on the hardware you are sitting at, and count your logins.

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

## At the machine: what to type, and what to look at

Everything in this section is hardware. None of it can be answered in a VM, and it is the reason a person is sitting in front of this machine at all.

Two kinds of work are mixed together in a hardware session, and keeping them apart is what makes the report worth reading:

- **Type** - commands, printed verbatim below. Their output can be copied, pasted and argued over a week later, and the capture in the next section collects most of them for you without you having to think about it.
- **Observe** - what the panel, the fan, the keyboard and the clock actually do. No log recovers these afterwards. No command substitutes for them. They are the whole reason a VM could not settle this question. Write them down in words as you go, even when the answer is "yes, fine" - especially then, because "yes, fine" is the result nobody has ever recorded for this machine.

The single sentence the project most wants out of this session is an observation and not a command: **did the panel light up and show a desktop drawn entirely by the CPU.**

### The session in one table

| Question | You type | You observe |
|---|---|---|
| Does the GMA 950 scan out with dumb buffers | `hyprctl monitors`, `dmesg \| grep -i i915` | Whether there is a **picture on the panel at all**, and whether it is right rather than torn, striped, shifted, half-drawn or stuck |
| Does the panel light up | nothing | The backlight, with your eyes. There is no command for this and it is not the same question as the one above |
| Is the desktop usable on a 2006 Core Duo | `Super+Return`, `Super+Space`, on the real keyboard | Whether the terminal and the menu appear, and **how many seconds** they take. Slow is a result; unusable is a different result |
| Wifi (ath5k) | `ip link`, `nmtui` | Whether the link is still up ten idle minutes later |
| Suspend and resume | `systemctl suspend`, and separately the lid | Whether the panel, the keyboard, the trackpad and wifi each come back |
| Brightness keys | `brightnessctl -l`, `brightnessctl set 50%` | Whether the screen visibly changes, and whether the `XF86MonBrightness` keys do it too |
| Fan control | `sensors` | Whether the fan **audibly** spins up under load, and whether the case becomes too hot to keep a hand on |
| iSight webcam | `ls /dev/video*` | Expected absent. Nothing to observe |
| Battery | `upower -i $(upower -e \| grep BAT)` | What the bar shows, and whether the machine survives being unplugged at all |
| Audio | `pactl info`, then play something | Whether sound comes out of the speakers, and whether the volume OSD appears when you press the keys |

### Type this first, on the first successful login

This is the baseline every other answer is read against. Run it once, whatever else the session does afterwards.

```bash
hyprctl systeminfo | grep -iE 'renderer|backend|^GPU|Monitor'
hyprctl monitors
lspci -nn | grep -i vga
ls -l /dev/dri/
dmesg | grep -iE 'i915|drm' | head -40
free -m
swapon --show
pacman -Q fontconfig neatvnc icu75 libxml2-legacy qt6-base qt6-imageformats libvips
git -C /usr/share/omarchy rev-parse HEAD
```

Two things in that output decide whether anything else you measure means anything:

- `Renderer: pixman (software)` and `Backend: drm`. Anything else and you are not testing this port. A desktop that merely appears is not evidence: Mesa's llvmpipe can supply GLES 3.0 in software and would look identical while using far more memory.
- The commit from the last line. Put it at the top of the report.

### 1. Does the GMA 950 scan out at all (the big one)

This is the single largest unknown in the whole port. The pixman renderer asks aquamarine for **DRM dumb buffers** (`AQ_FORCE_ALLOCATOR=dumb`) and writes pixels into them with the CPU. That needs the i915 KMS driver to accept a dumb buffer as a scanout framebuffer on an i945GM. It is a plain, old, well supported path, and it has never once been run.

**Type:**

```bash
dmesg | grep -i i915          # want "i915 ... registered", no "failed to"
ls -l /dev/dri/               # want card0 and renderD128
hyprctl monitors              # want the panel at 1280x800
```

**Working looks like:** `i915` registered without errors, a `card0`, a monitor named for the panel at 1280x800, and - the part only you can see - a **correct, stable picture**: the bar along the top, the wallpaper behind it, text that is sharp and in the right place, nothing torn or striped or offset by half a screen, nothing frozen while `hyprctl` still answers.

**Observe and write down separately:** does the backlight come on; is the image correct; is it stable over a few minutes; does the mouse cursor move smoothly or in jumps. These are four different answers and a report that gives all four is far more useful than one that says "it worked".

**If it does not:** the distinction that matters is *no picture with a live compositor* versus *no compositor*. `hyprctl monitors` answering while the screen is dark is the first; nothing answering is the second. Capture `dmesg | grep -i drm`, the full `journalctl -b -t omarchy-session`, and confirm the renderer variables actually reached the process:

```bash
tr '\0' '\n' < /proc/$(pgrep -x Hyprland)/environ | grep -E 'HYPRLAND_RENDERER|AQ_|QT_QUICK'
```

If the compositor exits complaining about GLES 3.0, the installed Hyprland is a stock build and not this fork's: only the fork's branches carry the pixman renderer, and step 7 is where that goes wrong.

The documented fallback is i3 on X11 with the modesetting driver. Say so in the report if you needed it.

### 2. The desktop under a Core Duo

New in this integration, and the part a VM measured but could not time honestly. 79 of the 92 shipped backgrounds are `.webp`, and the default one is 6016x3384. Decoding that is CPU work on a machine whose whole point is that it has no GPU.

**Type:**

```bash
# on the real keyboard, not over IPC
# Super+Return          -> a foot terminal
# Super+Space           -> the Omarchy menu, ten rows with icons
# Super+Space, type "background", Enter   -> the image picker
omarchy-theme-set "Tokyo Night"
```

**Working looks like:** the terminal and the menu open and are themed; the picker's carousel shows **real thumbnails of the images, not empty outlines**; moving with `Right` and pressing `Enter` changes the wallpaper and the new one draws; the theme switch retints the bar, the terminal, the window borders and the wallpaper together.

**Observe:** the times. How long from `Super+Space` to a drawn menu. How long the picker takes to fill in. How long a wallpaper change takes to appear. Seconds are fine and expected; the project has no idea whether the number is 2 or 30 on this hardware, and it matters more than any log line here.

**If it does not:** empty tiles in the picker mean the `MultiEffect` fix did not reach you - check you are on the pinned commit. A blank wallpaper with everything else working means `qt6-imageformats` is missing. Capture `journalctl -b -t omarchy-shell --no-pager | tail -60` either way.

Expected noise you should **not** report: every theme switch prints `Error accessing /usr/bin/omarchy-theme-set-browser-policy: No such file or directory`. That is a known fork-layout defect - the helper is elevated through `/usr/bin`, which a fork that ships no package does not have. Only the Chromium accent colour is lost; the theme switch itself completes.

### 3. Wifi (ath5k)

The AR5BXB63 is in-tree. No firmware install should be needed.

**Type:**

```bash
ip link                    # want a wl* device
nmtui                      # connect
grep -r . /etc/NetworkManager/conf.d/ath5k-no-powersave.conf
```

**Working looks like:** a `wl*` interface with no firmware errors in `dmesg`, a connection through `nmtui`, and the powersave override file present.

**Observe:** whether the link is still up after ten idle minutes. Known issue: powersave makes ath5k drop the link, and `install/hardware/apple/fix-a1181.sh` writes the NetworkManager override that turns it off. If the file is missing, the hardware stage of step 8 did not run - see "Step 8 is the one that fails quietly".

**If it does not:** `dmesg | grep -i ath5k`, `nmcli device status`, `journalctl -b -u NetworkManager | tail -60`.

### 4. Fan control (mbpfan)

**Not installed, and it cannot be.** mbpfan is not in the archlinux32 repos and the fork has no package for it yet; `fix-a1181.sh` skips it and says so. The MacBook runs on the firmware's own fan curve, which on this model is lazy.

**Type:**

```bash
sensors            # applesmc; lm_sensors arrives as a mesa dependency
```

**Observe, and this one is genuinely physical:** put the machine under load - a `pacman -Syu`, or just leave the desktop busy - and listen. Does the fan spin up at all? Can you keep a hand on the underside? A CPU renderer means the CPU is doing the drawing, so this machine will run hotter at idle desktop than the same machine running a text console, and nobody has ever measured by how much.

**If it climbs past 85 C on an ordinary workload**, say so with the number. A fan daemon then moves from the "nice to have" list to the "must package" list.

### 5. iSight webcam

**Expected absent.** It needs a firmware blob Apple does not allow us to redistribute, and `isight-firmware-tools` is not in archlinux32 either.

**Type:** `ls /dev/video*`

**Working looks like:** nothing. An empty result is the expected answer and is not a bug. If you want the camera, extract `AppleUSBVideoSupport` from a macOS install with `ift-extract` on another machine and reload `uvcvideo`.

### 6. Brightness keys

`brightnessctl` is in the core package list.

**Type:**

```bash
brightnessctl -l                 # is there a backlight device at all?
brightnessctl set 50%
```

**Then, on the keyboard:** the `XF86MonBrightnessUp` and `Down` keys, through the compositor.

**Working looks like:** at least one backlight device listed, `set 50%` visibly dimming the panel, and the keys doing the same thing with the OSD appearing.

**Observe:** these are two independent results. The backlight can work while the keys do nothing, and that is a keybinding question rather than a hardware one. Report which device name you got, or that there was none. On this generation the backlight is driven through `acpi_video` or the `gmux`/`apple_bl` path, and either can be missing.

### 7. Suspend and resume

This is where an old Intel graphics stack usually breaks: the machine sleeps and comes back with a dead panel because the KMS driver failed to restore the mode. Test the lid and the command separately; they are not the same path.

**Type:**

```bash
systemctl suspend
# after resume:
journalctl -b -k | grep -iE 'i915|drm' | tail -40
```

**Working looks like:** the machine sleeps, wakes on a keypress or the lid, and the panel comes back with the session as you left it.

**Observe, as four separate answers:** did the **display** come back, the **keyboard**, the **trackpad**, and **wifi**. A resume that restores three of the four is a much more useful report than "suspend broken".

**If it does not:** if the panel is dead but the machine is alive, get in over ssh or `Ctrl+Alt+F2` and capture the kernel log above; the failure will be in the `i915` lines around the resume.

### 8. Battery

**Type:** `upower -i $(upower -e | grep BAT)`

**Observe:** what the bar shows. A 2006 battery is very likely dead, and "reports 0% / not present / charges but does not hold" are all fine answers. Say which.

### 9. Audio

pipewire on archlinux32 is 0.3.65, which is old. Quickshell's pipewire service is compiled against it after a two-line patch, so the audio panel, the volume OSD and the media widgets are present rather than absent. **Whether the service actually talks to a 0.3.65 daemon has never been tested against a running daemon**, and this is the best chance anyone has had to find out.

**Type:**

```bash
pactl info
journalctl -b -t omarchy-shell --no-pager | grep -i pipewire
```

**Then:** play something.

**Working looks like:** `pactl info` naming a PipeWire server, sound out of the speakers, the bar's volume widget showing a real level, and the OSD appearing when you press the volume keys.

**Observe:** whether the widget tracks the volume, or sits at a fixed value while the sound changes. A widget that is present but wrong is the interesting failure here and it is invisible in any log.

## If it fails: what to capture

A failed attempt is still worth having if you bring these back. **Assume no desktop.** Everything below is written to run from a text console: `Ctrl+Alt+F2` for `tty2`, or a boot with `systemd.unit=multi-user.target` appended at the GRUB menu if even that fails. Nothing here needs a graphical session, a browser or a network.

### The one command to run

Copy this in as one block. It writes everything to a single file under `/tmp`, and it does not stop at the first thing that is missing.

```bash
out=/tmp/omarchy-report-$(date +%Y%m%d-%H%M%S).txt
{
  echo "### commit";        git -C /usr/share/omarchy rev-parse HEAD
  echo "### branch";        git -C /usr/share/omarchy rev-parse --abbrev-ref HEAD
  echo "### uname";         uname -a
  echo "### dmi";           cat /sys/class/dmi/id/product_name /sys/class/dmi/id/board_name
  echo "### session";       journalctl -b -t omarchy-session --no-pager | tail -200
  echo "### shell";         journalctl -b -t omarchy-shell   --no-pager | tail -100
  echo "### greetd";        journalctl -b -u greetd          --no-pager | tail -60
  echo "### failed units";  systemctl --failed --no-pager
  echo "### install log";   tail -100 /var/log/omarchy-install.log
  echo "### vga";           lspci -nn | grep -i vga
  echo "### dri";           ls -l /dev/dri/
  echo "### drm";           dmesg | grep -iE 'drm|i915' | tail -60
  echo "### env";           tr '\0' '\n' < /proc/$(pgrep -x Hyprland)/environ 2>/dev/null | grep -E 'HYPRLAND_|AQ_|QT_QUICK|XDG_|WAYLAND'
  echo "### systeminfo";    hyprctl systeminfo 2>&1 | head -40
  echo "### memory";        free -m; swapon --show
  echo "### packages";      pacman -Q fontconfig neatvnc icu75 libxml2-legacy qt6-base qt6-imageformats libvips
  echo "### quickshell";    quickshell --version
  echo "### hyprland ldd";  ldd -r /usr/local/bin/Hyprland 2>&1 | grep 'undefined symbol'
  echo "### crash reports"; ls -la ~/.cache/hyprland/ 2>/dev/null
  cat ~/.cache/hyprland/hyprlandCrashReport*.txt 2>/dev/null
} > "$out" 2>&1
echo "$out"
```

Several of those will print errors when the thing they ask about is not there. That is fine and it is the point: an error is data. Read the file before you leave the machine (`less "$out"`), because that is your last chance to notice you captured nothing.

Two things about running it as an ordinary user in a TTY. `journalctl -b -t ...` needs your account to be in `wheel`, `adm` or `systemd-journal` - the install user is in `wheel`, so it works, but `sudo` the whole block if a journal section comes back empty. And the two `git` lines will say `detected dubious ownership` unless you run them as root or add the `safe.directory` line above; the commit is the one field of this report nobody can reconstruct afterwards, so check that it is really in the file.

### Getting it off the machine

In order of how likely they are to work on a machine with no desktop:

```bash
# a USB stick
lsblk                            # find it
sudo mount /dev/sdb1 /mnt && sudo cp "$out" /mnt/ && sync && sudo umount /mnt

# the network, if wifi came up (nmtui works fine in a TTY)
scp "$out" you@another-machine:

# nothing else works: photograph the screen
less "$out"                      # space to page, q to quit
```

A phone photograph of a `less` page is a legitimate report and has settled arguments before. Take the `### drm` and `### session` blocks first if you can only take a few.

### What matters most, in order

If you can only bring back some of it:

1. **`journalctl -b -t omarchy-session`.** The compositor's own output. Hyprland's log file is empty by default (`debug:disable_logs`) and greetd sends the session's stdout nowhere, so this journal tag is the only place the banner, `malloc(): invalid size (unsorted)` and the crash-report path appear. If it comes back empty, your `/etc/greetd/config.toml` predates this branch; check you cloned the right branch, and add `systemd-cat -t omarchy-session ` in front of both `command =` lines.
2. **`dmesg | grep -iE 'drm|i915'` and `lspci -nn | grep -i vga`, verbatim.** This is the field the project most needs and the one no VM can produce.
3. **`hyprctl systeminfo`**, for the renderer line.
4. **The crash reports.** Two of zero bytes plus one full one is the normal shape of the login crash: the abort kills the process before the first report is written, and the full one is the safe-mode dialog segfault, which is a consequence and not the cause. Send all of them anyway.
5. **Your own sentences.** What you saw, in words. See the previous section for which observations are irreplaceable.

File it with the [hardware report form](https://github.com/cederikdotcom/omarchy32cpu/issues/new?template=hardware-report.yml). One report per machine. Read [`../../TESTING.md`](../../TESTING.md) first for the list of things already known to be broken, and do not report those.

## Memory: the 2 GB question is answered

Measured in the i686 VM held at 2048 MB, the MacBook's size, at 1280x800, **at commit `0faf8483` - before this integration, when the backgrounds were still JPEG and PNG**. The decoded size of an image does not depend on the container it was stored in, so the arithmetic below should carry over unchanged to the `.webp` originals. Should. Nobody has measured it on i686, and on x86_64 the shell measured 266 MB RSS holding the 6016x3384 WebP default against the 234 MB recorded the day before on the same VM with the JPEG-era default - close, but not the same number, and not measured under controls tight enough to say why. Re-measuring `free -m` and the shell's RSS on the hardware is cheap and is worth doing.

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
several hundred MB. On archlinux32 that fallback is a live possibility rather
than a hypothetical, because the repo's `libvips` is 8.11.3 and nobody has
confirmed its `vipsthumbnail` reads WebP. Check `ls ~/.cache/omarchy/image-selector/*.jpg`
after opening the picker, and watch `free -m` while it is open: four
5000x3000 originals held at once is the shape of the problem.

Do not drop `qt6-imageformats` either, for the opposite reason: without it the
WebP backgrounds do not decode at all, so the memory cost goes to zero and so
does the wallpaper.

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
- Stop the session locking itself while you work on it: `omarchy-toggle-idle stay-awake`. Do this before any measurement that takes longer than five minutes.
- Text console at any time: `Ctrl+Alt+F2`. greetd owns `vt1`, so `tty2` is always free.
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
- **The desktop comes up with no wallpaper, and no error anywhere.** `pacman -Q qt6-imageformats`. 79 of the 92 shipped backgrounds are `.webp`, and without that plugin Qt loads them as nothing at all - silently, which is what makes it hard to spot. The same cause empties the image picker.
- **The image picker's carousel is a row of empty outlines.** You are not on the pinned commit. Qt Quick's software scenegraph has no shader stage, so the `MultiEffect` upstream masks each tile through draws nothing and says nothing about it; `2f1378cc` skips that layer when `QT_QUICK_BACKEND=software`. Check with the three commands in "The repository".
- **Every theme switch prints `Error accessing /usr/bin/omarchy-theme-set-browser-policy`.** Known and expected on this fork. The helper elevates through an absolute `/usr/bin` path that upstream's package provides and a fork with no package does not. Only the Chromium-family accent colour is lost. Do not report it.
- **`hyprctl dispatch exec <cmd>` answers `')' expected near ...`.** The dispatcher takes Lua now: `hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-launch-shell")'`.
- **You ran `omarchy-restart-shell` and the screen went dark.** The old instance exits on the IPC request and the respawn does not always take. `pgrep -x quickshell` settles whether that is what happened; the line above brings it back. Reboot instead when the point is to test what greetd starts.
- **`Super+Space` prints `Image selector failed to accept request` but the picker opens anyway.** Timing, not a defect: `omarchy-menu-images` gives the shell 2 s (`OMARCHY_SHELL_IPC_TIMEOUT`) to accept, and laying out the carousel takes longer on a slow machine. Expect to see this on a Core Duo. The picker still opens, renders and applies the selection.
