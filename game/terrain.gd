class_name ActiveTerrain
extends Node2D

signal block_changed(cell: Vector2i)

const CHUNK_PIXELS := BlockWorld.CHUNK_SIZE * BlockWorld.TILE_SIZE
const VIEW_MARGIN := Vector2(96, 96)
const REBASE_DISTANCE := BlockWorld.CHUNK_SIZE * BlockWorld.TILE_SIZE * 12
const CELL_CENTER := Vector2(0.5, 0.5)

var world: BlockWorld
var origin_cell := Vector2i.ZERO
var forage := ForageLayer.new()
var _loaded: Dictionary[Vector2i, PackedByteArray] = {}
var _layers: Dictionary[Vector2i, TileMapLayer] = {}
var _idle_layers: Array[TileMapLayer] = []
var _loaded_area := Rect2i()
var _radius := Vector2i.ONE
var _tiles := TileSet.new()
var _atlas := TileSetAtlasSource.new()


func _ready() -> void:
	_create_tileset()
	forage.z_index = 1
	add_child(forage)
	get_viewport().size_changed.connect(_update_stream_radius)
	_update_stream_radius()


func open_region(new_world: BlockWorld, point: Vector2, origin := Vector2i.ZERO) -> void:
	world = new_world
	origin_cell = origin
	for key in _loaded.keys():
		_unload(key)
	_paint_atlas()
	stream_around(point)
	for layer in _layers.values():
		layer.update_internals()


func world_cell(point: Vector2) -> Vector2i:
	return origin_cell + BlockWorld.cell_at(point)


func scene_point(cell: Vector2i, inside := Vector2.ZERO) -> Vector2:
	return (Vector2(cell - origin_cell) + inside) * BlockWorld.TILE_SIZE


func rebase_if_needed(point: Vector2) -> Vector2:
	if absf(point.x) < REBASE_DISTANCE and absf(point.y) < REBASE_DISTANCE:
		return Vector2.ZERO
	var relative := BlockWorld.cell_at(point)
	# Move only the axes that need recentering.
	if absf(point.x) < REBASE_DISTANCE:
		relative.x = 0
	if absf(point.y) < REBASE_DISTANCE:
		relative.y = 0
	var shift := BlockWorld.chunk_at(relative) * BlockWorld.CHUNK_SIZE
	origin_cell += shift
	for key in _layers:
		var layer := _layers[key]
		layer.position = scene_point(key * BlockWorld.CHUNK_SIZE)
		layer.force_update_transform()
	forage.origin_cell = origin_cell
	forage.queue_redraw()
	return Vector2(shift) * BlockWorld.TILE_SIZE


func stream_around(point: Vector2) -> void:
	var center := BlockWorld.chunk_at(world_cell(point))
	var area := Rect2i(center - _radius, _radius * 2 + Vector2i.ONE)
	if area == _loaded_area and not _loaded.is_empty():
		return
	_loaded_area = area
	for key in _loaded.keys():
		if not area.has_point(key):
			_unload(key)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var key := Vector2i(x, y)
			if not _loaded.has(key):
				_load(key)
	_refresh_forage()


func _update_stream_radius() -> void:
	var extent := get_viewport_rect().size * 0.5 + VIEW_MARGIN
	_radius = Vector2i((extent / CHUNK_PIXELS).ceil()).max(Vector2i.ONE)


func is_editable(cell: Vector2i) -> bool:
	return _loaded.has(BlockWorld.chunk_at(cell)) and not BlockWorld.is_pad(cell)


func block_at(cell: Vector2i) -> int:
	var key := BlockWorld.chunk_at(cell)
	if not _loaded.has(key):
		return BlockWorld.Block.EMPTY
	return _loaded[key][_index(cell, key)]


func set_block(cell: Vector2i, material: int) -> void:
	var key := BlockWorld.chunk_at(cell)
	var cells := _loaded[key]
	var index := _index(cell, key)
	if cells[index] == material:
		return
	cells[index] = material
	_loaded[key] = cells
	world.record_edit(cell, material)
	_paint(_layer_for(key), _cell_offset(index), material)
	if world.planet != null and absi(cell.y - world.surface_row(cell.x)) <= 1:
		_refresh_forage()
	block_changed.emit(cell)


func nearest_forage(point: Vector2, range_squared: float) -> Variant:
	var closest: Variant = null
	for cell in forage.markers:
		var distance := point.distance_squared_to(scene_point(cell, CELL_CENTER))
		if distance <= range_squared and pulse_path_clear(point, cell):
			closest = cell
			range_squared = distance
	return closest


func has_block_near(point: Vector2, material: int, reach: float) -> bool:
	return nearest_block(point, material, reach) != null


