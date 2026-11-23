class_name ExpeditionSave
extends RefCounted

const DIRECTORY := "user://saves"
const DEFAULT_FILE := "expedition.save"
const SLOT := DIRECTORY + "/" + DEFAULT_FILE
const COMPACT_FORMAT := 3
const STATION_REFIT_FORMAT := 4
const TEMPERATURE_FORMAT := 5
const FIELD_EQUIPMENT_FORMAT := 6
const FORMAT := FIELD_EQUIPMENT_FORMAT
const MAX_BYTES := 64 * 1024 * 1024

var read_error: Error = OK
var loaded_format := FORMAT
var path: String


func _init(filename := DEFAULT_FILE) -> void:
	path = DIRECTORY.path_join(filename if _valid_filename(filename) else DEFAULT_FILE)


static func slots() -> Array[String]:
	var found: Array[String] = []
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return found
	var modified: Dictionary[String, int] = {}
	for filename in DirAccess.get_files_at(DIRECTORY):
		if _valid_filename(filename):
			found.append(filename)
			modified[filename] = FileAccess.get_modified_time(DIRECTORY.path_join(filename))
	found.sort_custom(func(a: String, b: String) -> bool:
		if modified[a] != modified[b]:
			return modified[a] > modified[b]
		if a == DEFAULT_FILE or b == DEFAULT_FILE:
			return b == DEFAULT_FILE
		return a > b)
	return found


static func unused_filename() -> String:
	if not FileAccess.file_exists(SLOT):
		return DEFAULT_FILE
	while true:
		var timestamp := int(Time.get_unix_time_from_system() * 1000.0)
		var filename := "expedition-%d-%08x.save" % [timestamp, randi()]
		if not FileAccess.file_exists(DIRECTORY.path_join(filename)):
			return filename
	return DEFAULT_FILE


static func slot_title(filename: String) -> String:
	if filename == DEFAULT_FILE:
		return "Original expedition"
	@warning_ignore("integer_division")
	var seconds := filename.get_slice("-", 1).to_int() / 1000
	return "Expedition %s UTC · %s" % [Time.get_datetime_string_from_unix_time(seconds, true),
			filename.get_basename().get_slice("-", 2).right(4).to_upper()]


static func _valid_filename(filename: String) -> bool:
	if filename == DEFAULT_FILE:
		return true
	if filename != filename.get_file() or not filename.begins_with("expedition-") or not filename.ends_with(".save"):
		return false
	var parts := filename.get_basename().split("-")
	return parts.size() == 3 and parts[1].length() == 13 and parts[1].is_valid_int() and parts[2].length() == 8 and parts[2].is_valid_hex_number()


func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
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
	loaded_format = state.format
	if loaded_format < COMPACT_FORMAT:
		state = _migrate_legacy(state)
	if not state.is_empty() and loaded_format < FORMAT:
		_upgrade_equipment(state)
	if not _state_data_valid(state):
		read_error = ERR_FILE_CORRUPT
		return {}
	return state


func _upgrade_equipment(state: Dictionary) -> void:
	if loaded_format < STATION_REFIT_FORMAT:
		state.kit = ExpeditionKit.new().snapshot()
	elif loaded_format < FIELD_EQUIPMENT_FORMAT:
		var kit: Variant = state.get("kit")
		if kit is Dictionary:
			kit["prospector"] = kit.get("pick")
			kit.erase("pick")
			kit["workbenches"] = 0

	var vitals: Variant = state.get("vitals")
	if vitals is Dictionary:
		if loaded_format < TEMPERATURE_FORMAT:
			vitals["body_temperature"] = SurvivalState.NORMAL_BODY_TEMPERATURE
		if loaded_format < FIELD_EQUIPMENT_FORMAT:
			vitals["suit_equipped"] = true
			vitals["suit_integrity"] = SurvivalState.MAX_LEVEL
	state.format = FORMAT


func write(state: Dictionary) -> Error:
	if read_error != OK:
		return read_error
	var result := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if result != OK:
		return result

	var temp := DIRECTORY.path_join(".%s-%d.tmp" % [path.get_file(), OS.get_process_id()])
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
		result = DirAccess.rename_absolute(temp, path)
	if result != OK:
		DirAccess.remove_absolute(temp)
	return result


