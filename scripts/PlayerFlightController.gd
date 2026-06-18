class_name PlayerFlightController
extends RefCounted

# Drives the hero's flight, the third-person chase camera (including capture-mode
# poses and view-blocking collision), the soft contact shadow that pins the hero to
# the streets, and the boost motion trail. Split out of Main.gd; `host` is the Main
# Node3D coordinator and provides scene-tree services (world space, add_child,
# materials).
#
# Input is unified across keyboard and gamepad: WASD / left stick translate, Space &
# Ctrl / triggers climb and dive, Shift / bumpers boost, and the right stick orbits
# the chase camera (respecting the SettingsManager look-sensitivity and invert-Y).

const DEADZONE := 0.2

var host
var hero: Node3D
var camera: Camera3D
var velocity: Vector3 = Vector3.ZERO

var _trail: CPUParticles3D
# Manual chase-camera orbit driven by the right stick, applied only in free gameplay
# (capture modes pose the camera explicitly). Yaw wraps; pitch is clamped.
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0

func setup(host_ref, hero_ref: Node3D, camera_ref: Camera3D) -> void:
	host = host_ref
	hero = hero_ref
	camera = camera_ref
	_build_trail()

func _build_trail() -> void:
	if hero == null:
		return
	_trail = CPUParticles3D.new()
	_trail.name = "FlightTrail"
	_trail.emitting = false
	_trail.amount = 64
	_trail.lifetime = 0.55
	_trail.local_coords = false  # leave emitted particles in world space → ribbon trail
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 6.0
	_trail.initial_velocity_min = 0.4
	_trail.initial_velocity_max = 1.6
	_trail.gravity = Vector3.ZERO
	_trail.damping_min = 1.0
	_trail.damping_max = 2.0
	_trail.scale_amount_min = 0.35
	_trail.scale_amount_max = 0.7
	# Slightly behind the hero (hero faces -Z, so +Z local trails behind).
	_trail.position = Vector3(0, 0, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.95, 1.0, 0.85))
	ramp.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	_trail.color_ramp = ramp
	var dot := SphereMesh.new()
	dot.radius = 0.22
	dot.height = 0.44
	dot.radial_segments = 6
	dot.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.95, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.9, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.material = mat
	_trail.mesh = dot
	hero.add_child(_trail)

func handle_flight(delta: float) -> void:
	var input_vec := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_vec.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_vec.z += 1.0
	if Input.is_key_pressed(KEY_A): input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_vec.x += 1.0
	if Input.is_key_pressed(KEY_SPACE): input_vec.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): input_vec.y -= 1.0
	# Gamepad: left stick translates on the XZ plane, triggers climb/dive.
	if Input.get_connected_joypads().size() > 0:
		var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
		if absf(lx) > DEADZONE: input_vec.x += lx
		if absf(ly) > DEADZONE: input_vec.z += ly
		var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		input_vec.y += clampf(rt, 0.0, 1.0) - clampf(lt, 0.0, 1.0)
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()
	var boosting := Input.is_action_pressed("aurora_boost")
	var speed := 62.0 if boosting else 34.0
	velocity = velocity.lerp(input_vec * speed, 4.0 * delta)
	if boosting and velocity.length() > 1.0:
		AuroraAudio.trigger("flight_boost_burst")
	hero.position += velocity * delta
	hero.position.y = clamp(hero.position.y, 5.0, 120.0)
	if velocity.length() > 1.0:
		hero.look_at(hero.position - Vector3(velocity.x, 0.0, velocity.z).normalized(), Vector3.UP)
	_update_trail(boosting)

func _update_trail(boosting: bool) -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var spd := velocity.length()
	_trail.emitting = spd > 6.0
	# Boost makes the trail longer, faster, and a touch larger.
	_trail.lifetime = 0.75 if boosting else 0.5
	_trail.initial_velocity_max = 2.4 if boosting else 1.6
	_trail.scale_amount_max = 0.9 if boosting else 0.7

