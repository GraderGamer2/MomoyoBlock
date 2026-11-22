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
	_check_previous_format()
	_check_journal()
	_write_legacy_save()
	var game := _open_game()
	await _frames(16)
	_expect(game.explorer.is_on_floor(), "Explorer settles on the protected pad")
	_expect(game.terrain.block_at(Vector2i(-4, BlockWorld.PAD_ROW)) == BlockWorld.Block.STONE,
			"First-playtest saves keep their existing Cinder Reach edits")
	_expect(game.survival.oxygen == 100.0 and game.survival.food == 2, "First-playtest saves gain survival defaults")
	_check_survival_model()
	await _check_weather(game)
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
	_expect(not game.gather_nearby(), "Forage beyond two tiles is out of reach")
	game.explorer.position.x = -100.0
	_expect(game.gather_nearby() and game.survival.food == food + 1, "Planet forage replenishes carried food")
	_expect(game.surface.harvested.has(-6), "Harvest marks the original plant column")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)

	var surface_block := Vector2i(2, BlockWorld.PAD_ROW)
	var above_surface := surface_block + Vector2i.UP
	var soil := game.inventory[0]
	_expect(not game.begin_mining(Vector2i(0, BlockWorld.PAD_ROW)), "Beacon pad is protected")
	_expect(not game.place(BlockWorld.cell_at(game.explorer.position)), "Placement avoids the explorer")
	_expect(not game.begin_mining(surface_block), "Mining cannot reach a tile center more than two tiles away")
	_expect(not game.place(Vector2i(3, BlockWorld.PAD_ROW - 1)), "Placement has the same short range")
	game.explorer.position.x = 35.0
	_expect(game.begin_mining(surface_block), "Nearby grass can be targeted")
	_expect(not game.advance_mining(0.18, surface_block, true) and game.inventory[0] == soil,
			"Mining for less than the hardness leaves the block and inventory unchanged")
	_expect(not game.advance_mining(1.0, surface_block, false), "Releasing the button cancels mining")
	_expect(game.begin_mining(surface_block) and not game.advance_mining(0.18, surface_block, true),
			"Returning to a cancelled block starts from zero")
	_expect(game.advance_mining(0.15, surface_block, true) and game.inventory[0] == soil + 1,
			"A completed hold breaks the block and pays out soil once")
	_expect(not game.advance_mining(4.0, surface_block, true) and not game.begin_mining(surface_block),
			"Continued holding cannot mine the empty cell twice")
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
	await _check_station(game)
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	await _frames(6)
	var station_block := Vector2i(-1, BlockWorld.PAD_ROW - 2)
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
	_expect(game.kit.pick and game.kit.liner and game.kit.canisters == 1, "Reopening restores crafted equipment")
	_expect(game.terrain.block_at(surface_block) == BlockWorld.Block.EMPTY, "Reopening restores the mined block")
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
	await _frames(32)
	_expect(game.survival.oxygen < before, "The EVA deck uses suit oxygen")
	game.explorer.position = BlockWorld.pad_position()
	game.explorer.velocity = Vector2.ZERO
	_expect(game.land_at(Vector2i.RIGHT), "The star chart accepts a different sector at the beacon")
	await _frames(90)
	_expect(game.sector == Vector2i.RIGHT and game.region == BlockWorld.Region.SURFACE, "Chart travel reaches a generated planet")
	_expect(not game.surface.planet.details.breathable, "The first destination requires suit oxygen")
	_expect(game.terrain.block_at(above_surface) == BlockWorld.Block.EMPTY, "Edits belong to the planet where they were made")
	var foreign_block := Vector2i(1, BlockWorld.PAD_ROW - 2)
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
	app.show_workshop()
	_expect(app.screen == MomoyoApp.Screen.WORKSHOP and get_tree().paused,
			"The landing beacon opens a workshop menu")
	app.resume_expedition()
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
	app.return_to_menu()
	await _frames(3)
	app.start_new_expedition()
	await _frames(3)
	_expect(app.game.universe_seed != first_seed and ExpeditionSave.slots().size() == 2,
			"A second expedition starts a new universe and keeps the previous slot")
	_expect(ExpeditionSave.new().read().get("universe_seed") == first_seed, "The original expedition is preserved")
	app.queue_free()
	await get_tree().process_frame


