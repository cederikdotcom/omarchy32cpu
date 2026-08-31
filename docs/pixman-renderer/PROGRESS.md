# Pixman renderer - progress

Plan: `/home/claude-user/hyprdev/PLAN.md`. Bench runbook: `/home/claude-user/hyprdev/BENCH.md`.
Branches: Hyprland `pixman-renderer` (base v0.56.2), aquamarine `cpu-backend` (base v0.15.0).
Commit locally only; never push.

Bench: root@46.224.193.205 (see BENCH.md; old 2.28.72.117 retired for builds).

## M0 - compiles, renderer selected, nested/headless session clears to a solid color - REACHED 2026-08-31

aquamarine:
- [x] 1. `Allocator.hpp`: add `AQ_ALLOCATOR_TYPE_SHM`
- [x] 2. `CShmAllocator` / `CShmBuffer` (`allocator/Shm.hpp` + `Shm.cpp`)
- [x] 3. `Backend.cpp` start(): shm-allocator fallback + `AQ_FORCE_ALLOCATOR`
- [x] 4. `Wayland.cpp`: dmabuf optional + wl_shm output buffer path
- [x] 5. Compile check + commit on `cpu-backend` (c04735e)

Hyprland:
- [x] 6. `Renderer.hpp`: add `RT_PIXMAN`
- [x] 7. `pixman/PixmanFormat.hpp/.cpp`
- [x] 8. `pixman/PixmanTexture.hpp/.cpp`
- [x] 9. `pixman/PixmanFramebuffer.hpp/.cpp` (incl. readPixels)
- [x] 10. `pixman/PixmanRenderbuffer.hpp/.cpp`
- [x] 11. `pixman/PixmanElementRenderer.hpp/.cpp` (clear/rect/border/tex all REAL, effects no-op)
- [x] 12. `PixmanRenderer.hpp/.cpp` (+ `CNoopSyncFDManager`)
- [x] 13. `Compositor.cpp`: selection branch + null guard
- [x] 14. Config: `render:renderer` (auto/gl/pixman); flat-mode DEVIATION: no hard-force
      (v0.56 config refactor has no simple programmatic setter); instead effects are
      structurally no-ops in the renderer + a config.reloaded listener logs a WARN
      listing enabled-but-unsupported options. Revisit hard-force upstream-side later.
- [x] 15. Bench: both forks BUILD CLEAN; headless pixman session (no seat, no wayland
      host -> aq headless backend + shm allocator fallback) clears to 0xff225588;
      grim screenshot from INSIDE the session verified 2042708/2073600 px = (34,85,136);
      screenshot saved at ~/hyprdev/pixman-m0-clear.png; committed (Hyprland 0078b961)

## M1 - client windows + borders, damage-driven, screenshot-verified - REACHED 2026-08-31

- [x] 1. Full `draw(CTexPassElement)`: fast path, wlroots transform recipe (NORMAL verified,
      others compiled + log-once warn), bilinear/nearest, alpha mask, OP_SRC promotion
- [x] 2. `draw(CBorderPassElement)` flat rings (gradient -> first stop, log-once);
      `draw(CFramebufferElement)` logs deprecated exactly like GL
- [x] 3. shm ingestion: damage-scoped update verified (foot printing a date line per second
      renders incrementally, no stale regions)
- [x] 4. Asset/text textures verified (notification banners + error overlay text render)
- [x] 5. Cursor verified: software cursor renders via the tex draw (headless has no cursor
      plane); HW-cursor buffer path exercised in the nested run (see session log crash+fix)
- [x] 6. Screencopy end-to-end: grim works INSIDE the session (mirror-FB copy in endRender
      + TO_BUFFER renders into the client shm buffer; "[Screenshare] Copied frame via shm")
- [x] 7. beginFullFakeRender + window close smoke test: no crash, correct after-close frame
- [x] 8. Screenshots (saved in ~/hyprdev/): pixman-m1-foot2.png (two tiled foots, borders,
      active/inactive), pixman-m1-overlap.png (floating overlap + occlusion),
      pixman-m1-xeyes2.png (foot + xeyes), pixman-nested-foot.png (NESTED under sway)
- [x] 9. Damage: TRACE "pixman: begin frame" shows small partial rects (e.g. 702x90) vs
      full-frame only on layout changes; idle = 0 cpu jiffies over 3s (zero-composite)
- [x] 10. Xwayland WORKS unaccelerated (glamor falls back to sw; xeyes renders); committed

