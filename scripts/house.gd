extends Node3D
## Builds the house out of simple boxes, cylinders and spheres.
## Every piece is a StaticBody3D tagged with an echo material
## (meta "echo_material"): 1 = solid, 2 = hollow, 3 = glass.
## Pieces also get a real-world colour (`paint`) and rooms get ceiling lights;
## those only matter in sighted mode. In blind mode the camera renders nothing.
##
## Layout (metres, +x east, +z south):
##   Living room  x -4..4,    z -3..3      (front door south, window north)
##   Hallway      x 4.2..10,  z -0.6..0.6
##   Bathroom     x 4.4..6.8, z -3.5..-0.8 (door from hallway)
##   Study        x 7..9.8,   z -3.5..-0.8 (door from hallway)
##   Bedroom      x 4.4..9.8, z 0.8..5     (door from hallway)
##   Kitchen      x 10.2..14, z -2.5..2.5
##   Laundry      x 10.2..14, z -4.7..-2.7 (door from kitchen)
##   Back hall    x 10.2..14, z 2.7..5     (arch from the kitchen)
##   Stair hall   x 14.2..17.4, z 0.7..5   (stairs up along the east wall)
##   Workshop     x 14.2..17.4, z -4.7..0.5 (door from the stair hall)
##   Upstairs (floor at y 2.7): corridor, landing, guest room, bathroom, kids' room,
##   storage, master bedroom, office. Built in `house_upstairs.gd`.
##
## Rooms and the passages between them (`rooms`, `passages`) are what sound travels
## through: a room whose doors are all closed is sealed (see `connected`).

signal door_toggled(door: StaticBody3D, open: bool)

const Upstairs := preload("res://scripts/house_upstairs.gd")
const Props := preload("res://scripts/props.gd")

const SOLID := 1
const HOLLOW := 2
const GLASS := 3
const WOODEN_LEG := 5 # the bad person's peg (scan dots are red); 4 = people
const DOOR := 6 # doors: an echo always picks them out clearly (dense dots, crisp frame)
const FLOOR2 := 2.7 # upstairs floor level
const RAMP_LAYER := 3 # invisible stair ramps: the player walks on them, scan rays ignore them

# How much of a sound survives each thing it has to get through (a fraction of its loudness).
const DOOR_CLOSED := 0.12 # a shut door (-18 dB)
const WALL := 0.04        # a wall (-28 dB)
const FLOOR_SLAB := 0.05  # the floor between storeys (-26 dB)

const H := 2.6 # ceiling height
const T := 0.2 # wall thickness

# Palette (sighted mode)
const C_WALL := Color(0.86, 0.84, 0.79)
const C_CEIL := Color(0.93, 0.93, 0.91)
const C_FLOOR := Color(0.52, 0.38, 0.26)
const C_TILE := Color(0.78, 0.8, 0.8)
const C_WOOD := Color(0.55, 0.38, 0.24)
const C_DARKWOOD := Color(0.3, 0.2, 0.13)
const C_WHITE := Color(0.93, 0.93, 0.92)
const C_METAL := Color(0.62, 0.64, 0.67)
const C_BLACK := Color(0.07, 0.07, 0.08)
const C_FABRIC := Color(0.3, 0.37, 0.48)
const C_RED := Color(0.55, 0.22, 0.2)
const C_GREEN := Color(0.24, 0.42, 0.22)
const C_BEIGE := Color(0.78, 0.7, 0.56)
const C_CARDBOARD := Color(0.66, 0.5, 0.32)
const C_BLUEGREY := Color(0.4, 0.45, 0.5)

const FAN_POS := Vector3(5.2, 1.2, 4.55)
const DRIP_POS := Vector3(5.4, 0.7, -3.35)
const WASHER_POS := Vector3(13.65, 0.5, -4.35)
const TV_POS := Vector3(3.85, 0.9, 1.8)
const FRIDGE_POS := Vector3(13.6, 1.0, -2.05)
const CLOCK_POS := Vector3(7.6, 2.0, -0.58)

const DOOR_TIME := 0.9

var _paint := C_WALL
var _mats := {}
var _glass_mat: StandardMaterial3D
var _screen_mat: StandardMaterial3D
var tv_screen_mat: StandardMaterial3D # the TV's own screen (the study monitor shares _screen_mat)
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.6, 0.8, 0.95, 0.25)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.05
	_glass_mat.metallic_specular = 1.0
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.05, 0.08, 0.12)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.35, 0.55, 0.9)
	_screen_mat.emission_energy_multiplier = 1.4
	tv_screen_mat = _screen_mat.duplicate()

	_build_shell()
	_build_living_room()
	_build_hallway()
	_build_bathroom()
	_build_study()
	_build_bedroom()
	_build_kitchen()
	_build_laundry()
	Upstairs.new().build(self)
	_register_rooms()


# --- Builders -------------------------------------------------------------

func paint(c: Color) -> void:
	_paint = c


func _mat_for(mat: int) -> Material:
	if mat == GLASS:
		return _glass_mat
	var key := _paint.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = _paint
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]


func _body(pos: Vector3, mat: int, label: String, parent: Node) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label if label != "" else "Part"
	body.position = pos
	body.set_meta("echo_material", mat)
	(parent if parent else self).add_child(body, true)
	return body


func _finish(body: StaticBody3D, shape: Shape3D, mesh: Mesh, mat: int) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat_for(mat)
	body.add_child(mi)


func box(center: Vector3, size: Vector3, mat := SOLID, label := "", parent: Node = null) -> StaticBody3D:
	var body := _body(center, mat, label, parent)
	var s := BoxShape3D.new()
	s.size = size
	var m := BoxMesh.new()
	m.size = size
	_finish(body, s, m, mat)
	return body


func cyl(center: Vector3, radius: float, height: float, mat := SOLID, label := "", parent: Node = null) -> StaticBody3D:
	var body := _body(center, mat, label, parent)
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 20
	_finish(body, s, m, mat)
	return body


func sph(center: Vector3, radius: float, mat := SOLID, label := "", parent: Node = null) -> StaticBody3D:
	var body := _body(center, mat, label, parent)
	var s := SphereShape3D.new()
	s.radius = radius
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	_finish(body, s, m, mat)
	return body


