class_name MomoyoGame
extends Node2D

signal chart_requested

const REACH_SQUARED := 126.0 * 126.0
const BEACON_RANGE_SQUARED := 54.0 * 54.0
const CURSOR_VALID := Color("#f9d688")
const CURSOR_OUTSIDE := Color(0.91, 0.94, 0.97, 0.3)

var sector := Vector2i.ZERO
var surface := BlockWorld.new(BlockWorld.Region.SURFACE, Vector2i.ZERO)
var station := BlockWorld.new(BlockWorld.Region.STATION)
var survival := SurvivalState.new()
var inventory := PackedInt32Array([12, 8, 30, 0])
var region := BlockWorld.Region.SURFACE
var selected := 0

var _planet_journals: Dictionary[Vector2i, Dictionary] = {}
var _save := ExpeditionSave.new()
var _in_transit := false
var _tick_progress := 0.0

@onready var terrain: ActiveTerrain = $Terrain
@onready var explorer: Explorer = $Explorer
@onready var _camera: Camera2D = $Explorer/Camera
@onready var _cursor: Line2D = $Target
@onready var _wildlife: SurfaceWildlife = $Wildlife
@onready var _sky: Horizon = $Backdrop/Sky
@onready var _weather: WeatherLayer = $Weather/Front
@onready var _hud: FlightHUD = $HUD


func _ready() -> void:
	var state := _save.read()
	var point := BlockWorld.pad_position()
	if not state.is_empty():
		region = state.region
		point = state.position
		inventory = state.inventory
		selected = state.selected
		_planet_journals.assign(state.planets)
		_load_planet(state.sector)
		station.restore_journal(state.station)
		survival.restore(state.vitals)
	elif _save.read_error != OK:
		_hud.show_status("Existing save could not be loaded. It has been kept.", false)
	$Beacon.position = Vector2(BlockWorld.pad_position().x, BlockWorld.PAD_ROW * BlockWorld.TILE_SIZE)
	_open_region(region, point)
	_hud.show_inventory(inventory, selected)