BONUS (beyond M1 scope, was the fork acceptance test in BENCH.md): the NESTED harness
works end to end: sway headless+pixman host (wl_shm only, NO dmabuf) -> aquamarine
Wayland backend + shm allocator + wl_shm submission -> pixman Hyprland 1280x720 -> foot
-> grim (harness: /opt/hyprdev/harness-pixman-nested.sh in the chroot). Needed 3
aquamarine fixes + 1 renderer guard (commits e088146 + 26febe72, see session log).

## M2 - boots on the omarchy32cpu VM via DRM - REACHED 2026-08-31

- [x] 1. `AQ_FORCE_ALLOCATOR=dumb` selects `CDRMDumbAllocator` as primary
      (aquamarine 60a765d; also forces `reopenDRMNode(..., allowRenderNode=false)`
      because dumb buffers exist only on the primary card node)
- [x] 2. DRM scanout of dumb-buffer PRIME FBs verified on the VM
      (`DRM Dumb: Allocated a new buffer with primeFD 34 ... 1280x800 ... XR24`,
      three of them = the scanout swapchain; frames reach the QEMU display)
- [x] 3. VM session plumbing: seatd + `LIBSEAT_BACKEND=seatd`, greetd stopped so
      sway releases DRM master and the VT, root wrapper `/usr/local/bin/vm-pixman`
      creates `/run/user/1000` and drops to `cederik` via setpriv
- [x] 4. Full omarchy32cpu VM boot + screenshot + idle CPU number
      (`~/hyprdev/m2-vm-drm.png`, Hyprland idle = 1 jiffy / 20 s = **0.05 %**)
- [x] 5. 32-bit review pass: covered by the i686 build phase; the whole stack is
      built `-m32` and the new renderer/allocator code compiles clean for i686
      (Hyprland 4a2b510e + 63417a30 were the only 32-bit fixes needed, both
      language-level, no size assumptions in the pixman/dumb paths)

NOT done (deliberately out of scope, see "optional polish" below): output
transforms on real hardware, hardware cursor planes, single-pixel-buffer.

## Session log

- 2026-08-31: Build host migrated to root@46.224.193.205 (old bench 2.28.72.117 retired for builds); chroot environment rebuilt and verified, both forks compile, stock-Hyprland DRM baseline harness passes (see BENCH.md).

