class_name PropScatter
extends Node3D
## Scatters the asset kit across the island by terrain rules, using one
## MultiMeshInstance3D per prop so 10k instances cost one draw call each.
##
## Expects GLBs in res://assets/kit/ (see assets/README.md). Any missing file
## is skipped with a warning, so the game runs with or without the kit.
##
## Scale: 1 world unit = 100 m, so real-size props would be invisible. Props
## are deliberately oversized (a "40 m" pine) for readability from the chase
## camera; tune PROP_SCALE per prop by eye.

const KIT := "res://assets/kit/"

# name, scale (world units per model metre), count, rule
const PROPS := [
	{"file": "pine_tree",    "scale": 0.28, "count": 2600, "rule": "forest"},
	{"file": "shrub",        "scale": 0.18, "count": 1800, "rule": "lowland"},
	{"file": "boulder",      "scale": 0.45, "count": 900,  "rule": "slope"},
	{"file": "rock_outcrop", "scale": 0.40, "count": 350,  "rule": "ridge"},
	{"file": "dead_tree",    "scale": 0.22, "count": 400,  "rule": "treeline"},
	{"file": "driftwood",    "scale": 0.30, "count": 250,  "rule": "beach"},
]

var _terrain: TerrainData
var _rng := RandomNumberGenerator.new()


func build(terrain: TerrainData, world_seed: int) -> void:
	_terrain = terrain
	_rng.seed = world_seed + 99
	for child in get_children():
		child.queue_free()

	for p in PROPS:
		var mesh := _load_mesh(p["file"])
		if mesh == null:
			continue
		var transforms := _place(p["rule"], p["count"], p["scale"])
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = p["file"]
		add_child(mmi)

	# one cairn on the summit
	var cairn := _load_mesh("summit_cairn")
	if cairn != null:
		var mi := MeshInstance3D.new()
		mi.mesh = cairn
		mi.position = _terrain.world_pos(terrain.summit.x, terrain.summit.y)
		mi.scale = Vector3.ONE * 0.9
		add_child(mi)


## Load the first mesh found inside a GLB scene. Returns null if missing.
func _load_mesh(name: String) -> Mesh:
	var path := KIT + name + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("PropScatter: missing %s (drop the asset kit into assets/kit/)" % path)
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var inst := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [inst]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.queue_free()
	return found


func _place(rule: String, count: int, scale: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var N := TerrainData.N
	var tries := 0
	while out.size() < count and tries < count * 12:
		tries += 1
		var x := _rng.randf_range(2.0, N - 3.0)
		var y := _rng.randf_range(2.0, N - 3.0)
		var i := _terrain.cell_index(x, y)
		var h := _terrain.H[i]
		if h <= TerrainData.SEA:
			continue
		var t := (h - TerrainData.SEA) / (1.1 - TerrainData.SEA)   # 0 coast .. 1 summit
		var rain := _terrain.RAIN[i]
		var slope := _slope(x, y)
		var lake := _terrain.W[i] > h + 0.003
		if lake:
			continue
		var ok := false
		match rule:
			"forest":   ok = t > 0.05 and t < 0.5 and rain > 0.45 and slope < 0.06 and _rng.randf() < rain
			"lowland":  ok = t > 0.03 and t < 0.35 and slope < 0.05
			"slope":    ok = t > 0.15 and slope > 0.04
			"ridge":    ok = t > 0.45 and slope > 0.06
			"treeline": ok = t > 0.45 and t < 0.7 and slope < 0.08
			"beach":    ok = t < 0.03
		if not ok:
			continue
		var pos := _terrain.world_pos(x, y, -0.02)
		var s := scale * _rng.randf_range(0.75, 1.3)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		out.append(Transform3D(basis, pos))
	return out


func _slope(x: float, y: float) -> float:
	var e := 1.0
	var dx := _terrain.sample_h(x + e, y) - _terrain.sample_h(x - e, y)
	var dy := _terrain.sample_h(x, y + e) - _terrain.sample_h(x, y - e)
	return sqrt(dx * dx + dy * dy) * 0.5
