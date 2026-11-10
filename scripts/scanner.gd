extends Node3D
## The echo: a 360 degree snapshot of the house, sent out from where you stand.
##
## The house has fixed dots (world_dots.gd): every surface carries its own dots, always in
## the same place, with close bright lines of dots on every sharp edge and corner. A click
## decides which of them light up. The rays are cast in every direction from your head (an
## equi-angular cube map, FACE_RES x FACE_RES per face) and only measure how far they went:
## a small depth cube map. The GPU then lights each fixed dot that was the nearest thing in
## its direction (a shadow-map test), when the wave reaches it (distance / WAVE_SPEED: one
## ring going out from you), as bright as its distance from you allows.
##
## Scans add up: the last SLOTS scans are all kept, so scanning again from the same place
## just scans again. They hold while you stand still; the moment you press a movement key
## they fade (gone FADE_TIME later). What you scanned is hidden behind walls once you have
## walked away (main.gd gives the blind view black occluders of the house).
##
## The capture is instant: at the click every person and every door is frozen (a still copy
## of its collision shapes on SNAP_LAYER) and the rays are cast against those copies, so a
## walking person shows in one pose even though the rays take a few ticks to cast.
##
## Things you can interact with (doors, the TV, the clock, anything you can pick up) get a
## detail pass (dots along their edges, rims and corners), and people a silhouette pass
## (outline dots as seen from where you stood). Both go through the same depth test, so
## only what the wave reached shows. People show only from the latest scan.
##
## Shadows: surfaces hidden behind things (from where you stood) are not left black. The
## wave bounces: a few extra vantage points about a metre around you cast a thinner set of
## rays, and what they see that you could not shows up as smaller, much dimmer dots.

const FixedShader := preload("res://shaders/echo_fixed.gdshader")
const DetailShader := preload("res://shaders/echo_detail.gdshader")
const Outline := preload("res://scripts/outline.gd")
const WorldDots := preload("res://scripts/world_dots.gd")

const FACE_RES := 60            # rays per cube face side (6 * 60 * 60 = 21,600 rays)
const BUDGET_USEC := 6000       # raycasting time per physics tick (all rays done in ~0.2 s)
const WAVE_SPEED := 12.0        # metres per second: fast like sound (the 4 m edge in about 0.35 s)
const WAVE_DELAY := 0.05        # the click leaves you; the first rays are ahead of the ring by then
const COOLDOWN := 0.45
const MAX_RANGE := 4.0          # how far the echo reaches (3.5 m + 15%)
const FADE_TIME := 0.6          # seconds from the first movement key press until a scan is gone
const NEVER := 1.0e9
const TOUCHES := 8              # touch patches at once (0 = the reaching hand)
const HAND_RADIUS := 0.75       # how wide the patch under your hand is
const SLOTS := 4                # scans kept at once (they add up)
const DOT_LAYER := 11           # visual layer the dots live on (blind mode renders only these)
const LIVE_MASK := 0b11         # world (1) and people (2); not the player-only stair ramps (3)
const SNAP_LAYER := 4           # the frozen copies of people and doors
const RAY_MASK := 0b1001        # what the scan rays hit: the world and the frozen copies
const PERSON_PTS := 260         # silhouette sample pool per body part (most are not used)
const DETAIL_PER_OBJECT := 540
const DETAIL_MAX := 9000
const PEOPLE_MAX := 8000
const SHADOW_ORIGINS := 6       # extra vantage points that see round the things in the way
const SHADOW_RAYS := 2025       # rays from each
const SHADOW_MAX := 12150

## Cube faces as columns (right, up, forward). The shaders have the same table.
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],   # front
	[Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)],   # left
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],   # right
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],   # back
	[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],    # up
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)],  # down
]

var camera: Camera3D
var exclude: Array[RID] = []
var clock := 0.0

