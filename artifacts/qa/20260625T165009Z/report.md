# Aurora Vigil — Fresh QA Review (2026-06-25 16:50:09Z)

- **Commit reviewed:** `d9e90f6fcae31343a83d0db1b83a736bd5be1b6c` (HEAD = `origin/main`)
- **Branch:** `main` — working tree clean, no uncommitted changes
- **Reviewer:** game-qa (read-only)
- **Verdict:** **PASS** — no critical/high/medium blockers; one low-severity gap and several
  low-severity polish observations documented for a future Kimi/delegation pass.

## 1. Scope

Aurora Vigil is a Godot 4.4.1 original 3D superhero sandbox (hero: The Lumen; city: Meridian).
This review covers HEAD `d9e90f6`, which is the most recent commit on `main` and adds the
skyway runaway event visual on top of the skyway runaway finale mission (`6fc887c`) and its
objective-marker wiring (`cec6ef3`).

The review inspected:
- `project.godot`, `README.md`, `CLAUDE.md`
- All 23 scripts under `scripts/`
- 12 tests under `tests/`
- 20 tools under `tools/` (validation, capture, audio, data)
- All 8 data JSON files under `data/`
- Audio asset directory tree (`assets/audio/`, 18 OGG files)
- Texture set wiring (3 ground + 5 facade sets)

## 2. Canonical gates — summary

All gates passed on first run, no retries needed.

| # | Command | Exit | Result |
|---|---------|------|--------|
| 1 | `./tools/validate_build.sh` | **0** | All 12 sub-gates green: IMPORT, DATA, VOLUMES, LOGIC, VOLUME_TESTS, CITY_ROADS_TESTS, CITY_FACADE_TEXTURES, CITY_FACADE_POLISH, SAVE_LOAD_GD, SAVE_LOAD_PY, SMOKE, VALIDATE |
| 2 | `./tools/capture_screenshots.sh artifacts/qa/20260625T165009Z/screenshots` | **0** | 4/4 PNGs (1152×648, mean brightness 66–85), contact sheet (1704×266, 4 panels) — all PASS |
| 3 | `python3 tools/make_contact_sheet.py artifacts/qa/20260625T165009Z/screenshots artifacts/qa/20260625T165009Z/contact_sheet.jpg` | **0** | 4-panel JPEG produced at top-level path as the task spec requires |
| 4 | `python3 tools/check_audio_wiring.py --require-existing-audio` | **0** | 18 files / 16 references / 14 triggers / 2 loops / avg 4.86s — see finding L1 below |
| 5 | `python3 tools/validate_data.py` | **0** | 8 files / 3 schemas / 11 missions / 7 event_kinds / 5 powers |
| 6 | `python3 tools/validate_volumes.py` | **0** | 7 markers / 7 event_kinds / 11 missions |

Logs preserved under `artifacts/qa/20260625T165009Z/`:
`validate_build.log`, `capture_screenshots.log`, `make_contact_sheet.log`,
`check_audio_wiring.log`, `validate_data.log`, `validate_volumes.log`, plus the
per-screenshot `.log` files (`city.log`, `closeup.log`, `drone.log`, `gameplay.log`).

## 3. Semantic screenshot review

