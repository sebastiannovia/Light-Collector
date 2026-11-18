@tool
extends Node2D
class_name ConstructionSite

signal resources_deposited(item_id: StringName, quantity: int, stage_index: int)
signal stage_completed(stage_index: int, stage_name: String)
signal construction_completed

@export var construction_config: ConstructionConfig
@export_file("*.tres") var construction_config_path := ""
@export var deposit_offset := Vector2(176, 32)
@export_range(32.0, 512.0, 1.0) var interaction_range := 220.0
@export var site_label := "Construction"
@export var prompt_text := "[E] Deposit Resources"

var current_stage_index := 0
var _deposited: Array[Dictionary] = []
var _nearby_player := false
var _last_feedback := ""
var _visual_instance: Node2D

func _ready() -> void:
	if not construction_config and not construction_config_path.is_empty():
		construction_config = load(construction_config_path) as ConstructionConfig
	if construction_config:
		_initialize_progress()
	queue_redraw()
	if not Engine.is_editor_hint():
		add_to_group("construction_sites")

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var was_nearby := _nearby_player
	_nearby_player = false
	if not is_complete():
		for node in get_tree().get_nodes_in_group("map_player"):
			if node is Node2D and (node as Node2D).global_position.distance_to(to_global(deposit_offset)) <= interaction_range:
				_nearby_player = true
				break
	if was_nearby != _nearby_player:
		queue_redraw()

func is_player_nearby() -> bool:
	return _nearby_player

func interact(player: Node) -> bool:
	if is_complete() or not _nearby_player:
		return false
	var inventory := _find_inventory(player)
	if not inventory:
		_last_feedback = "No inventory available"
		queue_redraw()
		return false
	var stage := _current_stage()
	if not stage:
		return false
	var any_deposited := false
	for requirement_index in stage.requirements.size():
		var requirement := stage.requirements[requirement_index]
		if not requirement or requirement.quantity <= 0:
			continue
		var remaining := requirement.quantity - int(_deposited[requirement_index].quantity)
		var moved := mini(remaining, inventory.get_item_quantity(requirement.item_id))
		if moved <= 0:
			continue
		if inventory.remove_item(requirement.item_id, moved):
			_deposited[requirement_index].quantity += moved
			resources_deposited.emit(requirement.item_id, moved, current_stage_index)
			any_deposited = true
	if any_deposited:
		_last_feedback = "Resources deposited"
		queue_redraw()
		if _stage_is_fulfilled(stage):
			var finished_index := current_stage_index
			stage_completed.emit(finished_index, stage.stage_name)
			current_stage_index += 1
			_initialize_progress()
			if is_complete():
				construction_completed.emit()
	else:
		_last_feedback = "No required resources in inventory"
	queue_redraw()
	return any_deposited

func is_complete() -> bool:
	return construction_config != null and current_stage_index >= construction_config.stages.size()

func get_stage_index() -> int:
	return current_stage_index

func get_stage_count() -> int:
	return construction_config.stages.size() if construction_config else 0

func get_deposited(item_id: StringName) -> int:
	var stage := _current_stage()
	if not stage:
		return 0
	for index in stage.requirements.size():
		if stage.requirements[index] and stage.requirements[index].item_id == item_id:
			return int(_deposited[index].quantity)
	return 0

func _initialize_progress() -> void:
	_deposited.clear()
	var stage := _current_stage()
	if stage:
		for _requirement in stage.requirements:
			_deposited.append({"quantity": 0})
	_refresh_stage_visual()
	queue_redraw()

func _current_stage() -> ConstructionStage:
	if not construction_config or is_complete():
		return null
	return construction_config.stages[current_stage_index]

func _stage_is_fulfilled(stage: ConstructionStage) -> bool:
	for index in stage.requirements.size():
		var requirement := stage.requirements[index]
		if requirement and int(_deposited[index].quantity) < requirement.quantity:
			return false
	return true

