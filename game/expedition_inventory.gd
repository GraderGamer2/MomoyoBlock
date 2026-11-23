class_name ExpeditionInventory
extends RefCounted

const HOTBAR_SLOTS := 9
const SUIT_SLOTS := 5
const SLOT_COUNT := HOTBAR_SLOTS + SUIT_SLOTS
const STACK_LIMIT := 64
const RATION := 64
const WATER := 65
const CANISTER := 66

# Each saved slot stores its item ID followed by its stack size.
var _slots := PackedInt32Array()


func _init() -> void:
	_slots.resize(SLOT_COUNT * 2)


static func starter() -> ExpeditionInventory:
	var inventory := ExpeditionInventory.new()
	inventory._set_slot(0, BlockWorld.Block.SOIL, 12)
	inventory._set_slot(1, BlockWorld.Block.STONE, 8)
	inventory._set_slot(2, BlockWorld.Block.ALLOY, 30)
	inventory._set_slot(HOTBAR_SLOTS, RATION, 2)
	inventory._set_slot(HOTBAR_SLOTS + 1, WATER, 2)
	return inventory


static func from_legacy(materials: PackedInt32Array, benches: int, rations: int, water: int, canisters: int) -> ExpeditionInventory:
	var inventory := ExpeditionInventory.new()
	for slot in materials.size():
		inventory._set_slot(slot, BlockWorld.BUILD_MATERIALS[slot], materials[slot])
	inventory._set_slot(4, BlockWorld.Block.WORKBENCH, benches)
	inventory._set_slot(HOTBAR_SLOTS, RATION, rations)
	inventory._set_slot(HOTBAR_SLOTS + 1, WATER, water)
	inventory._set_slot(HOTBAR_SLOTS + 2, CANISTER, canisters)
	return inventory


func item_at(slot: int) -> int:
	return _slots[slot * 2]


func quantity_at(slot: int) -> int:
	return _slots[slot * 2 + 1]


func count(item: int, suit_worn := true) -> int:
	var quantity := 0
	for slot in _accessible_slots(suit_worn):
		if item_at(slot) == item:
			quantity += quantity_at(slot)
	return quantity


func has_room(item: int, amount: int, suit_worn: bool) -> bool:
	for slot in _accessible_slots(suit_worn):
		if item_at(slot) == item or item_at(slot) == BlockWorld.Block.EMPTY:
			amount -= maxi(0, STACK_LIMIT - quantity_at(slot))
			if amount <= 0:
				return true
	return false


func add(item: int, amount: int, suit_worn := true) -> bool:
	if amount <= 0 or not is_item(item) or not has_room(item, amount, suit_worn):
		return false
	var slots := _accessible_slots(suit_worn)
	for slot in slots:
		if item_at(slot) == item:
			var moved := mini(amount, maxi(0, STACK_LIMIT - quantity_at(slot)))
			_set_slot(slot, item, quantity_at(slot) + moved)
			amount -= moved
			if amount == 0:
				return true
	# Supply pickups prefer suit storage. Construction materials prefer the hotbar.
	var start := HOTBAR_SLOTS if suit_worn and item >= RATION else 0
	for index in slots:
		var slot := (start + index) % slots
		if item_at(slot) == BlockWorld.Block.EMPTY:
			var moved := mini(amount, STACK_LIMIT)
			_set_slot(slot, item, moved)
			amount -= moved
			if amount == 0:
				break
	return true


func take(item: int, amount: int, suit_worn := true) -> bool:
	if amount <= 0 or count(item, suit_worn) < amount:
		return false
	for slot in _accessible_slots(suit_worn):
		if item_at(slot) == item:
			var moved := mini(amount, quantity_at(slot))
			_set_slot(slot, item, quantity_at(slot) - moved)
			amount -= moved
			if amount == 0:
				break
	return true


func take_from(slot: int) -> void:
	_set_slot(slot, item_at(slot), quantity_at(slot) - 1)


func move_slot(source: int, target: int, suit_worn: bool) -> bool:
	var limit := _accessible_slots(suit_worn)
	if source < 0 or source >= limit or target < 0 or target >= limit or source == target:
		return false
	var item := item_at(source)
	if item == BlockWorld.Block.EMPTY:
		return false
	var target_item := item_at(target)
	var amount := quantity_at(source)
	var target_amount := quantity_at(target)
	if item == target_item:
		var moved := mini(amount, maxi(0, STACK_LIMIT - target_amount))
		if moved <= 0:
			return false
		_set_slot(target, item, target_amount + moved)
		_set_slot(source, item, amount - moved)
	else:
		_set_slot(target, item, amount)
		_set_slot(source, target_item, target_amount)
	return true


func exchange(cost: Dictionary, result: int, quantity: int, suit_worn: bool, commit: bool) -> bool:
	var trial := ExpeditionInventory.new()
	trial._slots = _slots.duplicate()
	for item: int in cost:
		if not trial.take(item, cost[item], suit_worn):
			return false
	if quantity > 0 and not trial.add(result, quantity, suit_worn):
		return false
	if commit:
		_slots = trial._slots
	return true


func rescue_supplies() -> void:
	for slot in SLOT_COUNT:
		var item := item_at(slot)
		if item != BlockWorld.Block.WORKBENCH and BlockWorld.is_placeable(item):
			_set_slot(slot, item, quantity_at(slot) >> 1)
	for item in [RATION, WATER]:
		if count(item) == 0:
			add(item, 1)


func snapshot() -> PackedInt32Array:
	return _slots.duplicate()


func restore(slots: PackedInt32Array) -> void:
	_slots = slots.duplicate()


static func valid_snapshot(data: Variant) -> bool:
	if not data is PackedInt32Array or data.size() != SLOT_COUNT * 2:
		return false
	for slot in SLOT_COUNT:
		var item: int = data[slot * 2]
		var amount: int = data[slot * 2 + 1]
		if amount < 0 or (amount == 0 and item != BlockWorld.Block.EMPTY) or (amount > 0 and not is_item(item)):
			return false
	return true


static func is_item(item: int) -> bool:
	return BlockWorld.is_placeable(item) or item in [RATION, WATER, CANISTER]


static func item_name(item: int) -> String:
	match item:
		RATION:
			return "Ration"
		WATER:
			return "Water"
		CANISTER:
			return "Air canister"
		_:
			return BlockWorld.BLOCK_NAMES[item]


static func item_color(item: int) -> Color:
	match item:
		RATION:
			return Color("#ce9c69")
		WATER:
			return Color("#67cde8")
		CANISTER:
			return Color("#8eebbe")
		_:
			return BlockWorld.TILE_COLORS[item]


func _set_slot(slot: int, item: int, amount: int) -> void:
	_slots[slot * 2] = item if amount > 0 else BlockWorld.Block.EMPTY
	_slots[slot * 2 + 1] = maxi(0, amount)


static func _accessible_slots(suit_worn: bool) -> int:
	return SLOT_COUNT if suit_worn else HOTBAR_SLOTS
