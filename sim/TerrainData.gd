class_name TerrainData
extends RefCounted
## Procedural island terrain with guaranteed drainage.
##
## Pure data, no nodes: the same seed produces the same island on every
## machine, which is what lets the server and every client agree on the map.
##
## Arrays are row-major, index = y * N + x.
##   H     raw height 0..~1.1
##   W     depression-filled surface (every land cell drains to the sea)
##   DIST  chamfer distance to the nearest sea cell, in cells
##   RAIN  0..1 wetness field (greener = more water gained per second)
##   FLOW  steepest-descent direction on W, unit vector per cell

const N := 192                 # cells per side
const SEA := 0.30              # sea level in height units
const CELL_KM := 0.1           # 100 m per cell -> ~19 km island
const HEIGHT_SCALE := 24.0     # world units per height unit (vertical exaggeration)

var H := PackedFloat32Array()
var W := PackedFloat32Array()
var DIST := PackedFloat32Array()
var RAIN := PackedFloat32Array()
var FLOW_DX := PackedFloat32Array()
var FLOW_DY := PackedFloat32Array()
var summit := Vector2i.ZERO
var seed_used := 0


func generate(world_seed: int) -> void:
	seed_used = world_seed
	_build_heights(world_seed)
	_priority_flood()
	_distance_to_sea()
	_flow_field()


