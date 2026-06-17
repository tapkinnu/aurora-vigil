# Street Props — Sources

All props are built from Godot primitives (BoxMesh, CylinderMesh, SphereMesh)
in `scripts/Main.gd`. No external 3D models or textures were used.

## Prop Types

| Type | Function | Description |
|------|----------|-------------|
| Traffic Light | `_add_traffic_light()` | Pole + arm + 3-lens signal head (red/yellow/green) with OmniLight3D glow on active green |
| Bench | `_add_bench()` | Seat slab + backrest + legs + amber accent strip |
| Trash Bin | `_add_trash_bin()` | Cylinder body + lid + cyan rim accent |
| Planter | `_add_planter()` | Box container + sphere foliage + green glow light |
| Scaffolding | `_add_scaffolding()` | 4 posts + 3-level cross-braces + diagonal brace + red warning light |
| Barrier | `_add_barrier()` | Base + 2 posts + top rail + alternating hazard stripes |

## Provenance

- **Method:** Procedural primitive construction in GDScript
- **No external API calls:** No Meshy, FAL, or other generation services used
- **License:** Original IP, project-owned
- **Date:** 2026-06-17

## Placement

24 props total, distributed along avenues at regular intervals:
- 4 traffic lights at major intersections
- 4 benches along walking avenues
- 4 trash bins at street corners
- 4 planters in median areas
- 4 scaffolding units near outer blocks
- 4 barriers at avenue edges