class_name MissionDirector
extends RefCounted

# Owns the story-mission spine: the ordered mission list, current step, HUD text
# and the rule for advancing the campaign when a city event is resolved. Split out
# of Main.gd so mission content stays data-driven and independent of flight/event code.

var progression: ProgressionModel

var mission_step: int = 0

var missions: Array[Dictionary] = [
	{"id": "awakening_patrol", "title": "Dawn Patrol", "objective": "Fly through Meridian and answer the first emergency.", "target_kind": "tower_fire", "reward_xp": 80},
	{"id": "spire_rescue", "title": "The Burning Spire", "objective": "Rescue civilians from a tower fire before panic spreads.", "target_kind": "rescue_signal", "reward_xp": 140},
	{"id": "drone_chase", "title": "Ghosts in the Grid", "objective": "Disable rogue civic drones without harming the city.", "target_kind": "rogue_drone", "reward_xp": 180},
	{"id": "stormwall", "title": "Stormwall Protocol", "objective": "Use unlocked powers to protect Meridian during a citywide surge.", "target_kind": "power_surge", "reward_xp": 260}
]

func setup(progression_ref: ProgressionModel) -> void:
	progression = progression_ref

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
