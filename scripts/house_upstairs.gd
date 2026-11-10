extends RefCounted
## The east wing (back hall, stair hall, workshop) and the whole upstairs floor.
## Uses the house's builders (`box`, `cyl`, `door`, furniture helpers).
##
## Ground floor additions (y 0):
##   Back hall   x 10.2..14,   z 2.7..5     arch from the kitchen, arch to the stair hall
##   Stair hall  x 14.2..17.4, z 0.7..5     16 steps up along the east wall, rising north
##   Workshop    x 14.2..17.4, z -4.7..0.5  door from the stair hall
## Upstairs (floor y 2.7, ceiling y 5.3):
##   Corridor x 4.4..15.4, z -0.6..0.6, landing x 15.6..17.4 (stairwell opening)
##   North: guest room, bathroom, kids' room, storage. South: master bedroom, office.

const House := preload("res://scripts/house.gd")
const Props := preload("res://scripts/props.gd")
const H := House.H
const T := House.T
const F := House.FLOOR2

# Stairs: bottom step at z 4.3 (ground), top at z 0.8 (upstairs floor), x 16.2..17.2
const STAIR_X0 := 16.2
const STAIR_X1 := 17.2
const STAIR_Z_BOTTOM := 4.3
const STAIR_Z_TOP := 0.8
const STEPS := 16

var h: House


func build(house: House) -> void:
	h = house
	_shell()
	_back_hall()
	_stairs()
	_workshop()
	_upstairs_walls()
	_guest_room()
	_upstairs_bath()
	_kids_room()
	_storage()
	_master_bedroom()
	_office()


static func register_rooms(house: House) -> void:
	house.add_room("corridor", 4.3, 15.5, -0.7, 0.7, F)
	house.add_room("landing", 15.5, 17.5, -0.7, 5.1, F)
	house.add_room("guest", 4.3, 8.5, -4.8, -0.7, F)
	house.add_room("bath2", 8.5, 11.1, -4.8, -0.7, F)
	house.add_room("kids", 11.1, 15.5, -4.8, -0.7, F)
	house.add_room("storage", 15.5, 17.5, -4.8, -0.7, F)
	house.add_room("master", 4.3, 10.1, 0.7, 5.1, F)
	house.add_room("office", 10.1, 15.5, 0.7, 5.1, F)
	house.link("stairhall", "landing", "", 0.45) # the stairwell is always open, but a long way round
	house.link("corridor", "landing")
	house.link("landing", "storage", "StorageDoor")
	house.link("corridor", "guest", "GuestDoor")
	house.link("corridor", "bath2", "Bath2Door")
	house.link("corridor", "kids", "KidsDoor")
	house.link("corridor", "master", "MasterDoor")
	house.link("corridor", "office", "OfficeDoor")


# --- Helpers ------------------------------------------------------------------

## A wall along x at `z`, from x0 to x1, standing on floor y0. `gaps` are
## [xa, xb, door label ("" = open arch), swing]; each gets a header above it.
func wall_x(z: float, x0: float, x1: float, y0: float, gaps := []) -> void:
	h.paint(House.C_WALL)
	var x := x0
	for g in gaps:
		var xa: float = g[0]
		var xb: float = g[1]
		if xa > x:
			h.box(Vector3((x + xa) / 2, y0 + H / 2, z), Vector3(xa - x, H, T))
		h.box(Vector3((xa + xb) / 2, y0 + 2.35, z), Vector3(xb - xa, 0.5, T))
		if g[2] != "":
			h.door(Vector3(xa, y0, z), xb - xa, g[2], g[3])
			h.paint(House.C_WALL)
		x = xb
	if x1 > x:
		h.box(Vector3((x + x1) / 2, y0 + H / 2, z), Vector3(x1 - x, H, T))


