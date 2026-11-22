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
var _environment: Label
var _atmosphere: Label
var _workshop: Label
var _mining: Label
var _weather: Label
var _status_timeout: Timer
var _supplies: Label
var _meters: Array[ProgressBar] = []
var _meter_values: Array[Label] = []
var _body_temperature: Label
var _temperature_gauge: TemperatureGauge
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
	_anchor(screen, top, Control.PRESET_TOP_WIDE, Vector2(26, 54), Vector2(-26, 54))
	var card := _panel(Color("#73baad"))
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(card)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 1)
	card.add_child(heading)
	_region = _label("", 13, GREEN)
	_location = _label("", 25, PAPER)
	heading.add_child(_region)
	heading.add_child(_location)
	_status = _label("", 13, GREEN)
	_status.hide()
	heading.add_child(_status)
	_mining = _label("", 13, AMBER)
	_mining.hide()
	heading.add_child(_mining)
	_status_timeout = Timer.new()
	_status_timeout.one_shot = true
	_status_timeout.wait_time = 4.0
	add_child(_status_timeout)
	_status_timeout.timeout.connect(_status.hide)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var vitals := _panel()
	vitals.custom_minimum_size.x = 225.0
	vitals.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(vitals)
	var readings := VBoxContainer.new()
	readings.add_theme_constant_override("separation", 4)
	vitals.add_child(readings)
	_weather = _label("", 13, AMBER)
	_weather.name = "CurrentWeather"
	readings.add_child(_weather)
	_environment = _label("", 12, MUTED)
	readings.add_child(_environment)
	_atmosphere = _label("", 12, MUTED)
	_atmosphere.name = "LocalAtmosphere"
	readings.add_child(_atmosphere)
	var names := ["Health", "Hunger", "Thirst", "Oxygen"]
	var colors := [Color("#ea8e83"), Color("#f0c686"), Color("#72c9ea"), Color("#a7e8cf")]
	for i in names.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		readings.add_child(row)
		var reading_name := _label(names[i], 13, PAPER)
		reading_name.custom_minimum_size.x = 57.0
		row.add_child(reading_name)
		var bar := ProgressBar.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(98, 8)
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _meter_style(Color("#26384a")))
		bar.add_theme_stylebox_override("fill", _meter_style(colors[i]))
		row.add_child(bar)
		_meters.append(bar)
		var value := _label("", 12, PAPER)
		value.custom_minimum_size.x = 30
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_meter_values.append(value)

	var temperature := HBoxContainer.new()
	temperature.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readings.add_child(temperature)
	var temperature_label := _label("Body temp", 13, PAPER)
	temperature_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temperature.add_child(temperature_label)
	_body_temperature = _label("", 12, PAPER)
	_body_temperature.name = "BodyTemperature"
	_body_temperature.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	temperature.add_child(_body_temperature)

	var scale_row := HBoxContainer.new()
	scale_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readings.add_child(scale_row)
	scale_row.add_child(_label("Cold", 11, TemperatureGauge.COLD))
	_temperature_gauge = TemperatureGauge.new()
	_temperature_gauge.custom_minimum_size = Vector2(98.0, 12.0)
	_temperature_gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_temperature_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_temperature_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale_row.add_child(_temperature_gauge)
	scale_row.add_child(_label("Hot", 11, TemperatureGauge.HOT))

	_supplies = _label("", 13, GREEN)
	readings.add_child(_supplies)

	var legend := _label("A / D Move     Space Jump\nHold left Mine     Right click Build\nF Gather     R Eat     T Drink\nC Craft     O Use air     F5 Save     Esc Pause", 13, PAPER)
	var controls := _panel()
	_anchor(screen, controls, Control.PRESET_BOTTOM_LEFT, Vector2(26, -120), Vector2(26, -20))
	controls.add_child(legend)

	var bar := VBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 6)
	_anchor(screen, bar, Control.PRESET_CENTER_BOTTOM, Vector2(-228, -138), Vector2(228, -20))
	_workshop = _label("", 14, GREEN)
	_workshop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_workshop.hide()
	bar.add_child(_workshop)
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


func show_region(region: int, planet: PlanetProfile) -> void:
	var on_surface := region == BlockWorld.Region.SURFACE
	_region.text = String(planet.details.biome).to_upper() if on_surface else "ORBITAL STATION"
	_location.text = planet.title() if on_surface else "Relay Nine"


