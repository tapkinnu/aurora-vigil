# Aurora Vigil

Original 3D superhero sandbox game built in Godot 4.4.1.

You play as **The Lumen**, an original solar-charged guardian learning to protect Meridian City without becoming an occupying force. The game targets open-city flight, dynamic rescue/crime/disaster events, story missions, and RPG-style power progression.

## Current state

- 3D city sandbox with neon-cyberpunk aesthetic, readable skyline, and objective markers.
- Real 3D hero (The Lumen) and rogue drone models via Meshy AI pipeline (`tools/meshy_assets.py`).
- Free-flight superhero controls:
  - `WASD` horizontal flight
  - `Space` ascend
  - `Ctrl` descend
  - `Shift` boost (becomes Orbit Sprint when unlocked)
  - `F` radiant beam
  - `Q` sonic burst
  - `E` aegis field
  - `R` rescue lift
- Dynamic event seed system: tower fires, rogue drones, bridge collapse, power surges, transit derailments, and skyway runaways.
- Story mission spine: 10-mission campaign from tutorial patrol through Null Choir conflict, post-crisis grid stabilization, and sky-rail rescue response.
- Real audio pack: SFX, music, and TTS voice barks via FAL/Kenney/ElevenLabs (`tools/audio_pipeline.py`).
- Data-driven missions, events, and powers under `data/` with schema validation.
- Save/load system with v1→v2 migration and verifier.

## Verification

```bash
./tools/validate_build.sh
./tools/capture_screenshots.sh /tmp/aurora_vigil/screens
python3 tools/check_audio_wiring.py --require-existing-audio
```

## IP policy

Aurora Vigil must remain original. It can use broad superhero fantasy conventions — flight, strength, rescue, city patrol, radiant powers — but must not copy Superman names, symbols, costumes, lore, locations, villains, logos, or story beats.
