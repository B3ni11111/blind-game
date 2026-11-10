extends Node3D
## Wires the prototype together: house, player, scanner, people, senses (sound + smell
## sight), live layer, sound. The game's rules are written down in rules.md.
##
## Controls: WASD walk, mouse look around, Space / left click scan, E door / grab / drop /
## use, Tab switch between blind and sighted, Esc release mouse.

const House := preload("res://scripts/house.gd")
const Player := preload("res://scripts/player.gd")
const Scanner := preload("res://scripts/scanner.gd")
const Npc := preload("res://scripts/npc.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const Stalker := preload("res://scripts/stalker.gd")
const Fear := preload("res://scripts/fear.gd")
const LiveLayer := preload("res://scripts/live_layer.gd")
const SoundSight := preload("res://scripts/sound_sight.gd")

const GRAB_RANGE := 2.0

var house: House
var player: Player
var scanner: Scanner
var npc: Npc            # the bad person
var people: Array[Npc] = []
var live: LiveLayer
var sound_sight: SoundSight
var world_env: WorldEnvironment
var env_sighted: Environment
var env_blind: Environment
var hint: Label
var mode_label: Label
var sighted := false
var held: StaticBody3D = null

## Which level to play: "tutorial" or "level1" (set by the menu before it loads this scene).
static var level := "level1"
var tutorial: Tutorial = null
var stalker: Stalker = null      # the bad person's mind (Level 1)
var front_door: StaticBody3D     # the way out: locked until you bring the key
var say_label: Label
var fear: Fear                   # breathing, heartbeat, how afraid you are
var _vignette: ShaderMaterial
var _ending := ""                # "caught" or "escaped": the level is over
var _end_t := 0.0
var _fade: ColorRect
var _stalker_test := false
var _last_yaw := 0.0
var _looked := 0.0

var _autotest := ""
var _t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	if level == "tutorial":
		tutorial = Tutorial.new()
		add_child(tutorial)
		_last_yaw = player.rotation.y

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			_autotest = a.substr("--autotest=".length())
		if a.begins_with("--model="):
			_autotest = a.substr("--model=".length())
			AUTOTEST_STEPS = _model_steps()
		if a == "--perf":
			# scans only, no screenshots: watch the fps lines
			_autotest = "."
			AUTOTEST_STEPS = [[1.0, "scan"], [3.0, "scan"], [5.0, "scan"], [7.0, "quit"]]
		if a.begins_with("--features="):
			_autotest = a.substr("--features=".length())
			AUTOTEST_STEPS = _feature_steps()
		if a.begins_with("--stalker="):
			_autotest = a.substr("--stalker=".length())
			AUTOTEST_STEPS = _stalker_steps()
			_stalker_test = true
		if a == "--catch": # with --stalker=<folder>: stand still after a click and get caught
			AUTOTEST_STEPS = [[0.4, "nav_up"], [0.5, "place", Vector3(7.0, 0.05, 0.0), Vector3(12.0, 0.05, 0.0)], [1.1, "lure"],
				[10.0, "report"], [18.0, "report"], [21.0, "report"], [21.05, "shot", "s03_fear_a"], [22.5, "report"], [22.55, "shot", "s03_fear_b"], [45.0, "quit"]]
		if a == "--patrol": # with --stalker=<folder>: nobody makes a sound; where does his round take him?
			AUTOTEST_STEPS = []
			for k in 13:
				AUTOTEST_STEPS.append([1.0 + k * 9.0, "report"])
			AUTOTEST_STEPS.append([112.0, "quit"])
		if a == "--hide": # with --stalker=<folder>: a closet, under a bed, then he hears you in there
			AUTOTEST_STEPS = [[0.5, "place", Vector3(3.45, 0.05, -1.5), Vector3(3.45, 0.05, -2.65)], [0.7, "e"], [1.5, "shot", "h01_closet"],
				[1.6, "click"], [2.2, "shot", "h02_closet_click"], [2.3, "report"], [2.4, "e"],
				[3.2, "place", Vector3(8.8, 0.05, 2.7), Vector3(8.8, 0.05, 4.0)], [3.25, "pitch", -35.0], [3.4, "e"], [4.2, "shot", "h03_under_bed"],
				[4.3, "click"], [4.9, "shot", "h04_under_bed_click"], [5.0, "report"], [5.1, "lure"], [15.0, "report"], [25.0, "report"], [60.0, "quit"]]
		if a.begins_with("--tour="):
			_autotest = a.substr("--tour=".length())
			AUTOTEST_STEPS = _tour_steps()
	if _autotest == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioServer.set_bus_volume_db(0, 0.0)
	_setup_goal()
	# The bad person hunts by ear (not in the tutorial, and not in the look-and-feel test runs).
	if npc and (_autotest == "" or _stalker_test):
		stalker = Stalker.new()
		stalker.npc = npc
		stalker.player = player
		stalker.house = house
		stalker.patrol = BAD_ROUND
		stalker.first_wait = BAD_FIRST_WAIT
		add_child(stalker)
		stalker.bake()
		stalker.caught.connect(_caught)
	fear = Fear.new()
	fear.npc = npc if (_autotest == "" or _stalker_test) else null
	fear.player = player
	fear.house = house
	fear.stalker = stalker
	add_child(fear)


# --- The goal: the key and the front door -----------------------------------

## Places the key could have been left (each is checked: it must rest on something).
const KEY_SPOTS := [Vector3(6.9, 0.8, -0.42), Vector3(8.7, 0.76, -3.0), Vector3(4.75, 0.9, -2.0),
	Vector3(12.1, 0.865, -4.05), Vector3(12.3, 0.77, 1.4), Vector3(16.85, 0.95, -2.0)]

func _setup_goal() -> void:
	var keys := house.find_child("Keys", true, false) as Node3D
	if keys == null:
		return
	keys.set_meta("key", true)
	var space := get_world_3d().direct_space_state
	var spots: Array[Vector3] = []
	for s in KEY_SPOTS:
		var q := PhysicsRayQueryParameters3D.create(s + Vector3(0, 0.12, 0), s - Vector3(0, 0.12, 0), 1)
		q.exclude = [(keys as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and not (hit.collider as Node).is_in_group("grabbable"):
			spots.append(hit.position)
	if _autotest != "":
		print("key spots that hold a key: %d of %d" % [spots.size(), KEY_SPOTS.size()])
	elif level != "tutorial" and not spots.is_empty(): # (tests and the tutorial: it stays on the hallway table)
		keys.global_position = spots.pick_random() + Vector3(0, 0.005, 0)


## E on the front door: with the key in your hand you are out; without it, it rattles (loudly).
func _try_exit() -> void:
	live.touch(front_door, 1.2)
	if held and held.has_meta("key"):
		_escape()
		return
	var dp := door_players[0]
	dp.stream = load("res://audio/door_locked.wav")
	dp.global_position = front_door.global_position
	dp.pitch_scale = 1.0
	dp.play()
	sound_sight.flash([front_door], 0.8)
	_say("Locked. The key is somewhere in the house.", 3.5)
	_noise(front_door.global_position, 9.0)


# --- Hiding ------------------------------------------------------------------
# E on a wardrobe gets you inside it, E on a bed gets you under it; E again and you are
# out, where you were. Hidden, you can look (through the crack) and click, not move.

var _hide: Node3D = null          # the wardrobe or bed frame you are hiding in / under
var _hide_back := Vector3.ZERO    # where you stood before
var _hide_mask: ShaderMaterial
var _hide_busy := false

## Wardrobes and bed frames become hiding places (and show in detail in an echo).
func _setup_hiding() -> void:
	var frames: Array[Node3D] = []
	for n in house.find_children("*", "StaticBody3D", true, false):
		var nm := String(n.name)
		if nm.contains("Wardrobe"):
			n.set_meta("hide", "closet")
			n.add_to_group("interactive")
		elif nm.begins_with("BedFrame"):
			n.set_meta("hide", "bed")
			n.add_to_group("interactive")
			frames.append(n)
	# pointing at the mattress, the duvet or a pillow means the bed
	for n in house.find_children("*", "StaticBody3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Mattress") or nm.begins_with("Duvet") or nm.begins_with("Pillow") or nm.begins_with("Headboard"):
			for f in frames:
				if f.global_position.distance_to((n as Node3D).global_position) < 1.6:
					n.set_meta("hide_ref", f)


func _enter_hide(spot: Node3D) -> void:
	if _hide_busy or _ending != "":
		return
	var bed: bool = spot.get_meta("hide") == "bed"
	_hide = spot
	_hide_busy = true
	_hide_back = player.global_position
	scanner.start_fade()
	player.hidden = true
	player.collision_mask = 0
	var c := spot.global_position
	var to := Vector3(c.x, c.y - (0.35 if bed else 1.0) + 0.02, c.z)
	var out := _hide_back - to
	player.rotation.y = atan2(-out.x, -out.z) # face the way you came: the way out
	player.camera.rotation.x = 0.0
	_hide_mask.set_shader_parameter("mode", 1 if bed else 0)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tw.tween_property(player, "global_position", to, 0.5)
	tw.tween_property(player, "eye_height", 0.17 if bed else 1.5, 0.5)
	tw.tween_method(func(v: float): _hide_mask.set_shader_parameter("amount", v), 0.0, 1.0, 0.5)
	tw.chain().tween_callback(func(): _hide_busy = false)
	_hide_sound(bed)
	if stalker:
		stalker.player_hidden = true
	_noise(c, 2.0 if bed else 4.0) # if he hears you get in, hiding will not save you
	_say("Hidden. Press E to get out.", 2.5)
	_tut("hide")
	if _autotest != "":
		print("hidden in ", spot.name)


func _leave_hide() -> void:
	if _hide_busy or _ending != "":
		return
	var bed: bool = _hide.get_meta("hide") == "bed"
	_hide_busy = true
	_hide_sound(bed)
	_noise(_hide.global_position, 2.0 if bed else 4.0)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tw.tween_property(player, "global_position", _hide_back, 0.5)
	tw.tween_property(player, "eye_height", Player.EYE_HEIGHT, 0.5)
	tw.tween_method(func(v: float): _hide_mask.set_shader_parameter("amount", v), 1.0, 0.0, 0.5)
	tw.chain().tween_callback(func():
		_hide = null
		_hide_busy = false
		player.hidden = false
		player.collision_mask = 0b101
		if stalker:
			stalker.player_hidden = false
			stalker.knows_hide = false)


func _hide_sound(bed: bool) -> void:
	if bed: # cloth and a knee on the floor
		own_step.volume_db = -14.0
		own_step.pitch_scale = 0.7
		own_step.play()
	else: # the wardrobe door
		var dp := door_players[1]
		dp.stream = load("res://audio/door_close.wav")
		dp.global_position = _hide.global_position
		dp.pitch_scale = 1.25
		dp.play()


## A sound you made, for the bad person's ears: `radius` = how far it carries in open air.
func _noise(pos: Vector3, radius: float) -> void:
	if stalker and stalker.hear(pos, radius) and _hide:
		stalker.knows_hide = true # it came from your hiding place


func _say(text: String, seconds := 3.0) -> void:
	say_label.text = text
	say_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(say_label, "modulate:a", 0.0, 0.8)
	if _autotest != "":
		print("say: ", text)


## He has you. Touch is visual: for a moment you see all of him, right in your face.
func _caught() -> void:
	if _ending != "":
		return
	_ending = "caught"
	fear.forced = 1.0
	player.frozen = true
	live.touch(npc, 4.0)
	var sc := AudioStreamPlayer.new()
	sc.stream = load("res://audio/scare.wav")
	sc.volume_db = 2.0
	add_child(sc)
	sc.play()
	if _autotest != "":
		print("caught at t=%.1f" % _t)
		get_tree().create_timer(0.45).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(_autotest.path_join("s02_caught.png")))


func _escape() -> void:
	if _ending != "":
		return
	_ending = "escaped"
	player.frozen = true
	if stalker:
		stalker.enabled = false
	_on_door(front_door, true)
	if _autotest != "":
		print("escaped")


## The last seconds of a level: the grab (shake, his face), then black, then restart or menu.
func _update_ending(delta: float) -> void:
	_end_t += delta
	var cam := player.camera
	if _ending == "caught":
		var to := npc.global_position - player.global_position
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 14.0))
		cam.rotation.x = lerp_angle(cam.rotation.x, 0.06, minf(1.0, delta * 14.0))
		var shake := 0.03 * exp(-_end_t * 2.2)
		cam.h_offset = randf_range(-shake, shake)
		cam.v_offset = randf_range(-shake, shake)
	var black_from := 1.3 if _ending == "caught" else 0.4
	var k := clampf((_end_t - black_from) / 0.5, 0.0, 1.0)
	_fade.color.a = k
	AudioServer.set_bus_volume_db(0, lerpf(0.0, -60.0, k))
	if _end_t > black_from + 0.6 and _end_t - delta <= black_from + 0.6:
		_say("He found you." if _ending == "caught" else "You are out.", 2.0)
	if _end_t > black_from + 3.0:
		AudioServer.set_bus_volume_db(0, 0.0)
		if _autotest != "":
			get_tree().quit()
		elif _ending == "caught":
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _build_world() -> void:
	# Sighted: real lighting. Blind: pure black, only echo dots and sound blobs, with a soft glow.
	world_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.78)
	e.ambient_light_energy = 0.7
	env_sighted = e
	env_blind = Environment.new()
	env_blind.background_mode = Environment.BG_COLOR
	env_blind.background_color = Color.BLACK
	env_blind.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env_blind.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_blind.glow_enabled = true
	env_blind.glow_intensity = 0.5
	env_blind.glow_bloom = 0.05
	world_env.environment = env_blind
	add_child(world_env)

	# The sighted view is a debug view only: one flat light, no shadows, no lamps.
	var sun := DirectionalLight3D.new()
	sun.name = "DebugSun"
	sun.shadow_enabled = false
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-62, 35, 0)
	add_child(sun)

	house = House.new()
	house.name = "House"
	add_child(house)
	front_door = house.find_child("FrontDoor", true, false)
	front_door.add_to_group("interactive") # shows in detail in an echo, and as an outline under your hand
	front_door.set_meta("exit", true)
	_setup_hiding()

	player = Player.new()
	player.name = "Player"
	player.position = Vector3(-3.0, 0.05, -2.3)
	add_child(player)
	player.look_at(Vector3(4.0, 0.05, 0.6), Vector3.UP)

	if level != "tutorial": # the tutorial: you are alone in the house
		_build_people()

	sound_sight = SoundSight.new()
	sound_sight.name = "SoundSight"
	add_child(sound_sight)
	sound_sight.listener = player.camera
	sound_sight.listener_body = player
	sound_sight.house = house

	_build_audio()