## A group of parts placed relative to `pos` and turned by `yaw_deg`.
func group(pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = yaw_deg
	add_child(g)
	return g


## Something you can touch or use (a door, the TV, the alarm clock): the echo shows it in
## detail, and touching it shows it as an outline. `use` is the meta that says what E does.
func interactive(body: StaticBody3D, use := "") -> StaticBody3D:
	body.add_to_group("interactive")
	if use != "":
		body.set_meta(use, true)
	return body


## Small objects the player can pick up.
func grabbable(body: StaticBody3D, half_height: float) -> StaticBody3D:
	body.add_to_group("grabbable")
	body.add_to_group("interactive")
	body.set_meta("half_height", half_height)
	return body


## The lamp fixture only. Nothing lights the house: nobody plays in the light.
func ceiling_light(pos: Vector3, rng_m: float, energy := 1.0, shadows := false) -> void:
	paint(C_WHITE)
	# A flat dome flush with the ceiling (a hanging puck reads as a floating object in echo dots).
	var lamp := cyl(Vector3(pos.x, pos.y + H - 0.025, pos.z), 0.22, 0.05, HOLLOW, "CeilingLamp")
	(lamp.get_child(1).mesh as CylinderMesh).bottom_radius = 0.17
	lamp.collision_layer = 0 # too small and flush to resolve by echo; seen only with eyes
	# No light is emitted: the sighted view is only a debug view (one flat light in main.gd).


# --- Reusable furniture ---------------------------------------------------

## Chair: back on the local +z side.
func chair(pos: Vector3, yaw := 0.0, col := C_WOOD) -> void:
	paint(col)
	var g := group(pos, yaw)
	box(Vector3(0, 0.45, 0), Vector3(0.45, 0.05, 0.45), SOLID, "ChairSeat", g)
	box(Vector3(0, 0.75, 0.21), Vector3(0.45, 0.55, 0.04), SOLID, "ChairBack", g)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(Vector3(sx * 0.2, 0.225, sz * 0.2), Vector3(0.04, 0.45, 0.04), SOLID, "ChairLeg", g)


## Table with four legs.
func table(top_center: Vector3, size: Vector3, col := C_WOOD, floor_y := -1.0) -> void:
	if floor_y < 0.0: # standing on whichever floor is below the top
		floor_y = FLOOR2 if top_center.y > FLOOR2 else 0.0
	paint(col)
	box(top_center, size, SOLID, "TableTop")
	var leg_h := top_center.y - size.y / 2 - floor_y
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			box(Vector3(top_center.x + sx * (size.x / 2 - 0.06), floor_y + leg_h / 2, top_center.z + sz * (size.z / 2 - 0.06)),
				Vector3(0.05, leg_h, 0.05), SOLID, "TableLeg")


## Open shelf unit facing local -z (back panel on +z), with random books/boxes.
func shelf(pos: Vector3, yaw: float, width: float, height: float, depth: float, levels: int, col := C_WOOD) -> void:
	var g := group(pos, yaw)
	paint(col)
	box(Vector3(0, height / 2, depth / 2 - 0.01), Vector3(width, height, 0.02), SOLID, "ShelfBack", g)
	for sx in [-1, 1]:
		box(Vector3(sx * (width / 2 - 0.02), height / 2, 0), Vector3(0.04, height, depth), SOLID, "ShelfSide", g)
	for i in levels + 1:
		var y := 0.02 + i * (height - 0.04) / levels
		box(Vector3(0, y, 0), Vector3(width, 0.03, depth), SOLID, "Shelf", g)
		if i == levels:
			break
		var x := -width / 2 + 0.06
		var gap := (height - 0.04) / levels
		while x < width / 2 - 0.1:
			var w := rng.randf_range(0.03, 0.08)
			var h := rng.randf_range(0.5, 0.85) * gap
			paint(Color.from_hsv(rng.randf(), 0.45, rng.randf_range(0.35, 0.7)))
			box(Vector3(x + w / 2, y + 0.015 + h / 2, 0.0), Vector3(w, h, depth * 0.75), SOLID, "Book", g)
			x += w + rng.randf_range(0.0, 0.06)
			if rng.randf() < 0.12:
				x += 0.15 # a gap, or a box
		paint(col)


func lamp_table(pos: Vector3) -> void:
	paint(C_METAL)
	cyl(pos + Vector3(0, 0.15, 0), 0.03, 0.3, SOLID, "LampStem")
	cyl(pos + Vector3(0, 0.01, 0), 0.08, 0.02, SOLID, "LampFoot")
	paint(C_BEIGE)
	cyl(pos + Vector3(0, 0.38, 0), 0.13, 0.18, HOLLOW, "LampShade")


func lamp_floor(pos: Vector3) -> void:
	paint(C_METAL)
	cyl(pos + Vector3(0, 0.75, 0), 0.02, 1.5, SOLID, "LampPole")
	cyl(pos + Vector3(0, 0.02, 0), 0.17, 0.04, SOLID, "LampBase")
	paint(C_BEIGE)
	cyl(pos + Vector3(0, 1.55, 0), 0.2, 0.28, HOLLOW, "LampShade")


func plant(pos: Vector3, scale := 1.0) -> void:
	paint(C_DARKWOOD)
	cyl(pos + Vector3(0, 0.18 * scale, 0), 0.16 * scale, 0.36 * scale, HOLLOW, "PlantPot")
	paint(C_GREEN)
	sph(pos + Vector3(0, 0.6 * scale, 0), 0.24 * scale, SOLID, "Leaves")
	sph(pos + Vector3(0.1, 0.82 * scale, 0.05), 0.17 * scale, SOLID, "Leaves")
	sph(pos + Vector3(-0.08, 0.78 * scale, -0.07), 0.15 * scale, SOLID, "Leaves")


## Picture frame on a wall. `normal_axis` "x" = hanging on a wall facing ֲ±x, "z" = facing ֲ±z.
func picture(center: Vector3, w: float, h: float, normal_axis: String) -> void:
	paint(C_DARKWOOD)
	if normal_axis == "x":
		box(center, Vector3(0.03, h, w), SOLID, "Frame")
		box(center, Vector3(0.035, h - 0.08, w - 0.08), GLASS, "FrameGlass")
	else:
		box(center, Vector3(w, h, 0.03), SOLID, "Frame")
		box(center, Vector3(w - 0.08, h - 0.08, 0.035), GLASS, "FrameGlass")


func rug(center: Vector3, w: float, d: float, col: Color) -> void:
	paint(col)
	var y := FLOOR2 + 0.012 if center.y >= FLOOR2 - 0.01 else 0.0
	box(Vector3(center.x, y + 0.006, center.z), Vector3(w, 0.012, d), SOLID, "Rug")


# --- Doors ----------------------------------------------------------------

## A hinged hollow door. Hinge at `hinge` (floor level); the panel extends along +x.
## `swing` +1 opens toward +z (south), -1 toward -z (north).
func door(hinge: Vector3, width: float, label: String, swing := 1) -> void:
	var pivot := Node3D.new()
	pivot.name = label + "Hinge"
	pivot.position = hinge
	add_child(pivot, true)
	paint(C_WHITE)
	var panel := box(Vector3(width / 2, 1.04, 0), Vector3(width - 0.02, 2.08, 0.05), HOLLOW, label, pivot)
	paint(C_METAL)
	# Handles sit on both faces, near the free edge, at hand height (panel-local coordinates).
	var hx := width / 2 - 0.1
	var hy := 1.0 - 1.04
	for side in [1, -1]:
		cyl(Vector3(hx, hy, side * 0.045), 0.012, 0.04, SOLID, "HandleNeck", panel).rotation_degrees.x = 90
		var lever := cyl(Vector3(hx - 0.05, hy, side * 0.07), 0.012, 0.12, SOLID, "Handle", panel)
		lever.rotation_degrees.z = 90
	panel.set_meta("door", true)
	panel.add_to_group("interactive")
	panel.set_meta("echo_material", DOOR)
	panel.set_meta("size", Vector3(width - 0.02, 2.08, 0.05))
	panel.set_meta("open", false)
	panel.set_meta("open_deg", -100.0 if swing > 0 else 100.0)


func is_door(o: Object) -> bool:
	return o is Node and o.has_meta("door")


func toggle_door(panel: StaticBody3D) -> void:
	var open := not bool(panel.get_meta("open"))
	panel.set_meta("open", open)
	var pivot := panel.get_parent() as Node3D
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pivot, "rotation_degrees:y", float(panel.get_meta("open_deg")) if open else 0.0, DOOR_TIME)
	door_toggled.emit(panel, open)


