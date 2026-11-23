class_name MomoyoApp
extends Node

enum Screen { TITLE, EXPLORING, PAUSED, SETTINGS, STAR_CHART, LOAD, WORKSHOP, INVENTORY, SANDBOX }

const EXPEDITION := preload("res://game/main.tscn")

var screen := Screen.TITLE
var game: MomoyoGame
var preferences := GamePreferences.new()

var _settings_return := Screen.TITLE
var _sandbox_return := Screen.EXPLORING
var _quit_confirmed := false
var _inventory_slots: Array[InventorySlot] = []
var _moving_slot := -1
var _workshop_tab := 0
@onready var _ui: ShellUI = $Shell


func _ready() -> void:
	var display := DisplayServer.get_name()
	if display != "Wayland" and display != "headless":
		push_error("MomoyoBlock requires a Wayland session.")
		get_tree().quit(1)
		return
	if display == "Wayland":
		get_window().min_size = Vector2i(640, 360)
	get_window().size_changed.connect(_fit_window_content, CONNECT_DEFERRED)
	_fit_window_content()
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	preferences.load_settings()
	preferences.apply_live()
	_ui.close_pressed.connect(request_quit)
	show_title()


func _fit_window_content() -> void:
	var window := get_window()
	var fit := Vector2(window.size) / Vector2(window.content_scale_size)
	var scale := minf(fit.x, fit.y)
	if scale <= 0.0:
		return
	if not is_equal_approx(window.content_scale_factor, scale):
		window.content_scale_factor = scale
	_ui.fit_window_controls()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("sandbox_materials") and screen in [Screen.EXPLORING, Screen.SANDBOX]:
		get_viewport().set_input_as_handled()
		if screen == Screen.EXPLORING:
			show_sandbox(Screen.EXPLORING)
		else:
			_leave_sandbox()
		return
	if event.is_action_pressed("inventory") and screen in [Screen.EXPLORING, Screen.INVENTORY]:
		get_viewport().set_input_as_handled()
		if screen == Screen.EXPLORING:
			show_inventory()
		else:
			resume_expedition()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	match screen:
		Screen.EXPLORING:
			show_pause()
		Screen.PAUSED, Screen.STAR_CHART, Screen.WORKSHOP, Screen.INVENTORY:
			resume_expedition()
		Screen.SETTINGS:
			_leave_settings()
		Screen.LOAD:
			show_title()
		Screen.SANDBOX:
			_leave_sandbox()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


func show_title() -> void:
	screen = Screen.TITLE
	_quit_confirmed = false
	get_tree().paused = false
	var body := _ui.open_panel("MomoyoBlock", "Survival expedition", true)
	var slots := ExpeditionSave.slots()
	var play: Button
	if slots.is_empty():
		play = _ui.button("New expedition", start_new_expedition, true)
		body.add_child(play)
	else:
		play = _ui.button("Continue expedition", start_expedition.bind(slots[0]), true)
		body.add_child(play)
		body.add_child(_ui.button("New expedition", start_new_expedition))
		if slots.size() > 1:
			body.add_child(_ui.button("Load expedition", _show_load_menu))
	body.add_child(_ui.button("Settings", show_settings.bind(Screen.TITLE)))
	body.add_child(_ui.button("Quit", request_quit))
	_ui.finish_panel(play)


func start_new_expedition() -> void:
	start_expedition(ExpeditionSave.unused_filename())


func start_expedition(filename := ExpeditionSave.DEFAULT_FILE) -> void:
	if game != null:
		return
	game = EXPEDITION.instantiate()
	game.save_filename = filename
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	game.chart_requested.connect(show_chart)
	game.workshop_requested.connect(show_workshop)
	resume_expedition()


func _show_load_menu() -> void:
	var slots := ExpeditionSave.slots()
	if slots.is_empty():
		show_title()
		return
	screen = Screen.LOAD
	var body := _ui.open_panel("Load expedition", "Choose a saved expedition.", true)
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 36
	for filename in slots:
		picker.add_item(ExpeditionSave.slot_title(filename))
	picker.select(0)
	body.add_child(picker)
	var load_button := _ui.button("Load selected expedition",
			func() -> void: start_expedition(slots[picker.selected]), true)
	body.add_child(load_button)
	body.add_child(_ui.button("Back", show_title))
	_ui.finish_panel(picker)


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
	body.add_child(_ui.button("Sandbox materials", show_sandbox.bind(Screen.PAUSED)))
	body.add_child(_ui.button("Settings", show_settings.bind(Screen.PAUSED)))
	body.add_child(_ui.button("Save and return to menu", return_to_menu))
	body.add_child(_ui.button("Save and quit", request_quit))
	_ui.finish_panel(resume)