# --- People -----------------------------------------------------------------
# Same body script, different people: you tell them apart by build and by their steps.

## Real play (and the --stalker tests): Level 1 is simple. Only the bad person is in the
## house, and he starts far from you: upstairs, at the far end of the corridor. You hear him
## above you first. His round brings him down the stairs, through the back of the house to
## the kitchen and the hallway, and up again; he never comes into the living room (where
## you start, by the front door) unless he hears something.
const BAD_START := Vector3(5.5, House.FLOOR2, 0.0)
const BAD_ROUND := [
	[Vector3(16.4, House.FLOOR2, 0.2), 3.0],   # the landing, top of the stairs
	[Vector3(15.5, 0.0, 3.6), 4.0],            # the foot of the stairs
	[Vector3(11.0, 0.0, -1.0), 7.0],           # the kitchen
	[Vector3(7.0, 0.0, 0.0), 6.0],             # the hallway, outside the bedroom
	[Vector3(15.5, 0.0, 3.6), 1.0],            # back to the stairs
	[Vector3(5.5, House.FLOOR2, 0.0), 12.0],   # upstairs, the far end of the corridor
]
const BAD_FIRST_WAIT := 18.0

func _solo() -> bool:
	for a in OS.get_cmdline_user_args():
		for t in ["--autotest=", "--model=", "--features=", "--tour=", "--perf"]:
			if a.begins_with(t):
				return false
	return true


