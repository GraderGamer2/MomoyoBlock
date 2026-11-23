class_name HabitatRoom
extends RefCounted

const MAX_WIDTH := 16
const MAX_HEIGHT := 10
const STANDARD_VOLUME := 96.0
const FUEL_DURATION := 90.0
const GENERATOR_OUTPUT := 2.0
const RECYCLER_DRAW := 1.0
const BATTERY_CAPACITY := 120.0
const RECYCLER_BUFFER := 30.0
const AIR_LOSS_WITHOUT_POWER := 0.75
const B := BlockWorld.Block

var bounds: Rect2i
var air := 0.0
var charge := 0.0
var fuel_seconds := 0.0
var solar_output := 0.0
var solar_panels := 0
var _time := 0.0
var _openings := 0
var _has_recycler := false
var _has_generator := false
var _charge_capacity := 0.0
var _generator_cell: Variant = null
var _air_cells: Dictionary[Vector2i, bool] = {}


func _init(area: Rect2i, now: float) -> void:
	bounds = area
	_time = now


static func survey(world: BlockWorld, recycler: Vector2i) -> Rect2i:
	var area: Rect2i = survey_from(world, recycler + Vector2i.UP).get("bounds", Rect2i())
	return area if area.end.y == recycler.y else Rect2i()


static func survey_from(world: BlockWorld, start: Vector2i) -> Dictionary:
	if BlockWorld.is_airtight(world.material_at(start)):
		return {"issue": "Leave the tile above the equipment clear."}
	var left := _wall_distance(world, start, Vector2i.LEFT, MAX_WIDTH)
	var right := _wall_distance(world, start, Vector2i.RIGHT, MAX_WIDTH)
	var above := _wall_distance(world, start, Vector2i.UP, MAX_HEIGHT)
	var below := _wall_distance(world, start, Vector2i.DOWN, MAX_HEIGHT)
	var size := Vector2i(left + right - 1, above + below - 1)
	if left == 0 or right == 0 or size.x < 2 or size.x > MAX_WIDTH:
		return {"issue": "Fit sealed side walls around an interior 2 to 16 tiles wide."}
	if above == 0 or below == 0 or size.y < 2 or size.y > MAX_HEIGHT:
		return {"issue": "Fit a sealed floor and roof around an interior 2 to 10 tiles high."}
	var area := Rect2i(start - Vector2i(left - 1, above - 1), size)
	var gap := _shell_gap(world, area)
	if not gap.is_empty():
		return {"issue": gap}
	if _has_walls_inside(world, area):
		return {"issue": "Keep each sealed room rectangular. Put airlocks in the side walls."}
	return {"bounds": area}


func sync(world: BlockWorld, floor_anchor: Vector2i) -> void:
	_air_cells.clear()
	_openings = 0
	var start := floor_anchor + Vector2i.UP
	if BlockWorld.is_airtight(world.material_at(start)):
		for x in range(bounds.position.x, bounds.end.x):
			var candidate := Vector2i(x, bounds.end.y - 1)
			if not BlockWorld.is_airtight(world.material_at(candidate)):
				start = candidate
				break
	if bounds.has_point(start) and not BlockWorld.is_airtight(world.material_at(start)):
		_trace_air(world, start)
	_sync_power(world)


func _trace_air(world: BlockWorld, start: Vector2i) -> void:
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


func _sync_power(world: BlockWorld) -> void:
	_has_recycler = false
	_has_generator = false
	_charge_capacity = 0.0
	var recycler_buffer := 0.0
	for x in range(bounds.position.x, bounds.end.x):
		var tile := Vector2i(x, bounds.end.y)
		match world.material_at(tile):
			B.RECYCLER:
				_has_recycler = _has_recycler or contains(tile + Vector2i.UP)
				recycler_buffer = RECYCLER_BUFFER
			B.GENERATOR:
				_has_generator = true
			B.BATTERY:
				_charge_capacity += BATTERY_CAPACITY
	_charge_capacity += recycler_buffer
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


static func find_recycler(world: BlockWorld, area: Rect2i) -> Variant:
	for x in range(area.position.x, area.end.x):
		var cell := Vector2i(x, area.end.y)
		if world.material_at(cell) == B.RECYCLER:
			return cell
	return null


static func side_airlocks(world: BlockWorld, area: Rect2i) -> Array[Vector2i]:
	var locks: Array[Vector2i] = []
	for x: int in [area.position.x - 1, area.end.x]:
		for y in range(area.position.y, area.end.y - 1):
			var panel := Vector2i(x, y)
			if world.material_at(panel) == B.AIRLOCK and world.material_at(panel + Vector2i.DOWN) == B.AIRLOCK:
				locks.append(panel)
	return locks


func connects_at(panel: Vector2i) -> bool:
	var inside := panel + (Vector2i.RIGHT if panel.x < bounds.position.x else Vector2i.LEFT)
	return contains(inside) and contains(inside + Vector2i.DOWN)


func refuel(cell: Vector2i) -> void:
	_generator_cell = cell
	fuel_seconds = FUEL_DURATION


func keep_record(world: BlockWorld) -> bool:
	return (sealed() and not _air_cells.is_empty()) or _charge_capacity > 0.0 or _has_generator \
			or air > 0.0 or powered() or not side_airlocks(world, bounds).is_empty()


func powered() -> bool:
	return fuel_seconds > 0.0 or charge > 0.0


func recycles_air() -> bool:
	return sealed() and _has_recycler


func advance_to(now: float) -> void:
	advance_network([self], now)


