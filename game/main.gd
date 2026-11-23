class_name MomoyoGame
extends Node2D

signal chart_requested
signal workshop_requested

const REACH := 2.0 * BlockWorld.TILE_SIZE
const REACH_SQUARED := REACH * REACH
const WORKBENCH_REACH := 54.0
const BEACON_RANGE_SQUARED := 54.0 * 54.0
const PULSE_INTERVAL := 0.22
const PULSE_FLASH_TIME := 0.08
const DESCENT_CLEARANCE_TILES := 8
const DESCENT_ENTRY_SPEED := 260.0
const CURSOR_VALID := Color("#f9d688")
const CURSOR_OUTSIDE := Color(0.91, 0.94, 0.97, 0.3)

var universe_seed := 0
var sector := Vector2i.ZERO
var surface: BlockWorld
var station := BlockWorld.new(BlockWorld.Region.STATION)
var cabin := CabinAtmosphere.new()
var survival := SurvivalState.new()
var kit := ExpeditionKit.new()
var inventory := ExpeditionInventory.starter()
var region := BlockWorld.Region.SURFACE
var selected := 0
var sandbox_enabled := false
var sandbox_material := BlockWorld.Block.EMPTY

var _planet_journals: Dictionary[Vector2i, PackedByteArray] = {}
var _station_journal := PackedByteArray()
var _habitat_saves: Dictionary = {}
var _habitat_zone := Vector3i.ZERO
var _habitats: Dictionary[Vector2i, HabitatRoom] = {}
var _habitat_networks := HabitatNetworks.new()
var _near_beacon := false
var save_filename := ExpeditionSave.DEFAULT_FILE
var _save: ExpeditionSave
var _in_transit := false
var _tick_progress := 0.0
var _mine_cell := Vector2i.ZERO
var _mine_material := BlockWorld.Block.EMPTY
var _mine_time := 0.0
var _mine_elapsed := 0.0
var _pulse_left := 0.0

@onready var terrain: ActiveTerrain = $Terrain
@onready var explorer: Explorer = $Explorer
@onready var _camera: Camera2D = $Explorer/Camera
@onready var _cursor: Line2D = $Target
@onready var _mine_progress: ProgressBar = $Target/MiningProgress
@onready var _pulse: Line2D = $ToolPulse
@onready var _wildlife: SurfaceWildlife = $Wildlife
@onready var _sky: Horizon = $Backdrop/Sky
@onready var _beacon: Node2D = $Beacon
@onready var _station_art: StationInterior = $StationInterior
@onready var _loose_objects: Node2D = $LooseObjects
@onready var _weather: WeatherLayer = $Backdrop/Front
@onready var _hud: FlightHUD = $HUD


func _ready() -> void:
	explorer.vitals = survival
	terrain.block_changed.connect(_on_block_changed)
	_save = ExpeditionSave.new(save_filename)
	var state := _save.read()
	var point := BlockWorld.pad_position()
	var origin := Vector2i.ZERO
	if not state.is_empty():
		universe_seed = state.universe_seed
		region = state.region
		point = state.position
		origin = state.origin
		inventory.restore(state.inventory)
		selected = state.selected
		sandbox_enabled = state.sandbox_enabled
		_planet_journals.assign(state.planets)
		_habitat_saves = state.habitats
		_load_planet(state.sector)
		_station_journal = state.station
		station.restore_journal(TerrainJournal.unpack(_station_journal, false))
		cabin.pressure = state.cabin_pressure
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
	cabin.sync(station)
	_open_region(region, point, origin)
	_show_inventory()
	if state.is_empty() and _save.read_error == OK and not save_expedition(false):
		_hud.show_status("Could not save the new expedition. Press F5 to retry.", false)


