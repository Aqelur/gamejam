// Low-poly mountains: per-face colours come in as vertex colours (set by
// MountainRange from the city palette); distant ranges fade into the sky haze.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 horizon_color : source_color = vec4(0.78, 0.86, 0.94, 1.0); // sky horizon
uniform float fade_start = 2200.0;
uniform float fade_end = 6500.0;
uniform float fade_max = 0.85;
// Far ranges are raised to eye level so they always fill the horizon.
uniform float rim_start = 4300.0;
uniform float rim_end = 5700.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	VERTEX.y += max(CAMERA_POSITION_WORLD.y - wp.y, 0.0) * smoothstep(rim_start, rim_end, r);
}

void fragment() {
	float haze = smoothstep(fade_start, fade_end, length(wp.xz - CAMERA_POSITION_WORLD.xz)) * fade_max;
	ALBEDO = mix(COLOR.rgb, horizon_color.rgb, haze);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
