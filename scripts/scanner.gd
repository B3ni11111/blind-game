extends Node
## The echo scan.
## On scan, the camera pose is frozen. Rays are then cast row by row from that
## frozen pose (top to bottom) over SWEEP_TIME, writing into a small data image:
##   R = distance (0 = nothing heard back)
##   G = echo material (1 solid, 2 hollow, 3 glass)
##   B = how directly the surface faces the listener (0..1)
##   A = time the dot was revealed (game clock, seconds)
## The dot shader turns that image into the frozen, fading afterimage.
## Because rows keep their old timestamps until a new sweep overwrites them,
## a new scan "wipes" over the fading old one.

const ROWS := 120
const SWEEP_TIME := 0.7
const COOLDOWN := 1.5
const MAX_RANGE := 14.0

var camera: Camera3D
var overlay_mat: ShaderMaterial
var exclude: Array[RID] = []

var cols := 213
var clock := 0.0
var _img: Image
var _tex: ImageTexture

var _scanning := false
var _scan_start := 0.0
var _next_row := 0
var _frozen: Transform3D
var _tan_half_v := 1.0
var _aspect := 16.0 / 9.0
var _last_scan := -100.0


func setup(cam: Camera3D, mat: ShaderMaterial, exclude_rids: Array[RID]) -> void:
	camera = cam
	overlay_mat = mat
	exclude = exclude_rids
	var vp := get_viewport().get_visible_rect().size
	_aspect = vp.x / vp.y
	cols = int(round(ROWS * _aspect))
	_img = Image.create(cols, ROWS, false, Image.FORMAT_RGBAF)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	overlay_mat.set_shader_parameter("scan_data", _tex)
	overlay_mat.set_shader_parameter("grid", Vector2(cols, ROWS))
	overlay_mat.set_shader_parameter("max_dist", MAX_RANGE)


func can_scan() -> bool:
	return clock - _last_scan >= COOLDOWN


func scan() -> bool:
	if not can_scan():
		return false
	# Whatever is left of the previous picture gets wiped by the new sweep.
	overlay_mat.set_shader_parameter("old_fade", current_fade())
	_last_scan = clock
	_scanning = true
	_scan_start = clock
	_fade_begin = NEVER
	_next_row = 0
	_frozen = camera.global_transform
	_tan_half_v = tan(deg_to_rad(camera.fov) * 0.5)
	overlay_mat.set_shader_parameter("seed", randf() * 100.0)
	overlay_mat.set_shader_parameter("scan_start", _scan_start)
	overlay_mat.set_shader_parameter("fade_begin", _fade_begin)
	return true


# --- Holding the picture ----------------------------------------------------
# The snapshot stays on screen for as long as the player stands still.
# The first step after a scan starts the fade (not before the sweep is done).

const NEVER := 1.0e9
const FADE_TIME := 2.5
var _fade_begin := NEVER


func notify_moved() -> void:
	if _fade_begin >= NEVER:
		_fade_begin = maxf(clock, _scan_start + SWEEP_TIME)
		overlay_mat.set_shader_parameter("fade_begin", _fade_begin)


func current_fade() -> float:
	if _fade_begin >= NEVER:
		return 1.0
	return 1.0 - smoothstep(_fade_begin, _fade_begin + FADE_TIME, clock)


func _process(delta: float) -> void:
	clock += delta
	overlay_mat.set_shader_parameter("now", clock)
	overlay_mat.set_shader_parameter("fade_time", FADE_TIME)
	var sweep := -1.0
	if _scanning:
		sweep = clamp((clock - _scan_start) / SWEEP_TIME, 0.0, 1.0)
	overlay_mat.set_shader_parameter("sweep_y", sweep)


func _physics_process(_delta: float) -> void:
	if not _scanning:
		return
	var progress := clampf((clock - _scan_start) / SWEEP_TIME, 0.0, 1.0)
	var target_row := int(ceil(progress * ROWS))
	if target_row <= _next_row:
		return

	var space := camera.get_world_3d().direct_space_state
	var origin := _frozen.origin
	var b := _frozen.basis
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = exclude
	query.from = origin

	for y in range(_next_row, target_row):
		var ndc_y := 1.0 - 2.0 * (y + 0.5) / ROWS
		for x in cols:
			var ndc_x := 2.0 * (x + 0.5) / cols - 1.0
			var dir := (-b.z + b.x * (ndc_x * _tan_half_v * _aspect) + b.y * (ndc_y * _tan_half_v)).normalized()
			query.to = origin + dir * MAX_RANGE
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				_img.set_pixel(x, y, Color(0, 0, 0, clock))
				continue
			var dist := origin.distance_to(hit.position)
			var mat_id := 1
			var col: Object = hit.collider
			if col and col.has_meta("echo_material"):
				mat_id = col.get_meta("echo_material")
			var facing := absf((hit.normal as Vector3).dot(-dir))
			_img.set_pixel(x, y, Color(dist, mat_id, facing, clock))
	_next_row = target_row
	_tex.update(_img)
	if _next_row >= ROWS:
		_scanning = false
