# Aurora Vigil — Claude Code Implementation Guide: Facade Texture Polish

## Current State
Commit `92bb100` added PBR facade texture overlay panels to all imported Kenney GLB
buildings. The panels work (textures load, test passes) but visual QA identified
three issues that need fixing:

1. **Texture tiling too obvious** — the same texture repeats in a grid pattern on large facades
2. **Windows look flat** — no depth, no reflective glass, just emissive stickers
3. **No geometric detail** — buildings are still box-shaped with no ledges/vents/frames

## Key Files
- `scripts/Main.gd` — 4265-line main script
  - `_apply_facade_texture_overlay()` at line ~3337 — current overlay implementation
  - `_facade_texture_index_for()` at line ~3411 — texture set selection
  - `_accumulate_mesh_aabb()` at line ~1192 — building bounds computation
  - `_add_city_kit_building()` at line ~3317 — call site for Kenney buildings
  - `_add_city_builder_prop()` at line ~3432 — call site for City Builder tiles
  - `_add_box()` at line ~1162 — helper to add a BoxMesh MeshInstance3D
  - `_matte()` at line ~1854 — creates a StandardMaterial3D
  - `FACADE_SHADER` constant — preloaded building_facade.gdshader
  - `_facade_albedo_textures[]`, `_facade_normal_textures[]`,
    `_facade_roughness_textures[]`, `_facade_emission_textures[]` — 5 preloaded PBR sets
  - `FACADE_PBR_PROPS` — array of 5 dicts with roughness/metallic/emission_energy per set
  - `FACADE_TEXTURE_DIRS` — 5 texture prefixes (glass, concrete, brick, metal, commercial)
- `shaders/building_facade.gdshader` — 136-line facade shader
- `assets/textures/facades/` — 5 PBR texture sets (albedo, normal, roughness, emission per set)
- `assets/3d/kenney_city/commercial/` — 41 building GLBs (5 skyscrapers, 14 midrise, 14 low-detail)
- `tests/test_city_capture_facade_textures.gd` — test that must continue to pass
- `tools/validate_build.sh` — full validation (must pass)
- `tools/capture_screenshots.sh` — screenshot capture (must produce valid PNGs)

## The Task: Three Improvements

### Improvement 1: Break up texture tiling repetition
**Problem**: `uv_scale` is currently 3.5-5.5, causing visible tiling on large panels.
**Fix**: Modify the shader to add per-building UV offset and multi-scale detail blending.

In `building_facade.gdshader`:
- Add `uniform vec2 uv_offset = vec2(0.0, 0.0);` — per-building UV offset to break tiling
- Add `uniform float uv_scale_2 = 1.0;` — second detail layer at different scale
- Add `uniform sampler2D albedo_tex_2 : source_color, hint_default_white;` — optional second albedo for blending
- In `fragment()`: blend two albedo samples at different UV scales:
  ```glsl
  vec2 base_uv = UV * uv_scale + uv_offset;
  vec4 albedo_sample = texture(albedo_tex, base_uv);
  // Second detail layer at 2.7x scale with different offset breaks up tiling
  vec2 detail_uv = UV * uv_scale * 2.7 + uv_offset * 1.3;
  vec4 albedo_detail = texture(albedo_tex_2, detail_uv);
  vec3 albedo = mix(albedo_sample.rgb, albedo_detail.rgb, 0.3) * albedo_tint.rgb;
  ```
- Sample roughness and normal from both layers too (blend the same way)

In `_apply_facade_texture_overlay()`:
- Set `uv_offset` to a deterministic per-building random offset (use building_seed):
  ```gdscript
  var off_x: float = float(building_seed % 100) / 100.0
  var off_y: float = float((building_seed / 100) % 100) / 100.0
  mat.set_shader_parameter("uv_offset", Vector2(off_x, off_y))
  ```
- Set `uv_scale_2` to `uv_s * 2.7` for a detail layer at a different frequency
- For `albedo_tex_2`, use the NEXT texture set in the cycle (tex_idx + 1) to mix two materials
- Vary `uv_scale` more: use 2.0-6.0 range based on building footprint size (bigger buildings = more tiling needed)

### Improvement 2: Add window depth with parallax/depth effect
**Problem**: Windows are flat emissive stickers, no glass depth or reflection.
**Fix**: Enhance the shader's window rendering with fake depth and better glass.

