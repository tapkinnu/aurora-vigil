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

## Interaction volume layer (Task 3)
The in-world interaction layer gives every city event and the active mission a
real, observable, testable presence in 3D. It is a thin layer over the existing
power-driven resolution: entering a volume fires a *cue* (audio + HUD), while
resolution still flows through `CityEventSystem.attempt_resolve_nearest` exactly
as before. `Main.gd` stays a thin coordinator — all volume logic lives in the
modules below and is wired through one `ObjectiveDirector`.

### File map
- `scripts/InteractionVolume.gd` — reusable `Area3D` volume. Configurable shape
  (`sphere` / `box` / `cylinder`), color, billboard label, `kind` binding, and a
  list of named `triggers`. Built via `InteractionVolume.from_data(dict)`:
  missing OPTIONAL fields fall back to `DEFAULT_*` constants; a missing/empty
  required `kind` logs `push_error` and returns `null` (the spawner skips it, no
  crash). Emits `triggered(volume, source)` on an outside→inside transition via
  the polled `notify_point(point)` path (used because the hero is a plain
  `Node3D`, not a physics body) and via Area3D `body_entered` / `area_entered`.
- `scripts/VolumeSpawner.gd` — converts JSON (`events.seed_events` + the active
  mission `target_kind`) into `InteractionVolume` nodes parented to a city anchor.
  Colors/labels come from the `CityEventSystem` event-kind table so a volume's
  color always matches its event. Skips `bridge_collapse` (bespoke geometry).
- `scripts/BridgeCollapseZone.gd` — special-cased persistent hazard: severed road
  decks, tumbled debris, ROAD CLOSED barricades + sign, a hazard beacon light, and
  a box `InteractionVolume` covering the gap. Visible in screenshots, not just an
  invisible trigger.
- `scenes/objective_marker.tscn` + `scripts/ObjectiveMarker.gd` — billboard label
  + rotating diamond icon + down-beam that follows the active mission's volume so
  QA can confirm the active step without reading HUD text.
- `scripts/ObjectiveDirector.gd` — thin coordinator owning the spawner, bridge
  zone, marker, and per-frame polling. Routes enter triggers to the audio shim and
  the shared `host.last_event_text` HUD cue, and re-points the marker when the
  campaign advances. `stage_for_capture("city")` nudges the active objective to a
  central overlook so the city-overview screenshot reliably frames the marker.
- `scripts/VolumeAudioShim.gd` — audio dispatch shim. Trigger ids live in JSON but
  are routed through literal `AuroraAudio.trigger("...")` calls here so the
  audio-wiring contract (`tools/check_audio_wiring.py`) stays intact.
- `data/objective_markers.json` — declarative `target_kind → {label, icon,
  enter_audio}` table plus the `bridge_zone` placement. Validated by
  `schemas/volumes.schema.json`.
- `tools/validate_volumes.py` — static validator: schema-checks the marker data,
  confirms every mission/marker `target_kind` resolves to a real event kind (and
  every mission has a marker), and asserts all spawner-consumed positions are
  finite. Exits non-zero on failure.
- `tests/test_interaction_volumes.gd` — `extends SceneTree` unit test: default
  fallbacks, trigger-on-enter (emulated player), and malformed-dict rejection.

### Data flow
`data/events/events.json` (seed_events, kind colors) + `data/objective_markers.json`
(labels, icons, enter audio) + `data/missions/missions.json` (active `target_kind`)
→ `ObjectiveDirector.spawn_all()` → `VolumeSpawner` / `BridgeCollapseZone` build
`InteractionVolume` nodes under the `InteractionVolumeLayer` anchor → each frame
`ObjectiveDirector.update()` polls `hero.global_position` through
`InteractionVolume.notify_point()` → `triggered` → `VolumeAudioShim` (audio) +
`host.last_event_text` (HUD). Power-driven resolution and mission advancement are
unchanged; the marker re-points on `MissionDirector.mission_step` change.

### CI wiring
`tools/validate_build.sh` runs `python3 tools/validate_volumes.py` and the GDScript
`tests/test_interaction_volumes.gd` (alongside the existing data + logic checks), so
missing references, schema drift, or a broken volume break the build.
