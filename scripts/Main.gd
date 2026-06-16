extends Node3D

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")
const LUMEN_SCENE = preload("res://assets/3d/characters/lumen/lumen_body.glb")
const ROGUE_DRONE_SCENE = preload("res://assets/3d/characters/enemies/drone_rogue.glb")

var hero: Node3D
var rogue_drone_actor: Node3D
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
	{"id": "awakening_patrol", "title": "Dawn Patrol", "objective": "Fly through Meridian and answer the first emergency.", "target_kind": "tower_fire", "reward_xp": 80},
	{"id": "spire_rescue", "title": "The Burning Spire", "objective": "Rescue civilians from a tower fire before panic spreads.", "target_kind": "rescue_signal", "reward_xp": 140},
	{"id": "drone_chase", "title": "Ghosts in the Grid", "objective": "Disable rogue civic drones without harming the city.", "target_kind": "rogue_drone", "reward_xp": 180},
	{"id": "stormwall", "title": "Stormwall Protocol", "objective": "Use unlocked powers to protect Meridian during a citywide surge.", "target_kind": "power_surge", "reward_xp": 260}
]

func _ready() -> void:
	rng.seed = 20260616
	_build_audio()
	progression = ProgressionModel.new()
	_build_world()
	_build_city()
	_build_hero()
	_build_events_seed()
	_stage_capture_scene()
	_build_hud()
	_update_hud()
	if OS.get_environment("AURORA_CAPTURE_PATH") != "":
		call_deferred("_capture_after_delay")
	elif OS.get_environment("AURORA_AUTO_QUIT") == "1":
		call_deferred("_quit_after_delay")

func _build_audio() -> void:
	AuroraAudio.start_loop("ambience_city_base_loop")
	AuroraAudio.start_loop("music_city_exploration")
	AuroraAudio.trigger("stinger_mission_intro")

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
	district.name = "MeridianCity_ModularSkyline"
	add_child(district)
	_add_ground_plate(district)
	for x in range(-5, 6):
		for z in range(-5, 6):
			if abs(x) <= 1 and abs(z) <= 1:
				continue
			if (x + z) % 3 == 0:
				continue
			var is_collector: bool = abs(x) == 5 and abs(z) == 5
			var width: float = 8.5 + float((abs(x * 7 + z * 11) % 4))
			var depth: float = 8.5 + float((abs(x * 13 + z * 5) % 4))
			if is_collector:
				width = 11.0
				depth = 11.0
			var h: float = 18.0 + float((abs(x * 17 + z * 31) % 38))
			if is_collector:
				h += 18.0
			var tower_body := StaticBody3D.new()
			tower_body.name = "SkylineTower_%d_%d" % [x, z]
			tower_body.position = Vector3(x * 22.0, h * 0.5, z * 22.0)
			district.add_child(tower_body)

			var tower := MeshInstance3D.new()
			tower.name = "TexturedTowerShell"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(width, h, depth)
			tower.mesh = mesh
			tower.material_override = _city_facade_material(h, x, z, width, depth, is_collector)
			tower_body.add_child(tower)

			_add_floor_strips(tower_body, width, depth, h)
			_add_vertical_ribs(tower_body, width, depth, h, is_collector)
			_add_roof_detail(tower_body, width, depth, h, x, z, is_collector)

			var shape := CollisionShape3D.new()
			shape.name = "TowerCollision"
			var box := BoxShape3D.new()
			box.size = Vector3(width, h, depth)
			shape.shape = box
			tower_body.add_child(shape)

			if is_collector or (x - z) % 2 == 0:
				_add_rooftop_beacon(tower_body, Vector3(0, h * 0.5 + 3.8, 0), is_collector)
	_add_civic_grid(district)
	_add_skyline_props(district)
	_add_city_avenues(district)
	_add_transit_corridor(district)

