#!/usr/bin/env python3
"""Static validator for Aurora Vigil interaction-volume / objective-marker data.

Stdlib only. Reuses the small draft-07 subset validator from validate_data.py to
check data/objective_markers.json against schemas/volumes.schema.json, then runs
the cross-data invariants the in-engine spawner relies on:

  * every marker.target_kind references an existing event kind id;
  * every mission.target_kind references an existing event kind id AND has a
    matching objective marker (so the active mission always has an in-world marker);
  * every timed_spawn.types[] event kind has a matching objective marker entry;
  * every position value the spawner consumes is finite — seed_events positions,
    timed_spawn positions, and the bridge_zone position/size.

Exit 0 with `AURORA_VOLUMES_VALIDATE: PASS`; non-zero with
`AURORA_VOLUMES_VALIDATE: FAIL` and one clear message per issue. Accepts --root so
the negative test can point it at a deliberately broken copy of the data tree.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_data import validate_against_schema  # noqa: E402

EVENTS_REL = "data/events/events.json"
MISSIONS_REL = "data/missions/missions.json"
MARKERS_REL = "data/objective_markers.json"
SCHEMA_REL = "schemas/volumes.schema.json"


def _load_json(path: Path, rel: str, errors: list):
    if not path.exists():
        errors.append(f"{rel}: required file is missing")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        errors.append(f"{rel}: could not parse JSON: {exc}")
        return None


def _all_finite(value) -> bool:
    return isinstance(value, list) and all(
        isinstance(c, (int, float)) and not isinstance(c, bool) and math.isfinite(c)
        for c in value
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Aurora Vigil interaction-volume data.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]), help="repo root")
    args = parser.parse_args()
    root = Path(args.root).resolve()

    errors: list[str] = []

    events = _load_json(root / EVENTS_REL, EVENTS_REL, errors)
    missions = _load_json(root / MISSIONS_REL, MISSIONS_REL, errors)
    markers = _load_json(root / MARKERS_REL, MARKERS_REL, errors)
    schema = _load_json(root / SCHEMA_REL, SCHEMA_REL, errors)

    # 1. Schema-validate the marker data.
    if markers is not None and schema is not None:
        validate_against_schema(markers, schema, schema, MARKERS_REL, errors)

    kind_ids = set()
    if isinstance(events, dict):
        kind_ids = {k.get("id") for k in events.get("kinds", []) if isinstance(k, dict)}

    marker_kinds = set()
    if isinstance(markers, dict):
        # 2. Marker target_kind references must resolve to a real event kind.
        for m in markers.get("markers", []):
            if not isinstance(m, dict):
                continue
            tk = m.get("target_kind")
            marker_kinds.add(tk)
            if tk not in kind_ids:
                errors.append(f"{MARKERS_REL}: marker target_kind '{tk}' is not a known event kind")

        # 3. bridge_zone position/size finite.
        bz = markers.get("bridge_zone", {})
        if isinstance(bz, dict):
            for field in ("position", "size"):
                if field in bz and not _all_finite(bz[field]):
                    errors.append(f"{MARKERS_REL}: bridge_zone {field} must be finite numbers")

    # 4. Every mission target_kind must be a real event kind AND have a marker.
    if isinstance(missions, dict):
        for mission in missions.get("missions", []):
            if not isinstance(mission, dict):
                continue
            tk = mission.get("target_kind")
            mid = mission.get("id")
            if tk not in kind_ids:
                errors.append(f"{MISSIONS_REL}: mission '{mid}' target_kind '{tk}' is not a known event kind")
            if tk not in marker_kinds:
                errors.append(f"{MISSIONS_REL}: mission '{mid}' target_kind '{tk}' has no objective marker entry")

    # 5. All positions the spawner consumes must be finite.
    if isinstance(events, dict):
        for i, se in enumerate(events.get("seed_events", [])):
            if isinstance(se, dict) and not _all_finite(se.get("position")):
                errors.append(f"{EVENTS_REL}: seed_events[{i}] position must be finite numbers")
        ts = events.get("timed_spawn", {})
        if isinstance(ts, dict):
            for i, pos in enumerate(ts.get("positions", [])):
                if not _all_finite(pos):
                    errors.append(f"{EVENTS_REL}: timed_spawn positions[{i}] must be finite numbers")
            for t in ts.get("types", []):
                if t not in marker_kinds:
                    errors.append(f"{EVENTS_REL}: timed_spawn type '{t}' has no objective marker entry")

    if errors:
        print("AURORA_VOLUMES_VALIDATE: FAIL")
        for err in errors:
            print(f" - {err}")
        return 1

    print(
        "AURORA_VOLUMES_VALIDATE: PASS "
        f"markers={len(marker_kinds)} event_kinds={len(kind_ids)} "
        f"missions={len(missions.get('missions', [])) if isinstance(missions, dict) else 0}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
