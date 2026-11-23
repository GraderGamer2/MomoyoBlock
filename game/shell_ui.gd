class_name ShellUI
extends CanvasLayer

signal close_pressed

const PAPER := Color("#e4eeee")
const MUTED := Color("#a5bdc8")
const MINT := Color("#a8e5cb")
const AMBER := Color("#f1c182")

var _layer: Control
var _title_art: Horizon
var _overlay: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var _feedback: Label


func _ready() -> void:
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_title_art = Horizon.new()
	_title_art.z_index = -1
	_layer.add_child(_title_art)
	_title_art.show_region(BlockWorld.Region.STATION)

	_overlay = ColorRect.new()
	_overlay.color = Color(0.025, 0.055, 0.095, 0.68)
	_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 38
	center.offset_bottom = -10
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 408.0
	_panel.add_theme_stylebox_override("panel", _style(Color("#102031"), Color("#40616f"), 23))
	center.add_child(_panel)

	_build_titlebar()
	_add_resize_handle()


func open_panel(title: String, subtitle: String, as_title := false) -> VBoxContainer:
	_title_art.visible = as_title
	_overlay.show()
	if is_instance_valid(_body):
		_panel.remove_child(_body)
		_body.queue_free()
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 9)
	_panel.add_child(_body)
	_body.add_child(label(title, 34, PAPER))
	if not subtitle.is_empty():
		_body.add_child(label(subtitle, 14, MUTED))
	_feedback = label("", 13, AMBER)
	_feedback.hide()
	return _body


func finish_panel(focus: Control = null) -> void:
	_body.add_child(_feedback)
	if focus != null:
		_focus_visible.call_deferred(focus)


func _focus_visible(control: Control) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func show_feedback(message: String) -> void:
	if is_instance_valid(_feedback):
		_feedback.text = message
		_feedback.show()


func hide_panel() -> void:
	_overlay.hide()
	_title_art.hide()


func button(caption: String, action: Callable, primary := false) -> Button:
	var control := Button.new()
	control.text = caption
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.custom_minimum_size.y = 38
	control.add_theme_font_size_override("font_size", 16)
	control.add_theme_color_override("font_color", Color("#112b32") if primary else PAPER)
	var interaction_color := Color("#0e2b2f") if primary else Color.WHITE
	control.add_theme_color_override("font_hover_color", interaction_color)
	control.add_theme_color_override("font_focus_color", interaction_color)
	control.add_theme_color_override("font_pressed_color", interaction_color)
	control.add_theme_color_override("font_hover_pressed_color", interaction_color)
	control.add_theme_stylebox_override("normal", _style(MINT if primary else Color("#203447"), Color("#497180"), 6))
	control.add_theme_stylebox_override("hover", _style(Color("#caf4df") if primary else Color("#2b4558"), MINT, 6))
	control.add_theme_stylebox_override("pressed", _style(Color("#8ccbb6") if primary else Color("#162d41"), MINT, 6))
	control.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("#d9e8b0"), 6))
	control.pressed.connect(action)
	return control


func tabs() -> TabContainer:
	var control := TabContainer.new()
	control.use_hidden_tabs_for_min_size = true
	control.add_theme_font_size_override("font_size", 15)
	control.add_theme_color_override("font_selected_color", MINT)
	control.add_theme_color_override("font_unselected_color", MUTED)
	control.add_theme_stylebox_override("panel", _style(Color("#142637"), Color("#344f60"), 12))
	control.add_theme_stylebox_override("tab_selected", _style(Color("#1d3746"), Color("#69a297"), 8))
	control.add_theme_stylebox_override("tab_unselected", _style(Color("#172739"), Color("#344f60"), 8))
	control.add_theme_stylebox_override("tab_hovered", _style(Color("#243f50"), Color("#69a297"), 8))
	control.get_tab_bar().mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return control


static func label(caption: String, font_size: int, tint := PAPER) -> Label:
	var control := Label.new()
	control.text = caption
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_theme_color_override("font_color", tint)
	control.add_theme_font_size_override("font_size", font_size)
	return control


func _build_titlebar() -> void:
	var frame := PanelContainer.new()
	frame.name = "TitleBar"
	_layer.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	frame.offset_bottom = 38
	frame.add_theme_stylebox_override("panel", _style(Color("#0b1624"), Color("#1c3444"), 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	frame.add_child(row)

	var drag := Label.new()
	drag.text = "   MomoyoBlock"
	drag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	drag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag.gui_input.connect(_drag_titlebar)
	drag.add_theme_color_override("font_color", MINT)
	row.add_child(drag)

	_add_window_button(row, "−", "Minimize", _minimize)
	_add_window_button(row, "□", "Maximize or restore", _toggle_maximized)
	_add_window_button(row, "×", "Close game", close_pressed.emit)


func _add_window_button(row: HBoxContainer, glyph: String, hint: String, action: Callable) -> void:
	var control := button(glyph, action)
	control.custom_minimum_size = Vector2(42, 32)
	control.tooltip_text = hint
	control.focus_mode = Control.FOCUS_NONE
	row.add_child(control)


func _add_resize_handle() -> void:
	var handle := Control.new()
	_layer.add_child(handle)
	handle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	handle.offset_left = -18
	handle.offset_top = -18
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	handle.tooltip_text = "Resize window"
	handle.gui_input.connect(_resize_window)
	var grip := label("◢", 12, MUTED)
	handle.add_child(grip)


func _drag_titlebar(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			_toggle_maximized()
		elif DisplayServer.get_name() == "Wayland":
			get_window().start_drag()


func _resize_window(event: InputEvent) -> void:
	if DisplayServer.get_name() == "Wayland" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_window().start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT)


func _minimize() -> void:
	if DisplayServer.get_name() == "Wayland":
		get_window().mode = Window.MODE_MINIMIZED


func _toggle_maximized() -> void:
	if DisplayServer.get_name() == "Wayland":
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_MAXIMIZED else Window.MODE_MAXIMIZED


static func _style(fill: Color, border: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box