func nearest_block(point: Vector2, material: int, reach: float) -> Variant:
	var first := world_cell(point - Vector2.ONE * reach)
	var last := world_cell(point + Vector2.ONE * reach)
	var closest: Variant = null
	var range_squared := reach * reach
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if block_at(cell) != material:
				continue
			var distance := point.distance_squared_to(scene_point(cell, CELL_CENTER))
			if distance <= range_squared:
				closest = cell
				range_squared = distance
	return closest


func pulse_path_clear(point: Vector2, target: Vector2i) -> bool:
	var cell := world_cell(point)
	var ray := scene_point(target, CELL_CENTER) - point
	var step := Vector2i(ray.sign())
	var offset := point - scene_point(cell)
	var size := float(BlockWorld.TILE_SIZE)
	# Advance between tile boundaries and allow the pulse to hit its target tile.
	var intervals := Vector2(INF, INF)
	var crossing := Vector2(INF, INF)
	for axis in 2:
		if step[axis] != 0:
			var distance := size - offset[axis] if step[axis] > 0 else offset[axis]
			intervals[axis] = size / absf(ray[axis])
			crossing[axis] = distance / absf(ray[axis])
	while cell != target:
		if crossing.x < crossing.y:
			cell.x += step.x
			crossing.x += intervals.x
		elif crossing.y < crossing.x:
			cell.y += step.y
			crossing.y += intervals.y
		else:
			cell += step
			crossing += intervals
		if cell != target and block_at(cell) != BlockWorld.Block.EMPTY:
			return false
	return true


func harvest(cell: Vector2i) -> void:
	world.record_harvest(cell.x)
	forage.markers.erase(cell)
	forage.queue_redraw()


func _refresh_forage() -> void:
	forage.markers.clear()
	forage.origin_cell = origin_cell
	forage.planet = world.planet
	if world.planet != null:
		var start := _loaded_area.position.x * BlockWorld.CHUNK_SIZE
		var end := _loaded_area.end.x * BlockWorld.CHUNK_SIZE
		for x in range(start, end):
			var kind := world.forage_kind(x)
			if kind == 0:
				continue
			var ground := Vector2i(x, world.surface_row(x))
			var cell := ground + Vector2i.UP
			if is_editable(cell) and block_at(cell) == BlockWorld.Block.EMPTY and block_at(ground) != BlockWorld.Block.EMPTY:
				forage.markers[cell] = kind
	forage.queue_redraw()


func _load(key: Vector2i) -> void:
	var cells := world.make_chunk(key)
	_loaded[key] = cells
	var layer: TileMapLayer
	for index in cells.size():
		var material := cells[index]
		if material != BlockWorld.Block.EMPTY:
			if layer == null:
				layer = _layer_for(key)
			_paint(layer, _cell_offset(index), material)


func _unload(key: Vector2i) -> void:
	if _layers.has(key):
		var layer := _layers[key]
		_layers.erase(key)
		layer.clear()
		layer.hide()
		_idle_layers.append(layer)
	_loaded.erase(key)


func _layer_for(key: Vector2i) -> TileMapLayer:
	if _layers.has(key):
		return _layers[key]
	var layer: TileMapLayer
	if _idle_layers.is_empty():
		layer = TileMapLayer.new()
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.navigation_enabled = false
		layer.occlusion_enabled = false
		layer.tile_set = _tiles
		add_child(layer)
	else:
		layer = _idle_layers.pop_back()
	layer.position = scene_point(key * BlockWorld.CHUNK_SIZE)
	layer.show()
	_layers[key] = layer
	return layer


static func _paint(layer: TileMapLayer, cell: Vector2i, material: int) -> void:
	if material == BlockWorld.Block.EMPTY:
		layer.erase_cell(cell)
	else:
		layer.set_cell(cell, 0, Vector2i(material - 1, 0))


static func _cell_offset(index: int) -> Vector2i:
	return Vector2i(index & (BlockWorld.CHUNK_SIZE - 1), index >> BlockWorld.CHUNK_BITS)


static func _index(cell: Vector2i, key: Vector2i) -> int:
	var local := cell - key * BlockWorld.CHUNK_SIZE
	return local.y * BlockWorld.CHUNK_SIZE + local.x


func _create_tileset() -> void:
	var size := BlockWorld.TILE_SIZE
	_tiles.tile_size = Vector2i.ONE * size
	_tiles.add_physics_layer()
	_tiles.set_physics_layer_collision_layer(0, 1)
	_atlas.texture_region_size = _tiles.tile_size
	_paint_atlas()
	_tiles.add_source(_atlas, 0)

	var half := size * 0.5
	var shape := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for i in BlockWorld.TILE_COLORS.size() - 1:
		var coords := Vector2i(i, 0)
		_atlas.create_tile(coords)
		var data := _atlas.get_tile_data(coords, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, shape)


