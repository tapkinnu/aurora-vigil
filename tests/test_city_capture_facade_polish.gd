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
	_test_facade_polish(main)
	_finish()


func _finish() -> void:
	if failed:
		print("AURORA_CITY_FACADE_POLISH: FAIL")
		quit(1)
	else:
		print("AURORA_CITY_FACADE_POLISH: PASS")
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


func _collect_greebles(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if String(mesh.name).begins_with("Greeble_"):
			out.append(mesh)
	for child in node.get_children():
		_collect_greebles(child, out)


func _test_facade_polish(main: Node) -> void:
	var buildings: Array[Node] = []
	_collect_capture_buildings(main, buildings)
	_assert(buildings.size() >= 70, "city capture includes many imported building holders to texture")

	var all_panels: Array[MeshInstance3D] = []
	var buildings_with_greebles: int = 0
	var uv_offsets: Array = []
	var has_canopy_global: bool = false
	var has_antenna_global: bool = false
	var buildings_with_parapet: int = 0

	for building in buildings:
		_assert(building.has_meta("facade_texture_pass"), "%s opted into facade texture pass" % building.name)

		# -- Texture panel shader parameter checks --
		var panels: Array[MeshInstance3D] = []
		_collect_texture_panels(building, panels)
		all_panels.append_array(panels)

		for panel in panels:
			var mat: Material = panel.material_override
			_assert(mat is ShaderMaterial, "%s uses shader facade material" % panel.name)
			if not (mat is ShaderMaterial):
				continue
			var shader_mat: ShaderMaterial = mat as ShaderMaterial

			_assert(shader_mat.shader == FACADE_SHADER, "%s uses building_facade shader" % panel.name)

			# uv_offset: must be a Vector2
			var uv_off = shader_mat.get_shader_parameter("uv_offset")
			_assert(uv_off != null, "%s uv_offset is set" % panel.name)
			_assert(uv_off is Vector2, "%s uv_offset is Vector2" % panel.name)
			if uv_off is Vector2:
				uv_offsets.append(uv_off)

			# uv_scale: in [2.0, 6.0]
			var uv_s = shader_mat.get_shader_parameter("uv_scale")
			_assert(typeof(uv_s) == TYPE_FLOAT, "%s uv_scale is float" % panel.name)
			if typeof(uv_s) == TYPE_FLOAT:
				_assert(uv_s >= 2.0 and uv_s <= 6.0, "%s uv_scale in [2.0, 6.0] got %s" % [panel.name, uv_s])

			# uv_scale_2: exists and ≈ uv_scale * 2.7
			var uv_s2 = shader_mat.get_shader_parameter("uv_scale_2")
			_assert(typeof(uv_s2) == TYPE_FLOAT, "%s uv_scale_2 is float" % panel.name)
			if typeof(uv_s) == TYPE_FLOAT and typeof(uv_s2) == TYPE_FLOAT and uv_s != 0.0:
				var ratio: float = uv_s2 / uv_s
				_assert(abs(ratio - 2.7) < 0.001, "%s uv_scale_2/uv_scale ≈ 2.7 got %s/%s=%s" % [panel.name, uv_s2, uv_s, ratio])

			# albedo_tex_2: assigned
			var albedo2 = shader_mat.get_shader_parameter("albedo_tex_2")
			_assert(albedo2 != null, "%s albedo_tex_2 is assigned" % panel.name)

			# window_depth: [0.3, 0.6]
			var wd = shader_mat.get_shader_parameter("window_depth")
			_assert(typeof(wd) == TYPE_FLOAT, "%s window_depth is float" % panel.name)
			if typeof(wd) == TYPE_FLOAT:
				_assert(wd >= 0.3 and wd <= 0.6, "%s window_depth in [0.3, 0.6] got %s" % [panel.name, wd])

			# glass_reflectivity: [0.1, 0.25]
			var gr = shader_mat.get_shader_parameter("glass_reflectivity")
			_assert(typeof(gr) == TYPE_FLOAT, "%s glass_reflectivity is float" % panel.name)
			if typeof(gr) == TYPE_FLOAT:
				_assert(gr >= 0.1 and gr <= 0.25, "%s glass_reflectivity in [0.1, 0.25] got %s" % [panel.name, gr])

		# -- Greeble checks --
		var greebles: Array[MeshInstance3D] = []
		_collect_greebles(building, greebles)

		if greebles.size() > 0:
			buildings_with_greebles += 1

		var b_has_parapet: bool = false
		for g in greebles:
			var gname: String = String(g.name)
			if gname.begins_with("Greeble_Parapet"):
				b_has_parapet = true
			if gname == "Greeble_Canopy":
				has_canopy_global = true
			if gname == "Greeble_Antenna":
				has_antenna_global = true

		if b_has_parapet:
			buildings_with_parapet += 1

	# ---- Global assertions ----

	_assert(all_panels.size() >= buildings.size() * 2, "facade panels cover all building faces")

	# uv_offset uniqueness: at least 10 distinct offsets
	var unique_offsets: Dictionary = {}
	for off in uv_offsets:
		var key: String = str(off)
		unique_offsets[key] = true
	_assert(unique_offsets.size() >= 10, "at least 10 distinct uv_offset values across panels, got %d" % unique_offsets.size())

	# Greebles
	_assert(buildings_with_greebles >= 70, "at least 70 buildings have greebles, got %d" % buildings_with_greebles)
	_assert(buildings_with_parapet >= 70, "at least 70 buildings have parapet greebles, got %d" % buildings_with_parapet)
	_assert(has_canopy_global, "at least one Greeble_Canopy exists city-wide")
	_assert(has_antenna_global, "at least one Greeble_Antenna exists city-wide")
