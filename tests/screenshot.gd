extends SceneTree
## Saves screenshots of the game for checking visuals without a person at the keyboard.
##   godot --path . -s res://tests/screenshot.gd -- <output_dir>
## Needs a display (use xvfb-run on a headless Linux box).

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(60)
	var player = main.player
	var world = main.world
	var base: Vector3 = world.base_position
	main.spawner.enabled = false
	var g: Node = root.get_node("Game")
	g.armor_level = Upgrades.ARMOR.size() - 1
	g.health = 100000.0

	# 1: the base, with the shop and sell pad
	player.global_position = base + Vector3(0, 1.0, 6.0)
	player.rotation.y = 0
	player.camera.rotation.x = -0.15
	await _frames(20)
	_save(out_dir + "/shot_base.png")

	# 2: the countryside, after digging a few craters
	var c := base + Vector3(-16, 0, 6)
	for i in 5:
		var p := Vector3(c.x + i * 2.5, world.surface_height(int(c.x + i * 2.5), int(c.z)), c.z)
		world.dig(p, 1.3 + i * 0.5)
	await _settle(world)
	player.global_position = base + Vector3(-6, 1.5, 12)
	player.rotation.y = deg_to_rad(60)
	player.camera.rotation.x = -0.35
	await _frames(20)
	_save(out_dir + "/shot_craters.png")

	# 3: a big pit dug down to the ore layers
	var pit := base + Vector3(18, 0, -14)
	for depth in range(0, 40, 2):
		world.dig(pit + Vector3(0, -depth, 0), 5.0)
	await _settle(world)
	player.global_position = pit + Vector3(-7, 1.5, 0)
	player.rotation.y = deg_to_rad(-90)
	player.camera.rotation.x = -0.75
	await _frames(20)
	_save(out_dir + "/shot_pit.png")

	# 4: down in the pit with a drill
	g.tool_level = Upgrades.TOOLS.size() - 1
	g.upgraded.emit("tool")
	player.global_position = pit + Vector3(0, -40, 0)
	player.rotation.y = deg_to_rad(30)
	player.camera.rotation.x = -0.1
	await _frames(30)
	_save(out_dir + "/shot_deep.png")

	# 5: in a cave, with monsters
	main.spawner.enabled = false
	var cave := _find_cave(world)
	if cave != Vector3.INF:
		player.global_position = cave
		player.rotation.y = deg_to_rad(-90)
		player.camera.rotation.x = 0.0
		await _frames(5)
		for i in 3:
			var m = main.spawner.spawn_near_player()
			if m:
				m.global_position = cave + Vector3(5.0 + i * 2.0, 0.6 + i * 0.4, -1.8 + i * 1.8)
				m.set_physics_process(false)
				m.look_at(player.camera.global_position, Vector3.UP)
		g.weapon_level = 2
		g.upgraded.emit("weapon")
		await _frames(30)
		player.camera.rotation.x = 0.12
		player.shoot()
		await _frames(1)
		_save(out_dir + "/shot_cave.png")
	else:
		print("no cave found for screenshot")

	# 6: the shop menu
	g.money = 420
	player.global_position = main.shop.global_position + Vector3(0, 1.0, 1.6)
	await _frames(5)
	g.tool_level = 0
	g.upgraded.emit("tool")
	main.shop.open()
	await _frames(10)
	_save(out_dir + "/shot_shop.png")
	quit()


## Finds a spot about 25-40m down with open cave space ahead (+x).
func _find_cave(world) -> Vector3:
	var vs: float = world.voxel_size
	for gz in range(20, world.size.z - 20, 3):
		for gx in range(20, world.size.x - 40, 3):
			for depth in range(25, 40, 2):
				var p := Vector3(gx * vs, WorldConfig.SURFACE_Y - depth, gz * vs)
				var ok := true
				for k in 8:
					if not world.is_air(p + Vector3(k * 1.0, 0, 0)) or not world.is_air(p + Vector3(k * 1.0, 1.5, 0)):
						ok = false
						break
				if ok and not world.is_air(p + Vector3(0, -2.0, 0)):
					return p
	return Vector3.INF


func _save(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)


func _settle(world) -> void:
	for i in 300:
		await process_frame
		if not world.is_busy():
			break


func _frames(n: int) -> void:
	for i in n:
		await process_frame