func _add_city_avenues(parent: Node3D) -> void:
	var road_mat := _mat(Color(0.012, 0.016, 0.022, 1.0), Color(0.015, 0.05, 0.075, 1.0), 0.02)
	var lane_mat := _mat(Color(0.55, 0.85, 1.0, 1.0), Color(0.25, 0.75, 1.0, 1.0), 0.55)
	for i in range(-5, 6):
		var road_x := MeshInstance3D.new()
		road_x.name = "AvenueEastWest_%d" % i
		var mx := BoxMesh.new()
		mx.size = Vector3(270, 0.12, 4.2)
		road_x.mesh = mx
		road_x.position = Vector3(0, 0.07, i * 22.0)
		road_x.material_override = road_mat
		parent.add_child(road_x)
		var road_z := MeshInstance3D.new()
		road_z.name = "AvenueNorthSouth_%d" % i
		var mz := BoxMesh.new()
		mz.size = Vector3(4.2, 0.12, 270)
		road_z.mesh = mz
		road_z.position = Vector3(i * 22.0, 0.08, 0)
		road_z.material_override = road_mat
		parent.add_child(road_z)
		for j in range(-5, 6):
			var dash_x := MeshInstance3D.new()
			dash_x.name = "LaneDashEW_%d_%d" % [i, j]
			var dx := BoxMesh.new()
			dx.size = Vector3(5.0, 0.05, 0.22)
			dash_x.mesh = dx
			dash_x.position = Vector3(j * 22.0, 0.16, i * 22.0)
			dash_x.material_override = lane_mat
			parent.add_child(dash_x)
			var dash_z := MeshInstance3D.new()
			dash_z.name = "LaneDashNS_%d_%d" % [i, j]
			var dz := BoxMesh.new()
			dz.size = Vector3(0.22, 0.05, 5.0)
			dash_z.mesh = dz
			dash_z.position = Vector3(i * 22.0, 0.17, j * 22.0)
			dash_z.material_override = lane_mat
			parent.add_child(dash_z)
		if i in [-4, -2, 2, 4]:
			_add_streetlight(parent, Vector3(-11.0, 0.0, i * 22.0), 0.0)
			_add_streetlight(parent, Vector3(11.0, 0.0, i * 22.0), PI)
			_add_streetlight(parent, Vector3(i * 22.0, 0.0, -11.0), PI * 0.5)
			_add_streetlight(parent, Vector3(i * 22.0, 0.0, 11.0), -PI * 0.5)

func _add_civic_grid(parent: Node3D) -> void:
	var grid := Decal.new()
	grid.name = "CivicGrid_Decal"
	grid.position = Vector3(0, 0.42, 0)
	grid.size = Vector3(128.0, 0.2, 128.0)
	grid.texture_albedo = _city_texture("grid", Color(0.0, 0.0, 0.0, 0.0), Color(0.28, 0.9, 1.0, 0.9), Color(0.04, 0.16, 0.22, 0.35))
	parent.add_child(grid)

func _add_ground_plate(parent: Node3D) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "ModularDistrictGroundPlate"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(260.0, 0.18, 260.0)
	ground.mesh = mesh
	ground.position = Vector3(0, -0.09, 0)
	ground.material_override = _mat(Color(0.035, 0.045, 0.055, 1.0), Color(0.0, 0.03, 0.05, 1.0), 0.02)
	ground.material_override.albedo_texture = _city_texture("ground", Color(0.03, 0.045, 0.055, 1.0), Color(0.18, 0.55, 0.7, 0.75), Color(0.0, 0.0, 0.0, 0.0))
	parent.add_child(ground)

func _add_skyline_props(parent: Node3D) -> void:
	var accent_mat := _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.15, 0.75, 1.0, 1.0), 0.85)
	var magenta_mat := _mat(Color(0.9, 0.25, 0.75, 1.0), Color(0.7, 0.05, 0.45, 1.0), 0.75)
	for x in [-66.0, 66.0]:
		for z in [-66.0, 66.0]:
			_add_plaza_pylon(parent, Vector3(x, 0.0, z), accent_mat if x > 0.0 else magenta_mat)
	_add_city_prop(parent, "NorthSignalArray", Vector3(0, 0.0, -112.0), Vector3(0, 90, 0), accent_mat)
	_add_city_prop(parent, "SouthSignalArray", Vector3(0, 0.0, 112.0), Vector3(0, 90, 0), magenta_mat)
	_add_city_prop(parent, "WestRelayStack", Vector3(-112.0, 0.0, 0), Vector3(0, 0, 0), accent_mat)
	_add_city_prop(parent, "EastRelayStack", Vector3(112.0, 0.0, 0), Vector3(0, 0, 0), magenta_mat)
	_add_box(parent, "SkybridgeWestEast", Vector3(120.0, 0.55, 0.55), Vector3(0, 24.0, 0), accent_mat)
	_add_box(parent, "SkybridgeNorthSouth", Vector3(0.55, 0.55, 120.0), Vector3(0, 24.0, 0), magenta_mat)
	var arch := MeshInstance3D.new()
	arch.name = "CentralSkyArch"
	var arch_mesh := TorusMesh.new()
	arch_mesh.inner_radius = 28.0
	arch_mesh.outer_radius = 28.35
	arch.mesh = arch_mesh
	arch.position = Vector3(0, 24.0, 0)
	arch.rotation_degrees = Vector3(90, 0, 0)
	arch.material_override = _transparent_mat(Color(0.25, 0.9, 1.0, 0.12), Color(0.2, 0.8, 1.0, 1.0), 0.9)
	parent.add_child(arch)