func _check_survival_model() -> void:
	var suit := SurvivalState.new()
	suit.advance(10.0, false, false)
	_expect(is_equal_approx(suit.oxygen, 89.0) and suit.hunger < 100.0 and suit.thirst < 100.0,
			"Suit oxygen drains at the gentler vacuum rate")
	_expect(suit.eat() and suit.drink() and suit.hunger == 100.0 and suit.thirst == 100.0, "Food and drinking water restore vitals")
	suit.oxygen = 0
	suit.advance(1.0, false, true)
	_expect(is_equal_approx(suit.health, 96.0), "Empty oxygen uses the lower health penalty")
	suit.advance(7.0, true, false)
	_expect(suit.oxygen == 100.0, "Breathable air replenishes the suit")
	var exposed := SurvivalState.new()
	var protected := SurvivalState.new()
	exposed.advance(10.0, false, false, 226, 56.0)
	protected.advance(10.0, false, false, 226, 56.0, true)
	_expect(exposed.health < protected.health and protected.health < 100.0 and exposed.thirst < suit.thirst,
			"Dense air causes suit strain, heat increases thirst, and the liner reduces pressure damage")
	var gear := ExpeditionKit.new()
	gear.canisters = 1
	suit.oxygen = 22.0
	_expect(gear.use_canister(suit) and suit.oxygen == 67.0 and gear.canisters == 0,
			"A spare canister restores 45 oxygen and is consumed")
	_expect(BlockWorld.mining_time(BlockWorld.Block.HULL, false) > BlockWorld.mining_time(BlockWorld.Block.STONE, false) and
			BlockWorld.mining_time(BlockWorld.Block.STONE, true) < BlockWorld.mining_time(BlockWorld.Block.STONE, false),
			"Block hardness differs and the pick speeds up solid material")
	var origin := PlanetProfile.new(Vector2i.ZERO)
	_expect(origin.weather_at(12.0).is_empty() and origin.weather_at(55.0) == "Rain", "Planet weather moves through a cycle")
	var address := Vector2i(-2147483648, 2147483647)
	var first := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	var second := BlockWorld.new(BlockWorld.Region.SURFACE, address)
	_expect(first.make_chunk(Vector2i.ZERO) == second.make_chunk(Vector2i.ZERO), "Distant addresses reproduce the same terrain")


func _check_station(game: MomoyoGame) -> void:
	_expect(game.station.station_cabin_sealed(), "The refit begins with a sealed cabin")
	var wall := Vector2i(BlockWorld.STATION_CABIN.position.x - 1, BlockWorld.PAD_ROW - 1)
	game.explorer.position = game.terrain.scene_point(wall + Vector2i.RIGHT, ActiveTerrain.CELL_CENTER)
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)
	_expect(game.breathable_here(), "A player away from the beacon can breathe in the cabin")
	_expect(game.begin_mining(wall), "A hull block can be targeted up close")
	_expect(not game.advance_mining(1.0, wall, true), "The hull takes longer to break than grass")
	_expect(not game.advance_mining(3.0, wall + Vector2i.UP, true), "Switching targets cancels mining")
	_expect(game.begin_mining(wall) and game.advance_mining(2.2, wall, true), "Holding breaks a hull block at its hardness threshold")
	_expect(not game.breathable_here() and not game.station.station_cabin_sealed(), "A hull breach vents the cabin")
	_expect(game.place(wall) and game.breathable_here(), "An alloy patch restores the cabin")

	game.explorer.position = game.terrain.scene_point(BlockWorld.STATION_WORKBENCH, ActiveTerrain.CELL_CENTER)
	game.explorer.velocity = Vector2.ZERO
	await _frames(5)
	var before := game.inventory.duplicate()
	_expect(game.can_craft_here() and game.craft(ExpeditionKit.Recipe.PICK), "The workbench crafts a pick")
	_expect(game.inventory[1] == before[1] - 4 and game.inventory[2] == before[2] - 2,
			"Crafting deducts the listed materials")
	_expect(not game.craft(ExpeditionKit.Recipe.PICK), "An equipped pick cannot cost resources again")
	game.inventory[3] += 3
	_expect(game.craft(ExpeditionKit.Recipe.CANISTER) and game.craft(ExpeditionKit.Recipe.LINER), "Craftable air and pressure gear are available")
	_expect(not game.use_air_canister(), "A full oxygen tank does not waste a canister")
	_expect(game.kit.canisters == 1, "The first canister remains available for a later sortie")


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
	old.store_var({
		"format": 2, "world_revision": 1, "region": BlockWorld.Region.STATION, "sector": sector,
		"position": BlockWorld.pad_position(), "inventory": PackedInt32Array([12, 8, 30, 0]), "selected": 0,
		"planets": {sector: {"blocks": {edit: BlockWorld.Block.EMPTY}, "harvested": {7: true}}},
		"station": {"blocks": {}, "harvested": {}}, "vitals": SurvivalState.new().snapshot(),
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
		_expect(ExpeditionSave.new().write(migrated) == OK, "A 0.3 fixture can be written")
		var previous := ExpeditionSave.new()
		var updated := previous.read()
		_expect(previous.loaded_format == 3 and updated.get("sector") == sector and
				updated.get("kit", {}) == ExpeditionKit.new().snapshot(),
				"0.3 compact terrain is preserved while gear migrates")


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
