class_name InteractionVolume
extends Area3D

# Reusable, data-driven interaction volume for Aurora Vigil. A single component the
# rest of the game spawns from JSON to give every city event and mission a real,
# observable in-world presence. It carries a configurable shape (sphere / box /
# cylinder), color, billboard label, a volume-kind binding (event kind, "mission",
# or "bridge_collapse"), and a list of named triggers (e.g. audio ids) fired on
# enter. Resolution still happens through the power-driven CityEventSystem; this
# layer adds the readable, testable "player is here" trigger.
#
# It is schema-tolerant by design: `from_data` applies defaults for any missing
# OPTIONAL field and refuses (push_error + null) only when the single REQUIRED
# field `kind` is absent, so a malformed data dict skips a volume instead of
# crashing the spawner.
#
# Two entry paths feed the same `triggered` signal:
#   * Area3D body_entered / area_entered — fires if a real physics body/area is used.
#   * notify_point(global_point)         — frame polling used by ObjectiveDirector
#                                           (the hero is a plain Node3D, not a body)
#                                           and by the unit tests for determinism.

signal triggered(volume: InteractionVolume, source)

const SHAPE_SPHERE := "sphere"
const SHAPE_BOX := "box"
const SHAPE_CYLINDER := "cylinder"
const VALID_SHAPES := [SHAPE_SPHERE, SHAPE_BOX, SHAPE_CYLINDER]

const DEFAULT_SHAPE := SHAPE_SPHERE
const DEFAULT_RADIUS := 12.0
const DEFAULT_HEIGHT := 8.0
const DEFAULT_BOX_SIZE := Vector3(12.0, 8.0, 12.0)
const DEFAULT_COLOR := Color(0.5, 0.8, 1.0, 1.0)

var volume_kind: String = ""
var shape_kind: String = DEFAULT_SHAPE
var radius: float = DEFAULT_RADIUS
var height: float = DEFAULT_HEIGHT
var box_size: Vector3 = DEFAULT_BOX_SIZE
var color: Color = DEFAULT_COLOR
var label_text: String = ""
# Named trigger ids (typically audio ids) fired by the host when the volume is
# entered. Kept as plain strings so they can live in JSON and be dispatched
# through the literal AuroraAudio shim.
var triggers: Array[String] = []

var _inside: bool = false

# Builds a configured volume from a data dict. Returns null (after push_error) when
# the required `kind` field is missing or empty so the spawner can skip it safely.
static func from_data(data: Dictionary) -> InteractionVolume:
	var volume := InteractionVolume.new()
	if not volume.configure(data):
		volume.free()
		return null
	return volume

# Applies a data dict to this volume. Missing optional fields fall back to the
# DEFAULT_* constants; a missing/empty required `kind` logs an error and returns
# false without building any geometry.
func configure(data: Dictionary) -> bool:
	var kind := str(data.get("kind", ""))
	if kind.is_empty():
		push_error("InteractionVolume: data dict missing required 'kind' field; skipping volume")
		return false
	volume_kind = kind
	name = "InteractionVolume_%s" % kind

	var requested_shape := str(data.get("shape", DEFAULT_SHAPE))
	shape_kind = requested_shape if requested_shape in VALID_SHAPES else DEFAULT_SHAPE
	radius = float(data.get("radius", DEFAULT_RADIUS))
	height = float(data.get("height", DEFAULT_HEIGHT))
	box_size = _vec3_or(data.get("size", null), DEFAULT_BOX_SIZE)
	color = _color_or(data.get("color", null), DEFAULT_COLOR)
	label_text = str(data.get("label", ""))
	triggers.clear()
	for t in data.get("triggers", []):
		triggers.append(str(t))

	var pos = data.get("position", null)
	if pos is Array and pos.size() >= 3:
		position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))

	_build_geometry()
	# Wire the physics-body path too, so a real CollisionObject works in addition
	# to the polled notify_point path. Safe even though the hero is a plain Node3D.
	if not body_entered.is_connected(_on_physics_entered):
		body_entered.connect(_on_physics_entered)
	if not area_entered.is_connected(_on_physics_entered):
		area_entered.connect(_on_physics_entered)
	monitoring = true
	return true