func _add_plaza_pylon(parent: Node3D, pos: Vector3, mat: Material) -> void:
	var pylon := Node3D.new()
	pylon.name = "PlazaPylon"
	pylon.position = pos
	parent.add_child(pylon)
	_add_box(pylon, "PylonShaft", Vector3(1.2, 18.0, 1.2), Vector3(0, 9.0, 0), _mat(Color(0.06, 0.12, 0.16, 1.0), Color(0.0, 0.25, 0.35, 1.0), 0.12))
	var cap := MeshInstance3D.new()
	cap.name = "PylonCore"
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 1.5
	cap_mesh.height = 3.0
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 18.5, 0)
	cap.material_override = mat
	pylon.add_child(cap)
	var light := OmniLight3D.new()
	light.name = "PylonGlow"
	light.position = cap.position
	light.light_color = Color(0.2, 0.85, 1.0, 1.0)
	light.light_energy = 7.0
	light.omni_range = 20.0
	pylon.add_child(light)

func _add_city_prop(parent: Node3D, name: String, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var prop := Node3D.new()
	prop.name = name
	prop.position = pos
	prop.rotation_degrees = rot
	parent.add_child(prop)
	_add_box(prop, "RelayBase", Vector3(12.0, 1.0, 8.0), Vector3(0, 0.5, 0), _mat(Color(0.05, 0.1, 0.14, 1.0), Color(0.0, 0.2, 0.28, 1.0), 0.12))
	_add_box(prop, "RelayCore", Vector3(5.0, 14.0, 5.0), Vector3(0, 7.0, 0), mat)
	_add_box(prop, "RelayCrossA", Vector3(16.0, 0.55, 0.55), Vector3(0, 14.0, 0), mat)
	_add_box(prop, "RelayCrossB", Vector3(0.55, 0.55, 16.0), Vector3(0, 14.0, 0), mat)
	for side in [-1.0, 1.0]:
		var dish := MeshInstance3D.new()
		dish.name = "SignalDish_%s" % str(side)
		var dish_mesh := CylinderMesh.new()
		dish_mesh.top_radius = 1.0
		dish_mesh.bottom_radius = 1.4
		dish_mesh.height = 0.45
		dish.mesh = dish_mesh
		dish.position = Vector3(side * 6.2, 14.0, 0)
		dish.rotation_degrees = Vector3(90, 0, 0)
		dish.material_override = mat
		prop.add_child(dish)
	var light := OmniLight3D.new()
	light.name = "RelayGlow"
	light.position = Vector3(0, 14.0, 0)
	light.light_color = Color(0.2, 0.85, 1.0, 1.0)
	light.light_energy = 10.0
	light.omni_range = 24.0
	prop.add_child(light)

func _add_transit_corridor(parent: Node3D) -> void:
	for i in [-4, -2, 2, 4]:
		_add_transit_support(parent, Vector3(0, 0.0, i * 22.0), false)
		_add_transit_support(parent, Vector3(i * 22.0, 0.0, 0), true)
	var gate := _add_transit_support(parent, Vector3(0, 0.0, 0), false)
	gate.name = "CentralTransitGate"
	var beam := gate.get_node_or_null("TransitBeam") as MeshInstance3D
	if beam != null:
		beam.scale = Vector3(1.35, 1.0, 1.0)

func _add_transit_support(parent: Node3D, pos: Vector3, rotate_beam: bool) -> Node3D:
	var support := Node3D.new()
	support.name = "TransitSupport"
	support.position = pos
	parent.add_child(support)
	var mast_mat := _mat(Color(0.08, 0.13, 0.18, 1.0), Color(0.0, 0.25, 0.38, 1.0), 0.12)
	var glow_mat := _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.2, 0.8, 1.0, 1.0), 0.8)
	_add_box(support, "LeftMast", Vector3(0.35, 16.0, 0.35), Vector3(-3.6, 8.0, 0.0), mast_mat)
	_add_box(support, "RightMast", Vector3(0.35, 16.0, 0.35), Vector3(3.6, 8.0, 0.0), mast_mat)
	var beam := _add_box(support, "TransitBeam", Vector3(8.2, 0.45, 0.45), Vector3(0, 16.0, 0.0), glow_mat)
	if rotate_beam:
		beam.rotation_degrees = Vector3(0, 90, 0)
	var light := OmniLight3D.new()
	light.name = "TransitGlow"
	light.position = Vector3(0, 15.8, 0)
	light.light_color = Color(0.2, 0.85, 1.0, 1.0)
	light.light_energy = 8.0
	light.omni_range = 18.0
	support.add_child(light)
	return support

