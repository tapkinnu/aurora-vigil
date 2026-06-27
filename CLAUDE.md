# Aurora Vigil — Facade System Reference

This document describes the **current state** of the imported-building facade
system in Aurora Vigil. It is a reference for any future Claude Code session
that needs to extend, debug, or visually improve the city capture. It is **not**
an implementation backlog — see "Open work / escalations" at the bottom.

## Status

`bf85ac7 feat: polish facade textures — break tiling, add window depth, add building greebles`
(Co-Authored-By: Claude Opus 4.8) merged the three improvements originally
described in earlier revisions of this file. `586f37b fix: clamp facade UV
scale and test polish` added `tests/test_city_capture_facade_polish.gd` and
wired it into `tools/validate_build.sh`. Both `AURORA_CITY_FACADE_TEXTURES: PASS`
and `AURORA_CITY_FACADE_POLISH: PASS` exit 0 today.

The original "task spec" framing (tiling too obvious, windows flat, no geometric
detail) is preserved below as the **design rationale** for what each function
does, so a future maintainer can see *why* the code is shaped the way it is.

## Key Files

- `scripts/Main.gd` — 4425-line main script
  - `_apply_facade_texture_overlay(holder, building_seed, texture_index)` at line 3420 — adds four facade texture panels plus greebles to an imported building holder
  - `_add_building_greebles(holder, bmin, bmax, building_seed)` at line 3514 — adds procedural ledges, HVAC units, parapets, antennas, entrance canopies
  - `_facade_texture_index_for(node_name)` at line 3571 — deterministic texture-set picker (5 PBR sets)
  - `_accumulate_mesh_aabb(node, xf, acc)` at line 1200 — used to compute building bounds before placing panels/greebles
  - `_add_city_kit_building()` at line 3400 — call site for Kenney buildings (calls the overlay)
  - `_add_city_builder_prop()` at line 3594 — call site for City Builder tiles (calls the overlay)
  - `_add_box(parent, name, size, pos, mat)` at line 1170 — helper that creates a `BoxMesh` MeshInstance3D (used by greebles)
  - `_matte(albedo, rough, metal)` at line 1928 — creates a `StandardMaterial3D` (used by greebles)
  - `const FACADE_SHADER` at line 18 — preloaded `building_facade.gdshader`
  - `_facade_albedo_textures[]`, `_facade_normal_textures[]`, `_facade_roughness_textures[]`, `_facade_emission_textures[]` at line 48 — 5 preloaded PBR texture sets
  - `FACADE_PBR_PROPS` — array of 5 dicts with per-set roughness/metallic/emission_energy
  - `FACADE_TEXTURE_DIRS` — 5 texture prefixes (glass, concrete, brick, metal, commercial)
- `shaders/building_facade.gdshader` — 159-line facade shader (uniforms, window grid, blending)
- `assets/textures/facades/` — 5 PBR texture sets (albedo, normal, roughness, emission per set)
- `assets/3d/kenney_city/commercial/` — 41 building GLBs (5 skyscrapers, 14 midrise, 14 low-detail)
- `tests/test_city_capture_facade_textures.gd` — locks the original overlay pass (panels present, shader assigned, ≥4 texture sets)
- `tests/test_city_capture_facade_polish.gd` — locks the polish: UV offset uniqueness (≥10 distinct values), `uv_scale ∈ [2.0, 6.0]`, `uv_scale_2/uv_scale ≈ 2.7`, `albedo_tex_2` assigned, `window_depth ∈ [0.3, 0.6]`, `glass_reflectivity ∈ [0.1, 0.25]`, ≥70 buildings with parapet greebles, at least one `Greeble_Antenna` and one `Greeble_Canopy` city-wide
- `tools/validate_build.sh` — runs both facade tests as part of full validation

## Improvement 1 — Break texture tiling (status: implemented, locked)

**Rationale (originally a problem, now resolved):** `uv_scale` was 3.5–5.5 flat, which produced visible repeating grids on large facades.

**What the code does today:**

- `shaders/building_facade.gdshader` declares:
  - `uniform vec2 uv_offset` — per-building offset added to the base UV
  - `uniform float uv_scale_2` — second detail-layer scale
  - `uniform sampler2D albedo_tex_2` — second albedo texture blended in at the detail scale
  - Roughness is also sampled from two layers and blended
- `_apply_facade_texture_overlay()` (lines 3443–3449) computes:
  - `uv_s = clamp(2.0 + footprint * 0.18 + (seed % 3) * 0.4, 2.0, 6.0)` — bigger footprint = more tiling
  - `uv_s2 = uv_s * 2.7` — detail layer at a different frequency
  - `(off_x, off_y)` derived from `building_seed` to give each building a unique offset
  - `tex_idx2 = (tex_idx + 1) % _facade_albedo_textures.size()` — detail uses the *next* texture set
- The shader blends: `albedo = mix(sample1.rgb, sample2.rgb, 0.3) * albedo_tint.rgb`

## Improvement 2 — Add window depth / glass reflectivity (status: implemented, locked)

**Rationale:** Windows were flat emissive stickers with no glass depth or reflection.

**What the code does today:**

- `shaders/building_facade.gdshader` declares:
  - `uniform float window_depth = 0.0` — controls how recessed dark windows appear
  - `uniform float glass_reflectivity = 0.15` — base reflectivity for unlit glass
