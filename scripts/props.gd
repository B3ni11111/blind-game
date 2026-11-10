extends RefCounted
## Small things you can pick up, built the way they are really built: a mug is a revolved
## wall with a real inside and a handle, a bottle has a shoulder and a neck, keys hang on a
## ring, a hammer has a tapered handle, a head with a neck, a face and a curved claw.
## Simple flat colours, a few primitives each: low-end graphics, but real shapes, because in
## an echo scan the shape is all you get.
##
## Every prop is one StaticBody3D (echo material set on it, in group "grabbable") whose
## origin sits at the BASE of the object (so it can be set down on a surface); the parts are
## child meshes with exact collision, so scan rays hit the true shape.

const SOLID := 1
const HOLLOW := 2
const GLASS := 3

static var _mats := {}


# --- Building blocks ------------------------------------------------------------

static func body(h: Node3D, name: String, pos: Vector3, echo: int, half_height := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.position = pos
	b.set_meta("echo_material", echo)
	h.add_child(b, true)
	h.grabbable(b, half_height)
	return b


static func _material(h: Node3D, color: Color, glass: bool) -> Material:
	if glass:
		return h._glass_mat
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED # thin shells: both sides
		_mats[key] = m
	return _mats[key]


## Add one part: a mesh with exact (triangle mesh) collision.
static func add(b: StaticBody3D, h: Node3D, mesh: Mesh, color: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, glass := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(h, color, glass)
	mi.position = pos
	mi.rotation_degrees = rot
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	cs.position = pos
	cs.rotation_degrees = rot
	b.add_child(cs)


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(r_top: float, r_bottom: float, height: float, segments := 18) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m


## A ring: `ring_r` from the centre to the middle of the tube, `tube_r` the tube's radius.
static func torus(ring_r: float, tube_r: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = ring_r - tube_r
	m.outer_radius = ring_r + tube_r
	m.rings = 20
	m.ring_segments = 8
	return m


## A revolved shape: `profile` is a list of Vector2(radius, height) from the bottom up,
## over the rim and down the inside for hollow things.
static func lathe(profile: Array, segments := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var v00 := Vector3(p0.x * cos(a0), p0.y, p0.x * sin(a0))
			var v01 := Vector3(p0.x * cos(a1), p0.y, p0.x * sin(a1))
			var v10 := Vector3(p1.x * cos(a0), p1.y, p1.x * sin(a0))
			var v11 := Vector3(p1.x * cos(a1), p1.y, p1.x * sin(a1))
			for v in [v00, v11, v10, v00, v01, v11]: # Godot front faces: clockwise from outside
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A flat shape: a convex polygon of Vector2(x, z), `thick` tall, centred on y = 0.
static func prism(poly: Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shading
	var n := poly.size()
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
		top.append(Vector3(p.x, thick / 2.0, p.y))
		bottom.append(Vector3(p.x, -thick / 2.0, p.y))
	centre /= n
	var tris: Array = []
	for i in range(1, n - 1):
		tris.append([top[0], top[i], top[i + 1]])
		tris.append([bottom[0], bottom[i], bottom[i + 1]])
	for i in n:
		var j := (i + 1) % n
		tris.append([top[i], top[j], bottom[j]])
		tris.append([top[i], bottom[j], bottom[i]])
	var mid := Vector3(centre.x, 0.0, centre.y)
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var out := (b - a).cross(c - a).dot((a + b + c) / 3.0 - mid)
		if out > 0.0: # the cross product must point inward (Godot front faces)
			var tmp := b
			b = c
			c = tmp
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	st.generate_normals()
	return st.commit()


# --- The things ---------------------------------------------------------------

## A claw hammer lying flat, handle along x, origin at the middle of the handle.
static func hammer(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID, 0.02)
	var wood := Color(0.62, 0.43, 0.25)
	var grip := Color(0.12, 0.12, 0.13)
	var steel := Color(0.4, 0.41, 0.43)
	add(b, h, cyl(0.0125, 0.0165, 0.30), wood, Vector3(0, 0, 0), Vector3(0, 0, 90)) # tapered handle
	add(b, h, cyl(0.0185, 0.0185, 0.11), grip, Vector3(-0.095, 0, 0), Vector3(0, 0, 90)) # rubber grip
	add(b, h, cyl(0.011, 0.011, 0.012), steel, Vector3(0.152, 0, 0), Vector3(0, 0, 90)) # ferrule
	add(b, h, box(Vector3(0.034, 0.032, 0.05)), steel, Vector3(0.168, 0, 0)) # neck of the head
	add(b, h, cyl(0.0205, 0.017, 0.036, 20), steel, Vector3(0.168, 0, -0.043), Vector3(90, 0, 0)) # striking face
	add(b, h, cyl(0.0215, 0.0215, 0.006, 20), steel, Vector3(0.168, 0, -0.063), Vector3(90, 0, 0)) # face rim
	# the claw: a curved, tapering pair of tines, built from three angled blocks
	add(b, h, box(Vector3(0.03, 0.026, 0.04)), steel, Vector3(0.168, 0.0, 0.043), Vector3(0, 0, 0))
	add(b, h, box(Vector3(0.028, 0.02, 0.035)), steel, Vector3(0.168, -0.002, 0.078), Vector3(-14, 0, 0))
	add(b, h, box(Vector3(0.024, 0.014, 0.03)), steel, Vector3(0.168, -0.01, 0.107), Vector3(-32, 0, 0))
	add(b, h, box(Vector3(0.003, 0.012, 0.075)), Color(0.05, 0.05, 0.06), Vector3(0.168, -0.006, 0.09), Vector3(-18, 0, 0)) # the split
	b.set_meta("hold_rot", Vector3(-8, 75, 80)) # upright in the hand, head turned forward
	return b


## A mug with a real inside and a handle.
static func mug(h: Node3D, name: String, pos: Vector3, color: Color) -> StaticBody3D:
	var b := body(h, name, pos, HOLLOW)
	add(b, h, lathe([Vector2(0.0, 0.0), Vector2(0.034, 0.0), Vector2(0.039, 0.006), Vector2(0.04, 0.088),
		Vector2(0.0385, 0.09), Vector2(0.0345, 0.088), Vector2(0.0335, 0.012), Vector2(0.0, 0.012)]), color)
	add(b, h, torus(0.02, 0.005), color, Vector3(0.0425, 0.048, 0.0), Vector3(90, 0, 0))
	return b


## A glass bottle: base, body, shoulder, neck, lip and a cap.
static func bottle(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, GLASS)
	add(b, h, lathe([Vector2(0.0, 0.0), Vector2(0.028, 0.0), Vector2(0.034, 0.008), Vector2(0.034, 0.16),
		Vector2(0.03, 0.19), Vector2(0.017, 0.222), Vector2(0.0125, 0.24), Vector2(0.0125, 0.275),
		Vector2(0.015, 0.279), Vector2(0.015, 0.285), Vector2(0.0, 0.285)]), Color.WHITE, Vector3.ZERO, Vector3.ZERO, true)
	add(b, h, cyl(0.0165, 0.0165, 0.016), Color(0.2, 0.45, 0.25), Vector3(0, 0.285, 0))
	return b


## A drinking glass (tumbler): a thin wall that widens to the rim.
static func drinking_glass(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, GLASS)
	add(b, h, lathe([Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.036, 0.11), Vector2(0.034, 0.11),
		Vector2(0.025, 0.012), Vector2(0.0, 0.012)]), Color.WHITE, Vector3.ZERO, Vector3.ZERO, true)
	return b


## A TV remote: a slab with a grid of buttons and a red power button.
static func remote(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID)
	var dark := Color(0.08, 0.08, 0.09)
	var grey := Color(0.3, 0.3, 0.33)
	add(b, h, box(Vector3(0.045, 0.016, 0.175)), dark, Vector3(0, 0.008, 0))
	add(b, h, cyl(0.007, 0.007, 0.004, 14), Color(0.7, 0.1, 0.1), Vector3(0.012, 0.018, -0.07))
	for r in 5:
		for c in 3:
			add(b, h, box(Vector3(0.0105, 0.004, 0.0105)), grey, Vector3(-0.0135 + c * 0.0135, 0.018, -0.04 + r * 0.0155))
	add(b, h, cyl(0.011, 0.011, 0.004, 16), grey, Vector3(0, 0.018, 0.058))
	return b


## A phone lying flat: body, screen, camera bump.
static func phone(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID)
	add(b, h, box(Vector3(0.072, 0.0085, 0.152)), Color(0.1, 0.1, 0.12), Vector3(0, 0.00425, 0))
	add(b, h, box(Vector3(0.066, 0.0012, 0.14)), Color(0.02, 0.03, 0.06), Vector3(0, 0.0091, 0.0))
	add(b, h, cyl(0.011, 0.011, 0.003, 16), Color(0.05, 0.05, 0.06), Vector3(-0.02, -0.001, -0.052))
	add(b, h, box(Vector3(0.012, 0.0018, 0.003)), Color(0.4, 0.4, 0.43), Vector3(0, 0.0093, 0.07)) # speaker slot
	return b


## A ring of keys: a flat ring and a few keys with round heads and toothed blades.
static func keys(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID)
	var brass := Color(0.75, 0.62, 0.25)
	var steel := Color(0.7, 0.72, 0.75)
	add(b, h, torus(0.0125, 0.0018), steel, Vector3(0, 0.0018, 0))
	var angles := [20.0, 75.0, 140.0, -55.0]
	for k in angles.size():
		var a: float = deg_to_rad(angles[k])
		var col := brass if k % 2 == 0 else steel
		var dir := Vector3(cos(a), 0, sin(a))
		var rot := Vector3(0, -angles[k], 0)
		var head_at := dir * 0.027
		add(b, h, cyl(0.0105, 0.0105, 0.0022, 16), col, head_at + Vector3(0, 0.0012 + 0.0022 * k * 0.0, 0), Vector3.ZERO)
		add(b, h, box(Vector3(0.05, 0.0022, 0.0075)), col, dir * 0.057 + Vector3(0, 0.0012, 0), rot)
		for t in 3: # teeth
			var along := 0.045 + t * 0.012
			add(b, h, box(Vector3(0.005, 0.0022, 0.004)), col, dir * along + Vector3(-dir.z, 0, dir.x) * 0.0055 + Vector3(0, 0.0012, 0), rot)
	return b


## A kitchen knife lying on its side: blade along +x, handle behind it.
static func knife(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID)
	var steel := Color(0.78, 0.8, 0.83)
	var black := Color(0.06, 0.06, 0.07)
	# the blade lies on its side (flat on the board): a polygon with a straight spine and a curved edge
	add(b, h, prism([Vector2(0.0, -0.016), Vector2(0.15, -0.016), Vector2(0.205, -0.003), Vector2(0.155, 0.012), Vector2(0.0, 0.017)], 0.0025),
		steel, Vector3(0.0, 0.0013, 0.0))
	add(b, h, cyl(0.0105, 0.0105, 0.012, 16), steel, Vector3(-0.003, 0.0105, 0.0), Vector3(0, 0, 90)) # bolster
	add(b, h, box(Vector3(0.115, 0.02, 0.026)), black, Vector3(-0.0685, 0.01, 0.0)) # handle
	for k in 3:
		add(b, h, cyl(0.0035, 0.0035, 0.022, 10), steel, Vector3(-0.105 + k * 0.032, 0.01, 0.0), Vector3(0, 0, 0))
	return b


## A bar of soap: a rounded block with a stamped top.
static func soap(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, SOLID)
	var pink := Color(0.92, 0.78, 0.8)
	add(b, h, box(Vector3(0.078, 0.02, 0.05)), pink, Vector3(0, 0.01, 0))
	add(b, h, box(Vector3(0.07, 0.016, 0.044)), pink, Vector3(0, 0.0125, 0))
	add(b, h, box(Vector3(0.04, 0.001, 0.022)), Color(0.82, 0.66, 0.7), Vector3(0, 0.0205, 0))
	return b


## A cup of two toothbrushes: a glass tumbler and two brushes leaning on the rim.
static func toothbrush_cup(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, HOLLOW)
	add(b, h, lathe([Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.036, 0.09), Vector2(0.034, 0.09),
		Vector2(0.03, 0.01), Vector2(0.0, 0.01)]), Color(0.85, 0.9, 0.95))
	var cols := [Color(0.2, 0.5, 0.85), Color(0.9, 0.35, 0.4)]
	for k in 2:
		var lean := 11.0 if k == 0 else -9.0
		var base := Vector3(-0.012 if k == 0 else 0.013, 0.012, 0.0)
		var axis := Vector3(-sin(deg_to_rad(lean)), cos(deg_to_rad(lean)), 0.0)
		var rot := Vector3(0, 0, lean)
		add(b, h, box(Vector3(0.011, 0.19, 0.008)), cols[k], base + axis * 0.1, rot) # handle
		add(b, h, box(Vector3(0.011, 0.035, 0.008)), cols[k], base + axis * 0.2, rot) # head
		add(b, h, box(Vector3(0.008, 0.03, 0.008)), Color.WHITE, base + axis * 0.2 + Vector3(0, 0, 0.007), rot) # bristles
	return b


## A clothes iron: sole plate, shell with a pointed nose, and a loop handle.
static func iron(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, HOLLOW)
	var steel := Color(0.72, 0.74, 0.77)
	var shell := Color(0.25, 0.4, 0.7)
	var sole := [Vector2(-0.12, -0.05), Vector2(0.07, -0.05), Vector2(0.135, 0.0), Vector2(0.07, 0.05), Vector2(-0.12, 0.05)]
	var upper := [Vector2(-0.11, -0.043), Vector2(0.055, -0.043), Vector2(0.105, 0.0), Vector2(0.055, 0.043), Vector2(-0.11, 0.043)]
	var cap := [Vector2(-0.1, -0.033), Vector2(0.03, -0.033), Vector2(0.07, 0.0), Vector2(0.03, 0.033), Vector2(-0.1, 0.033)]
	add(b, h, prism(sole, 0.012), steel, Vector3(0, 0.006, 0))
	add(b, h, prism(upper, 0.03), shell, Vector3(0, 0.027, 0))
	add(b, h, prism(cap, 0.014), Color(0.15, 0.15, 0.17), Vector3(0, 0.049, 0))
	for sz in [-1, 1]:
		add(b, h, cyl(0.007, 0.007, 0.05, 12), Color(0.15, 0.15, 0.17), Vector3(-0.07, 0.074, sz * 0.026))
	add(b, h, cyl(0.009, 0.009, 0.06, 12), Color(0.15, 0.15, 0.17), Vector3(-0.07, 0.1, 0.0), Vector3(90, 0, 0))
	return b


## A ball with two seams.
static func ball(h: Node3D, name: String, pos: Vector3) -> StaticBody3D:
	var b := body(h, name, pos, HOLLOW)
	add(b, h, sph(0.12), Color(0.8, 0.2, 0.2), Vector3(0, 0.12, 0))
	add(b, h, torus(0.1205, 0.003), Color(0.95, 0.95, 0.95), Vector3(0, 0.12, 0))
	add(b, h, torus(0.1205, 0.003), Color(0.95, 0.95, 0.95), Vector3(0, 0.12, 0), Vector3(90, 0, 0))
	return b
