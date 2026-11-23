class_name BlockWorld
extends RefCounted

enum Region { SURFACE, STATION }
enum Block {
	EMPTY, GRASS, SOIL, STONE, ALLOY, ORE, BEACON, SAND, SHALE, BASALT, FROSTSTONE, HULL, WORKBENCH,
	GLASS, FRAME, INSULATION, AIRLOCK, RECYCLER,
}

const CHUNK_BITS := 5
const CHUNK_SIZE := 1 << CHUNK_BITS
const TILE_SIZE := 24
const PAD_ROW := 14
const LEGACY_REVISION := 1
const WORLD_REVISION := 2
const LEGACY_SURFACE_BOUNDS := Rect2i(-192, -32, 384, 128)
const LEGACY_STATION_BOUNDS := Rect2i(-96, -24, 192, 80)
const STATION_CABIN := Rect2i(-18, PAD_ROW - 6, 27, 6)
const STATION_HATCH := Vector2i(STATION_CABIN.end.x, PAD_ROW - 3)
const STATION_WORKBENCH := Vector2i(-9, PAD_ROW - 1)
const STATION_HULL := Rect2i(-19, PAD_ROW - 7, 44, 11)
const STATION_PRESSURE_AREA := Rect2i(-21, PAD_ROW - 9, 48, 15)
const STATION_DESCENT_ROW := 56
const STATION_GRAVITY_PX := 510.0
const STATION_GRAVITY_FALLOFF_TILES := 4.0
const ORBITAL_GRAVITY_FRACTION := 0.12
const BUILD_MATERIALS: Array[int] = [Block.SOIL, Block.STONE, Block.ALLOY, Block.ORE]
const BLOCK_NAMES := [
	"Empty", "Grass", "Soil", "Stone", "Alloy", "Ore", "Beacon", "Sand", "Shale", "Basalt", "Froststone",
	"Pressure hull", "Workbench", "Pressure glass", "Support frame", "Insulation", "Airlock panel", "Oxygen recycler",
]
const MINING_SECONDS := [0.0, 0.40, 0.58, 1.48, 2.15, 1.95, 0.0, 0.48, 1.10, 2.10, 1.67, 2.55, 1.0, 1.38, 1.72, 0.86, 1.92, 2.1]
const TILE_COLORS: Array[Color] = [
	Color.TRANSPARENT, Color("#aacea1"), Color("#856252"), Color("#50536e"),
	Color("#6f8d9d"), Color("#60768b"), Color("#43696b"), Color("#bca474"),
	Color("#64617c"), Color("#4f4152"), Color("#6a97a6"), Color("#465d72"), Color("#53736f"),
	Color("#53a6ad"), Color("#96764f"), Color("#a76d5b"),
	Color("#57788a"), Color("#4e8977"),
]

var region: int
var edits: Dictionary[Vector2i, int] = {}
var harvested: Dictionary[int, bool] = {}
var journal_dirty := false
var planet: PlanetProfile

var _edited_chunks: Dictionary[Vector2i, int] = {}
var _salt: int
var _soil := Block.SOIL
var _rock := Block.STONE
var _soil_depth := 5
var _ore_period := 41
var _cave_density := 3
var _relief := 1.0
var _forage_spacing := 7


func _init(world_region: int, sector := Vector2i.ZERO, universe_seed: int = 0) -> void:
	region = world_region
	if region == Region.SURFACE:
		planet = PlanetProfile.new(sector, universe_seed)
		_salt = planet.terrain_salt()
		_relief = planet.details.relief
		if not planet.legacy:
			_soil = Block.SAND if planet.kind == 1 or planet.sample(51) % 7 == 0 else Block.SOIL
			_rock = [Block.STONE, Block.SHALE, Block.BASALT, Block.FROSTSTONE][planet.rock_type]
			_soil_depth = 3 + planet.sample(53) % 6
			_ore_period = 23 + planet.sample(54) % 39
			_cave_density = 2 + planet.sample(55) % 4
			_forage_spacing = 5 + planet.sample(56) % 8


static func chunk_at(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x >> CHUNK_BITS, cell.y >> CHUNK_BITS)


static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i((point / TILE_SIZE).floor())


static func pad_position() -> Vector2:
	return Vector2(TILE_SIZE * 0.5, PAD_ROW * TILE_SIZE - 15.0)


static func station_gravity_strength(tile_position: Vector2) -> float:
	var field := Rect2(STATION_PRESSURE_AREA)
	var edge := tile_position.clamp(field.position, field.end)
	return 1.0 - smoothstep(0.0, STATION_GRAVITY_FALLOFF_TILES ** 2, tile_position.distance_squared_to(edge))


