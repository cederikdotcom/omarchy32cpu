# i686 compatibility packages

The libinput and dconf recipes were recovered from `/var/tmp/omarchy-build` on the working MacBook1,1. The libvips recipe was added during convergence to repair the thumbnail pipeline. Build on an ArchLinux32 system with the same dependency versions as the target; do not use an x86_64 build environment and infer target compatibility from the package filename.

| Package | Reason for the rebuild |
|---|---|
| libinput 1.29.1 | Supplies Hyprland's required API and upstream's 32-bit event-frame allocation fix (`ad2a2799`); replaces the unowned 1.29.0 library from the stack tarball |
| dconf 0.49.0 | Links against the target's glib2 2.80.0 rather than requiring symbols absent from that version |
| libvips 8.16.1 | Restores wallpaper thumbnails: the installed 8.11.3 package cannot load `libcfitsio.so.9`, `libtiff.so.5`, or `libimagequant.so.0` |
| ttfx 0.3.2 | Restores the terminal screensaver engine omitted by lite; no ArchLinux32 repository package was available |

The libvips build deliberately enables JPEG, PNG, WebP, and color management and disables optional format loaders. It is suitable for the shipped wallpaper workflow, but is not a full-feature replacement for a general-purpose image-processing installation. It builds against the target's existing libraries and requires no incompatible SONAME symlinks. Build parallelism and LTO are restricted for the physical machine's 1 GB memory budget.

As an unprivileged build user, install `base-devel` and the recipe's dependencies, then run `makepkg --verifysource` and `makepkg --cleanbuild` inside each package directory. `arch-meson` comes from the Arch build tooling. The libinput recipe verifies that its source contains the corrected event-frame allocation. Its upstream test suite is disabled in this recovered recipe; physical device tests remain required. dconf runs its Meson tests during the build.

Install the built packages **after** extracting the desktop stack, then run `ldconfig`, `bash packages/validate-runtime`, and session checks from the [runbook](../docs/runbooks/a1181-install.md). Re-extracting the stack afterwards would overwrite libinput again.

`bash packages/validate-runtime` is the read-only integrity and linker gate. It checks all three packages and actually resolves the dependencies of Hyprland, Quickshell, vipsthumbnail, and dconf-service; installed package names alone do not pass this gate. It does not replace a real thumbnail conversion, authentication, or physical input test.

The tested original binary artifacts have these SHA-256 hashes:

```text
0c0da2a57be39c13841449caa7a8217c596e3cfb13a731a6f55a82749df2201b  libinput-1.29.1-1.1-pentium4.pkg.tar.zst
dcb02727a8e3ce658c1716d1a483969bb088fd06f040a385b4ed149396e46130  dconf-0.49.0-1.1-pentium4.pkg.tar.zst
83be98e78b105b153f63c7d2289629cef19d6dcde9db679e2a72b74d1c5acaa3  libvips-8.16.1-1-pentium4.pkg.tar.zst
```

libvips was built and installed on the physical Mac on 2026-09-05 UTC: seven Meson tests passed, five skipped, none failed. The build took 16m36s wall time at nice 10 with one compile job and a 450 MB cgroup limit; it reached that limit and used up to 359 MB cgroup swap. Keep zram enabled and do not mistake this for a swap-free build. A real 1536×864 WebP-to-JPEG conversion took 1.13s. The caller must use `--output`, not the newer `--path` option unavailable in 8.16.1.

A rebuild is not promised to be byte-identical: record its toolchain, dependencies, logs, and new hash. Binary release hosting/signing and packaging the rest of the desktop stack remain open under issue #11. The recipes are now preserved in git; binaries reside in the Mac's package cache, with a second private recovery copy on the relay.

## Screensaver engine: ttfx

`ttfx/PKGBUILD` pins upstream source commit `7203e354498462064b7c0a89375051f65cf2ce99` (v0.3.2) and verifies the source archive. A native i686 build uses Rust, one compile job and `target-cpu=pentium-m`. Unlike the dynamically linked packages above, a static musl cross-build is also supported, but it must be executed and visually validated on the real Mac before claiming compatibility.

The 2026-09-06 cross-build used Rust 1.94.0, the pinned source's Cargo.lock, and:

```bash
rustup target add i686-unknown-linux-musl
CARGO_TARGET_I686_UNKNOWN_LINUX_MUSL_LINKER=rust-lld \
  RUSTFLAGS='-C target-cpu=pentium-m -C link-self-contained=yes' \
  cargo build --locked --release --target i686-unknown-linux-musl
```

The host also needs a native C linker for Rust build scripts. The resulting `target/i686-unknown-linux-musl/release/ttfx` SHA-256 is `51279425c27118fc9530b1ad41afc539a56f6fca13545e64192a5b0e3a32b81a`. This is a validation reference, not a promise that another toolchain reproduces its bytes.

Transfer the binary and recipe to an unprivileged build directory on the target and verify the hash before packaging. To package an already cross-built binary without installing a native compiler, set `TTFX_PREBUILT` to its absolute path and `TTFX_PREBUILT_SHA256` to its verified hash, then run `makepkg --nodeps`. This exception skips build-tool dependency checks only; the recipe still verifies the source archive and supplied binary. Install the resulting package with `sudo pacman -U ./ttfx-0.3.2-1-*.pkg.tar.zst`. Preserve the artifact and hash for recovery.

Install `socat` with `omarchy-pkg-add socat` on existing lite systems (it is now in the base list). Run `omarchy-launch-screensaver force` in an unlocked desktop with the menu closed and confirm fullscreen animation and clean input dismissal. Foot 1.13 needs `[colors]`, not `[colors-dark]`, in the screensaver config. The 14pt font fits the 81-column logo on the 1280×800 MacBook display; 18pt clips it at the panel's DPI. Missing user artwork falls back to the shipped logo; user customization is not overwritten. Do not use `omarchy-reinstall-configs` to repair this.

Codex is a separate optional application: this repair does not install `mise` or a compatible Codex build. Choosing an unavailable agent now explains the missing installer and leaves the existing default unchanged. A working notification is not proof the agent itself is installed.
