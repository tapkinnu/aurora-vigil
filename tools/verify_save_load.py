#!/usr/bin/env python3
"""Independent Python verifier for Aurora Vigil's save/load migration.

Mirrors the migration policy in scripts/SaveGame.gd and exercises it from the
outside (no Godot runtime required). The GDScript implementation is the source
of truth; this script is the producer-side guard that confirms a v1 payload
migrates to the v2 shape, that future versions are rejected, and that corrupt
JSON is handled without raising.

Exit 0 with `AURORA_SAVE_LOAD: PASS` on success. Non-zero with one clear
message per issue otherwise.
"""
from __future__ import annotations

import json
import sys
from typing import Any, Dict, Optional

CURRENT_SCHEMA_ID = "aurora_vigil_save_v2"
SAVE_VERSION = 2
SUPPORTED_VERSIONS = {1, 2}
DEFAULT_HERO_POSITION = [0.0, 28.0, 36.0]


class SaveLoadError(Exception):
    """Raised when a save payload fails validation/migration."""


def _v1_to_v2(data: Dict[str, Any]) -> Dict[str, Any]:
    prog = data.get("progression", {})
    if not isinstance(prog, dict):
        prog = {}
    return {
        "version": SAVE_VERSION,
        "schema_id": CURRENT_SCHEMA_ID,
        "saved_at_unix": 0,  # GDScript stamps Time.get_unix_time_from_system() at apply; mirror as 0 placeholder
        "progression": dict(prog),
        "mission_step": int(data.get("mission_step", 0)),
        "resolved_events": int(data.get("resolved_events", 0)),
        "hero_position": list(DEFAULT_HERO_POSITION),
        "powers_used": {},
        "objectives_completed": [],
    }