func _add_streetlight(parent: Node3D, pos: Vector3, rot: float) -> void:
	var light := Node3D.new()
	light.name = "StreetLight"
	light.position = pos
	light.rotation_degrees = Vector3(0, rad_to_deg(rot), 0)
	parent.add_child(light)
	_add_box(light, "StreetLightPole", Vector3(0.18, 5.5, 0.18), Vector3(0, 2.75, 0), _mat(Color(0.05, 0.08, 0.11, 1.0), Color(0.0, 0.18, 0.25, 1.0), 0.08))
	_add_box(light, "StreetLightArm", Vector3(1.8, 0.16, 0.16), Vector3(0.85, 5.35, 0.0), _mat(Color(0.08, 0.12, 0.16, 1.0), Color(0.0, 0.18, 0.25, 1.0), 0.08))
	var bulb := MeshInstance3D.new()
	bulb.name = "StreetLightGlow"
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.35
	bulb_mesh.height = 0.7
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(1.85, 5.35, 0)
	bulb.material_override = _mat(Color(0.9, 0.95, 1.0, 1.0), Color(0.55, 0.85, 1.0, 1.0), 1.1)
	light.add_child(bulb)
	var omni := OmniLight3D.new()
	omni.name = "StreetLightOmni"
	omni.position = bulb.position
	omni.light_color = Color(0.55, 0.85, 1.0, 1.0)
	omni.light_energy = 3.0
	omni.omni_range = 10.0
	light.add_child(omni)

func _add_floor_strips(parent: Node3D, width: float, depth: float, h: float) -> void:
	var rows := int(clamp(h / 4.2, 5.0, 11.0))
	var window_mat := _mat(Color(0.42, 0.88, 1.0, 1.0), Color(0.28, 0.8, 1.0, 1.0), 0.42)
	var pod_mat := _mat(Color(0.18, 0.32, 0.38, 1.0), Color(0.0, 0.45, 0.6, 1.0), 0.28)
	for r in range(rows):
		var y := -h * 0.45 + (float(r) + 0.5) * h / float(rows)
		_add_box(parent, "WindowStripFront_%d" % r, Vector3(width + 0.08, 0.07, 0.13), Vector3(0, y, depth * 0.5 + 0.08), window_mat)
		_add_box(parent, "WindowStripBack_%d" % r, Vector3(width + 0.08, 0.07, 0.13), Vector3(0, y, -depth * 0.5 - 0.08), window_mat)
		if width >= depth:
			_add_box(parent, "WindowStripLeft_%d" % r, Vector3(0.13, 0.07, depth + 0.08), Vector3(-width * 0.5 - 0.08, y, 0), window_mat)
			_add_box(parent, "WindowStripRight_%d" % r, Vector3(0.13, 0.07, depth + 0.08), Vector3(width * 0.5 + 0.08, y, 0), window_mat)
	for r in range(2, max(3, rows - 1), 3):
		var y := -h * 0.32 + float(r) * h / float(rows)
		_add_box(parent, "FrontServicePod_%d" % r, Vector3(2.4, 0.75, 1.15), Vector3(-width * 0.22, y, depth * 0.5 + 0.48), pod_mat)
		_add_box(parent, "BackServicePod_%d" % r, Vector3(2.4, 0.75, 1.15), Vector3(width * 0.22, y, -depth * 0.5 - 0.48), pod_mat)

