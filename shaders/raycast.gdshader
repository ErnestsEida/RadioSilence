shader_type canvas_item;
render_mode unshaded;

// Height-field raycaster ("2.5D voxel" style): every grid cell is a block with its own height,
// rays are marched through the grid per pixel so you can look up/down (y-shearing), see over low
// cover, onto roofs and block tops, under door lintels and into the sky. Billboard sprites on top.

uniform sampler2D map_tex : filter_nearest, repeat_disable;    // r = wall id, g = roof top * 40 (0 = open), b = floor type, a = block height * 40
uniform sampler2D wall_tex : filter_nearest, repeat_disable;   // wall atlas, 64px tiles in a row
uniform sampler2D sprite_tex : filter_nearest, repeat_disable; // sprite atlas, 16 x 16 frames
uniform sampler2D spr_data : filter_nearest, repeat_disable;
uniform sampler2D veh_tex : filter_nearest, repeat_disable;    // baked 3D vehicles: 16 angles x (5 types * 4 parts)
uniform vec2 veh_grid = vec2(16.0, 20.0);
uniform sampler2D veh3d_col : filter_nearest, repeat_disable;    // 3D vehicle layer (scripts/vehicle_layer.gd): lit colour
uniform sampler2D veh3d_depth : filter_nearest, repeat_disable;  // forward depth / veh3d_range in 3 base-54 digits + solid/shadow flag
uniform bool veh3d_on = false;
uniform float veh3d_range = 64.0;
uniform vec3 team_cols[4];   // row 0: x, y, frame, scale; row 1: zoff, flags(1 mirror, 2 sway, 4 glow), flash, alpha
uniform vec2 map_size = vec2(96.0, 96.0);
uniform vec2 cam_pos = vec2(5.5, 5.5);
uniform float cam_angle = 0.0;
uniform float plen = 0.84;
uniform float vscale = 1.0;
uniform float bob = 0.0;
uniform float look = 0.0;          // vertical look (y-shear), = tan(pitch) * vscale
uniform float eye = 0.6;           // absolute eye height in world units (1 unit = 1 cell)
uniform float time = 0.0;
uniform int weather = 0;           // 0 pollen, 1 dust, 2 snow, 3 embers, -1 none
uniform float snow_tops = 0.0;
uniform float weather_amt = 1.0;   // particle density multiplier (storms)
uniform float lightning = 0.0;
uniform float wall_tiles = 16.0;
uniform float tile_h[17];          // texture repeat height per wall type
uniform float atlas_grid = 16.0;
uniform float hurt = 0.0;
uniform float desat = 0.0;
uniform float indoor = 0.0;
uniform int sprite_count = 0;
uniform vec3 ground_a = vec3(0.19, 0.29, 0.12);
uniform vec3 ground_b = vec3(0.27, 0.37, 0.16);
uniform vec3 dirt_a = vec3(0.33, 0.27, 0.19);
uniform vec3 dirt_b = vec3(0.41, 0.34, 0.24);
uniform vec3 sky_top = vec3(0.30, 0.42, 0.58);
uniform vec3 sky_hor = vec3(0.72, 0.64, 0.52);
uniform vec3 fog_col = vec3(0.62, 0.62, 0.58);
uniform vec3 mount_col = vec3(0.30, 0.31, 0.37);
uniform vec3 rock_tint = vec3(1.0);
uniform float fog_dist = 42.0;

