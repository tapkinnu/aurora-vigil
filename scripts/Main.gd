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
	{"roughness": 0.35, "metallic": 0.35, "emission_energy": 0.05},
	{"roughness": 0.88, "metallic": 0.02, "emission_energy": 0.03},
	{"roughness": 0.80, "metallic": 0.04, "emission_energy": 0.04},
	{"roughness": 0.42, "metallic": 0.45, "emission_energy": 0.04},
	{"roughness": 0.48, "metallic": 0.35, "emission_energy": 0.06},
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
var _routed_traffic: Array[Dictionary] = []

# Real CC0/CC-BY low-poly street/vegetation/vehicle models live under PROP_DIR
# (see assets/3d/props/SOURCES.md for sources + licenses). _load_prop loads and
# caches the PackedScenes; every _add_* prop builder instances the real model and
# falls back to a primitive build if its GLB is missing or fails to import.
const PROP_DIR := "res://assets/3d/props/"
const CITY_KIT_BUILDING_DIR := "res://assets/3d/kenney_city/commercial/"
const CITY_KIT_ROAD_DIR := "res://assets/3d/kenney_city/roads/"
const CITY_KIT_SKYSCRAPER_VARIANTS := [
	"building-skyscraper-a.glb",
	"building-skyscraper-b.glb",
	"building-skyscraper-c.glb",
	"building-skyscraper-d.glb",
	"building-skyscraper-e.glb",
]
const CITY_KIT_MIDRISE_VARIANTS := [
	"building-a.glb", "building-b.glb", "building-c.glb", "building-d.glb",
	"building-e.glb", "building-f.glb", "building-g.glb", "building-h.glb",
	"building-i.glb", "building-j.glb", "building-k.glb", "building-l.glb",
	"building-m.glb", "building-n.glb",
]
const CITY_KIT_LOW_DETAIL_VARIANTS := [
	"low-detail-building-a.glb", "low-detail-building-b.glb", "low-detail-building-c.glb",
	"low-detail-building-d.glb", "low-detail-building-e.glb", "low-detail-building-f.glb",
	"low-detail-building-g.glb", "low-detail-building-h.glb", "low-detail-building-i.glb",
	"low-detail-building-j.glb", "low-detail-building-k.glb", "low-detail-building-l.glb",
	"low-detail-building-m.glb", "low-detail-building-n.glb", "low-detail-building-wide-a.glb",
	"low-detail-building-wide-b.glb",
]
# Kenney Starter Kit City Builder — compact 1x1-unit tile GLBs (CC0). Capture-only;
# used to lay grid-based plazas/parks/side streets and low-rise blocks so the city
# postcard reads like an actual city-builder layout instead of flat hand-placed slabs.
const CITY_BUILDER_DIR := "res://assets/3d/kenney_city_builder/"
const CITY_BUILDER_GRASS_VARIANTS := [
	"grass.glb", "grass-trees.glb", "grass-trees-tall.glb",
]
const CITY_BUILDER_LOWRISE_VARIANTS := [
	"building-small-a.glb", "building-small-b.glb", "building-small-c.glb",
	"building-small-d.glb", "building-garage.glb",
]
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
	flight.setup(self, hero, camera, progression)
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
	# Dry asphalt PBR for the city ground plane — high roughness, no metallic, no
	# emission, so it reads as real road tar in daylight, not a wet neon mirror.
	var mat := StandardMaterial3D.new()
	if not _ground_albedo_textures.is_empty():
		mat.albedo_texture = _ground_albedo_textures[0]
		if not _ground_normal_textures.is_empty() and _ground_normal_textures[0] != null:
			mat.normal_enabled = true
			mat.normal_texture = _ground_normal_textures[0]
		if not _ground_roughness_textures.is_empty() and _ground_roughness_textures[0] != null:
			mat.roughness_texture = _ground_roughness_textures[0]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.albedo_color = Color(0.30, 0.30, 0.31, 1.0)
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
	return mat

func _ground_grass_material() -> StandardMaterial3D:
	# Grass PBR for park zones — high roughness, no metallic, no emission; lit
	# entirely by the daytime sun and sky so parks read as ordinary green space.
	var mat := StandardMaterial3D.new()
	var idx := 1  # GROUND_TEXTURE_DIRS index 1 = grass
	if _ground_albedo_textures.size() > idx:
		mat.albedo_texture = _ground_albedo_textures[idx]
		if _ground_normal_textures.size() > idx and _ground_normal_textures[idx] != null:
			mat.normal_enabled = true
			mat.normal_texture = _ground_normal_textures[idx]
		if _ground_roughness_textures.size() > idx and _ground_roughness_textures[idx] != null:
			mat.roughness_texture = _ground_roughness_textures[idx]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	return mat

func _ground_plaza_material() -> StandardMaterial3D:
	# Concrete-pavement PBR for plazas and sidewalks — dry, fairly rough, no
	# emission. Reads as poured/cast concrete slabs in daylight.
	var mat := StandardMaterial3D.new()
	var idx := 2  # GROUND_TEXTURE_DIRS index 2 = plaza
	if _ground_albedo_textures.size() > idx:
		mat.albedo_texture = _ground_albedo_textures[idx]
		if _ground_normal_textures.size() > idx and _ground_normal_textures[idx] != null:
			mat.normal_enabled = true
			mat.normal_texture = _ground_normal_textures[idx]
		if _ground_roughness_textures.size() > idx and _ground_roughness_textures[idx] != null:
			mat.roughness_texture = _ground_roughness_textures[idx]
			mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.albedo_color = Color(0.48, 0.47, 0.45, 1.0)
	mat.roughness = 0.8
	mat.metallic = 0.0
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
	_update_routed_traffic(delta)
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
	# Golden-hour sky via ProceduralSkyMaterial — a deep saturated blue zenith
	# rolling down to a warm amber horizon, the way a metropolis reads when the
	# sun is low and raking the glass towers. No magenta band, no night plate;
	# the warm low sun is the dominant light, the cool blue sky fills the shadows.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky_resource := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.075, 0.235, 0.60, 1.0)
	sky_mat.sky_horizon_color = Color(0.62, 0.72, 0.86, 1.0)
	sky_mat.sky_curve = 0.28
	sky_mat.sky_energy_multiplier = 1.22
	sky_mat.ground_horizon_color = Color(0.78, 0.60, 0.43, 1.0)
	sky_mat.ground_bottom_color = Color(0.30, 0.28, 0.30, 1.0)
	sky_mat.ground_curve = 0.08
	# A larger, warmer sun disk sitting low over the skyline. The wide glow blends
	# into the amber horizon and, with the subtle bloom below, gives the sun-disc /
	# soft-flare read the reference frames at golden hour.
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.06
	sky_resource.sky_material = sky_mat
	e.sky = sky_resource
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Slightly lower sky ambient so the cool fill stays subordinate to the warm key
	# and shadows keep their blue cast instead of washing flat.
	e.ambient_light_energy = 0.68
	# Warm aerial haze: distant towers fade into a golden horizon murk rather than a
	# neutral grey. Low density keeps the streets crisp; aerial perspective fades
	# only the far skyline into the warm sky.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.00085
	e.fog_light_color = Color(0.74, 0.58, 0.44, 1.0)
	e.fog_light_energy = 1.0
	e.fog_sky_affect = 0.18
	e.fog_aerial_perspective = 0.42
	# A gentle warm ground-level haze; nothing pools thickly enough to read as murk.
	e.fog_height = 22.0
	e.fog_height_density = 0.009
	# No coloured volumetric fog — the flat distance fog carries the golden depth.
	e.volumetric_fog_enabled = false
	# Subtle bloom for the sun disc and the bright warm highlights skating off glass
	# towers only — the HDR threshold sits above 1.0 so lit windows and road paint do
	# not halo. This is grounded golden-hour glint, not a cyberpunk neon bloom.
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_strength = 1.0
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.25
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# glow_levels/1..7 are individual properties, not an array/dict.
	e.set("glow_levels/1", 0.0)
	e.set("glow_levels/2", 0.0)
	e.set("glow_levels/3", 0.4)
	e.set("glow_levels/4", 0.8)
	e.set("glow_levels/5", 0.8)
	e.set("glow_levels/6", 0.5)
	e.set("glow_levels/7", 0.3)
	# Dry daytime streets: disable SSR so asphalt/concrete do not look like a wet
	# reflective sci-fi floor.
	e.ssr_enabled = false
	e.ssr_max_steps = 32
	e.ssr_fade_in = 0.6
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.18
	# SSAO brings the avenues + skyline crevices some depth.
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 1.4
	e.ssao_power = 1.4
	# ACES tonemap — rolls the bright golden highlights off smoothly and keeps the
	# warm sun glint from clipping to white. Slightly lower exposure deepens the blue
	# sky and the long shadows for the cinematic golden-hour contrast.
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.9
	e.tonemap_white = 12.0
	# A gentle warm grade: lift the warm channels a touch and let the cool shadows
	# read blue, the teal/orange split the reference leans on.
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.12
	env.environment = e
	# Camera attributes drive exposure under Forward+ (auto-exposure moved off
	# Environment to CameraAttributesPractical in Godot 4). Auto-exposure is left
	# OFF deliberately: this is a fixed-time-of-day daylight city, so the exposure
	# stays at the hand-tuned value rather than drifting per frame. The node is
	# kept (with a sane sensitivity band) so a future day/night cycle can flip
	# auto_exposure_enabled on and tune it.
	var cam_attrs := CameraAttributesPractical.new()
	cam_attrs.auto_exposure_enabled = false
	cam_attrs.auto_exposure_scale = 0.4
	cam_attrs.auto_exposure_speed = 0.5
	cam_attrs.auto_exposure_min_sensitivity = 40.0
	cam_attrs.auto_exposure_max_sensitivity = 90.0
	env.camera_attributes = cam_attrs
	add_child(env)

	# Primary golden-hour key — a low, warm orange sun that rakes the avenues from
	# just above the horizon, throwing long dramatic shadows and lighting the
	# west-facing tower glass with a warm glint. This is the dominant light.
	var sun := DirectionalLight3D.new()
	sun.name = "GoldenHourSun"
	# Low elevation (~16° above horizon) and a wide azimuth so shadows stretch long
	# across the avenues and the highway deck. The azimuth places the sun off toward
	# the skyline so towers in the city shot are warm-faced, not flat-lit.
	sun.rotation_degrees = Vector3(-16, 62, 0)
	sun.light_color = Color(1.0, 0.74, 0.46, 1.0)
	sun.light_energy = 2.05
	# A warm-tinted indirect specular keeps the cool sky reflection from going grey.
	sun.light_specular = 0.9
	# Forward+ directional shadows — cast long warm-hour tower shadows down the avenues.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 350.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 1.5
	sun.shadow_bias = 0.08
	# Contact shadows close the gap between an object and its cast shadow so
	# props sitting on the pavement read as grounded (Forward+ only).
	sun.set("shadow/contact_shadows", true)
	sun.set("shadow/contact_shadows_size", 0.05)
	# 4096px directional shadow atlas for sharp building-edge shadows.
	get_viewport().set("positional_shadow_atlas_size", 4096)
	add_child(sun)
	# DirectionalLight3D shadow resolution is a project/render setting rather
	# than a per-light property; raise it for the sharp split shadows.
	RenderingServer.directional_shadow_atlas_set_size(4096, true)

	# VoxelGI — real-time indirect bounce in the street canyons and under
	# overhangs. Forward+ only; no bake needed when used dynamically.
	var gi := VoxelGI.new()
	gi.name = "CityVoxelGI"
	gi.subdiv = VoxelGI.SUBDIV_128
	gi.size = Vector3(400, 100, 400)
	gi.position = Vector3(0, 40, 0)
	add_child(gi)

	# ReflectionProbe — subtle daylight reflections for glass windows/metal only.
	var ref_probe := ReflectionProbe.new()
	ref_probe.name = "CityReflectionProbe"
	ref_probe.size = Vector3(400, 100, 400)
	ref_probe.position = Vector3(0, 20, 0)
	ref_probe.intensity = 1.0
	ref_probe.max_distance = 500.0
	ref_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(ref_probe)

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
	var capture_city := OS.get_environment("AURORA_CAPTURE_MODE") == "city"
	for x in range(-5, 5):
		for z in range(-5, 5):
			# The city postcard now uses a curated Los-Santos-style skyline cluster and
			# freeway foreground. Do not spawn the normal gameplay towers in this one
			# capture mode: the extra towers compete with the staged freeway/skyline and
			# can read as blockers in the road view. Gameplay and the other screenshot
			# modes still use the full dense city grid.
			if capture_city:
				continue
			if abs(x) <= 1 and abs(z) <= 1:
				continue
			if (x + z) % 3 == 0:
				continue
			var is_collector: bool = (x == -5 or x == 4) and (z == -5 or z == 4)
			# Vary footprints far more than the old 8.5-11.5 band so the lot sizes
			# read as irregular rather than a uniform stamp.
			var width: float = 6.6 + float((abs(x * 7 + z * 11) % 4))
			var depth: float = 6.6 + float((abs(x * 13 + z * 5) % 4))
			if is_collector:
				width = 10.0
				depth = 10.0
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
			# Road centers are at multiples of 22. Tower centers must live in the lots
			# halfway between those roads; the previous x*22/z*22 placement put tower
			# footprints directly on avenue centerlines. Keep only small bounded jitter so
			# large footprints never drift back into the asphalt/curb/sidewalk strips.
			var lot_x := float(x) * 22.0 + 11.0
			var lot_z := float(z) * 22.0 + 11.0
			var jx: float = 0.0
			var jz: float = 0.0
			if not is_collector:
				var max_jx: float = maxf(0.0, 11.0 - 5.9 - width * 0.5)
				var max_jz: float = maxf(0.0, 11.0 - 5.9 - depth * 0.5)
				jx = clampf(float((abs(x * 19 + z * 7) % 7) - 3) * 0.8, -max_jx, max_jx)
				jz = clampf(float((abs(x * 11 + z * 23) % 7) - 3) * 0.8, -max_jz, max_jz)
			tower_body.position = Vector3(lot_x + jx, 0.0, lot_z + jz)
			district.add_child(tower_body)
			var facade_mat := _city_facade_material(h, x, z, width, depth, is_collector)
			var top_info: Dictionary = _build_composite_tower(tower_body, form_type, width, depth, h, facade_mat)
			var top_y: float = float(top_info["top_y"])
			var top_w: float = float(top_info["top_w"])
			var top_d: float = float(top_info["top_d"])
			_add_vertical_ribs(tower_body, top_w, top_d, top_y, is_collector)
			_add_cornice(tower_body, top_w, top_d, top_y)
			_add_roof_detail(tower_body, top_w, top_d, top_y, x, z, is_collector)
			# Tiny red aviation lamps only on the tallest towers, as on real
			# high-rises — not a glowing beacon on every other roof.
			if is_collector or h > 54.0:
				_add_rooftop_beacon(tower_body, Vector3(0, top_y + 3.8, 0), is_collector)
	if not capture_city:
		_add_city_avenues(district)
		_add_park_zones(district)
		_add_plaza_paving(district)
		_add_sidewalks(district)
		_add_diagonal_streets(district)
		_add_curved_avenues(district)
		_add_irregular_plazas(district)
		_add_parking_lots(district)
	if capture_city:
		_add_city_kit_distant_skyline(district)
	else:
		_add_distant_skyline(district)
	_add_haze_layers(district)
	if not capture_city:
		_add_highway_interchange(district)
		_add_hero_tower(district)
		_add_landmark_grid_tower(district)
		_add_construction_crane(district, Vector3(92.0, 0.0, 36.0), -28.0, 86.0)
		_add_construction_crane(district, Vector3(-58.0, 0.0, 104.0), 140.0, 70.0)
		_add_construction_crane(district, Vector3(-86.0, 0.0, -118.0), 24.0, 58.0)
		_add_boulevard_palms(district)
		_add_street_props(district)
	# Cinematic city-capture dressing: a dominant foreground freeway, a cluster of
	# distinctive downtown landmark towers, and a subtle sun flare — staged only for
	# the deterministic "city" postcard capture so gameplay/flight stays unchanged.
	if capture_city:
		_add_reference_capture_scene(district)

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
	# Real road network: dark asphalt carriageways, poured-concrete curbs, and worn
	# white/yellow lane paint — all non-emissive, lit only by the daytime sun. No
	# glowing lines: the streets read as tarmac, not a neon lattice.
	var road_mat := _matte(Color(0.060, 0.060, 0.065, 1.0), 0.95)
	var lane_mat := _matte(Color(0.24, 0.235, 0.215, 1.0), 0.82)     # very worn dirty-white lane paint
	var center_mat := _matte(Color(0.32, 0.27, 0.08, 1.0), 0.82)     # faded double-yellow centre line
	var curb_mat := _matte(Color(0.24, 0.235, 0.225, 1.0), 0.88)     # aged concrete curb
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
		# Extremely sparse, muted lane paint. From aerial/gameplay cameras bright
		# repeated dashes read like a digital grid, so only the main central avenues
		# retain worn road markings.
		if i != 0:
			continue
		var seg := 12.0
		var n := int(132.0 / seg)
		for m in range(-n, n + 1):
			var t := float(m) * seg
			# Leave a gap through the 6 m intersection boxes so paint doesn't cross them.
			if absi(int(round(t)) % 22) <= 4:
				continue
			# East–west carriageway at z = i*22 (paint runs along X).
			_add_box(parent, "CtrEW_%d_%d" % [i, m], Vector3(seg * 0.22, 0.025, 0.07), Vector3(t, 0.205, i * 22.0), center_mat)
			if i == 0 and m % 3 == 0:
				_add_box(parent, "LnEWa_%d_%d" % [i, m], Vector3(seg * 0.18, 0.02, 0.045), Vector3(t, 0.2, i * 22.0 + 1.9), lane_mat)
				_add_box(parent, "LnEWb_%d_%d" % [i, m], Vector3(seg * 0.18, 0.02, 0.045), Vector3(t, 0.2, i * 22.0 - 1.9), lane_mat)
			# North–south carriageway at x = i*22 (paint runs along Z).
			_add_box(parent, "CtrNS_%d_%d" % [i, m], Vector3(0.07, 0.025, seg * 0.22), Vector3(i * 22.0, 0.205, t), center_mat)
			if i == 0 and m % 3 == 0:
				_add_box(parent, "LnNSa_%d_%d" % [i, m], Vector3(0.045, 0.02, seg * 0.18), Vector3(i * 22.0 + 1.9, 0.2, t), lane_mat)
				_add_box(parent, "LnNSb_%d_%d" % [i, m], Vector3(0.045, 0.02, seg * 0.18), Vector3(i * 22.0 - 1.9, 0.2, t), lane_mat)
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
	_add_road_surface_details(parent)

func _add_road_surface_details(parent: Node3D) -> void:
	# Cast-iron manhole covers, kerbside storm drains and a few asphalt patch
	# repairs scattered over the central carriageways. Small, dark, non-emissive
	# details that break up the flat tarmac and sell it as a real, worn street.
	var iron := _matte(Color(0.13, 0.13, 0.135, 1.0), 0.78, 0.25)
	var grate := _matte(Color(0.1, 0.1, 0.11, 1.0), 0.8, 0.2)
	var patch := _matte(Color(0.055, 0.055, 0.06, 1.0), 0.95)
	for i in range(-4, 5):
		for j in range(-4, 5):
			var hsh := absi(i * 73 + j * 31)
			if hsh % 3 == 0:
				continue
			var bx := float(i) * 22.0 + float((hsh % 5) - 2) * 1.6
			var bz := float(j) * 22.0 + float((hsh / 5 % 5) - 2) * 1.6
			if abs(bx) < 5.0 and abs(bz) < 5.0:
				continue
			if hsh % 5 == 0:
				# Rectangular asphalt patch repair (slightly darker, fresher tar).
				var pw := 2.0 + float(hsh % 3)
				_add_box(parent, "RoadPatch_%d_%d" % [i, j], Vector3(pw, 0.02, pw * 0.7), Vector3(bx, 0.175, bz), patch)
			else:
				var cover := MeshInstance3D.new()
				cover.name = "Manhole_%d_%d" % [i, j]
				var cm := CylinderMesh.new()
				cm.top_radius = 0.42
				cm.bottom_radius = 0.42
				cm.height = 0.04
				cover.mesh = cm
				cover.position = Vector3(bx, 0.18, bz)
				cover.material_override = iron
				parent.add_child(cover)
	# Storm drains tucked against the kerb on the central avenues.
	for k in [-2, -1, 1, 2]:
		var z := float(k) * 22.0 - 3.4
		_add_box(parent, "Drain_%d" % k, Vector3(1.1, 0.05, 0.4), Vector3(float(k) * 4.0, 0.185, z), grate)
		_add_box(parent, "DrainX_%d" % k, Vector3(0.4, 0.05, 1.1), Vector3(float(k) * 22.0 - 3.4, 0.185, float(k) * 4.0), grate)

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

