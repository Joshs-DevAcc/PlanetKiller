extends Node
## Global game state (autoloaded as "Game"): money, backpack and tool stats.
## Upgrades in later steps should change the numbers here.

signal money_changed(amount: int)
signal backpack_changed
signal toast(text: String)

var money := 0
## Block id -> count
var backpack := {}
var backpack_capacity := 40
## Multiplies mining speed. 1.0 = starter pickaxe.
var pickaxe_power := 1.0
## How far away you can mine, in blocks.
var reach := 5.0


func _ready() -> void:
	_setup_input()


func backpack_count() -> int:
	var total := 0
	for id in backpack:
		total += backpack[id]
	return total


func backpack_value() -> int:
	var total := 0
	for id in backpack:
		total += backpack[id] * Blocks.value(id)
	return total


func is_backpack_full() -> bool:
	return backpack_count() >= backpack_capacity


## Returns false when there is no room.
func add_to_backpack(id: int) -> bool:
	if is_backpack_full():
		return false
	backpack[id] = backpack.get(id, 0) + 1
	backpack_changed.emit()
	return true


## Sells everything in the backpack. Returns the money earned.
func sell_all() -> int:
	var count := backpack_count()
	if count == 0:
		return 0
	var earned := backpack_value()
	backpack.clear()
	money += earned
	backpack_changed.emit()
	money_changed.emit(money)
	toast.emit("Sold %d blocks for $%d" % [count, earned])
	return earned


func show_toast(text: String) -> void:
	toast.emit(text)


func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("recall", [KEY_R])
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
