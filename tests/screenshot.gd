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
	# 1: looking out over the base
	player.rotation.y = deg_to_rad(200)
	player.camera.rotation.x = -0.25
	await _frames(20)
	_save(out_dir + "/shot_surface.png")
	# 2: dig a pit and look down into it
	var cx := int(world.base_position.x) + 5
	var cz := int(world.base_position.z) + 5
	for y in range(world.surface_height(cx, cz), 20, -1):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if absi(dx) + absi(dz) < 5:
					world.data[world._index(cx + dx, y, cz + dz)] = 0
	world._build_all_chunks()
	player.global_position = Vector3(cx - 4.5, world.surface_height(cx - 5, cz) + 2.0, cz)
	player.rotation.y = deg_to_rad(-90)
	player.camera.rotation.x = -0.6
	await _frames(20)
	_save(out_dir + "/shot_pit.png")
	quit()


func _save(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
