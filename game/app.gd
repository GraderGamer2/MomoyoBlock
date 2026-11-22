class_name MomoyoApp
extends Node

enum Screen { TITLE, EXPLORING, PAUSED, SETTINGS, STAR_CHART }

const EXPEDITION := preload("res://game/main.tscn")

var screen := Screen.TITLE
var game: MomoyoGame
var preferences := GamePreferences.new()

var _settings_return := Screen.TITLE
var _quit_confirmed := false
@onready var _ui: ShellUI = $Shell


func _ready() -> void:
	var display := DisplayServer.get_name()
	if display != "Wayland" and display != "headless":
		push_error("MomoyoBlock requires a Wayland session.")
		get_tree().quit(1)
		return
	if display == "Wayland":
		get_window().min_size = Vector2i(640, 360)
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	preferences.load_settings()
	preferences.apply_live()
	_ui.close_pressed.connect(request_quit)
	show_title()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	match screen:
		Screen.EXPLORING:
			show_pause()
		Screen.PAUSED, Screen.STAR_CHART:
			resume_expedition()
		Screen.SETTINGS:
			_leave_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


func show_title() -> void:
	screen = Screen.TITLE
	_quit_confirmed = false
	get_tree().paused = false
	var body := _ui.open_panel("MomoyoBlock", "Survival expedition", true)
	var caption := "Continue expedition" if FileAccess.file_exists(ExpeditionSave.SLOT) else "New expedition"
	var play := _ui.button(caption, start_expedition, true)
	body.add_child(play)
	body.add_child(_ui.button("Settings", show_settings.bind(Screen.TITLE)))
	body.add_child(_ui.button("Quit", request_quit))
	_ui.finish_panel(play)


func start_expedition() -> void:
	if game != null:
		return
	game = EXPEDITION.instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.chart_requested.connect(show_chart)
	resume_expedition()


func resume_expedition() -> void:
	if game == null:
		return
	screen = Screen.EXPLORING
	_quit_confirmed = false
	get_tree().paused = false
	_ui.hide_panel()


func show_pause() -> void:
	screen = Screen.PAUSED
	get_tree().paused = true
	var body := _ui.open_panel("Expedition paused", "")
	var resume := _ui.button("Resume", resume_expedition, true)
	body.add_child(resume)
	if game.can_choose_planet():
		body.add_child(_ui.button("Star chart", show_chart))
	body.add_child(_ui.button("Settings", show_settings.bind(Screen.PAUSED)))
	body.add_child(_ui.button("Save and return to menu", return_to_menu))
	body.add_child(_ui.button("Save and quit", request_quit))
	_ui.finish_panel(resume)


func return_to_menu() -> void:
	if not game.save_expedition(false):
		_ui.show_feedback("Could not save. The expedition is still open.")
		return
	remove_child(game)
	game.queue_free()
	game = null
	show_title()


func request_quit() -> void:
	if game == null or _quit_confirmed or game.save_expedition(false):
		get_tree().quit()
		return
	show_pause()
	_quit_confirmed = true
	_ui.show_feedback("Could not save. Select Quit again to exit anyway.")


