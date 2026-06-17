class_name VolumeSpawner
extends RefCounted

# Converts JSON data (events seed_events + the active mission's target_kind) into
# real InteractionVolume nodes parented to a city anchor. Kept schema-tolerant: a
# data dict missing the required `kind` is skipped (InteractionVolume.from_data
# logs and returns null) instead of crashing the spawn pass. Colors come from the
# CityEventSystem event-kind table so a volume's color always matches its event.

const InteractionVolumeScript = preload("res://scripts/InteractionVolume.gd")

# Kinds with bespoke geometry handled elsewhere (BridgeCollapseZone) and therefore
# skipped by the generic seed-event volume pass.
const SPECIAL_KINDS := ["bridge_collapse"]

# Spawns one trigger volume per seed event (skipping special-cased kinds), parented
# to `anchor`. `events` supplies per-kind colors/display names; `markers` is the
# target_kind -> {label,enter_audio,...} table from data/objective_markers.json.
func spawn_from_seed_events(anchor: Node3D, seed_events: Array, events, markers: Dictionary) -> Array:
	var spawned: Array = []
	for se in seed_events:
		if typeof(se) != TYPE_DICTIONARY:
			continue
		var kind := str(se.get("kind", ""))
		if kind in SPECIAL_KINDS:
			continue
		var pos: Array = se.get("position", [0, 0, 0])
		var volume := spawn_one(anchor, _volume_data(kind, pos, events, markers))
		if volume != null:
			spawned.append(volume)
	return spawned

# Spawns a single mission objective volume for a target_kind at the given position.
# Used when no seed event already exists for the active mission's target_kind.
func spawn_mission_volume(anchor: Node3D, kind: String, pos: Array, events, markers: Dictionary) -> InteractionVolume:
	return spawn_one(anchor, _volume_data(kind, pos, events, markers))

func spawn_one(anchor: Node3D, data: Dictionary) -> InteractionVolume:
	var volume := InteractionVolumeScript.from_data(data)
	if volume == null:
		return null
	anchor.add_child(volume)
	return volume

func _volume_data(kind: String, pos, events, markers: Dictionary) -> Dictionary:
	var color: Color = events.event_color(kind) if events != null else Color(0.5, 0.8, 1.0, 1.0)
	var label: String = events.format_event_name(kind).to_upper() if events != null else kind.to_upper()
	var triggers: Array = []
	if markers.has(kind):
		var entry: Dictionary = markers[kind]
		label = str(entry.get("label", label))
		triggers = entry.get("enter_audio", [])
	return {
		"kind": kind,
		"position": pos,
		"color": [color.r, color.g, color.b, color.a],
		"label": label,
		"triggers": triggers,
	}
