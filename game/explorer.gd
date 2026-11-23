class_name Explorer
extends CharacterBody2D

const HALF_SIZE := Vector2(9, 14)
const SPEED := 214.0
const ACCELERATION := 1700.0
const JUMP_SPEED := -320.0
const MIN_JUMP_HEIGHT := BlockWorld.TILE_SIZE * 1.25

var gravity := PlanetProfile.EARTH_GRAVITY_PX
var _facing := 1
var _suited := true
var _breached := false


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		_face(direction)
	velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = minf(JUMP_SPEED, -sqrt(2.0 * gravity * MIN_JUMP_HEIGHT))
	else:
		velocity.y = minf(velocity.y + gravity * delta, 760.0)
	move_and_slide()


func body_rect() -> Rect2:
	return Rect2(global_position - HALF_SIZE, HALF_SIZE * 2)


func show_suit(equipped: bool, breached: bool) -> void:
	if equipped != _suited or breached != _breached:
		_suited = equipped
		_breached = breached
		queue_redraw()


func aim_tool_at(point: Vector2) -> Vector2:
	_face(point.x - position.x)
	return position + Vector2(_facing * 14, 2)


func _face(horizontal: float) -> void:
	var direction := int(signf(horizontal))
	if direction != 0 and _facing != direction:
		_facing = direction
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_facing, 1))
	if _suited:
		draw_rect(Rect2(-9, -5, 4, 13), Color("#5dafa3"))
		draw_rect(Rect2(-6, -4, 12, 13), Color("#e2cd99"))
		draw_rect(Rect2(-7, -14, 15, 11), Color("#edf0da"))
		draw_rect(Rect2(-1, -12, 9, 6), Color("#365367"))
		draw_rect(Rect2(4, -11, 2, 2), Color("#ed936e") if _breached else Color("#a8efde"))
	else:
		draw_rect(Rect2(-6, -4, 12, 13), Color("#6a938f"))
		draw_rect(Rect2(-5, -13, 12, 10), Color("#d99566"))
		draw_rect(Rect2(-5, -13, 12, 3), Color("#583e46"))
		draw_rect(Rect2(5, -9, 2, 2), Color("#273b4e"))
	draw_rect(Rect2(3, -1, 12, 6), Color("#334e62"))
	draw_rect(Rect2(12, 0, 3, 4), Color("#91e5d6"))
	draw_rect(Rect2(-6, 9, 5, 5), Color("#273b4e"))
	draw_rect(Rect2(2, 9, 5, 5), Color("#273b4e"))
