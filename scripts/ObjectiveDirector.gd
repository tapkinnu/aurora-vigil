class_name ObjectiveDirector
extends RefCounted

# Thin coordinator for the in-world interaction layer. Keeps Main.gd thin by owning
# the VolumeSpawner, the special-cased BridgeCollapseZone, the active-mission
# ObjectiveMarker, and the per-frame polling that turns the hero's position into
# volume `triggered` signals. Enter triggers are routed to the audio shim and the
# shared HUD cue; resolution itself still flows through the power-driven
# CityEventSystem, so the existing mission-advance / event-resolution logic is
# unchanged.

const VolumeSpawnerScript = preload("res://scripts/VolumeSpawner.gd")
const BridgeCollapseZoneScript = preload("res://scripts/BridgeCollapseZone.gd")
const VolumeAudioShimScript = preload("res://scripts/VolumeAudioShim.gd")
const ObjectiveMarkerScene = preload("res://scenes/objective_marker.tscn")

const DEFAULT_DATA_PATH := "res://data/objective_markers.json"
const DEFAULT_MISSION_POS := Vector3(0, 36, 0)
const DEFAULT_BRIDGE_CENTER := Vector3(0, 0.5, 160.0)
const DEFAULT_BRIDGE_SPAN := Vector3(44.0, 10.0, 14.0)

var host
var hero: Node3D
var camera: Camera3D
var events
var missions

var spawner: VolumeSpawner
var audio_shim: VolumeAudioShim
var bridge_zone: BridgeCollapseZone
var marker: ObjectiveMarker

# target_kind -> { label, icon, enter_audio } from data/objective_markers.json.
var markers: Dictionary = {}
var bridge_config: Dictionary = {}
# Raw payload, exposed for tests/inspection.
var loaded_data: Dictionary = {}

var volumes: Array = []
var _anchor: Node3D
var _last_mission_step: int = -1

func setup(host_ref, hero_ref: Node3D, camera_ref: Camera3D, events_ref, missions_ref, data_path: String = DEFAULT_DATA_PATH) -> void:
	host = host_ref
	hero = hero_ref
	camera = camera_ref
	events = events_ref
	missions = missions_ref
	spawner = VolumeSpawnerScript.new()
	audio_shim = VolumeAudioShimScript.new()
	load_data(data_path)