func _vec3_or(value, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

func _color_or(value, fallback: Color) -> Color:
	if value is Array and value.size() >= 4:
		return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return fallback

func _build_geometry() -> void:
	for child in get_children():
		child.queue_free()

	var collision := CollisionShape3D.new()
	collision.name = "VolumeShape"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "VolumeVisual"

	match shape_kind:
		SHAPE_BOX:
			var box_shape := BoxShape3D.new()
			box_shape.size = box_size
			collision.shape = box_shape
			var bm := BoxMesh.new()
			bm.size = box_size
			mesh_instance.mesh = bm
		SHAPE_CYLINDER:
			var cyl_shape := CylinderShape3D.new()
			cyl_shape.radius = radius
			cyl_shape.height = height
			collision.shape = cyl_shape
			var cm := CylinderMesh.new()
			cm.top_radius = radius
			cm.bottom_radius = radius
			cm.height = height
			mesh_instance.mesh = cm
		_:
			var sphere_shape := SphereShape3D.new()
			sphere_shape.radius = radius
			collision.shape = sphere_shape
			var sm := SphereMesh.new()
			sm.radius = radius
			sm.height = radius * 2.0
			mesh_instance.mesh = sm

	mesh_instance.material_override = _volume_material()
	add_child(collision)
	add_child(mesh_instance)

	# Bright ground ring so the volume footprint reads from a high capture angle.
	var ring := MeshInstance3D.new()
	ring.name = "VolumeRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.6
	ring_mesh.outer_radius = radius + 0.6
	ring.mesh = ring_mesh
	ring.position = Vector3(0, -position.y + 0.25, 0) if position.y > 1.0 else Vector3.ZERO
	ring.rotation_degrees = Vector3(90, 0, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 1.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	add_child(ring)

	if not label_text.is_empty():
		var label := Label3D.new()
		label.name = "VolumeLabel"
		label.text = label_text
		label.font_size = 48
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = color
		label.outline_modulate = Color(0, 0, 0, 1)
		label.outline_size = 4
		label.position = Vector3(0, max(height, radius) * 0.5 + 1.5, 0)
		add_child(label)

func _volume_material() -> StandardMaterial3D:
	# Kept deliberately faint: the filled dome only hints at the trigger footprint so
	# it never blobs over the camera. The bright ground ring and (for the active
	# mission) the ObjectiveMarker are the readable indicators.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.06)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.08
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

# Polls a world-space point (the hero position) against the volume shape. On an
# outside->inside transition it emits `triggered` once and returns true; staying
# inside or staying outside returns false. Leaving resets so re-entry re-triggers.
func notify_point(global_point: Vector3) -> bool:
	var inside_now := _point_inside(global_point)
	if inside_now and not _inside:
		_inside = true
		triggered.emit(self, "point")
		return true
	if not inside_now:
		_inside = false
	return false

func is_inside() -> bool:
	return _inside

func _point_inside(global_point: Vector3) -> bool:
	# Use the world position when parented into the scene; fall back to the local
	# position when the volume is standalone (unit tests construct it out of tree).
	var center := global_position if is_inside_tree() else position
	var local := global_point - center
	match shape_kind:
		SHAPE_BOX:
			return abs(local.x) <= box_size.x * 0.5 \
				and abs(local.y) <= box_size.y * 0.5 \
				and abs(local.z) <= box_size.z * 0.5
		SHAPE_CYLINDER:
			var horizontal := Vector2(local.x, local.z).length()
			return horizontal <= radius and abs(local.y) <= height * 0.5
		_:
			return local.length() <= radius

# The Area3D body/area signals would otherwise fire for static city geometry
# (towers, props) that happens to overlap the volume, so only a node explicitly in
# the "player" group is allowed through. The hero is a plain Node3D today and uses
# notify_point; this path stays ready for a future physics-body player.
func _on_physics_entered(source) -> void:
	if source is Node and not (source as Node).is_in_group("player"):
		return
	if not _inside:
		_inside = true
		triggered.emit(self, source)
