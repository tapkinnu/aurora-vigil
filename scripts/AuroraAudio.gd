extends Node
class_name AuroraAudioManager

const AUDIO_PATHS: Dictionary = {
	"flight_boost_burst": "res://assets/audio/sfx/flight/flight_boost_burst.ogg",
	"power_radiant_beam_fire": "res://assets/audio/sfx/powers/power_radiant_beam_fire.ogg",
	"power_sonic_burst": "res://assets/audio/sfx/powers/power_sonic_burst.ogg",
	"power_aegis_activate": "res://assets/audio/sfx/powers/power_aegis_activate.ogg",
	"power_orbit_sprint": "res://assets/audio/sfx/powers/power_orbit_sprint.ogg",
	"event_alert_rescue_needed": "res://assets/audio/sfx/events/event_alert_rescue_needed.ogg",
	"drone_alert": "res://assets/audio/sfx/enemies/drone_alert.ogg",
	"drone_death": "res://assets/audio/sfx/enemies/drone_death.ogg",
	"stinger_mission_intro": "res://assets/audio/sfx/stingers/stinger_mission_intro.ogg",
	"ambience_city_base_loop": "res://assets/audio/ambience/ambience_city_base_loop.ogg",
	"music_city_exploration": "res://assets/audio/music/music_city_exploration.ogg",
	"civic_grid_alert": "res://assets/audio/voices/civic_grid/civic_grid_alert.ogg",
	"civilian_panicked_help": "res://assets/audio/voices/civilian_panicked/civilian_panicked_help.ogg",
	"civilian_grateful_thanks": "res://assets/audio/voices/civilian_grateful/civilian_grateful_thanks.ogg",
	"emergency_dispatcher_dispatch": "res://assets/audio/voices/emergency_dispatcher/emergency_dispatcher_dispatch.ogg",
	"null_choir_cmdr_threat": "res://assets/audio/voices/null_choir_cmdr/null_choir_cmdr_threat.ogg",
}

const TRIGGER_RULES: Dictionary = {
	"flight_boost_burst": {"cooldown": 0.65, "probability": 1.0, "volume_db": -4.0},
	"power_radiant_beam_fire": {"cooldown": 0.35, "probability": 1.0, "volume_db": -5.0},
	"power_sonic_burst": {"cooldown": 0.45, "probability": 1.0, "volume_db": -5.0},
	"power_aegis_activate": {"cooldown": 1.25, "probability": 1.0, "volume_db": -6.0},
	"power_orbit_sprint": {"cooldown": 0.55, "probability": 1.0, "volume_db": -5.0},
	"event_alert_rescue_needed": {"cooldown": 8.0, "probability": 0.85, "volume_db": -7.0},
	"drone_alert": {"cooldown": 5.0, "probability": 0.8, "volume_db": -6.0},
	"drone_death": {"cooldown": 2.5, "probability": 1.0, "volume_db": -7.0},
	"stinger_mission_intro": {"cooldown": 20.0, "probability": 1.0, "volume_db": -8.0},
	"civic_grid_alert": {"cooldown": 12.0, "probability": 0.8, "volume_db": -5.0},
	"civilian_panicked_help": {"cooldown": 10.0, "probability": 0.75, "volume_db": -4.0},
	"civilian_grateful_thanks": {"cooldown": 12.0, "probability": 0.7, "volume_db": -5.0},
	"emergency_dispatcher_dispatch": {"cooldown": 14.0, "probability": 0.75, "volume_db": -6.0},
	"null_choir_cmdr_threat": {"cooldown": 18.0, "probability": 0.65, "volume_db": -5.0},
}

const LOOP_RULES: Dictionary = {
	"ambience_city_base_loop": {"volume_db": -16.0},
	"music_city_exploration": {"volume_db": -18.0},
}

var _last_played: Dictionary = {}
var _loops: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_rng.seed = 20260616 + int(Time.get_unix_time_from_system() * 1000.0) % 1000

func trigger(id: String) -> bool:
	if not AUDIO_PATHS.has(id):
		push_warning("AuroraAudio: missing AUDIO_PATHS entry for trigger '%s'" % id)
		return false

	var rule: Dictionary = TRIGGER_RULES.get(id, {})
	var cooldown: float = float(rule.get("cooldown", 0.0))
	var probability: float = float(rule.get("probability", 1.0))
	var volume_db: float = float(rule.get("volume_db", -8.0))

	if not _cooldown_ok(id, cooldown):
		return false
	if probability < 1.0 and _rng.randf() > probability:
		return false

	_play_once(str(AUDIO_PATHS[id]), volume_db)
	return true

func start_loop(id: String) -> bool:
	if not AUDIO_PATHS.has(id):
		push_warning("AuroraAudio: missing AUDIO_PATHS entry for loop '%s'" % id)
		return false
	var rule: Dictionary = LOOP_RULES.get(id, {})
	var volume_db: float = float(rule.get("volume_db", -14.0))
	_stop_loop(id)

	var path: String = str(AUDIO_PATHS[id])
	if not ResourceLoader.exists(path):
		push_warning("AuroraAudio: missing loop file '%s'" % path)
		return false
	var loaded = load(path)
	if not loaded is AudioStream:
		push_warning("AuroraAudio: loop is not AudioStream '%s'" % path)
		return false

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = loaded as AudioStream
	player.volume_db = volume_db
	player.bus = _safe_bus("Music")
	add_child(player)
	player.play()
	_loops[id] = player
	return true

func stop_loop(id: String) -> void:
	_stop_loop(id)

func stop_all() -> void:
	# Stop and free EVERY active player — tracked loops AND the one-shot players
	# spawned by _play_once (which otherwise only free themselves on `finished`).
	# Called from Main._cleanup_for_quit before quit; one-shots still playing at
	# that moment (event alerts, drone alerts, mission stingers) would otherwise
	# leave their OGG streams referenced and trip Godot's resource-leak detector
	# at exit ("resources still in use at exit"). get_children() returns a copy,
	# so freeing during iteration is safe; free() immediately releases the stream.
	for child in get_children():
		if child is AudioStreamPlayer:
			var p: AudioStreamPlayer = child as AudioStreamPlayer
			p.stop()
			p.stream = null
			p.free()
	_loops.clear()

func _stop_loop(id: String) -> void:
	if not _loops.has(id):
		return
	var player = _loops[id]
	if player is AudioStreamPlayer:
		player.stop()
		player.queue_free()
	_loops.erase(id)

func _cooldown_ok(id: String, cooldown: float) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = -1000.0
	if _last_played.has(id):
		last = float(_last_played[id])
	_last_played[id] = now
	return now - last >= cooldown

func _play_once(path: String, volume_db: float) -> void:
	if not ResourceLoader.exists(path):
		push_warning("AuroraAudio: missing one-shot file '%s'" % path)
		return
	var loaded = load(path)
	if not loaded is AudioStream:
		push_warning("AuroraAudio: one-shot is not AudioStream '%s'" % path)
		return

	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = loaded as AudioStream
	player.volume_db = volume_db
	player.bus = _safe_bus("SFX")
	add_child(player)
	player.play()
	player.finished.connect(Callable(player, "queue_free"))

# Returns `bus_name` if that bus exists (SettingsManager creates SFX/Music at
# startup), otherwise falls back to the always-present Master bus so audio never
# routes to a missing bus (e.g. in headless test contexts without SettingsManager).
func _safe_bus(bus_name: String) -> String:
	return bus_name if AudioServer.get_bus_index(bus_name) != -1 else "Master"
