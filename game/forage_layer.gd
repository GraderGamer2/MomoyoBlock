class_name ForageLayer
extends Node2D

var markers: Dictionary[Vector2i, int] = {}
var origin_cell := Vector2i.ZERO
var planet: PlanetProfile


func _draw() -> void:
	if planet == null:
		return
	var form: int = planet.details.plant_form
	var tint: Color = planet.details.plant_color
	var fruit: Color = planet.details.fruit_color
	for cell in markers:
		var base := (Vector2(cell - origin_cell) + Vector2(0.5, 1.0)) * BlockWorld.TILE_SIZE
		if markers[cell] == 2:
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(-6, -2), base + Vector2(-4, -9), base + Vector2(1, -17),
				base + Vector2(6, -8), base + Vector2(5, -2),
			]), Color("#67c9e5"))
			draw_line(base + Vector2(0, -14), base + Vector2(-2, -7), Color("#d6faff"), 2.0)
			continue

		draw_line(base, base + Vector2(0, -16), tint, 2.0)
		if form == 1:
			draw_rect(Rect2(base + Vector2(-5, -15), Vector2(10, 5)), tint)
			draw_circle(base + Vector2(-3, -16), 3.0, fruit)
			draw_circle(base + Vector2(2, -18), 3.0, fruit)
		elif form == 2:
			draw_line(base + Vector2(-5, -8), base + Vector2(5, -13), tint, 4.0)
			draw_circle(base + Vector2(0, -17), 4.0, fruit)
		else:
			draw_circle(base + Vector2(-4, -11), 4.0, tint)
			draw_circle(base + Vector2(4, -14), 4.0, tint)
			draw_circle(base + Vector2(0, -17), 2.7, fruit)
