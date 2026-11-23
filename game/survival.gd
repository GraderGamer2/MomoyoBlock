class_name SurvivalState
extends RefCounted

const MAX_LEVEL := 100.0
const TICK := 0.25
const VACUUM_DRAIN := 1.10
const VACUUM_GRACE := 8.0
const VACUUM_DAMAGE := 2.0
const STORM_SURCHARGE := 0.20
const HYPOXIA_DAMAGE := 4.0
const SUIT_PRESSURE_LIMIT := 175
const SUIT_LEAK_START := 55.0
const RESCUE_SUIT_INTEGRITY := 35.0
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
const BARE_EXPOSURE_TIME := 27.0
const BARE_STORM_EXPOSURE_TIME := 18.0
const JETPACK_CAPACITY := 1.5
const JETPACK_COOLDOWN := 1.25
const JETPACK_RECHARGE := 1.0

var health := MAX_LEVEL
var hunger := MAX_LEVEL
var thirst := MAX_LEVEL
var oxygen := MAX_LEVEL
var suit_integrity := MAX_LEVEL
var suit_equipped := true
var body_temperature := NORMAL_BODY_TEMPERATURE
var vacuum_exposure := 0.0
var jetpack_fuel := JETPACK_CAPACITY
var jetpack_cooldown := 0.0
var elapsed := 0.0
var _jetpack_running := false


func advance(seconds: float, breathable: bool, storm_wear: float, pressure: float = CABIN_PRESSURE,
		temperature := CABIN_TEMPERATURE, reinforced := false, orbital := false) -> void:
	elapsed += seconds
	var harsh_weather := storm_wear > 0.0
	var cold := clampf((4.0 - temperature) * 0.002, 0.0, 0.11)
	var heat := clampf((temperature - 28.0) * 0.004, 0.0, 0.19)
	hunger = maxf(0.0, hunger - (0.17 + cold) * seconds)
	thirst = maxf(0.0, thirst - (0.29 + heat + (0.20 if harsh_weather else 0.0)) * seconds)

	var pressure_strain := maxf(0.0, float(pressure - SUIT_PRESSURE_LIMIT))
	var liner_factor := 0.2 if reinforced else 1.0
	damage_suit(seconds * (storm_wear + pressure_strain * 0.016 * liner_factor))
	var protected := suit_active()
	var without_oxygen := seconds
	if protected:
		var leak := maxf(0.0, SUIT_LEAK_START - suit_integrity) / SUIT_LEAK_START
		var drain := VACUUM_DRAIN + leak * 1.4 + (STORM_SURCHARGE if harsh_weather else 0.0)
		var oxygen_rate := 16.0 if breathable else -drain
		without_oxygen = maxf(0.0, seconds - oxygen / drain)
		oxygen = clampf(oxygen + oxygen_rate * seconds, 0.0, MAX_LEVEL)

	var thermal_target := body_temperature_target(temperature)
	var response_time := STORM_EXPOSURE_TIME if harsh_weather else EXPOSURE_TIME
	if not protected:
		response_time = BARE_STORM_EXPOSURE_TIME if harsh_weather else BARE_EXPOSURE_TIME
	if thermal_target == NORMAL_BODY_TEMPERATURE:
		response_time = RECOVERY_TIME
	body_temperature = lerpf(body_temperature, thermal_target, 1.0 - exp(-seconds / response_time))

	var airless_vacuum := (orbital or pressure == 0.0) and not breathable and (not protected or oxygen <= 0.0)
	var loss := 0.0
	if airless_vacuum:
		var exposure := vacuum_exposure + without_oxygen
		loss = VACUUM_DAMAGE * maxf(0.0, exposure - VACUUM_GRACE)
		vacuum_exposure = minf(exposure, VACUUM_GRACE)
	else:
		vacuum_exposure = 0.0
		loss = seconds * _environment_damage(breathable, protected, storm_wear, pressure, pressure_strain, liner_factor)
	if hunger <= 0.0:
		loss += 1.4 * seconds
	if thirst <= 0.0:
		loss += 2.8 * seconds
	if loss > 0.0:
		health = maxf(0.0, health - loss)
	elif minf(hunger, thirst) > 72.0 and (breathable or (protected and oxygen > 70.0)):
		health = minf(MAX_LEVEL, health + 0.5 * seconds)


