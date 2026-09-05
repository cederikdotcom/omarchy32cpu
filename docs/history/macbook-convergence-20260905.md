# MacBook1,1 convergence run — 2026-09-05 UTC

This run uses the physical MacBook at the recorded SSH endpoint, starting from repository `21d1f16c` and the repaired libinput/dconf baseline. Changes were developed on `converge-macbook-20260905` for integration into `main`.

## Upstream integration

Merged all six commits through `upstream/quattro` at `36e56f4f`. The conflicts were the minimal package selection and the optional Chromium native-host test. The fork retains its minimal package selection; upstream's Brave Origin support, OpenClaw commands, menu changes, foot scroll tuning, and migration-test cleanup are integrated. The CLI suite and focused browser, agent, menu, config, systemd, hardware, and divergence checks passed on the controller.

The physical checkout was fast-forwarded and Hyprland reloaded successfully, with no configuration errors and the original compositor and Quickshell processes still running. The desktop and root menu were captured and visually inspected. This is a live-session validation, not a new cold-boot or manual-authentication result.

## Reduce deletions without adding running services

Restored 30 upstream Plymouth/SDDM source files unchanged: Plymouth commands, assets, configuration source, its publication tests, and SDDM theme assets. The Mac still uses greetd, and Plymouth is not installed or added to the initramfs. Style > Unlock is guarded by the presence of the Plymouth executable and the installed Omarchy theme. Registry entry #6 is resolved because its source divergence is gone; optional package selection remains tracked under #8.

The complete upstream Plymouth publisher test passed in a disposable checkout with normal directory permissions. It exercises logo input handling, destination ownership and symlink checks, refresh, reset, and failure cleanup; the test's simulated publisher rejects the development checkout's group-writable directories, so those checks were run from an archived tree under `/tmp` instead.

## Correct the hardware and package evidence

- Linux reports `MemTotal: 990688 kB`: approximately 1 GB usable RAM on this physical machine. The earlier 2 GB figures belong to the VM and the machine's supported capacity.
- Before the rebuild workload, uptime was nearly 14 hours; Hyprland and Quickshell had survived over 11 hours. Quickshell RSS was about 142 MB, Hyprland about 45 MB, memory available 499 MB, and zram swap used 125 MB. These are a baseline sample, not a controlled memory comparison.
- The libinput and dconf PKGBUILDs were recovered from `/var/tmp/omarchy-build`, preserved under `packages/`, and source checksums validated on the Mac. Both installed packages passed `pacman -Qkk`.
- The recovered libinput source contains the corrected event-frame allocation guarded by its recipe: `max_size * sizeof(*frame->events) + sizeof(*frame)`. The recipe identifies upstream `ad2a2799` as the 32-bit heap-overflow fix. This is concrete input-library evidence beyond the earlier allocator backtraces; it does not establish that every historical crash had one cause.
- The original libinput/dconf binaries were copied off the Mac to the relay's private `/var/tmp/omarchy32-convergence-artifacts` directory and their hashes matched the recorded baseline. That provides a second recovery copy, but is not a signed release repository.
- `vipsthumbnail` could not start: installed libvips 8.11.3 required missing `libcfitsio.so.9`, `libtiff.so.5`, and `libimagequant.so.0`. ImageMagick was also unusable because libraqm required a missing HarfBuzz symbol. A fallback to ImageMagick would not repair this target.

## Native thumbnail repair

Built libvips 8.16.1 directly on the Mac with JPEG/PNG/WebP/color-management support and optional format loaders disabled. The build completed in 16m36s wall time: seven Meson tests passed, five skipped, zero failures. One compile job, disabled LTO, nice 10, and a 450 MB cgroup limit bounded the workload; it reached the limit and used up to 359 MB swap. Hyprland and Quickshell survived with their original PIDs. This is a bounded build result, not evidence that the build needs no swap.

Installed package SHA-256: `83be98e78b105b153f63c7d2289629cef19d6dcde9db679e2a72b74d1c5acaa3`. Package integrity reports zero altered files; all four binaries in `packages/validate-runtime` pass dependency resolution. The original libvips 8.11.3 package remains in `/var/cache/pacman/pkg` for rollback. Installed size decreased by 5.69 MiB, reflecting the intentionally smaller codec selection.

The real wallpaper converted to a 1536×864 JPEG in 1.13 seconds. Testing the actual caller then caught a second defect: upstream's `--path` option is absent in 8.16.1. The command now uses `--output`, supported by both the [8.16.1 implementation](https://raw.githubusercontent.com/libvips/libvips/v8.16.1/tools/vipsthumbnail.c) and [newer libvips](https://raw.githubusercontent.com/libvips/libvips/master/tools/vipsthumbnail.c). The cache regression test rejects `--path` and passes all five cache/lock/retry cases. This two-file compatibility change is accounted under issue #9; no extra QML fork was needed.

The corrected caller generated all eight current-theme JPEG previews in 5.16s on the Mac. Its new package was copied to the private relay recovery directory and the checksum matched. Final visual inspection confirmed a clean password-entry lock screen; the session had locked during the long build, so the rebuilt picker's appearance remains unverified until the user unlocks normally. No authentication bypass was attempted. Temporary picker/terminal checks were closed or bounded by timeouts.

The final tracked-tree comparison at upstream `36e56f4f` has zero unmerged upstream commits and 145 divergent paths. This includes fork documentation, infrastructure, and new reproducibility material, not just runtime patches; it also excludes the out-of-tree Hyprland/aquamarine changes. Plymouth's own entry now has zero divergent files.

## Recovery and remaining gates

The pre-change configuration archive is `/root/omarchy-before-convergence-20260905.tar.gz`, SHA-256 `c940b6e6924dde9afa19123a86b157b38744479b0278c16d66e5e97652c2d991`. It contains the login, libinput, pacman, and user configuration paths available at capture time. It is not a full disk image or a package rollback snapshot. The original repository baseline remains in git history; no disk partition, bootloader, or firewall changes were made in this run.

Physical left/right-click confirmation, manual credential entry, repeated cold boots, suspend/resume, audio, and brightness keys remain separate acceptance gates. The broad MacBook input guard remains in place until hands-on events justify narrowing it. Replacing greetd, changing the session manager, or reverting the CPU renderer is not justified by a file-count improvement alone.
