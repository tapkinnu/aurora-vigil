extends SceneTree

const ProgressionModel = preload("res://scripts/ProgressionModel.gd")
const MissionDirector = preload("res://scripts/MissionDirector.gd")

var failed := false

# Minimal host mock for spawn_event visual identity tests.
class _SkywayTestHost:
	extends Node3D

	var _tweens: Array[Tween] = []

	func _mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = albedo
		m.emission = emission
		m.emission_enabled = energy > 0.0
		m.emission_energy_multiplier = energy
		m.roughness = 0.55
		m.metallic = 0.05
		return m

	func _transparent_mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
		var m := _mat(albedo, emission, energy)
		return m

	func _remember_tween(t: Tween) -> Tween:
		_tweens.append(t)
		return t

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
	_test_skyway_runaway_visual_id()
	_test_null_resonator_visual_id()
	_test_shimmer_echo_visual_id()
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
	_assert(md.count() == 11, "eleven missions loaded from json")
	_assert(str(md.missions[0]["title"]) == "Dawn Patrol", "first mission title is Dawn Patrol")
	_assert(str(md.missions[0]["target_kind"]) == "tower_fire", "first mission target_kind matches json")
	_assert(int(md.missions[0]["reward_xp"]) == 80, "first mission reward_xp matches json")
	_assert(str(md.missions[8]["id"]) == "dawn_aftershock", "ninth mission id is dawn_aftershock")
	_assert(str(md.missions[8]["title"]) == "Dawn Aftershock", "ninth mission title matches json")
	_assert(str(md.missions[8]["target_kind"]) == "power_surge", "ninth mission target_kind matches json")
	_assert(int(md.missions[8]["reward_xp"]) == 320, "ninth mission reward_xp matches json")
	_assert(str(md.missions[9]["id"]) == "tether_rescue", "tenth mission id is tether_rescue")
	_assert(str(md.missions[9]["title"]) == "Tether Rescue", "tenth mission title is Tether Rescue")
	_assert(str(md.missions[9]["target_kind"]) == "transit_derailment", "tenth mission target_kind is transit_derailment")
	_assert(int(md.missions[9]["reward_xp"]) == 150, "tenth mission reward_xp matches json")
	_assert(str(md.missions[10]["id"]) == "skyway_runaway_response", "eleventh mission id is skyway_runaway_response")
	_assert(str(md.missions[10]["title"]) == "Skyway Runaway", "eleventh mission title is Skyway Runaway")
	_assert(str(md.missions[10]["target_kind"]) == "skyway_runaway", "eleventh mission target_kind is skyway_runaway")
	_assert(int(md.missions[10]["reward_xp"]) == 200, "eleventh mission reward_xp matches json")

