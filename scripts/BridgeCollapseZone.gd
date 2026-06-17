class_name BridgeCollapseZone
extends Node3D

# Special-cased, persistent "bridge collapse" zone. Beyond firing the normal
# bridge_collapse trigger (via an InteractionVolume), it places real, observable
# in-city geometry — a severed road deck, tumbled debris blocks, and a ROAD CLOSED
# barricade marker — so the hazard is visible in screenshots instead of being an
# invisible trigger. Built procedurally to match the project's code-built city.

const InteractionVolumeScript = preload("res://scripts/InteractionVolume.gd")

var volume: InteractionVolume

# Builds the zone geometry centered on `center`, sized roughly to `span`, and a box
# InteractionVolume covering it. `color` matches the bridge_collapse event color so
# the hazard reads consistently with the rest of the event language.
func build(center: Vector3, span: Vector3, color: Color, enter_triggers: Array[String]) -> void:
	position = center

	var deck_mat := _mat(Color(0.12, 0.14, 0.17, 1.0), Color(0.0, 0.12, 0.18, 1.0), 0.08)
	var hazard_mat := _mat(Color(0.95, 0.5, 0.12, 1.0), Color(1.0, 0.45, 0.1, 1.0), 1.4)
	var debris_mat := _mat(Color(0.18, 0.2, 0.24, 1.0), Color(0.0, 0.08, 0.12, 1.0), 0.05)

	# Two severed road deck segments tilted away from a central gap.
	var half := span.x * 0.5
	var deck_a := _box("BridgeDeckWest", Vector3(half - 4.0, 0.6, span.z), Vector3(-half * 0.55, 0.4, 0.0), deck_mat)
	deck_a.rotation_degrees = Vector3(0, 0, 6)
	var deck_b := _box("BridgeDeckEast", Vector3(half - 4.0, 0.6, span.z), Vector3(half * 0.55, 0.4, 0.0), deck_mat)
	deck_b.rotation_degrees = Vector3(0, 0, -6)

	# Collapsed slab hanging into the gap.
	var slab := _box("BridgeCollapsedSlab", Vector3(7.0, 0.55, span.z * 0.8), Vector3(0, -2.2, 0.0), deck_mat)
	slab.rotation_degrees = Vector3(0, 0, 28)

	# Tumbled debris blocks scattered through the gap.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260617
	for i in range(7):
		var size := Vector3(rng.randf_range(1.2, 2.6), rng.randf_range(1.0, 2.2), rng.randf_range(1.2, 2.6))
		var pos := Vector3(rng.randf_range(-half * 0.4, half * 0.4), rng.randf_range(-1.5, 1.5), rng.randf_range(-span.z * 0.35, span.z * 0.35))
		var block := _box("Debris_%d" % i, size, pos, debris_mat)
		block.rotation_degrees = Vector3(rng.randf_range(0, 40), rng.randf_range(0, 360), rng.randf_range(0, 40))

	# Hazard barricades + ROAD CLOSED marker on both approaches.
	for side in [-1.0, 1.0]:
		var barricade := _box("Barricade_%s" % str(side), Vector3(span.z, 1.1, 0.5), Vector3(side * half * 0.92, 1.0, 0.0), hazard_mat)
		barricade.rotation_degrees = Vector3(0, 90, 0)
		for stripe in range(-2, 3):
			_box("BarricadeLeg_%s_%d" % [str(side), stripe], Vector3(0.4, 2.0, 0.4), Vector3(side * half * 0.92, 0.0, float(stripe) * span.z * 0.18), hazard_mat)

	var sign_label := Label3D.new()
	sign_label.name = "RoadClosedSign"
	sign_label.text = "⚠ ROAD CLOSED\nBRIDGE COLLAPSE"
	sign_label.font_size = 56
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(1.0, 0.55, 0.18, 1.0)
	sign_label.outline_modulate = Color(0, 0, 0, 1)
	sign_label.outline_size = 6
	sign_label.position = Vector3(0, 6.5, 0)
	add_child(sign_label)

	# Warning beacon light over the gap.
	var beacon := OmniLight3D.new()
	beacon.name = "HazardBeacon"
	beacon.position = Vector3(0, 5.0, 0)
	beacon.light_color = Color(1.0, 0.5, 0.12, 1.0)
	beacon.light_energy = 9.0
	beacon.omni_range = 26.0
	add_child(beacon)

	# Interaction trigger volume covering the gap; box-shaped to match the deck.
	volume = InteractionVolumeScript.from_data({
		"kind": "bridge_collapse",
		"shape": "box",
		"size": [span.x, max(span.y, 10.0), span.z],
		"color": [color.r, color.g, color.b, color.a],
		"label": "BRIDGE COLLAPSE",
		"triggers": enter_triggers,
	})
	if volume != null:
		add_child(volume)

func _box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = pos
	box.material_override = mat
	add_child(box)
	return box

func _mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = energy > 0.0
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.6
	mat.metallic = 0.08
	return mat
