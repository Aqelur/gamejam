// Expanding seismic shock ring drawn on a big flat plane over the city.
// CityEarthquake animates `radius` outward from the epicenter.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 center = vec3(0.0);
uniform float radius = 0.0;
uniform float width = 1.2;
uniform float strength = 1.0;
uniform vec4 color : source_color = vec4(0.5, 0.4, 0.3, 0.9);
uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);

varying vec3 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 rel = wp.xz - center.xz;
	float d = length(rel);
	float ang = atan(rel.y, rel.x);
	float wob = (noise(vec2(ang * 6.0, radius * 0.5)) - 0.5) * width * 0.8;
	float x = d - radius + wob;
	// leading crest
	float crest = 1.0 - smoothstep(0.0, width * 0.5, abs(x));
	// trailing ripples
	float behind = step(x, 0.0);
	float ripple = behind * (0.5 + 0.5 * cos(x * 6.2832 / width)) * exp(x / (width * 2.5)) * 0.55;
	float n = noise(wp.xz * 3.0) * 0.6 + 0.4;
	float a = (crest + ripple) * n * strength;
	vec3 col = mix(color.rgb, glow_color.rgb, crest * 0.35);
	ALBEDO = col;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
