extends Node

const GAME := preload("res://game/main.tscn")
const APP := preload("res://game/app.tscn")
const B := BlockWorld.Block
const I := preload("res://game/expedition_inventory.gd")
const TEST_RECYCLER := Vector2i(8, BlockWorld.PAD_ROW)
const TEST_GENERATOR := Vector2i(9, BlockWorld.PAD_ROW)
const TEST_BATTERY := Vector2i(7, BlockWorld.PAD_ROW)
const TEST_ROOF := Vector2i(8, BlockWorld.PAD_ROW - 4)
const LINKED_RECYCLER := Vector2i(18, BlockWorld.PAD_ROW)
const LINKED_GENERATOR := Vector2i(24, BlockWorld.PAD_ROW)
const LINKED_PANEL := Vector2i(24, BlockWorld.PAD_ROW - 6)
const TEST_SAND_PLACEMENT := Vector2i(3, BlockWorld.PAD_ROW - 1)

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	if FileAccess.file_exists(ExpeditionSave.SLOT):
		_expect(false, "Smoke test requires an empty test profile")
		get_tree().quit(1)
		return

	await _check_menu()
	_check_previous_format()
	_check_journal()
	_write_legacy_save()
	var game := _open_game()
	await _frames(16)
	_expect(game.explorer.is_on_floor(), "Explorer settles on the protected pad")
	_expect(game.terrain.block_at(Vector2i(-4, BlockWorld.PAD_ROW)) == BlockWorld.Block.STONE,
			"First-playtest saves keep their existing Cinder Reach edits")
	_expect(game.survival.oxygen == 100.0 and game.inventory.count(I.RATION) == 2, "First-playtest saves gain survival defaults")
	_check_inventory()
	_check_gravity()
	_check_survival_model()
	_check_habitat_power()
	_check_vacuum_grace()
	_check_body_temperature()
	_check_suit()
	_check_jetpack()
	await _check_weather(game)
	var field_bench := Vector2i(7, BlockWorld.PAD_ROW - 1)
	_check_field_crafting(game, field_bench)
	var start := game.explorer.position
	Input.action_press("move_right")
	await _frames(12)
	Input.action_release("move_right")
	_expect(game.explorer.position.x > start.x + 10.0, "Movement uses the actual physics controller")
	Input.action_press("jump")
	await _frames(8)
	Input.action_release("jump")
	_expect(game.explorer.position.y < start.y - 10.0, "Jump rises from the surface")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)

	var food := game.inventory.count(I.RATION)
	game.explorer.position.x = -80.0
	_expect(not game.gather_nearby(), "Forage beyond starter pulse range is out of reach")
	game.explorer.position.x = -100.0
	_expect(game.gather_nearby() and game.inventory.count(I.RATION) == food + 1, "Planet forage replenishes carried food")
	_expect(game.surface.harvested.has(-6), "Harvest marks the original plant column")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)

	var surface_block := Vector2i(2, BlockWorld.PAD_ROW)
	var above_surface := surface_block + Vector2i.UP
	var soil := game.inventory.count(B.SOIL)
	_expect(not game.begin_mining(Vector2i(0, BlockWorld.PAD_ROW)), "Beacon pad is protected")
	_expect(not game.place(BlockWorld.cell_at(game.explorer.position)), "Placement avoids the explorer")
	_expect(not game.begin_mining(surface_block), "Mining cannot reach a tile beyond the starter pulse radius")
	_expect(not game.place(Vector2i(3, BlockWorld.PAD_ROW - 1)), "Placement has the same short range")
	game.explorer.position.x = 35.0
	_expect(game.begin_mining(surface_block), "Nearby grass can be targeted")
	_expect(not game.advance_mining(0.18, surface_block, true) and game.inventory.count(B.SOIL) == soil,
			"Mining for less than the hardness leaves the block and inventory unchanged")
	_expect(not game.advance_mining(1.0, surface_block, false), "Releasing the button cancels mining")
	_expect(game.begin_mining(surface_block) and not game.advance_mining(0.18, surface_block, true),
			"Returning to a cancelled block starts from zero")
	_expect(game.advance_mining(0.25, surface_block, true) and game.inventory.count(B.SOIL) == soil + 1,
			"A completed hold breaks the block and pays out soil once")
	_expect(not game.advance_mining(4.0, surface_block, true) and not game.begin_mining(surface_block),
			"Continued holding cannot mine the empty cell twice")
	_expect(game.place(above_surface) and game.inventory.count(B.SOIL) == soil, "Placement consumes one block")
	_expect(not game.place(Vector2i(40, 7)), "Placement respects reach")
	_check_sand(game)

	game.terrain.stream_around(Vector2(2700.0, 350.0))
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.EMPTY, "Distant chunks unload")
	game.terrain.stream_around(game.explorer.position)
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL, "A streamed chunk restores its edits")
	_expect(BlockWorld.chunk_at(Vector2i(-1, -33)) == Vector2i(-1, -2), "Negative cells use the correct chunk")

	_expect(game.begin_travel(), "Surface beacon starts travel")
	_expect(not game.begin_travel(), "An active transfer cannot be queued twice")
	await _frames(90)
	_expect(game.region == BlockWorld.Region.STATION, "Travel reaches the orbital station")
	_expect(is_equal_approx(game.explorer.gravity, BlockWorld.STATION_GRAVITY_PX), "Relay Nine uses artificial gravity")
	game.selected = 2
	await _check_station(game)
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(6)
	var station_block := Vector2i(-1, BlockWorld.PAD_ROW - 2)
	var alloy := game.inventory.count(B.ALLOY)
	_expect(game.place(station_block), "The orbital station accepts building")
	_expect(game.begin_travel(), "The station beacon starts the return trip")
	await _frames(90)
	_expect(game.region == BlockWorld.Region.SURFACE, "The return trip reaches the surface")
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL, "Surface edits outlast a trip")
	game.survival.suit_integrity = 47.5
	_expect(game.toggle_suit(), "The explorer can remove the suit near a beacon")
	game.survival.body_temperature = 38.7
	_expect(game.save_expedition(), "The expedition saves")
	game.queue_free()
	await get_tree().process_frame

	game = _open_game()
	await _frames(5)
	_expect(game.region == BlockWorld.Region.SURFACE, "Reopening restores the last region")
	_expect(game.inventory.count(B.ALLOY) == alloy - 1 and game.selected == 2, "Reopening restores inventory and selection")
	_expect(game.kit.pulse_level == 3 and game.kit.liner and game.inventory.count(I.CANISTER) == 1, "Reopening restores crafted equipment")
	_expect(game.terrain.block_at(field_bench) == BlockWorld.Block.WORKBENCH, "A deployed workbench persists through travel and saves")
	_expect(not game.survival.suit_equipped and is_equal_approx(game.survival.suit_integrity, 47.5),
			"Reopening restores the suit's integrity and whether it is worn")
	_expect(game.toggle_suit() and game.survival.suit_active(), "The explorer can put the damaged suit back on")
	var temperature := game.find_child("BodyTemperature", true, false) as Label
	_expect(is_equal_approx(game.survival.body_temperature, 38.7) and temperature.text == "38.7 °C · Recovering",
			"The saved body temperature and recovery reading return at the beacon")
	_expect(game.terrain.block_at(surface_block) == BlockWorld.Block.EMPTY, "Reopening restores the mined block")
	_expect(game.terrain.block_at(TEST_SAND_PLACEMENT) == B.SAND, "Placed sand persists through travel and reload")
	_expect(game.station.edits.get(station_block) == BlockWorld.Block.ALLOY,
			"Reopening restores the inactive station edits")
	_expect(game.surface.harvested.has(-6), "Harvest persists after reopening")
	_expect(game.begin_travel(), "The station can be reached again")
	await _frames(90)
	game.explorer.position.x += 115.0
	game.survival.oxygen = 65.0
	await _frames(32)
	_expect(game.survival.oxygen > 65.0, "The sealed cabin refills oxygen away from the beacon")
	game.explorer.position.x = BlockWorld.TILE_SIZE * 14.5
	var before := game.survival.oxygen
	var body_before := game.survival.body_temperature
	await _frames(32)
	_expect(game.survival.oxygen < before and game.survival.body_temperature < body_before,
			"The EVA deck uses suit oxygen and starts cooling the explorer")
	_expect(game.toggle_suit(), "The suit can be removed on the EVA deck")
	var health := game.survival.health
	var tank := game.survival.oxygen
	await _frames(32)
	var air_warning := game.find_child("LocalAir", true, false) as Label
	_expect(game.survival.health == health and is_equal_approx(game.survival.oxygen, tank) and air_warning.text.contains("grace"),
			"The EVA deck keeps health steady and shows a countdown when the suit comes off")
	await _frames(520)
	_expect(game.survival.health < health and game.survival.health > health - 5.0 and air_warning.text.contains("Losing health"),
			"Prolonged exposure on the EVA deck drains health slowly after the countdown")
	_expect(game.toggle_suit(), "The suit can be put on again on the EVA deck")
	var vacuum_reserve := game.find_child("VacuumReserve", true, false) as Label
	_expect(game.survival.vacuum_exposure == SurvivalState.VACUUM_GRACE and vacuum_reserve.visible
			and vacuum_reserve.text.contains("+1 in 5 s"), "Suit oxygen pauses harm and shows the reserve recharge")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	_expect(game.land_at(Vector2i.RIGHT), "The star chart accepts a different sector at the beacon")
	await _frames(90)
	_expect(game.sector == Vector2i.RIGHT and game.region == BlockWorld.Region.SURFACE, "Chart travel reaches a generated planet")
	_expect(is_equal_approx(game.explorer.gravity, game.surface.planet.gravity_g * PlanetProfile.EARTH_GRAVITY_PX),
			"The destination's derived surface gravity drives the physics controller")
	_expect(not game.surface.planet.details.breathable, "The first destination requires suit oxygen")
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.EMPTY, "Edits belong to the planet where they were made")
	var foreign_block := Vector2i(1, BlockWorld.PAD_ROW - 2)
	_expect(game.place(foreign_block), "You can build on another planet")
	var saved_room := _check_habitat(game)
	_expect(game.save_expedition(), "The expedition saves a destination and its changes")
	game.queue_free()
	await get_tree().process_frame

	game = _open_game()
	await _frames(6)
	_expect(game.sector == Vector2i.RIGHT and game.terrain.block_at(foreign_block) == BlockWorld.Block.ALLOY,
			"Reopening restores a generated destination and its edits")
	var restored_habitat: HabitatRoom = game._habitats.get(TEST_RECYCLER)
	if restored_habitat != null:
		_expect(is_equal_approx(restored_habitat.air, saved_room.get("air", -1.0)) and game.breathable_here(),
				"A leaking habitat reloads with its remaining breathable air")
		_expect(is_equal_approx(restored_habitat.fuel_seconds, saved_room.get("fuel_seconds", -1.0))
				and is_equal_approx(restored_habitat.charge, saved_room.get("charge", -1.0))
				and game.terrain.block_at(TEST_GENERATOR) == B.GENERATOR and game.terrain.block_at(TEST_BATTERY) == B.BATTERY,
				"Reloading keeps installed power equipment, fuel, and battery charge")
		game._update_survival_display(14.0)
		_expect(not game.breathable_here(), "A habitat eventually loses enough air to require a suit")
		game.terrain.set_block(TEST_ROOF, B.GLASS)
		_expect(not game.breathable_here(), "A habitat patch begins a gradual refill")
		game._update_survival_display(5.0)
		_expect(game.breathable_here(), "Pressure glass restores the seal and the recycler supplies air")
	else:
		_expect(false, "A commissioned habitat is restored on reload")
	_check_linked_habitats(game)
	_expect(game.save_expedition(), "Both rooms of a powered habitat can be saved")
	game.queue_free()
	await get_tree().process_frame
	game = _open_game()
	await _frames(5)
	var reloaded_room: HabitatRoom = game._habitat_at_floor(LINKED_GENERATOR)
	var reloaded_network := game._habitat_networks.members(reloaded_room)
	_expect(reloaded_room != null and reloaded_network.size() == 2 and reloaded_room.fuel_seconds > 0.0,
			"Reloading rebuilds the shared circuit and retains the generator's fuel")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	_expect(game.begin_travel(), "The second planet connects back to Relay Nine")
	await _frames(90)
	await _check_orbital_descent(game)
	_expect(game.terrain.block_at(foreign_block) == B.ALLOY and game._habitats.has(TEST_RECYCLER),
			"Falling to a planet restores its buildings and habitat records")
	_check_habitat_solar(game)
	_expect(game.save_expedition(), "Solar equipment can be saved with the habitat")
	game.queue_free()
	await get_tree().process_frame
	game = _open_game()
	await _frames(5)
	reloaded_room = game._habitat_at_floor(LINKED_GENERATOR)
	_expect(game.terrain.block_at(LINKED_PANEL) == B.SOLAR_PANEL
			and game.terrain.block_at(LINKED_PANEL + Vector2i.DOWN) == B.SOLAR_MAST
			and reloaded_room != null and is_equal_approx(reloaded_room.solar_output, HabitatNetworks.PANEL_OUTPUT),
			"Reloading restores the solar blocks and derives their power from the saved terrain")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	_expect(game.begin_travel(), "The explorer can launch again after falling to the surface")
	await _frames(90)
	_expect(game.land_at(Vector2i.ZERO), "You can chart a return trip to the first planet")
	await _frames(90)
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL and game.surface.harvested.has(-6),
			"Returning to the original sector restores terrain and forage changes")
	_expect(game._habitats.is_empty(), "Habitat records are scoped to the sector where the room was built")
	game = await _check_far_terrain(game)
	_expect(not FileAccess.file_exists("user://logs/godot.log"), "Development file logging is disabled")
	game.queue_free()
	await get_tree().process_frame

	var damaged := FileAccess.open(ExpeditionSave.SLOT, FileAccess.WRITE)
	damaged.store_string("damaged save")
	damaged.close()
	game = _open_game()
	await _frames(4)
	_expect(not game.save_expedition(), "An invalid save cannot be overwritten")
	_expect(FileAccess.get_file_as_string(ExpeditionSave.SLOT) == "damaged save", "Invalid save contents are preserved")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _failures else 0)


