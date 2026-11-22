class_name PlanetProfile
extends RefCounted

const LEGACY_PROFILES := [
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

const NAME_START := ["Aev", "Bel", "Cael", "Dra", "Eri", "Fae", "Gal", "Hel", "Ily", "Jor", "Kae", "Lun", "Mer", "Nyr", "Oss", "Pra", "Quel", "Rho", "Sae", "Tor", "Ul", "Vael", "Wre", "Zer"]
const NAME_END := ["ara", "aris", "ea", "eron", "eth", "ia", "in", "ion", "is", "ora", "os", "una", "une", "ys"]
const LANDMARKS := ["Basin", "Crown", "Dawn", "Drift", "Dunes", "Expanse", "Haven", "Heights", "Reach", "Rift", "Vale", "Wilds"]
const LIFE_TRAITS := ["Amber", "Cloud", "Copper", "Dusk", "Frost", "Glass", "Ink", "Ivory", "Jade", "Ochre", "Opal", "Pearl", "Saffron", "Silver", "Spiral", "Star"]
const PLANTS := ["berry", "bloom", "cap", "fern", "leaf", "moss", "reed", "root", "sprout"]
const FLUIDS := ["dew pods", "ice buds", "mist nodules", "rain cups", "sap bulbs", "water reeds"]
const CREATURES := ["drifters", "gliders", "hoppers", "lopers", "runners", "skippers", "wanderers"]
const CLIMATES := ["Temperate", "Arid", "Frozen", "Humid", "Volcanic", "Highland"]
const BASE_TEMPERATURES := [19.0, 40.0, -24.0, 29.0, 54.0, 7.0]
const LEGACY_PRESSURES := [101, 36, 78, 19]
const FRONTS := [
	["Rain", "Fog", "Rainstorm"],
	["Dust storm", "Haze", "Dry wind"],
	["Snow", "Whiteout", "Fog"],
	["Rain", "Rainstorm", "Fog"],
	["Ashfall", "Haze", "Dry wind"],
	["Snow", "Rain", "Dry wind"],
]

var sector: Vector2i
var seed: int
var legacy: bool
var kind: int
var details: Dictionary
var fronts: Array
var weather_period: int
var weather_offset: int
var wind: float
var food_column: int
var water_column: int
var pressure_kpa: int
var _mean_temperature: float
var _day_length: float
var _temperature_swing: float


func _init(address: Vector2i, universe_seed: int = 0) -> void:
	sector = address
	legacy = universe_seed == 0
	if legacy:
		seed = 472913 if sector == Vector2i.ZERO else hash_cell(sector.x, sector.y, 834137)
		kind = seed % LEGACY_PROFILES.size()
		if sector == Vector2i.ZERO:
			kind = 0
		elif sector == Vector2i.RIGHT:
			kind = 1
		details = LEGACY_PROFILES[kind].duplicate()
		fronts = [details.weather]
		weather_period = 70
		weather_offset = 0 if sector == Vector2i.ZERO else seed % 70
		food_column = -6
		water_column = 7
		pressure_kpa = LEGACY_PRESSURES[kind]
		_mean_temperature = BASE_TEMPERATURES[kind]
	else:
		var low := _mix_32(sector.x ^ universe_seed ^ _mix_32(sector.y ^ (universe_seed >> 32)))
		var high := _mix_32(sector.y ^ (universe_seed >> 32) ^ _mix_32(sector.x ^ universe_seed ^ 0x91b8fcc5))
		seed = (high << 32) | low
		kind = sample(1) % CLIMATES.size()
		fronts = FRONTS[kind]
		weather_period = 57 + sample(2) % 67
		weather_offset = sample(3) % weather_period
		food_column = -4 - sample(4) % 4
		water_column = 4 + sample(5) % 4
		details = {
			"name": NAME_START[sample(6) % NAME_START.size()] + NAME_END[sample(7) % NAME_END.size()] + " " + LANDMARKS[sample(8) % LANDMARKS.size()],
			"biome": CLIMATES[kind],
			"flora": LIFE_TRAITS[sample(9) % LIFE_TRAITS.size()] + PLANTS[sample(10) % PLANTS.size()],
			"water": LIFE_TRAITS[sample(11) % LIFE_TRAITS.size()] + " " + FLUIDS[sample(12) % FLUIDS.size()],
			"fauna": LIFE_TRAITS[sample(13) % LIFE_TRAITS.size()] + " " + CREATURES[sample(14) % CREATURES.size()],
			"sky": Color.from_hsv(unit(15), 0.22 + 0.20 * unit(16), 0.53 + 0.21 * unit(17)),
			"breathable": sample(18) % 5 < 3,
			"gravity": 590.0 + float(sample(19) % 421),
			"relief": 0.55 + 0.9 * unit(20),
		}

		# The pressure range is seeded with atmospheric composition. Oxygen-poor
		# worlds can have thin air or a dense atmosphere that strains a suit.
		if details.breathable:
			pressure_kpa = 65 + sample(42) % 91
		elif sample(44) % 3 == 0:
			pressure_kpa = 178 + sample(42) % 58
		else:
			pressure_kpa = 12 + sample(42) % 76
		_mean_temperature = BASE_TEMPERATURES[kind] + lerpf(-10.0, 10.0, unit(45))

	_day_length = 170.0 + 140.0 * unit(46)
	_temperature_swing = lerpf(6.0, 19.0, unit(47))
	wind = lerpf(48.0, 170.0, unit(21)) * (-1.0 if sample(22) % 2 == 0 else 1.0)
	details["plant_color"] = Color.from_hsv(unit(23), 0.36 + 0.42 * unit(24), 0.78)
	details["fruit_color"] = Color.from_hsv(unit(25), 0.5, 0.98)
	details["plant_form"] = sample(26) % 3
	details["animal_color"] = Color.from_hsv(unit(27), 0.26 + 0.35 * unit(28), 0.81)
	details["animal_form"] = sample(29) % 3
	details["animal_size"] = 5.0 + 5.0 * unit(30)
	details["animal_speed"] = 0.46 + 0.62 * unit(31)
	details["fauna_spacing"] = 7 + sample(32) % 11
	details["soil_color"] = Color.from_hsv(unit(33), 0.32 + 0.23 * unit(34), 0.46 + 0.19 * unit(35))
	details["rock_color"] = Color.from_hsv(unit(36), 0.13 + 0.19 * unit(37), 0.34 + 0.14 * unit(38))
	details["surface_color"] = Color.from_hsv(unit(39), 0.27 + 0.20 * unit(40), 0.70 + 0.13 * unit(41))


func title() -> String:
	return details.name


func chart_title() -> String:
	return "%s  /  %d, %d" % [title(), sector.x, sector.y]


func weather_at(elapsed: float) -> String:
	var local_time := elapsed + weather_offset
	var phase := fposmod(local_time, float(weather_period))
	if legacy:
		return fronts[0] if phase >= 47.0 else ""

	var cycle := floori(local_time / weather_period)
	var pat := hash_cell(cycle, 43, terrain_salt())
	var start := 23 + pat % maxi(1, weather_period - 51)
	var duration := 13 + (pat >> 9) % 21
	if phase < start or phase >= start + duration:
		return ""
	return fronts[(pat >> 17) % fronts.size()]


func temperature_at(elapsed: float, front: String) -> float:
	var phase := fposmod(elapsed + weather_offset, _day_length) / _day_length
	var cooling := 0.0
	match front:
		"Rain", "Rainstorm", "Fog":
			cooling = 4.0
		"Snow", "Whiteout":
			cooling = 8.0
	return _mean_temperature + sin(phase * TAU) * _temperature_swing - cooling


static func harsh_weather(front: String) -> bool:
	return front in ["Rainstorm", "Dust storm", "Whiteout", "Dry wind", "Ashfall"]


func terrain_salt() -> int:
	return seed if legacy else (seed ^ (seed >> 32)) & 0x7fffffff


func sample(channel: int) -> int:
	return _mix_32(seed ^ _mix_32((seed >> 32) ^ (channel * 0x9e3779b9)))


func unit(channel: int) -> float:
	return float(sample(channel)) / 4294967295.0


static func _mix_32(value: int) -> int:
	value &= 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0xffffffff
	return value ^ (value >> 16)


static func hash_cell(x: int, y: int, salt: int) -> int:
	var value := ((x * 374761393) ^ (y * 668265263) ^ salt) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return value ^ (value >> 16)
