extends Node3D
## Builds the whole game at startup: sky and sun, the planet, the base, the player and the HUD.

var world: VoxelWorld
var player: Player
var hud: Hud
var shop: Shop
var spawner: MonsterSpawner
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	_setup_environment()
	# Show a loading screen for a couple of frames, then build the planet.
	var loading := _make_loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame

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

	spawner = MonsterSpawner.new()
	spawner.name = "Monsters"
	spawner.player = player
	spawner.world = world
	add_child(spawner)

	hud = Hud.new()
	hud.player = player
	hud.shop = shop
	add_child(hud)

	loading.queue_free()
	Game.show_toast("Dig, fill your backpack, sell on the green pad, then upgrade at the shop")


func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.22, 0.2, 0.17)
	sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# Screen-space effects. These only show in the default Forward+ renderer.
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	# Distance haze that takes on the sky's color.
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.76, 0.9)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.15
	env.fog_aerial_perspective = 0.5
	# A touch more color and contrast.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -30, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)


func _make_loading_screen() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 20
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "PLANET KILLER\n\nGenerating planet..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)
	add_child(layer)
	return layer


## Underground gets darker and hazier the deeper you go, and the headlamp brightens.
func _process(_delta: float) -> void:
	if player == null:
		return
	var depth := WorldConfig.SURFACE_Y - player.camera.global_position.y
	var u := clampf((depth - 3.0) / 12.0, 0.0, 1.0)
	env.ambient_light_energy = lerpf(0.55, 0.05, u)
	env.fog_light_color = Color(0.66, 0.76, 0.9).lerp(Color(0.03, 0.03, 0.045), u)
	env.fog_density = lerpf(0.006, 0.035, u)
	env.fog_aerial_perspective = lerpf(0.5, 0.0, u)
	player.lamp.light_energy = lerpf(0.45, 1.2, u)
	player.lamp.spot_range = lerpf(18.0, 24.0, u)
