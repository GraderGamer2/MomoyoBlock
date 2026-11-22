extends Node

const GAME := preload("res://game/main.tscn")
const APP := preload("res://game/app.tscn")

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
	_write_legacy_save()
	var game := _open_game()
	await _frames(16)
	_expect(game.explorer.is_on_floor(), "Explorer settles on the protected pad")
	_expect(game.terrain.block_at(Vector2i(-4, BlockWorld.PAD_ROW)) == BlockWorld.Block.STONE,
			"First-playtest saves keep their existing Cinder Reach edits")
	_expect(game.survival.oxygen == 100.0 and game.survival.food == 2, "First-playtest saves gain survival defaults")
	_check_survival_model()
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

	var food := game.survival.food
	game.explorer.position.x = -80.0
	_expect(game.gather_nearby() and game.survival.food == food + 1, "Planet forage replenishes carried food")
	_expect(game.surface.harvested.has(-6), "Harvest marks the original plant column")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)

	var surface_block := Vector2i(2, BlockWorld.PAD_ROW)
	var above_surface := surface_block + Vector2i.UP
	var soil := game.inventory[0]
	_expect(not game.mine(Vector2i(0, BlockWorld.PAD_ROW)), "Beacon pad is protected")
	_expect(not game.place(BlockWorld.cell_at(game.explorer.position)), "Placement avoids the explorer")
	_expect(game.mine(surface_block) and game.inventory[0] == soil + 1, "Mining pays out soil once")
	_expect(not game.mine(surface_block), "An empty cell cannot be mined")
	_expect(game.place(above_surface) and game.inventory[0] == soil, "Placement consumes one block")
	_expect(not game.place(Vector2i(40, 7)), "Placement respects reach")

	game.terrain.stream_around(Vector2(2700.0, 350.0))
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.EMPTY, "Distant chunks unload")
	game.terrain.stream_around(game.explorer.position)
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL, "A streamed chunk restores its edits")
	_expect(BlockWorld.chunk_at(Vector2i(-1, -33)) == Vector2i(-1, -2), "Negative cells use the correct chunk")

	_expect(game.begin_travel(), "Surface beacon starts travel")
	_expect(not game.begin_travel(), "An active transfer cannot be queued twice")
	await _frames(90)
	_expect(game.region == BlockWorld.Region.STATION, "Travel reaches the orbital station")
	game.selected = 2
	var station_block := Vector2i(-3, BlockWorld.PAD_ROW - 1)
	var alloy := game.inventory[2]
	_expect(game.place(station_block), "The orbital station accepts building")
	_expect(game.begin_travel(), "The station beacon starts the return trip")
	await _frames(90)
	_expect(game.region == BlockWorld.Region.SURFACE, "The return trip reaches the surface")
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL, "Surface edits outlast a trip")
	_expect(game.save_expedition(), "The expedition saves")
	game.queue_free()
	await get_tree().process_frame

	game = _open_game()
	await _frames(5)
	_expect(game.region == BlockWorld.Region.SURFACE, "Reopening restores the last region")
	_expect(game.inventory[2] == alloy - 1 and game.selected == 2, "Reopening restores inventory and selection")
	_expect(game.terrain.block_at(surface_block) == BlockWorld.Block.EMPTY, "Reopening restores the mined block")
	_expect(game.station.edits.get(station_block) == BlockWorld.Block.ALLOY,
			"Reopening restores the inactive station edits")
	_expect(game.surface.harvested.has(-6), "Harvest persists after reopening")
	_expect(game.begin_travel(), "The station can be reached again")
	await _frames(90)
	game.explorer.position.x += 115.0
	var before := game.survival.oxygen
	await _frames(32)
	_expect(game.survival.oxygen < before, "Oxygen drains away from the station beacon")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	_expect(game.land_at(Vector2i.RIGHT), "The star chart accepts a different sector at the beacon")
	await _frames(90)
	_expect(game.sector == Vector2i.RIGHT and game.region == BlockWorld.Region.SURFACE, "Chart travel reaches a generated planet")
	_expect(not game.surface.planet.details.breathable, "The first destination requires suit oxygen")
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.EMPTY, "Edits belong to the planet where they were made")
	var foreign_block := Vector2i(4, BlockWorld.PAD_ROW - 1)
	_expect(game.place(foreign_block), "You can build on another planet")
	_expect(game.save_expedition(), "The expedition saves a destination and its changes")
	game.queue_free()
	await get_tree().process_frame

	game = _open_game()
	await _frames(6)
	_expect(game.sector == Vector2i.RIGHT and game.terrain.block_at(foreign_block) == BlockWorld.Block.ALLOY,
			"Reopening restores a generated destination and its edits")
	_expect(game.begin_travel(), "The second planet connects back to Relay Nine")
	await _frames(90)
	_expect(game.land_at(Vector2i.ZERO), "You can chart a return trip to the first planet")
	await _frames(90)
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.SOIL and game.surface.harvested.has(-6),
			"Returning to the original sector restores terrain and forage changes")
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
	app.game.survival.hunger = 88.0
	app.show_pause()
	await _frames(30)
	_expect(get_tree().paused and app.game.survival.hunger == 88.0, "The pause menu stops survival time")
	app.return_to_menu()
	await _frames(3)
	_expect(app.game == null and app.screen == MomoyoApp.Screen.TITLE and not get_tree().paused, "Save and return reopens the main menu")
	_expect(FileAccess.file_exists(ExpeditionSave.SLOT), "Returning to the main menu saves the expedition")
	app.queue_free()
	await get_tree().process_frame


func _check_survival_model() -> void:
	var suit := SurvivalState.new()
	suit.advance(10.0, false, false)
	_expect(suit.oxygen < 90.0 and suit.hunger < 100.0 and suit.thirst < 100.0, "Survival vitals deplete in vacuum")
	_expect(suit.eat() and suit.drink() and suit.hunger == 100.0 and suit.thirst == 100.0, "Food and drinking water restore vitals")
	suit.oxygen = 0
	suit.advance(1.0, false, true)
	_expect(suit.health < 100.0, "Empty oxygen causes damage")
	suit.advance(7.0, true, false)
	_expect(suit.oxygen == 100.0, "Breathable air replenishes the suit")
	var origin := PlanetProfile.new(Vector2i.ZERO)
	_expect(not origin.weather_active(12.0) and origin.weather_active(55.0), "Planet weather moves through a cycle")
	var address := Vector2i(-2147483648, 2147483647)
	var first := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	var second := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	_expect(first.make_chunk(Vector2i.ZERO) == second.make_chunk(Vector2i.ZERO), "Distant addresses reproduce the same terrain")


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