func show_sandbox(previous: Screen) -> void:
	_sandbox_return = previous
	screen = Screen.SANDBOX
	get_tree().paused = true
	var enabled := game.sandbox_enabled
	var subtitle := "Enable unlimited building materials for this expedition."
	if enabled:
		subtitle = "Select any building block for unlimited placement."
	var body := _ui.open_panel("Sandbox materials", subtitle)
	var toggle := _ui.button("Disable sandbox materials" if enabled else "Enable sandbox materials", _toggle_sandbox, not enabled)
	toggle.name = "SandboxToggle"
	body.add_child(toggle)
	var focus: Control = toggle
	if enabled:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		body.add_child(grid)
		for material in range(1, BlockWorld.BLOCK_NAMES.size()):
			if not BlockWorld.is_placeable(material):
				continue
			var button := _ui.button(ExpeditionInventory.item_name(material), _select_sandbox_block.bind(material))
			button.name = "SandboxBlock%d" % material
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if grid.get_child_count() == 0:
				focus = button
			grid.add_child(button)
	body.add_child(_ui.button("Back", _leave_sandbox))
	_ui.finish_panel(focus)


func _toggle_sandbox() -> void:
	game.set_sandbox(not game.sandbox_enabled)
	show_sandbox(_sandbox_return)


func _leave_sandbox() -> void:
	if _sandbox_return == Screen.PAUSED:
		show_pause()
	else:
		resume_expedition()


func _select_sandbox_block(material: int) -> void:
	if game.select_sandbox_material(material):
		resume_expedition()


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


func show_workshop() -> void:
	if game == null:
		return
	screen = Screen.WORKSHOP
	get_tree().paused = true
	var workbench := game.workbench_name()
	var in_field := workbench.is_empty()
	var caption := "Field crafting" if in_field else workbench
	var subtitle := "Deploy a workbench to unlock equipment and repairs." if in_field else ""
	var body := _ui.open_panel(caption, subtitle)
	var focus: Control
	if in_field:
		body.add_child(_recipe_row(ExpeditionKit.Recipe.WORKBENCH))
	else:
		var tabs := _workshop_categories()
		body.add_child(tabs)
		focus = tabs.get_tab_bar()
	if game.sandbox_enabled:
		body.add_child(_ui.label("Unlimited crafting materials", 13, ShellUI.MINT))
	else:
		var supplies := PackedStringArray()
		for item: int in BlockWorld.BUILD_MATERIALS:
			supplies.append("%d %s" % [game.inventory.count(item, game.survival.suit_equipped), ExpeditionInventory.item_name(item).to_lower()])
		body.add_child(_ui.label("Carried  " + "  ·  ".join(supplies), 13, ShellUI.MINT))
	var back := _ui.button("Back to expedition", resume_expedition, true)
	body.add_child(back)
	_ui.finish_panel(focus if focus != null else back)


func _workshop_categories() -> TabContainer:
	var tabs := _ui.tabs()
	tabs.name = "RecipeCategories"
	var lists: Array[VBoxContainer] = []
	for caption: String in ExpeditionKit.CATEGORY_NAMES:
		var recipes := VBoxContainer.new()
		recipes.name = caption
		recipes.add_theme_constant_override("separation", 8)
		tabs.add_child(recipes)
		lists.append(recipes)
	for recipe in ExpeditionKit.RECIPES.size():
		if game.kit.shows_recipe(recipe, false):
			lists[ExpeditionKit.RECIPES[recipe].category].add_child(_recipe_row(recipe))
	if game.kit.pulse_level == ExpeditionKit.MAX_PULSE_LEVEL:
		lists[ExpeditionKit.Category.TOOLS].add_child(_ui.label("Starter pulse fully upgraded.", 14, ShellUI.MINT))
	tabs.current_tab = _workshop_tab
	tabs.tab_changed.connect(func(tab: int) -> void: _workshop_tab = tab)
	return tabs


func _recipe_row(recipe: int) -> HBoxContainer:
	var data: Dictionary = ExpeditionKit.RECIPES[recipe]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	details.add_child(_ui.label(data.name, 16))
	details.add_child(_ui.label(data.benefit, 13, ShellUI.MUTED))
	row.add_child(details)
	var action := "Craft"
	if recipe == ExpeditionKit.Recipe.REPAIR:
		action = "Repair"
	elif data.category == ExpeditionKit.Category.TOOLS:
		action = "Upgrade"
	var entry := action if game.sandbox_enabled else "%s  ·  %s" % [action, ExpeditionKit.cost_text(recipe)]
	if recipe == ExpeditionKit.Recipe.LINER and game.kit.liner:
		entry = "Equipped"
	var craft_button := _ui.button(entry, _craft.bind(recipe))
	craft_button.disabled = not game.kit.available(recipe, game.inventory, game.survival, game.sandbox_enabled)
	row.add_child(craft_button)
	return row