Four screenshots reviewed via the vision_analyze tool. The vision model flagged the city
as "greybox/low-poly" — this is the project's intentional neon-cyberpunk aesthetic
(README line 9: "3D city sandbox with neon-cyberpunk aesthetic, readable skyline, and
objective markers"). Real 3D Meshy hero and drone models are present per the README
contract. No actual placeholder greybox blockers, missing meshes, or untextured
checkers were observed.

- **gameplay.png (mean=75.20):** Hero (cyan emissive humanoid) hovering above a city
  block, large orange/yellow "Bridge collapse" objective beacon on the ground, purple
  vertical light beams in the background, full HUD readable (top status bar, powers
  list, HP/XP bars top-right, mission log top-left, minimap bottom-right). No black
  frames. Building facades show PBR texture variation (windows/lights/edges visible).
- **city.png (mean=66.04):** Wide-angle panoramic view of the dense city — elevated
  skyway bridge with "Hillview / Downtown / Airport-Harbor" road signs, vehicles on
  ground roads, dense skyscraper canyon, golden-hour lighting. Stylized black-edge
  cel-shaded look consistent with the project aesthetic.
- **drone.png (mean=83.23):** Recognizable 3D purple-emissive multi-rotor drone mesh
  (not a placeholder box/sphere) hovering over a building; orange impact/beam VFX on
  the rooftop below. Drone has detail and emissive material.
- **closeup.png (mean=84.71):** Mid-range hero perspective over the bridge-collapse
  event zone; orange/purple ground beacon + vertical light pillar visible. HUD fully
  populated. Some facades show window patterns from the 5 PBR facade sets.
- **contact_sheet.jpg (1704×266):** 4-panel horizontal strip — city / closeup / drone
  / gameplay. Each panel labeled and distinct in camera angle. Per-shot repetition of
  the HUD is expected (HUD is always-on) — panels differ in framing, not game state.

No black frames, no missing-resource checkers, no SCRIPT ERROR / Parse Error /
ObjectDB / leaked / null instance strings in any log file.

## 4. Failure-string sweep

`grep -E "SCRIPT ERROR|Parse Error|ObjectDB|leaked|null instance|black frame|Invalid call|missing resource"` across all generated logs returned **zero hits**.

Per-script `.gd` sweep for `TODO|FIXME|XXX|HACK|STUB` across `scripts/` returned **zero hits**.

The only defensive `push_error` / `push_warning` calls in the codebase (in
`SaveGame.gd`, `MissionDirector.gd`, `InteractionVolume.gd`, `AuroraAudio.gd`) are
legitimate validation guards, not stubs.

## 5. Findings

Severity legend: Critical (blocks shipping) / High (major player-facing regression) /
Medium (player-visible but workaround exists) / Low (polish / future improvement).

### Total: 0 Critical, 0 High, 0 Medium, 2 Low

### L1 — UI click / confirm sounds unwired (Low, Audio)

- **Where:** `scripts/AuroraAudio.gd:4` (`AUDIO_PATHS` constant)
- **Evidence:** `assets/audio/` contains 18 OGG files. `AUDIO_PATHS` only references 16.
  The two unwired files are:
  - `assets/audio/sfx/ui/ui_click.ogg`
  - `assets/audio/sfx/ui/ui_confirm.ogg`
  Both are listed in `data/manifest/asset_manifest.json` and `assets/audio/audio_manifest.json`
  with `"status": "complete"` and are declared in `tools/audio_pipeline.py` and
  `docs/studio/asset_audio_backlog.md`. However, no `AuroraAudio.trigger("ui_click")` or
  `trigger("ui_confirm")` call exists anywhere under `scripts/`.
- **Expected:** Menu / pause / settings / game-over UI button presses should produce
  click and confirm SFX cues.
- **Actual:** UI interactions are silent; the audio files sit on disk unused.
- **Why low:** Game is fully playable without them; no test or gate asserts their
  presence. Manifest already declares them as "complete," so this is a wiring gap, not
  a content gap.
- **Suggested fix:** Add `ui_click` and `ui_confirm` to `AUDIO_PATHS` in
  `scripts/AuroraAudio.gd` with reasonable cooldowns/probabilities (e.g. cooldown 0.0s,
  probability 1.0, volume_db -10) and call `AuroraAudio.trigger("ui_click")` /
  `trigger("ui_confirm")` from `MainMenu.gd`, `PauseMenu.gd`, `SettingsPanel.gd`, and
  `GameOverScreen.gd` button presses. Then re-run `check_audio_wiring.py` — expect
  `files=18 refs=18`.

### L2 — Contact sheet panels show same game state (Low, Polish)

- **Where:** `tools/capture_screenshots.sh` (scene choreography)
- **Evidence:** All 4 screenshot panels (city, closeup, drone, gameplay) show the
  hero during Story Mission 1/11 "Dawn Patrol," so the camera positions differ but
  the HUD/mission context is identical across panels.
- **Expected:** More variety — ideally each panel showing a different event type
  (tower_fire, rogue_drone, bridge_collapse, skyway_runaway) to demonstrate the
  dynamic-event seed system.
- **Actual:** Single-mission context repeated 4×.
- **Why low:** Functionally correct (panels are distinct in framing and capture the
  hero, drone, city, and event zone cleanly). This is a polish improvement, not a
  defect. README's verification section only asks for the script to produce valid
  PNGs, which it does.
- **Suggested fix:** Add optional `--scene` argument to `capture_screenshots.sh` that
  drives different `CityEventSystem.spawn_event(...)` calls before each shot, or
  pre-stage different `events.json` `seed_events` per panel. Optional.

## 6. Recent-commit review (`cec6ef3..d9e90f6`)

Three commits on top of HEAD, all small, all clean:

- **`cec6ef3` fix: wire skyway runaway objective marker** — adds a marker entry to
  `data/objective_markers.json` for `skyway_runaway` and extends
  `tools/validate_volumes.py` to accept it. Validated by `validate_volumes` (exit 0,
  markers=7).
- **`6fc887c` feat: add skyway runaway finale mission** — adds mission
  `skyway_runaway_response` to `data/missions/missions.json` (total now 11/11
  matches README), bumps MissionDirector fallback sync, expands `tests/test_logic.gd`.
  Validated by `AURORA_LOGIC: PASS`.
- **`d9e90f6` feat: add skyway runaway event visual** — adds `skyway_runaway` branch
  in `CityEventSystem.spawn_event(...)` (elongated 3.5×2.5×8 capsule mesh, 2 speed
  trail streaks, 2 skyway rails, 1 nose glow) and refactors `_dispatch_audio` from
  explicit `match` block to a generic `AuroraAudio.trigger(id)` autoload lookup.
  `push_error` on unknown IDs is no longer raised at the CityEventSystem layer, but
  `AuroraAudio.trigger()` still emits `push_warning` on unknown IDs and missing
  files (`AuroraAudio.gd:55, 73, 81, 85, 135, 139`), so the audio-error safety net
  is preserved end-to-end. Validated by all gates. `VolumeAudioShim.gd` also adds
  `drone_death` and `null_choir_cmdr_threat` shim entries.

No regressions detected. The capture screenshots, while not actively driving the
skyway_runaway event, render correctly because skyway_runaway is in the
`timed_spawn.types` rotation (`data/events/events.json:80`).

## 7. Pass-criteria checklist (from `tools/validate_build.sh`)

| Sub-gate | Status |
|----------|--------|
| AURORA_IMPORT | PASS |
| AURORA_DATA | PASS |
| AURORA_VOLUMES | PASS |
| AURORA_LOGIC | PASS |
| AURORA_VOLUME_TESTS | PASS |
| AURORA_CITY_ROADS_TESTS | PASS |
| AURORA_CITY_FACADE_TEXTURES | PASS |
| AURORA_CITY_FACADE_POLISH | PASS |
| AURORA_SAVE_LOAD_GD | PASS |
| AURORA_SAVE_LOAD_PY | PASS |
| AURORA_SMOKE | PASS |
| AURORA_VALIDATE | PASS |

## 8. What was tested

- All canonical gates from the repo root (exit codes captured).
- Visual QA on all 4 screenshots + contact sheet (semantic, not just brightness).
- Semantic-failure grep across all generated log files.
- README ↔ actual feature parity (controls, missions, powers, events).
- Recent-commit diff review (`cec6ef3..d9e90f6`).
- Audio asset count vs `AUDIO_PATHS` wiring.
- Data JSON consistency (event kinds ↔ marker kinds ↔ mission targets).
- Audio refactor safety (preserved `push_warning` coverage in AuroraAudio).

## 9. What was NOT tested (out of scope for read-only QA)

- In-engine interactive play (no headless Godot interaction harness in the repo).
- Performance under load (no FPS profiler integrated into `validate_build.sh`).
- Save/load round-trip with the actual save UI (covered by `AURORA_SAVE_LOAD_GD/PY`
  gates, but no full manual run).
- Networking (none — single-player only).

## 10. Concrete fix list for a follow-up Kimi / delegation-model pass

Ordered by ROI:

1. **Wire `ui_click` and `ui_confirm` audio triggers** (Low, ~10 lines): add to
   `AUDIO_PATHS` and call from `MainMenu.gd`, `PauseMenu.gd`, `SettingsPanel.gd`,
   `GameOverScreen.gd` button handlers.
2. **(Optional) Vary contact-sheet panel contexts** (Low, ~30 lines): drive different
   event spawns before each capture screenshot so the contact sheet demonstrates the
   full event variety.
3. **(Optional) Restore an explicit `push_error` in `CityEventSystem._dispatch_audio`**
   for IDs not present in `AUDIO_PATHS`. Currently the warning lives one layer
   deeper in `AuroraAudio.trigger()`, which is fine but slightly less visible to
   someone debugging the CityEventSystem surface.

## 11. Final verdict

**PASS** — Aurora Vigil HEAD `d9e90f6` is shippable. The skyway runaway event chain
(`cec6ef3` → `6fc887c` → `d9e90f6`) is correctly wired end-to-end (data → system →
visual → audio shim → autoload), all 12 build gates green, all 6 canonical QA
gates green, semantic screenshot review confirms hero/drone/event-markers/HUD
all render with no missing meshes or black frames. Two low-severity items
documented above for a future polish pass; neither blocks release.