const float HS = 40.0;     // height byte scale
const float CEIL = 1.0;    // interior ceiling height
const float MAXH = 6.4;    // nothing is taller than this
const float EDGE_H = 3.5;  // the world outside the map

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 floor_color(int ft, vec2 fp) {
	float n = hash(floor(fp * 16.0));
	vec2 f = fract(fp);
	if (ft == 0) {
		float n2 = hash(floor(fp * 3.0));
		float n3 = hash(floor(fp * 0.7));
		vec3 c = mix(ground_a, ground_b, n) * (0.85 + 0.15 * n2) * (0.92 + 0.12 * n3);
		return c;
	} else if (ft == 1) {
		float rut = (abs(f.x - 0.3) < 0.06 || abs(f.y - 0.3) < 0.06) ? 0.85 : 1.0;
		return mix(dirt_a, dirt_b, n) * rut;
	} else if (ft == 2) {
		float edge = (f.x < 0.04 || f.y < 0.04) ? 0.72 : 1.0;
		return vec3(0.42, 0.42, 0.40) * (0.9 + 0.1 * n) * edge;
	} else if (ft == 4) {
		// shallow water: moving ripples, sky reflection and sun glints
		float w = sin(fp.x * 6.0 + time * 1.7 + sin(fp.y * 2.0)) * 0.5 + sin(fp.y * 8.0 - time * 1.3 + fp.x * 3.0) * 0.5;
		vec3 c = mix(vec3(0.08, 0.17, 0.22), sky_top * 0.75, 0.45) + w * 0.035;
		if (hash(floor(fp * 10.0) + floor(time * 2.5)) > 0.987) c += vec3(0.35);
		return c;
	} else if (ft == 5) {
		// cobblestones
		vec2 g = fract(fp * vec2(3.0, 4.0) + vec2(floor(fp.y * 4.0) * 0.5, 0.0));
		float gap = (g.x < 0.1 || g.y < 0.12) ? 0.6 : 1.0;
		return vec3(0.40, 0.37, 0.33) * gap * (0.85 + 0.2 * hash(floor(fp * vec2(3.0, 4.0))));
	}
	vec2 g = fract(fp * 4.0);
	float l = (g.x < 0.12 || g.y < 0.12) ? 0.65 : 1.0;
	return vec3(0.26, 0.28, 0.31) * l * (0.92 + 0.08 * n);
}

vec3 wall_sample(int id, float u, float v) {
	return texture(wall_tex, vec2((float(id - 1) + clamp(u, 0.002, 0.998)) / wall_tiles, clamp(v, 0.002, 0.998))).rgb;
}

vec3 top_color(int id, vec2 fp) {
	vec2 f = fract(fp);
	vec3 c = wall_sample(id, f.x, f.y * 0.5 + 0.25);
	if (id == 1) c *= rock_tint;
	float edge = (f.x < 0.05 || f.y < 0.05 || f.x > 0.95 || f.y > 0.95) ? 0.82 : 1.0;
	c = c * 1.1 * edge;
	return mix(c, vec3(0.9, 0.92, 0.96), snow_tops * 0.8);
}

vec3 roof_color(vec2 fp) {
	vec2 f = fract(fp * vec2(1.0, 2.0));
	float n = hash(floor(fp * 12.0));
	vec3 c = vec3(0.29, 0.27, 0.26) * (0.88 + 0.14 * n);
	if (f.y < 0.06) c *= 0.7;
	return mix(c, vec3(0.88, 0.9, 0.94), snow_tops * 0.85);
}

vec3 ceil_color(vec2 fp) {
	vec2 f = fract(fp);
	float n = hash(floor(fp * 16.0));
	vec3 c = vec3(0.20, 0.20, 0.23) * (0.9 + 0.1 * n);
	if (f.x < 0.05 || f.y < 0.05) c *= 0.55;
	if (abs(f.x - 0.5) < 0.12 && abs(f.y - 0.5) < 0.28) c = vec3(0.85, 0.85, 0.72);
	return c;
}

vec3 sky_color(float sy, vec2 ray) {
	float ang = atan(ray.y, ray.x);
	float up = 0.5 - sy;
	vec3 c = mix(sky_hor, sky_top, clamp(up * 2.0, 0.0, 1.0));
	// drifting cloud bands
	float drift = time * 0.012;
	float cl = sin(ang * 5.0 + drift * 6.0 + up * 9.0) * 0.5 + sin(ang * 11.0 - drift * 9.0 - up * 23.0) * 0.3 + sin(ang * 23.0 + drift * 17.0 + up * 41.0) * 0.15;
	if (up > 0.08) c = mix(c, vec3(1.0), clamp((cl - 0.45) * 2.0, 0.0, 1.0) * 0.22 * clamp((up - 0.08) * 8.0, 0.0, 1.0));
	// sun glow
	float sun = max(0.0, cos(ang - 0.9)) * clamp(1.0 - abs(up - 0.25) * 4.0, 0.0, 1.0);
	c += vec3(1.0, 0.9, 0.7) * pow(sun, 24.0) * 0.35;
	float m = 0.06 + 0.03 * sin(ang * 3.0) + 0.02 * sin(ang * 7.0 + 1.3) + 0.012 * sin(ang * 17.0);
	if (up < m) c = mix(mount_col, c, 0.25);
	float m2 = 0.035 + 0.02 * sin(ang * 5.0 + 2.0) + 0.01 * sin(ang * 13.0);
	if (up < m2) c = mix(mount_col * 0.8, fog_col, 0.35);
	return c;
}

