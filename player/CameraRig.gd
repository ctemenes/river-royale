class_name CameraRig
extends Camera3D
## Chase camera that follows the player's river head, looking downstream.
## Tab toggles an overhead map view of the whole island.

var map_view := false
var _terrain: TerrainData
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _initialised := false


func setup(terrain: TerrainData) -> void:
	_terrain = terrain
	fov = 60.0
	far = 2000.0
	near = 0.1


func follow(r: RiverSim.River, dt: float) -> void:
	var head := _terrain.world_pos(r.x, r.y, 0.5)
	var heading := Vector3(r.hx, 0.0, r.hy)
	var rad := r.radius()
	# higher and further back than a car chase cam: you need to read the valleys ahead
	var back := 13.0 + rad * 4.0
	var up := 9.0 + rad * 3.0

	var want_pos: Vector3
	var want_look: Vector3
	if map_view:
		var c := _terrain.world_pos(TerrainData.N * 0.5, TerrainData.N * 0.5)
		want_pos = c + Vector3(0.0, 230.0, 60.0)
		want_look = c
	else:
		want_pos = head - heading * back + Vector3(0.0, up, 0.0)
		# keep the camera above the ground
		var ground := _terrain.sample_w(clampf(want_pos.x, 0, TerrainData.N - 1), clampf(want_pos.z, 0, TerrainData.N - 1)) * TerrainData.HEIGHT_SCALE
		want_pos.y = maxf(want_pos.y, ground + 2.5)
		want_look = head + heading * 10.0

	if not _initialised:
		_pos = want_pos
		_look = want_look
		_initialised = true
	var k := 1.0 - pow(0.001, dt)   # frame-rate independent smoothing
	_pos = _pos.lerp(want_pos, k * 0.6)
	_look = _look.lerp(want_look, k)
	global_position = _pos
	look_at(_look, Vector3.UP)
