class_name RiverRenderer
extends Node3D
## Draws every river as a ribbon mesh along its path, plus a head marker and
## a name label. Ribbons sit on the filled surface W, so they lie flat across
## lakes instead of diving into the basin floor.
##
## This is the first thing to make beautiful: swap the StandardMaterial for a
## flowing-water shader (scrolling normal map, foam at the edges, emissive
## tint per river) once the gameplay is locked.

const LIFT := 0.12
const LABEL_RANGE := 22.0
const REBUILD_INTERVAL := 0.2

var _sim: RiverSim
var _terrain: TerrainData
var _ribbons: Array[MeshInstance3D] = []
var _heads: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _materials: Array[ShaderMaterial] = []
var _banks: Array[MeshInstance3D] = []
var _bank_mat: StandardMaterial3D
var _last_count: PackedInt32Array = PackedInt32Array()
var _timer := 0.0
var _player_id := 0


func setup(sim: RiverSim, terrain: TerrainData, player_id: int) -> void:
	_sim = sim
	_terrain = terrain
	_player_id = player_id
	for child in get_children():
		child.queue_free()
	_ribbons.clear()
	_heads.clear()
	_labels.clear()
	_materials.clear()
	_banks.clear()
	_bank_mat = Materials.bank()
	_last_count.resize(sim.rivers.size())

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.5
	head_mesh.height = 1.0

	for r in sim.rivers:
		var mat := Materials.river(r.color)
		_materials.append(mat)

		var bank := MeshInstance3D.new()
		bank.material_override = _bank_mat
		add_child(bank)
		_banks.append(bank)

		var mi := MeshInstance3D.new()
		mi.material_override = mat
		add_child(mi)
		_ribbons.append(mi)

		var head := MeshInstance3D.new()
		head.mesh = head_mesh
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color.WHITE if r.id == player_id else r.color
		hm.emission_enabled = true
		hm.emission = hm.albedo_color
		hm.emission_energy_multiplier = 1.5
		head.material_override = hm
		add_child(head)
		_heads.append(head)

		var lbl := Label3D.new()
		lbl.text = r.display_name
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.0009
		lbl.font_size = 40
		lbl.outline_size = 10
		lbl.modulate = Color(0.22, 0.84, 0.82) if r.id == player_id else Color.WHITE
		add_child(lbl)
		_labels.append(lbl)


func update(dt: float) -> void:
	_timer += dt
	var rebuild := _timer >= REBUILD_INTERVAL
	if rebuild:
		_timer = 0.0
	var player := _sim.rivers[_player_id]
	var ppos := Vector2(player.x, player.y)

	for r in _sim.rivers:
		var i := r.id
		var head := _heads[i]
		var lbl := _labels[i]
		var active := r.alive and not r.done
		head.visible = active
		if active:
			var rad := r.radius()
			head.position = _terrain.world_pos(r.x, r.y, LIFT + rad * 0.2)
			head.scale = Vector3.ONE * maxf(0.6, rad * 1.4)
			var near := Vector2(r.x, r.y).distance_to(ppos) < LABEL_RANGE
			lbl.visible = near or i == _player_id
			if lbl.visible:
				lbl.position = head.position + Vector3(0, 1.2 + rad, 0)
				if i != _player_id:
					var mark := "▲ " if r.vol > player.vol * RiverSim.ABSORB_RATIO else ("▽ " if r.vol * RiverSim.ABSORB_RATIO < player.vol else "= ")
					lbl.text = mark + r.display_name
					lbl.modulate = Color(1.0, 0.55, 0.5) if mark == "▲ " else Color.WHITE
		else:
			lbl.visible = false

		if not r.alive and float(_materials[i].get_shader_parameter("dead")) < 0.5:
			# uniform change only: no shader recompile, which some drivers do not survive
			_materials[i].set_shader_parameter("dead", 1.0)
		elif active:
			_materials[i].set_shader_parameter("flow_speed", 1.0 + minf(1.5, r.slope) * 1.2 + (0.8 if r.surging() else 0.0))

		if rebuild and (active or _last_count[i] != r.path.size()):
			_build_ribbon(_ribbons[i], r, 1.0, LIFT)
			_build_ribbon(_banks[i], r, 1.7, LIFT * 0.4)
			_last_count[i] = r.path.size()


func _build_ribbon(mi: MeshInstance3D, r: RiverSim.River, width_mul: float, lift: float) -> void:
	var p := r.path
	var n := p.size()
	if n < 2:
		mi.mesh = null
		return
	var half := maxf(0.18, r.radius() * 0.5) * (0.5 if not r.alive else 1.0) * width_mul
	# left/right edge positions for every path point
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	left.resize(n)
	right.resize(n)
	for k in n:
		var prev := p[maxi(k - 1, 0)]
		var next := p[mini(k + 1, n - 1)]
		var dir := (next - prev)
		if dir.length_squared() < 0.0001:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		# taper: thin at the source, full width near the head
		var w := half * clampf(0.25 + float(k) / maxf(1.0, n * 0.6), 0.3, 1.0)
		var a := p[k] + perp * w
		var b := p[k] - perp * w
		left[k] = _terrain.world_pos(a.x, a.y, lift)
		right[k] = _terrain.world_pos(b.x, b.y, lift)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		st.set_uv(Vector2(0.0, float(k) * 0.5))
		st.add_vertex(left[k])
		st.set_uv(Vector2(1.0, float(k) * 0.5))
		st.add_vertex(right[k])
	for k in n - 1:
		var l0 := k * 2
		var r0 := k * 2 + 1
		var l1 := k * 2 + 2
		var r1 := k * 2 + 3
		st.add_index(l0)
		st.add_index(r0)
		st.add_index(l1)
		st.add_index(r0)
		st.add_index(r1)
		st.add_index(l1)
	st.generate_normals()
	st.generate_tangents()
	mi.mesh = st.commit()
