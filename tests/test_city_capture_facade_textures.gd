extends SceneTree

const FACADE_SHADER = preload("res://shaders/building_facade.gdshader")

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
	await process_frame
	_test_capture_buildings_have_texture_overlay(main)
	_finish()

func _finish() -> void:
	if failed:
		print("AURORA_CITY_FACADE_TEXTURES: FAIL")
		quit(1)
	else:
		print("AURORA_CITY_FACADE_TEXTURES: PASS")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		push_error(msg)

func _has_any_prefix(text: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if text.begins_with(prefix):
			return true
	return false

func _collect_capture_buildings(node: Node, out: Array[Node]) -> void:
	var building_prefixes: Array[String] = [
		"HeroAssetTower_",
		"MidriseAssetBlock_",
		"FreewayShoulderBlock_",
		"SideInner_",
		"SideOuter_",
		"FarAssetSkyline_",
		"FarAssetTower_",
		"PlazaLowrise_",
		"FgLowrise_",
	]
	if _has_any_prefix(String(node.name), building_prefixes):
		out.append(node)
	for child in node.get_children():
		_collect_capture_buildings(child, out)

func _collect_texture_panels(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.has_meta("facade_texture_panel") or String(mesh.name).begins_with("FacadeTexturePanel_"):
			out.append(mesh)
	for child in node.get_children():
		_collect_texture_panels(child, out)

func _test_capture_buildings_have_texture_overlay(main: Node) -> void:
	var buildings: Array[Node] = []
	_collect_capture_buildings(main, buildings)
	_assert(buildings.size() >= 70, "city capture includes many imported building holders to texture")
	var textured_count := 0
	var panel_count := 0
	var material_count := 0
	var texture_indices: Dictionary = {}
	for building in buildings:
		_assert(building.has_meta("facade_texture_pass"), "%s opted into facade texture pass" % building.name)
		var panels: Array[MeshInstance3D] = []
		_collect_texture_panels(building, panels)
		_assert(panels.size() >= 2, "%s has visible facade texture overlay panels" % building.name)
		if panels.size() >= 2:
			textured_count += 1
		panel_count += panels.size()
		for panel in panels:
			var mat := panel.material_override
			_assert(mat is ShaderMaterial, "%s uses shader facade material" % panel.name)
			if mat is ShaderMaterial:
				var shader_mat := mat as ShaderMaterial
				_assert(shader_mat.shader == FACADE_SHADER, "%s uses building_facade shader" % panel.name)
				material_count += 1
				if panel.has_meta("facade_texture_index"):
					texture_indices[int(panel.get_meta("facade_texture_index"))] = true
	_assert(textured_count >= 70, "at least 70 capture buildings have facade overlay panels")
	_assert(panel_count >= textured_count * 2, "each textured building has multiple visible facade panels")
	_assert(material_count >= panel_count, "every facade panel has a shader material")
	_assert(texture_indices.size() >= 4, "facade texture pass varies across at least four PBR texture sets")
