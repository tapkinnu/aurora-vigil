class_name ProgressionModel
extends RefCounted

var level: int = 1
# Cumulative total XP earned across the whole run. Level is derived from this via
# the XP_THRESHOLDS table rather than tracked as a per-level remainder.
var xp: int = 0
var unlocked: Array[String] = ["flight", "boost"]

# Cumulative XP required to *reach* each level. Index = level - 1, so reaching
# level L needs XP_THRESHOLDS[L - 1] total XP:
#   level 2 → 100, level 3 → 250, level 4 → 450, level 5 → 700, level 6 → 900.
const XP_THRESHOLDS: Array[int] = [0, 100, 250, 450, 700, 900]

# Power granted on first reaching each level. Level 1 starts with flight + boost.
static var POWER_UNLOCKS := {
	2: "rescue_lift",
	3: "radiant_beam",
	4: "sonic_burst",
	5: "aegis_field",
	6: "orbit_sprint",
}

# Cumulative total XP required to reach the next level (caps at the final tier so
# the HUD bar reads "max/max" once fully levelled). Used by the HUD as the divisor.
func xp_for_next() -> int:
	if level < XP_THRESHOLDS.size():
		return XP_THRESHOLDS[level]
	return XP_THRESHOLDS[XP_THRESHOLDS.size() - 1]

# Highest level reachable with `total` cumulative XP.
func _level_for_total(total: int) -> int:
	var lvl := 1
	for i in range(1, XP_THRESHOLDS.size()):
		if total >= XP_THRESHOLDS[i]:
			lvl = i + 1
	return lvl

func add_xp(amount: int) -> Array[String]:
	var gained: Array[String] = []
	xp += max(amount, 0)
	var new_level := _level_for_total(xp)
	while level < new_level:
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
