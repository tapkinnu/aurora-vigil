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
const FACADE_SHADER = preload("res://shaders/building_facade.gdshader")

# Ground texture prefixes — asphalt, grass (parks), plaza (collector-tower surrounds).
# Each prefix resolves to 4 PNGs (albedo, normal, roughness, emission).
const GROUND_TEXTURE_DIRS: Array[String] = [
	"res://assets/textures/ground/asphalt_",
	"res://assets/textures/ground/grass_",
	"res://assets/textures/ground/plaza_",
]
# _ground_*_textures are filled at startup; index matches GROUND_TEXTURE_DIRS.
var _ground_albedo_textures: Array[Texture2D] = []
var _ground_normal_textures: Array[Texture2D] = []
var _ground_roughness_textures: Array[Texture2D] = []
var _ground_emission_textures: Array[Texture2D] = []

# PBR facade texture sets — loaded once at startup, cycled per building.
const FACADE_TEXTURE_DIRS: Array[String] = [
	"res://assets/textures/facades/glass_curtain_wall_",
	"res://assets/textures/facades/concrete_panel_",
	"res://assets/textures/facades/brick_",
	"res://assets/textures/facades/metal_cladding_",
	"res://assets/textures/facades/commercial_facade_",
] 
const FACADE_PBR_PROPS: Array[Dictionary] = [
	{"roughness": 0.15, "metallic": 0.85, "emission_energy": 0.35},
	{"roughness": 0.85, "metallic": 0.02, "emission_energy": 0.18},
	{"roughness": 0.75, "metallic": 0.05, "emission_energy": 0.22},
	{"roughness": 0.25, "metallic": 0.90, "emission_energy": 0.18},
	{"roughness": 0.35, "metallic": 0.60, "emission_energy": 0.55},
]
var _facade_albedo_textures: Array[Texture2D] = []
var _facade_normal_textures: Array[Texture2D] = []
var _facade_roughness_textures: Array[Texture2D] = []
var _facade_emission_textures: Array[Texture2D] = []

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

# Real CC0/CC-BY low-poly street/vegetation/vehicle models live under PROP_DIR
# (see assets/3d/props/SOURCES.md for sources + licenses). _load_prop loads and
# caches the PackedScenes; every _add_* prop builder instances the real model and
# falls back to a primitive build if its GLB is missing or fails to import.
const PROP_DIR := "res://assets/3d/props/"
var _prop_scene_cache: Dictionary = {}

# Focused gameplay systems, wired in _ready.
var flight: PlayerFlightController
var events: CityEventSystem
var missions: MissionDirector
var powers: PowerSystem
var objectives: ObjectiveDirector
var civilians: CivilianSystem
var enemy_system: EnemySystem
var health_system: HealthSystem

# HUD: health bar, minimap, and the two transient notification banners.
var health_bar_bg: ColorRect
var health_bar_fill: ColorRect
var health_label: Label
var minimap: Minimap
var unlock_toast: Label
var mission_banner: Label
var game_over_label: Label
var controls_hint_label: Label
var screen_flash: ColorRect
var _toast_timer: float = 0.0
var _banner_timer: float = 0.0
var _last_unlocked_count: int = 2
var _last_banner_step: int = 0

# Release-polish menu overlays (built only in interactive play; never during the
# headless capture/auto-quit harness runs so screenshots and the smoke test are
# unaffected). main_menu pauses the tree as a cinematic title backdrop.
const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")
const PauseMenuScript := preload("res://scripts/PauseMenu.gd")
const GameOverScreenScript := preload("res://scripts/GameOverScreen.gd")
var main_menu: CanvasLayer
var pause_menu
var game_over_screen

# The four key-bound powers shown in the HUD with their lock state, in unlock order.
const HUD_POWERS: Array[Dictionary] = [
	{"id": "rescue_lift", "key": "R"},
	{"id": "radiant_beam", "key": "F"},
	{"id": "sonic_burst", "key": "Q"},
	{"id": "aegis_field", "key": "E"},
]

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
	elif _persistence_enabled():
		# Interactive launch: build the pause / game-over overlays and open the
		# title menu over the live skyline. Capture/auto-quit runs skip all of this.
		_build_menus()
		_show_main_menu()

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
	enemy_system = EnemySystem.new()
	enemy_system.setup(self, hero, events, progression)
	civilians = CivilianSystem.new()
	civilians.setup(self, hero, events, Callable(self, "_dispatch_civilian_audio"))
	health_system = HealthSystem.new()
	health_system.setup(self, hero, enemy_system, events)
	_apply_difficulty()

# Persistence is disabled during headless capture/smoke runs so screenshots and the
# smoke print stay deterministic regardless of any save file on disk.
func _persistence_enabled() -> bool:
	return OS.get_environment("AURORA_CAPTURE_PATH") == "" \
		and OS.get_environment("AURORA_CAPTURE_MODE") == "" \
		and OS.get_environment("AURORA_AUTO_QUIT") != "1"

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _persistence_enabled():
		SaveGame.save(progression, missions, events)

func _load_facade_textures() -> void:
	# Preload all PBR facade texture sets. Each set has albedo, normal, roughness, emission.
	print("AURORA_FACADE: loading ", FACADE_TEXTURE_DIRS.size(), " facade texture sets...")
	for prefix in FACADE_TEXTURE_DIRS:
		var albedo := load(prefix + "albedo.png") as Texture2D
		var normal := load(prefix + "normal.png") as Texture2D
		var roughness := load(prefix + "roughness.png") as Texture2D
		var emission := load(prefix + "emission.png") as Texture2D
		if albedo == null:
			push_warning("Failed to load facade albedo: " + prefix + "albedo.png — shader will use defaults")
			continue
		_facade_albedo_textures.append(albedo)
		_facade_normal_textures.append(normal if normal != null else albedo)
		_facade_roughness_textures.append(roughness if roughness != null else albedo)
		_facade_emission_textures.append(emission if emission != null else albedo)
		print("AURORA_FACADE: loaded set ", prefix)
	print("AURORA_FACADE_TEXTURES: loaded ", _facade_albedo_textures.size(), " sets")

func _load_ground_textures() -> void:
	# Preload all ground PBR texture sets (asphalt, grass, plaza).
	# Each set has albedo, normal, roughness, emission.
	print("AURORA_GROUND: loading ", GROUND_TEXTURE_DIRS.size(), " ground texture sets...")
	for prefix in GROUND_TEXTURE_DIRS:
		var albedo := load(prefix + "albedo.png") as Texture2D
		var normal := load(prefix + "normal.png") as Texture2D
		var roughness := load(prefix + "roughness.png") as Texture2D
		var emission := load(prefix + "emission.png") as Texture2D
		if albedo == null:
			push_warning("Failed to load ground albedo: " + prefix + "albedo.png — ground will use fallback material")
			continue
		_ground_albedo_textures.append(albedo)
		_ground_normal_textures.append(normal if normal != null else albedo)
		_ground_roughness_textures.append(roughness if roughness != null else albedo)
		_ground_emission_textures.append(emission if emission != null else albedo)
		print("AURORA_GROUND: loaded set ", prefix)
	print("AURORA_GROUND_TEXTURES: loaded ", _ground_albedo_textures.size(), " sets")

func _ground_asphalt_material() -> StandardMaterial3D:
	# Dark wet-asphalt PBR material for the city ground plane.
	# Low roughness + high metallic for a rain-slicked neon-reflective surface.
	var mat := StandardMaterial3D.new()
	if not _ground_albedo_textures.is_empty():
		mat.albedo_texture = _ground_albedo_textures[0]
		if not _ground_normal_textures.is_empty() and _ground_normal_textures[0] != null:
			mat.normal_texture = _ground_normal_textures[0]
		if not _ground_roughness_textures.is_empty() and _ground_roughness_textures[0] != null:
			mat.roughness_texture = _ground_roughness_textures[0]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if not _ground_emission_textures.is_empty() and _ground_emission_textures[0] != null:
			mat.emission_enabled = true
			mat.emission_texture = _ground_emission_textures[0]
			mat.emission = Color(0.15, 0.20, 0.35, 1.0)
			mat.emission_energy_multiplier = 0.25
	mat.roughness = 0.35
	mat.metallic = 0.15
	mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
	return mat

func _ground_grass_material() -> StandardMaterial3D:
	# Grass PBR for park zones — high roughness, no metallic, subtle emission
	# so park patches read as "green space" under the bloom without glowing.
	var mat := StandardMaterial3D.new()
	var idx := 1  # GROUND_TEXTURE_DIRS index 1 = grass
	if _ground_albedo_textures.size() > idx:
		mat.albedo_texture = _ground_albedo_textures[idx]
		if _ground_normal_textures.size() > idx and _ground_normal_textures[idx] != null:
			mat.normal_texture = _ground_normal_textures[idx]
		if _ground_roughness_textures.size() > idx and _ground_roughness_textures[idx] != null:
			mat.roughness_texture = _ground_roughness_textures[idx]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if _ground_emission_textures.size() > idx and _ground_emission_textures[idx] != null:
			mat.emission_enabled = true
			mat.emission_texture = _ground_emission_textures[idx]
			mat.emission = Color(0.04, 0.12, 0.06, 1.0)
			mat.emission_energy_multiplier = 0.08
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	return mat

func _ground_plaza_material() -> StandardMaterial3D:
	# Polished plaza/concrete PBR near collector towers — moderate roughness,
	# slight metallic for wet-stone reflective sheen under SSR.
	var mat := StandardMaterial3D.new()
	var idx := 2  # GROUND_TEXTURE_DIRS index 2 = plaza
	if _ground_albedo_textures.size() > idx:
		mat.albedo_texture = _ground_albedo_textures[idx]
		if _ground_normal_textures.size() > idx and _ground_normal_textures[idx] != null:
			mat.normal_texture = _ground_normal_textures[idx]
		if _ground_roughness_textures.size() > idx and _ground_roughness_textures[idx] != null:
			mat.roughness_texture = _ground_roughness_textures[idx]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if _ground_emission_textures.size() > idx and _ground_emission_textures[idx] != null:
			mat.emission_enabled = true
			mat.emission_texture = _ground_emission_textures[idx]
			mat.emission = Color(0.10, 0.15, 0.25, 1.0)
			mat.emission_energy_multiplier = 0.15
	mat.roughness = 0.45
	mat.metallic = 0.10
	mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
	return mat

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
	enemy_system.update(delta)
	civilians.update(delta)
	health_system.update(delta)
	flight.update_contact_shadows()
	_update_transients(delta)
	_update_hud()
	# Surface the game-over screen in interactive play (it pauses the tree, so the
	# auto-respawn loop in HealthSystem stays frozen until the player chooses Retry).
	if game_over_screen != null and health_system.game_over and not game_over_screen.is_shown():
		game_over_screen.show_screen()

# Power activation is action-based so keyboard (F/Q/E/R) and controller face buttons
# (A=rescue, B=sonic, X=radiant, Y=aegis, mapped in project.godot) both fire. While a
# menu/game-over overlay holds the tree paused, Main is pausable so this never runs.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("aurora_power_radiant"):
		powers.trigger("radiant_beam")
	elif event.is_action_pressed("aurora_power_sonic"):
		powers.trigger("sonic_burst")
		if progression.has_power("sonic_burst"):
			var disabled := enemy_system.disable_in_range(hero.position)
			if disabled > 0:
				last_event_text = "Sonic burst silenced %d Null Choir unit(s)." % disabled
	elif event.is_action_pressed("aurora_power_aegis"):
		powers.trigger("aegis_field")
		if progression.has_power("aegis_field"):
			health_system.activate_aegis()
	elif event.is_action_pressed("aurora_power_rescue"):
		powers.trigger("rescue_lift")
		if progression.has_power("rescue_lift"):
			var calmed := civilians.rescue_nearby()
			if calmed > 0:
				last_event_text = "Rescue lift reassured %d civilian(s)." % calmed

# Routes CivilianSystem audio cues through literal AuroraAudio.trigger(...) calls so
# the audio-wiring contract (check_audio_wiring.py) stays satisfied in one place.
func _dispatch_civilian_audio(id: String) -> void:
	match id:
		"civilian_panicked_help":
			AuroraAudio.trigger("civilian_panicked_help")
		"civilian_grateful_thanks":
			AuroraAudio.trigger("civilian_grateful_thanks")
		_:
			push_error("Main: unknown civilian audio trigger id '%s'" % id)