func _find_inventory(player: Node) -> PlayerInventory:
	if player is PlayerInventory:
		return player as PlayerInventory
	var child := player.get_node_or_null("PlayerInventory") as PlayerInventory
	if child:
		return child
	var inventories := get_tree().get_nodes_in_group("player_inventory")
	return inventories[0] as PlayerInventory if not inventories.is_empty() else null

func _refresh_stage_visual() -> void:
	if is_instance_valid(_visual_instance):
		_visual_instance.queue_free()
		_visual_instance = null
	var stage := _current_stage()
	if stage and stage.visual_scene:
		_visual_instance = stage.visual_scene.instantiate() as Node2D
		if _visual_instance:
			add_child(_visual_instance)
			_visual_instance.position = Vector2.ZERO

func _draw() -> void:
	var stage := _current_stage()
	var color := stage.visual_color if stage else Color("5b715e")
	if Engine.is_editor_hint():
		color = color.lightened(0.12)
	draw_rect(Rect2(-54, -22, 108, 130), Color("18232c"), true)
	draw_rect(Rect2(-48, -16, 96, 118), color, false, 7.0)
	draw_line(Vector2(-44, 94), Vector2(44, -10), color.lightened(0.2), 6.0)
	draw_line(Vector2(44, 94), Vector2(-44, -10), color.darkened(0.2), 6.0)
	draw_rect(Rect2(-12, 72, 24, 30), Color("152231"), true)
	draw_circle(deposit_offset, 28, Color("152231dd"))
	draw_arc(deposit_offset, 28, 0, TAU, 32, Color("d69a55"), 3.0)
	var requirement_count := stage.requirements.size() if stage else 0
	var editor_preview := Engine.is_editor_hint()
	var footer_lines := 2 if (_nearby_player or editor_preview) and not is_complete() else 1 if not _last_feedback.is_empty() else 0
	var bubble_height := 42.0 + requirement_count * 21.0 + footer_lines * 19.0
	var bubble := Rect2(deposit_offset + Vector2(-166, -bubble_height - 40.0), Vector2(332, bubble_height))
	draw_rect(bubble, Color("152231ee"), true)
	draw_rect(bubble, Color("d69a55"), false, 2.0)
	var title := "Construction complete" if is_complete() else "%s  •  %s" % [site_label, stage.stage_name if stage else "No stages"]
	draw_string(ThemeDB.fallback_font, bubble.position + Vector2(12, 23), title, HORIZONTAL_ALIGNMENT_LEFT, 310, 16, Color("f4f0df"))
	if stage:
		for index in stage.requirements.size():
			var requirement := stage.requirements[index]
			if not requirement:
				continue
			var database_nodes := get_tree().get_nodes_in_group("item_database")
			var definition := (database_nodes[0] as ItemDatabase).get_definition(requirement.item_id) if not database_nodes.is_empty() else null
			var item_display_name := definition.display_name if definition else String(requirement.item_id)
			var deposited := int(_deposited[index].quantity)
			var line := "%s  %d / %d" % [item_display_name, deposited, requirement.quantity]
			draw_string(ThemeDB.fallback_font, bubble.position + Vector2(12, 47 + index * 21), line, HORIZONTAL_ALIGNMENT_LEFT, 300, 15, Color("ffd166") if deposited >= requirement.quantity else Color("dce4e8"))
	if not _last_feedback.is_empty():
		draw_string(ThemeDB.fallback_font, bubble.position + Vector2(12, bubble.size.y - (24.0 if _nearby_player and not is_complete() else 7.0)), _last_feedback, HORIZONTAL_ALIGNMENT_LEFT, 300, 14, Color("a8d5ba"))
	if (_nearby_player or editor_preview) and not is_complete():
		var prompt := "Preview · " + prompt_text if editor_preview else prompt_text
		draw_string(ThemeDB.fallback_font, bubble.position + Vector2(12, bubble.size.y - 5.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, 300, 15, Color("ffd166"))
