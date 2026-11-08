shader_type canvas_item;
// Draws the frozen echo scan as a field of dots.
// Near = dense, bright, sharp. Far = sparse, dim, jittery, blurry.
// Hollow dots breathe, glass dots are sparse and shimmer. Everything else is the same.

uniform sampler2D scan_data : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(213.0, 120.0);
uniform float now = 0.0;
uniform float sweep_y = -1.0;   // 0..1 while a sweep is running, -1 otherwise
uniform float max_dist = 14.0;
uniform float seed = 0.0;       // changes each scan so dot jitter differs
uniform float scan_start = 0.0;  // when the current scan began (game clock)
uniform float fade_begin = 1.0e9; // when the player first moved after it (1e9 = still holding)
uniform float fade_time = 2.5;   // seconds to fade to black once moving
uniform float old_fade = 0.0;    // brightness of the previous picture when the new scan began

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 fetch(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(grid) - 1);
	return texelFetch(scan_data, c, 0);
}

// Outlines: jumps in distance (object silhouettes) or in surface angle (corners, creases).
float edge_at(ivec2 cell, float dist, float facing) {
	float e = 0.0;
	float thr = 0.06 * dist + 0.04;
	ivec2 offs[4] = { ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1) };
	for (int i = 0; i < 4; i++) {
		vec4 n = fetch(cell + offs[i]);
		if (n.r <= 0.0) {
			e += 1.0;
		} else {
			e += step(thr, abs(n.r - dist));
			e += 0.8 * step(0.22, abs(n.b - facing));
		}
	}
	return clamp(e, 0.0, 1.0);
}

void fragment() {
	vec2 g = UV * grid;
	vec2 cellf = floor(g);
	ivec2 cell = ivec2(cellf);
	vec2 local = fract(g);
	vec4 d = fetch(cell);
	float light = 0.0;

	if (d.r > 0.0) {
		float dist = d.r;
		float t = pow(clamp(dist / max_dist, 0.0, 1.0), 0.8); // 0 near .. 1 far
		float age = max(now - d.a, 0.0);
		float mat = d.g;
		// Held while standing still; fades once the player walks.
		// Leftovers of the previous scan fade out fast as the new sweep replaces them.
		float img_fade;
		if (d.a >= scan_start - 0.001) {
			img_fade = 1.0 - smoothstep(fade_begin, fade_begin + fade_time, now);
		} else {
			img_fade = old_fade * (1.0 - smoothstep(scan_start, scan_start + 0.5, now));
		}
		float h1 = hash(cellf + seed);
		float h2 = hash(cellf + seed + 19.7);
		float h3 = hash(cellf + seed + 41.3);
		float flick = floor(TIME * 14.0);

		float facing = d.b;
		float e = edge_at(cell, dist, facing);

		// Weak echoes (far, or surfaces seen at a grazing angle) often never come back.
		float keep = (0.15 + 0.5 * facing) * (1.0 - t * 0.75);
		bool presence = mat > 3.5;
		if (mat > 2.5 && !presence) keep *= 0.5; // glass reflects patchily
		keep = max(keep, e * (1.0 - t * 0.6)); // outlines survive
		if (presence) keep = 1.0;              // the presence never breaks up

		if (h3 < keep) {
			vec2 jit = (vec2(h1, h2) - 0.5) * mix(0.06, 0.6, t);
			jit += (vec2(hash(cellf + flick), hash(cellf + flick + 7.0)) - 0.5) * t * 0.35;
			float r = mix(0.30, 0.12, t) * (1.0 + e * 0.3);
			float soft = mix(0.03, 0.3, t) + (1.0 - img_fade) * 0.2; // blurrier far away and as it fades
			float dd = length(local - 0.5 - jit);
			float dotv = 1.0 - smoothstep(r - soft * 0.5, r + soft, dd);

			// Echo strength: falls off with distance, strongest from surfaces facing you.
			float bright = exp(-dist / 4.0) * (0.08 + 0.92 * pow(facing, 2.0)) * 1.2;
			bright += e * exp(-dist / 6.0) * 1.3;
			if (mat > 1.5 && mat < 2.5) {
				// hollow: slow breathing pulse
				bright *= 0.65 + 0.5 * (0.5 + 0.5 * sin(TIME * 2.6 + dist * 1.5));
			}
			if (presence) {
				bright = max(bright, 0.55) * (1.0 + e * 0.8);
			} else if (mat > 2.5) {
				// glass: fast shimmer
				bright *= mix(0.3, 1.35, step(0.45, hash(cellf + floor(TIME * 22.0))));
			}
			float flash = 1.0 + 1.8 * exp(-age * 7.0); // freshly revealed dots flare
			light = dotv * bright * flash * img_fade;
		}
	}

	// Scan line running top to bottom
	if (sweep_y >= 0.0 && sweep_y < 1.0) {
		float dy = abs(UV.y - sweep_y) * grid.y;
		light += exp(-dy * 1.5) * 0.18;
	}

	// Faint grain so the black never feels like a dead screen
	light += (hash(FRAGCOORD.xy + fract(TIME * 7.13) * vec2(97.0, 41.0)) - 0.5) * 0.012;

	COLOR = vec4(vec3(0.92, 0.95, 1.0) * max(light, 0.0), 1.0);
}