func _build_world() -> void:
	# Night/dusk sky with stars + magenta horizon glow via ProceduralSkyMaterial.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky_resource := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Deep night sky with a warm magenta horizon band — keeps the dark
	# cyberpunk aesthetic but reads as a real sky, not a flat black plate.
	sky_mat.sky_top_color = Color(0.012, 0.018, 0.05, 1.0)
	sky_mat.sky_horizon_color = Color(0.18, 0.06, 0.28, 1.0)
	sky_mat.ground_horizon_color = Color(0.04, 0.02, 0.08, 1.0)
	sky_mat.ground_bottom_color = Color(0.005, 0.005, 0.012, 1.0)
	# Subtle sun curve — the visible "sun" never peaks but a faint warm
	# gradient washes the horizon, giving volumetric-fog colour a target.
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.18
	sky_resource.sky_material = sky_mat
	e.sky = sky_resource
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.35, 0.42, 0.6, 1.0)
	e.ambient_light_energy = 0.65
	# Layered atmospheric haze. Exponential distance fog plus a height gradient:
	# dense, slightly warmer murk pools in the low streets and thins toward a
	# cooler veil up high. Aerial perspective desaturates distant towers toward the
	# sky so the far skyline reads as a faint silhouette (real depth cue).
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.0032
	e.fog_light_color = Color(0.20, 0.21, 0.34, 1.0)
	e.fog_light_energy = 1.0
	e.fog_sky_affect = 0.35
	e.fog_aerial_perspective = 0.55
	# Height band: fog accumulates below ~12 m and thins out above it, so the
	# 0-10 m ground band is the haziest and the upper floors clear up.
	e.fog_height = 12.0
	e.fog_height_density = 0.05
	# Volumetric fog — gives the avenues a "haze under the streetlights" reading.
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.012
	e.volumetric_fog_albedo = Color(0.32, 0.42, 0.65, 1.0)
	e.volumetric_fog_emission = Color(0.06, 0.10, 0.18, 1.0)
	e.volumetric_fog_emission_energy = 0.4
	e.volumetric_fog_length = 96.0
	e.volumetric_fog_detail_spread = 4.0
	e.volumetric_fog_anisotropy = 0.3
	# Bloom/glow tuned for neon streetlights and crown bands.
	e.glow_enabled = true
	e.glow_intensity = 1.25
	e.glow_strength = 1.05
	e.glow_bloom = 0.25
	e.glow_hdr_threshold = 0.9
	e.glow_hdr_scale = 1.6
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# glow_levels/1..7 are individual properties, not an array/dict.
	# Default curve + boost on the mid mip levels for stronger neon halos.
	e.set("glow_levels/1", 0.0)
	e.set("glow_levels/2", 0.5)
	e.set("glow_levels/3", 0.85)
	e.set("glow_levels/4", 1.0)
	e.set("glow_levels/5", 0.75)
	e.set("glow_levels/6", 0.5)
	e.set("glow_levels/7", 0.3)
	# Screen-space reflections for the wet-pavement look.
	e.ssr_enabled = true
	e.ssr_max_steps = 32
	e.ssr_fade_in = 0.6
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.18
	# SSAO brings the avenues + skyline crevices some depth.
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.4
	e.ssao_power = 1.4
	# ACES tonemap — better contrast for the neon / dark split.
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	env.environment = e
	add_child(env)

	# Faint warm sun direction — adds directional shading on the upper
	# tower faces without overpowering the night sky.
	var sun := DirectionalLight3D.new()
	sun.name = "MorningIonSun"
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_color = Color(0.9, 0.7, 0.55, 1.0)
	sun.light_energy = 0.6
	add_child(sun)

	# Textured ground plane. Asphalt PBR from assets/textures/ground/asphalt_*.
	# Subdivided to 320×320 cells with uv2_scale = (1, 1) so the texture
	# tiles cleanly across the 620×620 plane.
	_load_ground_textures()
	var ground := MeshInstance3D.new()
	ground.name = "MeridianGroundPlane"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(620, 620)
	ground_mesh.subdivide_width = 32
	ground_mesh.subdivide_depth = 32
	ground.mesh = ground_mesh
	ground.material_override = _ground_asphalt_material()
	add_child(ground)

	camera = Camera3D.new()
	camera.name = "ThirdPersonFlightCamera"
	camera.fov = 72
	add_child(camera)

func _build_city() -> void:
	_load_facade_textures()
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
			# Vary footprints far more than the old 8.5-11.5 band so the lot sizes
			# read as irregular rather than a uniform stamp.
			var width: float = 7.0 + float((abs(x * 7 + z * 11) % 9))
			var depth: float = 7.0 + float((abs(x * 13 + z * 5) % 9))
			if is_collector:
				width = 11.0
				depth = 11.0
			var h: float = 18.0 + float((abs(x * 17 + z * 31) % 38))
			if is_collector:
				h += 18.0
			# Deterministic form-type: L-shape 30%, stepped 20%, twin-tower 10%,
			# setback 20%, simple box 20%. Collectors always stepped for landmark read.
			var form_seed: int = abs(x * 41 + z * 37) % 100
			var form_type: int = 4
			if is_collector:
				form_type = 1
			elif form_seed < 30:
				form_type = 0  # L-shaped
			elif form_seed < 50:
				form_type = 1  # stepped
			elif form_seed < 60:
				form_type = 2  # twin-tower
			elif form_seed < 80:
				form_type = 3  # setback
			# else simple box (form_type stays 4)
			var tower_body := StaticBody3D.new()
			tower_body.name = "SkylineTower_%d_%d" % [x, z]
			# Break the rigid 22-unit lattice: deterministic per-lot jitter so the
			# spacing and street setback vary (~14-30 units) instead of a perfect
			# grid. Collectors stay anchored as landmark corners.
			var jx: float = 0.0
			var jz: float = 0.0
			if not is_collector:
				jx = float((abs(x * 19 + z * 7) % 7) - 3) * 1.4
				jz = float((abs(x * 11 + z * 23) % 7) - 3) * 1.4
			tower_body.position = Vector3(x * 22.0 + jx, 0.0, z * 22.0 + jz)
			district.add_child(tower_body)
			var facade_mat := _city_facade_material(h, x, z, width, depth, is_collector)
			var top_info: Dictionary = _build_composite_tower(tower_body, form_type, width, depth, h, facade_mat)
			var top_y: float = float(top_info["top_y"])
			var top_w: float = float(top_info["top_w"])
			var top_d: float = float(top_info["top_d"])
			_add_vertical_ribs(tower_body, top_w, top_d, top_y, is_collector)
			_add_crown_neon(tower_body, top_w, top_d, top_y)
			_add_roof_detail(tower_body, top_w, top_d, top_y, x, z, is_collector)
			if is_collector or (x - z) % 2 == 0:
				_add_rooftop_beacon(tower_body, Vector3(0, top_y + 3.8, 0), is_collector)
	_add_civic_grid(district)
	_add_skyline_props(district)
	_add_city_avenues(district)
	_add_transit_corridor(district)
	_add_park_zones(district)
	_add_plaza_paving(district)
	_add_sidewalks(district)
	_add_diagonal_streets(district)
	_add_curved_avenues(district)
	_add_irregular_plazas(district)
	_add_parking_lots(district)
	_add_distant_skyline(district)
	_add_haze_layers(district)
	_add_street_props(district)

# ── Composite building-silhouette builders ──

