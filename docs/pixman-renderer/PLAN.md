# Pixman (CPU) renderer for Hyprland - implementation plan

Goal (omarchy32cpu #1): Hyprland composites with zero GPU and zero GL, flat mode only
(animations off, blur off, rounding 0, shadows off), damage-driven blitting in the style
of wlroots' pixman renderer. NOT full-frame software GL (llvmpipe).

Workspaces:
- `~/hyprdev/Hyprland`, branch `pixman-renderer`, base `v0.56.2` (efb50993)
- `~/hyprdev/aquamarine`, branch `cpu-backend`, base `v0.15.0` (783bfd9)
- Reference: `~/hyprdev/wlroots-ref` (pixman renderer crib, commit bd75ebf)
- Bench: root@2.28.72.117 (Debian 13 x86_64, no GPU). Commit locally only, never push.

All file:line references verified against the checked-out trees on 2026-08-31.

---

## 1. Seam strategy: runtime branching over the EXISTING interfaces

Decision: **no new interface extraction**. Hyprland v0.56.2 already has the renderer
abstraction we need (landed in the v0.55 refactor series, PRs #13437/#13438/#13471/
#13485/#13488/#13631):

- `Render::IHyprRenderer` (`src/render/Renderer.hpp`) with `eType { RT_GL, RT_VK }` and
  a 3447-line renderer-agnostic base class (`Renderer.cpp`) that owns all frame
  orchestration, damage, and scene walking.
- `Render::IElementRenderer` (`src/render/ElementRenderer.hpp`) with 9 pure-virtual
  `draw(WP<C*PassElement>, const CRegion& damage)` overloads; the base class does all
  geometry/UV/clip math.
- Abstract `ITexture` / `IFramebuffer` / `IRenderbuffer` / `ISyncFDManager` with GL
  concretes isolated in `src/render/gl/`.

So the pixman renderer is a third concrete implementation next to
`Render::GL::CHyprGLRenderer`, selected at the single instantiation point. This is the
least invasive option and the one upstream anticipated (the `RT_VK` placeholder proves
the enum is meant to grow).

### Every concrete-GL call site outside `src/render/{gl/,OpenGL.*,GLRenderer.*}` and its seam

Verified by `grep -rn g_pHyprOpenGL src` (excluding GL renderer files). This is the
complete list; all EGL/`makeEGLCurrent`/`g_pShaderLoader` use is confined to GL files.

| Site | Today | Seam |
|---|---|---|
| `src/Compositor.cpp:693-696` (STAGE_BASICINIT) | unconditional `g_pHyprOpenGL = makeUnique<CHyprOpenGLImpl>(); g_pHyprRenderer = makeUnique<CHyprGLRenderer>();` | **The one real branch.** Read selection (sect. 8); pixman mode: skip `g_pHyprOpenGL` entirely (its ctor RASSERTs on EGL at `OpenGL.cpp:290+` and would abort on a GPU-less box), construct `CHyprPixmanRenderer`. |
| `src/Compositor.cpp:591` | `g_pHyprOpenGL->destroyMonitorResources(m)` UNGUARDED in `cleanup()` | Add `if (g_pHyprOpenGL)` null guard (one line). |
| `src/Compositor.cpp:615` | `g_pHyprOpenGL.reset()` | Safe on a null UP; no change. |
| `src/render/Renderer.cpp:226-227` `glBackend()` | returns the global | Keep; it returns null in pixman mode and every caller is guarded (below). |
| `src/output/Monitor.cpp:104,412,1065` | `if (g_pHyprRenderer->glBackend()) ... destroyMonitorResources(...)` | Already null-guarded; no change. (`CMonitorResources` offload work buffers are a GL-only concept; pixman renders direct to the target buffer.) |
| `src/helpers/SystemInfo.cpp:232-234` | `if (g_pHyprOpenGL) { explicit sync / GL ver strings }` | Guarded; optionally add an `else` printing `Renderer: pixman (software)`. |
| `src/debug/HyprCtl.cpp:1997` | `if (g_pHyprOpenGL && ... reloadShaders(...))` | Guarded; `CHyprPixmanRenderer::reloadShaders` returns false anyway. |

Shared-header GL leftovers we tolerate (do NOT refactor; header comment already says
"TODO move to GLTexture"): `ITexture::setTexParameter(GLenum, GLint)` (implement as
no-op), `ITexture::m_texID/magFilter/minFilter` (ignore; pixman filter choice comes from
the pass element's `useNearestNeighbor`). GL headers stay linked; we just never create a
context. Upstream-acceptability: the diff outside `src/render/pixman/` is ~5 small
hunks (enum value, one branch, one null guard, config value, protocol no-ops already
virtual), which is the shape upstream could take.

### Protocol gating comes free (no code change)

- `src/managers/ProtocolManager.cpp:258` binds linux-dmabuf + MesaDRM only if
  `g_pHyprRenderer->getDRMFormats()` is non-empty. Pixman returns `{}` so **dmabuf is
  never advertised**; `src/protocols/types/DMABuffer.cpp` never runs; clients fall back
  to wl_shm. Same structural rejection wlroots uses (`render/pixman/renderer.c:201` +
  `render/wlr_renderer.c:87`: return no formats for the dmabuf cap and the global is
  never created).
- `ProtocolManager.cpp:249` binds DRM syncobj only if `explicitSyncSupported()`; pixman
  returns false.
- Direct scanout (`attemptDirectScanout`) is dmabuf-only and degrades silently.

---

## 2. New files

### Hyprland (`pixman-renderer` branch)

Mirrors the GL layout (`GLRenderer.hpp/.cpp` at top level, concretes under `gl/`).
CMake uses `file(GLOB_RECURSE SRCFILES "src/*.cpp")` (`CMakeLists.txt:295`), so new
files build without build-system edits; `pixman-1` is ALREADY a link dependency
(`CMakeLists.txt:279`, hyprutils' `CRegion` wraps `pixman_region32`) - no new deps.

| File | Contents |
|---|---|
| `src/render/PixmanRenderer.hpp/.cpp` | `Render::Pixman::CHyprPixmanRenderer : IHyprRenderer` plus a private no-op `CNoopSyncFDManager : ISyncFDManager`. Full virtual surface in sect. 3. |
| `src/render/pixman/PixmanFormat.hpp/.cpp` | DRM fourcc <-> `pixman_format_code_t` table, cribbed from wlroots `render/pixman/pixel_format.c`: [AX]RGB8888, [AX]BGR8888, RGB[AX]8888, BGR[AX]8888, RGB565, 2101010 variants. Helper `pixmanFormatFromDRM(uint32_t)`. |
| `src/render/pixman/PixmanTexture.hpp/.cpp` | `CPixmanTexture : ITexture`. Owns its pixels (`std::vector<uint8_t>` + `pixman_image_create_bits` over them). `allocate(size, drmFormat)`; `update(drmFormat, pixels, stride, damage)` copies ONLY the damage rects row-by-row (Hyprland releases the client shm buffer right after commit - `src/protocols/core/Compositor.cpp:664` - so unlike wlroots we must copy, we cannot wrap the client mmap); `bind/unbind/setTexParameter` no-ops; `getImage()` accessor. |
| `src/render/pixman/PixmanFramebuffer.hpp/.cpp` | `CPixmanFramebuffer : IFramebuffer`. `internalAlloc` = owned pixel store + pixman image, `m_tex` = a `CPixmanTexture` sharing that image (so `CFramebufferElement`/matte/snapshot draws can sample it); `bind()` sets it as the renderer's current target image; `readPixels(CHLBufferReference, x, y, w, h)` = `beginDataPtr` on the dst aquamarine buffer + row copy (screencopy/screenshare: `ScreenshareFrame.cpp:397,444,462`, `CursorshareSession.cpp`); `addStencil` no-op (stencil is only used by rounding/blur paths, dead in flat mode); `release()` frees image + store. |
| `src/render/pixman/PixmanRenderbuffer.hpp/.cpp` | `CPixmanRenderbuffer : IRenderbuffer`. Wraps an `Aquamarine::IBuffer` with `BUFFER_CAPABILITY_DATAPTR`: `bind()` = `beginDataPtr()` + `pixman_image_create_bits_no_clear(fmt, w, h, data, stride)` over the mapping; cache the image but recreate if the data pointer moved (wlroots `renderer.c:26` `begin_pixman_data_ptr_access` pattern); `unbind()` = `endDataPtr()`. Refuse (log + fail) buffers without DATAPTR. |
| `src/render/pixman/PixmanElementRenderer.hpp/.cpp` | `CPixmanElementRenderer : IElementRenderer`, the 9 draws (sect. 4). |

### aquamarine (`cpu-backend` branch)

CMake also GLOB_RECURSEs `src/*.cpp` (`CMakeLists.txt:61`); no build edits.

| File | Contents |
|---|---|
| `include/aquamarine/allocator/Shm.hpp` + `src/allocator/Shm.cpp` | `CShmAllocator : IAllocator` + `CShmBuffer : IBuffer`. `memfd_create` + `ftruncate` + `mmap` per buffer (wlroots `render/allocator/shm.c` model). Buffer: `caps() = BUFFER_CAPABILITY_DATAPTR`, `type() = BUFFER_TYPE_SHM`, `shm()` filled (fd, format, stride, offset 0) so the Wayland backend can `wl_shm_create_pool` the memfd directly, `beginDataPtr/endDataPtr` return the mapping, `dmabuf()` empty. Allocator: `drmFD() = -1`, new enum `AQ_ALLOCATOR_TYPE_SHM` in `include/aquamarine/allocator/Allocator.hpp`. Format from `SAllocatorBufferParams` (single-plane linear only; reject multiplanar). |

Modified aquamarine files (no new files): `src/backend/Backend.cpp`,
`src/backend/Wayland.cpp` (sect. 5).

---

## 3. `CHyprPixmanRenderer` virtual surface

Pure virtuals of `IHyprRenderer` (verified against `Renderer.hpp`):

- `type()` -> new `RT_PIXMAN = 3` added to the enum in `Renderer.hpp`.
- `endRender(cb)` - the whole GL offload/fence dance collapses: run
  `m_renderData.damage = m_renderPass.render(m_renderData.damage)` (occlusion culling +
  per-element damage clipping happen inside `pass/Pass.cpp`, renderer-agnostic), unbind
  the target (endDataPtr - CPU writes are already in the mapped buffer, nothing to
  flush), for `RENDER_MODE_NORMAL` do `state->setBuffer(m_currentBuffer)`, invoke `cb`
  immediately (mirrors the GL `!explicitSyncSupported()` branch in `GLRenderer.cpp:84+`),
  clear `m_usedAsyncBuffers`.
- `createSyncFDManager()` -> `CNoopSyncFDManager` (invalid fds, no-ops).
- `elementRenderer()` -> the owned `CPixmanElementRenderer`.
- `createStencilTexture` -> invalid stub (stencil = rounding/blur only).
- `createTexture` x6: `(bool opaque)` empty tex; `(drmFormat, pixels, stride, size,
  keepDataCopy, opaque)` copy into `CPixmanTexture` (this is the wl_shm ingestion entry,
  sect. 6); `(SDMABUFAttrs)` -> log error, return invalid tex (unreachable: dmabuf never
  advertised); `(w, h, data)` RGBA copy (renderText); `(cairo_surface_t*)` copy from
  `cairo_image_surface_get_data` - cairo ARGB32 is premultiplied and byte-identical to
  `PIXMAN_a8r8g8b8` (cairo IS pixman underneath), used by `loadAsset`; `(lut3D, N)`
  invalid stub (CM forced off).
- `explicitSyncSupported()` -> false. `getDRMFormats()` -> `{}`.
  `getDRMFormatModifiers()` -> `{}`.
- `createFB(name)` -> `CPixmanFramebuffer` (snapshots, fake render, screencopy).
- `disableScissor()` -> clear the renderer's current clip state.
- `blend(bool)` -> toggles default op OVER vs SRC (state consumed by the element renderer).
- `drawShadow` x2, `drawGlow` x2 -> no-ops (flat mode). `blurFramebuffer` -> return the
  source FB's texture unmodified (flat mode never calls it; belt and braces).
- `setViewport` -> store; used to clamp composite dst.
- `reloadShaders` -> false.
- protected `renderOffToMain(off)` -> composite `off`'s image onto the current target
  (used by `bindTempFB` scopes); with no offload FB in the normal path it is rare.
- protected `getOrCreateRenderbufferInternal(buffer, fmt)` -> `CPixmanRenderbuffer`,
  cached per `IBuffer*` in `m_renderbuffers` like GL, invalidated via
  `onRenderbufferDestroy`.
- override `initRender()` -> no-op (GL: makeEGLCurrent).
- override `initRenderBuffer(buffer, fmt)` -> get/create the `CPixmanRenderbuffer`,
  `bind()` it (map + wrap), set it as current target.
- override `beginRenderInternal(pMonitor, damage, simple)` -> set target = the bound
  renderbuffer image, store damage. **No offload work buffer** (GL binds
  `CMonitorResources::getUnusedWorkBuffer()`; we render straight into the mapped output
  buffer, damage-scoped, like wlroots).
- override `beginFullFakeRenderInternal(...)` -> target = the passed `CPixmanFramebuffer`.
- override `bindFB(fb)` -> switch current target image.

Monitor transform note: GL applies the output transform in `g_pHyprOpenGL->end()` when
blitting offload -> renderbuffer. Rendering direct-to-buffer means the transform must be
applied per draw op instead (the wlroots way, transform recipe below). M0/M1 scope:
support `HYPRUTILS_TRANSFORM_NORMAL` outputs; carry the per-op transform recipe in the
tex draw so rotated outputs can follow, but log a warning and do not claim support until
verified. Mirrors (`renderMirrored`) reuse `CTexPassElement` draws and get whatever the
tex path supports.

## 4. `CPixmanElementRenderer` draws (9 overloads, `ElementRenderer.hpp:26-34`)

The base class precomputes boxes/regions/UV; each draw receives the element + final
damage region. Core primitive everywhere:
`pixman_image_set_clip_region32(target, damage.pixman())` then one or more
`pixman_image_composite32` calls, then clear the clip. `CRegion` in hyprutils is
`pixman_region32_t` underneath - zero conversion cost.

- `draw(CClearPassElement)` - solid fill image (`pixman_image_create_solid_fill`,
  16-bit channels = float * 0xFFFF), `PIXMAN_OP_SRC`, clipped composite over the full
  target box.
- `draw(CRectPassElement)` - same fill; `OP_SRC` when alpha == 1 (memcpy-class), else
  `OP_OVER`; clip = damage (base already intersected with the element's region).
- `draw(CTexPassElement)` - **the workhorse**; crib wlroots `render/pixman/pass.c:39-199`
  verbatim in spirit:
  - source = `CPixmanTexture::getImage()`;
  - blend: opaque tex + no alpha -> `PIXMAN_OP_SRC`, else `OP_OVER` (premultiplied);
  - alpha != 1 -> mask = `pixman_image_create_solid_fill({.alpha = 0xFFFF * a})`;
  - fast path: NORMAL transform and src size == dst size -> plain composite with src
    offset, no transform object;
  - slow path: build a `pixman_transform` in reverse order (crop translate -> flip ->
    rotate -> viewport translate -> scale; exact integer cos/sin per transform; scale =
    `pixman_double_to_fixed(src/dst)`), `pixman_image_set_transform`, filter =
    `PIXMAN_FILTER_NEAREST` when the element sets `useNearestNeighbor`, else
    `PIXMAN_FILTER_BILINEAR` with `PIXMAN_REPEAT_PAD` (avoids edge bleed), composite,
    then reset transform to NULL so pixman's cached fast paths stay hot;
  - clip = damage region throughout.
  Base-class `drawSurface` reduces every surface to `draw(CTexPassElement)`, so client
  windows, layers, lockscreen, IME, software cursors, and DPMS fade all come for free.
- `draw(CBorderPassElement)` - flat mode has rounding 0: the border is a rectangular
  ring; fill the region (outer box minus inner box, built with `CRegion` subtract) with
  the border color, `OP_SRC`/`OP_OVER` by alpha. Gradient borders (m_grad with >1 stop):
  M1 renders the first stop as a solid (log once); pixman linear gradients are a later
  nicety.
- `draw(CFramebufferElement)` - composite the FB's backing image to the target (used by
  the DPMS/fade and snapshot paths).
- `draw(CPreBlurElement)`, `draw(CShadowPassElement)`, `draw(CInnerGlowPassElement)`,
  `draw(CTextureMatteElement)` - no-ops in flat mode (blur/shadow/glow forced off;
  matte is only used by blur/snapshot effects).

Performance rules imported from wlroots (sect. 6 of the crib): OP_SRC for opaque, NULL
transform + a8r8g8b8 hits libpixman SIMD fast paths, clip-region compositing means a
static screen composites zero pixels, damage rects come pre-collapsed by Hyprland's
damage ring.

## 5. Aquamarine CPU buffer path (`cpu-backend`)

Reuse what exists: `IBuffer` already models CPU buffers (`BUFFER_CAPABILITY_DATAPTR`,
`beginDataPtr/endDataPtr`, `shm()`), `CDRMDumbAllocator` already exists and mmaps +
PRIME-exports (used today for DRM cursor planes), `CSwapchain` is allocator-generic,
and the Headless backend commit path is buffer-agnostic. What is missing:

1. **`CShmAllocator`** (new, sect. 2) - CPU buffers with no DRM node at all.
2. **`CBackend::start()` fallback** (`src/backend/Backend.cpp:163-178`): today
   `primaryAllocator` is created only from a `drmFD() >= 0` impl (GBM) and start()
   aborts with "no allocator available" otherwise. Change: when no DRM-fd impl exists
   (or a new `AQ_FORCE_ALLOCATOR=shm|dumb` env asks for it), fall back to
   `primaryAllocator = CShmAllocator::create(...)` instead of failing. The `// TODO:
   obviously change this when (if) we add different allocators.` comment marks the spot.
   Hyprland then needs no change: `Monitor.cpp:2257` reconfigures the swapchain from
   `getBackend()->preferredAllocator()`, which returns `backend->primaryAllocator` in
   Headless/Wayland/Null backends.
3. **Wayland nested backend** (`src/backend/Wayland.cpp`) - for the M1 nested harness:
   - `start()`: dmabuf is currently mandatory (`Wayland.cpp:147` "Missing protocols"
     requires `waylandState.dmabuf`). Make it optional when the primary allocator is
     CPU-type: only require `xdg + compositor + seat + shm`.
   - `wlBufferFromBuffer` / `CWaylandBuffer` ctor (`Wayland.cpp:864`) is dmabuf-only
     (`zwp_linux_buffer_params_v1`). Add an shm branch for buffers with
     `BUFFER_CAPABILITY_DATAPTR`: `wl_shm_create_pool(shm().fd)` +
     `wl_shm_pool_create_buffer` (zero-copy: the compositor reads our memfd directly).
     The cursor path at `Wayland.cpp:766-796` already does exactly this pool dance -
     crib it.
   - `drmFD()` stays -1 without dmabuf feedback; that is what triggers the Backend.cpp
     fallback above.
4. **DRM scanout (M2)**: wire `CDRMDumbAllocator` as `primaryAllocator` when a DRM impl
   exists but GBM/GL is unusable (selection via `AQ_FORCE_ALLOCATOR=dumb`). The DRM
   backend already imports buffers by their `dmabuf()` attrs for FBs, and
   `CDRMDumbBuffer` exports a LINEAR PRIME fd, so scanout should work unmodified;
   pixman writes through the mmap (same split wlroots uses: mmap for rendering, PRIME
   dmabuf for the KMS FB).

Cursor: `PointerManager.cpp:461-468` already treats a non-GBM allocator as the CPU
cursor path and composites cursors with cairo through `beginDataPtr`
(`BUFFER_CAPABILITY_DATAPTR`) - the shm allocator slots straight in. If the hardware
cursor path misbehaves, software cursors are the flat-mode fallback and render through
`CTexPassElement`.

## 6. Client buffer ingestion

- **wl_shm** (the only client path): surface commit ->
  `SSurfaceState::updateSynchronousTexture` (`src/protocols/types/SurfaceState.cpp:48-60`)
  maps the client buffer via `beginDataPtr(0)` and calls either
  `texture->update(drmFmt, dataPtr, stride, accumulateBufferDamage())` (damage-scoped)
  or `g_pHyprRenderer->createTexture(drmFmt, dataPtr, stride, bufferSize)`.
  `CPixmanTexture` implements both; `update` copies only the damaged rows. NOTE the
  deliberate divergence from wlroots: wlroots wraps the client mmap zero-copy and locks
  the buffer; Hyprland's protocol layer releases the shm buffer immediately after
  commit (`protocols/core/Compositor.cpp:664`), so the copy is required and also
  sidesteps the SIGBUS-on-pool-shrink hazard wlroots handles with a signal handler
  (Hyprland's copy window is short; verify Hyprland's own shm mapping guard during M1).
- **single-pixel-buffer** (`src/protocols/SinglePixel.cpp:13`): same `createTexture`
  path, free.
- **dmabuf**: structurally rejected (sect. 1); clients renegotiate to wl_shm.
- **Misc producers**: `renderText` -> `createTexture(w, h, data)`; `loadAsset` ->
  `createTexture(cairo_surface_t*)`; cursor buffer ingestion
  (`PointerManager.cpp:956`) uses the non-pure base `createTexture(SP<IBuffer>,
  keepDataCopy)` which funnels into the pixel-pointer overload.

## 7. Damage-driven composite loop (per frame)

Entirely reuses Hyprland's existing machinery; the pixman renderer adds no damage logic
of its own (wlroots model: the renderer only honors per-op clips).

1. `renderMonitor` (`Renderer.cpp:2019`) -> `beginRender`: `m_currentBuffer =
   swapchain->next(&bufferAge)` (works for shm/dumb buffers; `CSwapchain` is generic),
   `initRenderBuffer` maps it into a pixman image, damage =
   `pMonitor->m_damage.getBufferDamage(bufferAge)` + `rotate()` (`CDamageRing`,
   `src/output/DamageRing.hpp` - Hyprland's equivalent of wlroots'
   `wlr_damage_ring_rotate_buffer`).
2. Scene walk adds pass elements; `CRenderPass::render(damage)` (`pass/Pass.cpp:194`)
   does occlusion culling and hands each element its clipped damage; each draw
   composites only inside that region via `pixman_image_set_clip_region32`.
3. `endRender`: unmap, `state->setBuffer`, callback immediately (no fences).
4. `renderMonitor` tail: damage -> buffer coords -> `state->addDamage(frameDamage)`
   (reaches KMS FB_DAMAGE_CLIPS / host-compositor surface damage), commit, schedule.
   Failure path `swapchain->rollback()` (`Renderer.cpp:2488`) is renderer-agnostic.

Config for correctness: `debug:damage_tracking` stays at its default (full); pixman mode
must never be combined with damage tracking off (that would repaint everything every
frame - the llvmpipe failure mode this project exists to avoid).

## 8. Renderer selection + flat-mode enforcement

Selection (checked at `Compositor.cpp` STAGE_BASICINIT; `Config::mgr()->init()` runs in
the prior stage, so config is readable):

1. Env `HYPRLAND_RENDERER` = `gl` | `pixman` (wins, mirrors wlroots' `WLR_RENDERER`).
2. Config `render:renderer` = `auto` (default) | `gl` | `pixman` - new string value in
   `src/config/ConfigManager.cpp` defaults + `src/config/ConfigDescriptions.hpp`.
3. `auto` = gl (today's behavior). A later nicety can auto-fall-back to pixman when the
   aquamarine backend reports no DRM fd, like wlroots' `has_render_node` check; not in
   scope for M0/M1.

Flat-mode enforcement, per the brief ("error out unless disabled; auto-force"):
when the pixman renderer is selected, after every config load/reload
(`CConfigManager` post-load hook), force:
`animations:enabled = 0`, `decoration:blur:enabled = 0`, `decoration:rounding = 0`,
`decoration:shadow:enabled = 0`, `decoration:screen_shader = ""`,
`render:cm_enabled = 0`, and pin `debug:damage_tracking` to full. If the user's config
set any of them otherwise, push a config error (the `hyprctl configerrors` /
error-overlay path) naming the value and stating it is forced off under the pixman
renderer, then override anyway. Hard-forcing (not trusting the config) is the recon
recommendation and keeps every GL-flavored code path (blur prepass, shadow/glow draws,
stencil rounding, screen shader, CM LUTs) provably dormant.

## 9. Xwayland

Verified: `src/xwayland/*` has zero DRM/dmabuf/GL references. Xwayland is just another
Wayland client of Hyprland; with linux-dmabuf never advertised it falls back to software
rendering (no glamor) and wl_shm buffers. So Xwayland stays ENABLED by default and
should work, only unaccelerated. Contingency: if the bench shows Xwayland failing
without a render node, set `xwayland:enabled = false` in the flat-mode forced set and
note it in omarchy32cpu #1; do not sink time into it before M1 core goals pass.

---

## 10. Milestones

Bench note: recon 3 found SSH to 2.28.72.117 DOWN (connection reset after banner;
IPS/filter suspected; operator must restore). All build/run tasks below queue behind
`ssh root@2.28.72.117 'echo LIVE'` succeeding; the runbook is
`/home/claude-user/hyprdev/BENCH.md`. Code tasks proceed locally regardless.

### M0 - both forks compile with the pixman renderer selected; a nested (or headless) session clears the screen to a solid color

aquamarine, in order:
1. `include/aquamarine/allocator/Allocator.hpp` - add `AQ_ALLOCATOR_TYPE_SHM`.
2. `include/aquamarine/allocator/Shm.hpp` + `src/allocator/Shm.cpp` - `CShmAllocator`
   / `CShmBuffer` (memfd + mmap, DATAPTR caps, `shm()` attrs filled).
3. `src/backend/Backend.cpp` (start(), 163-178) - shm-allocator fallback when no
   DRM-fd impl; honor `AQ_FORCE_ALLOCATOR` env.
4. `src/backend/Wayland.cpp` - dmabuf optional in `start()`/registry check (147);
   wl_shm branch in the output buffer path (`CWaylandBuffer`/`wlBufferFromBuffer`,
   864) cribbed from the cursor pool code (766-796).
5. Local compile check (host toolchain if present), commit on `cpu-backend`.

Hyprland, in order:
6. `src/render/Renderer.hpp` - add `RT_PIXMAN` to `eType`.
7. `src/render/pixman/PixmanFormat.hpp/.cpp` - fourcc<->pixman table.
8. `src/render/pixman/PixmanTexture.hpp/.cpp`.
9. `src/render/pixman/PixmanFramebuffer.hpp/.cpp` (readPixels included - it is the M0
   verification instrument).
10. `src/render/pixman/PixmanRenderbuffer.hpp/.cpp`.
11. `src/render/pixman/PixmanElementRenderer.hpp/.cpp` - clear + rect real; tex/border
    compile-clean skeletons (log-once stubs); 4 effect draws as final no-ops.
12. `src/render/PixmanRenderer.hpp/.cpp` - full virtual surface (sect. 3) +
    `CNoopSyncFDManager`.
13. `src/Compositor.cpp` - selection branch at 693-696 (env + config, skip
    `g_pHyprOpenGL`); null guard at 591.
14. `src/config/ConfigManager.cpp` + `ConfigDescriptions.hpp` - `render:renderer`
    value; flat-mode force + config-error hook (sect. 8).
15. Bench: build aquamarine fork, `ninja install`; build Hyprland against it; run
    nested under the BENCH.md sway-headless harness (or Hyprland headless-only +
    `hyprctl output create headless`) with `HYPRLAND_RENDERER=pixman`; grim/screencopy
    screenshot must show the clear color (non-black-pixel check per BENCH.md); commit
    both forks.

M0 exit: 15/15 tasks; screenshot of a solid clear from a GPU-less pixman session.

### M1 - client windows composite with borders, damage-driven, screenshot-verified in the nested harness

In order:
1. `PixmanElementRenderer` - full `draw(CTexPassElement)`: fast path, transform
   recipe, filters, alpha mask, OP_SRC opaque promotion (wlroots `pass.c:39-199`).
2. `PixmanElementRenderer` - `draw(CBorderPassElement)` flat ring borders (gradient ->
   first stop, log once); `draw(CFramebufferElement)`.
3. `CPixmanTexture::update` damage-scoped copy verified against
   `SurfaceState.cpp:48-60` + `accumulateBufferDamage`; single-pixel protocol check.
4. Asset/text path: `createTexture(cairo_surface_t*)` and `(w,h,data)` verified via the
   error overlay / notifications (visible artifacts render).
5. Cursor: verify the existing CPU cursor path (`PointerManager.cpp:461+` cairo/dumb)
   under the shm allocator; else force software cursors; software cursors render
   through the now-real tex draw.
6. `CPixmanFramebuffer::readPixels` end-to-end: screencopy protocol -> grim screenshot
   works from inside the pixman session (this is the verification instrument).
7. Snapshot/fake-render path: `beginFullFakeRender` + `makeSnapshotFB` smoke test
   (window close does not crash even with animations off).
8. Bench harness run: launch a wl_shm client (foot terminal - NOT kitty, kitty needs
   GL) + a second client; screenshot-verify window content + borders + overlap
   occlusion; move/resize and screenshot again.
9. Damage verification: `HYPRLAND_TRACE=1` logging of per-frame damage while typing in
   foot - confirm small damage regions, not full-frame repaints; confirm idle frames
   composite nothing.
10. Xwayland smoke test (`xeyes`/`xterm` via software Xwayland); if broken, force
    `xwayland:enabled = false` and record in omarchy32cpu #1. Commit both forks.

M1 exit: 10/10 tasks; before/after screenshots + damage-trace excerpt in PROGRESS.md.

### M2 (stretch) - boots on the omarchy32cpu VM via DRM

1. aquamarine: `AQ_FORCE_ALLOCATOR=dumb` selects `CDRMDumbAllocator` as
   `primaryAllocator` in `Backend.cpp` when a DRM impl exists (reuse
   `reopenDRMNode`; allocator refuses non-primary nodes, `DRMDumb.cpp:113+`).
2. Verify the DRM backend imports `CDRMDumbBuffer::dmabuf()` (LINEAR PRIME export) as a
   scanout FB on the omarchy32-test VM (virtio-gpu or bochs KMS, no GL).
3. Session plumbing on the VM: seatd/logind, libinput, VT switch; flat config from
   `/home/claude-user/hyprdev/hyprland-flat.conf`.
4. Full boot of the omarchy32cpu image to a pixman Hyprland session; foot + screenshot;
   record CPU numbers (pidstat, per BENCH.md) against the llvmpipe baseline.
5. 32-bit note: everything here is arch-neutral C++; the i686 build belongs to the
   omarchy32cpu repo pipeline, not these forks - only flag any size assumptions
   (uintptr casts in new code) during review.

---

## 11. Risks

1. **Bench unreachable** (recon 3): SSH to 2.28.72.117 resets post-banner; every
   build/verify task is blocked until the operator restores inbound SSH. Mitigation:
   all M0 code tasks are local; BENCH.md is ready to run top-to-bottom.
2. **Monitor transform semantics**: GL applies output transform + screen shader + CM in
   its end-blit; pixman renders direct to the buffer, so transform must be per-op.
   Rotated/mirrored outputs are out of scope until verified; a wrong assumption here
   shows up as flipped/garbled output on real hardware (M2), not in the normal-transform
   nested harness.
3. **Hidden GL assumptions in the 3447-line base `Renderer.cpp`** (projection state,
   stencil-dependent clipping, blur prepass scheduling, `CMonitorResources` offload
   expectations). Flat-mode hard-forcing is the shield, but only runtime testing proves
   every effect path is dormant; expect M0->M1 whack-a-mole crashes.
4. **New wl_shm submission path in aquamarine's dmabuf-shaped Wayland backend**
   (feedback, presentation timing, buffer release lifecycles). Mitigation: the
   Headless backend is buffer-agnostic and is the first M0 target; nested comes second;
   the backend's own cursor code already exercises wl_shm pools.
5. **Texture copy cost + damage correctness on commit**: Hyprland releases client shm
   buffers right after commit, so every commit costs a damaged-region copy into
   `CPixmanTexture` (wlroots is zero-copy here). On 2 vCPU/32-bit targets a full-window
   copy storm (video, resize) is the main perf cliff; damage-scoped `update` plus
   OP_SRC blits keep the steady state cheap. Also: a bug in the damage-scoped copy
   shows as stale window regions - test with partial-damage clients (typing in foot).
6. (watch item) **Xwayland without a render node** is expected to fall back to software
   but is unverified; contingency is disabling it (sect. 9).
