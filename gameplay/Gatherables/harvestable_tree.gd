@tool
extends Node2D
class_name HarvestableTree

const TREE_OCCLUSION_SHADER := preload("res://gameplay/Gatherables/tree_occlusion.gdshader")

signal hit(hit_count: int, hits_required: int)
signal mined(item_id: StringName, quantity: int)

@export_group("Tree Appearance")
@export var tree_textures: Array[Texture2D] = []:
	set(value):
		tree_textures = value
		_choose_random_tree_texture()
		queue_redraw()
@export_range(0.1, 4.0, 0.05) var tree_scale := 1.0:
	set(value):
		tree_scale = value
		queue_redraw()
@export var texture_offset := Vector2.ZERO:
	set(value):
		texture_offset = value
		queue_redraw()

@export_group("Harvesting")
@export_range(1, 20, 1) var hits_required := 4
@export_range(1, 999, 1) var wood_quantity := 3
@export_range(32.0, 256.0, 1.0) var interaction_range := 176.0
@export var prompt_text := "[E] Cut Tree"

@export_group("Hit Animation")
@export_range(0.0, 24.0, 0.5) var hit_shake_distance := 4.0
@export_range(0.0, 15.0, 0.5) var hit_shake_rotation_degrees := 4.0
@export_range(0.05, 0.6, 0.01) var hit_shake_duration := 0.18

@export_group("Tree Occlusion")
@export_range(16.0, 180.0, 1.0) var occlusion_radius := 82.0
@export_range(1.0, 80.0, 1.0) var occlusion_edge_softness := 26.0
@export_range(0.0, 100.0, 1.0) var occluded_opacity_percent := 20.0:
	set(value):
		occluded_opacity_percent = clampf(value, 0.0, 100.0)
		if _occlusion_material:
			_occlusion_material.set_shader_parameter("occluded_opacity", occluded_opacity_percent / 100.0)

@export_group("Tree Collision")
@export_range(8.0, 128.0, 1.0) var trunk_collision_radius := 42.0
@export var trunk_collision_offset := Vector2.ZERO

var hit_count := 0
var _nearby_player := false
var _depleted := false
var _remaining_yield := 0
var _selected_tree_texture: Texture2D
var _occlusion_material: ShaderMaterial
var _occluding_player: Node2D
var _shake_tween: Tween
var _visual_shake_offset: Vector2 = Vector2.ZERO
var _visual_shake_rotation: float = 0.0

func _ready() -> void:
	_choose_random_tree_texture()
	if Engine.is_editor_hint():
		queue_redraw()
		return
	z_as_relative = false
	add_to_group("solid_tree_obstacles")
	add_to_group("e_interactables")
	hits_required = maxi(1, hits_required)
	wood_quantity = maxi(1, wood_quantity)
	_remaining_yield = wood_quantity
	_occlusion_material = ShaderMaterial.new()
	_occlusion_material.shader = TREE_OCCLUSION_SHADER
	_occlusion_material.set_shader_parameter("fade_enabled", false)
	_occlusion_material.set_shader_parameter("fade_radius_px", occlusion_radius)
	_occlusion_material.set_shader_parameter("edge_softness_px", occlusion_edge_softness)
	_occlusion_material.set_shader_parameter("occluded_opacity", occluded_opacity_percent / 100.0)
	material = _occlusion_material
	queue_redraw()

func blocks_player_motion(from_position: Vector2, to_position: Vector2, player_radius: float) -> bool:
	var collision_center := global_position + trunk_collision_offset
	var minimum_distance := trunk_collision_radius + player_radius
	var old_distance := from_position.distance_to(collision_center)
	var new_distance := to_position.distance_to(collision_center)
	return new_distance < minimum_distance and new_distance < old_distance

