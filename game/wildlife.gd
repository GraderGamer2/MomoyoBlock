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


func follow(column: int, rebased: bool) -> void:
	_center_column = column
	if rebased:
		queue_redraw()


func _process(delta: float) -> void:
	_motion += delta
	_frame_time += delta
	if _frame_time >= 1.0 / 16.0:
		_frame_time = 0.0
		queue_redraw()


func _draw() -> void:
	if _planet == null:
		return
	var spacing: int = _planet.details.fauna_spacing
	var salt := _planet.terrain_salt()
	@warning_ignore("integer_division")
	var group := (_center_column - posmod(_center_column, spacing)) / spacing
	for area in range(group - 3, group + 4):
		var draw := PlanetProfile.hash_cell(area, 61, salt)
		if draw % 4 == 0:
			continue
		var base_column := area * spacing + (draw >> 5) % spacing
		if absi(base_column) < 5:
			continue
		var phase := _motion * float(_planet.details.animal_speed) + (draw % 147) * 0.1
		var shift := sin(phase) * 1.7
		var column := base_column + floori(shift)
		var ground := Vector2i(column, _terrain.world.surface_row(column))
		if _terrain.block_at(ground) != BlockWorld.Block.GRASS or _terrain.block_at(ground + Vector2i.UP) != BlockWorld.Block.EMPTY:
			continue
		var point := _terrain.scene_point(ground, Vector2(fposmod(shift, 1.0), 0.0))
		_draw_creature(point, signf(cos(phase)), phase)


func _draw_creature(point: Vector2, direction: float, phase: float) -> void:
	var color: Color = _planet.details.animal_color
	var form: int = _planet.details.animal_form
	var height: float = _planet.details.animal_size
	var lift := absf(sin(phase * 6.0)) * 2.1
	if form == 2:
		lift += 14.0
	point.y -= height + lift
	draw_circle(point, height, color.darkened(0.15))
	var head := point + Vector2(direction * (height - 1.0), -3.0)
	draw_circle(head, height * 0.64, color)
	draw_circle(head + Vector2(1.9 * direction, -0.35), 1.3, Color("#192332"))
	if form == 0:
		draw_line(point, point + Vector2(-direction * height * 1.9, -height * 0.4), color, 2.0)
	elif form == 1:
		draw_line(head, head + Vector2(direction * 3.0, -height), color, 2.5)
	else:
		draw_line(point + Vector2(-height, 0), point + Vector2(height, -height * 0.8), color, 3.0)
		return
	for foot in [-3.0, 3.0]:
		var sway := sin(phase * 6.0 + foot) * 2.0
		draw_line(point + Vector2(foot, height * 0.45), point + Vector2(foot + sway, height), color, 1.9)
