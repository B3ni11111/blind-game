extends Node3D
## Wires the prototype together: house, player, scanner, overlay, presence, live layer, sound.
##
## Controls: WASD walk, mouse turn, Space / left click scan, E door / grab / drop,
## Tab switch between blind and sighted, Esc release mouse.

const House := preload("res://scripts/house.gd")
const Player := preload("res://scripts/player.gd")
const Scanner := preload("res://scripts/scanner.gd")
const Npc := preload("res://scripts/npc.gd")
const LiveLayer := preload("res://scripts/live_layer.gd")
const DotShader := preload("res://shaders/echo_dots.gdshader")

const GRAB_RANGE := 2.0

var house: House
var player: Player
var scanner: Scanner
var npc: Npc
var live: LiveLayer
var overlay: ColorRect
var hint: Label
var mode_label: Label
var sighted := false
var held: StaticBody3D = null

var _autotest := ""
var _t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			_autotest = a.substr("--autotest=".length())
	if _autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
	# Lighting only matters in sighted mode; in blind mode the camera renders nothing.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_intensity = 1.6
	e.glow_enabled = true
	e.glow_intensity = 0.4
	env.environment = e
	add_child(env)

	house = House.new()
	house.name = "House"
	add_child(house)

	player = Player.new()
	player.name = "Player"
	player.position = Vector3(-3.0, 0.05, -2.3)
	add_child(player)
	player.look_at(Vector3(4.0, 0.05, 0.6), Vector3.UP)

	npc = Npc.new()
	npc.name = "Presence"
	add_child(npc)

	_build_audio()


# --- Sound ----------------------------------------------------------------
# Heard, never seen. All ambient sources are positional so they help orientation.
# Sources behind a closed door are muffled (quieter, duller) until it opens.

var click_player: AudioStreamPlayer
var tv_player: AudioStreamPlayer3D
var _behind_door := {} # door name -> Array of [player, open_volume_db]

func _build_audio() -> void:
	click_player = AudioStreamPlayer.new()
	click_player.stream = load("res://audio/tongue_click.wav")
	click_player.volume_db = -3.0
	add_child(click_player)

	tv_player = _ambient("res://audio/tv_ad.wav", House.TV_POS, -6.0, 2.5, false)
	tv_player.finished.connect(func(): get_tree().create_timer(randf_range(2.5, 6.0)).timeout.connect(tv_player.play))
	_ambient("res://audio/fridge_loop.wav", House.FRIDGE_POS, -14.0, 1.5, true)
	_ambient("res://audio/clock_loop.wav", House.CLOCK_POS, -16.0, 1.5, true)

	_behind("BedroomDoor", _ambient("res://audio/fan_loop.wav", House.FAN_POS, -8.0, 2.0, true), -8.0)
	_behind("BathroomDoor", _ambient("res://audio/drip_loop.wav", House.DRIP_POS, -6.0, 1.5, true), -6.0)
	_behind("LaundryDoor", _ambient("res://audio/washer_loop.wav", House.WASHER_POS, -9.0, 2.0, true), -9.0)
	house.door_toggled.connect(func(d, open): _muffle(d.name, not open, House.DOOR_TIME))


func _ambient(path: String, pos: Vector3, vol_db: float, unit: float, loop: bool) -> AudioStreamPlayer3D:
	var stream: AudioStreamWAV = load(path)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = vol_db
	p.unit_size = unit
	p.max_distance = 25.0
	p.autoplay = true
	add_child(p)
	return p


func _behind(door_name: String, p: AudioStreamPlayer3D, open_db: float) -> void:
	if not _behind_door.has(door_name):
		_behind_door[door_name] = []
	_behind_door[door_name].append([p, open_db])
	_muffle(door_name, true, 0.0)


func _muffle(door_name: String, muffled: bool, time: float) -> void:
	for entry in _behind_door.get(door_name, []):
		var p: AudioStreamPlayer3D = entry[0]
		var vol: float = entry[1] - 12.0 if muffled else entry[1]
		var cutoff := 700.0 if muffled else 6000.0
		if time <= 0.0:
			p.volume_db = vol
			p.attenuation_filter_cutoff_hz = cutoff
			continue
		var tw := create_tween().set_parallel()
		tw.tween_property(p, "volume_db", vol, time)
		tw.tween_property(p, "attenuation_filter_cutoff_hz", cutoff, time)


func _do_scan() -> void:
	if scanner.scan():
		click_player.pitch_scale = randf_range(0.92, 1.08)
		click_player.play()