void fragment() {
	float sx = UV.x * 2.0 - 1.0;
	float sy = UV.y;
	float horizon = 0.5 + bob + look;
	vec2 dir = vec2(cos(cam_angle), sin(cam_angle));
	vec2 rightv = vec2(-dir.y, dir.x);
	vec2 ray = dir + rightv * plen * sx;
	if (abs(ray.x) < 1e-5) ray.x = 1e-5;
	if (abs(ray.y) < 1e-5) ray.y = 1e-5;
	// height gained per unit of forward distance along this pixel's ray
	float s = (horizon - sy) / vscale;

	ivec2 mp = ivec2(floor(cam_pos));
	vec2 dd = abs(1.0 / ray);
	ivec2 stp = ivec2(ray.x < 0.0 ? -1 : 1, ray.y < 0.0 ? -1 : 1);
	vec2 sd;
	sd.x = ray.x < 0.0 ? (cam_pos.x - float(mp.x)) * dd.x : (float(mp.x) + 1.0 - cam_pos.x) * dd.x;
	sd.y = ray.y < 0.0 ? (cam_pos.y - float(mp.y)) * dd.y : (float(mp.y) + 1.0 - cam_pos.y) * dd.y;
	float fd = mix(fog_dist, 16.0, indoor);
	float maxt = fd * 1.2;

	int kind = 0;      // 0 fog, 1 block face, 2 block top / floor, 3 roof top, 4 ceiling, 5 lintel face, 6 sky
	int side = 0;
	int wid = 0;
	int ftype = 0;
	float hh = 0.0;
	float thit = maxt;
	float zhit = 0.0;
	float t_in = 0.0;
	for (int i = 0; i < 320; i++) {
		float t_out = min(sd.x, sd.y);
		bool oob = mp.x < 0 || mp.y < 0 || mp.x >= int(map_size.x) || mp.y >= int(map_size.y);
		vec4 mc = oob ? vec4(1.0 / 255.0, 0.0, 0.0, EDGE_H * HS / 255.0) : texelFetch(map_tex, mp, 0);
		int w = int(mc.r * 255.0 + 0.5);
		float h = w > 0 ? mc.a * 255.0 / HS : 0.0;
		float z_in = eye + s * t_in;
		float z_out = eye + s * t_out;
		if (w > 0 && i > 0 && z_in < h) {
			kind = 1; wid = w; hh = h; thit = t_in; zhit = z_in;
			break;
		}
		if (z_out < h) {
			kind = 2; wid = w; hh = h;
			thit = s < -1e-6 ? (h - eye) / s : t_in;
			ftype = int(mc.b * 255.0 + 0.5);
			break;
		}
		float rt = mc.g * 255.0 / HS;
		if (rt > 0.0) {
			if (i > 0 && z_in > CEIL && z_in < rt) {
				kind = 5; hh = rt; thit = t_in; zhit = z_in;
				break;
			}
			if (z_in >= rt && z_out < rt) {
				kind = 3; thit = (rt - eye) / s;
				break;
			}
			if (z_in <= CEIL && z_out > CEIL) {
				kind = 4; thit = (CEIL - eye) / s;
				break;
			}
		}
		if (t_out > maxt) {
			kind = s > 0.0 ? 6 : 0;
			thit = maxt;
			break;
		}
		if (s > 0.0 && z_out > MAXH) {
			kind = 6;
			break;
		}
		if (sd.x < sd.y) { t_in = sd.x; sd.x += dd.x; mp.x += stp.x; side = 0; }
		else { t_in = sd.y; sd.y += dd.y; mp.y += stp.y; side = 1; }
	}

	vec3 col;
	float depth = thit;
	if (kind == 1 || kind == 5) {
		float wx = side == 0 ? cam_pos.y + thit * ray.y : cam_pos.x + thit * ray.x;
		wx = fract(wx);
		if (side == 0 && ray.x < 0.0) wx = 1.0 - wx;
		if (side == 1 && ray.y > 0.0) wx = 1.0 - wx;
		int tid = kind == 1 ? wid : 12;
		float tv = fract(hh - zhit);
		if (kind == 1) {
			float nt = max(1.0, floor(hh / max(tile_h[tid], 0.05) + 0.5));
			tv = fract((hh - zhit) * nt / hh);
		}
		col = wall_sample(tid, wx, tv);
		if (tid == 1) col *= rock_tint;
		// four-way directional light
		float lit = side == 0 ? (ray.x > 0.0 ? 0.80 : 1.0) : (ray.y > 0.0 ? 0.68 : 0.9);
		col *= lit;
		col *= 0.7 + 0.3 * clamp(zhit / 0.7, 0.0, 1.0);   // ambient occlusion toward the ground
		if (snow_tops > 0.0 && kind == 1 && hh - zhit < 0.05 && hh > 0.3) col = mix(col, vec3(0.92, 0.94, 0.98), snow_tops);
	} else if (kind == 2) {
		vec2 fp = cam_pos + ray * thit;
		col = hh <= 0.0 ? floor_color(ftype, fp) : top_color(wid, fp);
	} else if (kind == 3) {
		col = roof_color(cam_pos + ray * thit);
	} else if (kind == 4) {
		col = ceil_color(cam_pos + ray * thit);
	} else if (kind == 6) {
		col = sky_color(sy - (horizon - 0.5), ray);
		depth = 1000.0;
	} else {
		col = fog_col;
	}

	// real 3D vehicles: drawn where nearer than the world geometry; the ground shadow only darkens
	if (veh3d_on) {
		ivec2 vsz = textureSize(veh3d_depth, 0);
		ivec2 vpx = clamp(ivec2(UV * vec2(vsz)), ivec2(0), vsz - ivec2(1));
		vec4 vdp = texelFetch(veh3d_depth, vpx, 0);
		if (vdp.a > 0.5) {
			// three base-54 digits stored as 96 + 3n (see vehicle_layer.gd DEPTH_SHADER)
			vec3 dg = floor((vdp.rgb * 255.0 - 96.0) / 3.0 + 0.5);
			bool solid = dg.z >= 27.0;
			float vdz = (dg.x * 54.0 + dg.y + ((solid ? dg.z - 27.0 : dg.z) + 0.5) / 27.0) / 2916.0 * veh3d_range;
			if (vdz < depth) {
				vec4 vc = texelFetch(veh3d_col, vpx, 0);
				if (solid) {
					col = vc.rgb;
					depth = vdz;
				} else {
					col *= 1.0 - vc.a;
				}
			}
		}
	}

	// Billboard sprites, sorted far to near on the CPU
	float fogk = 1.0;
	for (int i = 0; i < 256; i++) {
		if (i >= sprite_count) break;
		vec4 a = texelFetch(spr_data, ivec2(i, 0), 0);
		vec4 b = texelFetch(spr_data, ivec2(i, 1), 0);
		vec2 rel = a.xy - cam_pos;
		float dz = dot(rel, dir);
		if (dz < 0.12 || dz > depth) continue;
		float lat = dot(rel, rightv);
		float u = (sx * plen * dz - lat) / a.w + 0.5;
		if (u < -0.1 || u >= 1.1) continue;
		float size = a.w * vscale / dz;
		float bottom = horizon + (eye - b.x) * vscale / dz;
		float v = (sy - (bottom - size)) / size;
		if (v < 0.0 || v >= 1.0) continue;
		int fl = int(b.y + 0.5);
		if ((fl & 1) != 0) u = 0.999 - u;
		if ((fl & 2) != 0) u += sin(time * 1.4 + a.x * 0.7 + a.y * 1.3) * 0.045 * (1.0 - v) * (1.0 - v);
		if (u < 0.0 || u >= 1.0) continue;
		vec4 sc;
		if ((fl & 8) != 0) {
			// pre-rendered 3D vehicle: team paint is stored as grey with alpha 0.6
			vec2 vc = vec2(mod(a.z, veh_grid.x), floor(a.z / veh_grid.x));
			sc = texture(veh_tex, (vc + clamp(vec2(u, v), 0.001, 0.999)) / veh_grid);
			if (sc.a > 0.5 && sc.a < 0.8) {
				int tm = (fl >> 4) & 7;
				vec3 tcol = tm > 0 ? team_cols[tm - 1] : vec3(0.45, 0.47, 0.4);
				sc = vec4(tcol * sc.r * 1.6, 1.0);
			}
		} else {
			vec2 cell = vec2(mod(a.z, atlas_grid), floor(a.z / atlas_grid));
			sc = texture(sprite_tex, (cell + clamp(vec2(u, v), 0.001, 0.999)) / atlas_grid);
		}
		if (b.w > 0.0) {
			col = mix(col, sc.rgb, sc.a * b.w);
			continue;
		}
		if (sc.a < 0.5) continue;
		col = mix(sc.rgb, vec3(1.0, 0.95, 0.7), b.z);
		depth = dz;
		fogk = (fl & 4) != 0 ? 0.15 : 1.0;
	}

	vec3 fogc = mix(fog_col, vec3(0.03, 0.03, 0.04), indoor);
	if (depth < 900.0) {
		float fg = clamp(depth / fd, 0.0, 1.0);
		col = mix(col, fogc, fg * fg * 0.95 * fogk);
	}

	// weather particles in three parallax layers around the camera
	if (weather >= 0 && indoor < 0.5) {
		float ang = cam_angle + atan(sx * plen);
		for (int L = 0; L < 3; L++) {
			float d = 2.2 + float(L) * 2.6;
			if (d > depth) continue;
			float hz = eye + (horizon - sy) * d / vscale;
			float hx = (ang * d - dot(cam_pos, rightv) * 0.6) * 1.45;
			float fl = float(L);
			vec2 q;
			float dens = 0.05;
			float rad = 0.16;
			vec3 pc = vec3(0.95, 0.95, 0.75);
			float pa = 0.55;
			if (weather == 2) {
				q = vec2(hx + sin(time * 0.7 + fl + hz) * 0.25, hz + time * (0.55 + 0.15 * fl)) * 5.0;
				dens = 0.22; rad = 0.14; pc = vec3(0.96, 0.97, 1.0); pa = 0.85;
			} else if (weather == 1) {
				q = vec2(hx - time * (1.6 + fl * 0.5), hz + sin(time * 1.3 + hx) * 0.08) * 4.0;
				dens = 0.07; rad = 0.12; pc = vec3(0.82, 0.70, 0.50); pa = 0.45;
			} else if (weather == 4) {
				// rain: thin fast streaks
				q = vec2(hx * 6.0 + hz * 0.6, (hz + time * (7.0 + fl * 1.5)) * 0.8);
				dens = 0.12; rad = 0.0; pc = vec3(0.75, 0.8, 0.88); pa = 0.5;
				vec2 gi4 = floor(q);
				vec2 gf4 = fract(q);
				if (hash(gi4 + fl * 11.1) < min(0.9, dens * weather_amt) && abs(gf4.x - hash(gi4 + 2.3) * 0.8 - 0.1) < 0.035 && gf4.y < 0.45)
					col = mix(col, pc, pa);
				continue;
			} else if (weather == 3) {
				q = vec2(hx + sin(time * 0.6 + hz * 2.0) * 0.3, hz - time * (0.3 + 0.1 * fl)) * 3.0;
				dens = 0.035; rad = 0.1; pc = vec3(1.0, 0.55, 0.18); pa = 0.9;
			} else {
				q = vec2(hx + time * 0.25, hz + sin(time * 0.8 + hx * 0.5) * 0.15 - time * 0.05) * 3.0;
				dens = 0.03; rad = 0.1; pc = vec3(0.98, 0.97, 0.8); pa = 0.6;
			}
			vec2 gi = floor(q);
			vec2 gf = fract(q);
			if (hash(gi + fl * 17.3) < min(0.8, dens * weather_amt)) {
				vec2 c = vec2(hash(gi + 3.1), hash(gi + 7.7)) * 0.6 + 0.2;
				if (length(gf - c) < rad * 0.4 / (1.0 + fl * 0.25)) col = mix(col, pc, pa * (1.0 - fl * 0.2));
			}
		}
	}

	col += vec3(0.75, 0.8, 0.95) * lightning * (depth > 900.0 ? 1.0 : 0.45);
	float vig = length(UV - 0.5);
	col *= 1.0 - vig * vig * 0.5;
	col = mix(col, vec3(0.75, 0.0, 0.0), clamp(hurt, 0.0, 1.0) * (0.15 + vig * 0.9));
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g) * vec3(0.8, 0.6, 0.55), desat);
	COLOR = vec4(col, 1.0);
}
