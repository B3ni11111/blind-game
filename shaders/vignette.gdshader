shader_type canvas_item;
// Fear closes in: the edges of the view go dark as the bad person gets close, and the dark
// ring pulses inward with each heartbeat.
uniform float fear = 0.0;  // 0 calm .. 1 terror
uniform float beat = 0.0;  // 1 at a heartbeat, falling off

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, 0.82);
	float r = length(p) * 2.0;
	float edge = mix(1.3, 0.5, fear) - beat * 0.07 * fear;
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(edge, edge + 0.5, r) * min(1.0, fear * 1.8));
}
