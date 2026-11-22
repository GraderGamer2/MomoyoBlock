class_name MomoyoGame
extends Node2D

signal chart_requested
signal workshop_requested

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
var kit := ExpeditionKit.new()
var inventory := PackedInt32Array([12, 8, 30, 0])
var region := BlockWorld.Region.SURFACE
var selected := 0

var _planet_journals: Dictionary[Vector2i, PackedByteArray] = {}
var _station_journal := PackedByteArray()
var _near_beacon := false
var _station_sealed := true
var save_filename := ExpeditionSave.DEFAULT_FILE
var _save: ExpeditionSave
var _in_transit := false
var _tick_progress := 0.0
var _mine_cell := Vector2i.ZERO
var _mine_material := BlockWorld.Block.EMPTY
var _mine_time := 0.0
var _mine_elapsed := 0.0

@onready var terrain: ActiveTerrain = $Terrain
@onready var explorer: Explorer = $Explorer
@onready var _camera: Camera2D = $Explorer/Camera
@onready var _cursor: Line2D = $Target
@onready var _mine_progress: ProgressBar = $Target/MiningProgress
@onready var _wildlife: SurfaceWildlife = $Wildlife
@onready var _sky: Horizon = $Backdrop/Sky
@onready var _beacon: Node2D = $Beacon
@onready var _station_art: StationInterior = $StationInterior
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
		kit.restore(state.kit)
		survival.restore(state.vitals)
		if region == BlockWorld.Region.STATION and _save.loaded_format < ExpeditionSave.STATION_REFIT_FORMAT:
			point = station.station_arrival()
			origin = Vector2i.ZERO
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
			_open_region(region, _arrival_point(region))
			_hud.show_status("Recovered at the beacon. Impact cost 25 health.", false)
		cell = terrain.world_cell(explorer.position)
	terrain.stream_around(explorer.position)
	_wildlife.follow(cell.x, rebased)
	if _near_beacon != _at_beacon():
		_update_travel()
	_update_target()
	if _mine_time > 0.0:
		advance_mining(delta, terrain.world_cell(get_global_mouse_position()), Input.is_action_pressed("mine"))

	_tick_progress += delta
	if _tick_progress >= SurvivalState.TICK:
		var elapsed := _tick_progress
		_tick_progress = 0.0
		_update_survival_display(elapsed)
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
	elif event.is_action_pressed("workshop"):
		if can_craft_here():
			workshop_requested.emit()
		else:
			_hud.show_status("Get close to the beacon or Relay Nine workbench", false)
	elif event.is_action_pressed("air_canister"):
		use_air_canister()
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
		begin_mining(terrain.world_cell(get_global_mouse_position()))
	elif event.is_action_pressed("place"):
		place(terrain.world_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			selected = event.physical_keycode - KEY_1
			_hud.show_inventory(inventory, selected)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		cancel_mining()


func begin_mining(cell: Vector2i) -> bool:
	cancel_mining()
	if _in_transit or not _within_reach(cell):
		_feedback_on_distant_action(cell)
		return false
	var material := terrain.block_at(cell)
	var slot := BlockWorld.BUILD_MATERIALS.find(BlockWorld.mined_material(material))
	if slot < 0 or inventory[slot] == 2147483647:
		return false
	_mine_cell = cell
	_mine_material = material
	_mine_time = BlockWorld.mining_time(material, kit.pick)
	_mine_progress.value = 0.0
	_mine_progress.show()
	_hud.show_mining(BlockWorld.BLOCK_NAMES[material], _mine_time)
	return true


func advance_mining(delta: float, aim: Vector2i, held: bool) -> bool:
	if _mine_time == 0.0:
		return false
	if not held or aim != _mine_cell or not _within_reach(_mine_cell) or terrain.block_at(_mine_cell) != _mine_material:
		cancel_mining()
		return false
	_mine_elapsed += delta
	if _mine_elapsed < _mine_time:
		_mine_progress.value = _mine_elapsed / _mine_time
		return false

	var slot := BlockWorld.BUILD_MATERIALS.find(BlockWorld.mined_material(_mine_material))
	var cell := _mine_cell
	cancel_mining()
	terrain.set_block(cell, BlockWorld.Block.EMPTY)
	inventory[slot] += 1
	_hud.show_inventory(inventory, selected)
	_on_block_changed(cell)
	return true


func cancel_mining() -> void:
	if _mine_time <= 0.0:
		return
	_mine_time = 0.0
	_mine_elapsed = 0.0
	_mine_progress.hide()
	_hud.hide_mining()


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
	_on_block_changed(cell)
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


func breathable_here() -> bool:
	if _at_beacon():
		return true
	if region == BlockWorld.Region.STATION:
		return _in_cabin() and _station_sealed
	return surface.planet.details.breathable


func can_craft_here() -> bool:
	if _in_transit:
		return false
	if region == BlockWorld.Region.SURFACE:
		return _at_beacon()
	var workbench := terrain.scene_point(BlockWorld.STATION_WORKBENCH, ActiveTerrain.CELL_CENTER)
	return explorer.position.distance_squared_to(workbench) <= BEACON_RANGE_SQUARED


func craft(recipe: int) -> bool:
	if not can_craft_here() or not kit.craft(recipe, inventory):
		return false
	_hud.show_inventory(inventory, selected)
	_update_survival_display()
	return true


func use_air_canister() -> bool:
	if not kit.use_canister(survival):
		_hud.show_status("No spare air canisters" if kit.canisters == 0 else "Oxygen is full", false)
		return false
	_hud.show_status("Air canister used")
	_update_survival_display()
	return true


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
		"station": _station_journal, "vitals": survival.snapshot(), "kit": kit.snapshot(),
	})
	if show_feedback:
		_hud.show_status("Expedition saved" if result == OK else "Could not save the expedition", result == OK)
	return result == OK


