extends CanvasLayer

# In-game pause menu. Owns the `aurora_pause` toggle (Esc / controller Select) for
# both opening and closing, since the host's _physics_process is frozen while paused.
# Pauses the scene tree (time scale 0 via get_tree().paused) behind a translucent
# overlay and offers Resume / Settings / Quit to Main Menu. Processes while paused
# (process_mode = ALWAYS). Never instanced during headless capture/auto-quit runs.

var host
var _settings: AuroraSettingsPanel
var _root: Control
var _panel: VBoxContainer
var _resume_button: Button
var _is_open: bool = false

func setup(host_ref) -> void:
	host = host_ref
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var title := Label.new()
	title.text = "PAUSED"
	title.position = Vector2(0, 180)
	title.size = Vector2(1280, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_root.add_child(title)

	_panel = VBoxContainer.new()
	_panel.position = Vector2(540, 320)
	_panel.custom_minimum_size = Vector2(200, 0)
	_panel.add_theme_constant_override("separation", 12)
	_root.add_child(_panel)

	_resume_button = _make_button("Resume", _on_resume)
	_make_button("Settings", _on_settings)
	_make_button("Quit to Main Menu", _on_quit_to_menu)

	_root.visible = false

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("aurora_pause"):
		return
	# Esc backs out of the settings sub-panel first if it is open.
	if _settings != null and is_instance_valid(_settings):
		_on_settings_closed()
		get_viewport().set_input_as_handled()
		return
	# Do not allow pause while the game-over screen owns the tree.
	if host != null and host.has_method("is_game_over") and host.is_game_over():
		return
	if _is_open:
		_on_resume()
	else:
		open()
	get_viewport().set_input_as_handled()

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_root.visible = true
	get_tree().paused = true
	if _resume_button != null:
		_resume_button.grab_focus()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	get_tree().paused = false

func is_open() -> bool:
	return _is_open

func _on_resume() -> void:
	close()

func _on_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		return
	_settings = AuroraSettingsPanel.new()
	_settings.build()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)
	_settings.focus_default()

func _on_settings_closed() -> void:
	if host != null and host.has_method("apply_difficulty"):
		host.apply_difficulty()
	if _settings != null and is_instance_valid(_settings):
		_settings.queue_free()
	_settings = null
	if _resume_button != null:
		_resume_button.grab_focus()

func _on_quit_to_menu() -> void:
	close()
	if host != null and host.has_method("return_to_main_menu"):
		host.return_to_main_menu()
