class_name ForageLayer
extends Node2D

var markers: Dictionary[Vector2i, int] = {}
var tint := Color("#a1dcb1")


func _draw() -> void:
	for cell in markers:
		var base := (Vector2(cell) + Vector2(0.5, 1.0)) * BlockWorld.TILE_SIZE
		if markers[cell] == 1:
			draw_line(base, base + Vector2(0, -16), tint, 2.0)
			draw_circle(base + Vector2(-4, -11), 4.0, tint)
			draw_circle(base + Vector2(4, -14), 4.0, tint)
			draw_circle(base + Vector2(0, -17), 2.7, Color("#f6c47d"))
		else:
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(-6, -2), base + Vector2(-4, -9), base + Vector2(1, -17),
				base + Vector2(6, -8), base + Vector2(5, -2),
			]), Color("#67c9e5"))
			draw_line(base + Vector2(0, -14), base + Vector2(-2, -7), Color("#d6faff"), 2.0)
