class_name BlockWorld
extends RefCounted

enum Region { SURFACE, STATION }
enum Block { EMPTY, GRASS, SOIL, STONE, ALLOY, ORE, BEACON }

const CHUNK_BITS := 5
const CHUNK_SIZE := 1 << CHUNK_BITS
const TILE_SIZE := 24
const PAD_ROW := 14
const ORIGIN_SEED := 472913
const WORLD_REVISION := 1
const SURFACE_BOUNDS := Rect2i(-192, -32, 384, 128)
const STATION_BOUNDS := Rect2i(-96, -24, 192, 80)
const BUILD_MATERIALS: Array[int] = [Block.SOIL, Block.STONE, Block.ALLOY, Block.ORE]
const MATERIAL_NAMES: Array[String] = ["Soil", "Stone", "Alloy", "Ore"]
const TILE_COLORS: Array[Color] = [
	Color.TRANSPARENT, Color("#aacea1"), Color("#856252"), Color("#50536e"),
	Color("#6f8d9d"), Color("#60768b"), Color("#43696b"),
]

var region: int
var bounds: Rect2i
var edits: Dictionary[Vector2i, int] = {}


func _init(world_region: int) -> void:
	region = world_region
	bounds = SURFACE_BOUNDS if region == Region.SURFACE else STATION_BOUNDS


static func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x >> CHUNK_BITS, cell.y >> CHUNK_BITS)


static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i((point / TILE_SIZE).floor())


static func pad_position() -> Vector2:
	return Vector2(TILE_SIZE * 0.5, PAD_ROW * TILE_SIZE - 15)


func make_chunk(chunk: Vector2i) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(CHUNK_SIZE * CHUNK_SIZE)
	var origin := chunk * CHUNK_SIZE
	var area := bounds.intersection(Rect2i(origin, Vector2i(CHUNK_SIZE, CHUNK_SIZE)))
	for x in range(area.position.x, area.end.x):
		var surface := surface_row(x) if region == Region.SURFACE else PAD_ROW
		for y in range(area.position.y, area.end.y):
			var cell := Vector2i(x, y)
			var index := (y - origin.y) * CHUNK_SIZE + x - origin.x
			if edits.has(cell):
				cells[index] = edits[cell]
			else:
				cells[index] = _base_block(cell, surface)
	return cells


func record_edit(cell: Vector2i, material: int) -> void:
	var surface := surface_row(cell.x) if region == Region.SURFACE else PAD_ROW
	if material == _base_block(cell, surface):
		edits.erase(cell)
	else:
		edits[cell] = material


static func is_pad(cell: Vector2i) -> bool:
	return cell.y == PAD_ROW and cell.x >= -1 and cell.x <= 1


static func surface_row(x: int) -> int:
	if x >= -9 and x <= 11:
		return PAD_ROW
	var segment := x >> 4
	var progress := posmod(x, 16)
	var left := _terrain_hash(segment, 11) % 13 - 6
	var right := _terrain_hash(segment + 1, 11) % 13 - 6
	var height := floori(lerpf(float(left), float(right), progress / 16.0))
	var ramp := minf(1.0, minf(absf(x + 9), absf(x - 11)) / 12.0)
	return PAD_ROW + roundi(height * ramp)


func _base_block(cell: Vector2i, surface: int) -> int:
	if is_pad(cell):
		return Block.BEACON
	if region == Region.STATION:
		if cell.x >= -13 and cell.x <= 13:
			if cell.y == PAD_ROW or cell.y == PAD_ROW + 1:
				return Block.ALLOY
			if absi(cell.x) >= 7 and cell.y == PAD_ROW - 7:
				return Block.ALLOY
			if absi(cell.x) == 13 and cell.y > PAD_ROW - 7 and cell.y < PAD_ROW:
				return Block.ALLOY
		return Block.EMPTY

	var depth := cell.y - surface
	if depth < 0:
		return Block.EMPTY
	if depth == 0:
		return Block.GRASS
	if depth < 5:
		return Block.SOIL
	if depth > 9 and _terrain_hash(cell.x >> 2, cell.y >> 2) % 17 < 3:
		return Block.EMPTY
	if _terrain_hash(cell.x, cell.y) % 41 == 0:
		return Block.ORE
	return Block.STONE


static func _terrain_hash(x: int, y: int) -> int:
	var value := ((x * 374761393) ^ (y * 668265263) ^ ORIGIN_SEED) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return value ^ (value >> 16)
