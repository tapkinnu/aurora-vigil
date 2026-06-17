extends Node3D

# Main is the thin coordinator for Aurora Vigil. It builds the world/city geometry
# and the hero, wires the focused gameplay systems together, owns the HUD and the
# screenshot/quit capture flow, and exposes shared scene-tree helpers (materials,
# tweens, actor visibility) that the systems call back into.
#
# Gameplay responsibilities live in focused modules:
#   PlayerFlightController.gd — flight, chase camera, contact shadow
#   CityEventSystem.gd        — dynamic event seeding/spawning/resolution
#   MissionDirector.gd        — story-mission spine and progression hooks
#   PowerSystem.gd            — power unlocks, VFX, audio, event dispatch
#   SaveGame.gd               — persistent save/load of run state
#   ProgressionModel.gd       — XP/level/power-unlock rules

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")
const LUMEN_SCENE = preload("res://assets/3d/characters/lumen/lumen_body.glb")

var hero: Node3D
var camera: Camera3D
var hud_label: Label
var mission_label: Label
var event_cue_label: Label
var hud_panel: ColorRect
var mission_panel: ColorRect
var progression: ProgressionModel
# Shared HUD feedback line written by several systems; owned here so it survives
# across systems and is rendered by _update_hud.
var last_event_text: String = "Awaiting first city emergency."
var _cleanup_tweens: Array[Tween] = []

# Focused gameplay systems, wired in _ready.
var flight: PlayerFlightController
var events: CityEventSystem
var missions: MissionDirector
var powers: PowerSystem
var objectives: ObjectiveDirector

func _ready() -> void:
	_build_audio()
	progression = ProgressionModel.new()
	_build_world()
	_build_city()
	_build_hero()
	_wire_systems()
	if _persistence_enabled():
		SaveGame.load_into(progression, missions, events)
	events.seed_initial()
	objectives.spawn_all()
	_stage_capture_scene()
	flight.attach_contact_shadow(hero, 2.6, 1.4)
	_build_hud()
	_update_hud()
	if OS.get_environment("AURORA_CAPTURE_PATH") != "":
		call_deferred("_capture_after_delay")
	elif OS.get_environment("AURORA_AUTO_QUIT") == "1":
		call_deferred("_quit_after_delay")

func _wire_systems() -> void:
	missions = MissionDirector.new()
	missions.setup(progression)
	events = CityEventSystem.new()
	events.setup(self, hero, camera, progression, missions)
	events.build_waypoint_layer()
	powers = PowerSystem.new()
	powers.setup(self, hero, progression, events)
	flight = PlayerFlightController.new()
	flight.setup(self, hero, camera)
	objectives = ObjectiveDirector.new()
	objectives.setup(self, hero, camera, events, missions)

# Persistence is disabled during headless capture/smoke runs so screenshots and the
# smoke print stay deterministic regardless of any save file on disk.
func _persistence_enabled() -> bool:
	return OS.get_environment("AURORA_CAPTURE_PATH") == "" \
		and OS.get_environment("AURORA_CAPTURE_MODE") == "" \
		and OS.get_environment("AURORA_AUTO_QUIT") != "1"

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _persistence_enabled():
		SaveGame.save(progression, missions, events)

func _remember_tween(t: Tween) -> Tween:
	_cleanup_tweens.append(t)
	return t

func _build_audio() -> void:
	AuroraAudio.start_loop("ambience_city_base_loop")
	AuroraAudio.start_loop("music_city_exploration")
	AuroraAudio.trigger("stinger_mission_intro")

