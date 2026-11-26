class_name Player
extends CharacterBody3D
## First-person miner. Hold left click to swing the tool at the terrain.
## Each hit adds progress; when it fills, a round chunk is dug out of the world.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_VELOCITY := 6.8
const GRAVITY := 20.0
const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 0.65 # above the body's center

## When in a swing the tool connects (0-1 through one swing).
const IMPACT_PHASE := 0.62
## Landing faster than this (m/s) hurts.
const FALL_DAMAGE_SPEED := 14.0
## Health per second you get back after not being hurt for a while, and at base.
const REGEN_DELAY := 6.0
const REGEN_RATE := 4.0
const BASE_HEAL_RATE := 30.0

var world: VoxelWorld
var spawn_position := Vector3.ZERO

## What the crosshair is on. Read by the HUD.
## {"hit": bool, "pos": Vector3, "normal": Vector3, "id": int}
var target := {"hit": false}
var mine_progress := 0.0

var camera: Camera3D
var _pitch := 0.0
var _dig_preview: MeshInstance3D
var _tool: Node3D
var _drill_bit: Node3D
var _swing_phase := 0.0
var _swinging := false
var _bob_time := 0.0
var _shake := 0.0
var _progress_anchor := Vector3.INF
var _progress_id := -1
var _toast_cooldown := 0.0
var lamp: SpotLight3D
var _gun: Node3D
var _gun_cooldown := 0.0
var _recoil := 0.0
var _muzzle_light: OmniLight3D
var _since_hurt := 99.0
var _fall_speed := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	add_child(shape)

	camera = Camera3D.new()
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.fov = 75.0
	camera.near = 0.05
	camera.current = true
	add_child(camera)

	# Headlamp so tunnels are not pitch black.
	lamp = SpotLight3D.new()
	lamp.spot_range = 18.0
	lamp.spot_angle = 40.0
	lamp.spot_attenuation = 0.6
	lamp.light_energy = 0.45
	lamp.light_cull_mask = 1 # don't light the tool (layer 2)
	lamp.shadow_enabled = true
	camera.add_child(lamp)

	_dig_preview = _make_dig_preview()
	_dig_preview.top_level = true
	add_child(_dig_preview)

	_build_tool()
	_build_gun()
	Game.upgraded.connect(func(_kind: String) -> void:
		_build_tool()
		_build_gun())
	Game.player_hurt.connect(func(_amount: float) -> void:
		_since_hurt = 0.0
		_shake = maxf(_shake, 0.15))
	Game.player_died.connect(_on_died)
	Game.health = Game.max_health()

	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55)
	respawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.5, 1.5)
		camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("recall"):
		respawn()
		Game.show_toast("Back at base")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	var speed := WALK_SPEED
	if not Game.ui_open:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_pressed("sprint"):
			speed = SPRINT_SPEED
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 10.0 * delta)
	var was_on_floor := is_on_floor()
	var falling := -velocity.y
	move_and_slide()
	# Fall damage for hard landings.
	if not was_on_floor and is_on_floor() and falling > FALL_DAMAGE_SPEED:
		Game.damage_player((falling - FALL_DAMAGE_SPEED) * 6.0)
		Game.show_toast("Ouch! Hard landing")

	if global_position.y < -10.0:
		respawn()


func _process(delta: float) -> void:
	_toast_cooldown = maxf(_toast_cooldown - delta, 0.0)
	_update_target()
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Game.ui_open
	var wants_to_mine := Input.is_action_pressed("mine") and active
	_animate(delta, wants_to_mine)

	_gun_cooldown = maxf(_gun_cooldown - delta, 0.0)
	if Input.is_action_pressed("attack") and active and _gun_cooldown <= 0.0:
		shoot()
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_gun.position = Vector3(-0.3, -0.3, -0.55 + _recoil * 0.08)
	_gun.rotation.x = _recoil * 0.25
	_muzzle_light.light_energy = _recoil * 3.0

	# Healing: slowly after a while, quickly at the base.
	_since_hurt += delta
	if _at_base():
		Game.heal_player(BASE_HEAL_RATE * delta)
	elif _since_hurt > REGEN_DELAY:
		Game.heal_player(REGEN_RATE * delta)


## Fires the weapon once. Returns the monster hit, if any. Public so tests can drive it.
func shoot() -> Monster:
	var w := Game.weapon()
	_gun_cooldown = 1.0 / w["shots_per_second"]
	_recoil = 1.0
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * w["range"])
	query.collide_with_areas = true
	query.collision_mask = 1 | Monster.HITBOX_LAYER
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = from + dir * w["range"]
	var hit_monster: Monster = null
	if not result.is_empty():
		end = result["position"]
		if result["collider"] is Monster:
			hit_monster = result["collider"]
			hit_monster.take_damage(w["damage"], global_position)
		else:
			_spawn_debris(end, Color(1, 0.9, 0.6), 4, 1.5)
	_spawn_tracer(_muzzle_light.global_position, end, w["color"])
	return hit_monster


