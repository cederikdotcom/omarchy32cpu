# BENCH.md — omarchy32cpu build + test bench runbook

> **NOTE (2026-08-31): old bench `2.28.72.117` is RETIRED for builds** (memory-starved,
> SSH reset at handshake). It is kept ONLY as the omarchy32cpu demo/VM host. Do not
> build there. All build + harness work moved to the bench below and is VERIFIED.

Bench: `root@46.224.193.205` (Debian 13, x86_64 native, 8 vCPU, 16 GB RAM, 300 GB disk,
key auth; pacman+pacstrap installed). Use `MAKEFLAGS=-j8` / `ninja -j8`.
Goal: native x86_64 Arch chroot to build our Hyprland/aquamarine forks and run a
stock-Hyprland baseline (llvmpipe) before the pixman-renderer work.

Local workspaces (commit locally only, never push):
- `~/hyprdev/Hyprland`  — branch `pixman-renderer` off tag `v0.56.2` (HEAD 26febe72, clean)
- `~/hyprdev/aquamarine` — branch `cpu-backend`    off tag `v0.15.0` (HEAD e088146, clean)

---

## Host layer (Debian 13) — DONE on 46.224.193.205

```bash
# pacman on Debian is the ARCADE GAME; the package manager is pacman-package-manager
apt-get update && apt-get install -y pacman-package-manager makepkg arch-install-scripts rsync

# DRM devices for the test harness: the default -cloud kernel ships NO DRM drivers.
# Install the standard kernel and boot it (grub-set-default by menuentry id):
apt-get install -y linux-image-amd64
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub && update-grub
grub-set-default "gnulinux-advanced-<UUID>>gnulinux-6.12.107+deb13-amd64-advanced-<UUID>"
printf 'vgem\nvkms\nudmabuf\n' > /etc/modules-load.d/hyprdev-bench.conf
reboot
# after reboot: uname -r = 6.12.107+deb13-amd64; /dev/dri has card0 (vgem),
# card1 + renderD129 (virtio-gpu, connector Virtual-1 CONNECTED — this is the one we use)
```

## Prepared local artifacts

`~/hyprdev/pacman-bootstrap.conf` (uploaded to `/opt/hyprdev/pacman-bootstrap.conf`):
```ini
[options]
Architecture = x86_64
SigLevel = Never
HoldPkg = pacman glibc
CheckSpace

[core]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch

[extra]
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
```

`~/hyprdev/hyprland-flat.conf` — minimal flat-mode config (effects off), uploaded to
`/opt/hyprdev/hyprland-flat.conf` AND `/opt/hyprdev/root/opt/hyprdev/hyprland-flat.conf`.

Dependency-version check (drives build order):
- Hyprland v0.56.2 requires: `aquamarine>=0.9.3`, `hyprlang>=0.6.7`, `hyprcursor>=0.1.7`,
  `hyprutils>=0.14.0`, `hyprgraphics>=0.5.1`, `hyprwayland-scanner>=0.4.0`.
- Chroot packaged versions (all satisfy): hyprland 0.56.2-1 (same tag as our fork —
  ideal stock baseline), aquamarine 0.14.0-2, hyprutils 0.14.1, hyprlang 0.6.8,
  hyprgraphics 0.5.1, hyprcursor 0.1.13, hyprwayland-scanner 0.4.6, gcc 16.2.1, cmake 4.4.3.
- **Build order:** our aquamarine fork FIRST, `ninja install` (goes to `/usr/local`),
  then our Hyprland with `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig` so it links ours.
  Our built `build/Hyprland` gets `RUNPATH /usr/local/lib` → loads fork libaquamarine
  0.15.0; packaged `/usr/bin/Hyprland` keeps packaged 0.14.0. Clean separation.

---

## Chroot bootstrap — DONE on 46.224.193.205 (repeat only for a rebuild from scratch)

