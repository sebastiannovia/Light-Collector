extends Node
class_name PlayerInventory

signal inventory_changed
signal item_added(item_id: StringName, quantity: int)
signal item_removed(item_id: StringName, quantity: int)
signal item_add_failed(item_id: StringName, quantity: int)

@export var rows := 4
@export var columns := 6
@export var item_database_path: NodePath

var _stacks: Array[Dictionary] = []
var _database: ItemDatabase
var _ui: Control
var _message := ""

func _ready() -> void:
	rows = maxi(1, rows)
	columns = maxi(1, columns)
	_stacks.resize(rows * columns)
	for i in _stacks.size():
		_stacks[i] = {"item_id": &"", "quantity": 0}
	_database = get_node_or_null(item_database_path) as ItemDatabase
	if not _database:
		var matches := get_tree().get_nodes_in_group("item_database")
		if not matches.is_empty():
			_database = matches[0] as ItemDatabase
	add_to_group("player_inventory")

func configure_database(database: ItemDatabase) -> void:
	_database = database

func add_item(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var definition := _definition(item_id)
	if not definition:
		item_add_failed.emit(item_id, quantity)
		return 0
	var allowed := mini(quantity, maxi(0, definition.max_carry_quantity - get_item_quantity(item_id)))
	allowed = mini(allowed, _free_capacity_for(item_id, definition))
	var remaining := allowed
	var accepted := 0
	for stack in _stacks:
		if remaining <= 0:
			break
		if stack.item_id == item_id and stack.quantity < definition.max_stack_size:
			var moved := mini(remaining, definition.max_stack_size - stack.quantity)
			stack.quantity += moved
			remaining -= moved
	for stack in _stacks:
		if remaining <= 0:
			break
		if stack.quantity == 0:
			var moved := mini(remaining, definition.max_stack_size)
			stack.item_id = item_id
			stack.quantity = moved
			remaining -= moved
	accepted = allowed - remaining
	if accepted > 0:
		item_added.emit(item_id, accepted)
		inventory_changed.emit()
	if accepted < quantity:
		if get_item_quantity(item_id) >= definition.max_carry_quantity:
			_message = "Can't carry more %s. Item limit reached." % definition.display_name
		elif _free_capacity_for(item_id, definition) <= 0:
			_message = "Inventory full. Make room to collect %s." % definition.display_name
		else:
			_message = "Could only collect %d %s. Make room or check its carry limit." % [accepted, definition.display_name]
		item_add_failed.emit(item_id, quantity - accepted)
	return accepted

func remove_item(item_id: StringName, quantity: int) -> bool:
	if quantity <= 0 or not has_item(item_id, quantity):
		return false
	var remaining := quantity
	for index in _stacks.size():
		var stack := _stacks[index]
		if stack.item_id != item_id:
			continue
		var removed := mini(remaining, stack.quantity)
		stack.quantity -= removed
		remaining -= removed
		if stack.quantity == 0:
			stack.item_id = &""
		_stacks[index] = stack
		if remaining == 0:
			break
	item_removed.emit(item_id, quantity)
	inventory_changed.emit()
	return true

func move_item(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= _stacks.size() or to_index < 0 or to_index >= _stacks.size():
		return false
	if from_index == to_index:
		return false
	var source: Dictionary = _stacks[from_index]
	var target: Dictionary = _stacks[to_index]
	if source.quantity <= 0:
		return false
	if target.quantity <= 0:
		_stacks[to_index] = source
		_stacks[from_index] = {"item_id": &"", "quantity": 0}
	elif source.item_id == target.item_id:
		var definition := _definition(source.item_id)
		if not definition:
			return false
		var moved := mini(source.quantity, maxi(0, definition.max_stack_size - target.quantity))
		if moved <= 0:
			return false
		target.quantity += moved
		source.quantity -= moved
		_stacks[to_index] = target
		if source.quantity <= 0:
			source = {"item_id": &"", "quantity": 0}
		_stacks[from_index] = source
	else:
		_stacks[from_index] = target
		_stacks[to_index] = source
	inventory_changed.emit()
	return true

func get_item_quantity(item_id: StringName) -> int:
	var total := 0
	for stack in _stacks:
		if stack.item_id == item_id:
			total += stack.quantity
	return total

func has_item(item_id: StringName, quantity: int = 1) -> bool:
	return quantity >= 0 and get_item_quantity(item_id) >= quantity

func can_add_item(item_id: StringName, quantity: int) -> bool:
	if quantity <= 0:
		return true
	var definition := _definition(item_id)
	return definition != null and get_item_quantity(item_id) + quantity <= definition.max_carry_quantity and _free_capacity_for(item_id, definition) >= quantity

func get_slot_capacity() -> int:
	return rows * columns

func get_slots() -> Array[Dictionary]:
	return _stacks.duplicate(true)

func get_item_definition(item_id: StringName) -> ItemDefinition:
	return _definition(item_id)

func get_feedback() -> String:
	return _message

func set_feedback(message: String) -> void:
	_message = message

func toggle_ui() -> void:
	if not _ui:
		_create_ui()
	_ui.visible = not _ui.visible

func _free_capacity_for(item_id: StringName, definition: ItemDefinition) -> int:
	var free := 0
	for stack in _stacks:
		if stack.quantity == 0:
			free += definition.max_stack_size
		elif stack.item_id == item_id:
			free += maxi(0, definition.max_stack_size - stack.quantity)
	return free

func _definition(item_id: StringName) -> ItemDefinition:
	if not _database:
		var matches := get_tree().get_nodes_in_group("item_database")
		if not matches.is_empty():
			_database = matches[0] as ItemDatabase
	return _database.get_definition(item_id) if _database else null

func _create_ui() -> void:
	var ui_script := load("res://gameplay/inventory_ui.gd")
	var layer := CanvasLayer.new()
	layer.name = "InventoryUILayer"
	layer.layer = 20
	get_tree().root.add_child(layer)
	_ui = Control.new()
	_ui.name = "InventoryWindow"
	_ui.set_script(ui_script)
	_ui.visible = false
	layer.add_child(_ui)
	_ui.call("configure", self)

