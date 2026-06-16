extends Node3D

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")

var hero: Node3D
var camera: Camera3D
var hud_label: Label
var mission_label: Label
var event_cue_label: Label
var hud_panel: ColorRect
var mission_panel: ColorRect
var event_nodes: Array[Node3D] = []
var progression: ProgressionModel
var resolved_events: int = 0
var last_event_text: String = "Awaiting first city emergency."
var event_waypoint_layer: CanvasLayer
var waypoint_arrows: Array[Control] = []
var velocity: Vector3 = Vector3.ZERO
var mission_step: int = 0
var event_timer: float = 0.0
var next_event_seconds: float = 6.0
var rng := RandomNumberGenerator.new()

const EVENT_RESOLVE_RADIUS: float = 18.0

var missions: Array[Dictionary] = [
	{"id": "awakening_patrol", "title": "Dawn Patrol", "objective": "Fly through Meridian and answer the first emergency.", "reward_xp": 80},
	{"id": "spire_rescue", "title": "The Burning Spire", "objective": "Rescue civilians from a tower fire before panic spreads.", "reward_xp": 140},
	{"id": "drone_chase", "title": "Ghosts in the Grid", "objective": "Disable rogue civic drones without harming the city.", "reward_xp": 180},
	{"id": "stormwall", "title": "Stormwall Protocol", "objective": "Use unlocked powers to protect Meridian during a citywide surge.", "reward_xp": 260}
]

func _ready() -> void:
	rng.seed = 20260616
	progression = ProgressionModel.new()
	_build_world()
	_build_city()
	_build_hero()
	_build_events_seed()
	_build_hud()
	_update_hud()
	if OS.get_environment("AURORA_CAPTURE_PATH") != "":
		call_deferred("_capture_after_delay")
	elif OS.get_environment("AURORA_AUTO_QUIT") == "1":
		call_deferred("_quit_after_delay")

func _physics_process(delta: float) -> void:
	_handle_flight(delta)
	_update_camera(delta)
	_update_events(delta)
	_update_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				_trigger_power("radiant_beam")
			KEY_Q:
				_trigger_power("sonic_burst")
			KEY_E:
				_trigger_power("aegis_field")
			KEY_R:
				_trigger_power("rescue_lift")

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.025, 0.045, 0.085, 1.0)
	e.ambient_light_color = Color(0.45, 0.55, 0.7, 1.0)
	e.ambient_light_energy = 0.85
	e.fog_enabled = true
	e.fog_density = 0.002
	e.fog_light_color = Color(0.15, 0.25, 0.38, 1.0)
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "MorningIonSun"
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_color = Color(1.0, 0.88, 0.62, 1.0)
	sun.light_energy = 2.0
	add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "MeridianGroundPlane"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(620, 620)
	ground.mesh = ground_mesh
	ground.material_override = _mat(Color(0.04, 0.09, 0.11, 1.0), Color(0.0, 0.08, 0.07, 1.0), 0.08)
	add_child(ground)

	camera = Camera3D.new()
	camera.name = "ThirdPersonFlightCamera"
	camera.fov = 72
	add_child(camera)

func _build_city() -> void:
	var district := Node3D.new()
	district.name = "MeridianCity_DynamicSandboxBlockout"
	add_child(district)
	for x in range(-5, 6):
		for z in range(-5, 6):
			if abs(x) <= 1 and abs(z) <= 1:
				continue
			if (x + z) % 3 == 0:
				continue
			var h: float = 18.0 + float((abs(x * 17 + z * 31) % 38))
			var tower := MeshInstance3D.new()
			tower.name = "SkylineTower_%d_%d" % [x, z]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(9.0, h, 9.0)
			tower.mesh = mesh
			tower.position = Vector3(x * 22.0, h * 0.5, z * 22.0)
			var tone: float = 0.13 + float((x * x + z * z) % 6) * 0.025
			tower.material_override = _mat(Color(tone, tone + 0.05, tone + 0.08, 1.0), Color(0.0, 0.22, 0.32, 1.0), 0.05)
			district.add_child(tower)
			if (x - z) % 2 == 0:
				_add_rooftop_beacon(district, tower.position + Vector3(0, h * 0.5 + 1.0, 0))
	_add_city_avenues(district)