func get_visual_half_width() -> float:
	var widest_texture := 0.0
	for texture in tree_textures:
		if texture:
			widest_texture = maxf(widest_texture, texture.get_width())
	if widest_texture <= 0.0:
		widest_texture = 104.0
	return widest_texture * tree_scale * 0.5

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _shake_tween and _shake_tween.is_running():
		queue_redraw()
	var was_nearby := _nearby_player
	var previous_occluding_player := _occluding_player
	var nearest_player_distance := INF
	_nearby_player = false
	_occluding_player = null
	if not _depleted:
		for node in get_tree().get_nodes_in_group("map_player"):
			if not node is Node2D:
				continue
			var player := node as Node2D
			var distance := player.global_position.distance_to(global_position)
			if distance <= interaction_range:
				_nearby_player = true
			if distance < nearest_player_distance:
				nearest_player_distance = distance
				_occluding_player = player
	var is_occluded := _is_player_behind_tree(_occluding_player)
	# Match the player's depth sort so a tree behind another tree cannot jump in front of it.
	var sort_y := global_position.y
	var map_area := get_parent().get_parent() as MapArea
	if map_area:
		sort_y -= map_area.global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)
	if _occlusion_material:
		_occlusion_material.set_shader_parameter("fade_enabled", is_occluded)
		if is_occluded and is_instance_valid(_occluding_player):
			var viewport_size := get_viewport().get_visible_rect().size
			if viewport_size.x > 0.0 and viewport_size.y > 0.0:
				var player_canvas_position := _occluding_player.get_global_transform_with_canvas() * Vector2.ZERO
				_occlusion_material.set_shader_parameter("player_screen_uv", player_canvas_position / viewport_size)
		if was_nearby != _nearby_player or previous_occluding_player != _occluding_player or is_occluded:
			queue_redraw()
	elif was_nearby != _nearby_player or previous_occluding_player != _occluding_player:
		queue_redraw()

func _is_player_behind_tree(player: Node2D) -> bool:
	if not is_instance_valid(player):
		return false
	var player_depth_y := float(player.call("get_depth_sort_y")) if player.has_method("get_depth_sort_y") else player.global_position.y
	if player_depth_y >= global_position.y:
		return false
	var size := _selected_tree_texture.get_size() * tree_scale if _selected_tree_texture else Vector2(110.0, 188.0)
	var player_local := to_local(player.global_position)
	var top := texture_offset.y - size.y
	var player_size := Vector2(player.call("get_visual_size")) if player.has_method("get_visual_size") else Vector2(48.0, 48.0)
	var player_left := player_local.x - player_size.x * 0.5
	var player_right := player_local.x + player_size.x * 0.5
	var player_top := player_local.y - player_size.y * 0.5
	var player_bottom := player_local.y + player_size.y * 0.5
	var tree_left := texture_offset.x - size.x * 0.5
	var tree_right := texture_offset.x + size.x * 0.5
	return player_bottom > top + 12.0 and player_top < texture_offset.y and player_right >= tree_left - 34.0 and player_left <= tree_right + 34.0

func _choose_random_tree_texture() -> void:
	_selected_tree_texture = null
	if tree_textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_selected_tree_texture = tree_textures[rng.randi_range(0, tree_textures.size() - 1)]

func is_player_nearby() -> bool:
	return _nearby_player and not _depleted

func interact(player: Node) -> bool:
	if not is_player_nearby():
		return false
	hit_count += 1
	hit.emit(hit_count, hits_required)
	_play_chop_shake()
	var inventory := _player_inventory(player)
	if hit_count < hits_required:
		if inventory:
			inventory.set_feedback("Tree chopped %d / %d" % [hit_count, hits_required])
		queue_redraw()
		return true

	if not inventory:
		hit_count = hits_required - 1
		queue_redraw()
		return false
	var collected := inventory.add_item(&"wood", _remaining_yield)
	if collected <= 0:
		hit_count = hits_required - 1
		inventory.set_feedback("Inventory full. Make room to collect Wood.")
		queue_redraw()
		return false
	_remaining_yield -= collected
	mined.emit(&"wood", collected)
	if _remaining_yield > 0:
		hit_count = 0
		inventory.set_feedback("Collected %d Wood. %d remain; make room and chop again." % [collected, _remaining_yield])
		queue_redraw()
		return true

	_depleted = true
	inventory.set_feedback("Collected %d Wood" % collected)
	_free_after_shake()
	return true