- 2026-08-31 (implementation session 1): M0 AND M1 REACHED, both verified on the bench.
  Commits: aquamarine `cpu-backend` c04735e (shm allocator + wl_shm wayland path, was the
  WIP from bench bring-up) + e088146 (nested fixes); Hyprland `pixman-renderer` 0078b961
  (the whole renderer) + eac00c82 (damage trace) + 26febe72 (endRender guard). NOT pushed.

  What works (all screenshot- or trace-verified, artifacts in ~/hyprdev/):
  - headless GPU-less session (no seat, no host): aq headless backend -> shm-allocator
    fallback -> pixman renderer; solid clear; foot content; borders; floating overlap;
    software cursor; notifications/error overlay text; grim inside the session;
    Xwayland/xeyes (sw glamor fallback); window close; idle composites NOTHING
    (0 jiffies/3s); partial-damage frames in the TRACE log.
  - nested session under sway headless+pixman (wl_shm ONLY, no dmabuf): full stack works.

  Bugs found + fixed on the way (in the commits above):
  1. ImageCopyCapture null-deref: PROTO::linuxDma->getMainDevice() with dmabuf never
     bound. Guarded both call sites (shm-only constraints). Upstreamable on its own.
  2. Clear color: base drawClear premultiplies via CM convertColor; a background color
     with alpha 0x00 (like the old flat.conf 0x225588) clears BLACK under GL too - NOT a
     renderer bug; flat.conf now uses 0xff225588. Pixman clear writes the raw color
     (mirrors glClear), no premultiplication.
  3. Screencopy black: grim reads the monitor MIRROR FB which only GL's end-blit
     maintained -> pixman endRender now copies target->mirrorFB (needsACopyFB) and marks
     it updated.
  4. aq Wayland backend vs sway host: (a) bound xdg_wm_base v6 while sway offers v5 =
     fatal protocol error killing the host connection (clamp binds to offered version);
     (b) initial surface commit never flushed without dmabuf (host never configures);
     (c) first configure can arrive before Hyprland's monitor state listener exists ->
     size lost forever; the output now advertises the configured size as its sole
     preferred mode so the mode-retry picks it up.
  5. renderHWCursorBuffer calls endRender without checking beginFullFakeRender's result
     -> popped empty transform stack = SEGV. endRender now drops the frame if begin
     didn't complete. Also CShmBuffer defaults DRM_FORMAT_INVALID -> ARGB8888 (cursor
     swapchain has no explicit format and shm buffers have no dmabuf attrs to infer from).

  Deviations from PLAN.md (recorded):
  - Plan sect. 8 flat-mode HARD-FORCE of config values: NOT implemented. The v0.56
    config refactor (Config::IConfigManager, typed CValues) has no simple programmatic
    setter; instead every effect path is a structural no-op in the renderer (blur/
    shadow/glow/matte draws empty, rounding ignored, no screen shader or CM LUT stage
    exists at all) and a config.reloaded listener WARNs listing enabled-but-unsupported
    options. Good enough for M0/M1; revisit if upstreaming.
  - M1 task 11 said tex/border as skeletons for M0; they were implemented fully at M0
    time (crib was ready), which is why M1 followed in the same session.
  - Single-pixel-buffer protocol untested explicitly (no client at hand); it uses the
    same createTexture(drmFormat, pixels,...) path foot exercises heavily.

  Bench workflow notes for the successor (also see BENCH.md):
  - harness scripts in the chroot: /opt/hyprdev/harness-pixman-headless.sh (M0 solid
    clear), harness-pixman-m1.sh (foot/overlap/xeyes/idle), harness-pixman-m1b.sh
    (damage trace + xeyes), harness-pixman-nested.sh (nested acceptance).
  - arch-chroot invocations are separate PID namespaces: processes started in one
    cannot be killed/ptraced from another; keep launch+inspect+kill in ONE bash -lc.
    gdb attach across invocations fails with "ptrace: No such process".
  - rsync --delete wipes Hyprland subprojects/ -> rerun `git submodule update --init
    --recursive` in the chroot before cmake/ninja (harness commands above do it).

  EXACT NEXT STEPS (M2, in PLAN.md order):
  1. aquamarine Backend.cpp: AQ_FORCE_ALLOCATOR=dumb -> CDRMDumbAllocator as
     primaryAllocator when a DRM impl exists (currently only "shm" is handled).
  2. Verify DRM scanout of dumb-buffer PRIME FBs: bench has virtio-gpu card1
     (connector Virtual-1); run harness-drm.sh style (seatd + AQ_DRM_DEVICES=
     /dev/dri/card1) with HYPRLAND_RENDERER=pixman + AQ_FORCE_ALLOCATOR=dumb.
  3. Then the omarchy32cpu VM boot per PLAN.md M2.3-5.
  4. Consider hyprlock/hyprpaper smoke tests (assets/lockscreen paths) and a
     rotated-output test (transform recipe is unverified beyond NORMAL).

