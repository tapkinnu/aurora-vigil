class_name MissionDirector
extends RefCounted

# Owns the story-mission spine: the ordered mission list, current step, HUD text
# and the rule for advancing the campaign when a city event is resolved. Split out
# of Main.gd so mission content stays data-driven and independent of flight/event code.

const DEFAULT_DATA_PATH := "res://data/missions/missions.json"

var progression: ProgressionModel

var mission_step: int = 0

# Raw JSON payload last loaded by `load_data`, exposed for tests/inspection.
var loaded_data: Dictionary = {}

# Hardcoded fallback used only if the JSON data fails to load, so the campaign
# spine still works when content is missing.
var missions: Array[Dictionary] = [
	{"id": "awakening_patrol", "title": "Dawn Patrol", "objective": "Fly through Meridian and answer the first emergency.", "target_kind": "tower_fire", "reward_xp": 80},
	{"id": "spire_rescue", "title": "The Burning Spire", "objective": "Rescue civilians from a tower fire before panic spreads.", "target_kind": "rescue_signal", "reward_xp": 140},
	{"id": "drone_chase", "title": "Ghosts in the Grid", "objective": "Disable rogue civic drones without harming the city.", "target_kind": "rogue_drone", "reward_xp": 180},
	{"id": "stormwall", "title": "Stormwall Protocol", "objective": "Use unlocked powers to protect Meridian during a citywide surge.", "target_kind": "power_surge", "reward_xp": 260},
	{"id": "null_choir_rising", "title": "Null Choir Rising", "objective": "Survive a wave of Null Choir ground units as the surge breaks open.", "target_kind": "power_surge", "reward_xp": 200},
	{"id": "civic_grid_down", "title": "Civic Grid Down", "objective": "Restore power to a blacked-out district and calm the panicking crowds.", "target_kind": "rescue_signal", "reward_xp": 220},
	{"id": "the_long_night", "title": "The Long Night", "objective": "Hold an extended patrol as the emergencies escalate across Meridian.", "target_kind": "tower_fire", "reward_xp": 280},
	{"id": "first_contact", "title": "First Contact", "objective": "Confront a Null Choir commander at the heart of the surge.", "target_kind": "power_surge", "reward_xp": 350}
]

func setup(progression_ref: ProgressionModel, data_path: String = DEFAULT_DATA_PATH) -> void:
	progression = progression_ref
	load_data(data_path)

# Loads the mission table from JSON, replacing the fallback list. Returns true on
# success; on any parse problem it keeps the hardcoded fallback and returns false.
func load_data(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("MissionDirector: missions data not found at %s; using fallback" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("missions"):
		push_error("MissionDirector: malformed missions data at %s; using fallback" % path)
		return false
	var loaded: Array[Dictionary] = []
	for entry in parsed["missions"]:
		loaded.append({
			"id": str(entry.get("id", "")),
			"title": str(entry.get("title", "")),
			"objective": str(entry.get("objective", "")),
			"target_kind": str(entry.get("target_kind", "")),
			"reward_xp": int(entry.get("reward_xp", 0)),
		})
	if loaded.is_empty():
		push_error("MissionDirector: missions data at %s had no entries; using fallback" % path)
		return false
	missions = loaded
	loaded_data = parsed
	return true

func count() -> int:
	return missions.size()

func is_complete() -> bool:
	return mission_step >= missions.size()

func hud_text() -> String:
	var safe_step: int = min(mission_step, missions.size() - 1)
	var m: Dictionary = missions[safe_step]
	var complete_text := ""
	if mission_step >= missions.size():
		complete_text = "\nCampaign loop complete — keep answering procedural city events for XP."
	return "Story Mission %d/%d: %s\n%s%s" % [safe_step + 1, missions.size(), m["title"], m["objective"], complete_text]

# Advances the campaign when an event of the right kind is resolved. Returns a
# feedback suffix (possibly empty) for the HUD's "last event" cue, mirroring the
# original inline behavior in Main.gd.
func advance_for_event(kind: String) -> String:
	if mission_step >= missions.size():
		return ""
	var m: Dictionary = missions[mission_step]
	if str(m.get("target_kind", "")) != kind and mission_step != 0:
		return ""
	var suffix := ""
	var reward := int(m.get("reward_xp", 0))
	if reward > 0:
		var gained: Array[String] = progression.add_xp(reward)
		suffix += " | Story step '%s' complete: +%d XP" % [m["title"], reward]
		if gained.size() > 0:
			suffix += " | story unlock %s" % ", ".join(gained)
	mission_step = min(mission_step + 1, missions.size())
	return suffix
