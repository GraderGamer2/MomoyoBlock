class_name ActiveTerrain
extends TileMapLayer

# At 1152 × 648, one 768 px chunk per side covers the camera plus a movement margin.
const RADIUS := 1

var world: BlockWorld
var forage := ForageLayer.new()
var _loaded: Dictionary[Vector2i, PackedByteArray] = {}
var _center := Vector2i(1000000, 1000000)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	navigation_enabled = false
	occlusion_enabled = false
	tile_set = _make_tileset()
	forage.z_index = 1
	add_child(forage)


func open_region(new_world: BlockWorld, point: Vector2) -> void:
	world = new_world
	clear()
	_loaded.clear()
	_center = Vector2i(1000000, 1000000)
	stream_around(point)
	update_internals()


func stream_around(point: Vector2) -> void:
	var center := BlockWorld.chunk_at(BlockWorld.cell_at(point))
	if center == _center:
		return
	_center = center
	var radius := Vector2i(RADIUS, RADIUS)
	var area := Rect2i(center - radius, radius * 2 + Vector2i.ONE)
	for key in _loaded.keys():
		if not area.has_point(key):
			_unload(key)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var key := Vector2i(x, y)
			if not _loaded.has(key):
				_load(key)

	_refresh_forage()

func is_editable(cell: Vector2i) -> bool:
	return world.bounds.has_point(cell) and _loaded.has(BlockWorld.chunk_at(cell)) and not BlockWorld.is_pad(cell)


func block_at(cell: Vector2i) -> int:
	var key := BlockWorld.chunk_at(cell)
	if not _loaded.has(key):
		return BlockWorld.Block.EMPTY
	return _loaded[key][_index(cell, key)]


func set_block(cell: Vector2i, material: int) -> void:
	var key := BlockWorld.chunk_at(cell)
	var cells := _loaded[key]
	cells[_index(cell, key)] = material
	_loaded[key] = cells
	world.record_edit(cell, material)
	_paint(cell, material)
	if world.region == BlockWorld.Region.SURFACE and absi(cell.y - world.surface_row(cell.x)) <= 1:
		_refresh_forage()


func nearest_forage(point: Vector2, range_squared: float) -> Vector2i:
	var closest := Vector2i(100000, 100000)
	for cell in forage.markers:
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * BlockWorld.TILE_SIZE
		var distance := point.distance_squared_to(center)
		if distance <= range_squared:
			closest = cell
			range_squared = distance
	return closest


func harvest(cell: Vector2i) -> void:
	world.harvested[cell.x] = true
	forage.markers.erase(cell)
	forage.queue_redraw()


func _refresh_forage() -> void:
	forage.markers.clear()
	if world.region == BlockWorld.Region.SURFACE:
		var start := maxi(world.bounds.position.x, (_center.x - RADIUS) * BlockWorld.CHUNK_SIZE)
		var end := mini(world.bounds.end.x, (_center.x + RADIUS + 1) * BlockWorld.CHUNK_SIZE)
		for x in range(start, end):
			var kind := world.forage_kind(x)
			if kind == 0:
				continue
			var ground := Vector2i(x, world.surface_row(x))
			var cell := ground + Vector2i.UP
			if is_editable(cell) and block_at(cell) == BlockWorld.Block.EMPTY and block_at(ground) != BlockWorld.Block.EMPTY:
				forage.markers[cell] = kind
		forage.tint = world.planet.details.sky.lightened(0.45)
	forage.queue_redraw()


func _load(key: Vector2i) -> void:
	var origin := key * BlockWorld.CHUNK_SIZE
	var chunk_rect := Rect2i(origin, Vector2i.ONE * BlockWorld.CHUNK_SIZE)
	if not world.bounds.intersects(chunk_rect):
		return
	var cells := world.make_chunk(key)
	_loaded[key] = cells
	for index in cells.size():
		var material := cells[index]
		if material != BlockWorld.Block.EMPTY:
			_paint(origin + _cell_offset(index), material)


func _unload(key: Vector2i) -> void:
	var origin := key * BlockWorld.CHUNK_SIZE
	var cells := _loaded[key]
	for index in cells.size():
		if cells[index] != BlockWorld.Block.EMPTY:
			erase_cell(origin + _cell_offset(index))
	_loaded.erase(key)


func _paint(cell: Vector2i, material: int) -> void:
	if material == BlockWorld.Block.EMPTY:
		erase_cell(cell)
	else:
		set_cell(cell, 0, Vector2i(material - 1, 0))


static func _cell_offset(index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % BlockWorld.CHUNK_SIZE, index / BlockWorld.CHUNK_SIZE)


static func _index(cell: Vector2i, key: Vector2i) -> int:
	var local := cell - key * BlockWorld.CHUNK_SIZE
	return local.y * BlockWorld.CHUNK_SIZE + local.x


static func _make_tileset() -> TileSet:
	var size := BlockWorld.TILE_SIZE
	var atlas_size := BlockWorld.TILE_COLORS.size() - 1
	var image := Image.create_empty(size * atlas_size, size, false, Image.FORMAT_RGBA8)
	for i in atlas_size:
		var block := i + 1
		var x := i * size
		var color := BlockWorld.TILE_COLORS[block]
		image.fill_rect(Rect2i(x, 0, size, size), color.darkened(0.23))
		image.fill_rect(Rect2i(x + 1, 0, size - 2, size - 1), color)
		if block == BlockWorld.Block.GRASS:
			image.fill_rect(Rect2i(x + 1, 6, size - 2, size - 7), BlockWorld.TILE_COLORS[BlockWorld.Block.SOIL])
		elif block == BlockWorld.Block.ORE:
			image.fill_rect(Rect2i(x + 7, 8, 7, 7), Color("#ebaa6d"))
		elif block == BlockWorld.Block.ALLOY:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, 2), color.lightened(0.27))
		elif block == BlockWorld.Block.BEACON:
			image.fill_rect(Rect2i(x + 1, 0, size - 2, 4), Color("#f5cc89"))

	var tiles := TileSet.new()
	tiles.tile_size = Vector2i.ONE * size
	tiles.add_physics_layer()
	tiles.set_physics_layer_collision_layer(0, 1)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = tiles.tile_size
	tiles.add_source(source, 0)

	var half := size * 0.5
	var shape := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for i in atlas_size:
		var coords := Vector2i(i, 0)
		source.create_tile(coords)
		var data := source.get_tile_data(coords, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, shape)
	return tiles
