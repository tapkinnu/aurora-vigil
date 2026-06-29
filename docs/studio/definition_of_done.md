# Aurora Vigil — Definition of Done

## Required commands

Godot binary:
`/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64`

Build/import/logic/smoke:
`./tools/validate_build.sh`

Screenshots:
`./tools/capture_screenshots.sh /tmp/aurora_vigil_release/screens`

Audio wiring:
`python3 tools/check_audio_wiring.py --require-existing-audio`

## Required release content

- Playable 3D city flight sandbox.
- Dynamic city events with event resolution and XP rewards.
- Story mission chain with at least 6 missions for release.
- Level progression with at least 6 unlockable powers.
- Save/load for level, XP, powers, mission state, city trust, and completed events.
- Real 3D hero, civilians, drones/enemies, major props, and imported runtime city dressing; no world-character 2D card composites.
- Music, SFX, and voice/city radio barks with provenance in `assets/audio/SOURCES.md`.
- README, controls, screenshots/contact sheet, and release artifact package.

## Release invariant

Do not release until Kanban has current completed Verification PASS and QA PASS cards with exact commands, exit codes, artifact paths, and current commit context.