func make_chunk(chunk: Vector2i) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(CHUNK_SIZE * CHUNK_SIZE)
	var origin := chunk * CHUNK_SIZE
	if region == Region.SURFACE:
		for col in CHUNK_SIZE:
			var x := origin.x + col
			var ground := surface_row(x)
			for row in range(maxi(0, ground - origin.y), CHUNK_SIZE):
				cells[row * CHUNK_SIZE + col] = _base_block(Vector2i(x, origin.y + row), ground)
	else:
		var hull := STATION_HULL.intersection(Rect2i(origin, Vector2i.ONE * CHUNK_SIZE))
		for y in range(hull.position.y, hull.end.y):
			for x in range(hull.position.x, hull.end.x):
				var index := (y - origin.y) * CHUNK_SIZE + x - origin.x
				cells[index] = _base_block(Vector2i(x, y), PAD_ROW)

	if _edited_chunks.has(chunk):
		for row in CHUNK_SIZE:
			for col in CHUNK_SIZE:
				var index := row * CHUNK_SIZE + col
				cells[index] = edits.get(origin + Vector2i(col, row), cells[index])
	return cells


func record_edit(cell: Vector2i, material: int) -> void:
	var chunk := chunk_at(cell)
	var ground := surface_row(cell.x) if region == Region.SURFACE else PAD_ROW
	if material == _base_block(cell, ground):
		if not edits.erase(cell):
			return
		var remaining := _edited_chunks[chunk] - 1
		if remaining == 0:
			_edited_chunks.erase(chunk)
		else:
			_edited_chunks[chunk] = remaining
	else:
		if not edits.has(cell):
			_count_edit(chunk)
		edits[cell] = material
	journal_dirty = true


func _count_edit(chunk: Vector2i) -> void:
	_edited_chunks[chunk] = _edited_chunks.get(chunk, 0) + 1


func record_harvest(column: int) -> void:
	harvested[column] = true
	journal_dirty = true


func restore_journal(data: Dictionary) -> void:
	edits.assign(data.get("blocks", {}))
	harvested.assign(data.get("harvested", {}))
	_edited_chunks.clear()
	for cell in edits:
		_count_edit(chunk_at(cell))
	journal_dirty = false


static func is_pad(cell: Vector2i) -> bool:
	return cell.y == PAD_ROW and cell.x >= -1 and cell.x <= 1


static func is_valid_edit(material: int) -> bool:
	return material >= Block.EMPTY and material < TILE_COLORS.size() and material != Block.BEACON


static func is_placeable(material: int) -> bool:
	return material == Block.SAND or material in BUILD_MATERIALS \
			or (material >= Block.WORKBENCH and material < TILE_COLORS.size())


static func is_airtight(material: int) -> bool:
	match material:
		Block.ALLOY, Block.HULL, Block.BEACON, Block.GLASS, Block.AIRLOCK, Block.RECYCLER:
			return true
		_:
			return false


func material_at(cell: Vector2i) -> int:
	if edits.has(cell):
		return edits[cell]
	return _base_block(cell, surface_row(cell.x) if region == Region.SURFACE else PAD_ROW)


static func mined_material(material: int) -> int:
	match material:
		Block.GRASS:
			return Block.SOIL
		Block.SHALE, Block.BASALT, Block.FROSTSTONE:
			return Block.STONE
		Block.HULL:
			return Block.ALLOY
	return material


static func mining_time(material: int, power := 1.0) -> float:
	var seconds: float = MINING_SECONDS[material]
	return seconds / power if seconds >= 1.0 else seconds


func surface_row(x: int) -> int:
	if x >= -9 and x <= 11:
		return PAD_ROW
	var bits := 4 if planet.legacy else 5
	var width := 1 << bits
	var segment := x >> bits
	var progress := posmod(x, width)
	var left := _terrain_hash(segment, 11) % 13 - 6
	var right := _terrain_hash(segment + 1, 11) % 13 - 6
	var height := floori(lerpf(float(left), float(right), float(progress) / width))
	var ramp := minf(1.0, minf(absf(x + 9), absf(x - 11)) / 12.0)
	return PAD_ROW + roundi(height * ramp * _relief)


func _base_block(cell: Vector2i, surface: int) -> int:
	if is_pad(cell):
		return Block.BEACON
	if region == Region.STATION:
		return _station_structure(cell)

	var depth := cell.y - surface
	if depth < 0:
		return Block.EMPTY
	if depth == 0:
		return Block.GRASS
	if depth < _soil_depth:
		return _soil
	if depth > 9 and _terrain_hash(cell.x >> 2, cell.y >> 2) % 17 < _cave_density:
		return Block.EMPTY
	if _terrain_hash(cell.x, cell.y) % _ore_period == 0:
		return Block.ORE
	return _rock


