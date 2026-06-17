class_name CivilianSystem
extends RefCounted

# Owns Meridian's ambient civilian crowd: a pool of emissive capsule pedestrians
# that wander the sidewalks beside the avenues, panic when a city emergency erupts
# nearby, and can be calmed by the hero's rescue lift. Split out of Main.gd so the
# crowd stays self-contained. `host` is the Main Node3D coordinator (add_child,
# _mat helper); `audio_dispatch` is a Callable(String) routed back through Main so
# the literal AuroraAudio.trigger(...) calls (and the wiring contract) stay in one
# place.

const CIVILIAN_COUNT: int = 30
const WALK_SPEED: float = 2.4
const PANIC_SPEED: float = 5.2
const PANIC_RADIUS: float = 30.0
const RESCUE_RADIUS: float = 22.0
const LOD_DISTANCE: float = 80.0
const LOD_INTERVAL: float = 0.5
const GROUND_Y: float = 1.0
const FIELD_HALF: float = 104.0

# Calm-state palette — soft emissive civvies so they read against the dark city.
const CALM_COLORS: Array[Color] = [
	Color(0.45, 0.75, 1.0, 1.0),
	Color(0.6, 1.0, 0.85, 1.0),
	Color(1.0, 0.85, 0.55, 1.0),
	Color(0.85, 0.7, 1.0, 1.0),
	Color(0.7, 0.95, 0.6, 1.0),
	Color(1.0, 0.7, 0.85, 1.0),
]
const PANIC_COLOR: Color = Color(1.0, 0.3, 0.1, 1.0)

var host
var hero: Node3D
var events
var audio_dispatch: Callable

# Per-civilian record: { node, axis, gridline, side, target, color, panic, lod_accum }.
var civilians: Array = []
var rng := RandomNumberGenerator.new()

func setup(host_ref, hero_ref: Node3D, events_ref, audio_dispatch_callable: Callable) -> void:
	host = host_ref
	hero = hero_ref
	events = events_ref
	audio_dispatch = audio_dispatch_callable
	rng.seed = 20260617
	_spawn_crowd()

func _spawn_crowd() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	for i in range(CIVILIAN_COUNT):
		# Half the crowd hugs a north–south avenue (walking in Z), half an
		# east–west avenue (walking in X). The fixed perpendicular curb offset
		# keeps every pedestrian on the sidewalk strip and clear of the roadway.
		var axis: int = i % 2
		var gridline: int = rng.randi_range(-4, 4)
		var side: float = 1.0 if rng.randi_range(0, 1) == 0 else -1.0
		var curb: float = (gridline * 22.0) + side * 4.6
		var along: float = rng.randf_range(-FIELD_HALF, FIELD_HALF)
		var pos: Vector3 = Vector3(curb, GROUND_Y, along) if axis == 0 else Vector3(along, GROUND_Y, curb)
		var color: Color = CALM_COLORS[i % CALM_COLORS.size()]
		var node := MeshInstance3D.new()
		node.name = "Civilian_%d" % i
		node.mesh = capsule
		node.position = pos
		node.material_override = host._mat(color * 0.5, color, 0.9)
		host.add_child(node)
		civilians.append({
			"node": node,
			"axis": axis,
			"curb": curb,
			"target": _pick_target(axis, curb, along),
			"color": color,
			"panic": false,
			"lod_accum": rng.randf() * LOD_INTERVAL,
		})

# A wander target on the same sidewalk strip: same curb offset, a new point along
# the avenue. Keeps pedestrians on the pavement and off the road centerlines.
func _pick_target(axis: int, curb: float, along: float) -> Vector3:
	var next_along: float = clamp(along + rng.randf_range(-18.0, 18.0), -FIELD_HALF, FIELD_HALF)
	var jitter: float = rng.randf_range(-0.8, 0.8)
	if axis == 0:
		return Vector3(curb + jitter, GROUND_Y, next_along)
	return Vector3(next_along, GROUND_Y, curb + jitter)

func update(delta: float) -> void:
	for c in civilians:
		var node: MeshInstance3D = c["node"]
		if not is_instance_valid(node):
			continue
		# LOD: pedestrians far from the hero only step on a 2 Hz cadence.
		var far: bool = hero.position.distance_to(node.position) > LOD_DISTANCE
		var step_delta := delta
		if far:
			c["lod_accum"] += delta
			if c["lod_accum"] < LOD_INTERVAL:
				continue
			step_delta = c["lod_accum"]
			c["lod_accum"] = 0.0
		_update_panic_state(c)
		_step_civilian(c, step_delta)

func _update_panic_state(c: Dictionary) -> void:
	var node: MeshInstance3D = c["node"]
	var nearest = events.nearest_event() if events != null else null
	var panicking := false
	if nearest != null and is_instance_valid(nearest):
		panicking = node.position.distance_to(nearest.position) <= PANIC_RADIUS
	if panicking and not c["panic"]:
		c["panic"] = true
		node.material_override = host._mat(PANIC_COLOR * 0.5, PANIC_COLOR, 1.4)
		if audio_dispatch.is_valid():
			audio_dispatch.call("civilian_panicked_help")
	elif not panicking and c["panic"]:
		c["panic"] = false
		var col: Color = c["color"]
		node.material_override = host._mat(col * 0.5, col, 0.9)

func _step_civilian(c: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = c["node"]
	var target: Vector3 = c["target"]
	var speed: float = PANIC_SPEED if c["panic"] else WALK_SPEED
	var to_target: Vector3 = target - node.position
	to_target.y = 0.0
	if to_target.length() < 1.0:
		var along: float = node.position.z if c["axis"] == 0 else node.position.x
		c["target"] = _pick_target(c["axis"], c["curb"], along)
		return
	var dir: Vector3 = to_target.normalized()
	node.position += dir * speed * delta
	if c["panic"]:
		# Panic jitter: small perpendicular shudder so the crowd reads as frantic.
		node.position.x += sin(node.position.z * 6.0) * 0.05
	node.position.y = GROUND_Y

# Called when the hero fires rescue lift (R): calms every panicking civilian within
# range and thanks them. Returns the number of pedestrians reassured.
func rescue_nearby() -> int:
	var calmed := 0
	for c in civilians:
		var node: MeshInstance3D = c["node"]
		if not is_instance_valid(node):
			continue
		if c["panic"] and hero.position.distance_to(node.position) <= RESCUE_RADIUS:
			c["panic"] = false
			var col: Color = c["color"]
			node.material_override = host._mat(col * 0.5, col, 0.9)
			calmed += 1
	if calmed > 0 and audio_dispatch.is_valid():
		audio_dispatch.call("civilian_grateful_thanks")
	return calmed

func panicking_count() -> int:
	var n := 0
	for c in civilians:
		if c["panic"]:
			n += 1
	return n