# --- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = DotShader
	overlay.material = mat
	layer.add_child(overlay)

	live = LiveLayer.new()
	live.set_anchors_preset(Control.PRESET_FULL_RECT)
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.camera = player.camera
	layer.add_child(live)
	npc.stepped.connect(live.add_ripple)

	hint = Label.new()
	hint.text = "SPACE / CLICK  echo     WASD  walk     MOUSE  turn     E  door / grab     TAB  blind / sighted     ESC  mouse"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	hint.add_theme_font_size_override("font_size", 14)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-hint.get_minimum_size().x / 2, -40)
	layer.add_child(hint)

	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	mode_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mode_label.position = Vector2(-190, 16)
	layer.add_child(mode_label)
	_set_sighted(false)

	scanner = Scanner.new()
	scanner.name = "Scanner"
	add_child(scanner)
	var excl: Array[RID] = [player.get_rid()]
	scanner.setup(player.camera, mat, excl)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				_do_scan()
			KEY_E:
				_toggle_grab()
			KEY_TAB, KEY_F1:
				_set_sighted(not sighted)
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_do_scan()


## Blind: black screen, echo dots, felt vibrations. Sighted: the house as a seeing person sees it.
func _set_sighted(on: bool) -> void:
	sighted = on
	overlay.visible = not on
	live.visible = not on
	player.camera.cull_mask = 0xFFFFF if on else 0
	mode_label.text = ("◉  SIGHTED" if on else "◌  BLIND") + "      [TAB]"


# --- Interaction ------------------------------------------------------------

## E: open/close a door you're facing, otherwise drop what you hold or pick something up.
func _toggle_grab() -> void:
	var cam := player.camera
	var from := cam.global_position
	var to := from + -cam.global_transform.basis.z * GRAB_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 1) # world only, not the presence
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var body: Object = null
	if not hit.is_empty():
		body = hit.collider
	if house.is_door(body):
		house.toggle_door(body)
		return
	if held:
		_drop()
		return
	if body == null or not (body is Node and body.is_in_group("grabbable")):
		# Nothing in front: feel around a bit (closest grabbable within reach of the view ray)
		body = _nearest_grabbable_along(from, -cam.global_transform.basis.z)
	if body == null:
		return
	held = body
	held.collision_layer = 0
	held.reparent(player.hold_point, false)
	held.position = Vector3.ZERO
	held.rotation = Vector3.ZERO
	live.set_held(held)


func _nearest_grabbable_along(from: Vector3, dir: Vector3) -> StaticBody3D:
	var best: StaticBody3D = null
	var best_d := 0.35 # max miss distance from the view ray
	for n in get_tree().get_nodes_in_group("grabbable"):
		if n == held:
			continue
		var p: Vector3 = n.global_position
		var along := (p - from).dot(dir)
		if along < 0.1 or along > GRAB_RANGE:
			continue
		var miss := (p - (from + dir * along)).length()
		if miss < best_d:
			best_d = miss
			best = n
	return best


func _drop() -> void:
	var cam := player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var spot := player.global_position + fwd * 0.6 + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(spot, spot + Vector3.DOWN * 3.0, 1)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground := 0.0
	if not hit.is_empty():
		ground = hit.position.y
	held.reparent(house, false)
	held.global_position = Vector3(spot.x, ground + float(held.get_meta("half_height", 0.05)), spot.z)
	held.rotation = Vector3.ZERO
	held.collision_layer = 1
	held = null
	live.set_held(null)


func _process(delta: float) -> void:
	_t += delta
	# The snapshot holds until the player walks.
	if Vector2(player.velocity.x, player.velocity.z).length() > 0.1:
		scanner.notify_moved()
	if hint.visible and _t > 10.0:
		hint.modulate.a = maxf(0.0, 1.0 - (_t - 10.0) / 2.0)
		hint.visible = hint.modulate.a > 0.0
	if _autotest != "":
		if int(_t * 2.0) != int((_t - delta) * 2.0):
			print("t=%.1f fps=%d sighted=%s" % [_t, Engine.get_frames_per_second(), sighted])
		_run_autotest()


