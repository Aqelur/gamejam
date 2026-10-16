// Stylised ocean: clear turquoise shallows over the sand, deepening to the
// city's blue, with foam lapping the shore and gentle swell lines.
// The far edge bends up to eye level so the sea always reaches the horizon.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.47, 0.86, 0.86, 1.0);
uniform vec4 mid_color : source_color = vec4(0.416, 0.588, 0.843, 1.0);  // palette blue
uniform vec4 deep_color : source_color = vec4(0.345, 0.420, 0.800, 1.0); // palette indigo
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.86, 0.94, 1.0); // sky horizon
uniform float shallow_depth = 6.0;
uniform float deep_depth = 24.0;
uniform float shore_foam = 0.9;
uniform float wave_speed = 0.16;
uniform float wave_spacing = 4.2;
// The sea is not drawn north of this Z (keeps it out of the river)...
uniform float north_limit = 389.0;
// ...nor north of river_edge_z between these X values, where the river is.
uniform float river_edge_z = 400.5;
uniform vec2 river_x = vec2(-793.0, 823.0);
uniform float fade_start = 1800.0;
uniform float fade_end = 5200.0;
uniform float rim_start = 3200.0;
uniform float rim_end = 5600.0;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Lift the far sea up to eye level so it meets the horizon.
	float r = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float lift = max(CAMERA_POSITION_WORLD.y - wp.y, 0.0) * smoothstep(rim_start, rim_end, r);
	VERTEX.y += lift;
}

void fragment() {
	if (wp.z < north_limit || (wp.z < river_edge_z && wp.x > river_x.x && wp.x < river_x.y)) discard;

	// Water depth under this point (vertical), from the depth buffer.
	float raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 floor_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 surf = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float depth = surf.y - floor_pos.y;
	if (!(depth >= 0.0) || depth > 1000.0) depth = 1000.0;

	vec3 col = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.0, shallow_depth, depth));
	col = mix(col, deep_color.rgb, smoothstep(shallow_depth, deep_depth, depth));
	float alpha = mix(0.6, 1.0, smoothstep(0.0, shallow_depth * 1.6, depth));

	// Foam: a ring hugging the shore plus lines rolling in towards it.
	float warp = noise(wp.xz * 0.012) * 1.4 + noise(wp.xz * 0.05) * 0.35;
	float edge = 1.0 - smoothstep(shore_foam * 0.6, shore_foam, depth);
	float w = fract(depth / wave_spacing + TIME * wave_speed + warp);
	float roll = step(0.86, w) * (1.0 - smoothstep(wave_spacing * 0.9, wave_spacing * 2.2, depth));
	roll *= step(0.35, noise(wp.xz * 0.03 + vec2(TIME * 0.05, 0.0)));
	float foam = max(edge, roll * 0.85);

	// Little white wave crests dotted over open water.
	vec2 cp = vec2(wp.x * 0.035, wp.z * 0.16 - TIME * 0.35);
	float crest = step(0.92, noise(cp + warp)) * step(0.6, noise(wp.xz * 0.006 + vec2(0.0, TIME * 0.02)));
	float swell = crest * smoothstep(deep_depth * 0.6, deep_depth, depth) * 0.55;

	col = mix(col, foam_color.rgb, max(foam, swell));
	alpha = max(alpha, foam);

	// Blend into the sky haze far away.
	float dist = length(surf - CAMERA_POSITION_WORLD);
	float haze = smoothstep(fade_start, fade_end, dist);
	col = mix(col, horizon_color.rgb, haze);
	alpha = mix(alpha, 1.0, haze);

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.08, 0.6, foam);
	SPECULAR = 0.6;
}
