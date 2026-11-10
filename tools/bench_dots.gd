extends SceneTree
## How many fixed echo dots the house gets and how long they take to build:
## godot --headless --path . --script res://tools/bench_dots.gd
const House := preload("res://scripts/house.gd")
const WorldDots := preload("res://scripts/world_dots.gd")
var house: Node3D
var _f := 0
func _initialize() -> void:
	house = House.new()
	root.add_child(house)
func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var t0 := Time.get_ticks_msec()
	var r := WorldDots.build(house, func(b): return b.is_in_group("interactive"))
	var edges := 0
	var buf: PackedFloat32Array = r.buffer
	for i in r.count:
		if fmod(buf[i * 16 + 15], 1.0) > 0.25:
			edges += 1
	var up := 0
	for i in r.count:
		if buf[i * 16 + 7] > 2.6:
			up += 1
	print("dots: %d (edges %d, upstairs %d)  built in %d ms" % [r.count, edges, up, Time.get_ticks_msec() - t0])
	return true