func _travel(address: Vector2i) -> bool:
	if _in_transit or not _at_beacon():
		return false
	var destination := BlockWorld.Region.STATION if region == BlockWorld.Region.SURFACE else BlockWorld.Region.SURFACE
	_in_transit = true
	cancel_mining()
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
	_open_region(destination, _arrival_point(destination))


func _finish_travel() -> void:
	_hud.transit.hide()
	_in_transit = false
	explorer.set_physics_process(true)
	save_expedition()


func _open_region(next_region: int, point: Vector2, origin := Vector2i.ZERO) -> void:
	cancel_mining()
	region = next_region
	explorer.position = point
	explorer.velocity = Vector2.ZERO
	explorer.gravity = surface.planet.details.gravity if region == BlockWorld.Region.SURFACE else 510.0
	explorer.force_update_transform()
	terrain.open_region(surface if region == BlockWorld.Region.SURFACE else station, point, origin)
	_update_beacon()
	_station_art.visible = region == BlockWorld.Region.STATION
	if _station_art.visible:
		_sync_station_air()
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
	_open_region(region, _arrival_point(region))
	_hud.show_inventory(inventory, selected)
	save_expedition(false)
	_hud.show_status("Rescued at the beacon. Half your blocks were lost.", false)


func _weather_name(elapsed: float) -> String:
	return surface.planet.weather_at(elapsed) if region == BlockWorld.Region.SURFACE else ""


func _update_survival_display(seconds := 0.0) -> void:
	var elapsed := survival.elapsed + seconds
	var front := _weather_name(elapsed)
	var on_surface := region == BlockWorld.Region.SURFACE
	var harsh := PlanetProfile.harsh_weather(front)
	var sheltered := harsh and _under_cover()
	var pressure := surface.planet.pressure_kpa if on_surface else 0
	# The suit regulates temperature in orbit. On a planet it is exposed to the local climate.
	var outside_temperature := surface.planet.temperature_at(elapsed, front) if on_surface else SurvivalState.CABIN_TEMPERATURE
	var temperature := outside_temperature
	var breathable := breathable_here()
	var air := "Breathable air" if breathable else "Suit oxygen in use"
	var at_beacon := _at_beacon()
	var inside := not on_surface and _in_cabin()
	var controlled := at_beacon or (inside and _station_sealed)
	if controlled:
		pressure = SurvivalState.CABIN_PRESSURE
		temperature = SurvivalState.CABIN_TEMPERATURE
		air = "Beacon air refill" if at_beacon and (on_surface or not _station_sealed) else "Cabin air"
	elif inside:
		air = "Hull breach · suit oxygen"
	elif pressure > SurvivalState.SUIT_PRESSURE_LIMIT:
		air = "Suit strain · liner equipped" if kit.liner else "Suit strain · pressure liner needed"
	elif sheltered:
		air += " · Under cover"
	if seconds > 0.0:
		survival.advance(seconds, breathable, harsh and not sheltered, pressure, temperature, kit.liner)
		if survival.health == 0.0:
			_rescue()
			return

	_weather.set_front(front, surface.planet.wind)
	var weather_text := front if not front.is_empty() else "Clear"
	var environment := "%d kPa · %d °C" % [pressure, roundi(temperature)] if pressure > 0 else "Vacuum"
	if on_surface:
		environment = "Outside  %d kPa · %d °C" % [surface.planet.pressure_kpa, roundi(outside_temperature)]
	_hud.show_survival(survival, kit, air, weather_text if on_surface else "Orbit", environment,
			on_surface and surface.planet.pressure_kpa > SurvivalState.SUIT_PRESSURE_LIMIT,
			SurvivalState.body_temperature_target(temperature))


func _under_cover() -> bool:
	var head := terrain.world_cell(explorer.position - Vector2(0.0, Explorer.HALF_SIZE.y))
	for gap in range(1, 7):
		if terrain.block_at(head + Vector2i(0, -gap)) != BlockWorld.Block.EMPTY:
			return true
	return false


func _arrival_point(destination: int) -> Vector2:
	return station.station_arrival() if destination == BlockWorld.Region.STATION else BlockWorld.pad_position()


func _in_cabin() -> bool:
	return BlockWorld.STATION_CABIN.has_point(terrain.world_cell(explorer.position))


func _sync_station_air() -> void:
	_station_sealed = station.station_cabin_sealed()
	_station_art.show_integrity(_station_sealed)


func _on_block_changed(cell: Vector2i) -> void:
	if region != BlockWorld.Region.STATION or not BlockWorld.STATION_CABIN.grow(1).has_point(cell):
		return
	var previously_sealed := _station_sealed
	_sync_station_air()
	if previously_sealed != _station_sealed:
		_hud.show_status("Cabin pressure restored" if _station_sealed else "Cabin leak. Patch the hull with alloy.", _station_sealed)
		_update_survival_display()


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
	_station_art.position = terrain.scene_point(Vector2i.ZERO)


func _at_beacon() -> bool:
	return explorer.position.distance_squared_to(_pad_center()) <= BEACON_RANGE_SQUARED


func _update_travel() -> void:
	_near_beacon = _at_beacon()
	var direction := Vector2i(0, BlockWorld.PAD_ROW - 1) - terrain.world_cell(explorer.position)
	_hud.show_travel(region, _near_beacon, surface.planet.title(), direction)
	_hud.show_workshop(can_craft_here(), region)


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