```bash
# 0. sanity + space (need ~10G free)
ssh root@46.224.193.205 'df -h /; uname -m; nproc; free -h | head -2'

# 1. copy the bootstrap pacman.conf up
ssh root@46.224.193.205 'mkdir -p /opt/hyprdev/src'
scp ~/hyprdev/pacman-bootstrap.conf root@46.224.193.205:/opt/hyprdev/pacman-bootstrap.conf
scp ~/hyprdev/hyprland-flat.conf    root@46.224.193.205:/opt/hyprdev/hyprland-flat.conf

# 2. pacstrap a mount-less x86_64 chroot (~2.0G)
ssh root@46.224.193.205 'mkdir -p /opt/hyprdev/root && \
  pacstrap -C /opt/hyprdev/pacman-bootstrap.conf -c -G -M /opt/hyprdev/root \
    base base-devel git cmake meson ninja pkgconf \
    wayland wayland-protocols libdrm libinput mesa pixman cairo pango libxkbcommon \
    seatd sway foot grim jq \
    hyprutils hyprlang hyprcursor hyprgraphics hyprwayland-scanner aquamarine hyprland \
    xorg-xwayland'

# 3. make pacman work INSIDE the chroot (default mirrorlist is empty; CheckSpace
#    cannot resolve the mount point in a mount-less chroot):
ssh root@46.224.193.205 'echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" \
    >> /opt/hyprdev/root/etc/pacman.d/mirrorlist; \
  sed -i -e "s/^SigLevel.*/SigLevel = Never/" -e "s/^CheckSpace/#CheckSpace/" \
    /opt/hyprdev/root/etc/pacman.conf'

# 4. extra packages used by the harness checks
ssh root@46.224.193.205 'arch-chroot /opt/hyprdev/root pacman -Sy --noconfirm python-pillow sysstat'

# 5. verify the packaged deps landed
ssh root@46.224.193.205 'arch-chroot /opt/hyprdev/root \
  pacman -Q hyprland aquamarine hyprutils hyprlang hyprgraphics mesa pixman'
```

Chroot entry (mount-less, arch-chroot handles the API mounts; the "not a mountpoint"
warning is expected and harmless):
```bash
ssh root@46.224.193.205 'arch-chroot /opt/hyprdev/root /bin/bash'
# non-interactive form used throughout: arch-chroot /opt/hyprdev/root <cmd...>
```
**Gotcha:** `/tmp` and `/run` inside arch-chroot are per-invocation tmpfs — anything
written there VANISHES when the arch-chroot exits. Persistent logs/artifacts go to
`/opt/hyprdev/logs` (= `/opt/hyprdev/root/opt/hyprdev/logs` from the host).

---

## Incremental rsync (local → bench)

```bash
# push both forks into the chroot's /opt/hyprdev/src (paths mirror the bench layout)
rsync -a --delete --exclude build --exclude .git/modules \
  ~/hyprdev/aquamarine/ root@46.224.193.205:/opt/hyprdev/root/opt/hyprdev/src/aquamarine/
rsync -a --delete --exclude build \
  ~/hyprdev/Hyprland/   root@46.224.193.205:/opt/hyprdev/root/opt/hyprdev/src/Hyprland/
# Hyprland keeps .git so `git submodule update --init` inside the chroot works
# (subprojects/ is empty locally; the chroot has network + git).
```
Re-run the same rsync for each incremental change — only deltas transfer.

---

## Build inside the chroot (aquamarine first, then Hyprland) — VERIFIED 2026-08-31

```bash
CH=/opt/hyprdev/root
run(){ ssh root@46.224.193.205 "arch-chroot $CH /bin/bash -lc '$*'"; }

# aquamarine (our cpu-backend fork) — install so Hyprland links ours
run 'export MAKEFLAGS=-j8; cd /opt/hyprdev/src/aquamarine && \
     cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
     ninja -C build -j8 && ninja -C build install'
# NOTE: installs to /usr/local; Arch pkg-config does NOT search /usr/local by default:
run 'PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion aquamarine'  # 0.15.0
run 'pkg-config --modversion aquamarine'                                            # 0.14.0 (packaged)

# Hyprland (our pixman-renderer fork) — needs safe.directory for root-owned rsynced .git
run 'export MAKEFLAGS=-j8 PKG_CONFIG_PATH=/usr/local/lib/pkgconfig; \
     cd /opt/hyprdev/src/Hyprland && \
     git config --global --add safe.directory \"*\" && \
     git submodule update --init --recursive && \
     cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
     ninja -C build -j8'
# link check: readelf -d build/Hyprland → RUNPATH /usr/local/lib;
# ldd build/Hyprland | grep aquamarine → /usr/local/lib/libaquamarine.so.14 (fork 0.15.0)

# incremental rebuilds after an rsync of changed sources:
run 'ninja -C /opt/hyprdev/src/aquamarine/build -j8 && ninja -C /opt/hyprdev/src/aquamarine/build install'
run 'ninja -C /opt/hyprdev/src/Hyprland/build -j8'
```
Fix missing deps as hit: `arch-chroot $CH pacman -S --noconfirm <pkg>`; record each here.

