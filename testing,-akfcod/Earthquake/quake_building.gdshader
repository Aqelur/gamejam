// Building material used while a building is being hit by an earthquake.
// BuildingQuake swaps this in for the building's normal material for the
// duration of the quake (and puts the original back on reset).
//
// It reproduces the city look (palette paint from building_paint.gdshader and
// grime/cracks/moss from weathering.gdshader) and adds:
//   * damage      - cracks spread and the walls get a coat of dust
//   * cut boxes   - jagged regions that are "broken off" the building. The
//                   main building discards them and each falling chunk keeps
//                   only its own box, so the pieces fit together exactly.
//   * interior    - back faces render as dark broken concrete, so holes look
//                   like real holes instead of see-through shells
//   * clip_y      - everything below the ground is discarded (used when a
//                   building pancakes into the ground)
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 paint_color : source_color = vec4(1.0, 0.75, 0.27, 1.0);
uniform vec4 trim_color : source_color = vec4(0.8, 0.33, 0.31, 1.0);
uniform float paint_strength = 0.0;
uniform float trim_strength = 0.0;
uniform float roughness_value = 0.85;
uniform vec3 emission_color = vec3(0.0);

// weathering (copied from the building's overlay when there is one)
uniform float grime = 0.0;
uniform float cracks = 0.0;
uniform float moss = 0.0;
uniform float water_line = -100.0;
uniform float ground_y = 0.0;
uniform float seed = 0.0;
uniform vec4 grime_color : source_color = vec4(0.40, 0.34, 0.28, 1.0);
uniform vec4 soot_color : source_color = vec4(0.17, 0.17, 0.19, 1.0);
uniform vec4 water_color : source_color = vec4(0.42, 0.34, 0.25, 1.0);
uniform vec4 moss_color : source_color = vec4(0.16, 0.56, 0.43, 1.0);

// earthquake
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dust_color : source_color = vec4(0.66, 0.61, 0.53, 1.0);
uniform vec4 interior_color : source_color = vec4(0.42, 0.39, 0.36, 1.0);
uniform mat4 mesh_to_cut = mat4(1.0);
uniform mat4 cut_to_world0 = mat4(1.0);
uniform int cut_count = 0;
uniform vec3 cut_center[6];
uniform vec3 cut_half[6];
uniform int keep_index = -1;
uniform float clip_y = -1000.0;

varying vec3 cp;
varying vec3 wp0;
varying vec3 wn0;
varying vec3 wpos;

void vertex() {
	cp = (mesh_to_cut * vec4(VERTEX, 1.0)).xyz;
	wp0 = (cut_to_world0 * vec4(cp, 1.0)).xyz;
	wn0 = normalize((cut_to_world0 * (mesh_to_cut * vec4(NORMAL, 0.0))).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float noise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float voronoi_edge(vec2 p) {
	vec2 n = floor(p); vec2 f = fract(p);
	vec2 mg; vec2 mr; float md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j)); vec2 r = g + hash2(n + g) - f;
		float d = dot(r, r); if (d < md) { md = d; mr = r; mg = g; }
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
		vec2 g = mg + vec2(float(i), float(j)); vec2 r = g + hash2(n + g) - f;
		if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
	}
	return md;
}

// jagged box test - identical for the building and its chunks so they match
bool in_cut(vec3 p, int i) {
	vec3 h = cut_half[i];
	float jag = min(h.x, min(h.y, h.z)) * 0.45;
	vec3 d = abs(p - cut_center[i]);
	vec3 j = vec3(
		noise3(p * 11.0 + float(i) * 3.1),
		noise3(p * 11.0 + 17.0 + float(i) * 3.1),
		noise3(p * 11.0 + 41.0 + float(i) * 3.1)) - 0.5;
	return all(lessThan(d, h + j * jag));
}