func _build_people() -> void:
	if _solo():
		npc = _person("BadPerson", {
			"who": "bad person", "peg_leg": true, "limp": 0.27, "step_interval": 0.74,
			"foot_sound": "res://audio/step_bad.wav", "foot_db": -1.0, "peg_db": 1.0,
			"position": BAD_START, "waypoints": []})
		return
	npc = _person("BadPerson", {
		"who": "bad person", "peg_leg": true, "limp": 0.27, "step_interval": 0.74,
		"foot_sound": "res://audio/step_bad.wav", "foot_db": -1.0, "peg_db": 1.0, # heavy, slow, uneven
		
		"waypoints": [Vector3(12.6, 0, -1.2), Vector3(10.8, 0, -0.1), Vector3(7.0, 0, 0.1),
			Vector3(4.6, 0, 0.0), Vector3(2.8, 0, 0.8), Vector3(0.6, 0, 0.3)]})
	# A stranger upstairs: heavier, slower, ordinary shoes. White steps.
	_person("Stranger", {
		"who": "stranger", "girth": 1.3, "height": 0.97, "speed": 0.85, "step_interval": 0.68,
		"foot_db": -2.0, "pause_at_ends": 5.0,
		"waypoints": [Vector3(5.0, House.FLOOR2, 0.05), Vector3(9.0, House.FLOOR2, -0.05),
			Vector3(14.6, House.FLOOR2, 0.0), Vector3(16.6, House.FLOOR2, 0.2)]})
	# The friend: slim, tall, quick, squeaky sneakers. Light green steps. Comes down the
	# stairs, through the back hall and kitchen to the living room, and back up.
	_person("Friend", {
		"who": "friend", "girth": 0.92, "height": 1.03, "speed": 1.35, "step_interval": 0.45,
		"foot_sound": "res://audio/step_friend.wav", "foot_db": -7.0,
		"step_color": Color(0.55, 1.0, 0.55), "pause_at_ends": 3.0,
		"waypoints": [Vector3(16.7, House.FLOOR2, 0.3), Vector3(16.7, House.FLOOR2, 0.75),
			Vector3(16.7, 0.0, 4.4), Vector3(16.3, 0.0, 4.75), Vector3(14.6, 0.0, 3.8),
			Vector3(12.0, 0.0, 3.8), Vector3(10.8, 0.0, 3.3), Vector3(10.8, 0.0, 2.2),
			Vector3(10.6, 0.0, 0.0), Vector3(7.0, 0.0, -0.1), Vector3(4.6, 0.0, -0.2),
			Vector3(2.5, 0.0, -0.4)]})


func _person(node_name: String, cfg: Dictionary) -> Npc:
	var p := Npc.new()
	p.name = node_name
	var wp: Array[Vector3] = []
	wp.assign(cfg["waypoints"])
	cfg["waypoints"] = wp
	p.setup(cfg)
	p.add_to_group("people") # the scanner freezes them at the click and outlines them
	add_child(p)
	people.append(p)
	return p