# ---------------------------------------------------------------- heights
func _build_heights(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var fbm := FastNoiseLite.new()
	fbm.seed = world_seed
	fbm.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fbm.fractal_type = FastNoiseLite.FRACTAL_FBM
	fbm.fractal_octaves = 6
	fbm.frequency = 3.0 / N

	var ridged := FastNoiseLite.new()
	ridged.seed = world_seed + 1
	ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridged.fractal_octaves = 4
	ridged.frequency = 4.0 / N

	var coast := FastNoiseLite.new()
	coast.seed = world_seed + 2
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.fractal_octaves = 3
	coast.frequency = 1.0

	var rain_noise := FastNoiseLite.new()
	rain_noise.seed = world_seed + 3
	rain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rain_noise.fractal_octaves = 3
	rain_noise.frequency = 5.0 / N

	H.resize(N * N)
	RAIN.resize(N * N)

	var cx := N * 0.5 + rng.randf_range(-0.1, 0.1) * N
	var cy := N * 0.5 + rng.randf_range(-0.1, 0.1) * N
	var best := -1.0

	for y in N:
		for x in N:
			var f: float = (fbm.get_noise_2d(x, y) + 1.0) * 0.5        # 0..1
			var r: float = (ridged.get_noise_2d(x, y) + 1.0) * 0.5     # 0..1, ridges near 1
			var dx := (x - cx) / N
			var dy := (y - cy) / N
			var ang := atan2(dy, dx)
			var wob := 0.54 + 0.12 * coast.get_noise_2d(cos(ang) * 2.0 + 5.0, sin(ang) * 2.0 + 5.0)
			var d := sqrt(dx * dx + dy * dy) / wob
			var island := clampf(1.0 - d * d, 0.0, 1.0)
			var peak := exp(-(dx * dx + dy * dy) * 34.0)
			var h := (0.44 + 0.38 * f + 0.3 * r * r) * island + 0.34 * peak * island
			var i := y * N + x
			H[i] = h
			RAIN[i] = (rain_noise.get_noise_2d(x, y) + 1.0) * 0.5
			if h > best:
				best = h
				summit = Vector2i(x, y)


# ------------------------------------------------- depression filling
# Priority-flood (Barnes et al. 2014). Seeds the queue with every sea cell and
# every border cell, then grows inward always taking the lowest cell. Each
# newly reached cell gets max(H, neighbour W + eps), so the filled surface W
# strictly descends to the sea from everywhere. O(n log n), one pass.
const EPS := 0.0012

var _hk := PackedFloat32Array()   # heap keys
var _hv := PackedInt32Array()     # heap values (cell index)


func _heap_push(k: float, v: int) -> void:
	_hk.append(k)
	_hv.append(v)
	var i := _hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= _hk[i]:
			break
		var tk := _hk[p]; _hk[p] = _hk[i]; _hk[i] = tk
		var tv := _hv[p]; _hv[p] = _hv[i]; _hv[i] = tv
		i = p


func _heap_pop() -> int:
	var top := _hv[0]
	var last := _hk.size() - 1
	_hk[0] = _hk[last]
	_hv[0] = _hv[last]
	_hk.resize(last)
	_hv.resize(last)
	var i := 0
	var n := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and _hk[l] < _hk[m]:
			m = l
		if r < n and _hk[r] < _hk[m]:
			m = r
		if m == i:
			break
		var tk := _hk[m]; _hk[m] = _hk[i]; _hk[i] = tk
		var tv := _hv[m]; _hv[m] = _hv[i]; _hv[i] = tv
		i = m
	return top


func _priority_flood() -> void:
	W.resize(N * N)
	var visited := PackedByteArray()
	visited.resize(N * N)
	_hk.clear()
	_hv.clear()
	for y in N:
		for x in N:
			var i := y * N + x
			if H[i] <= SEA or x == 0 or y == 0 or x == N - 1 or y == N - 1:
				W[i] = H[i]
				visited[i] = 1
				_heap_push(H[i], i)
	while _hk.size() > 0:
		var c := _heap_pop()
		var cx := c % N
		var cy := c / N
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var xx := cx + dx
				var yy := cy + dy
				if xx < 0 or yy < 0 or xx >= N or yy >= N:
					continue
				var n := yy * N + xx
				if visited[n] == 1:
					continue
				visited[n] = 1
				var step := EPS * (1.414 if (dx != 0 and dy != 0) else 1.0)
				W[n] = maxf(H[n], W[c] + step)
				_heap_push(W[n], n)


# --------------------------------------------------- distance to sea
func _distance_to_sea() -> void:
	DIST.resize(N * N)
	for i in N * N:
		DIST[i] = 0.0 if W[i] <= SEA else 1.0e9
	for p in 2:
		for k in N * N:
			var i: int = (N * N - 1 - k) if p == 1 else k
			var x := i % N
			var y := i / N
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= N or yy >= N:
						continue
					var d: float = DIST[yy * N + xx] + (1.414 if (dx != 0 and dy != 0) else 1.0)
					if d < DIST[i]:
						DIST[i] = d


# -------------------------------------------------------- flow field
func _flow_field() -> void:
	FLOW_DX.resize(N * N)
	FLOW_DY.resize(N * N)
	for y in N:
		for x in N:
			var i := y * N + x
			var bx := 0.0
			var by := 0.0
			var bd := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= N or yy >= N:
						continue
					var drop: float = (W[i] - W[yy * N + xx]) / (1.414 if (dx != 0 and dy != 0) else 1.0)
					if drop > bd:
						bd = drop
						bx = dx
						by = dy
			var l := sqrt(bx * bx + by * by)
			if l > 0.0:
				FLOW_DX[i] = bx / l
				FLOW_DY[i] = by / l


# ---------------------------------------------------------- sampling
func cell_index(x: float, y: float) -> int:
	return clampi(roundi(y), 0, N - 1) * N + clampi(roundi(x), 0, N - 1)


func sample_w(x: float, y: float) -> float:
	var xi := clampi(floori(x), 0, N - 2)
	var yi := clampi(floori(y), 0, N - 2)
	var xf := x - xi
	var yf := y - yi
	var i := yi * N + xi
	var top := lerpf(W[i], W[i + 1], xf)
	var bot := lerpf(W[i + N], W[i + N + 1], xf)
	return lerpf(top, bot, yf)


func sample_h(x: float, y: float) -> float:
	var xi := clampi(floori(x), 0, N - 2)
	var yi := clampi(floori(y), 0, N - 2)
	var xf := x - xi
	var yf := y - yi
	var i := yi * N + xi
	var top := lerpf(H[i], H[i + 1], xf)
	var bot := lerpf(H[i + N], H[i + N + 1], xf)
	return lerpf(top, bot, yf)


func is_sea(x: float, y: float) -> bool:
	return H[cell_index(x, y)] <= SEA


func km_to_sea(x: float, y: float) -> float:
	return DIST[cell_index(x, y)] * CELL_KM


## Cell coordinates -> world position on the filled surface (lake level in basins).
func world_pos(x: float, y: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, sample_w(x, y) * HEIGHT_SCALE + lift, y)
