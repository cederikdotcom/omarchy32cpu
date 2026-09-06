# MacBook lite launcher and screensaver repair — 2026-09-06

The user reported that choosing Codex did nothing and that screensavers did not work. We prioritized a repair on the physical MacBook1,1, not an upstream PR. These failures were primarily consequences of lite package omissions and the older terminal, not evidence of another renderer failure.

## Causes and repair

- `xdg-terminal-exec` was omitted, but the floating presentation, TUI and screensaver launchers still required it. They now use the installed `foot` when the dispatcher is absent.
- `mise` and Codex were both absent. The agent selector now explains the missing installer, exits without changing the default, and opens a persistent error terminal if notifications are unavailable. This does **not** install or validate Codex on i686.
- Presentation commands now preserve their failure status and wait for a key after failure rather than immediately disappearing. Cancellation status 130 remains exempt.
- Both `socat` and `ttfx` were absent. `socat` was restored to the shared base package list and installed from ArchLinux32. `ttfx` 0.3.2 was cross-built from pinned upstream source, packaged with makepkg and installed as a pacman-owned binary. The [recipe and reproduction instructions](../../packages/README.md#screensaver-engine-ttfx) preserve the build procedure.
- Foot 1.13 rejects `[colors-dark]`; the screensaver config now uses `[colors]`. The default 18pt branding also clipped on the 1280×800 panel at its DPI, so this config uses 14pt.
- User screensaver branding had never been seeded. The runner falls back to the shipped logo without overwriting customization; branding commands create their directory before editing/resetting.
- Missing or failed effect processes now stop instead of retrying indefinitely. The frame-rate target is 30 rather than 120 for the physical machine's CPU budget.

## Physical validation

Runtime changes were fast-forwarded into `/usr/share/omarchy`; Hyprland PID 11049 and Quickshell PID 11089 were preserved. No compositor restart, partition change, upstream runtime merge or credential change was needed.

`ttfx --version` executed successfully on i686. The installed packages are `socat 1.7.4.4-1.0` and `ttfx 0.3.2-1`. The latter artifact is `ttfx-0.3.2-1-pentium4.pkg.tar.zst`, SHA-256 `0d6d36f2de4e9c190e6405da477728d2621688c678bc5c329a79586bc0bea6b1`. The original package remains in `/var/tmp/omarchy-ttfx-20260906` on the Mac, with a hash-matching recovery copy under `/var/tmp/omarchy32-convergence-artifacts` on the relay.

The screensaver mapped as `org.omarchy.screensaver`, reported size 1280×800 and fullscreen state 2, and ran a real `ttfx` process. Escape dismissed it and left no effect process. A first diagnostic launch exited because the still-open menu owned focus; closing the menu allowed the normal launcher to work. This was a test-state problem, not a reason to remove the runner's focus-loss exit behavior.

Screenshots exposed and verified the font correction. A six-second, 2 FPS sampled full-screen recording was reviewed as extracted frames; `/tmp/omarchy-screensaver-final.mp4` and `/tmp/omarchy-screensaver-review.jpg` remain on the Mac as temporary evidence. This proves visible animation, not sustained 30 FPS performance. The repo's visual-verification guide led to the live capture and the additional font correction. No claim is made about every random effect or physical mouse-button dismissal.

A deliberately failing presentation command mapped an 875×600 floating terminal and displayed a readable failure prompt. The screenshot was inspected for clipping and the test terminal was dismissed by a key. The actual desktop D-Bus had no `org.freedesktop.Notifications` service, so the Codex error also needed the terminal fallback; merely attempting a notification would still have looked silent on this session.

Focused launcher/default-agent tests and all 116 CLI checks passed. The full shell run passed 213 of 222 test files, with nine failures: missing host tools (`magick`, `xkbcli`, `update-desktop-database`), the existing `omarchy-remove-ai-openclaw` command-helper style violation, current-upstream divergence classification, and about-animation, legacy-power migration, root-owned Plymouth fixture and update-lock checks. This is not a green full-suite claim; none of those unrelated files was changed to hide its failure. The focused new lite tests passed again after adding the notification fallback. The divergence ownership report passes against the last synchronized upstream baseline `36e56f4f`; the separately tracked nine-commit upstream backlog was not merged as part of this repair.

## Remaining work and recovery

- A compatible installer and Codex build are still needed before Codex can run locally. Do not label the visible-error fix as a working Codex installation.
- The absent desktop notification service needs its own diagnosis. The agent failure fallback does not restore notifications globally.
- Signed/public compatibility artifacts and automatic fresh-install inclusion of `ttfx` remain packaging work under issue #11. Until then, the runbook explicitly requires the compatibility package; `socat` is part of the normal base list.
- To undo runtime script/config changes, use a reviewed Git revert, retaining existing user configuration. Keep the package artifacts before changing packages. Do not re-extract the old desktop stack or run the destructive configuration reset as a repair.

These changes are owned by `packages-core` (#8), `theming-foot` (#10), `no-package-repo` (#11), and fork documentation in the divergence registry. An upstream PR is deferred until the fork-specific package omissions and runtime behavior are settled.
