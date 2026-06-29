extends SceneTree

var failed := false

func _initialize() -> void:
	# Non-city capture mode disables save/menu side effects but still builds the normal
	# gameplay skyline where AuroraAssetDressing should appear.
	OS.set_environment("AURORA_CAPTURE_MODE", "asset_dressing_test")
	OS.set_environment("AURORA_CAPTURE_PATH", "")
	OS.set_environment("AURORA_AUTO_QUIT", "")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_assert(false, "main scene loads")
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await process_frame
	_test_runtime_asset_dressing(main)
	_finish()

func _finish() -> void:
	if failed:
		print("AURORA_RUNTIME_ASSET_DRESSING: FAIL")
		quit(1)
	else:
		print("AURORA_RUNTIME_ASSET_DRESSING: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error("AURORA_RUNTIME_ASSET_DRESSING_ASSERT: %s" % msg)

func _find_named(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var hit := _find_named(child, wanted)
		if hit != null:
			return hit
	return null

func _collect_prefix(node: Node, prefix: String, out: Array[Node]) -> void:
	if String(node.name).begins_with(prefix):
		out.append(node)
	for child in node.get_children():
		_collect_prefix(child, prefix, out)

func _has_mesh_descendant(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return true
	for child in node.get_children():
		if _has_mesh_descendant(child):
			return true
	return false

func _assert_asset_nodes(nodes: Array[Node], expected_min: int, role: String, path_tail: String) -> void:
	_assert(nodes.size() >= expected_min, "%s count >= %d, got %d" % [role, expected_min, nodes.size()])
	for node in nodes:
		_assert(node.has_meta("runtime_asset_dressing"), "%s is tagged runtime_asset_dressing" % node.name)
		_assert(bool(node.get_meta("asset_loaded", false)), "%s loaded from GLB, not fallback" % node.name)
		_assert(str(node.get_meta("asset_path", "")).ends_with(path_tail), "%s path ends with %s" % [node.name, path_tail])
		_assert(str(node.get_meta("asset_role", "")) == role, "%s role meta is %s" % [node.name, role])
		_assert(_has_mesh_descendant(node), "%s has a MeshInstance3D descendant" % node.name)

func _test_runtime_asset_dressing(main: Node) -> void:
	var dressing := _find_named(main, "AuroraAssetDressing")
	_assert(dressing != null, "AuroraAssetDressing node exists in normal gameplay city")
	if dressing == null:
		return

	var skyway := _find_named(dressing, "AssetBackedSkywayLine")
	var solar := _find_named(dressing, "AssetBackedRooftopSolar")
	var civic := _find_named(dressing, "AssetBackedCivicTech")
	_assert(skyway != null, "skyway asset-dressing group exists")
	_assert(solar != null, "solar asset-dressing group exists")
	_assert(civic != null, "civic tech asset-dressing group exists")

	var pods: Array[Node] = []
	var panels: Array[Node] = []
	var emitters: Array[Node] = []
	var pylons: Array[Node] = []
	_collect_prefix(dressing, "SkywayTransitPod_AssetDressing_", pods)
	_collect_prefix(dressing, "RooftopSolarArray_AssetDressing_", panels)
	_collect_prefix(dressing, "CivicShimmerEmitter_AssetDressing_", emitters)
	_collect_prefix(dressing, "NullChoirContainmentPylon_AssetDressing_", pylons)

	_assert_asset_nodes(pods, 4, "skyway_transit_pod", "skyway_transit_pod.glb")
	_assert_asset_nodes(panels, 6, "solar_array_panel", "solar_array_panel.glb")
	_assert_asset_nodes(emitters, 3, "shimmer_echo_emitter", "shimmer_echo_emitter.glb")
	_assert_asset_nodes(pylons, 2, "null_choir_resonator", "null_choir_resonator.glb")

	var rails: Array[Node] = []
	_collect_prefix(dressing, "AssetGuidewayRail_", rails)
	_assert(rails.size() >= 2, "skyway has imported-pod guideway rails")
