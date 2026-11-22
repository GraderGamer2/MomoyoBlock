extends Node2D


func _draw() -> void:
	draw_line(Vector2(-38, -18), Vector2(38, -18), Color("#9ce6c5"), 1.0)
	draw_line(Vector2(-38, -18), Vector2(-38, -4), Color("#9ce6c5"), 1.0)
	draw_line(Vector2(38, -18), Vector2(38, -4), Color("#9ce6c5"), 1.0)
	for side in [-1, 1]:
		draw_rect(Rect2(side * 34 - 2, -13, 4, 13), Color("#476a71"))
		draw_rect(Rect2(side * 34 - 3, -15, 6, 4), Color("#eec887"))