func _physics_process(delta: float) -> void:
	flight.handle_flight(delta)
	flight.update_camera(delta, events.nearest_event())
	events.update(delta)
	objectives.update(delta)
	flight.update_contact_shadows()
	_update_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				powers.trigger("radiant_beam")
			KEY_Q:
				powers.trigger("sonic_burst")
			KEY_E:
				powers.trigger("aegis_field")
			KEY_R:
				powers.trigger("rescue_lift")

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
			_add_crown_neon(tower_body, width, depth, h)
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
	# Avenues get a brighter, slightly emissive surface so they read from high capture
	# angles as glowing streets instead of vanishing into the dark ground plane.
	var road_mat := _mat(Color(0.025, 0.04, 0.06, 1.0), Color(0.04, 0.18, 0.26, 1.0), 0.18)
	var lane_mat := _mat(Color(0.7, 0.95, 1.0, 1.0), Color(0.4, 0.85, 1.0, 1.0), 0.95)
	var curb_mat := _mat(Color(0.04, 0.07, 0.09, 1.0), Color(0.0, 0.5, 0.7, 1.0), 0.45)
	for i in range(-5, 6):
		var road_x := MeshInstance3D.new()
		road_x.name = "AvenueEastWest_%d" % i
		var mx := BoxMesh.new()
		mx.size = Vector3(270, 0.16, 6.0)
		road_x.mesh = mx
		road_x.position = Vector3(0, 0.08, i * 22.0)
		road_x.material_override = road_mat
		parent.add_child(road_x)
		var curb_n := MeshInstance3D.new()
		curb_n.name = "CurbN_%d" % i
		var cn_mesh := BoxMesh.new()
		cn_mesh.size = Vector3(270, 0.18, 0.45)
		curb_n.mesh = cn_mesh
		curb_n.position = Vector3(0, 0.09, i * 22.0 + 3.05)
		curb_n.material_override = curb_mat
		parent.add_child(curb_n)
		var curb_s := MeshInstance3D.new()
		curb_s.name = "CurbS_%d" % i
		var cs_mesh := BoxMesh.new()
		cs_mesh.size = Vector3(270, 0.18, 0.45)
		curb_s.mesh = cs_mesh
		curb_s.position = Vector3(0, 0.09, i * 22.0 - 3.05)
		curb_s.material_override = curb_mat
		parent.add_child(curb_s)
		var road_z := MeshInstance3D.new()
		road_z.name = "AvenueNorthSouth_%d" % i
		var mz := BoxMesh.new()
		mz.size = Vector3(6.0, 0.16, 270)
		road_z.mesh = mz
		road_z.position = Vector3(i * 22.0, 0.08, 0)
		road_z.material_override = road_mat
		parent.add_child(road_z)
		var curb_e := MeshInstance3D.new()
		curb_e.name = "CurbE_%d" % i
		var ce_mesh := BoxMesh.new()
		ce_mesh.size = Vector3(0.45, 0.18, 270)
		curb_e.mesh = ce_mesh
		curb_e.position = Vector3(i * 22.0 + 3.05, 0.09, 0)
		curb_e.material_override = curb_mat
		parent.add_child(curb_e)
		var curb_w := MeshInstance3D.new()
		curb_w.name = "CurbW_%d" % i
		var cw_mesh := BoxMesh.new()
		cw_mesh.size = Vector3(0.45, 0.18, 270)
		curb_w.mesh = cw_mesh
		curb_w.position = Vector3(i * 22.0 - 3.05, 0.09, 0)
		curb_w.material_override = curb_mat
		parent.add_child(curb_w)
		for j in range(-5, 6):
			var dash_x := MeshInstance3D.new()
			dash_x.name = "LaneDashEW_%d_%d" % [i, j]
			var dx := BoxMesh.new()
			dx.size = Vector3(5.0, 0.06, 0.32)
			dash_x.mesh = dx
			dash_x.position = Vector3(j * 22.0, 0.22, i * 22.0)
			dash_x.material_override = lane_mat
			parent.add_child(dash_x)
			var dash_z := MeshInstance3D.new()
			dash_z.name = "LaneDashNS_%d_%d" % [i, j]
			var dz := BoxMesh.new()
			dz.size = Vector3(0.32, 0.06, 5.0)
			dash_z.mesh = dz
			dash_z.position = Vector3(i * 22.0, 0.23, j * 22.0)
			dash_z.material_override = lane_mat
			parent.add_child(dash_z)
		if i in [-4, -2, 2, 4]:
			_add_streetlight(parent, Vector3(-11.0, 0.0, i * 22.0), 0.0)
			_add_streetlight(parent, Vector3(11.0, 0.0, i * 22.0), PI)
			_add_streetlight(parent, Vector3(i * 22.0, 0.0, -11.0), PI * 0.5)
			_add_streetlight(parent, Vector3(i * 22.0, 0.0, 11.0), -PI * 0.5)
			_add_street_trees(parent, i * 22.0, true)
			_add_street_trees(parent, i * 22.0, false)
		if abs(i) <= 1:
			_add_crosswalk(parent, i * 22.0, true)
			_add_crosswalk(parent, i * 22.0, false)

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