## A wall along z at `x` (open arches only).
func wall_z(x: float, z0: float, z1: float, y0: float, arches := []) -> void:
	h.paint(House.C_WALL)
	var z := z0
	for a in arches:
		if a[0] > z:
			h.box(Vector3(x, y0 + H / 2, (z + a[0]) / 2), Vector3(T, H, a[0] - z))
		h.box(Vector3(x, y0 + 2.35, (a[0] + a[1]) / 2), Vector3(T, 0.5, a[1] - a[0]))
		z = a[1]
	if z1 > z:
		h.box(Vector3(x, y0 + H / 2, (z + z1) / 2), Vector3(T, H, z1 - z))


## A horizontal slab from (x0, z0) to (x1, z1), top at y.
func slab(x0: float, x1: float, z0: float, z1: float, y: float, thick: float, label: String) -> void:
	h.box(Vector3((x0 + x1) / 2, y - thick / 2, (z0 + z1) / 2), Vector3(x1 - x0, thick, z1 - z0), House.SOLID, label)


func bed(center: Vector3, length: float, width: float, yaw_deg: float, col: Color) -> void:
	var g := h.group(center, yaw_deg) # head at local +x
	h.paint(House.C_WOOD)
	# the frame stands on legs: there is room to slide under it (0.3 m)
	h.box(Vector3(0, 0.35, 0), Vector3(length, 0.1, width), House.SOLID, "BedFrame", g)
	for lx in [-1.0, 1.0]:
		for lz in [-1.0, 1.0]:
			h.box(Vector3(lx * (length / 2 - 0.07), 0.15, lz * (width / 2 - 0.07)), Vector3(0.08, 0.3, 0.08), House.SOLID, "BedLeg", g)
	h.box(Vector3(length / 2 - 0.04, 0.55, 0), Vector3(0.08, 1.1, width), House.SOLID, "Headboard", g)
	h.paint(House.C_WHITE)
	h.box(Vector3(0, 0.47, 0), Vector3(length - 0.05, 0.14, width - 0.04), House.SOLID, "Mattress", g)
	h.box(Vector3(length / 2 - 0.3, 0.6, 0), Vector3(0.35, 0.12, width * 0.7), House.SOLID, "Pillow", g)
	h.paint(col)
	h.box(Vector3(-0.25, 0.57, 0), Vector3(length * 0.62, 0.07, width + 0.02), House.SOLID, "Duvet", g)


# --- Shell: floors, ceilings, roof, outer walls ------------------------------------

func _shell() -> void:
	# Ground floor slab under the new wing
	h.paint(House.C_FLOOR)
	slab(14.4, 17.6, -5.0, 5.4, 0.0, 0.1, "Floor")
	# Wing ceiling = upstairs floor, with the stairwell opening
	h.paint(House.C_CEIL)
	slab(14.4, STAIR_X0, -5.0, 5.4, F, 0.1, "Ceiling")
	slab(STAIR_X0, 17.6, -5.0, STAIR_Z_TOP, F, 0.1, "Ceiling")
	slab(STAIR_X0, 17.6, STAIR_Z_BOTTOM, 5.4, F, 0.1, "Ceiling")
	slab(STAIR_X1, 17.6, STAIR_Z_TOP, STAIR_Z_BOTTOM, F, 0.1, "Ceiling")
	# Upstairs wooden floor (on top of the ceiling slabs)
	h.paint(House.C_FLOOR)
	slab(4.3, STAIR_X0, -4.8, 5.1, F + 0.012, 0.012, "UpperFloor")
	slab(STAIR_X0, 17.5, -4.8, STAIR_Z_TOP, F + 0.012, 0.012, "UpperFloor")
	slab(STAIR_X0, 17.5, STAIR_Z_BOTTOM, 5.1, F + 0.012, 0.012, "UpperFloor")
	slab(STAIR_X1, 17.5, STAIR_Z_TOP, STAIR_Z_BOTTOM, F + 0.012, 0.012, "UpperFloor")
	# Roof (upstairs ceiling)
	h.paint(House.C_CEIL)
	slab(4.2, 17.6, -5.0, 5.4, F + H + 0.1, 0.1, "Roof")
	# Ground floor outer walls of the wing
	h.paint(House.C_WALL)
	h.box(Vector3(17.5, H / 2, 0.15), Vector3(T, H, 10.1))          # east
	h.box(Vector3(15.85, H / 2, -4.8), Vector3(3.5, H, T))          # north (workshop)
	h.box(Vector3(13.8, H / 2, 5.1), Vector3(7.6, H, T))            # south (back hall + stair hall)
	# Upstairs outer walls
	h.box(Vector3(4.3, F + H / 2, 0.15), Vector3(T, H, 10.1))       # west
	h.box(Vector3(17.5, F + H / 2, 0.15), Vector3(T, H, 10.1))      # east
	h.box(Vector3(10.9, F + H / 2, -4.8), Vector3(13.4, H, T))      # north
	h.box(Vector3(10.9, F + H / 2, 5.1), Vector3(13.4, H, T))       # south