## Your own footstep: heard, and seen as a faint ripple at your feet (running: louder, wider).
func _on_own_step(pos: Vector3, running: bool) -> void:
	own_step.volume_db = -9.0 if running else -19.0
	own_step.pitch_scale = randf_range(0.95, 1.1) * (1.0 if running else 1.12)
	own_step.play()
	live.add_ripple(pos, false, Color.WHITE, 1.0 if running else 0.75)
	_noise(pos, 9.0 if running else 2.5)
	scanner.add_touch(pos, 0.75 if running else 0.6, 1.3) # you feel the floor where you step


## You walked into something: you feel it (the patch you hit shows; a thing you can use shows whole).
func _on_bump(pos: Vector3, into: Node) -> void:
	scanner.add_touch(pos, 0.85, 1.8)
	if into and into.is_in_group("interactive"):
		live.touch(into, 1.0)
	own_step.volume_db = -15.0
	own_step.pitch_scale = 0.75
	own_step.play()
	_noise(pos, 3.0)


## The reaching hand: within arm's reach of a wall or furniture (where you face), your hand
## is on it and the patch under it shows. Things you can use show whole, as an outline.
const REACH := 0.75

func _update_reach(delta: float) -> void:
	if _hide: # your hands are still
		_touch = move_toward(_touch, 0.0, delta * 2.5)
		scanner.set_touch(_touch_pos, _touch)
		return
	var cam := player.camera
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH, 1)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var on := false
	if not hit.is_empty():
		var body := hit.collider as Node
		if body and body.is_in_group("interactive"):
			live.touch(body, 0.25)
		else:
			on = true
			_touch_pos = hit.position
	_touch = move_toward(_touch, 1.0 if on else 0.0, delta * (4.0 if on else 2.5))
	scanner.set_touch(_touch_pos, _touch)


## A footstep: heard (quieter and duller from a sealed room), felt as a floor ripple, and
## the leg that made it shows for a moment as a blurry shape in the person's colour.
func _on_step(pos: Vector3, right: bool, who: Npc) -> void:
	var sp := who.step_player(right)
	var base: float = sp.get_meta("base_db")
	var occ := sound_sight.step_occlusion(pos)
	sp.volume_db = base + linear_to_db(maxf(occ, 0.001))
	# open air: clear. Through the floor: dull, but a knock still carries. Through a wall: muffled.
	sp.attenuation_filter_cutoff_hz = 20500.0 if occ >= 0.99 else (1800.0 if occ > 0.15 else 600.0)
	var loud := sound_sight.loudness_at(base, sp.unit_size, pos) * occ
	var tint := who.step_tint(right)
	sound_sight.flash(who.step_parts(right), SoundSight.visibility(loud), tint)
	live.add_ripple(pos, right and who.peg_leg, tint, maxf(occ, 0.3))
	if who == npc:
		# his weight comes through the floor: the dots jump with each of his steps, more the closer he is
		var near := clampf(1.0 - pos.distance_to(player.global_position) / 8.0, 0.0, 1.0)
		_shock = maxf(_shock, near * maxf(occ, 0.35) * (1.0 if right else 0.75))


# --- Sound ----------------------------------------------------------------
# Everything that makes a sound is positional, so it helps orientation. Rooms sealed off
# by closed doors let almost nothing through (sound_sight.gd handles that every frame).

var click_player: AudioStreamPlayer
var own_step: AudioStreamPlayer
var _shock := 0.0               # the jolt of the bad person's last step (0..1), dies away quickly
var _touch := 0.0               # how firmly the reaching hand is on a surface (0..1)
var _touch_pos := Vector3.ZERO
var tv_player: AudioStreamPlayer3D
var door_players: Array[AudioStreamPlayer3D] = []

func _build_audio() -> void:
	# your own footsteps: heard in your head (not placed in the room), soft when you walk
	own_step = AudioStreamPlayer.new()
	own_step.stream = load("res://audio/step_foot.wav")
	add_child(own_step)
	player.stepped.connect(_on_own_step)
	player.bumped.connect(_on_bump)

	click_player = AudioStreamPlayer.new()
	click_player.stream = load("res://audio/tongue_click.wav")
	click_player.volume_db = -3.0
	add_child(click_player)

	# Each source has its own loudness (dB) and carry (unit size). The TV is by far the
	# loudest thing in the house, the washer next, the clock barely a whisper.
	tv_player = _ambient("res://audio/tv_ad.wav", House.TV_POS, -2.0, 3.5, false)
	tv_player.finished.connect(func(): get_tree().create_timer(randf_range(2.5, 6.0)).timeout.connect(_tv_replay))
	var fridge := _ambient("res://audio/fridge_loop.wav", House.FRIDGE_POS, -16.0, 1.2, true)
	var clock := _ambient("res://audio/clock_loop.wav", House.CLOCK_POS, -20.0, 1.0, true)
	var fan := _ambient("res://audio/fan_loop.wav", House.FAN_POS, -14.0, 1.5, true)
	var drip := _ambient("res://audio/drip_loop.wav", House.DRIP_POS, -11.0, 1.0, true)
	var washer := _ambient("res://audio/washer_loop.wav", House.WASHER_POS, -7.0, 2.5, true)
	for i in 3:
		var dp := AudioStreamPlayer3D.new()
		dp.volume_db = -4.0
		dp.unit_size = 2.0
		dp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		dp.max_distance = 14.0
		add_child(dp)
		door_players.append(dp)
	house.door_toggled.connect(_on_door)

	# Everything you hear, you also see (faintly): the parts that make each sound.
	sound_sight.add_source(_parts(["TV", "TVScreen"]), tv_player, 1.0)
	sound_sight.add_source(_parts(["Fridge"]), fridge, 1.0)
	sound_sight.add_source(_parts(["WallClock"]), clock, 1.0)
	sound_sight.add_source(_parts(["FanHead", "FanPole"]), fan, 1.0)
	sound_sight.add_source(_parts(["BathTap", "BathSpout", "BathTapPipe"]), drip, 1.0)
	sound_sight.add_source(_parts(["Washer", "WasherDoor"]), washer, 1.0)
	for p in people:
		p.stepped.connect(_on_step.bind(p))

	# The alarm clock: E winds it, it ticks for a few seconds, then rings very loudly.
	alarm_body = house.find_child("AlarmClock", true, false)
	alarm_tick = _ambient("res://audio/alarm_tick.wav", alarm_body.global_position, -14.0, 1.2, true)
	alarm_tick.autoplay = false
	alarm_tick.stop()
	alarm_ring = _ambient("res://audio/alarm_ring.wav", alarm_body.global_position, 6.0, 6.0, false)
	alarm_ring.autoplay = false
	alarm_ring.stop()
	sound_sight.add_source([alarm_body], alarm_tick, 1.0)
	sound_sight.add_source([alarm_body], alarm_ring, 1.0)

	# Smell: food shows in its own colour, up close.
	for n in get_tree().get_nodes_in_group("smell"):
		sound_sight.add_smell([n], n.get_meta("smell_color"))


