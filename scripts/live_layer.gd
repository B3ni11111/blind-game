extends Control
## Things the player senses in real time (not part of the echo snapshot):
##  - floor vibrations from footsteps (expanding rings of dots on the floor, tinted by who
##    stepped: the bad person's peg red, the friend light green, others white)
##  - what you touch, "seen" by touch: a clean white outline for as long as you touch it.
##    What you hold stays outlined low on the right of the view, like a tool in a
##    first-person game; a door you open is outlined while it swings; the TV when you press
##    it. When you stop touching it, it is gone. No colour.

const Outline := preload("res://scripts/outline.gd")

const RIPPLE_LIFE := 1.5
const RIPPLE_MAX_RADIUS := 1.1
const RIPPLE_POINTS := 28
const FEEL_RANGE := 8.0

var camera: Camera3D
var held: Node3D = null
var held_edges: Array = [] # each: [a, b, n1, n2 or null] in the object's own space
var _touched: Array = []   # each: {obj, edges, until}

var _ripples: Array = [] # each: {pos, t, seed, peg, tint, strength}
var _time := 0.0


## peg = the wooden leg: a tighter, sharper ring with a hard bright point,
## instead of a shoe's wide, soft ring. `strength` < 1 when felt from a sealed room.
func add_ripple(world_pos: Vector3, peg := false, tint := Color.WHITE, strength := 1.0) -> void:
	_ripples.append({"pos": world_pos + Vector3(0, 0.01, 0), "t": 0.0, "seed": randf() * 10.0,
		"peg": peg, "tint": tint, "strength": strength})


func set_held(obj: Node3D) -> void:
	held = obj
	held_edges = _edges_for(obj) if obj else []


## You touch something (a door, the TV, a clock): it shows as an outline for `seconds`.
func touch(obj: Node3D, seconds: float) -> void:
	if obj == null:
		return
	for t in _touched:
		if t.obj == obj:
			t.until = maxf(t.until, _time + seconds)
			return
	_touched.append({"obj": obj, "edges": _edges_for(obj), "until": _time + seconds})


func _edges_for(obj: Node3D) -> Array:
	return Outline.edges(obj)


func _process(delta: float) -> void:
	_time += delta
	for r in _ripples:
		r.t += delta
	_ripples = _ripples.filter(func(r): return r.t < RIPPLE_LIFE)
	_touched = _touched.filter(func(t): return t.until > _time and is_instance_valid(t.obj))
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
		var near := pow(clampf(1.0 - dist / FEEL_RANGE, 0.0, 1.0), 0.6) * float(r.strength)
		var tint: Color = r.tint
		if r.peg:
			# wooden peg: fast, small, hard ring and a sharp point that lingers
			var kp := minf(k * 1.6, 1.0)
			var strength := (1.0 - kp) * (1.0 - kp) * near
			var radius := 0.03 + kp * RIPPLE_MAX_RADIUS * 0.5
			_draw_world_dot(r.pos, 3.4, (1.0 - k) * near * 1.2, tint)
			for i in RIPPLE_POINTS + 8:
				var a := TAU * float(i) / (RIPPLE_POINTS + 8)
				var p: Vector3 = r.pos + Vector3(cos(a), 0, sin(a)) * radius
				_draw_world_dot(p, 1.5, strength, tint)
		else:
			# shoe: wide, soft, slightly irregular ring
			var strength := (1.0 - k) * (1.0 - k) * near
			var radius := 0.08 + k * RIPPLE_MAX_RADIUS
			_draw_world_dot(r.pos, 3.0, strength, tint)
			for i in RIPPLE_POINTS:
				var a := TAU * float(i) / RIPPLE_POINTS
				var wobble := 1.0 + 0.12 * sin(a * 5.0 + r.seed + _time * 3.0)
				var p: Vector3 = r.pos + Vector3(cos(a), 0, sin(a)) * radius * wobble
				_draw_world_dot(p, 2.0, strength * 0.8, tint)


## What you hold or touch, drawn as a clean white outline: its silhouette and its sharp
## edges, only the side facing you. You are touching it, so you know exactly what it is.
func _draw_held() -> void:
	if held != null:
		_draw_outline(held, held_edges, 1.0)
	for t in _touched:
		_draw_outline(t.obj, t.edges, clampf((t.until - _time) / 0.3, 0.0, 1.0))


func _draw_outline(obj: Node3D, edges: Array, alpha: float) -> void:
	var xf := obj.global_transform
	var cam_pos := camera.global_position
	for e in edges:
		var a: Vector3 = xf * e[0]
		var b: Vector3 = xf * e[1]
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		var to_cam := cam_pos - (a + b) * 0.5
		var n1: Vector3 = e[2]
		var front1 := (xf.basis * n1).dot(to_cam) > 0.0
		var show := false
		if e[3] == null:
			show = front1
		else:
			var n2: Vector3 = e[3]
			var front2 := (xf.basis * n2).dot(to_cam) > 0.0
			if front1 != front2:
				show = true # silhouette
			elif front1 and n1.dot(n2) < 0.8:
				show = true # a sharp edge on the visible side
		if show:
			draw_line(camera.unproject_position(a), camera.unproject_position(b), Color(1, 1, 1, 0.95 * alpha), 2.0, true)


func _draw_world_dot(p: Vector3, size: float, alpha: float, tint := Color(0.92, 0.95, 1.0)) -> void:
	if alpha <= 0.01 or camera.is_position_behind(p):
		return
	var s := camera.unproject_position(p)
	draw_circle(s, size, Color(tint.r, tint.g, tint.b, clampf(alpha, 0.0, 1.0)))


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
