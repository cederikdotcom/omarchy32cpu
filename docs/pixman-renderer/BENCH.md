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
