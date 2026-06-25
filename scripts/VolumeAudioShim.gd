class_name VolumeAudioShim
extends RefCounted

# Audio dispatch shim for interaction-volume enter triggers. The set of audio ids
# fired when the player enters a volume lives in data (data/objective_markers.json
# + per-event triggers), but each id is routed here through a literal
# `AuroraAudio.trigger("...")` call so the audio-wiring contract
# (tools/check_audio_wiring.py) and the call shape stay intact. Only ids that exist
# in AuroraAudio.AUDIO_PATHS are wired; anything else is a hard error.

func dispatch(id: String) -> void:
	match id:
		"event_alert_rescue_needed":
			AuroraAudio.trigger("event_alert_rescue_needed")
		"emergency_dispatcher_dispatch":
			AuroraAudio.trigger("emergency_dispatcher_dispatch")
		"civic_grid_alert":
			AuroraAudio.trigger("civic_grid_alert")
		"civilian_panicked_help":
			AuroraAudio.trigger("civilian_panicked_help")
		"drone_alert":
			AuroraAudio.trigger("drone_alert")
		"drone_death":
			AuroraAudio.trigger("drone_death")
		"null_choir_cmdr_threat":
			AuroraAudio.trigger("null_choir_cmdr_threat")
		_:
			push_error("VolumeAudioShim: unknown audio trigger id '%s'" % id)

func dispatch_all(ids: Array) -> void:
	for id in ids:
		dispatch(str(id))