# --- Ground floor: back hall, stairs, workshop --------------------------------------

func _back_hall() -> void:
	# East side: arch into the stair hall
	wall_z(14.1, 2.7, 5.0, 0.0, [[3.1, 4.5]])
	h.ceiling_light(Vector3(12.0, 0, 3.85), 4.0, 0.6)
	h.rug(Vector3(12.2, 0, 3.85), 2.4, 0.8, House.C_BLUEGREY)
	# Shoe rack and a bench under coat hooks
	h.paint(House.C_WOOD)
	h.box(Vector3(12.0, 0.23, 4.82), Vector3(1.2, 0.04, 0.35), House.SOLID, "Bench")
	for sx in [-1, 1]:
		h.box(Vector3(12.0 + sx * 0.56, 0.11, 4.82), Vector3(0.05, 0.22, 0.33), House.SOLID, "BenchLeg")
	h.paint(House.C_DARKWOOD)
	h.box(Vector3(12.0, 1.7, 4.97), Vector3(1.0, 0.08, 0.04), House.SOLID, "CoatHookBoard")
	h.paint(House.C_BLUEGREY)
	h.box(Vector3(11.7, 1.3, 4.9), Vector3(0.4, 0.7, 0.1), House.SOLID, "Jacket")
	h.plant(Vector3(10.4, 0, 4.7), 0.9)


func _stairs() -> void:
	var rise := F / STEPS
	var run := (STAIR_Z_BOTTOM - STAIR_Z_TOP) / STEPS
	var cx := (STAIR_X0 + STAIR_X1) / 2
	h.paint(House.C_WOOD)
	for k in STEPS:
		var top := (k + 1) * rise
		var z1 := STAIR_Z_BOTTOM - k * run
		h.box(Vector3(cx, top / 2, z1 - run / 2), Vector3(STAIR_X1 - STAIR_X0, top, run), House.SOLID, "Step")
	# Invisible ramp the player actually walks on (scan rays ignore it). Its top surface
	# runs along the step nosings: from the floor one step out, to the top step's edge.
	var z_low := STAIR_Z_BOTTOM + run
	var z_high := STAIR_Z_TOP + run
	var length := Vector2(z_low - z_high, F).length() + 0.02
	var ang := atan2(F, z_low - z_high)
	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.collision_layer = 1 << (House.RAMP_LAYER - 1)
	ramp.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(STAIR_X1 - STAIR_X0, 0.1, length)
	cs.shape = bs
	ramp.add_child(cs)
	# centre a little above the step nosings, tilted to rise toward -z
	var mid := Vector3(cx, F / 2 + 0.02 - 0.05 / cos(ang), (z_low + z_high) / 2)
	ramp.position = mid
	ramp.rotation.x = ang
	h.add_child(ramp)
	# Handrail on the open (west) side: posts and a sloped rail
	h.paint(House.C_DARKWOOD)
	for k in [0, 5, 10, 15]:
		var z: float = STAIR_Z_BOTTOM - (k + 0.5) * run
		var y0: float = (k + 1) * rise
		h.box(Vector3(STAIR_X0 + 0.04, y0 + 0.45, z), Vector3(0.05, 0.9, 0.05), House.SOLID, "RailPost")
	var rail := h.box(Vector3(STAIR_X0 + 0.04, F / 2 + 0.92, (z_low + z_high) / 2),
		Vector3(0.06, 0.05, length - 0.5), House.SOLID, "Handrail")
	rail.rotation.x = ang
	# Upstairs: railing around the stairwell opening
	for z in [1.3, 2.3, 3.3, 4.2]:
		h.box(Vector3(STAIR_X0 - 0.04, F + 0.45, z), Vector3(0.05, 0.9, 0.05), House.SOLID, "RailPost")
	h.box(Vector3(STAIR_X0 - 0.04, F + 0.92, (STAIR_Z_TOP + 0.5 + STAIR_Z_BOTTOM) / 2), Vector3(0.06, 0.05, STAIR_Z_BOTTOM - STAIR_Z_TOP - 0.5), House.SOLID, "Railing")
	h.box(Vector3(cx, F + 0.92, STAIR_Z_BOTTOM + 0.04), Vector3(STAIR_X1 - STAIR_X0 + 0.1, 0.05, 0.06), House.SOLID, "Railing")
	for x in [STAIR_X0 + 0.3, STAIR_X1 - 0.1]:
		h.box(Vector3(x, F + 0.45, STAIR_Z_BOTTOM + 0.04), Vector3(0.05, 0.9, 0.05), House.SOLID, "RailPost")
	h.ceiling_light(Vector3(15.0, 0, 3.0), 4.5, 0.6)
	h.plant(Vector3(14.5, 0, 1.0))