func _craft(recipe: int) -> void:
	if game.craft(recipe):
		show_workshop()
		match recipe:
			ExpeditionKit.Recipe.WORKBENCH:
				_ui.show_feedback("Select the workbench in your hotbar, then right-click to deploy it.")
			ExpeditionKit.Recipe.SMELT:
				_ui.show_feedback("Smelted %d alloy." % ExpeditionKit.ALLOY_YIELD)
			ExpeditionKit.Recipe.REPAIR:
				_ui.show_feedback("Suit integrity restored.")
			_:
				_ui.show_feedback("Crafted %s" % ExpeditionKit.RECIPES[recipe].name)
	else:
		_ui.show_feedback("The recipe is unavailable.")


func show_inventory() -> void:
	if game == null:
		return
	screen = Screen.INVENTORY
	get_tree().paused = true
	_inventory_slots.clear()
	_moving_slot = -1
	var body := _ui.open_panel("Inventory", "Drag stacks or select two slots to move them.")
	body.add_child(_ui.label("Hotbar", 15, ShellUI.MINT))
	body.add_child(_inventory_row(0, ExpeditionInventory.HOTBAR_SLOTS))
	var suit_title := "Suit storage" if game.survival.suit_equipped else "Suit storage · Suit off"
	body.add_child(_ui.label(suit_title, 15, ShellUI.MINT))
	body.add_child(_inventory_row(ExpeditionInventory.HOTBAR_SLOTS, ExpeditionInventory.SLOT_COUNT))
	_refresh_inventory()
	var back := _ui.button("Back to expedition", resume_expedition, true)
	body.add_child(back)
	_ui.finish_panel(_inventory_slots[game.selected])


func _inventory_row(first: int, end: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for index in range(first, end):
		var slot := InventorySlot.new()
		slot.slot_index = index
		slot.pressed.connect(_select_inventory_slot.bind(index))
		slot.moved_from.connect(_move_inventory.bind(index))
		_inventory_slots.append(slot)
		row.add_child(slot)
	return row


func _select_inventory_slot(index: int) -> void:
	if _moving_slot == index:
		_moving_slot = -1
	elif _moving_slot >= 0:
		_move_inventory(_moving_slot, index)
		return
	elif game.inventory.item_at(index) != BlockWorld.Block.EMPTY:
		_moving_slot = index
	_refresh_inventory()


func _move_inventory(source: int, target: int) -> void:
	if not game.move_inventory(source, target):
		_ui.show_feedback("These stacks cannot be moved together.")
	_moving_slot = -1
	_refresh_inventory()


func _refresh_inventory() -> void:
	for index in _inventory_slots.size():
		var locked := index >= ExpeditionInventory.HOTBAR_SLOTS and not game.survival.suit_equipped
		_inventory_slots[index].show_stack(game.inventory.item_at(index), game.inventory.quantity_at(index),
				index == _moving_slot, locked)


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


func _refresh_chart(column: SpinBox, row: SpinBox, preview: Label, detail: Label) -> void:
	var destination := PlanetProfile.new(Vector2i(int(column.value), int(row.value)), game.universe_seed)
	preview.text = destination.chart_title()
	var air := "Breathable" if destination.details.breathable else "Suit oxygen required"
	var front := destination.weather_at(game.survival.elapsed)
	var pressure := "%d kPa" % destination.pressure_kpa
	if destination.pressure_kpa > SurvivalState.SUIT_PRESSURE_LIMIT:
		pressure += " · Suit strain"
	detail.text = "%s  ·  %s  ·  %s\n%s  ·  %d °C\n%.2f g  ·  %d km radius  ·  %s\n%.2f Earth masses  ·  %.2f× Earth density\nForage  %s and %s  ·  %s" % [
		destination.details.biome, air, "Clear now" if front.is_empty() else front, pressure,
		roundi(destination.temperature_at(game.survival.elapsed, front)),
		destination.gravity_g, roundi(destination.radius_earth * PlanetProfile.EARTH_RADIUS_KM),
		PlanetProfile.ROCK_COMPOSITION[destination.rock_type], destination.mass_earth, destination.density_earth,
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
