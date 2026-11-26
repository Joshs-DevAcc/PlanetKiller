extends Node3D
## Builds the whole game at startup: sky and sun, the planet, the base, the player and the HUD.

var world: VoxelWorld
var player: Player
var hud: Hud
var shop: Shop


func _ready() -> void:
	_setup_environment()

	world = VoxelWorld.new()
	world.name = "World"
	add_child(world)
	var seed_value := WorldConfig.SEED if WorldConfig.SEED != 0 else randi()
	var started := Time.get_ticks_msec()
	world.generate(seed_value)
	print("Planet generated in %d ms (meshing %d ms)" % [Time.get_ticks_msec() - started, world.last_build_ms])

	var pad := SellPad.new()
	pad.name = "SellPad"
	pad.position = world.base_position + Vector3(3.0, 0, 0)
	add_child(pad)

	player = Player.new()
	player.name = "Player"
	player.world = world
	player.spawn_position = world.base_position + Vector3(0, 1.0, 3.0)
	add_child(player)

	shop = Shop.new()
	shop.name = "Shop"
	shop.position = world.base_position + Vector3(-3.0, 0, -1.0)
	shop.player = player
	add_child(shop)

	hud = Hud.new()
	hud.player = player
	hud.shop = shop
	add_child(hud)

	Game.show_toast("Dig, fill your backpack, sell on the green pad, then upgrade at the shop")


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.92)
	sky_mat.ground_horizon_color = Color(0.7, 0.8, 0.92)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# These only show in the default (Forward+) renderer.
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.7, 0.8, 0.92)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
