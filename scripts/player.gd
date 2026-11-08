extends CharacterBody3D
## First-person blind walker. WASD + mouse look.
## The camera still moves (it decides where the next scan is taken from),
## but it renders nothing: the screen only shows the frozen scan overlay.

const WALK_SPEED := 2.0
const EYE_HEIGHT := 1.62
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8

var camera: Camera3D
var hold_point: Node3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.05
	camera.cull_mask = 0 # sees nothing; F1 debug turns this on
	add_child(camera)
	camera.make_current()

	hold_point = Node3D.new()
	hold_point.position = Vector3(0.14, -0.17, -0.42)
	camera.add_child(hold_point)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input.y += 1
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input.x += 1
	input = input.normalized()

	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	move_and_slide()