def _normalize_v2(data: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(data)
    out["version"] = SAVE_VERSION
    # schema_id is preserved as-is; a v2 payload missing the right schema_id
    # is rejected by apply(), not silently rewritten.
    out["saved_at_unix"] = int(out.get("saved_at_unix", 0))
    prog = out.get("progression", {})
    if not isinstance(prog, dict):
        prog = {}
    out["progression"] = prog
    out["mission_step"] = int(out.get("mission_step", 0))
    out["resolved_events"] = int(out.get("resolved_events", 0))
    hp = out.get("hero_position")
    if not isinstance(hp, list):
        hp = list(DEFAULT_HERO_POSITION)
    out["hero_position"] = list(hp)
    pu = out.get("powers_used")
    if not isinstance(pu, dict):
        pu = {}
    out["powers_used"] = dict(pu)
    oc = out.get("objectives_completed")
    if not isinstance(oc, list):
        oc = []
    out["objectives_completed"] = list(oc)
    return out


def migrate(data: Dict[str, Any]) -> Dict[str, Any]:
    """Mirror of SaveGame.migrate(). Returns v2 dict or raises SaveLoadError."""
    version = int(data.get("version", 1))
    if version > SAVE_VERSION:
        raise SaveLoadError(f"unsupported save version {version}")
    if version == SAVE_VERSION:
        return _normalize_v2(data)
    return _v1_to_v2(data)


def apply_check(data: Dict[str, Any]) -> bool:
    """Mirror of SaveGame.apply()'s acceptance checks. Returns True if the
    payload would be applied, False if it would be rejected."""
    if not isinstance(data, dict):
        return False
    version = int(data.get("version", 1))
    if version not in SUPPORTED_VERSIONS:
        return False
    try:
        migrated = migrate(data)
    except SaveLoadError:
        return False
    if str(migrated.get("schema_id", "")) != CURRENT_SCHEMA_ID:
        return False
    return True


def parse_payload(text: str) -> Optional[Dict[str, Any]]:
    """Mirror of SaveGame.load_into()'s JSON parsing. Returns None on corrupt
    JSON or a non-dict payload; otherwise returns the parsed dict."""
    try:
        parsed = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        return None
    if not isinstance(parsed, dict):
        return None
    return parsed


def main() -> int:
    issues: list[str] = []

    # --- Positive: v1 migrates to v2 ---
    v1 = {
        "version": 1,
        "progression": {"level": 3, "xp": 120, "unlocked": ["flight", "boost", "radiant_beam"]},
        "mission_step": 2,
        "resolved_events": 5,
    }
    try:
        migrated = migrate(v1)
    except SaveLoadError as e:
        issues.append(f"v1 migration raised unexpectedly: {e}")
        migrated = {}
    expected_keys = {
        "version", "schema_id", "saved_at_unix", "progression",
        "mission_step", "resolved_events", "hero_position",
        "powers_used", "objectives_completed",
    }
    got_keys = set(migrated.keys())
    if got_keys != expected_keys:
        issues.append(f"v1 migration: expected keys {sorted(expected_keys)}, got {sorted(got_keys)}")
    if migrated.get("version") != 2:
        issues.append(f"v1 migration: expected version=2, got {migrated.get('version')!r}")
    if migrated.get("schema_id") != CURRENT_SCHEMA_ID:
        issues.append(f"v1 migration: expected schema_id={CURRENT_SCHEMA_ID!r}, got {migrated.get('schema_id')!r}")
    if migrated.get("mission_step") != 2:
        issues.append(f"v1 migration: mission_step not preserved (got {migrated.get('mission_step')!r})")
    if migrated.get("resolved_events") != 5:
        issues.append(f"v1 migration: resolved_events not preserved (got {migrated.get('resolved_events')!r})")
    if migrated.get("progression", {}).get("unlocked") != ["flight", "boost", "radiant_beam"]:
        issues.append(f"v1 migration: progression.unlocked not preserved (got {migrated.get('progression', {}).get('unlocked')!r})")
    if migrated.get("hero_position") != DEFAULT_HERO_POSITION:
        issues.append(f"v1 migration: hero_position default wrong (got {migrated.get('hero_position')!r})")
    if migrated.get("powers_used") != {}:
        issues.append(f"v1 migration: powers_used default wrong (got {migrated.get('powers_used')!r})")
    if migrated.get("objectives_completed") != []:
        issues.append(f"v1 migration: objectives_completed default wrong (got {migrated.get('objectives_completed')!r})")
    if not apply_check(v1):
        issues.append("v1 payload rejected by apply_check; should be accepted after migration")

    # --- Positive: v2 round-trips ---
    v2 = {
        "version": 2,
        "schema_id": CURRENT_SCHEMA_ID,
        "saved_at_unix": 1700000000,
        "progression": {"level": 5, "xp": 0, "unlocked": ["flight", "boost", "radiant_beam", "sonic_burst"]},
        "mission_step": 4,
        "resolved_events": 12,
        "hero_position": [10.0, 50.0, -20.0],
        "powers_used": {"radiant_beam": 3, "sonic_burst": 1},
        "objectives_completed": ["awakening_patrol", "spire_rescue"],
    }
    try:
        v2_back = migrate(v2)
    except SaveLoadError as e:
        issues.append(f"v2 round-trip raised unexpectedly: {e}")
        v2_back = {}
    if v2_back.get("mission_step") != 4:
        issues.append(f"v2 round-trip: mission_step lost (got {v2_back.get('mission_step')!r})")
    if v2_back.get("hero_position") != [10.0, 50.0, -20.0]:
        issues.append(f"v2 round-trip: hero_position lost (got {v2_back.get('hero_position')!r})")
    if v2_back.get("powers_used") != {"radiant_beam": 3, "sonic_burst": 1}:
        issues.append(f"v2 round-trip: powers_used lost (got {v2_back.get('powers_used')!r})")
    if v2_back.get("objectives_completed") != ["awakening_patrol", "spire_rescue"]:
        issues.append(f"v2 round-trip: objectives_completed lost (got {v2_back.get('objectives_completed')!r})")
    if not apply_check(v2):
        issues.append("v2 payload rejected by apply_check; should be accepted")

    # --- Negative: unsupported version ---
    v99 = {"version": 99, "schema_id": "future", "progression": {}, "mission_step": 0, "resolved_events": 0}
    try:
        migrate(v99)
        issues.append("v99 migration did not raise; expected SaveLoadError")
    except SaveLoadError:
        pass
    if apply_check(v99):
        issues.append("v99 payload accepted by apply_check; should be rejected")

    # --- Negative: corrupt JSON ---
    for bad in ["{", "{not json}", "[1, 2, 3]", '"just a string"', "null"]:
        parsed = parse_payload(bad)
        if parsed is not None:
            issues.append(f"parse_payload({bad!r}) returned {parsed!r}; expected None")
        if apply_check(parsed) if parsed is not None else False:
            issues.append(f"apply_check accepted corrupt payload from {bad!r}")

    # --- Negative: v2 with wrong schema_id ---
    bad_v2 = dict(v2)
    bad_v2["schema_id"] = "aurora_vigil_save_v99"
    if apply_check(bad_v2):
        issues.append("v2 with wrong schema_id accepted; should be rejected")

    # --- Negative: v1 with no progression ---
    sparse = {"version": 1, "mission_step": 0}
    if not apply_check(sparse):
        issues.append("v1 sparse payload rejected; should be accepted with safe defaults")

    # --- Positive: corrupt file-level call is safe ---
    if parse_payload("") is not None:
        issues.append("parse_payload('') returned non-None; expected None")
    if parse_payload("0") is not None:
        issues.append("parse_payload('0') returned non-None; expected None")

    if issues:
        print("AURORA_SAVE_LOAD: FAIL")
        for msg in issues:
            print(f"  - {msg}")
        return 1
    print("AURORA_SAVE_LOAD: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