func _station_structure(cell: Vector2i) -> int:
	if not STATION_HULL.has_point(cell):
		return Block.EMPTY
	var left := STATION_CABIN.position.x - 1
	var top := STATION_CABIN.position.y - 1
	var hatch := STATION_HATCH.x
	if cell.y == PAD_ROW:
		return Block.HULL if cell.x <= hatch else Block.ALLOY
	if cell.y == PAD_ROW + 1 and cell.x <= hatch + 4:
		return Block.HULL
	if cell.y >= PAD_ROW + 2 and cell.x in [-14, -13, -4, -3, 5, 6]:
		return Block.HULL
	if cell.y == top and cell.x <= hatch:
		return Block.HULL
	if cell.y > top and cell.y < PAD_ROW:
		if cell.x == left or (cell.x == hatch and cell.y < STATION_HATCH.y):
			return Block.HULL
	return Block.EMPTY


func station_breaches() -> Array[Vector2i]:
	var breaches: Array[Vector2i] = []
	var shell := STATION_CABIN.grow(1)
	for x in range(shell.position.x, shell.end.x):
		for y in [shell.position.y, shell.end.y - 1]:
			var cell := Vector2i(x, y)
			if not _pressure_rated(cell):
				breaches.append(cell)
	for y in range(STATION_CABIN.position.y, STATION_CABIN.end.y):
		var left := Vector2i(shell.position.x, y)
		var right := Vector2i(STATION_HATCH.x, y)
		if not _pressure_rated(left):
			breaches.append(left)
		if y < STATION_HATCH.y and not _pressure_rated(right):
			breaches.append(right)
	if breaches.is_empty():
		return breaches
	var exterior := _station_vacuum()
	var open: Array[Vector2i] = []
	for cell in breaches:
		if exterior.has(cell):
			open.append(cell)
	return open


func _station_vacuum() -> Dictionary[Vector2i, bool]:
	var bounds := STATION_PRESSURE_AREA
	var open: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for x in range(bounds.position.x, bounds.end.x):
		frontier.append(Vector2i(x, bounds.position.y))
		frontier.append(Vector2i(x, bounds.end.y - 1))
	for y in range(bounds.position.y + 1, bounds.end.y - 1):
		frontier.append(Vector2i(bounds.position.x, y))
		frontier.append(Vector2i(bounds.end.x - 1, y))
	var cardinal := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var read := 0
	while read < frontier.size():
		var cell := frontier[read]
		read += 1
		if open.has(cell) or STATION_CABIN.has_point(cell) or _pressure_rated(cell):
			continue
		if cell.x == STATION_HATCH.x and cell.y >= STATION_HATCH.y and cell.y < PAD_ROW:
			continue
		open[cell] = true
		for direction: Vector2i in cardinal:
			var neighbor := cell + direction
			if bounds.has_point(neighbor) and not open.has(neighbor):
				frontier.append(neighbor)
	return open


func station_arrival() -> Vector2:
	for column in [0, -1, 1, -2, 2, -3, 3, 4, 5, 6]:
		var x := int(column)
		if _station_block_at(Vector2i(x, PAD_ROW - 1)) == Block.EMPTY and _station_block_at(Vector2i(x, PAD_ROW - 2)) == Block.EMPTY:
			var floor_block := _station_block_at(Vector2i(x, PAD_ROW))
			if floor_block != Block.EMPTY:
				return Vector2((x + 0.5) * TILE_SIZE, pad_position().y)
	return pad_position()


func _pressure_rated(cell: Vector2i) -> bool:
	return is_airtight(_station_block_at(cell))


func _station_block_at(cell: Vector2i) -> int:
	return edits.get(cell, _base_block(cell, PAD_ROW))


func forage_kind(x: int) -> int:
	if region != Region.SURFACE or harvested.has(x):
		return 0
	if x == planet.food_column:
		return 1
	if x == planet.water_column:
		return 2
	if absi(x) <= 11:
		return 0
	if planet.legacy:
		return 1 + _terrain_hash(x, 37) % 2 if posmod(x, 7) == 0 else 0
	@warning_ignore("integer_division")
	var patch := (x - posmod(x, _forage_spacing)) / _forage_spacing
	var draw := _terrain_hash(patch, 37)
	if posmod(x, _forage_spacing) != draw % _forage_spacing:
		return 0
	return 1 + (draw >> 12) % 2


func _terrain_hash(x: int, y: int) -> int:
	return PlanetProfile.hash_cell(x, y, _salt)