func _add_street_trees(parent: Node3D, avenue_z: float, north_side: bool) -> void:
	# Stylised street trees: dark trunk + glowing canopy sphere. Placed every other
	# block so they don't choke the avenue. Trees sit between the road and the
	# tower footprints, breaking up the long flat curb line.
	var trunk_mat := _mat(Color(0.05, 0.08, 0.1, 1.0), Color(0.0, 0.18, 0.25, 1.0), 0.08)
	var canopy_a := _mat(Color(0.04, 0.5, 0.32, 1.0), Color(0.1, 0.85, 0.6, 1.0), 0.6)
	var canopy_b := _mat(Color(0.18, 0.05, 0.42, 1.0), Color(0.6, 0.18, 0.95, 1.0), 0.55)
	var side_sign := 1.0 if north_side else -1.0
	var base_x := -11.0 * side_sign
	for step in [-3, -1, 1, 3]:
		if step == 0:
			continue
		var offset := float(step) * 11.0
		var x := base_x
		var z := avenue_z + offset
		# Skip tree if it would land inside the central plaza block.
		if abs(x) < 4.5 and abs(z) < 4.5:
			continue
		var tree := Node3D.new()
		tree.name = "StreetTree_%s_%d" % [("N" if north_side else "S"), step]
		tree.position = Vector3(x, 0.0, z)
		parent.add_child(tree)
		var trunk := MeshInstance3D.new()
		trunk.name = "TreeTrunk"
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.18
		trunk_mesh.bottom_radius = 0.25
		trunk_mesh.height = 2.6
		trunk.mesh = trunk_mesh
		trunk.position = Vector3(0, 1.3, 0)
		trunk.material_override = trunk_mat
		tree.add_child(trunk)
		var canopy_mat := canopy_a if step > 0 else canopy_b
		var canopy := MeshInstance3D.new()
		canopy.name = "TreeCanopy"
		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = 1.4
		canopy_mesh.height = 2.6
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(0, 3.3, 0)
		canopy.material_override = canopy_mat
		tree.add_child(canopy)
		var glow := OmniLight3D.new()
		glow.name = "TreeGlow"
		glow.position = Vector3(0, 3.3, 0)
		glow.light_color = canopy_mat.emission
		glow.light_energy = 1.8
		glow.omni_range = 6.0
		tree.add_child(glow)

func _add_crosswalk(parent: Node3D, avenue_z: float, east_west: bool) -> void:
	# Zebra-striped crosswalk blocks placed where two avenues intersect so the
	# dark road network picks up a brighter graphic accent under the camera.
	var stripe_mat := _mat(Color(0.85, 0.95, 1.0, 1.0), Color(0.5, 0.9, 1.0, 1.0), 0.85)
	for k in range(-3, 4):
		var stripe := MeshInstance3D.new()
		stripe.name = "CrosswalkStripe_%s_%d" % [("EW" if east_west else "NS"), k]
		var s_mesh := BoxMesh.new()
		if east_west:
			s_mesh.size = Vector3(0.9, 0.06, 4.4)
			stripe.position = Vector3(float(k) * 5.5, 0.27, avenue_z)
		else:
			s_mesh.size = Vector3(4.4, 0.06, 0.9)
			stripe.position = Vector3(avenue_z, 0.27, float(k) * 5.5)
		stripe.mesh = s_mesh
		stripe.material_override = stripe_mat
		parent.add_child(stripe)

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

