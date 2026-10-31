class_name RiverSim
extends RefCounted
## The match simulation. Pure logic: no nodes, no rendering.
##
## Runs identically on a headless server and on clients. Inputs are a steer
## value per river (-1..1). Everything else is deterministic from the seed.
## Keep it that way: no Node access, no randf() outside the seeded rng.

const RIVER_COUNT := 80
const SPRING_COUNT := 110
const GRACE_SECONDS := 20.0      # no absorption before this
const ABSORB_RATIO := 1.5        # must be this much bigger to absorb
const SURGE_TIME := 1.5
const SURGE_COOLDOWN := 6.0
const SURGE_COST := 0.04         # fraction of volume
const SURGE_SPEED := 1.8
const START_VOLUME_MIN := 8000.0
const START_VOLUME_MAX := 14000.0

const NAMES := [
	"mizu_chan", "rio_loco", "Wasserfall", "torrent99", "drip.exe", "ruisseau_", "xX_Delta_Xx",
	"LaCascade", "brookie", "nile_jr", "meander", "oxbow", "splashzone", "rapids", "flowstate",
	"creek_t", "wadi", "burn_lad", "beck", "gully", "fjordan", "tributary", "sluice", "runnel",
	"freshet", "silt_king", "aqua_vitae", "estuary", "rillboi", "cataract", "headwater",
	"floodplain", "alluvium", "riparian", "watershed", "drizzle", "monsoon_", "spate", "torrente",
	"arroyo", "bayou_bb", "kill_van", "gill_", "leat", "mill_race", "overflow", "ford", "weir",
	"eddy_", "confluence", "moss_run", "glacial", "snowmelt", "thaw", "downpour", "sleet", "sump",
	"drainpipe", "hydro_", "riverdance", "wet_boi", "soak", "puddle_max", "gush", "trickle", "seep",
	"bogwater", "marsh", "quagmire", "brine", "tidal", "surge_", "current", "undertow", "whirlpool",
	"channel", "strait", "inlet", "lagoon", "cove_",
]


class River:
	var id := 0
	var display_name := ""
	var is_bot := true
	var x := 0.0
	var y := 0.0
	var hx := 0.0          # heading (unit)
	var hy := 1.0
	var vol := 10000.0     # litres
	var path := PackedVector2Array()
	var alive := true
	var done := false      # reached the sea
	var eaten := 0
	var length := 0.0      # cells travelled
	var color := Color.WHITE
	var steer := 0.0       # -1..1, set each tick (player input or bot AI)
	var target_spring := -1
	var retarget := 0.0
	var stuck := 0.0
	var killer := ""
	var aggression := 0.0  # bots: 0 = farmer, 1 = hunter
	var slope := 0.0       # last measured grade, 0 flat .. 1.5 very steep
	var want_surge := false  # input: set true to trigger a surge this tick
	var surge_timer := 0.0
	var surge_cd := 0.0

	func surging() -> bool:
		return surge_timer > 0.0

	func can_surge() -> bool:
		return surge_cd <= 0.0 and not surging()

	func radius() -> float:
		return 0.25 + sqrt(vol) / 900.0


class Spring:
	var x := 0.0
	var y := 0.0
	var vol := 0.0
	var taken := false


signal absorbed(big: River, small: River)
signal spring_taken(river: River, spring: Spring)
signal reached_sea(river: River)

var terrain: TerrainData
var rivers: Array[River] = []
var springs: Array[Spring] = []
var elapsed := 0.0
var finished_count := 0
var _rng := RandomNumberGenerator.new()