func _add_plaza_pylon(parent: Node3D, pos: Vector3, _mat_unused: Material = null) -> void:
	# A stone monument obelisk on a stepped base — a neutral civic plaza
	# centrepiece (think a small war memorial / commemorative column) that
	# replaces the old glowing sci-fi pylon. No emission, no coloured light.
	var pylon := Node3D.new()
	pylon.name = "PlazaMonument"
	pylon.position = pos
	parent.add_child(pylon)
	var stone := _mat(Color(0.66, 0.64, 0.6, 1.0), Color(0, 0, 0, 1.0), 0.0)
	stone.roughness = 0.85
	var dark_stone := _mat(Color(0.5, 0.48, 0.45, 1.0), Color(0, 0, 0, 1.0), 0.0)
	dark_stone.roughness = 0.9
	_add_box(pylon, "MonumentBase", Vector3(3.2, 0.5, 3.2), Vector3(0, 0.25, 0), dark_stone)
	_add_box(pylon, "MonumentPlinth", Vector3(2.2, 0.7, 2.2), Vector3(0, 0.85, 0), stone)
	# Tapered obelisk shaft (two stacked boxes give a slight taper read).
	_add_box(pylon, "MonumentShaftLower", Vector3(1.3, 5.5, 1.3), Vector3(0, 3.95, 0), stone)
	_add_box(pylon, "MonumentShaftUpper", Vector3(0.9, 3.5, 0.9), Vector3(0, 8.45, 0), stone)
	var cap := MeshInstance3D.new()
	cap.name = "MonumentCap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.0
	cap_mesh.bottom_radius = 0.7
	cap_mesh.height = 1.1
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 10.75, 0)
	cap.material_override = stone
	pylon.add_child(cap)

func _add_streetlight(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/street_light_modern.glb", "y", 5.6)
	if holder == null:
		_add_streetlight_primitive(parent, pos, rot)
		return
	holder.name = "StreetLight"
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rad_to_deg(rot), 0)
	parent.add_child(holder)
	# Warm sodium-vapour lamp glow — low energy so it barely reads in daylight
	# but keeps the fixture believable; no cyan.
	var omni := OmniLight3D.new()
	omni.name = "StreetLightOmni"
	omni.position = Vector3(0, 5.3, 0)
	omni.light_color = Color(1.0, 0.85, 0.6, 1.0)
	omni.light_energy = 1.0
	omni.omni_range = 9.0
	holder.add_child(omni)

func _add_streetlight_primitive(parent: Node3D, pos: Vector3, rot: float) -> void:
	var light := Node3D.new()
	light.name = "StreetLight"
	light.position = pos
	light.rotation_degrees = Vector3(0, rad_to_deg(rot), 0)
	parent.add_child(light)
	_add_box(light, "StreetLightPole", Vector3(0.18, 5.5, 0.18), Vector3(0, 2.75, 0), _mat(Color(0.12, 0.12, 0.13, 1.0), Color(0, 0, 0, 1.0), 0.0))
	_add_box(light, "StreetLightArm", Vector3(1.8, 0.16, 0.16), Vector3(0.85, 5.35, 0.0), _mat(Color(0.12, 0.12, 0.13, 1.0), Color(0, 0, 0, 1.0), 0.0))
	var bulb := MeshInstance3D.new()
	bulb.name = "StreetLightGlow"
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.3
	bulb_mesh.height = 0.5
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(1.85, 5.3, 0)
	bulb.material_override = _mat(Color(0.85, 0.82, 0.75, 1.0), Color(1.0, 0.85, 0.6, 1.0), 0.4)
	light.add_child(bulb)
	var omni := OmniLight3D.new()
	omni.name = "StreetLightOmni"
	omni.position = bulb.position
	omni.light_color = Color(1.0, 0.85, 0.6, 1.0)
	omni.light_energy = 1.0
	omni.omni_range = 9.0
	light.add_child(omni)

# Real CC0 Kenney Nature Kit trees, rotated through 3 variants. Placed every other
# block so they don't choke the avenue. Trees sit between the road and the tower
# footprints, breaking up the long flat curb line under ordinary daylight.
const TREE_VARIANTS := [
	"vegetation/tree_01.glb",
	"vegetation/tree_02.glb",
	"vegetation/tree_03.glb",
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
		_add_tree(parent, tree_name, Vector3(x, 0.0, z), variant)

func _add_tree(parent: Node3D, tree_name: String, pos: Vector3, variant: int) -> void:
	var holder := _instance_prop(PROP_DIR + TREE_VARIANTS[variant], "y", 5.0)
	if holder == null:
		_add_tree_primitive(parent, tree_name, pos)
		return
	holder.name = tree_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, float((int(pos.x) + int(pos.z)) % 4) * 90.0, 0)
	parent.add_child(holder)

func _add_tree_primitive(parent: Node3D, tree_name: String, pos: Vector3) -> void:
	var trunk_mat := _matte(Color(0.19, 0.13, 0.08, 1.0), 0.85)
	var canopy_mat := _matte(Color(0.08, 0.30, 0.12, 1.0), 0.9)
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

func _add_crosswalk(parent: Node3D, avenue_z: float, east_west: bool) -> void:
	# Painted zebra crosswalks where avenues intersect — worn white thermoplastic
	# paint, non-emissive, so they read as real continental-style markings.
	var stripe_mat := _matte(Color(0.34, 0.335, 0.31, 1.0), 0.84)
	for k in range(-1, 2):
		var stripe := MeshInstance3D.new()
		stripe.name = "CrosswalkStripe_%s_%d" % [("EW" if east_west else "NS"), k]
		var s_mesh := BoxMesh.new()
		if east_west:
			s_mesh.size = Vector3(0.45, 0.025, 2.7)
			stripe.position = Vector3(float(k) * 5.5, 0.27, avenue_z)
		else:
			s_mesh.size = Vector3(2.7, 0.025, 0.45)
			stripe.position = Vector3(avenue_z, 0.27, float(k) * 5.5)
		stripe.mesh = s_mesh
		stripe.material_override = stripe_mat
		parent.add_child(stripe)

func _add_floor_strips(parent: Node3D, width: float, depth: float, h: float) -> void:
	var rows := int(clamp(h / 4.2, 5.0, 11.0))
	var window_mat := _matte(Color(0.12, 0.14, 0.16, 1.0), 0.55, 0.15)
	var pod_mat := _matte(Color(0.28, 0.29, 0.30, 1.0), 0.7, 0.2)
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

func _add_cornice(parent: Node3D, width: float, depth: float, top_y: float) -> void:
	# A projecting stone/concrete cornice at the parapet line — the horizontal cap
	# that crowns most pre-war NYC buildings — plus a low parapet wall above the
	# roofline. Non-emissive masonry; replaces the old neon crown band. The tone
	# varies subtly per building so the skyline isn't uniform.
	var tone := 0.6 + fposmod(width + depth + top_y, 5.0) * 0.04
	var cornice_mat := _mat(Color(tone, tone * 0.97, tone * 0.92, 1.0), Color(0, 0, 0, 1.0), 0.0)
	cornice_mat.roughness = 0.85
	var y := top_y - 0.25
	var proj := 0.45
	_add_box(parent, "CorniceFront", Vector3(width + proj * 2.0, 0.55, proj), Vector3(0, y, depth * 0.5 + proj * 0.5), cornice_mat)
	_add_box(parent, "CorniceBack", Vector3(width + proj * 2.0, 0.55, proj), Vector3(0, y, -depth * 0.5 - proj * 0.5), cornice_mat)
	_add_box(parent, "CorniceLeft", Vector3(proj, 0.55, depth + proj * 2.0), Vector3(-width * 0.5 - proj * 0.5, y, 0), cornice_mat)
	_add_box(parent, "CorniceRight", Vector3(proj, 0.55, depth + proj * 2.0), Vector3(width * 0.5 + proj * 0.5, y, 0), cornice_mat)
	# Low parapet wall standing just above the roof slab behind the cornice.
	var parapet_mat := _mat(Color(tone * 0.9, tone * 0.88, tone * 0.84, 1.0), Color(0, 0, 0, 1.0), 0.0)
	parapet_mat.roughness = 0.9
	_add_box(parent, "ParapetFront", Vector3(width + 0.1, 0.7, 0.18), Vector3(0, top_y + 0.35, depth * 0.5 - 0.05), parapet_mat)
	_add_box(parent, "ParapetBack", Vector3(width + 0.1, 0.7, 0.18), Vector3(0, top_y + 0.35, -depth * 0.5 + 0.05), parapet_mat)
	_add_box(parent, "ParapetLeft", Vector3(0.18, 0.7, depth + 0.1), Vector3(-width * 0.5 + 0.05, top_y + 0.35, 0), parapet_mat)
	_add_box(parent, "ParapetRight", Vector3(0.18, 0.7, depth + 0.1), Vector3(width * 0.5 - 0.05, top_y + 0.35, 0), parapet_mat)

func _add_vertical_ribs(parent: Node3D, width: float, depth: float, top_y: float, collector: bool) -> void:
	# Vertical corner pilasters — projecting masonry/limestone ribs that run the
	# full height of the facade (a common pre-war detail). Non-emissive; the old
	# cyan glow that lit up every tower edge is gone.
	var rib_mat := _matte(Color(0.50, 0.49, 0.46, 1.0), 0.85)
	if collector:
		rib_mat = _matte(Color(0.40, 0.42, 0.45, 1.0), 0.6, 0.25)  # metal-clad mullion on commercial towers
	var rib_h: float = top_y + 0.3
	var rib_cy: float = top_y * 0.5
	_add_box(parent, "FrontLeftRib", Vector3(0.18, rib_h, 0.18), Vector3(-width * 0.48, rib_cy, depth * 0.48), rib_mat)
	_add_box(parent, "FrontRightRib", Vector3(0.18, rib_h, 0.18), Vector3(width * 0.48, rib_cy, depth * 0.48), rib_mat)
	_add_box(parent, "BackLeftRib", Vector3(0.18, rib_h, 0.18), Vector3(-width * 0.48, rib_cy, -depth * 0.48), rib_mat)
	_add_box(parent, "BackRightRib", Vector3(0.18, rib_h, 0.18), Vector3(width * 0.48, rib_cy, -depth * 0.48), rib_mat)

func _add_roof_detail(parent: Node3D, width: float, depth: float, top_y: float, x: int, z: int, collector: bool) -> void:
	# Real NYC rooftops: a tar-and-gravel roof slab cluttered with mechanical kit —
	# a timber water tank, HVAC/condenser boxes, vent stacks, a stair bulkhead. All
	# matte and non-emissive; the only roof light is the red aviation lamp added
	# separately on the tallest towers. No spires, beacons, drone pads or energy rings.
	var roof_mat := _matte(Color(0.12, 0.12, 0.125, 1.0), 0.95)      # tar/gravel roof
	var mech_mat := _matte(Color(0.46, 0.47, 0.48, 1.0), 0.65, 0.25) # galvanised metal
	var brick_mat := _matte(Color(0.4, 0.34, 0.3, 1.0), 0.85)        # bulkhead masonry
	_add_box(parent, "RooftopSlab", Vector3(width + 0.6, 0.4, depth + 0.6), Vector3(0, top_y + 0.2, 0), roof_mat)
	var seed := absi(x * 31 + z * 17)
	# Stair / elevator bulkhead — a small penthouse box set to one side.
	var bw: float = clampf(width * 0.34, 1.6, 3.4)
	var bd: float = clampf(depth * 0.34, 1.6, 3.4)
	_add_box(parent, "RoofBulkhead", Vector3(bw, 2.4, bd), Vector3(-width * 0.18, top_y + 1.6, depth * 0.16), brick_mat)
	# HVAC / condenser units.
	for u in range(1 + seed % 2):
		_add_box(parent, "RoofHVAC_%d" % u, Vector3(1.5, 0.9, 1.1), Vector3(width * (0.12 + 0.16 * float(u)), top_y + 0.85, -depth * 0.22), mech_mat)
	# Vent stacks.
	for v in range(2):
		var vent := MeshInstance3D.new()
		vent.name = "RoofVent_%d" % v
		var vm := CylinderMesh.new()
		vm.top_radius = 0.16
		vm.bottom_radius = 0.16
		vm.height = 1.1
		vent.mesh = vm
		vent.position = Vector3(width * (0.3 - 0.5 * float(v)), top_y + 0.95, depth * 0.3)
		vent.material_override = mech_mat
		parent.add_child(vent)
	# Iconic timber water tank on most mid/large roofs.
	if collector or width > 9.0 or seed % 3 != 0:
		var s: float = clampf(minf(width, depth) / 3.2, 0.55, 1.2)
		_add_water_tank(parent, Vector3(width * 0.14, top_y + 0.4, -depth * 0.04), s)
	# Slim antenna whip on a subset (dark metal, no glow).
	if seed % 4 == 0:
		var antenna := MeshInstance3D.new()
		antenna.name = "RooftopAntenna"
		var antenna_mesh := CylinderMesh.new()
		antenna_mesh.top_radius = 0.04
		antenna_mesh.bottom_radius = 0.08
		antenna_mesh.height = 3.4
		antenna.mesh = antenna_mesh
		antenna.position = Vector3(-width * 0.28, top_y + 2.1, -depth * 0.28)
		antenna.material_override = mech_mat
		parent.add_child(antenna)
	# Landmark collectors keep a taller masonry crown + a metal finial (no neon).
	if collector:
		_add_box(parent, "CollectorCrown", Vector3(width * 0.6, 3.0, depth * 0.6), Vector3(0, top_y + 2.0, 0), brick_mat)
		var finial := MeshInstance3D.new()
		finial.name = "CollectorFinial"
		var finial_mesh := CylinderMesh.new()
		finial_mesh.top_radius = 0.0
		finial_mesh.bottom_radius = 0.45
		finial_mesh.height = 5.0
		finial.mesh = finial_mesh
		finial.position = Vector3(0, top_y + 3.5 + 2.5, 0)
		finial.material_override = mech_mat
		parent.add_child(finial)

func _add_water_tank(parent: Node3D, base: Vector3, s: float = 1.0) -> void:
	# Classic rooftop timber water tank on a steel-leg frame with a conical lid —
	# one of the most recognisable silhouettes on the Manhattan skyline.
	var wood := _matte(Color(0.34, 0.23, 0.15, 1.0), 0.92)
	var steel := _matte(Color(0.16, 0.16, 0.17, 1.0), 0.7, 0.3)
	var leg_h: float = 2.3 * s
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			_add_box(parent, "WTLeg_%d_%d" % [int(lx), int(lz)], Vector3(0.15 * s, leg_h, 0.15 * s), base + Vector3(lx * 0.85 * s, leg_h * 0.5, lz * 0.85 * s), steel)
	var body := MeshInstance3D.new()
	body.name = "WaterTankBody"
	var bm := CylinderMesh.new()
	bm.top_radius = 1.2 * s
	bm.bottom_radius = 1.32 * s
	bm.height = 2.7 * s
	body.mesh = bm
	body.position = base + Vector3(0, leg_h + 1.35 * s, 0)
	body.material_override = wood
	parent.add_child(body)
	var cap := MeshInstance3D.new()
	cap.name = "WaterTankCap"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.36 * s
	cm.height = 0.9 * s
	cap.mesh = cm
	cap.position = base + Vector3(0, leg_h + 2.7 * s + 0.45 * s, 0)
	cap.material_override = steel
	parent.add_child(cap)

func _add_rooftop_beacon(parent: Node3D, pos: Vector3, collector: bool = false) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "AviationWarningLamp"
	var mesh := SphereMesh.new()
	mesh.radius = 0.22 if collector else 0.16
	mesh.height = 0.34 if collector else 0.24
	beacon.mesh = mesh
	beacon.position = pos
	beacon.material_override = _mat(Color(0.45, 0.04, 0.035, 1.0), Color(0.8, 0.04, 0.03, 1.0), 0.12 if collector else 0.08)
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
	elif mode == "city":
		# Cinematic city vista: park the hero as a small flying silhouette south of
		# the elevated interchange, facing north toward the skyline cluster. The
		# camera (PlayerFlightController) sits behind/above it so the highway sweeps
		# across the foreground as leading lines and the hero/grid towers rise into
		# the golden-hour sky behind — the reference wide-angle metropolitan frame.
		hero.position = Vector3(0, 24, -128)
		hero.rotation_degrees = Vector3(0, 0, 0)
		hero.visible = false
		for event_node in events.event_nodes:
			if is_instance_valid(event_node):
				event_node.visible = false
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
	_apply_capture_showcase_hud()

func _apply_capture_showcase_hud() -> void:
	# The city capture is the environment/style proof shot. Hide gameplay HUD and
	# objective overlays only for that deterministic capture mode so the skyline,
	# deep-blue sky, and interchange can fill the frame like a cinematic postcard.
	if OS.get_environment("AURORA_CAPTURE_MODE") != "city":
		return
	var showcase_nodes: Array = [
		hud_panel, mission_panel, hud_label, mission_label, event_cue_label,
		health_bar_bg, health_bar_fill, health_label, minimap, controls_hint_label,
		unlock_toast, mission_banner, game_over_label,
	]
	for node in showcase_nodes:
		if node != null and is_instance_valid(node):
			node.visible = false

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
		controls_hint_label.text = "Gamepad: Left stick fly · Triggers climb/dive · Bumpers orbit sprint (unlockable) · A rescue · B sonic · X radiant · Y aegis · Right stick look · Select pause"
	else:
		controls_hint_label.text = "Keyboard: WASD fly · Space/Ctrl climb/dive · Shift orbit sprint (unlockable) · R rescue · Q sonic · F radiant · E aegis · Esc pause"

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
	# Daytime: windows read as dark/reflective glass. Only a sparse handful are lit
	# (a few interior lights left on), at low energy — no wall of glowing offices.
	var lit_prob := 0.08 if not collector else 0.12
	var em_energy := 0.45 if not collector else 0.7
	# UV scale variation per building — real PBR textures need higher tiling for visible detail
	var uv_s := 4.0 + float(abs(x + z) % 3) * 0.5
	if h > 42.0:
		uv_s += 0.5
	if collector:
		uv_s += 0.3
	# Albedo tint variation — warm neutral stone/brick tones (not the old cool blue
	# cast). Lets the real PBR brick/concrete textures show their own colour.
	var tint_r := 0.90 + float(abs(x) % 5) * 0.018
	var tint_g := 0.88 + float(abs(z) % 4) * 0.015
	var tint_b := 0.82 + float(abs(x + z) % 3) * 0.02
	if collector:
		tint_r = 0.86
		tint_g = 0.89
		tint_b = 0.94  # commercial curtain-wall glass reads a touch cooler
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
	# Mullion frames in dark warm grey; unlit panes as dark neutral glass. The lit
	# palette is all warm interior tones — the cyan office glow is gone.
	mat.set_shader_parameter("frame_color", Color(0.06, 0.06, 0.065, 1.0))
	mat.set_shader_parameter("dark_window", Color(0.07, 0.08, 0.095, 1.0))
	mat.set_shader_parameter("warm_white", Color(1.0, 0.95, 0.84, 1.0))
	mat.set_shader_parameter("cool_office_white", Color(0.88, 0.89, 0.86, 1.0))
	mat.set_shader_parameter("warm_amber", Color(1.0, 0.82, 0.55, 1.0))
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
		var event_spawn_mult: float = sm.event_spawn_mult()
		var previous_spawn_mult: float = max(0.01, events.spawn_mult)
		var next_spawn_mult: float = max(0.01, event_spawn_mult)
		if absf(previous_spawn_mult - next_spawn_mult) > 0.001:
			# Keep the currently scheduled threshold in the same unscaled time domain
			# so difficulty applies immediately at game start and after settings changes
			# without compounding on repeated apply_difficulty() calls.
			events.next_event_seconds = max(0.25, events.next_event_seconds * previous_spawn_mult / next_spawn_mult)
		events.spawn_mult = event_spawn_mult

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