func _add_crown_neon(parent: Node3D, width: float, depth: float, h: float) -> void:
	# Bright neon rim band wrapped around the top of the tower so the skyline
	# silhouettes read against the dark sky from any capture altitude. Variants
	# cycle cyan / magenta per tower so the city feels populated.
	var hue := fposmod(width + depth + h, 4.0)
	var crown_mat: StandardMaterial3D
	if hue < 1.5:
		crown_mat = _mat(Color(0.25, 0.95, 1.0, 1.0), Color(0.25, 0.95, 1.0, 1.0), 1.0)
	elif hue < 3.0:
		crown_mat = _mat(Color(0.95, 0.25, 0.85, 1.0), Color(0.95, 0.25, 0.85, 1.0), 0.95)
	else:
		crown_mat = _mat(Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.85, 0.3, 1.0), 0.9)
	var y := h * 0.5 - 0.18
	_add_box(parent, "CrownBandFront", Vector3(width + 0.4, 0.16, 0.18), Vector3(0, y, depth * 0.5 + 0.16), crown_mat)
	_add_box(parent, "CrownBandBack", Vector3(width + 0.4, 0.16, 0.18), Vector3(0, y, -depth * 0.5 - 0.16), crown_mat)
	_add_box(parent, "CrownBandLeft", Vector3(0.18, 0.16, depth + 0.4), Vector3(-width * 0.5 - 0.16, y, 0), crown_mat)
	_add_box(parent, "CrownBandRight", Vector3(0.18, 0.16, depth + 0.4), Vector3(width * 0.5 + 0.16, y, 0), crown_mat)
	var crown_light := OmniLight3D.new()
	crown_light.name = "CrownNeonLight"
	crown_light.position = Vector3(0, y, 0)
	crown_light.light_color = crown_mat.emission
	crown_light.light_energy = 1.4
	crown_light.omni_range = 12.0
	parent.add_child(crown_light)

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
		var nearest_drone := events.nearest_event()
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
	objectives.stage_for_capture(mode)

func _add_part(parent: Node3D, part_name: String, mesh: Mesh, pos: Vector3, scale_v: Vector3, albedo: Color, emission: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale_v
	mi.material_override = _mat(albedo, emission, energy)
	parent.add_child(mi)

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

func _update_hud() -> void:
	if hud_label == null: return
	var next_xp: int = progression.xp_for_next()
	hud_label.text = "AURORA VIGIL  |  Level %d  XP %d/%d  |  Powers: %s  |  Active: %d  Resolved: %d" % [progression.level, progression.xp, next_xp, ", ".join(progression.unlocked), events.event_nodes.size(), events.resolved_events]
	mission_label.text = missions.hud_text()
	var nearest := events.nearest_event()
	if nearest == null:
		event_cue_label.text = "Event cue: no active emergencies. %s" % last_event_text
	else:
		var kind := str(nearest.get_meta("kind", "city_event"))
		var dist := hero.position.distance_to(nearest.position)
		var proximity := "IN RANGE" if dist <= events.EVENT_RESOLVE_RADIUS else "approach %.0fm" % max(dist - events.EVENT_RESOLVE_RADIUS, 0.0)
		event_cue_label.text = "Nearest: %s — %.0fm (%s). %s. Last: %s" % [events.format_event_name(kind), dist, proximity, events.required_action_for_event(kind), last_event_text]

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
	await _cleanup_for_quit()
	get_tree().quit(0)

func _quit_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout
	print("AURORA_SMOKE: level=", progression.level, " events=", events.event_nodes.size(), " hero_y=", hero.position.y)
	await _cleanup_for_quit()
	get_tree().quit(0)

func _cleanup_for_quit() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	for tween in _cleanup_tweens:
		if is_instance_valid(tween):
			tween.stop()
			tween.kill()
	var was_paused: bool = get_tree().paused
	get_tree().paused = true
	AuroraAudio.stop_all()
	for child in get_children():
		child.free()
	get_tree().paused = was_paused
	await get_tree().process_frame
