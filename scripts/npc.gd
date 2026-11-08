extends Node3D
## The bad person walking through the house.
## A jointed human figure (head, neck, torso, pelvis, arms, hands, legs) whose right leg
## is a wooden peg below the knee. He walks with a slight limp: the peg stays stiff and
## swings a little outward, his hips dip onto it, and he gets off it a bit sooner.
## Footsteps are heard (shoe thud vs. wooden knock) and felt (`stepped` -> floor ripples);
## an echo scan catches his silhouette, frozen mid-stride.
## Body parts are on collision layer 2: scan rays hit them, the player walks through.

signal stepped(world_pos: Vector3, peg: bool)

const SPEED := 1.05
const STEP_INTERVAL := 0.6
const PAUSE_AT_ENDS := 4.0
const BODY_LAYER := 2
const PRESENCE := 4 # echo material id

var waypoints: Array[Vector3] = [
	Vector3(12.6, 0, -1.2),
	Vector3(10.8, 0, -0.1),
	Vector3(7.0, 0, 0.1),
	Vector3(4.6, 0, 0.0),
	Vector3(2.8, 0, 0.8),
	Vector3(0.6, 0, 0.3),
]

var _i := 0
var _dir := 1
var _pause := 0.0
var _phase := 0.0
var _walk := 0.0 # 0 standing .. 1 walking
var _t := 0.0
var _last_strike := 0

var _mat: StandardMaterial3D
var _wood: StandardMaterial3D
var _cur_mat: StandardMaterial3D
var _step_foot: AudioStreamPlayer3D
var _step_peg: AudioStreamPlayer3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var ankle_l: Node3D
var ankle_r: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D


func _ready() -> void:
	position = waypoints[0]
	_build_body()
	_step_foot = _step_player("res://audio/step_foot.wav", -9.0)
	_step_peg = _step_player("res://audio/step_peg.wav", -6.0)


func _step_player(path: String, vol: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = vol
	p.unit_size = 2.0
	p.max_distance = 22.0
	p.top_level = true # positioned in world space at each footfall
	add_child(p)
	return p


# --- Body -------------------------------------------------------------------
# Faces -Z. Character's left = -X. About 1.77 m tall.

func _build_body() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.06, 0.06, 0.07)
	_mat.roughness = 0.9
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.45, 0.3, 0.17)
	_wood.roughness = 0.7
	_cur_mat = _mat

	hips = _joint(self, Vector3(0, 0.95, 0))
	_part(hips, Vector3(0, 0, 0), Vector3(0, 0, 90), "cap", 0.115, 0.34) # pelvis

	spine = _joint(hips, Vector3(0, 0.05, 0))
	_part(spine, Vector3(0, 0.14, 0.01), Vector3.ZERO, "cap", 0.12, 0.32) # belly

	chest = _joint(spine, Vector3(0, 0.26, 0))
	_part(chest, Vector3(-0.065, 0.12, 0), Vector3.ZERO, "cap", 0.115, 0.36) # ribcage, left half
	_part(chest, Vector3(0.065, 0.12, 0), Vector3.ZERO, "cap", 0.115, 0.36) # ribcage, right half
	_part(chest, Vector3(0, 0.22, 0.01), Vector3(0, 0, 90), "cap", 0.065, 0.42) # shoulder line

	neck = _joint(chest, Vector3(0, 0.27, 0.0))
	_part(neck, Vector3(0, 0.04, 0.0), Vector3.ZERO, "cap", 0.05, 0.13)
	_part(neck, Vector3(0, 0.15, 0.005), Vector3.ZERO, "ball", 0.098) # skull
	_part(neck, Vector3(0, 0.1, -0.035), Vector3.ZERO, "ball", 0.07) # jaw / face
	_part(neck, Vector3(0, 0.13, -0.085), Vector3(-80, 0, 0), "cap", 0.016, 0.05) # nose

	shoulder_l = _joint(chest, Vector3(-0.2, 0.21, 0.01))
	shoulder_r = _joint(chest, Vector3(0.2, 0.21, 0.01))
	for s in [shoulder_l, shoulder_r]:
		_part(s, Vector3(0, -0.145, 0), Vector3.ZERO, "cap", 0.047, 0.33) # upper arm
	elbow_l = _joint(shoulder_l, Vector3(0, -0.29, 0))
	elbow_r = _joint(shoulder_r, Vector3(0, -0.29, 0))
	for e in [elbow_l, elbow_r]:
		_part(e, Vector3(0, -0.125, 0), Vector3.ZERO, "cap", 0.038, 0.29) # forearm
		_part(e, Vector3(0, -0.31, 0), Vector3.ZERO, "box", 0.07, 0.15, 0.03) # hand
		_part(e, Vector3(0, -0.29, -0.03), Vector3(20, 0, 0), "cap", 0.014, 0.07) # thumb

	hip_l = _joint(hips, Vector3(-0.095, -0.03, 0))
	hip_r = _joint(hips, Vector3(0.095, -0.03, 0))
	for h in [hip_l, hip_r]:
		_part(h, Vector3(0, -0.215, 0), Vector3.ZERO, "cap", 0.075, 0.5) # thigh
	knee_l = _joint(hip_l, Vector3(0, -0.43, 0))
	knee_r = _joint(hip_r, Vector3(0, -0.43, 0))
	# Left: normal shin and foot
	_part(knee_l, Vector3(0, -0.21, 0), Vector3.ZERO, "cap", 0.055, 0.47)
	ankle_l = _joint(knee_l, Vector3(0, -0.42, 0))
	_part(ankle_l, Vector3(0, -0.035, -0.07), Vector3.ZERO, "box", 0.09, 0.07, 0.25)
	# Right: stump socket and a wooden peg down to the floor, no foot
	_cur_mat = _wood
	_part(knee_r, Vector3(0, -0.04, 0), Vector3.ZERO, "cyl", 0.068, 0.12) # socket cup
	_part(knee_r, Vector3(0, -0.13, 0), Vector3.ZERO, "cyl", 0.04, 0.08) # collar
	_part(knee_r, Vector3(0, -0.3, 0), Vector3.ZERO, "cyl", 0.028, 0.34) # peg
	_part(knee_r, Vector3(0, -0.475, 0), Vector3.ZERO, "ball", 0.026) # worn tip
	_cur_mat = _mat
	ankle_r = _joint(knee_r, Vector3(0, -0.49, 0)) # peg tip (where the knock lands)


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