func _build_composite_tower(parent: StaticBody3D, form_type: int, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	match form_type:
		0:
			return _build_l_shape(parent, width, depth, h, mat)
		1:
			return _build_stepped(parent, width, depth, h, mat)
		2:
			return _build_twin_tower(parent, width, depth, h, mat)
		3:
			return _build_setback(parent, width, depth, h, mat)
		_:
			return _build_simple_box(parent, width, depth, h, mat)

func _add_building_segment(parent: StaticBody3D, seg_name: String, size: Vector3, center: Vector3, mat: Material) -> void:
	# Visual mesh
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = seg_name + "_Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	mesh_inst.position = center
	mesh_inst.material_override = mat
	parent.add_child(mesh_inst)
	# Matching collision shape
	var col := CollisionShape3D.new()
	col.name = seg_name + "_Col"
	var col_shape := BoxShape3D.new()
	col_shape.size = size
	col.shape = col_shape
	col.position = center
	parent.add_child(col)

func _build_simple_box(parent: StaticBody3D, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	_add_building_segment(parent, "MainBox", Vector3(width, h, depth), Vector3(0, h * 0.5, 0), mat)
	return {"top_y": h, "top_w": width, "top_d": depth}

func _build_l_shape(parent: StaticBody3D, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	# L footprint: main bar + shorter perpendicular wing.
	var main_d: float = depth * 0.6
	var wing_w: float = width * 0.45
	var wing_h: float = h * 0.72
	_add_building_segment(parent, "LMain", Vector3(width, h, main_d), Vector3(0, h * 0.5, -depth * 0.2), mat)
	_add_building_segment(parent, "LWing", Vector3(wing_w, wing_h, depth), Vector3(-width * 0.275, wing_h * 0.5, depth * 0.2), mat)
	return {"top_y": h, "top_w": width, "top_d": depth}

func _build_stepped(parent: StaticBody3D, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	# 2-3 stacked boxes of decreasing width (ziggurat).
	var h1: float = h * 0.5
	var h2: float = h * 0.3
	var h3: float = h * 0.2
	var w2: float = width * 0.78
	var d2: float = depth * 0.78
	var w3: float = width * 0.52
	var d3: float = depth * 0.52
	_add_building_segment(parent, "Step1", Vector3(width, h1, depth), Vector3(0, h1 * 0.5, 0), mat)
	_add_building_segment(parent, "Step2", Vector3(w2, h2, d2), Vector3(0, h1 + h2 * 0.5, 0), mat)
	_add_building_segment(parent, "Step3", Vector3(w3, h3, d3), Vector3(0, h1 + h2 + h3 * 0.5, 0), mat)
	return {"top_y": h, "top_w": w3, "top_d": d3}

func _build_twin_tower(parent: StaticBody3D, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	# Two parallel slabs connected by a skybridge.
	var tower_w: float = width * 0.42
	var gap: float = width * 0.16
	var offset: float = tower_w * 0.5 + gap * 0.5
	var left_h: float = h * 0.85
	var right_h: float = h
	_add_building_segment(parent, "TwinLeft", Vector3(tower_w, left_h, depth), Vector3(-offset, left_h * 0.5, 0), mat)
	_add_building_segment(parent, "TwinRight", Vector3(tower_w, right_h, depth), Vector3(offset, right_h * 0.5, 0), mat)
	# Skybridge at ~60 % height spanning the gap.
	var bridge_w: float = gap + 2.0
	_add_building_segment(parent, "Skybridge", Vector3(bridge_w, 2.5, depth * 0.55), Vector3(0, h * 0.6, 0), mat)
	return {"top_y": right_h, "top_w": tower_w, "top_d": depth}

func _build_setback(parent: StaticBody3D, width: float, depth: float, h: float, mat: Material) -> Dictionary:
	# Lower 70 % full footprint, upper 30 % narrower setback.
	var lower_h: float = h * 0.7
	var upper_h: float = h * 0.3
	var upper_w: float = width * 0.72
	var upper_d: float = depth * 0.72
	_add_building_segment(parent, "SetbackLower", Vector3(width, lower_h, depth), Vector3(0, lower_h * 0.5, 0), mat)
	_add_building_segment(parent, "SetbackUpper", Vector3(upper_w, upper_h, upper_d), Vector3(0, lower_h + upper_h * 0.5, 0), mat)
	return {"top_y": h, "top_w": upper_w, "top_d": upper_d}

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
	# City district ground plate — uses PBR asphalt material matching the main
	# ground plane so the district sits on the same textured surface.
	var ground := MeshInstance3D.new()
	ground.name = "ModularDistrictGroundPlate"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(260.0, 0.18, 260.0)
	ground.mesh = mesh
	ground.position = Vector3(0, -0.09, 0)
	ground.material_override = _ground_asphalt_material()
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
	var holder := _instance_prop(PROP_DIR + "street/street_light_modern.glb", "y", 5.6)
	if holder == null:
		_add_streetlight_primitive(parent, pos, rot)
		return
	holder.name = "StreetLight"
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rad_to_deg(rot), 0)
	parent.add_child(holder)
	# Warm-cyan lamp glow at the top of the post, parented to the model.
	var omni := OmniLight3D.new()
	omni.name = "StreetLightOmni"
	omni.position = Vector3(0, 5.3, 0)
	omni.light_color = Color(0.55, 0.85, 1.0, 1.0)
	omni.light_energy = 3.0
	omni.omni_range = 11.0
	holder.add_child(omni)

func _add_streetlight_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
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

# Real CC0 Kenney Nature Kit trees, rotated through 3 variants. Placed every other
# block so they don't choke the avenue. Trees sit between the road and the tower
# footprints, breaking up the long flat curb line. A faint canopy glow keeps the
# foliage reading against the night sky like the rest of the neon city.
const TREE_VARIANTS := [
	"vegetation/tree_01.glb",
	"vegetation/tree_02.glb",
	"vegetation/tree_03.glb",
]
const TREE_GLOW_COLORS := [
	Color(0.1, 0.85, 0.6, 1.0),
	Color(0.6, 0.18, 0.95, 1.0),
]

func _add_street_trees(parent: Node3D, avenue_z: float, north_side: bool) -> void:
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
		var tree_name := "StreetTree_%s_%d" % [("N" if north_side else "S"), step]
		var variant := absi(int(avenue_z) + step) % TREE_VARIANTS.size()
		var glow_color: Color = TREE_GLOW_COLORS[0] if step > 0 else TREE_GLOW_COLORS[1]
		_add_tree(parent, tree_name, Vector3(x, 0.0, z), variant, glow_color)

func _add_tree(parent: Node3D, tree_name: String, pos: Vector3, variant: int, glow_color: Color) -> void:
	var holder := _instance_prop(PROP_DIR + TREE_VARIANTS[variant], "y", 5.0)
	if holder == null:
		_add_tree_primitive(parent, tree_name, pos, glow_color)
		return
	holder.name = tree_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, float((int(pos.x) + int(pos.z)) % 4) * 90.0, 0)
	parent.add_child(holder)
	var glow := OmniLight3D.new()
	glow.name = "TreeGlow"
	glow.position = Vector3(0, 3.2, 0)
	glow.light_color = glow_color
	glow.light_energy = 1.4
	glow.omni_range = 5.5
	holder.add_child(glow)

func _add_tree_primitive(parent: Node3D, tree_name: String, pos: Vector3, glow_color: Color) -> void:
	var trunk_mat := _mat(Color(0.05, 0.08, 0.1, 1.0), Color(0.0, 0.18, 0.25, 1.0), 0.08)
	var canopy_mat := _mat(glow_color * 0.45, glow_color, 0.6)
	var tree := Node3D.new()
	tree.name = tree_name
	tree.position = pos
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
	glow.light_color = glow_color
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

func _add_crown_neon(parent: Node3D, width: float, depth: float, top_y: float) -> void:
	# Bright neon rim band wrapped around the top segment so the skyline
	# silhouettes read against the dark sky from any capture altitude. Variants
	# cycle cyan / magenta per tower so the city feels populated.
	var hue := fposmod(width + depth + top_y, 4.0)
	var crown_mat: StandardMaterial3D
	if hue < 1.5:
		crown_mat = _mat(Color(0.25, 0.95, 1.0, 1.0), Color(0.25, 0.95, 1.0, 1.0), 1.0)
	elif hue < 3.0:
		crown_mat = _mat(Color(0.95, 0.25, 0.85, 1.0), Color(0.95, 0.25, 0.85, 1.0), 0.95)
	else:
		crown_mat = _mat(Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.85, 0.3, 1.0), 0.9)
	var y := top_y - 0.18
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

func _add_vertical_ribs(parent: Node3D, width: float, depth: float, top_y: float, collector: bool) -> void:
	var rib_mat := _mat(Color(0.16, 0.24, 0.29, 1.0), Color(0.0, 0.25, 0.34, 1.0), 0.1)
	if collector:
		rib_mat = _mat(Color(0.18, 0.34, 0.42, 1.0), Color(0.0, 0.45, 0.65, 1.0), 0.2)
	var rib_h: float = top_y + 0.3
	var rib_cy: float = top_y * 0.5
	_add_box(parent, "FrontLeftRib", Vector3(0.18, rib_h, 0.18), Vector3(-width * 0.48, rib_cy, depth * 0.48), rib_mat)
	_add_box(parent, "FrontRightRib", Vector3(0.18, rib_h, 0.18), Vector3(width * 0.48, rib_cy, depth * 0.48), rib_mat)
	_add_box(parent, "BackLeftRib", Vector3(0.18, rib_h, 0.18), Vector3(-width * 0.48, rib_cy, -depth * 0.48), rib_mat)
	_add_box(parent, "BackRightRib", Vector3(0.18, rib_h, 0.18), Vector3(width * 0.48, rib_cy, -depth * 0.48), rib_mat)

func _add_roof_detail(parent: Node3D, width: float, depth: float, top_y: float, x: int, z: int, collector: bool) -> void:
	var cap_mat := _mat(Color(0.18, 0.28, 0.34, 1.0), Color(0.0, 0.32, 0.42, 1.0), 0.12)
	var roof := _add_box(parent, "RooftopCap", Vector3(width + 0.8, 0.45, depth + 0.8), Vector3(0, top_y + 0.22, 0), cap_mat)
	var antenna := MeshInstance3D.new()
	antenna.name = "RooftopAntenna"
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.18
	antenna_mesh.bottom_radius = 0.18
	antenna_mesh.height = 3.0
	antenna.mesh = antenna_mesh
	antenna.position = Vector3(0, top_y + 1.9, 0)
	antenna.material_override = _mat(Color(0.2, 0.9, 1.0, 1.0), Color(0.2, 0.9, 1.0, 1.0), 0.9)
	parent.add_child(antenna)
	if collector:
		_add_box(parent, "CollectorCrown", Vector3(width * 0.7, 3.2, depth * 0.7), Vector3(0, top_y + 2.2, 0), _mat(Color(0.12, 0.32, 0.42, 1.0), Color(0.0, 0.7, 1.0, 1.0), 0.7))
		var spire := MeshInstance3D.new()
		spire.name = "CollectorSpire"
		var spire_mesh := CylinderMesh.new()
		spire_mesh.top_radius = 0.18
		spire_mesh.bottom_radius = 0.55
		spire_mesh.height = 7.5
		spire.mesh = spire_mesh
		spire.position = Vector3(0, top_y + 6.1, 0)
		spire.material_override = _mat(Color(0.25, 0.95, 1.0, 1.0), Color(0.1, 0.8, 1.0, 1.0), 1.0)
		parent.add_child(spire)
	elif (x + z) % 4 == 0:
		_add_box(parent, "CrownBlock", Vector3(width * 0.55, 2.8, depth * 0.55), Vector3(0, top_y + 1.85, 0), _mat(Color(0.22, 0.3, 0.36, 1.0), Color(0.0, 0.35, 0.48, 1.0), 0.25))
	elif (x - z) % 4 == 0:
		var spire := MeshInstance3D.new()
		spire.name = "SignalSpire"
		var spire_mesh := CylinderMesh.new()
		spire_mesh.top_radius = 0.18
		spire_mesh.bottom_radius = 0.7
		spire_mesh.height = 5.5
		spire.mesh = spire_mesh
		spire.position = Vector3(0, top_y + 3.3, 0)
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
		pad.position = Vector3(0, top_y + 0.42, 0)
		pad.material_override = _mat(Color(0.04, 0.11, 0.16, 1.0), Color(0.0, 0.35, 0.5, 1.0), 0.25)
		parent.add_child(pad)
		var ring := MeshInstance3D.new()
		ring.name = "DronePadRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 2.0
		ring_mesh.outer_radius = 2.25
		ring.mesh = ring_mesh
		ring.position = Vector3(0, top_y + 0.58, 0)
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
			ring.position = Vector3(0, top_y + offset, 0)
			ring.rotation_degrees = Vector3(90, 0, 0)
			ring.material_override = _transparent_mat(Color(0.0, 0.55, 0.9, 0.28), Color(0.0, 0.9, 1.0, 1.0), 0.75)
			parent.add_child(ring)
		var core := MeshInstance3D.new()
		core.name = "CollectorCoreGlow"
		var core_mesh := CylinderMesh.new()
		core_mesh.top_radius = 1.2
		core_mesh.bottom_radius = 1.2
		core_mesh.height = top_y + 4.0
		core.mesh = core_mesh
		core.position = Vector3(0, (top_y + 4.0) * 0.5, 0)
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

# ── Real prop loading / fitting ──

# Load and cache a GLB PackedScene. Returns null (and warns once) if the asset is
# missing or fails to import so callers can fall back to a primitive build.
func _load_prop(path: String) -> PackedScene:
	if _prop_scene_cache.has(path):
		return _prop_scene_cache[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
		if scene == null:
			push_warning("Prop asset failed to load as PackedScene: " + path)
	else:
		push_warning("Prop asset not found: " + path)
	_prop_scene_cache[path] = scene
	return scene

# Combined world-space AABB of every MeshInstance3D under `node`, accumulated into
# acc = [min_corner, max_corner] (each null until the first mesh is seen).
func _accumulate_mesh_aabb(node: Node, xf: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var a: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for i in range(8):
			var corner := a.position + Vector3(
				a.size.x if (i & 1) != 0 else 0.0,
				a.size.y if (i & 2) != 0 else 0.0,
				a.size.z if (i & 4) != 0 else 0.0)
			var p: Vector3 = xf * corner
			if acc[0] == null:
				acc[0] = p
				acc[1] = p
			else:
				acc[0] = Vector3(min(acc[0].x, p.x), min(acc[0].y, p.y), min(acc[0].z, p.z))
				acc[1] = Vector3(max(acc[1].x, p.x), max(acc[1].y, p.y), max(acc[1].z, p.z))
	for ch in node.get_children():
		var cxf := xf
		if ch is Node3D:
			cxf = xf * (ch as Node3D).transform
		_accumulate_mesh_aabb(ch, cxf, acc)

# Instance a real prop GLB auto-fitted to a target size. The model is uniformly
# scaled so its `fit_axis` ("x"/"y"/"z") native extent equals `target_size`, then
# grounded so its lowest point sits at y=0. Source GLBs range from ~0.1u (Kenney)
# to ~230u (Google Poly) native, so fitting is computed at runtime from the mesh
# AABB rather than hardcoded. Returns a holder Node3D, or null on load failure.
func _instance_prop(path: String, fit_axis: String, target_size: float, recenter_xz: bool = false, pre_rot := Vector3.ZERO) -> Node3D:
	var scene := _load_prop(path)
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		push_warning("Prop scene root is not Node3D: " + path)
		return null
	if pre_rot != Vector3.ZERO:
		model.rotation_degrees = pre_rot
	var acc: Array = [null, null]
	_accumulate_mesh_aabb(model, model.transform, acc)
	var holder := Node3D.new()
	holder.add_child(model)
	if acc[0] == null:
		return holder
	var size: Vector3 = acc[1] - acc[0]
	var native: float = size.y
	if fit_axis == "x":
		native = size.x
	elif fit_axis == "z":
		native = size.z
	if native <= 0.0001:
		native = max(size.x, max(size.y, size.z))
	var scale_f: float = target_size / native if native > 0.0001 else 1.0
	model.scale = model.scale * scale_f
	var smin: Vector3 = acc[0] * scale_f
	var smax: Vector3 = acc[1] * scale_f
	model.position.y = -smin.y
	if recenter_xz:
		model.position.x = -(smin.x + smax.x) * 0.5
		model.position.z = -(smin.z + smax.z) * 0.5
	return holder

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

	# Health bar (top-right free margin beside the status panel).
	health_bar_bg = ColorRect.new()
	health_bar_bg.name = "HealthBarBG"
	health_bar_bg.position = Vector2(1040, 14)
	health_bar_bg.size = Vector2(224, 26)
	health_bar_bg.color = Color(0.02, 0.04, 0.06, 0.85)
	health_bar_bg.z_index = 0
	layer.add_child(health_bar_bg)
	health_bar_fill = ColorRect.new()
	health_bar_fill.name = "HealthBarFill"
	health_bar_fill.position = Vector2(1042, 16)
	health_bar_fill.size = Vector2(220, 22)
	health_bar_fill.color = Color(0.2, 0.9, 0.45, 1.0)
	health_bar_fill.z_index = 1
	layer.add_child(health_bar_fill)
	health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.position = Vector2(1048, 16)
	health_label.add_theme_font_size_override("font_size", 16)
	health_label.add_theme_color_override("font_color", Color(0.02, 0.05, 0.04, 1.0))
	health_label.z_index = 2
	layer.add_child(health_label)

	# Minimap / radar — bottom-right corner.
	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.size = Vector2(156, 156)
	minimap.position = Vector2(1108, 548)
	minimap.z_index = 1
	layer.add_child(minimap)

	# Transient power-unlock toast (top-centre, hidden until an unlock fires).
	unlock_toast = Label.new()
	unlock_toast.name = "UnlockToast"
	unlock_toast.position = Vector2(360, 110)
	unlock_toast.size = Vector2(560, 40)
	unlock_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unlock_toast.add_theme_font_size_override("font_size", 26)
	unlock_toast.add_theme_color_override("font_color", Color(0.4, 1.0, 0.85, 1.0))
	unlock_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	unlock_toast.add_theme_constant_override("shadow_offset_x", 2)
	unlock_toast.add_theme_constant_override("shadow_offset_y", 2)
	unlock_toast.modulate = Color(1, 1, 1, 0)
	unlock_toast.z_index = 3
	layer.add_child(unlock_toast)

	# Transient mission-completion banner (centre screen).
	mission_banner = Label.new()
	mission_banner.name = "MissionBanner"
	mission_banner.position = Vector2(340, 300)
	mission_banner.size = Vector2(600, 48)
	mission_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_banner.add_theme_font_size_override("font_size", 30)
	mission_banner.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55, 1.0))
	mission_banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	mission_banner.add_theme_constant_override("shadow_offset_x", 2)
	mission_banner.add_theme_constant_override("shadow_offset_y", 2)
	mission_banner.modulate = Color(1, 1, 1, 0)
	mission_banner.z_index = 3
	layer.add_child(mission_banner)

	# Game-over overlay (centre screen, hidden until health hits zero).
	game_over_label = Label.new()
	game_over_label.name = "GameOverOverlay"
	game_over_label.position = Vector2(440, 320)
	game_over_label.size = Vector2(400, 80)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 56)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2, 1.0))
	game_over_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	game_over_label.add_theme_constant_override("shadow_offset_x", 3)
	game_over_label.add_theme_constant_override("shadow_offset_y", 3)
	game_over_label.visible = false
	game_over_label.z_index = 4
	layer.add_child(game_over_label)

	# Controls hint (bottom-left); text swaps between keyboard and gamepad in _update_hud.
	controls_hint_label = Label.new()
	controls_hint_label.name = "ControlsHint"
	controls_hint_label.position = Vector2(24, 678)
	controls_hint_label.size = Vector2(1000, 28)
	controls_hint_label.add_theme_font_size_override("font_size", 15)
	controls_hint_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.85))
	controls_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	controls_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	controls_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	controls_hint_label.z_index = 1
	layer.add_child(controls_hint_label)

	# Full-screen tint used by power VFX (e.g. sonic-burst screen flash). Starts clear
	# and is pulsed by flash_screen(). Ignores mouse so it never blocks the UI.
	screen_flash = ColorRect.new()
	screen_flash.name = "ScreenFlash"
	screen_flash.position = Vector2(0, 0)
	screen_flash.size = Vector2(1280, 720)
	screen_flash.color = Color(1, 1, 1, 0)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_flash.z_index = 5
	layer.add_child(screen_flash)

	# Sync transient-notification baselines after any save-load so the first frame
	# does not fire a spurious unlock toast / mission banner for restored progress.
	_last_unlocked_count = progression.unlocked.size()
	_last_banner_step = missions.mission_step

