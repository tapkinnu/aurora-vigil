extends SceneTree

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")
const MissionDirector = preload("res://scripts/MissionDirector.gd")
const CityEventSystem = preload("res://scripts/CityEventSystem.gd")
const PowerSystem = preload("res://scripts/PowerSystem.gd")

var failed := false

# Minimal stand-ins for the mission/event systems so SaveGame can be exercised
# without building the full scene tree.
class _MissionHolder:
	var mission_step: int = 0

class _EventHolder:
	var resolved_events: int = 0

func _init() -> void:
	_test_progression_unlocks()
	_test_save_load_roundtrip()
	_test_savegame_roundtrip()
	_test_mission_data()
	_test_event_data()
	_test_power_data()
	if failed:
		print("AURORA_LOGIC_TESTS: FAIL")
		quit(1)
	else:
		print("AURORA_LOGIC_TESTS: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error(msg)

func _test_progression_unlocks() -> void:
	var p := ProgressionModel.new()
	_assert(p.level == 1, "starts at level 1")
	_assert(p.has_power("flight"), "starts with flight")
	_assert(p.has_power("boost"), "starts with boost")
	_assert(not p.has_power("rescue_lift"), "rescue lift locked initially")
	var gained := p.add_xp(100)
	_assert(p.level == 2, "100 xp reaches level 2")
	_assert(gained.has("rescue_lift"), "level 2 unlocks rescue lift")
	_assert(p.has_power("rescue_lift"), "rescue lift now available")
	var gained3 := p.add_xp(150)  # cumulative 250 XP
	_assert(p.level == 3, "250 xp reaches level 3")
	_assert(gained3.has("radiant_beam"), "level 3 unlocks radiant beam")
	_assert(p.has_power("radiant_beam"), "radiant beam now available")
	var gained5 := p.add_xp(450)  # cumulative 700 XP, jumps two levels
	_assert(p.level == 5, "700 xp reaches level 5")
	_assert(gained5.has("sonic_burst"), "level 4 unlocks sonic burst")
	_assert(gained5.has("aegis_field"), "level 5 unlocks aegis field")
	_assert(p.has_power("sonic_burst"), "sonic burst unlocks by level 4")
	_assert(p.has_power("aegis_field"), "aegis field unlocks by level 5")

func _test_save_load_roundtrip() -> void:
	var p := ProgressionModel.new()
	p.add_xp(300)
	var data := p.save_state()
	var q := ProgressionModel.new()
	q.load_state(data)
	_assert(q.level == p.level, "level roundtrips")
	_assert(q.xp == p.xp, "xp roundtrips")
	_assert(q.unlocked == p.unlocked, "unlocked powers roundtrip")

func _test_savegame_roundtrip() -> void:
	var p := ProgressionModel.new()
	p.add_xp(300)
	var ms := _MissionHolder.new()
	ms.mission_step = 2
	var ev := _EventHolder.new()
	ev.resolved_events = 5
	var err := SaveGame.save(p, ms, ev)
	_assert(err == OK, "savegame writes file")
	var p2 := ProgressionModel.new()
	var ms2 := _MissionHolder.new()
	var ev2 := _EventHolder.new()
	var loaded := SaveGame.load_into(p2, ms2, ev2)
	_assert(loaded, "savegame loads file")
	_assert(p2.level == p.level, "savegame level roundtrips")
	_assert(p2.xp == p.xp, "savegame xp roundtrips")
	_assert(p2.unlocked == p.unlocked, "savegame unlocked roundtrips")
	_assert(ms2.mission_step == 2, "savegame mission step roundtrips")
	_assert(ev2.resolved_events == 5, "savegame resolved count roundtrips")

func _test_mission_data() -> void:
	var md := MissionDirector.new()
	_assert(md.load_data("res://data/missions/missions.json"), "missions json loads")
	_assert(md.loaded_data.has("missions"), "missions loaded_data populated")
	_assert(md.count() == 9, "nine missions loaded from json")
	_assert(str(md.missions[0]["title"]) == "Dawn Patrol", "first mission title is Dawn Patrol")
	_assert(str(md.missions[0]["target_kind"]) == "tower_fire", "first mission target_kind matches json")
	_assert(int(md.missions[0]["reward_xp"]) == 80, "first mission reward_xp matches json")
	_assert(str(md.missions[8]["id"]) == "dawn_aftershock", "ninth mission id is dawn_aftershock")
	_assert(str(md.missions[8]["title"]) == "Dawn Aftershock", "ninth mission title matches json")
	_assert(str(md.missions[8]["target_kind"]) == "power_surge", "ninth mission target_kind matches json")
	_assert(int(md.missions[8]["reward_xp"]) == 320, "ninth mission reward_xp matches json")

func _test_event_data() -> void:
	var ev := CityEventSystem.new()
	_assert(ev.load_data("res://data/events/events.json"), "events json loads")
	_assert(ev.event_kinds.size() == 5, "five event kinds loaded")
	for kind in ["tower_fire", "rogue_drone", "power_surge", "rescue_signal", "bridge_collapse"]:
		_assert(ev.event_kinds.has(kind), "event kind present: %s" % kind)
	_assert(ev.seed_events_data.size() == 3, "three seed events loaded")
	_assert(ev.timed_spawn_data.get("types", []).size() >= 1, "timed_spawn has at least one type")
	_assert(ev.timed_spawn_data.get("positions", []).size() >= 1, "timed_spawn has at least one position")
	for t in ev.timed_spawn_data.get("types", []):
		_assert(ev.event_kinds.has(str(t)), "timed_spawn type '%s' defined in event_kinds" % str(t))
	_assert(ev.timed_spawn_data.get("types", []).has("bridge_collapse"), "bridge_collapse in timed_spawn.types")
	# Round-trip: resolve reward comes from the data lookup, not a constant.
	_assert(ev._event_reward("tower_fire") == 70, "tower_fire reward resolves to 70 from data")
	_assert(ev.format_event_name("tower_fire") == "Tower fire", "tower_fire display name from data")
	_assert(ev._power_matches_event("radiant_beam", "tower_fire"), "radiant_beam matches tower_fire from data")

func _test_power_data() -> void:
	var ps := PowerSystem.new()
	_assert(ps.load_data("res://data/powers/powers.json"), "powers json loads")
	_assert(ps.power_data.size() >= 4, "at least four powers loaded")
	_assert(ps.power_data.has("radiant_beam"), "radiant_beam power present")
	var c: Color = ps.power_data["radiant_beam"]["flash_color"]
	_assert(c.is_equal_approx(Color(1.0, 0.72, 0.22, 1.0)), "radiant_beam flash_color matches original")
