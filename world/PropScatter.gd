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
const KENNEY := "res://assets/kenney/nature-kit/"

# path, scale (world units per model unit), count, rule. Kenney models are
# roughly 1 unit = 1 m; the Higgsfield kit is in metres too. Oversized on
# purpose so they read from the chase camera (1 world unit = 100 m).
const PROPS := [
	{"file": KENNEY + "tree_pineTallA.glb",     "scale": 0.20, "count": 900, "rule": "forest"},
	{"file": KENNEY + "tree_pineTallB.glb",     "scale": 0.20, "count": 900, "rule": "forest"},
	{"file": KENNEY + "tree_pineDefaultA.glb",  "scale": 0.22, "count": 700, "rule": "forest"},
	{"file": KENNEY + "tree_pineRoundA.glb",    "scale": 0.22, "count": 500, "rule": "forest"},
	{"file": KENNEY + "tree_default.glb",       "scale": 0.24, "count": 500, "rule": "lowland"},
	{"file": KENNEY + "tree_oak.glb",           "scale": 0.24, "count": 350, "rule": "lowland"},
	{"file": KENNEY + "plant_bushLarge.glb",    "scale": 0.22, "count": 900, "rule": "lowland"},
	{"file": KENNEY + "plant_bush.glb",         "scale": 0.22, "count": 700, "rule": "lowland"},
	{"file": KENNEY + "tree_pineSmallA.glb",    "scale": 0.20, "count": 400, "rule": "treeline"},
	{"file": KENNEY + "stump_oldTall.glb",      "scale": 0.25, "count": 150, "rule": "treeline"},
	{"file": KENNEY + "rock_largeA.glb",        "scale": 0.30, "count": 300, "rule": "slope"},
	{"file": KENNEY + "rock_largeC.glb",        "scale": 0.30, "count": 300, "rule": "slope"},
	{"file": KENNEY + "rock_smallA.glb",        "scale": 0.30, "count": 400, "rule": "slope"},
	{"file": KENNEY + "rock_tallB.glb",         "scale": 0.32, "count": 200, "rule": "ridge"},
	{"file": KENNEY + "rock_tallE.glb",         "scale": 0.32, "count": 200, "rule": "ridge"},
	{"file": KENNEY + "stone_largeD.glb",       "scale": 0.30, "count": 150, "rule": "ridge"},
	{"file": KENNEY + "tree_palmTall.glb",      "scale": 0.20, "count": 200, "rule": "beach"},
	{"file": KENNEY + "log.glb",                "scale": 0.25, "count": 150, "rule": "beach"},
	# Higgsfield kit, used where Kenney has no equivalent
	{"file": KIT + "dead_tree.glb",             "scale": 0.22, "count": 200, "rule": "treeline"},
	{"file": KIT + "rock_outcrop.glb",          "scale": 0.40, "count": 150, "rule": "ridge"},
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
	var cairn := _load_mesh(KIT + "summit_cairn.glb")
	if cairn != null:
		var mi := MeshInstance3D.new()
		mi.mesh = cairn
		mi.position = _terrain.world_pos(terrain.summit.x, terrain.summit.y)
		mi.scale = Vector3.ONE * 0.9
		add_child(mi)


## Load the first mesh found inside a GLB scene. Returns null if missing.
func _load_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("PropScatter: missing %s" % path)
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
