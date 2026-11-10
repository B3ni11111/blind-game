extends Control
## The main menu: Play, then pick a level (Tutorial or Level 1). Black screen, white text,
## like the game itself. The test runs (--autotest, --features, ...) skip it and go
## straight into Level 1.

const Main := preload("res://scripts/main.gd")
const GAME := "res://scenes/main.tscn"
const TEST_ARGS := ["--autotest=", "--model=", "--features=", "--tour=", "--perf", "--stalker="]

var _main_box: VBoxContainer
var _levels_box: VBoxContainer


func _ready() -> void:
	# test runs go straight into the game (Level 1, or the tutorial with --level=tutorial)
	var args := OS.get_cmdline_user_args()
	for a in args:
		for t in TEST_ARGS:
			if a.begins_with(t):
				Main.level = "tutorial" if args.has("--level=tutorial") else "level1"
				get_tree().change_scene_to_file.call_deferred(GAME)
				return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	var title := Label.new()
	title.text = "ECHO"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "you can't see. listen."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_spacer(30))

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	col.add_child(_main_box)
	var play := _button("Play", _main_box)
	play.pressed.connect(_show_levels.bind(true))
	_button("Quit", _main_box).pressed.connect(get_tree().quit)

	_levels_box = VBoxContainer.new()
	_levels_box.add_theme_constant_override("separation", 12)
	_levels_box.visible = false
	col.add_child(_levels_box)
	_button("Tutorial", _levels_box).pressed.connect(_play.bind("tutorial"))
	_button("Level 1", _levels_box).pressed.connect(_play.bind("level1"))
	_button("Back", _levels_box).pressed.connect(_show_levels.bind(false))
	play.grab_focus()

	for a in OS.get_cmdline_user_args(): # screenshot of the menu (and of the level list)
		if a.begins_with("--menu-shot="):
			_shots(a.substr("--menu-shot=".length()))


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.flat = true
	for s in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(s, Color(1, 1, 1, 0.7))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.border_color = Color(1, 1, 1, 0.35)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	var hover := frame.duplicate()
	hover.border_color = Color(1, 1, 1, 0.9)
	for s in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, frame)
	for s in ["hover", "focus"]:
		b.add_theme_stylebox_override(s, hover)
	parent.add_child(b)
	return b


func _show_levels(on: bool) -> void:
	_main_box.visible = not on
	_levels_box.visible = on
	(_levels_box.get_child(0) if on else _main_box.get_child(0)).grab_focus()


func _play(which: String) -> void:
	Main.level = which
	get_tree().change_scene_to_file(GAME)


func _shots(folder: String) -> void:
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(folder.path_join("menu_main.png"))
	_show_levels(true)
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(folder.path_join("menu_levels.png"))
	get_tree().quit()