# --- Rooms ----------------------------------------------------------------

func _build_shell() -> void:
	paint(C_FLOOR)
	box(Vector3(5, -0.05, 0.2), Vector3(18.8, 0.1, 10.4), SOLID, "Floor")
	paint(C_CEIL)
	box(Vector3(5, H + 0.05, 0.2), Vector3(18.8, 0.1, 10.4), SOLID, "Ceiling")


func _build_living_room() -> void:
	paint(C_WALL)
	# North wall with a window
	box(Vector3(-2.6, H / 2, -3.1), Vector3(3.2, H, T))
	box(Vector3(2.6, H / 2, -3.1), Vector3(3.2, H, T))
	box(Vector3(0, 0.45, -3.1), Vector3(2.0, 0.9, T))
	box(Vector3(0, 2.3, -3.1), Vector3(2.0, 0.6, T))
	box(Vector3(0, 1.45, -3.1), Vector3(2.0, 1.1, 0.03), GLASS, "Window")
	# South wall with the front door
	box(Vector3(-3.35, H / 2, 3.1), Vector3(1.7, H, T))
	box(Vector3(1.35, H / 2, 3.1), Vector3(5.7, H, T))
	box(Vector3(-2.0, 2.35, 3.1), Vector3(1.0, 0.5, T))
	paint(C_DARKWOOD)
	box(Vector3(-2.0, 1.05, 3.06), Vector3(0.95, 2.1, 0.05), HOLLOW, "FrontDoor")
	paint(C_WALL)
	# West wall, east wall with opening to the hallway
	box(Vector3(-4.1, H / 2, 0), Vector3(T, H, 6.4))
	box(Vector3(4.1, H / 2, -1.9), Vector3(T, H, 2.6))
	box(Vector3(4.1, H / 2, 1.9), Vector3(T, H, 2.6))
	box(Vector3(4.1, 2.35, 0), Vector3(T, 0.5, 1.2))

	ceiling_light(Vector3(-1.5, 0, 0), 7.0, 1.2)
	ceiling_light(Vector3(1.8, 0, -1.2), 5.0, 0.8)

	# Couch + cushions
	paint(C_FABRIC)
	box(Vector3(-3.4, 0.25, 0), Vector3(0.9, 0.5, 2.2), SOLID, "CouchSeat")
	box(Vector3(-3.85, 0.6, 0), Vector3(0.2, 0.9, 2.2), SOLID, "CouchBack")
	box(Vector3(-3.4, 0.35, 1.2), Vector3(0.9, 0.7, 0.2), SOLID, "CouchArm")
	box(Vector3(-3.4, 0.35, -1.2), Vector3(0.9, 0.7, 0.2), SOLID, "CouchArm")
	paint(C_RED)
	box(Vector3(-3.6, 0.65, 0.6), Vector3(0.15, 0.35, 0.4), SOLID, "Cushion")
	box(Vector3(-3.6, 0.65, -0.55), Vector3(0.15, 0.35, 0.4), SOLID, "Cushion")
	paint(C_BEIGE)
	box(Vector3(-3.3, 0.53, -0.1), Vector3(0.5, 0.05, 0.6), SOLID, "Blanket")

	# Side table + lamp, floor lamp, plants
	paint(C_WOOD)
	box(Vector3(-3.5, 0.3, -1.65), Vector3(0.4, 0.6, 0.4), HOLLOW, "SideTable")
	lamp_table(Vector3(-3.5, 0.6, -1.65))
	lamp_floor(Vector3(-3.4, 0, 1.75))
	plant(Vector3(-3.6, 0, -2.65))
	plant(Vector3(3.6, 0, 0.9), 0.8)

	# Rug + coffee table with things on it
	rug(Vector3(-1.8, 0, 0), 2.2, 1.9, C_RED)
	table(Vector3(-1.8, 0.42, 0), Vector3(0.8, 0.06, 1.3))
	paint(C_WHITE)
	Props.mug(self, "Mug", Vector3(-1.75, 0.45, -0.35), Color(0.93, 0.93, 0.9))
	Props.bottle(self, "Bottle", Vector3(-1.9, 0.45, 0.3))
	paint(C_BLACK)
	Props.remote(self, "Remote", Vector3(-1.62, 0.45, 0.05))
	_alarm_clock(Vector3(-1.65, 0.45, 0.5))
	paint(C_RED)
	box(Vector3(-1.95, 0.465, -0.05), Vector3(0.22, 0.03, 0.3), SOLID, "Magazine")

	# Pictures over the couch
	picture(Vector3(-3.98, 1.6, -0.5), 0.6, 0.45, "x")
	picture(Vector3(-3.98, 1.65, 0.45), 0.45, 0.6, "x")

	# Dining table, four chairs, fruit bowl
	table(Vector3(1.5, 0.75, -1.4), Vector3(1.6, 0.05, 0.9))
	chair(Vector3(1.05, 0, -0.65))
	chair(Vector3(1.95, 0, -0.65))
	chair(Vector3(1.05, 0, -2.15), 180)
	chair(Vector3(1.95, 0, -2.15), 180)
	paint(C_WHITE)
	cyl(Vector3(1.5, 0.81, -1.4), 0.16, 0.07, HOLLOW, "FruitBowl")
	paint(C_RED)
	food(sph(Vector3(1.45, 0.86, -1.38), 0.04, SOLID, "Apple"), Color(1.0, 0.15, 0.12))
	food(sph(Vector3(1.56, 0.86, -1.43), 0.04, SOLID, "Apple"), Color(1.0, 0.15, 0.12))
	paint(Color(0.9, 0.8, 0.25))
	var banana := food(cyl(Vector3(1.5, 0.87, -1.32), 0.018, 0.17, SOLID, "Banana"), Color(1.0, 0.9, 0.2))
	banana.rotation_degrees = Vector3(0, 30, 80)

	# Bookshelf against the south wall
	shelf(Vector3(2.5, 0, 2.85), 0, 1.2, 1.9, 0.3, 4)

	# TV corner (screen = glass)
	paint(C_DARKWOOD)
	interactive(box(Vector3(3.75, 0.25, 1.8), Vector3(0.4, 0.5, 1.4), HOLLOW, "TVStand"), "tv_switch")
	paint(C_BLACK)
	interactive(box(Vector3(3.9, 0.88, 1.8), Vector3(0.06, 0.65, 1.1), SOLID, "TV"), "tv_switch")
	var screen := box(Vector3(3.865, 0.88, 1.8), Vector3(0.01, 0.56, 1.0), GLASS, "TVScreen")
	interactive(screen, "tv_switch")
	(screen.get_child(1) as MeshInstance3D).material_override = tv_screen_mat
	box(Vector3(3.75, 0.56, 1.25), Vector3(0.18, 0.12, 0.25), SOLID, "GameConsole")

	# Wardrobe, entry corner
	paint(C_WOOD)
	box(Vector3(3.45, 1.0, -2.65), Vector3(1.0, 2.0, 0.6), HOLLOW, "Wardrobe")
	# Coat rack: pole with pegs at the top, a coat hanging from one peg
	paint(C_DARKWOOD)
	cyl(Vector3(-3.4, 0.9, 2.65), 0.025, 1.8, SOLID, "CoatRack")
	cyl(Vector3(-3.4, 0.02, 2.65), 0.2, 0.04, SOLID, "CoatRackBase")
	sph(Vector3(-3.4, 1.82, 2.65), 0.04, SOLID, "CoatRackTop")
	for a in [0, 90, 180, 270]:
		var peg := cyl(Vector3(-3.4, 1.7, 2.65) + Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a))) * 0.08, 0.012, 0.16, SOLID, "CoatPeg")
		peg.rotation_degrees = Vector3(70, a, 0)
	paint(C_BEIGE)
	box(Vector3(-3.4, 1.62, 2.77), Vector3(0.36, 0.1, 0.1), SOLID, "CoatShoulders")
	box(Vector3(-3.4, 1.22, 2.79), Vector3(0.42, 0.72, 0.12), SOLID, "Coat")
	paint(C_METAL)
	cyl(Vector3(-2.85, 0.25, 2.8), 0.12, 0.5, HOLLOW, "UmbrellaStand")
	cyl(Vector3(-2.85, 0.55, 2.8), 0.02, 0.9, SOLID, "Umbrella")
	# Shoe bench by the front door, two pairs on it
	paint(C_WOOD)
	box(Vector3(-0.9, 0.42, 2.82), Vector3(0.9, 0.04, 0.32), SOLID, "ShoeBench")
	box(Vector3(-0.9, 0.12, 2.82), Vector3(0.9, 0.03, 0.32), SOLID, "ShoeBenchShelf")
	for sx in [-1, 1]:
		box(Vector3(-0.9 + sx * 0.43, 0.2, 2.82), Vector3(0.04, 0.4, 0.32), SOLID, "ShoeBenchSide")
	paint(C_BLACK)
	for i in 2:
		for k in 2:
			var x := -1.2 + i * 0.4 + k * 0.12
			box(Vector3(x, 0.155, 2.8), Vector3(0.09, 0.04, 0.26), SOLID, "ShoeSole")
			box(Vector3(x, 0.2, 2.85), Vector3(0.085, 0.06, 0.14), SOLID, "Shoe")


