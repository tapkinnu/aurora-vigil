class_name Minimap
extends Control

# Bottom-right radar. North-up, 200 m range around the hero: draws the hero as a
# heading arrow at the centre, active city events as colour-coded dots (clamped to
# the rim when out of range), and the current mission objective as a hollow marker.
# Main feeds it each frame via set_radar(...) which stashes the data and requests a
# redraw; all rendering happens in _draw().

const RADAR_RANGE: float = 200.0
const BG_COLOR: Color = Color(0.01, 0.03, 0.06, 0.72)
const RIM_COLOR: Color = Color(0.3, 0.85, 1.0, 0.9)
const PLAYER_COLOR: Color = Color(0.95, 1.0, 1.0, 1.0)
const OBJECTIVE_COLOR: Color = Color(1.0, 0.9, 0.35, 1.0)

var _hero_pos: Vector3 = Vector3.ZERO
var _forward: Vector2 = Vector2(0, -1)
# Each entry: { "offset": Vector2 (world XZ relative to hero), "color": Color }.
var _dots: Array = []
var _objective_offset = null  # Vector2 or null

func set_radar(hero_pos: Vector3, forward: Vector3, dots: Array, objective_offset) -> void:
	_hero_pos = hero_pos
	var f := Vector2(forward.x, forward.z)
	if f.length() > 0.001:
		_forward = f.normalized()
	_dots = dots
	_objective_offset = objective_offset
	queue_redraw()

func _draw() -> void:
	var radius: float = size.x * 0.5
	var center: Vector2 = size * 0.5
	var scale: float = radius / RADAR_RANGE
	# Radar field + rim.
	draw_circle(center, radius, BG_COLOR)
	draw_arc(center, radius - 1.0, 0.0, TAU, 48, RIM_COLOR, 2.0)
	# Cross hairs for orientation.
	var hair := Color(0.3, 0.85, 1.0, 0.25)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), hair, 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), hair, 1.0)

	# Objective marker (hollow diamond), clamped to the rim if out of range.
	if _objective_offset != null:
		var op: Vector2 = _clamp_to_radar(_objective_offset * scale, radius)
		_draw_diamond(center + op, 5.0, OBJECTIVE_COLOR)

	# Event dots.
	for d in _dots:
		var off: Vector2 = _clamp_to_radar(d["offset"] * scale, radius)
		draw_circle(center + off, 3.5, d["color"])

	# Hero heading arrow.
	var ang := _forward.angle()
	var tip := center + Vector2(8, 0).rotated(ang)
	var left := center + Vector2(-5, -4).rotated(ang)
	var right := center + Vector2(-5, 4).rotated(ang)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), PLAYER_COLOR)

func _clamp_to_radar(v: Vector2, radius: float) -> Vector2:
	if v.length() > radius - 2.0:
		return v.normalized() * (radius - 2.0)
	return v

func _draw_diamond(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)
	])
	draw_polyline(pts, col, 2.0)