func show_settings(previous: Screen) -> void:
	_settings_return = previous
	screen = Screen.SETTINGS
	var body := _ui.open_panel("Settings", "Frame rate, display, and sound", previous == Screen.TITLE)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)

	var fps := OptionButton.new()
	fps.name = "FrameLimit"
	for cap in GamePreferences.FPS_OPTIONS:
		fps.add_item("Unlimited" if cap == 0 else "%d FPS" % cap, cap)
	fps.select(GamePreferences.FPS_OPTIONS.find(preferences.fps_limit))
	_add_setting(grid, "Frame rate limit", fps)

	var vsync := CheckButton.new()
	vsync.name = "VSync"
	vsync.text = "Enabled"
	vsync.button_pressed = preferences.vsync
	_add_setting(grid, "VSync", vsync)

	var renderer := OptionButton.new()
	renderer.name = "Renderer"
	renderer.add_item("Compatibility (OpenGL)")
	renderer.add_item("Mobile (Vulkan)")
	renderer.select(GamePreferences.RENDERERS.find(preferences.renderer))
	_add_setting(grid, "Renderer", renderer)

	var volume_row := HBoxContainer.new()
	var volume := HSlider.new()
	volume.name = "MasterVolume"
	volume.max_value = 100.0
	volume.step = 1.0
	volume.value = preferences.volume * 100.0
	volume.custom_minimum_size = Vector2(132, 24)
	volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var volume_value := _ui.label("%d%%" % roundi(volume.value), 14)
	volume_value.custom_minimum_size.x = 43
	volume.value_changed.connect(func(value: float) -> void: volume_value.text = "%d%%" % roundi(value))
	volume_row.add_child(volume)
	volume_row.add_child(volume_value)
	_add_setting(grid, "Master volume", volume_row)

	var active := RenderingServer.get_current_rendering_method()
	var active_text := "Mobile (Vulkan)" if active == "mobile" else "Compatibility (OpenGL)"
	body.add_child(_ui.label("Running %s. Renderer changes apply on next launch." % active_text, 13, ShellUI.MUTED))
	var apply := _ui.button("Apply settings", _apply_settings.bind(fps, vsync, renderer, volume), true)
	apply.name = "ApplySettings"
	body.add_child(apply)
	body.add_child(_ui.button("Back", _leave_settings))
	_ui.finish_panel(fps)


func _apply_settings(fps: OptionButton, vsync: CheckButton, renderer: OptionButton, volume: HSlider) -> void:
	var draft := GamePreferences.new()
	draft.fps_limit = fps.get_selected_id()
	draft.vsync = vsync.button_pressed
	draft.renderer = GamePreferences.RENDERERS[renderer.selected]
	draft.volume = volume.value / 100.0
	if draft.save_settings() != OK:
		_ui.show_feedback("Could not save settings.")
		return
	preferences = draft
	preferences.apply_live()
	_ui.show_feedback("Settings applied. Restart for the selected renderer." if draft.renderer != RenderingServer.get_current_rendering_method() else "Settings applied.")


func _leave_settings() -> void:
	if _settings_return == Screen.PAUSED:
		show_pause()
	else:
		show_title()


func show_chart() -> void:
	if game == null or not game.can_choose_planet():
		return
	screen = Screen.STAR_CHART
	get_tree().paused = true
	var body := _ui.open_panel("Star chart", "Select a sector to land from Relay Nine.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	body.add_child(grid)
	var preferred_x := game.sector.x + (1 if game.sector.x < 2147483647 else -1)
	var column := _sector_coordinate(preferred_x)
	var row := _sector_coordinate(game.sector.y)
	_add_setting(grid, "Sector X", column)
	_add_setting(grid, "Sector Y", row)
	var preview := _ui.label("", 16, ShellUI.MINT)
	body.add_child(preview)
	var detail := _ui.label("", 14, ShellUI.MUTED)
	body.add_child(detail)
	var refresh := _refresh_chart.bind(column, row, preview, detail)
	column.value_changed.connect(func(_value: float) -> void: refresh.call())
	row.value_changed.connect(func(_value: float) -> void: refresh.call())
	refresh.call()
	var land := _ui.button("Land on this planet", _land.bind(column, row), true)
	body.add_child(land)
	body.add_child(_ui.button("Back", resume_expedition))
	_ui.finish_panel(land)


func _land(column: SpinBox, row: SpinBox) -> void:
	column.apply()
	row.apply()
	if game.land_at(Vector2i(int(column.value), int(row.value))):
		resume_expedition()


static func _refresh_chart(column: SpinBox, row: SpinBox, preview: Label, detail: Label) -> void:
	var destination := PlanetProfile.new(Vector2i(int(column.value), int(row.value)))
	preview.text = destination.title()
	var air := "Breathable" if destination.details.breathable else "Suit oxygen required"
	detail.text = "%s  ·  %s  ·  %s\nForage: %s and %s  ·  %s" % [
		destination.details.biome, air, destination.details.weather,
		destination.details.flora, destination.details.water, destination.details.fauna,
	]


static func _sector_coordinate(value: int) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = -2147483648
	field.max_value = 2147483647
	field.value = value
	field.custom_minimum_size.x = 170.0
	return field


func _add_setting(grid: GridContainer, caption: String, control: Control) -> void:
	grid.add_child(_ui.label(caption, 15, ShellUI.PAPER))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
