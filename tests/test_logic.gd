extends SceneTree

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")

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
	_assert(not p.has_power("radiant_beam"), "radiant beam locked initially")
	var gained := p.add_xp(100)
	_assert(p.level == 2, "100 xp reaches level 2")
	_assert(gained.has("radiant_beam"), "level 2 unlocks radiant beam")
	_assert(p.has_power("radiant_beam"), "radiant beam now available")
	p.add_xp(500)
	_assert(p.level >= 4, "large xp levels up repeatedly")
	_assert(p.has_power("sonic_burst"), "sonic burst unlocks by level 3")
	_assert(p.has_power("aegis_field"), "aegis field unlocks by level 4")

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
