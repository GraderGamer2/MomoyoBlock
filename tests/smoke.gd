extends Node

const GAME := preload("res://game/main.tscn")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "check-export-save":
		await _check_export_save(args[1])
		get_tree().quit(1 if _failures else 0)
		return

	if FileAccess.file_exists(ExpeditionSave.SLOT):
		_expect(false, "Smoke test requires an empty test profile")
		get_tree().quit(1)
		return

	var game := _open_game()
	await _frames(16)
	_expect(game.explorer.is_on_floor(), "Explorer settles on the protected pad")
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
	_expect(game.worlds[BlockWorld.Region.STATION].edits.get(station_block) == BlockWorld.Block.ALLOY,
			"Reopening restores the inactive station edits")
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


func _check_export_save(file_path: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file != null:
			var state: Variant = file.get_var(false)
			if state is Dictionary and state.get("region") == BlockWorld.Region.STATION:
				return
		await get_tree().create_timer(0.15).timeout
	_expect(false, "The packaged game did not save at the orbital station")


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
