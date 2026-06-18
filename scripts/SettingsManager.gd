extends Node

# SettingsManager is an autoload singleton that owns Aurora Vigil's player-facing
# options: mouse sensitivity, the three volume sliders (Master/SFX/Music), the
# flight invert-Y toggle, and the difficulty tier. Settings persist to a ConfigFile
# at user://settings.cfg and are applied at startup so a fresh launch matches the
# last saved options.
#
# Difficulty is exposed as plain multipliers (enemy_damage_mult / health_regen_mult
# / event_spawn_mult) that the gameplay systems read at wire time. The defaults all
# resolve to 1.0 so any code path that runs without this autoload (e.g. the headless
# -s unit-test scripts) keeps the original Normal-difficulty behaviour.
#
# Audio routing: at startup this creates two child buses, "SFX" and "Music", sending
# into "Master". AuroraAudio routes one-shots to SFX and loops to Music when those
# buses exist (falling back to Master), so the three sliders are independently live.

const CONFIG_PATH := "user://settings.cfg"

# Difficulty multiplier tables: [enemy_damage, health_regen, event_spawn].
# event_spawn > 1 means events arrive MORE often (shorter interval).
const DIFFICULTY_PRESETS := {
	"Easy": {"enemy_damage": 0.5, "health_regen": 2.0, "event_spawn": 0.7},
	"Normal": {"enemy_damage": 1.0, "health_regen": 1.0, "event_spawn": 1.0},
	"Hard": {"enemy_damage": 1.5, "health_regen": 0.5, "event_spawn": 1.3},
}
const DIFFICULTY_ORDER := ["Easy", "Normal", "Hard"]

# Sensible defaults applied before any config file is read.
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var volume_master: float = 0.9
var volume_sfx: float = 1.0
var volume_music: float = 0.8
var difficulty: String = "Normal"

func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply_all()

# ── Persistence ──

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# No file yet (fresh install) — keep defaults, write them so the file exists.
		save_settings()
		return
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	volume_master = float(cfg.get_value("audio", "master", volume_master))
	volume_sfx = float(cfg.get_value("audio", "sfx", volume_sfx))
	volume_music = float(cfg.get_value("audio", "music", volume_music))
	var diff := str(cfg.get_value("gameplay", "difficulty", difficulty))
	if DIFFICULTY_PRESETS.has(diff):
		difficulty = diff
	_clamp_all()

func save_settings() -> void:
	_clamp_all()
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("audio", "master", volume_master)
	cfg.set_value("audio", "sfx", volume_sfx)
	cfg.set_value("audio", "music", volume_music)
	cfg.set_value("gameplay", "difficulty", difficulty)
	cfg.save(CONFIG_PATH)

func _clamp_all() -> void:
	mouse_sensitivity = clampf(mouse_sensitivity, 0.1, 4.0)
	volume_master = clampf(volume_master, 0.0, 1.0)
	volume_sfx = clampf(volume_sfx, 0.0, 1.0)
	volume_music = clampf(volume_music, 0.0, 1.0)
	if not DIFFICULTY_PRESETS.has(difficulty):
		difficulty = "Normal"

# ── Application ──

func apply_all() -> void:
	apply_audio()

func apply_audio() -> void:
	_set_bus_volume("Master", volume_master)
	_set_bus_volume("SFX", volume_sfx)
	_set_bus_volume("Music", volume_music)

func _ensure_audio_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if linear <= 0.0005:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0005, 1.0)))

# ── Difficulty accessors (default 1.0 when an unknown tier sneaks in) ──

func _mult(key: String) -> float:
	var preset: Dictionary = DIFFICULTY_PRESETS.get(difficulty, DIFFICULTY_PRESETS["Normal"])
	return float(preset.get(key, 1.0))

func enemy_damage_mult() -> float:
	return _mult("enemy_damage")

func health_regen_mult() -> float:
	return _mult("health_regen")

func event_spawn_mult() -> float:
	return _mult("event_spawn")

func set_difficulty(tier: String) -> void:
	if DIFFICULTY_PRESETS.has(tier):
		difficulty = tier
		save_settings()

func has_save_file() -> bool:
	return FileAccess.file_exists(CONFIG_PATH)
