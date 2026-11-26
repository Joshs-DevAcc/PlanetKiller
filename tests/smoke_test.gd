extends SceneTree
## Headless smoke test. Run from the project folder:
##   godot --headless --path . -s res://tests/smoke_test.gd
## Loads the game, checks the player lands on the ground, digs into the terrain,
## sells what was dug, buys upgrades and checks the numbers.
## Exits with code 1 on failure.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)

	var world = main.world
	var player = main.player
	var shop = main.shop
	var game: Node = root.get_node("Game")
	var spawner = main.spawner
	spawner.enabled = false
	_check(world.world_size().is_equal_approx(WorldConfig.WORLD_SIZE), "world has the configured size")
	_check(player.is_on_floor(), "player is standing on the ground (at %s)" % player.global_position)
	print("  info generating took %d ms, meshing %d ms, grid %s" % [world.last_generate_ms, world.last_build_ms, world.size])

	# Every material the generator promises should exist somewhere as solid ground.
	var counts := {}
	for i in world.density.size():
		if world.density[i] >= VoxelWorld.ISO:
			counts[world.material[i]] = counts.get(world.material[i], 0) + 1
	for id in Blocks.DEFS.size():
		if id != Blocks.AIR:
			_check(counts.get(id, 0) > 0, "%s appears in the world (%d)" % [Blocks.block_name(id), counts.get(id, 0)])

	# The terrain has collision: a physics ray straight down hits the base floor.
	var from: Vector3 = world.base_position + Vector3(0.3, 3.0, 0.3)
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and absf(hit["position"].y - world.base_position.y) < 0.2, "a ray down lands on the base floor")
	if not hit.is_empty():
		_check(world.material_at(hit["position"] + Vector3.DOWN * 0.3) == Blocks.BASE_FLOOR, "the floor under the base is Base Floor")

	# Dig straight down a few times somewhere away from the base.
	var x := int(world.base_position.x) + 14
	var z := int(world.base_position.z)
	player.camera.rotation.x = -PI / 2 + 0.01
	player.rotation.y = 0
	var digs := 0
	for step in 4:
		var top := _surface_at(world, x, z)
		var p := Vector3(x, top, z)
		var id: int = world.material_at(p + Vector3.DOWN * 0.3)
		player.target = {"hit": true, "pos": p, "normal": Vector3.UP, "id": id}
		var before := top
		for i in 40:
			player.hit()
			if _surface_at(world, x, z) < before - 0.5:
				break
		await _frames(3)
		var after := _surface_at(world, x, z)
		_check(after < before - 0.5, "dig %d through %s lowered the ground from %.1f to %.1f" % [step + 1, Blocks.block_name(id), before, after])
		digs += 1
	_check(game.backpack_count() > 0, "backpack has %d blocks" % game.backpack_count())
	var t0 := Time.get_ticks_usec()
	world.dig(Vector3(x + 0.5, _surface_at(world, x, z), z + 0.5), 3.5)
	print("  info a max-size dig took %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))

	var value: int = game.backpack_value()
	player.global_position = main.get_node("SellPad").global_position + Vector3(0, 1.0, 0)
	await _frames(30)
	_check(game.money == value and value > 0, "selling at the pad paid $%d (expected $%d)" % [game.money, value])
	_check(game.backpack_count() == 0, "backpack is empty after selling")

	# Shop: can't buy when broke, can when rich, and upgrades change the stats.
	game.money = 0
	_check(not game.buy("tool"), "can't buy a tool with no money")
	game.money = 100000
	var old_radius: float = game.dig_radius()
	_check(game.buy("tool") and game.tool()["name"] == Upgrades.TOOLS[1]["name"], "bought %s" % Upgrades.TOOLS[1]["name"])
	_check(game.buy("dig") and game.dig_radius() > old_radius, "bought a bigger dig size (%.1f)" % game.dig_radius())
	_check(game.buy("backpack") and game.backpack_capacity() == Upgrades.BACKPACK[1]["capacity"], "bought a bigger backpack")
	for i in 10:
		game.buy("tool")
	_check(game.tool_level == Upgrades.TOOLS.size() - 1 and game.next_upgrade("tool").is_empty(), "tool upgrades stop at the last level")
	await _frames(5)
	player.global_position = shop.global_position + Vector3(0, 1.0, 1.5)
	await _frames(5)
	_check(shop.is_player_near(), "player standing at the counter can use the shop")
	shop.open()
	_check(game.ui_open, "opening the shop takes over the mouse")
	shop.close()

	# The base floor can't be dug.
	var base_top: float = world.base_position.y
	player.target = {"hit": true, "pos": world.base_position + Vector3(1.5, 0, 1.5), "normal": Vector3.UP, "id": Blocks.BASE_FLOOR}
	for i in 30:
		player.hit()
	_check(absf(_surface_at(world, int(world.base_position.x) + 1, int(world.base_position.z) + 1) - base_top) < 0.3, "the base floor can't be dug")

	# A full backpack stops digging.
	game.backpack = {Blocks.STONE: float(game.backpack_capacity())}
	var fx := x + 8
	var ftop := _surface_at(world, fx, z)
	player.target = {"hit": true, "pos": Vector3(fx, ftop, z), "normal": Vector3.UP, "id": Blocks.GRASS + 1}
	for i in 40:
		player.hit()
	_check(absf(_surface_at(world, fx, z) - ftop) < 0.01, "a full backpack stops digging")

	# Caves: there should be open air well below the surface.
	var cave_air := 0
	var vs: float = world.voxel_size
	for gz in range(4, world.size.z - 4, 4):
		for gx in range(4, world.size.x - 4, 4):
			var ground: float = world.surface_height(gx * vs, gz * vs)
			for gy in range(int((ground - 12.0) / vs), int(4.0 / vs), -4):
				if world.get_density(Vector3i(gx, gy, gz)) < VoxelWorld.ISO:
					cave_air += 1
	_check(cave_air > 200, "caves: found %d open air samples deep underground" % cave_air)

	# Monsters: none at the surface, some when deep.
	game.backpack.clear()
	player.respawn()
	await _frames(2)
	_check(spawner.spawn_near_player() == null, "no monsters spawn at the surface")
	player.global_position = Vector3(world.base_position.x + 10, WorldConfig.SURFACE_Y - 30.0, world.base_position.z + 10)
	var mon = spawner.spawn_near_player()
	_check(mon != null, "a monster spawns when you are 30m down (%s)" % (mon.kind["name"] if mon else "none"))
	if mon:
		var mdepth: float = WorldConfig.SURFACE_Y - mon.global_position.y
		_check(mdepth >= Monsters.MIN_DEPTH, "it spawned deep enough (%.0fm)" % mdepth)
		# Shoot it point blank until it dies.
		mon.global_position = player.camera.global_position - player.camera.global_basis.z * 3.0
		var money_before: int = game.money
		var reward: int = mon.kind["reward"]
		var shots := 0
		for i in 200:
			await _frames(1)
			if not is_instance_valid(mon) or mon._dying:
				break
			mon.global_position = player.camera.global_position - player.camera.global_basis.z * 3.0
			await physics_frame
			player.shoot()
			shots += 1
		_check(not is_instance_valid(mon) or mon._dying, "shooting kills it (%d shots)" % shots)
		_check(game.money == money_before + reward, "killing it pays $%d" % reward)

	# A monster that reaches you bites.
	game.health = game.max_health()
	var biter = spawner.spawn_near_player()
	if biter:
		biter.global_position = player.global_position + Vector3(0.5, 0.3, 0)
		var hp: float = game.health
		await _frames(10)
		_check(game.health < hp, "a monster bite hurts (%.0f -> %.0f)" % [hp, game.health])
		biter.queue_free()

	# Dying sends you home and empties the backpack.
	game.backpack = {Blocks.GOLD: 5.0}
	game.damage_player(10000.0)
	await _frames(2)
	_check(game.backpack_count() == 0, "dying empties the backpack")
	_check(player.global_position.distance_to(player.spawn_position) < 1.0, "dying sends you back to base")
	_check(is_equal_approx(game.health, game.max_health()), "you come back with full health")

	# Armor raises max health.
	var hp_before: float = game.max_health()
	game.money = 100000
	_check(game.buy("armor") and game.max_health() > hp_before, "armor raises max health to %d" % game.max_health())
	_check(game.buy("weapon") and game.weapon()["name"] == Upgrades.WEAPONS[1]["name"], "bought the %s" % Upgrades.WEAPONS[1]["name"])

	# Fall damage.
	game.health = game.max_health()
	player.global_position = world.base_position + Vector3(0, 14.0, 3.0)
	player.velocity = Vector3.ZERO
	for i in 180:
		await physics_frame
		if player.is_on_floor():
			break
	await _frames(2)
	_check(game.health < game.max_health(), "falling 14m hurts (%.0f / %d)" % [game.health, game.max_health()])

	print("\n%s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Height in meters of the topmost surface in a column (x, z in meters), from the density data.
func _surface_at(world, x: float, z: float) -> float:
	var vs: float = world.voxel_size
	var gx := roundi(x / vs)
	var gz := roundi(z / vs)
	for y in range(world.size.y - 2, -1, -1):
		var d_hi: int = world.get_density(Vector3i(gx, y + 1, gz))
		var d_lo: int = world.get_density(Vector3i(gx, y, gz))
		if d_lo >= VoxelWorld.ISO and d_hi < VoxelWorld.ISO:
			return (y + (d_lo - (VoxelWorld.ISO - 0.5)) / float(d_lo - d_hi)) * vs
	return 0.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1