func _update_hud() -> void:
	if hud_label == null: return
	var next_xp: int = progression.xp_for_next()
	hud_label.text = "AURORA VIGIL  |  Level %d  XP %d/%d  |  %s  |  Active: %d  Resolved: %d  Choir: %d" % [progression.level, progression.xp, next_xp, _power_hud_text(), events.event_nodes.size(), events.resolved_events, enemy_system.active_count()]
	mission_label.text = missions.hud_text()
	var nearest := events.nearest_event()
	if nearest == null:
		event_cue_label.text = "Event cue: no active emergencies. %s" % last_event_text
	else:
		var kind := str(nearest.get_meta("kind", "city_event"))
		var dist := hero.position.distance_to(nearest.position)
		var proximity := "IN RANGE" if dist <= events.EVENT_RESOLVE_RADIUS else "approach %.0fm" % max(dist - events.EVENT_RESOLVE_RADIUS, 0.0)
		event_cue_label.text = "Nearest: %s — %.0fm (%s). %s. Last: %s" % [events.format_event_name(kind), dist, proximity, events.required_action_for_event(kind), last_event_text]
	_update_health_hud()
	_update_minimap()
	_update_controls_hint()

func _update_controls_hint() -> void:
	if controls_hint_label == null:
		return
	if Input.get_connected_joypads().size() > 0:
		controls_hint_label.text = "Gamepad: Left stick fly · Triggers climb/dive · Bumpers boost · A rescue · B sonic · X radiant · Y aegis · Right stick look · Select pause"
	else:
		controls_hint_label.text = "Keyboard: WASD fly · Space/Ctrl climb/dive · Shift boost · R rescue · Q sonic · F radiant · E aegis · Esc pause"

# Lists the four key-bound powers, marking any the hero has not yet unlocked.
func _power_hud_text() -> String:
	var parts: Array[String] = []
	for p in HUD_POWERS:
		var id: String = p["id"]
		var label := "%s %s" % [p["key"], id.replace("_", " ")]
		if not progression.has_power(id):
			label += " [LOCKED]"
		parts.append(label)
	return "Powers: " + "  ".join(parts)

func _update_health_hud() -> void:
	if health_bar_fill == null:
		return
	var hp: float = health_system.health
	var frac: float = clamp(hp / HealthSystem.MAX_HEALTH, 0.0, 1.0)
	health_bar_fill.size = Vector2(220.0 * frac, 22.0)
	# Green → amber → red as the hero takes damage; cyan flash while aegis is up.
	if health_system.is_aegis_active():
		health_bar_fill.color = Color(0.3, 0.8, 1.0, 1.0)
	elif frac > 0.5:
		health_bar_fill.color = Color(0.2, 0.9, 0.45, 1.0)
	elif frac > 0.25:
		health_bar_fill.color = Color(0.95, 0.7, 0.2, 1.0)
	else:
		health_bar_fill.color = Color(0.95, 0.25, 0.2, 1.0)
	var suffix := "  [AEGIS]" if health_system.is_aegis_active() else ""
	health_label.text = "HP %d/%d%s" % [int(round(hp)), int(HealthSystem.MAX_HEALTH), suffix]
	if game_over_label != null:
		# In interactive play the dedicated GameOverScreen overlay handles this; the
		# simple centre label only shows when no screen exists (capture/headless).
		game_over_label.visible = health_system.game_over and game_over_screen == null
		if game_over_label.visible:
			game_over_label.text = "GAME OVER"

func _update_minimap() -> void:
	if minimap == null:
		return
	var dots: Array = []
	for marker in events.event_nodes:
		if not is_instance_valid(marker):
			continue
		var kind := str(marker.get_meta("kind", "city_event"))
		dots.append({
			"offset": Vector2(marker.position.x - hero.position.x, marker.position.z - hero.position.z),
			"color": events.event_color(kind),
		})
	# Null Choir units as violet pips so the radar shows the ground threat too.
	for u in enemy_system.units:
		var node = u["node"]
		if not is_instance_valid(node) or u["dying"]:
			continue
		dots.append({
			"offset": Vector2(node.position.x - hero.position.x, node.position.z - hero.position.z),
			"color": EnemySystem.UNIT_COLOR,
		})
	var objective_offset = null
	var obj_pos = _objective_world_pos()
	if obj_pos != null:
		objective_offset = Vector2(obj_pos.x - hero.position.x, obj_pos.z - hero.position.z)
	var forward := -hero.global_transform.basis.z
	minimap.set_radar(hero.position, forward, dots, objective_offset)

# World position of the active mission objective marker, or null when none is live.
func _objective_world_pos():
	if objectives != null and objectives.marker != null and is_instance_valid(objectives.marker):
		return objectives.marker.global_position
	return null

# Drives the transient unlock toast and mission banner: detects new unlocks / mission
# advances by comparing against cached counters, then fades the labels out over 3 s.
func _update_transients(delta: float) -> void:
	if progression.unlocked.size() > _last_unlocked_count:
		var newly: Array[String] = []
		for i in range(_last_unlocked_count, progression.unlocked.size()):
			newly.append(progression.unlocked[i].replace("_", " ").to_upper())
		_last_unlocked_count = progression.unlocked.size()
		if unlock_toast != null:
			unlock_toast.text = "POWER UNLOCKED: %s" % ", ".join(newly)
			unlock_toast.modulate = Color(1, 1, 1, 1)
			_toast_timer = 3.0
	if missions.mission_step > _last_banner_step:
		var done_idx: int = clamp(missions.mission_step - 1, 0, missions.missions.size() - 1)
		_last_banner_step = missions.mission_step
		var done: Dictionary = missions.missions[done_idx]
		_show_mission_banner(str(done["title"]), int(done.get("reward_xp", 0)))
	if _toast_timer > 0.0 and unlock_toast != null:
		_toast_timer = max(0.0, _toast_timer - delta)
		unlock_toast.modulate = Color(1, 1, 1, clamp(_toast_timer, 0.0, 1.0))

# Gold mission-complete banner that slides in from the top, holds ~2 s with the XP
# reward, then slides back out — driven by a single remembered tween.
func _show_mission_banner(title: String, reward_xp: int) -> void:
	if mission_banner == null:
		return
	mission_banner.text = "MISSION COMPLETE: %s   +%d XP" % [title, reward_xp]
	mission_banner.position = Vector2(340, -48)
	mission_banner.modulate = Color(1, 1, 1, 0)
	var tween: Tween = _remember_tween(create_tween())
	tween.tween_property(mission_banner, "position:y", 96.0, 0.4)
	tween.parallel().tween_property(mission_banner, "modulate:a", 1.0, 0.4)
	tween.tween_interval(2.0)
	tween.tween_property(mission_banner, "position:y", -48.0, 0.4)
	tween.parallel().tween_property(mission_banner, "modulate:a", 0.0, 0.4)

func _city_facade_material(h: float, x: int, z: int, width: float, depth: float, collector: bool) -> ShaderMaterial:
	# Per-building deterministic seed from grid position
	var seed_val := (x * 73856093) ^ (z * 19349663)
	if seed_val < 0:
		seed_val = -seed_val
	# Window grid params derived from building dimensions
	var floors_val: int = int(clamp(h / 4.2, 5.0, 11.0))
	var windows_val: int = 3 + (abs(x * 13 + z * 7) % 4)
	# Collectors: more lit windows, brighter emission
	var lit_prob := 0.55 if not collector else 0.75
	var em_energy := 1.0 if not collector else 1.6
	# UV scale variation per building — real PBR textures need higher tiling for visible detail
	var uv_s := 4.0 + float(abs(x + z) % 3) * 0.5
	if h > 42.0:
		uv_s += 0.5
	if collector:
		uv_s += 0.3
	# Albedo tint variation
	var tint_r := 0.80 + float(abs(x) % 5) * 0.03
	var tint_g := 0.88 + float(abs(z) % 4) * 0.025
	var tint_b := 1.0
	if collector:
		tint_r = 0.70
		tint_g = 0.85
	# Cycle through PBR texture sets (collectors → commercial facade = index 4)
	var mat_idx: int = 4 if collector else abs(x * 3 + z * 7) % 5
	var mat := ShaderMaterial.new()
	mat.shader = FACADE_SHADER
	mat.set_shader_parameter("building_seed", seed_val)
	mat.set_shader_parameter("floors", floors_val)
	mat.set_shader_parameter("windows_per_floor", windows_val)
	mat.set_shader_parameter("lit_probability", lit_prob)
	mat.set_shader_parameter("emission_energy", em_energy)
	mat.set_shader_parameter("uv_scale", uv_s)
	mat.set_shader_parameter("albedo_tint", Color(tint_r, tint_g, tint_b, 1.0))
	mat.set_shader_parameter("flicker_speed", 2.5 + float(abs(x * 3 + z) % 5) * 0.5)
	mat.set_shader_parameter("frame_color", Color(0.02, 0.04, 0.06, 1.0))
	mat.set_shader_parameter("dark_window", Color(0.015, 0.03, 0.045, 1.0))
	# PBR texture uniforms — passed from preloaded facade texture sets
	if not _facade_albedo_textures.is_empty():
		var idx: int = clamp(mat_idx, 0, _facade_albedo_textures.size() - 1)
		var pbr: Dictionary = FACADE_PBR_PROPS[idx]
		mat.set_shader_parameter("albedo_tex", _facade_albedo_textures[idx])
		mat.set_shader_parameter("normal_tex", _facade_normal_textures[idx])
		mat.set_shader_parameter("roughness_tex", _facade_roughness_textures[idx])
		mat.set_shader_parameter("emission_tex", _facade_emission_textures[idx])
		mat.set_shader_parameter("roughness_base", float(pbr.get("roughness", 0.5)))
		mat.set_shader_parameter("metallic_val", float(pbr.get("metallic", 0.14)))
		mat.set_shader_parameter("use_normal_map", true)
		# Real PBR textures: respect roughness map more, scale normal map intensity
		mat.set_shader_parameter("roughness_tex_weight", 0.8)
		mat.set_shader_parameter("normal_map_scale", 0.8)
	else:
		mat.set_shader_parameter("use_normal_map", false)
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

