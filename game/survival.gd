class_name SurvivalState
extends RefCounted

const MAX_LEVEL := 100.0
const TICK := 0.25
const MAX_SUPPLIES := 99
const VACUUM_DRAIN := 1.10
const STORM_SURCHARGE := 0.20
const HYPOXIA_DAMAGE := 4.0
const SUIT_PRESSURE_LIMIT := 175
const CABIN_TEMPERATURE := 21.0
const CABIN_PRESSURE := 101
const NORMAL_BODY_TEMPERATURE := 37.0
const MIN_BODY_TEMPERATURE := 31.0
const MAX_BODY_TEMPERATURE := 43.0
const COLD_STRESS_TEMPERATURE := 34.0
const HEAT_STRESS_TEMPERATURE := 40.0
const RECOVERY_TIME := 20.0
const EXPOSURE_TIME := 65.0
const STORM_EXPOSURE_TIME := 50.0

var health := MAX_LEVEL
var hunger := MAX_LEVEL
var thirst := MAX_LEVEL
var oxygen := MAX_LEVEL
var body_temperature := NORMAL_BODY_TEMPERATURE
var food := 2
var water := 2
var elapsed := 0.0


func advance(seconds: float, breathable: bool, harsh_weather: bool, pressure := CABIN_PRESSURE,
		temperature := CABIN_TEMPERATURE, reinforced := false) -> void:
	elapsed += seconds
	var cold := clampf((4.0 - temperature) * 0.002, 0.0, 0.11)
	var heat := clampf((temperature - 28.0) * 0.004, 0.0, 0.19)
	hunger = maxf(0.0, hunger - (0.17 + cold) * seconds)
	thirst = maxf(0.0, thirst - (0.29 + heat + (0.20 if harsh_weather else 0.0)) * seconds)
	var oxygen_rate := 16.0 if breathable else -(VACUUM_DRAIN + (STORM_SURCHARGE if harsh_weather else 0.0))
	oxygen = clampf(oxygen + oxygen_rate * seconds, 0.0, MAX_LEVEL)

	var thermal_target := body_temperature_target(temperature)
	var response_time := STORM_EXPOSURE_TIME if harsh_weather else EXPOSURE_TIME
	if thermal_target == NORMAL_BODY_TEMPERATURE:
		response_time = RECOVERY_TIME
	body_temperature = lerpf(body_temperature, thermal_target, 1.0 - exp(-seconds / response_time))

	var damage := maxf(0.0, float(pressure - SUIT_PRESSURE_LIMIT)) * (0.004 if reinforced else 0.020)
	var thermal_stress := maxf(0.0, COLD_STRESS_TEMPERATURE - body_temperature) \
			+ maxf(0.0, body_temperature - HEAT_STRESS_TEMPERATURE)
	damage += thermal_stress * 0.35
	if hunger <= 0.0:
		damage += 1.4
	if thirst <= 0.0:
		damage += 2.8
	if oxygen <= 0.0:
		damage += HYPOXIA_DAMAGE
	if damage > 0.0:
		health = maxf(0.0, health - damage * seconds)
	elif minf(hunger, thirst) > 72.0 and oxygen > 70.0:
		health = minf(MAX_LEVEL, health + 0.5 * seconds)


static func body_temperature_target(ambient: float) -> float:
	var exposure := ambient - clampf(ambient, 12.0, 28.0)
	return clampf(NORMAL_BODY_TEMPERATURE + exposure * 0.17, MIN_BODY_TEMPERATURE, MAX_BODY_TEMPERATURE)


func eat() -> bool:
	if food == 0 or hunger >= MAX_LEVEL:
		return false
	food -= 1
	hunger = minf(MAX_LEVEL, hunger + 38.0)
	return true


func drink() -> bool:
	if water == 0 or thirst >= MAX_LEVEL:
		return false
	water -= 1
	thirst = minf(MAX_LEVEL, thirst + 48.0)
	return true


func restore_after_rescue() -> void:
	health = MAX_LEVEL
	hunger = 60.0
	thirst = 60.0
	oxygen = MAX_LEVEL
	body_temperature = NORMAL_BODY_TEMPERATURE
	food = 1
	water = 1


func snapshot() -> Dictionary:
	return {
		"health": health, "hunger": hunger, "thirst": thirst, "oxygen": oxygen,
		"body_temperature": body_temperature, "food": food, "water": water, "elapsed": elapsed,
	}


func restore(data: Dictionary) -> void:
	health = data.health
	hunger = data.hunger
	thirst = data.thirst
	oxygen = data.oxygen
	body_temperature = data.body_temperature
	food = data.food
	water = data.water
	elapsed = data.elapsed


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var temperature: Variant = data.get("body_temperature")
	if not (temperature is float or temperature is int) or not is_finite(float(temperature)):
		return false
	if temperature < MIN_BODY_TEMPERATURE or temperature > MAX_BODY_TEMPERATURE:
		return false
	for key in ["health", "hunger", "thirst", "oxygen", "elapsed"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0:
			return false
		if key != "elapsed" and value > MAX_LEVEL:
			return false
	for key in ["food", "water"]:
		var count: Variant = data.get(key)
		if not count is int or count < 0 or count > MAX_SUPPLIES:
			return false
	return true