void fragment() {
	if (wpos.y < clip_y) discard;
	if (keep_index >= 0) {
		if (!in_cut(cp, keep_index)) discard;
	} else {
		for (int i = 0; i < cut_count; i++) {
			if (in_cut(cp, i)) discard;
		}
	}

	if (!FRONT_FACING) {
		// inside of a broken wall
		float n = noise3(cp * 25.0);
		// broken concrete + darker floor slabs every ~0.42 units
		float slab = smoothstep(0.03, 0.0, abs(fract(cp.y / 0.42) - 0.5) - 0.44);
		vec3 ic = interior_color.rgb * (0.75 + 0.5 * n) * (1.0 - slab * 0.45);
		ALBEDO = ic;
		EMISSION = ic * 0.35;
		ROUGHNESS = 1.0;
		SPECULAR = 0.1;
	} else {
		vec3 tex = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
		vec3 col = tex;
		if (paint_strength > 0.0 || trim_strength > 0.0) {
			float mx = max(tex.r, max(tex.g, tex.b));
			float mn = min(tex.r, min(tex.g, tex.b));
			float sat = mx > 0.0001 ? (mx - mn) / mx : 0.0;
			float lum = dot(tex, vec3(0.299, 0.587, 0.114));
			float grey = 1.0 - smoothstep(0.22, 0.32, sat);
			float wall = grey * smoothstep(0.55, 0.72, lum);
			vec3 wall_col = paint_color.rgb * clamp(lum / 0.88, 0.0, 1.1);
			float trim = grey * smoothstep(0.26, 0.34, lum) * (1.0 - wall);
			vec3 trim_col = trim_color.rgb * clamp(lum * 1.35, 0.0, 1.0);
			col = mix(col, trim_col, trim * trim_strength);
			col = mix(col, wall_col, wall * paint_strength);
		}

		// weathering, evaluated at the position the surface had before the quake
		vec3 n = normalize(wn0);
		bool is_roof = n.y > 0.7;
		vec2 uv = abs(n.x) > abs(n.z) ? wp0.zy : wp0.xy;
		if (is_roof) uv = wp0.xz;
		uv += vec2(seed * 3.7, seed * 1.3);
		float h = wp0.y - ground_y;
		float gr = clamp(grime + damage * 0.3, 0.0, 1.0);
		float blot = fbm(uv * 2.2);
		float streak = is_roof ? 0.0 : fbm(vec2(uv.x * 9.0, uv.y * 0.6)) * (0.6 + 0.4 * noise(vec2(uv.x * 2.0, 0.0)));
		float base_dirt = 1.0 - smoothstep(0.0, 0.55, h);
		float g = blot * 0.55 + streak * 0.55 + base_dirt * 0.55;
		float t1 = 1.08 - gr * 0.62;
		float t2 = t1 + 0.15;
		float a = gr * 0.32 + step(t1, g) * 0.3 + step(t2, g) * 0.28;
		vec3 wcol = mix(grime_color.rgb, soot_color.rgb, step(t2, g));
		a *= gr > 0.001 ? 1.0 : 0.0;
		float m = fbm(uv * 3.1 + 11.0) + (is_roof ? 0.15 : base_dirt * 0.35);
		if (moss > 0.0 && m > 1.08 - moss * 0.5) { wcol = moss_color.rgb; a = max(a, 0.55); }
		if (water_line > ground_y && !is_roof) {
			float wob = noise(vec2(uv.x * 6.0, 0.0)) * 0.03;
			float below = 1.0 - step(water_line + wob, wp0.y);
			float band = step(water_line - 0.035, wp0.y) * (1.0 - step(water_line, wp0.y));
			if (below > 0.5) { wcol = mix(wcol, water_color.rgb, 0.85); a = max(a, 0.58 + base_dirt * 0.2); }
			if (band > 0.5) { wcol = water_color.rgb * 0.5; a = 0.9; }
		}
		col = mix(col, wcol, clamp(a, 0.0, 1.0));

		// cracks - existing ones plus new ones that spread with damage
		float ck = clamp(cracks + damage * 0.95, 0.0, 1.0);
		if (ck > 0.0 && !is_roof) {
			float e = voronoi_edge(uv * vec2(2.4, 1.6));
			float gate = fbm(uv * 0.9 + 5.0) + (1.0 - smoothstep(0.0, 1.2, h)) * 0.15;
			float w = 0.022 + damage * 0.02;
			if (e < w && gate > 1.0 - ck * 0.6) col = vec3(0.09, 0.09, 0.1);
		}

		// dust settling on everything (heavier on upward faces)
		float coat = damage * (0.22 + 0.4 * clamp(n.y, 0.0, 1.0)) * (0.7 + 0.6 * noise(uv * 7.0));
		col = mix(col, dust_color.rgb, clamp(coat, 0.0, 0.8));

		ALBEDO = col;
		ROUGHNESS = roughness_value;
		SPECULAR = 0.4;
		EMISSION = emission_color * (1.0 - damage * 0.6);
	}
}