func _add_vertical_ribs(parent: Node3D, width: float, depth: float, h: float, collector: bool) -> void:
	var rib_mat := _mat(Color(0.16, 0.24, 0.29, 1.0), Color(0.0, 0.25, 0.34, 1.0), 0.1)
	if collector:
		rib_mat = _mat(Color(0.18, 0.34, 0.42, 1.0), Color(0.0, 0.45, 0.65, 1.0), 0.2)
	_add_box(parent, "FrontLeftRib", Vector3(0.18, h + 0.3, 0.18), Vector3(-width * 0.48, 0.0, depth * 0.48), rib_mat)
	_add_box(parent, "FrontRightRib", Vector3(0.18, h + 0.3, 0.18), Vector3(width * 0.48, 0.0, depth * 0.48), rib_mat)
	_add_box(parent, "BackLeftRib", Vector3(0.18, h + 0.3, 0.18), Vector3(-width * 0.48, 0.0, -depth * 0.48), rib_mat)
	_add_box(parent, "BackRightRib", Vector3(0.18, h + 0.3, 0.18), Vector3(width * 0.48, 0.0, -depth * 0.48), rib_mat)

func _add_roof_detail(parent: Node3D, width: float, depth: float, h: float, x: int, z: int, collector: bool) -> void:
	var cap_mat := _mat(Color(0.18, 0.28, 0.34, 1.0), Color(0.0, 0.32, 0.42, 1.0), 0.12)
	var roof := _add_box(parent, "RooftopCap", Vector3(width + 0.8, 0.45, depth + 0.8), Vector3(0, h * 0.5 + 0.22, 0), cap_mat)
	var antenna := MeshInstance3D.new()
	antenna.name = "RooftopAntenna"
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.18
	antenna_mesh.bottom_radius = 0.18
	antenna_mesh.height = 3.0
	antenna.mesh = antenna_mesh
	antenna.position = Vector3(0, h * 0.5 + 1.9, 0)
	antenna.material_override = _mat(Color(0.2, 0.9, 1.0, 1.0), Color(0.2, 0.9, 1.0, 1.0), 0.9)
	parent.add_child(antenna)
	if collector:
		_add_box(parent, "CollectorCrown", Vector3(width * 0.7, 3.2, depth * 0.7), Vector3(0, h * 0.5 + 2.2, 0), _mat(Color(0.12, 0.32, 0.42, 1.0), Color(0.0, 0.7, 1.0, 1.0), 0.7))
		var spire := MeshInstance3D.new()
		spire.name = "CollectorSpire"
		var spire_mesh := CylinderMesh.new()
		spire_mesh.top_radius = 0.18
		spire_mesh.bottom_radius = 0.55
		spire_mesh.height = 7.5
		spire.mesh = spire_mesh
		spire.position = Vector3(0, h * 0.5 + 6.1, 0)
		spire.material_override = _mat(Color(0.25, 0.95, 1.0, 1.0), Color(0.1, 0.8, 1.0, 1.0), 1.0)
		parent.add_child(spire)
	elif (x + z) % 4 == 0:
		_add_box(parent, "CrownBlock", Vector3(width * 0.55, 2.8, depth * 0.55), Vector3(0, h * 0.5 + 1.85, 0), _mat(Color(0.22, 0.3, 0.36, 1.0), Color(0.0, 0.35, 0.48, 1.0), 0.25))
	elif (x - z) % 4 == 0:
		var spire := MeshInstance3D.new()
		spire.name = "SignalSpire"
		var spire_mesh := CylinderMesh.new()
		spire_mesh.top_radius = 0.18
		spire_mesh.bottom_radius = 0.7
		spire_mesh.height = 5.5
		spire.mesh = spire_mesh
		spire.position = Vector3(0, h * 0.5 + 3.3, 0)
		spire.material_override = _mat(Color(0.22, 0.88, 1.0, 1.0), Color(0.1, 0.7, 1.0, 1.0), 0.85)
		parent.add_child(spire)
	if collector or (abs(x) + abs(z)) % 5 == 0:
		var pad := MeshInstance3D.new()
		pad.name = "RooftopDronePad"
		var pad_mesh := CylinderMesh.new()
		pad_mesh.top_radius = 2.2
		pad_mesh.bottom_radius = 2.2
		pad_mesh.height = 0.18
		pad.mesh = pad_mesh
		pad.position = Vector3(0, h * 0.5 + 0.42, 0)
		pad.material_override = _mat(Color(0.04, 0.11, 0.16, 1.0), Color(0.0, 0.35, 0.5, 1.0), 0.25)
		parent.add_child(pad)
		var ring := MeshInstance3D.new()
		ring.name = "DronePadRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 2.0
		ring_mesh.outer_radius = 2.25
		ring.mesh = ring_mesh
		ring.position = Vector3(0, h * 0.5 + 0.58, 0)
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.material_override = _mat(Color(0.35, 0.9, 1.0, 1.0), Color(0.25, 0.8, 1.0, 1.0), 0.9)
		parent.add_child(ring)
	if collector:
		for offset in [3.0, 5.0]:
			var ring := MeshInstance3D.new()
			ring.name = "CollectorEnergyRing_%s" % str(offset)
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = max(width, depth) * 0.55 + offset
			ring_mesh.outer_radius = ring_mesh.inner_radius + 0.18
			ring.mesh = ring_mesh
			ring.position = Vector3(0, h * 0.5 + offset, 0)
			ring.rotation_degrees = Vector3(90, 0, 0)
			ring.material_override = _transparent_mat(Color(0.0, 0.55, 0.9, 0.28), Color(0.0, 0.9, 1.0, 1.0), 0.75)
			parent.add_child(ring)
		var core := MeshInstance3D.new()
		core.name = "CollectorCoreGlow"
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 1.2
		core_mesh.bottom_radius = 1.2
		core_mesh.height = h + 4.0
		core.mesh = core_mesh
		core.position = Vector3(0, 0, 0)
		core.material_override = _transparent_mat(Color(0.0, 0.45, 0.8, 0.08), Color(0.0, 0.8, 1.0, 1.0), 0.65)
		parent.add_child(core)

