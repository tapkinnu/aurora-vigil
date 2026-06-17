# Ground PBR Textures — Sources & Provenance

## Production Textures (CC0 — Public Domain)

All ground textures are real CC0 photogrammetry PBR sets downloaded from
[Polyhaven](https://polyhaven.com) at 2K resolution, resized to 1024×1024
PNG with max compression.

License: CC0 (Public Domain). No attribution required, but appreciated.
Source: https://polyhaven.com/license

| Our Name | Polyhaven Asset ID | Source URL |
|----------|-------------------|-----------|
| asphalt | asphalt_01 | https://polyhaven.com/a/asphalt_01 |
| grass | grass_medium_01 | https://polyhaven.com/a/grass_medium_01 |
| plaza | concrete_pavement | https://polyhaven.com/a/concrete_pavement |

Each set includes:
- **albedo** (Diffuse map from Polyhaven)
- **normal** (OpenGL normal map — `nor_gl` format, compatible with Godot)
- **roughness** (Roughness map)
- **emission** (Procedurally derived from albedo — dimmed + blurred to create
  subtle night-time ambient glow for bloom/SSR effects.)

## Fallback Generator

If the real textures are missing, `tools/generate_ground_textures.py` can
regenerate procedural fallbacks using seeded deterministic Pillow functions.
See the script header for details.