func _workshop() -> void:
	wall_x(0.6, 14.1, 17.5, 0.0, [[14.6, 15.5, "WorkshopDoor", 1]])
	h.ceiling_light(Vector3(15.8, 0, -2.1), 4.5, 0.8)
	# Workbench along the east wall, pegboard with tools above
	h.table(Vector3(16.9, 0.9, -2.2), Vector3(0.75, 0.06, 2.0), House.C_WOOD)
	h.paint(House.C_BEIGE)
	h.box(Vector3(17.38, 1.6, -2.2), Vector3(0.02, 0.9, 1.8), House.SOLID, "Pegboard")
	h.paint(House.C_METAL)
	for k in 4: # hanging tools: wrench, saw, screwdrivers
		var z := -2.9 + k * 0.45
		h.box(Vector3(17.35, 1.55 - (k % 2) * 0.1, z), Vector3(0.03, 0.35 + (k % 2) * 0.15, 0.26 if k == 1 else 0.06), House.SOLID, "Tool")
	h.paint(House.C_RED)
	h.box(Vector3(16.9, 1.03, -1.6), Vector3(0.4, 0.2, 0.22), House.HOLLOW, "Toolbox")
	Props.hammer(h, "Hammer", Vector3(16.85, 0.946, -2.5))
	# Shelf with paint cans, sawhorse, an old bicycle shape
	h.shelf(Vector3(14.4, 0, -3.0), -90, 1.6, 1.8, 0.35, 4, House.C_WOOD)
	h.paint(House.C_BLUEGREY)
	for k in 3:
		h.cyl(Vector3(15.0 + k * 0.32, 0.12, -4.45), 0.11, 0.24, House.HOLLOW, "PaintCan")
	h.paint(House.C_WOOD)
	h.box(Vector3(15.6, 0.6, -1.2), Vector3(1.0, 0.08, 0.1), House.SOLID, "Sawhorse")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var leg := h.box(Vector3(15.6 + sx * 0.4, 0.29, -1.2 + sz * 0.14), Vector3(0.05, 0.6, 0.05), House.SOLID, "SawhorseLeg")
			leg.rotation_degrees.x = -sz * 13


# --- Upstairs -------------------------------------------------------------------