static func _state_header_valid(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	var format: Variant = state.get("format")
	if not format is int or format < 1 or format > FORMAT:
		return false
	var region: Variant = state.get("region")
	if not region is int or region < BlockWorld.Region.SURFACE or region > BlockWorld.Region.STATION:
		return false
	var point: Variant = state.get("position")
	if not point is Vector2 or not point.is_finite():
		return false
	var inventory: Variant = state.get("inventory")
	if not inventory is PackedInt32Array or inventory.size() != BlockWorld.BUILD_MATERIALS.size():
		return false
	for count in inventory:
		if count < 0:
			return false
	var selected: Variant = state.get("selected")
	var slots: int = inventory.size() + int(format >= FIELD_EQUIPMENT_FORMAT)
	return selected is int and selected >= 0 and selected < slots


static func _migrate_legacy(state: Dictionary) -> Dictionary:
	if state.get("world_revision") != BlockWorld.LEGACY_REVISION:
		return {}
	var bounds := BlockWorld.LEGACY_SURFACE_BOUNDS if state.region == BlockWorld.Region.SURFACE else BlockWorld.LEGACY_STATION_BOUNDS
	if not bounds.has_point(BlockWorld.cell_at(state.position)):
		return {}

	if state.format == 1:
		var edits: Variant = state.get("edits")
		if not edits is Array or edits.size() != 2:
			return {}
		state.sector = Vector2i.ZERO
		state.planets = {Vector2i.ZERO: {"blocks": edits[0], "harvested": {}}}
		state.station = {"blocks": edits[1], "harvested": {}}
		state.vitals = SurvivalState.new().snapshot()
		state.erase("edits")

	var planets: Variant = state.get("planets")
	if not planets is Dictionary or not _valid_legacy_journal(state.get("station"), BlockWorld.LEGACY_STATION_BOUNDS, false):
		return {}
	var packed: Dictionary[Vector2i, PackedByteArray] = {}
	for sector: Variant in planets:
		var journal: Variant = planets[sector]
		if not sector is Vector2i or not _valid_legacy_journal(journal, BlockWorld.LEGACY_SURFACE_BOUNDS, true):
			return {}
		if not journal.blocks.is_empty() or not journal.harvested.is_empty():
			packed[sector] = TerrainJournal.pack(journal.blocks, journal.harvested)

	state.format = COMPACT_FORMAT
	state.universe_seed = 0
	state.origin = Vector2i.ZERO
	state.planets = packed
	state.station = TerrainJournal.pack(state.station.blocks, state.station.harvested)
	return state


static func _state_data_valid(state: Dictionary) -> bool:
	var world_seed: Variant = state.get("universe_seed")
	if not world_seed is int:
		return false
	var expected_revision := BlockWorld.LEGACY_REVISION if world_seed == 0 else BlockWorld.WORLD_REVISION
	if state.get("world_revision") != expected_revision:
		return false
	var origin: Variant = state.get("origin")
	if not origin is Vector2i or origin % BlockWorld.CHUNK_SIZE != Vector2i.ZERO:
		return false
	var point: Vector2 = state.position
	if maxf(absf(point.x), absf(point.y)) > ActiveTerrain.REBASE_DISTANCE + 2 * BlockWorld.TILE_SIZE:
		return false
	var planets: Variant = state.get("planets")
	if not state.get("sector") is Vector2i or not planets is Dictionary:
		return false
	if not SurvivalState.valid_snapshot(state.get("vitals")) or not ExpeditionKit.valid_snapshot(state.get("kit")):
		return false
	var station: Variant = state.get("station")
	if not station is PackedByteArray or TerrainJournal.unpack(station, false).is_empty():
		return false
	for address: Variant in planets:
		var packet: Variant = planets[address]
		if not address is Vector2i or not packet is PackedByteArray or TerrainJournal.unpack(packet, true).is_empty():
			return false
	return true


static func _valid_legacy_journal(data: Variant, bounds: Rect2i, can_harvest: bool) -> bool:
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
