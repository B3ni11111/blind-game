extends Node3D
## The senses that aren't the echo: hearing and smell, both shown as faint visuals.
##
## Hearing ("if you can hear it, you can see it"): everything that makes a sound shows up
## as a weak, blurry, drifting cloud of dots on its surface. Brightness follows how loud
## it is right now at the listener: volume, distance, the sound's own loudness over time
## (a clock flickers per tick, the TV goes dark between ads), and walls: a sound from a
## sealed room (every door shut between it and you) is almost gone, and is muffled in the
## speakers too. Only very loud sounds still show through. Short sounds (footsteps, doors)
## leave a brief flash of whatever made them, tinted by who made it.
##
## Smell: food shows in its own colour (broccoli green, apple red, fried chicken orange),
## clearer than sound but only up close, and not out of a sealed room.

const BlurShader := preload("res://shaders/sound_blur.gdshader")
const LAYER := 12               # visual layer (rendered only in blind mode)
const ENV_RATE := 40.0          # loudness envelope samples per second
const FLASH_CAPACITY := 4000
const FLOATS := 20              # 12 transform + 4 colour + 4 custom
const FLOOR_BORNE := 0.2        # footsteps carried by the floor itself from another storey
const HEAR_RANGE := 14.0        # beyond this nothing is heard or seen
const SMELL_RANGE := 5.0
const SMELL_SEALED := 0.0

var listener: Camera3D
var listener_body: Node3D      # whose feet decide which room the listener is in
var house: Node                # has room_at(pos) and connected(a, b)

class Source:
	var player: AudioStreamPlayer3D
	var env: PackedFloat32Array
	var mat: ShaderMaterial
	var gain: float
	var base_db: float
	var pos: Vector3
	var occ := 1.0
	var smell := false
	var steam := false

var _sources: Array[Source] = []
var _flash_mm: MultiMesh
var _flash_buf := PackedFloat32Array()
var _flash_next := 0
var _clock := 0.0
var _flash_mat: ShaderMaterial
var _samples_cache := {} # "mesh instance id:kind" -> PackedVector3Array (local)
var _quad: QuadMesh
var _listener_room := ""


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2(2, 2)
	_flash_mm = MultiMesh.new()
	_flash_mm.transform_format = MultiMesh.TRANSFORM_3D
	_flash_mm.use_colors = true
	_flash_mm.use_custom_data = true
	_flash_mm.mesh = _quad
	_flash_mm.instance_count = FLASH_CAPACITY
	_flash_buf.resize(FLASH_CAPACITY * FLOATS)
	_flash_mat = _make_mat()
	_flash_mat.set_shader_parameter("transient", true)
	_add_instance(_flash_mm, _flash_mat)


## A continuous sound source: `bodies` are the parts that make it (their surfaces are
## what you "see"), `player` is the sound. `gain` scales how visible it is.
func add_source(bodies: Array, player: AudioStreamPlayer3D, gain := 1.0) -> void:
	var s := _new_source(bodies, 0)
	if s == null:
		return
	s.player = player
	s.env = _envelope(player.stream)
	s.gain = gain
	s.base_db = player.volume_db
	s.pos = player.global_position


## Food you can smell: shown in its smell colour, fairly clear, only up close.
func add_smell(bodies: Array, color: Color, strength := 1.0) -> void:
	var s := _new_source(bodies, 2)
	if s == null:
		return
	s.smell = true
	s.gain = strength
	s.pos = (bodies[0] as Node3D).global_position
	s.mat.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	s.mat.set_shader_parameter("wobble", 0.004)
	s.mat.set_shader_parameter("blob_min", 0.008)
	s.mat.set_shader_parameter("blob_k", 0.004)
	s.mat.set_shader_parameter("brightness", 0.55)
	s.mat.set_shader_parameter("fill_base", 1.0)
	_add_steam(bodies, color, strength)


func _new_source(bodies: Array, kind: int) -> Source:
	var pts := PackedVector3Array()
	for b in bodies:
		for mi in _meshes(b):
			var xf: Transform3D = mi.global_transform
			for p in _sample(mi, kind):
				pts.append(xf * p)
	if pts.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
		mm.set_instance_custom_data(i, Color(-1.0, 1.0, randf(), 0.0)) # always / strength 1 / random
	var s := Source.new()
	s.mat = _make_mat()
	_add_instance(mm, s.mat)
	_sources.append(s)
	return s


