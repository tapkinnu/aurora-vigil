# Aurora Vigil — Claude Code Project Context

Godot 4.4.1 project. Build a polished original 3D superhero sandbox: city flight, dynamic events, story missions, progression and power unlocks. Do not copy Superman IP.

Key commands:
- `./tools/validate_build.sh`
- `./tools/capture_screenshots.sh /tmp/aurora_vigil/screens`
- `python3 tools/check_audio_wiring.py --require-existing-audio`

## Shared studio harness

One command runs all QA gates and writes a unified PASS/FAIL report:

```bash
python3 /home/ganomix/projects/studio_harness/studio_harness/cli.py run /home/ganomix/projects/aurora-vigil --out /tmp/studio_harness/aurora-vigil
# or: python3 tools/studio_harness.py
```

Report: `/tmp/studio_harness/aurora-vigil/report.md` (+ `report.json`, per-gate `logs/`). Gates:
- `headless_import` — `Godot --headless --import` exits clean with no script/parse errors.
- `repo_validator` — runs `tools/validate_build.sh`; last line must read PASS.
- `screenshots` — `tools/capture_screenshots.sh`; each PNG exists, > 5 KB, non-black.
- `contact_sheet` — `tools/make_contact_sheet.py` builds a sheet (informational only).
- `audio_wiring` — `tools/check_audio_wiring.py --require-existing-audio` exits 0.

Quality bars:
- Real 3D city and in-world hero/enemy/event geometry; no 2D character cards as world actors.
- Playable flight must feel fast, readable, and controllable.
- Dynamic events and story missions must be data-driven enough for content expansion.
- Progression unlocks powers over time, not all powers at start.
- Verification scripts must stay green before commits.
