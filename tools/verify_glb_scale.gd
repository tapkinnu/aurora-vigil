extends SceneTree

# Headless scale verification for imported GLB actors.
# Loads each GLB, instantiates it, walks every MeshInstance3D accumulating a
# combined AABB in the instance's local root space, and reports the real
# bounding-box height plus the scale factor needed to reach a target height.
#
# Run: godot --headless --path . -s tools/verify_glb_scale.gd

const ASSETS := [
	{"path": "res://assets/3d/characters/lumen/lumen_body.glb", "target": 1.85},
	{"path": "res://assets/3d/characters/enemies/drone_rogue.glb", "target": 0.9},
]

func _accumulate(node: Node, xform: Transform3D, acc: Dictionary) -> void:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb := (node as MeshInstance3D).mesh.get_aabb()
		for i in range(8):
			var corner := aabb.position + Vector3(
				aabb.size.x if (i & 1) else 0.0,
				aabb.size.y if (i & 2) else 0.0,
				aabb.size.z if (i & 4) else 0.0)
			var p := local * corner
			if not acc["init"]:
				acc["min"] = p
				acc["max"] = p
				acc["init"] = true
			else:
				acc["min"] = (acc["min"] as Vector3).min(p)
				acc["max"] = (acc["max"] as Vector3).max(p)
	for c in node.get_children():
		_accumulate(c, local, acc)

func _initialize() -> void:
	var ok := true
	for entry in ASSETS:
		var path: String = entry["path"]
		var target: float = entry["target"]
		if not ResourceLoader.exists(path):
			print("VERIFY_SCALE MISSING ", path)
			ok = false
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			print("VERIFY_SCALE LOAD_FAIL ", path)
			ok = false
			continue
		var inst := packed.instantiate()
		var acc := {"init": false, "min": Vector3.ZERO, "max": Vector3.ZERO}
		_accumulate(inst, Transform3D.IDENTITY, acc)
		inst.free()
		if not acc["init"]:
			print("VERIFY_SCALE NO_MESH ", path)
			ok = false
			continue
		var size: Vector3 = (acc["max"] as Vector3) - (acc["min"] as Vector3)
		var height := size.y
		var factor := target / height if height > 0.0001 else 0.0
		print("VERIFY_SCALE %s height=%.4f size=(%.3f,%.3f,%.3f) target=%.3f scale_factor=%.5f" % [
			path, height, size.x, size.y, size.z, target, factor])
	if ok:
		print("VERIFY_SCALE: PASS")
	else:
		print("VERIFY_SCALE: FAIL")
	quit(0 if ok else 1)
