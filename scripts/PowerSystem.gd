class_name PowerSystem
extends RefCounted

# Handles the hero's powers: gating by unlocks, training surges that grant XP for
# locked powers, the power flash VFX, power audio, and dispatching a matching
# nearest-event resolution through the CityEventSystem. Split out of Main.gd.
# `host` is the Main Node3D coordinator (materials, tweens, scene tree, HUD cue).

var host
var hero: Node3D
var progression: ProgressionModel
var events: CityEventSystem

func setup(host_ref, hero_ref: Node3D, progression_ref: ProgressionModel, events_ref: CityEventSystem) -> void:
	host = host_ref
	hero = hero_ref
	progression = progression_ref
	events = events_ref

func trigger(power_id: String) -> void:
	if not progression.has_power(power_id):
		var gained: Array[String] = progression.add_xp(110)
		host.last_event_text = "%s training surge: +110 XP%s" % [power_id.replace("_", " ").capitalize(), " and new power unlocked" if gained.has(power_id) else ""]
		if gained.has(power_id):
			_spawn_power_flash(power_id)
		return
	_spawn_power_flash(power_id)
	_play_power_audio(power_id)
	var resolved := events.attempt_resolve_nearest(power_id)
	if not resolved:
		host.last_event_text = "%s fired, but no matching city event is within %.0fm." % [power_id.replace("_", " ").capitalize(), events.EVENT_RESOLVE_RADIUS]

func _spawn_power_flash(power_id: String) -> void:
	var flash := MeshInstance3D.new()
	flash.name = "PowerFlash_%s" % power_id
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	flash.mesh = mesh
	flash.position = hero.position
	var c := Color(0.2, 1.0, 0.9, 1.0)
	if power_id == "radiant_beam": c = Color(1.0, 0.72, 0.22, 1.0)
	if power_id == "sonic_burst": c = Color(0.7, 0.45, 1.0, 1.0)
	if power_id == "aegis_field": c = Color(0.2, 0.65, 1.0, 1.0)
	flash.material_override = host._mat(c, c, 1.8)
	host.add_child(flash)
	var tween: Tween = host._remember_tween(host.create_tween())
	tween.tween_property(flash, "scale", Vector3(7, 7, 7), 0.35)
	tween.parallel().tween_property(flash, "transparency", 1.0, 0.35)
	tween.tween_callback(flash.queue_free)

func _play_power_audio(power_id: String) -> void:
	match power_id:
		"radiant_beam":
			AuroraAudio.trigger("power_radiant_beam_fire")
		"sonic_burst":
			AuroraAudio.trigger("power_sonic_burst")
		"aegis_field":
			AuroraAudio.trigger("power_aegis_activate")
		"rescue_lift":
			AuroraAudio.trigger("event_alert_rescue_needed")
