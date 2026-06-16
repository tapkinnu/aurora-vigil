# Aurora Vigil — QA Gates

## Visual gates
- Screenshots must show a real 3D city, readable skyline, visible hero, HUD objectives, and active dynamic event markers.
- World characters cannot be 2D cards, lineup panels, or Sprite3D character cutouts in final release builds.
- Procedural articulated placeholder hero is acceptable for foundation only; release needs real 3D character assets.
- No black screen, missing texture checkerboards, or greybox-only release screenshots.

## Gameplay gates
- Player can fly freely in 3D with vertical movement and boost.
- At least three dynamic event types can spawn and resolve.
- Story missions have objectives, progression rewards, and visible HUD state.
- Progression unlocks powers over levels; not all powers are unlocked at start.

## Technical gates
- `./tools/validate_build.sh` exits 0 and prints `AURORA_VALIDATE: PASS`.
- `./tools/capture_screenshots.sh <outdir>` exits 0 and prints `AURORA_SCREENSHOT: PASS`.
- `python3 tools/check_audio_wiring.py --require-existing-audio` exits 0.
- Contact sheet must be visually inspected after major visual changes.

## Anti-IP-copy gates
- No Superman, Clark Kent, Krypton, Daily Planet, Metropolis, S-symbol, red-blue costume, Lois/Luthor/Zod analog names, or recognizably copied story beats.
- Broad powers are allowed; concrete expression must remain original.