var tv_on := true


## E on the TV (or its stand): turn it off, or on again. Off, it makes no sound, so it
## also stops being seen as a sound.
func _toggle_tv() -> void:
	tv_on = not tv_on
	if tv_on:
		tv_player.play()
	else:
		tv_player.stop()
	house.tv_screen_mat.emission_enabled = tv_on
	house.tv_screen_mat.albedo_color = Color(0.05, 0.08, 0.12) if tv_on else Color(0.02, 0.02, 0.025)


func _tv_replay() -> void:
	if tv_on:
		tv_player.play()


var alarm_body: Node3D
var alarm_tick: AudioStreamPlayer3D
var alarm_ring: AudioStreamPlayer3D
var _alarm_left := -1.0
const ALARM_DELAY := 6.0


func _arm_alarm() -> void:
	if _alarm_left > 0.0 or alarm_ring.playing:
		return
	_alarm_left = ALARM_DELAY
	alarm_tick.play()


func _update_alarm(delta: float) -> void:
	if _alarm_left <= 0.0:
		return
	_alarm_left -= delta
	if _alarm_left <= 0.0:
		alarm_tick.stop()
		alarm_ring.play()
		_noise(alarm_body.global_position, 16.0) # a lure: he comes to see what is ringing


## Doors thump (one sound for opening and closing), and the door shows for a moment as you hear it.
func _on_door(panel: StaticBody3D, _open: bool) -> void:
	var dp := door_players[0]
	for d in door_players:
		if not d.playing:
			dp = d
			break
	dp.stream = load("res://audio/door_close.wav")
	dp.global_position = panel.global_position
	dp.pitch_scale = randf_range(0.92, 1.06)
	dp.play()
	var loud := sound_sight.loudness_at(dp.volume_db, dp.unit_size, panel.global_position)
	# the thump comes 0.3 s into the sound
	get_tree().create_timer(0.3).timeout.connect(func(): sound_sight.flash([panel], SoundSight.visibility(loud)))


func _parts(names: Array) -> Array:
	var out := []
	for n in names:
		var node := house.find_child(n, true, false)
		if node:
			out.append(node)
		else:
			push_warning("sound source part not found: " + n)
	return out


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
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	p.max_distance = 14.0 # noisy things are only heard when you are close
	p.autoplay = true
	add_child(p)
	return p


func _do_scan() -> void:
	if _ending != "":
		return
	if scanner.scan():
		_tut("scan")
		_noise(player.global_position, 5.0 if _hide else 8.0) # muffled from inside a hiding place
		click_player.pitch_scale = randf_range(0.92, 1.08)
		click_player.play()


# --- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	live = LiveLayer.new()
	live.set_anchors_preset(Control.PRESET_FULL_RECT)
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.camera = player.camera
	layer.add_child(live)

	# Controls, always on screen at the bottom
	hint = Label.new()
	hint.text = "SPACE / CLICK  echo     WASD  walk     SHIFT  run     MOUSE  look around     E  door / grab / use     TAB  blind / sighted     ESC  mouse (twice: menu)"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.42))
	hint.add_theme_font_size_override("font_size", 14)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_top = -34
	hint.offset_bottom = -12
	layer.add_child(hint)

	var hm := ColorRect.new()
	hm.set_anchors_preset(Control.PRESET_FULL_RECT)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_mask = ShaderMaterial.new()
	_hide_mask.shader = preload("res://shaders/hide_mask.gdshader")
	hm.material = _hide_mask
	layer.add_child(hm)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = ShaderMaterial.new()
	_vignette.shader = preload("res://shaders/vignette.gdshader")
	vig.material = _vignette
	layer.add_child(vig)

	say_label = Label.new()
	say_label.add_theme_font_size_override("font_size", 22)
	say_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	say_label.add_theme_color_override("font_outline_color", Color.BLACK)
	say_label.add_theme_constant_override("outline_size", 10)
	say_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	say_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	say_label.offset_top = -120
	say_label.offset_bottom = -90
	say_label.modulate.a = 0.0
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	layer.add_child(say_label)

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
	scanner.setup(player.camera, excl, house)
	_build_occluders()


## The blind view draws the house in plain black (depth only, in effect), so echo dots
## behind a wall from where you are now are hidden: once you walk into another room you no
## longer see the room you scanned through the wall. Not for things you can pick up (you
## carry them) or people (an invisible person must not blot out the dots behind them).
const OCCLUDER_LAYER := 13

func _build_occluders() -> void:
	var black := ShaderMaterial.new()
	black.shader = preload("res://shaders/occluder.gdshader")
	for c in house.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var body := mi.get_parent()
		if body.is_in_group("grabbable") or body.get_parent().is_in_group("grabbable"):
			continue
		var occ := MeshInstance3D.new()
		occ.mesh = mi.mesh
		occ.material_override = black
		occ.layers = 1 << (OCCLUDER_LAYER - 1)
		occ.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(occ)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				_do_scan()
			KEY_W, KEY_A, KEY_S, KEY_D:
				scanner.start_fade() # the moment you move, the echo starts to fade
				_tut("move")
			KEY_E:
				_toggle_grab()
			KEY_TAB, KEY_F1:
				_set_sighted(not sighted)
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().change_scene_to_file("res://scenes/menu.tscn") # Esc twice: the menu
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_do_scan()


func _tut(what: String) -> void:
	if tutorial:
		tutorial.done(what)
		if what == "look":
			_looked = 0.0


func _moving_key_held() -> bool:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		if Input.is_physical_key_pressed(k):
			return true
	return false


## Blind: black screen, echo dots, faint sound shapes, felt vibrations.
## Sighted: the house as a seeing person sees it.
const BLIND_LAYERS := (1 << (Scanner.DOT_LAYER - 1)) | (1 << (SoundSight.LAYER - 1)) | (1 << (OCCLUDER_LAYER - 1))

func _set_sighted(on: bool) -> void:
	sighted = on
	live.visible = not on
	player.camera.cull_mask = (0xFFFFF & ~BLIND_LAYERS) if on else BLIND_LAYERS
	world_env.environment = env_sighted if on else env_blind
	mode_label.text = ("◉  SIGHTED" if on else "◌  BLIND") + "      [TAB]"


