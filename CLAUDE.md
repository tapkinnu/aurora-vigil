# Aurora Vigil — Claude Code Implementation Guide

## Project
Godot 4.4.1 game. City capture mode (`AURORA_CAPTURE_MODE=city`) builds a golden-hour
metropolitan postcard using imported Kenney City Kit Commercial + Road Kit GLB assets
and Kenney Starter Kit City Builder tile GLBs.

## Key Files
- `scripts/Main.gd` — 4177-line main script. Contains all city building code.
- `shaders/building_facade.gdshader` — facade shader with PBR texture support
  (albedo_tex, normal_tex, roughness_tex, emission_tex uniforms).
- `assets/textures/facades/` — 5 PBR texture sets: glass_curtain_wall, concrete_panel,
  brick, metal_cladding, commercial_facade (each has _albedo.png, _normal.png,
  _roughness.png, _emission.png).
- `assets/3d/kenney_city/` — 41 Kenney City Kit Commercial building GLBs
- `assets/3d/kenney_city_builder/` — 15 City Builder tile GLBs
- `tools/validate_build.sh` — full validation pipeline
- `tools/capture_screenshots.sh` — screenshot capture (gameplay, city, drone, closeup)
- `tests/test_city_capture_facade_textures.gd` — NEW test for facade texture overlay

## Existing Texture Infrastructure
The procedural/composite towers (non-GLB) already use `_city_facade_material()` which
creates a ShaderMaterial with `building_facade.gdshader` and assigns PBR textures from
`_facade_albedo_textures[]` etc (loaded by `_load_facade_textures()` from 5 facade sets).

The imported Kenney GLB buildings go through `_add_city_kit_building()` and
`_add_city_builder_prop()`, which call `_instance_prop()` → load the GLB, scale it,
add to tree. These do NOT currently get facade texture overlay materials.

## The Task
Apply textured facade overlay panels to ALL imported Kenney GLB buildings in the city
capture scene so they look less toy-like.

### Approach: Texture Overlay Panels
For each imported building holder returned by `_add_city_kit_building()` or
`_add_city_builder_prop()`, add thin `MeshInstance3D` panels (BoxMesh) on the visible
faces (front + at least one side) with a `ShaderMaterial` using
`building_facade.gdshader` and one of the 5 preloaded PBR texture sets.

### Implementation Requirements

1. **Create a new function `_apply_facade_texture_overlay(holder: Node3D, building_seed: int, texture_index: int)`**:
   - Called after `_add_city_kit_building()` / `_add_city_builder_prop()` returns a non-null holder
   - Uses `_accumulate_mesh_aabb(holder, ...)` to get the building's world-space bounding box
   - Creates 2-4 thin BoxMesh panels on the largest visible faces (front, sides)
   - Each panel is a `MeshInstance3D` named `"FacadeTexturePanel_N"` with:
     - `material_override` = a `ShaderMaterial` using `FACADE_SHADER` (preload the shader)
     - The ShaderMaterial gets PBR textures from `_facade_albedo_textures[texture_index]` etc.
     - Set shader params: `building_seed`, `floors`, `windows_per_floor`, `uv_scale`,
       `albedo_tint`, `use_normal_map=true`, `roughness_tex_weight`, `normal_map_scale`
     - Panel mesh meta: `facade_texture_panel = true`, `facade_texture_index = texture_index`
   - Building holder meta: `facade_texture_pass = true`
   - Panels must be offset slightly outside the building surface (0.05m) to avoid z-fighting
   - Panels should NOT cover roofs, doors, awnings, or parasols

2. **Texture index variation**: Use a deterministic index based on building name hash
   or position so different buildings get different textures from the 5 sets.

3. **Call sites to modify** (add `_apply_facade_texture_overlay` after each):
   - `_add_city_kit_building()` (line ~3317) — called for hero towers, midrise blocks,
     freeway shoulder blocks, distant skyline, dense sides
   - `_add_city_builder_prop()` (line ~3350) — only when the asset is a building
     (check name contains "lowrise" or "building"), not for pavement/grass/road tiles

4. **Test must pass**: `tests/test_city_capture_facade_textures.gd` expects:
   - 70+ buildings with `facade_texture_pass` meta
   - Each has 2+ panels named `FacadeTexturePanel_*` or with `facade_texture_panel` meta
   - Each panel has a `ShaderMaterial` with `building_facade.gdshader`
   - 4+ distinct texture indices across all buildings

## Validation
```bash
# Run just the new test
AURORA_CAPTURE_MODE=city /home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64 --headless --path . -s tests/test_city_capture_facade_textures.gd

# Full validation
./tools/validate_build.sh

# Screenshots
./tools/capture_screenshots.sh /tmp/aurora_screenshots
```

## Constraints
- Only modify capture-mode city code paths (`AURORA_CAPTURE_MODE=city`)
- Do NOT break existing tests (test_logic, test_city_capture_roads, test_save_load, etc.)
- Do NOT modify the gameplay city code path (non-capture buildings)
- Panels must be thin (0.02-0.05m) and slightly offset from building surface
- Use `_accumulate_mesh_aabb()` to compute building bounds — don't hardcode sizes
- GDScript 4.4.1: use explicit types (`var x: float = ...` not `var x := ...` when
  the return type is Variant or from `.get()` calls)
- Do NOT use `class_name` — causes circular resolution issues in headless mode
- Commit with: `git add -A && git commit -m "feat: apply PBR facade texture overlays to imported Kenney city buildings"`