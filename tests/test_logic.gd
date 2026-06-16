extends SceneTree

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")

var failed := false

func _init() -> void:
	_test_progression_unlocks()
	_test_save_load_roundtrip()
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
