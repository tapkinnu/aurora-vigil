class_name PlayerFlightController
extends RefCounted

# Drives the hero's flight, the third-person chase camera (including capture-mode
# poses and view-blocking collision), and the soft contact shadow that pins the
# hero to the streets. Split out of Main.gd; `host` is the Main Node3D coordinator
# and provides scene-tree services (world space, add_child, materials).

var host
var hero: Node3D
var camera: Camera3D
var velocity: Vector3 = Vector3.ZERO

func setup(host_ref, hero_ref: Node3D, camera_ref: Camera3D) -> void:
	host = host_ref
	hero = hero_ref
	camera = camera_ref

func handle_flight(delta: float) -> void:
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
		# City capture should show a readable skyline overview, not a wall the
		# camera starts inside. Use an open high-angle position over the central
		# avenue and pull the camera above the skyline ring.
		offset = Vector3(-24, 46, -58)
	elif mode == "closeup":
		camera.fov = 62
		offset = Vector3(6, 1.2, -14)
	var target := hero.position + Vector3(0, 1.2, 0)
	if mode == "city":
		target = Vector3(0, 24, 0)
	elif mode == "closeup":
		target = hero.position + Vector3(0, 1.55, 0)
	var desired := hero.position + offset
	var resolved := _resolve_camera_collision(target, desired)
	camera.global_position = camera.global_position.lerp(resolved, clamp(delta * 5.0, 0, 1))
	camera.look_at(target, Vector3.UP)

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