## A short sound: a brief blurry flash of these parts where they are right now,
## tinted (white for most things; the people's steps have their own colours).
func flash(parts: Array, loudness: float, tint := Color.WHITE) -> void:
	if loudness <= 0.01:
		return
	for b in parts:
		for mi in _meshes(b):
			var xf: Transform3D = mi.global_transform
			for p in _sample(mi, 1):
				var o := _flash_next * FLOATS
				var w: Vector3 = xf * p
				_flash_buf[o] = 1.0; _flash_buf[o + 5] = 1.0; _flash_buf[o + 10] = 1.0
				_flash_buf[o + 3] = w.x; _flash_buf[o + 7] = w.y; _flash_buf[o + 11] = w.z
				_flash_buf[o + 12] = tint.r; _flash_buf[o + 13] = tint.g; _flash_buf[o + 14] = tint.b; _flash_buf[o + 15] = 1.0
				_flash_buf[o + 16] = _clock
				_flash_buf[o + 17] = loudness
				_flash_buf[o + 18] = randf()
				_flash_next = (_flash_next + 1) % FLASH_CAPACITY
	_flash_mm.buffer = _flash_buf


## How loud a sound (at its normal volume) is at the listener, before walls (0..~1).
## You only hear things well when you are close: the level falls with the square of the
## distance, and past HEAR_RANGE there is nothing.
func loudness_at(base_db: float, unit_size: float, at: Vector3) -> float:
	if listener == null:
		return 0.0
	var d := listener.global_position.distance_to(at)
	var k := minf(1.0, unit_size / maxf(d, 0.01))
	return db_to_linear(base_db) * k * k * (1.0 - smoothstep(HEAR_RANGE - 4.0, HEAR_RANGE, d))


## The fraction of a sound that reaches the listener from `at`, after the best route
## through the house: 1 in the same room or down a clear opening; every closed door,
## wall and floor on the way cuts it down (house.transmission).
func occlusion(at: Vector3) -> float:
	if house == null:
		return 1.0
	var r: String = house.room_at(at)
	if r == "" or _listener_room == "":
		return 1.0
	return house.transmission(_listener_room, r)


func floors_differ(at: Vector3) -> bool:
	if listener_body == null:
		return false
	return (at.y > 2.5) != (listener_body.global_position.y > 2.5)


## Footsteps also travel through the floor itself: from another storey you still feel and
## hear them, weakly (and dull, but the knock of a wooden leg survives).
func step_occlusion(at: Vector3) -> float:
	var o := occlusion(at)
	if floors_differ(at):
		o = maxf(o, FLOOR_BORNE)
	return o


## Brightness on screen for a loudness. Quiet is quiet: no boost for faint sounds.
static func visibility(loud: float) -> float:
	return clampf(pow(loud, 0.7) * 2.0, 0.0, 1.0)


func _process(delta: float) -> void:
	_clock += delta
	if listener_body and house:
		var r: String = house.room_at(listener_body.global_position + Vector3(0, 0.3, 0))
		if r != "":
			_listener_room = r
	_flash_mat.set_shader_parameter("now", _clock)
	var k := minf(1.0, delta * 6.0)
	for s in _sources:
		s.mat.set_shader_parameter("now", _clock)
		if s.smell:
			var d := listener.global_position.distance_to(s.pos)
			var near := clampf(1.0 - d / SMELL_RANGE, 0.0, 1.0)
			var through := 1.0 if occlusion(s.pos) >= 1.0 else SMELL_SEALED
			var reach := near if s.steam else near * near # steam carries a little further
			s.mat.set_shader_parameter("level", reach * through * s.gain)
			continue
		s.occ = lerpf(s.occ, occlusion(s.pos), k)
		# what you hear: much quieter and duller through a wall or a floor
		s.player.volume_db = s.base_db + linear_to_db(maxf(s.occ, 0.001))
		s.player.attenuation_filter_cutoff_hz = lerpf(450.0, 20500.0, pow(clampf(s.occ, 0.0, 1.0), 0.5))
		var level := 0.0
		if s.player.playing:
			var e := 1.0
			if not s.env.is_empty():
				var idx := int(s.player.get_playback_position() * ENV_RATE)
				e = s.env[clampi(idx, 0, s.env.size() - 1)]
			level = loudness_at(s.base_db, s.player.unit_size, s.pos) * e * s.gain * s.occ
		s.mat.set_shader_parameter("level", visibility(level))


