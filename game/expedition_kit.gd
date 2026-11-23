class_name ExpeditionKit
extends RefCounted

const B := BlockWorld.Block
enum Recipe { WORKBENCH, SMELT, REPAIR, PULSE_1, PULSE_2, PULSE_3, CANISTER, LINER, GLASS, FRAME, INSULATION, AIRLOCK, RECYCLER }
enum Category { MATERIALS, CONSTRUCTION, SURVIVAL, TOOLS }

const CATEGORY_NAMES := ["Materials", "Construction", "Survival", "Tools"]
const CANISTER_REFILL := 45.0
const ALLOY_YIELD := 3
const MAX_PULSE_LEVEL := 3
const PULSE_REACH_TILES := [2.1, 2.65, 3.1, 3.6]
const MINING_POWER := [1.0, 1.7, 2.05, 2.5]
const RECIPES := [
	{
		"category": Category.CONSTRUCTION,
		"name": "Field workbench", "benefit": "Deploy from any hotbar slot.",
		"cost": {B.SOIL: 2, B.STONE: 4}, "item": B.WORKBENCH, "count": 1,
	},
	{
		"category": Category.MATERIALS,
		"name": "Smelt alloy", "benefit": "Refines ore into 3 alloy.",
		"cost": {B.ORE: 2}, "item": B.ALLOY, "count": ALLOY_YIELD,
	},
	{
		"category": Category.SURVIVAL,
		"name": "Repair suit", "benefit": "Restores suit integrity to 100%.",
		"cost": {B.ALLOY: 3},
	},
	{
		"category": Category.TOOLS,
		"name": "Pulse level 1", "benefit": "2.65 tiles and faster hard-block mining.",
		"cost": {B.STONE: 4, B.ALLOY: 2}, "requires_level": 0,
	},
	{
		"category": Category.TOOLS,
		"name": "Pulse level 2", "benefit": "3.1 tiles and stronger mining pulses.",
		"cost": {B.ALLOY: 5, B.ORE: 2}, "requires_level": 1,
	},
	{
		"category": Category.TOOLS,
		"name": "Pulse level 3", "benefit": "3.6 tiles and maximum starter-tool power.",
		"cost": {B.ALLOY: 8, B.ORE: 4}, "requires_level": 2,
	},
	{
		"category": Category.SURVIVAL,
		"name": "Air canister", "benefit": "Restores 45 oxygen with O.",
		"cost": {B.ALLOY: 3, B.ORE: 1}, "item": ExpeditionInventory.CANISTER, "count": 1,
	},
	{
		"category": Category.SURVIVAL,
		"name": "Pressure liner", "benefit": "Cuts suit wear and pressure damage.",
		"cost": {B.STONE: 2, B.ALLOY: 4, B.ORE: 2},
	},
	{
		"category": Category.MATERIALS,
		"name": "Pressure glass ×4", "benefit": "Transparent tiles that seal the hull.",
		"cost": {B.SOIL: 3, B.ORE: 1}, "item": B.GLASS, "count": 4,
	},
	{
		"category": Category.CONSTRUCTION,
		"name": "Support frame ×4", "benefit": "Build scaffolds, decks, and supports.",
		"cost": {B.ALLOY: 2}, "item": B.FRAME, "count": 4,
	},
	{
		"category": Category.CONSTRUCTION,
		"name": "Insulation ×4", "benefit": "Roof panels soften heat and cold.",
		"cost": {B.SOIL: 2, B.ALLOY: 2}, "item": B.INSULATION, "count": 4,
	},
	{
		"category": Category.CONSTRUCTION,
		"name": "Airlock panels ×2", "benefit": "Stack two panels for a sealed entrance.",
		"cost": {B.ALLOY: 4, B.ORE: 1}, "item": B.AIRLOCK, "count": 2,
	},
	{
		"category": Category.CONSTRUCTION,
		"name": "Oxygen recycler", "benefit": "Fills one airtight room from the floor.",
		"cost": {B.ALLOY: 4, B.ORE: 2}, "item": B.RECYCLER, "count": 1,
	},
]

var pulse_level := 0
var liner := false


func pulse_reach_squared() -> float:
	var reach: float = PULSE_REACH_TILES[pulse_level] * BlockWorld.TILE_SIZE
	return reach * reach


func mining_power() -> float:
	return MINING_POWER[pulse_level]


func shows_recipe(recipe: int, in_field: bool) -> bool:
	if in_field:
		return recipe == Recipe.WORKBENCH
	return RECIPES[recipe].get("requires_level", pulse_level) == pulse_level


func available(recipe: int, inventory: ExpeditionInventory, vitals: SurvivalState) -> bool:
	return _exchange(recipe, inventory, vitals, false)


func craft(recipe: int, inventory: ExpeditionInventory, vitals: SurvivalState) -> bool:
	if not _exchange(recipe, inventory, vitals, true):
		return false
	match recipe:
		Recipe.REPAIR:
			vitals.suit_integrity = SurvivalState.MAX_LEVEL
		Recipe.PULSE_1, Recipe.PULSE_2, Recipe.PULSE_3:
			pulse_level += 1
		Recipe.LINER:
			liner = true
	return true


func _exchange(recipe: int, inventory: ExpeditionInventory, vitals: SurvivalState, commit: bool) -> bool:
	if recipe < 0 or recipe >= RECIPES.size() or not shows_recipe(recipe, false):
		return false
	if (recipe == Recipe.REPAIR and vitals.suit_integrity >= SurvivalState.MAX_LEVEL) or (recipe == Recipe.LINER and liner):
		return false
	var data: Dictionary = RECIPES[recipe]
	return inventory.exchange(data.cost, data.get("item", B.EMPTY), data.get("count", 0), vitals.suit_equipped, commit)


func snapshot() -> Dictionary:
	return {"pulse_level": pulse_level, "liner": liner}


func restore(data: Dictionary) -> void:
	pulse_level = data.pulse_level
	liner = data.liner


static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("liner") is bool:
		return false
	var level: Variant = data.get("pulse_level")
	return level is int and level >= 0 and level <= MAX_PULSE_LEVEL


static func cost_text(recipe: int) -> String:
	var cost: Dictionary = RECIPES[recipe].cost
	var parts := PackedStringArray()
	for item: int in cost:
		parts.append("%d %s" % [cost[item], ExpeditionInventory.item_name(item)])
	return " + ".join(parts)
