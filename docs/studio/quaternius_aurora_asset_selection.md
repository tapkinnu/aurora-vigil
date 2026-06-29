# Quaternius Aurora Asset Selection

Aurora Vigil target: original Godot 4.4.1 superhero city-flight game with Meridian City, skyways, civic tech, solar arrays, rogue drones, Null Choir resonators, Shimmer Echo emitters, and golden-hour/cyberpunk city visuals.

Selection principle: keep the download compact by selecting relevant models from official Quaternius free/CC0 packs instead of importing large unrelated dumps. No runtime/source files were changed; this is a provenance and staging pass only.

## Cyberpunk Game Kit

- Downloaded/staged path: `/home/ganomix/projects/aurora-vigil/assets/3d/quaternius_aurora/cyberpunk_game_kit`
- Why it fits: Best thematic match for Meridian City cyberpunk street tech: flying enemies can read as rogue drones; turrets fit civic-security hazards; antenna, computer, street light, rail, and sign pieces fit rooftops, skyways, and Null Choir/shimmer emitter set dressing.
- Suggested in-game uses:
  - rogue drone proxies
  - rooftop turret/security nodes
  - skyway rails and signage
  - civic tech consoles/antenna clusters
  - street-level cyberpunk dressing
- Style/scale caveats: Stylized low-poly and partly untextured; likely needs project palette/material overrides for golden-hour neon/cyberpunk contrast.
- Selected highlights:
  - `Enemies/Enemy_Flying.gltf`
  - `Enemies/Enemy_Flying_Gun.gltf`
  - `Enemies/Turret_Cannon.gltf`
  - `Enemies/Turret_Teleporter.gltf`
  - `Platforms/Antenna_1.gltf`
  - `Platforms/Computer_Large.gltf`
  - `Platforms/Light_Street_1.gltf`
  - `Platforms/Rail_Long.gltf`
  - `Platforms/Sign_1.gltf`

## Ultimate Modular Sci-Fi Pack

- Downloaded/staged path: `/home/ganomix/projects/aurora-vigil/assets/3d/quaternius_aurora/ultimate_modular_scifi`
- Why it fits: Compact sci-fi prop subset for civic tech, resonator machinery, rooftop utility pods, pipe runs, and Shimmer Echo/Null Choir device silhouettes.
- Suggested in-game uses:
  - Null Choir resonator bases
  - Shimmer Echo emitter support props
  - solar-array service equipment
  - rooftop/server-room clutter
  - mission-interactable civic consoles
- Style/scale caveats: FBX-only selection; convert/import-test in Godot before runtime placement. Interior sci-fi scale may need resizing for city rooftops.
- Selected highlights:
  - `FBX/Props_Computer.fbx`
  - `FBX/Props_ComputerSmall.fbx`
  - `FBX/Props_Teleporter_1.fbx`
  - `FBX/Props_Teleporter_2.fbx`
  - `FBX/Props_Laser.fbx`
  - `FBX/Props_Pod.fbx`
  - `FBX/Props_CrateLong.fbx`
  - `FBX/Details/Details_Pipes_Long.fbx`
  - `FBX/RoofTile_Pipes1.fbx`

## Ultimate Buildings Pack

- Downloaded/staged path: `/home/ganomix/projects/aurora-vigil/assets/3d/quaternius_aurora/ultimate_buildings_pack`
- Why it fits: Adds Quaternius skyline massing for Meridian City beyond existing Kenney blocks; selected mid/tall buildings can be used as distant skyline, rooftop landing silhouettes, and city-block accents.
- Suggested in-game uses:
  - skyline dressing
  - rooftop flight landmarks
  - street canyon silhouettes
  - background city blocks
- Style/scale caveats: Older FBX pack, not GLB/glTF; material style is simple low-poly and may need palette/scale harmonization with Aurora Vigil’s existing assets.
- Selected highlights:
  - `Models with Materials/FBX/2Story_Balcony_Mat.fbx`
  - `Models with Materials/FBX/2Story_Sign_Mat.fbx`
  - `Models with Materials/FBX/3Story_Slim_Mat.fbx`
  - `Models with Materials/FBX/4Story_Wide_2Doors_Roof_Mat.fbx`
  - `Models with Materials/FBX/6Story_Stack_Mat.fbx`

## Ultimate Spaceships Pack

- Downloaded/staged path: `/home/ganomix/projects/aurora-vigil/assets/3d/quaternius_aurora/ultimate_spaceships_pack`
- Why it fits: Spaceships can be repurposed as compact skyway pods, civic patrol craft, distant air traffic, or rogue drone variants in a superhero city-flight game.
- Suggested in-game uses:
  - skyway transit pods
  - distant aerial traffic
  - rogue drone/vehicle silhouettes
  - civic patrol craft
  - moving skyline dressing
- Style/scale caveats: Spacecraft silhouettes are more space-opera than municipal; use restrained scale/materials and possibly remove/avoid weaponlike reads for civilian routes.
- Selected highlights:
  - `Dispatcher/glTF/Dispatcher.gltf`
  - `Striker/glTF/Striker.gltf`
  - `Zenith/glTF/Zenith.gltf`

## Integration notes

- Prefer importing glTF selections first (`cyberpunk_game_kit`, `ultimate_spaceships_pack`) because verification found no missing external URI dependencies.
- FBX selections (`ultimate_modular_scifi`, `ultimate_buildings_pack`) are useful but should be import-tested or converted to GLB before runtime dressing.
- Use AABB-based scale normalization and project palette/material overrides before adding to gameplay scenes.
- Keep decorative dressing non-colliding unless it becomes a traversal or combat affordance.
- Possible first pass: use Cyberpunk flying enemies as rogue drone proxies, modular sci-fi props as Null Choir/Shimmer hardware, buildings as skyline blockers, and ships as skyway traffic pods.
