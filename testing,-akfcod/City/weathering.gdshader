// Stylised weathering overlay for the Kenney-style city.
// Applied as material_overlay by weathering.gd - adds grime, rain streaks,
// structural cracks, moss and a flood-water stain line, posterised so it keeps
// the flat low-poly look of the kit.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform float grime : hint_range(0.0, 1.0) = 0.5;
uniform float cracks : hint_range(0.0, 1.0) = 0.3;
uniform float moss : hint_range(0.0, 1.0) = 0.0;
uniform float water_line = -100.0;     // world height of the flood stain (disabled when below ground)
uniform float ground_y = 0.0;
uniform float seed = 0.0;
uniform vec4 grime_color : source_color = vec4(0.40, 0.34, 0.28, 1.0);
uniform vec4 soot_color : source_color = vec4(0.17, 0.17, 0.19, 1.0);
uniform vec4 water_color : source_color = vec4(0.42, 0.34, 0.25, 1.0);
uniform vec4 moss_color : source_color = vec4(0.16, 0.56, 0.43, 1.0);

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
// distance to the nearest voronoi cell border -> jagged crack network
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

void fragment() {
	vec3 n = normalize(wn);
	bool is_roof = n.y > 0.7;
	vec2 uv = abs(n.x) > abs(n.z) ? wp.zy : wp.xy;
	if (is_roof) uv = wp.xz;
	uv += vec2(seed * 3.7, seed * 1.3);
	float h = wp.y - ground_y;

	// --- grime: blotches + vertical rain streaks + dirt rising from the ground
	float blot = fbm(uv * 2.2);
	float streak = is_roof ? 0.0 : fbm(vec2(uv.x * 9.0, uv.y * 0.6)) * (0.6 + 0.4 * noise(vec2(uv.x * 2.0, 0.0)));
	float base_dirt = 1.0 - smoothstep(0.0, 0.55, h);
	float g = blot * 0.55 + streak * 0.55 + base_dirt * 0.55;
	float t1 = 1.08 - grime * 0.62;
	float t2 = t1 + 0.15;
	// overall dull wash so worn districts read as dingy even from far away
	float a = grime * 0.32 + step(t1, g) * 0.3 + step(t2, g) * 0.28;
	vec3 col = mix(grime_color.rgb, soot_color.rgb, step(t2, g));
	a *= grime > 0.001 ? 1.0 : 0.0;

	// --- moss on lower walls and roofs
	float m = fbm(uv * 3.1 + 11.0) + (is_roof ? 0.15 : base_dirt * 0.35);
	if (moss > 0.0 && m > 1.08 - moss * 0.5) { col = moss_color.rgb; a = max(a, 0.55); }

	// --- flood stain: darker tide-mark band + muddy tint below it
	if (water_line > ground_y && !is_roof) {
		float below = 1.0 - step(water_line, wp.y);
		float band = step(water_line - 0.035, wp.y) * below;
		float wob = noise(vec2(uv.x * 6.0, 0.0)) * 0.03;
		below = 1.0 - step(water_line + wob, wp.y);
		if (below > 0.5) { col = mix(col, water_color.rgb, 0.85); a = max(a, 0.58 + base_dirt * 0.2); }
		if (band > 0.5) { col = water_color.rgb * 0.5; a = 0.9; }
	}

	// --- structural cracks on walls (jagged voronoi borders, gated by noise)
	if (cracks > 0.0 && !is_roof) {
		float e = voronoi_edge(uv * vec2(2.4, 1.6));
		float gate = fbm(uv * 0.9 + 5.0) + (1.0 - smoothstep(0.0, 1.2, h)) * 0.15;
		if (e < 0.022 && gate > 1.0 - cracks * 0.55) { col = vec3(0.09, 0.09, 0.1); a = 0.92; }
	}

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 1.0;
}
