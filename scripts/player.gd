class_name Player
extends CharacterBody3D
## First-person miner: walks, jumps, and mines the block under the crosshair
## by holding the left mouse button.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_VELOCITY := 6.8
const GRAVITY := 20.0
const MOUSE_SENSITIVITY := 0.0025
const EYE_HEIGHT := 0.65 # above the body's center

var world: VoxelWorld
var spawn_position := Vector3.ZERO

## What the crosshair is on. Read by the HUD.
var target := {"hit": false}
var mine_progress := 0.0

var camera: Camera3D
var _pitch := 0.0
var _highlight: MeshInstance3D
var _pickaxe: Node3D
var _swing_time := 0.0
var _toast_cooldown := 0.0


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
	var lamp := SpotLight3D.new()
	lamp.spot_range = 16.0
	lamp.spot_angle = 40.0
	lamp.spot_attenuation = 0.5
	lamp.light_energy = 0.7
	lamp.light_cull_mask = 1 # don't light the pickaxe (layer 2)
	camera.add_child(lamp)

	_pickaxe = _make_pickaxe()
	camera.add_child(_pickaxe)
	_highlight = _make_highlight()
	_highlight.top_level = true
	add_child(_highlight)

	floor_snap_length = 0.3
	respawn()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
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
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	if dir != Vector3.ZERO:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, speed * 10.0 * delta)
	move_and_slide()

	if global_position.y < -10.0:
		respawn()


func _process(delta: float) -> void:
	_toast_cooldown = maxf(_toast_cooldown - delta, 0.0)
	_update_target()
	var mining := Input.is_action_pressed("mine") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if mining and target["hit"]:
		mine_tick(delta)
	else:
		mine_progress = 0.0
	_animate_pickaxe(delta, mining)


## Advances mining on the current target. Public so tests can drive it.
func mine_tick(delta: float) -> void:
	var id: int = target["id"]
	var hardness := Blocks.hardness(id)
	if hardness < 0.0:
		mine_progress = 0.0
		_toast_once("%s is too hard to mine with this pickaxe" % Blocks.block_name(id))
		return
	if Blocks.is_collectable(id) and Game.is_backpack_full():
		mine_progress = 0.0
		_toast_once("Backpack full! Sell at the base pad (press R to go back)")
		return
	mine_progress += delta * Game.pickaxe_power / maxf(hardness, 0.05)
	if mine_progress >= 1.0:
		_break_block(target["pos"], id)
		mine_progress = 0.0


func _update_target() -> void:
	var previous: Variant = target.get("pos")
	target = world.raycast(camera.global_position, -camera.global_basis.z, Game.reach)
	if not target["hit"] or target.get("pos") != previous:
		mine_progress = 0.0
	_highlight.visible = target["hit"]
	if target["hit"]:
		_highlight.global_position = Vector3(target["pos"]) + Vector3(0.5, 0.5, 0.5)


func _break_block(pos: Vector3i, id: int) -> void:
	if Blocks.is_collectable(id):
		Game.add_to_backpack(id)
	world.set_block(pos, Blocks.AIR)
	_spawn_debris(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Blocks.color(id))


func _toast_once(text: String) -> void:
	if _toast_cooldown <= 0.0:
		Game.show_toast(text)
		_toast_cooldown = 2.0


func _spawn_debris(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.14, 0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	cube.material = mat
	p.mesh = cube
	p.amount = 14
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -14, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.4, 0.4, 0.4)
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _animate_pickaxe(delta: float, mining: bool) -> void:
	if mining:
		_swing_time += delta
		_pickaxe.rotation.x = -absf(sin(_swing_time * 11.0)) * 0.9
	else:
		_swing_time = 0.0
		_pickaxe.rotation.x = lerpf(_pickaxe.rotation.x, 0.0, minf(delta * 10.0, 1.0))


func _make_pickaxe() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.38, -0.32, -0.55)
	root.rotation = Vector3(0, deg_to_rad(-15), deg_to_rad(10))
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.05, 0.55, 0.05)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.33, 0.18)
	hm.material = wood
	handle.mesh = hm
	handle.position = Vector3(0, 0.1, 0)
	root.add_child(handle)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.45, 0.47, 0.52)
	metal.roughness = 0.5
	# Pick head: a long thin bar with pointed tips.
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.05, 0.05)
	bm.material = metal
	bar.mesh = bm
	bar.position = Vector3(0, 0.37, 0)
	root.add_child(bar)
	for side in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.05, 0.1, 0.05)
		pm.material = metal
		tip.mesh = pm
		tip.position = Vector3(side * 0.21, 0.35, 0)
		tip.rotation.z = -side * deg_to_rad(110)
		root.add_child(tip)
	var collar := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.09, 0.08, 0.08)
	cm.material = metal
	collar.mesh = cm
	collar.position = Vector3(0, 0.37, 0)
	root.add_child(collar)
	for child in root.get_children():
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 2
	return root


func _make_highlight() -> MeshInstance3D:
	# 12 edges of a cube, slightly bigger than a block.
	var s := 0.505
	var c := [
		Vector3(-s, -s, -s), Vector3(s, -s, -s), Vector3(s, -s, s), Vector3(-s, -s, s),
		Vector3(-s, s, -s), Vector3(s, s, -s), Vector3(s, s, s), Vector3(-s, s, s),
	]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	var verts := PackedVector3Array()
	for e in edges:
		verts.append(c[e[0]])
		verts.append(c[e[1]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