func update_camera(delta: float, nearest: Node3D) -> void:
	var mode := OS.get_environment("AURORA_CAPTURE_MODE")
	if mode == "drone" and nearest != null:
		var drone_target := Vector3(0, 75, 60)
		var drone_desired := Vector3(-35, 105, -20)
		camera.fov = 76
		camera.global_position = camera.global_position.lerp(drone_desired, clamp(delta * 5.0, 0, 1))
		camera.look_at(drone_target, Vector3.UP)
		return
	# Keep the playable chase camera in the central flight corridor; the previous
	# positive-Z offset could spawn the camera inside the first skyline ring.
	var offset := Vector3(0, 10, -22)
	if mode == "city":
		# City capture frames the cinematic golden-hour vista in the style of the
		# Los Santos reference: a low, near-eye-level camera so the wide multilane
		# freeway dominates the lower third as converging leading lines, the
		# distinctive downtown landmark cluster looms large across the mid/upper
		# frame, and the deep-blue sky fills the top. The camera sits just behind and
		# above the (hidden) staged hero looking north up the boulevard.
		camera.fov = 78
		offset = Vector3(0, 28, -66)
	elif mode == "closeup":
		camera.fov = 62
		offset = Vector3(6, 1.2, -14)
	else:
		# Free gameplay: right stick orbits the chase camera.
		_update_look(delta)
		offset = offset.rotated(Vector3.UP, _cam_yaw)
		offset.y += _cam_pitch
	var target := hero.position + Vector3(0, 1.2, 0)
	if mode == "city":
		# Aim up the boulevard toward the landmark cluster, biased slightly upward so
		# the towers rise and the blue sky tops the frame rather than a top-down plan.
		target = Vector3(0, 42, 48)
	elif mode == "closeup":
		target = hero.position + Vector3(0, 1.55, 0)
	var desired := hero.position + offset
	# The curated city postcard deliberately opens a clear procedural highway
	# corridor. Collision resolution can still snap the camera against a remaining
	# side tower and turn the frame into a brick wall, so use the exact staged pose
	# for this non-gameplay capture.
	var resolved := desired if mode == "city" else _resolve_camera_collision(target, desired)
	camera.global_position = camera.global_position.lerp(resolved, clamp(delta * 5.0, 0, 1))
	camera.look_at(target, Vector3.UP)

func _update_look(delta: float) -> void:
	if Input.get_connected_joypads().size() == 0:
		return
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var sens := _look_sensitivity()
	if absf(rx) > DEADZONE:
		_cam_yaw = wrapf(_cam_yaw - rx * sens * 1.6 * delta, -PI, PI)
	if absf(ry) > DEADZONE:
		var inv := -1.0 if _invert_y() else 1.0
		_cam_pitch = clampf(_cam_pitch + ry * inv * sens * 9.0 * delta, -6.0, 16.0)

func _settings_node():
	if host == null:
		return null
	return host.get_node_or_null("/root/SettingsManager")

func _look_sensitivity() -> float:
	var sm = _settings_node()
	return float(sm.mouse_sensitivity) if sm != null else 1.0

func _invert_y() -> bool:
	var sm = _settings_node()
	return bool(sm.invert_y) if sm != null else false

func _resolve_camera_collision(from_pos: Vector3, desired_camera_pos: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = host.get_world_3d().direct_space_state
	# Cast from the desired camera back toward the hero. If a building blocks the
	# view, place the camera just outside that obstruction on the camera side.
	var query := PhysicsRayQueryParameters3D.create(desired_camera_pos, from_pos, 1, [])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return desired_camera_pos
	var away := (desired_camera_pos - from_pos).normalized()
	return Vector3(hit["position"]) + away * 1.4

func attach_contact_shadow(target: Node3D, radius: float, height: float) -> void:
	# Soft circular shadow disc parented to the coordinator. Updated each frame so
	# the disc always sits directly beneath the actor's XZ position at ground level.
	if target == null:
		return
	var disc := MeshInstance3D.new()
	disc.name = "ContactShadowDisc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.06
	disc.mesh = cyl
	disc.position = Vector3(0, -target.position.y + 0.04, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	disc.material_override = mat
	host.add_child(disc)
	target.set_meta("contact_shadow", disc)
	target.set_meta("contact_shadow_height", height)

func update_contact_shadows() -> void:
	for actor in [hero]:
		if actor == null or not is_instance_valid(actor):
			continue
		var disc = actor.get_meta("contact_shadow", null)
		if disc == null or not is_instance_valid(disc):
			continue
		disc.position = Vector3(actor.position.x, 0.04, actor.position.z)