func _build_hallway() -> void:
	paint(C_WALL)
	# North wall: bathroom door (x 5.0..5.9) and study door (x 8.2..9.1)
	box(Vector3(4.6, H / 2, -0.7), Vector3(0.8, H, T))
	box(Vector3(7.05, H / 2, -0.7), Vector3(2.3, H, T))
	box(Vector3(9.55, H / 2, -0.7), Vector3(0.9, H, T))
	box(Vector3(5.45, 2.35, -0.7), Vector3(0.9, 0.5, T))
	box(Vector3(8.65, 2.35, -0.7), Vector3(0.9, 0.5, T))
	door(Vector3(5.0, 0, -0.7), 0.9, "BathroomDoor", -1)
	door(Vector3(8.2, 0, -0.7), 0.9, "StudyDoor", -1)
	# South wall: bedroom door (x 6.6..7.5)
	box(Vector3(5.4, H / 2, 0.7), Vector3(2.4, H, T))
	box(Vector3(8.75, H / 2, 0.7), Vector3(2.5, H, T))
	box(Vector3(7.05, 2.35, 0.7), Vector3(0.9, 0.5, T))
	door(Vector3(6.6, 0, 0.7), 0.9, "BedroomDoor", 1)

	ceiling_light(Vector3(7.1, 0, 0), 4.5, 0.7)
	rug(Vector3(7.1, 0, 0), 5.0, 0.7, C_RED)
	paint(C_WOOD)
	box(Vector3(7.0, 0.4, -0.45), Vector3(0.4, 0.8, 0.25), HOLLOW, "SideTable")
	paint(C_WHITE)
	cyl(Vector3(7.08, 0.92, -0.45), 0.06, 0.24, GLASS, "Vase")
	paint(C_METAL)
	Props.keys(self, "Keys", Vector3(6.9, 0.8, -0.42))
	picture(Vector3(6.4, 1.5, -0.58), 0.5, 0.4, "z")
	# Wall clock (its ticking comes from here)
	paint(C_WHITE)
	var clock := cyl(CLOCK_POS, 0.15, 0.04, SOLID, "WallClock")
	clock.rotation_degrees.x = 90
	# Shoe rack near the living room
	paint(C_WOOD)
	box(Vector3(4.8, 0.25, 0.45), Vector3(0.6, 0.5, 0.25), HOLLOW, "ShoeRack")


