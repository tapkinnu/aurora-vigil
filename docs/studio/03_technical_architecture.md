# Aurora Vigil — Technical Architecture Draft

## Engine
Godot 4.4.1, GDScript, code-built 3D city sandbox. Python only for tooling.

## Current modules
- `scripts/Main.gd`: foundation scene controller, city blockout, hero, HUD, dynamic event seed system.
- `scripts/ProgressionModel.gd`: pure progression/save-load model, tested by `tests/test_logic.gd`.
- `tools/validate_build.sh`: import, logic, and smoke validation.
- `tools/capture_screenshots.sh`: Xvfb OpenGL screenshot capture and contact sheet generation.

## Next architecture tasks
- Split `Main.gd` into `PlayerFlightController`, `CityEventSystem`, `MissionDirector`, `PowerSystem`, and `SaveGame`.
- Move missions/events/powers to JSON under `data/` with schema validation.
- Add real physics/collision city traversal and event interaction volumes.
- Add save/load resource or JSON format with migration version.
- Add asset manifest for 3D models, VFX, and audio provenance.
