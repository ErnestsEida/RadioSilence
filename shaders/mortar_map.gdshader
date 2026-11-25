shader_type canvas_item;
// Aerial / tactical top-down render of the packed map (see map_data.pack_image):
// r = wall id, g = roof top * 40, b = floor type, a = block height * 40.
// Used by the base mortar view (scripts/mortar_view.gd).

uniform sampler2D map_tex : filter_nearest;
uniform sampler2D fog_tex : filter_linear;
uniform vec2 map_size = vec2(160.0, 160.0);
uniform vec2 view_origin;          // world position at the rect's top-left corner
uniform float ppu = 20.0;          // screen pixels per world unit
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec3 ground_a = vec3(0.19, 0.29, 0.12);
uniform vec3 ground_b = vec3(0.27, 0.37, 0.16);
uniform vec3 dirt_a = vec3(0.33, 0.27, 0.19);
uniform vec3 dirt_b = vec3(0.41, 0.34, 0.24);
uniform vec3 rock_tint = vec3(1.0);
uniform float snow = 0.0;
uniform float time = 0.0;
uniform vec2 mortar_pos;
uniform float r_max = 80.0;
uniform float r_min = 8.0;
uniform vec3 team_col = vec3(0.3, 0.5, 0.9);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 cell(vec2 wp) {
	ivec2 c = ivec2(floor(wp));
	if (c.x < 0 || c.y < 0 || float(c.x) >= map_size.x || float(c.y) >= map_size.y) {
		return vec4(1.0 / 255.0, 0.0, 0.0, 140.0 / 255.0);
	}
	return texelFetch(map_tex, c, 0);
}

int wall_id(vec4 t) { return int(round(t.r * 255.0)); }
float block_h(vec4 t) { return t.a * 255.0 / 40.0; }
float roof_h(vec4 t) { return t.g * 255.0 / 40.0; }

// height of whatever you'd see from above in this cell
float top_h(vec4 t) {
	if (wall_id(t) > 0) return block_h(t);
	if (t.g > 0.0) return roof_h(t);
	return 0.0;
}

vec3 wall_col(int id, vec2 wp, float n) {
	vec2 f = fract(wp);
	if (id == 1) {   // rock: strata and cracks
		float s = vnoise(wp * vec2(2.0, 5.0)) * 0.5 + vnoise(wp * 7.0) * 0.25;
		return vec3(0.47, 0.43, 0.38) * rock_tint * (0.75 + s * 0.5);
	}
	if (id == 2) {   // brick
		float row = floor(wp.y * 4.0);
		float bx = fract(wp.x * 2.0 + mod(row, 2.0) * 0.5);
		float by = fract(wp.y * 4.0);
		float mortar = (bx < 0.08 || by < 0.12) ? 0.7 : 1.0;
		return vec3(0.56, 0.28, 0.19) * mortar * (0.9 + n * 0.15);
	}
	if (id == 3) return vec3(0.6, 0.6, 0.57) * (0.92 + n * 0.1) * ((f.x < 0.04 || f.y < 0.04) ? 0.82 : 1.0);
	if (id == 4) return vec3(0.33, 0.39, 0.5) * ((mod(floor(wp.x * 2.0) + floor(wp.y * 2.0), 2.0) < 1.0) ? 1.0 : 0.9);
	if (id == 5) return vec3(0.55, 0.2, 0.17);
	if (id == 6) return (fract((wp.x + wp.y) * 1.5) < 0.5) ? vec3(0.85, 0.7, 0.12) : vec3(0.12, 0.12, 0.12);
	if (id == 7) return vec3(0.68, 0.68, 0.62) * (0.92 + n * 0.1);
	if (id == 8) return vec3(0.9, 0.55, 0.12);
	if (id == 9) {   // sandbags: rows of stuffed bags
		float row = floor(wp.y * 3.0);
		vec2 q = vec2(fract(wp.x * 2.0 + mod(row, 2.0) * 0.5), fract(wp.y * 3.0)) - 0.5;
		float bag = 1.0 - smoothstep(0.25, 0.5, length(q * vec2(1.0, 1.3)));
		return vec3(0.6, 0.53, 0.36) * (0.62 + bag * 0.45);
	}
	if (id == 10) return vec3(0.58, 0.42, 0.22) * ((fract(wp.x * 3.0) < 0.1) ? 0.7 : 1.0);
	if (id == 11) return vec3(0.2, 0.4, 0.5) * (0.85 + 0.15 * step(0.5, fract(wp.x * 5.0)));
	if (id == 12) return vec3(0.58, 0.58, 0.56) * (0.92 + n * 0.1);
	if (id == 13) return vec3(0.52, 0.36, 0.2) * ((fract(wp.y * 4.0) < 0.12) ? 0.7 : (0.92 + n * 0.12));
	if (id == 14) return vec3(0.44, 0.45, 0.5) * ((fract(wp.x * 4.0) < 0.15) ? 0.75 : 1.0);
	if (id == 15) {  // hedge
		float l = vnoise(wp * 6.0);
		return vec3(0.16, 0.34, 0.12) * (0.7 + l * 0.6);
	}
	return vec3(0.74, 0.66, 0.52) * (0.92 + n * 0.1);
}

