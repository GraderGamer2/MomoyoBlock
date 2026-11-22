class_name MomoyoGame
extends Node2D

signal chart_requested

const REACH := 2.0 * BlockWorld.TILE_SIZE
const REACH_SQUARED := REACH * REACH
const BEACON_RANGE_SQUARED := 54.0 * 54.0
const CURSOR_VALID := Color("#f9d688")
const CURSOR_OUTSIDE := Color(0.91, 0.94, 0.97, 0.3)

var universe_seed := 0
var sector := Vector2i.ZERO
var surface: BlockWorld
var station := BlockWorld.new(BlockWorld.Region.STATION)
var survival := SurvivalState.new()
var inventory := PackedInt32Array([12, 8, 30, 0])
var region := BlockWorld.Region.SURFACE
var selected := 0

var _planet_journals: Dictionary[Vector2i, PackedByteArray] = {}
var _station_journal := PackedByteArray()
var _near_beacon := false
var save_filename := ExpeditionSave.DEFAULT_FILE
var _save: ExpeditionSave
var _in_transit := false
var _tick_progress := 0.0

@onready var terrain: ActiveTerrain = $Terrain
@onready var explorer: Explorer = $Explorer
@onready var _camera: Camera2D = $Explorer/Camera
@onready var _cursor: Line2D = $Target
@onready var _wildlife: SurfaceWildlife = $Wildlife
@onready var _sky: Horizon = $Backdrop/Sky
@onready var _beacon: Node2D = $Beacon
@onready var _weather: WeatherLayer = $Backdrop/Front
@onready var _hud: FlightHUD = $HUD


func _ready() -> void:
	_save = ExpeditionSave.new(save_filename)
	var state := _save.read()
	var point := BlockWorld.pad_position()
	var origin := Vector2i.ZERO
	if not state.is_empty():
		universe_seed = state.universe_seed
		region = state.region
		point = state.position
		origin = state.origin
		inventory = state.inventory
		selected = state.selected
		_planet_journals.assign(state.planets)
		_load_planet(state.sector)
		_station_journal = state.station
		station.restore_journal(TerrainJournal.unpack(_station_journal, false))
		survival.restore(state.vitals)
	elif _save.read_error == OK:
		universe_seed = (randi() << 32) | randi()
		if universe_seed == 0:
			universe_seed = 1
		_load_planet(Vector2i(randi_range(-999999, 999999), randi_range(-999999, 999999)))
	else:
		_load_planet(Vector2i.ZERO)
		_hud.show_status("Existing save could not be loaded. It has been kept.", false)
	_open_region(region, point, origin)
	_hud.show_inventory(inventory, selected)
	if state.is_empty() and _save.read_error == OK and not save_expedition(false):
		_hud.show_status("Could not save the new expedition. Press F5 to retry.", false)


