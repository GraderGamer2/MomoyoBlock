class_name ExpeditionSave
extends RefCounted

const DIRECTORY := "user://saves"
const SLOT := DIRECTORY + "/expedition.save"
const FORMAT := 1
const MAX_BYTES := 8 * 1024 * 1024

var read_error: Error = OK


func read() -> Dictionary:
	if not FileAccess.file_exists(SLOT):
		return {}

	var error: Error
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
	error = file.get_error()
	file.close()
	if error != OK or not _is_valid(state):
		read_error = ERR_FILE_CORRUPT
		return {}
	return state


func write(region: int, position: Vector2, inventory: PackedInt32Array, selected: int, worlds: Array[BlockWorld]) -> Error:
	if read_error != OK:
		return read_error
	var result := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if result != OK:
		return result

	var temp := DIRECTORY.path_join(".expedition-%d.tmp" % OS.get_process_id())
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var state := {
		"format": FORMAT,
		"world_revision": BlockWorld.WORLD_REVISION,
		"region": region,
		"position": position,
		"inventory": inventory,
		"selected": selected,
		"edits": [worlds[0].edits, worlds[1].edits],
	}
	if file.store_var(state):
		file.flush()
		result = file.get_error()
	else:
		result = ERR_FILE_CANT_WRITE
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temp, SLOT)
	if result != OK:
		DirAccess.remove_absolute(temp)
	return result


static func _is_valid(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	if state.get("format") != FORMAT or state.get("world_revision") != BlockWorld.WORLD_REVISION:
		return false
	var region: Variant = state.get("region")
	if not region is int or region < BlockWorld.Region.SURFACE or region > BlockWorld.Region.STATION:
		return false
	var position: Variant = state.get("position")
	if not position is Vector2 or not position.is_finite():
		return false
	var bounds := BlockWorld.SURFACE_BOUNDS if region == BlockWorld.Region.SURFACE else BlockWorld.STATION_BOUNDS
	if not bounds.has_point(BlockWorld.cell_at(position)):
		return false
	var inventory: Variant = state.get("inventory")
	if not inventory is PackedInt32Array or inventory.size() != BlockWorld.BUILD_MATERIALS.size():
		return false
	for count in inventory:
		if count < 0:
			return false
	var selected: Variant = state.get("selected")
	if not selected is int or selected < 0 or selected >= inventory.size():
		return false
	var edits: Variant = state.get("edits")
	if not edits is Array or edits.size() != 2:
		return false
	return _valid_edits(edits[0], BlockWorld.SURFACE_BOUNDS) and _valid_edits(edits[1], BlockWorld.STATION_BOUNDS)


static func _valid_edits(edits: Variant, bounds: Rect2i) -> bool:
	if not edits is Dictionary or edits.size() > bounds.get_area():
		return false
	for cell: Variant in edits:
		if not cell is Vector2i or not bounds.has_point(cell) or BlockWorld.is_pad(cell):
			return false
		var material: Variant = edits[cell]
		if not material is int or material < BlockWorld.Block.EMPTY or material >= BlockWorld.Block.BEACON:
			return false
	return true
