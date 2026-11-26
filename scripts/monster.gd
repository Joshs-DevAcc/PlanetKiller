class_name Monster
extends Area3D
## An underground creature. It drifts through caves toward the player and can
## burrow (slowly) through rock. It bites when close. Shoot it to get a reward.

const HITBOX_LAYER := 8 # physics layer 4, which the player's shots look for

var kind: Dictionary
var player: Player
var world: VoxelWorld
var health := 1.0

var _bite_cooldown := 0.0
var _flash := 0.0
var _time := 0.0
var _body_mat: StandardMaterial3D
var _visual: Node3D
var _knockback := Vector3.ZERO
var _dying := false


func setup(p_kind: Dictionary, p_player: Player, p_world: VoxelWorld) -> void:
	kind = p_kind
	player = p_player
	world = p_world
	health = kind["health"]


func _ready() -> void:
	collision_layer = HITBOX_LAYER
	collision_mask = 0
	monitoring = false
	var size: float = kind["size"]
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = size * 1.1
	shape.shape = sphere
	add_child(shape)
	_visual = _build_visual(size)
	add_child(_visual)
	_time = randf() * 10.0


func _physics_process(delta: float) -> void:
	if _dying or player == null:
		return
	_time += delta
	_bite_cooldown = maxf(_bite_cooldown - delta, 0.0)
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_body_mat.emission_energy_multiplier = _base_glow() + _flash * 3.0

	var target := player.global_position + Vector3(0, 0.3, 0)
	var to_player := target - global_position
	var dist := to_player.length()
	var size: float = kind["size"]
	var speed: float = kind["speed"]
	# Slower while tunnelling through rock.
	if not world.is_air(global_position):
		speed *= 0.4
	if dist > size + 0.6:
		var dir := to_player / dist
		# Wobble a little so they don't fly in perfectly straight lines.
		dir += Vector3(sin(_time * 1.7), sin(_time * 2.3) * 0.5, cos(_time * 1.3)) * 0.25
		global_position += dir.normalized() * speed * delta
	elif _bite_cooldown <= 0.0:
		Game.damage_player(kind["damage"])
		_bite_cooldown = 1.0 / kind["bite_rate"]
		_visual.scale = Vector3.ONE * 1.25
	global_position += _knockback * delta
	_knockback = _knockback.lerp(Vector3.ZERO, minf(delta * 6.0, 1.0))

	if dist > 0.1:
		look_at(target, Vector3.UP)
	# Breathing / bobbing.
	_visual.scale = _visual.scale.lerp(Vector3.ONE * (1.0 + sin(_time * 4.0) * 0.05), minf(delta * 8.0, 1.0))
	_visual.position.y = sin(_time * 2.5) * 0.08


func take_damage(amount: float, from: Vector3) -> void:
	if _dying:
		return
	health -= amount
	_flash = 1.0
	_knockback = (global_position - from).normalized() * 4.0
	if health <= 0.0:
		_die()


func _die() -> void:
	_dying = true
	Game.kills += 1
	Game.add_money(kind["reward"])
	Game.show_toast("%s defeated  +$%d" % [kind["name"], kind["reward"]])
	var p := CPUParticles3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = kind["color"]
	mat.emission_enabled = true
	mat.emission = kind["eye"]
	mat.emission_energy_multiplier = 0.6
	cube.material = mat
	p.mesh = cube
	p.amount = 30
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9, 0)
	get_parent().add_child(p)
	p.global_position = global_position
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	queue_free()


## Removes the monster with a puff, without a reward.
func vanish() -> void:
	_dying = true
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(queue_free)


func _base_glow() -> float:
	return 0.8 if kind["name"] == "Magma Crawler" else 0.0


func _build_visual(size: float) -> Node3D:
	var root := Node3D.new()
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = kind["color"]
	_body_mat.roughness = 0.8
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 1, 1) if kind["name"] != "Magma Crawler" else Color(1.0, 0.35, 0.05)
	_body_mat.emission_energy_multiplier = _base_glow()

	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 1.7
	sphere.material = _body_mat
	body.mesh = sphere
	root.add_child(body)

	# Spikes along the back.
	var spikes := 5 if kind["name"] != "Gloomling" else 3
	for i in spikes:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = size * 0.22
		cone.height = size * 0.7
		cone.radial_segments = 5
		cone.material = _body_mat
		spike.mesh = cone
		var a := (float(i) / maxf(spikes - 1, 1) - 0.5) * 1.6
		spike.position = Vector3(sin(a) * size * 0.6, size * 0.75, cos(a) * size * 0.3 + size * 0.2)
		spike.rotation = Vector3(0.4, 0, -a * 0.8)
		root.add_child(spike)

	# Glowing eyes facing forward (-Z, the way look_at points).
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = kind["eye"]
	eye_mat.emission_enabled = true
	eye_mat.emission = kind["eye"]
	eye_mat.emission_energy_multiplier = 4.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = size * 0.16
		em.height = size * 0.32
		em.material = eye_mat
		eye.mesh = em
		eye.position = Vector3(side * size * 0.38, size * 0.2, -size * 0.85)
		root.add_child(eye)

	var glow := OmniLight3D.new()
	glow.light_color = kind["eye"]
	glow.light_energy = 0.6
	glow.omni_range = 3.0
	glow.position = Vector3(0, 0, -size)
	root.add_child(glow)
	return root
