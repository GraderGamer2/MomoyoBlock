class_name HabitatRoom
extends RefCounted

const MAX_WIDTH := 12
const MAX_HEIGHT := 8
const B := BlockWorld.Block

var bounds: Rect2i
var air := 0.0
var _time := 0.0
var _openings := 0
var _pumping := false
var _air_cells: Dictionary[Vector2i, bool] = {}


func _init(area: Rect2i, now: float) -> void:
	bounds = area
	_time = now


static func survey(world: BlockWorld, recycler: Vector2i) -> Rect2i:
	var start := recycler + Vector2i.UP
	if BlockWorld.is_airtight(world.material_at(start)):
		return Rect2i()
	var left := _wall_distance(world, start, Vector2i.LEFT, MAX_WIDTH)
	var right := _wall_distance(world, start, Vector2i.RIGHT, MAX_WIDTH)
	var above := _wall_distance(world, start, Vector2i.UP, MAX_HEIGHT)
	var size := Vector2i(left + right - 1, above)
	if left == 0 or right == 0 or size.x < 2 or size.y < 2 or size.x > MAX_WIDTH or size.y > MAX_HEIGHT:
		return Rect2i()
	var area := Rect2i(start - Vector2i(left - 1, above - 1), size)
	if _open_edges(world, area) > 0 or _has_walls_inside(world, area):
		return Rect2i()
	return area


func sync(world: BlockWorld, recycler: Vector2i) -> void:
	_air_cells.clear()
	_openings = 0
	_pumping = false
	var start := recycler + Vector2i.UP
	if not bounds.has_point(start) or BlockWorld.is_airtight(world.material_at(start)):
		return
	_air_cells[start] = true
	var frontier: Array[Vector2i] = [start]
	var index := 0
	var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	while index < frontier.size():
		var cell := frontier[index]
		index += 1
		for direction: Vector2i in directions:
			var next := cell + direction
			if _air_cells.has(next) or BlockWorld.is_airtight(world.material_at(next)):
				continue
			if bounds.has_point(next):
				_air_cells[next] = true
				frontier.append(next)
			else:
				_openings += 1
	_pumping = sealed() and world.material_at(recycler) == B.RECYCLER


func contains(cell: Vector2i) -> bool:
	return _air_cells.has(cell)


func sealed() -> bool:
	return _openings == 0


func advance_to(now: float) -> void:
	var seconds := maxf(0.0, now - _time)
	_time = now
	if _openings > 0:
		air = CabinAtmosphere.vent(air, _openings, seconds)
	elif _pumping:
		air = move_toward(air, SurvivalState.CABIN_PRESSURE, seconds * CabinAtmosphere.PUMP_RATE)


func breathable() -> bool:
	return air >= CabinAtmosphere.BREATHABLE_PRESSURE


func condition() -> String:
	if _openings > 0:
		return "Habitat venting"
	if _pumping and air < SurvivalState.CABIN_PRESSURE:
		return "Habitat breathable" if breathable() else "Habitat filling"
	return "Habitat air" if breathable() else "Habitat offline"


func snapshot() -> Dictionary:
	return {"bounds": bounds, "air": air, "time": _time}


static func from_snapshot(data: Dictionary, world: BlockWorld, recycler: Vector2i, now: float) -> HabitatRoom:
	var room := HabitatRoom.new(data.bounds, data.time)
	room.air = data.air
	room.sync(world, recycler)
	room.advance_to(now)
	return room


static func valid_snapshot(data: Variant, recycler: Vector2i, elapsed: float) -> bool:
	if not data is Dictionary:
		return false
	var area: Variant = data.get("bounds")
	if not area is Rect2i or area.size.x < 2 or area.size.x > MAX_WIDTH or area.size.y < 2 or area.size.y > MAX_HEIGHT:
		return false
	if area.end.y != recycler.y or recycler.x < area.position.x or recycler.x >= area.end.x:
		return false
	var air_value: Variant = data.get("air")
	var time: Variant = data.get("time")
	return _valid_level(air_value, SurvivalState.CABIN_PRESSURE) and _valid_level(time, elapsed)


static func _valid_level(value: Variant, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0.0 and value <= maximum


static func _wall_distance(world: BlockWorld, start: Vector2i, direction: Vector2i, limit: int) -> int:
	for distance in range(1, limit + 1):
		if BlockWorld.is_airtight(world.material_at(start + direction * distance)):
			return distance
	return 0


static func _open_edges(world: BlockWorld, area: Rect2i) -> int:
	var leaks := 0
	for x in range(area.position.x, area.end.x):
		leaks += int(not BlockWorld.is_airtight(world.material_at(Vector2i(x, area.position.y - 1))))
		leaks += int(not BlockWorld.is_airtight(world.material_at(Vector2i(x, area.end.y))))
	for y in range(area.position.y, area.end.y):
		leaks += int(not BlockWorld.is_airtight(world.material_at(Vector2i(area.position.x - 1, y))))
		leaks += int(not BlockWorld.is_airtight(world.material_at(Vector2i(area.end.x, y))))
	return leaks


static func _has_walls_inside(world: BlockWorld, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if BlockWorld.is_airtight(world.material_at(Vector2i(x, y))):
				return true
	return false
