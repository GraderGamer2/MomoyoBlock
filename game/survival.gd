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

var health := MAX_LEVEL
var hunger := MAX_LEVEL
var thirst := MAX_LEVEL
var oxygen := MAX_LEVEL
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

	var damage := maxf(0.0, float(pressure - SUIT_PRESSURE_LIMIT)) * (0.004 if reinforced else 0.020)
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
	food = 1
	water = 1


func snapshot() -> Dictionary:
	return {
		"health": health, "hunger": hunger, "thirst": thirst, "oxygen": oxygen,
		"food": food, "water": water, "elapsed": elapsed,
	}


func restore(data: Dictionary) -> void:
	health = data.health
	hunger = data.hunger
	thirst = data.thirst
	oxygen = data.oxygen
	food = data.food
	water = data.water
	elapsed = data.elapsed


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary:
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