func _physics_process(delta: float) -> void:
	cabin.advance(delta)
	if _in_transit:
		return
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		if _pulse_left == 0.0:
			_pulse.hide()
	var rebased := _rebase_explorer()
	var cell := terrain.world_cell(explorer.position)
	if region == BlockWorld.Region.STATION:
		if cell.y >= BlockWorld.STATION_DESCENT_ROW:
			_start_travel(BlockWorld.Region.SURFACE, sector, true)
			return
		_update_orbital_gravity()
	terrain.stream_around(explorer.position)
	if region == BlockWorld.Region.STATION:
		_apply_station_airflow()
	_wildlife.follow(cell.x, rebased)
	if _near_beacon != _at_beacon():
		_update_travel()
	var aim := terrain.world_cell(get_global_mouse_position())
	_update_target(aim)
	if _mine_time > 0.0:
		advance_mining(delta, aim, Input.is_action_pressed("mine"))

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
		interact()
	elif event.is_action_pressed("star_chart") and can_choose_planet():
		chart_requested.emit()
	elif event.is_action_pressed("workshop"):
		workshop_requested.emit()
	elif event.is_action_pressed("toggle_suit"):
		toggle_suit()
	elif event.is_action_pressed("air_canister"):
		use_air_canister()
	elif event.is_action_pressed("gather"):
		gather_nearby()
	elif event.is_action_pressed("eat"):
		consume(ExpeditionInventory.RATION)
	elif event.is_action_pressed("drink"):
		consume(ExpeditionInventory.WATER)
	elif event.is_action_pressed("mine"):
		begin_mining(terrain.world_cell(get_global_mouse_position()))
	elif event.is_action_pressed("place"):
		use_or_place(terrain.world_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			selected = event.physical_keycode - KEY_1
			sandbox_material = BlockWorld.Block.EMPTY
			_show_inventory()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			selected = posmod(selected + direction, ExpeditionInventory.HOTBAR_SLOTS)
			sandbox_material = BlockWorld.Block.EMPTY
			_show_inventory()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		cancel_mining()


func begin_mining(cell: Vector2i) -> bool:
	cancel_mining()
	var pulse_reach := kit.pulse_reach_squared()
	if _in_transit or not _within_reach(cell, pulse_reach):
		_feedback_on_distant_action(cell, pulse_reach)
		return false
	var material := terrain.block_at(cell)
	var item := BlockWorld.mined_material(material)
	if not BlockWorld.is_placeable(item):
		return false
	if not sandbox_enabled and not inventory.has_room(item, 1, survival.suit_equipped):
		_hud.show_status("Inventory is full", false)
		return false
	if not terrain.pulse_path_clear(explorer.position, cell):
		_hud.show_status("Terrain blocked the pulse", false)
		return false
	_mine_cell = cell
	_mine_material = material
	_mine_time = BlockWorld.mining_time(material, kit.mining_power())
	_mine_progress.value = 0.0
	_mine_progress.show()
	_hud.show_mining(BlockWorld.BLOCK_NAMES[material], _mine_time)
	_flash_pulse(cell)
	return true


func advance_mining(delta: float, aim: Vector2i, held: bool) -> bool:
	if _mine_time == 0.0:
		return false
	if not held or aim != _mine_cell or not _within_reach(_mine_cell, kit.pulse_reach_squared()) \
			or terrain.block_at(_mine_cell) != _mine_material or not terrain.pulse_path_clear(explorer.position, _mine_cell):
		cancel_mining()
		return false
	var previous_pulse := int(_mine_elapsed / PULSE_INTERVAL)
	_mine_elapsed += delta
	if _mine_elapsed < _mine_time:
		_mine_progress.value = _mine_elapsed / _mine_time
		if previous_pulse != int(_mine_elapsed / PULSE_INTERVAL):
			_flash_pulse(_mine_cell)
		return false

	var cell := _mine_cell
	var material := _mine_material
	cancel_mining()
	if not inventory.add(BlockWorld.mined_material(material), 1, survival.suit_equipped) and not sandbox_enabled:
		_hud.show_status("Inventory is full", false)
		return false
	_flash_pulse(cell)
	terrain.set_block(cell, BlockWorld.Block.EMPTY)
	if material == BlockWorld.Block.WORKBENCH:
		_hud.show_status("Workbench recovered")
	_show_inventory()
	return true


func cancel_mining() -> void:
	if _mine_time > 0.0:
		_mine_time = 0.0
		_mine_elapsed = 0.0
		_mine_progress.hide()
		_hud.hide_mining()
	_clear_pulse()


func _flash_pulse(cell: Vector2i) -> void:
	var aim := terrain.scene_point(cell, ActiveTerrain.CELL_CENTER)
	_pulse.set_point_position(0, explorer.aim_tool_at(aim))
	_pulse.set_point_position(1, aim)
	_pulse_left = PULSE_FLASH_TIME
	_pulse.show()


func _clear_pulse() -> void:
	if _pulse_left > 0.0:
		_pulse.hide()
		_pulse_left = 0.0


func use_or_place(cell: Vector2i) -> bool:
	if _in_transit:
		return false
	match terrain.block_at(cell):
		BlockWorld.Block.GENERATOR:
			return _refuel_generator(cell)
		BlockWorld.Block.SOLAR_PANEL:
			if not _within_reach(cell):
				_feedback_on_distant_action(cell)
				return false
			if not terrain.pulse_path_clear(explorer.position, cell):
				_hud.show_status("The solar panel is blocked.", false)
				return false
			_hud.show_status(_habitat_networks.panel_reading(terrain.world, cell))
			return true
	var item := _held_item()
	if item == ExpeditionInventory.FUEL_CELL:
		_hud.show_status("Right-click a fuel generator to load a cell.", false)
		return false
	return consume(item) if item >= ExpeditionInventory.RATION else place(cell)


func _refuel_generator(cell: Vector2i) -> bool:
	if not _within_reach(cell):
		_feedback_on_distant_action(cell)
		return false
	if not terrain.pulse_path_clear(explorer.position, cell):
		_hud.show_status("The generator is blocked.", false)
		return false
	var room := _habitat_at_floor(cell)
	if room == null:
		if not _commission_habitat(cell):
			return false
		room = _habitat_at_floor(cell)
	HabitatRoom.advance_network(_habitat_networks.members(room), survival.elapsed)
	if room.fuel_seconds > 0.0:
		_hud.show_status("The generator already has fuel.", false)
		return false
	if not sandbox_enabled and not inventory.take(ExpeditionInventory.FUEL_CELL, 1, survival.suit_equipped):
		_hud.show_status("Craft a fuel cell at a workbench to refuel.", false)
		return false
	room.refuel(cell)
	_hud.show_status("Fuel cell loaded.")
	_show_inventory()
	_update_survival_display()
	return true


func place(cell: Vector2i) -> bool:
	if _in_transit or not _within_reach(cell):
		_feedback_on_distant_action(cell)
		return false
	var material := _held_item()
	if terrain.block_at(cell) != BlockWorld.Block.EMPTY or not BlockWorld.is_placeable(material):
		return false
	var tile_rect := Rect2(terrain.scene_point(cell), Vector2.ONE * BlockWorld.TILE_SIZE)
	if tile_rect.intersects(explorer.body_rect()):
		return false
	if not sandbox_enabled:
		inventory.take_from(selected)
	terrain.set_block(cell, material)
	if material == BlockWorld.Block.WORKBENCH:
		_hud.show_status("Workbench deployed")
	_show_inventory()
	return true


func gather_nearby() -> bool:
	var cell: Variant = terrain.nearest_forage(explorer.position, kit.pulse_reach_squared())
	if cell == null:
		_hud.show_status("No food or water in pulse range", false)
		return false
	var food: bool = terrain.forage.markers[cell] == 1
	var item := ExpeditionInventory.RATION if food else ExpeditionInventory.WATER
	if not inventory.add(item, 1, survival.suit_equipped):
		_hud.show_status("Inventory is full", false)
		return false
	_hud.show_status("Gathered %s" % (surface.planet.details.flora if food else surface.planet.details.water))
	_flash_pulse(cell)
	terrain.harvest(cell)
	_show_inventory()
	_update_survival_display()
	return true


func breathable_here() -> bool:
	return _breathable_with(_habitat_here(survival.elapsed))


func _breathable_with(habitat: HabitatRoom) -> bool:
	if _at_beacon():
		return true
	if habitat != null and habitat.breathable():
		return true
	if region == BlockWorld.Region.STATION:
		return _in_cabin() and cabin.pressure >= CabinAtmosphere.BREATHABLE_PRESSURE
	return surface.planet.details.breathable


func workbench_name() -> String:
	if region == BlockWorld.Region.STATION:
		var workbench := terrain.scene_point(BlockWorld.STATION_WORKBENCH, ActiveTerrain.CELL_CENTER)
		if explorer.position.distance_squared_to(workbench) <= BEACON_RANGE_SQUARED:
			return "Relay Nine workshop"
	if terrain.has_block_near(explorer.position, BlockWorld.Block.WORKBENCH, WORKBENCH_REACH):
		return "Field workbench"
	return ""


func craft(recipe: int) -> bool:
	if _in_transit or (recipe != ExpeditionKit.Recipe.WORKBENCH and workbench_name().is_empty()):
		return false
	if not kit.craft(recipe, inventory, survival, sandbox_enabled):
		return false
	_show_inventory()
	_update_survival_display()
	return true


func toggle_suit() -> bool:
	if not survival.suit_equipped and survival.suit_integrity == 0.0:
		_hud.show_status("Repair the suit at a workbench", false)
		return false
	survival.suit_equipped = not survival.suit_equipped
	_hud.show_status("Suit equipped" if survival.suit_equipped else "Suit removed", survival.suit_equipped)
	_update_survival_display()
	return true


func use_air_canister() -> bool:
	return consume(ExpeditionInventory.CANISTER)


func consume(item: int) -> bool:
	if item == ExpeditionInventory.CANISTER and not survival.suit_active():
		_hud.show_status("Equip a working suit to use spare air", false)
		return false
	if not sandbox_enabled and inventory.count(item, survival.suit_equipped) == 0:
		_hud.show_status("No %s in accessible storage" % ExpeditionInventory.item_name(item).to_lower(), false)
		return false
	match item:
		ExpeditionInventory.RATION:
			if not survival.eat():
				_hud.show_status("Hunger is full")
				return false
		ExpeditionInventory.WATER:
			if not survival.drink():
				_hud.show_status("Thirst is full")
				return false
		ExpeditionInventory.CANISTER:
			if survival.oxygen >= SurvivalState.MAX_LEVEL:
				_hud.show_status("Oxygen is full")
				return false
			survival.oxygen = minf(SurvivalState.MAX_LEVEL, survival.oxygen + ExpeditionKit.CANISTER_REFILL)
		_:
			return false
	if not sandbox_enabled:
		inventory.take(item, 1, survival.suit_equipped)
	_show_inventory()
	_update_survival_display()
	return true


func move_inventory(source: int, target: int) -> bool:
	if not inventory.move_slot(source, target, survival.suit_equipped):
		return false
	_show_inventory()
	_update_survival_display()
	return true


func can_choose_planet() -> bool:
	return region == BlockWorld.Region.STATION and _at_beacon() and not _in_transit


func begin_travel() -> bool:
	return _travel(sector)


func interact() -> bool:
	if _in_transit:
		return false
	if _at_beacon():
		return begin_travel()
	var exit: Variant = _airlock_exit()
	if exit != null:
		var target: Vector2i = exit
		if not terrain.is_editable(target) or not terrain.is_editable(target + Vector2i.UP) or \
				terrain.block_at(target) != BlockWorld.Block.EMPTY or terrain.block_at(target + Vector2i.UP) != BlockWorld.Block.EMPTY:
			_hud.show_status("Airlock exit blocked.", false)
			return false
		cancel_mining()
		explorer.position = terrain.scene_point(target, Vector2(0.5, 1.0)) - Vector2(0.0, Explorer.HALF_SIZE.y + 1.0)
		explorer.velocity = Vector2.ZERO
		explorer.force_update_transform()
		_hud.show_status("Airlock cycled.")
		_update_survival_display()
		_update_travel()
		return true
	var recycler: Variant = terrain.nearest_block(explorer.position, BlockWorld.Block.RECYCLER, WORKBENCH_REACH)
	return false if recycler == null else _commission_habitat(recycler)


func _airlock_exit() -> Variant:
	var cell := terrain.world_cell(explorer.position)
	for side: int in [-1, 1]:
		var panel := cell + Vector2i(side, 0)
		if terrain.block_at(panel) != BlockWorld.Block.AIRLOCK:
			continue
		if terrain.block_at(panel + Vector2i.DOWN) == BlockWorld.Block.AIRLOCK:
			panel += Vector2i.DOWN
		elif terrain.block_at(panel + Vector2i.UP) != BlockWorld.Block.AIRLOCK:
			continue
		if explorer.position.distance_squared_to(terrain.scene_point(panel, ActiveTerrain.CELL_CENTER)) <= BEACON_RANGE_SQUARED:
			return panel + Vector2i(side, 0)
	return null


func _commission_habitat(equipment: Vector2i) -> bool:
	var survey := HabitatRoom.survey_from(terrain.world, equipment + Vector2i.UP)
	if not survey.has("bounds"):
		_hud.show_status(survey.issue, false)
		return false
	var area: Rect2i = survey.bounds
	if equipment.y != area.end.y:
		_hud.show_status("Fit the equipment into the bottom row of the habitat.", false)
		return false
	var rooms := HabitatNetworks.discover(terrain.world, area)
	var layout := _plan_habitat_layout(rooms)
	if layout.is_empty():
		return false
	_habitat_networks.advance_to(survival.elapsed)
	for anchor: Vector2i in layout:
		var chamber: Rect2i = layout[anchor]
		var room: HabitatRoom = _habitats.get(anchor)
		if room == null:
			room = HabitatRoom.new(chamber, survival.elapsed)
			_habitats[anchor] = room
		else:
			room.air *= minf(1.0, float(room.bounds.get_area()) / chamber.get_area())
			room.bounds = chamber
		room.sync(terrain.world, anchor)
	_rebuild_habitat_networks()
	var count := _habitat_networks.members(_habitat_at_floor(equipment)).size()
	_hud.show_status("Life support linked across %d rooms." % count if count > 1 else "Habitat commissioned.")
	_update_survival_display()
	return true


func _plan_habitat_layout(rooms: Array[Rect2i]) -> Dictionary[Vector2i, Rect2i]:
	var layout: Dictionary[Vector2i, Rect2i] = {}
	var has_recycler := false
	for chamber in rooms:
		var recycler: Variant = HabitatRoom.find_recycler(terrain.world, chamber)
		has_recycler = has_recycler or recycler != null
		var anchor := Vector2i(chamber.position.x, chamber.end.y) if recycler == null else Vector2i(recycler)
		for known: Vector2i in _habitats:
			if _habitats[known].bounds == chamber:
				anchor = known
				break
		for known: Vector2i in _habitats:
			if known != anchor and chamber.intersects(_habitats[known].bounds):
				_hud.show_status("This shell overlaps a commissioned room. Keep a dividing wall with an airlock.", false)
				return {}
		layout[anchor] = chamber
	if not has_recycler:
		_hud.show_status("Fit an oxygen recycler in this floor or connect to one through a two-panel airlock.", false)
		return {}
	return layout


func _habitat_at_floor(cell: Vector2i) -> HabitatRoom:
	for room: HabitatRoom in _habitats.values():
		if room.floor_contains(cell):
			return room
	return null


func land_at(address: Vector2i) -> bool:
	return can_choose_planet() and _travel(address)


func save_expedition(show_feedback := true) -> bool:
	_rebase_explorer()
	_remember_planet()
	_store_habitats()
	if station.journal_dirty:
		_station_journal = TerrainJournal.pack(station.edits, station.harvested)
		station.journal_dirty = false
	var revision := BlockWorld.LEGACY_REVISION if universe_seed == 0 else BlockWorld.WORLD_REVISION
	var result := _save.write({
		"format": ExpeditionSave.FORMAT, "world_revision": revision, "universe_seed": universe_seed,
		"region": region, "sector": sector, "origin": terrain.origin_cell, "position": explorer.position,
		"inventory": inventory.snapshot(), "selected": selected, "planets": _planet_journals,
		"station": _station_journal, "cabin_pressure": cabin.pressure, "vitals": survival.snapshot(), "kit": kit.snapshot(),
		"habitats": _habitat_saves, "sandbox_enabled": sandbox_enabled,
	})
	if show_feedback:
		_hud.show_status("Expedition saved" if result == OK else "Could not save the expedition", result == OK)
	return result == OK


func _travel(address: Vector2i) -> bool:
	if _in_transit or not _at_beacon():
		return false
	var destination := BlockWorld.Region.STATION if region == BlockWorld.Region.SURFACE else BlockWorld.Region.SURFACE
	_start_travel(destination, address)
	return true


func _start_travel(destination: int, address: Vector2i, falling := false) -> void:
	_in_transit = true
	cancel_mining()
	explorer.set_physics_process(false)
	_cursor.hide()
	var planet_name := surface.planet.title() if address == sector else PlanetProfile.new(address, universe_seed).title()
	_hud.set_transit_route(destination, planet_name, falling)
	_hud.transit.show()
	var flight := create_tween()
	flight.tween_property(_hud.transit, "modulate:a", 1.0, 0.35)
	flight.tween_interval(0.50)
	flight.tween_callback(_arrive.bind(destination, address, falling))
	flight.tween_property(_hud.transit, "modulate:a", 0.0, 0.35)
	flight.tween_callback(_finish_travel)


func _arrive(destination: int, address: Vector2i, falling: bool) -> void:
	if address != sector:
		_remember_planet()
		_load_planet(address)
	_open_region(destination, _surface_descent_point() if falling else _arrival_point(destination))
	if falling:
		explorer.velocity.y = DESCENT_ENTRY_SPEED


func _finish_travel() -> void:
	_hud.transit.hide()
	_in_transit = false
	explorer.set_physics_process(true)
	save_expedition()


func _open_region(next_region: int, point: Vector2, origin := Vector2i.ZERO) -> void:
	cancel_mining()
	_store_habitats()
	for body in _loose_objects.get_children():
		body.queue_free()
	region = next_region
	explorer.position = point
	explorer.velocity = Vector2.ZERO
	explorer.airflow = Vector2.ZERO
	explorer.force_update_transform()
	terrain.open_region(surface if region == BlockWorld.Region.SURFACE else station, point, origin)
	if region == BlockWorld.Region.STATION:
		_update_orbital_gravity()
	else:
		explorer.gravity = surface.planet.gravity_g * PlanetProfile.EARTH_GRAVITY_PX
	_load_habitats()
	_update_beacon()
	_station_art.visible = region == BlockWorld.Region.STATION
	_wildlife.show_local_life(terrain, surface.planet if region == BlockWorld.Region.SURFACE else null)
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	_sky.show_region(region, surface.planet)
	_hud.show_region(region, surface.planet)
	_update_travel()
	_update_survival_display()


func _orbital_pull() -> float:
	return surface.planet.gravity_g * PlanetProfile.EARTH_GRAVITY_PX * BlockWorld.ORBITAL_GRAVITY_FRACTION


func _update_orbital_gravity() -> void:
	var tile_position := explorer.position / BlockWorld.TILE_SIZE + Vector2(terrain.origin_cell)
	var strength := BlockWorld.station_gravity_strength(tile_position)
	explorer.gravity = lerpf(_orbital_pull(), BlockWorld.STATION_GRAVITY_PX, strength)


func _rescue() -> void:
	inventory.rescue_supplies()
	survival.restore_after_rescue()
	_open_region(region, _arrival_point(region))
	_show_inventory()
	save_expedition(false)
	_hud.show_status("Rescued at the beacon. Some construction supplies were lost.", false)


func _weather_name(elapsed: float) -> String:
	return surface.planet.weather_at(elapsed) if region == BlockWorld.Region.SURFACE else ""


func _habitat_here(now: float) -> HabitatRoom:
	if _habitats.is_empty():
		return null
	var cell := terrain.world_cell(explorer.position)
	for room: HabitatRoom in _habitats.values():
		if room.contains(cell):
			HabitatRoom.advance_network(_habitat_networks.members(room), now)
			return room
	return null


func _store_habitats() -> void:
	if terrain.world == null:
		return
	_habitat_networks.advance_to(survival.elapsed)
	var states := {}
	for device in _habitats:
		var room: HabitatRoom = _habitats[device]
		if room.keep_record(terrain.world):
			states[device] = room.snapshot()
	if states.is_empty():
		_habitat_saves.erase(_habitat_zone)
	else:
		_habitat_saves[_habitat_zone] = states


func _load_habitats() -> void:
	_habitat_zone = Vector3i(0, 0, region) if region == BlockWorld.Region.STATION else Vector3i(sector.x, sector.y, region)
	_habitats.clear()
	var states: Dictionary = _habitat_saves.get(_habitat_zone, {})
	for device: Vector2i in states:
		_habitats[device] = HabitatRoom.from_snapshot(states[device], terrain.world, device, states[device].time)
	_rebuild_habitat_networks()
	_habitat_networks.advance_to(survival.elapsed)


func _rebuild_habitat_networks() -> void:
	_habitat_networks.rebuild(terrain.world, _habitats.values())


func _update_survival_display(seconds := 0.0) -> void:
	var elapsed := survival.elapsed + seconds
	var habitat := _habitat_here(elapsed)
	var front := _weather_name(elapsed)
	var on_surface := region == BlockWorld.Region.SURFACE
	var inside := not on_surface and _in_cabin()
	var storm_wear := PlanetProfile.storm_wear(front)
	var cover := _overhead_block() if on_surface else BlockWorld.Block.EMPTY
	var sheltered := cover != BlockWorld.Block.EMPTY or (habitat != null and habitat.sealed())
	var pressure: float = surface.planet.pressure_kpa if on_surface else (cabin.pressure if inside else 0.0)
	var outside_temperature := surface.planet.temperature_at(elapsed, front) if on_surface else survival.vacuum_exposure_temperature()
	var temperature := outside_temperature
	var breathable := _breathable_with(habitat)
	var network: Array = [] if habitat == null else _habitat_networks.members(habitat)
	var solar := 0.0
	var air := "Breathable air" if breathable else "Suit oxygen in use"
	var at_beacon := _at_beacon()
	if inside:
		temperature = lerpf(outside_temperature, SurvivalState.CABIN_TEMPERATURE, pressure / SurvivalState.CABIN_PRESSURE)
		if not cabin.breaches.is_empty():
			air = "Cabin venting" if breathable else "Cabin venting · Suit oxygen"
		elif pressure < SurvivalState.CABIN_PRESSURE:
			air = "Cabin repressurizing"
		else:
			air = "Cabin air"
	if at_beacon:
		pressure = SurvivalState.CABIN_PRESSURE
		temperature = SurvivalState.CABIN_TEMPERATURE
		if on_surface or not cabin.breaches.is_empty() or cabin.pressure < CabinAtmosphere.BREATHABLE_PRESSURE:
			air = "Beacon shelter"
	elif habitat != null:
		var clean_air := habitat.air / SurvivalState.CABIN_PRESSURE
		pressure = lerpf(pressure, SurvivalState.CABIN_PRESSURE, clean_air)
		temperature = lerpf(temperature, SurvivalState.CABIN_TEMPERATURE, clean_air)
		for room: HabitatRoom in network:
			solar += room.solar_output
		var supplied := solar >= HabitatRoom.RECYCLER_DRAW or network.any(func(room: HabitatRoom) -> bool: return room.powered())
		air = habitat.condition(network.any(func(room: HabitatRoom) -> bool: return room.recycles_air()), supplied, solar)
	elif on_surface:
		if pressure > SurvivalState.SUIT_PRESSURE_LIMIT:
			air = "Suit strain · liner equipped" if kit.liner else "Suit strain · Pressure liner needed"
		elif sheltered and storm_wear > 0.0:
			air += " · Under cover"
		if cover == BlockWorld.Block.INSULATION:
			temperature = lerpf(outside_temperature, SurvivalState.CABIN_TEMPERATURE, 0.45)
	if seconds > 0.0:
		survival.advance(seconds, breathable, 0.0 if at_beacon or sheltered else storm_wear,
				pressure, temperature, kit.liner, not on_surface)
		if survival.health == 0.0:
			_rescue()
			return

	var breathing := survival.has_breathing_air(breathable)
	var airless := (not on_surface or pressure == 0.0) and not breathing
	if airless:
		var remaining := SurvivalState.VACUUM_GRACE - survival.vacuum_exposure
		air = "No oxygen · %d s grace" % ceili(remaining) if remaining > 0.0 else "No oxygen · Losing health"
	elif not survival.suit_active():
		if not breathable:
			air = "No breathable air"
		air += " · Suit breached" if survival.suit_equipped else " · Suit off"
	elif not breathable and survival.suit_integrity < SurvivalState.SUIT_LEAK_START:
		air = "Suit leaking air"
	explorer.show_suit(survival.suit_equipped, survival.suit_integrity == 0.0)
	if not on_surface:
		_station_art.show_integrity(cabin.breaches.is_empty() and cabin.pressure >= SurvivalState.CABIN_PRESSURE - 1.0)
		_hud.show_orbital_gravity(explorer.gravity, explorer.gravity > _orbital_pull())
	_weather.set_front(front, surface.planet.wind)
	var weather_text := front if not front.is_empty() else "Clear"
	var environment := "Cabin %.0f kPa" % cabin.pressure if inside else "Vacuum · Cold exposure"
	if on_surface:
		environment = "Outside  %d kPa · %d °C" % [surface.planet.pressure_kpa, roundi(outside_temperature)]
	var habitat_power := ""
	if habitat != null and not at_beacon:
		environment = "Habitat air %.0f%% · %.0f kPa" % [habitat.air * 100.0 / SurvivalState.CABIN_PRESSURE, pressure]
		habitat_power = HabitatRoom.network_reading(network, solar)
	_hud.show_survival(survival, inventory, air, weather_text if on_surface else "Orbit", environment,
			(on_surface and surface.planet.pressure_kpa > SurvivalState.SUIT_PRESSURE_LIMIT) or
			(inside and not cabin.breaches.is_empty()),
			SurvivalState.body_temperature_target(temperature))
	_hud.show_habitat_power(habitat_power)
	_hud.show_vacuum_recovery(survival, breathing)


func _overhead_block() -> int:
	var head := terrain.world_cell(explorer.position - Vector2(0.0, Explorer.HALF_SIZE.y))
	for gap in range(1, 7):
		var block := terrain.block_at(head + Vector2i(0, -gap))
		if block != BlockWorld.Block.EMPTY:
			return block
	return BlockWorld.Block.EMPTY


func _arrival_point(destination: int) -> Vector2:
	return station.station_arrival() if destination == BlockWorld.Region.STATION else BlockWorld.pad_position()


func _surface_descent_point() -> Vector2:
	var cell := Vector2i(0, BlockWorld.PAD_ROW)
	var empty_rows := 0
	while empty_rows < DESCENT_CLEARANCE_TILES:
		cell.y -= 1
		empty_rows = empty_rows + 1 if surface.material_at(cell) == BlockWorld.Block.EMPTY else 0
	# Leave an empty tile above the explorer's center for the collision shape.
	return BlockWorld.pad_position() + Vector2(0.0, (cell.y + 2 - BlockWorld.PAD_ROW) * BlockWorld.TILE_SIZE)


func _in_cabin() -> bool:
	return BlockWorld.STATION_CABIN.has_point(terrain.world_cell(explorer.position))


func _on_block_changed(cell: Vector2i) -> void:
	var habitat_changed := false
	for device in _habitats.keys():
		var room: HabitatRoom = _habitats[device]
		if not room.bounds.grow(1).has_point(cell):
			continue
		if not habitat_changed:
			_habitat_networks.advance_to(survival.elapsed)
		room.sync(terrain.world, device)
		if not room.keep_record(terrain.world):
			_habitats.erase(device)
		habitat_changed = true
	if habitat_changed:
		_rebuild_habitat_networks()
		_update_survival_display()
	elif _habitat_networks.solar_affected(cell):
		_habitat_networks.advance_to(survival.elapsed)
		_habitat_networks.refresh_solar(terrain.world)
		_update_survival_display()
	if region != BlockWorld.Region.STATION or not BlockWorld.STATION_PRESSURE_AREA.has_point(cell):
		return
	var previous := cabin.breaches
	cabin.sync(station)
	var opened := false
	for breach in cabin.breaches:
		if not previous.has(breach):
			opened = true
			if cabin.pressure > CabinAtmosphere.FLOW_CUTOFF:
				_spawn_breach_debris(breach)
	if opened:
		_hud.show_status("Hull breach. Cabin losing air.", false)
		_update_survival_display()
	elif not previous.is_empty() and cabin.breaches.is_empty():
		_hud.show_status("Hull sealed. Restoring cabin pressure.")
		_update_survival_display()


func _apply_station_airflow() -> void:
	explorer.airflow = cabin.airflow_at(explorer.position, terrain.origin_cell)
	if cabin.breaches.is_empty() or cabin.pressure <= CabinAtmosphere.FLOW_CUTOFF:
		return
	for body: RigidBody2D in _loose_objects.get_children():
		var flow := cabin.airflow_at(body.position, terrain.origin_cell)
		if flow != Vector2.ZERO:
			body.apply_central_force(flow * body.mass * 10.0)


func _spawn_breach_debris(cell: Vector2i) -> void:
	var room := BlockWorld.STATION_CABIN
	var inside := cell.clamp(room.position, room.end - Vector2i.ONE)
	var edge := terrain.scene_point(inside, ActiveTerrain.CELL_CENTER)
	for i in mini(3, 18 - _loose_objects.get_child_count()):
		var piece := RigidBody2D.new()
		piece.position = edge + Vector2((i - 1) * 6.0, (i - 1) * 7.0)
		piece.collision_layer = 0
		piece.collision_mask = 1
		piece.gravity_scale = 0.12
		piece.linear_damp = 3.0
		var collider := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 2.0
		collider.shape = shape
		piece.add_child(collider)
		var art := Polygon2D.new()
		art.polygon = PackedVector2Array([Vector2(-4, 0), Vector2(2, -2), Vector2(4, 2)])
		art.color = Color("#e0b690") if i == 1 else Color("#aacad1")
		piece.add_child(art)
		var timer := Timer.new()
		timer.wait_time = 4.0 + i * 0.25
		timer.one_shot = true
		timer.autostart = true
		timer.timeout.connect(piece.queue_free)
		piece.add_child(timer)
		_loose_objects.add_child(piece)


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
	for body: RigidBody2D in _loose_objects.get_children():
		body.position -= shift
	_clear_pulse()
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
	var interaction := ""
	if not _near_beacon:
		if _airlock_exit() != null:
			interaction = "E  Cycle airlock"
		elif terrain.has_block_near(explorer.position, BlockWorld.Block.RECYCLER, WORKBENCH_REACH):
			interaction = "E  Commission life support"
	_hud.show_travel(region, _near_beacon, surface.planet.title(), direction, interaction)
	_hud.show_workshop(workbench_name())


func _show_inventory() -> void:
	_hud.show_inventory(inventory, selected, kit.pulse_level, sandbox_enabled, sandbox_material)


func set_sandbox(enabled: bool) -> void:
	sandbox_enabled = enabled
	sandbox_material = BlockWorld.Block.EMPTY
	_show_inventory()


func select_sandbox_material(material: int) -> bool:
	if not sandbox_enabled or not BlockWorld.is_placeable(material):
		return false
	sandbox_material = material
	_show_inventory()
	return true


func _held_item() -> int:
	return sandbox_material if sandbox_material != BlockWorld.Block.EMPTY else inventory.item_at(selected)


func _within_reach(cell: Vector2i, reach_squared := REACH_SQUARED) -> bool:
	return terrain.is_editable(cell) and explorer.position.distance_squared_to(terrain.scene_point(cell, ActiveTerrain.CELL_CENTER)) <= reach_squared


func _feedback_on_distant_action(cell: Vector2i, reach_squared := REACH_SQUARED) -> void:
	if explorer.position.distance_squared_to(terrain.scene_point(cell, ActiveTerrain.CELL_CENTER)) > reach_squared:
		_hud.show_status("Move closer to reach that block", false)


func _update_target(cell: Vector2i) -> void:
	var point := terrain.scene_point(cell)
	var occupied := terrain.block_at(cell) != BlockWorld.Block.EMPTY
	var reachable := _within_reach(cell, kit.pulse_reach_squared() if occupied else REACH_SQUARED)
	var clear_path := reachable and (not occupied or terrain.pulse_path_clear(explorer.position, cell))
	var tint := CURSOR_VALID if clear_path else CURSOR_OUTSIDE
	if _cursor.position != point:
		_cursor.position = point
	if _cursor.default_color != tint:
		_cursor.default_color = tint
	if not _cursor.visible:
		_cursor.show()
