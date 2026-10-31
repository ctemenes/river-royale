// River ribbon: flowing water with bank foam and a per-river tint.
// UV.x runs across the ribbon (0 = left bank, 1 = right bank),
// UV.y runs along it (increases downstream), so scrolling -UV.y flows.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(0.2, 0.8, 0.8, 1.0);
uniform float flow_speed = 1.0;
uniform float foam_width = 0.3;
uniform float dead = 0.0;         // 1 = absorbed river, still and pale
uniform float glow = 0.3;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 uv = UV;
	float t = TIME * flow_speed * (1.0 - dead);
	float n1 = texture(noise_tex, vec2(uv.x * 0.6, uv.y * 0.12 - t * 0.10)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 1.1 + 0.37, uv.y * 0.22 - t * 0.19)).r;
	float n3 = texture(noise_tex, vec2(uv.x * 2.3 + 0.71, uv.y * 0.45 - t * 0.33)).r;
	float n = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;

	// bank foam: strongest at the edges, broken up by noise, streaking downstream
	float edge_dist = min(uv.x, 1.0 - uv.x);
	float bank = 1.0 - smoothstep(0.0, foam_width, edge_dist);
	float streak = smoothstep(0.42, 0.68, n2 * 0.6 + n3 * 0.4);
	float foam = clamp(bank * (0.45 + streak) + streak * 0.12, 0.0, 1.0) * (1.0 - dead * 0.8);

	vec3 deep = tint.rgb * 0.45;
	vec3 bright = tint.rgb * 1.05;
	vec3 water = mix(deep, bright, n);
	vec3 pale = vec3(0.60, 0.70, 0.74);
	water = mix(water, pale, dead);
	ALBEDO = mix(water, vec3(0.93, 0.97, 1.0), foam);
	EMISSION = tint.rgb * glow * n * (1.0 - dead) * (1.0 - foam);

	// ripple the normal so the sun breaks up along the flow
	vec3 ripple = TANGENT * (n1 - 0.5) * 0.9 + BINORMAL * (n3 - 0.5) * 0.9;
	NORMAL = normalize(NORMAL + ripple * (1.0 - dead));
	ROUGHNESS = mix(0.12, 0.6, foam + dead * 0.5);
	SPECULAR = 0.7;
}