# --- helpers ----------------------------------------------------------------

## Steam rising from food: soft puffs that start on top of the food, drift up and fade,
## in the food's smell colour. Animated entirely in the shader.
func _add_steam(bodies: Array, color: Color, strength: float) -> void:
	var tops := PackedVector3Array()
	var all := PackedVector3Array()
	var top_y := -1.0e9
	for b in bodies:
		for mi in _meshes(b):
			var xf: Transform3D = mi.global_transform
			for p in _sample(mi, 1):
				var w: Vector3 = xf * p
				all.append(w)
				top_y = maxf(top_y, w.y)
	for w in all:
		if w.y > top_y - 0.02:
			tops.append(w)
	if tops.is_empty():
		return
	var count := mini(8, tops.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis(), tops[randi() % tops.size()]))
		mm.set_instance_custom_data(i, Color(-1.0, 1.0, randf(), 0.0))
	var s := Source.new()
	s.mat = _make_mat()
	s.smell = true
	s.steam = true
	s.gain = strength
	s.pos = (bodies[0] as Node3D).global_position
	s.mat.set_shader_parameter("steam", true)
	s.mat.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	s.mat.set_shader_parameter("wobble", 0.0)
	s.mat.set_shader_parameter("blob_min", 0.028)
	s.mat.set_shader_parameter("blob_k", 0.004)
	s.mat.set_shader_parameter("brightness", 0.5)
	s.mat.set_shader_parameter("fill_base", 1.0)
	_add_instance(mm, s.mat)
	_sources.append(s)


func _make_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BlurShader
	m.set_shader_parameter("seed", randf() * 50.0)
	return m


func _add_instance(mm: MultiMesh, mat: ShaderMaterial) -> void:
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.layers = 1 << (LAYER - 1)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.top_level = true
	inst.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	add_child(inst)


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## Surface points in the mesh's local space, cached. kind 0: sound (sparse, ~ one per
## 25 cm2), 1: flash (denser), 2: smell (dense: it should read as the food it is).
func _sample(mi: MeshInstance3D, kind: int) -> PackedVector3Array:
	var key := str(mi.get_instance_id(), ":", kind)
	if _samples_cache.has(key):
		return _samples_cache[key]
	var faces := mi.mesh.get_faces()
	var out := PackedVector3Array()
	if faces.size() >= 3:
		var areas := PackedFloat32Array()
		var total := 0.0
		var sc := mi.global_transform.basis.get_scale()
		for i in range(0, faces.size(), 3):
			total += ((faces[i + 1] - faces[i]) * sc).cross((faces[i + 2] - faces[i]) * sc).length() * 0.5
			areas.append(total)
		var density: float = [400.0, 900.0, 12000.0][kind]
		var count := clampi(int(total * density), 12 if kind < 2 else 60, 700)
		for n in count:
			var tri := mini(areas.bsearch(randf() * total), areas.size() - 1)
			var a := faces[tri * 3]
			var b := faces[tri * 3 + 1]
			var c := faces[tri * 3 + 2]
			var u := randf()
			var v := randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			out.append(a + (b - a) * u + (c - a) * v)
	_samples_cache[key] = out
	return out


## Loudness over time (RMS per 1/ENV_RATE s, normalised to 1) from the WAV file.
func _envelope(stream: AudioStream) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if stream == null or stream.resource_path == "":
		return out
	# Imported WAVs are compressed; read the original 16-bit file instead.
	var wav := AudioStreamWAV.load_from_file(stream.resource_path)
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var data := wav.data
	var ch := 2 if wav.stereo else 1
	var frames := data.size() / (2 * ch)
	var win := maxi(1, int(wav.mix_rate / ENV_RATE))
	var peak := 0.0001
	var f := 0
	while f < frames:
		var acc := 0.0
		var n := mini(win, frames - f)
		for k in n:
			var v := data.decode_s16((f + k) * 2 * ch) / 32768.0
			acc += v * v
		var rms := sqrt(acc / n)
		out.append(rms)
		peak = maxf(peak, rms)
		f += win
	for i in out.size():
		out[i] = out[i] / peak
	return out
