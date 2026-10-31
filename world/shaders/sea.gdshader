// Sea plane: slow swell, shoreline foam from depth difference, deep-to-shallow colour.
shader_type spatial;
render_mode depth_draw_always;

uniform vec4 deep_color : source_color = vec4(0.03, 0.18, 0.30, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.55, 0.62, 1.0);
uniform float foam_depth = 1.2;
uniform float fade_depth = 6.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wuv = world_pos.xz * 0.02;
	float t = TIME * 0.05;
	float n1 = texture(noise_tex, wuv + vec2(t, t * 0.6)).r;
	float n2 = texture(noise_tex, wuv * 2.7 - vec2(t * 0.8, t * 0.3)).r;
	float n = n1 * 0.6 + n2 * 0.4;

	// how much water is between the surface and the seabed behind it
	float scene_depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float frag_depth = -(VIEW_MATRIX * vec4(world_pos, 1.0)).z;
	float water_depth = max(0.0, scene_depth - frag_depth);
	float shallow = 1.0 - clamp(water_depth / fade_depth, 0.0, 1.0);
	float foam = (1.0 - smoothstep(0.0, foam_depth, water_depth)) * smoothstep(0.35, 0.65, n2);

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, shallow * 0.8 + n * 0.1);
	ALBEDO = mix(col, vec3(0.95), foam);
	ALPHA = mix(0.88, 0.55, shallow) + foam * 0.3;
	vec3 ripple = TANGENT * (n1 - 0.5) * 0.35 + BINORMAL * (n2 - 0.5) * 0.35;
	NORMAL = normalize(NORMAL + ripple);
	ROUGHNESS = 0.08 + foam * 0.6;
	SPECULAR = 0.8;
}