func _play_chop_shake() -> void:
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
	_visual_shake_offset = Vector2.ZERO
	_visual_shake_rotation = 0.0
	var direction := -1.0 if hit_count % 2 == 1 else 1.0
	var rotation_amount := deg_to_rad(hit_shake_rotation_degrees) * direction
	var first_duration := hit_shake_duration * 0.25
	var return_duration := hit_shake_duration * 0.25
	var settle_duration := hit_shake_duration * 0.5
	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(self, "_visual_shake_rotation", rotation_amount, first_duration)
	_shake_tween.parallel().tween_property(self, "_visual_shake_offset", Vector2(direction * hit_shake_distance, -hit_shake_distance * 0.2), first_duration)
	_shake_tween.tween_property(self, "_visual_shake_rotation", -rotation_amount * 0.45, return_duration)
	_shake_tween.parallel().tween_property(self, "_visual_shake_offset", Vector2(-direction * hit_shake_distance * 0.4, 0.0), return_duration)
	_shake_tween.tween_property(self, "_visual_shake_rotation", 0.0, settle_duration)
	_shake_tween.parallel().tween_property(self, "_visual_shake_offset", Vector2.ZERO, settle_duration)

func _free_after_shake() -> void:
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.finished.connect(queue_free, CONNECT_ONE_SHOT)
	else:
		queue_free()

func _player_inventory(player: Node) -> PlayerInventory:
	if player is PlayerInventory:
		return player as PlayerInventory
	return player.get_node_or_null("PlayerInventory") as PlayerInventory

func _draw() -> void:
	draw_set_transform(_visual_shake_offset, _visual_shake_rotation)
	if _selected_tree_texture:
		var drawn_size := _selected_tree_texture.get_size() * tree_scale
		var top_left := Vector2(-drawn_size.x * 0.5, -drawn_size.y) + texture_offset
		draw_texture_rect(_selected_tree_texture, Rect2(top_left, drawn_size), false)
	else:
		_draw_placeholder_tree()

	if Engine.is_editor_hint():
		draw_string(ThemeDB.fallback_font, Vector2(-92, 28), "Harvestable Tree", HORIZONTAL_ALIGNMENT_CENTER, 184, 13, Color("f4f0df"))
		return
	if not _nearby_player or _depleted:
		return
	var tree_top := texture_offset.y - (_selected_tree_texture.get_height() * tree_scale if _selected_tree_texture else 188.0)
	draw_string(ThemeDB.fallback_font, Vector2(-130, tree_top - 34.0), "%s  %d/%d" % [prompt_text, hit_count, hits_required], HORIZONTAL_ALIGNMENT_CENTER, 260, 16, Color("ffd166"))
	for index in hits_required:
		var bar_color := Color("75a85a") if index < hit_count else Color("263746")
		draw_rect(Rect2(-hits_required * 9.0 + index * 18.0, tree_top - 15.0, 14, 5), bar_color)

func _draw_placeholder_tree() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 8), Vector2(-13, -47), Vector2(-8, -104),
		Vector2(8, -104), Vector2(13, -47), Vector2(8, 8),
	]), Color("71472f"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, 2), Vector2(-5, -84), Vector2(0, -99),
		Vector2(3, -47), Vector2(8, -32), Vector2(7, 3),
	]), Color("9a6540"))
	draw_circle(Vector2(0, -138), 52, Color("315b39"))
	draw_circle(Vector2(-31, -124), 35, Color("3f7443"))
	draw_circle(Vector2(32, -125), 34, Color("3a6b3e"))
	draw_circle(Vector2(-18, -160), 31, Color("4d824a"))
	draw_circle(Vector2(19, -161), 30, Color("477b46"))
	draw_circle(Vector2(0, -181), 25, Color("55894b"))
	draw_circle(Vector2(-22, -136), 6, Color("75a85a"))
	draw_circle(Vector2(23, -153), 5, Color("75a85a"))
	draw_circle(Vector2(5, -183), 4, Color("86b95f"))