In `building_facade.gdshader`:
- Add `uniform float window_depth = 0.0;` — controls how much windows appear recessed
- Add `uniform float glass_reflectivity = 0.15;` — base reflectivity for unlit windows
- In the dark window branch (the `else` after `is_lit`), instead of just mixing albedo:
  ```glsl
  } else {
      // Dark window: recessed glass with subtle sky reflection
      float recess = smoothstep(frame_thickness, 0.5, local.x) * smoothstep(frame_thickness, 0.5, 1.0 - local.x)
                    * smoothstep(frame_thickness, 0.5, local.y) * smoothstep(frame_thickness, 0.5, 1.0 - local.y);
      vec3 sky_tint = vec3(0.15, 0.12, 0.10) * (1.0 - recess * window_depth);
      albedo = mix(albedo, dark_window, 0.15);
      albedo = mix(albedo, sky_tint, recess * glass_reflectivity);
      roughness = mix(roughness, 0.15, recess * glass_reflectivity); // glass is smoother
  }
  ```
- For lit windows, add a subtle glow falloff so they look like they have depth:
  ```glsl
  } else if (is_lit) {
      float window_glow = smoothstep(0.0, 0.5, 1.0 - length(local - vec2(0.5)) * 1.5);
      final_emission = window_emission * window_intensity * window_glow;
      albedo = mix(albedo, window_emission, 0.06 * window_glow);
  }
  ```

In `_apply_facade_texture_overlay()`:
- Set `window_depth` to 0.3-0.6 based on building height
- Set `glass_reflectivity` to 0.1-0.25 based on texture index (glass sets get more)

### Improvement 3: Add geometric greebles (ledges, vents, roof details)
**Problem**: Buildings are plain boxes with no secondary geometry.
**Fix**: Add procedural geometric details in `_apply_facade_texture_overlay()` AFTER the texture panels.

Add a new function `_add_building_greebles(holder: Node3D, bmin: Vector3, bmax: Vector3, building_seed: int)`:
- Called at the end of `_apply_facade_texture_overlay()` (pass the AABB data)
- Uses `_add_box()` to add small MeshInstance3D details:

1. **Horizontal floor ledges** (every N floors): thin dark boxes spanning the front face
   - For buildings with 6+ floors, add 2-3 thin ledges at 25%, 50%, 75% of height
   - Ledge size: `(size.x * 0.96, 0.15, 0.12)`, positioned at the front face + slight offset
   - Material: `_matte(Color(0.15, 0.15, 0.16, 1.0), 0.7, 0.3)` — dark concrete/metal

2. **Roof HVAC units**: 1-2 small boxes on top of the building
   - Size: `(size.x * 0.2, 0.4, size.z * 0.2)` at `(center.x, bmax.y + 0.2, center.z)`
   - Material: `_matte(Color(0.25, 0.24, 0.22, 1.0), 0.8, 0.4)`

3. **Roof edge parapet**: thin raised box around the roof perimeter
   - Front parapet: `(size.x * 0.98, 0.3, 0.08)` at `(center.x, bmax.y + 0.15, bmax.z + 0.02)`
   - Side parapets: similar on X faces
   - Material: same as ledges

4. **Antenna/spire on tall buildings**: for buildings where size.y > 20
   - Thin tall box: `(0.08, 2.0, 0.08)` at `(center.x + offset, bmax.y + 1.0, center.z)`
   - Material: `_matte(Color(0.1, 0.1, 0.1, 1.0), 0.4, 0.6)` — dark metal

5. **Entrance canopy** on the front face at ground level
   - Size: `(size.x * 0.3, 0.08, 0.6)` at `(center.x, bmin.y + 1.5, bmin.z - 0.3)`
   - Material: `_matte(Color(0.12, 0.12, 0.13, 1.0), 0.6, 0.5)`

Use `building_seed` to deterministically decide which greebles each building gets
(not all buildings need all greebles — use modulo/hash to vary).

Each greeble should be a child of the `holder` Node3D, just like the texture panels.
Name them `"Greeble_Ledge_N"`, `"Greeble_RoofUnit_N"`, `"Greeble_Parapet_N"`,
`"Greeble_Antenna"`, `"Greeble_Canopy"`.

## Verification

```bash
# Run the facade texture test
AURORA_CAPTURE_MODE=city /home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64 --headless --path . -s tests/test_city_capture_facade_textures.gd

# Full validation
./tools/validate_build.sh

# Screenshots
./tools/capture_screenshots.sh /tmp/aurora_polish_screenshots
```

## Constraints
- Do NOT modify `tests/test_city_capture_facade_textures.gd` — it must still pass
- Do NOT break any other existing tests
- Only modify capture-mode city code paths
- GDScript 4.4.1: use explicit types (`var x: float = ...` not `:=` for Variant returns)
- Do NOT use `class_name`
- Do NOT use `write_file` to rewrite Main.gd (4265 lines) — use `patch` or targeted edits
- Keep changes focused on `_apply_facade_texture_overlay()`, the shader, and the new
  `_add_building_greebles()` function
- Commit with: `git add -A && git commit -m "feat: polish facade textures — break tiling, add window depth, add building greebles"`
- Push to main after commit