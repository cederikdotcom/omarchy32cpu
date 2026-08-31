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

## M2 (stretch) - boots on the omarchy32cpu VM via DRM

- [ ] 1. `AQ_FORCE_ALLOCATOR=dumb` selects `CDRMDumbAllocator` as primary
- [ ] 2. DRM scanout of dumb-buffer PRIME FBs verified on the VM
- [ ] 3. VM session plumbing (seatd/logind, libinput, VT, flat config)
- [ ] 4. Full omarchy32cpu VM boot + screenshot + CPU numbers vs llvmpipe baseline
- [ ] 5. 32-bit review pass on new code (no size assumptions)

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
