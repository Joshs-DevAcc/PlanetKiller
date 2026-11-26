class_name Shop
extends Node3D
## The shop counter at the base. Walk up to it and press E to buy upgrades.

const USE_DISTANCE := 3.5
const ROWS := [
	{"kind": "tool", "title": "Mining Tool", "stat": "tool"},
	{"kind": "dig", "title": "Dig Size", "stat": "dig"},
	{"kind": "backpack", "title": "Backpack", "stat": "backpack"},
	{"kind": "weapon", "title": "Weapon", "stat": "weapon"},
	{"kind": "armor", "title": "Armor", "stat": "armor"},
]

var player: Player

var _ui: CanvasLayer
var _money_label: Label
var _rows := {} # kind -> {"current": Label, "next": Label, "button": Button}


func _ready() -> void:
	_build_counter()
	_build_ui()
	Game.money_changed.connect(func(_m: int) -> void: _refresh())
	Game.upgraded.connect(func(_k: String) -> void: _refresh())


func is_player_near() -> bool:
	return player != null and player.global_position.distance_to(global_position) < USE_DISTANCE


func is_open() -> bool:
	return _ui.visible


func open() -> void:
	_ui.visible = true
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_ui.visible = false
	Game.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if is_open():
		if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			close()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and is_player_near():
		open()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open() and not is_player_near():
		close()


# --- 3D counter -------------------------------------------------------------------

func _build_counter() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.22)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.95, 0.7, 0.2)
	trim.emission_enabled = true
	trim.emission = Color(0.95, 0.7, 0.2)
	trim.emission_energy_multiplier = 0.6

	var body := StaticBody3D.new()
	add_child(body)
	var counter := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 1.1, 0.9)
	box.material = wood
	counter.mesh = box
	counter.position = Vector3(0, 0.55, 0)
	body.add_child(counter)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = counter.position
	body.add_child(col)

	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(2.6, 0.08, 1.05)
	top_mesh.material = trim
	top.mesh = top_mesh
	top.position = Vector3(0, 1.14, 0)
	add_child(top)

	# Posts holding up the sign.
	for i in 2:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 2.4, 0.12)
		post_mesh.material = wood
		post.mesh = post_mesh
		post.position = Vector3(-1.1 + i * 2.2, 1.2, -0.35)
		add_child(post)
	var sign_board := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(2.6, 0.5, 0.08)
	sign_mesh.material = trim
	sign_board.mesh = sign_mesh
	sign_board.position = Vector3(0, 2.4, -0.35)
	add_child(sign_board)

	var label := Label3D.new()
	label.text = "SHOP"
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 12
	label.position = Vector3(0, 2.4, -0.3)
	add_child(label)

	var hint := Label3D.new()
	hint.text = "press E"
	hint.font_size = 40
	hint.pixel_size = 0.005
	hint.outline_size = 10
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.position = Vector3(0, 1.6, 0.3)
	add_child(hint)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.omni_range = 5.0
	light.light_energy = 1.0
	light.position = Vector3(0, 2.0, 0.8)
	add_child(light)


# --- Menu -------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	_ui.visible = false
	add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.09, 0.96)
	style.border_color = Color(0.95, 0.7, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _label("SHOP", 32, Color(0.95, 0.75, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_money_label = _label("", 28, Color(0.55, 1.0, 0.6))
	header.add_child(_money_label)

	for row in ROWS:
		box.add_child(HSeparator.new())
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18)
		box.add_child(line)
		var info := VBoxContainer.new()
		info.custom_minimum_size = Vector2(380, 0)
		line.add_child(info)
		info.add_child(_label(row["title"], 22, Color.WHITE))
		var current := _label("", 16, Color(0.8, 0.8, 0.8))
		info.add_child(current)
		var next := _label("", 16, Color(0.6, 0.9, 1.0))
		info.add_child(next)
		var button := Button.new()
		button.add_theme_stylebox_override("normal", _button_style(Color(0.2, 0.55, 0.3)))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.25, 0.68, 0.36)))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.15, 0.45, 0.25)))
		button.add_theme_stylebox_override("disabled", _button_style(Color(0.25, 0.25, 0.25)))
		button.custom_minimum_size = Vector2(150, 50)
		button.add_theme_font_size_override("font_size", 20)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kind: String = row["kind"]
		button.pressed.connect(func() -> void: _buy(kind))
		line.add_child(button)
		_rows[kind] = {"current": current, "next": next, "button": button}

	box.add_child(HSeparator.new())
	box.add_child(_label("Press E or Esc to close", 14, Color(1, 1, 1, 0.6)))


func _buy(kind: String) -> void:
	if Game.buy(kind):
		Game.show_toast("Upgraded!")
	else:
		Game.show_toast("Not enough money")


func _refresh() -> void:
	_money_label.text = "$%d" % Game.money
	for kind in _rows:
		var r: Dictionary = _rows[kind]
		var ladder := Game.ladder(kind)
		var cur: Dictionary = ladder[Game.level(kind)]
		var next := Game.next_upgrade(kind)
		r["current"].text = "Now: " + _describe(kind, cur)
		var button: Button = r["button"]
		if next.is_empty():
			r["next"].text = "Maxed out"
			button.text = "MAX"
			button.disabled = true
		else:
			r["next"].text = "Next: " + _describe(kind, next)
			button.text = "$%d" % next["cost"]
			button.disabled = Game.money < next["cost"]


func _describe(kind: String, entry: Dictionary) -> String:
	match kind:
		"tool":
			return "%s  (power %.1f)" % [entry["name"], entry["power"]]
		"dig":
			return "%.1f block radius" % entry["radius"]
		"backpack":
			return "holds %d blocks" % entry["capacity"]
		"weapon":
			return "%s  (%d damage, %.0f shots/s)" % [entry["name"], entry["damage"], entry["shots_per_second"]]
		"armor":
			return "%s  (%d health)" % [entry["name"], entry["health"]]
	return ""


func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
