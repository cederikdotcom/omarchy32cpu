# Runbook: omarchy32-test cloud bench

A Hetzner Cloud server that stands in for the MacBook1,1 during
development. Created 2026-08-30. Delete it when the port ships.

- Server: `omarchy32-test`, cpx22 (2 vCPU x86, 4 GB), nbg1, Hetzner
  project context `cederik`, root@2.28.72.117 (key: neoremote).
- No nested KVM on Hetzner Cloud; the VM runs in QEMU TCG (software
  emulation), which is close to 2006-laptop speed. The chroot runs i686
  natively at full speed.

## Environment 1: i686 chroot (fast porting loop)

- Path: `/opt/omarchy32/chroot32`, bootstrapped with Debian's pacstrap
  against `pacman32.conf` (Architecture = i686, archlinux32 mirror).
- Enter: `systemd-nspawn --personality=x86 -q -D /opt/omarchy32/chroot32
  bash` (personality makes `uname -m` report i686).
- SigLevel is `Never` in the chroot pacman.conf (throwaway bench; a
  stale mirror signature on libvterm forced it). The real install uses
  the keyring.
- The Lite desktop core is installed. The rebuilt
  `fontconfig-2:2.18.3-2-i686.pkg.tar.zst` lives in
  `/home/tester/fontconfig/` inside the chroot; without it sway dies on
  a fontconfig symbol (see the gap analysis).
- Headless sway smoke test (run as user `tester`):
  `install -d -o tester -g tester /run/user/1000`, then as tester with
  `XDG_RUNTIME_DIR=/run/user/1000 WLR_BACKENDS=headless
  WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 SWAYSOCK=/run/user/1000/sway.sock
  sway -d`, then `swaymsg -t get_outputs`. Validated 2026-08-30.

## Environment 2: QEMU VM with 32-bit UEFI (boot-chain rehearsal)

- Path: `/opt/omarchy32/`. Scripts: `launch-uefi32.sh` (OVMF32 firmware,
  the Apple-EFI stand-in) and `launch-bios.sh` (CSM stand-in).
- VM models the MacBook1,1: `qemu-system-i386 -cpu coreduo -smp 2
  -m 2048`, AHCI disk `macbook11.qcow2` (20 G), e1000 NIC.
- ISO: `archlinux32-2024.07.10-i686.iso` in the same directory. Attach
  with `ISO=/opt/omarchy32/archlinux32-2024.07.10-i686.iso
  ./launch-uefi32.sh`.
- Console: serial on stdio, VNC on 127.0.0.1:5900 (tunnel with
  `ssh -L 5900:127.0.0.1:5900 root@2.28.72.117`), QEMU monitor on
  `/opt/omarchy32/qemu-mon.sock`.
- Purpose: rehearse the full install including GRUB i386-efi as
  `BOOTIA32.EFI` against real 32-bit UEFI firmware before touching the
  Mac. DONE 2026-08-30: boots to sway on the display.
- The rehearsed system lives in `/opt/omarchy32/disk.img` (raw, 20 G
  sparse), built by `build-image.sh` + `configure-image.sh` in the same
  directory (pacstrap Lite core, greetd initial_session into
  sway/pixman, GRUB removable install; grub-install must run via
  arch-chroot, not nspawn, so it can see the loop device). Login
  cederik/omarchy or root/omarchy, serial console on ttyS0.
- Boot it: the detached qemu-system-i386 command in the shell history
  of this repo's rehearsal, or adapt launch-uefi32.sh to
  `-drive ...file=disk.img,format=raw`. Screenshot: `echo screendump
  /opt/omarchy32/shot.ppm | socat - unix-connect:/opt/omarchy32/qemu-mon.sock`.

## Costs and teardown

- cpx22 bills hourly, about 5 EUR/month if left running.
- Teardown when done: `HCLOUD_CONTEXT=cederik hcloud server delete
  omarchy32-test`. Nothing on it is unique; everything is scripted here.
