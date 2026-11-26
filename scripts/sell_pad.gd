class_name SellPad
extends Area3D
## A glowing pad at the base. Step on it to sell everything in your backpack.


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.0, 3.0)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)

	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.4
	cyl.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.45)
	mat.emission_energy_multiplier = 1.5
	cyl.material = mat
	pad.mesh = cyl
	pad.position = Vector3(0, 0.04, 0)
	add_child(pad)

	var label := Label3D.new()
	label.text = "SELL\nstep on to sell your backpack"
	label.font_size = 48
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 12
	label.position = Vector3(0, 2.6, 0)
	add_child(label)

	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.6)
	light.omni_range = 6.0
	light.light_energy = 1.2
	light.position = Vector3(0, 1.0, 0)
	add_child(light)

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		Game.sell_all()
