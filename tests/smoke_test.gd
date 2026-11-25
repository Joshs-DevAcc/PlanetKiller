extends SceneTree
## Headless smoke test. Run from the project folder:
##   godot --headless --path . -s res://tests/smoke_test.gd
## Loads the game, checks the player lands on the ground, mines a column of
## blocks, sells them and checks the money went up. Exits with code 1 on failure.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)

	var world = main.world
	var player = main.player
	var game: Node = root.get_node("Game")
	_check(world.size == WorldConfig.WORLD_SIZE, "world has the configured size")
	_check(player.is_on_floor(), "player is standing on the ground (at %s)" % player.global_position)

	# Every block layer the generator promises should exist somewhere.
	var counts := {}
	for i in world.data.size():
		counts[world.data[i]] = counts.get(world.data[i], 0) + 1
	for id in Blocks.DEFS.size():
		if id != Blocks.AIR:
			_check(counts.get(id, 0) > 0, "%s appears in the world (%d)" % [Blocks.block_name(id), counts.get(id, 0)])

	# Raycast straight down onto the base pad.
	var hit: Dictionary = world.raycast(world.base_position + Vector3(0.5, 2.0, 0.5), Vector3.DOWN, 5.0)
	_check(hit["hit"] and hit["id"] == Blocks.BASE_FLOOR, "raycast down finds the base floor")

	# Mine a column next to the base by aiming the player's target at it.
	var x := int(world.base_position.x) + 6
	var z := int(world.base_position.z)
	var top: int = world.surface_height(x, z)
	for y in range(top, top - 8, -1):
		var p := Vector3i(x, y, z)
		var id: int = world.get_block(p)
		player.target = {"hit": true, "pos": p, "id": id, "normal": Vector3i.UP}
		player.mine_progress = 0.0
		for i in 200:
			player.mine_tick(0.05)
			if world.get_block(p) == Blocks.AIR:
				break
		_check(world.get_block(p) == Blocks.AIR, "mined %s at %s" % [Blocks.block_name(id), p])
	_check(game.backpack_count() > 0, "backpack has %d blocks" % game.backpack_count())

	var value: int = game.backpack_value()
	player.respawn()
	player.global_position = world.base_position + Vector3(0, 1.0, 0)
	await _frames(30)
	_check(game.money == value and value > 0, "selling at the pad paid $%d (expected $%d)" % [game.money, value])
	_check(game.backpack_count() == 0, "backpack is empty after selling")

	# The backpack refuses blocks when full.
	game.backpack_capacity = 0
	var p2 := Vector3i(x, top - 8, z)
	player.target = {"hit": true, "pos": p2, "id": world.get_block(p2), "normal": Vector3i.UP}
	for i in 100:
		player.mine_tick(0.05)
	_check(world.get_block(p2) != Blocks.AIR, "a full backpack stops mining")

	print("\n%s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