func _check_menu() -> void:
	get_window().size = get_window().content_scale_size
	var app: MomoyoApp = APP.instantiate()
	add_child(app)
	await _frames(4)
	_expect(app.screen == MomoyoApp.Screen.TITLE and app.game == null, "Startup opens the title menu")
	app.show_settings(MomoyoApp.Screen.TITLE)
	var fps := app.find_child("FrameLimit", true, false) as OptionButton
	var sync := app.find_child("VSync", true, false) as CheckButton
	var renderer := app.find_child("Renderer", true, false) as OptionButton
	var volume := app.find_child("MasterVolume", true, false) as HSlider
	var apply := app.find_child("ApplySettings", true, false) as Button
	fps.select(GamePreferences.FPS_OPTIONS.find(120))
	sync.button_pressed = false
	renderer.select(1)
	volume.value = 25
	apply.pressed.emit()
	var saved := GamePreferences.new()
	saved.load_settings()
	_expect(saved.fps_limit == 120 and Engine.max_fps == 120, "The applied frame cap is active and persisted")
	_expect(not saved.vsync and saved.renderer == "mobile", "VSync and renderer choices persist")
	_expect(is_equal_approx(saved.volume, 0.25) and is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.25)),
			"Master volume applies and persists")
	_expect(FileAccess.get_file_as_string(GamePreferences.PATH).contains('renderer="mobile"'),
			"Renderer selection is readable by the native startup")
	app.start_expedition()
	await _frames(5)
	_expect(app.screen == MomoyoApp.Screen.EXPLORING, "The main menu starts an expedition")
	var first_seed := app.game.universe_seed
	var first_sector := app.game.sector
	var first_title := app.game.surface.planet.title()
	_expect(first_seed != 0 and first_title != "Cinder Reach", "A new expedition starts on a seeded planet with a generated name")
	_expect(ExpeditionSave.new().read().get("universe_seed") == first_seed, "The starting seed is saved immediately")
	await _check_window_layout(app)
	app.show_workshop()
	_expect(app.screen == MomoyoApp.Screen.WORKSHOP and get_tree().paused,
			"Field crafting can open at the landing beacon")
	_expect(app.game.workbench_name().is_empty() and not app.game.craft(ExpeditionKit.Recipe.CANISTER),
			"The landing beacon provides no workbench")
	_expect(app.find_child("RecipeCategories", true, false) == null, "Field crafting shows its only recipe directly")
	var bench := Vector2i(2, BlockWorld.PAD_ROW - 1)
	app.game.terrain.set_block(bench, B.WORKBENCH)
	app.show_workshop()
	var tabs := app.find_child("RecipeCategories", true, false) as TabContainer
	_expect(tabs != null and tabs.get_tab_count() == ExpeditionKit.CATEGORY_NAMES.size(), "The workbench shows every recipe category")
	if tabs != null:
		tabs.current_tab = ExpeditionKit.Category.LIFE_SUPPORT
		_expect(tabs.get_current_tab_control().get_child_count() == 2, "Life support groups airlocks and recyclers")
		tabs.current_tab = ExpeditionKit.Category.POWER
		_expect(tabs.get_current_tab_control().get_child_count() == 5, "Power groups fuel, batteries, panels, and masts")
		tabs.current_tab = ExpeditionKit.Category.TOOLS
		_expect(tabs.get_current_tab_control().name == "Tools", "Choosing Tools opens the pulse upgrades")
		app._craft(ExpeditionKit.Recipe.PULSE_1)
		var rebuilt := app.find_child("RecipeCategories", true, false) as TabContainer
		_expect(app.game.kit.pulse_level == 1 and rebuilt != null and rebuilt.current_tab == ExpeditionKit.Category.TOOLS,
				"Crafting an upgrade keeps its category open")
	app.game.terrain.set_block(bench, B.EMPTY)
	app.show_inventory()
	_expect(app.screen == MomoyoApp.Screen.INVENTORY and app._inventory_slots.size() == 14,
			"The inventory menu shows nine hotbar slots and five suit slots")
	app._select_inventory_slot(0)
	app._select_inventory_slot(8)
	_expect(app.game.inventory.item_at(8) == B.SOIL and app.game.inventory.item_at(0) == B.EMPTY,
			"The inventory menu moves stacks into the ninth hotbar slot")
	app.resume_expedition()
	await _check_sandbox(app)
	app.game.survival.hunger = 88.0
	app.show_pause()
	await _frames(30)
	_expect(get_tree().paused and app.game.survival.hunger == 88.0, "The pause menu stops survival time")
	app.return_to_menu()
	await _frames(3)
	_expect(app.game == null and app.screen == MomoyoApp.Screen.TITLE and not get_tree().paused, "Save and return reopens the main menu")
	_expect(FileAccess.file_exists(ExpeditionSave.SLOT), "Returning to the main menu saves the expedition")
	app.start_expedition()
	await _frames(5)
	_expect(app.game.universe_seed == first_seed and app.game.sector == first_sector and app.game.surface.planet.title() == first_title,
			"Continuing an expedition restores the same generated starting planet")
	_expect(app.game.sandbox_enabled, "Sandbox mode persists with its expedition")
	app.show_sandbox(MomoyoApp.Screen.EXPLORING)
	var toggle := app.find_child("SandboxToggle", true, false) as Button
	toggle.pressed.emit()
	_expect(not app.game.sandbox_enabled and not app.game.select_sandbox_material(B.GENERATOR), "Sandbox mode can be turned off again")
	app.return_to_menu()
	await _frames(3)
	app.start_new_expedition()
	await _frames(3)
	_expect(app.game.universe_seed != first_seed and ExpeditionSave.slots().size() == 2,
			"A second expedition starts a new universe and keeps the previous slot")
	_expect(not app.game.sandbox_enabled, "New expeditions default to ordinary material costs")
	_expect(ExpeditionSave.new().read().get("universe_seed") == first_seed, "The original expedition is preserved")
	app.queue_free()
	await get_tree().process_frame


