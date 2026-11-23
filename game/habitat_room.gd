class_name HabitatRoom
extends RefCounted

const MAX_WIDTH := 16
const MAX_HEIGHT := 10
const STANDARD_VOLUME := 96.0
const FUEL_DURATION := 90.0
const GENERATOR_OUTPUT := 2.0
const BATTERY_CAPACITY := 120.0
const RECYCLER_BUFFER := 30.0
const AIR_LOSS_WITHOUT_POWER := 0.75
const B := BlockWorld.Block

var bounds: Rect2i
var air := 0.0
var charge := 0.0
var fuel_seconds := 0.0
var _time := 0.0
var _openings := 0
var _can_pump := false
var _has_generator := false
var _charge_capacity := 0.0
var _generator_cell: Variant = null
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
	_can_pump = false
	var recycler_installed := world.material_at(recycler) == B.RECYCLER
	_sync_power(world, recycler_installed)
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
	_can_pump = sealed() and recycler_installed


func _sync_power(world: BlockWorld, recycler_installed: bool) -> void:
	_has_generator = false
	_charge_capacity = RECYCLER_BUFFER if recycler_installed else 0.0
	for x in range(bounds.position.x, bounds.end.x):
		match world.material_at(Vector2i(x, bounds.end.y)):
			B.GENERATOR:
				_has_generator = true
			B.BATTERY:
				_charge_capacity += BATTERY_CAPACITY
	charge = minf(charge, _charge_capacity)
	if _generator_cell != null and (not floor_contains(_generator_cell) or world.material_at(_generator_cell) != B.GENERATOR):
		_generator_cell = null
		fuel_seconds = 0.0


func contains(cell: Vector2i) -> bool:
	return _air_cells.has(cell)


func sealed() -> bool:
	return _openings == 0


func floor_contains(cell: Vector2i) -> bool:
	return cell.y == bounds.end.y and bounds.has_point(cell + Vector2i.UP)


func refuel(cell: Vector2i) -> void:
	_generator_cell = cell
	fuel_seconds = FUEL_DURATION


func has_reserves() -> bool:
	return air > 0.0 or powered()


func powered() -> bool:
	return fuel_seconds > 0.0 or charge > 0.0


func advance_to(now: float) -> void:
	var seconds := now - _time
	if seconds <= 0.0:
		return
	_time = now
	# A working recycler draws one unit per second. Any surplus charges the room's batteries.
	var generated_for := minf(seconds, fuel_seconds)
	fuel_seconds -= generated_for
	if fuel_seconds == 0.0:
		_generator_cell = null
	var draw := 1.0 if _can_pump else 0.0
	charge = minf(_charge_capacity, charge + generated_for * (GENERATOR_OUTPUT - draw))
	var pumping_for := 0.0
	if _can_pump:
		var battery_time := minf(seconds - generated_for, charge)
		charge -= battery_time
		pumping_for = generated_for + battery_time
	if _openings > 0:
		air = CabinAtmosphere.vent(air, _openings, seconds)
		return
	var pump_rate := CabinAtmosphere.PUMP_RATE * minf(1.0, STANDARD_VOLUME / maxi(1, _air_cells.size()))
	air = move_toward(air, SurvivalState.CABIN_PRESSURE, pumping_for * pump_rate)
	air = move_toward(air, 0.0, maxf(0.0, seconds - pumping_for) * AIR_LOSS_WITHOUT_POWER)


func breathable() -> bool:
	return air >= CabinAtmosphere.BREATHABLE_PRESSURE


func condition() -> String:
	if _openings > 0:
		return "Habitat venting"
	if _can_pump and powered() and air < SurvivalState.CABIN_PRESSURE:
		return "Habitat breathable" if breathable() else "Habitat filling"
	if breathable():
		return "Habitat air" if _can_pump and powered() else "Habitat on reserve air"
	return "Habitat needs power" if _can_pump else "Habitat offline"


func power_reading() -> String:
	var battery := "Battery %d/%d s" % [ceili(charge), roundi(_charge_capacity)]
	if fuel_seconds > 0.0:
		return "Fuel %d s · %s" % [ceili(fuel_seconds), battery]
	if charge > 0.0:
		return battery
	return "Power off · Load fuel" if _has_generator else "Power off · Fit a generator"


func snapshot() -> Dictionary:
	return {
		"bounds": bounds, "air": air, "time": _time,
		"charge": charge, "fuel_seconds": fuel_seconds, "generator": _generator_cell,
	}


static func from_snapshot(data: Dictionary, world: BlockWorld, recycler: Vector2i, now: float) -> HabitatRoom:
	var room := HabitatRoom.new(data.bounds, data.time)
	room.air = data.air
	room.charge = data.charge
	room.fuel_seconds = data.fuel_seconds
	room._generator_cell = data.generator
	room.sync(world, recycler)
	room.advance_to(now)
	return room


static func valid_snapshot(data: Variant, recycler: Vector2i, elapsed: float, includes_power := true) -> bool:
	if not data is Dictionary:
		return false
	var area: Variant = data.get("bounds")
	if not area is Rect2i or area.size.x < 2 or area.size.x > MAX_WIDTH or area.size.y < 2 or area.size.y > MAX_HEIGHT:
		return false
	if area.end.y != recycler.y or recycler.x < area.position.x or recycler.x >= area.end.x:
		return false
	var air_value: Variant = data.get("air")
	var time: Variant = data.get("time")
	if not _valid_level(air_value, SurvivalState.CABIN_PRESSURE) or not _valid_level(time, elapsed):
		return false
	if not includes_power:
		return true
	var fuel: Variant = data.get("fuel_seconds")
	if not _valid_level(data.get("charge"), RECYCLER_BUFFER + float(area.size.x) * BATTERY_CAPACITY) \
			or not _valid_level(fuel, FUEL_DURATION) or not data.has("generator"):
		return false
	var generator: Variant = data.generator
	if fuel == 0.0:
		return generator == null
	return generator is Vector2i and generator.y == area.end.y and area.has_point(generator + Vector2i.UP)


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