func _physics_process(delta: float) -> void:
	if _in_transit:
		return
	var bounds := terrain.world.bounds
	var px := float(BlockWorld.TILE_SIZE)
	if explorer.position.y >= bounds.end.y * px - Explorer.HALF_SIZE.y - 1.0:
		survival.health = maxf(0.0, survival.health - 25.0)
		if survival.health == 0.0:
			_rescue()
		else:
			_open_region(region, BlockWorld.pad_position())
			_hud.show_status("Recovered at the beacon. Impact cost 25 health.", false)
	explorer.position.x = clampf(explorer.position.x, bounds.position.x * px + Explorer.HALF_SIZE.x,
			bounds.end.x * px - Explorer.HALF_SIZE.x)
	terrain.stream_around(explorer.position)
	_wildlife.follow(BlockWorld.cell_at(explorer.position).x)
	_hud.show_travel(region, _at_beacon(), surface.planet.title())
	_update_target()

	_tick_progress += delta
	if _tick_progress >= SurvivalState.TICK:
		var exposed := _weather_name()
		survival.advance(_tick_progress, breathable_here(), not exposed.is_empty() and not surface.planet.details.breathable)
		_tick_progress = 0.0
		if survival.health == 0.0:
			_rescue()
		_update_survival_display()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_world"):
		save_expedition()
		return
	if _in_transit:
		return
	if event.is_action_pressed("travel"):
		begin_travel()
	elif event.is_action_pressed("star_chart") and can_choose_planet():
		chart_requested.emit()
	elif event.is_action_pressed("gather"):
		gather_nearby()
	elif event.is_action_pressed("eat"):
		if survival.eat():
			_update_survival_display()
		else:
			_hud.show_status("No rations left" if survival.food == 0 else "Hunger is full")
	elif event.is_action_pressed("drink"):
		if survival.drink():
			_update_survival_display()
		else:
			_hud.show_status("No water left" if survival.water == 0 else "Thirst is full")
	elif event.is_action_pressed("mine"):
		mine(BlockWorld.cell_at(get_global_mouse_position()))
	elif event.is_action_pressed("place"):
		place(BlockWorld.cell_at(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			selected = event.physical_keycode - KEY_1
			_hud.show_inventory(inventory, selected)


func mine(cell: Vector2i) -> bool:
	if not _within_reach(cell):
		return false
	var material := terrain.block_at(cell)
	if material == BlockWorld.Block.GRASS:
		material = BlockWorld.Block.SOIL
	var slot := BlockWorld.BUILD_MATERIALS.find(material)
	if slot < 0 or inventory[slot] == 2147483647:
		return false
	terrain.set_block(cell, BlockWorld.Block.EMPTY)
	inventory[slot] += 1
	_hud.show_inventory(inventory, selected)
	return true


func place(cell: Vector2i) -> bool:
	if not _within_reach(cell) or terrain.block_at(cell) != BlockWorld.Block.EMPTY or inventory[selected] <= 0:
		return false
	var tile_rect := Rect2(Vector2(cell * BlockWorld.TILE_SIZE), Vector2.ONE * BlockWorld.TILE_SIZE)
	if tile_rect.intersects(explorer.body_rect()):
		return false
	terrain.set_block(cell, BlockWorld.BUILD_MATERIALS[selected])
	inventory[selected] -= 1
	_hud.show_inventory(inventory, selected)
	return true


func gather_nearby() -> bool:
	var cell := terrain.nearest_forage(explorer.position, REACH_SQUARED)
	var kind: int = terrain.forage.markers.get(cell, 0)
	if kind == 0:
		_hud.show_status("No food or water within reach", false)
		return false
	if kind == 1:
		if survival.food >= SurvivalState.MAX_SUPPLIES:
			_hud.show_status("Rations are full")
			return false
		survival.food += 1
		_hud.show_status("Gathered %s" % surface.planet.details.flora)
	else:
		if survival.water >= SurvivalState.MAX_SUPPLIES:
			_hud.show_status("Water supplies are full")
			return false
		survival.water += 1
		_hud.show_status("Gathered %s" % surface.planet.details.water)
	terrain.harvest(cell)
	_update_survival_display()
	return true


func breathable_here() -> bool:
	return _at_beacon() or (region == BlockWorld.Region.SURFACE and surface.planet.details.breathable)


func can_choose_planet() -> bool:
	return region == BlockWorld.Region.STATION and _at_beacon() and not _in_transit


func begin_travel() -> bool:
	return _travel(sector)


func land_at(address: Vector2i) -> bool:
	return can_choose_planet() and _travel(address)


func save_expedition(show_feedback := true) -> bool:
	_remember_planet()
	var result := _save.write({
		"format": ExpeditionSave.FORMAT, "world_revision": BlockWorld.WORLD_REVISION,
		"region": region, "sector": sector, "position": explorer.position,
		"inventory": inventory, "selected": selected, "planets": _planet_journals,
		"station": station.journal(), "vitals": survival.snapshot(),
	})
	if show_feedback:
		_hud.show_status("Expedition saved" if result == OK else "Could not save the expedition", result == OK)
	return result == OK


func _travel(address: Vector2i) -> bool:
	if _in_transit or not _at_beacon():
		return false
	var destination := BlockWorld.Region.STATION if region == BlockWorld.Region.SURFACE else BlockWorld.Region.SURFACE
	_in_transit = true
	explorer.set_physics_process(false)
	_cursor.hide()
	var planet_name := surface.planet.title() if address == sector else PlanetProfile.new(address).title()
	_hud.set_transit_route(destination, planet_name)
	_hud.transit.show()
	var flight := create_tween()
	flight.tween_property(_hud.transit, "modulate:a", 1.0, 0.35)
	flight.tween_interval(0.50)
	flight.tween_callback(_arrive.bind(destination, address))
	flight.tween_property(_hud.transit, "modulate:a", 0.0, 0.35)
	flight.tween_callback(_finish_travel)
	return true


func _arrive(destination: int, address: Vector2i) -> void:
	if address != sector:
		_remember_planet()
		_load_planet(address)
	_open_region(destination, BlockWorld.pad_position())


func _finish_travel() -> void:
	_hud.transit.hide()
	_in_transit = false
	explorer.set_physics_process(true)
	save_expedition()


func _open_region(next_region: int, point: Vector2) -> void:
	region = next_region
	explorer.position = point
	explorer.velocity = Vector2.ZERO
	explorer.gravity = surface.planet.details.gravity if region == BlockWorld.Region.SURFACE else 510.0
	explorer.force_update_transform()
	terrain.open_region(surface if region == BlockWorld.Region.SURFACE else station, point)
	_wildlife.show_local_life(terrain, surface.planet if region == BlockWorld.Region.SURFACE else null)
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	_sky.show_region(region, surface.planet)
	_hud.show_region(region, surface.planet)
	_hud.show_travel(region, _at_beacon(), surface.planet.title())
	_update_survival_display()


func _rescue() -> void:
	for slot in inventory.size():
		inventory[slot] >>= 1
	survival.restore_after_rescue()
	_open_region(region, BlockWorld.pad_position())
	_hud.show_inventory(inventory, selected)
	save_expedition(false)
	_hud.show_status("Rescued at the beacon. Half your blocks were lost.", false)


func _weather_name() -> String:
	if region == BlockWorld.Region.SURFACE and surface.planet.weather_active(survival.elapsed):
		return surface.planet.details.weather
	return ""


func _update_survival_display() -> void:
	var front := _weather_name()
	_weather.set_front(front)
	var air := "Breathable air" if breathable_here() else "Suit oxygen in use"
	if _at_beacon() and (region == BlockWorld.Region.STATION or not surface.planet.details.breathable):
		air = "Beacon air refill"
	var weather_text := front if not front.is_empty() else "Clear"
	_hud.show_survival(survival, air, weather_text if region == BlockWorld.Region.SURFACE else "Orbit")


func _remember_planet() -> void:
	if surface.edits.is_empty() and surface.harvested.is_empty():
		_planet_journals.erase(sector)
	else:
		_planet_journals[sector] = surface.journal()


func _load_planet(address: Vector2i) -> void:
	sector = address
	surface = BlockWorld.new(BlockWorld.Region.SURFACE, sector)
	surface.restore_journal(_planet_journals.get(sector, {}))


func _at_beacon() -> bool:
	return explorer.position.distance_squared_to(BlockWorld.pad_position()) <= BEACON_RANGE_SQUARED


func _within_reach(cell: Vector2i) -> bool:
	var middle := (Vector2(cell) + Vector2(0.5, 0.5)) * BlockWorld.TILE_SIZE
	return terrain.is_editable(cell) and explorer.position.distance_squared_to(middle) <= REACH_SQUARED


func _update_target() -> void:
	var cell := BlockWorld.cell_at(get_global_mouse_position())
	var point := Vector2(cell * BlockWorld.TILE_SIZE)
	var tint := CURSOR_VALID if _within_reach(cell) else CURSOR_OUTSIDE
	if _cursor.position != point:
		_cursor.position = point
	if _cursor.default_color != tint:
		_cursor.default_color = tint
	if not _cursor.visible:
		_cursor.show()