func _add_city_avenues(parent: Node3D) -> void:
	for i in range(-5, 6):
		var road_x := MeshInstance3D.new()
		road_x.name = "AvenueEastWest_%d" % i
		var mx := BoxMesh.new()
		mx.size = Vector3(270, 0.12, 4.0)
		road_x.mesh = mx
		road_x.position = Vector3(0, 0.07, i * 22.0)
		road_x.material_override = _mat(Color(0.015, 0.018, 0.022, 1), Color(0.02, 0.06, 0.08, 1), 0.02)
		parent.add_child(road_x)
		var road_z := MeshInstance3D.new()
		road_z.name = "AvenueNorthSouth_%d" % i
		var mz := BoxMesh.new()
		mz.size = Vector3(4.0, 0.12, 270)
		road_z.mesh = mz
		road_z.position = Vector3(i * 22.0, 0.08, 0)
		road_z.material_override = road_x.material_override
		parent.add_child(road_z)

func _add_rooftop_beacon(parent: Node3D, pos: Vector3) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "RooftopBeacon"
	var mesh := SphereMesh.new()
	mesh.radius = 0.7
	mesh.height = 1.4
	beacon.mesh = mesh
	beacon.position = pos
	beacon.material_override = _mat(Color(0.2, 0.9, 1.0, 1.0), Color(0.2, 0.9, 1.0, 1.0), 0.9)
	parent.add_child(beacon)

func _build_hero() -> void:
	hero = Node3D.new()
	hero.name = "TheLumen_ProceduralArticulatedHero"
	hero.position = Vector3(0, 28, 36)
	add_child(hero)
	_add_part(hero, "Torso", CapsuleMesh.new(), Vector3(0, 0, 0), Vector3(0.8, 1.25, 0.45), Color(0.02, 0.35, 0.42, 1), Color(0.0, 0.7, 0.75, 1), 0.18)
	_add_part(hero, "Head", SphereMesh.new(), Vector3(0, 1.55, 0), Vector3(0.46, 0.46, 0.46), Color(0.94, 0.78, 0.56, 1), Color(1.0, 0.82, 0.4, 1), 0.05)
	_add_part(hero, "LeftArm", CylinderMesh.new(), Vector3(-0.78, 0.28, 0), Vector3(0.18, 0.85, 0.18), Color(0.0, 0.65, 0.66, 1), Color(0.0, 0.9, 0.85, 1), 0.14)
	_add_part(hero, "RightArm", CylinderMesh.new(), Vector3(0.78, 0.28, 0), Vector3(0.18, 0.85, 0.18), Color(0.0, 0.65, 0.66, 1), Color(0.0, 0.9, 0.85, 1), 0.14)
	_add_part(hero, "LeftLeg", CylinderMesh.new(), Vector3(-0.28, -1.08, 0), Vector3(0.2, 0.98, 0.2), Color(0.04, 0.12, 0.22, 1), Color(0.0, 0.5, 0.85, 1), 0.08)
	_add_part(hero, "RightLeg", CylinderMesh.new(), Vector3(0.28, -1.08, 0), Vector3(0.2, 0.98, 0.2), Color(0.04, 0.12, 0.22, 1), Color(0.0, 0.5, 0.85, 1), 0.08)
	_add_part(hero, "ChestAuroraSigil", BoxMesh.new(), Vector3(0, 0.48, -0.42), Vector3(0.46, 0.14, 0.05), Color(1.0, 0.82, 0.18, 1), Color(1.0, 0.78, 0.2, 1), 0.7)
	_add_part(hero, "LeftIonMantleFin", BoxMesh.new(), Vector3(-0.58, 0.22, 0.48), Vector3(0.13, 1.4, 0.65), Color(0.95, 0.65, 0.12, 0.75), Color(1.0, 0.65, 0.1, 1), 0.35)
	_add_part(hero, "RightIonMantleFin", BoxMesh.new(), Vector3(0.58, 0.22, 0.48), Vector3(0.13, 1.4, 0.65), Color(0.95, 0.65, 0.12, 0.75), Color(1.0, 0.65, 0.1, 1), 0.35)