---

## Test harness — WORKING: seatd + stock Hyprland on the DRM backend (virtio-gpu)

**Finding (2026-08-31):** the originally planned nested harness (headless sway host →
stock Hyprland via aquamarine's *Wayland* backend) does NOT work for STOCK Hyprland on
this bench: aquamarine's Wayland backend needs `linux-dmabuf`, which sway cannot offer
headless here (sway+pixman = no dmabuf; sway+gles2 = `gbm_bo_create: Permission denied` —
no GL buffer export on vgem/virtio without virgl, dumb buffers are card-node-only).
That nested path becomes viable exactly when our cpu-backend fork's **Shm allocator +
wl_shm Wayland backend** lands — it IS the fork's acceptance test (script kept at
`/opt/hyprdev/harness.sh` in the chroot; sway headless+pixman host itself runs fine).

The WORKING stock baseline runs Hyprland directly on aquamarine's DRM backend against
the virtio-gpu card (connector Virtual-1, 1280x800 preferred), GL via mesa/llvmpipe:

```bash
# script installed at /opt/hyprdev/root/opt/hyprdev/harness-drm.sh; essence:
ssh root@46.224.193.205 'arch-chroot /opt/hyprdev/root /bin/bash -lc "/opt/hyprdev/harness-drm.sh"'
```
harness-drm.sh does (all inside ONE arch-chroot shell so /run is shared):
```bash
export XDG_RUNTIME_DIR=/run/bench-xdg   # fresh, chmod 700
seatd -g root &                          # wait for /run/seatd.sock
export LIBSEAT_BACKEND=seatd AQ_DRM_DEVICES=/dev/dri/card1
# root inside the chroot → Hyprland needs its root-bypass flag:
/usr/bin/Hyprland --i-am-really-stupid --config /opt/hyprdev/hyprland-flat.conf &
# wait for $XDG_RUNTIME_DIR/wayland-*; then:
WAYLAND_DISPLAY=wayland-1 foot -e sleep 30 &
WAYLAND_DISPLAY=wayland-1 grim /opt/hyprdev/logs/shot.png
python3 Pillow non-black check; /proc/<pid>/stat CPU sample; cleanup
```
Verified result 2026-08-31: `total (1280, 800) nonblack_px 979910 distinct 607` —
real frame (foot fullscreen + Hyprland notifications + cursor). Pull it down with:
```bash
scp root@46.224.193.205:/opt/hyprdev/root/opt/hyprdev/logs/shot.png ~/hyprdev/baseline-shot.png
```
Logs persist at `/opt/hyprdev/root/opt/hyprdev/logs/` (sway.log, seatd.log, hypr.log,
hypr-runtime/<sig>/hyprland.log — the runtime log dir is copied out of tmpfs before exit).

To test OUR fork instead of stock, run `/opt/hyprdev/src/Hyprland/build/Hyprland`
in place of `/usr/bin/Hyprland` (RUNPATH already selects fork aquamarine).

---

## Cleanup (keep chroot + build trees in place)

```bash
# just kill leftover nested processes; do NOT remove /opt/hyprdev
ssh root@46.224.193.205 'pkill -f "/opt/hyprdev/src/Hyprland/build" ; pkill Hyprland; pkill sway; pkill seatd; true'
# full teardown only when finished with the bench:
# ssh root@46.224.193.205 'rm -rf /opt/hyprdev/root /opt/hyprdev/src'
```

---

## Pixman-renderer harnesses (added implementation session 1, all VERIFIED 2026-08-31)

Scripts live in the chroot at `/opt/hyprdev/*.sh`; run each as
`ssh root@46.224.193.205 'arch-chroot /opt/hyprdev/root /bin/bash -lc /opt/hyprdev/<script>'`:

- `harness-pixman-headless.sh` — M0: GPU-less headless session (no seat, no host ->
  aq headless backend + shm allocator), solid-clear grim check.