- 2026-08-31 (implementation session 2): **M2 REACHED.** The i686 pixman Hyprland
  runs on the DRM display of a freshly built omarchy32cpu VM on the bench.
  Commit: aquamarine `cpu-backend` **60a765d** (NOT pushed). Hyprland fork needed
  NO change for M2 (HEAD stays 63417a30).

  ### Evidence (all from the VM, artifacts in ~/hyprdev/)
  - `m2-vm-drm.png` - QEMU `screendump` of the VM's ACTUAL display: foot at
    1260x780 with its 2px blue active border, the 0xff225588 pixman clear showing
    through the gaps, the shell prompt `[cederik@omarchy32cpu ~]$` with its cursor
    block, and the software mouse cursor. Inspected: real rendered content.
  - `m2-vm-drm-nofoot.png` - the same session before foot: solid clear + cursor
    (proves the clear path reaches scanout on its own).
  - `m2-vm-hyprland.log` - the runtime log. Proof lines:
    ```
     40: drm: Starting backend for /dev/dri/card0, with driver bochs-drm
     59: drm: Connector Virtual-1 connected
     90: drm: gpu /dev/dri/card0 becomes primary drm
     97: AQ_FORCE_ALLOCATOR: using a drm dumb (cpu) allocator
    159: Renderer: pixman (software)
    201: Creating the HyprRenderer (pixman)!
    405: DRM Dumb: Allocated a new buffer with primeFD 34, size 1280x800, format XR24
    ```
    `hyprctl monitors` -> `Monitor Virtual-1 (ID 0) 1280x800@74.994`.
  - **Idle CPU: 0.05 %** (1 jiffy over 20 s, HZ=100, `/proc/<pid>/stat`). The
    zero-composite-at-idle property from M1 carries over to the DRM path intact.

  ### The two engineering fixes (aquamarine 60a765d)
  1. `src/backend/Backend.cpp` - `AQ_FORCE_ALLOCATOR=dumb` was ACCEPTED BUT
     SILENTLY IGNORED: only `"shm"` was handled, everything else fell through to
     `CGBMAllocator`. On bochs-drm that means GBM against a device with no render
     node and no gallium driver. Now `dumb` selects `CDRMDumbAllocator`, and
     `reopenDRMNode()` is called with `allowRenderNode=false` in that mode because
     dumb buffers exist ONLY on the primary card node.
  2. `src/backend/drm/DRM.cpp` (`initMgpu()` + `onReady()`) - with a non-GBM
     primary allocator there is no EGL/GBM pipeline at all: the compositor renders
     straight into a mappable scanout buffer and `shouldBlit()` is false without a
     secondary GPU. Clear `rendererRequired` and return early, exactly as the
     existing **evdi** path already does. Before the fix, every commit retried
     `CDRMRenderer::attempt()`: the log filled with `MESA-LOADER: failed to open
     bochs-drm` + `eglQueryDeviceStringEXT EGL_BAD_PARAMETER` +
     `drm: initMgpu: no renderer` + `Failed to update renderer state for Virtual-1
     on applyCommit` on EVERY frame. Non-fatal (the picture was already correct)
     but an EGL device probe per frame is pure waste on a 2006 CPU.
     After: MESA-LOADER count 0, initMgpu errors 0, picture unchanged.

  ### The VM (built from scratch, ~35 min)
  The old server 2.28.72.117 was probed ONCE for its existing image as instructed
  and refused the connection at the handshake ("Connection reset by peer"), so a
  fresh omarchy32cpu was built on the bench. Full recipe in BENCH.md; summary:
  20G raw GPT (512M FAT32 ESP + ext4 root) -> `pacstrap -C
  /opt/hypr32/pacman-i686.conf` of `install/omarchy-base.packages` -> fontconfig
  override -> user cederik -> `omarchy-apply-system --install-user cederik
  --first-install` -> `omarchy-refresh-grub` (BOOTIA32.EFI, i386-efi) -> boots
  under IA32 OVMF in `qemu-system-i386 -M q35 -cpu coreduo -smp 2 -m 2048`.
  greetd comes up and autologins into sway; ufw is masked so the bench ssh works.

  ### Gotchas found this session (all cost real time, all avoidable)
  - `pkill -f qemu-system-i386` / `pkill -f Hyprland` run over ssh SELF-MATCH: the
    pattern appears in the remote `bash -c` command line, so pkill kills its own
    parent shell and the ssh dies with no output. Always bracket a character:
    `pkill -f "[H]yprland"`.
  - `genfstab`/`pacstrap`'s Arch pacman.conf uses TABS around `SigLevel`, so a
    `SigLevel *=` sed silently misses it and every later `pacman -S` in the image
    dies with "required key missing from keyring". Match with `[[:space:]]*`.
  - mkinitcpio's `kms` hook pulls EVERY GPU firmware blob: a no-autodetect image
    came to **179 MB** (very slow to load under TCG). Dropping `kms` and putting
    `bochs` in `MODULES=` gives **27 MB** and boots fine.
  - Hyprland inherits the launching shell's cwd, so `hyprctl dispatch exec foot`
    from a wrapper started in `/root` made foot die with
    `slave.c:332: failed to change working directory to /root: Permission denied`.
    The wrapper now `cd /home/cederik` first. This looks exactly like a font or
    Wayland failure in the log; it is not.
  - `/run/user/1000` is destroyed when the greetd session ends, so `su - cederik`
    afterwards has no XDG_RUNTIME_DIR and Hyprland bails with "couldn't create
    /run/user/1000/hypr/<sig>". The root wrapper re-creates it with `install -d`.

  ### EXACT NEXT STEPS (post-M2)
  1. **Real hardware.** Everything so far is bochs-drm under TCG. The MacBook1,1
     path is i915/GMA 950 - a real KMS driver with tiling, a cursor plane and
     possibly no linear XR24 scanout. Boot the image on the A1181 and re-run the
     same three proofs (log lines, screenshot, idle CPU).
  2. **CPU comparison vs llvmpipe.** M2 measured pixman idle only. Get the
     interesting number: pixman vs stock-Hyprland-on-llvmpipe under the SAME load
     (foot scrolling / window drag) in the same VM. The llvmpipe baseline harness
     already exists on the bench (`harness-drm.sh`).
  3. **Optional polish still open** (deliberately skipped in M2): output
     transforms beyond NORMAL, hardware cursor planes (currently software cursor
     on the tex path), single-pixel-buffer protocol.
  4. **Upstreamability.** Two commits in the aquamarine fork are independent of
     the pixman renderer and could go upstream alone: the ImageCopyCapture
     null-deref guard (from M1) and the `initMgpu` cpu-allocator early-out here.