var _fixed: MultiMeshInstance3D                  # the house's fixed dots
var _fixed_mat: ShaderMaterial
var _imgs: Array[Image] = []                     # per slot: the depth cube map
var _texs: Array[ImageTexture] = []
var _d_clouds: Array[MultiMeshInstance3D] = []   # per slot: detail dots of interactive things
var _d_mats: Array[ShaderMaterial] = []
var _s_clouds: Array[MultiMeshInstance3D] = []   # per slot: the dim dots that fill shadows
var _s_mats: Array[ShaderMaterial] = []
var _p_cloud: MultiMeshInstance3D                # people, from the latest scan only
var _p_mat: ShaderMaterial
var _dbuf := PackedFloat32Array()
var _pbuf := PackedFloat32Array()
var _sbuf := PackedFloat32Array()
var _detail_pts := {}                            # instance id -> points in the object's own space
var _s_origins: Array[Vector3] = []
var _s_k := 0
var _s_r := 0
var _s_count := 0
var _cur := 0
var _dirs := PackedVector3Array()   # unit ray directions in scan space, indexed by ray id
var _order := PackedInt32Array()    # cast order: coarse subset first, randomly scattered

# per slot, as the fixed shader takes them
var _origins := PackedVector3Array()
var _bx := PackedVector3Array()
var _bz := PackedVector3Array()
var _t0s := PackedFloat32Array()
var _fades := PackedFloat32Array()
var _slot_fade := PackedFloat32Array()  # when each slot started to fade (NEVER: holding)
var _slot_used: Array[bool] = []

var _scanning := false
var _scan_start := -100.0
var _next := 0
var _origin := Vector3.ZERO
var _basis := Basis()
var _last_scan := -100.0
var _query := PhysicsRayQueryParameters3D.new()       # scan rays: world + frozen copies
var _live := PhysicsRayQueryParameters3D.new()        # checks made at the click: the live world
var _frozen: Array[RID] = []
var _touches: Array[Vector4] = []
var _touch_r := PackedFloat32Array()
var _touch_fall := PackedFloat32Array()
var _person_pts := {}   # body part instance id -> [points, normals] in the part's own space


