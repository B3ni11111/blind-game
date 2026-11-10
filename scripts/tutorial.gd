extends CanvasLayer
## The tutorial: the house with nobody else in it, and one hint at a time at the top of the
## screen. Each hint moves on when you do what it says (main.gd calls `done(what)`).

const STEPS := [
	["scan", "Click (or press Space) to make a tongue click.\nThe echo shows what is around you, a few steps away."],
	["look", "Look around with the mouse.\nThe echo stays where you made it, all the way around you."],
	["move", "Walk with W A S D.\nThe moment you move, the echo fades: you only know what you just heard."],
	["scan", "Stop and click again. Click as often as you like:\nstanding still, your echoes add up."],
	["door", "Find a door (its frame shows clearly) and press E to open it."],
	["grab", "Small things on tables and shelves show in detail.\nPress E to pick one up, and E again to put it down."],
	["", "That's the tutorial.\nEverything that makes a sound shows as a faint shape. Press Esc twice for the menu."],
]

var _i := 0
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 10) # readable over the dots
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 40
	_label.offset_bottom = 120
	add_child(_label)
	_show()


## You did `what` ("scan", "look", "move", "door", "grab"): on to the next hint if it asked for that.
func done(what: String) -> void:
	if _i < STEPS.size() - 1 and STEPS[_i][0] == what:
		_i += 1
		_show()


func _show() -> void:
	_label.text = STEPS[_i][1]
