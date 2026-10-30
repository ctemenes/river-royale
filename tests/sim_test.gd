extends SceneTree
## Headless simulation test. No rendering, no scene.
##
##   godot --headless --import      (once, builds the script class cache)
##   godot --headless -s tests/sim_test.gd
##
## Generates an island, runs a full 80-river match with all bots at 120 Hz,
## and prints timings plus the final leaderboard. Also checks determinism:
## two sims from the same seed must produce identical results. This is the
## property the multiplayer server relies on.


const TD = preload("res://sim/TerrainData.gd")
const RS = preload("res://sim/RiverSim.gd")


func _init() -> void:
	var world_seed := 20261031
	var t0 := Time.get_ticks_msec()
	var terrain = TD.new()
	terrain.generate(world_seed)
	var t_terrain := Time.get_ticks_msec() - t0
	print("terrain: %d ms   summit %s   km to sea from summit %.2f" % [t_terrain, terrain.summit, terrain.km_to_sea(terrain.summit.x, terrain.summit.y)])

	# every land cell must drain: W >= H everywhere, and flow is defined on land
	var undrained := 0
	for i in TD.N * TD.N:
		if terrain.W[i] > TD.SEA and terrain.FLOW_DX[i] == 0.0 and terrain.FLOW_DY[i] == 0.0:
			undrained += 1
	print("land cells with no downhill neighbour: %d (should be 0)" % undrained)

	var result_a := _run_match(terrain, world_seed)
	var result_b := _run_match(terrain, world_seed)
	print("deterministic: %s" % ("YES" if result_a == result_b else "NO  <-- fix before multiplayer"))
	quit()


func _run_match(terrain, world_seed: int) -> String:
	var sim = RS.new()
	var names: Array[String] = []
	sim.setup(terrain, world_seed, names)
	var t0 := Time.get_ticks_msec()
	var steps := 0
	var dt := 1.0 / 120.0
	while sim.remaining() > 0 and sim.elapsed < 600.0:
		sim.step(dt)
		steps += 1
	var ms := Time.get_ticks_msec() - t0
	print("match: %d steps (%.1f s sim) in %d ms  -> %.1f ms per sim-second" % [steps, sim.elapsed, ms, ms / maxf(sim.elapsed, 0.001)])

	var board := []
	for r in sim.rivers:
		if r.alive:
			board.append(r)
	board.sort_custom(func(a, b): return a.vol > b.vol)
	var summary := ""
	for i in mini(5, board.size()):
		var r = board[i]
		var line := "  #%d %-12s %10d L  ate %d  %.1f km" % [i + 1, r.display_name, int(r.vol), r.eaten, r.length * TD.CELL_KM]
		print(line)
		summary += line + "\n"
	print("  survivors %d, reached sea %d, absorbed %d" % [board.size(), sim.finished_count, RS.RIVER_COUNT - board.size()])
	return summary
