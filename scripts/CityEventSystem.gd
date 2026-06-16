class_name CityEventSystem
extends RefCounted

# Owns Meridian's dynamic emergencies: seeding, procedural timed spawning, the
# in-world beacon/label/VFX for each event kind, rogue-drone motion, off-screen
# waypoint arrows, and power-driven resolution (which advances the mission spine).
# Split out of Main.gd. `host` is the Main Node3D coordinator and supplies the
# scene tree plus shared material/tween/actor-visibility helpers.

const ROGUE_DRONE_SCENE = preload("res://assets/3d/characters/enemies/drone_rogue.glb")
const EVENT_RESOLVE_RADIUS: float = 18.0

var host
var hero: Node3D
var camera: Camera3D
var progression: ProgressionModel
var missions: MissionDirector

var event_nodes: Array[Node3D] = []
var rogue_drone_actor: Node3D
var resolved_events: int = 0
var event_timer: float = 0.0
var next_event_seconds: float = 6.0
var rng := RandomNumberGenerator.new()

var event_waypoint_layer: CanvasLayer
var waypoint_arrows: Array[Control] = []

func setup(host_ref, hero_ref: Node3D, camera_ref: Camera3D, progression_ref: ProgressionModel, missions_ref: MissionDirector) -> void:
	host = host_ref
	hero = hero_ref
	camera = camera_ref
	progression = progression_ref
	missions = missions_ref
	rng.seed = 20260616

func build_waypoint_layer() -> void:
	event_waypoint_layer = CanvasLayer.new()
	event_waypoint_layer.name = "EventWaypoints"
	event_waypoint_layer.layer = 10
	host.add_child(event_waypoint_layer)

func seed_initial() -> void:
	spawn_event("tower_fire", Vector3(-66, 48, -22))
	spawn_event("rogue_drone", Vector3(0, 44, 80))
	spawn_event("bridge_collapse", Vector3(0, 4, 160))

func update(delta: float) -> void:
	event_timer += delta
	for marker in event_nodes.duplicate():
		if not is_instance_valid(marker):
			event_nodes.erase(marker)
			continue
		var kind := str(marker.get_meta("kind", "city_event"))
		if kind == "rogue_drone":
			_update_rogue_drone(marker, delta)
		var dist := hero.position.distance_to(marker.position)
		var label := marker.get_node_or_null("EventLabel") as Label3D
		if label != null:
			var label_name := "Non-lethal civic drone" if kind == "rogue_drone" else format_event_name(kind)
			label.text = "%s\n%.0fm" % [label_name.to_upper(), dist]
			var color := event_color(kind)
			label.modulate = Color(1.0, 1.0, 1.0, 1.0) if dist <= EVENT_RESOLVE_RADIUS else Color(color.r, color.g, color.b, 0.86)
	if event_timer >= next_event_seconds:
		event_timer = 0.0
		next_event_seconds = 8.0 + rng.randf_range(0, 6.0)
		var positions := [Vector3(-92, 46, 44), Vector3(88, 28, -44), Vector3(0, 18, -112), Vector3(112, 32, 78)]
		var types := ["tower_fire", "rogue_drone", "power_surge", "rescue_signal"]
		spawn_event(types[rng.randi_range(0, types.size() - 1)], positions[rng.randi_range(0, positions.size() - 1)])
	_update_waypoint_arrows()

func event_color(kind: String) -> Color:
	match kind:
		"rogue_drone": return Color(0.8, 0.2, 1.0, 1)
		"power_surge": return Color(0.2, 0.85, 1.0, 1)
		"rescue_signal": return Color(1.0, 0.9, 0.2, 1)
		"bridge_collapse": return Color(1.0, 0.55, 0.18, 1)
		"tower_fire": return Color(1, 0.4, 0.1, 1)
		_: return Color(1, 0.4, 0.1, 1)

