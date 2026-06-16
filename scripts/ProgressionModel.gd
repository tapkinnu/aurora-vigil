class_name ProgressionModel
extends RefCounted

var level: int = 1
var xp: int = 0
var unlocked: Array[String] = ["flight", "boost"]

static var POWER_UNLOCKS := {
	2: "radiant_beam",
	3: "sonic_burst",
	4: "aegis_field",
	5: "rescue_lift",
	6: "orbit_sprint"
}

func xp_for_next() -> int:
	return 100 + (level - 1) * 75

func add_xp(amount: int) -> Array[String]:
	var gained: Array[String] = []
	xp += max(amount, 0)
	while xp >= xp_for_next():
		xp -= xp_for_next()
		level += 1
		if POWER_UNLOCKS.has(level):
			var power: String = POWER_UNLOCKS[level]
			if not unlocked.has(power):
				unlocked.append(power)
				gained.append(power)
	return gained

func has_power(power_id: String) -> bool:
	return unlocked.has(power_id)

func save_state() -> Dictionary:
	return {"level": level, "xp": xp, "unlocked": unlocked.duplicate()}

func load_state(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	xp = int(data.get("xp", 0))
	unlocked.clear()
	for p in data.get("unlocked", ["flight", "boost"]):
		unlocked.append(str(p))
	if unlocked.is_empty():
		unlocked = ["flight", "boost"]