func _check_sandbox(app: MomoyoApp) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(3)
	_expect(app.screen == MomoyoApp.Screen.SANDBOX and not app.game.sandbox_enabled,
			"B opens the sandbox menu without enabling free materials")
	var toggle := app.find_child("SandboxToggle", true, false) as Button
	if toggle == null:
		_expect(false, "Sandbox mode has an enable switch")
		return
	toggle.pressed.emit()
	var palette_entry := app.find_child("SandboxBlock%d" % B.GLASS, true, false) as Button
	_expect(app.game.sandbox_enabled and palette_entry != null, "Enabling sandbox mode reveals the material palette")
	if palette_entry == null:
		return
	palette_entry.pressed.emit()
	var game := app.game
	var counts := game.inventory.snapshot()
	var left := Vector2i(-1, BlockWorld.PAD_ROW - 2)
	var right := Vector2i(1, BlockWorld.PAD_ROW - 2)
	_expect(app.screen == MomoyoApp.Screen.EXPLORING and game.use_or_place(left) and game.use_or_place(right)
			and game.terrain.block_at(left) == B.GLASS and game.terrain.block_at(right) == B.GLASS
			and game.inventory.snapshot() == counts, "A palette block places repeatedly without occupying or spending an inventory stack")
	_expect(not game.place(Vector2i(40, BlockWorld.PAD_ROW - 2)), "Sandbox mode preserves building reach")
	var soil := game.inventory.count(B.SOIL)
	var stone := game.inventory.count(B.STONE)
	_expect(game.craft(ExpeditionKit.Recipe.WORKBENCH) and game.inventory.count(B.WORKBENCH) == 1
			and game.inventory.count(B.SOIL) == soil and game.inventory.count(B.STONE) == stone,
			"Sandbox crafting preserves the carried ingredients")


func _check_window_layout(app: MomoyoApp) -> void:
	var window := get_window()
	var initial_size := window.size
	var titlebar := app.find_child("TitleBar", true, false) as PanelContainer
	var close := titlebar.get_child(0).get_child(-1) as Button
	var grip := app.find_child("ResizeGrip", true, false) as Control
	var air_readout := app.game.find_child("LocalAir", true, false) as Label
	var initial_title := _window_pixel_rect(titlebar)
	var initial_close := _window_pixel_rect(close)
	var initial_grip := _window_pixel_rect(grip)
	var distant_column := -38
	var edge := Vector2i(distant_column, app.game.surface.surface_row(distant_column))
	_expect(app.game.terrain.block_at(edge) == B.EMPTY, "The normal view keeps its original chunk budget")
	window.size = Vector2i(1920, 1080)
	await _frames(5)
	var game_scale := Vector2.ONE * (1920.0 / initial_size.x)
	_expect(air_readout.get_viewport_transform().get_scale().is_equal_approx(game_scale)
			and app.game.explorer.get_viewport_transform().get_scale().is_equal_approx(game_scale),
			"The game world and HUD scale up together on a 1080p display")
	_expect(window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED
			and window.get_visible_rect().size.is_equal_approx(Vector2(initial_size)),
			"The scaled game fills a native-resolution window")
	var window_growth := Vector2(window.size - initial_size)
	var title_rect := _window_pixel_rect(titlebar)
	var close_rect := _window_pixel_rect(close)
	var grip_rect := _window_pixel_rect(grip)
	_expect(title_rect.is_equal_approx(initial_title.grow_side(SIDE_RIGHT, window_growth.x)),
			"The title bar retains its physical height (%s to %s)" % [initial_title, title_rect])
	_expect(close_rect.is_equal_approx(Rect2(initial_close.position + Vector2(window_growth.x, 0), initial_close.size)),
			"Window buttons retain their size and right alignment (%s to %s)" % [initial_close, close_rect])
	_expect(grip_rect.is_equal_approx(Rect2(initial_grip.position + window_growth, initial_grip.size)),
			"The resize grip follows the physical corner (%s to %s)" % [initial_grip, grip_rect])
	window.size = Vector2i(2560, 1080)
	await _frames(5)
	_expect(window.get_stretch_transform().get_scale().is_equal_approx(game_scale)
			and app.game.terrain.block_at(edge) == B.GRASS, "Ultrawide windows show extra terrain instead of stretching tiles")
	window.size = Vector2i(640, 360)
	await _frames(4)
	_expect(window.get_visible_rect().size.is_equal_approx(Vector2(window.content_scale_size)) and window.content_scale_factor < 1.0,
			"Small window layout mismatch (%s, canvas %s, scale %.3f)" % [
				window.size, window.get_visible_rect().size, window.content_scale_factor,
			])
	window.size = initial_size
	await _frames(4)
	_expect(is_equal_approx(window.content_scale_factor, 1.0) and _window_pixel_rect(grip).is_equal_approx(initial_grip)
			and app.game.terrain.block_at(edge) == B.EMPTY,
			"Restored window did not return to native scale and chunk budget (%s, scale %.3f, tile %d)" % [
				initial_size, window.content_scale_factor, app.game.terrain.block_at(edge),
			])


func _window_pixel_rect(control: Control) -> Rect2:
	return control.get_viewport_transform() * control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


func _check_sand(game: MomoyoGame) -> void:
	var deposit := TEST_SAND_PLACEMENT + Vector2i.DOWN
	game.terrain.set_block(deposit, B.SAND)
	var previous := game.explorer.position
	var previous_slot := game.selected
	game.explorer.position.x = game.terrain.scene_point(deposit + Vector2i.RIGHT, ActiveTerrain.CELL_CENTER).x
	var soil := game.inventory.count(B.SOIL)
	_expect(game.begin_mining(deposit) and game.advance_mining(0.5, deposit, true),
			"The starter pulse can break a nearby sand block")
	_expect(game.inventory.count(B.SAND) == 1 and game.inventory.count(B.SOIL) == soil
			and I.valid_snapshot(game.inventory.snapshot()), "Sand has its own valid inventory stack")
	for slot in I.HOTBAR_SLOTS:
		if game.inventory.item_at(slot) == B.SAND:
			game.selected = slot
			break
	_expect(game.place(TEST_SAND_PLACEMENT) and game.inventory.count(B.SAND) == 0
			and game.terrain.block_at(TEST_SAND_PLACEMENT) == B.SAND, "Placing mined sand consumes the sand stack")
	game.selected = previous_slot
	game.explorer.position = previous


func _check_inventory() -> void:
	var cargo := I.new()
	_expect(cargo.add(B.SOIL, I.HOTBAR_SLOTS * I.STACK_LIMIT, false), "Nine hotbar slots fit nine stacks")
	_expect(not cargo.add(B.STONE, 1, false) and cargo.add(B.STONE, 1), "Suit storage adds five more slots when worn")
	_expect(not cargo.move_slot(9, 0, false) and cargo.move_slot(9, 13, true), "Suit storage locks when the suit is off")
	_expect(cargo.add(B.SOIL, 4 * I.STACK_LIMIT) and cargo.add(B.STONE, 63), "All fourteen slots can hold full stacks")
	var full := cargo.snapshot()
	_expect(not cargo.exchange({B.SOIL: 1}, B.GLASS, 4, true, true) and cargo.snapshot() == full,
			"A full inventory rejects a craft without consuming ingredients")
	_expect(cargo.exchange({B.SOIL: I.STACK_LIMIT}, B.GLASS, 4, true, true) and cargo.count(B.GLASS) == 4,
			"Crafting can use a slot freed by its ingredients")


func _check_jetpack() -> void:
	var suit := SurvivalState.new()
	var burn := 0.0
	for _frame in 12:
		burn += suit.burn_jetpack(0.25, true, false)
	_expect(is_equal_approx(burn, 1.5) and suit.jetpack_fuel == 0.0, "An uninterrupted jetpack burst is limited to 1.5 seconds")
	_expect(suit.burn_jetpack(2.0, true, false) == 0.0 and suit.jetpack_fuel == 0.0,
			"An empty jetpack cannot recharge in flight")
	suit.burn_jetpack(0.75, false, true)
	_expect(suit.jetpack_fuel > 0.0 and suit.burn_jetpack(0.25, true, true) == 0.0,
			"The jetpack waits for a full recharge on solid ground")
	suit.burn_jetpack(1.0, false, true)
	_expect(suit.burn_jetpack(0.2, true, true) > 0.0 and suit.jetpack_cooldown > 0.0,
			"A charged jetpack can fire again")
	suit.suit_equipped = false
	_expect(suit.burn_jetpack(0.25, true, false) == 0.0, "The jetpack requires a working, worn suit")