func _matte(albedo: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	# Non-emissive diffuse material — the workhorse for realistic daytime surfaces
	# (asphalt, concrete, road paint, masonry, painted metal). No glow whatsoever,
	# so these read as real materials lit by the sun rather than neon graphics.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = rough
	mat.metallic = metal
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
	# The facade PBR texture sets are loaded at runtime and held in these member
	# arrays on Main (which outlives its freed children), so they would otherwise
	# linger as "resources still in use at exit". Release them here too. Any
	# remaining leak warnings come from const-preloaded shaders/scenes that
	# intentionally live for the whole process lifetime and are harmless.
	_facade_albedo_textures.clear()
	_facade_normal_textures.clear()
	_facade_roughness_textures.clear()
	_facade_emission_textures.clear()
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
		var px: float = float(coord[0]) * 22.0 + 11.0
		var pz: float = float(coord[1]) * 22.0 + 11.0
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
		# Low shrubs/planting beds as ordinary daylight greenery.
		for i in range(3):
			var shrub_pos := Vector3(px + float((i * 7 - 7)), 0, pz + float((i * 5 - 5)))
			_add_park_shrub(parent, shrub_pos, i)

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
	# Layered canopy — two matte spheres for volume.
	var canopy_a_mat := _matte(Color(0.06, 0.33, 0.16, 1.0), 0.9)
	var canopy_b_mat := _matte(Color(0.05, 0.38, 0.18, 1.0), 0.9)
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

func _add_park_shrub(parent: Node3D, pos: Vector3, variant: int) -> void:
	var shrub := Node3D.new()
	shrub.name = "ParkShrub_%d_%d" % [int(pos.x), int(pos.z)]
	shrub.position = pos
	parent.add_child(shrub)
	var colors: Array[Color] = [
		Color(0.05, 0.24, 0.10, 1.0),
		Color(0.08, 0.30, 0.13, 1.0),
		Color(0.12, 0.34, 0.16, 1.0),
	]
	var c: Color = colors[variant % colors.size()]
	var shrub_mat := _matte(c, 0.92)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ShrubMesh"
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.6
	s_mesh.height = 1.0
	mesh_inst.mesh = s_mesh
	mesh_inst.position = Vector3(0, 0.5, 0)
	mesh_inst.material_override = shrub_mat
	shrub.add_child(mesh_inst)

func _add_plaza_paving(parent: Node3D) -> void:
	# Polished plaza-textured quads around the 4 collector towers. Collector lots
	# now sit halfway between avenue centerlines, so the paving uses the same lot
	# centers and no longer paints plaza slabs over the roads.
	var plaza_mat := _ground_plaza_material()
	for x in [-5, 4]:
		for z in [-5, 4]:
			var lot_x := float(x) * 22.0 + 11.0
			var lot_z := float(z) * 22.0 + 11.0
			var plaza := MeshInstance3D.new()
			plaza.name = "PlazaPaving_%d_%d" % [x, z]
			var p_mesh := PlaneMesh.new()
			p_mesh.size = Vector2(18.0, 18.0)
			plaza.mesh = p_mesh
			plaza.position = Vector3(lot_x, 0.15, lot_z)
			plaza.material_override = plaza_mat
			parent.add_child(plaza)
			# Raised concrete/stone edging around the paved plaza — no emissive inlay.
			for side in [-1.0, 1.0]:
				var strip_x := MeshInstance3D.new()
				strip_x.name = "PlazaStripX_%d_%d_%d" % [x, z, int(side)]
				var sx_mesh := BoxMesh.new()
				sx_mesh.size = Vector3(18.0, 0.04, 0.3)
				strip_x.mesh = sx_mesh
				strip_x.position = Vector3(lot_x, 0.17, lot_z + side * 9.0)
				strip_x.material_override = _matte(Color(0.38, 0.37, 0.35, 1.0), 0.82)
				parent.add_child(strip_x)
				var strip_z := MeshInstance3D.new()
				strip_z.name = "PlazaStripZ_%d_%d_%d" % [x, z, int(side)]
				var sz_mesh := BoxMesh.new()
				sz_mesh.size = Vector3(0.3, 0.04, 18.0)
				strip_z.mesh = sz_mesh
				strip_z.position = Vector3(lot_x + side * 9.0, 0.17, lot_z)
				strip_z.material_override = _matte(Color(0.38, 0.37, 0.35, 1.0), 0.82)
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
	_add_cornice(body, top_w, top_d, top_y)

func _add_diagonal_streets(parent: Node3D) -> void:
	# Three boulevards slicing across the rigid grid at 30-45 degrees. Each lays a
	# matte asphalt road surface + faded centre dashes + raised sidewalks, and lines its outer
	# (suburban) reaches with towers rotated to the street direction so the city
	# reads as real topology rather than a pure lattice.
	var road_mat := _matte(Color(0.085, 0.085, 0.09, 1.0), 0.93)
	var dash_mat := _matte(Color(0.34, 0.28, 0.08, 1.0), 0.82)  # very faded yellow centre line
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
			var dash := _add_box(parent, "DiagDash_%d_%d" % [di, k], Vector3(2.6, 0.035, 0.14), dpos, dash_mat)
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
	var road_mat := _matte(Color(0.085, 0.085, 0.09, 1.0), 0.93)
	var dash_mat := _matte(Color(0.30, 0.295, 0.27, 1.0), 0.84)  # worn white lane paint
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
				var dash := _add_box(parent, "CurveDash_%d_%d" % [ci, si], Vector3(seg_len * 0.30, 0.035, 0.14), pos + Vector3(0, 0.11, 0), dash_mat)
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
	var edge_mat := _matte(Color(0.46, 0.45, 0.43, 1.0), 0.8)  # poured-concrete kerb trim
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
		# Stone commemorative monument at the plaza centre (no glowing beacon).
		_add_plaza_pylon(parent, Vector3(cx, 0.0, cz))
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
	# Raised sidewalks with a 0.15 m curb along the road edges. These used to be
	# drawn through the half-grid lot centers, which made the sidewalk/grid texture
	# appear to continue underneath tower footprints. Keep them tied to avenue
	# centerlines so roads and pedestrian strips stay outside building lots.
	var walk_mat := _ground_plaza_material()
	var curb_mat := _matte(Color(0.30, 0.295, 0.28, 1.0), 0.86)  # weathered concrete curb
	var corridors := [-88.0, -66.0, -44.0, -22.0, 0.0, 22.0, 44.0, 66.0, 88.0]
	for c in corridors:
		for s in [-1.0, 1.0]:
			_add_box(parent, "SidewalkNS_%d_%d" % [int(c), int(s)], Vector3(2.6, 0.15, 220.0), Vector3(c + s * 4.6, 0.075, 0.0), walk_mat)
			_add_box(parent, "SidewalkCurbNS_%d_%d" % [int(c), int(s)], Vector3(0.25, 0.17, 220.0), Vector3(c + s * 3.3, 0.085, 0.0), curb_mat)
			_add_box(parent, "SidewalkEW_%d_%d" % [int(c), int(s)], Vector3(220.0, 0.15, 2.6), Vector3(0.0, 0.075, c + s * 4.6), walk_mat)
			_add_box(parent, "SidewalkCurbEW_%d_%d" % [int(c), int(s)], Vector3(220.0, 0.17, 0.25), Vector3(0.0, 0.085, c + s * 3.3), curb_mat)
	# A few muted crosswalks at key mid-block corridor intersections. Too many
	# repeated bright stripes read like a prototype grid from high cameras.
	for c in [-22.0, 0.0, 22.0]:
		_add_crosswalk(parent, c, true)
		_add_crosswalk(parent, c, false)
		for s in [-1.0, 1.0]:
			# Curb-cut accessibility ramp wedges at the corners.
			_add_box(parent, "CurbCut_%d_%d" % [int(c), int(s)], Vector3(2.2, 0.07, 2.2), Vector3(c + s * 3.6, 0.04, c + s * 3.6), walk_mat)

func _add_parking_lots(parent: Node3D) -> void:
	# Flat asphalt lots with painted stalls + parked cars, dropped onto otherwise
	# empty lots and one suburban clearing — more grid-breaking open space.
	var lot_mat := _matte(Color(0.09, 0.09, 0.095, 1.0), 0.92)  # asphalt lot
	var line_mat := _matte(Color(0.34, 0.33, 0.30, 1.0), 0.84)   # faded painted stall lines
	# [cx, cz, cols, rows, rot]
	var lots := [
		[77.0, 11.0, 4, 3, 0.0],
		[11.0, -55.0, 4, 3, 0.0],
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
	# Dark plastic rim; no sci-fi cyan accent.
	var rim := _matte(Color(0.055, 0.075, 0.065, 1.0), 0.82)
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
	var plant_mat := _matte(Color(0.05, 0.30, 0.12, 1.0), 0.9)
	var plant := MeshInstance3D.new()
	plant.name = "PlanterFoliage"
	var p_mesh := SphereMesh.new()
	p_mesh.radius = 0.7
	p_mesh.height = 0.8
	plant.mesh = p_mesh
	plant.position = Vector3(0, 0.7, 0)
	plant.material_override = plant_mat
	prop.add_child(plant)


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
	warn.light_energy = 0.05
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
	warn.light_energy = 0.05
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
	var bar_mat := _matte(Color(0.42, 0.34, 0.06, 1.0), 0.72)
	# Base
	_add_box(prop, "BarrierBase", Vector3(2.0, 0.08, 0.4), Vector3(0, 0.06, 0), bar_mat)
	# Vertical posts
	for sx in [-0.8, 0.8]:
		_add_box(prop, "BarrierPost_%d" % int(sx), Vector3(0.1, 0.8, 0.1), Vector3(sx, 0.5, 0), bar_mat)
	# Top rail
	_add_box(prop, "BarrierRail", Vector3(2.0, 0.08, 0.08), Vector3(0, 0.9, 0), bar_mat)
	# Hazard stripes — alternating dark/yellow via 4 small boxes
	for i in range(4):
		var stripe_mat := _matte(Color(0.62, 0.50, 0.08, 1.0), 0.7) if i % 2 == 0 else _matte(Color(0.04, 0.04, 0.035, 1.0), 0.8)
		_add_box(prop, "BarrierStripe_%d" % i, Vector3(0.45, 0.25, 0.03), Vector3(-0.7 + float(i) * 0.45, 0.45, 0.18), stripe_mat)

# ── New real-model city props (no prior primitive; fall back to a tinted box) ──

func _add_prop_fallback_box(parent: Node3D, prop_name: String, pos: Vector3, rot: float, size: Vector3, emission: Color) -> Node3D:
	var holder := Node3D.new()
	holder.name = prop_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	_add_box(holder, "Body", size, Vector3(0, size.y * 0.5, 0), _matte(emission, 0.78, 0.05))
	return holder

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

func _add_news_stand(parent: Node3D, pos: Vector3, rot: float) -> void:
	var holder := _instance_prop(PROP_DIR + "street/news_stand.glb", "y", 2.6, true)
	if holder == null:
		_add_prop_fallback_box(parent, "NewsStand_%d_%d" % [int(pos.x), int(pos.z)], pos, rot, Vector3(2.4, 2.6, 1.6), Color(0.6, 0.4, 0.15))
		return
	holder.name = "NewsStand_%d_%d" % [int(pos.x), int(pos.z)]
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)

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

func _add_car(parent: Node3D, car_name: String, pos: Vector3, rot: float, variant: int) -> Node3D:
	# Fit by length (Z) so the chunky low-poly cars read at a believable street scale.
	var holder := _instance_prop(PROP_DIR + CAR_VARIANTS[variant], "z", 4.4, true)
	if holder == null:
		return _add_prop_fallback_box(parent, car_name, pos, rot, Vector3(1.6, 1.2, 4.0), Color(0.3, 0.4, 0.6))
	holder.name = car_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0, rot, 0)
	parent.add_child(holder)
	return holder