func spawn_event(kind: String, pos: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = "DynamicEvent_%s" % kind
	marker.position = pos
	marker.set_meta("kind", kind)
	host.add_child(marker)
	event_nodes.append(marker)
	_play_event_spawn_audio(kind)
	var color := event_color(kind)

	# --- Resolution volume ---
	var volume := MeshInstance3D.new()
	volume.name = "ResolutionVolume_%s" % kind
	var volume_mesh := SphereMesh.new()
	volume_mesh.radius = 1.0
	volume_mesh.height = 2.0
	volume.mesh = volume_mesh
	volume.scale = Vector3(EVENT_RESOLVE_RADIUS, EVENT_RESOLVE_RADIUS * 0.35, EVENT_RESOLVE_RADIUS)
	volume.material_override = host._transparent_mat(Color(color.r, color.g, color.b, 0.22), color, 0.22)
	marker.add_child(volume)

	# --- Vertical light pillar ---
	var pillar_height := pos.y
	if pillar_height > 2.0:
		var pillar := MeshInstance3D.new()
		pillar.name = "EventPillar"
		var pillar_mesh := CylinderMesh.new()
		pillar_mesh.top_radius = 0.3
		pillar_mesh.bottom_radius = 0.8
		pillar_mesh.height = pillar_height
		pillar.mesh = pillar_mesh
		pillar.position = Vector3(0, -pillar_height * 0.5, 0)
		pillar.material_override = host._transparent_mat(Color(color.r, color.g, color.b, 0.25), color, 0.6)
		marker.add_child(pillar)

	# --- Main beacon: large, type-distinct shape ---
	var beacon := MeshInstance3D.new()
	beacon.name = "EventBeacon"
	var beacon_mesh: Mesh
	var beacon_scale := Vector3.ONE
	match kind:
		"tower_fire":
			beacon_mesh = CylinderMesh.new()
			beacon_mesh.top_radius = 0.0
			beacon_mesh.bottom_radius = 5.0
			beacon_mesh.height = 10.0
			beacon_scale = Vector3(1.2, 1.2, 1.2)
		"rogue_drone":
			beacon_mesh = SphereMesh.new()
			beacon_mesh.radius = 4.0
			beacon_mesh.height = 8.0
			beacon_scale = Vector3(1.0, 0.6, 1.0)
		"power_surge":
			beacon_mesh = TorusMesh.new()
			beacon_mesh.inner_radius = 3.0
			beacon_mesh.outer_radius = 5.5
			beacon_scale = Vector3(1.0, 1.0, 1.0)
		"rescue_signal":
			beacon_mesh = CylinderMesh.new()
			beacon_mesh.top_radius = 3.5
			beacon_mesh.bottom_radius = 3.5
			beacon_mesh.height = 8.0
			beacon_scale = Vector3(1.0, 1.0, 1.0)
		_:
			beacon_mesh = SphereMesh.new()
			beacon_mesh.radius = 4.0
			beacon_mesh.height = 8.0
			beacon_scale = Vector3(1.0, 1.0, 1.0)
	beacon.mesh = beacon_mesh
	beacon.scale = beacon_scale
	beacon.material_override = host._mat(color, color, 2.0)
	marker.add_child(beacon)

	# --- Pulsing animation ---
	var tween: Tween = host._remember_tween(host.create_tween().set_loops())
	tween.tween_property(beacon, "scale", beacon_scale * 1.35, 0.8)
	tween.tween_property(beacon, "scale", beacon_scale, 0.8)

	# --- Glow ring at base ---
	var glow_ring := MeshInstance3D.new()
	glow_ring.name = "EventGlowRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 4.0
	ring_mesh.outer_radius = 6.0
	glow_ring.mesh = ring_mesh
	glow_ring.position = Vector3(0, -pos.y * 0.3, 0)
	glow_ring.material_override = host._transparent_mat(Color(color.r, color.g, color.b, 0.15), color, 1.0)
	marker.add_child(glow_ring)
	var ring_tween: Tween = host._remember_tween(host.create_tween().set_loops())
	ring_tween.tween_property(glow_ring, "rotation:y", TAU, 4.0)

	# --- Type-specific visuals ---
	if kind == "rogue_drone":
		marker.set_meta("orbit_center", pos)
		marker.set_meta("drift_radius", 10.0)
		marker.set_meta("drift_speed", 0.7)
		var drone_actor := ROGUE_DRONE_SCENE.instantiate() as Node3D
		if drone_actor == null:
			push_error("Failed to load Meshy drone asset: res://assets/3d/characters/enemies/drone_rogue.glb")
			drone_actor = Node3D.new()
		drone_actor.name = "RogueCivicDrone_MeshyActor"
		drone_actor.position = Vector3(0, 18.0, 0)
		drone_actor.scale = Vector3(9.0, 9.0, 9.0)
		drone_actor.rotation_degrees = Vector3(0, 35, -12)
		host._apply_actor_visibility_overrides(drone_actor, Color(1.4, 0.75, 2.0, 1), Color(1.2, 0.35, 1.8, 1), 1.15)
		var drone_light := drone_actor.get_node_or_null("ActorVisibilityLight") as OmniLight3D
		if drone_light != null:
			drone_light.light_energy = 45.0
			drone_light.omni_range = 28.0
		rogue_drone_actor = drone_actor
		marker.add_child(drone_actor)
	elif kind == "tower_fire":
		for i in range(4):
			var spark := MeshInstance3D.new()
			spark.name = "FireSpark_%d" % i
			var spark_mesh := SphereMesh.new()
			spark_mesh.radius = 0.6 + float(i) * 0.3
			spark_mesh.height = 1.2 + float(i) * 0.6
			spark.mesh = spark_mesh
			spark.position = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(1.0, 4.0), rng.randf_range(-2.0, 2.0))
			var spark_color := Color(1.0, 0.3 + float(i) * 0.15, 0.0, 1.0)
			spark.material_override = host._mat(spark_color, spark_color, 2.5)
			marker.add_child(spark)
			var spark_tween: Tween = host._remember_tween(host.create_tween().set_loops())
			spark_tween.tween_property(spark, "position:y", spark.position.y + 3.0, 0.3 + float(i) * 0.1)
			spark_tween.tween_property(spark, "position:y", spark.position.y, 0.3 + float(i) * 0.1)
	elif kind == "power_surge":
		for i in range(3):
			var arc := MeshInstance3D.new()
			arc.name = "PowerArc_%d" % i
			var arc_mesh := TorusMesh.new()
			arc_mesh.inner_radius = 5.0 + float(i) * 1.5
			arc_mesh.outer_radius = 5.5 + float(i) * 1.5
			arc.mesh = arc_mesh
			arc.position = Vector3(0, float(i) * 1.5, 0)
			arc.material_override = host._transparent_mat(Color(0.2, 0.85, 1.0, 0.3), Color(0.2, 0.85, 1.0, 1.0), 1.5)
			marker.add_child(arc)
			var arc_tween: Tween = host._remember_tween(host.create_tween().set_loops())
			arc_tween.tween_property(arc, "rotation:x", arc.rotation.x + TAU, 1.0 + float(i) * 0.5)
	elif kind == "rescue_signal":
		var cross_h := MeshInstance3D.new()
		cross_h.name = "RescueCrossH"
		var cross_h_mesh := BoxMesh.new()
		cross_h_mesh.size = Vector3(8, 0.3, 1.5)
		cross_h.mesh = cross_h_mesh
		cross_h.position = Vector3(0, -pos.y + 1.0, 0)
		cross_h.material_override = host._transparent_mat(Color(1.0, 0.9, 0.2, 0.4), Color(1.0, 0.9, 0.2, 1.0), 1.2)
		marker.add_child(cross_h)
		var cross_v := MeshInstance3D.new()
		cross_v.name = "RescueCrossV"
		var cross_v_mesh := BoxMesh.new()
		cross_v_mesh.size = Vector3(1.5, 0.3, 8)
		cross_v.mesh = cross_v_mesh
		cross_v.position = Vector3(0, -pos.y + 1.0, 0)
		cross_v.material_override = cross_h.material_override
		marker.add_child(cross_v)

	# --- Large floating label with outline ---
	var label := Label3D.new()
	label.name = "EventLabel"
	label.text = kind.replace("_", " ").to_upper()
	label.font_size = 64
	label.billboard = 1
	label.position = Vector3(0, 8.0, 0)
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 4
	marker.add_child(label)

	# --- Ground distance ring ---
	var ground_ring := MeshInstance3D.new()
	ground_ring.name = "EventGroundRing"
	var gr_mesh := TorusMesh.new()
	gr_mesh.inner_radius = EVENT_RESOLVE_RADIUS - 0.5
	gr_mesh.outer_radius = EVENT_RESOLVE_RADIUS + 0.5
	ground_ring.mesh = gr_mesh
	ground_ring.position = Vector3(0, -pos.y + 0.2, 0)
	ground_ring.rotation_degrees = Vector3(90, 0, 0)
	ground_ring.material_override = host._transparent_mat(Color(color.r, color.g, color.b, 0.3), color, 0.8)
	marker.add_child(ground_ring)

