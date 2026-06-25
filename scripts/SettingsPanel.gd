class_name AuroraSettingsPanel
extends Control

# Reusable settings overlay used by both the main menu and the pause menu. Builds a
# keyboard/controller-navigable column of controls (mouse/look sensitivity, the three
# volume sliders, flight invert-Y, and difficulty) that read and write the existing
# SettingsManager autoload, persisting to user://settings.cfg on every change. Emits
# `closed` when the player backs out so the host can re-apply difficulty and refocus.
#
# Built entirely in code so it works whether instanced from a .tscn or via .new().
# Robust if SettingsManager is somehow absent (headless contexts) — it simply no-ops
# the reads/writes and shows defaults.

signal closed

var _mouse_slider: HSlider
var _master_slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _invert_check: CheckButton
var _difficulty_option: OptionButton
var _back_button: Button
var _built: bool = false

func _ready() -> void:
	if not _built:
		build()

func build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.01, 0.02, 0.05, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(440, 120)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_mouse_slider = _add_slider(col, "Look / Mouse Sensitivity", 0.1, 4.0, 0.05, _get_mouse_sensitivity())
	_master_slider = _add_slider(col, "Master Volume", 0.0, 1.0, 0.01, _get_vol("master"))
	_sfx_slider = _add_slider(col, "SFX Volume", 0.0, 1.0, 0.01, _get_vol("sfx"))
	_music_slider = _add_slider(col, "Music Volume", 0.0, 1.0, 0.01, _get_vol("music"))

	_invert_check = CheckButton.new()
	_invert_check.text = "Invert Flight / Look Y"
	_invert_check.button_pressed = _get_invert_y()
	_invert_check.toggled.connect(_on_invert_toggled)
	col.add_child(_invert_check)

	var diff_row := HBoxContainer.new()
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	diff_label.custom_minimum_size = Vector2(180, 0)
	diff_row.add_child(diff_label)
	_difficulty_option = OptionButton.new()
	for i in _difficulty_order().size():
		_difficulty_option.add_item(_difficulty_order()[i], i)
	_difficulty_option.selected = _current_difficulty_index()
	_difficulty_option.item_selected.connect(_on_difficulty_selected)
	diff_row.add_child(_difficulty_option)
	col.add_child(diff_row)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(0, 40)
	_back_button.pressed.connect(_on_back)
	col.add_child(_back_button)

	_mouse_slider.value_changed.connect(_on_mouse_changed)
	_master_slider.value_changed.connect(_on_master_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_music_slider.value_changed.connect(_on_music_changed)

func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(180, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	parent.add_child(row)
	return slider

func focus_default() -> void:
	if _back_button != null:
		_back_button.grab_focus()

# ── SettingsManager bridge (guarded so a missing autoload never crashes the UI) ──

func _sm():
	return get_node_or_null("/root/SettingsManager")

func _get_mouse_sensitivity() -> float:
	var sm = _sm()
	return sm.mouse_sensitivity if sm != null else 1.0

func _get_invert_y() -> bool:
	var sm = _sm()
	return sm.invert_y if sm != null else false

func _get_vol(which: String) -> float:
	var sm = _sm()
	if sm == null:
		return 1.0
	match which:
		"master": return sm.volume_master
		"sfx": return sm.volume_sfx
		"music": return sm.volume_music
	return 1.0

func _difficulty_order() -> Array:
	var sm = _sm()
	if sm != null:
		return sm.DIFFICULTY_ORDER
	return ["Easy", "Normal", "Hard"]

func _current_difficulty_index() -> int:
	var sm = _sm()
	if sm == null:
		return 1
	var idx := _difficulty_order().find(sm.difficulty)
	return idx if idx >= 0 else 1

func _on_mouse_changed(v: float) -> void:
	var sm = _sm()
	if sm != null:
		sm.mouse_sensitivity = v
		sm.save_settings()

func _on_master_changed(v: float) -> void:
	var sm = _sm()
	if sm != null:
		sm.volume_master = v
		sm.apply_audio()
		sm.save_settings()

func _on_sfx_changed(v: float) -> void:
	var sm = _sm()
	if sm != null:
		sm.volume_sfx = v
		sm.apply_audio()
		sm.save_settings()

func _on_music_changed(v: float) -> void:
	var sm = _sm()
	if sm != null:
		sm.volume_music = v
		sm.apply_audio()
		sm.save_settings()

func _on_invert_toggled(pressed: bool) -> void:
	var sm = _sm()
	if sm != null:
		sm.invert_y = pressed
		sm.save_settings()

func _on_difficulty_selected(index: int) -> void:
	var order := _difficulty_order()
	if index < 0 or index >= order.size():
		return
	var sm = _sm()
	if sm != null:
		sm.set_difficulty(str(order[index]))

func _on_back() -> void:
	AuroraAudio.trigger("ui_click")
	closed.emit()