func _route_length(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		total += a.distance_to(b)
	return total

func _route_point_at_distance(points: Array, distance: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var total := _route_length(points)
	if total <= 0.001:
		return points[0]
	var remaining := fposmod(distance, total)
	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.001:
			continue
		if remaining <= seg_len:
			return a.lerp(b, remaining / seg_len)
		remaining -= seg_len
	return points[points.size() - 1]

func _route_heading_degrees(points: Array, distance: float) -> float:
	if points.size() < 2:
		return 0.0
	var total := _route_length(points)
	if total <= 0.001:
		return 0.0
	var p := _route_point_at_distance(points, distance)
	var q := _route_point_at_distance(points, distance + 1.5)
	var dir := q - p
	if dir.length() <= 0.001:
		return 0.0
	return rad_to_deg(atan2(dir.x, dir.z))

func _add_routed_traffic_car(parent: Node3D, car_name: String, route_points: Array, destination_name: String, variant: int, speed: float, route_fraction: float) -> Node3D:
	if route_points.size() < 2:
		return null
	var route_len := _route_length(route_points)
	if route_len <= 0.001:
		return null
	var progress := fposmod(route_len * route_fraction, route_len)
	var start := _route_point_at_distance(route_points, progress)
	var heading := _route_heading_degrees(route_points, progress)
	var car := _add_car(parent, car_name, start, heading, variant % CAR_VARIANTS.size())
	if car == null:
		return null
	var stored_points := route_points.duplicate(true)
	car.name = car_name
	car.set_meta("destination_name", destination_name)
	car.set_meta("route_points", stored_points)
	car.set_meta("route_speed", speed)
	car.set_meta("route_length", route_len)
	_routed_traffic.append({
		"node": car,
		"route_points": stored_points,
		"destination_name": destination_name,
		"speed": speed,
		"route_length": route_len,
		"progress": progress,
	})
	return car

func _update_routed_traffic(delta: float) -> void:
	if _routed_traffic.is_empty():
		return
	for i in range(_routed_traffic.size()):
		var actor: Dictionary = _routed_traffic[i]
		var car: Node3D = actor.get("node", null) as Node3D
		if car == null or not is_instance_valid(car):
			continue
		var points: Array = actor.get("route_points", []) as Array
		var route_len := float(actor.get("route_length", _route_length(points)))
		if points.size() < 2 or route_len <= 0.001:
			continue
		var progress := fposmod(float(actor.get("progress", 0.0)) + float(actor.get("speed", 10.0)) * delta, route_len)
		actor["progress"] = progress
		_routed_traffic[i] = actor
		var p := _route_point_at_distance(points, progress)
		var q := _route_point_at_distance(points, progress + 1.5)
		var dir := q - p
		car.position = p
		if dir.length() > 0.001:
			car.rotation.y = atan2(dir.x, dir.z)

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

# ── Golden-hour cinematic landmarks: glass towers, highway interchange, crane, palms ──

func _glass_tower_material(albedo: Color) -> StandardMaterial3D:
	# Curtain-wall glass/steel for the hero landmarks. High metallic + low roughness
	# so the warm low sun throws a hot specular glint across one face while the cool
	# blue sky reflects in the rest — the teal/orange split the reference leans on.
	# No emission: the warmth comes from the directional key, not a neon glow.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = 0.85
	mat.metallic_specular = 0.9
	mat.roughness = 0.12
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.7
	return mat

func _add_hero_tower(parent: Node3D) -> void:
	# Distinctive fictional landmark: a dark rounded-glass corporate spire that
	# catches the golden sun on one face. Cylindrical shaft, tapered crown, a thin
	# metallic crown ring and a small warm-lit "Vigil" mark plate near the top.
	var body := StaticBody3D.new()
	body.name = "VigilSpire_HeroTower"
	body.position = Vector3(33.0, 0.0, 99.0)
	parent.add_child(body)
	var h := 114.0
	var rad := 7.4
	var glass := _glass_tower_material(Color(0.10, 0.15, 0.22, 1.0))
	var shaft := MeshInstance3D.new()
	shaft.name = "VigilSpireShaft"
	var cm := CylinderMesh.new()
	cm.top_radius = rad * 0.80
	cm.bottom_radius = rad
	cm.height = h
	cm.radial_segments = 40
	shaft.mesh = cm
	shaft.position = Vector3(0, h * 0.5, 0)
	shaft.material_override = glass
	body.add_child(shaft)
	# Collision: a single cylinder so flight + camera collision treat it as solid.
	var col := CollisionShape3D.new()
	col.name = "VigilSpireCol"
	var cyl := CylinderShape3D.new()
	cyl.radius = rad
	cyl.height = h
	col.shape = cyl
	col.position = Vector3(0, h * 0.5, 0)
	body.add_child(col)
	# Horizontal floor bands — thin darker mullion rings that give the cylinder the
	# stacked-glass-floor read instead of a smooth tube.
	var band_mat := _matte(Color(0.05, 0.06, 0.08, 1.0), 0.5, 0.4)
	var bands := int(h / 4.4)
	for i in range(1, bands):
		var ring := MeshInstance3D.new()
		ring.name = "VigilBand_%d" % i
		var rm := CylinderMesh.new()
		var ry := float(i) * 4.4
		var taper := 1.0 - 0.20 * (ry / h)
		rm.top_radius = rad * taper + 0.06
		rm.bottom_radius = rad * taper + 0.06
		rm.height = 0.4
		rm.radial_segments = 40
		ring.mesh = rm
		ring.position = Vector3(0, ry, 0)
		ring.material_override = band_mat
		body.add_child(ring)
	# Metallic crown ring + a slim mast at the very top.
	var crown_mat := _matte(Color(0.30, 0.30, 0.33, 1.0), 0.35, 0.7)
	var crown := MeshInstance3D.new()
	crown.name = "VigilCrown"
	var crm := CylinderMesh.new()
	crm.top_radius = rad * 0.86
	crm.bottom_radius = rad * 0.82
	crm.height = 4.0
	crm.radial_segments = 40
	crown.mesh = crm
	crown.position = Vector3(0, h + 1.6, 0)
	crown.material_override = crown_mat
	body.add_child(crown)
	var mast := _add_box(body, "VigilMast", Vector3(0.5, 12.0, 0.5), Vector3(0, h + 9.0, 0), crown_mat)
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_add_rooftop_beacon(body, Vector3(0, h + 15.5, 0), true)
	# Fictional corporate mark — a small chevron sign plate on the sunlit face, lit
	# at very low warm energy so it reads as building signage, not neon.
	var sign_mat := _mat(Color(0.85, 0.86, 0.9, 1.0), Color(1.0, 0.86, 0.6, 1.0), 0.5)
	var sign := _add_box(body, "VigilMarkPlate", Vector3(0.4, 5.0, 5.0), Vector3(rad * 0.86, h - 12.0, 0), sign_mat)
	sign.rotation_degrees = Vector3(0, 0, 0)
	var chevron := _add_box(body, "VigilMarkChevron", Vector3(0.5, 0.7, 3.4), Vector3(rad * 0.92, h - 12.0, 0), _mat(Color(0.1, 0.13, 0.2, 1.0), Color(0, 0, 0, 1), 0.0))
	chevron.rotation_degrees = Vector3(0, 0, 32.0)

func _add_landmark_grid_tower(parent: Node3D) -> void:
	# Central rectangular grid-facade tower: strong alternating window panels via the
	# facade shader, plus a muted vertical accent stripe up one corner and a flat
	# parapet crown. The procedural facade carries the window grid; the stripe and
	# spandrel bands give it the bold blocky read of the reference's centre tower.
	var body := StaticBody3D.new()
	body.name = "MeridianOne_GridTower"
	body.position = Vector3(-33.0, 0.0, 99.0)
	parent.add_child(body)
	var w := 14.0
	var d := 13.0
	var h := 100.0
	var facade := _city_facade_material(h, 9, 11, w, d, true)
	facade.set_shader_parameter("floors", 20)
	facade.set_shader_parameter("windows_per_floor", 6)
	facade.set_shader_parameter("uv_scale", 6.0)
	facade.set_shader_parameter("lit_probability", 0.07)
	facade.set_shader_parameter("albedo_tint", Color(0.80, 0.84, 0.92, 1.0))
	_add_building_segment(body, "GridMain", Vector3(w, h, d), Vector3(0, h * 0.5, 0), facade)
	# Muted vertical accent stripe up the front-left corner (brushed metal mullion).
	var stripe_mat := _matte(Color(0.40, 0.42, 0.46, 1.0), 0.45, 0.6)
	_add_box(body, "GridStripe", Vector3(1.4, h, 0.5), Vector3(-w * 0.5 + 0.7, h * 0.5, d * 0.5 + 0.26), stripe_mat)
	_add_box(body, "GridStripeSide", Vector3(0.5, h, 1.4), Vector3(-w * 0.5 - 0.26, h * 0.5, d * 0.5 - 0.7), stripe_mat)
	# Spandrel bands every few floors break the glass into bold horizontal panels.
	var spandrel_mat := _matte(Color(0.18, 0.19, 0.22, 1.0), 0.6, 0.3)
	var floor_h := h / 20.0
	for fi in range(1, 20):
		var sy := float(fi) * floor_h
		_add_box(body, "GridSpandrelF_%d" % fi, Vector3(w + 0.12, 0.7, 0.18), Vector3(0, sy, d * 0.5 + 0.1), spandrel_mat)
		_add_box(body, "GridSpandrelB_%d" % fi, Vector3(w + 0.12, 0.7, 0.18), Vector3(0, sy, -d * 0.5 - 0.1), spandrel_mat)
		_add_box(body, "GridSpandrelL_%d" % fi, Vector3(0.18, 0.7, d + 0.12), Vector3(-w * 0.5 - 0.1, sy, 0), spandrel_mat)
		_add_box(body, "GridSpandrelR_%d" % fi, Vector3(0.18, 0.7, d + 0.12), Vector3(w * 0.5 + 0.1, sy, 0), spandrel_mat)
	# Flat parapet crown + rooftop mechanical block.
	var crown_mat := _matte(Color(0.22, 0.23, 0.26, 1.0), 0.7)
	_add_box(body, "GridParapet", Vector3(w + 0.6, 1.6, d + 0.6), Vector3(0, h + 0.8, 0), crown_mat)
	_add_box(body, "GridMech", Vector3(w * 0.5, 4.0, d * 0.5), Vector3(0, h + 3.6, 0), crown_mat)
	_add_rooftop_beacon(body, Vector3(0, h + 6.5, 0), true)

func _highway_concrete_material() -> StandardMaterial3D:
	return _matte(Color(0.50, 0.48, 0.45, 1.0), 0.88)

func _add_highway_interchange(parent: Node3D) -> void:
	# A sweeping multi-level elevated interchange across the city foreground: two
	# concentric curved viaducts at different heights, supported on concrete piers,
	# edged with metal guardrails, and dashed with worn white lane paint. Sparse
	# vehicles on the upper deck give it scale. Non-emissive concrete + painted
	# metal only — it reads as poured highway in the low sun, not a sci-fi ribbon.
	var hw := Node3D.new()
	hw.name = "GoldenInterchange"
	# Push the whole interchange south of the southern building cluster (the city grid
	# ends near z=-110) so the viaducts sweep across open ground as a clean foreground
	# leading line in the city vista instead of being buried among the skyline towers.
	hw.position = Vector3(0, 0, -88)
	parent.add_child(hw)
	var deck_mat := _highway_concrete_material()
	var rail_mat := _matte(Color(0.62, 0.60, 0.56, 1.0), 0.5, 0.4)
	var paint_mat := _matte(Color(0.74, 0.72, 0.66, 1.0), 0.76)
	var pier_mat := _matte(Color(0.44, 0.42, 0.40, 1.0), 0.9)
	# Upper viaduct sweeps wide across the near foreground; lower viaduct nests
	# inside it at a shallower radius and height for the stacked interchange read.
	_add_highway_arc(hw, deck_mat, rail_mat, paint_mat, pier_mat, "Upper", 0.0, -250.0, 196.0, 56.0, 124.0, 13.0, 16.0, 26, 3)
	_add_highway_arc(hw, deck_mat, rail_mat, paint_mat, pier_mat, "Lower", 0.0, -252.0, 150.0, 64.0, 116.0, 7.0, 12.0, 22, 4)
	# A straight off-ramp peeling off the upper deck down toward the surface streets.
	var ramp_y0 := 13.0
	for ri in range(8):
		var t := float(ri) / 7.0
		var rx := 70.0 - t * 26.0
		var rz := -70.0 + t * 30.0
		var ry := ramp_y0 - t * (ramp_y0 - 0.4)
		var ramp := _add_box(hw, "RampSeg_%d" % ri, Vector3(7.0, 0.6, 9.0), Vector3(rx, ry, rz), deck_mat)
		ramp.rotation_degrees = Vector3(0, 42.0, 0)
		if ry > 1.5:
			_add_box(hw, "RampPier_%d" % ri, Vector3(1.8, ry, 1.8), Vector3(rx, ry * 0.5, rz), pier_mat)
	# Sparse vehicles along the upper deck, aligned to the arc tangent.
	var ox := 0.0
	var oz := -250.0
	var radius := 196.0
	var ci := 0
	for frac in [0.07, 0.12, 0.18, 0.25, 0.33, 0.42, 0.50, 0.58, 0.66, 0.74, 0.82, 0.90]:
		var ang := deg_to_rad(56.0 + (124.0 - 56.0) * frac)
		var px := ox + radius * cos(ang)
		var pz := oz + radius * sin(ang)
		var tangent_deg := rad_to_deg(ang) + 90.0
		var b := Basis(Vector3.UP, deg_to_rad(-tangent_deg))
		var perp: Vector3 = b.z
		var lane_off := -4.0 if ci % 2 == 0 else 4.0
		var cpos: Vector3 = Vector3(px, 13.8, pz) + perp * lane_off
		_add_car(hw, "HighwayCar_%d" % ci, cpos, -tangent_deg + (180.0 if ci % 2 == 0 else 0.0), ci % CAR_VARIANTS.size())
		ci += 1

func _add_highway_arc(parent: Node3D, deck_mat: Material, rail_mat: Material, paint_mat: Material, pier_mat: Material, prefix: String, ox: float, oz: float, radius: float, a0_deg: float, a1_deg: float, deck_y: float, deck_w: float, seg_count: int, pier_every: int) -> void:
	var arc_span := deg_to_rad(absf(a1_deg - a0_deg))
	var seg_len := (arc_span * radius) / float(seg_count) + 1.4
	for si in range(seg_count):
		var fmid := (float(si) + 0.5) / float(seg_count)
		var ang := deg_to_rad(a0_deg + (a1_deg - a0_deg) * fmid)
		var px := ox + radius * cos(ang)
		var pz := oz + radius * sin(ang)
		var tangent_deg := rad_to_deg(ang) + 90.0
		var pos := Vector3(px, deck_y, pz)
		var deck := _add_box(parent, "%sDeck_%d" % [prefix, si], Vector3(seg_len, 0.7, deck_w), pos, deck_mat)
		deck.rotation_degrees = Vector3(0, -tangent_deg, 0)
		var b := Basis(Vector3.UP, deg_to_rad(-tangent_deg))
		var perp: Vector3 = b.z
		for s in [-1.0, 1.0]:
			var rpos: Vector3 = pos + Vector3(0, 0.6, 0) + perp * (s * deck_w * 0.5)
			var rail := _add_box(parent, "%sRail_%d_%d" % [prefix, si, int(s)], Vector3(seg_len, 0.65, 0.22), rpos, rail_mat)
			rail.rotation_degrees = Vector3(0, -tangent_deg, 0)
		# Continuous shoulder lines plus several dashed lane separators make the
		# foreground viaduct read as a real multilane freeway instead of a blank slab.
		for soff in [-deck_w * 0.42, deck_w * 0.42]:
			var shoulder := _add_box(parent, "%sShoulder_%d_%d" % [prefix, si, int(soff * 10.0)], Vector3(seg_len * 0.92, 0.06, 0.22), pos + Vector3(0, 0.39, 0) + perp * soff, paint_mat)
			shoulder.rotation_degrees = Vector3(0, -tangent_deg, 0)
		if si % 2 == 0:
			for loff in [-deck_w * 0.24, 0.0, deck_w * 0.24]:
				var paint := _add_box(parent, "%sLane_%d_%d" % [prefix, si, int(loff * 10.0)], Vector3(seg_len * 0.56, 0.06, 0.34), pos + Vector3(0, 0.40, 0) + perp * loff, paint_mat)
				paint.rotation_degrees = Vector3(0, -tangent_deg, 0)
		if si % pier_every == 0:
			_add_box(parent, "%sPier_%d" % [prefix, si], Vector3(2.6, deck_y, 2.6), Vector3(px, deck_y * 0.5, pz), pier_mat)
			var cap := _add_box(parent, "%sPierCap_%d" % [prefix, si], Vector3(deck_w * 0.66, 0.7, 3.2), Vector3(px, deck_y - 0.2, pz), pier_mat)
			cap.rotation_degrees = Vector3(0, -tangent_deg, 0)

func _add_construction_crane(parent: Node3D, base: Vector3, rot_deg: float, mast_h: float) -> void:
	# A tower crane beside the under-construction lots: a slim lattice mast, a long
	# horizontal jib with a counter-jib + counterweight, and a hook block on a cable.
	# Painted-steel matte yellow so it catches the warm sun without glowing.
	var crane := Node3D.new()
	crane.name = "TowerCrane_%d_%d" % [int(base.x), int(base.z)]
	crane.position = base
	crane.rotation_degrees = Vector3(0, rot_deg, 0)
	parent.add_child(crane)
	var steel := _matte(Color(0.78, 0.62, 0.16, 1.0), 0.6, 0.4)
	var dark_steel := _matte(Color(0.20, 0.20, 0.22, 1.0), 0.6, 0.5)
	# Mast: a thin square column with a few cross-brace rings for the lattice read.
	_add_box(crane, "CraneMast", Vector3(1.6, mast_h, 1.6), Vector3(0, mast_h * 0.5, 0), steel)
	var rings := int(mast_h / 8.0)
	for i in range(1, rings):
		_add_box(crane, "CraneBrace_%d" % i, Vector3(2.0, 0.3, 2.0), Vector3(0, float(i) * 8.0, 0), dark_steel)
	# Operator cab + slewing unit at the top.
	_add_box(crane, "CraneCab", Vector3(2.4, 2.2, 2.4), Vector3(0, mast_h + 1.2, 0), dark_steel)
	var jib_y := mast_h + 2.6
	# Main jib reaches out one way; counter-jib + counterweight the other.
	var jib_len := mast_h * 0.62
	_add_box(crane, "CraneJib", Vector3(jib_len, 0.7, 1.0), Vector3(jib_len * 0.5, jib_y, 0), steel)
	_add_box(crane, "CraneCounterJib", Vector3(jib_len * 0.36, 0.7, 1.0), Vector3(-jib_len * 0.20, jib_y, 0), steel)
	_add_box(crane, "CraneCounterweight", Vector3(2.4, 2.0, 2.4), Vector3(-jib_len * 0.34, jib_y - 0.4, 0), dark_steel)
	# A-frame apex tie above the cab.
	_add_box(crane, "CraneApex", Vector3(0.5, mast_h * 0.18, 0.5), Vector3(0, jib_y + mast_h * 0.09, 0), steel)
	# Hook cable + block hanging part-way along the jib.
	var hook_x := jib_len * 0.7
	var cable := _add_box(crane, "CraneCable", Vector3(0.12, jib_y * 0.45, 0.12), Vector3(hook_x, jib_y - jib_y * 0.225, 0), dark_steel)
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_box(crane, "CraneHook", Vector3(0.8, 1.0, 0.8), Vector3(hook_x, jib_y - jib_y * 0.45, 0), dark_steel)

func _add_boulevard_palms(parent: Node3D) -> void:
	# Sparse decorative palms lining the central boulevard + the irregular plazas,
	# the way a sunbelt metropolis dresses its avenues. Grounded and shadowed.
	var spots := [
		Vector3(13.0, 0.0, 30.0), Vector3(-13.0, 0.0, 46.0), Vector3(13.0, 0.0, 62.0),
		Vector3(-13.0, 0.0, 78.0), Vector3(13.0, 0.0, -30.0), Vector3(-13.0, 0.0, -46.0),
		Vector3(40.0, 0.0, 18.0), Vector3(-40.0, 0.0, 18.0), Vector3(150.0, 0.0, 40.0),
		Vector3(58.0, 0.0, -150.0), Vector3(-122.0, 0.0, -120.0),
		Vector3(-54.0, 0.0, -154.0), Vector3(-22.0, 0.0, -162.0), Vector3(42.0, 0.0, -154.0), Vector3(82.0, 0.0, -132.0),
	]
	var i := 0
	for s in spots:
		_add_palm_tree(parent, s, i)
		i += 1

func _add_palm_tree(parent: Node3D, pos: Vector3, variant: int) -> void:
	# Procedural palm: a slim tapered curved trunk + a crown of drooping frond
	# planes. Matte foliage/bark — no emission, casts a long golden-hour shadow.
	var palm := Node3D.new()
	palm.name = "Palm_%d" % variant
	palm.position = pos
	palm.rotation_degrees = Vector3(0, float((variant * 47) % 360), 0)
	parent.add_child(palm)
	var bark := _matte(Color(0.34, 0.27, 0.18, 1.0), 0.9)
	var frond := _matte(Color(0.18, 0.34, 0.14, 1.0), 0.85)
	_add_box(palm, "PalmGroundCollar", Vector3(1.35, 0.08, 1.35), Vector3(0, 0.04, 0), _matte(Color(0.16, 0.11, 0.07, 1.0), 0.92))
	var trunk_h := 8.0 + float(variant % 3) * 1.4
	var segs := 6
	for ti in range(segs):
		var t := float(ti) / float(segs)
		var ty := t * trunk_h + trunk_h / float(segs) * 0.5
		var lean := sin(t * 1.2) * 0.7
		var seg := MeshInstance3D.new()
		seg.name = "PalmTrunk_%d" % ti
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34 * (1.0 - 0.4 * t)
		cm.bottom_radius = 0.40 * (1.0 - 0.4 * t)
		cm.height = trunk_h / float(segs) + 0.06
		cm.radial_segments = 8
		seg.mesh = cm
		seg.position = Vector3(lean, ty, 0)
		seg.material_override = bark
		palm.add_child(seg)
	var crown_y := trunk_h + 0.2
	var crown_x := sin(1.2) * 0.7
	for fi in range(7):
		var ang := float(fi) / 7.0 * TAU
		var frond_mi := MeshInstance3D.new()
		frond_mi.name = "PalmFrond_%d" % fi
		var bm := BoxMesh.new()
		bm.size = Vector3(3.6, 0.08, 0.7)
		frond_mi.mesh = bm
		frond_mi.position = Vector3(crown_x + cos(ang) * 1.6, crown_y - 0.2, sin(ang) * 1.6)
		frond_mi.rotation = Vector3(0, -ang, deg_to_rad(-22.0))
		frond_mi.material_override = frond
		palm.add_child(frond_mi)

# ── Reference-match city-capture dressing (AURORA_CAPTURE_MODE=city only) ──
# Everything below is staged exclusively for the deterministic "city" postcard so it
# closely matches the Los Santos golden-hour reference — a dominant wide multilane
# freeway in the lower third, a cluster of distinctive downtown landmark towers
# (cylindrical glass, stepped glass, a big dark-blue rounded tower, a banded white
# mid-rise), and a subtle anamorphic sun flare. None of it spawns during gameplay.

func _add_reference_capture_scene(parent: Node3D) -> void:
	var ref := Node3D.new()
	ref.name = "ReferenceCaptureAssetCity"
	parent.add_child(ref)
	# Ground cover goes down first so the freeway/buildings/props sit on a fully paved
	# metropolitan floor instead of the bare tan ground plane that dominated the old
	# side thirds of the frame.
	_add_city_kit_ground_cover(ref)
	_add_city_kit_freeway_foreground(ref)
	_add_capture_connected_road_network(ref)
	_add_city_kit_skyline_blocks(ref)
	_add_city_kit_dense_sides(ref)
	_add_city_kit_horizon_fill(ref)
	# City Builder tile districts complement (do not replace) the Commercial/Road kit
	# skyline & freeway: grid plazas/parks/side streets + low-rise blocks that break up
	# the flat foreground/plaza slabs QA flagged. Placed before street life so furniture
	# and traffic sit on top of the tiles.
	_add_city_builder_districts(ref)
	_add_city_kit_street_life(ref)
	_add_city_kit_street_detailing(ref)
	_add_sun_flare_capture_only()

func _add_city_kit_ground_cover(parent: Node3D) -> void:
	# Capture-only paved floor. The old city postcard exposed the bare tan ground
	# plane across the left/right foreground thirds; here a cool dark-asphalt street
	# slab fills the whole visible footprint, raised concrete sidewalks flank the
	# freeway where the buildings sit, a downtown plaza joins the freeway to the
	# skyline base, and worn paint/crosswalks break up the foreground. Everything is
	# flat non-building geometry (simple meshes + a few Road Kit pieces), so it stays
	# headless-safe and never reads as procedural skyline.
	var ground := Node3D.new()
	ground.name = "KenneyCityKit_GroundCover"
	parent.add_child(ground)
	# Cool, slightly desaturated asphalt so the lower frame reads as wet-free city
	# tarmac at golden hour rather than the warm desert-brown of the old ground plane.
	var street := _matte(Color(0.105, 0.110, 0.125, 1.0), 0.93)
	var sidewalk := _matte(Color(0.44, 0.43, 0.41, 1.0), 0.82)
	var kerb := _matte(Color(0.56, 0.55, 0.52, 1.0), 0.78)
	var plaza := _matte(Color(0.40, 0.395, 0.385, 1.0), 0.8)
	# One large street slab covering the entire camera footprint (top ~0.40, flush
	# with the Road Kit deck) so no ground plane shows around the freeway and blocks.
	# Sized to blanket the whole ground-plane footprint within the wide capture FOV so
	# neither the near corners nor the far-right horizon gap show bare tan; the distant
	# edge fades into the warm aerial fog instead of a hard brown band.
	_add_box(ground, "CaptureStreetFloor", Vector3(640.0, 0.5, 640.0), Vector3(0.0, 0.15, 30.0), street)
	# Low-contrast asphalt seams/wear over the giant slab. These are deliberately
	# geometric, not glowing: they break up the single-sheet look that QA caught while
	# keeping the base surface cheap and headless-safe.
	var asphalt_seam := _matte(Color(0.055, 0.058, 0.065, 1.0), 0.97)
	var asphalt_wear := _matte(Color(0.155, 0.150, 0.145, 1.0), 0.94)
	for si in range(13):
		var seam_z := -196.0 + float(si) * 23.0
		_add_box(ground, "CaptureAsphaltExpansion_%d" % si, Vector3(158.0, 0.035, 0.42), Vector3(0.0, 0.425, seam_z), asphalt_seam)
		if si % 2 == 0:
			_add_box(ground, "CaptureAsphaltWear_%d" % si, Vector3(32.0, 0.03, 1.8), Vector3(-18.0 + float(si % 5) * 8.0, 0.43, seam_z + 7.0), asphalt_wear)
	for sx in [-54.0, -36.0, 36.0, 54.0, 96.0, -96.0]:
		_add_box(ground, "CaptureLongPavementJoint_%d" % int(sx), Vector3(0.32, 0.035, 238.0), Vector3(sx, 0.426, -48.0), asphalt_seam)
	# Raised sidewalks flanking the freeway — the paved band the side blocks rise from.
	for side in [-1.0, 1.0]:
		_add_box(ground, "CaptureSidewalk_%d" % int(side), Vector3(58.0, 0.62, 168.0), Vector3(side * 65.0, 0.30, -72.0), sidewalk)
		# Inner kerb line where the sidewalk meets the freeway shoulder.
		_add_box(ground, "CaptureKerb_%d" % int(side), Vector3(0.7, 0.66, 168.0), Vector3(side * 37.0, 0.32, -72.0), kerb)
		# Far set-back sidewalk for the second building row.
		_add_box(ground, "CaptureSidewalkFar_%d" % int(side), Vector3(34.0, 0.6, 150.0), Vector3(side * 104.0, 0.29, -64.0), sidewalk)
		# Sidewalk slab joints + building-base shadow strips anchor the imported kit
		# facades. Without these, the pale blocks read as floating on a tan/pink void.
		for sj in range(9):
			var joint_z := -152.0 + float(sj) * 22.0
			_add_box(ground, "CaptureSidewalkJoint_%d_%d" % [int(side), sj], Vector3(58.0, 0.035, 0.22), Vector3(side * 65.0, 0.625, joint_z), asphalt_seam)
			_add_box(ground, "CaptureFarSidewalkJoint_%d_%d" % [int(side), sj], Vector3(34.0, 0.035, 0.22), Vector3(side * 104.0, 0.615, joint_z), asphalt_seam)
		_add_box(ground, "CaptureInnerBuildingContact_%d" % int(side), Vector3(5.5, 0.045, 178.0), Vector3(side * 49.5, 0.64, -66.0), asphalt_seam)
		_add_box(ground, "CaptureOuterBuildingContact_%d" % int(side), Vector3(6.0, 0.045, 178.0), Vector3(side * 88.0, 0.62, -60.0), asphalt_seam)
	# Downtown plaza joining the freeway head to the skyline base.
	_add_box(ground, "CapturePlaza", Vector3(150.0, 0.56, 46.0), Vector3(0.0, 0.27, 8.0), plaza)
	# Foreground crosswalk + worn paint on the near asphalt so the lower third reads
	# as a real road approach, not a flat slab.
	var paint := _matte(Color(0.50, 0.49, 0.45, 1.0), 0.86)
	for cx in range(-7, 8):
		_add_box(ground, "CaptureCross_%d" % cx, Vector3(1.5, 0.04, 6.0), Vector3(float(cx) * 3.7, 0.42, -168.0), paint)
	for lx in [-27.0, -9.0, 9.0, 27.0]:
		var zz := -196.0
		var di := 0
		while zz < -158.0:
			_add_box(ground, "CaptureApronDash_%d_%d" % [int(lx), di], Vector3(0.26, 0.04, 4.6), Vector3(lx, 0.42, zz), paint)
			zz += 9.0
			di += 1
	# A few Road Kit zebra crossings keep the cover asset-based at the freeway head.
	for zx in [-18.0, 0.0, 18.0]:
		_add_city_kit_road(ground, "road-crossing.glb", "CaptureCrossingTile_%d" % int(zx), Vector3(zx, 0.02, -6.0), 0.0, 18.0)

func _add_city_kit_dense_sides(parent: Node3D) -> void:
	# Two flanking rows of imported low/mid-rise kit blocks down each side of the
	# freeway, turning the empty side thirds into a continuous street canyon with real
	# depth layering. Inner row sits on the raised sidewalk facing the road; the taller
	# outer row reads behind it. All blocks stay outside the x=±36 freeway lanes.
	var blocks := Node3D.new()
	blocks.name = "KenneyCityKit_DenseSides"
	parent.add_child(blocks)
	for side in [-1, 1]:
		var sf := float(side)
		# Inner row: low-detail storefront blocks lining the sidewalk, z from the near
		# foreground up to the downtown base.
		for r in range(8):
			var z := -150.0 + float(r) * 21.0
			var asset := str(CITY_KIT_LOW_DETAIL_VARIANTS[(r * 2 + (0 if side < 0 else 5)) % CITY_KIT_LOW_DETAIL_VARIANTS.size()])
			var fp := 15.0 + float(r % 3) * 2.0
			var ys := 1.0 + float((r + side) % 4) * 0.4
			_add_city_kit_building(blocks, asset, "SideInner_%d_%d" % [side, r], Vector3(sf * (50.0 + float(r % 2) * 4.0), 0.0, z), fp, ys, sf * -6.0)
		# Outer row: taller mid-rise/commercial blocks set back behind the inner row.
		for r in range(6):
			var z := -138.0 + float(r) * 27.0
			var asset := str(CITY_KIT_MIDRISE_VARIANTS[(r * 3 + (1 if side < 0 else 8)) % CITY_KIT_MIDRISE_VARIANTS.size()])
			var fp := 17.0 + float(r % 3) * 2.0
			var ys := 1.7 + float((r * 2 + side) % 5) * 0.35
			_add_city_kit_building(blocks, asset, "SideOuter_%d_%d" % [side, r], Vector3(sf * (88.0 + float(r % 2) * 8.0), 0.0, z), fp, ys, sf * -4.0)

func _add_city_kit_road(parent: Node3D, asset_name: String, node_name: String, pos: Vector3, rot_y: float, target_size: float, y_offset: float = 0.0) -> Node3D:
	var holder := _instance_prop(CITY_KIT_ROAD_DIR + asset_name, "x", target_size, true)
	if holder == null:
		push_warning("City road kit asset failed: " + CITY_KIT_ROAD_DIR + asset_name)
		return null
	holder.name = node_name
	holder.position = pos + Vector3(0.0, y_offset, 0.0)
	holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(holder)
	return holder

func _add_city_kit_road_prop(parent: Node3D, asset_name: String, node_name: String, pos: Vector3, rot_y: float, fit_axis: String, target_size: float) -> Node3D:
	var holder := _instance_prop(CITY_KIT_ROAD_DIR + asset_name, fit_axis, target_size, true)
	if holder == null:
		push_warning("City road prop asset failed: " + CITY_KIT_ROAD_DIR + asset_name)
		return null
	holder.name = node_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(holder)
	return holder

func _add_city_kit_building(parent: Node3D, asset_name: String, node_name: String, pos: Vector3, footprint: float, vertical_scale: float, rot_y: float) -> Node3D:
	var holder := _instance_prop(CITY_KIT_BUILDING_DIR + asset_name, "x", footprint, true)
	if holder == null:
		push_warning("City building kit asset failed: " + CITY_KIT_BUILDING_DIR + asset_name)
		return null
	holder.name = node_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	# Keep the imported facade/window/awning geometry but stretch the Godot holder in
	# Y so the kit pieces form a GTA-style downtown skyline instead of identical toy
	# blocks. The source model is still the visible city asset; no BoxMesh skyline.
	holder.scale.y *= vertical_scale
	parent.add_child(holder)
	_apply_facade_texture_overlay(holder, abs(node_name.hash()), _facade_texture_index_for(node_name))
	return holder

# Apply textured PBR facade overlay panels to an imported Kenney GLB building holder so
# the toy-like kit pieces read as real glass/brick/concrete towers in the city postcard.
# Adds thin BoxMesh panels on the four vertical faces, each with a ShaderMaterial using
# the building_facade shader and one of the 5 preloaded PBR texture sets. Capture-mode only.
func _apply_facade_texture_overlay(holder: Node3D, building_seed: int, texture_index: int) -> void:
	if holder == null or _facade_albedo_textures.is_empty():
		return
	# Bounding box in holder-local space (identity start, descending through the model's
	# own transform) — the holder's Y stretch is applied on top, so panels placed here are
	# stretched consistently with the imported geometry.
	var acc: Array = [null, null]
	_accumulate_mesh_aabb(holder, Transform3D.IDENTITY, acc)
	if acc[0] == null:
		return
	var bmin: Vector3 = acc[0]
	var bmax: Vector3 = acc[1]
	var size: Vector3 = bmax - bmin
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var center := (bmin + bmax) * 0.5
	var tex_idx: int = clamp(texture_index, 0, _facade_albedo_textures.size() - 1)
	# Window grid derived from the building's footprint/height (deterministic per holder).
	var floors_val: int = int(clamp(size.y / 4.0, 4.0, 12.0))
	var windows_val: int = 3 + (abs(building_seed) % 4)
	# Bigger footprints need more tiling to keep window/material density readable, so scale
	# the base UV with the building footprint (2.0-6.0) instead of a flat 3.5-5.0.
	var footprint: float = max(size.x, size.z)
	var uv_s: float = clamp(2.0 + footprint * 0.18 + float(abs(building_seed) % 3) * 0.4, 2.0, 6.0)
	var uv_s2: float = uv_s * 2.7
	# Per-building UV offset breaks the visible grid repeat across neighbouring towers.
	var off_x: float = float(building_seed % 100) / 100.0
	var off_y: float = float((building_seed / 100) % 100) / 100.0
	# Second material set (next in the cycle) is blended in as detail to defeat tiling.
	var tex_idx2: int = (tex_idx + 1) % _facade_albedo_textures.size()
	# Window recess depth scales with building height; glass sets reflect the sky more.
	var window_depth_val: float = clamp(0.3 + size.y / 80.0, 0.3, 0.6)
	var glass_refl_val: float = (0.25 if tex_idx == 0 else 0.1 + float(tex_idx % 3) * 0.04)
	var pbr: Dictionary = FACADE_PBR_PROPS[tex_idx]
	var tint_r: float = 0.88 + float(abs(building_seed) % 5) * 0.02
	var tint_g: float = 0.87 + float(abs(building_seed / 7) % 4) * 0.015
	var tint_b: float = 0.82 + float(abs(building_seed / 13) % 3) * 0.02
	var albedo_tint := Color(tint_r, tint_g, tint_b, 1.0)
	# Panels are slightly shorter than the full height and dropped a touch so they cover the
	# facade glass without overlapping the roof cap, doors or awnings at the very edges.
	var thickness := 0.04
	var offset := 0.05
	var panel_h: float = size.y * 0.86
	var panel_cy: float = center.y - size.y * 0.04
	# Four vertical faces: +Z (front), -Z (back), +X, -X sides. Each gets its own panel so
	# every visible side reads as a textured facade, never a roof or floor.
	var faces := [
		{"size": Vector3(size.x * 0.94, panel_h, thickness), "pos": Vector3(center.x, panel_cy, bmax.z + offset)},
		{"size": Vector3(size.x * 0.94, panel_h, thickness), "pos": Vector3(center.x, panel_cy, bmin.z - offset)},
		{"size": Vector3(thickness, panel_h, size.z * 0.94), "pos": Vector3(bmax.x + offset, panel_cy, center.z)},
		{"size": Vector3(thickness, panel_h, size.z * 0.94), "pos": Vector3(bmin.x - offset, panel_cy, center.z)},
	]
	for i in range(faces.size()):
		var f: Dictionary = faces[i]
		var box := BoxMesh.new()
		box.size = f["size"]
		var panel := MeshInstance3D.new()
		panel.name = "FacadeTexturePanel_%d" % i
		panel.mesh = box
		panel.position = f["pos"]
		panel.set_meta("facade_texture_panel", true)
		panel.set_meta("facade_texture_index", tex_idx)
		var mat := ShaderMaterial.new()
		mat.shader = FACADE_SHADER
		mat.set_shader_parameter("building_seed", building_seed)
		mat.set_shader_parameter("floors", floors_val)
		mat.set_shader_parameter("windows_per_floor", windows_val)
		mat.set_shader_parameter("uv_scale", uv_s)
		mat.set_shader_parameter("uv_scale_2", uv_s2)
		mat.set_shader_parameter("uv_offset", Vector2(off_x, off_y))
		mat.set_shader_parameter("window_depth", window_depth_val)
		mat.set_shader_parameter("glass_reflectivity", glass_refl_val)
		mat.set_shader_parameter("albedo_tint", albedo_tint)
		mat.set_shader_parameter("lit_probability", 0.08)
		mat.set_shader_parameter("emission_energy", 0.4)
		mat.set_shader_parameter("albedo_tex", _facade_albedo_textures[tex_idx])
		mat.set_shader_parameter("albedo_tex_2", _facade_albedo_textures[tex_idx2])
		mat.set_shader_parameter("normal_tex", _facade_normal_textures[tex_idx])
		mat.set_shader_parameter("roughness_tex", _facade_roughness_textures[tex_idx])
		mat.set_shader_parameter("emission_tex", _facade_emission_textures[tex_idx])
		mat.set_shader_parameter("roughness_base", float(pbr.get("roughness", 0.5)))
		mat.set_shader_parameter("metallic_val", float(pbr.get("metallic", 0.14)))
		mat.set_shader_parameter("use_normal_map", true)
		mat.set_shader_parameter("roughness_tex_weight", 0.8)
		mat.set_shader_parameter("normal_map_scale", 0.8)
		panel.material_override = mat
		holder.add_child(panel)
	_add_building_greebles(holder, bmin, bmax, building_seed)
	holder.set_meta("facade_texture_pass", true)

# Add small procedural geometric details (ledges, roof units, parapets, antennas,
# entrance canopies) on top of an imported building so the boxy kit pieces gain
# secondary silhouette/shadow detail. Deterministic per building_seed; not every
# building gets every greeble. Children of `holder`, alongside the texture panels.
func _add_building_greebles(holder: Node3D, bmin: Vector3, bmax: Vector3, building_seed: int) -> void:
	var size: Vector3 = bmax - bmin
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var center := (bmin + bmax) * 0.5
	var seed: int = abs(building_seed)
	var floors_est: int = int(size.y / 3.5)
	var ledge_mat := _matte(Color(0.15, 0.15, 0.16, 1.0), 0.7, 0.3)
	# 1. Horizontal floor ledges across the front face for taller buildings.
	if floors_est >= 6:
		var fracs := [0.25, 0.5, 0.75]
		for li in range(fracs.size()):
			# Skip one band on some buildings so the spacing varies.
			if (seed / (li + 1)) % 5 == 0:
				continue
			var ly: float = bmin.y + size.y * float(fracs[li])
			_add_box(holder, "Greeble_Ledge_%d" % li,
				Vector3(size.x * 0.96, 0.15, 0.12),
				Vector3(center.x, ly, bmax.z + 0.06), ledge_mat)
	# 2. Roof HVAC units — 1-2 small boxes on top.
	var roof_units: int = 1 + (seed % 2)
	var hvac_mat := _matte(Color(0.25, 0.24, 0.22, 1.0), 0.8, 0.4)
	for ui in range(roof_units):
		var ox: float = (float((seed / (ui + 3)) % 100) / 100.0 - 0.5) * size.x * 0.4
		var oz: float = (float((seed / (ui + 5)) % 100) / 100.0 - 0.5) * size.z * 0.4
		_add_box(holder, "Greeble_RoofUnit_%d" % ui,
			Vector3(size.x * 0.2, 0.4, size.z * 0.2),
			Vector3(center.x + ox, bmax.y + 0.2, center.z + oz), hvac_mat)
	# 3. Roof edge parapet around the perimeter.
	_add_box(holder, "Greeble_Parapet_0",
		Vector3(size.x * 0.98, 0.3, 0.08),
		Vector3(center.x, bmax.y + 0.15, bmax.z + 0.02), ledge_mat)
	_add_box(holder, "Greeble_Parapet_1",
		Vector3(size.x * 0.98, 0.3, 0.08),
		Vector3(center.x, bmax.y + 0.15, bmin.z - 0.02), ledge_mat)
	_add_box(holder, "Greeble_Parapet_2",
		Vector3(0.08, 0.3, size.z * 0.98),
		Vector3(bmax.x + 0.02, bmax.y + 0.15, center.z), ledge_mat)
	_add_box(holder, "Greeble_Parapet_3",
		Vector3(0.08, 0.3, size.z * 0.98),
		Vector3(bmin.x - 0.02, bmax.y + 0.15, center.z), ledge_mat)
	# 4. Antenna/spire on tall buildings.
	if size.y > 20.0:
		var ax: float = (float(seed % 100) / 100.0 - 0.5) * size.x * 0.3
		_add_box(holder, "Greeble_Antenna",
			Vector3(0.08, 2.0, 0.08),
			Vector3(center.x + ax, bmax.y + 1.0, center.z),
			_matte(Color(0.1, 0.1, 0.1, 1.0), 0.4, 0.6))
	# 5. Entrance canopy on the front face at ground level (most buildings).
	if seed % 3 != 0:
		_add_box(holder, "Greeble_Canopy",
			Vector3(size.x * 0.3, 0.08, 0.6),
			Vector3(center.x, bmin.y + 1.5, bmin.z - 0.3),
			_matte(Color(0.12, 0.12, 0.13, 1.0), 0.6, 0.5))

# Deterministic facade texture set index for a building, derived from its node name so
# different buildings get different PBR sets (glass/concrete/brick/metal/commercial).
func _facade_texture_index_for(node_name: String) -> int:
	if _facade_albedo_textures.is_empty():
		return 0
	return abs(node_name.hash()) % _facade_albedo_textures.size()

func _add_city_kit_detail(parent: Node3D, asset_name: String, node_name: String, pos: Vector3, rot_y: float, fit_axis: String, target_size: float) -> Node3D:
	var holder := _instance_prop(CITY_KIT_BUILDING_DIR + asset_name, fit_axis, target_size, true)
	if holder == null:
		push_warning("City detail kit asset failed: " + CITY_KIT_BUILDING_DIR + asset_name)
		return null
	holder.name = node_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(holder)
	return holder

# ── Kenney Starter Kit City Builder tile districts (AURORA_CAPTURE_MODE=city only) ──
# These reuse the compact 1x1-unit CC0 tile GLBs to stamp grid-based plazas, parks,
# side streets and low-rise blocks around the freeway and skyline base. The tiles are
# real imported geometry auto-fitted by _instance_prop, so the foreground/plaza no
# longer reads as flat hand-placed slabs. Everything stays clear of the central freeway
# travel lanes (|x| < ~38) and is gated behind the capture-only reference scene.

func _add_city_builder_prop(parent: Node3D, asset_name: String, node_name: String, pos: Vector3, rot_y: float, target_size: float) -> Node3D:
	# All City Builder tiles/blocks are ~1 unit on X, so a single uniform x-fit keeps the
	# native proportions (no Y stretch) — pavement stays flat, buildings stay buildings.
	var holder := _instance_prop(CITY_BUILDER_DIR + asset_name, "x", target_size, true)
	if holder == null:
		push_warning("City builder asset failed: " + CITY_BUILDER_DIR + asset_name)
		return null
	holder.name = node_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0.0, rot_y, 0.0)
	parent.add_child(holder)
	# Only buildings get facade overlays — pavement, grass, road and other flat tiles stay
	# untouched (their names never contain "building"/"lowrise").
	if asset_name.contains("building") or node_name.to_lower().contains("lowrise"):
		_apply_facade_texture_overlay(holder, abs(node_name.hash()), _facade_texture_index_for(node_name))
	return holder

func _add_city_builder_districts(parent: Node3D) -> void:
	var district := Node3D.new()
	district.name = "KenneyCityBuilder_TileDistricts"
	parent.add_child(district)
	_add_city_builder_skyline_plaza(district)
	_add_city_builder_foreground_blocks(district)

func _add_city_builder_skyline_plaza(parent: Node3D) -> void:
	# A tiled downtown plaza/park at the foot of the skyline (north of where the freeway
	# ends at z=-10), joining the freeway head to the tower cluster. Pavement grid with a
	# central fountain, flanking tree parks, and a few low-rise blocks facing the freeway.
	var plaza := Node3D.new()
	plaza.name = "CityBuilderSkylinePlaza"
	parent.add_child(plaza)
	var tile := 14.0
	var y := 0.57  # just above the CapturePlaza slab top (~0.55)
	# Central paved plaza grid. z stays >= 2 so it never reaches the freeway travel lanes.
	var cols := [-42.0, -28.0, -14.0, 0.0, 14.0, 28.0, 42.0]
	var rows := [4.0, 18.0]
	for ri in range(rows.size()):
		for ci in range(cols.size()):
			var cx: float = cols[ci]
			# Central fountain anchors the plaza; everything else is plain pavement.
			if ci == 3 and ri == 0:
				_add_city_builder_prop(plaza, "pavement-fountain.glb", "PlazaFountain", Vector3(cx, y, rows[ri]), 0.0, tile)
			else:
				_add_city_builder_prop(plaza, "pavement.glb", "PlazaPave_%d_%d" % [ri, ci], Vector3(cx, y, rows[ri]), 0.0, tile)
	# Flanking tree parks just outside the paved core (well clear of the freeway lanes).
	for side in [-1, 1]:
		var sf := float(side)
		for pi in range(3):
			var px := sf * (60.0 + float(pi % 2) * 14.0)
			var pz := 2.0 + float(pi) * 14.0
			var grass := str(CITY_BUILDER_GRASS_VARIANTS[(pi + (0 if side < 0 else 1)) % CITY_BUILDER_GRASS_VARIANTS.size()])
			_add_city_builder_prop(plaza, grass, "PlazaPark_%d_%d" % [side, pi], Vector3(px, y, pz), float(pi) * 30.0, tile)
		# Low-rise blocks lining the plaza edge, facing the freeway/camera (south).
		for bi in range(2):
			var asset := str(CITY_BUILDER_LOWRISE_VARIANTS[(bi + (1 if side < 0 else 3)) % CITY_BUILDER_LOWRISE_VARIANTS.size()])
			var bx := sf * (34.0 + float(bi) * 12.0)
			var bz := 16.0
			_add_city_builder_prop(plaza, asset, "PlazaLowrise_%d_%d" % [side, bi], Vector3(bx, y, bz), 180.0 + sf * 6.0, 13.0)

func _add_city_builder_foreground_blocks(parent: Node3D) -> void:
	# The near foreground flank thirds (beyond the freeway shoulders) were the flat
	# asphalt slabs QA flagged. Each side gets a small city-builder block: a paved/park
	# grid, an east-west side street leading off the freeway, and low-rise buildings — so
	# the lower frame reads as real city blocks. All x >= 50, clear of the freeway lanes.
	var blocks := Node3D.new()
	blocks.name = "CityBuilderForegroundBlocks"
	parent.add_child(blocks)
	var tile := 13.0
	var y := 0.42  # just above the CaptureStreetFloor asphalt top (~0.40)
	var cols := [52.0, 65.0, 78.0, 91.0]
	for side in [-1, 1]:
		var sf := float(side)
		# Side street (east-west) leading away from the freeway shoulder.
		for ci in range(cols.size()):
			var sx: float = sf * cols[ci]
			var road := "road-straight.glb"
			if ci == 0:
				road = "road-intersection.glb"
			elif ci == cols.size() - 1:
				road = "road-corner.glb"
			elif ci == 2:
				road = "road-straight-lightposts.glb"
			_add_city_builder_prop(blocks, road, "FgStreet_%d_%d" % [side, ci], Vector3(sx, y, -171.0), 90.0, tile)
		# North strip (toward the skyline): paved plaza apron.
		for ci in range(cols.size()):
			var sx: float = sf * cols[ci]
			_add_city_builder_prop(blocks, "pavement.glb", "FgPaveN_%d_%d" % [side, ci], Vector3(sx, y, -158.0), 0.0, tile)
		# South strip (nearest camera): parks + low-rise blocks on a paved base.
		for ci in range(cols.size()):
			var sx: float = sf * cols[ci]
			_add_city_builder_prop(blocks, "pavement.glb", "FgPaveS_%d_%d" % [side, ci], Vector3(sx, y, -184.0), 0.0, tile)
			if ci % 2 == 0:
				var asset := str(CITY_BUILDER_LOWRISE_VARIANTS[(ci + (0 if side < 0 else 2)) % CITY_BUILDER_LOWRISE_VARIANTS.size()])
				_add_city_builder_prop(blocks, asset, "FgLowrise_%d_%d" % [side, ci], Vector3(sx, y, -184.0), float(side) * -6.0, 11.5)
			else:
				var grass := str(CITY_BUILDER_GRASS_VARIANTS[(ci + (1 if side < 0 else 0)) % CITY_BUILDER_GRASS_VARIANTS.size()])
				_add_city_builder_prop(blocks, grass, "FgPark_%d_%d" % [side, ci], Vector3(sx, y, -184.0), float(ci) * 25.0, tile)

func _add_capture_traffic_destination(parent: Node3D, key: String, display_name: String, pos: Vector3, color: Color) -> Node3D:
	var dest := Node3D.new()
	dest.name = "TrafficDestination_" + key
	dest.position = pos
	dest.set_meta("destination_name", display_name)
	parent.add_child(dest)
	_add_box(dest, "DestinationPad", Vector3(8.0, 0.18, 8.0), Vector3(0.0, 0.09, 0.0), _matte(Color(color.r * 0.45, color.g * 0.45, color.b * 0.45, 1.0), 0.86, 0.0))
	_add_box(dest, "DestinationSignPost", Vector3(0.35, 3.4, 0.35), Vector3(0.0, 1.7, -3.2), _matte(Color(0.22, 0.22, 0.24, 1.0), 0.55, 0.5))
	_add_box(dest, "DestinationSignPanel", Vector3(7.4, 2.0, 0.35), Vector3(0.0, 3.55, -3.2), _matte(color, 0.62, 0.08))
	var label := Label3D.new()
	label.name = "DestinationLabel"
	label.text = display_name
	label.position = Vector3(0.0, 3.65, -3.42)
	label.font_size = 42
	label.pixel_size = 0.034
	label.modulate = Color(0.96, 0.96, 0.88, 1.0)
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.86)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dest.add_child(label)
	return dest