# ── Release-polish: screen flash, difficulty, and menu flow ──

# Pulse a full-screen tint to 0 alpha over ~0.4 s. `c.a` is the peak intensity.
# Called by PowerSystem for the sonic-burst flash; safe if the HUD is not built.
func flash_screen(c: Color) -> void:
	if screen_flash == null or not is_instance_valid(screen_flash):
		return
	screen_flash.color = c
	var tween: Tween = _remember_tween(create_tween())
	tween.tween_property(screen_flash, "color:a", 0.0, 0.4)

# Reads the current difficulty multipliers from SettingsManager and pushes them into
# the live gameplay systems. Re-callable after a settings change. Guarded so it is a
# no-op if the autoload is unavailable (defaults already resolve to Normal).
func _apply_difficulty() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	if enemy_system != null:
		enemy_system.damage_mult = sm.enemy_damage_mult()
	if health_system != null:
		health_system.regen_mult = sm.health_regen_mult()
	if events != null:
		events.spawn_mult = sm.event_spawn_mult()

# Public hook the settings UI calls when it closes.
func apply_difficulty() -> void:
	_apply_difficulty()

func is_game_over() -> bool:
	if game_over_screen != null:
		return game_over_screen.is_shown()
	return health_system != null and health_system.game_over

func _build_menus() -> void:
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(self)
	game_over_screen = GameOverScreenScript.new()
	game_over_screen.name = "GameOverScreen"
	add_child(game_over_screen)
	game_over_screen.setup(self)

func _show_main_menu() -> void:
	if main_menu != null and is_instance_valid(main_menu):
		main_menu.queue_free()
	main_menu = MAIN_MENU_SCENE.instantiate()
	add_child(main_menu)
	main_menu.setup(self)
	get_tree().paused = true

# New Game (fresh=true) resets run progress in place; Continue (fresh=false) keeps the
# loaded save. Either way the title backdrop is dismissed and play resumes.
func start_game(fresh: bool) -> void:
	if fresh:
		progression.level = 1
		progression.xp = 0
		var base_powers: Array[String] = ["flight", "boost"]
		progression.unlocked = base_powers
		missions.mission_step = 0
		events.resolved_events = 0
		health_system.health = HealthSystem.MAX_HEALTH
		health_system.game_over = false
		if hero != null:
			hero.position = health_system.checkpoint
		_last_unlocked_count = progression.unlocked.size()
		_last_banner_step = 0
	get_tree().paused = false
	if main_menu != null and is_instance_valid(main_menu):
		main_menu.queue_free()
		main_menu = null
	_update_hud()

func retry_from_checkpoint() -> void:
	health_system.game_over = false
	health_system.health = HealthSystem.RESPAWN_HEALTH
	health_system.aegis_timer = 0.0
	if hero != null:
		hero.position = health_system.checkpoint
	get_tree().paused = false
	_update_hud()

func return_to_main_menu() -> void:
	if pause_menu != null and pause_menu.is_open():
		pause_menu.close()
	_show_main_menu()

func request_quit() -> void:
	if _persistence_enabled():
		SaveGame.save(progression, missions, events)
	get_tree().paused = false
	await _cleanup_for_quit()
	get_tree().quit(0)

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
	# Drop cached PackedScene references before test/screenshot auto-quit so Godot's
	# resource leak detector does not report imported prop scenes still in use.
	_prop_scene_cache.clear()
	for child in get_children():
		child.free()
	get_tree().paused = was_paused
	await get_tree().process_frame

# ── Park zones, plaza paving, street props ──

func _add_park_zones(parent: Node3D) -> void:
	# 3 park/greenery zones at grid positions where the city loop skips buildings
	# (x+z)%3==0 → no building placed there. Each park is a grass-textured quad
	# with clustered tree props + low-glow bioluminescent shrubs.
	# Park quads sit at y=0.15 to render ABOVE the avenue surface (y=0.08).
	var grass_mat := _ground_grass_material()
	var park_coords := [
		[-4, 4],   # SW outer
		[2, 4],    # mid-east outer
		[-2, -4],  # NW outer
	]
	for coord in park_coords:
		var px: float = float(coord[0]) * 22.0
		var pz: float = float(coord[1]) * 22.0
		var park := MeshInstance3D.new()
		park.name = "ParkZone_%d_%d" % [coord[0], coord[1]]
		var park_mesh := PlaneMesh.new()
		park_mesh.size = Vector2(18.0, 18.0)
		park.mesh = park_mesh
		park.position = Vector3(px, 0.15, pz)
		park.material_override = grass_mat
		parent.add_child(park)
		# Tree cluster: 5-7 trees in a loose ring
		var tree_positions := [
			Vector3(px - 6, 0, pz - 4),
			Vector3(px + 5, 0, pz - 6),
			Vector3(px - 2, 0, pz + 7),
			Vector3(px + 7, 0, pz + 3),
			Vector3(px - 7, 0, pz + 5),
			Vector3(px + 2, 0, pz - 8),
		]
		for tpos in tree_positions:
			_add_park_tree(parent, tpos)
		# Bioluminescent shrub glow
		for i in range(3):
			var shrub_pos := Vector3(px + float((i * 7 - 7)), 0, pz + float((i * 5 - 5)))
			_add_glow_shrub(parent, shrub_pos, i)

func _add_park_tree(parent: Node3D, pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.name = "ParkTree_%d_%d" % [int(pos.x), int(pos.z)]
	tree.position = pos
	parent.add_child(tree)
	var trunk_mat := _mat(Color(0.08, 0.06, 0.04, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	var trunk := MeshInstance3D.new()
	trunk.name = "ParkTreeTrunk"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.35
	trunk_mesh.height = 4.0
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, 2.0, 0)
	trunk.material_override = trunk_mat
	tree.add_child(trunk)
	# Layered canopy — two spheres for volume
	var canopy_a_mat := _mat(Color(0.06, 0.35, 0.18, 1.0), Color(0.08, 0.6, 0.35, 1.0), 0.35)
	var canopy_b_mat := _mat(Color(0.04, 0.45, 0.22, 1.0), Color(0.1, 0.75, 0.4, 1.0), 0.45)
	var canopy1 := MeshInstance3D.new()
	canopy1.name = "ParkTreeCanopy1"
	var c1_mesh := SphereMesh.new()
	c1_mesh.radius = 2.2
	c1_mesh.height = 3.5
	canopy1.mesh = c1_mesh
	canopy1.position = Vector3(0, 5.0, 0)
	canopy1.material_override = canopy_a_mat
	tree.add_child(canopy1)
	var canopy2 := MeshInstance3D.new()
	canopy2.name = "ParkTreeCanopy2"
	var c2_mesh := SphereMesh.new()
	c2_mesh.radius = 1.6
	c2_mesh.height = 2.5
	canopy2.mesh = c2_mesh
	canopy2.position = Vector3(0.8, 6.5, 0.5)
	canopy2.material_override = canopy_b_mat
	tree.add_child(canopy2)
	var glow := OmniLight3D.new()
	glow.name = "ParkTreeGlow"
	glow.position = Vector3(0, 5.0, 0)
	glow.light_color = Color(0.1, 0.6, 0.35, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 8.0
	tree.add_child(glow)

func _add_glow_shrub(parent: Node3D, pos: Vector3, variant: int) -> void:
	var shrub := Node3D.new()
	shrub.name = "GlowShrub_%d_%d" % [int(pos.x), int(pos.z)]
	shrub.position = pos
	parent.add_child(shrub)
	var colors: Array[Color] = [
		Color(0.25, 0.9, 1.0, 1.0),
		Color(0.9, 0.25, 0.75, 1.0),
		Color(0.3, 0.95, 0.5, 1.0),
	]
	var c: Color = colors[variant % colors.size()]
	var shrub_mat := _mat(c * 0.3, c, 0.6)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ShrubMesh"
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.6
	s_mesh.height = 1.0
	mesh_inst.mesh = s_mesh
	mesh_inst.position = Vector3(0, 0.5, 0)
	mesh_inst.material_override = shrub_mat
	shrub.add_child(mesh_inst)
	var glow := OmniLight3D.new()
	glow.name = "ShrubGlow"
	glow.position = Vector3(0, 0.5, 0)
	glow.light_color = c
	glow.light_energy = 1.5
	glow.omni_range = 4.0
	shrub.add_child(glow)

func _add_plaza_paving(parent: Node3D) -> void:
	# Polished plaza-textured quads around the 4 collector towers at (±5, ±5).
	var plaza_mat := _ground_plaza_material()
	for x in [-5, 5]:
		for z in [-5, 5]:
			var plaza := MeshInstance3D.new()
			plaza.name = "PlazaPaving_%d_%d" % [x, z]
			var p_mesh := PlaneMesh.new()
			p_mesh.size = Vector2(24.0, 24.0)
			plaza.mesh = p_mesh
			plaza.position = Vector3(float(x) * 22.0, 0.15, float(z) * 22.0)
			plaza.material_override = plaza_mat
			parent.add_child(plaza)
			# Decorative plaza border strip — cyan inlay
			for side in [-1.0, 1.0]:
				var strip_x := MeshInstance3D.new()
				strip_x.name = "PlazaStripX_%d_%d_%d" % [x, z, int(side)]
				var sx_mesh := BoxMesh.new()
				sx_mesh.size = Vector3(24.0, 0.04, 0.3)
				strip_x.mesh = sx_mesh
				strip_x.position = Vector3(float(x) * 22.0, 0.17, float(z) * 22.0 + side * 11.5)
				strip_x.material_override = _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.2, 0.8, 1.0, 1.0), 0.7)
				parent.add_child(strip_x)
				var strip_z := MeshInstance3D.new()
				strip_z.name = "PlazaStripZ_%d_%d_%d" % [x, z, int(side)]
				var sz_mesh := BoxMesh.new()
				sz_mesh.size = Vector3(0.3, 0.04, 24.0)
				strip_z.mesh = sz_mesh
				strip_z.position = Vector3(float(x) * 22.0 + side * 11.5, 0.17, float(z) * 22.0)
				strip_z.material_override = _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.2, 0.8, 1.0, 1.0), 0.7)
				parent.add_child(strip_z)

# ── Grid-breaking topology: diagonals, curves, plazas, sidewalks, parking ──

# Build a tower rotated to a street direction (not the grid). Reuses the full
# composite/facade/crown pipeline so aligned outskirt towers match the core city.
func _add_aligned_tower(parent: Node3D, t_name: String, pos: Vector3, rot_deg: float, width: float, depth: float, h: float, seed_a: int, seed_b: int) -> void:
	var body := StaticBody3D.new()
	body.name = t_name
	body.position = pos
	body.rotation_degrees = Vector3(0, rot_deg, 0)
	parent.add_child(body)
	var mat := _city_facade_material(h, seed_a, seed_b, width, depth, false)
	var form: int = abs(seed_a * 41 + seed_b * 37) % 5
	var top: Dictionary = _build_composite_tower(body, form, width, depth, h, mat)
	var top_y: float = float(top["top_y"])
	var top_w: float = float(top["top_w"])
	var top_d: float = float(top["top_d"])
	_add_vertical_ribs(body, top_w, top_d, top_y, false)
	_add_crown_neon(body, top_w, top_d, top_y)