## `house` is the root of the level: its static bodies get the fixed dots.
func setup(cam: Camera3D, exclude_rids: Array[RID], house: Node) -> void:
	camera = cam
	exclude = exclude_rids
	_build_dirs()
	_build_order()
	for i in TOUCHES:
		_touches.append(Vector4.ZERO)
		_touch_r.append(HAND_RADIUS)
		_touch_fall.append(1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_dbuf = _identity_buffer(DETAIL_MAX)
	_pbuf = _identity_buffer(PEOPLE_MAX)
	_sbuf = _identity_buffer(SHADOW_MAX)
	for k in SLOTS:
		var img := Image.create(FACE_RES * 6, FACE_RES, false, Image.FORMAT_RGBAH)
		img.fill(Color(0, 0, 0, 0))
		_imgs.append(img)
		_texs.append(ImageTexture.create_from_image(img))
		_origins.append(Vector3.ZERO)
		_bx.append(Vector3.RIGHT)
		_bz.append(Vector3.BACK)
		_t0s.append(-100.0)
		_fades.append(0.0)
		_slot_fade.append(NEVER)
		_slot_used.append(false)
		var dmat := _detail_mat(k, 1.0, 1.0, true)
		_d_clouds.append(_instance(_cloud(quad, DETAIL_MAX), dmat))
		_d_mats.append(dmat)
		var smat := _detail_mat(k, 0.2, 0.7, false)
		_s_clouds.append(_instance(_cloud(quad, SHADOW_MAX), smat))
		_s_mats.append(smat)
	_p_mat = _detail_mat(0, 1.0, 1.0, true)
	_p_cloud = _instance(_cloud(quad, PEOPLE_MAX), _p_mat)

	# the fixed dots of the house
	var dots := WorldDots.build(house, func(b: Node) -> bool:
		return b.is_in_group("interactive") or _is_person(b))
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	fmm.use_custom_data = true
	fmm.mesh = quad
	fmm.instance_count = dots.count
	fmm.buffer = dots.buffer
	_fixed_mat = ShaderMaterial.new()
	_fixed_mat.shader = FixedShader
	for k in SLOTS:
		_fixed_mat.set_shader_parameter("scan%d" % k, _texs[k])
	_fixed_mat.set_shader_parameter("face_res", FACE_RES)
	_fixed_mat.set_shader_parameter("wave_speed", WAVE_SPEED)
	_fixed_mat.set_shader_parameter("max_dist", MAX_RANGE)
	_fixed_mat.set_shader_parameter("texel_angle", deg_to_rad(90.0 / FACE_RES))
	_push_slots()
	_fixed = _instance(fmm, _fixed_mat)
	print("echo: %d fixed dots" % dots.count)

	_query.collision_mask = RAY_MASK
	_query.exclude = exclude
	_live.collision_mask = LIVE_MASK
	_live.exclude = exclude
	# Work out the structure dots of everything interactive now, not on the first click.
	for node in get_tree().get_nodes_in_group("interactive"):
		_object_points(node)


func _is_person(n: Node) -> bool:
	for p in get_tree().get_nodes_in_group("people"):
		if (p as Node).is_ancestor_of(n):
			return true
	return false


func _identity_buffer(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n * 16)
	for i in n:
		b[i * 16] = 1.0
		b[i * 16 + 5] = 1.0
		b[i * 16 + 10] = 1.0
	return b


func _cloud(quad: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	mm.visible_instance_count = 0
	return mm


## A material for detail / shadow / people dots of slot k. `depth_test`: only dots the
## wave reached from where you stood (the slot's depth cube map) light up.
func _detail_mat(k: int, strength: float, size_mul: float, depth_test: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DetailShader
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("size_mul", size_mul)
	m.set_shader_parameter("fade", 0.0)
	m.set_shader_parameter("depth_test", depth_test)
	m.set_shader_parameter("scan_data", _texs[k])
	m.set_shader_parameter("face_res", FACE_RES)
	m.set_shader_parameter("texel_angle", deg_to_rad(90.0 / FACE_RES))
	m.set_shader_parameter("max_dist", MAX_RANGE)
	return m


func _instance(mm: MultiMesh, mat: ShaderMaterial) -> MultiMeshInstance3D:
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.layers = 1 << (DOT_LAYER - 1)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.top_level = true
	inst.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	add_child(inst)
	return inst


func _push_slots() -> void:
	_fixed_mat.set_shader_parameter("origin", _origins)
	_fixed_mat.set_shader_parameter("basis_x", _bx)
	_fixed_mat.set_shader_parameter("basis_z", _bz)
	_fixed_mat.set_shader_parameter("t0", _t0s)
	_fixed_mat.set_shader_parameter("fade", _fades)


## Equi-angular cube map: rays are spread almost evenly over the sphere.
## Ray id = face * R*R + j * R + i (the data texture uses x = face * R + i, y = j).
func _build_dirs() -> void:
	_dirs.resize(6 * FACE_RES * FACE_RES)
	for f in 6:
		var right: Vector3 = FACES[f][0]
		var up: Vector3 = FACES[f][1]
		var fwd: Vector3 = FACES[f][2]
		for j in FACE_RES:
			var v := tan(((j + 0.5) / FACE_RES * 2.0 - 1.0) * PI / 4.0)
			for i in FACE_RES:
				var u := tan(((i + 0.5) / FACE_RES * 2.0 - 1.0) * PI / 4.0)
				_dirs[(f * FACE_RES + j) * FACE_RES + i] = (right * u - up * v + fwd).normalized()


## The wave goes out in all directions at once, so rays are cast in a random scatter, a
## coarse subset (1 in 16) first, then 1 in 4, then the rest. By the time the wave has
## reached a few metres the whole sphere already has a thin layer of dots, and it fills in.
func _build_order() -> void:
	var passes: Array = [[], [], []]
	for f in 6:
		for j in FACE_RES:
			for i in FACE_RES:
				var id := (f * FACE_RES + j) * FACE_RES + i
				var p := 2
				if i % 4 == 0 and j % 4 == 0:
					p = 0
				elif i % 2 == 0 and j % 2 == 0:
					p = 1
				passes[p].append(id)
	seed(7)
	_order = PackedInt32Array()
	for p in passes:
		p.shuffle()
		for id in p:
			_order.append(id)



## Wipe every scan (used by tests).
func clear() -> void:
	_scanning = false
	_thaw()
	for k in SLOTS:
		_slot_used[k] = false
		_fades[k] = 0.0
	_push_slots()


func can_scan() -> bool:
	return clock - _last_scan >= COOLDOWN


func scan() -> bool:
	if not can_scan():
		return false
	# Scans add up: this one takes the oldest slot; the others stay as they are.
	_cur = (_cur + 1) % SLOTS
	_last_scan = clock
	_scan_start = clock
	_scanning = true
	_next = 0
	_origin = camera.global_position
	# Yaw only: the cube is aligned with the body, so "front" is where you face.
	_basis = Basis(Vector3.UP, camera.global_rotation.y)
	_freeze()
	_query.from = _origin
	_live.from = _origin
	_imgs[_cur].fill(Color(0, 0, 0, 0))
	_texs[_cur].update(_imgs[_cur])
	_origins[_cur] = _origin
	_bx[_cur] = _basis.x
	_bz[_cur] = _basis.z
	_t0s[_cur] = _wave_t0()
	_slot_fade[_cur] = NEVER
	_slot_used[_cur] = true
	_fades[_cur] = 1.0
	_push_slots()
	for m in [_d_mats[_cur], _s_mats[_cur], _p_mat]:
		m.set_shader_parameter("origin", _origin)
		m.set_shader_parameter("basis_x", _basis.x)
		m.set_shader_parameter("basis_z", _basis.z)
	_p_mat.set_shader_parameter("scan_data", _texs[_cur])
	_build_detail()
	_build_shadow_origins()
	_s_k = 0
	_s_r = 0
	_s_count = 0
	_s_clouds[_cur].multimesh.visible_instance_count = 0
	return true


## The extra vantage points: about a metre to each side, in front and behind, and two
## diagonals, pulled in if a wall or person is in the way.
func _build_shadow_origins() -> void:
	_s_origins.clear()
	var space := get_world_3d().direct_space_state
	var right := _basis.x
	var fwd := -_basis.z
	var offsets: Array[Vector3] = [right * 1.1, -right * 1.1, fwd * 1.1, -fwd * 1.1,
		(right + fwd) * 1.3, -(right + fwd) * 1.3]
	for off in offsets:
		var reach := off.length()
		_live.to = _origin + off
		var hit := space.intersect_ray(_live)
		if not hit.is_empty():
			reach = maxf(_origin.distance_to(hit.position) - 0.25, 0.2)
		_s_origins.append(_origin + off.normalized() * reach)


## Detail pass: dots along the structure of each interactive thing in range, and the
## silhouettes of people. The shader keeps only the dots the wave actually reached.
func _build_detail() -> void:
	var n := 0
	for node in get_tree().get_nodes_in_group("interactive"):
		var body := node as CollisionObject3D
		if body == null or body.collision_layer == 0: # (held things have no layer)
			continue
		var xf := body.global_transform
		if xf.origin.distance_to(_origin) > MAX_RANGE + 1.0:
			continue
		var pts := _object_points(body)
		var mat_id := float(body.get_meta("echo_material", 1))
		for p in pts:
			if n >= DETAIL_MAX:
				break
			var w: Vector3 = xf * p
			var dist := _origin.distance_to(w)
			if dist > MAX_RANGE:
				continue
			_put(_dbuf, n, w, dist, mat_id)
			n += 1
	var mm := _d_clouds[_cur].multimesh
	mm.buffer = _dbuf
	mm.visible_instance_count = n
	var np := _build_people_detail()
	_p_cloud.multimesh.buffer = _pbuf
	_p_cloud.multimesh.visible_instance_count = np


func _put(buf: PackedFloat32Array, n: int, w: Vector3, dist: float, mat_id: float) -> void:
	var o := n * 16
	buf[o + 3] = w.x
	buf[o + 7] = w.y
	buf[o + 11] = w.z
	buf[o + 12] = _wave_t0() + dist / WAVE_SPEED
	buf[o + 13] = mat_id
	buf[o + 14] = randf()
	buf[o + 15] = dist


## People: for each body part in range, dots on its outline as seen from where you stood
## (surface points side-on to you) and a thinner fill of the side facing you.
func _build_people_detail() -> int:
	var n := 0
	for person in get_tree().get_nodes_in_group("people"):
		var root := person as Node3D
		if root.global_position.distance_to(_origin) > MAX_RANGE + 1.0:
			continue
		for c in root.find_children("*", "StaticBody3D", true, false):
			var part := c as StaticBody3D
			var xf := part.global_transform
			var pn: Array = _part_points(part)
			var pts: PackedVector3Array = pn[0]
			var nrm: PackedVector3Array = pn[1]
			var mat_id := float(part.get_meta("echo_material", 4))
			for k in pts.size():
				if n >= PEOPLE_MAX:
					return n
				var w: Vector3 = xf * pts[k]
				var nw: Vector3 = (xf.basis * nrm[k]).normalized()
				var f := nw.dot((_origin - w).normalized())
				if f < -0.05:
					continue # the far side of the body part
				var rim := f < 0.35
				if not rim and randf() > 0.3:
					continue # a thin fill of the side facing you
				var dist := _origin.distance_to(w)
				if dist > MAX_RANGE:
					continue
				_put(_pbuf, n, w, dist, mat_id + (0.5 if rim else 0.0)) # +.5: an outline dot
				n += 1
	return n


## Points spread evenly over a body part's surface, with their outward normals (cached).
func _part_points(part: StaticBody3D) -> Array:
	var key := part.get_instance_id()
	if _person_pts.has(key):
		return _person_pts[key]
	var tris := PackedVector3Array()
	var inv := part.global_transform.affine_inverse()
	for c in part.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var to_part := inv * mi.global_transform
		for v in mi.mesh.get_faces():
			tris.append(to_part * v)
	var center := Vector3.ZERO
	for v in tris:
		center += v
	center /= maxf(tris.size(), 1)
	var areas := PackedFloat32Array()
	var total := 0.0
	for t in range(0, tris.size(), 3):
		total += (tris[t + 1] - tris[t]).cross(tris[t + 2] - tris[t]).length() * 0.5
		areas.append(total)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var count := clampi(int(total * 2600.0), 24, PERSON_PTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = key
	for k in count:
		var pick := rng.randf() * total
		var lo := 0
		var hi := areas.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if areas[mid] < pick:
				lo = mid + 1
			else:
				hi = mid
		var a := tris[lo * 3]
		var b := tris[lo * 3 + 1]
		var c := tris[lo * 3 + 2]
		var r1 := sqrt(rng.randf())
		var r2 := rng.randf()
		var p := a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)
		var nn := (b - a).cross(c - a).normalized()
		if nn.dot(p - center) < 0.0:
			nn = -nn # outward (the parts are convex)
		pts.append(p)
		nrm.append(nn)
	_person_pts[key] = [pts, nrm]
	return _person_pts[key]


# --- The frozen moment ------------------------------------------------------
# Every person and every door is copied, as it is at the click, into still bodies on
# SNAP_LAYER. The scan rays hit only the world and these copies, so nothing that moves
# while the rays are being cast can smear. A copy carries the original node's id, so a hit
# reads the original's echo material. The copies are removed once the scan is cast.

func _freeze() -> void:
	_thaw()
	var space_rid := get_world_3d().space
	var ex: Array[RID] = exclude.duplicate()
	var movers: Array = []
	for person in get_tree().get_nodes_in_group("people"):
		movers.append_array((person as Node).find_children("*", "StaticBody3D", true, false))
	for node in get_tree().get_nodes_in_group("interactive"):
		if node is StaticBody3D and node.has_meta("open_deg"): # a door panel
			movers.append(node)
	for m in movers:
		var body := m as CollisionObject3D
		if body.collision_layer == 0:
			continue
		var xf := body.global_transform
		var inv := xf.affine_inverse()
		var b := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(b, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(b, 1 << (SNAP_LAYER - 1))
		PhysicsServer3D.body_set_collision_mask(b, 0)
		PhysicsServer3D.body_attach_object_instance_id(b, body.get_instance_id())
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs and cs.shape and not cs.disabled:
				PhysicsServer3D.body_add_shape(b, cs.shape.get_rid(), inv * cs.global_transform)
		PhysicsServer3D.body_set_state(b, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		PhysicsServer3D.body_set_space(b, space_rid)
		_frozen.append(b)
		if body.collision_layer & 1:
			ex.append(body.get_rid()) # the live door: its frozen copy stands in for it
	_query.exclude = ex


func _thaw() -> void:
	for b in _frozen:
		PhysicsServer3D.free_rid(b)
	_frozen.clear()
	_query.exclude = exclude




## Fear: every dot shakes (0 = still .. 1 = terror).
func set_tremble(v: float) -> void:
	_fixed_mat.set_shader_parameter("tremble", v)
	_p_mat.set_shader_parameter("tremble", v)
	for k in SLOTS:
		_d_mats[k].set_shader_parameter("tremble", v)
		_s_mats[k].set_shader_parameter("tremble", v)


## Your reaching hand: the patch of surface around `pos` shows (strength 0..1).
func set_touch(pos: Vector3, strength: float) -> void:
	_touches[0] = Vector4(pos.x, pos.y, pos.z, strength)


## A touch that is over at once (a footfall, something you bumped into): the patch of
## surface `radius` wide around `pos` shows, then dies away over `seconds`.
func add_touch(pos: Vector3, radius: float, seconds: float) -> void:
	var k := 1
	for i in range(1, TOUCHES): # the weakest slot
		if _touches[i].w < _touches[k].w:
			k = i
	_touches[k] = Vector4(pos.x, pos.y, pos.z, 1.0)
	_touch_r[k] = radius
	_touch_fall[k] = 1.0 / maxf(seconds, 0.05)


func _wave_t0() -> float:
	return _scan_start + WAVE_DELAY


# --- Holding the picture ----------------------------------------------------
# Scans hold while you stand still (looking around is fine). The moment you press a
# movement key they start to fade, and are gone FADE_TIME later, however far you walk.

## Start fading every scan now (a movement key was pressed). `only_finished`: only scans
## whose wave is already out (used while a movement key is held: a scan made on the move
## still shows once, then fades).
func start_fade(only_finished := false) -> void:
	for k in SLOTS:
		if not _slot_used[k] or _slot_fade[k] < NEVER:
			continue
		if only_finished and clock < _t0s[k] + MAX_RANGE / WAVE_SPEED:
			continue
		_slot_fade[k] = clock


func _process(delta: float) -> void:
	clock += delta
	for i in range(1, TOUCHES):
		_touches[i].w = maxf(0.0, _touches[i].w - delta * _touch_fall[i])
	_fixed_mat.set_shader_parameter("touches", _touches)
	_fixed_mat.set_shader_parameter("touch_r", _touch_r)
	for k in SLOTS:
		var f := 0.0
		if _slot_used[k]:
			f = 1.0 - smoothstep(_slot_fade[k], _slot_fade[k] + FADE_TIME, clock)
			if f <= 0.0:
				_slot_used[k] = false
		_fades[k] = f
		_d_mats[k].set_shader_parameter("fade", f)
		_s_mats[k].set_shader_parameter("fade", f)
		_d_mats[k].set_shader_parameter("now", clock)
		_s_mats[k].set_shader_parameter("now", clock)
	_p_mat.set_shader_parameter("fade", _fades[_cur])
	_p_mat.set_shader_parameter("now", clock)
	_fixed_mat.set_shader_parameter("fade", _fades)
	_fixed_mat.set_shader_parameter("now", clock)


func _physics_process(_delta: float) -> void:
	if not _scanning:
		return
	var space := get_world_3d().direct_space_state
	var img := _imgs[_cur]
	var t0 := Time.get_ticks_usec()
	var total := _order.size()
	var r := FACE_RES
	while _next < total:
		var id := _order[_next]
		_next += 1
		var dir := _basis * _dirs[id]
		_query.to = _origin + dir * MAX_RANGE
		var hit := space.intersect_ray(_query)
		var f := id / (r * r)
		var rem := id % (r * r)
		var px := f * r + rem % r
		var py := rem / r
		if hit.is_empty():
			img.set_pixel(px, py, Color(0, 0, 0, 1)) # cast, nothing came back
		else:
			img.set_pixel(px, py, Color(_origin.distance_to(hit.position), 0, 0, 1))
		if (_next & 31) == 0 and Time.get_ticks_usec() - t0 > BUDGET_USEC:
			break
	_texs[_cur].update(img)
	if _next >= total:
		_cast_shadow(space, t0)


## Rays from the extra vantage points. Each uses its own slice of the scattered ray list,
## so together they cover the sphere; hits become dim dots lit when the bounced wave arrives.
func _cast_shadow(space: PhysicsDirectSpaceState3D, t0: int) -> void:
	var p1_start := 6 * (FACE_RES / 4) * (FACE_RES / 4)  # where the "1 in 4" pass starts in _order
	var p2_start := 6 * (FACE_RES / 2) * (FACE_RES / 2)  # where the rest starts
	var slice1 := (p2_start - p1_start) / SHADOW_ORIGINS
	var changed := false
	var mm := _s_clouds[_cur].multimesh
	while _s_k < _s_origins.size():
		var o: Vector3 = _s_origins[_s_k]
		_query.from = o
		var path0 := _origin.distance_to(o)
		while _s_r < SHADOW_RAYS:
			var r := _s_r
			_s_r += 1
			var slot := p1_start + _s_k * slice1 + r if r < slice1 else p2_start + _s_k * 1350 + (r - slice1)
			var dir := _basis * _dirs[_order[slot]]
			_query.to = o + dir * MAX_RANGE
			var hit := space.intersect_ray(_query)
			if not hit.is_empty() and _s_count < SHADOW_MAX:
				var p: Vector3 = hit.position
				var w := _s_count * 16
				_sbuf[w + 3] = p.x
				_sbuf[w + 7] = p.y
				_sbuf[w + 11] = p.z
				_sbuf[w + 12] = _wave_t0() + (path0 + o.distance_to(p)) / WAVE_SPEED + 0.04
				_sbuf[w + 13] = 1.0
				_sbuf[w + 14] = randf()
				_sbuf[w + 15] = _origin.distance_to(p)
				_s_count += 1
				changed = true
			if (_s_r & 31) == 0 and Time.get_ticks_usec() - t0 > BUDGET_USEC:
				if changed:
					mm.buffer = _sbuf
					mm.visible_instance_count = _s_count
				_query.from = _origin
				return
		_s_k += 1
		_s_r = 0
	if changed:
		mm.buffer = _sbuf
		mm.visible_instance_count = _s_count
	_query.from = _origin
	_scanning = false
	_thaw()


## The structure dots of a thing, in its own space, cached (see outline.gd).
func _object_points(body: Node3D) -> PackedVector3Array:
	var key := body.get_instance_id()
	if _detail_pts.has(key):
		return _detail_pts[key]
	var pts := Outline.structure_points(body, DETAIL_PER_OBJECT)
	_detail_pts[key] = pts
	return pts