# --- Interaction ------------------------------------------------------------

## E: open/close a door you're facing, otherwise drop what you hold or pick something up.
func _toggle_grab() -> void:
	if _hide:
		_leave_hide()
		return
	var cam := player.camera
	var from := cam.global_position
	var to := from + -cam.global_transform.basis.z * GRAB_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 1) # world only, not the presence
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var body: Object = null
	if not hit.is_empty():
		body = hit.collider
	if body is Node and body.has_meta("exit"):
		_try_exit()
		return
	if body is Node and body.has_meta("hide_ref"):
		body = body.get_meta("hide_ref")
	if body is Node and body.has_meta("hide"):
		_enter_hide(body)
		return
	if house.is_door(body):
		_noise((body as Node3D).global_position, 7.0)
		house.toggle_door(body)
		live.touch(body, House.DOOR_TIME + 0.5) # you touch it: you see it swing, then it is gone
		_tut("door")
		return
	if body is Node and body.has_meta("alarm"):
		_arm_alarm()
		live.touch(body, 1.6)
		return
	if body is Node and body.has_meta("tv_switch"):
		_toggle_tv()
		for n in ["TV", "TVScreen", "TVStand"]:
			live.touch(house.find_child(n, true, false), 1.4)
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
	held.rotation_degrees = held.get_meta("hold_rot", Vector3.ZERO)
	live.set_held(held)
	_tut("grab")
	if held.has_meta("key"):
		_say("Keys. Now find the front door.", 3.5)


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
	# Scans hold while you stand still; a movement key starts their fade (see _unhandled_input).
	# A scan made while a key is held shows once, then fades.
	if _moving_key_held() or player.autopilot != Vector3.ZERO:
		scanner.start_fade(true)
	_update_reach(delta)
	# fear shows: the dots shake and the edges of the view close in, pulsing with your heart
	_shock = maxf(0.0, _shock - delta * 3.5)
	scanner.set_tremble(maxf(smoothstep(0.35, 1.0, fear.level), _shock * 0.9))
	player.camera.v_offset = -_shock * 0.012 if _ending == "" else player.camera.v_offset
	_vignette.set_shader_parameter("fear", smoothstep(0.3, 1.0, fear.level))
	_vignette.set_shader_parameter("beat", fear.beat)
	if _ending != "":
		_update_ending(delta)
	if tutorial: # looking around: a good half turn of the head
		_looked += absf(angle_difference(_last_yaw, player.rotation.y))
		_last_yaw = player.rotation.y
		if _looked > 2.5:
			_tut("look")
	_update_alarm(delta)
	if _autotest != "":
		if int(_t * 2.0) != int((_t - delta) * 2.0):
			print("t=%.1f fps=%d sighted=%s" % [_t, Engine.get_frames_per_second(), sighted])
		_run_autotest()


# --- Automated screenshot run (used for development) ---------------------
# godot --path . -- --autotest=<folder>
# Each step: [time, action, args...]. "goto" takes a position and a point to look at.
var AUTOTEST_STEPS := [
	[0.6, "scan"], [0.8, "shot", "01a_wave_0.2s"], [1.0, "shot", "01_wave_0.4s"], [1.25, "shot", "01b_wave_0.65s"], [1.6, "shot", "01c_wave_1.0s"], [1.6, "pitch", -35.0], [1.7, "scan"], [1.85, "shot", "01d_rings_floor_0.15s"], [1.95, "shot", "01e_rings_floor_0.25s"], [2.05, "shot", "01f_rings_floor_0.35s"], [2.2, "shot", "01g_rings_floor_0.5s"], [2.35, "pitch", 0.0], [2.4, "shot", "02_scan"],
	[2.5, "turn", 70.0], [2.6, "shot", "03_look_left"], [2.7, "turn", 110.0], [2.8, "shot", "03b_look_behind"], [2.9, "turn", 180.0],
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
	# Scans add up: a second click from the same place keeps the first (no reset, no flash)
	[24.7, "goto", Vector3(-3.0, 0.05, -2.3), Vector3(4.0, 0.05, 0.6)], [24.8, "scan"], [25.6, "scan"], [25.7, "shot", "16_second_scan_0.1s"],
	# Walk out (without fading) into the hall: the scanned living room is behind the wall now
	[26.6, "place", Vector3(7.1, 0.05, 1.2), Vector3(7.1, 0.05, -3.0)], [26.8, "shot", "17_hall_old_scan_hidden"],
	# The reaching hand: no echo, a wall at arm's length shows as a patch under your hand
	[26.9, "goto", Vector3(16.7, 2.75, 0.2), Vector3(18.0, 2.75, 0.2)], [27.7, "shot", "18_hand_on_wall"],
	# Walking into a wall: you feel it where you hit it
	[27.72, "place", Vector3(16.7, 2.75, 0.2), Vector3(18.0, 2.75, 0.2)], [27.74, "walk", Vector3(0, 0, -1)], [28.3, "shot", "18b_bumped_wall"], [28.32, "walk", Vector3.ZERO],
	# Walking: head bob, your own steps as ripples
	[28.4, "goto", Vector3(-3.0, 0.05, -2.3), Vector3(4.0, 0.05, 0.6)], [28.45, "pitch", -62.0], [28.5, "walk", Vector3(0, 0, -1)], [29.6, "shot", "19_walking_own_steps"], [29.65, "walk", Vector3.ZERO],
	[29.8, "quit"],
]
var _step := 0


## Sighted photo tour: every room from its middle in 4 directions, all doors open.
## godot --path . -- --tour=<folder>   (half-size PNGs, for checking object placement)
const TOUR_SPOTS := {
	"living_w": Vector3(-1.8, 0.05, 0.0), "living_e": Vector3(1.8, 0.05, 0.0),
	"hall": Vector3(7.1, 0.05, 0.0), "bath": Vector3(5.7, 0.05, -1.6),
	"study": Vector3(8.4, 0.05, -1.5), "bed": Vector3(7.1, 0.05, 2.6),
	"kitchen": Vector3(12.0, 0.05, 0.0), "laundry": Vector3(12.6, 0.05, -3.6),
	"backhall": Vector3(12.2, 0.05, 3.9), "stairhall": Vector3(15.2, 0.05, 3.2),
	"workshop": Vector3(15.6, 0.05, -2.2),
	"up_corridor": Vector3(9.0, 2.75, 0.0), "up_landing": Vector3(16.0, 2.75, 0.2),
	"guest": Vector3(6.4, 2.75, -2.5), "bath2": Vector3(9.8, 2.75, -2.2),
	"kids": Vector3(13.3, 2.75, -2.6), "storage": Vector3(16.5, 2.75, -2.6),
	"master": Vector3(7.2, 2.75, 2.8), "office": Vector3(12.8, 2.75, 2.6),
}


