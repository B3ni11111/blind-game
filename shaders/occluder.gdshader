shader_type spatial;
// The house in plain black for the blind view: it only hides echo dots that are behind
// something from where you are now. Pushed a little away from the camera along the view
// ray (it covers the same pixels), so the dots on its own surface are never cut, even seen
// at a grazing angle. Dots on the far side of a thin wall are hidden by echo_fixed's
// back-face test instead.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

void vertex() {
	vec4 vc = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vc.xyz);
	vc.xyz += (vc.xyz / max(d, 1e-4)) * (0.06 + 0.04 * d);
	POSITION = PROJECTION_MATRIX * vc;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
