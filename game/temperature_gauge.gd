class_name TemperatureGauge
extends Control

const COLD := Color("#83cdef")
const HOT := Color("#f4a787")
const COMFORT_MIN := 36.0
const COMFORT_MAX := 38.0
const INSET := 3.0
const TRACK_HEIGHT := 6.0

var _temperature := SurvivalState.NORMAL_BODY_TEMPERATURE


func _ready() -> void:
	resized.connect(queue_redraw)


func show_temperature(value: float) -> void:
	if not is_equal_approx(_temperature, value):
		_temperature = value
		queue_redraw()


func _draw() -> void:
	var y := floorf((size.y - TRACK_HEIGHT) * 0.5)
	var cold_limit := _position(SurvivalState.COLD_STRESS_TEMPERATURE)
	var hot_limit := _position(SurvivalState.HEAT_STRESS_TEMPERATURE)
	var comfort_start := _position(COMFORT_MIN)
	var comfort_end := _position(COMFORT_MAX)
	draw_rect(Rect2(0.0, y, size.x, TRACK_HEIGHT), Color("#34495a"))
	draw_rect(Rect2(0.0, y, cold_limit, TRACK_HEIGHT), Color("#396c8e"))
	draw_rect(Rect2(comfort_start, y, comfort_end - comfort_start, TRACK_HEIGHT), Color("#548b7c"))
	draw_rect(Rect2(hot_limit, y, size.x - hot_limit, TRACK_HEIGHT), Color("#94584c"))

	var marker := _position(_temperature)
	draw_rect(Rect2(marker - 2.0, y - 2.0, 5.0, TRACK_HEIGHT + 4.0), Color("#102033"))
	draw_rect(Rect2(marker - 1.0, y - 2.0, 3.0, TRACK_HEIGHT + 4.0), Color("#edf5f4"))


func _position(value: float) -> float:
	var ratio := inverse_lerp(SurvivalState.MIN_BODY_TEMPERATURE, SurvivalState.MAX_BODY_TEMPERATURE, value)
	return roundf(lerpf(INSET, size.x - INSET, ratio))