func _add_capture_connected_road_network(parent: Node3D) -> void:
	# The original postcard freeway stopped at the skyline plaza, so the road read as a
	# movie-set stub. This node extends that imported Road Kit freeway into a small but
	# legible city road graph: a downtown continuation, a crosstown arterial, foreground
	# side streets, signed destinations, and traffic cars assigned to routes.
	var network := Node3D.new()
	network.name = "ReferenceCaptureRoadNetwork"
	parent.add_child(network)
	var tile := 18.0
	var freeway_y := 0.58
	var city_y := 0.44
	var lane_xs := [-27.0, -9.0, 9.0, 27.0]
	# Continue the four freeway lanes past the old z=-10 visual end so they visibly
	# feed downtown rather than terminating at the plaza.
	for z_val in [8.0, 26.0, 44.0, 62.0]:
		var zf := float(z_val)
		for x_val in lane_xs:
			var xf := float(x_val)
			var asset := "road-straight.glb"
			if zf == 8.0 or zf == 62.0:
				asset = "road-crossroad-line.glb"
			_add_city_kit_road(network, asset, "RoadRoute_Downtown_%d_%d" % [int(xf), int(zf)], Vector3(xf, freeway_y, zf), 0.0, tile)
	# A signed east-west arterial at the freeway head connects to district destinations.
	for ix in range(-7, 8):
		var x := float(ix) * tile
		var asset := "road-straight.glb"
		if ix >= -2 and ix <= 2:
			asset = "road-intersection.glb"
		_add_city_kit_road(network, asset, "RoadRoute_Crosstown_%d" % ix, Vector3(x, freeway_y, 8.0), 90.0, tile)
	# Outer collector spines connect the foreground side streets to the crosstown road.
	for side in [-1, 1]:
		var sf := float(side)
		var prefix := "Hillview" if side < 0 else "Airport"
		for zi in range(10):
			var z := -154.0 + float(zi) * tile
			var asset := "road-straight.glb"
			if zi == 0 or zi == 9:
				asset = "road-intersection.glb"
			_add_city_kit_road(network, asset, "RoadRoute_%sSpine_%d" % [prefix, zi], Vector3(sf * 126.0, city_y, z), 0.0, tile)
		# Foreground arterial branching away from the freeway into the side districts.
		for xi in range(3, 9):
			var x := sf * float(xi) * tile
			var road := "road-straight.glb"
			if xi == 3 or xi == 8:
				road = "road-intersection.glb"
			elif xi == 5:
				road = "road-straight-lightposts.glb"
			_add_city_builder_prop(network, road, "RoadRoute_%sForeground_%d" % [prefix, xi], Vector3(x, city_y, -171.0), 90.0, 13.5)
		# A visible corner/ramp pair at the freeway shoulder makes the side street read as
		# physically joined to the central carriageway, not a detached decorative strip.
		_add_city_builder_prop(network, "road-corner.glb", "RoadRoute_%sRampCorner" % prefix, Vector3(sf * 39.0, city_y, -154.0), 0.0 if side < 0 else 90.0, 13.5)
		_add_city_builder_prop(network, "road-split.glb", "RoadRoute_%sRampSplit" % prefix, Vector3(sf * 45.0, city_y, -171.0), 90.0, 13.5)
	# Destination anchors with labels/metadata for both visual readability and tests.
	_add_capture_traffic_destination(network, "DowntownCore", "Downtown Core", Vector3(0.0, freeway_y, 78.0), Color(0.18, 0.34, 0.78, 1.0))
	_add_capture_traffic_destination(network, "HarborFreight", "Harbor Freight", Vector3(144.0, city_y, 8.0), Color(0.12, 0.44, 0.34, 1.0))
	_add_capture_traffic_destination(network, "AirportConnector", "Airport Connector", Vector3(144.0, city_y, -171.0), Color(0.50, 0.34, 0.12, 1.0))
	_add_capture_traffic_destination(network, "HillviewResidential", "Hillview Residential", Vector3(-144.0, city_y, 8.0), Color(0.42, 0.26, 0.58, 1.0))
	_add_city_kit_road_prop(network, "sign-highway-wide.glb", "DestinationSign_DowntownHarbor", Vector3(-22.0, 0.55, -6.0), -4.0, "y", 8.0)
	_add_city_kit_road_prop(network, "sign-highway-detailed.glb", "DestinationSign_AirportHillview", Vector3(24.0, 0.55, -28.0), 8.0, "y", 7.3)
	_add_capture_visible_foreground_junction(network)
	_add_capture_destination_traffic(network)