func _add_part(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3, scale_v: Vector3, albedo: Color, emission: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_v
	mi.material_override = _mat(albedo, emission, energy)
	parent.add_child(mi)

func _build_events_seed() -> void:
	_spawn_event("tower_fire", Vector3(-66, 48, -22))
	_spawn_event("rogue_drone", Vector3(42, 34, -65))
	_spawn_event("bridge_collapse", Vector3(0, 4, 74))

func _update_events(delta: float) -> void:
	event_timer += delta
	for marker in event_nodes.duplicate():
		if not is_instance_valid(marker):
			event_nodes.erase(marker)
			continue
		var kind := str(marker.get_meta("kind", "city_event"))
		var dist := hero.position.distance_to(marker.position)
		var label := marker.get_node_or_null("EventLabel") as Label3D
		if label != null:
			label.text = "%s\n%.0fm" % [kind.replace("_", " ").to_upper(), dist]
			var color := _event_color(kind)
			label.modulate = Color(1.0, 1.0, 1.0, 1.0) if dist <= EVENT_RESOLVE_RADIUS else Color(color.r, color.g, color.b, 0.86)
	if event_timer >= next_event_seconds:
		event_timer = 0.0
		next_event_seconds = 8.0 + rng.randf_range(0, 6.0)
		var positions := [Vector3(-92, 46, 44), Vector3(88, 28, -44), Vector3(0, 18, -112), Vector3(112, 32, 78)]
		var types := ["tower_fire", "rogue_drone", "power_surge", "rescue_signal"]
		_spawn_event(types[rng.randi_range(0, types.size() - 1)], positions[rng.randi_range(0, positions.size() - 1)])
	_update_waypoint_arrows()

func _event_color(kind: String) -> Color:
	match kind:
		"rogue_drone": return Color(0.8, 0.2, 1.0, 1)
		"power_surge": return Color(0.2, 0.85, 1.0, 1)
		"rescue_signal": return Color(1.0, 0.9, 0.2, 1)
		"bridge_collapse": return Color(1.0, 0.55, 0.18, 1)
		"tower_fire": return Color(1, 0.4, 0.1, 1)
		_: return Color(1, 0.4, 0.1, 1)

func _spawn_event(kind: String, pos: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = "DynamicEvent_%s" % kind
	marker.position = pos
	marker.set_meta("kind", kind)
	add_child(marker)
	event_nodes.append(marker)
	var color := _event_color(kind)

	# --- Resolution volume ---
	var volume := MeshInstance3D.new()
	volume.name = "ResolutionVolume_%s" % kind
	var volume_mesh := SphereMesh.new()
	volume_mesh.radius = 1.0
	volume_mesh.height = 2.0
	volume.mesh = volume_mesh
	volume.scale = Vector3(EVENT_RESOLVE_RADIUS, EVENT_RESOLVE_RADIUS * 0.35, EVENT_RESOLVE_RADIUS)
	volume.material_override = _transparent_mat(Color(color.r, color.g, color.b, 0.22), color, 0.22)
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
		pillar.material_override = _transparent_mat(Color(color.r, color.g, color.b, 0.25), color, 0.6)
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
	beacon.material_override = _mat(color, color, 2.0)
	marker.add_child(beacon)

	# --- Pulsing animation ---
	var tween := create_tween().set_loops()
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
	glow_ring.material_override = _transparent_mat(Color(color.r, color.g, color.b, 0.15), color, 1.0)
	marker.add_child(glow_ring)
	var ring_tween := create_tween().set_loops()
	ring_tween.tween_property(glow_ring, "rotation:y", TAU, 4.0)

	# --- Type-specific visuals ---
	if kind == "rogue_drone":
		_add_part(marker, "NonLethalDroneBody", BoxMesh.new(), Vector3(0, 0, 0), Vector3(2.2, 0.6, 1.4), Color(0.25, 0.18, 0.38, 1), Color(0.8, 0.25, 1.0, 1), 0.45)
		_add_part(marker, "NonLethalDroneWingL", BoxMesh.new(), Vector3(-2.4, 0, 0), Vector3(1.5, 0.12, 0.4), Color(0.36, 0.24, 0.52, 1), Color(0.8, 0.25, 1.0, 1), 0.35)
		_add_part(marker, "NonLethalDroneWingR", BoxMesh.new(), Vector3(2.4, 0, 0), Vector3(1.5, 0.12, 0.4), Color(0.36, 0.24, 0.52, 1), Color(0.8, 0.25, 1.0, 1), 0.35)
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
			spark.material_override = _mat(spark_color, spark_color, 2.5)
			marker.add_child(spark)
			var spark_tween := create_tween().set_loops()
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
			arc.material_override = _transparent_mat(Color(0.2, 0.85, 1.0, 0.3), Color(0.2, 0.85, 1.0, 1.0), 1.5)
			marker.add_child(arc)
			var arc_tween := create_tween().set_loops()
			arc_tween.tween_property(arc, "rotation:x", arc.rotation.x + TAU, 1.0 + float(i) * 0.5)
	elif kind == "rescue_signal":
		var cross_h := MeshInstance3D.new()
		cross_h.name = "RescueCrossH"
		var cross_h_mesh := BoxMesh.new()
		cross_h_mesh.size = Vector3(8, 0.3, 1.5)
		cross_h.mesh = cross_h_mesh
		cross_h.position = Vector3(0, -pos.y + 1.0, 0)
		cross_h.material_override = _transparent_mat(Color(1.0, 0.9, 0.2, 0.4), Color(1.0, 0.9, 0.2, 1.0), 1.2)
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
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 12.0, 0)
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
	ground_ring.material_override = _transparent_mat(Color(color.r, color.g, color.b, 0.3), color, 0.8)
	marker.add_child(ground_ring)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HeroHUD"
	add_child(layer)

	hud_panel = ColorRect.new()
	hud_panel.name = "TopStatusPanel"
	hud_panel.position = Vector2(12, 10)
	hud_panel.size = Vector2(1008, 52)
	hud_panel.color = Color(0.005, 0.012, 0.028, 0.82)
	hud_panel.z_index = 0
	layer.add_child(hud_panel)

	mission_panel = ColorRect.new()
	mission_panel.name = "ObjectiveEventPanel"
	mission_panel.position = Vector2(12, 72)
	mission_panel.size = Vector2(768, 168)
	mission_panel.color = Color(0.005, 0.012, 0.028, 0.85)
	mission_panel.z_index = 0
	layer.add_child(mission_panel)

	hud_label = Label.new()
	hud_label.name = "LevelPowerHUD"
	hud_label.position = Vector2(24, 20)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_color", Color(0.9, 1.0, 1.0, 1.0))
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hud_label.add_theme_constant_override("shadow_offset_x", 2)
	hud_label.add_theme_constant_override("shadow_offset_y", 2)
	hud_label.z_index = 1
	layer.add_child(hud_label)

	mission_label = Label.new()
	mission_label.name = "MissionHUD"
	mission_label.position = Vector2(24, 78)
	mission_label.add_theme_font_size_override("font_size", 18)
	mission_label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 1.0))
	mission_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	mission_label.add_theme_constant_override("shadow_offset_x", 2)
	mission_label.add_theme_constant_override("shadow_offset_y", 2)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.size = Vector2(720, 90)
	mission_label.z_index = 1
	layer.add_child(mission_label)

	event_cue_label = Label.new()
	event_cue_label.name = "NearestEventDistanceCue"
	event_cue_label.position = Vector2(24, 168)
	event_cue_label.add_theme_font_size_override("font_size", 17)
	event_cue_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.62, 1.0))
	event_cue_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	event_cue_label.add_theme_constant_override("shadow_offset_x", 2)
	event_cue_label.add_theme_constant_override("shadow_offset_y", 2)
	event_cue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_cue_label.size = Vector2(720, 52)
	event_cue_label.z_index = 1
	layer.add_child(event_cue_label)

	# --- Waypoint arrow layer ---
	event_waypoint_layer = CanvasLayer.new()
	event_waypoint_layer.name = "EventWaypoints"
	event_waypoint_layer.layer = 10
	add_child(event_waypoint_layer)