func _build_bathroom() -> void:
	# Shared north block walls (bathroom + study)
	paint(C_WALL)
	box(Vector3(4.3, H / 2, -2.2), Vector3(T, H, 3.0))   # west
	box(Vector3(9.9, H / 2, -2.2), Vector3(T, H, 3.0))   # east
	box(Vector3(6.9, H / 2, -2.2), Vector3(T, H, 2.8))   # divider bathroom | study
	# North wall with a small bathroom window and a study window
	box(Vector3(4.65, H / 2, -3.6), Vector3(0.9, H, T))
	box(Vector3(6.75, H / 2, -3.6), Vector3(2.1, H, T))
	box(Vector3(9.5, H / 2, -3.6), Vector3(1.0, H, T))
	box(Vector3(5.4, 0.85, -3.6), Vector3(0.6, 1.7, T))
	box(Vector3(5.4, 2.35, -3.6), Vector3(0.6, 0.5, T))
	box(Vector3(5.4, 1.9, -3.6), Vector3(0.6, 0.4, 0.03), GLASS, "BathroomWindow")
	box(Vector3(8.4, 0.45, -3.6), Vector3(1.2, 0.9, T))
	box(Vector3(8.4, 2.3, -3.6), Vector3(1.2, 0.6, T))
	box(Vector3(8.4, 1.45, -3.6), Vector3(1.2, 1.1, 0.03), GLASS, "StudyWindow")

	ceiling_light(Vector3(5.6, 0, -2.15), 3.5, 0.7)
	paint(C_TILE)
	box(Vector3(5.6, 0.004, -2.15), Vector3(2.4, 0.008, 2.7), SOLID, "Tiles")

	# Bathtub (a hollow shell) with tap
	paint(C_WHITE)
	box(Vector3(5.4, 0.28, -3.12), Vector3(1.7, 0.56, 0.72), HOLLOW, "Bathtub")
	paint(C_METAL)
	# Tap: a pipe out of the wall above the tub rim, bending down into a spout (the drip comes from here)
	cyl(Vector3(DRIP_POS.x, 0.66, -3.44), 0.018, 0.2, SOLID, "BathTapPipe")
	cyl(Vector3(DRIP_POS.x, 0.76, -3.4), 0.018, 0.12, SOLID, "BathTap").rotation_degrees.x = 90
	cyl(Vector3(DRIP_POS.x, 0.72, -3.345), 0.015, 0.08, SOLID, "BathSpout")
	# Toilet
	paint(C_WHITE)
	cyl(Vector3(6.45, 0.2, -2.0), 0.19, 0.4, HOLLOW, "Toilet")
	cyl(Vector3(6.45, 0.415, -2.0), 0.2, 0.03, SOLID, "ToiletLid")
	box(Vector3(6.68, 0.6, -2.0), Vector3(0.2, 0.42, 0.45), HOLLOW, "ToiletTank")
	paint(C_WHITE)
	paint(C_METAL)
	box(Vector3(6.77, 0.85, -1.4), Vector3(0.06, 0.03, 0.03), SOLID, "PaperHolder")
	paint(C_WHITE)
	cyl(Vector3(6.73, 0.81, -1.4), 0.055, 0.11, SOLID, "ToiletPaper").rotation_degrees.x = 90
	# Sink cabinet, basin, tap, mirror
	paint(C_WOOD)
	box(Vector3(4.68, 0.4, -2.0), Vector3(0.5, 0.8, 0.6), HOLLOW, "SinkCabinet")
	paint(C_WHITE)
	box(Vector3(4.68, 0.85, -2.0), Vector3(0.5, 0.1, 0.6), SOLID, "Basin")
	paint(C_METAL)
	cyl(Vector3(4.5, 0.97, -2.0), 0.015, 0.14, SOLID, "SinkTap")
	box(Vector3(4.42, 1.5, -2.0), Vector3(0.02, 0.7, 0.6), GLASS, "Mirror")
	paint(C_WHITE)
	Props.toothbrush_cup(self, "Toothbrushes", Vector3(4.75, 0.9, -2.2))
	Props.soap(self, "Soap", Vector3(4.75, 0.9, -1.8))
	# Towel, bath mat, bin
	paint(C_FABRIC)
	# Towel draped over a rail on the divider wall
	paint(C_METAL)
	cyl(Vector3(6.75, 1.5, -3.0), 0.012, 0.5, SOLID, "TowelRail").rotation_degrees.x = 90
	for sz in [-1, 1]:
		box(Vector3(6.775, 1.5, -3.0 + sz * 0.24), Vector3(0.05, 0.03, 0.02), SOLID, "TowelRailBracket")
	paint(C_FABRIC)
	box(Vector3(6.73, 1.2, -3.0), Vector3(0.03, 0.6, 0.4), SOLID, "Towel")
	box(Vector3(6.765, 1.25, -3.0), Vector3(0.02, 0.5, 0.4), SOLID, "TowelBack")
	box(Vector3(5.4, 0.014, -2.45), Vector3(0.8, 0.012, 0.5), SOLID, "BathMat")
	paint(C_METAL)
	cyl(Vector3(6.55, 0.15, -1.15), 0.11, 0.3, HOLLOW, "Bin")


func _build_study() -> void:
	ceiling_light(Vector3(8.4, 0, -2.15), 4.0, 0.8)
	# Desk under the window, computer
	table(Vector3(8.4, 0.74, -3.15), Vector3(1.4, 0.04, 0.65), C_DARKWOOD)
	paint(C_BLACK)
	cyl(Vector3(8.4, 0.85, -3.3), 0.03, 0.18, SOLID, "MonitorStand")
	box(Vector3(8.4, 1.08, -3.3), Vector3(0.6, 0.36, 0.03), SOLID, "Monitor")
	var mon := box(Vector3(8.4, 1.08, -3.28), Vector3(0.56, 0.32, 0.006), GLASS, "MonitorScreen")
	(mon.get_child(1) as MeshInstance3D).material_override = _screen_mat
	box(Vector3(8.4, 0.77, -3.0), Vector3(0.45, 0.02, 0.15), SOLID, "Keyboard")
	box(Vector3(8.75, 0.77, -3.0), Vector3(0.06, 0.03, 0.1), SOLID, "Mouse")
	box(Vector3(7.85, 0.95, -3.3), Vector3(0.2, 0.4, 0.4), HOLLOW, "ComputerCase")
	paint(C_WHITE)
	Props.mug(self, "StudyMug", Vector3(8.95, 0.76, -3.0), Color(0.3, 0.45, 0.7))
	paint(C_BEIGE)
	box(Vector3(8.0, 0.77, -2.95), Vector3(0.22, 0.02, 0.3), SOLID, "Papers")
	# Office chair
	paint(C_BLACK)
	cyl(Vector3(8.4, 0.48, -2.5), 0.24, 0.07, SOLID, "ChairSeat")
	box(Vector3(8.4, 0.82, -2.25), Vector3(0.42, 0.52, 0.06), SOLID, "ChairBack")
	box(Vector3(8.4, 0.53, -2.27), Vector3(0.05, 0.1, 0.05), SOLID, "ChairBackPost")
	cyl(Vector3(8.4, 0.25, -2.5), 0.025, 0.42, SOLID, "ChairPole")
	cyl(Vector3(8.4, 0.04, -2.5), 0.28, 0.04, SOLID, "ChairBase")
	# Bookcase on the divider wall
	shelf(Vector3(7.18, 0, -2.4), -90, 1.4, 2.0, 0.3, 5, C_DARKWOOD)
	# Filing cabinet with a globe
	paint(C_METAL)
	box(Vector3(9.55, 0.55, -3.2), Vector3(0.45, 1.1, 0.55), HOLLOW, "FilingCabinet")
	paint(C_FABRIC)
	sph(Vector3(9.55, 1.32, -3.2), 0.15, HOLLOW, "Globe")
	paint(C_DARKWOOD)
	cyl(Vector3(9.55, 1.11, -3.2), 0.07, 0.02, SOLID, "GlobeStand")
	cyl(Vector3(9.55, 1.15, -3.2), 0.012, 0.08, SOLID, "GlobeAxis")
	# Armchair + floor lamp
	paint(C_RED)
	box(Vector3(9.4, 0.22, -2.0), Vector3(0.75, 0.44, 0.75), SOLID, "Armchair")
	box(Vector3(9.72, 0.62, -2.0), Vector3(0.15, 0.8, 0.75), SOLID, "ArmchairBack")
	box(Vector3(9.4, 0.32, -2.33), Vector3(0.75, 0.62, 0.1), SOLID, "ArmchairArm")
	box(Vector3(9.4, 0.32, -1.67), Vector3(0.75, 0.62, 0.1), SOLID, "ArmchairArm")
	lamp_floor(Vector3(9.6, 0, -1.1))
	rug(Vector3(8.4, 0, -2.2), 1.6, 1.2, C_FABRIC)