func _add_capture_wayfinding_sign(parent: Node3D, sign_name: String, text: String, pos: Vector3, color: Color) -> Node3D:
	var sign := Node3D.new()
	sign.name = sign_name
	sign.position = pos
	parent.add_child(sign)
	_add_box(sign, "PostLeft", Vector3(0.24, 3.0, 0.24), Vector3(-3.2, 1.5, 0.0), _matte(Color(0.18, 0.18, 0.20, 1.0), 0.55, 0.4))
	_add_box(sign, "PostRight", Vector3(0.24, 3.0, 0.24), Vector3(3.2, 1.5, 0.0), _matte(Color(0.18, 0.18, 0.20, 1.0), 0.55, 0.4))
	_add_box(sign, "Panel", Vector3(8.8, 2.0, 0.32), Vector3(0.0, 3.1, 0.0), _matte(color, 0.62, 0.08))
	var label := Label3D.new()
	label.name = "WayfindingLabel"
	label.text = text
	label.position = Vector3(0.0, 3.16, -0.23)
	label.font_size = 36
	label.pixel_size = 0.032
	label.modulate = Color(0.98, 0.96, 0.84, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.88)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.add_child(label)
	return sign

func _add_capture_visible_foreground_junction(parent: Node3D) -> void:
	# Put the destination split in the part of the city postcard the camera clearly sees.
	# This keeps the road from reading as a single dead-end canyon: cars can visibly peel
	# left/right toward Hillview, Airport and Harbor while through-traffic continues north.
	var tile := 18.0
	var y := 0.70
	var z := -118.0
	for ix in range(-7, 8):
		var asset := "road-straight.glb"
		if ix >= -2 and ix <= 2:
			asset = "road-crossroad-line.glb"
		elif ix == -7 or ix == 7:
			asset = "road-end-round.glb"
		_add_city_kit_road(parent, asset, "RoadRoute_VisibleJunction_%d" % ix, Vector3(float(ix) * tile, y, z), 90.0, tile)
	# Dark asphalt underlay and lane-paint arrows make the cross-street visible even when
	# the imported road tiles are partially hidden by the wide freeway lanes.
	var asphalt := _matte(Color(0.045, 0.046, 0.050, 1.0), 0.94, 0.0)
	var white := _matte(Color(0.55, 0.54, 0.50, 1.0), 0.88, 0.0)
	var yellow := _matte(Color(0.50, 0.38, 0.10, 1.0), 0.86, 0.0)
	_add_box(parent, "RoadRoute_VisibleJunction_Asphalt", Vector3(260.0, 0.035, 9.5), Vector3(0.0, y + 0.08, z), asphalt)
	for x_val in [-96.0, -72.0, -48.0, 48.0, 72.0, 96.0]:
		_add_box(parent, "RoadRoute_VisibleJunction_LaneDash_%d" % int(x_val), Vector3(8.5, 0.04, 0.42), Vector3(x_val, y + 0.13, z), white)
	_add_box(parent, "RoadRoute_VisibleJunction_CenterYellow", Vector3(248.0, 0.04, 0.32), Vector3(0.0, y + 0.14, z - 2.3), yellow)
	_add_box(parent, "RoadRoute_VisibleAirportArrowShaft", Vector3(16.0, 0.04, 0.55), Vector3(62.0, y + 0.16, z + 2.2), white)
	_add_box(parent, "RoadRoute_VisibleAirportArrowHeadA", Vector3(5.5, 0.04, 0.55), Vector3(72.0, y + 0.17, z + 3.4), white)
	_add_box(parent, "RoadRoute_VisibleAirportArrowHeadB", Vector3(5.5, 0.04, 0.55), Vector3(72.0, y + 0.17, z + 1.0), white)
	_add_box(parent, "RoadRoute_VisibleHillviewArrowShaft", Vector3(16.0, 0.04, 0.55), Vector3(-62.0, y + 0.16, z + 2.2), white)
	_add_box(parent, "RoadRoute_VisibleHillviewArrowHeadA", Vector3(5.5, 0.04, 0.55), Vector3(-72.0, y + 0.17, z + 3.4), white)
	_add_box(parent, "RoadRoute_VisibleHillviewArrowHeadB", Vector3(5.5, 0.04, 0.55), Vector3(-72.0, y + 0.17, z + 1.0), white)
	_add_capture_wayfinding_sign(parent, "TrafficDestinationSign_AirportHarbor", "AIRPORT / HARBOR  →", Vector3(54.0, y + 0.02, z - 7.0), Color(0.10, 0.28, 0.36, 1.0))
	_add_capture_wayfinding_sign(parent, "TrafficDestinationSign_Hillview", "←  HILLVIEW", Vector3(-54.0, y + 0.02, z - 7.0), Color(0.32, 0.20, 0.44, 1.0))
	var right_route := [Vector3(9.0, y + 0.05, -154.0), Vector3(9.0, y + 0.05, z), Vector3(54.0, y + 0.05, z), Vector3(126.0, y + 0.05, z), Vector3(126.0, y + 0.05, -171.0), Vector3(54.0, y + 0.05, -171.0), Vector3(9.0, y + 0.05, -154.0)]
	var left_route := [Vector3(-9.0, y + 0.05, -154.0), Vector3(-9.0, y + 0.05, z), Vector3(-54.0, y + 0.05, z), Vector3(-126.0, y + 0.05, z), Vector3(-126.0, y + 0.05, -171.0), Vector3(-54.0, y + 0.05, -171.0), Vector3(-9.0, y + 0.05, -154.0)]
	for i in range(4):
		_add_routed_traffic_car(parent, "RoutedTrafficCar_VisibleAirport_%d" % i, right_route, "Airport Connector", (i + 1) % CAR_VARIANTS.size(), 9.5, 0.17 + float(i) * 0.16)
		_add_routed_traffic_car(parent, "RoutedTrafficCar_VisibleHillview_%d" % i, left_route, "Hillview Residential", (i + 2) % CAR_VARIANTS.size(), 8.8, 0.17 + float(i) * 0.16)
	_add_capture_overhead_destination_gantry(parent)

func _add_capture_overhead_destination_gantry(parent: Node3D) -> void:
	# Large near-camera gantry: unlike the imported highway-sign props, this text is
	# intentionally oversized for screenshot readability at 1152px wide.
	var gantry := Node3D.new()
	gantry.name = "TrafficDestinationSign_MainGantry"
	gantry.position = Vector3(0.0, 0.0, -142.0)
	parent.add_child(gantry)
	var metal := _matte(Color(0.18, 0.18, 0.20, 1.0), 0.55, 0.4)
	var panel_mat := _matte(Color(0.05, 0.22, 0.30, 1.0), 0.62, 0.08)
	_add_box(gantry, "GantryPostL", Vector3(0.42, 8.2, 0.42), Vector3(-39.0, 4.1, 0.0), metal)
	_add_box(gantry, "GantryPostR", Vector3(0.42, 8.2, 0.42), Vector3(39.0, 4.1, 0.0), metal)
	_add_box(gantry, "GantryBeam", Vector3(82.0, 0.55, 0.55), Vector3(0.0, 8.2, 0.0), metal)
	_add_box(gantry, "GantryPanel", Vector3(72.0, 4.4, 0.36), Vector3(0.0, 7.0, -0.36), panel_mat)
	var label := Label3D.new()
	label.name = "MainGantryLabel"
	label.text = "← HILLVIEW    DOWNTOWN ↑    AIRPORT / HARBOR →"
	label.position = Vector3(0.0, 7.1, -0.70)
	label.font_size = 86
	label.pixel_size = 0.058
	label.modulate = Color(0.98, 0.96, 0.82, 1.0)
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.90)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gantry.add_child(label)

