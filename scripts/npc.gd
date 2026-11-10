extends Node3D
## A person walking through the house. One script for everyone; `setup()` decides who:
## build (height, girth), gait (speed, step rate, limp), footstep sounds, the colour their
## steps show in, their route, and whether the right leg is a wooden peg.
##
## The people (see main.gd):
##  - the bad person: wooden right leg below the knee, slight limp, shoe thud + peg knock.
##    His peg and its steps show red.
##  - a stranger: heavier build, ordinary shoes, steps show white.
##  - the friend: slim and quick, sneakers with a squeak you learn to recognise; steps show
##    light green.
##
## A jointed human figure on a joint skeleton. Footsteps are heard and felt (`stepped` ->
## floor ripples, a blurry flash of the stepping leg); an echo scan catches the silhouette.
## Body parts are on collision layer 2: scan rays hit them, the player walks through.

signal stepped(world_pos: Vector3, right: bool)
signal arrived   # the end of `nav_path` was reached

const BODY_LAYER := 2
const PERSON := 4      # echo material id
const WOODEN_LEG := 5  # echo material id (red in scans)

# --- who this is (set with setup() before adding to the tree) ---
var who := "person"
var peg_leg := false
var height := 1.0       # 1.0 = about 1.80 m
var girth := 1.0        # 1.0 = slim
var speed := 1.05
var step_interval := 0.6
var limp := 0.0         # 0 = even gait; the bad person 0.16
var pause_at_ends := 4.0
var foot_sound := "res://audio/step_foot.wav"
var foot_db := -9.0
var peg_sound := "res://audio/step_peg.wav"
var peg_db := -6.0
var step_color := Color.WHITE       # tint of footstep visuals
var peg_color := Color(1.0, 0.18, 0.12)
var waypoints: Array[Vector3] = []

## A route to follow instead of the patrol waypoints (the stalker sets it). Empty: patrol.
var nav_path := PackedVector3Array()
var pace := 1.0          # speed multiplier (the stalker hurries when he has heard you)
var _nav_i := 0

var _i := 0
var _dir := 1
var _pause := 0.0
var _phase := 0.0
var _walk := 0.0 # 0 standing .. 1 walking
var _t := 0.0
var _last_strike := 0
var _hip_y := 0.95

var _mat: StandardMaterial3D
var _wood: StandardMaterial3D
var _cur_mat: StandardMaterial3D
var _cur_echo := PERSON
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


func setup(cfg: Dictionary) -> void:
	for k in cfg:
		set(k, cfg[k])


func _ready() -> void:
	if not waypoints.is_empty():
		position = waypoints[0]
	_hip_y = 0.95 * height
	_build_body()
	_step_foot = _step_player(foot_sound, foot_db)
	_step_peg = _step_player(peg_sound, peg_db)


