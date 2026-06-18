extends CanvasLayer

# Game-over overlay shown when the hero's health reaches zero. Freezes the tree
# (get_tree().paused) behind a dark overlay so the auto-respawn loop in HealthSystem
# cannot fire while the player decides, then offers Retry (respawn at the last
# checkpoint with 50 HP) or Quit to Main Menu. Processes while paused
# (process_mode = ALWAYS). Never instanced during headless capture/auto-quit runs.

var host
var _root: Control
var _retry_button: Button
var _shown: bool = false

func setup(host_ref) -> void:
	host = host_ref
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 45
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.0, 0.02, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var title := Label.new()
	title.text = "YOU FELL PROTECTING MERIDIAN"
	title.position = Vector2(0, 200)
	title.size = Vector2(1280, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.32, 0.25, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_root.add_child(title)

	var sub := Label.new()
	sub.text = "The city still needs its guardian."
	sub.position = Vector2(0, 286)
	sub.size = Vector2(1280, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1.0, 0.8, 0.75, 0.95))
	_root.add_child(sub)

	var box := VBoxContainer.new()
	box.position = Vector2(540, 380)
	box.custom_minimum_size = Vector2(200, 0)
	box.add_theme_constant_override("separation", 12)
	_root.add_child(box)

	_retry_button = Button.new()
	_retry_button.text = "Retry"
	_retry_button.custom_minimum_size = Vector2(200, 44)
	_retry_button.add_theme_font_size_override("font_size", 22)
	_retry_button.pressed.connect(_on_retry)
	box.add_child(_retry_button)

	var quit_b := Button.new()
	quit_b.text = "Quit to Main Menu"
	quit_b.custom_minimum_size = Vector2(200, 44)
	quit_b.add_theme_font_size_override("font_size", 22)
	quit_b.pressed.connect(_on_quit_to_menu)
	box.add_child(quit_b)

	_root.visible = false

func show_screen() -> void:
	if _shown:
		return
	_shown = true
	_root.visible = true
	get_tree().paused = true
	if _retry_button != null:
		_retry_button.grab_focus()

func hide_screen() -> void:
	if not _shown:
		return
	_shown = false
	_root.visible = false
	get_tree().paused = false

func is_shown() -> bool:
	return _shown

func _on_retry() -> void:
	hide_screen()
	if host != null and host.has_method("retry_from_checkpoint"):
		host.retry_from_checkpoint()

func _on_quit_to_menu() -> void:
	hide_screen()
	if host != null and host.has_method("return_to_main_menu"):
		host.return_to_main_menu()