func _add_rooftop_beacon(parent: Node3D, pos: Vector3, collector: bool = false) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "RooftopBeacon"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0 if collector else 0.7
	mesh.height = 2.0 if collector else 1.4
	beacon.mesh = mesh
	beacon.position = pos
	beacon.material_override = _mat(Color(0.2, 0.9, 1.0, 1.0), Color(0.2, 0.9, 1.0, 1.0), 1.1 if collector else 0.9)
	parent.add_child(beacon)

func _add_box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = pos
	box.material_override = mat
	parent.add_child(box)
	return box

func _build_hero() -> void:
	hero = LUMEN_SCENE.instantiate() as Node3D
	if hero == null:
		push_error("Failed to load Meshy hero asset: res://assets/3d/characters/lumen/lumen_body.glb")
		hero = Node3D.new()
	hero.name = "TheLumen_MeshyHero"
	hero.position = Vector3(0, 28, 36)
	hero.scale = Vector3(1.35, 1.35, 1.35)
	_apply_actor_visibility_overrides(hero, Color(0.05, 0.9, 1.0, 1), Color(0.0, 0.75, 0.9, 1), 0.08)
	add_child(hero)

func _apply_actor_visibility_overrides(actor: Node3D, albedo: Color, emission: Color, energy: float) -> void:
	var mesh_count := 0
	for child in actor.find_children("*", "MeshInstance3D", true, true):
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		mesh_count += 1
		var mat := mesh.get_surface_override_material(0)
		if mat == null:
			mat = mesh.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			var copy := mat.duplicate() as StandardMaterial3D
			copy.albedo_color = albedo
			copy.emission_enabled = energy > 0.0
			copy.emission = emission
			copy.emission_energy_multiplier = energy
			mesh.set_surface_override_material(0, copy)
		else:
			mesh.material_override = _mat(albedo, emission, energy)
	if mesh_count == 0:
		push_warning("No MeshInstance3D found for actor visibility pass: ", actor.name)
	var light := OmniLight3D.new()
	light.name = "ActorVisibilityLight"
	light.position = Vector3(0, 2.2, 0)
	light.light_color = emission
	light.light_energy = 20.0
	light.omni_range = 22.0
	actor.add_child(light)

func _stage_capture_scene() -> void:
	var mode := OS.get_environment("AURORA_CAPTURE_MODE")
	if mode == "gameplay":
		# Stage gameplay captures in the open central avenue so the chase camera
		# reads as city flight instead of starting with a tower face behind the hero.
		hero.position = Vector3(-8, 34, 10)
	elif mode == "drone":
		# Put the hero and seeded rogue drone in the same air corridor; the drone
		# camera frames the pair and the actual Meshy drone actor, not just the
		# event volume. Use a fixed high oblique capture pose so both actors sit
		# below the HUD and remain readable at 1152×648.
		var nearest_drone := _nearest_event()
		if nearest_drone != null and str(nearest_drone.get_meta("kind", "")) == "rogue_drone":
			nearest_drone.position = Vector3(0, 70, 60)
			nearest_drone.set_meta("orbit_center", nearest_drone.position)
			nearest_drone.set_meta("drift_radius", 4.0)
			nearest_drone.set_meta("drift_angle", 0.4)
		hero.position = Vector3(-10, 70, 55)
	elif mode == "closeup":
		camera.fov = 55
		# Pull the close-up back into the central avenue so the hero silhouettes
		# against sky/open street depth, not a skyscraper wall.
		hero.position = Vector3(0, 34, 4)
		hero.rotation_degrees = Vector3(0, 180, 0)
		hero.scale = Vector3(2.0, 2.0, 2.0)

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
	_spawn_event("rogue_drone", Vector3(0, 44, 80))
	_spawn_event("bridge_collapse", Vector3(0, 4, 160))

