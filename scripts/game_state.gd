extends Node
## Global game state (autoloaded as "Game"): money, backpack and upgrade levels.

signal money_changed(amount: int)
signal backpack_changed
signal upgraded(kind: String)
signal toast(text: String)
signal health_changed(health: float, max_health: float)
signal player_hurt(amount: float)
signal player_died

var money := 0
## Material id -> amount (floats, since digging removes partial blocks).
var backpack := {}
var tool_level := 0
var dig_level := 0
var backpack_level := 0
var weapon_level := 0
var armor_level := 0
var health := 100.0
var kills := 0
## How far away you can mine, in blocks.
var reach := 5.5
## True while a menu (like the shop) has the mouse.
var ui_open := false


func _ready() -> void:
	_setup_input()


# --- Upgrades -------------------------------------------------------------------

func tool() -> Dictionary:
	return Upgrades.TOOLS[tool_level]


func dig_radius() -> float:
	return Upgrades.DIG_SIZE[dig_level]["radius"]


func weapon() -> Dictionary:
	return Upgrades.WEAPONS[weapon_level]


func max_health() -> float:
	return Upgrades.ARMOR[armor_level]["health"]


func damage_player(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	player_hurt.emit(amount)
	health_changed.emit(health, max_health())
	if health <= 0.0:
		player_died.emit()


func heal_player(amount: float) -> void:
	var before := health
	health = minf(health + amount, max_health())
	if health != before:
		health_changed.emit(health, max_health())


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func backpack_capacity() -> int:
	return Upgrades.BACKPACK[backpack_level]["capacity"]


## The upgrade ladders by name, for the shop.
func ladder(kind: String) -> Array:
	match kind:
		"tool": return Upgrades.TOOLS
		"dig": return Upgrades.DIG_SIZE
		"backpack": return Upgrades.BACKPACK
		"weapon": return Upgrades.WEAPONS
		"armor": return Upgrades.ARMOR
	return []


func level(kind: String) -> int:
	match kind:
		"tool": return tool_level
		"dig": return dig_level
		"backpack": return backpack_level
		"weapon": return weapon_level
		"armor": return armor_level
	return 0


## Next level's entry, or an empty dictionary when maxed.
func next_upgrade(kind: String) -> Dictionary:
	var l := ladder(kind)
	var next := level(kind) + 1
	return l[next] if next < l.size() else {}


func buy(kind: String) -> bool:
	var next := next_upgrade(kind)
	if next.is_empty() or money < next["cost"]:
		return false
	money -= next["cost"]
	match kind:
		"tool": tool_level += 1
		"dig": dig_level += 1
		"backpack": backpack_level += 1
		"weapon": weapon_level += 1
		"armor":
			armor_level += 1
			health = max_health()
			health_changed.emit(health, max_health())
	money_changed.emit(money)
	upgraded.emit(kind)
	return true


# --- Backpack -------------------------------------------------------------------

func backpack_amount() -> float:
	var total := 0.0
	for id in backpack:
		total += backpack[id]
	return total


func backpack_count() -> int:
	return floori(backpack_amount())


func backpack_value() -> int:
	var total := 0.0
	for id in backpack:
		total += backpack[id] * Blocks.value(id)
	return floori(total)


func is_backpack_full() -> bool:
	return backpack_amount() >= backpack_capacity() - 0.01


## Adds dug material. Anything past the backpack's capacity is lost.
func add_materials(amounts: Dictionary) -> void:
	for id in amounts:
		if not Blocks.is_collectable(id):
			continue
		var room := backpack_capacity() - backpack_amount()
		if room <= 0.0:
			break
		backpack[id] = backpack.get(id, 0.0) + minf(amounts[id], room)
	backpack_changed.emit()


## Sells everything in the backpack. Returns the money earned.
func sell_all() -> int:
	var count := backpack_count()
	var earned := backpack_value()
	if earned <= 0 and count == 0:
		return 0
	backpack.clear()
	money += earned
	backpack_changed.emit()
	money_changed.emit(money)
	toast.emit("Sold %d blocks for $%d" % [count, earned])
	return earned


func show_toast(text: String) -> void:
	toast.emit(text)


# --- Input ----------------------------------------------------------------------

func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("recall", [KEY_R])
	_add_keys("interact", [KEY_E])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("attack", right)
	if not InputMap.has_action("mine"):
		InputMap.add_action("mine")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("mine", mouse)


func _add_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
