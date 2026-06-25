extends CanvasLayer

# Aurora Vigil title / main menu. Shown as a top-level overlay over the live city
# (which acts as a slow-panning cinematic backdrop) while the scene tree is paused.
# Stage 1 is the title card with a "press any key" prompt; the first input reveals
# the New Game / Continue / Settings / Quit options. Processes while paused
# (process_mode = ALWAYS) and drives a gentle camera orbit so the skyline drifts
# behind the menu. Never instanced during headless capture/auto-quit runs.

var host
var _camera: Camera3D
var _settings: AuroraSettingsPanel
var _orbit_angle: float = 0.0
var _stage: int = 0  # 0 = title prompt, 1 = menu options

var _prompt: Label
var _menu_box: VBoxContainer
var _new_button: Button
var _continue_button: Button
var _settings_button: Button
var _quit_button: Button

const ORBIT_CENTER := Vector3(0, 30, 0)
const ORBIT_RADIUS := 132.0
const ORBIT_HEIGHT := 58.0
const ORBIT_SPEED := 0.12

func setup(host_ref) -> void:
	host = host_ref
	if host != null:
		_camera = host.camera
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_build_ui()

func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Darkened vignette so the title reads over the bright skyline.
	var vignette := ColorRect.new()
	vignette.color = Color(0.01, 0.02, 0.05, 0.45)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var title := Label.new()
	title.name = "Title"
	title.text = "AURORA VIGIL"
	title.position = Vector2(0, 150)
	title.size = Vector2(1280, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.2, 0.0, 0.35, 0.95))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Guardian of Meridian"
	subtitle.position = Vector2(0, 244)
	subtitle.size = Vector2(1280, 40)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 26)
	subtitle.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0, 0.9))
	root.add_child(subtitle)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "Press any key to begin"
	_prompt.position = Vector2(0, 430)
	_prompt.size = Vector2(1280, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	root.add_child(_prompt)

	_menu_box = VBoxContainer.new()
	_menu_box.name = "MenuOptions"
	_menu_box.position = Vector2(540, 400)
	_menu_box.custom_minimum_size = Vector2(200, 0)
	_menu_box.add_theme_constant_override("separation", 12)
	_menu_box.visible = false
	root.add_child(_menu_box)

	_new_button = _make_button("New Game", _on_new_game)
	_continue_button = _make_button("Continue", _on_continue)
	_settings_button = _make_button("Settings", _on_settings)
	_quit_button = _make_button("Quit", _on_quit)
	_continue_button.disabled = not _has_save()

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	_menu_box.add_child(b)
	return b

func _process(delta: float) -> void:
	# Slow cinematic orbit of the skyline behind the menu while the tree is paused.
	_orbit_angle += delta * ORBIT_SPEED
	if _camera != null and is_instance_valid(_camera):
		var pos := ORBIT_CENTER + Vector3(sin(_orbit_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(_orbit_angle) * ORBIT_RADIUS)
		_camera.global_position = pos
		_camera.look_at(ORBIT_CENTER, Vector3.UP)
	# Pulse the prompt so the title card feels alive.
	if _prompt != null and _stage == 0:
		_prompt.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_orbit_angle * 18.0))

func _unhandled_input(event: InputEvent) -> void:
	if _stage != 0:
		return
	if _settings != null and is_instance_valid(_settings):
		return
	var go: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if go:
		_reveal_menu()
		get_viewport().set_input_as_handled()

func _reveal_menu() -> void:
	_stage = 1
	if _prompt != null:
		_prompt.visible = false
	if _menu_box != null:
		_menu_box.visible = true
		_new_button.grab_focus()

func _on_new_game() -> void:
	AuroraAudio.trigger("ui_confirm")
	if host != null:
		host.start_game(true)
	_dismiss()

func _on_continue() -> void:
	AuroraAudio.trigger("ui_confirm")
	if host != null:
		host.start_game(false)
	_dismiss()

func _on_settings() -> void:
	AuroraAudio.trigger("ui_click")
	if _settings != null and is_instance_valid(_settings):
		return
	_settings = AuroraSettingsPanel.new()
	_settings.build()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)
	_settings.focus_default()

func _on_settings_closed() -> void:
	AuroraAudio.trigger("ui_click")
	if host != null and host.has_method("apply_difficulty"):
		host.apply_difficulty()
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	if _settings_button != null:
		_settings_button.grab_focus()

func _on_quit() -> void:
	AuroraAudio.trigger("ui_confirm")
	if host != null and host.has_method("request_quit"):
		host.request_quit()
	else:
		get_tree().quit(0)

func _dismiss() -> void:
	queue_free()

func _has_save() -> bool:
	return FileAccess.file_exists("user://aurora_vigil_save.json")
