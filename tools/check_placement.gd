extends SceneTree
## Finds furniture/objects that float or stick into each other.
## Run:  godot --headless --path . --script res://tools/check_placement.gd
## For every body in the house it checks whether something holds it up
## (floor/furniture under it, a wall behind it, or the ceiling above it).

const House := preload("res://scripts/house.gd")

var house: Node3D


func _initialize() -> void:
	house = House.new()
	root.add_child(house)


var _frames := 0

func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_check()
		return true
	return false


func _check() -> void:
	var space := house.get_world_3d().direct_space_state
	var bodies: Array = []
	_collect(house, bodies)
	var problems := 0
	for b in bodies:
		var box := _world_aabb(b)
		if box.size == Vector3.ZERO:
			continue
		var name := String(b.name)
		if name in ["Floor", "Ceiling"]:
			continue
		if box.position.y < 0.03:
			continue # stands on the floor
		if box.end.y > House.H - 0.03:
			continue # touches the ceiling
		if _touching(space, b, box):
			continue
		problems += 1
		print("FLOATING  %-16s at %s  size %s" % [name, _v(box.get_center()), _v(box.size)])
	print("checked %d bodies, %d floating" % [bodies.size(), problems])


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is StaticBody3D:
			out.append(c)
		_collect(c, out)


func _world_aabb(b: StaticBody3D) -> AABB:
	for c in b.get_children():
		if c is MeshInstance3D:
			return c.global_transform * c.get_aabb()
	return AABB()


## Something within a few cm below, behind or above (including the parent body).
func _touching(space: PhysicsDirectSpaceState3D, b: StaticBody3D, box: AABB) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var s := BoxShape3D.new()
	s.size = box.size + Vector3(0.04, 0.04, 0.04)
	q.shape = s
	q.transform = Transform3D(Basis(), box.get_center())
	q.exclude = [b.get_rid()]
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 8)
	return not hits.is_empty()


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
