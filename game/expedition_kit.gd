class_name ExpeditionKit
extends RefCounted

enum Recipe { WORKBENCH, SMELT, REPAIR, PROSPECTOR, CANISTER, LINER }

const MAX_CANISTERS := 6
const MAX_WORKBENCHES := 99
const CANISTER_REFILL := 45.0
const ALLOY_YIELD := 3
const ALLOY_SLOT := 2
const STARTER_REACH := 1.8 * BlockWorld.TILE_SIZE
const PROSPECTOR_REACH := 2.5 * BlockWorld.TILE_SIZE
const RECIPES := [
	{
		"name": "Field workbench", "benefit": "Place with slot 5 to craft and repair nearby.",
		"cost": [2, 4, 0, 0],
	},
	{
		"name": "Smelt alloy", "benefit": "Refines ore into 3 alloy.",
		"cost": [0, 0, 0, 2],
	},
	{
		"name": "Repair suit", "benefit": "Restores suit integrity to 100%.",
		"cost": [0, 0, 3, 0],
	},
	{
		"name": "Prospector module", "benefit": "Extends pulse range and mines hard blocks faster.",
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

var prospector := false
var canisters := 0
var liner := false
var workbenches := 0


func pulse_reach_squared() -> float:
	return PROSPECTOR_REACH * PROSPECTOR_REACH if prospector else STARTER_REACH * STARTER_REACH


func available(recipe: int, materials: PackedInt32Array, vitals: SurvivalState) -> bool:
	if recipe < 0 or recipe >= RECIPES.size():
		return false
	match recipe:
		Recipe.WORKBENCH:
			if workbenches >= MAX_WORKBENCHES:
				return false
		Recipe.SMELT:
			if materials[ALLOY_SLOT] > BlockWorld.MATERIAL_LIMIT - ALLOY_YIELD:
				return false
		Recipe.REPAIR:
			if vitals.suit_integrity >= SurvivalState.MAX_LEVEL:
				return false
		Recipe.PROSPECTOR:
			if prospector:
				return false
		Recipe.CANISTER:
			if canisters >= MAX_CANISTERS:
				return false
		Recipe.LINER:
			if liner:
				return false
	var cost: Array = RECIPES[recipe].cost
	for slot in cost.size():
		if materials[slot] < cost[slot]:
			return false
	return true


func craft(recipe: int, materials: PackedInt32Array, vitals: SurvivalState) -> bool:
	if not available(recipe, materials, vitals):
		return false
	var cost: Array = RECIPES[recipe].cost
	for slot in cost.size():
		materials[slot] -= cost[slot]
	match recipe:
		Recipe.WORKBENCH:
			workbenches += 1
		Recipe.SMELT:
			materials[ALLOY_SLOT] += ALLOY_YIELD
		Recipe.REPAIR:
			vitals.suit_integrity = SurvivalState.MAX_LEVEL
		Recipe.PROSPECTOR:
			prospector = true
		Recipe.CANISTER:
			canisters += 1
		Recipe.LINER:
			liner = true
	return true


func use_canister(vitals: SurvivalState) -> bool:
	if canisters == 0 or not vitals.suit_active() or vitals.oxygen >= SurvivalState.MAX_LEVEL:
		return false
	canisters -= 1
	vitals.oxygen = minf(SurvivalState.MAX_LEVEL, vitals.oxygen + CANISTER_REFILL)
	return true


func snapshot() -> Dictionary:
	return {"prospector": prospector, "liner": liner, "canisters": canisters, "workbenches": workbenches}


func restore(data: Dictionary) -> void:
	prospector = data.prospector
	liner = data.liner
	canisters = data.canisters
	workbenches = data.workbenches


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("prospector") is bool or not data.get("liner") is bool:
		return false
	var stored: Variant = data.get("canisters")
	var benches: Variant = data.get("workbenches")
	return stored is int and stored >= 0 and stored <= MAX_CANISTERS \
			and benches is int and benches >= 0 and benches <= MAX_WORKBENCHES


static func cost_text(recipe: int) -> String:
	var cost: Array = RECIPES[recipe].cost
	var parts := PackedStringArray()
	for slot in cost.size():
		if cost[slot] > 0:
			parts.append("%d %s" % [cost[slot], BlockWorld.MATERIAL_NAMES[slot]])
	return " + ".join(parts)
