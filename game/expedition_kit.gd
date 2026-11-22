class_name ExpeditionKit
extends RefCounted

enum Recipe { PICK, CANISTER, LINER }

const MAX_CANISTERS := 6
const CANISTER_REFILL := 45.0
const RECIPES := [
	{
		"name": "Prospector pick", "benefit": "Mines rock, ore, and hull faster.",
		"cost": [0, 4, 2, 0],
	},
	{
		"name": "Air canister", "benefit": "Restores 45 oxygen when used with O.",
		"cost": [0, 0, 3, 1],
	},
	{
		"name": "Pressure liner", "benefit": "Cuts suit damage in dense atmospheres.",
		"cost": [0, 2, 4, 2],
	},
]

var pick := false
var canisters := 0
var liner := false


func available(recipe: int, materials: PackedInt32Array) -> bool:
	if recipe < 0 or recipe >= RECIPES.size():
		return false
	if recipe == Recipe.PICK and pick or recipe == Recipe.LINER and liner:
		return false
	if recipe == Recipe.CANISTER and canisters >= MAX_CANISTERS:
		return false
	var cost: Array = RECIPES[recipe].cost
	for slot in cost.size():
		if materials[slot] < cost[slot]:
			return false
	return true


func craft(recipe: int, materials: PackedInt32Array) -> bool:
	if not available(recipe, materials):
		return false
	var cost: Array = RECIPES[recipe].cost
	for slot in cost.size():
		materials[slot] -= cost[slot]
	match recipe:
		Recipe.PICK:
			pick = true
		Recipe.CANISTER:
			canisters += 1
		Recipe.LINER:
			liner = true
	return true


func use_canister(vitals: SurvivalState) -> bool:
	if canisters == 0 or vitals.oxygen >= SurvivalState.MAX_LEVEL:
		return false
	canisters -= 1
	vitals.oxygen = minf(SurvivalState.MAX_LEVEL, vitals.oxygen + CANISTER_REFILL)
	return true


func snapshot() -> Dictionary:
	return {"pick": pick, "liner": liner, "canisters": canisters}


func restore(data: Dictionary) -> void:
	pick = data.pick
	liner = data.liner
	canisters = data.canisters


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("pick") is bool or not data.get("liner") is bool:
		return false
	var stored: Variant = data.get("canisters")
	return stored is int and stored >= 0 and stored <= MAX_CANISTERS


static func cost_text(recipe: int) -> String:
	var cost: Array = RECIPES[recipe].cost
	var parts := PackedStringArray()
	for slot in cost.size():
		if cost[slot] > 0:
			parts.append("%d %s" % [cost[slot], BlockWorld.MATERIAL_NAMES[slot]])
	return " + ".join(parts)