func setup(t: TerrainData, world_seed: int, player_names: Array[String]) -> void:
	terrain = t
	_rng.seed = world_seed
	elapsed = 0.0
	finished_count = 0
	rivers.clear()
	springs.clear()

	var pool := NAMES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	for i in RIVER_COUNT:
		var r := River.new()
		r.id = i
		if i < player_names.size():
			r.display_name = player_names[i]
			r.is_bot = false
		else:
			r.display_name = pool[i % pool.size()]
			r.is_bot = true
		var a := _rng.randf() * TAU
		var dist := 4.0 + _rng.randf() * 14.0
		r.x = terrain.summit.x + cos(a) * dist
		r.y = terrain.summit.y + sin(a) * dist
		r.hx = cos(a)
		r.hy = sin(a)
		r.vol = _rng.randf_range(START_VOLUME_MIN, START_VOLUME_MAX)
		r.path.append(Vector2(r.x, r.y))
		r.color = Color.from_hsv(_rng.randf(), 0.7, 0.95) if r.is_bot else Color(0.22, 0.84, 0.82)
		# a few hunters, most farmers
		var a := _rng.randf()
		r.aggression = a * a
		rivers.append(r)

	var tries := 0
	while springs.size() < SPRING_COUNT and tries < 5000:
		tries += 1
		var sx := _rng.randf() * TerrainData.N
		var sy := _rng.randf() * TerrainData.N
		var ci := terrain.cell_index(sx, sy)
		var far_from_summit := Vector2(sx, sy).distance_to(Vector2(terrain.summit)) > 8.0
		if terrain.H[ci] > TerrainData.SEA + 0.02 and terrain.DIST[ci] > 6.0 and far_from_summit:
			var s := Spring.new()
			s.x = sx
			s.y = sy
			s.vol = _rng.randf_range(9000.0, 35000.0)
			springs.append(s)


func alive_rivers() -> Array[River]:
	var out: Array[River] = []
	for r in rivers:
		if r.alive and not r.done:
			out.append(r)
	return out


func rank_of(r: River) -> int:
	var k := 1
	for o in rivers:
		if o != r and o.alive and o.vol > r.vol:
			k += 1
	return k


func remaining() -> int:
	var k := 0
	for r in rivers:
		if r.alive and not r.done:
			k += 1
	return k


## Advance the sim by dt seconds. Bots decide their own steer here;
## non-bot rivers use whatever was written into r.steer before the call.
func step(dt: float) -> void:
	elapsed += dt
	var N := TerrainData.N
	var active := alive_rivers()

	for r in active:
		var ci := terrain.cell_index(r.x, r.y)
		var fx := terrain.FLOW_DX[ci]
		var fy := terrain.FLOW_DY[ci]
		var h_here := terrain.sample_w(r.x, r.y)
		var slope := clampf((h_here - terrain.sample_w(r.x + fx * 1.5, r.y + fy * 1.5)) * 30.0, 0.0, 1.5)
		r.slope = slope

		if r.is_bot:
			r.steer = _bot_steer(r, active, h_here, dt)

		# surge
		r.surge_cd = maxf(0.0, r.surge_cd - dt)
		r.surge_timer = maxf(0.0, r.surge_timer - dt)
		if r.want_surge and r.can_surge():
			r.surge_timer = SURGE_TIME
			r.surge_cd = SURGE_COOLDOWN
			r.vol *= 1.0 - SURGE_COST
		r.want_surge = false

		var px := -r.hy
		var py := r.hx
		var gravity := 0.10 + slope * 0.25
		var nx := r.hx * 0.86 + fx * gravity + px * r.steer * 0.30
		var ny := r.hy * 0.86 + fy * gravity + py * r.steer * 0.30
		var l := sqrt(nx * nx + ny * ny)
		if l > 0.0:
			nx /= l
			ny /= l
		# water does not flow uphill: snap toward the flow direction if ahead is higher
		if terrain.sample_w(r.x + nx, r.y + ny) > h_here + 0.004:
			nx = lerpf(nx, fx, 0.6)
			ny = lerpf(ny, fy, 0.6)
			var l2 := sqrt(nx * nx + ny * ny)
			if l2 > 0.0:
				nx /= l2
				ny /= l2
		r.hx = nx
		r.hy = ny

		# size barely affects speed: big rivers cannot simply run you down
		var speed := (0.7 + slope * 2.4) * (1.0 + log(r.vol / 8000.0 + 1.0) / log(10.0) * 0.08)
		if r.surging():
			speed *= SURGE_SPEED
		var mv := speed * dt
		r.x = clampf(r.x + nx * mv, 1.0, N - 2.0)
		r.y = clampf(r.y + ny * mv, 1.0, N - 2.0)
		r.length += mv

		var last := r.path[r.path.size() - 1]
		if last.distance_squared_to(Vector2(r.x, r.y)) > 0.36:
			r.path.append(Vector2(r.x, r.y))

		# volume: rain gain, evaporation on flats
		var rain := terrain.RAIN[terrain.cell_index(r.x, r.y)]
		r.vol += dt * (900.0 + 2600.0 * rain) * (0.6 + slope * 0.6)
		if slope < 0.04:
			r.stuck += dt
			r.vol -= dt * r.vol * 0.05
		else:
			r.stuck = maxf(0.0, r.stuck - dt * 2.0)

		# springs
		var reach := r.radius() + 0.8
		for s in springs:
			if s.taken:
				continue
			var ddx := s.x - r.x
			var ddy := s.y - r.y
			if ddx * ddx + ddy * ddy < reach * reach:
				s.taken = true
				r.vol += s.vol
				spring_taken.emit(r, s)

		# the sea
		if terrain.is_sea(r.x, r.y):
			r.done = true
			finished_count += 1
			reached_sea.emit(r)

	# absorption
	if elapsed > GRACE_SECONDS:
		for a in active.size():
			var A := active[a]
			if not A.alive or A.done:
				continue
			for b in range(a + 1, active.size()):
				var B := active[b]
				if not B.alive or B.done:
					continue
				var rr := A.radius() + B.radius()
				var ddx := A.x - B.x
				var ddy := A.y - B.y
				if ddx * ddx + ddy * ddy < rr * rr * 0.55:
					var big := A if A.vol >= B.vol else B
					var small := B if big == A else A
					if big.vol < small.vol * ABSORB_RATIO:
						continue   # evenly matched: run side by side
					big.vol += small.vol
					big.eaten += 1
					small.alive = false
					small.killer = big.display_name
					absorbed.emit(big, small)


