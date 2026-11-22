class_name PlanetProfile
extends RefCounted

const TYPES := [
	{
		"name": "Cinder Reach", "biome": "Temperate", "weather": "Rain",
		"flora": "Amberleaf", "water": "Rainwater", "fauna": "Lopers",
		"sky": Color("#709e90"), "breathable": true, "gravity": 940.0, "relief": 1.0,
	},
	{
		"name": "Brass Dunes", "biome": "Arid", "weather": "Dust storm",
		"flora": "Suncap", "water": "Dew cactus", "fauna": "Dune skippers",
		"sky": Color("#bc815c"), "breathable": false, "gravity": 760.0, "relief": 1.3,
	},
	{
		"name": "Glass Tundra", "biome": "Frozen", "weather": "Snow",
		"flora": "Frostberry", "water": "Ice bud", "fauna": "Snow hoppers",
		"sky": Color("#779db0"), "breathable": true, "gravity": 860.0, "relief": 0.66,
	},
	{
		"name": "Violet Basin", "biome": "Thin atmosphere", "weather": "Haze",
		"flora": "Lantern moss", "water": "Mist pod", "fauna": "Basin grazers",
		"sky": Color("#987fa5"), "breathable": false, "gravity": 620.0, "relief": 1.65,
	},
]

var sector: Vector2i
var seed: int
var kind: int
var details: Dictionary


func _init(address: Vector2i) -> void:
	sector = address
	seed = 472913 if sector == Vector2i.ZERO else hash_cell(sector.x, sector.y, 834137)
	# The first jump east always introduces a world that needs suit oxygen.
	if sector == Vector2i.ZERO:
		kind = 0
	elif sector == Vector2i.RIGHT:
		kind = 1
	else:
		kind = seed % TYPES.size()
	details = TYPES[kind]


func title() -> String:
	if sector == Vector2i.ZERO:
		return details.name
	return "%s  /  %d, %d" % [details.name, sector.x, sector.y]


func weather_active(elapsed: float) -> bool:
	var phase := 0 if sector == Vector2i.ZERO else seed % 70
	return fposmod(elapsed + phase, 70.0) >= 47.0


static func hash_cell(x: int, y: int, salt: int) -> int:
	var value := ((x * 374761393) ^ (y * 668265263) ^ salt) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return value ^ (value >> 16)
