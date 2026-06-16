# Aurora Vigil

Original 3D superhero sandbox game built in Godot 4.4.1.

You play as **The Lumen**, an original solar-charged guardian learning to protect Meridian City without becoming an occupying force. The game targets open-city flight, dynamic rescue/crime/disaster events, story missions, and RPG-style power progression.

## Current playable foundation

- 3D city sandbox blockout with readable skyline and objective markers.
- Free-flight superhero controls:
  - `WASD` horizontal flight
  - `Space` ascend
  - `Ctrl` descend
  - `Shift` boost
  - `F` radiant beam
  - `Q` sonic burst
  - `E` aegis field
  - `R` rescue lift
- Dynamic event seed system: tower fires, rogue drones, bridge collapse, and power surges.
- Story mission spine: tutorial patrol → rescue → drone chase → level-up power unlock path.
- Procedural articulated hero placeholder with original teal/gold visual identity.

## Verification

```bash
./tools/validate_build.sh
./tools/capture_screenshots.sh /tmp/aurora_vigil/screens
python3 tools/check_audio_wiring.py --require-existing-audio
```

## IP policy

Aurora Vigil must remain original. It can use broad superhero fantasy conventions — flight, strength, rescue, city patrol, radiant powers — but must not copy Superman names, symbols, costumes, lore, locations, villains, logos, or story beats.
