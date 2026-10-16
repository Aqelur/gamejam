// Flat, low-poly beach ground: grass strip along the river, dry sand,
// darker wet sand right at the waterline. Colours come from the city palette.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_color : source_color = vec4(0.380, 0.796, 0.545, 1.0); // palette mint (same as city ground)
uniform vec4 grass_edge_color : source_color = vec4(0.129, 0.553, 0.427, 1.0); // palette deep green
uniform vec4 sand_color : source_color = vec4(0.984, 0.890, 0.765, 1.0);  // palette cream
uniform vec4 sand_shade : source_color = vec4(0.965, 0.835, 0.660, 1.0);  // palette warm sand
uniform vec4 wet_color : source_color = vec4(0.870, 0.690, 0.505, 1.0);   // palette tan
uniform vec4 water_shallow : source_color = vec4(0.47, 0.86, 0.86, 1.0);
uniform vec4 water_deep : source_color = vec4(0.345, 0.420, 0.800, 1.0);
uniform float water_y = -12.6;
uniform float land_y = -1.94;
uniform float wet_height = 1.8;
uniform float grass_edge_z = 430.0;

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
	// Soft patches of slightly warmer sand, kept as flat colour blobs.
	float n = noise(wp.xz * 0.018) * 0.7 + noise(wp.xz * 0.05) * 0.3;
	vec3 col = mix(sand_color.rgb, sand_shade.rgb, step(0.6, n) * 0.8);

	// Wet sand band + a thin high-tide line just above it.
	float above = wp.y - water_y;
	col = mix(col, wet_color.rgb, 1.0 - smoothstep(wet_height * 0.75, wet_height, above));
	float tide = 1.0 - smoothstep(0.0, 0.18, abs(above - wet_height * 1.25));
	col = mix(col, wet_color.rgb, tide * 0.45);

	// Grass strip along the river, with a wavy dune edge.
	float gz = grass_edge_z + 7.0 * sin(wp.x / 41.0) + 4.0 * sin(wp.x / 13.0 + 1.7);
	if (wp.y > land_y - 0.3 && wp.z < gz) {
		col = grass_color.rgb;
		if (wp.z > gz - 2.2) col = grass_edge_color.rgb;
	}

	// Below sea level the ground takes on the water's colour, so the cut-away
	// edge of the sea reads as a block of water.
	float under = water_y - wp.y;
	if (under > 0.0) {
		vec3 wcol = mix(water_shallow.rgb, water_deep.rgb, smoothstep(2.0, 20.0, under));
		col = mix(col, wcol, smoothstep(0.0, 6.0, under) * 0.9);
	}

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