func _step_player(path: String, vol: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.volume_db = vol
	p.unit_size = 1.2
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	p.max_distance = 14.0 # you only hear footsteps well when they are close
	p.top_level = true # positioned in world space at each footfall
	p.set_meta("base_db", vol)
	add_child(p)
	return p


# --- Body -------------------------------------------------------------------
# Faces -Z. Character's left = -X, back = +Z. About 1.80 m tall, slim build.
# Each body part is a smooth lofted shape: a stack of elliptical rings
# [height, half-width (x), half-depth (z), forward/back offset (z), side offset (x)]
# along the joint's local Y axis. The silhouette is what the player reads, so the
# proportions follow a real standing man: narrow waist, broader chest and shoulders,
# tapered limbs with calves and forearms, a head with jaw and ears, flat hands.

func _build_body() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.06, 0.06, 0.07)
	_mat.roughness = 0.9
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.45, 0.3, 0.17)
	_wood.roughness = 0.7
	_cur_mat = _mat

	hips = _joint(self, Vector3(0, 0.95, 0))
	_loft(hips, [ # pelvis: crotch up to the waist
		[-0.12, 0.06, 0.055, 0.0], [-0.095, 0.125, 0.09, 0.006], [-0.04, 0.158, 0.11, 0.012],
		[0.02, 0.155, 0.105, 0.006], [0.075, 0.143, 0.097, -0.002]], 1.0)

	spine = _joint(hips, Vector3(0, 0.05, 0))
	_loft(spine, [ # belly and waist
		[-0.02, 0.144, 0.097, -0.002], [0.08, 0.136, 0.094, -0.008], [0.17, 0.146, 0.1, -0.006],
		[0.28, 0.162, 0.106, -0.004]], 1.4)

	chest = _joint(spine, Vector3(0, 0.26, 0))
	_loft(chest, [ # ribcage, chest, shoulders sloping up to the neck
		[-0.02, 0.162, 0.106, -0.004], [0.08, 0.172, 0.114, -0.01], [0.15, 0.176, 0.11, -0.008],
		[0.19, 0.172, 0.096, -0.002], [0.215, 0.15, 0.078, 0.004], [0.24, 0.105, 0.064, 0.008],
		[0.262, 0.068, 0.058, 0.01], [0.28, 0.058, 0.055, 0.01]], 1.1)

	neck = _joint(chest, Vector3(0, 0.27, 0.0))
	_loft(neck, [[-0.01, 0.058, 0.056, 0.01], [0.04, 0.05, 0.052, 0.006], [0.09, 0.048, 0.05, 0.0]], 0.8)
	_loft(neck, [ # head: chin up to the crown, back of the skull rounder
		[0.035, 0.03, 0.03, -0.07], [0.05, 0.05, 0.06, -0.035], [0.075, 0.065, 0.085, -0.01],
		[0.11, 0.072, 0.096, 0.0], [0.15, 0.078, 0.1, 0.005], [0.19, 0.08, 0.1, 0.008],
		[0.225, 0.072, 0.09, 0.01], [0.252, 0.05, 0.065, 0.01], [0.268, 0.018, 0.025, 0.01]], 0.25)
	for sx in [-1, 1]: # ears
		_loft(neck, [[0.11, 0.008, 0.015, 0.012, sx * 0.075], [0.135, 0.014, 0.024, 0.014, sx * 0.08],
			[0.165, 0.012, 0.02, 0.016, sx * 0.079], [0.175, 0.005, 0.01, 0.016, sx * 0.077]])
	_loft(neck, [[0.11, 0.012, 0.01, -0.095], [0.14, 0.016, 0.016, -0.1], [0.165, 0.008, 0.008, -0.092]]) # nose

	shoulder_l = _joint(chest, Vector3(-0.168, 0.19, 0.005))
	shoulder_r = _joint(chest, Vector3(0.168, 0.19, 0.005))
	elbow_l = _joint(shoulder_l, Vector3(0, -0.29, 0))
	elbow_r = _joint(shoulder_r, Vector3(0, -0.29, 0))
	for sx in [-1, 1]:
		var s: Node3D = shoulder_l if sx < 0 else shoulder_r
		var e: Node3D = elbow_l if sx < 0 else elbow_r
		_loft(s, [ # deltoid and upper arm
			[0.05, 0.015, 0.02, 0.0, -sx * 0.015], [0.035, 0.042, 0.045, 0.0, -sx * 0.004], [0.0, 0.056, 0.052, 0.0, sx * 0.006],
			[-0.06, 0.052, 0.048, 0.0, sx * 0.006], [-0.15, 0.042, 0.045, 0.0], [-0.25, 0.036, 0.039, 0.0], [-0.3, 0.034, 0.036, 0.0]], 0.8)
		_loft(e, [ # forearm, wider below the elbow, thin at the wrist
			[0.01, 0.035, 0.037, 0.0], [-0.06, 0.039, 0.036, -0.004], [-0.16, 0.03, 0.026, 0.0],
			[-0.245, 0.022, 0.019, 0.0]], 0.6)
		_loft(e, [ # hand: palm faces the thigh, so it is thin across and wide front to back
			[-0.245, 0.017, 0.024, 0.0], [-0.285, 0.016, 0.039, 0.003], [-0.33, 0.014, 0.041, 0.005],
			[-0.375, 0.011, 0.036, 0.007], [-0.41, 0.008, 0.024, 0.008], [-0.425, 0.004, 0.01, 0.008]], 0.3)
		_loft(e, [[-0.27, 0.011, 0.011, -0.035, -sx * 0.008], [-0.31, 0.01, 0.01, -0.05, -sx * 0.012],
			[-0.35, 0.007, 0.007, -0.052, -sx * 0.014]], 0.3) # thumb

	hip_l = _joint(hips, Vector3(-0.083, -0.045, 0))
	hip_r = _joint(hips, Vector3(0.083, -0.045, 0))
	knee_l = _joint(hip_l, Vector3(0, -0.43, 0))
	knee_r = _joint(hip_r, Vector3(0, -0.43, 0))
	for sx in [-1, 1]:
		var h: Node3D = hip_l if sx < 0 else hip_r
		_loft(h, [ # thigh: full at the top, tapering to the knee
			[0.04, 0.075, 0.08, 0.004, sx * 0.004], [-0.03, 0.088, 0.09, 0.0, sx * 0.004], [-0.16, 0.076, 0.08, -0.004],
			[-0.32, 0.058, 0.062, -0.004], [-0.43, 0.048, 0.051, -0.002]], 1.0)
	# Left: normal shin with a calf, and a foot
	ankle_l = _shin_and_foot(knee_l)
	if not peg_leg:
		ankle_r = _shin_and_foot(knee_r)
		return
	# Right: the leg ends a little below the knee in a socket, then a wooden peg to the floor
	_loft(knee_r, [[0.01, 0.047, 0.05, -0.002], [-0.06, 0.046, 0.052, 0.006], [-0.1, 0.044, 0.048, 0.004]], 0.7)
	_cur_mat = _wood
	_cur_echo = WOODEN_LEG
	_part(knee_r, Vector3(0, -0.11, 0), Vector3.ZERO, "cyl", 0.056, 0.08) # socket cup
	_part(knee_r, Vector3(0, -0.17, 0), Vector3.ZERO, "cyl", 0.035, 0.05) # collar
	_part(knee_r, Vector3(0, -0.32, 0), Vector3.ZERO, "cyl", 0.026, 0.28) # peg
	_part(knee_r, Vector3(0, -0.465, 0), Vector3.ZERO, "ball", 0.025) # worn tip
	_cur_mat = _mat
	_cur_echo = PERSON
	ankle_r = _joint(knee_r, Vector3(0, -0.49, 0)) # peg tip (where the knock lands)


