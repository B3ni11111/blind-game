shader_type spatial;
// Heard (or smelled), therefore faintly seen. Soft, drifting, low-resolution blobs on the
// surface of a source, visible through walls. Louder = brighter and more of the shape fills in.
// INSTANCE_CUSTOM: x spawn time (-1 = always), y own strength, z random.
// Flashes (footsteps, doors) carry their tint in the instance colour.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float level = 0.0;        // continuous sources: how strong it is right now (0..1)
uniform bool transient = false;   // flashes: each dot fades on its own, tint per instance
uniform bool steam = false;       // puffs that rise from the source, grow and fade
uniform float flash_life = 0.7;
uniform float seed = 0.0;
uniform vec3 tint = vec3(0.85, 0.9, 1.0);
uniform float wobble = 0.06;      // how far blobs drift around the true surface (m)
uniform float blob_min = 0.07;    // blob size: at least this (m)...
uniform float blob_k = 0.022;     // ...or this much per metre of distance
uniform float brightness = 0.11;
uniform float fill_base = 0.15;   // share of blobs shown even when quiet (1 = all)

varying float v_light;
varying vec3 v_tint;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float r = cd.z;
	float lv;
	float ph = 0.0;
	v_tint = tint;
	if (transient) {
		float age = now - cd.x;
		lv = cd.y * exp(-age * 4.5) * step(0.0, age) * step(age, flash_life * 3.0);
		v_tint = COLOR.rgb;
	} else if (steam) {
		ph = fract(now * 0.2 + r * 5.17);       // each puff has its own phase of rising
		wpos.y += ph * 0.34;
		wpos.x += sin(now * 1.3 + r * 40.0 + ph * 6.0) * 0.04 * ph;
		wpos.z += cos(now * 1.1 + r * 31.0 + ph * 5.0) * 0.04 * ph;
		lv = level * cd.y * sin(ph * 3.14159);  // fade in, then out
	} else {
		lv = level * cd.y;
	}
	// Louder: more of the shape fills in. Quiet: only scattered blobs.
	float show = step(r, fill_base + lv * 0.9);
	v_light = lv * show * brightness;

	float t = now * 0.8 + r * 40.0 + seed;
	vec3 wob = vec3(sin(t * 1.3 + r * 7.0), sin(t * 1.7 + r * 13.0), sin(t * 1.1 + r * 3.0)) * wobble;
	vec4 vc = VIEW_MATRIX * vec4(wpos + wob, 1.0);
	float cam_d = max(-vc.z, 0.05);
	float size = max(blob_min, cam_d * blob_k) * (1.0 + ph * 1.5);
	vc.xy += VERTEX.xy * size;
	POSITION = PROJECTION_MATRIX * vc;
	if (v_light < 0.003) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float blob = exp(-d * d * 4.0) * (1.0 - smoothstep(0.8, 1.0, d));
	ALBEDO = v_tint * v_light * blob;
}
