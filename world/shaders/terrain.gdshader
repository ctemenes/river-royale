// Island terrain. Vertex colour carries the base biome tint (height + rain);
// this shader adds what makes the ground readable from a chase camera:
//   slope -> bare rock on steep faces, grass/soil on flats
//   faint contour lines every few metres of height
//   noise detail so flat areas are not a single smooth colour
//   snow above the snow line, thinning on steep faces
shader_type spatial;
render_mode cull_disabled;

uniform float sea_level_y = 4.8;        // SEA * HEIGHT_SCALE
uniform float snow_y = 20.0;            // world height where snow begins
uniform float contour_spacing = 1.5;    // world units between contour lines
uniform float contour_strength = 0.18;
uniform float rock_slope = 0.55;        // 1 - normal.y where rock takes over
uniform vec3 rock_color : source_color = vec3(0.40, 0.38, 0.35);
uniform vec3 cliff_color : source_color = vec3(0.30, 0.27, 0.25);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec2 wuv = world_pos.xz;
	float d1 = texture(noise_tex, wuv * 0.08).r;
	float d2 = texture(noise_tex, wuv * 0.35 + 0.5).r;
	float detail = (d1 - 0.5) * 0.22 + (d2 - 0.5) * 0.10;

	// slope: 0 flat .. 1 vertical
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(rock_slope - 0.15, rock_slope + 0.15, slope + (d2 - 0.5) * 0.2);
	float cliff = smoothstep(0.75, 0.95, slope);
	vec3 ground = base * (1.0 + detail);
	vec3 rockc = mix(rock_color, cliff_color, cliff) * (1.0 + detail * 0.8);
	vec3 col = mix(ground, rockc, rock);

	// snow line, blown off steep faces
	float snow = smoothstep(snow_y - 2.0, snow_y + 2.0, world_pos.y + (d1 - 0.5) * 3.0) * (1.0 - smoothstep(0.45, 0.75, slope));
	col = mix(col, vec3(0.93, 0.95, 0.97), snow);

	// contour lines: thin dark bands at fixed height intervals, fading on cliffs
	float h = world_pos.y - sea_level_y;
	float band = abs(fract(h / contour_spacing + 0.5) - 0.5) * contour_spacing;   // distance to nearest contour
	float fw = fwidth(h) * 1.2 + 0.015;
	float line = 1.0 - smoothstep(0.0, fw, band);
	col *= 1.0 - line * contour_strength * (1.0 - snow * 0.6);

	// beach wash just above the waterline
	float beach = 1.0 - smoothstep(0.0, 0.5, h);
	col = mix(col, vec3(0.80, 0.76, 0.62), beach * (1.0 - rock));

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, snow);
}
