extends Node2D
class_name WorldItemDrop

signal collected(item_id: StringName, quantity: int)

@export var item_id: StringName
@export var quantity := 1
@export var collection_radius := 54.0
@export var display_quantity := true

var _database: ItemDatabase
var _feedback := ""

func _ready() -> void:
	add_to_group("world_item_drops")
	var databases := get_tree().get_nodes_in_group("item_database")
	if not databases.is_empty():
		_database = databases[0] as ItemDatabase
	queue_redraw()

func _process(_delta: float) -> void:
	if quantity <= 0:
		queue_free()
		return
	var definition := _database.get_definition(item_id) if _database else null
	if not definition:
		return
	for node in get_tree().get_nodes_in_group("map_player"):
		if node is Node2D and (node as Node2D).global_position.distance_to(global_position) <= collection_radius:
			var inventories := get_tree().get_nodes_in_group("player_inventory")
			if inventories.is_empty():
				return
			var inventory := inventories[0] as PlayerInventory
			var accepted := inventory.add_item(item_id, quantity)
			if accepted > 0:
				quantity -= accepted
				_feedback = "Collected %d %s" % [accepted, definition.display_name]
				collected.emit(item_id, accepted)
				queue_redraw()
				if quantity <= 0:
					queue_free()
			elif quantity > 0:
				inventory.set_feedback("Inventory full")
				_feedback = "Full"
				queue_redraw()
			return

func _draw() -> void:
	var definition := _database.get_definition(item_id) if _database else null
	var color := definition.world_color if definition else Color("d69a55")
	draw_circle(Vector2(0, 8), 17, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, 14, color)
	draw_arc(Vector2.ZERO, 14, 0.0, TAU, 24, Color("f4f0df"), 2.0)
	if display_quantity and quantity > 1:
		draw_string(ThemeDB.fallback_font, Vector2(12, -12), str(quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
