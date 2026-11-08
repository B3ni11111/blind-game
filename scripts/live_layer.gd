extends Control
## Things the player senses in real time (not part of the frozen scan):
##  - floor vibrations from footsteps (expanding rings of dots on the floor)
##  - the object held in the hands, "seen" by touch as a dense, clear dot shape

const RIPPLE_LIFE := 1.5
const RIPPLE_MAX_RADIUS := 1.1
const RIPPLE_POINTS := 28
const FEEL_RANGE := 13.0

var camera: Camera3D
var held: Node3D = null
var held_points := PackedVector3Array()
var held_material := 1

var _ripples: Array = [] # each: {pos: Vector3, t: float}
var _time := 0.0


## peg = the wooden leg: a tighter, sharper ring with a hard bright point,
## instead of a shoe's wide, soft ring.
func add_ripple(world_pos: Vector3, peg := false) -> void:
	_ripples.append({"pos": Vector3(world_pos.x, 0.01, world_pos.z), "t": 0.0, "seed": randf() * 10.0, "peg": peg})


func set_held(obj: Node3D) -> void:
	held = obj
	held_points = PackedVector3Array()
	if obj == null:
		return
	held_material = obj.get_meta("echo_material", 1)
	for c in obj.get_children():
		if c is MeshInstance3D:
			held_points = _sample_surface(c.mesh, 420)
			break


func _process(delta: float) -> void:
	_time += delta
	for r in _ripples:
		r.t += delta
	_ripples = _ripples.filter(func(r): return r.t < RIPPLE_LIFE)
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	_draw_ripples()
	_draw_held()


func _draw_ripples() -> void:
	var cam_pos := camera.global_position
	for r in _ripples:
		var k: float = r.t / RIPPLE_LIFE
		var dist := cam_pos.distance_to(r.pos)
		if dist > FEEL_RANGE:
			continue
		var near := pow(clampf(1.0 - dist / FEEL_RANGE, 0.0, 1.0), 0.6)
		if r.peg:
			# wooden peg: fast, small, hard ring and a sharp point that lingers
			var kp := minf(k * 1.6, 1.0)
			var strength := (1.0 - kp) * (1.0 - kp) * near
			var radius := 0.03 + kp * RIPPLE_MAX_RADIUS * 0.5
			_draw_world_dot(r.pos, 3.4, (1.0 - k) * near * 1.2)
			for i in RIPPLE_POINTS + 8:
				var a := TAU * float(i) / (RIPPLE_POINTS + 8)
				var p: Vector3 = r.pos + Vector3(cos(a), 0, sin(a)) * radius
				_draw_world_dot(p, 1.5, strength)
		else:
			# shoe: wide, soft, slightly irregular ring
			var strength := (1.0 - k) * (1.0 - k) * near
			var radius := 0.08 + k * RIPPLE_MAX_RADIUS
			_draw_world_dot(r.pos, 3.0, strength)
			for i in RIPPLE_POINTS:
				var a := TAU * float(i) / RIPPLE_POINTS
				var wobble := 1.0 + 0.12 * sin(a * 5.0 + r.seed + _time * 3.0)
				var p: Vector3 = r.pos + Vector3(cos(a), 0, sin(a)) * radius * wobble
				_draw_world_dot(p, 2.0, strength * 0.8)


func _draw_held() -> void:
	if held == null or held_points.is_empty():
		return
	var xf := held.global_transform
	var pulse := 1.0
	if held_material == 2:
		pulse = 0.7 + 0.3 * (0.5 + 0.5 * sin(_time * 2.6))
	for i in held_points.size():
		var a := 0.85 * pulse
		if held_material == 3 and fmod(float(i) * 7.31 + floor(_time * 22.0) * 3.7, 1.0) < 0.4:
			a *= 0.3
		_draw_world_dot(xf * held_points[i], 1.4, a)


func _draw_world_dot(p: Vector3, size: float, alpha: float) -> void:
	if alpha <= 0.01 or camera.is_position_behind(p):
		return
	var s := camera.unproject_position(p)
	draw_circle(s, size, Color(0.92, 0.95, 1.0, clampf(alpha, 0.0, 1.0)))


static func _sample_surface(mesh: Mesh, count: int) -> PackedVector3Array:
	var faces := mesh.get_faces()
	var out := PackedVector3Array()
	if faces.size() < 3:
		return out
	var areas := PackedFloat32Array()
	var total := 0.0
	for i in range(0, faces.size(), 3):
		var area := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() * 0.5
		total += area
		areas.append(total)
	for n in count:
		var pick := randf() * total
		var tri := areas.bsearch(pick)
		tri = mini(tri, areas.size() - 1)
		var a := faces[tri * 3]
		var b := faces[tri * 3 + 1]
		var c := faces[tri * 3 + 2]
		var u := randf()
		var v := randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		out.append(a + (b - a) * u + (c - a) * v)
	return out
