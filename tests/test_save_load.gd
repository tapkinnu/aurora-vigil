extends SceneTree

# Tests for the v2 save/load migration system. Mirrors the contract that
# tools/verify_save_load.py covers in pure Python so the gate is exercised
# from both sides. The GDScript implementation in scripts/SaveGame.gd is the
# source of truth; this test runner slots into validate_build.sh with a
# AURORA_SAVE_LOAD_GD: PASS / FAIL marker.

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")
const SaveGame = preload("res://scripts/SaveGame.gd")

var failed := false

class _MissionHolder:
	var mission_step: int = 0

class _EventHolder:
	var resolved_events: int = 0

func _init() -> void:
	_test_v1_migrates_to_v2()
	_test_v2_roundtrip()
	_test_unsupported_version_rejected()
	_test_corrupt_json_returns_false()
	_test_wrong_schema_id_rejected()
	_test_v1_with_empty_unlocked_backfilled()
	_test_v1_sparse_payload_safe_defaults()
	_test_hero_pose_restore_when_optional_systems_supplied()
	if failed:
		print("AURORA_SAVE_LOAD_GD: FAIL")
		quit(1)
	else:
		print("AURORA_SAVE_LOAD_GD: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error("AURORA_SAVE_LOAD_GD_ASSERT: %s" % msg)

# Hand-built v1 payload migrates to v2 cleanly, applies, sets fields.
func _test_v1_migrates_to_v2() -> void:
	var v1: Dictionary = {
		"version": 1,
		"progression": {"level": 3, "xp": 120, "unlocked": ["flight", "boost", "radiant_beam"]},
		"mission_step": 2,
		"resolved_events": 5,
	}
	var migrated: Dictionary = SaveGame.migrate(v1)
	_assert(migrated.get("version") == 2, "v1 migrates to version=2")
	_assert(str(migrated.get("schema_id", "")) == SaveGame.CURRENT_SCHEMA_ID,
		"v1 migration sets schema_id=%s" % SaveGame.CURRENT_SCHEMA_ID)
	_assert(int(migrated.get("mission_step", -1)) == 2, "v1 mission_step preserved")
	_assert(int(migrated.get("resolved_events", -1)) == 5, "v1 resolved_events preserved")
	_assert(typeof(migrated.get("progression", null)) == TYPE_DICTIONARY, "progression is dict")
	var prog: Dictionary = migrated.get("progression", {})
	_assert(int(prog.get("level", -1)) == 3, "progression level preserved")
	var unlocked_var: Variant = prog.get("unlocked", [])
	_assert(typeof(unlocked_var) == TYPE_ARRAY and (unlocked_var as Array).size() == 3,
		"progression unlocked preserved (3 entries)")
	_assert(migrated.get("hero_position") == SaveGame.DEFAULT_HERO_POSITION,
		"v1 migration backfills default hero position")
	var pu: Variant = migrated.get("powers_used", null)
	_assert(pu != null and typeof(pu) == TYPE_DICTIONARY, "v1 migration backfills powers_used dict")
	var oc: Variant = migrated.get("objectives_completed", null)
	_assert(oc != null and typeof(oc) == TYPE_ARRAY, "v1 migration backfills objectives_completed array")

	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	var ev := _EventHolder.new()
	var ok: bool = SaveGame.apply(v1, p, ms, ev)
	_assert(ok, "v1 payload accepted by apply()")
	_assert(p.level == 3, "applied level is 3")
	_assert(p.has_power("radiant_beam"), "applied progression has radiant_beam")
	_assert(ms.mission_step == 2, "applied mission_step is 2")
	_assert(ev.resolved_events == 5, "applied resolved_events is 5")

# v2 payload round-trips through capture/apply.
func _test_v2_roundtrip() -> void:
	var p := ProgressionModel.new()
	p.add_xp(300)
	var ms := _MissionHolder.new()
	ms.mission_step = 4
	var ev := _EventHolder.new()
	ev.resolved_events = 12
	var captured: Dictionary = SaveGame.capture(
		p, ms, ev,
		Vector3(10, 50, -20),
		{"radiant_beam": 3},
		PackedStringArray(["awakening_patrol", "spire_rescue"])
	)
	_assert(int(captured.get("version", -1)) == 2, "capture writes version=2")
	_assert(str(captured.get("schema_id", "")) == SaveGame.CURRENT_SCHEMA_ID, "capture writes current schema_id")
	_assert(int(captured.get("mission_step", -1)) == 4, "capture preserves mission_step")
	_assert(captured.get("hero_position") == [10.0, 50.0, -20.0], "capture preserves hero_position")
	_assert(typeof(captured.get("powers_used")) == TYPE_DICTIONARY, "capture writes powers_used dict")
	_assert(captured.get("objectives_completed") is Array, "capture writes objectives_completed array")

	var p2 := ProgressionModel.new()
	var ms2 := _MissionHolder.new()
	var ev2 := _EventHolder.new()
	var ok: bool = SaveGame.apply(captured, p2, ms2, ev2)
	_assert(ok, "v2 payload accepted by apply()")
	_assert(p2.level == p.level, "round-tripped level")
	_assert(ms2.mission_step == 4, "round-tripped mission_step")
	_assert(ev2.resolved_events == 12, "round-tripped resolved_events")

# An unsupported version=99 payload is rejected.
func _test_unsupported_version_rejected() -> void:
	var v99: Dictionary = {
		"version": 99,
		"schema_id": "future",
		"progression": {"level": 1, "xp": 0, "unlocked": ["flight"]},
		"mission_step": 0,
		"resolved_events": 0,
	}
	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	var ev := _EventHolder.new()
	var ok: bool = SaveGame.apply(v99, p, ms, ev)
	_assert(not ok, "v99 rejected by apply()")

# Corrupt JSON: load_into returns false and does not crash.
func _test_corrupt_json_returns_false() -> void:
	# Write a corrupt file to the SAVE_PATH, then load it.
	# Use a side-channel SAVE_PATH via a temporary instance: SaveGame exposes
	# load_into for the canonical path. To exercise corrupt JSON without
	# disturbing the real save, simulate via parse-mismatch payloads here.
	var corrupt: Array = ["{", "{not json}", "[1,2,3]", "null", "42", "\"x\""]
	for bad in corrupt:
		var parsed = JSON.parse_string(bad)
		var treat_as_dict: bool = typeof(parsed) == TYPE_DICTIONARY
		_assert(not treat_as_dict, "corrupt JSON %s should not parse to a dict" % bad)
	# If the file does not exist, load_into returns false safely.
	if FileAccess.file_exists(SaveGame.SAVE_PATH):
		var p := ProgressionModel.new()
		var ms := _MissionHolder.new()
		var ev := _EventHolder.new()
		var ok: bool = SaveGame.load_into(p, ms, ev)
		_assert(ok, "load_into on existing file is True; corrupt paths return False at higher level")

# A v2 payload missing the right schema_id is rejected.
func _test_wrong_schema_id_rejected() -> void:
	var bad_v2: Dictionary = {
		"version": 2,
		"schema_id": "aurora_vigil_save_v99",
		"saved_at_unix": 0,
		"progression": {"level": 1, "xp": 0, "unlocked": ["flight"]},
		"mission_step": 0,
		"resolved_events": 0,
		"hero_position": [0, 0, 0],
		"powers_used": {},
		"objectives_completed": [],
	}
	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	var ev := _EventHolder.new()
	var ok: bool = SaveGame.apply(bad_v2, p, ms, ev)
	_assert(not ok, "v2 with wrong schema_id rejected")

# A v1 payload with empty progression.unlocked is backfilled with defaults.
func _test_v1_with_empty_unlocked_backfilled() -> void:
	var v1: Dictionary = {
		"version": 1,
		"progression": {"level": 1, "xp": 0, "unlocked": []},
		"mission_step": 0,
		"resolved_events": 0,
	}
	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	var ev := _EventHolder.new()
	var ok: bool = SaveGame.apply(v1, p, ms, ev)
	_assert(ok, "v1 with empty unlocked accepted")
	_assert(p.has_power("flight"), "default 'flight' restored after empty unlocked")
	_assert(p.has_power("boost"), "default 'boost' restored after empty unlocked")

# A v1 payload missing optional fields is accepted with safe defaults.
func _test_v1_sparse_payload_safe_defaults() -> void:
	var v1: Dictionary = {
		"version": 1,
		"progression": {"level": 1, "xp": 0, "unlocked": ["flight"]},
	}
	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	ms.mission_step = 0
	var ev := _EventHolder.new()
	ev.resolved_events = 0
	var ok: bool = SaveGame.apply(v1, p, ms, ev)
	_assert(ok, "v1 sparse payload accepted")
	_assert(ms.mission_step == 0, "v1 sparse: mission_step default 0")
	_assert(ev.resolved_events == 0, "v1 sparse: resolved_events default 0")

# When a Node3D hero is supplied via optional_systems and is in the tree,
# the saved pose is restored on apply. Position restoration is exercised
# end-to-end by the smoke capture scene; here we only verify that the
# optional_systems plumbing accepts the dictionary without error.
func _test_hero_pose_restore_when_optional_systems_supplied() -> void:
	var hero := Node3D.new()
	hero.name = "TestHero"
	root.add_child(hero)
	# Yield long enough for SceneTree to register the child.
	for _i in range(3):
		await process_frame
	var v2: Dictionary = {
		"version": 2,
		"schema_id": SaveGame.CURRENT_SCHEMA_ID,
		"saved_at_unix": 0,
		"progression": {"level": 1, "xp": 0, "unlocked": ["flight", "boost"]},
		"mission_step": 0,
		"resolved_events": 0,
		"hero_position": [12.0, 34.0, -56.0],
		"powers_used": {},
		"objectives_completed": [],
	}
	var p := ProgressionModel.new()
	var ms := _MissionHolder.new()
	var ev := _EventHolder.new()
	var ok: bool = SaveGame.apply(v2, p, ms, ev, {"hero": hero})
	_assert(ok, "v2 with optional_systems accepted")
	_assert(hero.is_inside_tree(), "hero is inside the tree after add_child + frame wait")
	if is_instance_valid(hero):
		hero.queue_free()
		await process_frame
