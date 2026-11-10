extends Node
## The bad person's mind: he looks for you by ear.
##
## He walks his round (`patrol`: places and how long he stops at each, walked in a loop
## on the navigation mesh) until he hears something: your tongue click, your footsteps (running
## carries far, careful walking only a couple of metres), a door, the locked front door
## rattling, the alarm clock. A sound reaches him if it is close enough, and what is in the
## way counts: walls, closed doors and floors shorten how far it carries (the same numbers
## the player's hearing uses, `house.transmission`).
##
## When he hears something he goes to where the sound came from (he never knows where you
## are, only where the last sound was), faster if it was close. He opens the doors in his
## way. There he stands and listens for a while, then goes back to his patrol.
## Stand still and silent and he may pass a step away. If he comes within reach, he has you.
##
## Hiding (a closet, under a bed): he cannot find you there, unless he hears a sound come
## from your hiding place (getting in while he is in earshot, or a click). Then he knows:
## he comes, opens it, and has you.
##
## He finds his way with a navigation mesh baked from the house at start (`bake()`), so he
## walks round furniture, through doorways and up the stairs.

signal caught

enum { PATROL, INVESTIGATE, LISTEN }

const CATCH_DIST := 0.85        # within this (and nothing between you): he has you
const LISTEN_TIME := 4.0        # how long he stands at the place he heard something
const PACE_INVESTIGATE := 1.2
const PACE_HUNT := 1.65         # heard you close by: he hurries (you walk at 1.45 m/s)
const HUNT_DIST := 4.5
const DOOR_REACH := 1.0
const HIDE_CATCH_DIST := 1.6    # he knows where you hide and is standing at it

var npc: Node3D                 # npc.gd
var player: Node3D
var house: Node3D               # house.gd
var enabled := true
var player_hidden := false      # you are in a closet or under a bed
var knows_hide := false         # he heard your hiding place: it will not save you
var state := PATROL

## His round: [place, seconds he stops there], in a loop. Empty: the body's own waypoints.
var patrol: Array = []
var first_wait := 0.0           # how long he stays at the first place before the first round
var _patrol_i := 0
var _wait := 0.0

var _map: RID
var _listen := 0.0
var _region: NavigationRegion3D


## Bake the navigation mesh from the house's collision (doors left out: he opens them).
func bake() -> void:
	var t0 := Time.get_ticks_msec()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 0b101 # the world and the stair ramps
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.2 # the stairs are 1 m wide between the rail and the edge
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 46.0
	nm.region_min_size = 6.0 # no islands on table tops
	var doors: Array = []
	for n in house.find_children("*", "StaticBody3D", true, false):
		var b := n as StaticBody3D
		if house.is_door(b) or b.is_in_group("grabbable"):
			doors.append([b, b.collision_layer])
			b.collision_layer = 0
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, house)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	for d in doors:
		d[0].collision_layer = d[1]
	_region = NavigationRegion3D.new()
	_region.navigation_mesh = nm
	add_child(_region)
	_map = house.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(_map, 0.1)
	NavigationServer3D.map_set_cell_height(_map, 0.1)
	print("stalker: navigation baked in %d ms (%d polygons)" % [Time.get_ticks_msec() - t0, nm.get_polygon_count()])


func _ready() -> void:
	npc.arrived.connect(_on_arrived)
	_wait = first_wait


## A sound was made at `pos` that carries `radius` metres in open air. Does he hear it?
func hear(pos: Vector3, radius: float) -> bool:
	if not enabled:
		return false
	var at: Vector3 = npc.global_position
	var a: String = house.room_at(pos + Vector3(0, 0.3, 0))
	var b: String = house.room_at(at + Vector3(0, 0.3, 0))
	var through := 1.0
	if a != "" and b != "" and a != b:
		through = house.transmission(a, b)
	var d := at.distance_to(pos)
	if d > radius * sqrt(clampf(through, 0.0, 1.0)):
		return false
	# close by, on his own storey: he hurries
	var close := d < HUNT_DIST and absf(at.y - pos.y) < 1.5
	npc.pace = PACE_HUNT if close else maxf(npc.pace, PACE_INVESTIGATE)
	if _go_to(pos):
		state = INVESTIGATE
	return true


func _go_to(pos: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(_map, npc.global_position, pos, true)
	if path.size() < 2:
		return false
	# the mesh floats a little above the floor: put every point on the ground
	var space := house.get_world_3d().direct_space_state
	for i in path.size():
		var q := PhysicsRayQueryParameters3D.create(path[i] + Vector3(0, 0.4, 0), path[i] - Vector3(0, 0.6, 0), 0b101)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			path[i] = hit.position
	npc.follow(path)
	return true


func _on_arrived() -> void:
	match state:
		INVESTIGATE:
			state = LISTEN
			_listen = LISTEN_TIME
			npc._pause = LISTEN_TIME + 0.2
		PATROL:
			if not patrol.is_empty():
				_wait = patrol[_patrol_i][1]
				_patrol_i = (_patrol_i + 1) % patrol.size()


func _process(delta: float) -> void:
	if not enabled:
		return
	if state == LISTEN:
		_listen -= delta
		if _listen <= 0.0:
			# nothing more: back to his round
			npc.pace = 1.0
			state = PATROL
			_wait = 0.0
			if patrol.is_empty() and not npc.waypoints.is_empty():
				_go_to(npc.waypoints[npc._i])
	elif state == PATROL and not patrol.is_empty() and npc.nav_path.is_empty():
		_wait -= delta
		if _wait <= 0.0 and not _go_to(patrol[_patrol_i][0]):
			_patrol_i = (_patrol_i + 1) % patrol.size() # can't get there: the next place
	_open_doors()
	_try_catch()


## He opens a closed door that is right in front of him (you hear it).
func _open_doors() -> void:
	if state == PATROL or state == LISTEN:
		return
	var at: Vector3 = npc.global_position
	var fwd: Vector3 = -npc.global_transform.basis.z
	for name in house._doors:
		var panel: StaticBody3D = house._doors[name]
		if panel.get_meta("open") or panel.has_meta("locked"):
			continue
		var to := panel.global_position - at
		to.y = 0.0
		if absf(panel.global_position.y - 1.04 - at.y) < 1.0 and to.length() < DOOR_REACH and to.normalized().dot(fwd) > 0.1:
			house.toggle_door(panel)
			npc._pause = 0.7


func _try_catch() -> void:
	var a: Vector3 = npc.global_position
	var b: Vector3 = player.global_position
	var flat := Vector2(a.x - b.x, a.z - b.z).length()
	if player_hidden:
		# only if he heard you in there: then he goes to it and pulls you out
		if knows_hide and absf(a.y - b.y) < 1.0 and flat < HIDE_CATCH_DIST:
			_catch()
		return
	if absf(a.y - b.y) > 1.0 or flat > CATCH_DIST:
		return
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.2, 0), b + Vector3(0, 1.2, 0), 1)
	q.exclude = [player.get_rid()]
	var hit := house.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or house.is_door(hit.collider):
		_catch()


func _catch() -> void:
	enabled = false
	npc.nav_path = PackedVector3Array()
	npc._pause = 1.0e6
	caught.emit()