func _handle_flight(delta: float) -> void:
	var input_vec := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_vec.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_vec.z += 1.0
	if Input.is_key_pressed(KEY_A): input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_vec.x += 1.0
	if Input.is_key_pressed(KEY_SPACE): input_vec.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): input_vec.y -= 1.0
	if input_vec.length() > 0:
		input_vec = input_vec.normalized()
	var speed := 34.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 62.0
	velocity = velocity.lerp(input_vec * speed, 4.0 * delta)
	hero.position += velocity * delta
	hero.position.y = clamp(hero.position.y, 5.0, 120.0)
	if velocity.length() > 1.0:
		hero.look_at(hero.position - Vector3(velocity.x, 0.0, velocity.z).normalized(), Vector3.UP)

func _update_camera(delta: float) -> void:
	var offset := Vector3(0, 8, 18)
	if OS.get_environment("AURORA_CAPTURE_MODE") == "city":
		offset = Vector3(18, 18, 34)
	elif OS.get_environment("AURORA_CAPTURE_MODE") == "closeup":
		offset = Vector3(4, 3.0, 8)
	var target := hero.position + offset
	camera.global_position = camera.global_position.lerp(target, clamp(delta * 5.0, 0, 1))
	camera.look_at(hero.position + Vector3(0, 1.2, 0), Vector3.UP)

