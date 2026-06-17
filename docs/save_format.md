# Aurora Vigil — Save Format

The persistent save for Aurora Vigil is a single JSON file at
`user://aurora_vigil_save.json`. On Linux this resolves to
`~/.local/share/godot/app_userdata/Aurora Vigil/aurora_vigil_save.json`.

## Current schema: v2

Schema id: `aurora_vigil_save_v2`

```json
{
  "version": 2,
  "schema_id": "aurora_vigil_save_v2",
  "saved_at_unix": 1700000000,
  "progression": {
    "level": 1,
    "xp": 0,
    "unlocked": ["flight", "boost"]
  },
  "mission_step": 0,
  "resolved_events": 0,
  "hero_position": [0.0, 28.0, 36.0],
  "powers_used": {},
  "objectives_completed": []
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `version` | int | Schema version, currently `2`. |
| `schema_id` | string | Must equal `aurora_vigil_save_v2`. |
| `saved_at_unix` | int | UNIX timestamp at save time. |
| `progression` | object | `{level, xp, unlocked[]}`. |
| `mission_step` | int | Index into the mission table. |
| `resolved_events` | int | Total city events resolved. |
| `hero_position` | `[x, y, z]` | Last known hero world position. |
| `powers_used` | `{power_id: count}` | Per-power usage telemetry. |
| `objectives_completed` | `[id]` | Objective ids completed. |

## Migration policy

`scripts/SaveGame.gd` is the source of truth for migration.

* `version` absent → treated as v1 and migrated forward.
* `version == 1` → migrated to v2; new fields backfilled with safe defaults.
* `version == 2` → normalized in place; `schema_id` is preserved as-is.
* `version > 2` → rejected; the payload is not loaded.

After migration, `apply()` rejects any payload whose `schema_id` is not the
current one. A future v3+ schema change must update `CURRENT_SCHEMA_ID` and
add a v2→v3 step in `migrate()`. Old v1 saves continue to load on top of any
future v3+ version because the v1 path is preserved as a stable input.

## Corrupt-save behaviour

* Missing file → `load_into` returns `false`; the game starts a fresh run.
* JSON parse error → `load_into` returns `false`; no crash.
* Non-dict payload → `load_into` returns `false`.
* Unsupported `version` → `load_into` returns `false`; an error is pushed
  to the Godot log so it is visible during QA.

## Verifier

Two independent gates exercise the migration from the outside:

* `tests/test_save_load.gd` runs under Godot and prints
  `AURORA_SAVE_LOAD_GD: PASS` on success.
* `tools/verify_save_load.py` is a pure-Python mirror that prints
  `AURORA_SAVE_LOAD: PASS`.

Both are wired into `tools/validate_build.sh` after the existing
`AURORA_VOLUME_TESTS` step. A fault-injection on either gate (an
unsupported version, a corrupt JSON string, or a payload with the wrong
`schema_id`) exits non-zero with a clear per-issue message.
