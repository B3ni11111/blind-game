extends SceneTree
## Measures raycast cost in the house:  godot --headless --path . --script res://tools/bench_rays.gd
const House := preload("res://scripts/house.gd")
var house: Node3D
var _f := 0
func _initialize() -> void:
	house = House.new()
	root.add_child(house)
func _physics_process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var space := house.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = Vector3(-1.5, 1.6, 0)
	var n := 20000
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for i in n:
		var a := i * 0.6180339 * TAU
		var z := 1.0 - 2.0 * (i + 0.5) / n
		var r := sqrt(1.0 - z * z)
		q.to = q.from + Vector3(cos(a) * r, z, sin(a) * r) * 14.0
		if not space.intersect_ray(q).is_empty():
			hits += 1
	var dt := Time.get_ticks_usec() - t0
	print("rays: %d  hits: %d  total %.1f ms  per ray %.2f us" % [n, hits, dt / 1000.0, float(dt) / n])
	return true