# Loads the objective-marker table + bridge-zone config. Returns true on success;
# on any parse problem it leaves the lookups empty so spawn_all falls back to
# defaults (every volume still gets a generated label/color).
func load_data(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("ObjectiveDirector: marker data not found at %s; using fallback" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("markers"):
		push_error("ObjectiveDirector: malformed marker data at %s; using fallback" % path)
		return false
	var table := {}
	for entry in parsed["markers"]:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("target_kind"):
			table[str(entry["target_kind"])] = entry
	markers = table
	bridge_config = parsed.get("bridge_zone", {})
	loaded_data = parsed
	return true

# Builds all interaction volumes: one per seed event, the bridge collapse zone, and
# the active-mission objective marker. Parents everything under a single anchor so
# Main stays thin and the layer is easy to inspect/clear.
func spawn_all() -> void:
	_anchor = Node3D.new()
	_anchor.name = "InteractionVolumeLayer"
	host.add_child(_anchor)

	var seed_events: Array = events.seed_events_data if events != null else []
	volumes = spawner.spawn_from_seed_events(_anchor, seed_events, events, markers)
	for v in volumes:
		v.triggered.connect(_on_volume_triggered)

	_build_bridge_zone(seed_events)
	_spawn_objective_marker()

func _build_bridge_zone(seed_events: Array) -> void:
	var center := DEFAULT_BRIDGE_CENTER
	var span := DEFAULT_BRIDGE_SPAN
	# Prefer the seeded bridge_collapse position if present, then any explicit
	# bridge_zone override in the marker data.
	for se in seed_events:
		if typeof(se) == TYPE_DICTIONARY and str(se.get("kind", "")) == "bridge_collapse":
			var p: Array = se.get("position", [center.x, center.y, center.z])
			center = Vector3(float(p[0]), max(float(p[1]), 0.5), float(p[2]))
	if bridge_config.has("position"):
		var bp: Array = bridge_config["position"]
		center = Vector3(float(bp[0]), float(bp[1]), float(bp[2]))
	if bridge_config.has("size"):
		var bs: Array = bridge_config["size"]
		span = Vector3(float(bs[0]), float(bs[1]), float(bs[2]))

	var color: Color = events.event_color("bridge_collapse") if events != null else Color(1.0, 0.55, 0.18, 1.0)
	var enter_triggers: Array[String] = []
	for t in bridge_config.get("enter_audio", ["event_alert_rescue_needed"]):
		enter_triggers.append(str(t))

	bridge_zone = BridgeCollapseZoneScript.new()
	host.add_child(bridge_zone)
	bridge_zone.build(center, span, color, enter_triggers)
	if bridge_zone.volume != null:
		volumes.append(bridge_zone.volume)
		bridge_zone.volume.triggered.connect(_on_volume_triggered)

func _spawn_objective_marker() -> void:
	marker = ObjectiveMarkerScene.instantiate() as ObjectiveMarker
	_anchor.add_child(marker)
	_refresh_active_objective()

# Points the marker at the volume for the active mission's target_kind, spawning a
# dedicated mission volume if no seed event already covers that kind.
func _refresh_active_objective() -> void:
	if missions == null or marker == null:
		return
	_last_mission_step = missions.mission_step
	var target_kind := _active_target_kind()
	if target_kind.is_empty():
		return
	var target := _volume_for_kind(target_kind)
	if target == null:
		target = spawner.spawn_mission_volume(_anchor, target_kind, _default_mission_pos(target_kind), events, markers)
		if target != null:
			volumes.append(target)
			target.triggered.connect(_on_volume_triggered)
	if target == null:
		return
	var color: Color = events.event_color(target_kind) if events != null else Color(0.4, 0.95, 1.0, 1.0)
	var title := "OBJECTIVE: %s" % _active_mission_title()
	var icon: String = str(markers[target_kind].get("icon", "diamond")) if markers.has(target_kind) else "diamond"
	marker.configure(color, title, icon)
	marker.global_position = target.global_position + ObjectiveMarker.HOVER_OFFSET
	marker.set_meta("target_path", target.get_path() if target.is_inside_tree() else NodePath())
	marker.set_meta("target_kind", target_kind)

# Capture-only staging: nudge the active objective's volume (and the marker that
# follows it) to a central, elevated overlook so the city-overview screenshot
# reliably frames at least one objective marker. Mirrors how Main._stage_capture_scene
# already repositions the hero / nearest event for deterministic captures.
func stage_for_capture(mode: String) -> void:
	if mode != "city":
		return
	var target := _volume_for_kind(_active_target_kind())
	if target == null:
		return
	# Park the active objective on the city camera's center ray (camera ~(-24,74,-22)
	# looking at (0,24,0)) so the marker lands mid-frame instead of clipping an edge.
	target.position = Vector3(-8, 28, -8)
	if marker != null:
		marker.global_position = target.global_position + ObjectiveMarker.HOVER_OFFSET

func update(_delta: float) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	for v in volumes:
		if is_instance_valid(v):
			v.notify_point(hero.global_position)
	# Re-point the marker when the campaign advances to a new step.
	if missions != null and missions.mission_step != _last_mission_step:
		_refresh_active_objective()
	# Keep the marker glued above its active volume (positions are static, but this
	# also covers any volume that is repositioned for capture staging).
	if marker != null and marker.has_meta("target_kind"):
		var target := _volume_for_kind(str(marker.get_meta("target_kind")))
		if target != null and is_instance_valid(target):
			marker.global_position = target.global_position + ObjectiveMarker.HOVER_OFFSET

func _on_volume_triggered(volume: InteractionVolume, _source) -> void:
	audio_shim.dispatch_all(volume.triggers)
	if host != null:
		var label: String = events.format_event_name(volume.volume_kind) if events != null else volume.volume_kind
		host.last_event_text = "Entered %s zone — %s" % [label, _required_action(volume.volume_kind)]

func _required_action(kind: String) -> String:
	if events != null:
		return events.required_action_for_event(kind)
	return "use a matching power"

func _active_target_kind() -> String:
	var idx: int = clamp(missions.mission_step, 0, missions.missions.size() - 1)
	if idx < 0 or idx >= missions.missions.size():
		return ""
	return str(missions.missions[idx].get("target_kind", ""))

func _active_mission_title() -> String:
	var idx: int = clamp(missions.mission_step, 0, missions.missions.size() - 1)
	if idx < 0 or idx >= missions.missions.size():
		return "Patrol Meridian"
	return str(missions.missions[idx].get("title", "Patrol Meridian"))

func _volume_for_kind(kind: String) -> InteractionVolume:
	for v in volumes:
		if is_instance_valid(v) and v.volume_kind == kind:
			return v
	return null

func _default_mission_pos(kind: String) -> Array:
	# Reuse a timed-spawn position when available so mission volumes land over real
	# city space rather than a fixed point.
	if events != null and not events.timed_spawn_data.is_empty():
		var positions: Array = events.timed_spawn_data.get("positions", [])
		if positions.size() > 0:
			return positions[abs(kind.hash()) % positions.size()]
	return [DEFAULT_MISSION_POS.x, DEFAULT_MISSION_POS.y, DEFAULT_MISSION_POS.z]
