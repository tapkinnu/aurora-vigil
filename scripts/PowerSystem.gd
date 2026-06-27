class_name PowerSystem
extends RefCounted

# Handles the hero's powers: gating by unlocks, training surges that grant XP for
# locked powers, the power flash VFX, power audio, and dispatching a matching
# nearest-event resolution through the CityEventSystem. Split out of Main.gd.
# `host` is the Main Node3D coordinator (materials, tweens, scene tree, HUD cue).

const DEFAULT_DATA_PATH := "res://data/powers/powers.json"
# Flash color used for any power without an explicit data entry (e.g. training
# surges for not-yet-unlocked powers). Matches the original inline default.
const DEFAULT_FLASH_COLOR := Color(0.2, 1.0, 0.9, 1.0)

var host
var hero: Node3D
var progression: ProgressionModel
var events: CityEventSystem

# Raw JSON payload last loaded by `load_data`, exposed for tests/inspection.
var loaded_data: Dictionary = {}
# Per-power lookup: id -> { "flash_color": Color, "audio_triggers": Array[String],
#                               "name": String, "key": String }.
var power_data: Dictionary = {}

func setup(host_ref, hero_ref: Node3D, progression_ref: ProgressionModel, events_ref: CityEventSystem, data_path: String = DEFAULT_DATA_PATH) -> void:
	host = host_ref
	hero = hero_ref
	progression = progression_ref
	events = events_ref
	load_data(data_path)

