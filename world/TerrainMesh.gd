class_name TerrainMesh
extends MeshInstance3D
## Builds the island mesh from TerrainData with per-vertex colours.
## One mesh for the whole island (~37k verts at N=192), which is fine.
## Later: split into chunks + LOD, and replace vertex colours with a
## splat-mapped material using textures authored in Blender.


func build(t: TerrainData) -> void:
	var N := TerrainData.N
	var HS := TerrainData.HEIGHT_SCALE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in N:
		for x in N:
			var i := y * N + x
			var h := t.H[i]
			st.set_color(_color_for(t, x, y))
			st.set_uv(Vector2(float(x) / N, float(y) / N))
			st.add_vertex(Vector3(x, h * HS, y))

	for y in N - 1:
		for x in N - 1:
			var i := y * N + x
			# two triangles, clockwise as seen from above (Godot front face = CCW in +Y up looking down -Y... keep consistent and flip if lit wrong)
			st.add_index(i)
			st.add_index(i + N)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + N)
			st.add_index(i + N + 1)

	st.generate_normals()
	mesh = st.commit()

	material_override = Materials.terrain()


static func _color_for(t: TerrainData, x: int, y: int) -> Color:
	var i := y * TerrainData.N + x
	var h := t.H[i]
	var SEA := TerrainData.SEA
	if h <= SEA:
		var k := clampf((SEA - h) / 0.2, 0.0, 1.0)
		return Color(lerpf(0.27, 0.06, k), lerpf(0.63, 0.27, k), lerpf(0.69, 0.51, k))
	var tt := clampf((h - SEA) / (1.1 - SEA), 0.0, 1.0)
	var rain := t.RAIN[i]
	var c1 := Color(lerpf(0.46, 0.27, rain), lerpf(0.52, 0.45, rain), lerpf(0.27, 0.19, rain))  # lowland
	var c2 := Color(0.57, 0.53, 0.41)   # dry upland
	var c3 := Color(0.42, 0.41, 0.38)   # rock
	var c4 := Color(0.91, 0.93, 0.94)   # snow
	var c: Color
	if tt < 0.32:
		c = c1.lerp(c2, tt / 0.32)
	elif tt < 0.86:
		c = c2.lerp(c3, (tt - 0.32) / 0.54)
	else:
		c = c3.lerp(c4, smoothstep(0.0, 1.0, (tt - 0.86) / 0.14))
	if tt < 0.025:
		c = Color(0.80, 0.77, 0.63).lerp(c, tt / 0.025)   # beach
	return c