- `harness-pixman-m1.sh` — M1: foot x2, floating overlap, xeyes, idle-CPU sample,
  window-close smoke; screenshots to /opt/hyprdev/logs/pixman-m1-*.png.
- `harness-pixman-m1b.sh` — damage trace (HYPRLAND_TRACE=1, grep "pixman: begin frame")
  + xeyes with DISPLAY=:0.
- `harness-pixman-nested.sh` — the fork acceptance test: sway headless+pixman host
  (wl_shm only) -> our aq Wayland backend + shm allocator -> pixman Hyprland -> foot ->
  grim. WORKS since aquamarine e088146.

Gotchas learned:
- **arch-chroot = a fresh PID namespace per invocation**: launch, inspect (gdb/ps) and
  kill in the SAME `bash -lc`, or gdb fails with "ptrace: No such process" and stale
  compositors survive host-side pkill invisibly.
- rsync --delete wipes `subprojects/` -> rerun `git submodule update --init --recursive`
  in the chroot before building Hyprland.
- `misc:background_color` needs an ALPHA byte (0xffRRGGBB): alpha 0x00 clears BLACK
  under GL and pixman alike (CM premultiplies). hyprland-flat.conf now uses 0xff225588.
- grim's "failed to create buffer" = screencopy advertising a 0x0 buffer (monitor had
  no mode yet), not an shm problem.

## Run log

- 2026-08-31: Local repos confirmed (Hyprland pixman-renderer@v0.56.2,
  aquamarine cpu-backend@v0.15.0). Old bench 2.28.72.117 SSH blocked → RETIRED for
  builds (kept as omarchy32cpu demo/VM host only).
- 2026-08-31: NEW bench 46.224.193.205 bootstrapped end to end: host layer
  (pacman-package-manager, standard kernel + vgem/vkms/udmabuf for /dev/dri),
  pacstrap chroot (2.0G), both forks rsynced + BUILT CLEAN (aquamarine cpu-backend
  incl. uncommitted Shm WIP → 0.15.0 in /usr/local; Hyprland pixman-renderer →
  build/Hyprland links fork aquamarine via RUNPATH; `--version` runs). Stock-Hyprland
  baseline harness VERIFIED via DRM backend on virtio-gpu (screenshot non-black,
  ~/hyprdev/baseline-shot.png). Nested-sway path documented as fork acceptance test.
- 2026-08-31 (impl session 1): pixman renderer M0+M1 verified on this bench (headless +
  nested harnesses above). Both forks build clean; Hyprland pixman-renderer @26febe72,
  aquamarine cpu-backend @e088146. Screenshots pulled to ~/hyprdev/pixman-*.png.

---

## i686 chroot (M2, omarchy32cpu target) — VERIFIED 2026-08-31

