@tool
extends Node2D
class_name HarvestableRock

signal hit(hit_count: int, hits_required: int)
signal mined(item_id: StringName, quantity: int)

@export_range(1, 20, 1) var hits_required := 4
@export_range(1, 999, 1) var stone_quantity := 3
@export_range(32.0, 256.0, 1.0) var interaction_range := 176.0
@export var prompt_text := "[E] Mine Rock"

var hit_count := 0
var _nearby_player := false
var _depleted := false
var _remaining_yield := 0

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	add_to_group("e_interactables")
	hits_required = maxi(1, hits_required)
	stone_quantity = maxi(1, stone_quantity)
	_remaining_yield = stone_quantity
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var was_nearby := _nearby_player
	_nearby_player = false
	if not _depleted:
		for node in get_tree().get_nodes_in_group("map_player"):
			if node is Node2D and (node as Node2D).global_position.distance_to(global_position) <= interaction_range:
				_nearby_player = true
				break
	if was_nearby != _nearby_player:
		queue_redraw()

func is_player_nearby() -> bool:
	return _nearby_player and not _depleted

func interact(player: Node) -> bool:
	if not is_player_nearby():
		return false
	hit_count += 1
	hit.emit(hit_count, hits_required)
	var inventory := _player_inventory(player)
	if hit_count < hits_required:
		if inventory:
			inventory.set_feedback("Rock hit %d / %d" % [hit_count, hits_required])
		queue_redraw()
		return true

	if not inventory:
		hit_count = hits_required - 1
		queue_redraw()
		return false
	var collected := inventory.add_item(&"stone", _remaining_yield)
	if collected <= 0:
		hit_count = hits_required - 1
		inventory.set_feedback("Inventory full. Make room to collect Stone.")
		queue_redraw()
		return false
	_remaining_yield -= collected
	mined.emit(&"stone", collected)
	if _remaining_yield > 0:
		hit_count = 0
		inventory.set_feedback("Collected %d Stone. %d remain; make room and mine again." % [collected, _remaining_yield])
		queue_redraw()
		return true

	_depleted = true
	inventory.set_feedback("Collected %d Stone" % collected)
	queue_redraw()
	queue_free()
	return true

func _player_inventory(player: Node) -> PlayerInventory:
	if player is PlayerInventory:
		return player as PlayerInventory
	return player.get_node_or_null("PlayerInventory") as PlayerInventory

func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-110, -49), "%s  %d/%d" % [prompt_text, hit_count, hits_required], HORIZONTAL_ALIGNMENT_CENTER, 220, 16, Color("ffd166"))
	for index in hits_required:
		var bar_color := Color("d69a55") if index < hit_count else Color("263746")
		draw_rect(Rect2(-hits_required * 9.0 + index * 18.0, 43, 14, 5), bar_color)