func _build_bedroom() -> void:
	paint(C_WALL)
	box(Vector3(4.3, H / 2, 2.95), Vector3(T, H, 4.3))
	box(Vector3(9.9, H / 2, 2.95), Vector3(T, H, 4.3))
	box(Vector3(5.35, H / 2, 5.1), Vector3(2.3, H, T))
	box(Vector3(8.85, H / 2, 5.1), Vector3(2.3, H, T))
	box(Vector3(7.1, 0.45, 5.1), Vector3(1.2, 0.9, T))
	box(Vector3(7.1, 2.3, 5.1), Vector3(1.2, 0.6, T))
	box(Vector3(7.1, 1.45, 5.1), Vector3(1.2, 1.1, 0.03), GLASS, "BedroomWindow")

	ceiling_light(Vector3(7.1, 0, 2.9), 5.0, 0.8)
	rug(Vector3(7.4, 0, 3.6), 2.0, 1.6, C_BEIGE)

	# Bed with headboard, pillows, duvet
	paint(C_WOOD)
	# the frame stands on legs: there is room to slide under it (0.3 m)
	box(Vector3(8.8, 0.35, 4.0), Vector3(2.0, 0.1, 1.4), SOLID, "BedFrame")
	for lx in [-0.93, 0.93]:
		for lz in [-0.63, 0.63]:
			box(Vector3(8.8 + lx, 0.15, 4.0 + lz), Vector3(0.08, 0.3, 0.08), SOLID, "BedLeg")
	box(Vector3(9.76, 0.55, 4.0), Vector3(0.08, 1.1, 1.4), SOLID, "Headboard")
	paint(C_WHITE)
	box(Vector3(8.8, 0.47, 4.0), Vector3(1.95, 0.14, 1.36), SOLID, "Mattress")
	box(Vector3(9.45, 0.6, 3.68), Vector3(0.35, 0.12, 0.55), SOLID, "Pillow")
	box(Vector3(9.45, 0.6, 4.32), Vector3(0.35, 0.12, 0.55), SOLID, "Pillow")
	paint(C_FABRIC)
	box(Vector3(8.5, 0.57, 4.0), Vector3(1.3, 0.07, 1.42), SOLID, "Duvet")

	# Nightstand (hollow) with lamp, glass of water, phone
	paint(C_WOOD)
	box(Vector3(9.6, 0.3, 2.95), Vector3(0.4, 0.6, 0.4), HOLLOW, "Nightstand")
	lamp_table(Vector3(9.65, 0.6, 3.05))
	Props.drinking_glass(self, "WaterGlass", Vector3(9.5, 0.6, 2.85))
	paint(C_BLACK)
	Props.phone(self, "Phone", Vector3(9.55, 0.6, 2.8))

	# Desk + chair against the west wall, laptop, books
	table(Vector3(4.75, 0.74, 2.2), Vector3(0.6, 0.04, 1.2))
	chair(Vector3(5.35, 0, 2.2), 90)
	paint(C_METAL)
	box(Vector3(4.75, 0.77, 2.25), Vector3(0.24, 0.02, 0.33), SOLID, "Laptop")
	box(Vector3(4.6, 0.88, 2.25), Vector3(0.02, 0.22, 0.33), GLASS, "LaptopScreen")
	paint(C_RED)
	box(Vector3(4.75, 0.79, 1.75), Vector3(0.2, 0.06, 0.28), SOLID, "Books")
	paint(C_BLUEGREY)
	box(Vector3(4.75, 0.85, 1.75), Vector3(0.18, 0.05, 0.25), SOLID, "Books")

	# Wardrobe next to the door, laundry basket, mirror
	paint(C_WOOD)
	box(Vector3(5.0, 1.0, 1.2), Vector3(1.2, 2.0, 0.6), HOLLOW, "BedroomWardrobe")
	paint(C_BEIGE)
	cyl(Vector3(9.5, 0.25, 1.3), 0.2, 0.5, HOLLOW, "LaundryBasket")
	box(Vector3(9.78, 1.2, 1.9), Vector3(0.02, 1.2, 0.5), GLASS, "WallMirror")
	picture(Vector3(7.8, 1.6, 5.0), 0.7, 0.5, "z")

	# Standing fan (the fan sound comes from here)
	paint(C_WHITE)
	cyl(Vector3(FAN_POS.x, 0.02, FAN_POS.z), 0.2, 0.04, SOLID, "FanBase")
	cyl(Vector3(FAN_POS.x, 0.6, FAN_POS.z), 0.02, 1.1, SOLID, "FanPole")
	var head := cyl(FAN_POS, 0.22, 0.12, HOLLOW, "FanHead")
	head.rotation_degrees = Vector3(90, 30, 0)


