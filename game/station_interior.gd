class_name StationInterior
extends Node2D

const TILE := BlockWorld.TILE_SIZE
const PANEL := Color("#172b3e")
const STEEL := Color("#4d7185")
const PAPER := Color("#d6e9ee")
const AIR := Color("#8ae2be")
const LEAK := Color("#e99471")

var _sealed := true


func show_integrity(sealed: bool) -> void:
	if sealed != _sealed:
		_sealed = sealed
		queue_redraw()


func _draw() -> void:
	var cabin := BlockWorld.STATION_CABIN
	var room := Rect2(Vector2(cabin.position * TILE), Vector2(cabin.size * TILE))
	var indicator := AIR if _sealed else LEAK
	var wall_top := room.position.y
	var deck := room.end.y
	draw_rect(room, Color("#101d2e"))
	draw_rect(Rect2(room.position, Vector2(room.size.x, 18.0)), PANEL)
	draw_rect(Rect2(Vector2(room.position.x, deck - 21.0), Vector2(room.size.x, 21.0)), PANEL)
	draw_line(Vector2(room.position.x, deck - 8.0), Vector2(room.end.x, deck - 8.0), STEEL, 1.0)

	for i in 5:
		var x := room.position.x + 14.0 + i * 129.0
		var window := Rect2(x, wall_top + 28.0, 105.0, 52.0)
		draw_rect(window.grow(4.0), Color("#233e51"))
		draw_rect(window, Color("#203551"))
		draw_line(window.position, Vector2(window.end.x, window.position.y), Color("#679598"), 2.0)
		draw_line(Vector2(window.position.x, window.end.y), window.end, Color("#0f1a2f"), 3.0)
		draw_circle(window.position + Vector2(23 + 8 * (i % 3), 18), 1.1, PAPER)
		draw_circle(window.position + Vector2(76, 14 + 7 * (i % 4)), 0.8, Color("#bdc0e7"))
		draw_rect(Rect2(window.position.x + 43.0, wall_top + 9.0, 24.0, 3.0), indicator)

	var bench := (BlockWorld.STATION_WORKBENCH.x + 0.5) * TILE
	draw_rect(Rect2(bench - 47.0, deck - 31.0, 94.0, 8.0), STEEL)
	draw_rect(Rect2(bench - 40.0, deck - 23.0, 80.0, 23.0), Color("#263f50"))
	draw_rect(Rect2(bench + 11.0, deck - 46.0, 28.0, 17.0), Color("#365464"))
	draw_rect(Rect2(bench + 14.0, deck - 43.0, 22.0, 10.0), Color("#63b8ad"))
	draw_line(Vector2(bench - 28.0, deck - 12.0), Vector2(bench + 29.0, deck - 12.0), STEEL, 1.0)
	_label("WORKSHOP", bench - 64.0, deck - 52.0, 128.0, PAPER)

	var service := 97.0
	for bin in 3:
		var x := service + bin * 18.0
		draw_rect(Rect2(x, deck - 64.0, 12.0, 48.0), Color("#38506a"))
		draw_rect(Rect2(x + 3.0, deck - 54.0, 6.0, 31.0), indicator.darkened(0.23))
	_label("LIFE SUPPORT", service - 25.0, deck - 70.0, 100.0, indicator)

	var hatch := BlockWorld.STATION_HATCH * TILE
	draw_rect(Rect2(hatch.x, hatch.y, TILE, TILE * 3), Color("#274756"))
	draw_rect(Rect2(hatch.x + 3.0, hatch.y + 6.0, TILE - 6.0, TILE * 3 - 6.0), Color("#182c3b"))
	draw_rect(Rect2(hatch.x + 6.0, hatch.y + 10.0, TILE - 12.0, 5.0), indicator)
	draw_rect(Rect2(hatch.x + TILE, hatch.y + 2.0, 88.0, 20.0), PANEL)
	_label("←  AIRLOCK", hatch.x + TILE, hatch.y + 16.0, 88.0, indicator)

	var outside := hatch.x + 2.0 * TILE
	draw_rect(Rect2(outside, deck - 11.0, 12.0 * TILE, 2.0), STEEL)
	for i in 12:
		var x := outside + i * TILE
		draw_line(Vector2(x, deck - 11), Vector2(x, deck), STEEL, 2.0)
		if i % 3 == 0:
			draw_rect(Rect2(x - 3, deck - 13, 6, 4), Color("#f0b875"))
	_label("EVA DECK", outside + 36.0, deck - 25.0, 120.0, Color("#eac593"))

	var mast := room.position.x + 130.0
	draw_line(Vector2(mast, wall_top - TILE), Vector2(mast, wall_top - 76.0), STEEL, 3.0)
	draw_line(Vector2(mast - 23.0, wall_top - 59.0), Vector2(mast + 23.0, wall_top - 59.0), STEEL, 2.0)
	draw_circle(Vector2(mast, wall_top - 78.0), 3.0, Color("#ecbd85"))

	var array_top := Vector2(room.end.x - 280.0, wall_top - 71.0)
	var axle := array_top + Vector2(110.0, 29.0)
	draw_line(axle, Vector2(axle.x, wall_top - TILE), STEEL, 6.0)
	draw_line(axle + Vector2(32.0, 0.0), Vector2(axle.x + 15.0, wall_top - TILE), STEEL, 2.0)
	draw_rect(Rect2(array_top - Vector2(3.0, 3.0), Vector2(226.0, 36.0)), STEEL)
	for panel in 4:
		var p := array_top + Vector2(panel * 56.0, 0.0)
		draw_rect(Rect2(p, Vector2(52.0, 30.0)), Color("#233653"))
		for strip in range(1, 4):
			var edge := p + Vector2(strip * 13.0, 2.0)
			draw_line(edge, edge + Vector2(0.0, 26.0), Color("#465d83"), 1.0)
		draw_line(p + Vector2(2.0, 15.0), p + Vector2(50.0, 15.0), Color("#465d83"), 1.0)


func _label(caption: String, x: float, y: float, width: float, tint: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_CENTER, width, 12, tint)