func _add_capture_destination_traffic(parent: Node3D) -> void:
	var y := 0.64
	var routes := [
		{
			"destination": "Downtown Core",
			"speed": 12.0,
			"points": [Vector3(-9.0, y, -190.0), Vector3(-9.0, y, -154.0), Vector3(-9.0, y, -82.0), Vector3(-9.0, y, 8.0), Vector3(-9.0, y, 70.0), Vector3(9.0, y, 70.0), Vector3(9.0, y, 8.0), Vector3(9.0, y, -82.0), Vector3(9.0, y, -154.0), Vector3(9.0, y, -190.0)],
		},
		{
			"destination": "Harbor Freight",
			"speed": 10.5,
			"points": [Vector3(27.0, y, -188.0), Vector3(27.0, y, -154.0), Vector3(45.0, y, -171.0), Vector3(126.0, y, -171.0), Vector3(126.0, y, -82.0), Vector3(126.0, y, 8.0), Vector3(144.0, y, 8.0), Vector3(72.0, y, 8.0), Vector3(27.0, y, 8.0), Vector3(27.0, y, -154.0)],
		},
		{
			"destination": "Airport Connector",
			"speed": 11.0,
			"points": [Vector3(9.0, y, 60.0), Vector3(9.0, y, 8.0), Vector3(45.0, y, 8.0), Vector3(126.0, y, 8.0), Vector3(126.0, y, -82.0), Vector3(126.0, y, -171.0), Vector3(144.0, y, -171.0), Vector3(90.0, y, -171.0), Vector3(45.0, y, -171.0), Vector3(9.0, y, -154.0), Vector3(9.0, y, 8.0)],
		},
		{
			"destination": "Hillview Residential",
			"speed": 9.5,
			"points": [Vector3(-27.0, y, -186.0), Vector3(-27.0, y, -154.0), Vector3(-45.0, y, -171.0), Vector3(-126.0, y, -171.0), Vector3(-126.0, y, -82.0), Vector3(-126.0, y, 8.0), Vector3(-144.0, y, 8.0), Vector3(-72.0, y, 8.0), Vector3(-27.0, y, 8.0), Vector3(-27.0, y, -154.0)],
		},
	]
	var car_i := 0
	for ri in range(routes.size()):
		var route: Dictionary = routes[ri]
		var points: Array = route.get("points", []) as Array
		var destination := str(route.get("destination", "Downtown Core"))
		var speed := float(route.get("speed", 10.0))
		for slot in range(3):
			var frac := (float(slot) / 3.0) + float(ri) * 0.07
			_add_routed_traffic_car(parent, "RoutedTrafficCar_%02d_%s" % [car_i, destination.replace(" ", "")], points, destination, (ri + slot) % CAR_VARIANTS.size(), speed, frac)
			car_i += 1

func _add_city_kit_freeway_foreground(parent: Node3D) -> void:
	# City Kit Roads replaces the old handmade freeway boxes: four parallel tiled
	# road strips, an asset overpass, bridge pillars, highway signs, barriers and
	# construction props. This keeps the showcase city model-based, not procedural.
	var freeway := Node3D.new()
	freeway.name = "KenneyCityKit_FreewayForeground"
	parent.add_child(freeway)
	var tile_size := 18.0
	var lane_xs := [-27.0, -9.0, 9.0, 27.0]
	var zs := [-154.0, -136.0, -118.0, -100.0, -82.0, -64.0, -46.0, -28.0, -10.0]
	for zi in range(zs.size()):
		for xi in range(lane_xs.size()):
			var road_asset := "road-straight.glb"
			if xi == 0 or xi == lane_xs.size() - 1:
				road_asset = "road-straight-barrier.glb"
			if zi == 0:
				road_asset = "road-crossroad-line.glb"
			elif zi == 2 and (xi == 1 or xi == 2):
				road_asset = "road-side-entry.glb"
			_add_city_kit_road(freeway, road_asset, "FreewayTile_%d_%d" % [xi, zi], Vector3(float(lane_xs[xi]), 0.02, float(zs[zi])), 0.0, tile_size)
	# Asset-built lateral overpass crossing the foreground freeway.
	for xi in range(-4, 5):
		var asset := "road-bridge.glb" if xi >= -2 and xi <= 2 else "road-straight-barrier.glb"
		_add_city_kit_road(freeway, asset, "FreewayOverpass_%d" % xi, Vector3(float(xi) * tile_size, 0.0, -57.0), 90.0, tile_size, 5.4)
	for px in [-58.0, -28.0, 0.0, 28.0, 58.0]:
		_add_city_kit_road_prop(freeway, "bridge-pillar-wide.glb", "OverpassPillar_%d" % int(px), Vector3(px, 0.04, -57.0), 0.0, "y", 5.4)
	# Curved/sloped ramps give the foreground the stacked-interchange read of the reference.
	_add_city_kit_road(freeway, "road-slant-high.glb", "RampLeftHigh", Vector3(-75.0, 0.0, -75.0), 0.0, tile_size, 2.6)
	_add_city_kit_road(freeway, "road-slant-high-barrier.glb", "RampRightHigh", Vector3(75.0, 0.0, -75.0), 180.0, tile_size, 2.6)
	_add_city_kit_road(freeway, "road-slant-curve.glb", "RampLeftCurve", Vector3(-75.0, 0.0, -93.0), 0.0, tile_size, 1.2)
	_add_city_kit_road(freeway, "road-slant-curve-barrier.glb", "RampRightCurve", Vector3(75.0, 0.0, -93.0), 180.0, tile_size, 1.2)
	_add_city_kit_road_prop(freeway, "sign-highway-wide.glb", "HighwaySignNear", Vector3(-20.0, 0.0, -120.0), 0.0, "y", 8.2)
	_add_city_kit_road_prop(freeway, "sign-highway-detailed.glb", "HighwaySignFar", Vector3(22.0, 0.0, -37.0), 0.0, "y", 7.2)
	for i in range(8):
		var side := -1.0 if i % 2 == 0 else 1.0
		var px := side * (35.0 + float(i % 3) * 5.0)
		var pz := -150.0 + float(i) * 17.0
		_add_city_kit_road_prop(freeway, "construction-cone.glb", "FreewayCone_%d" % i, Vector3(px, 0.0, pz), float(i) * 35.0, "y", 1.0)
		if i % 3 == 0:
			_add_city_kit_road_prop(freeway, "construction-barrier.glb", "FreewayBarrierAsset_%d" % i, Vector3(px + side * 2.5, 0.0, pz + 3.0), 90.0, "x", 3.0)
	_add_city_kit_freeway_markings(freeway)

func _add_city_kit_freeway_markings(parent: Node3D) -> void:
	# Thin paint-only helpers over the imported Road Kit deck. The road geometry stays
	# model-based; these make the lanes read at screenshot distance where the low-poly
	# road material alone can collapse into a pale slab.
	var white := _matte(Color(0.50, 0.49, 0.45, 1.0), 0.88)
	var yellow := _matte(Color(0.44, 0.35, 0.10, 1.0), 0.86)
	for ex in [-35.5, 35.5]:
		_add_box(parent, "AssetFwyEdgePaint_%d" % int(ex), Vector3(0.35, 0.035, 142.0), Vector3(ex, 0.44, -82.0), white)
	for lx in [-18.0, 0.0, 18.0]:
		var zz := -151.0
		var idx := 0
		while zz < -12.0:
			_add_box(parent, "AssetFwyDash_%d_%d" % [int(lx), idx], Vector3(0.26, 0.035, 4.8), Vector3(lx, 0.45, zz), white if lx != 0.0 else yellow)
			zz += 9.0
			idx += 1
	for spec in [[-27.0, -134.0], [-9.0, -104.0], [9.0, -122.0], [27.0, -88.0]]:
		_add_lane_arrow(parent, Vector3(float(spec[0]), 0.45, float(spec[1])))

func _add_city_kit_skyline_blocks(parent: Node3D) -> void:
	var skyline := Node3D.new()
	skyline.name = "KenneyCityKit_DowntownSkyline"
	parent.add_child(skyline)
	var hero_specs := [
		["building-skyscraper-d.glb", -84.0, 34.0, 23.0, 1.45, -8.0],
		["building-skyscraper-b.glb", -55.0, 68.0, 19.0, 1.55, 6.0],
		["building-skyscraper-e.glb", -22.0, 88.0, 18.0, 1.35, -4.0],
		["building-skyscraper-c.glb", 14.0, 76.0, 17.0, 1.30, 3.0],
		["building-skyscraper-a.glb", 49.0, 62.0, 16.0, 1.42, -6.0],
		["building-skyscraper-b.glb", 76.0, 92.0, 18.0, 1.50, 7.0],
	]
	for i in range(hero_specs.size()):
		var s: Array = hero_specs[i]
		_add_city_kit_building(skyline, str(s[0]), "HeroAssetTower_%d" % i, Vector3(float(s[1]), 0.0, float(s[2])), float(s[3]), float(s[4]), float(s[5]))
	# Dense mid-rise blocks in front and between hero towers. Hand-placed, not grid-random.
	var mid_specs := [
		[-102.0, 78.0, 15.0, 2.0, -10.0], [-72.0, 104.0, 13.0, 2.3, 8.0],
		[-40.0, 118.0, 14.0, 2.5, -4.0], [-8.0, 126.0, 15.0, 2.2, 6.0],
		[24.0, 114.0, 13.0, 2.4, -9.0], [56.0, 106.0, 14.0, 2.1, 5.0],
		[94.0, 76.0, 15.0, 2.0, -6.0], [-118.0, 34.0, 14.0, 1.7, 2.0],
		[112.0, 38.0, 14.0, 1.8, -3.0], [-52.0, 22.0, 13.0, 1.6, 0.0],
		[45.0, 24.0, 13.0, 1.7, 0.0], [-18.0, 36.0, 12.0, 1.5, 4.0],
		[18.0, 40.0, 12.0, 1.5, -4.0],
	]
	for i in range(mid_specs.size()):
		var s: Array = mid_specs[i]
		var asset := str(CITY_KIT_MIDRISE_VARIANTS[i % CITY_KIT_MIDRISE_VARIANTS.size()])
		_add_city_kit_building(skyline, asset, "MidriseAssetBlock_%d" % i, Vector3(float(s[0]), 0.0, float(s[1])), float(s[2]), float(s[3]), float(s[4]))
	# Low foreground city blocks along the freeway shoulders cover the empty ground.
	for side in [-1, 1]:
		for row in range(6):
			var asset := str(CITY_KIT_LOW_DETAIL_VARIANTS[(row + (0 if side < 0 else 7)) % CITY_KIT_LOW_DETAIL_VARIANTS.size()])
			var x := float(side) * (52.0 + float(row % 2) * 12.0)
			var z := -132.0 + float(row) * 29.0
			_add_city_kit_building(skyline, asset, "FreewayShoulderBlock_%d_%d" % [side, row], Vector3(x, 0.0, z), 16.0 + float(row % 3) * 2.0, 1.15 + float(row % 3) * 0.35, float(side) * 4.0)
	_add_city_kit_facade_details(skyline)

func _add_city_kit_facade_details(parent: Node3D) -> void:
	# Visible imported commercial-kit accessories at street level keep the postcard
	# from reading as bare stretched prisms: awnings, overhangs, cafe parasols and
	# small storefront color accents along the freeway-facing blocks.
	var awnings := [
		["detail-awning-wide.glb", -64.0, -124.0, 0.0, 6.0],
		["detail-overhang-wide.glb", 64.0, -96.0, 180.0, 7.0],
		["detail-awning.glb", -52.0, -65.0, 0.0, 4.4],
		["detail-overhang.glb", 52.0, -38.0, 180.0, 4.8],
		["detail-awning-wide.glb", -118.0, 31.0, 90.0, 5.6],
		["detail-overhang-wide.glb", 112.0, 35.0, -90.0, 6.4],
	]
	for i in range(awnings.size()):
		var a: Array = awnings[i]
		_add_city_kit_detail(parent, str(a[0]), "ImportedStorefrontDetail_%d" % i, Vector3(float(a[1]), 3.2, float(a[2])), float(a[3]), "x", float(a[4]))
	for i in range(6):
		var asset := "detail-parasol-a.glb" if i % 2 == 0 else "detail-parasol-b.glb"
		var x := -38.0 + float(i) * 15.0
		var z := -18.0 + float(i % 3) * 14.0
		_add_city_kit_detail(parent, asset, "ImportedSidewalkParasol_%d" % i, Vector3(x, 0.0, z), float(i) * 27.0, "y", 3.2)

func _add_city_kit_distant_skyline(parent: Node3D) -> void:
	var far := Node3D.new()
	far.name = "KenneyCityKit_DistantSkyline"
	parent.add_child(far)
	for i in range(-9, 10):
		var idx := absi(i * 3 + 11) % CITY_KIT_LOW_DETAIL_VARIANTS.size()
		var x := float(i) * 24.0
		var z := 178.0 + float(absi(i) % 3) * 11.0
		var footprint := 18.0 + float(absi(i) % 4) * 2.0
		var yscale := 1.1 + float(absi(i * 5) % 4) * 0.22
		_add_city_kit_building(far, str(CITY_KIT_LOW_DETAIL_VARIANTS[idx]), "FarAssetSkyline_%d" % i, Vector3(x, 0.0, z), footprint, yscale, float(i % 3) * 4.0)
	for i in range(-5, 6):
		var idx := absi(i * 7 + 2) % CITY_KIT_SKYSCRAPER_VARIANTS.size()
		var x := float(i) * 42.0
		var z := 220.0 + float(absi(i) % 2) * 16.0
		_add_city_kit_building(far, str(CITY_KIT_SKYSCRAPER_VARIANTS[idx]), "FarAssetTower_%d" % i, Vector3(x, 0.0, z), 13.0, 1.1 + float(absi(i) % 3) * 0.18, float(i % 2) * 5.0)

func _add_city_kit_street_life(parent: Node3D) -> void:
	var life := Node3D.new()
	life.name = "KenneyCityKit_StreetLife"
	parent.add_child(life)
	var car_specs := [
		[-18.0, -143.0, 180.0, 0], [-8.0, -116.0, 180.0, 1], [9.0, -134.0, 0.0, 2],
		[27.0, -96.0, 0.0, 1], [-27.0, -72.0, 180.0, 2], [8.0, -42.0, 0.0, 0],
		[54.0, -16.0, 90.0, 1], [-56.0, 8.0, -90.0, 2],
	]
	for i in range(car_specs.size()):
		var s: Array = car_specs[i]
		_add_car(life, "AssetTrafficCar_%d" % i, Vector3(float(s[0]), 0.0, float(s[1])), float(s[2]), int(s[3]) % CAR_VARIANTS.size())
	for i in range(7):
		var z := -146.0 + float(i) * 23.0
		_add_streetlight(life, Vector3(-40.0, 0.0, z), 0.0)
		_add_streetlight(life, Vector3(40.0, 0.0, z), PI)
		if i % 2 == 0:
			_add_tree(life, "AssetStreetTreeL_%d" % i, Vector3(-48.0, 0.0, z + 6.0), i % TREE_VARIANTS.size())
			_add_tree(life, "AssetStreetTreeR_%d" % i, Vector3(48.0, 0.0, z - 6.0), (i + 1) % TREE_VARIANTS.size())
	# Road Kit lamp standards down the freeway shoulders add scale and vertical rhythm
	# between the streetlights, then sidewalk furniture (benches, planters, bins,
	# hydrants, news stands) and cafe parasols dress the flanking sidewalks so the
	# side thirds read as inhabited street, not bare blocks.
	for i in range(8):
		var z := -150.0 + float(i) * 20.0
		var lamp := "light-square-double.glb" if i % 2 == 0 else "light-curved-double.glb"
		_add_city_kit_road_prop(life, lamp, "AssetLampL_%d" % i, Vector3(-38.0, 0.6, z), 90.0, "y", 7.4)
		_add_city_kit_road_prop(life, lamp, "AssetLampR_%d" % i, Vector3(38.0, 0.6, z), -90.0, "y", 7.4)
	for i in range(7):
		var z := -144.0 + float(i) * 22.0
		var lf := -44.0
		var rf := 44.0
		match i % 4:
			0:
				_add_bench(life, Vector3(lf, 0.6, z), 90.0)
				_add_planter(life, Vector3(rf, 0.6, z), 0.0)
			1:
				_add_news_stand(life, Vector3(lf, 0.6, z), 90.0)
				_add_trash_bin(life, Vector3(rf, 0.6, z), 0.0)
			2:
				_add_planter(life, Vector3(lf, 0.6, z), 0.0)
				_add_fire_hydrant(life, Vector3(rf, 0.6, z), 0.0)
			3:
				_add_trash_bin(life, Vector3(lf, 0.6, z), 0.0)
				_add_bench(life, Vector3(rf, 0.6, z), -90.0)
	for i in range(6):
		var asset := "detail-parasol-a.glb" if i % 2 == 0 else "detail-parasol-b.glb"
		var side := -1.0 if i % 2 == 0 else 1.0
		_add_city_kit_detail(life, asset, "AssetSidewalkCafe_%d" % i, Vector3(side * 42.0, 0.6, -120.0 + float(i) * 30.0), float(i) * 41.0, "y", 3.4)
	# A couple more vehicles on the foreground apron approaching the crosswalk.
	_add_car(life, "AssetApronCar_0", Vector3(-9.0, 0.42, -176.0), 0.0, 1)
	_add_car(life, "AssetApronCar_1", Vector3(9.0, 0.42, -188.0), 180.0, 2)
	_add_car(life, "AssetApronCar_2", Vector3(27.0, 0.42, -182.0), 0.0, 0)

func _add_city_kit_horizon_fill(parent: Node3D) -> void:
	# Capture-only deep-background fill. The wide 78° FOV city frame exposed a bare
	# tan ground/horizon wedge on the flanks (clearest on the right) where the
	# foreground side rows stop and the distant downtown cluster has not yet begun.
	# These set-back imported kit rows extend the canyon walls continuously into the
	# midground on both sides and seal the horizon with a wide low-rise band, so no
	# desert ground shows past the city. All rows stay well outside the freeway lanes.
	var fill := Node3D.new()
	fill.name = "KenneyCityKit_HorizonFill"
	parent.add_child(fill)
	# Solid lateral periphery: a multi-column grid of set-back imported blocks filling
	# the entire flank from the near foreground through the midground on each side, so
	# the wide-angle screen edges never open onto bare horizon ground (the right-side
	# tan wedge). Columns march outward and rows span the full visible depth.
	for side in [-1, 1]:
		var sf := float(side)
		for cx in range(4):
			var x := sf * (100.0 + float(cx) * 40.0)
			for rz in range(11):
				var z := -140.0 + float(rz) * 30.0
				var asset := str(CITY_KIT_MIDRISE_VARIANTS[absi(cx * 7 + rz * 3 + (side + 1) * 5) % CITY_KIT_MIDRISE_VARIANTS.size()])
				var fp := 17.0 + float((cx + rz) % 4) * 3.0
				var ys := 1.5 + float(absi(cx * 2 + rz + side) % 5) * 0.5
				_add_city_kit_building(fill, asset, "Periphery_%d_%d_%d" % [side, cx, rz], Vector3(x, 0.0, z), fp, ys, sf * float((rz % 3) - 1) * 4.0)
		# A taller outer skyscraper screen catches the very widest viewing angle.
		for r in range(6):
			var z := 30.0 + float(r) * 28.0
			var x := sf * (228.0 + float(r % 2) * 22.0)
			var asset := str(CITY_KIT_SKYSCRAPER_VARIANTS[(r + (1 if side < 0 else 3)) % CITY_KIT_SKYSCRAPER_VARIANTS.size()])
			_add_city_kit_building(fill, asset, "FlankScreen_%d_%d" % [side, r], Vector3(x, 0.0, z), 16.0 + float(r % 2) * 3.0, 1.4 + float(r % 3) * 0.3, sf * 6.0)
	# Continuous low-rise horizon band sealing the gap between the downtown cluster and
	# the existing distant skyline; spans the full frame width so neither flank shows
	# horizon ground at any camera angle. It fades into the warm aerial fog far back.
	var bx := -276.0
	var bi := 0
	while bx <= 276.0:
		var asset := str(CITY_KIT_LOW_DETAIL_VARIANTS[absi(bi * 5 + 3) % CITY_KIT_LOW_DETAIL_VARIANTS.size()])
		var z := 150.0 + float(absi(bi) % 3) * 12.0
		var ys := 1.2 + float(absi(bi * 3) % 4) * 0.3
		_add_city_kit_building(fill, asset, "HorizonBand_%d" % bi, Vector3(bx, 0.0, z), 20.0 + float(absi(bi) % 3) * 3.0, ys, float(bi % 4) * 3.0)
		bx += 18.0
		bi += 1