func _update_events(delta: float) -> void:
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
			var label_name := "Non-lethal civic drone" if kind == "rogue_drone" else _format_event_name(kind)
			label.text = "%s\n%.0fm" % [label_name.to_upper(), dist]
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
	_play_event_spawn_audio(kind)
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
		_apply_actor_visibility_overrides(drone_actor, Color(1.4, 0.75, 2.0, 1), Color(1.2, 0.35, 1.8, 1), 1.15)
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
	if Input.is_key_pressed(KEY_SHIFT) and velocity.length() > 1.0:
		AuroraAudio.trigger("flight_boost_burst")
	hero.position += velocity * delta
	hero.position.y = clamp(hero.position.y, 5.0, 120.0)
	if velocity.length() > 1.0:
		hero.look_at(hero.position - Vector3(velocity.x, 0.0, velocity.z).normalized(), Vector3.UP)

func _update_camera(delta: float) -> void:
	var nearest := _nearest_event()
	var mode := OS.get_environment("AURORA_CAPTURE_MODE")
	if mode == "drone" and nearest != null:
		var target := Vector3(0, 75, 60)
		var desired := Vector3(-35, 105, -20)
		camera.fov = 76
		camera.global_position = camera.global_position.lerp(desired, clamp(delta * 5.0, 0, 1))
		camera.look_at(target, Vector3.UP)
		return
	# Keep the playable chase camera in the central flight corridor; the previous
	# positive-Z offset could spawn the camera inside the first skyline ring.
	var offset := Vector3(0, 10, -22)
	if mode == "city":
		offset = Vector3(18, 18, 34)
	elif mode == "closeup":
		camera.fov = 62
		offset = Vector3(6, 1.2, -14)
	var target := hero.position + Vector3(0, 1.2, 0)
	if mode == "closeup":
		target = hero.position + Vector3(0, 1.55, 0)
	var desired := hero.position + offset
	var resolved := _resolve_camera_collision(target, desired)
	camera.global_position = camera.global_position.lerp(resolved, clamp(delta * 5.0, 0, 1))
	camera.look_at(target, Vector3.UP)