func _build_kitchen() -> void:
	paint(C_WALL)
	# West wall with the opening from the hallway
	box(Vector3(10.1, H / 2, -1.65), Vector3(T, H, 2.1))
	box(Vector3(10.1, H / 2, 1.65), Vector3(T, H, 2.1))
	box(Vector3(10.1, 2.35, 0), Vector3(T, 0.5, 1.2))
	# North wall with the laundry door (x 11.6..12.5)
	box(Vector3(10.75, H / 2, -2.6), Vector3(1.7, H, T))
	box(Vector3(13.35, H / 2, -2.6), Vector3(1.7, H, T))
	box(Vector3(12.05, 2.35, -2.6), Vector3(0.9, 0.5, T))
	door(Vector3(11.6, 0, -2.6), 0.9, "LaundryDoor", -1)
	# South wall with an open arch to the back hall (x 10.35..11.25), east wall
	box(Vector3(12.775, H / 2, 2.6), Vector3(3.05, H, T))
	box(Vector3(10.125, H / 2, 2.6), Vector3(0.45, H, T))
	box(Vector3(10.8, 2.35, 2.6), Vector3(0.9, 0.5, T))
	box(Vector3(14.1, H / 2, 0), Vector3(T, H, 5.4))

	ceiling_light(Vector3(12.0, 0, 0), 5.0, 0.9)
	paint(C_TILE)
	box(Vector3(12.05, 0.004, 0), Vector3(3.9, 0.008, 5.0), SOLID, "Tiles")

	# Counter (hollow cabinets), worktop, upper cabinets
	paint(C_WHITE)
	box(Vector3(13.6, 0.43, 0.35), Vector3(0.7, 0.86, 3.7), HOLLOW, "Counter")
	paint(C_DARKWOOD)
	box(Vector3(13.6, 0.88, 0.35), Vector3(0.72, 0.04, 3.72), SOLID, "Worktop")
	paint(C_WHITE)
	box(Vector3(13.82, 1.85, 0.35), Vector3(0.35, 0.7, 3.7), HOLLOW, "UpperCabinets")
	# Fridge
	paint(C_METAL)
	box(Vector3(13.6, 0.95, -2.05), Vector3(0.7, 1.9, 0.7), SOLID, "Fridge")
	# Sink, stove, pots, kettle, microwave, glasses
	box(Vector3(13.6, 0.885, -0.6), Vector3(0.45, 0.03, 0.5), SOLID, "Sink")
	cyl(Vector3(13.85, 1.02, -0.6), 0.015, 0.25, SOLID, "KitchenTap")
	paint(C_BLACK)
	box(Vector3(13.6, 0.91, 1.4), Vector3(0.6, 0.02, 0.6), SOLID, "Stove")
	paint(C_METAL)
	cyl(Vector3(13.5, 1.0, 1.25), 0.12, 0.16, HOLLOW, "Pot")
	cyl(Vector3(13.65, 0.99, 1.6), 0.08, 0.16, HOLLOW, "Kettle")
	paint(C_WHITE)
	box(Vector3(13.65, 1.06, -1.2), Vector3(0.4, 0.3, 0.5), HOLLOW, "Microwave")
	cyl(Vector3(13.5, 0.96, 0.5), 0.035, 0.12, GLASS, "Glass")
	cyl(Vector3(13.5, 0.96, 0.7), 0.035, 0.12, GLASS, "Glass")
	paint(C_WOOD)
	box(Vector3(13.45, 0.91, 0.1), Vector3(0.3, 0.02, 0.4), SOLID, "CuttingBoard")
	paint(C_METAL)
	Props.knife(self, "Knife", Vector3(13.45, 0.92, 0.05)).rotation_degrees.y = 90

	# Round table and chairs
	paint(C_WOOD)
	cyl(Vector3(11.8, 0.75, 1.1), 0.5, 0.04, SOLID, "KitchenTable")
	cyl(Vector3(11.8, 0.365, 1.1), 0.05, 0.73, SOLID, "KitchenTableLeg")
	cyl(Vector3(11.8, 0.02, 1.1), 0.25, 0.04, SOLID, "KitchenTableFoot")
	chair(Vector3(11.8, 0, 1.75), 0)
	chair(Vector3(11.15, 0, 1.1), -90)
	paint(C_WHITE)
	Props.drinking_glass(self, "JuiceGlass", Vector3(12.05, 0.77, 1.3))
	_dinner(Vector3(11.75, 0.77, 1.0))

	# Trash can
	paint(C_METAL)
	cyl(Vector3(12.6, 0.35, 2.25), 0.17, 0.7, HOLLOW, "TrashCan")


func _build_laundry() -> void:
	paint(C_WALL)
	box(Vector3(10.1, H / 2, -3.7), Vector3(T, H, 2.2))
	box(Vector3(12.1, H / 2, -4.8), Vector3(4.4, H, T))
	box(Vector3(14.1, H / 2, -3.7), Vector3(T, H, 2.2))

	ceiling_light(Vector3(12.1, 0, -3.7), 4.0, 0.7)
	paint(C_TILE)
	box(Vector3(12.1, 0.004, -3.7), Vector3(3.8, 0.008, 2.0), SOLID, "Tiles")

	# Washer + dryer (the washer is running)
	paint(C_WHITE)
	box(WASHER_POS - Vector3(0, 0.07, 0), Vector3(0.6, 0.86, 0.6), HOLLOW, "Washer")
	box(Vector3(12.95, 0.43, -4.35), Vector3(0.6, 0.86, 0.6), HOLLOW, "Dryer")
	var w_door := cyl(Vector3(13.65, 0.5, -4.04), 0.17, 0.02, GLASS, "WasherDoor")
	w_door.rotation_degrees.x = 90
	var d_door := cyl(Vector3(12.95, 0.5, -4.04), 0.17, 0.02, GLASS, "DryerDoor")
	d_door.rotation_degrees.x = 90
	paint(C_FABRIC)
	box(Vector3(13.3, 0.9, -4.35), Vector3(0.4, 0.06, 0.35), SOLID, "FoldedClothes")

	# Shelves on the west wall with cans and boxes
	shelf(Vector3(10.38, 0, -3.75), -90, 1.6, 1.8, 0.3, 4, C_WOOD)
	# Laundry basket, ironing board, broom
	paint(C_BEIGE)
	cyl(Vector3(12.2, 0.25, -4.3), 0.22, 0.5, HOLLOW, "LaundryBasket")
	paint(C_METAL)
	box(Vector3(11.4, 0.85, -4.05), Vector3(1.2, 0.03, 0.35), SOLID, "IroningBoard")
	cyl(Vector3(11.0, 0.42, -4.05), 0.015, 0.84, SOLID, "IroningLeg")
	cyl(Vector3(11.8, 0.42, -4.05), 0.015, 0.84, SOLID, "IroningLeg")
	Props.iron(self, "Iron", Vector3(11.75, 0.865, -4.05))
	paint(C_WOOD)
	var broom := cyl(Vector3(13.85, 0.7, -3.0), 0.015, 1.4, SOLID, "Broom")
	broom.rotation_degrees.z = 12
	paint(C_BLUEGREY)
	cyl(Vector3(13.4, 0.2, -2.95), 0.14, 0.4, HOLLOW, "Detergent")


# --- Food (smelled, so it shows in colour) --------------------------------------

## Food is tagged with the colour of its smell (`smell` group, meta "smell_color").
func food(body: StaticBody3D, smell: Color) -> StaticBody3D:
	body.add_to_group("smell")
	body.set_meta("smell_color", smell)
	return body


## A dinner plate on the kitchen table: fried chicken and broccoli.
func _dinner(at: Vector3) -> void:
	paint(C_WHITE)
	cyl(at, 0.14, 0.015, SOLID, "DinnerPlate")
	var orange := Color(1.0, 0.55, 0.12)
	var green := Color(0.35, 0.95, 0.3)
	paint(Color(0.75, 0.45, 0.15))
	for k in 2: # drumsticks: a fat end and a thin bone
		var d := Vector3(at.x - 0.05, at.y + 0.035, at.z - 0.04 + k * 0.07)
		food(box(d, Vector3(0.08, 0.045, 0.055), SOLID, "FriedChicken"), orange)
		var bone := food(cyl(d + Vector3(0.065, -0.01, 0.0), 0.009, 0.06, SOLID, "ChickenBone"), orange)
		bone.rotation_degrees.z = 90
	paint(Color(0.2, 0.5, 0.18))
	for k in 3: # broccoli florets: a stalk and a bushy head
		var b := Vector3(at.x + 0.06, at.y + 0.022, at.z - 0.05 + k * 0.045)
		food(cyl(b, 0.008, 0.03, SOLID, "BroccoliStalk"), green)
		food(sph(b + Vector3(0, 0.03, 0), 0.022, SOLID, "Broccoli"), green)


# --- Rooms (how sound travels) -----------------------------------------------