# --- Automated screenshot run (used for development) ---------------------
# godot --path . -- --autotest=<folder>
# Each step: [time, action, args...]. "goto" takes a position and a point to look at.
var AUTOTEST_STEPS := [
	[0.6, "scan"], [0.95, "shot", "01_sweeping"], [2.0, "shot", "02_scan"],
	[2.1, "turn", 70.0], [2.4, "shot", "03_turned_still_frozen"],
	[6.0, "shot", "04_still_held_after_4s"], [6.05, "moved"],
	[7.0, "shot", "05_fading_after_walking"], [9.0, "shot", "06_faded"],
	# The presence walking toward you
	[9.1, "npc_close"], [9.3, "scan"], [10.3, "shot", "07_presence"],
	[10.35, "sighted", true], [10.4, "shot", "07s_presence_sighted"], [10.45, "sighted", false],
	# Bathroom
	[10.5, "goto", Vector3(5.45, 0.05, -0.05), Vector3(5.45, 0.05, -1.0)], [10.6, "e"],
	[11.6, "goto", Vector3(5.75, 0.05, -1.25), Vector3(5.1, 0.05, -3.1)], [11.7, "scan"],
	[12.7, "shot", "08_bathroom"], [12.75, "sighted", true], [12.8, "shot", "08s_bathroom"], [12.85, "sighted", false],
	# Study
	[12.9, "goto", Vector3(8.65, 0.05, -0.05), Vector3(8.65, 0.05, -1.0)], [13.0, "e"],
	[14.0, "goto", Vector3(8.95, 0.05, -1.15), Vector3(7.8, 0.05, -3.2)], [14.1, "scan"],
	[15.1, "shot", "09_study"], [15.15, "sighted", true], [15.2, "shot", "09s_study"], [15.25, "sighted", false],
	# Laundry
	[15.3, "goto", Vector3(12.05, 0.05, -1.7), Vector3(12.05, 0.05, -3.0)], [15.4, "e"],
	[16.4, "goto", Vector3(12.5, 0.05, -2.95), Vector3(13.5, 0.05, -4.4)], [16.5, "scan"],
	[17.5, "shot", "10_laundry"], [17.55, "sighted", true], [17.6, "shot", "10s_laundry"],
	# Sighted tour
	[17.65, "goto", Vector3(10.6, 0.05, -1.2), Vector3(13.5, 0.05, 1.2)], [17.75, "shot", "11s_kitchen"],
	[17.8, "goto", Vector3(-3.0, 0.05, -2.3), Vector3(4.0, 0.05, 0.6)], [17.9, "shot", "12s_living"],
	[17.95, "goto", Vector3(7.6, 0.05, -0.1), Vector3(7.05, 0.05, 0.7)], [18.0, "e"],
	[19.0, "goto", Vector3(7.0, 0.05, 1.3), Vector3(8.5, 0.05, 4.5)], [19.3, "shot", "13s_bedroom"],
	[19.4, "goto", Vector3(-3.0, 0.05, -2.3), Vector3(4.0, 0.05, 0.6)], [22.5, "shot", "14s_living_after_3s"],
	# The bad person walking toward you, seen with eyes, then caught by an echo
	[22.6, "npc_close"], [22.65, "goto", Vector3(-0.9, 0.05, 0.6), Vector3(1.0, 0.05, 0.3)], [23.5, "shot", "15s_bad_person"],
	[23.55, "sighted", false], [23.6, "scan"], [24.6, "shot", "15_bad_person_scan"],
	[24.7, "quit"],
]
var _step := 0


func _run_autotest() -> void:
	while _step < AUTOTEST_STEPS.size() and _t >= AUTOTEST_STEPS[_step][0]:
		_autotest_action(AUTOTEST_STEPS[_step])
		_step += 1


func _autotest_action(s: Array) -> void:
	match s[1]:
		"shot":
			get_viewport().get_texture().get_image().save_png(_autotest.path_join(s[2] + ".png"))
		"scan":
			scanner.scan()
		"turn":
			player.rotate_y(deg_to_rad(s[2]))
		"moved":
			scanner.notify_moved()
		"npc_close":
			npc.position = Vector3(1.9, 0, 0.25)
			npc._i = 5
			npc._dir = 1
			npc._pause = 0.0
			npc.rotation.y = PI * 0.5
			player.global_position = Vector3(-0.7, 0.05, 0.3)
			player.look_at(Vector3(1.9, 0.05, 0.25), Vector3.UP)
		"goto":
			player.global_position = s[2]
			player.look_at(s[3], Vector3.UP)
			player.camera.rotation.x = 0.0
		"e":
			_toggle_grab()
		"sighted":
			_set_sighted(s[2])
		"quit":
			get_tree().quit()
