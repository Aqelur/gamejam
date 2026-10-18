shader_type canvas_item;

uniform float glitch = 0.0;
uniform float seed = 0.0;
uniform float spread = 0.86;

void fragment() {
	float band = floor(UV.y * 36.0);
	float n = fract(sin(band * 47.13 + seed * 19.7) * 43758.5453);
	float tear = step(spread, n) * step(0.001, glitch);
	float shift = (fract(sin(band * 12.7 + seed) * 23421.631) - 0.5) * tear * 0.22;
	vec2 uv = vec2(clamp(UV.x + shift, 0.0, 1.0), UV.y);
	vec4 tex = texture(TEXTURE, uv);
	vec4 split = texture(TEXTURE, vec2(clamp(uv.x - tear * 0.018, 0.0, 1.0), uv.y));
	vec3 color = tex.rgb;
	color.r = mix(color.r, split.r, tear);
	float bar = tear * step(0.62, fract(UV.y * 140.0 + seed));
	color = mix(color, vec3(0.9, 0.93, 1.0), bar * 0.8);
	COLOR = vec4(color, tex.a);
}
