shader_type spatial;
// The fixed dots of the house (scripts/world_dots.gd). Every dot sits on a surface, always in
// the same place; an echo lights the ones it reached. Up to 4 scans are kept (they add up):
// for each, the scanner gives the depth cube map of what the rays hit from where you stood,
// and a dot is lit if it was the nearest thing in its direction (a shadow-map test).
// It lights when the wave reaches it (one ring going out from you), at a brightness set by
// its distance from where you stood: near = bright, far = dim. Edges and corners are the
// brightest, so the structure of the house shows. Nothing flashes and then dims.
// INSTANCE_CUSTOM: xyz outward normal, w echo material (+0.5 = an edge dot).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D scan0 : filter_nearest, repeat_disable;
uniform sampler2D scan1 : filter_nearest, repeat_disable;
uniform sampler2D scan2 : filter_nearest, repeat_disable;
uniform sampler2D scan3 : filter_nearest, repeat_disable;
uniform vec3 origin[4];
uniform vec3 basis_x[4];  // the scan's yaw basis (columns), inverse = transpose
uniform vec3 basis_z[4];
uniform float t0[4];       // when the wave left
uniform float fade[4];     // 1 = fresh, 0 = gone (fades while you walk)
uniform int face_res = 60;
uniform float now = 0.0;
uniform float wave_speed = 16.0;
uniform float max_dist = 14.0;
uniform float texel_angle = 0.026;
// Touch: places your body is on right now (xyz, w = strength 0..1) and how wide each patch
// is. 0 is your reaching hand; the rest are footfalls and things you bumped into, dying away.
uniform vec4 touches[8];
uniform float touch_r[8];
uniform float tremble = 0.0;         // fear: the dots shake (0..1)

const vec3 F_RIGHT[6] = vec3[](vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 0, -1), vec3(-1, 0, 0), vec3(1, 0, 0), vec3(1, 0, 0));
const vec3 F_UP[6] = vec3[](vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 1, 0), vec3(0, 0, 1), vec3(0, 0, -1));
const vec3 F_FWD[6] = vec3[](vec3(0, 0, -1), vec3(-1, 0, 0), vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0), vec3(0, -1, 0));