func _at_base() -> bool:
	var flat := Vector2(global_position.x - world.base_position.x, global_position.z - world.base_position.z)
	return flat.length() < WorldConfig.BASE_RADIUS and absf(global_position.y - world.base_position.y) < 3.0


func _on_died() -> void:
	Game.backpack.clear()
	Game.backpack_changed.emit()
	respawn()
	Game.health = Game.max_health()
	Game.health_changed.emit(Game.health, Game.max_health())
	Game.show_toast("You were knocked out! Your backpack was lost.")


func _spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	get_parent().add_child(mi)
	var tween := mi.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(mi.queue_free)

## One strike of the tool against the current target. Public so tests can drive it.
func hit() -> void:
	if not target["hit"]:
		return
	var id: int = target["id"]
	var hardness := Blocks.hardness(id)
	if hardness < 0.0:
		_toast_once("%s can't be mined" % Blocks.block_name(id))
		_spawn_debris(target["pos"], Color(0.8, 0.8, 0.8), 4, 1.5)
		return
	if Blocks.is_collectable(id) and Game.is_backpack_full():
		_toast_once("Backpack full! Sell at the green pad (press R to go back)")
		return
	var center := dig_center()
	if _progress_id != id or center.distance_to(_progress_anchor) > Game.dig_radius() * 0.6:
		mine_progress = 0.0
		_progress_id = id
		_progress_anchor = center
	var tool := Game.tool()
	mine_progress += Upgrades.MINING_RATE * tool["power"] / (maxf(hardness, 0.05) * tool["hits_per_second"])
	_shake = maxf(_shake, 0.05 if tool["kind"] == "pickaxe" else 0.025)
	_spawn_debris(target["pos"], Blocks.color(id), 5, 2.0)
	if mine_progress >= 1.0:
		mine_progress = 0.0
		_progress_id = -1
		var removed := world.dig(center, Game.dig_radius())
		Game.add_materials(removed)
		_shake = 0.12
		_spawn_debris(center, Blocks.color(id), 18 + int(Game.dig_radius() * 6), 4.5)


## Where the next dig is centered: a little past the surface, so it scoops out a chunk.
func dig_center() -> Vector3:
	var into := -camera.global_basis.z
	return target["pos"] + into * Game.dig_radius() * 0.35


func _update_target() -> void:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * Game.reach)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		target = {"hit": false}
		mine_progress = 0.0
		_progress_id = -1
	else:
		var pos: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		var id := world.material_at(pos - normal * 0.3)
		# Ignore things that aren't terrain, like the shop counter.
		target = {"hit": true, "pos": pos, "normal": normal, "id": id} if id != Blocks.AIR else {"hit": false}
	_dig_preview.visible = target["hit"]
	if target["hit"]:
		_dig_preview.global_position = dig_center()
		_dig_preview.scale = Vector3.ONE * Game.dig_radius()


func _toast_once(text: String) -> void:
	if _toast_cooldown <= 0.0:
		Game.show_toast(text)
		_toast_cooldown = 2.0


# --- Animation --------------------------------------------------------------------

func _animate(delta: float, wants_to_mine: bool) -> void:
	var tool := Game.tool()
	var rate: float = tool["hits_per_second"]
	var is_drill: bool = tool["kind"] == "drill"

	# Swing cycle. Finish the current swing even after the button is released.
	if wants_to_mine or _swinging:
		var before := _swing_phase
		_swing_phase += delta * rate
		if wants_to_mine and before < IMPACT_PHASE and _swing_phase >= IMPACT_PHASE:
			hit()
		if _swing_phase >= 1.0:
			_swing_phase -= 1.0
			_swinging = wants_to_mine
			if not wants_to_mine:
				_swing_phase = 0.0
		else:
			_swinging = true
	if not wants_to_mine:
		mine_progress = maxf(mine_progress - delta * 0.5, 0.0)

	# Walking bob.
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * 1.7
	var bob := clampf(flat_speed / SPRINT_SPEED, 0.0, 1.0)
	camera.position.y = EYE_HEIGHT + sin(_bob_time * 2.0) * 0.04 * bob

	# Shake on hits.
	_shake = maxf(_shake - delta * 0.6, 0.0)
	camera.h_offset = randf_range(-1, 1) * _shake * 0.3
	camera.v_offset = randf_range(-1, 1) * _shake * 0.3

	var rest := Vector3(0.36, -0.34, -0.55)
	var sway := Vector3(cos(_bob_time) * 0.012, sin(_bob_time * 2.0) * 0.015, 0) * bob
	if is_drill:
		var active := wants_to_mine
		_drill_bit.rotate_object_local(Vector3.UP, delta * (40.0 if active else 6.0))
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * (0.008 if active else 0.0)
		var push := Vector3(0, 0, -0.08) if active else Vector3.ZERO
		_tool.position = _tool.position.lerp(rest + sway + push + jitter, minf(delta * 18.0, 1.0))
		_tool.rotation = Vector3(deg_to_rad(-80), 0, 0)
	else:
		var angle := _swing_angle(_swing_phase) if _swinging else 0.0
		_tool.position = rest + sway + Vector3(0, 0, -0.12 * maxf(-angle, 0.0))
		_tool.rotation = Vector3(angle, deg_to_rad(-15), deg_to_rad(10))


