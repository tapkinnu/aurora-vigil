extends SceneTree

var failed: bool = false

func _initialize() -> void:
	OS.set_environment("AURORA_CAPTURE_MODE", "city")
	OS.set_environment("AURORA_AUTO_QUIT", "")
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_assert(false, "main scene loads")
		_finish()
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_test_city_capture_has_connected_destination_roads(main)
	_finish()

func _finish() -> void:
	if failed:
		print("AURORA_CITY_ROADS_TESTS: FAIL")
		quit(1)
	else:
		print("AURORA_CITY_ROADS_TESTS: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error(msg)

func _find_by_name(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var hit: Node = _find_by_name(child, wanted)
		if hit != null:
			return hit
	return null

func _collect_prefixed(node: Node, prefix: String, out: Array) -> void:
	if String(node.name).begins_with(prefix):
		out.append(node)
	for child in node.get_children():
		_collect_prefixed(child, prefix, out)

func _test_city_capture_has_connected_destination_roads(main: Node) -> void:
	var network: Node = _find_by_name(main, "ReferenceCaptureRoadNetwork")
	_assert(network != null, "city capture has an explicit connected road-network node")

	var destinations: Array = []
	_collect_prefixed(main, "TrafficDestination_", destinations)
	_assert(destinations.size() >= 4, "city capture exposes at least four traffic destinations")
	var destination_names: Dictionary = {}
	for destination in destinations:
		_assert(destination.has_meta("destination_name"), "%s has destination_name metadata" % destination.name)
		if destination.has_meta("destination_name"):
			destination_names[str(destination.get_meta("destination_name"))] = true
	for expected in ["Downtown Core", "Harbor Freight", "Airport Connector", "Hillview Residential"]:
		_assert(destination_names.has(expected), "traffic destination present: %s" % expected)

	var road_segments: Array = []
	_collect_prefixed(main, "RoadRoute_", road_segments)
	_assert(road_segments.size() >= 12, "city capture has visible route segments beyond the foreground freeway stub")
	var visible_junction_segments: Array = []
	_collect_prefixed(main, "RoadRoute_VisibleJunction", visible_junction_segments)
	_assert(visible_junction_segments.size() >= 8, "city capture has a foreground visible split/intersection, not only a far-off route")
	_assert(_find_by_name(main, "TrafficDestinationSign_MainGantry") != null, "city capture has readable overhead destination signage")

	var routed_cars: Array = []
	_collect_prefixed(main, "RoutedTrafficCar_", routed_cars)
	_assert(routed_cars.size() >= 10, "city capture has routed moving traffic cars")
	var car_destinations: Dictionary = {}
	for car in routed_cars:
		_assert(car.has_meta("destination_name"), "%s has a destination" % car.name)
		if car.has_meta("destination_name"):
			car_destinations[str(car.get_meta("destination_name"))] = true
		_assert(car.has_meta("route_points"), "%s has route points" % car.name)
		_assert(car.has_meta("route_speed"), "%s has route speed" % car.name)
		if not car.has_meta("route_points"):
			continue
		var raw_points: Variant = car.get_meta("route_points")
		_assert(raw_points is Array, "%s route_points is an Array" % car.name)
		if not (raw_points is Array):
			continue
		var route_points: Array = raw_points as Array
		_assert(route_points.size() >= 3, "%s has at least three route points (origin, turn/merge, destination)" % car.name)
		for point in route_points:
			_assert(point is Vector3, "%s route point is Vector3" % car.name)
	for expected in ["Downtown Core", "Harbor Freight", "Airport Connector", "Hillview Residential"]:
		_assert(car_destinations.has(expected), "routed traffic includes cars bound for %s" % expected)