func _paint_atlas() -> void:
	var size := BlockWorld.TILE_SIZE
	var colors: Array[Color] = BlockWorld.TILE_COLORS.duplicate()
	if world != null and world.planet != null and not world.planet.legacy:
		colors[BlockWorld.Block.GRASS] = world.planet.details.surface_color
		colors[BlockWorld.Block.SOIL] = world.planet.details.soil_color
		colors[BlockWorld.Block.STONE] = world.planet.details.rock_color
	var atlas_size := BlockWorld.TILE_COLORS.size() - 1
	var image := Image.create_empty(size * atlas_size, size, false, Image.FORMAT_RGBA8)
	for i in atlas_size:
		var block := i + 1
		var x := i * size
		var color := colors[block]
		image.fill_rect(Rect2i(x, 0, size, size), color.darkened(0.23))
		image.fill_rect(Rect2i(x + 1, 0, size - 2, size - 1), color)
		if block == BlockWorld.Block.GRASS:
			image.fill_rect(Rect2i(x + 1, 6, size - 2, size - 7), colors[BlockWorld.Block.SOIL])
		elif block == BlockWorld.Block.ORE:
			image.fill_rect(Rect2i(x + 7, 8, 7, 7), Color("#ebaa6d"))
		elif block == BlockWorld.Block.ALLOY:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, 2), color.lightened(0.27))
		elif block == BlockWorld.Block.HULL:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, size - 7), color.darkened(0.15))
			image.fill_rect(Rect2i(x + 5, 5, size - 10, 2), color.lightened(0.37))
			image.fill_rect(Rect2i(x + 3, size - 6, 2, 2), Color("#c6a370"))
			image.fill_rect(Rect2i(x + size - 5, size - 6, 2, 2), Color("#c6a370"))
		elif block == BlockWorld.Block.BEACON:
			image.fill_rect(Rect2i(x + 1, 0, size - 2, 4), Color("#f5cc89"))
		elif block == BlockWorld.Block.WORKBENCH:
			image.fill_rect(Rect2i(x + 2, 5, size - 4, size - 7), Color("#203a42"))
			image.fill_rect(Rect2i(x + 1, 4, size - 2, 3), Color("#a39c70"))
			image.fill_rect(Rect2i(x + 4, 11, 9, 6), Color("#37585e"))
			image.fill_rect(Rect2i(x + 15, 10, 5, 4), Color("#a0e0ba"))
			image.fill_rect(Rect2i(x + 4, 19, size - 8, 1), Color("#4f7377"))
		elif block == BlockWorld.Block.GLASS:
			image.fill_rect(Rect2i(x + 2, 2, size - 4, size - 4), Color(0.19, 0.58, 0.66, 0.32))
			image.fill_rect(Rect2i(x + 4, 5, size - 8, 1), Color("#9ddadf"))
			image.fill_rect(Rect2i(x + 5, 9, 4, 1), Color("#7bbac7"))
		elif block == BlockWorld.Block.FRAME:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, size - 6), Color.TRANSPARENT)
			for rail in range(4, size - 5, 2):
				image.fill_rect(Rect2i(x + rail, rail, 3, 3), color)
				image.fill_rect(Rect2i(x + size - rail - 3, rail, 3, 3), color.lightened(0.16))
		elif block == BlockWorld.Block.INSULATION:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, size - 7), Color("#483745"))
			for stripe in 3:
				image.fill_rect(Rect2i(x + 5, 5 + stripe * 5, size - 10, 3), color.lightened(0.12))
		elif block == BlockWorld.Block.AIRLOCK:
			image.fill_rect(Rect2i(x + 4, 0, size - 8, size), color.darkened(0.42))
			image.fill_rect(Rect2i(x + 10, 0, 2, size), color.lightened(0.18))
			image.fill_rect(Rect2i(x + 14, 10, 4, 4), Color("#9bd8bc"))
		elif block == BlockWorld.Block.RECYCLER:
			image.fill_rect(Rect2i(x + 3, 3, size - 6, size - 6), color.darkened(0.44))
			image.fill_rect(Rect2i(x + 5, 4, size - 10, 3), Color("#a3e5bd"))
			for stripe in 3:
				image.fill_rect(Rect2i(x + 6, 10 + stripe * 3, size - 12, 1), color.lightened(0.24))

	_atlas.texture = ImageTexture.create_from_image(image)
