class_name EnemySystem
extends RefCounted

# Owns the Null Choir: violet energy-humanoid ground units (original IP) that erupt
# from power_surge emergencies and stalk the hero across the avenues. Split out of
# Main.gd. `host` is the Main Node3D coordinator (add_child, create_tween, _mat).
#
# Damage is *reported*, not applied: update() accumulates intended melee damage from
# units in contact, and HealthSystem pulls it via take_pending_damage() so the aegis
# field can veto it. sonic_burst (Q) fades units out through disable_in_range().

const UNITS_PER_SURGE_MIN: int = 2
const UNITS_PER_SURGE_MAX: int = 5
const MOVE_SPEED_MIN: float = 3.0
const MOVE_SPEED_MAX: float = 4.0
const CONTACT_RANGE: float = 3.0
const CONTACT_DAMAGE: float = 5.0
const CONTACT_COOLDOWN: float = 1.0
const SONIC_RADIUS: float = 22.0
const GROUND_Y: float = 1.0
const UNIT_COLOR: Color = Color(0.45, 0.12, 0.78, 1.0)

var host
var hero: Node3D
var events
var progression: ProgressionModel

# Difficulty scaling: contact melee damage is multiplied by this (Easy 0.5 .. Hard
# 1.5). Defaults to 1.0 so any code path that runs without SettingsManager wiring
# keeps the original Normal-difficulty behaviour.
var damage_mult: float = 1.0

# Per-unit record: { node, speed, contact_cd, dying }.
var units: Array = []
# Instance ids of power_surge markers already converted into a wave, so a standing
# surge spawns its Null Choir exactly once.
var _handled_surges: Dictionary = {}
var _pending_damage: float = 0.0
var rng := RandomNumberGenerator.new()

func setup(host_ref, hero_ref: Node3D, events_ref, progression_ref: ProgressionModel) -> void:
	host = host_ref
	hero = hero_ref
	events = events_ref
	progression = progression_ref
	rng.seed = 20260618

func update(delta: float) -> void:
	_check_for_surges()
	for u in units.duplicate():
		var node: MeshInstance3D = u["node"]
		if not is_instance_valid(node):
			units.erase(u)
			continue
		if u["dying"]:
			continue
		_step_unit(u, delta)

func _check_for_surges() -> void:
	if events == null:
		return
	# Prune ids whose surge has been resolved (no longer a live marker) so the dict
	# cannot grow forever and a reused instance id still spawns a fresh wave.
	var live := {}
	for marker in events.event_nodes:
		if is_instance_valid(marker):
			live[marker.get_instance_id()] = true
	for id in _handled_surges.keys():
		if not live.has(id):
			_handled_surges.erase(id)
	for marker in events.event_nodes:
		if not is_instance_valid(marker):
			continue
		if str(marker.get_meta("kind", "")) != "power_surge":
			continue
		var id: int = marker.get_instance_id()
		if _handled_surges.has(id):
			continue
		_handled_surges[id] = true
		_spawn_wave(Vector3(marker.position.x, GROUND_Y, marker.position.z))

func _spawn_wave(ground_pos: Vector3) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 2.0
	var count := rng.randi_range(UNITS_PER_SURGE_MIN, UNITS_PER_SURGE_MAX)
	for i in range(count):
		var node := MeshInstance3D.new()
		node.name = "NullChoirUnit_%d" % (units.size() + i)
		node.mesh = capsule
		var offset := Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
		node.position = ground_pos + offset
		node.position.y = GROUND_Y
		node.material_override = host._mat(UNIT_COLOR * 0.4, UNIT_COLOR, 1.6)
		# Violet ground glow so the unit reads as an energy being against the asphalt.
		var glow := OmniLight3D.new()
		glow.name = "NullChoirGlow"
		glow.position = Vector3(0, 1.0, 0)
		glow.light_color = UNIT_COLOR
		glow.light_energy = 6.0
		glow.omni_range = 7.0
		node.add_child(glow)
		host.add_child(node)
		units.append({
			"node": node,
			"speed": rng.randf_range(MOVE_SPEED_MIN, MOVE_SPEED_MAX),
			"contact_cd": 0.0,
			"dying": false,
		})

func _step_unit(u: Dictionary, delta: float) -> void:
	var node: MeshInstance3D = u["node"]
	var to_hero: Vector3 = hero.position - node.position
	to_hero.y = 0.0
	var dist := to_hero.length()
	if dist > CONTACT_RANGE and dist > 0.01:
		node.position += to_hero.normalized() * u["speed"] * delta
		node.position.y = GROUND_Y
		node.look_at(Vector3(hero.position.x, GROUND_Y, hero.position.z), Vector3.UP)
	# Contact damage on a per-unit cooldown so a clinging unit cannot burst the hero.
	u["contact_cd"] = max(0.0, u["contact_cd"] - delta)
	if dist <= CONTACT_RANGE and u["contact_cd"] <= 0.0:
		u["contact_cd"] = CONTACT_COOLDOWN
		_pending_damage += CONTACT_DAMAGE * damage_mult

# HealthSystem pulls (and clears) the melee damage accumulated since the last frame.
func take_pending_damage() -> float:
	var d := _pending_damage
	_pending_damage = 0.0
	return d

# sonic_burst (Q): fade out every live unit within range and free it after the
# shrink animation. Returns how many units were disabled.
func disable_in_range(center: Vector3, radius: float = SONIC_RADIUS) -> int:
	var disabled := 0
	for u in units:
		var node: MeshInstance3D = u["node"]
		if not is_instance_valid(node) or u["dying"]:
			continue
		if center.distance_to(node.position) <= radius:
			u["dying"] = true
			disabled += 1
			var tween: Tween = host._remember_tween(host.create_tween())
			tween.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), 0.5)
			tween.parallel().tween_property(node, "position:y", GROUND_Y + 2.5, 0.5)
			tween.tween_callback(node.queue_free)
	return disabled

func active_count() -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u["node"]) and not u["dying"]:
			n += 1
	return n

func nearest_distance(pos: Vector3) -> float:
	var best := INF
	for u in units:
		var node: MeshInstance3D = u["node"]
		if not is_instance_valid(node) or u["dying"]:
			continue
		best = min(best, pos.distance_to(node.position))
	return best