func _trigger_power(power_id: String) -> void:
	if not progression.has_power(power_id):
		var gained: Array[String] = progression.add_xp(110)
		if gained.has(power_id):
			_spawn_power_flash(power_id)
		return
	_spawn_power_flash(power_id)
	if event_nodes.size() > 0:
		var resolved: Node3D = event_nodes.pop_front()
		if is_instance_valid(resolved):
			resolved.queue_free()
			progression.add_xp(65)

func _spawn_power_flash(power_id: String) -> void:
	var flash := MeshInstance3D.new()
	flash.name = "PowerFlash_%s" % power_id
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	flash.mesh = mesh
	flash.position = hero.position
	var c := Color(0.2, 1.0, 0.9, 1.0)
	if power_id == "radiant_beam": c = Color(1.0, 0.72, 0.22, 1.0)
	if power_id == "sonic_burst": c = Color(0.7, 0.45, 1.0, 1.0)
	if power_id == "aegis_field": c = Color(0.2, 0.65, 1.0, 1.0)
	flash.material_override = _mat(c, c, 1.8)
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3(7, 7, 7), 0.35)
	tween.parallel().tween_property(flash, "transparency", 1.0, 0.35)
	tween.tween_callback(flash.queue_free)

func _update_hud() -> void:
	if hud_label == null: return
	var next_xp: int = progression.xp_for_next()
	hud_label.text = "AURORA VIGIL  |  Level %d  XP %d/%d  |  Powers: %s  |  Active: %d  Resolved: %d" % [progression.level, progression.xp, next_xp, ", ".join(progression.unlocked), event_nodes.size(), resolved_events]
	var safe_step: int = min(mission_step, missions.size() - 1)
	var m: Dictionary = missions[safe_step]
	var complete_text := ""
	if mission_step >= missions.size():
		complete_text = "\nCampaign loop complete — keep answering procedural city events for XP."
	mission_label.text = "Story Mission %d/%d: %s\n%s%s" % [safe_step + 1, missions.size(), m["title"], m["objective"], complete_text]
	var nearest := _nearest_event()
	if nearest == null:
		event_cue_label.text = "Event cue: no active emergencies. %s" % last_event_text
	else:
		var kind := str(nearest.get_meta("kind", "city_event"))
		var dist := hero.position.distance_to(nearest.position)
		var proximity := "IN RANGE" if dist <= EVENT_RESOLVE_RADIUS else "approach %.0fm" % max(dist - EVENT_RESOLVE_RADIUS, 0.0)
		event_cue_label.text = "Nearest: %s — %.0fm (%s). Last: %s" % [kind.replace("_", " ").capitalize(), dist, proximity, last_event_text]

func _nearest_event() -> Node3D:
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
		var color := _event_color(kind)
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

func _mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = energy > 0.0
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.55
	mat.metallic = 0.05
	return mat

func _transparent_mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := _mat(albedo, emission, energy)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

func _capture_after_delay() -> void:
	await get_tree().create_timer(2.5).timeout
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var path: String = OS.get_environment("AURORA_CAPTURE_PATH")
	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(path)
	print("AURORA_SCREENSHOT: ", path, " err=", err, " size=", image.get_width(), "x", image.get_height())
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)

func _quit_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout
	print("AURORA_SMOKE: level=", progression.level, " events=", event_nodes.size(), " hero_y=", hero.position.y)
	get_tree().quit(0)
