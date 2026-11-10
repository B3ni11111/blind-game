extends Node
## Your body's fear: a heartbeat, and how afraid you are (`level`, 0..1).
##
## Fear follows how close the bad person is: nothing beyond about 9 m, full when he is a
## step away. A wall, a closed door or a floor between you takes some of it off
## (the same numbers hearing uses), and it is worse while he is coming for a sound. It
## rises quickly and settles slowly.
##
## What you hear: a heartbeat that starts when he is near and speeds up (62 to 150 a
## minute). (There is no breathing sound: the designer dropped it.)
## What you see (main.gd passes `level` and `beat` on): the dots tremble and the edges of
## the view close in, pulsing with the heartbeat.

const FAR := 9.0
const NEAR := 1.2

var npc: Node3D        # the bad person (null in the tutorial: no fear)
var player: Node3D     # player.gd
var house: Node3D
var stalker: Node      # stalker.gd, may be null
var forced := -1.0     # >= 0: fear is held at this (the moment you are caught)

var level := 0.0       # 0 calm .. 1 terror
var beat := 0.0        # 1 at each heartbeat, falling off quickly (for the pulse you see)

var _next_beat := 0.0
var _heart: AudioStreamPlayer


func _ready() -> void:
	_heart = AudioStreamPlayer.new()
	_heart.stream = load("res://audio/heartbeat.wav")
	add_child(_heart)


func _target() -> float:
	if forced >= 0.0:
		return forced
	if npc == null:
		return 0.0
	var a := npc.global_position
	var b := player.global_position
	var d := a.distance_to(b)
	var ra: String = house.room_at(a + Vector3(0, 0.3, 0))
	var rb: String = house.room_at(b + Vector3(0, 0.3, 0))
	var through := 1.0
	if ra != "" and rb != "" and ra != rb:
		through = house.transmission(ra, rb)
	# slow to start, steep at the end: most of the fear is in the last few metres
	var f := pow(clampf((FAR - d) / (FAR - NEAR), 0.0, 1.0), 1.6) * lerpf(0.3, 1.0, sqrt(clampf(through, 0.0, 1.0)))
	if stalker and stalker.state == 1: # coming for a sound
		f = minf(1.0, f * 1.2)
	return f


func _process(delta: float) -> void:
	var t := _target()
	level = move_toward(level, t, delta * (1.1 if t > level else 0.22))
	beat = maxf(0.0, beat - delta * 5.0)
	if level > 0.06:
		_next_beat -= delta
		if _next_beat <= 0.0:
			_next_beat = 60.0 / lerpf(62.0, 150.0, level)
			_heart.volume_db = lerpf(-26.0, -1.0, sqrt(level))
			_heart.pitch_scale = 0.95 + 0.2 * level
			_heart.play()
			beat = 1.0