func _add_city_kit_street_detailing(parent: Node3D) -> void:
	# Capture-only foreground enrichment so the freeway reads as a landscaped divided
	# boulevard instead of a sterile slab. A raised planted central median runs the
	# length of the carriageway as a strong converging leading line, brighter curb
	# caps sharpen the sidewalk separation, and larger imported signs/planters/barriers
	# sit where the low near-eye camera reads them big. The median occupies only the
	# centre lane gap (x≈0, never a travel lane); all furniture sits off the lanes.
	var dress := Node3D.new()
	dress.name = "KenneyCityKit_StreetDetailing"
	parent.add_child(dress)
	var concrete := _matte(Color(0.50, 0.49, 0.46, 1.0), 0.82)
	var curb_cap := _matte(Color(0.62, 0.61, 0.57, 1.0), 0.70)
	var hedge := _matte(Color(0.16, 0.30, 0.13, 1.0), 0.90)
	# Raised planted central median between the opposing inner lanes: concrete kerb +
	# a continuous clipped hedge + spaced real planters so the centre reads as a green
	# divider sweeping north to the skyline.
	_add_box(dress, "MedianKerb", Vector3(2.2, 0.6, 150.0), Vector3(0.0, 0.45, -80.0), concrete)
	_add_box(dress, "MedianKerbCap", Vector3(2.4, 0.12, 150.0), Vector3(0.0, 0.78, -80.0), curb_cap)
	var mz := -150.0
	var mi := 0
	while mz < -10.0:
		_add_box(dress, "MedianHedge_%d" % mi, Vector3(1.7, 0.95, 5.2), Vector3(0.0, 1.0, mz), hedge)
		if mi % 3 == 0:
			_add_planter(dress, Vector3(0.0, 0.78, mz + 2.6), 0.0)
		mz += 7.0
		mi += 1
	# Brighter raised curb caps over the freeway-shoulder kerbs so the sidewalk/road
	# separation the flat slab lost at distance reads sharply again.
	for side in [-1.0, 1.0]:
		_add_box(dress, "ShoulderCurbCap_%d" % int(side), Vector3(0.8, 0.16, 168.0), Vector3(side * 37.0, 0.66, -72.0), curb_cap)
	# Larger prominent foreground furniture on the near sidewalks where the low camera
	# reads it big: overhead-scale highway signs, planters and barriers.
	_add_city_kit_road_prop(dress, "sign-highway-wide.glb", "ApronSignL", Vector3(-44.0, 0.0, -150.0), 25.0, "y", 9.4)
	_add_city_kit_road_prop(dress, "sign-highway-detailed.glb", "ApronSignR", Vector3(46.0, 0.0, -138.0), -20.0, "y", 8.6)
	for i in range(6):
		var z := -176.0 + float(i) * 30.0
		var side := -1.0 if i % 2 == 0 else 1.0
		_add_planter(dress, Vector3(side * 42.0, 0.6, z), 0.0)
		_add_barrier(dress, Vector3(side * 38.0, 0.6, z + 6.0), 0.0)
	# Big foreground apron planters flanking the crosswalk approach, large and close so
	# the lower frame carries significant set dressing instead of bare paint.
	for px in [-48.0, -40.0, 40.0, 48.0]:
		_add_box(dress, "ApronPlanterBox_%d" % int(px), Vector3(3.2, 0.9, 3.2), Vector3(px, 0.6, -182.0), concrete)
		_add_box(dress, "ApronPlanterGreen_%d" % int(px), Vector3(2.8, 0.8, 2.8), Vector3(px, 1.25, -182.0), hedge)

func _add_reference_foreground_freeway(parent: Node3D) -> void:
	# A wide, multilane surface freeway running north up the centre of the frame,
	# converging toward the skyline as strong leading lines. Matte asphalt + worn
	# paint, concrete jersey barriers, a raised central median, a foreground zebra
	# crosswalk, painted lane arrows, and sparse traffic for scale. No glow anywhere.
	var fwy := Node3D.new()
	fwy.name = "ReferenceFreeway"
	parent.add_child(fwy)
	var asphalt := _matte(Color(0.066, 0.066, 0.072, 1.0), 0.95)
	var white := _matte(Color(0.44, 0.43, 0.40, 1.0), 0.85)   # worn lane paint
	var yellow := _matte(Color(0.36, 0.30, 0.10, 1.0), 0.84)  # faded centre yellow
	var concrete := _matte(Color(0.47, 0.46, 0.43, 1.0), 0.9)
	# Carriageway deck (slightly proud of the ground plane so paint reads cleanly).
	_add_box(fwy, "FwyDeck", Vector3(58.0, 0.22, 152.0), Vector3(0, 0.11, -83.0), asphalt)
	# Raised central median + faded double-yellow either side.
	_add_box(fwy, "FwyMedian", Vector3(3.0, 0.5, 132.0), Vector3(0, 0.32, -83.0), concrete)
	_add_box(fwy, "FwyYellowL", Vector3(0.18, 0.05, 132.0), Vector3(-1.9, 0.18, -83.0), yellow)
	_add_box(fwy, "FwyYellowR", Vector3(0.18, 0.05, 132.0), Vector3(1.9, 0.18, -83.0), yellow)
	# Continuous worn shoulder lines.
	for ex in [-26.0, 26.0]:
		_add_box(fwy, "FwyEdge_%d" % int(ex), Vector3(0.3, 0.05, 146.0), Vector3(ex, 0.165, -83.0), white)
	# Dashed lane separators — converging perspective lines toward the skyline.
	for lane_x in [-21.0, -14.0, -7.0, 7.0, 14.0, 21.0]:
		var zz := -154.0
		var di := 0
		while zz < -14.0:
			_add_box(fwy, "FwyLane_%d_%d" % [int(lane_x), di], Vector3(0.24, 0.05, 4.0), Vector3(lane_x, 0.165, zz), white)
			zz += 7.0
			di += 1
	# Concrete jersey barriers down both outer edges, segmented with small gaps.
	var bz := -152.0
	var bi := 0
	while bz < -16.0:
		for bx in [-28.0, 28.0]:
			_add_box(fwy, "FwyBarrier_%d_%d" % [bi, int(bx)], Vector3(0.6, 1.0, 5.4), Vector3(bx, 0.5, bz), concrete)
		bz += 6.0
		bi += 1
	# Foreground zebra crosswalk (bars run with traffic, spaced across the width).
	for cx in range(-6, 7):
		_add_box(fwy, "FwyCross_%d" % cx, Vector3(1.4, 0.05, 6.0), Vector3(float(cx) * 3.6, 0.17, -150.0), white)
	# Painted forward lane arrows.
	for spec in [[-17.5, -118.0], [-3.5, -100.0], [10.5, -120.0], [17.5, -94.0]]:
		_add_lane_arrow(fwy, Vector3(float(spec[0]), 0.17, float(spec[1])))
	# Sparse traffic spread across the lanes.
	var car_specs := [
		[-17.5, -140.0, 180, 0], [-10.5, -104.0, 180, 1], [-3.5, -64.0, 180, 2],
		[3.5, -132.0, 0, 1], [10.5, -88.0, 0, 2], [17.5, -52.0, 0, 0], [-10.5, -28.0, 180, 1],
	]
	for ci in range(car_specs.size()):
		var cs: Array = car_specs[ci]
		_add_car(fwy, "FwyCar_%d" % ci, Vector3(float(cs[0]), 0.0, float(cs[1])), float(cs[2]), int(cs[3]) % CAR_VARIANTS.size())

func _add_lane_arrow(parent: Node3D, pos: Vector3) -> void:
	var white := _matte(Color(0.44, 0.43, 0.40, 1.0), 0.85)
	var tag := "%d_%d" % [int(pos.x), int(pos.z)]
	_add_box(parent, "ArrowShaft_%s" % tag, Vector3(0.5, 0.04, 3.4), pos, white)
	var hl := _add_box(parent, "ArrowHeadL_%s" % tag, Vector3(0.5, 0.04, 1.8), pos + Vector3(-0.45, 0, 1.5), white)
	hl.rotation_degrees = Vector3(0, 40.0, 0)
	var hr := _add_box(parent, "ArrowHeadR_%s" % tag, Vector3(0.5, 0.04, 1.8), pos + Vector3(0.45, 0, 1.5), white)
	hr.rotation_degrees = Vector3(0, -40.0, 0)

func _add_reference_landmark_cluster(parent: Node3D) -> void:
	# Layout note: the city capture camera looks north (+Z), so on screen world −X is
	# to the RIGHT and world +X is to the LEFT. Placement mirrors the reference frame.
	var cluster := Node3D.new()
	cluster.name = "ReferenceLandmarkCluster"
	parent.add_child(cluster)
	# Image-left: warm gold curtain-wall round towers catching the low sun.
	_add_capture_cyl_tower(cluster, "RefGoldA", Vector3(42, 0, 58), 13.0, 188.0, Color(0.17, 0.13, 0.085, 1.0), 0.80)
	_add_capture_cyl_tower(cluster, "RefGoldB", Vector3(61, 0, 72), 11.0, 150.0, Color(0.18, 0.14, 0.09, 1.0), 0.82)
	# Image-left slim stepped light-glass tower.
	_add_capture_glass_tower(cluster, "RefSlim", Vector3(76, 0, 66), 13.0, 12.0, 128.0, Color(0.12, 0.15, 0.20, 1.0), true, 1)
	# Centre: twin dark-blue glass cylinders rising behind the white block.
	_add_capture_cyl_tower(cluster, "RefTwinA", Vector3(-14, 0, 62), 10.0, 152.0, Color(0.05, 0.07, 0.13, 1.0), 0.88)
	_add_capture_cyl_tower(cluster, "RefTwinB", Vector3(-28, 0, 74), 9.0, 138.0, Color(0.05, 0.075, 0.135, 1.0), 0.88)
	# Image-right: a tall stepped cool-glass tower.
	_add_capture_glass_tower(cluster, "RefRightStep", Vector3(-46, 0, 66), 16.0, 14.0, 174.0, Color(0.09, 0.11, 0.16, 1.0), false, 2)
	# Far image-right, close: the big dark-blue rounded landmark (Arcadius-style).
	_add_capture_arcadius(cluster, Vector3(-84, 0, 34), 18.0, 182.0)
	# Filler skyline towers densifying the gaps behind the hero landmarks.
	_add_capture_glass_tower(cluster, "RefFill1", Vector3(26, 0, 94), 14.0, 13.0, 116.0, Color(0.10, 0.12, 0.17, 1.0), false, 0)
	_add_capture_glass_tower(cluster, "RefFill2", Vector3(-62, 0, 98), 15.0, 14.0, 132.0, Color(0.09, 0.11, 0.15, 1.0), false, 1)
	_add_capture_glass_tower(cluster, "RefFill3", Vector3(2, 0, 112), 16.0, 15.0, 150.0, Color(0.08, 0.10, 0.15, 1.0), false, 2)

func _add_capture_cyl_tower(parent: Node3D, t_name: String, pos: Vector3, radius: float, height: float, albedo: Color, taper: float = 0.85) -> Node3D:
	# A curtain-wall glass cylinder: tapered shaft + stacked floor mullion rings +
	# a mechanical crown. High-metal/low-rough glass so the warm sun glints off one
	# face while the cool sky fills the rest (the reference teal/orange split).
	var node := Node3D.new()
	node.name = t_name
	node.position = pos
	parent.add_child(node)
	var glass := _glass_tower_material(albedo)
	var shaft := MeshInstance3D.new()
	shaft.name = t_name + "_Shaft"
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius * taper
	cm.height = height
	cm.radial_segments = 44
	shaft.mesh = cm
	shaft.position = Vector3(0, height * 0.5, 0)
	shaft.material_override = glass
	node.add_child(shaft)
	var band := _matte(Color(0.03, 0.04, 0.06, 1.0), 0.5, 0.4)
	var rings := int(height / 4.4)
	for i in range(1, rings):
		var ry := float(i) * 4.4
		var t := ry / height
		var r := radius * (1.0 - (1.0 - taper) * t) + 0.08
		var ring := MeshInstance3D.new()
		ring.name = "%s_Band_%d" % [t_name, i]
		var rm := CylinderMesh.new()
		rm.top_radius = r
		rm.bottom_radius = r
		rm.height = 0.34
		rm.radial_segments = 44
		ring.mesh = rm
		ring.position = Vector3(0, ry, 0)
		ring.material_override = band
		node.add_child(ring)
	var crown_mat := _matte(Color(0.28, 0.28, 0.31, 1.0), 0.35, 0.7)
	var topr := radius * taper
	_add_box(node, t_name + "_Crown", Vector3(topr * 1.5, 2.6, topr * 1.5), Vector3(0, height + 1.3, 0), crown_mat)
	return node

func _add_capture_glass_tower(parent: Node3D, t_name: String, pos: Vector3, w: float, d: float, h: float, albedo: Color, stripe: bool = false, steps: int = 0) -> Node3D:
	# Rectangular curtain-wall tower with protruding horizontal spandrel bands,
	# vertical corner mullions, optional setback steps, and a parapet/mech crown.
	var node := Node3D.new()
	node.name = t_name
	node.position = pos
	parent.add_child(node)
	var glass := _glass_tower_material(albedo)
	_add_box(node, t_name + "_Core", Vector3(w, h, d), Vector3(0, h * 0.5, 0), glass)
	var spandrel := _matte(Color(albedo.r * 0.5 + 0.05, albedo.g * 0.5 + 0.05, albedo.b * 0.5 + 0.06, 1.0), 0.55, 0.4)
	var floor_h := 4.4
	var n := int(h / floor_h)
	for i in range(1, n):
		var sy := float(i) * floor_h
		_add_box(node, "%s_SpF_%d" % [t_name, i], Vector3(w + 0.14, 0.7, 0.18), Vector3(0, sy, d * 0.5 + 0.07), spandrel)
		_add_box(node, "%s_SpB_%d" % [t_name, i], Vector3(w + 0.14, 0.7, 0.18), Vector3(0, sy, -d * 0.5 - 0.07), spandrel)
		_add_box(node, "%s_SpL_%d" % [t_name, i], Vector3(0.18, 0.7, d + 0.14), Vector3(-w * 0.5 - 0.07, sy, 0), spandrel)
		_add_box(node, "%s_SpR_%d" % [t_name, i], Vector3(0.18, 0.7, d + 0.14), Vector3(w * 0.5 + 0.07, sy, 0), spandrel)
	var mull := _matte(Color(0.30, 0.31, 0.34, 1.0), 0.45, 0.6)
	for cx in [-w * 0.5, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			_add_box(node, "%s_Mull_%d_%d" % [t_name, int(cx), int(cz)], Vector3(0.5, h, 0.5), Vector3(cx, h * 0.5, cz), mull)
	if stripe:
		_add_box(node, "%s_Stripe" % t_name, Vector3(1.3, h, 0.45), Vector3(0, h * 0.5, d * 0.5 + 0.22), mull)
	if steps > 0:
		var sw := w
		var sd := d
		var sy0 := h
		for s in range(steps):
			sw *= 0.72
			sd *= 0.72
			var sh := h * 0.16
			_add_box(node, "%s_Step_%d" % [t_name, s], Vector3(sw, sh, sd), Vector3(0, sy0 + sh * 0.5, 0), glass)
			sy0 += sh
		_add_box(node, "%s_Mast" % t_name, Vector3(0.6, h * 0.12, 0.6), Vector3(0, sy0 + h * 0.06, 0), mull)
	else:
		var crown := _matte(Color(0.22, 0.23, 0.26, 1.0), 0.6, 0.3)
		_add_box(node, "%s_Parapet" % t_name, Vector3(w + 0.5, 1.4, d + 0.5), Vector3(0, h + 0.7, 0), crown)
		_add_box(node, "%s_Mech" % t_name, Vector3(w * 0.55, 4.5, d * 0.55), Vector3(0, h + 3.5, 0), crown)
	return node

func _add_capture_banded_block(parent: Node3D, pos: Vector3, w: float, d: float, h: float) -> Node3D:
	# The reference's closest centre building: a pale concrete tower with bold,
	# continuous dark horizontal window bands and a dark/maroon retail base.
	var node := Node3D.new()
	node.name = "RefCenterBlock"
	node.position = pos
	parent.add_child(node)
	var concrete := _matte(Color(0.60, 0.58, 0.55, 1.0), 0.6, 0.05)
	_add_box(node, "CoreWhite", Vector3(w, h, d), Vector3(0, h * 0.5, 0), concrete)
	var glassband := _matte(Color(0.05, 0.06, 0.08, 1.0), 0.28, 0.5)
	var floor_h := 4.0
	var floors := int(h / floor_h)
	for i in range(floors):
		var fy := 7.0 + float(i) * floor_h
		if fy > h - 2.5:
			break
		_add_box(node, "WinF_%d" % i, Vector3(w + 0.06, 2.3, 0.22), Vector3(0, fy, d * 0.5), glassband)
		_add_box(node, "WinB_%d" % i, Vector3(w + 0.06, 2.3, 0.22), Vector3(0, fy, -d * 0.5), glassband)
		_add_box(node, "WinL_%d" % i, Vector3(0.22, 2.3, d + 0.06), Vector3(-w * 0.5, fy, 0), glassband)
		_add_box(node, "WinR_%d" % i, Vector3(0.22, 2.3, d + 0.06), Vector3(w * 0.5, fy, 0), glassband)
	var base := _matte(Color(0.22, 0.07, 0.05, 1.0), 0.7)
	_add_box(node, "RetailBase", Vector3(w + 0.4, 6.0, d + 0.4), Vector3(0, 3.0, 0), base)
	_add_box(node, "Parapet", Vector3(w + 0.5, 1.6, d + 0.5), Vector3(0, h + 0.6, 0), concrete)
	return node

func _add_capture_arcadius(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	# The big dark-blue rounded glass landmark on the right of the frame: a nearly
	# straight tube of very dark reflective glass with a faint warm signage band.
	var node := _add_capture_cyl_tower(parent, "RefArcadius", pos, radius, height, Color(0.035, 0.05, 0.09, 1.0), 0.97)
	var sign := _add_box(node, "RefArcadiusSign", Vector3(radius * 0.9, 4.0, 0.3), Vector3(0, height - 24.0, -radius * 0.98), _mat(Color(0.5, 0.52, 0.58, 1.0), Color(0.7, 0.6, 0.45, 1.0), 0.22))
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _flare_texture() -> ImageTexture:
	# Soft radial disc (white core → transparent edge) for the lens-flare sprites.
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := float(s) * 0.5
	for y in range(s):
		for x in range(s):
			var dist := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
			var a := clampf(1.0 - dist, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

func _add_sun_flare_capture_only() -> void:
	# A chain of warm additive billboard discs locked to the capture camera, running
	# from the upper-right sun glow through the frame — the reference's golden flare.
	# Parented to the camera so it stays in screen space; city-capture only.
	if camera == null or not is_instance_valid(camera):
		return
	var tex := _flare_texture()
	var holder := Node3D.new()
	holder.name = "SunFlareCapture"
	camera.add_child(holder)
	# [local x, local y, size, r, g, b, alpha]
	var discs := [
		[13.0, 7.0, 12.0, 1.0, 0.72, 0.42, 0.55],
		[9.5, 4.8, 4.4, 1.0, 0.85, 0.60, 0.50],
		[4.5, 1.8, 2.6, 1.0, 0.62, 0.50, 0.40],
		[-1.0, -1.2, 3.4, 0.70, 0.58, 1.0, 0.32],
		[-6.0, -4.2, 5.2, 1.0, 0.62, 0.40, 0.30],
		[-11.0, -7.0, 2.4, 0.90, 0.82, 0.60, 0.40],
	]
	for i in range(discs.size()):
		var dd: Array = discs[i]
		var q := MeshInstance3D.new()
		q.name = "Flare_%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(float(dd[2]), float(dd[2]))
		q.mesh = qm
		q.position = Vector3(float(dd[0]), float(dd[1]), -30.0)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.albedo_color = Color(float(dd[3]), float(dd[4]), float(dd[5]), float(dd[6]))
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		m.disable_receive_shadows = true
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(q)