varying float v_light;
varying vec3 v_tint;
varying float v_edge;
varying float v_soft;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 fetch(int k, ivec2 tc) {
	if (k == 0) return texelFetch(scan0, tc, 0);
	if (k == 1) return texelFetch(scan1, tc, 0);
	if (k == 2) return texelFetch(scan2, tc, 0);
	return texelFetch(scan3, tc, 0);
}

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 cd = INSTANCE_CUSTOM;
	vec3 nrm = cd.xyz;
	float mat = floor(cd.w + 0.01);
	bool edge = cd.w - mat > 0.25;
	float h = hash(wpos.xz * 3.1 + wpos.y * 7.7);
	float best = 0.0;
	int R = face_res;
	for (int k = 0; k < 4; k++) {
		if (fade[k] <= 0.001) continue;
		vec3 d = wpos - origin[k];
		float dist = length(d);
		if (dist > max_dist || dist < 0.05) continue;
		float age = now - (t0[k] + dist / wave_speed);
		if (age < 0.0) continue; // the wave isn't there yet
		vec3 dirw = d / dist;
		vec3 by = vec3(0.0, 1.0, 0.0);
		vec3 l = vec3(dot(dirw, basis_x[k]), dot(dirw, by), dot(dirw, basis_z[k])); // scan space
		int f = 0;
		float m = -2.0;
		for (int i = 0; i < 6; i++) {
			float q = dot(l, F_FWD[i]);
			if (q > m) { m = q; f = i; }
		}
		float u = dot(l, F_RIGHT[f]) / m;
		float v = -dot(l, F_UP[f]) / m;
		int ti = clamp(int((atan(u) / (PI / 4.0) * 0.5 + 0.5) * float(R)), 0, R - 1);
		int tj = clamp(int((atan(v) / (PI / 4.0) * 0.5 + 0.5) * float(R)), 0, R - 1);
		vec4 s = fetch(k, ivec2(f * R + ti, tj));
		if (s.a < 0.5 || s.r <= 0.0) continue; // not cast yet, or nothing came back
		float facing = abs(dot(nrm, -dirw));
		float tol = 0.05 + dist * texel_angle * (edge ? 1.5 : 1.0) / max(facing, 0.15);
		if (dist > s.r + tol) continue; // something nearer was in the way
		// brightness: distance from where you stood, how squarely the surface faced you
		// near = bright, dimming toward the edge of the echo's reach (gone at max_dist)
		float near = exp(-dist / (max_dist * 0.45)) * smoothstep(max_dist, max_dist * 0.75, dist);
		float b;
		if (edge) {
			b = (0.18 + 1.1 * near) * smoothstep(max_dist, max_dist * 0.75, dist);
		} else {
			b = (0.05 + 0.75 * near) * (0.35 + 0.65 * facing);
		}
		if (mat > 1.5 && mat < 2.5) b *= 0.7 + 0.3 * sin(TIME * 2.6 + dist * 1.5); // hollow: breathing
		if (mat > 2.5 && mat < 3.5) {
			if (!edge && h < 0.5) b = 0.0;                                  // glass: patchy
			b *= mix(0.4, 1.2, step(0.45, hash(wpos.xy + floor(TIME * 22.0)))); // and shimmering
		}
		b *= 1.0 + 0.7 * exp(-age * 18.0); // the ring: a little brighter as the wave passes
		best = max(best, b * fade[k]);
	}
	// Touch: the patch of surface under your hand shows, whether or not an echo reached it.
	for (int k = 0; k < 8; k++) {
		if (touches[k].w <= 0.001) continue;
		float td = distance(wpos, touches[k].xyz);
		best = max(best, touches[k].w * smoothstep(touch_r[k], touch_r[k] * 0.1, td) * (edge ? 1.3 : 0.85));
	}
	// a surface facing away from you now (the far side of a wall): not seen from here
	vec3 to_cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - wpos;
	if (!edge && dot(nrm, to_cam) < 0.0) best = 0.0;
	v_light = best;
	v_edge = edge ? 1.0 : 0.0;
	v_tint = vec3(0.92, 0.95, 1.0);
	vec4 vc = VIEW_MATRIX * vec4(wpos, 1.0);
	float cam_d = max(-vc.z, 0.05);
	// Not a grid of equal dots: every dot has its own size (a few are much bigger and
	// softer), drifts a little around its place, and breathes in brightness.
	float h2 = hash(wpos.xy * 5.3 + wpos.z * 2.9);
	float ph = h * 6.2832;
	float big = step(0.94, h2);
	float size_k = edge ? (0.75 + 0.6 * h2) : (0.5 + 1.1 * h2 * h2 + big * 1.0);
	v_soft = edge ? 0.0 : clamp(h2 * 0.5 + big * 0.5, 0.0, 1.0);
	v_light *= (0.78 + 0.22 * sin(TIME * (0.8 + h2) + ph * 3.0)) * (1.0 - big * 0.35);
	vec2 drift = vec2(sin(TIME * 0.7 + ph), cos(TIME * 0.55 + ph * 1.7)) * (edge ? 0.004 : 0.014);
	float size = max(edge ? 0.016 : 0.02, cam_d * 0.0022) * size_k;
	size = min(size, cam_d * (0.011 + big * 0.007)); // right in front of your face they don't balloon
	float tk = floor(TIME * 22.0);
	vec2 shake = (vec2(hash(wpos.xy + tk), hash(wpos.zy - tk)) - 0.5) * tremble * 0.05;
	vc.xy += drift + shake + VERTEX.xy * size;
	vc.z += 0.01; // just in front of the surface it is on (the occluders sit behind, main.gd)
	POSITION = PROJECTION_MATRIX * vc;
	if (v_light < 0.004) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0); // off screen
	}
}

void fragment() {
	float dd = length(UV - 0.5) * 2.0;
	float dotv = 1.0 - smoothstep(mix(0.55, 0.1, v_soft), 1.0, dd);
	ALBEDO = v_tint * v_light * dotv;
}