func nearest_event() -> Node3D:
	var best: Node3D = null
	var best_dist: float = INF
	for marker in event_nodes:
		if not is_instance_valid(marker):
			continue
		var dist := hero.position.distance_to(marker.position)
		if dist < best_dist:
			best_dist = dist
			best = marker
	return best

func _update_waypoint_arrows() -> void:
	for arrow in waypoint_arrows:
		if is_instance_valid(arrow):
			arrow.queue_free()
	waypoint_arrows.clear()
	if event_waypoint_layer == null:
		return
	var viewport_size := Vector2(1280, 720)
	var margin := 60.0
	for marker in event_nodes:
		if not is_instance_valid(marker):
			continue
		var kind := str(marker.get_meta("kind", "city_event"))
		var color := event_color(kind)
		var screen_pos := camera.unproject_position(marker.position)
		var on_screen := (screen_pos.x >= -margin and screen_pos.x <= viewport_size.x + margin
			and screen_pos.y >= -margin and screen_pos.y <= viewport_size.y + margin)
		if on_screen:
			continue
		var edge_pos := screen_pos
		edge_pos.x = clamp(edge_pos.x, margin, viewport_size.x - margin)
		edge_pos.y = clamp(edge_pos.y, margin, viewport_size.y - margin)
		var center := viewport_size * 0.5
		var angle := (screen_pos - center).angle()
		var arrow := ColorRect.new()
		arrow.size = Vector2(28, 48)
		arrow.position = edge_pos - Vector2(14, 24)
		arrow.rotation = angle
		arrow.color = Color(color.r, color.g, color.b, 0.7)
		var dist := hero.position.distance_to(marker.position)
		var arrow_label := Label.new()
		arrow_label.text = "%s %.0fm" % [kind.replace("_", " ").capitalize(), dist]
		arrow_label.add_theme_font_size_override("font_size", 14)
		arrow_label.add_theme_color_override("font_color", color)
		arrow_label.position = Vector2(-20, -22)
		arrow.add_child(arrow_label)
		event_waypoint_layer.add_child(arrow)
		waypoint_arrows.append(arrow)

