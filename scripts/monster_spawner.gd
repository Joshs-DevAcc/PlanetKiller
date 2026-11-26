class_name MonsterSpawner
extends Node3D
## Spawns monsters around the player, but only deep underground.
## Settings live in scripts/data/monsters.gd.

var player: Player
var world: VoxelWorld
## Set to false to turn monsters off (e.g. for tests).
var enabled := true

var _timer := 0.0


func _ready() -> void:
	Game.player_died.connect(clear)


func monsters() -> Array[Node]:
	return get_children().filter(func(n: Node) -> bool: return n is Monster)


func clear() -> void:
	for m in monsters():
		(m as Monster).vanish()


func player_depth() -> float:
	return WorldConfig.SURFACE_Y - player.global_position.y


func _process(delta: float) -> void:
	if player == null:
		return
	# Monsters wander off when you go back up or get far away.
	for m in monsters():
		var mon := m as Monster
		if mon._dying:
			continue
		var far := mon.global_position.distance_to(player.global_position) > Monsters.DESPAWN_DISTANCE
		if far or player_depth() < Monsters.MIN_DEPTH - 4.0:
			mon.vanish()

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = Monsters.SPAWN_INTERVAL * randf_range(0.7, 1.3)
	if enabled and player_depth() >= Monsters.MIN_DEPTH and monsters().size() < Monsters.MAX_ALIVE:
		spawn_near_player()


## Tries to spawn one monster near the player. Returns it, or null.
func spawn_near_player() -> Monster:
	if player_depth() < Monsters.MIN_DEPTH:
		return null
	var spot := _find_spot()
	if spot == Vector3.INF:
		return null
	var depth := WorldConfig.SURFACE_Y - spot.y
	var kind := _pick_kind(depth)
	if kind.is_empty():
		return null
	var m := Monster.new()
	m.setup(kind, player, world)
	add_child(m)
	m.global_position = spot
	return m


func _find_spot() -> Vector3:
	var size := world.world_size()
	var fallback := Vector3.INF
	# Prefer open cave space; otherwise come out of the rock.
	for attempt in 16:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
		var p := player.global_position + dir * randf_range(Monsters.SPAWN_DISTANCE_MIN, Monsters.SPAWN_DISTANCE_MAX)
		if p.x < 2 or p.z < 2 or p.x > size.x - 2 or p.z > size.z - 2 or p.y < WorldConfig.CORE_DEPTH + 2:
			continue
		if WorldConfig.SURFACE_Y - p.y < Monsters.MIN_DEPTH:
			continue
		if world.is_air(p):
			return p
		if fallback == Vector3.INF:
			fallback = p
	return fallback


func _pick_kind(depth: float) -> Dictionary:
	var options := []
	for k in Monsters.KINDS:
		if depth >= k["min_depth"] and depth <= k["max_depth"]:
			options.append(k)
	if options.is_empty():
		return {}
	# Deeper kinds are a bit more likely when several fit.
	var weights := []
	var total := 0.0
	for i in options.size():
		total += 1.0 + i
		weights.append(total)
	var r := randf() * total
	for i in options.size():
		if r <= weights[i]:
			return options[i]
	return options[-1]
