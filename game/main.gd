class_name MomoyoGame
extends Node2D

const REACH_SQUARED := 126.0 * 126.0
const BEACON_RANGE_SQUARED := 54.0 * 54.0
const CURSOR_VALID := Color("#f9d688")
const CURSOR_OUTSIDE := Color(0.91, 0.94, 0.97, 0.3)

var worlds: Array[BlockWorld] = [
	BlockWorld.new(BlockWorld.Region.SURFACE),
	BlockWorld.new(BlockWorld.Region.STATION),
]
var inventory := PackedInt32Array([12, 8, 30, 0])
var region := BlockWorld.Region.SURFACE
var selected := 0

var _save := ExpeditionSave.new()
var _in_transit := false
var _confirm_quit := false

@onready var terrain: ActiveTerrain = $Terrain
@onready var explorer: Explorer = $Explorer
@onready var _camera: Camera2D = $Explorer/Camera
@onready var _cursor: Line2D = $Target
@onready var _sky: Horizon = $Backdrop/Sky
@onready var _hud: FlightHUD = $HUD


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	var state := _save.read()
	var point := BlockWorld.pad_position()
	if not state.is_empty():
		region = state.region
		point = state.position
		inventory = state.inventory
		selected = state.selected
		worlds[0].edits.assign(state.edits[0])
		worlds[1].edits.assign(state.edits[1])
	elif _save.read_error != OK:
		_hud.show_status("Existing save could not be loaded. It has been kept.", false)
	$Beacon.position = Vector2(BlockWorld.pad_position().x, BlockWorld.PAD_ROW * BlockWorld.TILE_SIZE)
	_open_region(region, point)
	_hud.show_inventory(inventory, selected)


func _physics_process(_delta: float) -> void:
	if _in_transit:
		return
	var bounds := worlds[region].bounds
	var px := float(BlockWorld.TILE_SIZE)
	if explorer.position.y >= bounds.end.y * px - Explorer.HALF_SIZE.y - 1.0:
		_open_region(region, BlockWorld.pad_position())
		_hud.show_status("Recovered at the beacon")
	explorer.position.x = clampf(explorer.position.x, bounds.position.x * px + Explorer.HALF_SIZE.x,
			bounds.end.x * px - Explorer.HALF_SIZE.x)
	terrain.stream_around(explorer.position)
	_hud.show_travel(region, _at_beacon())
	_update_target()


func _unhandled_input(event: InputEvent) -> void:
	if _in_transit:
		return
	if event.is_action_pressed("travel"):
		begin_travel()
	elif event.is_action_pressed("save_world"):
		save_expedition()
	elif event.is_action_pressed("mine"):
		mine(BlockWorld.cell_at(get_global_mouse_position()))
	elif event.is_action_pressed("place"):
		place(BlockWorld.cell_at(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			selected = event.physical_keycode - KEY_1
			_hud.show_inventory(inventory, selected)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if _confirm_quit or save_expedition():
		get_tree().quit()
	else:
		_confirm_quit = true
		_hud.show_status("Save unavailable. Close again to exit.", false)


func mine(cell: Vector2i) -> bool:
	if not _within_reach(cell):
		return false
	var material := terrain.block_at(cell)
	if material == BlockWorld.Block.GRASS:
		material = BlockWorld.Block.SOIL
	var slot := BlockWorld.BUILD_MATERIALS.find(material)
	if slot < 0:
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


func begin_travel() -> bool:
	if _in_transit or not _at_beacon():
		return false
	var destination := BlockWorld.Region.STATION if region == BlockWorld.Region.SURFACE else BlockWorld.Region.SURFACE
	_in_transit = true
	explorer.set_physics_process(false)
	_cursor.hide()
	_hud.set_transit_route(destination)
	_hud.transit.show()
	var flight := create_tween()
	flight.tween_property(_hud.transit, "modulate:a", 1.0, 0.35)
	flight.tween_interval(0.50)
	flight.tween_callback(_open_region.bind(destination, BlockWorld.pad_position()))
	flight.tween_property(_hud.transit, "modulate:a", 0.0, 0.35)
	flight.tween_callback(_finish_travel)
	return true


func save_expedition() -> bool:
	var result := _save.write(region, explorer.position, inventory, selected, worlds)
	if result == OK:
		_hud.show_status("Expedition saved")
		return true
	_hud.show_status("Could not save the expedition", false)
	return false


func _finish_travel() -> void:
	_hud.transit.hide()
	_in_transit = false
	explorer.set_physics_process(true)
	save_expedition()


func _open_region(next_region: int, point: Vector2) -> void:
	region = next_region
	explorer.position = point
	explorer.velocity = Vector2.ZERO
	explorer.gravity = 940.0 if region == BlockWorld.Region.SURFACE else 510.0
	explorer.force_update_transform()
	terrain.open_region(worlds[region], point)
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	_sky.show_region(region)
	_hud.show_region(region)
	_hud.show_travel(region, _at_beacon())


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