Second chroot on the SAME bench: `/opt/hypr32/root` (archlinux32 i686, pacstrap with
`/opt/hypr32/pacman-i686.conf`, Server = https://mirror.archlinux32.org/i686/$repo).
Enter: `arch-chroot /opt/hypr32/root setarch i686 /bin/bash -lc <cmd>` (uname = i686).
Build env inside: `source /opt/hyprdev/env.sh` (adds /usr/local to PATH/PKG_CONFIG_PATH).
pip supplies cmake 4.4.3 + meson 1.12.0 (+jinja2); repo cmake/meson too old.

- Full dep story (source-built versions, the two patch files, chroot quirks:
  pango .pc floors, libxml2-legacy, ld.so.conf /usr/local/lib, locale-gen):
  `~/hyprdev/patches32/README.md`.
- Both forks build CLEAN for i686 after two Hyprland commits (4a2b510e py3.11
  stubs-gen, 63417a30 no ranges::starts_with); aquamarine needed nothing.
- Headless proof: `/opt/hyprdev/harness-pixman-headless-32.sh` in the chroot —
  fork Hyprland + pixman renderer + headless output + foot + grim; verified
  1920x1080, 2023552 non-black px, "Renderer: pixman (software)" in the runtime
  log; screenshot pulled to `~/hyprdev/i686-headless.png`.
- fontconfig 2:2.18.3-2 i686 override rebuilt (makepkg, doc=disabled) →
  `/opt/hypr32/overrides/fontconfig-2:2.18.3-2-i686.pkg.tar.zst` (also installed
  in the chroot; pango pkg-config chain needs it).
- Installable stage tree for the VM phase: `/opt/hypr32/stage` (89M, DESTDIR
  install of the whole stack: /usr/local/{bin,lib,share} + libinput 1.29 under
  /usr + etc/ld.so.conf.d/00-usrlocal.conf). Regenerate with
  `/opt/hyprdev/stage.sh` inside the chroot (writes /opt/stage32, host-mv to
  /opt/hypr32/stage).

---

## omarchy32cpu VM (M2 target) — BUILT + VERIFIED 2026-08-31

Lives on the SAME bench at `/opt/omarchy32vm/`. Built from scratch (the old
server `2.28.72.117` was probed once for its existing `disk2.img` and reset the
connection at the handshake, so do not bother with it again).

Layout:
- `disk.img` — 20 G raw GPT, 512 M FAT32 ESP at `/boot` + ext4 root (2.9 G used)
- `omarchy-src/` — the omarchy32cpu fork, copied into the image as
  `/usr/share/omarchy`
- `mkimage.sh` / `configure.sh` / `apply.sh` — the three build phases, re-runnable
- `launch-vm.sh` — the QEMU launcher (below)
- `OVMF32_VARS.fd` — writable copy of the IA32 firmware vars
- `serial.log`, `qemu.log`, `qemu-mon.sock` — console, QEMU stderr, monitor

Host packages needed: `qemu-system-x86 ovmf-ia32 dosfstools parted
arch-install-scripts rsync socat netpbm`.

### Image build (only to rebuild from scratch)

```bash
ssh root@46.224.193.205 '/opt/omarchy32vm/mkimage.sh'    # image + partitions + pacstrap i686
ssh root@46.224.193.205 '/opt/omarchy32vm/configure.sh'  # fstab, pacman.conf, fontconfig
                                                          # override, users, keys, mkinitcpio
ssh root@46.224.193.205 '/opt/omarchy32vm/apply.sh'      # omarchy-apply-system + GRUB + services
# then the hypr stack:
ssh root@46.224.193.205 'rsync -a /opt/hypr32/stage/usr/ /mnt/o32/usr/ && \
  rsync -a /opt/hypr32/stage/etc/ /mnt/o32/etc/ && arch-chroot /mnt/o32 ldconfig && \
  arch-chroot /mnt/o32 pacman -Sy --noconfirm muparser re2 tomlplusplus libzip'
ssh root@46.224.193.205 'umount -R /mnt/o32; losetup -d /dev/loop0'
```
The stage tree's four missing runtime libs (`libmuparser.so.2`, `libre2.so.10`,
`libtomlplusplus.so.3`, `libzip.so.5`) are the ONLY extra packages the stack needs.

Traps that cost time — read before rebuilding:
- Arch's `pacman.conf` uses TABS around `SigLevel`; a `SigLevel *=` sed misses it
  and every later `pacman -S` fails with "required key missing from keyring".
  Match with `[[:space:]]*`.
- mkinitcpio's `kms` hook drags in every GPU firmware blob (179 MB image, painful
  under TCG). Use `MODULES=(ahci sd_mod ext4 bochs)` and
  `HOOKS=(base udev modconf block filesystems fsck)` → 27 MB.
- `arch-chroot` into the image needs the loop device present for `grub-install`
  (i386-efi) to probe the ESP; `omarchy-refresh-grub` handles the rest.

### Launch / attach

