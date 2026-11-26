class_name Hud
extends CanvasLayer
## On-screen info: money, backpack, depth, what you are aiming at, mining progress.

var player: Player
var shop: Shop

var _money: Label
var _bag: Label
var _depth: Label
var _tool: Label
var _prompt: Label
var _target: Label
var _progress: ProgressBar
var _toast: Label
var _toast_time := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_money = _label(root, 28, Color(0.55, 1.0, 0.6))
	_money.position = Vector2(20, 14)
	_bag = _label(root, 18)
	_bag.position = Vector2(20, 56)
	_depth = _label(root, 18)
	_depth.position = Vector2(20, 82)
	_tool = _label(root, 16, Color(1, 1, 1, 0.85))
	_tool.position = Vector2(20, 108)

	_prompt = _label(root, 22, Color(1.0, 0.85, 0.4))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(400, 0)
	_prompt.position += Vector2(-200, 90)

	var crosshair := _label(root, 26)
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_target = _label(root, 18)
	_target.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target.custom_minimum_size = Vector2(400, 0)
	_target.position += Vector2(-200, 28)

	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(160, 10)
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_progress.position += Vector2(-80, 56)
	_progress.max_value = 1.0
	root.add_child(_progress)

	_toast = _label(root, 22, Color(1.0, 0.9, 0.4))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.custom_minimum_size = Vector2(700, 0)
	_toast.position += Vector2(-350, 20)

	var help := _label(root, 14, Color(1, 1, 1, 0.7))
	help.text = "WASD move   Space jump   Shift sprint   Hold left click mine   E shop   R back to base   Esc free mouse"
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(20, -34)

	Game.toast.connect(_on_toast)


func _process(delta: float) -> void:
	_money.text = "$%d" % Game.money
	var bag_text := "Backpack %d / %d" % [Game.backpack_count(), Game.backpack_capacity()]
	if Game.backpack_count() > 0:
		bag_text += "   (worth $%d)" % Game.backpack_value()
	if Game.is_backpack_full():
		bag_text += "   FULL"
	_bag.text = bag_text

	_tool.text = "%s   Dig size %.1f" % [Game.tool()["name"], Game.dig_radius()]
	_prompt.text = "Press E to shop" if shop and shop.is_player_near() and not shop.is_open() else ""

	if player:
		var feet_y := floori(player.global_position.y - 0.85 + 0.2)
		var depth := WorldConfig.SURFACE_Y - feet_y
		_depth.text = "Depth %dm" % depth if depth > 0 else "Surface"
		if player.target["hit"]:
			var id: int = player.target["id"]
			var value := Blocks.value(id)
			var extra := ""
			if Blocks.hardness(id) < 0.0:
				extra = "  (unbreakable)"
			elif value > 0:
				extra = "  $%d" % value
			_target.text = Blocks.block_name(id) + extra
		else:
			_target.text = ""
		_progress.value = player.mine_progress
		_progress.visible = player.mine_progress > 0.0

	_toast_time = maxf(_toast_time - delta, 0.0)
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func _on_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.0


func _label(parent: Control, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
