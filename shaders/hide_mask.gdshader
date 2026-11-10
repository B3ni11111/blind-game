shader_type canvas_item;
// Hiding: you are shut in. In a closet you only have the crack between the doors (a narrow
// upright slit); under a bed, the low gap between the frame and the floor (a wide flat slit).
uniform float amount = 0.0;  // 0 = not hiding .. 1 = hidden
uniform int mode = 0;        // 0 closet, 1 under a bed

void fragment() {
	float dark;
	if (mode == 0) {
		dark = smoothstep(0.045, 0.11, abs(UV.x - 0.5));
	} else {
		dark = smoothstep(0.09, 0.17, abs(UV.y - 0.6));
	}
	COLOR = vec4(0.0, 0.0, 0.0, dark * amount * 0.985);
}
