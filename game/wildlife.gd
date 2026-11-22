class_name SurfaceWildlife
extends Node2D

var _terrain: ActiveTerrain
var _planet: PlanetProfile
var _center_column := 0
var _motion := 0.0
var _frame_time := 0.0


func _ready() -> void:
	set_process(false)


func show_local_life(terrain: ActiveTerrain, planet: PlanetProfile) -> void:
	_terrain = terrain
	_planet = planet
	visible = planet != null
	set_process(visible)
	queue_redraw()


func follow(column: int) -> void:
	_center_column = column


func _process(delta: float) -> void:
	_motion += delta
	_frame_time += delta
	if _frame_time >= 1.0 / 16.0:
		_frame_time = 0.0
		queue_redraw()


func _draw() -> void:
	if _planet == null:
		return
	var group := floori(_center_column / 12.0)
	for area in range(group - 2, group + 3):
		var base_column := area * 12 + 5
		if absi(base_column) < 6:
			continue
		var phase := _motion * (0.67 + 0.14 * _planet.kind) + area * 2.2
		var x := base_column + sin(phase) * 1.7
		var column := floori(x)
		var ground := Vector2i(column, _terrain.world.surface_row(column))
		if _terrain.block_at(ground) != BlockWorld.Block.GRASS or _terrain.block_at(ground + Vector2i.UP) != BlockWorld.Block.EMPTY:
			continue
		var point := Vector2(x * BlockWorld.TILE_SIZE, ground.y * BlockWorld.TILE_SIZE)
		_draw_creature(point, signf(cos(phase)), phase)


func _draw_creature(point: Vector2, direction: float, phase: float) -> void:
	var color := Color(_planet.details.sky).lightened(0.35)
	var lift := absf(sin(phase * 6.0)) * 2.1
	var height := 6.0 + _planet.kind
	point.y -= height + lift
	draw_circle(point, height, color.darkened(0.15))
	var head := point + Vector2(direction * (height - 1.0), -3.0)
	draw_circle(head, height * 0.64, color)
	draw_circle(head + Vector2(1.9 * direction, -0.35), 1.3, Color("#192332"))
	for foot in [-3.0, 3.0]:
		var sway := sin(phase * 6.0 + foot) * 2.0
		draw_line(point + Vector2(foot, height * 0.45), point + Vector2(foot + sway, height), color, 1.9)