func _event_reward(kind: String) -> int:
	match kind:
		"tower_fire":
			return 70
		"rescue_signal":
			return 95
		"rogue_drone":
			return 110
		"power_surge":
			return 125
		"bridge_collapse":
			return 85
		_:
			return 60

func format_event_name(kind: String) -> String:
	return kind.replace("_", " ").capitalize()

func required_action_for_event(kind: String) -> String:
	match kind:
		"tower_fire":
			return "Use F radiant beam to vent heat"
		"rescue_signal", "bridge_collapse":
			return "Use R rescue lift near civilians"
		"rogue_drone":
			return "Use Q sonic burst for non-lethal shutdown"
		"power_surge":
			return "Use E aegis field to ground the surge"
		_:
			return "Use any unlocked power in the volume"

func _power_matches_event(power_id: String, kind: String) -> bool:
	match kind:
		"tower_fire":
			return power_id == "radiant_beam"
		"rescue_signal", "bridge_collapse":
			return power_id == "rescue_lift"
		"rogue_drone":
			return power_id == "sonic_burst"
		"power_surge":
			return power_id == "aegis_field"
		_:
			return true

func attempt_resolve_nearest(power_id: String) -> bool:
	var marker := nearest_event()
	if marker == null:
		return false
	var kind := str(marker.get_meta("kind", "city_event"))
	var dist := hero.position.distance_to(marker.position)
	if dist > EVENT_RESOLVE_RADIUS:
		host.last_event_text = "%s is %.0fm away; enter the %.0fm resolution volume first." % [format_event_name(kind), dist, EVENT_RESOLVE_RADIUS]
		return false
	if not _power_matches_event(power_id, kind):
		host.last_event_text = "%s needs: %s." % [format_event_name(kind), required_action_for_event(kind)]
		return false
	_resolve_event(marker, power_id)
	return true