var rooms := {}     # name -> AABB (walls included up to their centre line)
var room_floor := {} # name -> 0 (ground) or 1 (upstairs)
var passages := []  # [room_a, room_b, door name ("" = always open), factor]
var _doors := {}    # door name -> panel
var _adj := {}      # room -> Array of [other room, factor, door name]: every way sound can go


func add_room(name: String, x0: float, x1: float, z0: float, z1: float, y0 := 0.0) -> void:
	rooms[name] = AABB(Vector3(x0, y0 - 0.4, z0), Vector3(x1 - x0, H + 0.45, z1 - z0))
	room_floor[name] = 1 if y0 > 1.0 else 0


## An opening between two rooms: a doorway (door_name "") or a door. `factor` < 1 for a
## long way round (e.g. up the stairwell).
func link(a: String, b: String, door_name := "", factor := 1.0) -> void:
	passages.append([a, b, door_name, factor])


func _register_rooms() -> void:
	add_room("living", -4.1, 4.1, -3.1, 3.1)
	add_room("hallway", 4.1, 10.1, -0.7, 0.7)
	add_room("bathroom", 4.3, 6.9, -3.6, -0.7)
	add_room("study", 6.9, 9.9, -3.6, -0.7)
	add_room("bedroom", 4.3, 9.9, 0.7, 5.1)
	add_room("kitchen", 10.1, 14.1, -2.6, 2.6)
	add_room("laundry", 10.1, 14.1, -4.8, -2.6)
	add_room("backhall", 9.9, 14.1, 2.6, 5.1)
	add_room("stairhall", 14.1, 17.5, 0.6, 5.1)
	add_room("workshop", 14.1, 17.5, -4.8, 0.6)
	link("living", "hallway")
	link("hallway", "bathroom", "BathroomDoor")
	link("hallway", "study", "StudyDoor")
	link("hallway", "bedroom", "BedroomDoor")
	link("hallway", "kitchen")
	link("kitchen", "laundry", "LaundryDoor")
	link("kitchen", "backhall")
	link("backhall", "stairhall")
	link("stairhall", "workshop", "WorkshopDoor")
	Upstairs.register_rooms(self) # upstairs rooms + the stairwell link
	for n in find_children("*", "StaticBody3D", true, false):
		if is_door(n):
			_doors[String(n.name)] = n
	_build_acoustics()


## Which room a point is in ("" if none, e.g. outside).
func room_at(p: Vector3) -> String:
	for name in rooms:
		if (rooms[name] as AABB).has_point(p):
			return name
	return ""


## Can sound get from room a to room b through open doorways? A room with every
## door shut is sealed from the rest of the house.
func connected(a: String, b: String) -> bool:
	if a == b:
		return true
	if a == "" or b == "":
		return false
	var seen := {a: true}
	var todo := [a]
	while not todo.is_empty():
		var r: String = todo.pop_back()
		for p in passages:
			var other := ""
			if p[0] == r:
				other = p[1]
			elif p[1] == r:
				other = p[0]
			else:
				continue
			if seen.has(other):
				continue
			var dn: String = p[2]
			if dn != "" and not bool(_doors[dn].get_meta("open")):
				continue
			if other == b:
				return true
			seen[other] = true
			todo.append(other)
	return false


## A wind-up alarm clock: press E on it, it ticks for a few seconds, then rings very loudly
## (main.gd). Meant for testing that loud sounds still show through walls. The body is the
## round case; bells, hammer and legs are its children, so all of it "makes the sound".
func _alarm_clock(at: Vector3) -> void:
	paint(C_RED)
	var clock := cyl(at + Vector3(0, 0.08, 0), 0.08, 0.05, HOLLOW, "AlarmClock")
	clock.rotation_degrees.x = 90
	interactive(clock, "alarm")
	# children are positioned in the clock's own (rotated) space: local y is the face normal
	paint(C_WHITE)
	cyl(Vector3(0, 0.026, 0), 0.066, 0.006, SOLID, "AlarmFace", clock)
	paint(C_METAL)
	for sx in [-1, 1]:
		var bell := sph(Vector3(sx * 0.055, 0.0, -0.075), 0.032, HOLLOW, "AlarmBell", clock)
		# a flattened dome: squash the mesh, and give it a matching hull (Jolt can't scale a sphere unevenly)
		var squash := Vector3(1, 0.5, 1)
		var bell_mesh := bell.find_children("*", "MeshInstance3D", false, false)[0] as MeshInstance3D
		var hull := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for v in bell_mesh.mesh.get_faces():
			pts.append(v * squash)
		hull.points = pts
		bell_mesh.scale = squash
		(bell.find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D).shape = hull
		cyl(Vector3(sx * 0.03, 0.0, -0.05), 0.004, 0.05, SOLID, "AlarmBellPost", clock).rotation_degrees = Vector3(90, 0, sx * -30)
	cyl(Vector3(0, 0.0, -0.1), 0.005, 0.03, SOLID, "AlarmHammer", clock)
	for sx in [-1, 1]:
		var leg := box(Vector3(sx * 0.05, 0.0, 0.07), Vector3(0.012, 0.03, 0.03), SOLID, "AlarmLeg", clock)
		leg.rotation_degrees.x = 0


# --- Acoustics: how much of a sound gets from one room to another ---------------

## Every route sound can take: openings (doorways, doors, the stairwell), and straight
## through a wall or a floor into any neighbouring room.
func _build_acoustics() -> void:
	_adj.clear()
	for name in rooms:
		_adj[name] = []
	for p in passages:
		_adj[p[0]].append([p[1], p[3], p[2]])
		_adj[p[1]].append([p[0], p[3], p[2]])
	var names := rooms.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: AABB = rooms[names[i]]
			var b: AABB = rooms[names[j]]
			var ox := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var oz := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			var through := 0.0
			if room_floor[names[i]] == room_floor[names[j]]:
				if (absf(ox) <= 0.45 and oz > 0.6) or (absf(oz) <= 0.45 and ox > 0.6):
					through = WALL
			elif ox > 0.6 and oz > 0.6:
				through = FLOOR_SLAB
			if through > 0.0:
				_adj[names[i]].append([names[j], through, ""])
				_adj[names[j]].append([names[i], through, ""])


## The fraction of a sound's loudness that gets from room `a` to room `b`: the best route
## through the house, where every closed door, wall and floor on the way multiplies it down
## (two walls = much quieter than one). 1 = a clear path.
func transmission(a: String, b: String) -> float:
	if a == b or a == "" or b == "":
		return 1.0
	var best := {a: 1.0}
	var todo := [a]
	while not todo.is_empty():
		var r: String = todo.pop_front()
		var tr: float = best[r]
		for e in _adj[r]:
			var f: float = e[1]
			var dn: String = e[2]
			if dn != "" and not bool(_doors[dn].get_meta("open")):
				f *= DOOR_CLOSED
			var t := tr * f
			if t > float(best.get(e[0], 0.0)):
				best[e[0]] = t
				todo.append(e[0])
	return float(best.get(b, 0.0))

