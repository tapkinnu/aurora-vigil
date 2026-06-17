# PBR Facade Textures — Sources & Provenance

## Production Textures (CC0 — Public Domain)

All facade textures are real CC0 photogrammetry PBR sets downloaded from
[Polyhaven](https://polyhaven.com) at 2K resolution, resized to 1024×1024
PNG with max compression.

License: CC0 (Public Domain). No attribution required, but appreciated.
Source: https://polyhaven.com/license

| Our Name | Polyhaven Asset ID | Source URL |
|----------|-------------------|-----------|
| glass_curtain_wall | exterior_wall_cladding | https://polyhaven.com/a/exterior_wall_cladding |
| concrete_panel | concrete_panels | https://polyhaven.com/a/concrete_panels |
| brick | red_brick | https://polyhaven.com/a/red_brick |
| metal_cladding | box_profile_metal_sheet | https://polyhaven.com/a/box_profile_metal_sheet |
| commercial_facade | blue_metal_plate | https://polyhaven.com/a/blue_metal_plate |

Each set includes:
- **albedo** (Diffuse map from Polyhaven)
- **normal** (OpenGL normal map — `nor_gl` format, compatible with Godot)
- **roughness** (Roughness map)
- **emission** (Procedurally derived from albedo — dimmed + blurred to create
  subtle night-time glow. The shader's window-grid system overlays the lit
  windows on top of this base emission.)

## Fallback Generator

If the real textures are missing, `tools/generate_facade_textures.py` can
regenerate procedural fallbacks using FAL.ai for albedo + Pillow for
normal/roughness/emission. See the script header for details.