func _test_event_data() -> void:
	var text: String = FileAccess.get_file_as_string("res://data/events/events.json")
	var parsed_variant: Variant = JSON.parse_string(text)
	_assert(typeof(parsed_variant) == TYPE_DICTIONARY, "events json parses to dictionary")
	if typeof(parsed_variant) != TYPE_DICTIONARY:
		return
	var parsed: Dictionary = parsed_variant
	_assert(parsed.has("kinds"), "events json loads")
	var event_kinds: Dictionary = {}
	var kind_entries: Array = parsed.get("kinds", [])
	for raw_entry in kind_entries:
		_assert(typeof(raw_entry) == TYPE_DICTIONARY, "event kind entry is dictionary")
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		event_kinds[str(entry.get("id", ""))] = entry
	_assert(event_kinds.size() == 9, "nine event kinds loaded")
	for kind in ["tower_fire", "rogue_drone", "power_surge", "rescue_signal", "bridge_collapse", "transit_derailment", "skyway_runaway", "null_resonator", "shimmer_echo"]:
		_assert(event_kinds.has(kind), "event kind present: %s" % kind)
	var seed_events_data: Array = parsed.get("seed_events", [])
	_assert(seed_events_data.size() == 3, "three seed events loaded")
	var timed_spawn_data: Dictionary = parsed.get("timed_spawn", {})
	_assert(timed_spawn_data.get("types", []).size() >= 1, "timed_spawn has at least one type")
	_assert(timed_spawn_data.get("positions", []).size() >= 1, "timed_spawn has at least one position")
	for t in timed_spawn_data.get("types", []):
		_assert(event_kinds.has(str(t)), "timed_spawn type '%s' defined in event_kinds" % str(t))
	_assert(timed_spawn_data.get("types", []).has("bridge_collapse"), "bridge_collapse in timed_spawn.types")
	_assert(timed_spawn_data.get("types", []).has("transit_derailment"), "transit_derailment in timed_spawn.types")
	# Null resonator round-trips.
	_assert(event_kinds.has("null_resonator"), "null_resonator event kind exists")
	var nr_event: Dictionary = event_kinds.get("null_resonator", {})
	_assert(str(nr_event.get("display_name", "")) == "Null resonator", "null_resonator display name from data")
	_assert("sonic_burst" == str(nr_event.get("required_power", "")), "sonic_burst matches null_resonator from data")
	var nr_action: String = str(nr_event.get("required_action", "")).to_lower()
	_assert(nr_action.contains("q") and nr_action.contains("sonic burst"), "null_resonator action mentions Q and sonic burst")
	_assert(nr_action.contains("resonator"), "null_resonator action mentions resonator")
	_assert(int(nr_event.get("reward_xp", 0)) == 160, "null_resonator reward resolves to 160 from data")
	_assert(timed_spawn_data.get("types", []).has("null_resonator"), "null_resonator in timed_spawn.types")

	# Check objective marker data includes null_resonator.
	var om_text: String = FileAccess.get_file_as_string("res://data/objective_markers.json")
	var om_parsed_variant: Variant = JSON.parse_string(om_text)
	_assert(typeof(om_parsed_variant) == TYPE_DICTIONARY, "objective_markers json parses to dictionary")
	if typeof(om_parsed_variant) == TYPE_DICTIONARY:
		var om_parsed: Dictionary = om_parsed_variant
		var markers_arr: Array = om_parsed.get("markers", [])
		var found_nr_marker := false
		for m in markers_arr:
			if typeof(m) == TYPE_DICTIONARY and str(m.get("target_kind", "")) == "null_resonator":
				found_nr_marker = true
				break
		_assert(found_nr_marker, "objective_markers has entry for null_resonator")

	# Round-trip: resolve reward comes from the data lookup, not a constant.
	_assert(int(event_kinds["tower_fire"].get("reward_xp", 0)) == 70, "tower_fire reward resolves to 70 from data")
	_assert(str(event_kinds["tower_fire"].get("display_name", "")) == "Tower fire", "tower_fire display name from data")
	_assert("radiant_beam" == str(event_kinds["tower_fire"].get("required_power", "")), "radiant_beam matches tower_fire from data")
	# Transit derailment round-trips.
	_assert(event_kinds.has("transit_derailment"), "transit_derailment event kind exists")
	var transit_event: Dictionary = event_kinds.get("transit_derailment", {})
	_assert(str(transit_event.get("display_name", "")) == "Transit derailment", "transit_derailment display name from data")
	_assert("aegis_field" == str(transit_event.get("required_power", "")), "aegis_field matches transit_derailment from data")
	var transit_action: String = str(transit_event.get("required_action", "")).to_lower()
	_assert(transit_action.contains("aegis field") and transit_action.contains("transit car"), "transit_derailment action mentions aegis field and transit car")
	_assert(int(transit_event.get("reward_xp", 0)) == 150, "transit_derailment reward resolves to 150 from data")
	# Skyway runaway round-trips.
	_assert(event_kinds.has("skyway_runaway"), "skyway_runaway event kind exists")
	var skyway_event: Dictionary = event_kinds.get("skyway_runaway", {})
	_assert(str(skyway_event.get("display_name", "")) == "Skyway runaway", "skyway_runaway display name from data")
	_assert("orbit_sprint" == str(skyway_event.get("required_power", "")), "orbit_sprint matches skyway_runaway from data")
	var skyway_action: String = str(skyway_event.get("required_action", "")).to_lower()
	_assert(skyway_action.contains("shift") and skyway_action.contains("orbit sprint"), "skyway_runaway action mentions shift and orbit sprint")
	_assert(int(skyway_event.get("reward_xp", 0)) == 180, "skyway_runaway reward resolves to 180 from data")

	# Shimmer Echo round-trips.
	_assert(event_kinds.has("shimmer_echo"), "shimmer_echo event kind exists")
	var shimmer_event: Dictionary = event_kinds.get("shimmer_echo", {})
	_assert(str(shimmer_event.get("display_name", "")) == "Shimmer Echo", "shimmer_echo display name from data")
	_assert("aegis_field" == str(shimmer_event.get("required_power", "")), "aegis_field matches shimmer_echo from data")
	var shimmer_action: String = str(shimmer_event.get("required_action", "")).to_lower()
	_assert(shimmer_action.contains("hold e") and shimmer_action.contains("aegis field"), "shimmer_echo action mentions Hold E and aegis field")
	var shimmer_xp: int = int(shimmer_event.get("reward_xp", 0))
	_assert(shimmer_xp > 125 and shimmer_xp < 180, "shimmer_echo reward_xp between power_surge(125) and skyway_runaway(180), got %d" % shimmer_xp)
	_assert(timed_spawn_data.get("types", []).has("shimmer_echo"), "shimmer_echo in timed_spawn.types")

	# Check objective marker data includes shimmer_echo.
	var om_text2: String = FileAccess.get_file_as_string("res://data/objective_markers.json")
	var om_parsed_variant2: Variant = JSON.parse_string(om_text2)
	_assert(typeof(om_parsed_variant2) == TYPE_DICTIONARY, "objective_markers json parses to dictionary (shimmer check)")
	if typeof(om_parsed_variant2) == TYPE_DICTIONARY:
		var om_parsed2: Dictionary = om_parsed_variant2
		var markers_arr2: Array = om_parsed2.get("markers", [])
		var found_se_marker := false
		for m in markers_arr2:
			if typeof(m) == TYPE_DICTIONARY and str(m.get("target_kind", "")) == "shimmer_echo":
				found_se_marker = true
				break
		_assert(found_se_marker, "objective_markers has entry for shimmer_echo")