func _add_diagonal_streets(parent: Node3D) -> void:
	# Three boulevards slicing across the rigid grid at 30-45 degrees. Each lays a
	# glowing road surface + centre dashes + raised sidewalks, and lines its outer
	# (suburban) reaches with towers rotated to the street direction so the city
	# reads as real topology rather than a pure lattice.
	var road_mat := _mat(Color(0.03, 0.03, 0.05, 1.0), Color(0.22, 0.06, 0.20, 1.0), 0.22)
	var dash_mat := _mat(Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.7, 0.3, 1.0), 0.9)
	var walk_mat := _ground_plaza_material()
	# [angle_deg, perpendicular offset from centre, length]
	var diagonals := [
		[32.0, 0.0, 470.0],
		[-38.0, 46.0, 450.0],
		[45.0, -70.0, 440.0],
	]
	var di := 0
	for d in diagonals:
		var ang: float = d[0]
		var off: float = d[1]
		var length: float = d[2]
		var basis := Basis(Vector3.UP, deg_to_rad(ang))
		var dir: Vector3 = basis.x
		var perp: Vector3 = basis.z
		var center: Vector3 = perp * off
		var road := _add_box(parent, "DiagAvenue_%d" % di, Vector3(length, 0.16, 7.2), center + Vector3(0, 0.12, 0), road_mat)
		road.rotation_degrees = Vector3(0, ang, 0)
		for s in [-1.0, 1.0]:
			var walk := _add_box(parent, "DiagWalk_%d_%d" % [di, int(s)], Vector3(length, 0.15, 2.6), center + perp * (s * 5.4) + Vector3(0, 0.075, 0), walk_mat)
			walk.rotation_degrees = Vector3(0, ang, 0)
		var n_dash := int(length / 9.0)
		for k in range(-n_dash / 2, n_dash / 2):
			var t := float(k) * 9.0 + 4.5
			var dpos: Vector3 = center + dir * t + Vector3(0, 0.22, 0)
			var dash := _add_box(parent, "DiagDash_%d_%d" % [di, k], Vector3(4.5, 0.06, 0.3), dpos, dash_mat)
			dash.rotation_degrees = Vector3(0, ang, 0)
		# Aligned towers along the outer reaches (beyond the dense core).
		var t2 := -length * 0.5 + 20.0
		var bi := 0
		while t2 < length * 0.5 - 20.0:
			var along: Vector3 = center + dir * t2
			var r := along.length()
			if r > 118.0 and r < 210.0:
				for s2 in [-1.0, 1.0]:
					var bpos: Vector3 = along + perp * (s2 * 16.0)
					bpos.y = 0.0
					var seed_a := di * 17 + bi * 3 + int(s2)
					var seed_b := bi * 7 + di * 5
					var bw := 9.0 + float(abs(seed_a * 5 + seed_b) % 7)
					var bd := 9.0 + float(abs(seed_b * 3 + seed_a) % 7)
					var bh := 22.0 + float(abs(seed_a * 13 + seed_b * 7) % 40)
					_add_aligned_tower(parent, "DiagTower_%d_%d_%d" % [di, bi, int(s2)], bpos, ang, bw, bd, bh, seed_a, seed_b)
			t2 += 28.0
			bi += 1
		di += 1

func _add_curved_avenues(parent: Node3D) -> void:
	# Two sweeping arcs approximated by short tangent-aligned road segments. Outer
	# reaches carry towers rotated to the local tangent so the curve feels built.
	var road_mat := _mat(Color(0.03, 0.04, 0.05, 1.0), Color(0.06, 0.20, 0.24, 1.0), 0.2)
	var dash_mat := _mat(Color(0.7, 0.95, 1.0, 1.0), Color(0.4, 0.85, 1.0, 1.0), 0.9)
	# [origin_x, origin_z, radius, start_deg, end_deg]
	var curves := [
		[220.0, 220.0, 300.0, 182.0, 268.0],
		[-235.0, -210.0, 305.0, 2.0, 88.0],
	]
	var ci := 0
	for c in curves:
		var ox: float = c[0]
		var oz: float = c[1]
		var radius: float = c[2]
		var a0: float = c[3]
		var a1: float = c[4]
		var seg_count := 26
		for si in range(seg_count + 1):
			var frac := float(si) / float(seg_count)
			var ang_deg := a0 + (a1 - a0) * frac
			var ang_rad := deg_to_rad(ang_deg)
			var px := ox + radius * cos(ang_rad)
			var pz := oz + radius * sin(ang_rad)
			var pos := Vector3(px, 0.12, pz)
			var tangent_deg := ang_deg + 90.0
			var seg_len := (deg_to_rad(absf(a1 - a0)) * radius) / float(seg_count) + 1.5
			if si < seg_count:
				var road := _add_box(parent, "CurveSeg_%d_%d" % [ci, si], Vector3(seg_len, 0.16, 7.2), pos, road_mat)
				road.rotation_degrees = Vector3(0, -tangent_deg, 0)
				var dash := _add_box(parent, "CurveDash_%d_%d" % [ci, si], Vector3(seg_len * 0.5, 0.06, 0.3), pos + Vector3(0, 0.11, 0), dash_mat)
				dash.rotation_degrees = Vector3(0, -tangent_deg, 0)
			var r := Vector2(px, pz).length()
			if r > 118.0 and r < 215.0 and si % 2 == 0:
				var cb := Basis(Vector3.UP, deg_to_rad(-tangent_deg))
				var perp: Vector3 = cb.z
				for s2 in [-1.0, 1.0]:
					var bpos: Vector3 = pos + perp * (s2 * 16.0)
					bpos.y = 0.0
					var seed_a := ci * 23 + si * 5 + int(s2)
					var seed_b := si * 11 + ci * 7
					var bw := 9.0 + float(abs(seed_a * 5 + seed_b) % 7)
					var bd := 9.0 + float(abs(seed_b * 3 + seed_a) % 7)
					var bh := 22.0 + float(abs(seed_a * 13 + seed_b * 7) % 38)
					_add_aligned_tower(parent, "CurveTower_%d_%d_%d" % [ci, si, int(s2)], bpos, -tangent_deg, bw, bd, bh, seed_a, seed_b)
		ci += 1

func _add_irregular_plazas(parent: Node3D) -> void:
	# Open paved squares out in the suburban ring where the diagonal/curved streets
	# converge — built from a few overlapping rotated quads for an irregular
	# outline, ringed (not filled) with towers and dressed with a beacon + benches.
	var plaza_mat := _ground_plaza_material()
	var edge_mat := _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.2, 0.8, 1.0, 1.0), 0.7)
	# [cx, cz, base_size, rot]
	var plazas := [
		[150.0, 36.0, 30.0, 18.0],
		[-122.0, -128.0, 34.0, -24.0],
		[58.0, -158.0, 28.0, 40.0],
	]
	var pidx := 0
	for p in plazas:
		var cx: float = p[0]
		var cz: float = p[1]
		var bs: float = p[2]
		var rot: float = p[3]
		var center := Vector3(cx, 0.15, cz)
		for q in range(3):
			var quad := MeshInstance3D.new()
			quad.name = "IrrPlazaPave_%d_%d" % [pidx, q]
			var qm := PlaneMesh.new()
			qm.size = Vector2(bs * (0.7 + 0.18 * float(q)), bs * (0.9 - 0.16 * float(q)))
			quad.mesh = qm
			quad.position = center + Vector3(float(q - 1) * bs * 0.16, float(q) * 0.01, float(1 - q) * bs * 0.14)
			quad.rotation_degrees = Vector3(0, rot + float(q) * 24.0, 0)
			quad.material_override = plaza_mat
			parent.add_child(quad)
		for s in [-1.0, 1.0]:
			var strip := _add_box(parent, "IrrPlazaEdgeX_%d_%d" % [pidx, int(s)], Vector3(bs, 0.05, 0.3), center + Vector3(0, 0.04, s * bs * 0.5), edge_mat)
			strip.rotation_degrees = Vector3(0, rot, 0)
			var strip2 := _add_box(parent, "IrrPlazaEdgeZ_%d_%d" % [pidx, int(s)], Vector3(0.3, 0.05, bs), center + Vector3(s * bs * 0.5, 0.04, 0), edge_mat)
			strip2.rotation_degrees = Vector3(0, rot, 0)
		var beacon_mat := _mat(Color(0.9, 0.25, 0.75, 1.0), Color(0.7, 0.05, 0.45, 1.0), 0.8)
		if pidx % 2 == 1:
			beacon_mat = _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.15, 0.75, 1.0, 1.0), 0.85)
		_add_plaza_pylon(parent, Vector3(cx, 0.0, cz), beacon_mat)
		for a in range(6):
			var ring_ang := float(a) * 60.0 + rot
			var rad := bs * 0.95
			var bx := cx + rad * cos(deg_to_rad(ring_ang))
			var bz := cz + rad * sin(deg_to_rad(ring_ang))
			var seed_a := pidx * 13 + a * 5
			var seed_b := a * 9 + pidx * 3
			var bw := 8.0 + float(abs(seed_a * 5 + seed_b) % 6)
			var bd := 8.0 + float(abs(seed_b * 3 + seed_a) % 6)
			var bh := 20.0 + float(abs(seed_a * 11 + seed_b * 7) % 34)
			var face := rad_to_deg(atan2(cz - bz, bx - cx))
			_add_aligned_tower(parent, "PlazaTower_%d_%d" % [pidx, a], Vector3(bx, 0.0, bz), face, bw, bd, bh, seed_a, seed_b)
		_add_bench(parent, Vector3(cx + 5.0, 0.0, cz), 0.0)
		_add_bench(parent, Vector3(cx - 5.0, 0.0, cz), 180.0)
		pidx += 1

func _add_sidewalks(parent: Node3D) -> void:
	# Raised sidewalks with a 0.15 m curb along the open mid-block corridors — the
	# real pedestrian streets that run between building rows at the half-gridlines.
	var walk_mat := _ground_plaza_material()
	var curb_mat := _mat(Color(0.06, 0.09, 0.12, 1.0), Color(0.0, 0.5, 0.7, 1.0), 0.4)
	var corridors := [-55.0, -33.0, -11.0, 11.0, 33.0, 55.0]
	for c in corridors:
		for s in [-1.0, 1.0]:
			_add_box(parent, "SidewalkNS_%d_%d" % [int(c), int(s)], Vector3(2.6, 0.15, 220.0), Vector3(c + s * 4.6, 0.075, 0.0), walk_mat)
			_add_box(parent, "SidewalkCurbNS_%d_%d" % [int(c), int(s)], Vector3(0.25, 0.17, 220.0), Vector3(c + s * 3.3, 0.085, 0.0), curb_mat)
			_add_box(parent, "SidewalkEW_%d_%d" % [int(c), int(s)], Vector3(220.0, 0.15, 2.6), Vector3(0.0, 0.075, c + s * 4.6), walk_mat)
			_add_box(parent, "SidewalkCurbEW_%d_%d" % [int(c), int(s)], Vector3(220.0, 0.17, 0.25), Vector3(0.0, 0.085, c + s * 3.3), curb_mat)
	# Fresh crosswalks at the mid-block corridor intersections (curb-cut ramps).
	for c in [-33.0, -11.0, 11.0, 33.0]:
		_add_crosswalk(parent, c, true)
		_add_crosswalk(parent, c, false)
		for s in [-1.0, 1.0]:
			# Curb-cut accessibility ramp wedges at the corners.
			_add_box(parent, "CurbCut_%d_%d" % [int(c), int(s)], Vector3(2.2, 0.07, 2.2), Vector3(c + s * 3.6, 0.04, c + s * 3.6), walk_mat)