func _upstairs_walls() -> void:
	# Corridor north wall with four doors, south wall with two doors (landing open)
	wall_x(-0.7, 4.4, 17.4, F, [
		[6.0, 6.9, "GuestDoor", -1], [9.3, 10.2, "Bath2Door", -1],
		[13.5, 14.4, "KidsDoor", -1], [16.0, 16.9, "StorageDoor", -1]])
	wall_x(0.7, 4.4, 15.5, F, [[7.0, 7.9, "MasterDoor", 1], [12.0, 12.9, "OfficeDoor", 1]])
	# Room dividers
	wall_z(8.5, -4.7, -0.8, F)
	wall_z(11.1, -4.7, -0.8, F)
	wall_z(15.5, -4.7, -0.8, F)
	wall_z(10.1, 0.8, 5.0, F)
	wall_z(15.5, 0.8, 5.0, F)
	h.ceiling_light(Vector3(9.0, F, 0.0), 5.0, 0.6)
	h.ceiling_light(Vector3(16.5, F, 2.5), 4.0, 0.6)
	h.rug(Vector3(9.5, F, 0.0), 6.0, 0.7, House.C_RED)
	h.picture(Vector3(11.5, F + 1.5, -0.58), 0.6, 0.45, "z")
	h.plant(Vector3(17.0, F, -0.3), 0.8)


func _guest_room() -> void:
	h.ceiling_light(Vector3(6.4, F, -2.7), 4.0, 0.6)
	bed(Vector3(5.45, F, -3.6), 1.9, 1.3, 180, House.C_GREEN) # head against the west wall
	h.paint(House.C_WOOD)
	h.box(Vector3(4.65, F + 0.3, -2.3), Vector3(0.4, 0.6, 0.4), House.HOLLOW, "Nightstand")
	h.lamp_table(Vector3(4.65, F + 0.6, -2.3))
	h.box(Vector3(8.1, F + 1.0, -2.6), Vector3(0.6, 2.0, 1.1), House.HOLLOW, "GuestWardrobe")
	h.rug(Vector3(6.4, F, -2.2), 1.6, 1.0, House.C_BEIGE)


func _upstairs_bath() -> void:
	h.ceiling_light(Vector3(9.8, F, -2.7), 3.5, 0.6)
	h.paint(House.C_TILE)
	h.box(Vector3(9.8, F + 0.016, -2.75), Vector3(2.4, 0.008, 3.9), House.SOLID, "Tiles")
	h.paint(House.C_WHITE)
	h.box(Vector3(9.8, F + 1.0, -4.2), Vector3(1.0, 2.0, 0.9), House.GLASS, "ShowerGlass")
	h.box(Vector3(9.8, F + 0.05, -4.2), Vector3(1.0, 0.08, 0.9), House.SOLID, "ShowerTray")
	h.cyl(Vector3(10.65, F + 0.2, -2.4), 0.19, 0.4, House.HOLLOW, "Toilet")
	h.cyl(Vector3(10.65, F + 0.415, -2.4), 0.2, 0.03, House.SOLID, "ToiletLid")
	h.box(Vector3(10.88, F + 0.6, -2.4), Vector3(0.2, 0.42, 0.45), House.HOLLOW, "ToiletTank")
	h.paint(House.C_WOOD)
	h.box(Vector3(8.88, F + 0.4, -2.0), Vector3(0.5, 0.8, 0.6), House.HOLLOW, "SinkCabinet")
	h.paint(House.C_WHITE)
	h.box(Vector3(8.88, F + 0.85, -2.0), Vector3(0.5, 0.1, 0.6), House.SOLID, "Basin")
	h.box(Vector3(8.62, F + 1.5, -2.0), Vector3(0.02, 0.7, 0.6), House.GLASS, "Mirror")


func _kids_room() -> void:
	h.ceiling_light(Vector3(13.3, F, -2.7), 4.5, 0.6)
	bed(Vector3(12.2, F, -3.9), 1.6, 0.9, 180, House.C_RED)
	h.paint(House.C_BLUEGREY)
	h.box(Vector3(15.0, F + 0.25, -4.3), Vector3(0.7, 0.5, 0.5), House.HOLLOW, "ToyBox")
	h.table(Vector3(14.6, F + 0.6, -2.0), Vector3(0.9, 0.04, 0.55), House.C_WHITE)
	h.chair(Vector3(14.6, F, -1.45), 0, House.C_WHITE)
	h.paint(House.C_RED)
	Props.ball(h, "Ball", Vector3(13.0, F, -2.0))
	h.rug(Vector3(13.2, F, -2.5), 2.0, 1.5, House.C_GREEN)
	h.paint(House.C_BEIGE)
	h.box(Vector3(11.5, F + 0.2, -1.4), Vector3(0.3, 0.4, 0.3), House.HOLLOW, "Teddy")
	h.sph(Vector3(11.5, F + 0.52, -1.4), 0.12, House.SOLID, "TeddyHead")


