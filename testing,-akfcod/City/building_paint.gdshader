// Repaints the grey/white facades of the Kenney city buildings with a colour
// from the city palette. Applied as material_override by weathering.gd.
// Windows (saturated blue), brick, wood and dark trim keep their kit colours,
// and the texture's light-to-dark gradients are preserved so the shading still reads.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 paint_color : source_color = vec4(1.0, 0.75, 0.27, 1.0);
// secondary colour used on mid-grey trim (ground floors, ledges)
uniform vec4 trim_color : source_color = vec4(0.8, 0.33, 0.31, 1.0);
uniform float paint_strength : hint_range(0.0, 1.0) = 0.9;
uniform float trim_strength : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float mx = max(tex.r, max(tex.g, tex.b));
	float mn = min(tex.r, min(tex.g, tex.b));
	float sat = mx > 0.0001 ? (mx - mn) / mx : 0.0;
	float lum = dot(tex, vec3(0.299, 0.587, 0.114));
	// only greys / near-whites get painted
	float grey = 1.0 - smoothstep(0.22, 0.32, sat);

	// light facade walls -> main palette colour, keeping the texture's gradient
	float wall = grey * smoothstep(0.55, 0.72, lum);
	vec3 wall_col = paint_color.rgb * clamp(lum / 0.88, 0.0, 1.1);

	// mid-grey trim -> darker version of the trim colour
	float trim = grey * smoothstep(0.26, 0.34, lum) * (1.0 - wall);
	vec3 trim_col = trim_color.rgb * clamp(lum * 1.35, 0.0, 1.0);

	vec3 col = tex;
	col = mix(col, trim_col, trim * trim_strength);
	col = mix(col, wall_col, wall * paint_strength);

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.4;
}
