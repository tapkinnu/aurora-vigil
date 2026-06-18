class_name HealthSystem
extends RefCounted

# Owns the hero's survivability loop: hit points, the aegis-field damage window,
# passive regen when the streets are clear, and the death/respawn cycle. Split out
# of Main.gd. `host` is the Main Node3D coordinator; damage is sourced from the
# EnemySystem (Null Choir melee) and from rogue-drone markers in the CityEventSystem.

const MAX_HEALTH: float = 100.0
const RESPAWN_HEALTH: float = 50.0
const AEGIS_DURATION: float = 3.0
const REGEN_RATE: float = 2.0
const REGEN_SAFE_RADIUS: float = 30.0
const DRONE_DAMAGE: float = 10.0
const DRONE_RANGE: float = 2.0
const DRONE_COOLDOWN: float = 1.0
const RESPAWN_DELAY: float = 3.0

var host
var hero: Node3D
var enemy_system
var events

# Difficulty scaling: passive regen rate is multiplied by this (Easy 2.0 .. Hard
# 0.5). Defaults to 1.0 so headless/unit contexts keep Normal regen.
var regen_mult: float = 1.0

var health: float = MAX_HEALTH
var aegis_timer: float = 0.0
var game_over: bool = false
var checkpoint: Vector3 = Vector3(0, 28, 36)
var _drone_cd: float = 0.0
var _respawn_timer: float = 0.0

func setup(host_ref, hero_ref: Node3D, enemy_system_ref, events_ref) -> void:
	host = host_ref
	hero = hero_ref
	enemy_system = enemy_system_ref
	events = events_ref
	if hero != null:
		checkpoint = hero.position

# Hero pressed E with aegis_field unlocked — open a 3 s damage-immunity window.
func activate_aegis() -> void:
	aegis_timer = AEGIS_DURATION

func is_aegis_active() -> bool:
	return aegis_timer > 0.0

func update(delta: float) -> void:
	if game_over:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return

	aegis_timer = max(0.0, aegis_timer - delta)
	_drone_cd = max(0.0, _drone_cd - delta)

	var incoming := 0.0
	if enemy_system != null:
		incoming += enemy_system.take_pending_damage()
	incoming += _drone_contact_damage()

	# Aegis field nullifies all incoming damage while it is up.
	if is_aegis_active():
		incoming = 0.0

	if incoming > 0.0:
		health -= incoming
	elif _streets_clear():
		health = min(MAX_HEALTH, health + REGEN_RATE * regen_mult * delta)

	health = clamp(health, 0.0, MAX_HEALTH)
	if health <= 0.0:
		_enter_game_over()

# Rogue-drone bodies in the CityEventSystem deal a heavier hit on contact, gated by
# their own cooldown so a hovering drone cannot drain the hero instantly.
func _drone_contact_damage() -> float:
	if events == null or _drone_cd > 0.0:
		return 0.0
	for marker in events.event_nodes:
		if not is_instance_valid(marker):
			continue
		if str(marker.get_meta("kind", "")) != "rogue_drone":
			continue
		if hero.position.distance_to(marker.position) <= DRONE_RANGE:
			_drone_cd = DRONE_COOLDOWN
			return DRONE_DAMAGE
	return 0.0

func _streets_clear() -> bool:
	if enemy_system != null and enemy_system.nearest_distance(hero.position) <= REGEN_SAFE_RADIUS:
		return false
	if events != null:
		for marker in events.event_nodes:
			if not is_instance_valid(marker):
				continue
			if str(marker.get_meta("kind", "")) != "rogue_drone":
				continue
			if hero.position.distance_to(marker.position) <= REGEN_SAFE_RADIUS:
				return false
	return true

func _enter_game_over() -> void:
	if game_over:
		return
	game_over = true
	health = 0.0
	_respawn_timer = RESPAWN_DELAY

func _respawn() -> void:
	game_over = false
	health = RESPAWN_HEALTH
	aegis_timer = 0.0
	if hero != null:
		hero.position = checkpoint
