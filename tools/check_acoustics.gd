extends SceneTree
## Prints how much of a sound survives between rooms (door states as built: all shut).
## godot --headless --path . --script res://tools/check_acoustics.gd
const House := preload("res://scripts/house.gd")
var house: Node3D
var _f := 0
func _initialize() -> void:
	house = House.new()
	root.add_child(house)
func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
		return false
	var pairs := [["hallway", "living"], ["hallway", "bedroom"], ["living", "bedroom"], ["living", "bathroom"],
		["living", "kitchen"], ["kitchen", "laundry"], ["living", "laundry"], ["living", "master"], ["living", "landing"],
		["hallway", "corridor"], ["corridor", "master"], ["living", "workshop"], ["living", "stairhall"]]
	for p in pairs:
		print("%-9s -> %-9s  %.4f  (%.0f dB)" % [p[0], p[1], house.transmission(p[0], p[1]), linear_to_db(maxf(house.transmission(p[0], p[1]), 0.00001))])
	print("-- bedroom door open --")
	house.toggle_door(house._doors["BedroomDoor"])
	for p in [["living", "bedroom"], ["hallway", "bedroom"]]:
		print("%-9s -> %-9s  %.4f" % [p[0], p[1], house.transmission(p[0], p[1])])
	quit()
	return true