- Dark-window branch (shader lines 141–149):
  - Computes a `recess` smoothstep from the four frame edges → 1.0 at pane center, 0.0 at frame
  - Adds a subtle `sky_tint` toward pane center (`window_depth * recess`)
  - Mixes albedo toward `dark_window` and tints toward sky at the center
  - Pushes roughness down to 0.15 in the pane center (`recess * glass_reflectivity`) to fake polished glass
- Lit-window branch (shader lines 137–140):
  - Computes a `window_glow` smoothstep falloff from pane center
  - Emission intensity is `window_emission * window_intensity * window_glow`
  - Albedo picks up a small amount of the emission color in the center
- `_apply_facade_texture_overlay()` sets:
  - `window_depth_val = clamp(0.3 + size.y / 80.0, 0.3, 0.6)` — taller buildings recess deeper
  - `glass_refl_val = 0.25` for glass sets, otherwise `0.1 + (idx % 3) * 0.04`

## Improvement 3 — Add building greebles (status: implemented, locked)

**Rationale:** Imported kit buildings were plain boxes with no secondary silhouette/shadow detail.

**What the code does today (`_add_building_greebles`, lines 3514–3567):**

- **Horizontal floor ledges** — for buildings with `floors_est ≥ 6`, up to 3 ledges at 25/50/75 % height. Ledge size `(size.x * 0.96, 0.15, 0.12)`. Material `_matte(Color(0.15, 0.15, 0.16, 1.0), 0.7, 0.3)` (dark concrete/metal). One band per building is deterministically skipped via `(seed / (li + 1)) % 5 == 0` so spacing varies.
- **Roof HVAC units** — 1–2 boxes `(size.x * 0.2, 0.4, size.z * 0.2)`, deterministically offset on X/Z. Material `_matte(Color(0.25, 0.24, 0.22, 1.0), 0.8, 0.4)`.
- **Roof parapet** — four thin boxes around the perimeter, `(size.x * 0.98, 0.3, 0.08)` and `(0.08, 0.3, size.z * 0.98)` for the sides. Same material as ledges.
- **Antenna/spire** — only when `size.y > 20.0`. Thin tall box `(0.08, 2.0, 0.08)`, dark metal material.
- **Entrance canopy** — added for 2/3 of buildings (`seed % 3 != 0`). Front-face canopy `(size.x * 0.3, 0.08, 0.6)` at `(center.x, bmin.y + 1.5, bmin.z - 0.3)`. Material `_matte(Color(0.12, 0.12, 0.13, 1.0), 0.6, 0.5)`.

Each greeble is a `MeshInstance3D` child of the building `holder`, named with
the `Greeble_*` prefix so the polish test (and any future QA tool) can find
them by name.

## Verification

Both facade tests must continue to pass; both are part of `./tools/validate_build.sh`.

```bash
# Just the facade tests
AURORA_CAPTURE_MODE=city /home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64 --headless --path . -s tests/test_city_capture_facade_textures.gd
AURORA_CAPTURE_MODE=city /home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64 --headless --path . -s tests/test_city_capture_facade_polish.gd

# Full validation
./tools/validate_build.sh

# Visual QA
./tools/capture_screenshots.sh /tmp/aurora_facade_screenshots
```

## Constraints (unchanged from original task spec)

- Do NOT modify `tests/test_city_capture_facade_textures.gd` — it must still pass
- Do NOT modify `tests/test_city_capture_facade_polish.gd` — it locks the polish
- Do NOT break any other existing test
- Only modify capture-mode city code paths for facade work
- GDScript 4.4.1: use explicit types (`var x: float = ...` not `:=` for Variant returns)
- Do NOT use `class_name` (kept off to avoid autoload cache rebuild churn)
- Do NOT use `write_file` to rewrite `Main.gd` — use `patch` or targeted edits
- Keep changes focused on `_apply_facade_texture_overlay()`, `_add_building_greebles()`, the shader, and the relevant tests

## Open work / escalations

These are **not** recommended for low-risk free-quota cron runs (Big Pickle).
They are foundation-tier work that needs Claude Code Opus judgment — see the
`coding-agent-routing` skill's escalation table.

1. **Visual gap in the rendered city capture.** Automated tests confirm the
   polish is *applied* (UV offsets are unique and in range, greebles are
   placed, shader parameters are set correctly), but vision-model QA on
   `tools/capture_screenshots.sh` output still reports:
   - "windows appear as flat stickers" — `window_depth`/`glass_reflectivity`
     effects are too subtle at capture distance
   - "facade textures still show repeating grid" — the blend factor (0.3) is
     gentle, and the offset may be moving the UV outside the visible repeat
     period without changing the dominant pattern
   - "minimal secondary geometry" — greebles are sized for close-up play
     (ledges 0.15 m, parapets 0.3 m, antennas 0.08 m thick). At city-capture
     camera distance they are sub-pixel.
   Recommended next step: a focused Claude Code Opus session that picks a
   capture-distance-appropriate scale and intensity for each polish effect,
   not "add more polish" — see `creative/ludo-style-game-asset-studio/references/facade-polish-regression-gate.md`.
2. **CLAUDE.md previously described the work as a pending task.** This
   revision reframes it as completed/implemented/locked. Future revisions
   should preserve the "Improvement N — Status: implemented, locked"
   structure unless an item moves back into "open work."