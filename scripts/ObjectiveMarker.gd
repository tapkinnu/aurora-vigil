class_name ObjectiveMarker
extends Node3D

# Small floating 3D objective marker that follows the active mission's interaction
# volume: a billboarded label plus a rotating diamond icon and a downward beam so
# QA can confirm the active step from the gameplay/city camera without reading HUD
# text. Built procedurally (matching the rest of the project) and instanced from
# scenes/objective_marker.tscn so it stays a real scene asset.

const HOVER_OFFSET := Vector3(0, 13.0, 0)

var marker_color: Color = Color(0.4, 0.95, 1.0, 1.0)
var label_text: String = "OBJECTIVE"
var icon_name: String = "diamond"

var _label: Label3D
var _icon: MeshInstance3D
var _built: bool = false

func _ready() -> void:
	_build()

# Sets the marker's color/label/icon. Safe to call before or after _ready; the
# geometry is (re)built lazily so configuration always lands on real nodes.
func configure(color: Color, text: String, icon: String = "diamond") -> void:
	marker_color = color
	label_text = text
	icon_name = icon
	_build()
	_apply()

func _build() -> void:
	if _built:
		return
	_built = true

	# Capture-distance readability: scale up beam, icon, and halo so the marker
	# reads as a clear waypoint from 60+ unit gameplay camera distance, not just
	# from close range. Original icon was 3.4m, beam 0.18-0.6 radius; now 5.5m
	# icon, 0.3-1.0 beam, 5.5-7.0 halo.
	var beam := MeshInstance3D.new()
	beam.name = "ObjectiveBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.3
	beam_mesh.bottom_radius = 1.0
	beam_mesh.height = HOVER_OFFSET.y
	beam.mesh = beam_mesh
	beam.position = Vector3(0, -HOVER_OFFSET.y * 0.5, 0)
	beam.material_override = _beam_material()
	add_child(beam)

	_icon = MeshInstance3D.new()
	_icon.name = "ObjectiveIcon"
	var icon_mesh := BoxMesh.new()
	icon_mesh.size = Vector3(5.5, 5.5, 5.5)
	_icon.mesh = icon_mesh
	_icon.rotation_degrees = Vector3(0, 45, 45)
	_icon.material_override = _solid_material()
	add_child(_icon)

	var halo := MeshInstance3D.new()
	halo.name = "ObjectiveHalo"
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 5.5
	halo_mesh.outer_radius = 7.0
	halo.mesh = halo_mesh
	halo.rotation_degrees = Vector3(90, 0, 0)
	halo.material_override = _beam_material()
	add_child(halo)

	_label = Label3D.new()
	_label.name = "ObjectiveLabel"
	_label.text = label_text
	_label.font_size = 108
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = marker_color
	_label.outline_modulate = Color(0, 0, 0, 1)
	_label.outline_size = 14
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0025
	_label.render_priority = 4
	_label.outline_render_priority = 3
	_label.position = Vector3(0, 8.0, 0)
	add_child(_label)

	_apply()

	var spin := create_tween().set_loops()
	spin.tween_property(_icon, "rotation:y", _icon.rotation.y + TAU, 3.5)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_icon, "scale", Vector3(1.25, 1.25, 1.25), 0.8)
	pulse.tween_property(_icon, "scale", Vector3.ONE, 0.8)

func _apply() -> void:
	if _label != null:
		_label.text = label_text
		_label.modulate = marker_color
	if _icon != null:
		_icon.material_override = _solid_material()

func _solid_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = marker_color
	mat.emission_enabled = true
	mat.emission = marker_color
	mat.emission_energy_multiplier = 4.5
	# Unshaded so the icon reads as a bright objective beacon from any capture angle
	# regardless of the time-of-day lighting, matching the city's emissive language.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _beam_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(marker_color.r, marker_color.g, marker_color.b, 0.4)
	mat.emission_enabled = true
	mat.emission = marker_color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat
