class_name WeatherLayer
extends Node2D

var _kind := ""
var _offset := 0.0
var _wind := 0.0
var _redraw_in := 0.0


func _ready() -> void:
	set_process(false)


func set_front(kind: String, wind: float) -> void:
	if _kind == kind and _wind == wind:
		return
	_kind = kind
	_wind = wind
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
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var snow := _kind == "Snow" or _kind == "Whiteout"
	var rain := _kind == "Rain" or _kind == "Rainstorm"
	var haze := _kind == "Fog" or _kind == "Haze"
	var harsh := PlanetProfile.harsh_weather(_kind)
	var tint := Color(0.24, 0.49, 0.65, 0.13) if rain or snow else Color(0.78, 0.46, 0.35, 0.16)
	if haze:
		tint = Color(0.68, 0.69, 0.77, 0.21)
	draw_rect(Rect2(Vector2.ZERO, size), tint)
	if haze:
		return
	var extent := Vector2(_wind * 0.024, 14.0) if rain else Vector2(6.0 if not snow else 3.0, 2.0)
	for i in (64 if harsh else 45):
		var x := fposmod(i * 83.0 + _offset * _wind, size.x)
		var y := fposmod(i * 119.0 + _offset * (450.0 if rain else 64.0), size.y)
		draw_line(Vector2(x, y), Vector2(x, y) + extent, Color(0.83, 0.92, 0.98, 0.4), 1.5)