## New-feature checks: stairs, upstairs, sealed rooms + the alarm, smell, the hammer,
## the three people's steps.  godot --path . -- --features=<folder>
func _feature_steps() -> Array:
	return [
		# Food on the kitchen table: smelled in colour
		[0.5, "goto", Vector3(11.2, 0.05, 1.9), Vector3(11.75, 0.8, 1.0)], [0.55, "pitch", -30.0],
		[1.5, "shot", "f01_food_smell"], [1.55, "sighted", true], [1.7, "shot", "f01s_food"], [1.75, "sighted", false],
		# The hammer in hand
		[1.8, "goto", Vector3(16.3, 0.05, -2.5), Vector3(16.85, 0.95, -2.5)], [1.85, "pitch", -40.0], [1.9, "e"],
		[2.0, "pitch", 0.0], [2.5, "shot", "f02_hammer_held"], [2.55, "sighted", true], [2.7, "shot", "f02s_hammer_held"], [2.75, "sighted", false], [2.8, "e"],
		# The stairs: walk up them for real (physics), then look around upstairs
		[3.0, "goto", Vector3(16.7, 0.1, 4.8), Vector3(16.7, 0.1, 0.0)], [3.1, "walk", Vector3(0, 0, -1)],
		[7.5, "walk", Vector3.ZERO], [7.6, "report_y"], [7.7, "scan"], [9.0, "shot", "f03_upstairs_scan"],
		[9.05, "sighted", true], [9.2, "shot", "f03s_upstairs"], [9.25, "sighted", false],
		# Alarm: wind it in the living room, go to the bedroom and shut the door
		[9.5, "goto", Vector3(-0.8, 0.05, 0.5), Vector3(-1.65, 0.05, 0.5)], [9.55, "pitch", -50.0], [9.6, "e"],
		[9.7, "shot", "f04a_alarm_wound"],
		[9.8, "goto", Vector3(7.05, 0.05, 3.2), Vector3(-1.65, 0.05, 0.5)], [9.85, "close_door", "BedroomDoor"],
		[11.0, "shot", "f04_sealed_ticking"], [16.5, "shot", "f05_sealed_alarm_ringing"],
		[16.55, "goto", Vector3(5.0, 0.05, 0.0), Vector3(-1.65, 0.05, 0.5)], [17.6, "shot", "f06_open_hall_alarm_ringing"],
		[17.7, "open_door", "BedroomDoor"],
		# The three people's steps
		[19.0, "npc_close"], [19.1, "goto", Vector3(-0.7, 0.05, 0.3), Vector3(1.9, 0.05, 0.25)], [20.6, "shot", "f07_bad_person_steps"],
		[20.7, "scan"], [22.0, "shot", "f08_bad_person_scan"],
		[22.1, "people_close"], [23.6, "shot", "f09_friend_stranger_steps"], [23.7, "scan"], [25.0, "shot", "f10_friend_stranger_scan"],
		[25.1, "goto", Vector3(5.2, 0.05, 0.0), Vector3(9.0, 0.05, 0.0)], [25.2, "pitch", 0.0], [25.3, "scan"], [26.7, "shot", "f11_doors_scan"],
		# touch is visual: a door you open is outlined while it swings, then it is gone
		[26.9, "clear_scan"], [27.0, "goto", Vector3(7.05, 0.05, -0.1), Vector3(7.05, 0.05, 1.0)], [27.05, "pitch", 0.0],
		[27.1, "close_door", "BedroomDoor"], [28.3, "e"], [28.7, "shot", "f12_door_touch_swinging"], [30.6, "shot", "f13_door_touch_gone"],
		# the TV: touched (outlined), switched off, silent
		[30.7, "goto", Vector3(2.4, 0.05, 1.8), Vector3(3.9, 0.05, 1.8)], [30.75, "pitch", -20.0], [30.8, "e"],
		[31.1, "shot", "f14_tv_touch"], [32.6, "shot", "f15_tv_off"],
		# interactive things in detail: the workshop bench, the kitchen counter
		[32.7, "goto", Vector3(15.9, 0.05, -2.3), Vector3(16.9, 0.05, -2.2)], [32.75, "pitch", -20.0], [32.8, "scan"], [34.2, "shot", "f16_workshop_scan"],
		[34.3, "goto", Vector3(12.4, 0.05, 0.5), Vector3(13.4, 0.05, 0.05)], [34.35, "pitch", -25.0], [34.4, "scan"], [35.8, "shot", "f17_kitchen_scan"],
		# shadows filled with dim, small dots: someone close in the hallway
		[35.9, "npc_close"], [36.0, "goto", Vector3(-0.7, 0.05, 0.3), Vector3(1.9, 0.05, 0.25)], [36.1, "scan"], [37.6, "shot", "f18_shadow_fill"],
		[37.7, "quit"],
	]

## The bad person standing still in the living room, front / side / back, sighted and scanned.
## godot --path . -- --model=<folder>
func _model_steps() -> Array:
	var steps := [[0.1, "npc_stand", Vector3(0.0, 0, 0.6)]]
	var t := 1.0
	for v in [["front", Vector3(0.0, 0.05, -2.6)], ["side", Vector3(3.0, 0.05, 0.6)], ["back", Vector3(0.0, 0.05, 2.9)]]:
		steps.append([t, "goto", v[1], Vector3(0.0, 0.05, 0.6)])
		steps.append([t + 0.05, "pitch", -4.0])
		steps.append([t + 0.1, "sighted", true])
		steps.append([t + 0.4, "shot", "npc_%s_sighted" % v[0]])
		steps.append([t + 0.45, "sighted", false])
		steps.append([t + 0.5, "scan"])
		steps.append([t + 1.6, "shot", "npc_%s_scan" % v[0]])
		t += 1.7
	steps.append([t, "quit"])
	return steps


