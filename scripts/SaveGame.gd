class_name SaveGame
extends RefCounted

# Persistent save/load for Aurora Vigil. Serializes the cross-system run state
# (progression, mission step, resolved-event count, plus optional hero pose /
# power-usage / objective telemetry) to a JSON file under user://.
#
# Saves are versioned. v2 is the current schema; v1 payloads are migrated forward
# on load. The migration policy is the source of truth that tools/verify_save_load.py
# mirrors in pure Python — keep the two consistent.
#
# Kept as a thin static module so Main.gd and tests can drive it without holding a
# live instance, and so progression rules stay in ProgressionModel.

const SAVE_PATH := "user://aurora_vigil_save.json"
const SAVE_VERSION := 2
const CURRENT_SCHEMA_ID := "aurora_vigil_save_v2"
const SUPPORTED_VERSIONS := [1, 2]

# Default hero spawn pose used when migrating a v1 save that never stored one.
const DEFAULT_HERO_POSITION := [0.0, 28.0, 36.0]

# Builds a plain-dictionary v2 snapshot. mission_holder must expose `mission_step`;
# event_holder must expose `resolved_events`. progression must be a ProgressionModel.
# The trailing fields are optional run telemetry and default to safe empties.
static func capture(
		progression: ProgressionModel,
		mission_holder,
		event_holder,
		hero_position: Vector3 = Vector3.ZERO,
		powers_used: Dictionary = {},
		objectives_completed: Array[String] = []) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"schema_id": CURRENT_SCHEMA_ID,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"progression": progression.save_state(),
		"mission_step": mission_holder.mission_step,
		"resolved_events": event_holder.resolved_events,
		"hero_position": [hero_position.x, hero_position.y, hero_position.z],
		"powers_used": powers_used.duplicate(true),
		"objectives_completed": objectives_completed.duplicate(),
	}

# Migrates an arbitrary (possibly older) payload to the v2 shape.
#   * missing `version` is treated as v1;
#   * v1 is upgraded by copying known fields and backfilling the new ones;
#   * v2 is normalized in place (missing keys filled, schema_id left untouched so
#     a v2 payload that lacks the right schema_id is still rejected by apply());
#   * any version greater than SAVE_VERSION returns {"_unsupported_version": v}.
# This is the canonical migration; tools/verify_save_load.py mirrors it.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version > SAVE_VERSION:
		return {"_unsupported_version": version}
	if version == SAVE_VERSION:
		return _normalize_v2(data)
	# Treat anything below the current version as v1 input.
	return _v1_to_v2(data)

static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var prog = data.get("progression", {})
	if typeof(prog) != TYPE_DICTIONARY:
		prog = {}
	return {
		"version": SAVE_VERSION,
		"schema_id": CURRENT_SCHEMA_ID,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"progression": prog.duplicate(true),
		"mission_step": int(data.get("mission_step", 0)),
		"resolved_events": int(data.get("resolved_events", 0)),
		"hero_position": DEFAULT_HERO_POSITION.duplicate(),
		"powers_used": {},
		"objectives_completed": [],
	}

static func _normalize_v2(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out["version"] = SAVE_VERSION
	# schema_id is intentionally preserved as-is; a v2 payload missing the current
	# schema_id must fail the apply() check rather than be silently fixed up.
	out["saved_at_unix"] = int(out.get("saved_at_unix", 0))
	var prog = out.get("progression", {})
	if typeof(prog) != TYPE_DICTIONARY:
		prog = {}
	out["progression"] = prog
	out["mission_step"] = int(out.get("mission_step", 0))
	out["resolved_events"] = int(out.get("resolved_events", 0))
	if typeof(out.get("hero_position")) != TYPE_ARRAY:
		out["hero_position"] = DEFAULT_HERO_POSITION.duplicate()
	if typeof(out.get("powers_used")) != TYPE_DICTIONARY:
		out["powers_used"] = {}
	if typeof(out.get("objectives_completed")) != TYPE_ARRAY:
		out["objectives_completed"] = []
	return out

# Applies a payload (any supported version) to the live systems. Returns true on
# success, false (with a pushed error) when the payload is rejected. optional_systems
# may be a Dictionary carrying additional targets, e.g. {"hero": <Node3D>}, used to
# restore the saved hero pose when available.
static func apply(
		data: Dictionary,
		progression: ProgressionModel,
		mission_holder,
		event_holder,
		optional_systems = null) -> bool:
	if data.has("_unsupported_version"):
		push_error("SaveGame: unsupported save version %s; refusing to load." % str(data["_unsupported_version"]))
		return false
	var version := int(data.get("version", 1))
	if not SUPPORTED_VERSIONS.has(version):
		push_error("SaveGame: save version %d is not supported (supported: %s)." % [version, str(SUPPORTED_VERSIONS)])
		return false
	var migrated := migrate(data)
	if migrated.has("_unsupported_version"):
		push_error("SaveGame: unsupported save version %s after migration." % str(migrated["_unsupported_version"]))
		return false
	if str(migrated.get("schema_id", "")) != CURRENT_SCHEMA_ID:
		push_error("SaveGame: schema_id mismatch (expected '%s', got '%s'); refusing to load." % [CURRENT_SCHEMA_ID, str(migrated.get("schema_id", ""))])
		return false

	var prog = migrated.get("progression", null)
	if typeof(prog) == TYPE_DICTIONARY and progression != null:
		progression.load_state(prog)
	if mission_holder != null:
		mission_holder.mission_step = int(migrated.get("mission_step", mission_holder.mission_step))
	if event_holder != null:
		event_holder.resolved_events = int(migrated.get("resolved_events", event_holder.resolved_events))

	if typeof(optional_systems) == TYPE_DICTIONARY:
		var hero = optional_systems.get("hero", null)
		var hp = migrated.get("hero_position", null)
		if hero != null and typeof(hp) == TYPE_ARRAY and hp.size() == 3:
			var v := Vector3(float(hp[0]), float(hp[1]), float(hp[2]))
			if hero is Node3D:
				(hero as Node3D).global_position = v
			elif hero is Node2D:
				(hero as Node2D).global_position = Vector2(v.x, v.y)
			else:
				push_warning("SaveGame: optional_systems['hero'] is not a Node2D/Node3D; cannot restore position")
	return true

static func save(
		progression: ProgressionModel,
		mission_holder,
		event_holder,
		hero_position: Vector3 = Vector3.ZERO,
		powers_used: Dictionary = {},
		objectives_completed: Array[String] = []) -> Error:
	var data := capture(progression, mission_holder, event_holder, hero_position, powers_used, objectives_completed)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	return OK

# Loads the save file into the supplied systems if present. Returns true when a
# valid save was applied, false when no/invalid save exists (a fresh run). Corrupt
# JSON or a non-dict payload is treated as "no save"; an unsupported version is
# rejected with a pushed error. Never crashes on malformed input.
static func load_into(
		progression: ProgressionModel,
		mission_holder,
		event_holder,
		optional_systems = null) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return apply(parsed, progression, mission_holder, event_holder, optional_systems)
