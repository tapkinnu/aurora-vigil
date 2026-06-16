extends Node3D

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")

var hero: Node3D
var camera: Camera3D
var hud_label: Label
var mission_label: Label
var event_nodes: Array[Node3D] = []
var progression: ProgressionModel
var velocity: Vector3 = Vector3.ZERO
var mission_step: int = 0
var event_timer: float = 0.0
var next_event_seconds: float = 6.0
var rng := RandomNumberGenerator.new()

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
	if event_timer >= next_event_seconds:
		event_timer = 0.0
		next_event_seconds = 8.0 + rng.randf_range(0, 6.0)
		var positions := [Vector3(-92, 46, 44), Vector3(88, 28, -44), Vector3(0, 18, -112), Vector3(112, 32, 78)]
		var types := ["tower_fire", "rogue_drone", "power_surge", "rescue_signal"]
		_spawn_event(types[rng.randi_range(0, types.size() - 1)], positions[rng.randi_range(0, positions.size() - 1)])

func _spawn_event(kind: String, pos: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = "DynamicEvent_%s" % kind
	marker.position = pos
	add_child(marker)
	event_nodes.append(marker)
	var color := Color(1, 0.4, 0.1, 1)
	if kind == "rogue_drone": color = Color(0.8, 0.2, 1.0, 1)
	elif kind == "power_surge": color = Color(0.2, 0.85, 1.0, 1)
	elif kind == "rescue_signal": color = Color(1.0, 0.9, 0.2, 1)
	_add_part(marker, "EventBeacon", SphereMesh.new(), Vector3.ZERO, Vector3(2.2, 2.2, 2.2), color, color, 1.4)
	var label := Label3D.new()
	label.text = kind.replace("_", " ").to_upper()
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 4, 0)
	label.modulate = color
	marker.add_child(label)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HeroHUD"
	add_child(layer)
	hud_label = Label.new()
	hud_label.name = "LevelPowerHUD"
	hud_label.position = Vector2(24, 20)
	hud_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(hud_label)
	mission_label = Label.new()
	mission_label.name = "MissionHUD"
	mission_label.position = Vector2(24, 78)
	mission_label.add_theme_font_size_override("font_size", 18)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.size = Vector2(720, 90)
	layer.add_child(mission_label)

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
	hud_label.text = "AURORA VIGIL  |  Level %d  XP %d/%d  |  Powers: %s  |  Events: %d" % [progression.level, progression.xp, next_xp, ", ".join(progression.unlocked), event_nodes.size()]
	var m: Dictionary = missions[mission_step]
	mission_label.text = "Story Mission: %s\n%s\nDynamic city events resolve for XP and unlock radiant beam, sonic burst, aegis field, rescue lift, and orbit sprint." % [m["title"], m["objective"]]

func _mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = energy > 0.0
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.55
	mat.metallic = 0.05
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