## The hunt, the key and the door: watch the printed lines.
## godot --path . -- --stalker=<folder>
func _stalker_steps() -> Array:
	return [
		# a loud noise in the hallway: he is upstairs, hears it and comes down
		[0.5, "place", Vector3(7.0, 0.05, 0.0), Vector3(12.0, 0.05, 0.0)], [1.0, "report"], [1.1, "lure"], [1.3, "report"],
		[1.4, "place", Vector3(-3.0, 0.05, -2.3), Vector3(4.0, 0.05, 0.6)], # slip away, silent
		[8.0, "report"], [16.0, "report"], [24.0, "report"], [30.0, "report"], [40.0, "report"],
		# the locked front door, then the key, then out
		[40.1, "place", Vector3(-2.0, 0.05, 2.3), Vector3(-2.0, 0.05, 3.1)], [40.3, "e"], [40.5, "report"],
		[40.6, "place", Vector3(6.9, 0.05, 0.25), Vector3(6.9, 0.05, -0.42)], [40.65, "pitch", -50.0], [40.8, "e"], [40.9, "report_held"],
		[41.0, "place", Vector3(-2.0, 0.05, 2.3), Vector3(-2.0, 0.05, 3.1)], [41.05, "pitch", 0.0], [41.25, "shot", "s01_front_door_hand"], [41.3, "e"],
		[50.0, "quit"],
	]


func _tour_steps() -> Array:
	var steps := [[0.2, "sighted", true], [0.3, "open_doors"]]
	var t := 1.5
	for spot in TOUR_SPOTS:
		for i in 4:
			var yaw := i * 90.0
			steps.append([t, "pose", TOUR_SPOTS[spot], yaw, -12.0])
			steps.append([t + 0.25, "halfshot", "%s_%d" % [spot, int(yaw)]])
			t += 0.35
	steps.append([t, "quit"])
	return steps


func _run_autotest() -> void:
	while _step < AUTOTEST_STEPS.size() and _t >= AUTOTEST_STEPS[_step][0]:
		_autotest_action(AUTOTEST_STEPS[_step])
		_step += 1


func _autotest_action(s: Array) -> void:
	if people.is_empty() and s[1] in ["npc_close", "people_close", "npc_stand"]:
		return # the tutorial has nobody in it
	match s[1]:
		"shot":
			get_viewport().get_texture().get_image().save_png(_autotest.path_join(s[2] + ".png"))
		"scan":
			scanner.scan()
		"click":
			_do_scan()
		"report":
			if stalker:
				print("t=%.1f stalker state=%d pace=%.2f at %s (%s), %.1f m from you" % [_t, stalker.state, npc.pace,
					npc.global_position.snapped(Vector3(0.1, 0.1, 0.1)), house.room_at(npc.global_position + Vector3(0, 0.3, 0)),
					npc.global_position.distance_to(player.global_position)])
				print("   fear %.2f" % fear.level)
		"nav_up": # can he find a way upstairs?
			if stalker and stalker._go_to(Vector3(9.0, House.FLOOR2, 0.0)):
				var top := 0.0
				for p in npc.nav_path:
					top = maxf(top, p.y)
				print("path upstairs: %d points, highest %.2f, ends %s" % [npc.nav_path.size(), top, npc.nav_path[npc.nav_path.size() - 1]])
				npc.nav_path = PackedVector3Array()
			else:
				print("path upstairs: none")
		"lure": # a noise he cannot miss, from where you are
			_noise(player.global_position, 100.0)
		"report_held":
			print("held: ", held.name if held else "nothing")
		"turn":
			player.rotate_y(deg_to_rad(s[2]))
		"moved":
			scanner.start_fade() # as if a movement key was pressed
		"npc_close":
			npc.position = Vector3(1.9, 0, 0.25)
			npc._i = 5
			npc._dir = 1
			npc._pause = 0.0
			npc.rotation.y = PI * 0.5
			player.global_position = Vector3(-0.7, 0.05, 0.3)
			player.look_at(Vector3(1.9, 0.05, 0.25), Vector3.UP)
		"people_close":
			# the friend and the stranger walking toward you in the hallway
			var fr: Npc = people[2]
			var st: Npc = people[1]
			fr.position = Vector3(8.5, 0, -0.25)
			fr._i = 9
			fr._dir = 1
			fr._pause = 0.0
			st.position = Vector3(9.4, 0, 0.3)
			var wp: Array[Vector3] = [Vector3(9.4, 0, 0.3), Vector3(5.5, 0, 0.3)]
			st.waypoints = wp
			st._i = 1
			st._dir = 1
			st._pause = 0.0
			player.global_position = Vector3(4.6, 0.05, 0.0)
			player.look_at(Vector3(9.0, 0.05, 0.0), Vector3.UP)
		"walk":
			player.autopilot = s[2]
		"report_y":
			print("player y after the stairs: %.2f (room %s)" % [player.global_position.y, house.room_at(player.global_position + Vector3(0, 0.3, 0))])
		"close_door":
			var d: Node = house._doors[s[2]]
			if d.get_meta("open"):
				house.toggle_door(d)
		"open_door":
			var d2: Node = house._doors[s[2]]
			if not d2.get_meta("open"):
				house.toggle_door(d2)
		"goto":
			player.global_position = s[2]
			var look_to: Vector3 = s[3]
			look_to.y = player.global_position.y # turn the body only; the camera does the pitch
			player.look_at(look_to, Vector3.UP)
			player.camera.rotation.x = 0.0
			scanner.clear() # teleporting: old scans are gone
		"halfshot":
			var img := get_viewport().get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2)
			img.save_png(_autotest.path_join(s[2] + ".png"))
		"place": # move without it counting as walking (scans do not fade)
			player.global_position = s[2]
			var to2: Vector3 = s[3]
			to2.y = player.global_position.y
			player.look_at(to2, Vector3.UP)
			player.camera.rotation.x = 0.0
		"pose":
			player.global_position = s[2]
			player.rotation_degrees.y = s[3]
			player.camera.rotation_degrees.x = s[4]
		"npc_stand":
			# bad person, stranger, friend in a row, all standing still, facing the player (-z... +z)
			for k in people.size():
				people[k].position = s[2] + Vector3((k - 1) * 0.9, 0, 0)
				people[k]._pause = 1.0e6
				people[k].rotation.y = 0.0
		"pitch":
			player.camera.rotation_degrees.x = s[2]
		"open_doors":
			for n in house.find_children("*", "StaticBody3D", true, false):
				if house.is_door(n) and not n.get_meta("open"):
					house.toggle_door(n)
		"e":
			_toggle_grab()
		"clear_scan":
			scanner.clear()
		"toggle_tv":
			_toggle_tv()
		"sighted":
			_set_sighted(s[2])
		"quit":
			get_tree().quit()