## Pickaxe tilt through a swing: wind up, strike fast, then recover.
func _swing_angle(p: float) -> float:
	const RAISED := 0.95
	const STRUCK := -0.75
	if p < 0.5:
		return lerpf(0.0, RAISED, ease(p / 0.5, 0.5))
	if p < IMPACT_PHASE:
		return lerpf(RAISED, STRUCK, ease((p - 0.5) / (IMPACT_PHASE - 0.5), 2.2))
	return lerpf(STRUCK, 0.0, ease((p - IMPACT_PHASE) / (1.0 - IMPACT_PHASE), 0.6))


func _spawn_debris(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.12, 0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	cube.material = mat
	p.mesh = cube
	p.amount = maxi(amount, 1)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.8
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# --- Models -----------------------------------------------------------------------

func _build_tool() -> void:
	if _tool:
		_tool.queue_free()
	var info := Game.tool()
	_tool = _make_drill(info["color"]) if info["kind"] == "drill" else _make_pickaxe(info["color"])
	camera.add_child(_tool)
	for child in _tool.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2


func _mat(color: Color, metallic := 0.0, roughness := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_gun() -> void:
	if _gun:
		_gun.queue_free()
	var w := Game.weapon()
	_gun = Node3D.new()
	var body := _mat(w["color"] * 0.7, 0.2, 0.5)
	var dark := _mat(Color(0.12, 0.12, 0.14), 0.3, 0.5)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = w["color"]
	glow.emission_enabled = true
	glow.emission = w["color"]
	glow.emission_energy_multiplier = 1.0
	_box(_gun, Vector3(0.09, 0.1, 0.32), Vector3(0, 0, 0), body)
	_box(_gun, Vector3(0.05, 0.05, 0.22), Vector3(0, 0.02, -0.25), dark)
	_box(_gun, Vector3(0.06, 0.13, 0.07), Vector3(0, -0.1, 0.08), dark)
	_box(_gun, Vector3(0.095, 0.02, 0.2), Vector3(0, 0.06, -0.02), glow)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = w["color"]
	_muzzle_light.omni_range = 4.0
	_muzzle_light.light_energy = 0.0
	_muzzle_light.position = Vector3(0, 0.02, -0.4)
	_gun.add_child(_muzzle_light)
	_gun.scale = Vector3.ONE * 0.75
	camera.add_child(_gun)
	for child in _gun.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2


func _make_pickaxe(head_color: Color) -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.5, 0.33, 0.18), 0.0, 0.8)
	var metal := _mat(head_color * 0.8, 0.0, 0.45)
	_box(root, Vector3(0.05, 0.55, 0.05), Vector3(0, 0.1, 0), wood)
	_box(root, Vector3(0.34, 0.05, 0.05), Vector3(0, 0.37, 0), metal)
	_box(root, Vector3(0.09, 0.08, 0.08), Vector3(0, 0.37, 0), metal)
	for side in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.05, 0.1, 0.05)
		pm.material = metal
		tip.mesh = pm
		tip.position = Vector3(side * 0.21, 0.35, 0)
		tip.rotation.z = -side * deg_to_rad(110)
		root.add_child(tip)
	return root


func _make_drill(body_color: Color) -> Node3D:
	var root := Node3D.new()
	var body := _mat(body_color, 0.2, 0.5)
	var dark := _mat(Color(0.15, 0.15, 0.17), 0.3, 0.6)
	_box(root, Vector3(0.12, 0.26, 0.14), Vector3(0, 0.0, 0), body)
	_box(root, Vector3(0.06, 0.08, 0.16), Vector3(0, -0.12, 0.04), dark) # grip
	_drill_bit = Node3D.new()
	_drill_bit.position = Vector3(0, 0.2, 0)
	root.add_child(_drill_bit)
	var bit := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.24
	cone.radial_segments = 6
	cone.material = _mat(Color(0.6, 0.62, 0.66), 0.2, 0.4)
	bit.mesh = cone
	bit.position = Vector3(0, 0.08, 0)
	_drill_bit.add_child(bit)
	return root


func _make_dig_preview() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/dig_preview.gdshader")
	sphere.material = mat
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