func _environment_damage(breathable: bool, protected: bool, storm_wear: float, pressure: float,
		pressure_strain: float, liner_factor: float) -> float:
	var damage := pressure_strain * 0.020 * liner_factor
	if not protected:
		var extreme_pressure := maxf(0.0, 50.0 - pressure) + maxf(0.0, pressure - 155.0)
		damage = extreme_pressure * 0.035 + storm_wear * 3.0
	if not breathable:
		if not protected:
			damage += 9.0
		elif oxygen <= 0.0:
			damage += HYPOXIA_DAMAGE
	var thermal_stress := maxf(0.0, COLD_STRESS_TEMPERATURE - body_temperature) \
			+ maxf(0.0, body_temperature - HEAT_STRESS_TEMPERATURE)
	return damage + thermal_stress * (0.35 if protected else 0.65)


func suit_active() -> bool:
	return suit_equipped and suit_integrity > 0.0


func damage_suit(amount: float) -> void:
	if suit_active():
		suit_integrity = maxf(0.0, suit_integrity - amount)


func vacuum_exposure_temperature() -> float:
	var protection := suit_integrity / MAX_LEVEL if suit_active() else 0.0
	return lerpf(-55.0, -4.0, protection)


func burn_jetpack(seconds: float, requested: bool, grounded: bool) -> float:
	if requested and suit_active() and jetpack_fuel > 0.0 and (_jetpack_running or jetpack_fuel == JETPACK_CAPACITY):
		var burn := minf(jetpack_fuel, seconds)
		jetpack_fuel -= burn
		_jetpack_running = jetpack_fuel > 0.0
		jetpack_cooldown = JETPACK_COOLDOWN
		return burn
	_jetpack_running = false
	var charging_time := maxf(0.0, seconds - jetpack_cooldown)
	jetpack_cooldown = maxf(0.0, jetpack_cooldown - seconds)
	if grounded and suit_active():
		jetpack_fuel = minf(JETPACK_CAPACITY, jetpack_fuel + charging_time * JETPACK_RECHARGE)
	return 0.0


static func body_temperature_target(ambient: float) -> float:
	var exposure := ambient - clampf(ambient, 12.0, 28.0)
	return clampf(NORMAL_BODY_TEMPERATURE + exposure * 0.17, MIN_BODY_TEMPERATURE, MAX_BODY_TEMPERATURE)


func eat() -> bool:
	if hunger >= MAX_LEVEL:
		return false
	hunger = minf(MAX_LEVEL, hunger + 38.0)
	return true


func drink() -> bool:
	if thirst >= MAX_LEVEL:
		return false
	thirst = minf(MAX_LEVEL, thirst + 48.0)
	return true


func restore_after_rescue() -> void:
	health = MAX_LEVEL
	hunger = 60.0
	thirst = 60.0
	oxygen = MAX_LEVEL
	suit_equipped = true
	suit_integrity = maxf(suit_integrity, RESCUE_SUIT_INTEGRITY)
	body_temperature = NORMAL_BODY_TEMPERATURE
	vacuum_exposure = 0.0
	jetpack_fuel = JETPACK_CAPACITY
	jetpack_cooldown = 0.0
	_jetpack_running = false


func snapshot() -> Dictionary:
	return {
		"health": health, "hunger": hunger, "thirst": thirst, "oxygen": oxygen,
		"suit_integrity": suit_integrity, "suit_equipped": suit_equipped,
		"body_temperature": body_temperature, "vacuum_exposure": vacuum_exposure, "elapsed": elapsed,
		"jetpack_fuel": jetpack_fuel, "jetpack_cooldown": jetpack_cooldown,
	}


func restore(data: Dictionary) -> void:
	health = data.health
	hunger = data.hunger
	thirst = data.thirst
	oxygen = data.oxygen
	suit_integrity = data.suit_integrity
	suit_equipped = data.suit_equipped
	body_temperature = data.body_temperature
	vacuum_exposure = data.vacuum_exposure
	jetpack_fuel = data.jetpack_fuel
	jetpack_cooldown = data.jetpack_cooldown
	_jetpack_running = false
	elapsed = data.elapsed


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("suit_equipped") is bool:
		return false
	var temperature: Variant = data.get("body_temperature")
	if not (temperature is float or temperature is int) or not is_finite(float(temperature)):
		return false
	if temperature < MIN_BODY_TEMPERATURE or temperature > MAX_BODY_TEMPERATURE:
		return false
	for key in ["health", "hunger", "thirst", "oxygen", "suit_integrity", "elapsed"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0:
			return false
		if key != "elapsed" and value > MAX_LEVEL:
			return false
	var equipment_limits := {
		"jetpack_fuel": JETPACK_CAPACITY, "jetpack_cooldown": JETPACK_COOLDOWN, "vacuum_exposure": VACUUM_GRACE,
	}
	for key in equipment_limits:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0 or value > equipment_limits[key]:
			return false
	return true
