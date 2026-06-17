# Street, Vegetation, and Vehicle Props — Sources

This directory contains real low-poly 3D model assets used by `scripts/Main.gd` for street props, trees, and parked vehicles. Models are loaded from `res://assets/3d/props/` via `_instance_prop()` and fall back to primitive GDScript geometry if an asset is missing or fails to import.

All included source models are CC0 or CC-BY licensed. CC-BY assets are attributed below.

## Directory layout

- `street/` — traffic lights, benches, bins, planters, scaffolding, barriers, bollards, signs, utility/news props, cones.
- `vegetation/` — tree variants.
- `vehicles/` — parked car variants.

## Poly.Pizza assets

These files are used as-downloaded GLB models from Poly.Pizza. Keep author/title/license rows intact for attribution.

| Local file | Title | Creator | License | Source |
|---|---|---|---|---|
| `street/bench_park.glb` | Bench | Ev Amitay | CC-BY 3.0 | https://poly.pizza/m/dOSjmdmKaxi |
| `street/bollard.glb` | Fence Pillar | Kay Lousberg | CC0 1.0 | https://poly.pizza/m/O8wNXcCDLL |
| `street/fire_hydrant.glb` | Fire hydrant | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/eNPaSEPrst8 |
| `street/news_stand.glb` | Market Stand | Quaternius | CC0 1.0 | https://poly.pizza/m/DGIM5HGISb |
| `street/newspaper_box.glb` | Vending Machine | Don Carson | CC-BY 3.0 | https://poly.pizza/m/0CX6wj64Swu |
| `street/road_sign_speed.glb` | Road Sign Double | J-Toastie | CC-BY 3.0 | https://poly.pizza/m/zjqn0wVnWw |
| `street/road_sign_stop.glb` | Stop sign | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/60GyU9CdZ9r |
| `street/scaffolding.glb` | ASW Scaffolding | TRASH - TANUKI | CC-BY 3.0 | https://poly.pizza/m/7OsuL_bU9Qf |
| `street/traffic_light.glb` | Three way traffic light | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/ayAwgj82oUR |
| `street/trash_bin.glb` | Trashcan Small | Quaternius | CC0 1.0 | https://poly.pizza/m/i7HDuYDLkx |
| `street/utility_box.glb` | Power Box | J-Toastie | CC-BY 3.0 | https://poly.pizza/m/WFVjj4vnGg |

Generated companion texture files extracted by Godot from embedded Poly.Pizza model data:

- `street/bollard_halloweenbits_texture.png` — from `street/bollard.glb`.
- `street/road_sign_stop_1358 Stop Sign.png` — from `street/road_sign_stop.glb`.

## Kenney CC0 assets

Kenney packs are Creative Commons Zero (CC0 1.0). Attribution is not required by the license, but credit is included for clarity.

| Local file | Kenney pack | Original model | License | Source |
|---|---|---|---|---|
| `street/barrier.glb` | City Kit Roads 2.0 | `construction-barrier` | CC0 1.0 | https://kenney.nl/assets/city-kit-roads |
| `street/street_light_modern.glb` | City Kit Roads 2.0 | `light-square` | CC0 1.0 | https://kenney.nl/assets/city-kit-roads |
| `street/traffic_cone.glb` | City Kit Roads 2.0 | `construction-cone` | CC0 1.0 | https://kenney.nl/assets/city-kit-roads |
| `street/planter.glb` | City Kit Suburban | `planter` | CC0 1.0 | https://kenney.nl/assets/city-kit-suburban |
| `vegetation/tree_01.glb` | Nature Kit | `tree_default` | CC0 1.0 | https://kenney.nl/assets/nature-kit |
| `vegetation/tree_02.glb` | Nature Kit | `tree_fat` | CC0 1.0 | https://kenney.nl/assets/nature-kit |
| `vegetation/tree_03.glb` | Nature Kit | `tree_pineRoundA` | CC0 1.0 | https://kenney.nl/assets/nature-kit |
| `vehicles/car_hatchback.glb` | Car Kit | `hatchback-sports` | CC0 1.0 | https://kenney.nl/assets/car-kit |
| `vehicles/car_sedan.glb` | Car Kit | `sedan` | CC0 1.0 | https://kenney.nl/assets/car-kit |
| `vehicles/car_suv.glb` | Car Kit | `suv` | CC0 1.0 | https://kenney.nl/assets/car-kit |

Generated companion texture files extracted by Godot from embedded Kenney model data:

- `street/barrier_colormap.png`
- `street/planter_colormap.png`
- `street/street_light_modern_colormap.png`
- `street/traffic_cone_colormap.png`
- `vehicles/car_hatchback_colormap.png`
- `vehicles/car_sedan_colormap.png`
- `vehicles/car_suv_colormap.png`

## Category substitutions

Where no exact CC0/CC-BY model was available, a close-fitting model stands in. These
substitutions are intentional and read correctly at street scale:

- **Utility box / phone booth** → `street/utility_box.glb` ("Power Box"). A roadside
  utility cabinet covers the same "street infrastructure box" role as a phone booth.
- **Newspaper / vending box** → `street/newspaper_box.glb` ("Vending Machine") and
  **news stand** → `street/news_stand.glb` ("Market Stand").
- **Bollard** → `street/bollard.glb` ("Fence Pillar"), a short post matching a bollard.
- **Speed sign** → `street/road_sign_speed.glb` ("Road Sign Double"), a generic post sign
  used for the speed-limit role.

All other categories use directly-matching models. Every category required by the task
(street light, three tree variants, bench, trash bin, planter, traffic light, scaffolding,
barrier, parked sedan/SUV/hatchback, stop sign, speed sign, utility box, fire hydrant,
news stand/newspaper box, bollard, plus a bonus traffic cone) is represented above.

## Runtime integration notes

- `Main.gd` caches `PackedScene` resources in `_prop_scene_cache` so repeated instances do not reload the same GLB.
- `_instance_prop()` computes a combined mesh AABB, uniformly scales models to a target axis size, recenters them on X/Z when needed, and grounds them at `y=0`.
- Every prop builder retains a primitive fallback path so the level remains playable if a model import is absent or corrupt.
- All GLB files are under 2 MB each.

## Update date

2026-06-18