func _resolve_camera_collision(from_pos: Vector3, desired_camera_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	# Cast from the desired camera back toward the hero. If a building blocks the
	# view, place the camera just outside that obstruction on the camera side.
	var query := PhysicsRayQueryParameters3D.create(desired_camera_pos, from_pos, 1, [])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return desired_camera_pos
	var away := (desired_camera_pos - from_pos).normalized()
	return Vector3(hit["position"]) + away * 1.4

func _trigger_power(power_id: String) -> void:
	if not progression.has_power(power_id):
		var gained: Array[String] = progression.add_xp(110)
		last_event_text = "%s training surge: +110 XP%s" % [power_id.replace("_", " ").capitalize(), " and new power unlocked" if gained.has(power_id) else ""]
		if gained.has(power_id):
			_spawn_power_flash(power_id)
		return
	_spawn_power_flash(power_id)
	_play_power_audio(power_id)
	var resolved := _attempt_resolve_nearest(power_id)
	if not resolved:
		last_event_text = "%s fired, but no matching city event is within %.0fm." % [power_id.replace("_", " ").capitalize(), EVENT_RESOLVE_RADIUS]

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

func _play_power_audio(power_id: String) -> void:
	match power_id:
		"radiant_beam":
			AuroraAudio.trigger("power_radiant_beam_fire")
		"sonic_burst":
			AuroraAudio.trigger("power_sonic_burst")
		"aegis_field":
			AuroraAudio.trigger("power_aegis_activate")
		"rescue_lift":
			AuroraAudio.trigger("event_alert_rescue_needed")

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
		event_cue_label.text = "Nearest: %s — %.0fm (%s). %s. Last: %s" % [_format_event_name(kind), dist, proximity, _required_action_for_event(kind), last_event_text]

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

func _format_event_name(kind: String) -> String:
	return kind.replace("_", " ").capitalize()

func _required_action_for_event(kind: String) -> String:
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

func _attempt_resolve_nearest(power_id: String) -> bool:
	var marker := _nearest_event()
	if marker == null:
		return false
	var kind := str(marker.get_meta("kind", "city_event"))
	var dist := hero.position.distance_to(marker.position)
	if dist > EVENT_RESOLVE_RADIUS:
		last_event_text = "%s is %.0fm away; enter the %.0fm resolution volume first." % [_format_event_name(kind), dist, EVENT_RESOLVE_RADIUS]
		return false
	if not _power_matches_event(power_id, kind):
		last_event_text = "%s needs: %s." % [_format_event_name(kind), _required_action_for_event(kind)]
		return false
	_resolve_event(marker, power_id)
	return true

func _resolve_event(marker: Node3D, power_id: String) -> void:
	var kind := str(marker.get_meta("kind", "city_event"))
	var event_xp := int(marker.get_meta("reward_xp", _event_reward(kind)))
	var gained: Array[String] = progression.add_xp(event_xp)
	resolved_events += 1
	event_nodes.erase(marker)
	last_event_text = "Resolved %s with %s: +%d XP" % [_format_event_name(kind), power_id.replace("_", " "), event_xp]
	_play_event_resolve_audio(kind)
	if gained.size() > 0:
		last_event_text += " | unlocked %s" % ", ".join(gained)
	_advance_story_for_event(kind)
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

func _advance_story_for_event(kind: String) -> void:
	if mission_step >= missions.size():
		return
	var m: Dictionary = missions[mission_step]
	if str(m.get("target_kind", "")) != kind and mission_step != 0:
		return
	var reward := int(m.get("reward_xp", 0))
	if reward > 0:
		var gained: Array[String] = progression.add_xp(reward)
		last_event_text += " | Story step '%s' complete: +%d XP" % [m["title"], reward]
		if gained.size() > 0:
			last_event_text += " | story unlock %s" % ", ".join(gained)
	mission_step = min(mission_step + 1, missions.size())

func _update_rogue_drone(marker: Node3D, delta: float) -> void:
	var center: Vector3 = marker.get_meta("orbit_center", marker.position)
	var angle := float(marker.get_meta("drift_angle", 0.0)) + delta * float(marker.get_meta("drift_speed", 0.65))
	var radius := float(marker.get_meta("drift_radius", 10.0))
	marker.set_meta("drift_angle", angle)
	marker.position = center + Vector3(cos(angle) * radius, sin(angle * 0.7) * 4.0, sin(angle) * radius)
	marker.rotate_y(delta * 1.8)
	if is_instance_valid(rogue_drone_actor):
		rogue_drone_actor.rotate_y(delta * 2.4)

func _city_facade_material(h: float, x: int, z: int, width: float, depth: float, collector: bool) -> StandardMaterial3D:
	var base := Color(0.09 + float(abs(x + z) % 4) * 0.018, 0.13 + float(abs(x - z) % 5) * 0.015, 0.18 + float(abs(x * z) % 4) * 0.014, 1.0)
	var accent := Color(0.32, 0.88 + float(abs(x - z) % 3) * 0.03, 1.0, 1.0)
	if collector:
		base = Color(0.07, 0.22, 0.32, 1.0)
		accent = Color(0.35, 1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _city_texture("facade", base, accent, Color(0.03, 0.08, 0.11, 1.0))
	mat.albedo_color = Color(0.95, 1.0, 1.0, 1.0)
	mat.emission_enabled = collector or h > 42.0
	mat.emission = Color(0.0, 0.18, 0.25, 1.0) if collector else Color(0.0, 0.08, 0.12, 1.0)
	mat.emission_energy_multiplier = 0.16 if collector else 0.07
	mat.roughness = 0.42
	mat.metallic = 0.14
	return mat

func _city_texture(kind: String, base: Color, accent: Color, grid: Color) -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var c := base
			if kind == "facade":
				var px := x % 16
				var py := y % 16
				if px == 0 or py == 0:
					c = grid
				elif px >= 5 and px <= 10 and py >= 3 and py <= 12:
					c = accent
				elif py >= 13 and py <= 14:
					c = Color(base.r * 0.75, base.g * 0.85, base.b * 0.95, 1.0)
			else:
				var on_line := x % 16 == 0 or y % 16 == 0
				var on_node := (x % 32 >= 14 and x % 32 <= 17) and (y % 32 >= 14 and y % 32 <= 17)
				if on_node:
					c = accent
				elif on_line:
					c = grid
				else:
					c.a = 0.0
			img.set_pixel(x, y, c)
	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

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
