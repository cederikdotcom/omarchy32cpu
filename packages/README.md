# i686 compatibility packages

These recipes were recovered from `/var/tmp/omarchy-build` on the working MacBook1,1. They restore pacman ownership of two libraries required by the desktop. Build on an ArchLinux32 system with the same dependency versions as the target; do not use an x86_64 build environment and infer target compatibility from the package filename.

| Package | Reason for the rebuild |
|---|---|
| libinput 1.29.1 | Supplies Hyprland's required API and upstream's 32-bit event-frame allocation fix (`ad2a2799`); replaces the unowned 1.29.0 library from the stack tarball |
| dconf 0.49.0 | Links against the target's glib2 2.80.0 rather than requiring symbols absent from that version |

As an unprivileged build user, install `base-devel` and the recipe's dependencies, then run `makepkg --verifysource` and `makepkg --cleanbuild` inside each package directory. `arch-meson` comes from the Arch build tooling. The libinput recipe verifies that its source contains the corrected event-frame allocation. Its upstream test suite is disabled in this recovered recipe; physical device tests remain required. dconf runs its Meson tests during the build.

Install the built packages **after** extracting the desktop stack, then run `ldconfig`, `pacman -Qkk libinput dconf`, and linker/session checks from the [runbook](../docs/runbooks/a1181-install.md). Re-extracting the stack afterwards would overwrite libinput again.

The tested original binary artifacts have these SHA-256 hashes:

```text
0c0da2a57be39c13841449caa7a8217c596e3cfb13a731a6f55a82749df2201b  libinput-1.29.1-1.1-pentium4.pkg.tar.zst
dcb02727a8e3ce658c1716d1a483969bb088fd06f040a385b4ed149396e46130  dconf-0.49.0-1.1-pentium4.pkg.tar.zst
```

A rebuild is not promised to be byte-identical: record its toolchain, dependencies, logs, and new hash. Binary release hosting/signing and packaging the rest of the desktop stack remain open under issue #11. The recipes are now preserved in git; the original binaries still reside in the Mac's package cache.