func _check_gravity() -> void:
	_expect(is_equal_approx(PlanetProfile.surface_gravity(8.0, 2.0), 2.0),
			"Doubling radius at Earth density gives eight times the mass and twice the surface gravity")
	var relay_edge := Vector2(BlockWorld.STATION_PRESSURE_AREA.end.x, BlockWorld.PAD_ROW)
	var fading := BlockWorld.station_gravity_strength(relay_edge + Vector2(2, 0))
	_expect(BlockWorld.station_gravity_strength(relay_edge) == 1.0 and fading > 0.0 and fading < 1.0
			and BlockWorld.station_gravity_strength(relay_edge + Vector2(4, 0)) == 0.0,
			"Artificial gravity fades to zero at the edge of the Relay's field")
	var low := INF
	var high := 0.0
	for i in 36:
		var sector := Vector2i(i * 29 - 600, 7)
		var planet := PlanetProfile.new(sector, 53289)
		var same := PlanetProfile.new(sector, 53289)
		_expect(planet.gravity_g == same.gravity_g and is_equal_approx(planet.gravity_g, planet.density_earth * planet.radius_earth),
				"Seeded gravity is repeatable and follows the planet's radius and density")
		low = minf(low, planet.gravity_g)
		high = maxf(high, planet.gravity_g)
	_expect(low < 0.6 and high > 1.6, "Generated worlds have distinct surface gravity")


func _check_survival_model() -> void:
	var suit := SurvivalState.new()
	suit.advance(10.0, false, 0.0)
	_expect(is_equal_approx(suit.oxygen, 89.0) and suit.hunger < 100.0 and suit.thirst < 100.0,
			"Suit oxygen drains at the gentler vacuum rate")
	_expect(suit.eat() and suit.drink() and suit.hunger == 100.0 and suit.thirst == 100.0, "Food and drinking water restore vitals")
	suit.oxygen = 0
	suit.advance(1.0, false, PlanetProfile.storm_wear("Dust storm"))
	_expect(is_equal_approx(suit.health, 96.0), "Empty oxygen uses the lower health penalty")
	suit.advance(7.0, true, 0.0)
	_expect(suit.oxygen == 100.0, "Breathable air replenishes the suit")
	var exposed := SurvivalState.new()
	var protected := SurvivalState.new()
	exposed.advance(10.0, false, 0.0, 226, 56.0)
	protected.advance(10.0, false, 0.0, 226, 56.0, true)
	_expect(exposed.health < protected.health and protected.health < 100.0 and exposed.thirst < suit.thirst,
			"Dense air causes suit strain, heat increases thirst, and the liner reduces pressure damage")
	_expect(protected.suit_integrity > exposed.suit_integrity, "The liner reduces suit wear under high pressure")
	_expect(BlockWorld.mining_time(B.HULL) > BlockWorld.mining_time(B.STONE) and
			BlockWorld.mining_time(B.STONE, ExpeditionKit.MINING_POWER[3]) < BlockWorld.mining_time(B.STONE),
			"Block hardness differs and pulse upgrades speed up solid material")
	var origin := PlanetProfile.new(Vector2i.ZERO)
	_expect(origin.weather_at(12.0).is_empty() and origin.weather_at(55.0) == "Rain", "Planet weather moves through a cycle")
	var address := Vector2i(-2147483648, 2147483647)
	var first := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	var second := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	_expect(first.make_chunk(Vector2i.ZERO) == second.make_chunk(Vector2i.ZERO), "Distant addresses reproduce the same terrain")


func _check_vacuum_grace() -> void:
	var bare := SurvivalState.new()
	bare.suit_equipped = false
	bare.advance(7.75, false, 0.0, 0.0, bare.vacuum_exposure_temperature())
	_expect(bare.health == 100.0 and bare.vacuum_exposure == 7.75, "Unsuited vacuum exposure starts with a grace period")
	bare.advance(1.25, false, 0.0, 0.0, bare.vacuum_exposure_temperature())
	_expect(bare.health == 98.0, "Health drains at two points a second after eight seconds")
	var continued := SurvivalState.new()
	continued.restore(bare.snapshot())
	continued.advance(1.0, false, 0.0, 0.0)
	_expect(continued.health == 96.0, "Reloading preserves exposure time")
	continued.advance(4.0, true, 0.0)
	_expect(continued.vacuum_exposure == 8.0 and continued.vacuum_recovery == 4.0,
			"Finding air pauses health loss and waits five seconds before restoring grace")
	continued.advance(0.5, false, 0.0, 0.0)
	_expect(continued.health == 97.0 and continued.vacuum_recovery == 4.0,
			"Leaving shelter early resumes vacuum damage and keeps partial recovery")
	continued.restore(continued.snapshot())
	continued.advance(1.0, true, 0.0)
	_expect(continued.vacuum_exposure == 7.0 and continued.vacuum_recovery == 0.0,
			"One second of grace returns after five total seconds of breathing")
	var recovered_health := continued.health
	continued.advance(1.5, false, 0.0, 0.0)
	_expect(continued.vacuum_exposure == 8.0 and continued.health == recovered_health - 1.0,
			"Leaving shelter uses only the recovered grace before vacuum damage resumes")
	continued.advance(41.0, true, 0.0)
	_expect(continued.vacuum_exposure == 0.0 and continued.vacuum_recovery == 0.0,
			"Vacuum grace caps at eight seconds and stops recovering")

	var empty_tank := SurvivalState.new()
	empty_tank.oxygen = SurvivalState.VACUUM_DRAIN
	empty_tank.advance(8.5, false, 0.0, 0.0)
	_expect(empty_tank.health == 100.0 and is_equal_approx(empty_tank.vacuum_exposure, 7.5),
			"Oxygen from the suit delays the start of the grace period")
	empty_tank.advance(1.0, false, 0.0, 0.0)
	_expect(empty_tank.health == 99.0, "An empty tank gets the same gradual loss as an unequipped suit")
	empty_tank.advance(4.5, true, 0.0)
	empty_tank.oxygen = SurvivalState.VACUUM_DRAIN * 0.75
	empty_tank.advance(1.0, false, 0.0, 0.0)
	_expect(is_equal_approx(empty_tank.vacuum_exposure, 7.25) and is_equal_approx(empty_tank.vacuum_recovery, 0.25),
			"Only the oxygenated part of a suit's last breath recharges vacuum grace")


func _check_habitat_power() -> void:
	var world := BlockWorld.new(BlockWorld.Region.STATION)
	var area := Rect2i(48, -16, 16, 10)
	var recycler := Vector2i(area.position.x + 1, area.end.y)
	var generator := recycler + Vector2i.RIGHT
	var battery := generator + Vector2i.RIGHT
	for x in range(area.position.x, area.end.x):
		world.record_edit(Vector2i(x, area.position.y - 1), B.GLASS)
		world.record_edit(Vector2i(x, area.end.y), B.ALLOY)
	for y in range(area.position.y, area.end.y):
		world.record_edit(Vector2i(area.position.x - 1, y), B.ALLOY)
		world.record_edit(Vector2i(area.end.x, y), B.ALLOY)
	world.record_edit(recycler, B.RECYCLER)
	world.record_edit(generator, B.GENERATOR)
	world.record_edit(battery, B.BATTERY)
	_expect(HabitatRoom.survey(world, recycler) == area, "A sealed room can be sixteen tiles wide and ten tiles high")
	var room := HabitatRoom.new(area, 0.0)
	room.sync(world, recycler)
	room.refuel(generator)
	room.advance_to(10.0)
	_expect(is_equal_approx(room.air, 48.0) and room.charge == 10.0 and not room.breathable(),
			"A large habitat fills more slowly and charges its battery during generation")
	room.advance_to(95.0)
	_expect(room.fuel_seconds == 0.0 and room.charge == 85.0 and room.air == SurvivalState.CABIN_PRESSURE,
			"The battery seamlessly takes over after the fuel cell runs out")
	var away := HabitatRoom.from_snapshot(room.snapshot(), world, recycler, 240.0)
	_expect(away.charge == 0.0 and is_equal_approx(away.air, 56.0) and not away.breathable(),
			"An absent expedition uses the remaining battery and only then loses breathable air")
	room.refuel(generator)
	room.advance_to(105.0)
	world.record_edit(generator, B.EMPTY)
	room.sync(world, recycler)
	world.record_edit(generator, B.GENERATOR)
	room.sync(world, recycler)
	_expect(room.fuel_seconds == 0.0 and room.charge == 95.0, "Mining a running generator discards its fuel but retains the battery reserve")
	world.record_edit(battery, B.GLASS)
	room.sync(world, recycler)
	_expect(room.charge == HabitatRoom.RECYCLER_BUFFER, "Removing a battery drops charge above the remaining capacity")
	_check_solar_power(world, area, recycler, generator)


func _check_solar_power(world: BlockWorld, area: Rect2i, recycler: Vector2i, generator: Vector2i) -> void:
	var panel := Vector2i(generator.x, area.position.y - 2)
	var shade := panel + Vector2i.UP
	world.record_edit(panel, B.SOLAR_PANEL)
	var room := HabitatRoom.new(area, 0.0)
	room.sync(world, recycler)
	var power := HabitatNetworks.new()
	power.rebuild(world, [room])
	power.advance_to(20.0)
	_expect(room.breathable() and is_equal_approx(room.charge, 4.0),
			"An exposed panel supplies the recycler and banks surplus sunlight")
	room.refuel(generator)
	power.advance_to(25.0)
	_expect(room.fuel_seconds == HabitatRoom.FUEL_DURATION, "An exposed panel lets a filled generator idle")
	world.record_edit(shade, B.GLASS)
	power.refresh_solar(world)
	_expect(room.solar_output > 0.54 and room.solar_output < HabitatNetworks.PANEL_OUTPUT,
			"Pressure glass passes some light and reduces the solar yield")
	world.record_edit(shade, B.ALLOY)
	power.refresh_solar(world)
	_expect(is_equal_approx(room.solar_output, 0.54), "An opaque overhang leaves only the side light")
	power.advance_to(35.0)
	_expect(is_equal_approx(room.fuel_seconds, 85.4) and is_equal_approx(room.charge, 9.6),
			"Dim solar covers part of the recycler load and extends the generator fuel")

	var resumed := HabitatRoom.from_snapshot(room.snapshot(), world, recycler, 35.0)
	var resumed_power := HabitatNetworks.new()
	resumed_power.rebuild(world, [resumed])
	resumed_power.advance_to(700.0)
	for second in range(36, 701):
		power.advance_to(float(second))
	_expect(resumed.fuel_seconds == 0.0 and resumed.charge == 0.0
			and is_equal_approx(resumed.air, 0.54 * SurvivalState.CABIN_PRESSURE)
			and is_equal_approx(resumed.air, room.air),
			"Catch-up matches incremental updates after fuel and battery reserves run out under dim solar")


