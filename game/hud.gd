class_name FlightHUD
extends CanvasLayer

const PAPER := Color("#dce8e8")
const MUTED := Color("#9bb4c0")
const GREEN := Color("#a7e8cf")
const AMBER := Color("#f0c686")

var transit: ColorRect

var _region: Label
var _location: Label
var _status: Label
var _travel: Label
var _transit_title: Label
var _transit_route: Label
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	var screen := Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	_anchor(screen, top, Control.PRESET_TOP_WIDE, Vector2(26, 22), Vector2(-26, 22))
	var card := _panel(Color("#73baad"))
	top.add_child(card)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 1)
	card.add_child(heading)
	_region = _label("", 13, GREEN)
	_location = _label("", 25, PAPER)
	heading.add_child(_region)
	heading.add_child(_location)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_status = _label("", 15, GREEN)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	top.add_child(_status)

	var legend := _label("A / D  Move     Space  Jump\nLeft click  Mine     Right click  Build\nF5  Save expedition", 13, PAPER)
	var controls := _panel()
	_anchor(screen, controls, Control.PRESET_BOTTOM_LEFT, Vector2(26, -104), Vector2(26, -20))
	controls.add_child(legend)

	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	_anchor(screen, bar, Control.PRESET_CENTER_BOTTOM, Vector2(-228, -108), Vector2(228, -20))
	_travel = _label("", 16, AMBER)
	_travel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_travel)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	bar.add_child(slots)
	_slot_styles = [_style(Color("#395061")), _style(GREEN)]
	for i in BlockWorld.MATERIAL_NAMES.size():
		var panel := _panel()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(panel)
		_slot_panels.append(panel)
		var label := _label("", 14, PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
		_slot_labels.append(label)

	transit = ColorRect.new()
	transit.color = Color("#0a1323")
	transit.modulate.a = 0.0
	transit.hide()
	_anchor(screen, transit, Control.PRESET_FULL_RECT, Vector2.ZERO, Vector2.ZERO)
	var route := VBoxContainer.new()
	route.alignment = BoxContainer.ALIGNMENT_CENTER
	_anchor(transit, route, Control.PRESET_FULL_RECT, Vector2.ZERO, Vector2.ZERO)
	_transit_title = _label("", 32, PAPER)
	_transit_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transit_route = _label("", 16, GREEN)
	_transit_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.add_child(_transit_title)
	route.add_child(_transit_route)


func show_region(region: int) -> void:
	var on_surface := region == BlockWorld.Region.SURFACE
	_region.text = "PLANET SURFACE" if on_surface else "LOW ORBIT"
	_location.text = "Cinder Reach" if on_surface else "Relay Nine"


func show_inventory(inventory: PackedInt32Array, selected: int) -> void:
	for i in _slot_labels.size():
		_slot_labels[i].text = "%d  %s\n%d" % [i + 1, BlockWorld.MATERIAL_NAMES[i], inventory[i]]
		_slot_panels[i].add_theme_stylebox_override("panel", _slot_styles[int(i == selected)])


func show_travel(region: int, nearby: bool) -> void:
	var prompt := "Find the beacon to travel"
	if nearby:
		prompt = "E  Launch to Relay Nine" if region == BlockWorld.Region.SURFACE else "E  Return to Cinder Reach"
	if _travel.text != prompt:
		_travel.text = prompt


func show_status(message: String, saved: bool = true) -> void:
	_status.text = message
	_status.modulate = Color.WHITE if saved else AMBER


func set_transit_route(target: int) -> void:
	var outbound := target == BlockWorld.Region.STATION
	_transit_title.text = "Ascending to orbit" if outbound else "Returning to the surface"
	_transit_route.text = "CINDER REACH  →  RELAY NINE" if outbound else "RELAY NINE  →  CINDER REACH"


static func _anchor(parent: Control, item: Control, preset: int, start: Vector2, end: Vector2) -> void:
	parent.add_child(item)
	item.set_anchors_and_offsets_preset(preset)
	item.offset_left = start.x
	item.offset_top = start.y
	item.offset_right = end.x
	item.offset_bottom = end.y
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label


static func _panel(border := Color("#395061")) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _style(border))
	return card


static func _style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.15, 0.94)
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 11
	style.content_margin_right = 11
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
