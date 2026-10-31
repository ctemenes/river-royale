class_name Materials
extends RefCounted
## Shared shader materials and the noise texture they all sample.

static var _noise: NoiseTexture2D


static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 4
		n.frequency = 0.02
		n.seed = 7
		_noise = NoiseTexture2D.new()
		_noise.noise = n
		_noise.seamless = true
		_noise.width = 256
		_noise.height = 256
		_noise.generate_mipmaps = true
	return _noise


static func river(tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/river.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("flow_speed", 1.0)
	m.set_shader_parameter("dead", 0.0)
	return m


static func bank() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.19, 0.15)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func sea() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/sea.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	return m


static func terrain() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/terrain.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("sea_level_y", TerrainData.SEA * TerrainData.HEIGHT_SCALE)
	m.set_shader_parameter("snow_y", 0.95 * TerrainData.HEIGHT_SCALE)
	m.set_shader_parameter("contour_spacing", TerrainData.HEIGHT_SCALE * 0.06)
	return m
