class_name CabinAtmosphere
extends RefCounted

const BREATHABLE_PRESSURE := 60.0
const FLOW_CUTOFF := 5.0
const LEAK_RATE := 0.042
const PUMP_RATE := 8.0
const FLOW_REACH := 10.0 * BlockWorld.TILE_SIZE
const FLOW_SPEED := 265.0

var pressure := float(SurvivalState.CABIN_PRESSURE)
var breaches: Array[Vector2i] = []


func sync(world: BlockWorld) -> void:
	breaches = world.station_breaches()


func advance(seconds: float) -> void:
	if breaches.is_empty():
		pressure = move_toward(pressure, SurvivalState.CABIN_PRESSURE, seconds * PUMP_RATE)
	elif pressure > 0.0:
		pressure *= exp(-LEAK_RATE * mini(breaches.size(), 6) * seconds)
		if pressure < 0.25:
			pressure = 0.0


func airflow_at(point: Vector2, origin: Vector2i) -> Vector2:
	if pressure <= FLOW_CUTOFF or breaches.is_empty():
		return Vector2.ZERO
	var position := point + Vector2(origin) * BlockWorld.TILE_SIZE
	if not BlockWorld.STATION_CABIN.has_point(BlockWorld.cell_at(position)):
		return Vector2.ZERO
	var flow := Vector2.ZERO
	for cell in breaches:
		var offset := (Vector2(cell) + Vector2.ONE * 0.5) * BlockWorld.TILE_SIZE - position
		var distance := offset.length()
		if distance < FLOW_REACH:
			flow += offset.normalized() * (1.0 - distance / FLOW_REACH)
	return flow.limit_length(1.0) * FLOW_SPEED * (pressure / SurvivalState.CABIN_PRESSURE)
