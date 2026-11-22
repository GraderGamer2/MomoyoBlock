class_name ExpeditionSave
extends RefCounted

const DIRECTORY := "user://saves"
const SLOT := DIRECTORY + "/expedition.save"
const FORMAT := 2
const MAX_BYTES := 64 * 1024 * 1024

var read_error: Error = OK


func read() -> Dictionary:
	if not FileAccess.file_exists(SLOT):
		return {}

	var file := FileAccess.open(SLOT, FileAccess.READ)
	if file == null:
		read_error = FileAccess.get_open_error()
		return {}
	var length := file.get_length()
	if length < 8 or length > MAX_BYTES or file.get_32() != length - 4:
		read_error = ERR_FILE_CORRUPT
		return {}
	file.seek(0)
	var state: Variant = file.get_var(false)
	var error := file.get_error()
	file.close()
	if error != OK or not _state_header_valid(state):
		read_error = ERR_FILE_CORRUPT
		return {}
	if state.format == 1:
		state = _migrate_first_playtest(state)
	if not _state_data_valid(state):
		read_error = ERR_FILE_CORRUPT
		return {}
	return state


func write(state: Dictionary) -> Error:
	if read_error != OK:
		return read_error
	var result := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if result != OK:
		return result

	var temp := DIRECTORY.path_join(".expedition-%d.tmp" % OS.get_process_id())
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if file.store_var(state):
		file.flush()
		result = file.get_error()
		if result == OK and file.get_length() > MAX_BYTES:
			result = ERR_OUT_OF_MEMORY
	else:
		result = ERR_FILE_CANT_WRITE
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temp, SLOT)
	if result != OK:
		DirAccess.remove_absolute(temp)
	return result


static func _state_header_valid(state: Variant) -> bool:
	if not state is Dictionary or state.get("world_revision") != BlockWorld.WORLD_REVISION:
		return false
	if state.get("format") != 1 and state.get("format") != FORMAT:
		return false
	var region: Variant = state.get("region")
	if not region is int or region < BlockWorld.Region.SURFACE or region > BlockWorld.Region.STATION:
		return false
	var position: Variant = state.get("position")
	if not position is Vector2 or not position.is_finite():
		return false
	var bounds := BlockWorld.SURFACE_BOUNDS if region == BlockWorld.Region.SURFACE else BlockWorld.STATION_BOUNDS
	if not Rect2(Vector2(bounds.position), Vector2(bounds.size)).has_point(position / BlockWorld.TILE_SIZE):
		return false
	var inventory: Variant = state.get("inventory")
	if not inventory is PackedInt32Array or inventory.size() != BlockWorld.BUILD_MATERIALS.size():
		return false
	for count in inventory:
		if count < 0:
			return false
	var selected: Variant = state.get("selected")
	return selected is int and selected >= 0 and selected < inventory.size()


static func _migrate_first_playtest(state: Dictionary) -> Dictionary:
	var edits: Variant = state.get("edits")
	if not edits is Array or edits.size() != 2:
		return {}
	state.format = FORMAT
	state.sector = Vector2i.ZERO
	state.planets = {Vector2i.ZERO: {"blocks": edits[0], "harvested": {}}}
	state.station = {"blocks": edits[1], "harvested": {}}
	state.vitals = SurvivalState.new().snapshot()
	state.erase("edits")
	return state


static func _state_data_valid(state: Dictionary) -> bool:
	var planets: Variant = state.get("planets")
	if not state.get("sector") is Vector2i or not planets is Dictionary:
		return false
	if not SurvivalState.valid_snapshot(state.get("vitals")):
		return false
	if not _valid_journal(state.get("station"), BlockWorld.STATION_BOUNDS, false):
		return false
	for address: Variant in planets:
		if not address is Vector2i or not _valid_journal(planets[address], BlockWorld.SURFACE_BOUNDS, true):
			return false
	return true


static func _valid_journal(data: Variant, bounds: Rect2i, can_harvest: bool) -> bool:
	if not data is Dictionary:
		return false
	var edits: Variant = data.get("blocks")
	if not edits is Dictionary or edits.size() > bounds.get_area():
		return false
	for cell: Variant in edits:
		if not cell is Vector2i or not bounds.has_point(cell) or BlockWorld.is_pad(cell):
			return false
		var material: Variant = edits[cell]
		if not material is int or material < BlockWorld.Block.EMPTY or material >= BlockWorld.Block.BEACON:
			return false
	var harvested: Variant = data.get("harvested")
	if not harvested is Dictionary or harvested.size() > bounds.size.x:
		return false
	if not can_harvest and not harvested.is_empty():
		return false
	for column: Variant in harvested:
		if not column is int or column < bounds.position.x or column >= bounds.end.x or harvested[column] != true:
			return false
	return true
