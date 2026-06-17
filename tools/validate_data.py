#!/usr/bin/env python3
"""Validate Aurora Vigil content data files against their JSON Schemas.

Stdlib only. Parses every data/**/*.json file, validates the three schema-backed
content files (missions, events, powers) against schemas/*.schema.json using a
small draft-07 subset validator, then cross-validates references between them
(target_kind -> event id, required_power -> power id, timed_spawn.types -> event
id, seed_events[].kind -> event id) plus value-shape invariants (color arrays,
vec3 positions, non-negative integer rewards, non-empty audio trigger strings).

Exit 0 with `AURORA_DATA_VALIDATE: PASS`; non-zero with `AURORA_DATA_VALIDATE: FAIL`
and one clear message per issue.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Maps a data file (relative to repo root) to the schema that describes it.
SCHEMA_FOR = {
    "data/missions/missions.json": "schemas/missions.schema.json",
    "data/events/events.json": "schemas/events.schema.json",
    "data/powers/powers.json": "schemas/powers.schema.json",
}


def _type_ok(value, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        # JSON has no int/float distinction for whole-number floats; reject bools.
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return False


def _resolve_ref(ref: str, root_schema: dict):
    if not ref.startswith("#/"):
        raise ValueError(f"unsupported $ref: {ref}")
    node = root_schema
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def validate_against_schema(value, schema: dict, root_schema: dict, path: str, errors: list) -> None:
    """Draft-07 subset: $ref, type, required, properties, additionalProperties,
    items, minItems, maxItems, minLength, minimum, maximum, enum."""
    if "$ref" in schema:
        schema = _resolve_ref(schema["$ref"], root_schema)

    expected = schema.get("type")
    if expected is not None and not _type_ok(value, expected):
        errors.append(f"{path}: expected type {expected}, got {type(value).__name__}")
        return

    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: value {value!r} not in enum {schema['enum']}")

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(f"{path}: string shorter than minLength {schema['minLength']}")

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{path}: value {value} below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{path}: value {value} above maximum {schema['maximum']}")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}: array has {len(value)} items, fewer than minItems {schema['minItems']}")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{path}: array has {len(value)} items, more than maxItems {schema['maxItems']}")
        item_schema = schema.get("items")
        if item_schema is not None:
            for i, item in enumerate(value):
                validate_against_schema(item, item_schema, root_schema, f"{path}[{i}]", errors)

    if isinstance(value, dict):
        props = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required property '{req}'")
        if schema.get("additionalProperties", True) is False:
            for key in value:
                if key not in props:
                    errors.append(f"{path}: unexpected property '{key}'")
        for key, sub in props.items():
            if key in value:
                validate_against_schema(value[key], sub, root_schema, f"{path}.{key}", errors)


def _is_color(value) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 4
        and all(isinstance(c, (int, float)) and not isinstance(c, bool) and 0.0 <= c <= 1.0 for c in value)
    )


def _is_vec3(value) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 3
        and all(isinstance(c, (int, float)) and not isinstance(c, bool) for c in value)
    )


def _is_nonneg_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def cross_validate(missions: dict, events: dict, powers: dict, errors: list) -> None:
    kind_ids = {k.get("id") for k in events.get("kinds", []) if isinstance(k, dict)}
    power_ids = {p.get("id") for p in powers.get("powers", []) if isinstance(p, dict)}

    # Mission target_kind must reference an existing event kind id.
    for m in missions.get("missions", []):
        if not isinstance(m, dict):
            continue
        tk = m.get("target_kind")
        if tk not in kind_ids:
            errors.append(f"missions.json: mission '{m.get('id')}' target_kind '{tk}' is not a known event kind")
        if not _is_nonneg_int(m.get("reward_xp")):
            errors.append(f"missions.json: mission '{m.get('id')}' reward_xp must be a non-negative integer")

    # Event kind value shapes + required_power references.
    for k in events.get("kinds", []):
        if not isinstance(k, dict):
            continue
        kid = k.get("id")
        if not _is_color(k.get("color")):
            errors.append(f"events.json: kind '{kid}' color must be 4 numbers in 0..1")
        if not _is_nonneg_int(k.get("reward_xp")):
            errors.append(f"events.json: kind '{kid}' reward_xp must be a non-negative integer")
        rp = k.get("required_power")
        if rp not in power_ids:
            errors.append(f"events.json: kind '{kid}' required_power '{rp}' is not a known power id")
        for field in ("spawn_audio", "resolve_audio"):
            audio = k.get(field, [])
            if not isinstance(audio, list) or not all(isinstance(a, str) and a for a in audio):
                errors.append(f"events.json: kind '{kid}' {field} must be non-empty strings")

    # seed_events references + positions.
    for i, se in enumerate(events.get("seed_events", [])):
        if not isinstance(se, dict):
            continue
        if se.get("kind") not in kind_ids:
            errors.append(f"events.json: seed_events[{i}] kind '{se.get('kind')}' is not a known event kind")
        if not _is_vec3(se.get("position")):
            errors.append(f"events.json: seed_events[{i}] position must be a 3-element number array")

    # timed_spawn type references + positions.
    ts = events.get("timed_spawn", {})
    if isinstance(ts, dict):
        for t in ts.get("types", []):
            if t not in kind_ids:
                errors.append(f"events.json: timed_spawn type '{t}' is not a known event kind")
        for i, pos in enumerate(ts.get("positions", [])):
            if not _is_vec3(pos):
                errors.append(f"events.json: timed_spawn positions[{i}] must be a 3-element number array")
        mn, mx = ts.get("min_seconds"), ts.get("max_seconds")
        if isinstance(mn, (int, float)) and isinstance(mx, (int, float)) and mx < mn:
            errors.append(f"events.json: timed_spawn max_seconds {mx} is less than min_seconds {mn}")

    # Power value shapes.
    for p in powers.get("powers", []):
        if not isinstance(p, dict):
            continue
        pid = p.get("id")
        if not _is_color(p.get("flash_color")):
            errors.append(f"powers.json: power '{pid}' flash_color must be 4 numbers in 0..1")
        triggers = p.get("audio_triggers", [])
        if not isinstance(triggers, list) or not triggers or not all(isinstance(a, str) and a for a in triggers):
            errors.append(f"powers.json: power '{pid}' audio_triggers must be non-empty strings")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Aurora Vigil content data files.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]), help="repo root (default: repo root)")
    args = parser.parse_args()
    root = Path(args.root).resolve()

    errors: list[str] = []
    parsed: dict[str, object] = {}

    # 1. Parse every data file (catches broken JSON anywhere under data/).
    data_files = sorted((root / "data").rglob("*.json")) if (root / "data").exists() else []
    if not data_files:
        errors.append("no JSON files found under data/")
    for path in data_files:
        try:
            parsed[path.relative_to(root).as_posix()] = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            errors.append(f"{path.relative_to(root).as_posix()}: could not parse JSON: {exc}")

    # 2. Load + validate each schema-backed file against its schema.
    schema_cache: dict[str, dict] = {}
    for rel, schema_rel in SCHEMA_FOR.items():
        if rel not in parsed:
            errors.append(f"{rel}: required data file is missing")
            continue
        schema_path = root / schema_rel
        if not schema_path.exists():
            errors.append(f"{schema_rel}: schema file is missing")
            continue
        try:
            schema = json.loads(schema_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            errors.append(f"{schema_rel}: could not parse schema: {exc}")
            continue
        schema_cache[rel] = schema
        validate_against_schema(parsed[rel], schema, schema, rel, errors)

    # 3. Cross-validate references between the three files (only if all parsed).
    if all(rel in parsed for rel in SCHEMA_FOR):
        cross_validate(
            parsed["data/missions/missions.json"],
            parsed["data/events/events.json"],
            parsed["data/powers/powers.json"],
            errors,
        )

    if errors:
        print("AURORA_DATA_VALIDATE: FAIL")
        for err in errors:
            print(f" - {err}")
        return 1

    print(
        "AURORA_DATA_VALIDATE: PASS "
        f"files={len(data_files)} schemas={len(schema_cache)} "
        f"missions={len(parsed['data/missions/missions.json'].get('missions', []))} "
        f"event_kinds={len(parsed['data/events/events.json'].get('kinds', []))} "
        f"powers={len(parsed['data/powers/powers.json'].get('powers', []))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