func _check_habitat(game: MomoyoGame) -> Dictionary:
	var floor_y := BlockWorld.PAD_ROW
	for x in range(6, 10):
		game.terrain.set_block(Vector2i(x, floor_y), B.ALLOY)
		if x != TEST_ROOF.x:
			game.terrain.set_block(Vector2i(x, TEST_ROOF.y), B.GLASS)
	for y in range(floor_y - 3, floor_y):
		game.terrain.set_block(Vector2i(5, y), B.AIRLOCK if y >= floor_y - 2 else B.ALLOY)
		game.terrain.set_block(Vector2i(10, y), B.ALLOY)
	game.explorer.position = game.terrain.scene_point(TEST_RECYCLER, Vector2(0.5, -15.0 / BlockWorld.TILE_SIZE))
	game.explorer.velocity = Vector2.ZERO
	var bench := Vector2i(7, floor_y - 2)
	game.terrain.set_block(bench, B.WORKBENCH)
	game.inventory.add(B.ALLOY, 20)
	game.inventory.add(B.ORE, 9)
	_expect(game.craft(ExpeditionKit.Recipe.RECYCLER) and game.craft(ExpeditionKit.Recipe.GENERATOR)
			and game.craft(ExpeditionKit.Recipe.BATTERY) and game.craft(ExpeditionKit.Recipe.FUEL_CELL),
			"Workbenches craft a recycler, generator, battery, and fuel cells")
	game.terrain.set_block(bench, B.EMPTY)
	var equipment := {TEST_RECYCLER: B.RECYCLER, TEST_GENERATOR: B.GENERATOR, TEST_BATTERY: B.BATTERY}
	for cell: Vector2i in equipment:
		game.terrain.set_block(cell, B.EMPTY)
		_expect(_place_habitat_device(game, cell, equipment[cell]), "Crafted habitat equipment can be placed in the floor")
	var fuel := game.inventory.count(I.FUEL_CELL)
	_expect(fuel == 2 and not game.use_or_place(TEST_GENERATOR) and game.inventory.count(I.FUEL_CELL) == fuel
			and game._hud._status.text.contains("roof"),
			"An unsealed roof gives actionable feedback and leaves fuel in inventory")
	_expect(not game.interact(), "A recycler cannot start with a hole in the roof")
	game.terrain.set_block(TEST_ROOF, B.GLASS)
	game.terrain.set_block(TEST_RECYCLER, B.ALLOY)
	_expect(not game.use_or_place(TEST_GENERATOR) and game._hud._status.text.contains("recycler"),
			"A complete shell without a recycler identifies the missing equipment")
	game.terrain.set_block(TEST_RECYCLER, B.RECYCLER)
	var power := game.find_child("HabitatPower", true, false) as Label
	_expect(game.use_or_place(TEST_GENERATOR) and game._habitats.has(TEST_RECYCLER)
			and game.inventory.count(I.FUEL_CELL) == fuel - 1 and not game.breathable_here(),
			"Right-click commissions a valid habitat and starts its generator in one action")
	_expect(power.text.contains("90 s") and not game.use_or_place(TEST_GENERATOR) and game.inventory.count(I.FUEL_CELL) == fuel - 1,
			"The HUD shows the fuel timer and a running generator cannot waste another cell")
	game._update_survival_display(5.0)
	_expect(not game.breathable_here(), "A freshly sealed room requires time to fill with air")
	game._update_survival_display(5.0)
	_expect(game.breathable_here(), "A filled habitat supplies breathable air on a hostile planet")

	var interior_block := Vector2i(7, floor_y - 2)
	game.terrain.set_block(interior_block, B.ALLOY)
	var occupied_room: HabitatRoom = game._habitats.get(TEST_RECYCLER)
	_expect(occupied_room != null and occupied_room.sealed() and game.breathable_here(),
			"An interior block redirects air without opening the shell")
	game.terrain.set_block(interior_block, B.EMPTY)

	game.explorer.position = game.terrain.scene_point(Vector2i(6, floor_y - 1), ActiveTerrain.CELL_CENTER)
	_expect(game.interact() and not game.breathable_here(), "The airlock exits to the hostile atmosphere")
	var obstruction := Vector2i(6, floor_y - 2)
	game.terrain.set_block(obstruction, B.SOIL)
	_expect(not game.interact(), "An obstruction prevents cycling through the airlock")
	game.terrain.set_block(obstruction, B.EMPTY)
	_expect(game.interact() and game.breathable_here(), "Cycling into the habitat preserves its air")
	var room: HabitatRoom = game._habitats.get(TEST_RECYCLER)
	if room == null:
		_expect(false, "The commissioned room is registered")
		return {}
	var full := room.air
	var stored := room.charge
	game.terrain.set_block(TEST_ROOF, B.EMPTY)
	game._update_survival_display(1.0)
	_expect(room.air < full and game.breathable_here(), "A leaking habitat loses air gradually")
	_expect(is_equal_approx(room.charge, stored + HabitatRoom.GENERATOR_OUTPUT),
			"A generator keeps charging while a breach stops the recycler")
	return room.snapshot()


func _check_linked_habitats(game: MomoyoGame) -> void:
	var floor_y := BlockWorld.PAD_ROW
	var airlock := Vector2i(21, floor_y - 2)
	var leaking_roof := Vector2i(23, floor_y - 4)
	for x in range(17, 26):
		if x == airlock.x:
			continue
		game.terrain.set_block(Vector2i(x, floor_y), B.ALLOY)
		game.terrain.set_block(Vector2i(x, floor_y - 4), B.GLASS)
		for y in range(floor_y - 3, floor_y):
			game.terrain.set_block(Vector2i(x, y), B.EMPTY)
	for y in range(floor_y - 3, floor_y):
		game.terrain.set_block(Vector2i(16, y), B.ALLOY)
		game.terrain.set_block(Vector2i(26, y), B.ALLOY)
		game.terrain.set_block(Vector2i(21, y), B.AIRLOCK if y >= airlock.y else B.ALLOY)
	game.terrain.set_block(LINKED_RECYCLER, B.RECYCLER)
	game.terrain.set_block(LINKED_GENERATOR, B.GENERATOR)
	game.terrain.set_block(LINKED_GENERATOR + Vector2i.LEFT, B.BATTERY)
	game.explorer.position = game.terrain.scene_point(LINKED_GENERATOR, Vector2(0.5, -15.0 / BlockWorld.TILE_SIZE))
	game.explorer.velocity = Vector2.ZERO
	game.set_sandbox(true)
	var fuel := game.inventory.count(I.FUEL_CELL)
	_expect(game.use_or_place(LINKED_GENERATOR) and game.inventory.count(I.FUEL_CELL) == fuel,
			"A sandbox generator draws unlimited fuel and links to the recycler in the neighboring room")
	game.set_sandbox(false)
	var source: HabitatRoom = game._habitats.get(LINKED_RECYCLER)
	var annex := game._habitat_at_floor(LINKED_GENERATOR)
	if source == null or annex == null:
		_expect(false, "Commissioning discovers both airlock-linked rooms")
		return
	game._update_survival_display(12.0)
	_expect(source.breathable() and annex.breathable() and not annex.recycles_air() and source.charge > 0.0,
			"A generator and battery share power with a single recycler that supplies both rooms")
	game.explorer.position = game.terrain.scene_point(Vector2i(22, floor_y - 1), ActiveTerrain.CELL_CENTER)
	_expect(game.interact() and source.contains(game.terrain.world_cell(game.explorer.position)),
			"The shared wall airlock lets the explorer cross into the neighboring room")
	game.terrain.set_block(leaking_roof, B.EMPTY)
	game._update_survival_display(12.0)
	_expect(source.breathable() and not annex.breathable(), "A breach vents the damaged annex and leaves the adjoining chamber breathable")
	game.terrain.set_block(leaking_roof, B.GLASS)
	game._update_survival_display(6.0)
	_expect(annex.breathable(), "The annex refills automatically after repair")
	game.terrain.set_block(airlock, B.ALLOY)
	_expect(game._habitat_networks.members(annex).size() == 1 and game._habitat_networks.members(source).size() == 1,
			"Replacing one airlock panel with an airtight wall separates the power circuits")
	game.terrain.set_block(airlock, B.AIRLOCK)
	_expect(game._habitat_networks.members(annex).size() == 2, "Restoring both airlock panels reconnects the circuit")