func _bot_steer(r: River, active: Array[River], h_here: float, dt: float) -> float:
	r.retarget -= dt
	if r.retarget <= 0.0:
		r.retarget = 1.5 + _rng.randf() * 2.0
		r.target_spring = -1
		var bd := 400.0
		for i in springs.size():
			var s := springs[i]
			if s.taken:
				continue
			var d := (s.x - r.x) * (s.x - r.x) + (s.y - r.y) * (s.y - r.y)
			if d < bd and terrain.sample_w(s.x, s.y) < h_here + 0.01:
				bd = d
				r.target_spring = i
	var tx := 0.0
	var ty := 0.0
	var w := 0
	var threatened := false
	var hunting := false
	var hunt_range := 36.0 + r.aggression * 100.0     # squared cells
	for o in active:
		if o == r:
			continue
		var dx := o.x - r.x
		var dy := o.y - r.y
		var d2 := dx * dx + dy * dy
		if d2 > 144.0:
			continue
		var d := maxf(sqrt(d2), 0.001)
		var k := 0.0
		if o.vol > r.vol * 1.3:
			k = -1.6                       # flee anything that could eat us
			if d2 < 36.0:
				threatened = true
		elif o.vol * ABSORB_RATIO < r.vol and d2 < hunt_range and _rng.randf() < r.aggression:
			k = 0.6 + r.aggression         # hunters chase clearly smaller prey
			hunting = true
		tx += dx / d * k
		ty += dy / d * k
		w += 1
	if r.target_spring >= 0:
		var s := springs[r.target_spring]
		if not s.taken:
			var dx := s.x - r.x
			var dy := s.y - r.y
			var d := maxf(sqrt(dx * dx + dy * dy), 0.001)
			tx += dx / d * 0.9
			ty += dy / d * 0.9
			w += 1
	# surge to escape, or to close on prey if aggressive
	if r.can_surge() and (threatened or (hunting and r.aggression > 0.6)):
		r.want_surge = true
	if w == 0:
		return 0.0
	var px := -r.hy
	var py := r.hx
	return clampf((tx * px + ty * py) * 1.2, -1.0, 1.0)