func _add_parking_lots(parent: Node3D) -> void:
	# Flat asphalt lots with painted stalls + parked cars, dropped onto otherwise
	# empty lots and one suburban clearing — more grid-breaking open space.
	var lot_mat := _mat(Color(0.04, 0.045, 0.055, 1.0), Color(0.02, 0.05, 0.07, 1.0), 0.06)
	var line_mat := _mat(Color(0.85, 0.85, 0.6, 1.0), Color(0.6, 0.6, 0.3, 1.0), 0.5)
	# [cx, cz, cols, rows, rot]
	var lots := [
		[66.0, 0.0, 4, 3, 0.0],
		[0.0, -66.0, 4, 3, 0.0],
		[168.0, -40.0, 5, 3, 22.0],
	]
	var li := 0
	for lot in lots:
		var cx: float = lot[0]
		var cz: float = lot[1]
		var cols: int = lot[2]
		var rows: int = lot[3]
		var rot: float = lot[4]
		var stall_w := 2.6
		var stall_d := 5.0
		var lot_w := float(cols) * stall_w + 2.0
		var lot_d := float(rows) * stall_d + 2.0
		var pad := MeshInstance3D.new()
		pad.name = "ParkingLot_%d" % li
		var pm := PlaneMesh.new()
		pm.size = Vector2(lot_w, lot_d)
		pad.mesh = pm
		pad.position = Vector3(cx, 0.14, cz)
		pad.rotation_degrees = Vector3(0, rot, 0)
		pad.material_override = lot_mat
		parent.add_child(pad)
		var basis := Basis(Vector3.UP, deg_to_rad(rot))
		var ax: Vector3 = basis.x
		var az: Vector3 = basis.z
		for ccol in range(cols + 1):
			var lx := (float(ccol) - float(cols) * 0.5) * stall_w
			var lpos: Vector3 = Vector3(cx, 0.16, cz) + ax * lx
			var line := _add_box(parent, "ParkLine_%d_%d" % [li, ccol], Vector3(0.12, 0.04, stall_d * float(rows)), lpos, line_mat)
			line.rotation_degrees = Vector3(0, rot, 0)
		var carn := 0
		for ccol in range(cols):
			for rrow in range(rows):
				if (ccol + rrow) % 2 == 1:
					continue
				var sx := (float(ccol) - float(cols) * 0.5 + 0.5) * stall_w
				var sz := (float(rrow) - float(rows) * 0.5 + 0.5) * stall_d
				var cpos: Vector3 = Vector3(cx, 0.0, cz) + ax * sx + az * sz
				_add_car(parent, "LotCar_%d_%d" % [li, carn], cpos, rot, (li + carn) % CAR_VARIANTS.size())
				carn += 1
		li += 1