func _check_habitat_solar(game: MomoyoGame) -> void:
	var annex := game._habitat_at_floor(LINKED_GENERATOR)
	if annex == null:
		return
	var mast := LINKED_PANEL + Vector2i.DOWN
	game.explorer.position = game.terrain.scene_point(mast + Vector2i.RIGHT, ActiveTerrain.CELL_CENTER)
	game.set_sandbox(true)
	_expect(game.select_sandbox_material(B.SOLAR_MAST) and game.use_or_place(mast), "The palette places a mast on a roof")
	_expect(game.select_sandbox_material(B.SOLAR_PANEL) and game.use_or_place(LINKED_PANEL), "The palette places a panel on the mast")
	game.set_sandbox(false)
	_expect(game.use_or_place(LINKED_PANEL) and game._hud._status.text.contains("100% light"),
			"Right-click reports the light at a reachable installed panel")
	game.terrain.set_block(mast, B.EMPTY)
	_expect(annex.solar_output == 0.0 and game.use_or_place(LINKED_PANEL)
			and game._hud._status.text.contains("Mount above"), "Removing the mast disconnects an otherwise sunny panel")
	game.terrain.set_block(mast, B.SOLAR_MAST)

	game.explorer.position = game.terrain.scene_point(LINKED_RECYCLER + Vector2i.UP, ActiveTerrain.CELL_CENTER)
	game._update_survival_display()
	var fuel := annex.fuel_seconds
	var power := game.find_child("HabitatPower", true, false) as Label
	game._update_survival_display(5.0)
	_expect(annex.fuel_seconds == fuel and power.text.contains("Solar 1.20"),
			"A separate room's panel supplies the linked recycler and the HUD shows the solar output")
	var shadow_row := LINKED_PANEL + Vector2i.UP
	for dx in range(-1, 2):
		game.terrain.set_block(shadow_row + Vector2i(dx, 0), B.ALLOY)
	game._update_survival_display(5.0)
	_expect(is_equal_approx(annex.fuel_seconds, fuel - 5.0) and power.text.contains("Solar 0.00"),
			"Building cover outside the room immediately restores full fuel burn")
	for dx in range(-1, 2):
		game.terrain.set_block(shadow_row + Vector2i(dx, 0), B.EMPTY)
	_expect(power.text.contains("Solar 1.20"), "Clearing the overhang restores sunlight")


func _place_habitat_device(game: MomoyoGame, cell: Vector2i, material: int) -> bool:
	for slot in I.SLOT_COUNT:
		if game.inventory.item_at(slot) != material:
			continue
		if slot < I.HOTBAR_SLOTS:
			game.selected = slot
		elif not game.move_inventory(slot, game.selected):
			return false
		return game.place(cell)
	return false


func _check_body_temperature() -> void:
	var hot := SurvivalState.new()
	var cold := SurvivalState.new()
	var storm := SurvivalState.new()
	hot.advance(5.0, true, 0.0, SurvivalState.CABIN_PRESSURE, 72.0)
	cold.advance(5.0, true, 0.0, SurvivalState.CABIN_PRESSURE, -45.0)
	storm.advance(5.0, true, PlanetProfile.storm_wear("Whiteout"), SurvivalState.CABIN_PRESSURE, -45.0)
	_expect(hot.body_temperature > 37.0 and cold.body_temperature < 37.0 and
			hot.health == 100.0 and cold.health == 100.0, "Brief exposure changes body temperature without damaging health")
	_expect(storm.body_temperature < cold.body_temperature, "Unshielded storms increase exposure")
	for _tick in 240:
		hot.advance(SurvivalState.TICK, true, 0.0, SurvivalState.CABIN_PRESSURE, 72.0)
		cold.advance(SurvivalState.TICK, true, 0.0, SurvivalState.CABIN_PRESSURE, -45.0)
	_expect(hot.body_temperature > SurvivalState.HEAT_STRESS_TEMPERATURE and hot.health < 100.0 and
			cold.body_temperature < SurvivalState.COLD_STRESS_TEMPERATURE and cold.health < 100.0,
			"Prolonged exposure to heat or cold damages health")
	var before := hot.body_temperature
	hot.advance(15.0, true, 0.0)
	_expect(hot.body_temperature < before and hot.body_temperature > 37.0,
			"Normal conditions recover body temperature gradually")
	cold.restore_after_rescue()
	_expect(cold.body_temperature == 37.0, "Rescue resets body temperature")
	var invalid := cold.snapshot()
	invalid["body_temperature"] = NAN
	_expect(not SurvivalState.valid_snapshot(invalid), "A non-finite saved body temperature is rejected")


func _check_suit() -> void:
	var sealed := SurvivalState.new()
	var worn := SurvivalState.new()
	worn.suit_integrity = 30.0
	sealed.advance(5.0, false, 0.0, 0)
	worn.advance(5.0, false, 0.0, 0)
	_expect(worn.oxygen < sealed.oxygen and worn.suit_integrity == 30.0, "A worn suit leaks air during EVA")

	var bare := SurvivalState.new()
	bare.suit_equipped = false
	bare.advance(5.0, true, 0.0)
	_expect(bare.health == 100.0 and not bare.suit_active(), "Mild, breathable air is safe without a suit")
	var ash := PlanetProfile.storm_wear("Ashfall")
	var storm := SurvivalState.new()
	storm.advance(5.0, true, ash, SurvivalState.CABIN_PRESSURE, 72.0)
	bare.advance(5.0, true, ash, SurvivalState.CABIN_PRESSURE, 72.0)
	_expect(storm.suit_integrity < 100.0 and bare.health < storm.health and bare.body_temperature > storm.body_temperature,
			"Ash wears out a suit and causes more heat and direct damage without protection")
	storm.suit_integrity = 0.5
	storm.advance(1.0, false, ash, 220)
	_expect(not storm.suit_active() and storm.health < 90.0, "A suit breach exposes the explorer to unsafe air and pressure")
	storm.restore_after_rescue()
	_expect(storm.suit_active() and storm.suit_integrity == SurvivalState.RESCUE_SUIT_INTEGRITY,
			"Rescue restores a minimally working suit")


func _check_field_crafting(game: MomoyoGame, bench: Vector2i) -> void:
	game.explorer.position = Vector2(150.0, BlockWorld.pad_position().y)
	game.explorer.velocity = Vector2.ZERO
	var soil := game.inventory.count(B.SOIL)
	var stone := game.inventory.count(B.STONE)
	var alloy := game.inventory.count(B.ALLOY)
	_expect(game.workbench_name().is_empty() and not game.craft(ExpeditionKit.Recipe.SMELT),
			"Advanced crafting requires a nearby bench")
	_expect(game.craft(ExpeditionKit.Recipe.WORKBENCH) and game.inventory.count(B.WORKBENCH) == 1 and
			game.inventory.count(B.SOIL) == soil - 2 and game.inventory.count(B.STONE) == stone - 4,
			"Field crafting produces a workbench from soil and stone")
	_expect(game.move_inventory(3, 8), "The crafted workbench can move to the ninth slot")
	game.selected = 8
	_expect(game.place(bench) and game.workbench_name() == "Field workbench" and game.inventory.count(B.WORKBENCH) == 0,
			"Slot nine deploys a functional workbench away from the landing beacon")

	var ore := bench + Vector2i.RIGHT
	game.terrain.set_block(ore, BlockWorld.Block.ORE)
	_expect(not game.begin_mining(ore), "The starter pulse cannot harvest ore beyond its range")
	game.kit.pulse_level = 1
	_expect(not game.begin_mining(ore), "A solid block stops an otherwise in-range pulse")
	_expect(game.begin_mining(bench) and game.advance_mining(1.1, bench, true) and game.inventory.count(B.WORKBENCH) == 1,
			"Mining recovers a deployed bench for reuse")
	_expect(game.move_inventory(3, 8), "The recovered bench can move back into its hotbar slot")
	_expect(game.save_expedition(false), "Carried workbenches and their selection can be saved")
	var state := ExpeditionSave.new().read()
	var slots := I.new()
	if state.has("inventory"):
		slots.restore(state.inventory)
	_expect(state.get("selected") == 8 and slots.item_at(8) == B.WORKBENCH, "Save restores a workbench in the ninth slot")
	for _shot in 2:
		_expect(game.begin_mining(ore) and game.advance_mining(2.0, ore, true), "The upgraded pulse reaches and collects ore")
		if game.inventory.count(B.ORE) < 2:
			game.terrain.set_block(ore, BlockWorld.Block.ORE)
	game.kit.pulse_level = 0
	_expect(game.place(bench), "Recovered workbenches can be redeployed")
	_expect(game.craft(ExpeditionKit.Recipe.SMELT) and game.inventory.count(B.ORE) == 0 and
			game.inventory.count(B.ALLOY) == alloy + ExpeditionKit.ALLOY_YIELD, "The field workbench smelts mined ore")
	game.survival.suit_integrity = 0.0
	_expect(game.craft(ExpeditionKit.Recipe.REPAIR) and game.survival.suit_active() and game.inventory.count(B.ALLOY) == alloy,
			"Smelted alloy repairs a breached suit at the field workbench")
	game.selected = 0
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO


func _check_station(game: MomoyoGame) -> void:
	_expect(game.cabin.breaches.is_empty(), "The refit begins with a sealed cabin")
	var wall := Vector2i(BlockWorld.STATION_CABIN.position.x - 1, BlockWorld.PAD_ROW - 1)
	game.explorer.position = game.terrain.scene_point(wall + Vector2i.RIGHT, ActiveTerrain.CELL_CENTER)
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)
	_expect(game.breathable_here(), "A player away from the beacon can breathe in the cabin")
	_expect(game.begin_mining(wall), "A hull block can be targeted up close")
	_expect(not game.advance_mining(1.0, wall, true), "The hull takes longer to break than grass")
	_expect(not game.advance_mining(3.0, wall + Vector2i.UP, true), "Switching targets cancels mining")
	_expect(game.begin_mining(wall) and game.advance_mining(2.6, wall, true), "Holding breaks a hull block at its hardness threshold")
	_expect(game.breathable_here() and game.cabin.pressure == 101.0 and game.cabin.breaches.has(wall),
			"A new hull breach leaves an initially breathable cabin")
	var start := game.explorer.position.x
	var objects := game.get_node("LooseObjects")
	var fragment := objects.get_child(0) as RigidBody2D
	var fragment_x := fragment.position.x
	await _frames(9)
	_expect(game.explorer.position.x < start and fragment.position.x < fragment_x, "Venting moves the explorer and loose debris toward the breach")
	_expect(game.cabin.pressure < 101.0 and game.cabin.pressure > 95.0, "A single breach loses air gradually")
	game.explorer.position = game.terrain.scene_point(wall + Vector2i.RIGHT, ActiveTerrain.CELL_CENTER)
	game.explorer.velocity = Vector2.ZERO
	game.cabin.advance(25.0)
	_expect(not game.breathable_here(), "Continued venting makes the cabin unbreathable")
	_expect(game.save_expedition(false) and is_equal_approx(float(ExpeditionSave.new().read().get("cabin_pressure", -1.0)), game.cabin.pressure),
			"Partially vented cabin pressure is persisted")
	_expect(game.place(wall) and game.cabin.breaches.is_empty() and not game.breathable_here(),
			"An alloy patch seals the breach before the air returns")
	game.cabin.advance(9.0)
	_expect(game.breathable_here(), "Life support gradually restores pressure after repair")
	game.terrain.set_block(wall, B.FRAME)
	_expect(game.cabin.breaches.has(wall), "Any terrain damage can open a breach, and frames are unsealed")
	game.cabin.advance(100.0)
	_expect(game.cabin.airflow_at(game.explorer.position, game.terrain.origin_cell) == Vector2.ZERO,
			"Airflow stops once the cabin has nearly emptied")
	game.terrain.set_block(wall, B.GLASS)
	_expect(game.cabin.breaches.is_empty(), "Pressure glass can close a hull breach")
	game.cabin.advance(15.0)
	var floor_panel := Vector2i(-8, BlockWorld.PAD_ROW)
	game.terrain.set_block(floor_panel, B.EMPTY)
	_expect(game.cabin.breaches.is_empty(), "An intact outer floor layer keeps the cabin sealed")
	game.terrain.set_block(floor_panel + Vector2i.DOWN, B.EMPTY)
	_expect(game.cabin.breaches.has(floor_panel), "A breach through both floor layers opens to space")
	game.terrain.set_block(floor_panel, B.HULL)
	game.terrain.set_block(floor_panel + Vector2i.DOWN, B.HULL)

	game.explorer.position = game.terrain.scene_point(BlockWorld.STATION_WORKBENCH, ActiveTerrain.CELL_CENTER)
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)
	var stone := game.inventory.count(B.STONE)
	var alloy := game.inventory.count(B.ALLOY)
	_expect(is_equal_approx(game.kit.pulse_reach_squared(), (2.1 * BlockWorld.TILE_SIZE) ** 2), "The starter pulse reaches 2.1 tiles")
	_expect(game.workbench_name() == "Relay Nine workshop" and game.craft(ExpeditionKit.Recipe.PULSE_1),
			"The station workshop crafts the first pulse upgrade")
	_expect(game.inventory.count(B.STONE) == stone - 4 and game.inventory.count(B.ALLOY) == alloy - 2,
			"Crafting deducts the listed materials")
	_expect(not game.craft(ExpeditionKit.Recipe.PULSE_1), "An installed upgrade cannot cost resources again")
	game.inventory.add(B.STONE, 2)
	game.inventory.add(B.ORE, 13)
	_expect(not game.craft(ExpeditionKit.Recipe.PULSE_3) and game.craft(ExpeditionKit.Recipe.PULSE_2) and
			game.craft(ExpeditionKit.Recipe.PULSE_3) and game.kit.pulse_level == 3,
			"Levels two and three are craftable in order")
	_expect(game.craft(ExpeditionKit.Recipe.CANISTER) and game.craft(ExpeditionKit.Recipe.LINER), "Craftable air and pressure gear are available")
	_expect(game.craft(ExpeditionKit.Recipe.GLASS) and game.craft(ExpeditionKit.Recipe.FRAME) and
			game.craft(ExpeditionKit.Recipe.INSULATION), "The workbench crafts all three new construction blocks")
	game.survival.oxygen = 100.0
	_expect(not game.use_air_canister(), "A full oxygen tank does not waste a canister")
	_expect(game.inventory.count(I.CANISTER) == 1, "The first canister occupies an inventory stack")
	game.survival.oxygen = 22.0
	_expect(game.use_air_canister() and game.survival.oxygen == 67.0 and game.inventory.count(I.CANISTER) == 0,
			"A canister restores 45 oxygen and is consumed from inventory")
	_expect(game.craft(ExpeditionKit.Recipe.CANISTER), "A spare canister can be crafted after the first is used")
	_expect(game.craft(ExpeditionKit.Recipe.SMELT), "The workshop refines more alloy for later construction")


func _check_orbital_descent(game: MomoyoGame) -> void:
	var address := game.sector
	var deck_edge := Vector2i(23, BlockWorld.PAD_ROW)
	game.explorer.position = game.terrain.scene_point(deck_edge, Vector2(0.5, -15.0 / BlockWorld.TILE_SIZE))
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)
	_expect(game.explorer.is_on_floor() and game.explorer.gravity == BlockWorld.STATION_GRAVITY_PX,
			"The EVA deck remains inside the Relay's artificial gravity")
	var health := game.survival.health
	var integrity := game.survival.suit_integrity
	Input.action_press("move_right")
	await _frames(65)
	Input.action_release("move_right")
	_expect(not game.explorer.is_on_floor() and game.explorer.velocity.y > 0.0
			and is_equal_approx(game.explorer.gravity, game._orbital_pull()), "Walking off the EVA deck leaves only the planet's pull")
	for _frame in 420:
		if game.region == BlockWorld.Region.SURFACE:
			break
		await get_tree().process_frame
	_expect(game.region == BlockWorld.Region.SURFACE and game.sector == address
			and game.explorer.position.y < BlockWorld.pad_position().y - 5 * BlockWorld.TILE_SIZE and game.explorer.velocity.y > 0.0,
			"An orbital fall brings the explorer into the same planet's sky with downward momentum")
	await _frames(92)
	_expect(game.explorer.is_on_floor() and game._at_beacon() and game.survival.health >= health
			and is_equal_approx(game.survival.suit_integrity, integrity), "The explorer lands near the beacon without a station rescue penalty")
	var saved := ExpeditionSave.new().read()
	_expect(saved.get("region") == BlockWorld.Region.SURFACE and saved.get("sector") == address,
			"The orbital descent saves the surface arrival")


func _check_weather(game: MomoyoGame) -> void:
	var weather := game.find_child("CurrentWeather", true, false) as Label
	var precipitation := game.get_node("Backdrop/Front") as WeatherLayer
	game.survival.elapsed = 46.93
	await _frames(18)
	_expect(weather.text == "Weather: Rain" and precipitation.visible, "Rain and the HUD switch on together")
	game.survival.elapsed = 69.93
	await _frames(18)
	_expect(weather.text == "Weather: Clear" and not precipitation.visible, "Clear weather also updates the HUD")


func _check_far_terrain(game: MomoyoGame) -> MomoyoGame:
	for direction: int in [-1, 1]:
		var old_wall := 192 * BlockWorld.TILE_SIZE * direction
		var standing := Vector2(old_wall - 8.0 * direction, 0.0)
		var column := floori(standing.x / BlockWorld.TILE_SIZE)
		var ground := game.surface.surface_row(column)
		for x: int in range(column - 6, column + 7):
			game.surface.record_edit(Vector2i(x, ground), BlockWorld.Block.STONE)
			for gap in range(1, 4):
				game.surface.record_edit(Vector2i(x, ground - gap), BlockWorld.Block.EMPTY)
		game._open_region(BlockWorld.Region.SURFACE, Vector2(standing.x, ground * BlockWorld.TILE_SIZE - 15.0))
		await _frames(5)
		var walk := "move_left" if direction < 0 else "move_right"
		Input.action_press(walk)
		await _frames(20)
		Input.action_release(walk)
		_expect(game.explorer.position.x * direction > absi(old_wall) + 24.0, "Walking crosses the former horizontal boundary")

	var origin := Vector2i(4000000, 128)
	var local := Vector2(ActiveTerrain.REBASE_DISTANCE + 14.0, BlockWorld.TILE_SIZE * 3 - 15.0)
	var absolute_cell := origin + BlockWorld.cell_at(local)
	for x in range(absolute_cell.x - 2, absolute_cell.x + 3):
		for headroom in range(3):
			game.surface.record_edit(Vector2i(x, absolute_cell.y - headroom), BlockWorld.Block.EMPTY)
		game.surface.record_edit(Vector2i(x, absolute_cell.y + 1), BlockWorld.Block.STONE)
	game._open_region(BlockWorld.Region.SURFACE, local, origin)
	await _frames(10)
	_expect(game.terrain.origin_cell.x > origin.x and absf(game.explorer.position.x) < BlockWorld.TILE_SIZE * 2.0,
			"The scene origin recenters far from spawn")
	_expect(game.terrain.world_cell(game.explorer.position) == absolute_cell and game.explorer.is_on_floor(),
			"Recentering keeps the logical position and local collision deep underground")
	_expect(game.save_expedition(), "An expedition saves a rebased position")
	game.queue_free()
	await get_tree().process_frame

	game = _open_game()
	await _frames(8)
	_expect(game.terrain.world_cell(game.explorer.position) == absolute_cell and game.explorer.is_on_floor(),
			"A far-away explorer reloads with correct world coordinates and collision")
	return game


