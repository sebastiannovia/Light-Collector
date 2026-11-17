extends RefCounted
class_name ItemDropSpawner

static func spawn_item_drop(item_id: StringName, quantity: int, world_position: Vector2) -> Node2D:
	if quantity <= 0:
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.current_scene:
		return null
	var database_nodes := tree.get_nodes_in_group("item_database")
	if database_nodes.is_empty():
		push_warning("Cannot spawn item drop: no ItemDatabase is active.")
		return null
	var database := database_nodes[0] as ItemDatabase
	var definition := database.get_definition(item_id)
	if not definition:
		push_warning("Cannot spawn item drop: unknown item '%s'." % String(item_id))
		return null
	var scene := definition.drop_scene
	if not scene:
		scene = load("res://gameplay/item_drop.tscn") as PackedScene
	if not scene:
		return null
	var drop := scene.instantiate() as Node2D
	if not drop:
		return null
	drop.set("item_id", item_id)
	drop.set("quantity", quantity)
	tree.current_scene.add_child(drop)
	drop.global_position = world_position
	return drop
