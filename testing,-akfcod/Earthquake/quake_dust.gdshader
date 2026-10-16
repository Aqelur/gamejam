// Soft billowing dust/smoke puff for GPUParticles3D (use on a QuadMesh).
// Camera-facing, noisy edges, darker underside and soft intersection with
// the ground/buildings so clouds don't show hard lines.
// Particle COLOR (from the process material colour/ramp) tints it and its
// alpha fades it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform float softness = 0.25;
uniform float noise_scale = 2.4;
uniform float edge_breakup = 0.6;
uniform float shade = 0.25;

varying float ang;
varying float rnd;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
	return v;
}

void vertex() {
	ang = INSTANCE_CUSTOM.x;
	rnd = fract(sin(ang * 12.9898 + 4.1) * 43758.5453);
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(UV * noise_scale + rnd * 17.0);
	float r = length(p) + (n - 0.5) * edge_breakup;
	float shape = 1.0 - smoothstep(0.3, 1.0, r);
	// un-rotate so the dark side is always at the bottom of the screen
	vec2 ps = vec2(cos(ang) * p.x + sin(ang) * p.y, -sin(ang) * p.x + cos(ang) * p.y);
	float lit = mix(1.0 - shade, 1.0 + shade * 0.35, clamp(-ps.y * 0.5 + 0.5, 0.0, 1.0));
	lit *= 0.82 + 0.36 * n;
	ALBEDO = COLOR.rgb * lit;

	float alpha = shape * COLOR.a;
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 upos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
#endif
	float scene_z = upos.z / upos.w;
	alpha *= clamp((VERTEX.z - scene_z) / softness, 0.0, 1.0);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
