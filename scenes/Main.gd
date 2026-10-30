extends Node3D
## Single-player match: one island, you plus 79 bots.
## Everything here is a client-side view of RiverSim. When multiplayer lands,
## this scene keeps rendering while the sim moves to the server and the
## player's steer value goes over the wire instead of straight into the river.

const SUBSTEP := 1.0 / 120.0
const PLAYER_NAME := "riverboi"

var terrain := TerrainData.new()
var sim := RiverSim.new()
var player: RiverSim.River
var terrain_mesh: TerrainMesh
var rivers: RiverRenderer
var camera: CameraRig
var hud: HUD
var _acc := 0.0
var _running := false
var _ended := false


func _ready() -> void:
	var world_seed := randi()
	print("River Royale: generating island, seed %d" % world_seed)
	var t0 := Time.get_ticks_msec()
	terrain.generate(world_seed)
	print("  terrain %d ms, summit %s" % [Time.get_ticks_msec() - t0, terrain.summit])

	var names: Array[String] = [PLAYER_NAME]
	sim.setup(terrain, world_seed, names)
	player = sim.rivers[0]
	sim.absorbed.connect(_on_absorbed)
	sim.spring_taken.connect(_on_spring)
	sim.reached_sea.connect(_on_reached_sea)

	_build_world()
	_running = true


func _build_world() -> void:
	_trace("environment")
	# light + sky
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.75)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.16)
	sky_mat.ground_horizon_color = Color(0.72, 0.8, 0.88)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.8, 0.88)
	e.fog_density = 0.0035
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160
	add_child(sun)

	_trace("terrain mesh")
	# island
	terrain_mesh = TerrainMesh.new()
	terrain_mesh.build(terrain)
	add_child(terrain_mesh)

	_trace("sea")
	# sea
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(TerrainData.N * 4, TerrainData.N * 4)
	sea.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.1, 0.42, 0.55, 0.82)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 0.05
	sm.metallic = 0.2
	sea.material_override = sm
	sea.position = Vector3(TerrainData.N * 0.5, TerrainData.SEA * TerrainData.HEIGHT_SCALE + 0.05, TerrainData.N * 0.5)
	add_child(sea)

	_trace("springs")
	# springs
	var spring_mesh := SphereMesh.new()
	spring_mesh.radius = 0.35
	spring_mesh.height = 0.7
	var spring_mat := StandardMaterial3D.new()
	spring_mat.albedo_color = Color(0.6, 0.95, 1.0)
	spring_mat.emission_enabled = true
	spring_mat.emission = Color(0.5, 0.95, 1.0)
	spring_mat.emission_energy_multiplier = 2.0
	var springs_node := Node3D.new()
	springs_node.name = "Springs"
	add_child(springs_node)
	for s in sim.springs:
		var mi := MeshInstance3D.new()
		mi.mesh = spring_mesh
		mi.material_override = spring_mat
		mi.position = terrain.world_pos(s.x, s.y, 0.4)
		springs_node.add_child(mi)

	_trace("rivers")
	# rivers
	rivers = RiverRenderer.new()
	rivers.setup(sim, terrain, player.id)
	add_child(rivers)

	_trace("camera + hud")
	# camera + hud
	camera = CameraRig.new()
	camera.setup(terrain)
	add_child(camera)
	camera.make_current()

	hud = HUD.new()
	add_child(hud)
	hud.again_button.pressed.connect(func(): get_tree().reload_current_scene())
	_trace("world built")


var _frames := 0


func _trace(what: String) -> void:
	print("  build: %s" % what)


func _process(dt: float) -> void:
	_frames += 1
	if _frames <= 3 or _frames == 60 or _frames == 300:
		print("  frame %d ok (%.1f fps)" % [_frames, Engine.get_frames_per_second()])
	if _running:
		var steer := 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			steer -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			steer += 1.0
		player.steer = steer

		_acc += minf(dt, 0.05)
		while _acc >= SUBSTEP:
			sim.step(SUBSTEP)
			_acc -= SUBSTEP
			if not _running:
				break

	rivers.update(dt)
	camera.follow(player, dt)
	hud.update(sim, player)
	_hide_taken_springs()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB:
			camera.map_view = not camera.map_view


func _hide_taken_springs() -> void:
	var node := get_node_or_null("Springs")
	if node == null:
		return
	var i := 0
	for child in node.get_children():
		if i < sim.springs.size() and sim.springs[i].taken:
			child.visible = false
		i += 1


func _on_absorbed(big: RiverSim.River, small: RiverSim.River) -> void:
	if big == player:
		hud.post("absorbed %s  +%s L" % [small.display_name, HUD._fmt(small.vol)], HUD.WATER)
	elif small == player:
		hud.post("swallowed by %s" % big.display_name, HUD.RANK_COLOR)
		_end(false)
	elif Vector2(big.x, big.y).distance_to(Vector2(player.x, player.y)) < 30.0:
		hud.post("%s absorbed %s" % [big.display_name, small.display_name], Color(0.85, 0.9, 0.95))


func _on_spring(r: RiverSim.River, s: RiverSim.Spring) -> void:
	if r == player:
		hud.post("spring  +%s L" % HUD._fmt(s.vol), HUD.WATER)


func _on_reached_sea(r: RiverSim.River) -> void:
	if r == player:
		_end(true)
	elif Vector2(r.x, r.y).distance_to(Vector2(player.x, player.y)) < 40.0:
		hud.post("%s reached the sea" % r.display_name, Color(0.85, 0.9, 0.95))


func _end(reached_sea: bool) -> void:
	if _ended:
		return
	_ended = true
	_running = false
	await get_tree().create_timer(0.8).timeout
	hud.show_end(sim, player, reached_sea)