func _add_distant_skyline(parent: Node3D) -> void:
	# A static ring of dark, windowless silhouette blocks far beyond the playable
	# city, filling the horizon in every direction. No collision, no emission — they
	# read as a faint hazy skyline through the aerial-perspective fog.
	var sil := Node3D.new()
	sil.name = "DistantSkyline"
	parent.add_child(sil)
	var dark_a := _mat(Color(0.035, 0.04, 0.06, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	var dark_b := _mat(Color(0.05, 0.045, 0.07, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	var count := 96
	for i in range(count):
		var ang := float(i) / float(count) * TAU
		var ring := i % 2
		var base_r := 330.0 if ring == 0 else 430.0
		var jitter := float((abs(i * 37) % 60) - 30)
		var r := base_r + jitter
		var ang_jit := ang + float((abs(i * 13) % 20) - 10) * 0.004
		var px := r * cos(ang_jit)
		var pz := r * sin(ang_jit)
		var w := 16.0 + float(abs(i * 7) % 22)
		var d := 16.0 + float(abs(i * 11) % 22)
		var h := 30.0 + float(abs(i * 17) % 50)
		_add_box(sil, "Silhouette_%d" % i, Vector3(w, h, d), Vector3(px, h * 0.5, pz), dark_a if ring == 0 else dark_b)

func _add_haze_layers(parent: Node3D) -> void:
	# Two faint additive slabs giving the height bands a tint the single-colour
	# Environment fog can't: a warmer pool low, a cooler veil up high. The height
	# fog + aerial perspective do the heavy lifting; these only tint, never darken.
	var low := MeshInstance3D.new()
	low.name = "HazeLayerLow"
	var lm := PlaneMesh.new()
	lm.size = Vector2(300.0, 300.0)
	low.mesh = lm
	low.position = Vector3(0, 6.0, 0)
	var low_mat := _transparent_mat(Color(0.9, 0.55, 0.4, 0.05), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	low_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	low_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	low.material_override = low_mat
	low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(low)
	var high := MeshInstance3D.new()
	high.name = "HazeLayerHigh"
	var hm := PlaneMesh.new()
	hm.size = Vector2(320.0, 320.0)
	high.mesh = hm
	high.position = Vector3(0, 64.0, 0)
	var high_mat := _transparent_mat(Color(0.4, 0.5, 0.7, 0.04), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	high_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	high_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	high.material_override = high_mat
	high.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(high)

func _add_street_props(parent: Node3D) -> void:
	# Distribute real low-poly prop models along avenues at regular intervals.
	# Types: 0 traffic light, 1 bench, 2 trash bin, 3 planter, 4 scaffolding,
	# 5 barrier, 6 fire hydrant, 7 utility box, 8 news stand, 9 newspaper box,
	# 10 stop sign, 11 speed sign, 12 traffic cone.
	var prop_positions := [
		# [x, z, type, rotation]
		[-15.0, -44.0, 0, 0.0],   # traffic light
		[15.0, 22.0, 0, 180.0],
		[-44.0, 11.0, 0, 90.0],
		[44.0, -33.0, 0, -90.0],
		[-8.0, 66.0, 1, 0.0],     # bench
		[8.0, -66.0, 1, 180.0],
		[66.0, -11.0, 1, 90.0],
		[-66.0, 33.0, 1, -90.0],
		[-12.0, 0.0, 2, 0.0],     # trash bin
		[12.0, 44.0, 2, 180.0],
		[0.0, -22.0, 2, 90.0],
		[0.0, 55.0, 2, -90.0],
		[-9.0, 33.0, 3, 0.0],     # planter
		[9.0, -11.0, 3, 180.0],
		[33.0, 22.0, 3, 90.0],
		[-33.0, -44.0, 3, -90.0],
		[-88.0, -55.0, 4, 0.0],   # scaffolding
		[88.0, 55.0, 4, 180.0],
		[55.0, 88.0, 4, 90.0],
		[-55.0, -88.0, 4, -90.0],
		[-13.0, 77.0, 5, 0.0],    # barrier
		[13.0, -77.0, 5, 180.0],
		[77.0, 13.0, 5, 90.0],
		[-77.0, -13.0, 5, -90.0],
		[-11.0, -22.0, 6, 0.0],   # fire hydrant
		[11.0, 44.0, 6, 180.0],
		[-33.0, 11.0, 6, 90.0],
		[33.0, -55.0, 6, -90.0],
		[-11.0, 55.0, 7, 0.0],    # utility box
		[55.0, -11.0, 7, 90.0],
		[-55.0, 22.0, 7, -90.0],
		[12.0, -33.0, 8, 90.0],   # news stand
		[-66.0, -11.0, 8, -90.0],
		[11.0, 11.0, 9, 0.0],     # newspaper box
		[-12.0, -55.0, 9, 180.0],
		[44.0, 22.0, 9, 90.0],
		[-15.0, 22.0, 10, -90.0], # stop sign
		[15.0, -44.0, 10, 90.0],
		[-44.0, -11.0, 10, 0.0],
		[44.0, 33.0, 11, 90.0],   # speed sign
		[-33.0, 55.0, 11, -90.0],
		[33.0, -77.0, 11, 0.0],
		[-9.0, -77.0, 12, 0.0],   # traffic cone
		[9.0, 77.0, 12, 0.0],
		[77.0, -9.0, 12, 0.0],
		[-77.0, 9.0, 12, 0.0],
	]
	for pp in prop_positions:
		var pos := Vector3(pp[0], 0.0, pp[1])
		var ptype: int = int(pp[2])
		var rot: float = float(pp[3])
		match ptype:
			0:
				_add_traffic_light(parent, pos, rot)
			1:
				_add_bench(parent, pos, rot)
			2:
				_add_trash_bin(parent, pos, rot)
			3:
				_add_planter(parent, pos, rot)
			4:
				_add_scaffolding(parent, pos, rot)
			5:
				_add_barrier(parent, pos, rot)
			6:
				_add_fire_hydrant(parent, pos, rot)
			7:
				_add_utility_box(parent, pos, rot)
			8:
				_add_news_stand(parent, pos, rot)
			9:
				_add_newspaper_box(parent, pos, rot)
			10:
				_add_road_sign(parent, pos, rot, false)
			11:
				_add_road_sign(parent, pos, rot, true)
			12:
				_add_traffic_cone(parent, pos, rot)
	_add_parked_cars(parent)
	_add_bollard_line(parent)

func _add_traffic_light(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/traffic_light.glb", "y", 6.0, true)
	if holder == null:
		_add_traffic_light_primitive(parent, pos, rot)
		return
	holder.name = "TrafficLight_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	var glow := OmniLight3D.new()
	glow.name = "TLGlow"
	glow.position = Vector3(0, 4.2, 0)
	glow.light_color = Color(0.1, 0.9, 0.2, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 5.0
	holder.add_child(glow)

func _add_traffic_light_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "TrafficLight_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var pole_mat := _mat(Color(0.05, 0.08, 0.1, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	_add_box(prop, "TLPole", Vector3(0.18, 5.0, 0.18), Vector3(0, 2.5, 0), pole_mat)
	_add_box(prop, "TLArm", Vector3(2.2, 0.14, 0.14), Vector3(1.1, 4.8, 0), pole_mat)
	# Signal head with 3 lenses
	var head_mat := _mat(Color(0.04, 0.06, 0.08, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	_add_box(prop, "TLHead", Vector3(0.6, 1.2, 0.35), Vector3(2.2, 4.3, 0), head_mat)
	# Red (top) — dim
	var red_mat := _mat(Color(0.5, 0.05, 0.05, 1.0), Color(0.8, 0.1, 0.1, 1.0), 0.4)
	_add_box(prop, "TLRed", Vector3(0.35, 0.3, 0.05), Vector3(2.2, 4.65, 0.18), red_mat)
	# Yellow (middle) — brighter
	var yellow_mat := _mat(Color(0.5, 0.4, 0.05, 1.0), Color(0.9, 0.7, 0.1, 1.0), 0.6)
	_add_box(prop, "TLYellow", Vector3(0.35, 0.3, 0.05), Vector3(2.2, 4.3, 0.18), yellow_mat)
	# Green (bottom) — brightest, active signal
	var green_mat := _mat(Color(0.05, 0.5, 0.1, 1.0), Color(0.1, 0.9, 0.2, 1.0), 0.8)
	_add_box(prop, "TLGreen", Vector3(0.35, 0.3, 0.05), Vector3(2.2, 3.95, 0.18), green_mat)
	var glow := OmniLight3D.new()
	glow.name = "TLGlow"
	glow.position = Vector3(2.2, 3.95, 0.3)
	glow.light_color = Color(0.1, 0.9, 0.2, 1.0)
	glow.light_energy = 1.0
	glow.omni_range = 5.0
	prop.add_child(glow)

func _add_bench(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/bench_park.glb", "y", 0.95, true)
	if holder == null:
		_add_bench_primitive(parent, pos, rot)
		return
	holder.name = "Bench_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_bench_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "Bench_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var bench_mat := _mat(Color(0.15, 0.1, 0.08, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	# Seat slab
	_add_box(prop, "BenchSeat", Vector3(2.0, 0.12, 0.6), Vector3(0, 0.5, 0), bench_mat)
	# Backrest
	_add_box(prop, "BenchBack", Vector3(2.0, 0.6, 0.1), Vector3(0, 0.8, -0.25), bench_mat)
	# Legs
	_add_box(prop, "BenchLegL", Vector3(0.1, 0.5, 0.5), Vector3(-0.85, 0.25, 0), bench_mat)
	_add_box(prop, "BenchLegR", Vector3(0.1, 0.5, 0.5), Vector3(0.85, 0.25, 0), bench_mat)
	# Subtle amber accent strip on seat front
	var accent := _mat(Color(0.2, 0.15, 0.1, 1.0), Color(0.6, 0.4, 0.15, 1.0), 0.25)
	_add_box(prop, "BenchAccent", Vector3(2.0, 0.03, 0.04), Vector3(0, 0.56, 0.3), accent)

func _add_trash_bin(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/trash_bin.glb", "y", 1.1, true)
	if holder == null:
		_add_trash_bin_primitive(parent, pos, rot)
		return
	holder.name = "TrashBin_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_trash_bin_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "TrashBin_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var bin_mat := _mat(Color(0.08, 0.12, 0.1, 1.0), Color(0.0, 0.15, 0.2, 1.0), 0.1)
	var body := MeshInstance3D.new()
	body.name = "TrashBinBody"
	var b_mesh := CylinderMesh.new()
	b_mesh.top_radius = 0.45
	b_mesh.bottom_radius = 0.4
	b_mesh.height = 1.1
	body.mesh = b_mesh
	body.position = Vector3(0, 0.55, 0)
	body.material_override = bin_mat
	prop.add_child(body)
	# Lid
	var lid := MeshInstance3D.new()
	lid.name = "TrashBinLid"
	var l_mesh := CylinderMesh.new()
	l_mesh.top_radius = 0.48
	l_mesh.bottom_radius = 0.48
	l_mesh.height = 0.15
	lid.mesh = l_mesh
	lid.position = Vector3(0, 1.18, 0)
	lid.material_override = bin_mat
	prop.add_child(lid)
	# Cyan rim
	var rim := _mat(Color(0.25, 0.9, 1.0, 1.0), Color(0.2, 0.8, 1.0, 1.0), 0.5)
	_add_box(prop, "TrashBinRim", Vector3(0.96, 0.04, 0.08), Vector3(0, 1.1, 0.46), rim)

func _add_planter(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/planter.glb", "y", 0.7, true)
	if holder == null:
		_add_planter_primitive(parent, pos, rot)
		return
	holder.name = "Planter_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	var glow := OmniLight3D.new()
	glow.name = "PlanterGlow"
	glow.position = Vector3(0, 0.6, 0)
	glow.light_color = Color(0.1, 0.5, 0.2, 1.0)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	holder.add_child(glow)

func _add_planter_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "Planter_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var box_mat := _mat(Color(0.12, 0.1, 0.08, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
	# Planter box
	_add_box(prop, "PlanterBox", Vector3(1.2, 0.5, 0.8), Vector3(0, 0.25, 0), box_mat)
	# Soil/plant mass
	var plant_mat := _mat(Color(0.05, 0.3, 0.12, 1.0), Color(0.1, 0.5, 0.2, 1.0), 0.3)
	var plant := MeshInstance3D.new()
	plant.name = "PlanterFoliage"
	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.7
	p_mesh.height = 0.8
	plant.mesh = p_mesh
	plant.position = Vector3(0, 0.7, 0)
	plant.material_override = plant_mat
	prop.add_child(plant)
	# Small glow
	var glow := OmniLight3D.new()
	glow.name = "PlanterGlow"
	glow.position = Vector3(0, 0.7, 0)
	glow.light_color = Color(0.1, 0.5, 0.2, 1.0)
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	prop.add_child(glow)

func _add_scaffolding(parent: Node3D, pos: Vector3, rot: float) -> void:
	# The source scaffold bay is a wide, short horizontal section; rotate it upright
	# (roll 90°) so it reads as a tall multi-level construction frame on the street.
	var holder := _instance_prop(PROP_DIR + "street/scaffolding.glb", "y", 6.0, true, Vector3(0, 0, 90))
	if holder == null:
		_add_scaffolding_primitive(parent, pos, rot)
		return
	holder.name = "Scaffolding_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	var warn := OmniLight3D.new()
	warn.name = "ScaffoldWarnLight"
	warn.position = Vector3(0, 6.0, 0)
	warn.light_color = Color(0.9, 0.2, 0.1, 1.0)
	warn.light_energy = 0.8
	warn.omni_range = 4.0
	holder.add_child(warn)

func _add_scaffolding_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "Scaffolding_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var frame_mat := _mat(Color(0.12, 0.12, 0.14, 1.0), Color(0.3, 0.3, 0.35, 1.0), 0.15)
	# 4 vertical posts
	for sx in [-1.5, 1.5]:
		for sz in [-1.0, 1.0]:
			_add_box(prop, "Post_%d_%d" % [int(sx), int(sz)], Vector3(0.12, 6.0, 0.12), Vector3(sx, 3.0, sz), frame_mat)
	# Horizontal cross-braces at 3 levels
	for y in [1.5, 3.5, 5.5]:
		_add_box(prop, "CrossX_%d" % int(y), Vector3(3.2, 0.08, 0.08), Vector3(0, y, -1.0), frame_mat)
		_add_box(prop, "CrossX2_%d" % int(y), Vector3(3.2, 0.08, 0.08), Vector3(0, y, 1.0), frame_mat)
		_add_box(prop, "CrossZ_%d" % int(y), Vector3(0.08, 0.08, 2.2), Vector3(-1.5, y, 0), frame_mat)
		_add_box(prop, "CrossZ2_%d" % int(y), Vector3(0.08, 0.08, 2.2), Vector3(1.5, y, 0), frame_mat)
	# Diagonal brace
	_add_box(prop, "DiagBrace", Vector3(0.06, 6.2, 0.06), Vector3(-1.5, 3.0, 0), frame_mat)
	var diag := prop.get_node_or_null("DiagBrace") as MeshInstance3D
	if diag != null:
		diag.rotation_degrees = Vector3(0, 0, 15)
	# Warning light on top
	var warn := OmniLight3D.new()
	warn.name = "ScaffoldWarnLight"
	warn.position = Vector3(0, 6.2, 0)
	warn.light_color = Color(0.9, 0.2, 0.1, 1.0)
	warn.light_energy = 0.8
	warn.omni_range = 4.0
	prop.add_child(warn)

func _add_barrier(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/barrier.glb", "z", 2.0, true)
	if holder == null:
		_add_barrier_primitive(parent, pos, rot)
		return
	holder.name = "Barrier_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_barrier_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var prop := Node3D.new()
	prop.name = "Barrier_%d_%d" % [int(pos.x), int(pos.z)]
	prop.position = pos
	prop.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(prop)
	var bar_mat := _mat(Color(0.15, 0.15, 0.08, 1.0), Color(0.6, 0.45, 0.1, 1.0), 0.2)
	# Base
	_add_box(prop, "BarrierBase", Vector3(2.0, 0.08, 0.4), Vector3(0, 0.06, 0), bar_mat)
	# Vertical posts
	for sx in [-0.8, 0.8]:
		_add_box(prop, "BarrierPost_%d" % int(sx), Vector3(0.1, 0.8, 0.1), Vector3(sx, 0.5, 0), bar_mat)
	# Top rail
	_add_box(prop, "BarrierRail", Vector3(2.0, 0.08, 0.08), Vector3(0, 0.9, 0), bar_mat)
	# Hazard stripes — alternating dark/yellow via 4 small boxes
	for i in range(4):
		var stripe_mat := _mat(Color(0.5, 0.4, 0.05, 1.0), Color(0.8, 0.65, 0.1, 1.0), 0.3) if i % 2 == 0 else _mat(Color(0.04, 0.04, 0.02, 1.0), Color(0.0, 0.0, 0.0, 1.0), 0.0)
		_add_box(prop, "BarrierStripe_%d" % i, Vector3(0.45, 0.25, 0.03), Vector3(-0.7 + float(i) * 0.45, 0.45, 0.18), stripe_mat)

# ── New real-model city props (no prior primitive; fall back to a tinted box) ──

func _add_prop_fallback_box(parent: Node3D, prop_name: String, pos: Vector3, rot: float, size: Vector3, emission: Color) -> void:
	var holder := Node3D.new()
	holder.name = prop_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	_add_box(holder, "Body", size, Vector3(0, size.y * 0.5, 0), _mat(emission * 0.4, emission, 0.3))

func _add_fire_hydrant(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/fire_hydrant.glb", "y", 1.0, true)
	if holder == null:
		_add_prop_fallback_box(parent, "FireHydrant_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(0.4, 0.9, 0.4), Color(0.8, 0.15, 0.1))
		return
	holder.name = "FireHydrant_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_utility_box(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/utility_box.glb", "y", 1.3, true)
	if holder == null:
		_add_prop_fallback_box(parent, "UtilityBox_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(0.6, 1.3, 0.4), Color(0.2, 0.5, 0.4))
		return
	holder.name = "UtilityBox_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	var glow := OmniLight3D.new()
	glow.name = "UtilityGlow"
	glow.position = Vector3(0, 1.4, 0)
	glow.light_color = Color(0.2, 0.8, 1.0, 1.0)
	glow.light_energy = 0.5
	glow.omni_range = 3.0
	holder.add_child(glow)

func _add_news_stand(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/news_stand.glb", "y", 2.6, true)
	if holder == null:
		_add_prop_fallback_box(parent, "NewsStand_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(2.4, 2.6, 1.6), Color(0.6, 0.4, 0.15))
		return
	holder.name = "NewsStand_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	var glow := OmniLight3D.new()
	glow.name = "NewsStandGlow"
	glow.position = Vector3(0, 2.4, 0)
	glow.light_color = Color(1.0, 0.8, 0.4, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 5.0
	holder.add_child(glow)

func _add_newspaper_box(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/newspaper_box.glb", "y", 1.5, true)
	if holder == null:
		_add_prop_fallback_box(parent, "NewspaperBox_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(0.7, 1.5, 0.6), Color(0.2, 0.6, 0.9))
		return
	holder.name = "NewspaperBox_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_road_sign(parent: Node3D, pos: Vector3, rot: float, is_speed: bool) -> void:
	var path := PROP_DIR + ("street/road_sign_speed.glb" if is_speed else "street/road_sign_stop.glb")
	var target := 2.8 if is_speed else 2.6
	var holder := _instance_prop(path, "y", target, true)
	if holder == null:
		var col := Color(0.7, 0.7, 0.2) if is_speed else Color(0.8, 0.1, 0.1)
		_add_prop_fallback_box(parent, "RoadSign_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(0.1, target, 0.7), col)
		return
	holder.name = "RoadSign_%s_%d_%d" % [("Speed" if is_speed else "Stop"), int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_traffic_cone(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/traffic_cone.glb", "y", 0.7, true)
	if holder == null:
		_add_prop_fallback_box(parent, "TrafficCone_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(0.4, 0.7, 0.4), Color(0.9, 0.4, 0.05))
		return
	holder.name = "TrafficCone_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

func _add_bollard(parent: Node3D, prop_name: String, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/bollard.glb", "y", 1.0)
	if holder == null:
		_add_prop_fallback_box(parent, prop_name, pos, rot, Vector3(0.22, 1.0, 0.22), Color(0.2, 0.7, 0.9))
		return
	holder.name = prop_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

# Bollards frame the open ground around the central plaza, marking the sidewalk
# edge. Spaced evenly along the plaza perimeter corridors (clear of crosswalks).
func _add_bollard_line(parent: Node3D) -> void:
	for n in range(-10, 11, 4):
		for side in [-12.0, 12.0]:
			_add_bollard(parent, "Bollard_X_%d_%d" % [n, int(side)], Vector3(float(n), 0.0, side), 0.0)
			_add_bollard(parent, "Bollard_Z_%d_%d" % [n, int(side)], Vector3(side, 0.0, float(n)), 0.0)

const CAR_VARIANTS := [
	"vehicles/car_sedan.glb",
	"vehicles/car_suv.glb",
	"vehicles/car_hatchback.glb",
]

func _add_car(parent: Node3D, car_name: String, pos: Vector3, rot: float, variant: int) -> void:
	# Fit by length (Z) so the chunky low-poly cars read at a believable street scale.
	var holder := _instance_prop(PROP_DIR + CAR_VARIANTS[variant], "z", 4.4, true)
	if holder == null:
		_add_prop_fallback_box(parent, car_name, pos, rot, Vector3(1.6, 1.2, 4.0), Color(0.3, 0.4, 0.6))
		return
	holder.name = car_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

# Parked cars line the open mid-block corridors (the genuinely clear lanes at the
# ±11 half-gridlines, where the streetlights and trees already sit). Cars alternate
# kerb side and cycle through the 3 colour/shape variants so no two neighbours match.
func _add_parked_cars(parent: Node3D) -> void:
	var idx := 0
	for i in [-4, -2, 2, 4]:
		var avenue := float(i) * 22.0
		# North–south corridors at x = ±11 → cars aligned with Z (rot 0).
		for kerb in [-11.0, 11.0]:
			for off in [-7.0, 7.0]:
				var z: float = avenue + off
				if abs(kerb) < 4.5 and abs(z) < 4.5:
					continue
				_add_car(parent, "ParkedCar_NS_%d" % idx, Vector3(kerb, 0.0, z), 0.0, idx % CAR_VARIANTS.size())
				idx += 1
		# East–west corridors at z = ±11 → cars aligned with X (rot 90).
		for kerb in [-11.0, 11.0]:
			for off in [-7.0, 7.0]:
				var x: float = avenue + off
				if abs(x) < 4.5 and abs(kerb) < 4.5:
					continue
				_add_car(parent, "ParkedCar_EW_%d" % idx, Vector3(x, 0.0, kerb), 90.0, idx % CAR_VARIANTS.size())
				idx += 1