func _test_power_data() -> void:
	var text: String = FileAccess.get_file_as_string("res://data/powers/powers.json")
	var parsed_variant: Variant = JSON.parse_string(text)
	_assert(typeof(parsed_variant) == TYPE_DICTIONARY, "powers json parses to dictionary")
	if typeof(parsed_variant) != TYPE_DICTIONARY:
		return
	var parsed: Dictionary = parsed_variant
	_assert(parsed.has("powers"), "powers json loads")
	var power_data: Dictionary = {}
	var power_entries: Array = parsed.get("powers", [])
	for raw_entry in power_entries:
		_assert(typeof(raw_entry) == TYPE_DICTIONARY, "power entry is dictionary")
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		power_data[str(entry.get("id", ""))] = entry
	_assert(power_data.size() >= 4, "at least four powers loaded")
	_assert(power_data.has("radiant_beam"), "radiant_beam power present")
	_assert(power_data.has("aegis_field"), "aegis_field power present for transit_derailment")
	var radiant_power: Dictionary = power_data.get("radiant_beam", {})
	var c_arr: Array = radiant_power.get("flash_color", [])
	_assert(c_arr.size() == 4, "radiant_beam flash_color has four channels")
	if c_arr.size() == 4:
		var c: Color = Color(c_arr[0], c_arr[1], c_arr[2], c_arr[3])
		_assert(c.is_equal_approx(Color(1.0, 0.72, 0.22, 1.0)), "radiant_beam flash_color matches original")

func _test_skyway_runaway_visual_id() -> void:
	var host := _SkywayTestHost.new()
	root.add_child(host)
	var CEScript = load("res://scripts/CityEventSystem.gd")
	var ces = CEScript.new()
	var temp_hero := Node3D.new()
	var temp_camera := Camera3D.new()
	ces.setup(host, temp_hero, temp_camera, ProgressionModel.new(), MissionDirector.new())
	ces.spawn_event("skyway_runaway", Vector3(12.0, 10.0, -8.0))

	var marker := host.get_node("DynamicEvent_skyway_runaway") as Node3D
	_assert(marker != null, "skyway_runaway: marker exists on host")
	if marker != null:
		var beacon := marker.get_node("EventBeacon") as MeshInstance3D
		_assert(beacon != null, "skyway_runaway: EventBeacon exists")
		if beacon != null:
			_assert(not (beacon.mesh is SphereMesh), "skyway_runaway: EventBeacon is NOT SphereMesh")
			_assert(beacon.mesh is BoxMesh, "skyway_runaway: EventBeacon is BoxMesh")
			if beacon.mesh is BoxMesh:
				var box: BoxMesh = beacon.mesh
				_assert(box.size.z > box.size.x, "skyway_runaway: BoxMesh elongated in Z (capsule-like)")

		# Named children for skyway runaway visual identity.
		_assert(marker.get_node("SkywayTrail_0") != null, "skyway_runaway: SkywayTrail_0 exists")
		_assert(marker.get_node("SkywayRail_0") != null, "skyway_runaway: SkywayRail_0 exists")
		_assert(marker.get_node("SkywayNoseGlow") != null, "skyway_runaway: SkywayNoseGlow exists")

	for t in host._tweens:
		if is_instance_valid(t):
			t.kill()
	host.queue_free()
	temp_hero.queue_free()
	temp_camera.queue_free()