func _storage() -> void:
	h.shelf(Vector3(16.5, F, -4.5), 180, 1.6, 2.0, 0.35, 4, House.C_WOOD)
	h.paint(House.C_CARDBOARD)
	h.box(Vector3(16.0, F + 0.25, -1.4), Vector3(0.6, 0.5, 0.5), House.HOLLOW, "Box")
	h.box(Vector3(16.05, F + 0.65, -1.4), Vector3(0.45, 0.3, 0.4), House.HOLLOW, "Box")
	h.box(Vector3(17.0, F + 0.3, -2.5), Vector3(0.6, 0.6, 0.6), House.HOLLOW, "Box")
	h.paint(House.C_BLUEGREY)
	h.box(Vector3(17.05, F + 0.7, -3.4), Vector3(0.55, 1.4, 0.25), House.HOLLOW, "Suitcase")


func _master_bedroom() -> void:
	h.ceiling_light(Vector3(7.2, F, 2.9), 5.0, 0.7)
	bed(Vector3(5.45, F, 3.2), 2.0, 1.6, 180, House.C_FABRIC)
	h.paint(House.C_WOOD)
	for z in [2.15, 4.25]:
		h.box(Vector3(4.65, F + 0.3, z), Vector3(0.4, 0.6, 0.4), House.HOLLOW, "Nightstand")
		h.lamp_table(Vector3(4.65, F + 0.6, z))
	h.box(Vector3(9.7, F + 1.0, 3.0), Vector3(0.6, 2.0, 1.6), House.HOLLOW, "MasterWardrobe")
	h.box(Vector3(7.5, F + 0.45, 4.78), Vector3(1.2, 0.9, 0.45), House.HOLLOW, "Dresser")
	h.paint(House.C_WHITE)
	h.box(Vector3(7.5, F + 1.45, 4.98), Vector3(0.7, 0.9, 0.02), House.GLASS, "DresserMirror")
	h.rug(Vector3(6.8, F, 3.2), 2.0, 2.0, House.C_BEIGE)


func _office() -> void:
	h.ceiling_light(Vector3(12.8, F, 2.9), 5.0, 0.7)
	h.table(Vector3(12.8, F + 0.74, 4.6), Vector3(1.5, 0.04, 0.7), House.C_DARKWOOD)
	h.paint(House.C_BLACK)
	h.box(Vector3(12.8, F + 1.08, 4.85), Vector3(0.6, 0.36, 0.03), House.SOLID, "Monitor")
	h.cyl(Vector3(12.8, F + 0.85, 4.85), 0.03, 0.18, House.SOLID, "MonitorStand")
	h.box(Vector3(12.8, F + 0.77, 4.5), Vector3(0.45, 0.02, 0.15), House.SOLID, "Keyboard")
	h.chair(Vector3(12.8, F, 3.9), 180, House.C_BLACK)
	h.shelf(Vector3(10.38, F, 2.9), -90, 1.8, 2.0, 0.3, 5, House.C_DARKWOOD)
	# An upright piano against the east wall
	h.paint(House.C_BLACK)
	h.box(Vector3(15.1, F + 0.6, 2.4), Vector3(0.6, 1.2, 1.5), House.HOLLOW, "Piano")
	h.paint(House.C_WHITE)
	h.box(Vector3(14.75, F + 0.73, 2.4), Vector3(0.2, 0.03, 1.4), House.SOLID, "PianoKeys")
	h.paint(House.C_WOOD)
	h.box(Vector3(14.35, F + 0.24, 2.4), Vector3(0.35, 0.48, 0.8), House.SOLID, "PianoBench")
	h.rug(Vector3(12.6, F, 2.6), 2.4, 1.6, House.C_FABRIC)
