shader_type spatial;
// The detail dots: things you can interact with (a hammer, a mug, a door), people's
// silhouettes, and (dimmed, via `strength`) the dots that fill the shadows. Each lights when
// the echo's wave reaches it (one ring going out from you) and stays lit.
// With `depth_test`, a dot shows only if the wave reached it from where you stood: it must
// be the nearest thing in its direction in the scan's depth cube map (as echo_fixed does).
// INSTANCE_CUSTOM: x reveal time, y echo material (+0.5 = an outline dot of a person),
// z random, w distance from the listener.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float now = 0.0;
uniform float fade = 0.0;      // 1 = fresh, 0 = gone (the scanner fades it while you walk)
uniform float dot_size = 0.006;
uniform float strength = 1.0;  // < 1: dim, e.g. the faint dots that fill the shadows behind things
uniform float size_mul = 1.0;
uniform bool depth_test = false;
uniform float tremble = 0.0;   // fear: the dots shake (0..1)
uniform sampler2D scan_data : filter_nearest, repeat_disable;
uniform vec3 origin = vec3(0.0);
uniform vec3 basis_x = vec3(1.0, 0.0, 0.0);
uniform vec3 basis_z = vec3(0.0, 0.0, 1.0);
uniform int face_res = 60;
uniform float texel_angle = 0.026;
uniform float max_dist = 4.0;  // how far the echo reaches (scanner.MAX_RANGE)

const vec3 F_RIGHT[6] = vec3[](vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 0, -1), vec3(-1, 0, 0), vec3(1, 0, 0), vec3(1, 0, 0));
const vec3 F_UP[6] = vec3[](vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(0, 0, -1));
const vec3 F_FWD[6] = vec3[](vec3(0, 0, -1), vec3(-1, 0, 0), vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0), vec3(0, -1, 0));

varying float v_light;
varying vec3 v_tint;

// Was this point the nearest thing in its direction when the scan was cast?
bool reached(vec3 wpos) {
	vec3 d = wpos - origin;
	float dist = length(d);
	vec3 dirw = d / max(dist, 1e-4);
	vec3 l = vec3(dot(dirw, basis_x), dirw.y, dot(dirw, basis_z));
	int f = 0;
	float m = -2.0;
	for (int i = 0; i < 6; i++) {
		float q = dot(l, F_FWD[i]);
		if (q > m) { m = q; f = i; }
	}
	float u = dot(l, F_RIGHT[f]) / m;
	float v = -dot(l, F_UP[f]) / m;
	int R = face_res;
	int ti = clamp(int((atan(u) / (PI / 4.0) * 0.5 + 0.5) * float(R)), 0, R - 1);
	int tj = clamp(int((atan(v) / (PI / 4.0) * 0.5 + 0.5) * float(R)), 0, R - 1);
	// lenient: the nearest of this ray and its neighbours (small things fall between rays)
	float far = 0.0;
	bool any = false;
	for (int k = 0; k < 5; k++) {
		ivec2 o = k == 0 ? ivec2(0) : (k == 1 ? ivec2(1, 0) : (k == 2 ? ivec2(-1, 0) : (k == 3 ? ivec2(0, 1) : ivec2(0, -1))));
		ivec2 tc = ivec2(clamp(ti + o.x, 0, R - 1), clamp(tj + o.y, 0, R - 1));
		vec4 s = texelFetch(scan_data, ivec2(f * R + tc.x, tc.y), 0);
		if (s.a < 0.5) continue;
		any = true;
		far = max(far, s.r <= 0.0 ? 1.0e3 : s.r);
	}
	return any && dist <= far + 0.08 + dist * texel_angle;
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float age = now - cd.x;
	float dist = cd.w;
	float mat = floor(cd.y + 0.01);
	bool outline = cd.y - mat > 0.25;
	bool person = mat > 3.5 && mat < 5.5;
	float ring = 1.0 + 0.7 * exp(-max(age, 0.0) * 18.0); // a little brighter as the wave passes
	float base = (0.35 + 0.65 * exp(-dist / (max_dist * 0.45))) * smoothstep(max_dist + 0.1, max_dist * 0.75, dist) * strength;
	float size_k = 1.0;
	v_tint = vec3(0.92, 0.95, 1.0);
	if (person) {
		// a person: a bright, unbroken outline of the body seen from where you stood
		base *= outline ? 1.25 : 0.55;
		size_k = outline ? 1.5 : 1.15;
	}
	if (mat > 4.5 && mat < 5.5) {
		v_tint = vec3(1.0, 0.05, 0.03); // the wooden leg: deep red
	}
	v_light = (age < 0.0) ? 0.0 : base * ring * fade;
	if (v_light > 0.004 && depth_test && !reached(wpos)) {
		v_light = 0.0;
	}
	vec4 vc = VIEW_MATRIX * vec4(wpos, 1.0);
	float cam_d = max(-vc.z, 0.05);
	float size = max(dot_size, cam_d * 0.004) * size_mul * size_k; // a crisp dot: a few pixels at any distance
	float tk = floor(TIME * 22.0);
	vec2 shake = (fract(sin(vec2(dot(wpos.xy, vec2(12.9898, 78.233)) + tk, dot(wpos.zy, vec2(39.346, 11.135)) - tk)) * 43758.5453) - 0.5) * tremble * 0.035;
	vc.xy += shake + VERTEX.xy * size;
	vc.z += 0.01; // just in front of the surface it is on (the occluders sit behind, main.gd)
	POSITION = PROJECTION_MATRIX * vc;
	if (v_light < 0.004) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float dotv = 1.0 - smoothstep(0.65, 1.0, d);
	ALBEDO = v_tint * v_light * dotv;
}