func _resolve_event(marker: Node3D, power_id: String) -> void:
	var kind := str(marker.get_meta("kind", "city_event"))
	var event_xp := int(marker.get_meta("reward_xp", _event_reward(kind)))
	var gained: Array[String] = progression.add_xp(event_xp)
	resolved_events += 1
	event_nodes.erase(marker)
	host.last_event_text = "Resolved %s with %s: +%d XP" % [format_event_name(kind), power_id.replace("_", " "), event_xp]
	_play_event_resolve_audio(kind)
	if gained.size() > 0:
		host.last_event_text += " | unlocked %s" % ", ".join(gained)
	host.last_event_text += missions.advance_for_event(kind)
	if is_instance_valid(marker):
		marker.queue_free()

func _play_event_spawn_audio(kind: String) -> void:
	match kind:
		"rogue_drone":
			AuroraAudio.trigger("drone_alert")
		"rescue_signal":
			AuroraAudio.trigger("event_alert_rescue_needed")
			AuroraAudio.trigger("civilian_panicked_help")
		"tower_fire":
			AuroraAudio.trigger("event_alert_rescue_needed")
		"power_surge":
			AuroraAudio.trigger("event_alert_rescue_needed")
			AuroraAudio.trigger("null_choir_cmdr_threat")
		"bridge_collapse":
			AuroraAudio.trigger("event_alert_rescue_needed")
			AuroraAudio.trigger("civilian_panicked_help")

func _play_event_resolve_audio(kind: String) -> void:
	match kind:
		"rogue_drone":
			AuroraAudio.trigger("drone_death")
		"rescue_signal", "bridge_collapse":
			AuroraAudio.trigger("civilian_grateful_thanks")
		"tower_fire":
			AuroraAudio.trigger("emergency_dispatcher_dispatch")
		"power_surge":
			AuroraAudio.trigger("civic_grid_alert")

func _update_rogue_drone(marker: Node3D, delta: float) -> void:
	var center: Vector3 = marker.get_meta("orbit_center", marker.position)
	var angle := float(marker.get_meta("drift_angle", 0.0)) + delta * float(marker.get_meta("drift_speed", 0.65))
	var radius := float(marker.get_meta("drift_radius", 10.0))
	marker.set_meta("drift_angle", angle)
	marker.position = center + Vector3(cos(angle) * radius, sin(angle * 0.7) * 4.0, sin(angle) * radius)
	marker.rotate_y(delta * 1.8)
	if is_instance_valid(rogue_drone_actor):
		rogue_drone_actor.rotate_y(delta * 2.4)