func show_inventory(inventory: PackedInt32Array, selected: int) -> void:
	for i in _slot_labels.size():
		_slot_labels[i].text = "%d  %s\n%d" % [i + 1, BlockWorld.MATERIAL_NAMES[i], inventory[i]]
		_slot_panels[i].add_theme_stylebox_override("panel", _slot_styles[int(i == selected)])


func show_travel(region: int, nearby: bool, planet_name: String, direction: Vector2i) -> void:
	var prompt: String
	if nearby:
		prompt = "E  Launch to Relay Nine" if region == BlockWorld.Region.SURFACE else "E  Return to %s   ·   M  Star Chart" % planet_name
	else:
		var vertical := "%d %s" % [absi(direction.y), "up" if direction.y < 0 else "down"]
		var horizontal := "%d %s" % [absi(direction.x), "left" if direction.x < 0 else "right"]
		var path := vertical if direction.x == 0 else horizontal
		if direction.x != 0 and absi(direction.y) > 3:
			path += ", " + vertical
		prompt = "Beacon  %s tiles" % path
	if _travel.text != prompt:
		_travel.text = prompt


func show_mining(material: String, seconds: float) -> void:
	_mining.text = "%s  ·  %.2f s" % [material, seconds]
	_mining.show()


func hide_mining() -> void:
	_mining.hide()


func show_workshop(nearby: bool, region: int) -> void:
	_workshop.visible = nearby
	if nearby:
		_workshop.text = "C  Beacon workbench" if region == BlockWorld.Region.SURFACE else "C  Relay Nine workshop"


func show_status(message: String, saved: bool = true) -> void:
	_status.text = message
	_status.visible = not message.is_empty()
	_status.modulate = Color.WHITE if saved else AMBER
	_status_timeout.start()


func set_transit_route(target: int, planet_name: String) -> void:
	var outbound := target == BlockWorld.Region.STATION
	_transit_title.text = "Ascending to orbit" if outbound else "Returning to the surface"
	_transit_route.text = "%s  →  RELAY NINE" % planet_name.to_upper() if outbound else "RELAY NINE  →  %s" % planet_name.to_upper()


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

func show_survival(state: SurvivalState, kit: ExpeditionKit, air: String, weather: String,
		atmosphere: String, pressure_warning: bool, temperature_target: float) -> void:
	var levels := [state.health, state.hunger, state.thirst, state.oxygen]
	for i in _meters.size():
		_meters[i].value = levels[i]
		var value := str(ceili(levels[i]))
		if _meter_values[i].text != value:
			_meter_values[i].text = value
	_show_body_temperature(state.body_temperature, temperature_target)
	var supplies := "Rations %d  ·  Water %d  ·  Air %d" % [state.food, state.water, kit.canisters]
	if _supplies.text != supplies:
		_supplies.text = supplies
	var conditions := "Weather: %s" % weather if weather != "Orbit" else "Orbit"
	if _weather.text != conditions:
		_weather.text = conditions
		_weather.modulate = Color("#f4bb87") if PlanetProfile.harsh_weather(weather) else Color.WHITE
	if _environment.text != air:
		_environment.text = air
	if _atmosphere.text != atmosphere:
		_atmosphere.text = atmosphere
	_atmosphere.modulate = AMBER if pressure_warning else Color.WHITE


func _show_body_temperature(value: float, target: float) -> void:
	_temperature_gauge.show_temperature(value)
	var reading := "%.1f °C" % value
	if value <= SurvivalState.COLD_STRESS_TEMPERATURE:
		reading += " · Too cold"
	elif value >= SurvivalState.HEAT_STRESS_TEMPERATURE:
		reading += " · Too hot"
	elif absf(target - value) > 0.15:
		if target == SurvivalState.NORMAL_BODY_TEMPERATURE:
			reading += " · Recovering"
		else:
			reading += " · Cooling" if target < value else " · Warming"
	if _body_temperature.text != reading:
		_body_temperature.text = reading
	var tint := PAPER
	if value < TemperatureGauge.COMFORT_MIN:
		tint = TemperatureGauge.COLD
	elif value > TemperatureGauge.COMFORT_MAX:
		tint = TemperatureGauge.HOT
	if _body_temperature.get_theme_color("font_color") != tint:
		_body_temperature.add_theme_color_override("font_color", tint)


static func _meter_style(fill: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.set_corner_radius_all(2)
	return result