static func advance_network(rooms: Array, now: float) -> void:
	var last_time := 0.0
	for room: HabitatRoom in rooms:
		last_time = maxf(last_time, room._time)
	var seconds := now - last_time
	if seconds <= 0.0:
		return
	var recycling := false
	var volume := 0
	var solar := 0.0
	for room: HabitatRoom in rooms:
		if room._time < last_time:
			room.advance_to(last_time)
		room._time = now
		solar += room.solar_output
		recycling = recycling or room.recycles_air()
		if room.sealed():
			volume += room._air_cells.size()
	var burn_rate := maxf(0.0, 1.0 - solar / RECYCLER_DRAW)
	var generator_time := 0.0
	var generated_charge := 0.0
	if burn_rate > 0.0:
		for room: HabitatRoom in rooms:
			var burned := minf(seconds * burn_rate, room.fuel_seconds)
			room.fuel_seconds -= burned
			if room.fuel_seconds == 0.0:
				room._generator_cell = null
			generator_time = maxf(generator_time, burned / burn_rate)
			generated_charge += burned * GENERATOR_OUTPUT
	# Solar covers demand first. A running generator makes up the deficit and can charge the reserve.
	var demand := RECYCLER_DRAW if recycling else 0.0
	var deficit := maxf(0.0, demand - solar)
	var pumping_for := generator_time if recycling else 0.0
	var surplus := generated_charge - deficit * generator_time + maxf(0.0, solar - demand) * seconds
	for room: HabitatRoom in rooms:
		var stored := minf(room._charge_capacity - room.charge, surplus)
		room.charge += stored
		surplus -= stored
	var limited_power := 0.0
	if recycling:
		if deficit == 0.0:
			pumping_for = seconds
		else:
			for room: HabitatRoom in rooms:
				var discharged := minf(room.charge, deficit * maxf(0.0, seconds - pumping_for))
				room.charge -= discharged
				pumping_for += discharged / deficit
			limited_power = solar / demand
	var pump_rate := CabinAtmosphere.PUMP_RATE * minf(1.0, STANDARD_VOLUME / maxi(1, volume))
	for room: HabitatRoom in rooms:
		room._advance_air(seconds, pumping_for, pump_rate, limited_power)


func _advance_air(seconds: float, pumping_for: float, pump_rate: float, limited_power: float) -> void:
	if _openings > 0:
		air = CabinAtmosphere.vent(air, _openings, seconds)
		return
	if _air_cells.is_empty():
		pumping_for = 0.0
		limited_power = 0.0
	air = move_toward(air, SurvivalState.CABIN_PRESSURE, pumping_for * pump_rate)
	# A partly powered recycler can sustain only part of normal cabin pressure.
	var target := SurvivalState.CABIN_PRESSURE * limited_power
	var rate := pump_rate * limited_power if air < target else AIR_LOSS_WITHOUT_POWER * (1.0 - limited_power)
	air = move_toward(air, target, maxf(0.0, seconds - pumping_for) * rate)


func breathable() -> bool:
	return air >= CabinAtmosphere.BREATHABLE_PRESSURE


func condition(recycling: bool, supplied: bool, solar: float) -> String:
	if _openings > 0:
		return "Habitat venting"
	if recycling and not supplied and solar > 0.0:
		return "Habitat on limited solar"
	if recycling and supplied and air < SurvivalState.CABIN_PRESSURE:
		return "Habitat breathable" if breathable() else "Habitat filling"
	if breathable():
		return "Habitat air" if recycling and supplied else "Habitat on reserve air"
	return "Habitat needs power" if recycling else "Habitat offline"


static func network_reading(rooms: Array, solar: float) -> String:
	var fuel := 0.0
	var reserve := 0.0
	var capacity := 0.0
	var has_generator := false
	var panels := 0
	for room: HabitatRoom in rooms:
		fuel = maxf(fuel, room.fuel_seconds)
		reserve += room.charge
		capacity += room._charge_capacity
		has_generator = has_generator or room._has_generator
		panels += room.solar_panels
	var battery := "Battery %d/%d s" % [ceili(reserve), roundi(capacity)]
	var reading := "Power off · Load fuel" if has_generator else "Power off · Fit a generator"
	if fuel > 0.0:
		reading = "Fuel %d s · %s" % [ceili(fuel), battery]
	elif reserve > 0.0 or solar > 0.0:
		reading = battery
	elif panels > 0:
		reading = "Power off · Panels shaded"
	if rooms.size() > 1:
		reading = "%d rooms · %s" % [rooms.size(), reading]
	if panels > 0:
		reading += "\nSolar %.2f u/s" % solar
	return reading


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


static func _shell_gap(world: BlockWorld, area: Rect2i) -> String:
	for x in range(area.position.x, area.end.x):
		if not BlockWorld.is_airtight(world.material_at(Vector2i(x, area.position.y - 1))):
			return "Seal every roof tile with alloy or pressure glass."
		if not BlockWorld.is_airtight(world.material_at(Vector2i(x, area.end.y))):
			return "Seal the entire floor with alloy, pressure glass, or habitat equipment."
	for y in range(area.position.y, area.end.y):
		var left_sealed := BlockWorld.is_airtight(world.material_at(Vector2i(area.position.x - 1, y)))
		var right_sealed := BlockWorld.is_airtight(world.material_at(Vector2i(area.end.x, y)))
		if not left_sealed or not right_sealed:
			return "Seal both side walls. Stack two airlock panels for an entrance."
	return ""


static func _has_walls_inside(world: BlockWorld, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if BlockWorld.is_airtight(world.material_at(Vector2i(x, y))):
				return true
	return false
