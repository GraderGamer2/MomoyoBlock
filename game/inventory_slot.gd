class_name InventorySlot
extends Button

signal moved_from(source: int)

const SLOT_COLOR := Color("#101e30")
const LINE := Color("#344d5c")
const TEXT := Color("#e1e9e7")
const SELECTED := Color("#a7e8cf")

var slot_index := 0
var _item := BlockWorld.Block.EMPTY
var _count := 0
var _selected := false


func _ready() -> void:
	custom_minimum_size = Vector2(64, 52)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", _style(SLOT_COLOR, LINE))
	add_theme_stylebox_override("hover", _style(Color("#203647"), SELECTED))
	add_theme_stylebox_override("pressed", _style(Color("#294557"), SELECTED))
	add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("#d4e5b2")))
	add_theme_stylebox_override("disabled", _style(Color("#17222d"), Color("#2e3c47")))
	resized.connect(queue_redraw)


func show_stack(item: int, count: int, selected: bool, locked := false) -> void:
	_item = item
	_count = count
	_selected = selected
	disabled = locked
	if locked:
		tooltip_text = "Suit storage is locked"
	else:
		tooltip_text = "%s ×%d" % [ExpeditionInventory.item_name(item), count] if count > 0 else "Empty slot"
	queue_redraw()


func _draw() -> void:
	if _selected:
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), SELECTED, false, 1.5)
	var font := ThemeDB.fallback_font
	var tint := TEXT.darkened(0.45) if disabled else TEXT
	if slot_index < ExpeditionInventory.HOTBAR_SLOTS:
		draw_string(font, Vector2(6, 16), str(slot_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)
	if _item == BlockWorld.Block.EMPTY:
		return
	var origin := Vector2(floorf((size.x - 19.0) * 0.5), 12.0)
	var item_color := ExpeditionInventory.item_color(_item)
	if disabled:
		item_color = item_color.darkened(0.44)
	draw_rect(Rect2(origin, Vector2(19, 19)), item_color.darkened(0.3))
	draw_rect(Rect2(origin + Vector2(2, 2), Vector2(15, 15)), item_color)
	draw_rect(Rect2(origin + Vector2(2, 2), Vector2(15, 2)), item_color.lightened(0.25))
	draw_string(font, Vector2(4, size.y - 8), str(_count), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 12, tint)


func _get_drag_data(_position: Vector2) -> Variant:
	if disabled or _item == BlockWorld.Block.EMPTY:
		return null
	var preview := Label.new()
	preview.text = "%s ×%d" % [ExpeditionInventory.item_name(_item), _count]
	set_drag_preview(preview)
	return {"inventory_slot": slot_index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not disabled and data is Dictionary and data.get("inventory_slot") is int and data.inventory_slot != slot_index


func _drop_data(_position: Vector2, data: Variant) -> void:
	moved_from.emit(data.inventory_slot)


static func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