vec3 floor_col(int fl, vec2 wp, float n, float n2) {
	float grain = hash(floor(wp * 8.0)) * 0.08 - 0.04;
	if (fl == 1) {   // dirt road with tyre ruts
		vec3 c = mix(dirt_a, dirt_b, vnoise(wp * 1.3));
		return c * (0.95 + grain * 1.5 + n2 * 0.08);
	}
	if (fl == 2) {   // concrete slabs
		vec2 f = fract(wp * 0.5);
		float seam = (f.x < 0.025 || f.y < 0.025) ? 0.78 : 1.0;
		vec3 c = vec3(0.47, 0.47, 0.45) * (0.92 + vnoise(wp * 0.8) * 0.12 + grain);
		return c * seam;
	}
	if (fl == 3) {   // metal floor plates
		vec2 f = fract(wp);
		float seam = (f.x < 0.04 || f.y < 0.04) ? 0.7 : 1.0;
		float dia = step(0.5, fract((wp.x + wp.y) * 6.0)) * 0.05;
		return vec3(0.3, 0.32, 0.36) * seam * (0.95 + dia);
	}
	if (fl == 4) {   // water: deep tint and moving ripples
		float w = sin(wp.x * 3.1 + time * 1.4 + sin(wp.y * 1.7) * 2.0) * sin(wp.y * 2.6 - time * 1.1);
		vec3 c = vec3(0.1, 0.26, 0.4) + vec3(0.12, 0.16, 0.18) * smoothstep(0.55, 1.0, w);
		return c * (0.9 + vnoise(wp * 0.7) * 0.2);
	}
	if (fl == 5) {   // cobbles
		vec2 q = fract(wp * 3.0) - 0.5;
		float stone = 1.0 - smoothstep(0.3, 0.5, max(abs(q.x), abs(q.y)));
		return vec3(0.4, 0.37, 0.34) * (0.7 + stone * 0.35) * (0.9 + hash(floor(wp * 3.0)) * 0.2);
	}
	// grass / sand / snow
	vec3 c = mix(ground_a, ground_b, n);
	c *= 0.92 + n2 * 0.16 + grain;
	return c;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 wp = view_origin + px / ppu;
	vec4 t = cell(wp);
	int id = wall_id(t);
	int fl = int(round(t.b * 255.0));
	float n = vnoise(wp * 0.35);
	float n2 = vnoise(wp * 2.3);
	float h = top_h(t);
	vec3 col;
	bool outside = wp.x < 0.0 || wp.y < 0.0 || wp.x >= map_size.x || wp.y >= map_size.y;
	vec2 f = fract(wp);
	if (outside) {
		col = vec3(0.07, 0.075, 0.08) + vec3(hash(floor(wp * 2.0)) * 0.03);
	} else if (id > 0) {
		col = wall_col(id, wp, n2);
		if (snow > 0.5 && id != 6 && id != 8) {
			col = mix(col, vec3(0.9, 0.92, 0.96), 0.55 * smoothstep(0.3, 0.7, vnoise(wp * 3.0)));
		}
		col *= clamp(0.78 + h * 0.12, 0.75, 1.2);
	} else if (t.g > 0.0) {
		// roof: corrugated sheets
		float corr = 0.9 + 0.1 * sin(wp.x * 18.0);
		col = vec3(0.4, 0.36, 0.33) * corr * (0.9 + n2 * 0.15);
		if (snow > 0.5) col = mix(col, vec3(0.88, 0.9, 0.95), 0.7);
		col *= clamp(0.8 + h * 0.1, 0.8, 1.15);
	} else {
		col = floor_col(fl, wp, n, n2);
	}
	// bevels: lit top/left edges, dark bottom/right edges where the neighbour is lower
	if (!outside && h > 0.0) {
		float e = 0.13;
		float hl = top_h(cell(wp + vec2(-1.0, 0.0)));
		float hu = top_h(cell(wp + vec2(0.0, -1.0)));
		float hr = top_h(cell(wp + vec2(1.0, 0.0)));
		float hd = top_h(cell(wp + vec2(0.0, 1.0)));
		if ((f.x < e && hl < h - 0.05) || (f.y < e && hu < h - 0.05)) col *= 1.22;
		if ((f.x > 1.0 - e && hr < h - 0.05) || (f.y > 1.0 - e && hd < h - 0.05)) col *= 0.62;
	}
	// cast shadows: march towards the sun (upper left)
	if (!outside) {
		vec2 sun = normalize(vec2(-1.0, -0.75));
		float sh = 0.0;
		for (int i = 1; i <= 12; i++) {
			float d = float(i) * 0.22;
			float hq = top_h(cell(wp + sun * d));
			if (hq > h + d * 0.85) {
				sh = max(sh, 1.0 - float(i) / 14.0);
			}
		}
		col *= 1.0 - sh * 0.42;
	}
	// fog of war: unexplored ground is dimmed and greyed out
	if (!outside) {
		float fogA = texture(fog_tex, wp / map_size).a;
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(lum) * vec3(0.55, 0.58, 0.62), fogA * 0.75);
	}
	// tactical grid every 10 m
	vec2 g = abs(fract(wp / 10.0 + 0.5) - 0.5) * 10.0 * ppu;
	float gl = 1.0 - smoothstep(0.0, 1.2, min(g.x, g.y));
	col = mix(col, vec3(0.85, 0.95, 0.85), gl * 0.1);
	// reach of the mortar: outside the max range (and inside the min range) is shaded
	float dm = distance(wp, mortar_pos);
	float out_k = smoothstep(r_max - 0.2, r_max + 0.6, dm) + (1.0 - smoothstep(r_min - 0.6, r_min + 0.2, dm));
	col = mix(col, col * vec3(0.5, 0.38, 0.36), clamp(out_k, 0.0, 1.0) * 0.7);
	float ring = 1.0 - smoothstep(0.6, 2.2, abs(dm - r_max) * ppu);
	float dash = step(0.45, fract(atan(wp.y - mortar_pos.y, wp.x - mortar_pos.x) * r_max / 6.2831 * 0.5 + time * 0.1));
	col = mix(col, vec3(1.0, 0.82, 0.35), ring * (0.35 + 0.5 * dash));
	float ring2 = 1.0 - smoothstep(0.6, 1.8, abs(dm - r_min) * ppu);
	col = mix(col, vec3(1.0, 0.4, 0.3), ring2 * 0.6);
	// recon-photo grade: slight desaturation, cool shadows, vignette, grain
	float lum2 = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum2), 0.12) * vec3(0.98, 1.0, 1.02);
	vec2 v = UV - 0.5;
	col *= 1.0 - 0.55 * pow(length(v * vec2(rect_size.x / rect_size.y, 1.0)) * 0.95, 2.6);
	col += (hash(px + fract(time) * 91.0) - 0.5) * 0.035;
	COLOR = vec4(col, 1.0);
}