## A shin with a calf and a foot below `knee`; returns the ankle joint.
func _shin_and_foot(knee: Node3D) -> Node3D:
	_loft(knee, [
		[0.01, 0.047, 0.05, -0.002], [-0.06, 0.046, 0.054, 0.008], [-0.14, 0.047, 0.056, 0.014],
		[-0.25, 0.036, 0.04, 0.006], [-0.36, 0.026, 0.028, 0.0], [-0.42, 0.028, 0.03, 0.0]], 0.7)
	var ankle := _joint(knee, Vector3(0, -0.42, 0))
	var foot := _joint(ankle, Vector3(0, -0.045, 0.02))
	foot.rotation_degrees.x = -90 # foot loft runs forward (local +Y -> world -Z), local +Z is up
	_loft(foot, [ # heel to toes: [along, half-width, half-height, up offset]
		[-0.045, 0.024, 0.026, 0.004], [-0.02, 0.035, 0.04, 0.012], [0.05, 0.04, 0.034, 0.006],
		[0.13, 0.046, 0.02, -0.008], [0.18, 0.04, 0.015, -0.012], [0.2, 0.02, 0.01, -0.014]], 0.3, true)
	return ankle


## A smooth body part: rings [y, half_x, half_z, z_offset, x_offset] stacked along local Y,
## closed at both ends. Scan rays hit it through a convex collision shape of the same form.
## Build: lengths scale with `height`; widths with `girth`, by `fat` (how much this part
## takes on weight: belly most, head least). `flat` = a foot (its rings run forward).
func _loft(parent: Node3D, rings: Array, fat := 1.0, flat := false) -> void:
	const SEG := 18
	var g := 1.0 + (girth - 1.0) * fat
	var along := 1.0 if flat else height
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var pts := PackedVector3Array()
	for r in rings:
		var xo: float = r[4] if r.size() > 4 else 0.0
		for k in SEG:
			var a := TAU * k / SEG
			pts.append(Vector3((xo + r[1] * cos(a)) * g, r[0] * along, (r[3] + r[2] * sin(a)) * g))
	var n := rings.size()
	for i in n - 1:
		for k in SEG:
			var a := i * SEG + k
			var b := i * SEG + (k + 1) % SEG
			var c := a + SEG
			var d := b + SEG
			for v in [a, b, c, b, d, c]: # clockwise seen from outside (Godot front faces)
				st.add_vertex(pts[v])
	# end caps
	for end in [0, n - 1]:
		var center := Vector3.ZERO
		for k in SEG:
			center += pts[end * SEG + k]
		center /= SEG
		center.y += -0.004 if end == 0 else 0.004
		for k in SEG:
			var a: int = end * SEG + k
			var b: int = end * SEG + (k + 1) % SEG
			if end == 0:
				st.add_vertex(center); st.add_vertex(pts[b]); st.add_vertex(pts[a])
			else:
				st.add_vertex(center); st.add_vertex(pts[a]); st.add_vertex(pts[b])
	st.generate_normals()
	var mesh := st.commit()

	var body := StaticBody3D.new()
	body.collision_layer = 1 << (BODY_LAYER - 1)
	body.collision_mask = 0
	body.set_meta("echo_material", _cur_echo)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cur_mat
	body.add_child(cs)
	body.add_child(mi)
	parent.add_child(body)


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = Vector3(pos.x * (1.0 + (girth - 1.0) * 0.8), pos.y * height, pos.z)
	parent.add_child(j)
	return j


