class_name Horizon
extends Node2D

var _region := BlockWorld.Region.SURFACE
var _planet: PlanetProfile


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func show_region(region: int, planet: PlanetProfile = null) -> void:
	_region = region
	_planet = planet
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var in_orbit := _region == BlockWorld.Region.STATION
	var sky_top := Color("#10142c") if in_orbit else Color("#152641")
	var horizon := Color("#709e90") if _planet == null else Color(_planet.details.sky)
	var sky_bottom := Color("#2b2747") if in_orbit else horizon
	var band_height := size.y / 36.0
	for band in 36:
		draw_rect(Rect2(0.0, band * band_height, size.x, band_height + 1.0),
				sky_top.lerp(sky_bottom, band / 35.0))

	var random := RandomNumberGenerator.new()
	random.seed = 16 if in_orbit else 61
	for star in (90 if in_orbit else 24):
		var point := Vector2(random.randf(), random.randf() * (0.86 if in_orbit else 0.52)) * size
		var extent := 2.0 if star % 9 == 0 else 1.0
		var alpha := random.randf_range(0.23, 0.78) if in_orbit else 0.24
		draw_rect(Rect2(point, Vector2.ONE * extent), Color(0.81, 0.92, 0.88, alpha))

	if in_orbit:
		var center := size * Vector2(0.73, 0.67)
		var radius := size.y * 0.32
		draw_circle(center, radius + 5.0, Color("#493f62"), true, -1.0, true)
		draw_circle(center, radius, Color("#686183"), true, -1.0, true)
		draw_arc(center, radius * 0.89, 0.66, 2.86, 40, Color("#80728f"), 4.0, true)
		draw_arc(center, radius * 0.69, 0.54, 2.86, 40, Color("#887791"), 3.0, true)
		draw_set_transform(center, -0.22, Vector2(1.0, 0.26))
		draw_arc(Vector2.ZERO, radius * 1.54, 0.0, PI, 64, Color("#c198a9"), 6.0, true)
		draw_arc(Vector2.ZERO, radius * 1.67, 0.0, PI, 64, Color("#786581"), 4.0, true)
	else:
		draw_circle(size * Vector2(0.74, 0.26), size.y * 0.061, Color("#f1ce91"), true, -1.0, true)
		_draw_ridge(size, 0.55, 0.12, 1.0, Color("#406276"))
		_draw_ridge(size, 0.66, 0.10, 3.0, Color("#355566"))


func _draw_ridge(size: Vector2, baseline: float, height: float, phase: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for i in 25:
		var progress := i / 24.0
		var slope := absf(sin(progress * 16.0 + phase) * cos(progress * 5.0 + phase))
		points.append(Vector2(progress * size.x, (baseline - slope * height) * size.y))
	points.append(size)
	points.append(Vector2(0.0, size.y))
	draw_colored_polygon(points, tint)
