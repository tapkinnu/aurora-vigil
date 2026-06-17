extends SceneTree

# Hand-rolled tests for the interaction-volume layer. Exercises:
#   (a) default fallbacks when constructed from a minimal data dict,
#   (b) the trigger signal firing on an emulated player entering the volume,
#   (c) graceful rejection of a malformed data dict (missing required field).
# Prints AURORA_VOLUME_TESTS: PASS / FAIL and quits with a matching exit code, so
# it slots into validate_build.sh exactly like tests/test_logic.gd.

const InteractionVolume = preload("res://scripts/InteractionVolume.gd")

var failed := false

func _init() -> void:
	_test_default_fallbacks()
	_test_trigger_on_enter()
	_test_malformed_rejected()
	if failed:
		print("AURORA_VOLUME_TESTS: FAIL")
		quit(1)
	else:
		print("AURORA_VOLUME_TESTS: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error("AURORA_VOLUME_TEST_ASSERT: %s" % msg)

# (a) A minimal dict supplies only the required `kind`; every optional field must
# fall back to the InteractionVolume DEFAULT_* constants.
func _test_default_fallbacks() -> void:
	var volume := InteractionVolume.from_data({"kind": "tower_fire"})
	_assert(volume != null, "minimal data dict builds a volume")
	if volume == null:
		return
	_assert(volume.volume_kind == "tower_fire", "kind is carried through")
	_assert(volume.shape_kind == InteractionVolume.SHAPE_SPHERE, "shape defaults to sphere")
	_assert(is_equal_approx(volume.radius, InteractionVolume.DEFAULT_RADIUS), "radius falls back to default")
	_assert(volume.color.is_equal_approx(InteractionVolume.DEFAULT_COLOR), "color falls back to default")
	_assert(volume.label_text == "", "label defaults to empty string")
	_assert(volume.triggers.is_empty(), "triggers default to empty list")
	# An unknown shape string must also fall back rather than corrupt the volume.
	var weird := InteractionVolume.from_data({"kind": "x", "shape": "tesseract"})
	_assert(weird != null and weird.shape_kind == InteractionVolume.SHAPE_SPHERE, "unknown shape falls back to sphere")
	if weird != null:
		weird.free()
	volume.free()

# (b) Emulate the player entering the volume by polling a point through the same
# notify_point path gameplay uses; the trigger must fire exactly once on entry and
# re-arm after the player leaves.
func _test_trigger_on_enter() -> void:
	var volume := InteractionVolume.from_data({
		"kind": "rescue_signal",
		"radius": 10.0,
		"position": [0.0, 0.0, 0.0],
		"triggers": ["civilian_panicked_help"],
	})
	_assert(volume != null, "trigger volume builds")
	if volume == null:
		return
	var hits := [0]
	var sources := []
	volume.triggered.connect(func(_v, source):
		hits[0] += 1
		sources.append(source))

	_assert(not volume.notify_point(Vector3(100, 0, 0)), "point outside does not trigger")
	_assert(hits[0] == 0, "no trigger while outside")
	_assert(volume.notify_point(Vector3(2, 0, 0)), "entering returns true")
	_assert(hits[0] == 1, "trigger fires once on enter")
	_assert(not volume.notify_point(Vector3(1, 0, 1)), "staying inside does not re-trigger")
	_assert(hits[0] == 1, "still only one trigger while inside")
	volume.notify_point(Vector3(100, 0, 0))  # leave -> re-arm
	_assert(volume.notify_point(Vector3(0, 0, 0)), "re-entry triggers again")
	_assert(hits[0] == 2, "re-entry produces a second trigger")
	_assert(volume.triggers.size() == 1 and volume.triggers[0] == "civilian_panicked_help", "named trigger id carried from data")
	volume.free()

# (c) A dict missing the required `kind` must be rejected (null) without crashing.
func _test_malformed_rejected() -> void:
	var bad := InteractionVolume.from_data({"radius": 5.0, "color": [1, 0, 0, 1]})
	_assert(bad == null, "malformed dict (missing kind) is rejected with null")
	var empty_kind := InteractionVolume.from_data({"kind": ""})
	_assert(empty_kind == null, "empty kind is rejected with null")