```bash
# launch (detached, survives the shell)
ssh root@46.224.193.205 '/opt/omarchy32vm/launch-vm.sh'
# essence:
#   qemu-system-i386 -M q35 -cpu coreduo -smp 2 -m 2048 \
#     -drive if=pflash,unit=0,readonly=on,file=/usr/share/OVMF/OVMF32_CODE_4M.fd \
#     -drive if=pflash,unit=1,file=/opt/omarchy32vm/OVMF32_VARS.fd \
#     -drive id=hd0,if=none,format=raw,file=/opt/omarchy32vm/disk.img \
#     -device ich9-ahci,id=ahci -device ide-hd,drive=hd0,bus=ahci.0 \
#     -nic user,model=e1000,hostfwd=tcp:127.0.0.1:2222-:22 \
#     -vnc 127.0.0.1:0 -monitor unix:/opt/omarchy32vm/qemu-mon.sock,server,nowait \
#     -serial file:/opt/omarchy32vm/serial.log -display none

# boot progress (login prompt ≈ 90 s under TCG)
ssh root@46.224.193.205 'tail -f /opt/omarchy32vm/serial.log'

# ssh INTO the VM from this machine (ProxyJump through the bench)
VMSSH="ssh -o ProxyJump=root@46.224.193.205 -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
$VMSSH root@127.0.0.1        # or cederik@127.0.0.1; password omarchy, keys installed

# screenshot the VM's REAL display
ssh root@46.224.193.205 'echo "screendump /opt/omarchy32vm/shot.ppm" | \
  socat - unix-connect:/opt/omarchy32vm/qemu-mon.sock; sleep 2; \
  pnmtopng /opt/omarchy32vm/shot.ppm > /opt/omarchy32vm/shot.png'
scp root@46.224.193.205:/opt/omarchy32vm/shot.png ~/hyprdev/shot.png

# stop it
ssh root@46.224.193.205 'pkill -f "qemu-system-[i]386"'
```

### Run the pixman Hyprland on the VM's DRM display

`/usr/local/bin/vm-pixman` in the image is a root wrapper that prepares the
runtime dir and drops to `cederik`:
```bash
$VMSSH root@127.0.0.1 'systemctl stop greetd'   # release DRM master + the VT
$VMSSH root@127.0.0.1 'pkill -f "[H]yprland"; /usr/local/bin/vm-pixman'
# wrapper essence (cwd MUST be /home/cederik, see below):
#   cd /home/cederik
#   install -d -m 700 -o cederik -g cederik /run/user/1000
#   setpriv --reuid=cederik --regid=cederik --init-groups env \
#     HOME=/home/cederik XDG_RUNTIME_DIR=/run/user/1000 LIBSEAT_BACKEND=seatd \
#     HYPRLAND_RENDERER=pixman AQ_FORCE_ALLOCATOR=dumb AQ_DRM_DEVICES=/dev/dri/card0 \
#     /usr/local/bin/Hyprland --config /home/cederik/hyprland-flat.conf

# talk to it
$VMSSH root@127.0.0.1 'SIG=$(ls -t /run/user/1000/hypr | head -1); \
  setpriv --reuid=cederik --regid=cederik --init-groups env HOME=/home/cederik \
    XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$SIG \
    PATH=/usr/local/bin:/usr/bin hyprctl dispatch exec foot'
```

### Reinstall a rebuilt component into a RUNNING VM

```bash
ssh root@46.224.193.205 'arch-chroot /opt/hypr32/root setarch i686 /bin/bash -lc \
  "source /opt/hyprdev/env.sh; ninja -C /opt/hyprdev/src/aquamarine/build -j8 && \
   ninja -C /opt/hyprdev/src/aquamarine/build install"'
ssh root@46.224.193.205 'scp -P 2222 -o StrictHostKeyChecking=no \
  /opt/hypr32/root/usr/local/lib/libaquamarine.so.0.15.0 \
  root@127.0.0.1:/usr/local/lib/libaquamarine.so.0.15.0'
$VMSSH root@127.0.0.1 'ldconfig; pkill -f "[H]yprland"; /usr/local/bin/vm-pixman'
```

### VM gotchas

- **`pkill -f <pattern>` over ssh SELF-MATCHES**: the pattern is in the remote
  `bash -c` command line, so pkill kills its own parent shell and the ssh returns
  nothing at all. Always bracket a character: `pkill -f "[H]yprland"`,
  `pkill -f "qemu-system-[i]386"`.
- **Hyprland inherits the launcher's cwd.** Started from `/root`, every
  `hyprctl dispatch exec` client dies with
  `slave.c: failed to change working directory to /root: Permission denied`,
  which reads like a font/Wayland failure but is not. Launch from the user's home.
- **`/run/user/1000` disappears** when the greetd session ends; `su - cederik`
  after that gives Hyprland no XDG_RUNTIME_DIR and it bails with "couldn't create
  /run/user/1000/hypr/<sig>". Re-create it as root before dropping privileges.
- `ufw` is masked in the image on purpose — it comes up deny-incoming and blocks
  the port-2222 ssh.