func _physics_process(delta: float) -> void:
	if _in_transit:
		return
	var rebased := _rebase_explorer()
	var cell := terrain.world_cell(explorer.position)
	if region == BlockWorld.Region.STATION and cell.y >= BlockWorld.STATION_RESCUE_ROW:
		survival.health = maxf(0.0, survival.health - 25.0)
		if survival.health == 0.0:
			_rescue()
		else:
			_open_region(region, BlockWorld.pad_position())
			_hud.show_status("Recovered at the beacon. Impact cost 25 health.", false)
		cell = terrain.world_cell(explorer.position)
	terrain.stream_around(explorer.position)
	_wildlife.follow(cell.x, rebased)
	if _near_beacon != _at_beacon():
		_update_travel()
	_update_target()

	_tick_progress += delta
	if _tick_progress >= SurvivalState.TICK:
		var front := _weather_name(survival.elapsed + _tick_progress)
		survival.advance(_tick_progress, breathable_here(), PlanetProfile.harsh_weather(front))
		_tick_progress = 0.0
		if survival.health == 0.0:
			_rescue()
		else:
			_apply_conditions(front)
			_update_travel()


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
		mine(terrain.world_cell(get_global_mouse_position()))
	elif event.is_action_pressed("place"):
		place(terrain.world_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			selected = event.physical_keycode - KEY_1
			_hud.show_inventory(inventory, selected)


func mine(cell: Vector2i) -> bool:
	if not _within_reach(cell):
		_feedback_on_distant_action(cell)
		return false
	var material := BlockWorld.mined_material(terrain.block_at(cell))
	var slot := BlockWorld.BUILD_MATERIALS.find(material)
	if slot < 0 or inventory[slot] == 2147483647:
		return false
	terrain.set_block(cell, BlockWorld.Block.EMPTY)
	inventory[slot] += 1
	_hud.show_inventory(inventory, selected)
	return true


func place(cell: Vector2i) -> bool:
	if not _within_reach(cell):
		_feedback_on_distant_action(cell)
		return false
	if terrain.block_at(cell) != BlockWorld.Block.EMPTY or inventory[selected] <= 0:
		return false
	var tile_rect := Rect2(terrain.scene_point(cell), Vector2.ONE * BlockWorld.TILE_SIZE)
	if tile_rect.intersects(explorer.body_rect()):
		return false
	terrain.set_block(cell, BlockWorld.BUILD_MATERIALS[selected])
	inventory[selected] -= 1
	_hud.show_inventory(inventory, selected)
	return true


func gather_nearby() -> bool:
	var cell: Variant = terrain.nearest_forage(explorer.position, REACH_SQUARED)
	if cell == null:
		_hud.show_status("No food or water within reach", false)
		return false
	if terrain.forage.markers[cell] == 1:
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


func weather_forecast(planet: PlanetProfile) -> String:
	var front := planet.weather_at(survival.elapsed)
	return "Clear now" if front.is_empty() else front


func breathable_here() -> bool:
	return _at_beacon() or (region == BlockWorld.Region.SURFACE and surface.planet.details.breathable)


func can_choose_planet() -> bool:
	return region == BlockWorld.Region.STATION and _at_beacon() and not _in_transit


func begin_travel() -> bool:
	return _travel(sector)


func land_at(address: Vector2i) -> bool:
	return can_choose_planet() and _travel(address)


func save_expedition(show_feedback := true) -> bool:
	_rebase_explorer()
	_remember_planet()
	if station.journal_dirty:
		_station_journal = TerrainJournal.pack(station.edits, station.harvested)
		station.journal_dirty = false
	var revision := BlockWorld.LEGACY_REVISION if universe_seed == 0 else BlockWorld.WORLD_REVISION
	var result := _save.write({
		"format": ExpeditionSave.FORMAT, "world_revision": revision, "universe_seed": universe_seed,
		"region": region, "sector": sector, "origin": terrain.origin_cell, "position": explorer.position,
		"inventory": inventory, "selected": selected, "planets": _planet_journals,
		"station": _station_journal, "vitals": survival.snapshot(),
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
	var planet_name := surface.planet.title() if address == sector else PlanetProfile.new(address, universe_seed).title()
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


func _open_region(next_region: int, point: Vector2, origin := Vector2i.ZERO) -> void:
	region = next_region
	explorer.position = point
	explorer.velocity = Vector2.ZERO
	explorer.gravity = surface.planet.details.gravity if region == BlockWorld.Region.SURFACE else 510.0
	explorer.force_update_transform()
	terrain.open_region(surface if region == BlockWorld.Region.SURFACE else station, point, origin)
	_update_beacon()
	_wildlife.show_local_life(terrain, surface.planet if region == BlockWorld.Region.SURFACE else null)
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	_sky.show_region(region, surface.planet)
	_hud.show_region(region, surface.planet)
	_update_travel()
	_update_survival_display()


func _rescue() -> void:
	for slot in inventory.size():
		inventory[slot] >>= 1
	survival.restore_after_rescue()
	_open_region(region, BlockWorld.pad_position())
	_hud.show_inventory(inventory, selected)
	save_expedition(false)
	_hud.show_status("Rescued at the beacon. Half your blocks were lost.", false)


func _weather_name(elapsed: float) -> String:
	return surface.planet.weather_at(elapsed) if region == BlockWorld.Region.SURFACE else ""


func _update_survival_display() -> void:
	_apply_conditions(_weather_name(survival.elapsed))


func _apply_conditions(front: String) -> void:
	_weather.set_front(front, surface.planet.wind)
	var air := "Breathable air" if breathable_here() else "Suit oxygen in use"
	if _at_beacon() and (region == BlockWorld.Region.STATION or not surface.planet.details.breathable):
		air = "Beacon air refill"
	var weather_text := front if not front.is_empty() else "Clear"
	_hud.show_survival(survival, air, weather_text if region == BlockWorld.Region.SURFACE else "Orbit")


func _remember_planet() -> void:
	if not surface.journal_dirty:
		return
	var packet := TerrainJournal.pack(surface.edits, surface.harvested)
	if packet.is_empty():
		_planet_journals.erase(sector)
	else:
		_planet_journals[sector] = packet
	surface.journal_dirty = false


func _load_planet(address: Vector2i) -> void:
	sector = address
	surface = BlockWorld.new(BlockWorld.Region.SURFACE, sector, universe_seed)
	if _planet_journals.has(sector):
		surface.restore_journal(TerrainJournal.unpack(_planet_journals[sector], true))


func _rebase_explorer() -> bool:
	var shift := terrain.rebase_if_needed(explorer.position)
	if shift == Vector2.ZERO:
		return false
	explorer.position -= shift
	explorer.force_update_transform()
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	_update_beacon()
	return true


func _pad_center() -> Vector2:
	return terrain.scene_point(Vector2i(0, BlockWorld.PAD_ROW), Vector2(0.5, -15.0 / BlockWorld.TILE_SIZE))


func _update_beacon() -> void:
	_beacon.position = terrain.scene_point(Vector2i(0, BlockWorld.PAD_ROW), Vector2(0.5, 0.0))
	_beacon.visible = _beacon.position.length_squared() < float(ActiveTerrain.REBASE_DISTANCE * 2) ** 2


func _at_beacon() -> bool:
	return explorer.position.distance_squared_to(_pad_center()) <= BEACON_RANGE_SQUARED


func _update_travel() -> void:
	_near_beacon = _at_beacon()
	var direction := Vector2i(0, BlockWorld.PAD_ROW - 1) - terrain.world_cell(explorer.position)
	_hud.show_travel(region, _near_beacon, surface.planet.title(), direction)


func _within_reach(cell: Vector2i) -> bool:
	return terrain.is_editable(cell) and explorer.position.distance_squared_to(terrain.scene_point(cell, ActiveTerrain.CELL_CENTER)) <= REACH_SQUARED


func _feedback_on_distant_action(cell: Vector2i) -> void:
	if explorer.position.distance_squared_to(terrain.scene_point(cell, ActiveTerrain.CELL_CENTER)) > REACH_SQUARED:
		_hud.show_status("Move closer to reach that block", false)


func _update_target() -> void:
	var cell := terrain.world_cell(get_global_mouse_position())
	var point := terrain.scene_point(cell)
	var tint := CURSOR_VALID if _within_reach(cell) else CURSOR_OUTSIDE
	if _cursor.position != point:
		_cursor.position = point
	if _cursor.default_color != tint:
		_cursor.default_color = tint
	if not _cursor.visible:
		_cursor.show()
