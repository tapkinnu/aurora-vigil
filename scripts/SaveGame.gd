class_name SaveGame
extends RefCounted

# Persistent save/load for Aurora Vigil. Serializes the cross-system run state
# (progression, mission step, resolved-event count) to a JSON file under user://.
# Kept as a thin static module so Main.gd and tests can drive it without holding a
# live instance, and so progression rules stay in ProgressionModel.

const SAVE_PATH := "user://aurora_vigil_save.json"
const SAVE_VERSION := 1

# Builds a plain-dictionary snapshot. mission_holder must expose `mission_step`;
# event_holder must expose `resolved_events`. progression must be a ProgressionModel.
static func capture(progression: ProgressionModel, mission_holder, event_holder) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"progression": progression.save_state(),
		"mission_step": mission_holder.mission_step,
		"resolved_events": event_holder.resolved_events,
	}

static func apply(data: Dictionary, progression: ProgressionModel, mission_holder, event_holder) -> void:
	if data.has("progression") and typeof(data["progression"]) == TYPE_DICTIONARY:
		progression.load_state(data["progression"])
	mission_holder.mission_step = int(data.get("mission_step", mission_holder.mission_step))
	event_holder.resolved_events = int(data.get("resolved_events", event_holder.resolved_events))

static func save(progression: ProgressionModel, mission_holder, event_holder) -> Error:
	var data := capture(progression, mission_holder, event_holder)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	return OK

# Loads the save file into the supplied systems if present. Returns true when a
# valid save was applied, false when no/invalid save exists (a fresh run).
static func load_into(progression: ProgressionModel, mission_holder, event_holder) -> bool:
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
	apply(parsed, progression, mission_holder, event_holder)
	return true