# Loads the powers table from JSON into `power_data`. Returns true on success;
# on failure it leaves `power_data` empty so the inline defaults take over.
func load_data(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("PowerSystem: powers data not found at %s; using fallback" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("powers"):
		push_error("PowerSystem: malformed powers data at %s; using fallback" % path)
		return false
	var lookup := {}
	for entry in parsed["powers"]:
		var c: Array = entry.get("flash_color", [DEFAULT_FLASH_COLOR.r, DEFAULT_FLASH_COLOR.g, DEFAULT_FLASH_COLOR.b, DEFAULT_FLASH_COLOR.a])
		var triggers: Array[String] = []
		for t in entry.get("audio_triggers", []):
			triggers.append(str(t))
		lookup[str(entry.get("id", ""))] = {
			"flash_color": Color(c[0], c[1], c[2], c[3]),
			"audio_triggers": triggers,
			"name": str(entry.get("name", "")),
			"key": str(entry.get("key", "")),
		}
	if lookup.is_empty():
		push_error("PowerSystem: powers data at %s had no entries; using fallback" % path)
		return false
	power_data = lookup
	loaded_data = parsed
	return true

func trigger(power_id: String) -> void:
	if not progression.has_power(power_id):
		var gained: Array[String] = progression.add_xp(110)
		host.last_event_text = "%s training surge: +110 XP%s" % [power_id.replace("_", " ").capitalize(), " and new power unlocked" if gained.has(power_id) else ""]
		if gained.has(power_id):
			_spawn_power_flash(power_id)
		return
	_spawn_power_flash(power_id)
	_play_power_audio(power_id)
	var resolved := events.attempt_resolve_nearest(power_id)
	if not resolved:
		host.last_event_text = "%s fired, but no matching city event is within %.0fm." % [power_id.replace("_", " ").capitalize(), events.EVENT_RESOLVE_RADIUS]

func _spawn_power_flash(power_id: String) -> void:
	var c: Color = DEFAULT_FLASH_COLOR
	if power_data.has(power_id):
		c = power_data[power_id]["flash_color"]
	# Base burst: a quick emissive bloom at the hero, kept from the original VFX so
	# every power (including training surges with no data entry) reads on screen.
	var flash := MeshInstance3D.new()
	flash.name = "PowerFlash_%s" % power_id
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	flash.mesh = mesh
	flash.position = hero.position
	flash.material_override = host._mat(c, c, 1.8)
	host.add_child(flash)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(flash, "scale", Vector3(7, 7, 7), 0.35)
	tween.parallel().tween_property(flash, "transparency", 1.0, 0.35)
	tween.tween_callback(flash.queue_free)
	# Per-power signature VFX layered on top of the base burst.
	_spawn_power_vfx(power_id, c)

# Dispatches the distinctive, performant, gl_compatibility-safe VFX for each power.
# All effects are short (≤2 s) and self-free via a remembered tween so they are torn
# down cleanly at quit. Unknown/training-surge ids fall through to the base burst.
func _spawn_power_vfx(power_id: String, c: Color) -> void:
	match power_id:
		"radiant_beam":
			_vfx_radiant_beam(c)
		"sonic_burst":
			_vfx_sonic_burst(c)
		"aegis_field":
			_vfx_aegis_field(c)
		"rescue_lift":
			_vfx_rescue_lift(c)
		"orbit_sprint":
			_vfx_orbit_sprint(c)

# Bright beam from the hero to the nearest event (or straight ahead), with a particle
# burst where it lands.
func _vfx_radiant_beam(c: Color) -> void:
	var origin: Vector3 = hero.position
	var target: Vector3 = origin + (-hero.global_transform.basis.z) * 42.0
	var ne: Node3D = events.nearest_event()
	if ne != null and is_instance_valid(ne) and origin.distance_to(ne.position) < 90.0:
		target = ne.position
	var dir := (target - origin)
	var dist := dir.length()
	if dist < 0.5:
		return
	var beam := MeshInstance3D.new()
	beam.name = "RadiantBeam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.22
	cyl.height = dist
	beam.mesh = cyl
	beam.material_override = host._mat(c, c, 3.2)
	host.add_child(beam)
	beam.global_position = (origin + target) * 0.5
	beam.look_at(target, Vector3.UP)
	beam.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)  # align cylinder Y axis to the beam line
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_interval(0.12)
	tween.tween_property(beam, "transparency", 1.0, 0.28)
	tween.tween_callback(beam.queue_free)
	_burst(target, c, 26, 9.0, 0.55)

# Expanding shockwave ring around the hero plus a brief screen flash.
func _vfx_sonic_burst(c: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "SonicRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.2
	torus.outer_radius = 1.8
	ring.mesh = torus
	ring.material_override = host._mat(c, c, 2.6)
	ring.position = hero.position
	host.add_child(ring)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(ring, "scale", Vector3(16, 4, 16), 0.5)
	tween.parallel().tween_property(ring, "transparency", 1.0, 0.5)
	tween.tween_callback(ring.queue_free)
	if host.has_method("flash_screen"):
		host.flash_screen(Color(c.r, c.g, c.b, 0.32))

# Translucent protective bubble around the hero, parented so it tracks the hero, with
# a shimmer pulse before it fades.
func _vfx_aegis_field(c: Color) -> void:
	var bubble := MeshInstance3D.new()
	bubble.name = "AegisBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	bubble.mesh = sphere
	var mat = host._transparent_mat(Color(c.r, c.g, c.b, 0.22), c, 1.6)
	bubble.material_override = mat
	hero.add_child(bubble)
	bubble.scale = Vector3(0.4, 0.4, 0.4)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(bubble, "scale", Vector3(1.0, 1.0, 1.0), 0.25)
	tween.tween_property(bubble, "scale", Vector3(1.1, 1.1, 1.1), 0.6)
	tween.tween_property(bubble, "scale", Vector3(1.0, 1.0, 1.0), 0.6)
	tween.tween_property(bubble, "transparency", 1.0, 0.55)
	tween.tween_callback(bubble.queue_free)

# Green glow pillar rising from the nearest civilian/event toward the sky with a
# sparkle burst, evoking a rescue lift.
func _vfx_rescue_lift(c: Color) -> void:
	var base: Vector3 = hero.position
	var ne: Node3D = events.nearest_event()
	if ne != null and is_instance_valid(ne) and hero.position.distance_to(ne.position) < 90.0:
		base = Vector3(ne.position.x, 1.0, ne.position.z)
	var pillar := MeshInstance3D.new()
	pillar.name = "RescuePillar"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.4
	cyl.height = 26.0
	pillar.mesh = cyl
	pillar.material_override = host._transparent_mat(Color(c.r, c.g, c.b, 0.28), c, 2.4)
	pillar.position = base + Vector3(0, 13.0, 0)
	pillar.scale = Vector3(1, 0.05, 1)
	host.add_child(pillar)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(pillar, "scale", Vector3(1, 1, 1), 0.4)
	tween.tween_interval(0.4)
	tween.tween_property(pillar, "transparency", 1.0, 0.5)
	tween.tween_callback(pillar.queue_free)
	_burst(base + Vector3(0, 2.0, 0), c, 30, 7.0, 0.7)

# Fast horizontal speed-streak effect: a glowing trail cylinder shooting forward
# from the hero in the facing direction, plus a brief ring burst.
func _vfx_orbit_sprint(c: Color) -> void:
	var origin: Vector3 = hero.position
	var target: Vector3 = origin + (-hero.global_transform.basis.z) * 18.0
	var dir := (target - origin)
	var dist := dir.length()
	if dist < 0.5:
		return
	var streak := MeshInstance3D.new()
	streak.name = "OrbitSprintStreak"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.55
	cyl.height = dist
	streak.mesh = cyl
	streak.material_override = host._mat(c, c, 2.0)
	host.add_child(streak)
	streak.global_position = (origin + target) * 0.5
	streak.look_at(target, Vector3.UP)
	streak.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(streak, "transparency", 1.0, 0.25)
	tween.tween_callback(streak.queue_free)
	_burst(origin, c, 14, 5.0, 0.4)

# One-shot CPUParticles3D burst (gl_compatibility safe). Self-frees after its
# lifetime via a remembered tween so quit cleanup stays leak-free.
func _burst(pos: Vector3, c: Color, count: int, vel: float, life: float) -> void:
	var p := CPUParticles3D.new()
	p.name = "PowerBurst"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.position = pos
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.55
	var dot := SphereMesh.new()
	dot.radius = 0.18
	dot.height = 0.36
	dot.radial_segments = 6
	dot.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.material = mat
	p.mesh = dot
	host.add_child(p)
	p.emitting = true
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_interval(life + 0.3)
	tween.tween_callback(p.queue_free)

# The set of audio ids that fire for a power now comes from data (power_data),
# but each id is dispatched through a literal `AuroraAudio.trigger("...")` so the
# audio-wiring contract (check_audio_wiring.py) and call shape stay intact.
func _play_power_audio(power_id: String) -> void:
	if not power_data.has(power_id):
		return
	for id in power_data[power_id]["audio_triggers"]:
		_dispatch_audio(str(id))

func _dispatch_audio(id: String) -> void:
	match id:
		"power_radiant_beam_fire":
			AuroraAudio.trigger("power_radiant_beam_fire")
		"power_sonic_burst":
			AuroraAudio.trigger("power_sonic_burst")
		"power_aegis_activate":
			AuroraAudio.trigger("power_aegis_activate")
		"power_orbit_sprint":
			AuroraAudio.trigger("power_orbit_sprint")
		"event_alert_rescue_needed":
			AuroraAudio.trigger("event_alert_rescue_needed")
		_:
			push_error("PowerSystem: unknown audio trigger id '%s'" % id)
