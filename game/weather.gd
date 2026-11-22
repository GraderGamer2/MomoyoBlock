class_name WeatherLayer
extends Node2D

var _kind := ""
var _offset := 0.0
var _redraw_in := 0.0


func _ready() -> void:
	set_process(false)


func set_front(kind: String) -> void:
	if _kind == kind:
		return
	_kind = kind
	visible = not kind.is_empty()
	set_process(visible)
	queue_redraw()


func _process(delta: float) -> void:
	_offset += delta
	_redraw_in += delta
	if _redraw_in >= 1.0 / 24.0:
		_redraw_in = 0.0
		queue_redraw()


func _draw() -> void:
	if _kind.is_empty():
		return
	var size := get_viewport_rect().size
	var snow := _kind == "Snow"
	var rain := _kind == "Rain"
	var tint := Color(0.23, 0.50, 0.69, 0.13) if rain or snow else Color(0.78, 0.46, 0.35, 0.16)
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	for i in 52:
		var x := fposmod(i * 83.0 + _offset * (120.0 if rain else 72.0), size.x)
		var y := fposmod(i * 119.0 + _offset * (450.0 if rain else 64.0), size.y)
		var extent := Vector2(3.0, 14.0) if rain else Vector2(5.0, 2.0)
		if snow:
			extent = Vector2(3.0, 3.0)
		draw_line(Vector2(x, y), Vector2(x, y) + extent, Color(0.83, 0.92, 0.98, 0.4), 1.5)