## kind "cap" (radius, height), "ball" (radius), "box" (x, y, z)
func _part(parent: Node3D, pos: Vector3, rot_deg: Vector3, kind: String, a: float, b := 0.0, c := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (BODY_LAYER - 1)
	body.collision_mask = 0
	body.set_meta("echo_material", PRESENCE)
	body.position = pos
	body.rotation_degrees = rot_deg
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	match kind:
		"cap":
			var s := CapsuleShape3D.new()
			s.radius = a
			s.height = b
			cs.shape = s
			var m := CapsuleMesh.new()
			m.radius = a
			m.height = b
			mi.mesh = m
		"ball":
			var s := SphereShape3D.new()
			s.radius = a
			cs.shape = s
			var m := SphereMesh.new()
			m.radius = a
			m.height = a * 2
			mi.mesh = m
		"box":
			var s := BoxShape3D.new()
			s.size = Vector3(a, b, c)
			cs.shape = s
			var m := BoxMesh.new()
			m.size = Vector3(a, b, c)
			mi.mesh = m
		"cyl":
			var s := CylinderShape3D.new()
			s.radius = a
			s.height = b
			cs.shape = s
			var m := CylinderMesh.new()
			m.top_radius = a
			m.bottom_radius = a * 0.8
			m.height = b
			mi.mesh = m
	mi.material_override = _cur_mat
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)


# --- Movement ---------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var moving := false
	if _pause > 0.0:
		_pause -= delta
	else:
		var target := waypoints[_i]
		var to := target - position
		to.y = 0
		if to.length() < 0.05:
			_advance()
		else:
			moving = true
			var move := to.normalized() * SPEED * delta
			if move.length() > to.length():
				move = to
			position += move
			# turn smoothly toward the walking direction
			var want := atan2(-move.x, -move.z)
			rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 6.0))

	_walk = move_toward(_walk, 1.0 if moving else 0.0, delta * 3.0)
	if moving:
		# Limp: the half of the stride spent on the peg (sin < 0) goes a little faster.
		var limp := 1.0 + 0.16 * maxf(0.0, -sin(_phase))
		_phase += delta * PI / STEP_INTERVAL * limp
		# a footfall at each peak of the stride
		var strike := int(floor((_phase - PI * 0.5) / PI))
		if strike != _last_strike:
			_last_strike = strike
			var peg := sin(_phase) < 0.0
			var foot := (ankle_r if peg else ankle_l).global_position
			var at := Vector3(foot.x, 0.0, foot.z)
			var p := _step_peg if peg else _step_foot
			p.global_position = at + Vector3(0, 0.03, 0)
			p.pitch_scale = randf_range(0.9, 1.08)
			p.play()
			stepped.emit(at, peg)
	_pose()


## Walk cycle blended with an idle stance (breathing, slowly looking around).
func _pose() -> void:
	var w := _walk
	var s := sin(_phase)
	var c := cos(_phase)

	# hips dip and roll slightly toward the peg while standing on it
	hips.position.y = 0.95 + w * (0.022 * absf(c) - 0.015 - 0.018 * maxf(0.0, -s))
	hips.rotation.z = w * 0.04 * minf(0.0, s)
	hips.rotation.y = w * 0.09 * s
	spine.rotation.y = -w * 0.12 * s
	spine.rotation.x = 0.04 * w + (1.0 - w) * 0.015 * sin(_t * 1.6) # slight forward lean / breathing

	# legs: hip swing, knee bends while the leg swings forward, foot stays roughly level
	var hl := 0.45 * s * w
	var hr := -0.45 * s * w
	var kl := -(0.06 + 0.75 * maxf(0.0, c)) * w
	# the peg knee barely bends; the leg swings stiffly and a little outward instead
	var kr := -(0.03 + 0.18 * maxf(0.0, -c)) * w
	hip_l.rotation.x = hl
	hip_r.rotation.x = hr * 0.9
	hip_r.rotation.z = 0.07 * maxf(0.0, -c) * w
	knee_l.rotation.x = kl
	knee_r.rotation.x = kr
	ankle_l.rotation.x = -(hl + kl) * 0.7

	# arms swing opposite to the legs, elbows slightly bent, hanging a little outward
	shoulder_l.rotation = Vector3(-0.38 * s * w + 0.03, 0.0, -0.08)
	shoulder_r.rotation = Vector3(0.38 * s * w + 0.03, 0.0, 0.08)
	elbow_l.rotation.x = 0.18 + 0.25 * maxf(0.0, -s) * w
	elbow_r.rotation.x = 0.18 + 0.25 * maxf(0.0, s) * w

	# head: steady while walking, slowly turns to look around while standing
	neck.rotation.y = (1.0 - w) * 0.7 * sin(_t * 0.35)
	neck.rotation.x = 0.05 * w


func _advance() -> void:
	var next := _i + _dir
	if next < 0 or next >= waypoints.size():
		_dir = -_dir
		_pause = PAUSE_AT_ENDS
		next = _i + _dir
	_i = next
