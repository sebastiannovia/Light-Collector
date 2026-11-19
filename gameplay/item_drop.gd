@tool
extends Node2D
class_name WorldItemDrop

signal collected(item_id: StringName, quantity: int)

@export var item_id: StringName = &"stone"
@export var item_definition: ItemDefinition:
	set(value):
		item_definition = value
		if item_definition and not item_definition.item_id.is_empty():
			item_id = item_definition.item_id
		queue_redraw()
@export var quantity := 1
@export var collection_radius := 54.0
@export var display_quantity := true

var _database: ItemDatabase
var _feedback := ""

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	add_to_group("world_item_drops")
	var databases := get_tree().get_nodes_in_group("item_database")
	if not databases.is_empty():
		_database = databases[0] as ItemDatabase
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if quantity <= 0:
		queue_free()
		return
	var definition := _get_item_definition()
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
	var definition := _get_item_definition()
	var color := definition.world_color if definition else Color("d69a55")
	var world_texture := definition.world_texture if definition and definition.world_texture else definition.icon if definition else null
	draw_circle(Vector2(0, 8), 17, Color(0, 0, 0, 0.25))
	if world_texture:
		var texture_scale := definition.world_texture_scale if definition else 1.0
		var texture_offset := definition.world_texture_offset if definition else Vector2.ZERO
		var texture_size := world_texture.get_size() * texture_scale
		var texture_origin := -texture_size * 0.5 + texture_offset
		draw_texture_rect(world_texture, Rect2(texture_origin, texture_size), false)
	else:
		draw_circle(Vector2.ZERO, 14, color)
		draw_arc(Vector2.ZERO, 14, 0.0, TAU, 24, Color("f4f0df"), 2.0)
	if display_quantity and quantity > 1:
		draw_string(ThemeDB.fallback_font, Vector2(12, -12), str(quantity), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	if Engine.is_editor_hint():
		var editor_name := definition.display_name if definition else String(item_id) if not item_id.is_empty() else "Item Drop"
		draw_string(ThemeDB.fallback_font, Vector2(-72, 36), editor_name, HORIZONTAL_ALIGNMENT_CENTER, 144, 13, Color("f4f0df"))

func _get_item_definition() -> ItemDefinition:
	if item_definition:
		return item_definition
	if not _database:
		var databases := get_tree().get_nodes_in_group("item_database")
		if not databases.is_empty():
			_database = databases[0] as ItemDatabase
	return _database.get_definition(item_id) if _database else null
