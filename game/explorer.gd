class_name Explorer
extends CharacterBody2D

const HALF_SIZE := Vector2(9, 14)
const SPEED := 214.0
const ACCELERATION := 1700.0
const JUMP_SPEED := -320.0

var gravity := 940.0
var _facing := 1


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0 and signi(int(direction)) != _facing:
		_facing = signi(int(direction))
		queue_redraw()
	velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y = minf(velocity.y + gravity * delta, 760.0)
	move_and_slide()


func body_rect() -> Rect2:
	return Rect2(global_position - HALF_SIZE, HALF_SIZE * 2)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_facing, 1))
	draw_rect(Rect2(-9, -5, 4, 13), Color("#5dafa3"))
	draw_rect(Rect2(-6, -4, 12, 13), Color("#e2cd99"))
	draw_rect(Rect2(-7, -14, 15, 11), Color("#edf0da"))
	draw_rect(Rect2(-1, -12, 9, 6), Color("#365367"))
	draw_rect(Rect2(4, -11, 2, 2), Color("#a8efde"))
	draw_rect(Rect2(-6, 9, 5, 5), Color("#273b4e"))
	draw_rect(Rect2(2, 9, 5, 5), Color("#273b4e"))