## kind "cap" (radius, height), "ball" (radius), "box" (x, y, z)
func _part(parent: Node3D, pos: Vector3, rot_deg: Vector3, kind: String, a: float, b := 0.0, c := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (BODY_LAYER - 1)
	body.collision_mask = 0
	body.set_meta("echo_material", _cur_echo)
	body.position = pos * Vector3(1, height, 1)
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
		var on_path := not nav_path.is_empty()
		if not on_path and waypoints.is_empty():
			_pose()
			return
		var target := nav_path[_nav_i] if on_path else waypoints[_i]
		var to := target - position # includes height: routes go up and down the stairs
		if to.length() < 0.06:
			if on_path:
				_nav_i += 1
				if _nav_i >= nav_path.size():
					nav_path = PackedVector3Array()
					arrived.emit()
			else:
				_advance()
		else:
			moving = true
			var move := to.normalized() * speed * pace * delta
			if move.length() > to.length():
				move = to
			position += move
			# turn smoothly toward the walking direction
			if Vector2(move.x, move.z).length() > 0.0001:
				var want := atan2(-move.x, -move.z)
				rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * 6.0))

	_walk = move_toward(_walk, 1.0 if moving else 0.0, delta * 3.0)
	if moving:
		# Limp: the half of the stride spent on the right leg (sin < 0) goes a little faster.
		var hurry := 1.0 + limp * maxf(0.0, -sin(_phase))
		_phase += delta * PI / step_interval * hurry * pace
		# a footfall at each peak of the stride
		var strike := int(floor((_phase - PI * 0.5) / PI))
		if strike != _last_strike:
			_last_strike = strike
			var right := sin(_phase) < 0.0
			var foot := (ankle_r if right else ankle_l).global_position
			var at := Vector3(foot.x, global_position.y, foot.z)
			var p := step_player(right)
			p.global_position = at + Vector3(0, 0.03, 0)
			p.pitch_scale = randf_range(0.9, 1.08)
			stepped.emit(at, right) # main sets the volume (walls, floors) before it plays
			p.play()
	_pose()


## Walk cycle blended with an idle stance (breathing, slowly looking around).
func _pose() -> void:
	var w := _walk
	var s := sin(_phase)
	var c := cos(_phase)

	# hips dip and roll slightly toward the peg while standing on it
	var dip := 1.0 if peg_leg else 0.3
	hips.position.y = _hip_y + w * (0.022 * absf(c) - 0.015 - 0.018 * dip * maxf(0.0, -s))
	hips.rotation.z = w * 0.04 * dip * minf(0.0, s)
	hips.rotation.y = w * 0.09 * s
	spine.rotation.y = -w * 0.12 * s
	spine.rotation.x = 0.04 * w + (1.0 - w) * 0.015 * sin(_t * 1.6) # slight forward lean / breathing

	# legs: hip swing, knee bends while the leg swings forward, foot stays roughly level
	var hl := 0.45 * s * w
	var hr := -0.45 * s * w
	var kl := -(0.06 + 0.75 * maxf(0.0, c)) * w
	var kr := -(0.06 + 0.75 * maxf(0.0, -c)) * w
	hip_l.rotation.x = hl
	hip_r.rotation.x = hr
	if peg_leg:
		# the peg knee barely bends; the leg swings stiffly and a little outward instead
		kr = -(0.03 + 0.18 * maxf(0.0, -c)) * w
		hip_r.rotation.x = hr * 0.9
		hip_r.rotation.z = 0.07 * maxf(0.0, -c) * w
	else:
		ankle_r.rotation.x = -(hr + kr) * 0.7
	knee_l.rotation.x = kl
	knee_r.rotation.x = kr
	ankle_l.rotation.x = -(hl + kl) * 0.7

	# arms swing opposite to the legs, elbows slightly bent, hanging a little outward
	shoulder_l.rotation = Vector3(-0.38 * s * w + 0.03, 0.0, -0.1)
	shoulder_r.rotation = Vector3(0.38 * s * w + 0.03, 0.0, 0.1)
	elbow_l.rotation.x = 0.18 + 0.25 * maxf(0.0, -s) * w
	elbow_r.rotation.x = 0.18 + 0.25 * maxf(0.0, s) * w

	# head: steady while walking, slowly turns to look around while standing
	neck.rotation.y = (1.0 - w) * 0.7 * sin(_t * 0.35)
	neck.rotation.x = 0.05 * w


## Walk this route now (world points), instead of the patrol.
func follow(path: PackedVector3Array) -> void:
	nav_path = path
	_nav_i = 0
	_pause = 0.0


func _advance() -> void:
	var next := _i + _dir
	if next < 0 or next >= waypoints.size():
		_dir = -_dir
		_pause = pause_at_ends
		next = _i + _dir
	_i = next


## The leg that just stepped (its parts make the sound, so they flash in sound sight).
func step_parts(right: bool) -> Array:
	return [knee_r] if right else [knee_l]


func step_player(right: bool) -> AudioStreamPlayer3D:
	return _step_peg if right and peg_leg else _step_foot


## The colour a footstep shows in: the peg's knock is red, everything else the person's colour.
func step_tint(right: bool) -> Color:
	return peg_color if right and peg_leg else step_color