func _check_previous_format() -> void:
	var old := FileAccess.open(ExpeditionSave.SLOT, FileAccess.WRITE)
	var edit := Vector2i(2, BlockWorld.PAD_ROW)
	var sector := Vector2i.RIGHT
	var old_vitals := SurvivalState.new().snapshot()
	var old_inventory := PackedInt32Array([170, 8, 30, 0])
	old_vitals.erase("body_temperature")
	old_vitals.erase("suit_equipped")
	old_vitals.erase("suit_integrity")
	old_vitals.erase("jetpack_fuel")
	old_vitals.erase("jetpack_cooldown")
	old_vitals["food"] = 3
	old_vitals["water"] = 4
	old.store_var({
		"format": 2, "world_revision": 1, "region": BlockWorld.Region.STATION, "sector": sector,
		"position": BlockWorld.pad_position(), "inventory": old_inventory, "selected": 0,
		"planets": {sector: {"blocks": {edit: BlockWorld.Block.EMPTY}, "harvested": {7: true}}},
		"station": {"blocks": {}, "harvested": {}}, "vitals": old_vitals,
	})
	old.close()
	var migrated := ExpeditionSave.new().read()
	_expect(migrated.get("sector") == sector and migrated.get("universe_seed") == 0 and
			migrated.get("kit", {}) == ExpeditionKit.new().snapshot(),
			"A 0.2 expedition keeps its original galaxy and destination")
	if not migrated.is_empty():
		var journal := TerrainJournal.unpack(migrated.planets[sector], true)
		_expect(journal.blocks.get(edit) == BlockWorld.Block.EMPTY and journal.harvested.has(7),
				"0.2 building and forage data migrate into compact journals")
		migrated.format = 3
		migrated.erase("kit")
		migrated.inventory = old_inventory
		migrated.vitals = old_vitals.duplicate()
		_expect(ExpeditionSave.new().write(migrated) == OK, "A 0.3 fixture can be written")
		var previous := ExpeditionSave.new()
		var updated := previous.read()
		_expect(previous.loaded_format == 3 and updated.get("sector") == sector and
				updated.get("kit", {}) == ExpeditionKit.new().snapshot(),
				"0.3 compact terrain is preserved while gear migrates")
		if not updated.is_empty():
			var workbench := BlockWorld.pad_position() + Vector2(-216.0, 0.0)
			updated.format = ExpeditionSave.STATION_REFIT_FORMAT
			updated.position = workbench
			updated.kit = {"pick": true, "liner": false, "canisters": 2}
			updated.inventory = old_inventory
			updated.vitals = old_vitals.duplicate()
			_expect(previous.write(updated) == OK, "A 0.4 fixture can be written")
			var game := _open_game()
			_expect(game.region == BlockWorld.Region.STATION and game.explorer.position == workbench and
					game.kit.pulse_level == 1 and game.inventory.count(I.CANISTER) == 2 and game.survival.body_temperature == 37.0,
					"A 0.4 station save gains normal body temperature and keeps its position and equipment")
			game.free()
			updated.format = ExpeditionSave.TEMPERATURE_FORMAT
			updated.vitals["body_temperature"] = 38.4
			_expect(previous.write(updated) == OK, "A 0.4.1 fixture can be written")
			game = _open_game()
			_expect(game.kit.pulse_level == 1 and game.explorer.position == workbench and
					is_equal_approx(game.survival.body_temperature, 38.4) and game.survival.suit_integrity == 100.0,
					"0.4.1 upgrades the old pick and adds a clean suit without resetting existing vitals")
			game.free()
			updated.format = ExpeditionSave.FIELD_EQUIPMENT_FORMAT
			updated.kit = {"prospector": true, "liner": true, "canisters": 2, "workbenches": 3}
			updated.selected = 4
			updated.vitals["suit_equipped"] = false
			updated.vitals["suit_integrity"] = 54.0
			_expect(previous.write(updated) == OK, "A 0.5 fixture can be written")
			game = _open_game()
			_expect(game.inventory.quantity_at(0) == 170 and game.inventory.item_at(4) == B.WORKBENCH and
					game.selected == 4 and game.inventory.count(I.RATION) == 3 and game.inventory.count(I.WATER) == 4 and
					game.kit.pulse_level == 1 and game.kit.liner and not game.survival.suit_equipped and
					game.inventory.count(I.CANISTER) == 2 and game.survival.jetpack_fuel == 1.5,
					"0.5 saves preserve all resources, including large stacks, and add a charged jetpack")
			game.free()
			var slotted := ExpeditionSave.new().read()
			if not slotted.is_empty():
				slotted.format = ExpeditionSave.SLOTTED_FORMAT
				slotted.erase("habitats")
				slotted.vitals.erase("vacuum_exposure")
				slotted.vitals.erase("vacuum_recovery")
				_expect(previous.write(slotted) == OK, "A 0.6 fixture can be written")
				var restored := ExpeditionSave.new().read()
				_expect(restored.get("habitats") == {} and restored.get("vitals", {}).get("vacuum_exposure") == 0.0 and
						restored.get("inventory") == slotted.inventory, "0.6 saves retain their slots and gain the vacuum defaults")
				if not restored.is_empty():
					restored.format = ExpeditionSave.HABITAT_FORMAT
					restored.vitals["vacuum_exposure"] = 6.25
					restored.vitals.erase("vacuum_recovery")
					_expect(previous.write(restored) == OK, "A 0.7 fixture can be written")
					var migrated_habitat := ExpeditionSave.new().read()
					var vitals: Dictionary = migrated_habitat.get("vitals", {})
					_expect(vitals.get("vacuum_exposure") == 6.25 and vitals.get("vacuum_recovery") == 0.0,
							"0.7 saves retain their remaining vacuum grace and gain the recharge timer")
					if not vitals.is_empty():
						vitals.vacuum_recovery = 2.5
						_expect(previous.write(migrated_habitat) == OK and ExpeditionSave.new().read().get("vitals", {}) == vitals,
								"Expedition saves preserve partial vacuum recovery")
						_check_power_migration(previous, migrated_habitat)


func _check_power_migration(save: ExpeditionSave, state: Dictionary) -> void:
	var zone := Vector3i(1, 0, BlockWorld.Region.SURFACE)
	var area := Rect2i(6, BlockWorld.PAD_ROW - 3, 4, 3)
	state.format = ExpeditionSave.VACUUM_RECOVERY_FORMAT
	state.vitals.elapsed = 120.0
	state.habitats = {zone: {TEST_RECYCLER: {"bounds": area, "air": 72.0, "time": 5.0}}}
	_expect(save.write(state) == OK, "A pre-power habitat fixture can be written")
	var migrated := ExpeditionSave.new().read()
	var room: Dictionary = migrated.get("habitats", {}).get(zone, {}).get(TEST_RECYCLER, {})
	_expect(room.get("time") == 120.0 and room.get("air") == 72.0 and room.get("charge") == HabitatRoom.RECYCLER_BUFFER
			and room.get("fuel_seconds") == 0.0 and migrated.get("vitals", {}).get("vacuum_recovery") == 2.5,
			"Existing habitats retain air and get a fresh reserve without changing the explorer's vacuum recovery")
	if not room.is_empty():
		room.charge = 12.0
		migrated.format = ExpeditionSave.POWER_FORMAT
		migrated.erase("sandbox_enabled")
		_expect(save.write(migrated) == OK, "An existing powered habitat can be written without the sandbox flag")
		var powered := save.read()
		var existing: Dictionary = powered.get("habitats", {}).get(zone, {}).get(TEST_RECYCLER, {})
		_expect(powered.get("sandbox_enabled") == false and existing.get("charge") == 12.0,
				"Power-era saves preserve their battery state and start with sandbox mode disabled")


func _check_journal() -> void:
	var edits: Dictionary[Vector2i, int] = {}
	for x in range(-100, 100):
		for y in range(100, 105):
			edits[Vector2i(x, y)] = BlockWorld.Block.STONE
	var harvests := {-876543: true, 54321: true}
	var packet := TerrainJournal.pack(edits, harvests)
	var journal := TerrainJournal.unpack(packet, true)
	_expect(packet.size() < 4000 and journal.get("blocks") == edits and journal.get("harvested") == harvests,
			"An edited region compresses and restores every cell and harvest")
	_expect(TerrainJournal.unpack(packet, false).is_empty(), "Station journals do not contain surface harvests")
	var world := BlockWorld.new(BlockWorld.Region.STATION)
	var station_extension := Vector2i(-93, -34)
	var chunk := BlockWorld.chunk_at(station_extension)
	var local := station_extension - chunk * BlockWorld.CHUNK_SIZE
	var index := local.y * BlockWorld.CHUNK_SIZE + local.x
	world.restore_journal({"blocks": {station_extension: BlockWorld.Block.ALLOY}})
	_expect(world.make_chunk(chunk)[index] == BlockWorld.Block.ALLOY,
			"An otherwise empty orbit chunk regenerates a saved extension")
	world.record_edit(station_extension, BlockWorld.Block.EMPTY)
	_expect(world.make_chunk(chunk)[index] == BlockWorld.Block.EMPTY and world.edits.is_empty(),
			"Removing the last edit restores a blank chunk")
	world.record_edit(station_extension, BlockWorld.Block.STONE)
	_expect(world.make_chunk(chunk)[index] == BlockWorld.Block.STONE, "A new edit is tracked after a chunk reverts")
	var first := PlanetProfile.new(Vector2i(18, -23), 112334)
	var repeat := PlanetProfile.new(Vector2i(18, -23), 112334)
	var different := PlanetProfile.new(Vector2i(18, -23), 471104)
	_expect(first.details == repeat.details and first.details != different.details,
			"Planet profiles depend on both the persistent universe seed and sector")
	for t in range(20, 200, 17):
		_expect(first.weather_at(t) == repeat.weather_at(t), "Seeded fronts reproduce on the expedition clock")


func _write_legacy_save() -> void:
	var old := FileAccess.open(ExpeditionSave.SLOT, FileAccess.WRITE)
	old.store_var({
		"format": 1, "world_revision": 1, "region": BlockWorld.Region.SURFACE,
		"position": BlockWorld.pad_position(), "inventory": PackedInt32Array([12, 8, 30, 0]),
		"selected": 0, "edits": [{Vector2i(-4, BlockWorld.PAD_ROW): BlockWorld.Block.STONE}, {}],
	})
	old.close()


func _open_game() -> MomoyoGame:
	var game: MomoyoGame = GAME.instantiate()
	add_child(game)
	return game


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _expect(result: bool, failure: String) -> void:
	if not result:
		push_error(failure)
		_failures += 1