func _test_null_resonator_visual_id() -> void:
	var host := _SkywayTestHost.new()
	root.add_child(host)
	var CEScript = load("res://scripts/CityEventSystem.gd")
	var ces = CEScript.new()
	var temp_hero := Node3D.new()
	var temp_camera := Camera3D.new()
	ces.setup(host, temp_hero, temp_camera, ProgressionModel.new(), MissionDirector.new())
	ces.spawn_event("null_resonator", Vector3(5.0, 10.0, -3.0))

	var marker := host.get_node("DynamicEvent_null_resonator") as Node3D
	_assert(marker != null, "null_resonator: marker exists on host")
	if marker != null:
		var beacon := marker.get_node("EventBeacon") as MeshInstance3D
		_assert(beacon != null, "null_resonator: EventBeacon exists")
		if beacon != null:
			_assert(beacon.mesh is CylinderMesh, "null_resonator: EventBeacon is a distinct CylinderMesh")
			if beacon.mesh is CylinderMesh:
				var cyl: CylinderMesh = beacon.mesh
				_assert(cyl.height > cyl.bottom_radius * 4.0, "null_resonator: EventBeacon is tall resonator silhouette")
		_assert(marker.get_node("NullResonatorMast") != null, "null_resonator: NullResonatorMast exists")
		_assert(marker.get_node("NullResonatorWave_0") != null, "null_resonator: NullResonatorWave_0 exists")
		_assert(marker.get_node("NullResonatorWave_1") != null, "null_resonator: NullResonatorWave_1 exists")
		_assert(marker.get_node("NullResonatorCore") != null, "null_resonator: NullResonatorCore exists")

	for t in host._tweens:
		if is_instance_valid(t):
			t.kill()
	host.queue_free()
	temp_hero.queue_free()
	temp_camera.queue_free()

func _test_shimmer_echo_visual_id() -> void:
	var host := _SkywayTestHost.new()
	root.add_child(host)
	var CEScript = load("res://scripts/CityEventSystem.gd")
	var ces = CEScript.new()
	var temp_hero := Node3D.new()
	var temp_camera := Camera3D.new()
	ces.setup(host, temp_hero, temp_camera, ProgressionModel.new(), MissionDirector.new())
	ces.spawn_event("shimmer_echo", Vector3(7.0, 12.0, -5.0))

	var marker := host.get_node("DynamicEvent_shimmer_echo") as Node3D
	_assert(marker != null, "shimmer_echo: marker exists on host")
	if marker != null:
		var beacon := marker.get_node("EventBeacon") as MeshInstance3D
		_assert(beacon != null, "shimmer_echo: EventBeacon exists")
		if beacon != null:
			_assert(beacon.mesh is TorusMesh, "shimmer_echo: EventBeacon is TorusMesh (halo/rift silhouette)")

		_assert(marker.get_node("ShimmerEchoCore") != null, "shimmer_echo: ShimmerEchoCore exists")
		_assert(marker.get_node("ShimmerEchoRing_0") != null, "shimmer_echo: ShimmerEchoRing_0 exists")
		_assert(marker.get_node("ShimmerEchoRing_1") != null, "shimmer_echo: ShimmerEchoRing_1 exists")
		_assert(marker.get_node("ShimmerEchoArc_0") != null, "shimmer_echo: ShimmerEchoArc_0 exists")

	for t in host._tweens:
		if is_instance_valid(t):
			t.kill()
	host.queue_free()
	temp_hero.queue_free()
	temp_camera.queue_free()
