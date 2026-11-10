extends CharacterBody3D
## First-person blind walker. WASD + mouse look, Shift to run.
## A body moving through the dark, not a gliding camera: you walk slowly and carefully (run
## with Shift: fast but loud), the head dips and sways with every step, leans a little when
## you turn, and each footfall is reported (`stepped`) so it can be heard and seen.

signal stepped(world_pos: Vector3, running: bool)
signal bumped(world_pos: Vector3, into: Node)   # you walked into a wall or a piece of furniture

const WALK_SPEED := 1.45
const RUN_SPEED := 3.3
const STEP_WALK := 0.62         # metres per step
const STEP_RUN := 0.95
const EYE_HEIGHT := 1.62
const MOUSE_SENS := 0.0022
const GRAVITY := 9.8

var camera: Camera3D
var hold_point: Node3D
var autopilot := Vector3.ZERO # test runs only: walk in this local direction
var running := false
var frozen := false      # caught, or the level is over: no more input
var hidden := false      # in a closet or under a bed: you can look, not move
var eye_height := EYE_HEIGHT

var _step_phase := 0.0   # steps taken (fraction): a footfall each time it passes a whole number
var _bob := 0.0          # 0 standing .. 1 walking (blends the head movement in and out)
var _turn := 0.0         # recent turning speed (for the lean)
var _lean := 0.0
var _bump_wait := 0.0


func _ready() -> void:
	# World (1) and the invisible stair ramps (3); floor snapping keeps you on the stairs.
	collision_mask = 0b101
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
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

	# Where a held object sits: low on the right, like a tool in a first-person game.
	hold_point = Node3D.new()
	hold_point.position = Vector3(0.21, -0.19, -0.5)
	camera.add_child(hold_point)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not frozen:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_turn += -event.relative.x * MOUSE_SENS
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))


func _physics_process(delta: float) -> void:
	if hidden:
		velocity = Vector3.ZERO
		running = false
		_move_head(delta)
		return
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
	if frozen:
		input = Vector2.ZERO
	if autopilot != Vector3.ZERO:
		input = Vector2(autopilot.x, autopilot.z)

	running = Input.is_physical_key_pressed(KEY_SHIFT) and input != Vector2.ZERO
	var speed := RUN_SPEED if running else WALK_SPEED
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	# a body has weight: it takes a moment to get going and to stop
	var k := 1.0 - exp(-delta * (9.0 if input != Vector2.ZERO else 12.0))
	velocity.x = lerpf(velocity.x, dir.x * speed, k)
	velocity.z = lerpf(velocity.z, dir.z * speed, k)
	move_and_slide()
	_feel_bumps(delta, dir * speed)
	_move_head(delta)


## Walking into something: you feel it where your body met it.
func _feel_bumps(delta: float, want: Vector3) -> void:
	_bump_wait -= delta
	if _bump_wait > 0.0 or want.length() < 0.5:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < 0.4 and want.normalized().dot(-n) > 0.45: # a wall-like surface, walked into
			_bump_wait = 0.45
			bumped.emit(c.get_position(), c.get_collider() as Node)
			return


## Head bob, sway and lean, and the footfalls.
func _move_head(delta: float) -> void:
	var v := Vector2(velocity.x, velocity.z).length()
	var moving := v > 0.25 and is_on_floor()
	_bob = move_toward(_bob, 1.0 if moving else 0.0, delta * (4.0 if moving else 3.0))
	if moving:
		var before := floori(_step_phase)
		_step_phase += v * delta / (STEP_RUN if running else STEP_WALK)
		if floori(_step_phase) != before:
			stepped.emit(global_position, running)
	else:
		_step_phase = roundf(_step_phase) # the next step starts from a planted foot
	var s := sin(PI * _step_phase)          # one swing left, the next right
	var dip := absf(s)                       # the head dips between footfalls
	var amp := 1.7 if running else 1.0
	camera.position.y = eye_height - dip * 0.035 * amp * _bob
	camera.position.x = s * 0.022 * amp * _bob
	# lean into turns, and roll a little with each step
	_lean = lerpf(_lean, clampf(_turn / maxf(delta, 0.001) * 0.012, -0.045, 0.045), 1.0 - exp(-delta * 6.0))
	_turn = 0.0
	camera.rotation.z = _lean + s * 0.008 * amp * _bob
