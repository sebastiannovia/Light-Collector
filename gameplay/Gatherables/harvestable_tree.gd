@tool
extends Node2D
class_name HarvestableTree

const TREE_OCCLUSION_SHADER := preload("res://gameplay/Gatherables/tree_occlusion.gdshader")
const DEFAULT_STUMP := preload("res://Assets/Stumps/forest_treestump_01.png")
const STUMPS_BY_TREE := {
	"forest_sprucetree_01": preload("res://Assets/Stumps/forest_sprucetreestump_01.png"),
	"forest_sprucetree_02": preload("res://Assets/Stumps/forest_sprucetreestump_02.png"),
	"forest_sprucetree_03": preload("res://Assets/Stumps/forest_sprucetreestump_03.png"),
	"forest_talltree_01": preload("res://Assets/Stumps/forest_talltreestump_01.png"),
	"forest_tree_01": DEFAULT_STUMP,
	"forest_tree_02": preload("res://Assets/Stumps/forest_treestump_02.png"),
	"forest_tree_03": preload("res://Assets/Stumps/forest_treestump_03.png"),
	"forest_tree_04": preload("res://Assets/Stumps/forest_treestump_04and05.png"),
	"forest_tree_05": preload("res://Assets/Stumps/forest_treestump_04and05.png"),
	"forest_tree_withhole_01": DEFAULT_STUMP,
	"forest_tree_withhole_05": preload("res://Assets/Stumps/forest_treestump_04and05.png"),
}
const HOLLOW_EYE_FRAMES: Array[Texture2D] = [
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_01.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_02.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_03.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_04.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_05.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_06.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_07.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_08.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_09.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_10.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_11.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_12.png"),
	preload("res://Assets/LurkyEyesForHoles/eyes_animation_frame_13.png"),
]

signal hit(hit_count: int, hits_required: int)
signal mined(item_id: StringName, quantity: int)

static var _used_texture_rects: Dictionary[Texture2D, Rect2] = {}

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
@export var stump_texture_override: Texture2D
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
var _has_hollow_eyes := false
var _eye_frame_index := 0
var _eye_frame_elapsed := 0.0
var _eye_pause_remaining := 0.0
var _occlusion_material: ShaderMaterial
var _player: Node2D
var _player_sprite: Sprite2D
var _stump_texture: Texture2D
var _stump_draw_rect: Rect2
var _map_area: MapArea
var _shake_tween: Tween
var _visual_shake_offset: Vector2 = Vector2.ZERO
var _visual_shake_rotation: float = 0.0

func _ready() -> void:
	_choose_random_tree_texture()
	if Engine.is_editor_hint():
		queue_redraw()
		return
	var ancestor := get_parent()
	while ancestor and not ancestor is MapArea:
		ancestor = ancestor.get_parent()
	_map_area = ancestor as MapArea
	z_as_relative = false
	add_to_group("solid_tree_obstacles")
	add_to_group("e_interactables")
	hits_required = maxi(1, hits_required)
	wood_quantity = maxi(1, wood_quantity)
	_remaining_yield = wood_quantity
	queue_redraw()

func blocks_player_motion(from_position: Vector2, to_position: Vector2, player_radius: float) -> bool:
	if _depleted:
		return false
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

static func get_used_texture_rect(texture: Texture2D) -> Rect2:
	if not _used_texture_rects.has(texture):
		var used := Rect2(Vector2.ZERO, texture.get_size())
		var source := texture.get_image()
		if source and not source.is_empty():
			if not source.is_compressed() or source.decompress() == OK:
				var opaque := source.get_used_rect()
				if opaque.has_area():
					used = Rect2(opaque)
		_used_texture_rects[texture] = used
	return _used_texture_rects[texture]


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_visible_in_tree():
		_nearby_player = false
		return
	_update_hollow_eyes(delta)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("map_player") as Node2D
		_player_sprite = _player.get_node_or_null("PlayerSprite") as Sprite2D if _player else null
	var was_nearby := _nearby_player
	_nearby_player = not _depleted and is_instance_valid(_player) and _player.global_position.distance_to(global_position) <= interaction_range
	if was_nearby != _nearby_player or (_shake_tween and _shake_tween.is_running()):
		queue_redraw()
	# Keep the depth scale consistent with the player's feet.
	var sort_y := global_position.y
	if _map_area:
		sort_y -= _map_area.global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)
	_update_occlusion()


func _update_occlusion() -> void:
	if not is_instance_valid(_player_sprite) or not _player_sprite.texture or not _is_player_behind_tree():
		if material:
			material = null
		return
	if not _occlusion_material:
		_occlusion_material = ShaderMaterial.new()
		_occlusion_material.shader = TREE_OCCLUSION_SHADER
		_occlusion_material.set_shader_parameter("occluded_opacity", occluded_opacity_percent / 100.0)
	var sprite_rect := _player_sprite.get_rect()
	var to_sprite := _player_sprite.global_transform.affine_inverse()
	# Project each tree fragment into the current player frame's texture.
	var origin := to_sprite.origin - sprite_rect.position
	_occlusion_material.set_shader_parameter("player_uv_x", Vector3(to_sprite.x.x, to_sprite.y.x, origin.x) / sprite_rect.size.x)
	_occlusion_material.set_shader_parameter("player_uv_y", Vector3(to_sprite.x.y, to_sprite.y.y, origin.y) / sprite_rect.size.y)
	_occlusion_material.set_shader_parameter("player_texture", _player_sprite.texture)
	_occlusion_material.set_shader_parameter("player_flip_h", _player_sprite.flip_h)
	_occlusion_material.set_shader_parameter("player_flip_v", _player_sprite.flip_v)
	if material != _occlusion_material:
		material = _occlusion_material


func _is_player_behind_tree() -> bool:
	var player_depth_y := float(_player.call("get_depth_sort_y")) if _player.has_method("get_depth_sort_y") else _player.global_position.y
	if player_depth_y >= global_position.y:
		return false
	var tree_rect := Rect2(texture_offset + Vector2(-55.0, -188.0), Vector2(110.0, 188.0))
	if _selected_tree_texture:
		var size := _selected_tree_texture.get_size()
		var visible_rect := get_used_texture_rect(_selected_tree_texture)
		tree_rect = Rect2(texture_offset + (Vector2(-size.x * 0.5, -size.y) + visible_rect.position) * tree_scale, visible_rect.size * tree_scale)
	var shake := Transform2D(_visual_shake_rotation, _visual_shake_offset)
	var player_rect := _player_sprite.global_transform * _player_sprite.get_rect()
	return (global_transform * shake * tree_rect).intersects(player_rect)


func _choose_random_tree_texture() -> void:
	_selected_tree_texture = null
	_has_hollow_eyes = false
	if tree_textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_selected_tree_texture = tree_textures[rng.randi_range(0, tree_textures.size() - 1)]
	_has_hollow_eyes = _selected_tree_texture != null and _selected_tree_texture.resource_path.contains("withhole")
	_eye_frame_index = 0
	_eye_frame_elapsed = 0.0
	_eye_pause_remaining = 0.0

func _update_hollow_eyes(delta: float) -> void:
	if not _has_hollow_eyes or HOLLOW_EYE_FRAMES.is_empty():
		return
	if _eye_pause_remaining > 0.0:
		_eye_pause_remaining = maxf(0.0, _eye_pause_remaining - delta)
		return
	_eye_frame_elapsed += delta
	if _eye_frame_elapsed < 0.075:
		return
	_eye_frame_elapsed = 0.0
	_eye_frame_index += 1
	if _eye_frame_index >= HOLLOW_EYE_FRAMES.size():
		_eye_frame_index = 0
		_eye_pause_remaining = 1.8
	queue_redraw()

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
	remove_from_group("solid_tree_obstacles")
	remove_from_group("e_interactables")
	inventory.set_feedback("Collected %d Wood" % collected)
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.finished.connect(_show_stump, CONNECT_ONE_SHOT)
	else:
		_show_stump()
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

func _show_stump() -> void:
	var tree_name := _selected_tree_texture.resource_path.get_file().get_basename() if _selected_tree_texture else ""
	_stump_texture = stump_texture_override if stump_texture_override else STUMPS_BY_TREE.get(tree_name, DEFAULT_STUMP)
	var tree_base := 0.0
	if _selected_tree_texture:
		tree_base = get_used_texture_rect(_selected_tree_texture).end.y - _selected_tree_texture.get_height()
	var stump_size := _stump_texture.get_size()
	var stump_base := get_used_texture_rect(_stump_texture).end.y
	var stump_origin := Vector2(-stump_size.x * 0.5, tree_base - stump_base) * tree_scale
	_stump_draw_rect = Rect2(texture_offset + stump_origin, stump_size * tree_scale)
	material = null
	_occlusion_material = null
	set_process(false)
	queue_redraw()

func _player_inventory(player: Node) -> PlayerInventory:
	if player is PlayerInventory:
		return player as PlayerInventory
	return player.get_node_or_null("PlayerInventory") as PlayerInventory

func _draw() -> void:
	if _stump_texture:
		draw_texture_rect(_stump_texture, _stump_draw_rect, false)
		return
	draw_set_transform(_visual_shake_offset, _visual_shake_rotation)
	if _selected_tree_texture:
		var drawn_size := _selected_tree_texture.get_size() * tree_scale
		var top_left := Vector2(-drawn_size.x * 0.5, -drawn_size.y) + texture_offset
		draw_texture_rect(_selected_tree_texture, Rect2(top_left, drawn_size), false)
	else:
		_draw_placeholder_tree()
	if _has_hollow_eyes and not HOLLOW_EYE_FRAMES.is_empty():
		var eye_texture := HOLLOW_EYE_FRAMES[_eye_frame_index]
		var eye_offset := Vector2(4.5, -123.0) if _selected_tree_texture.resource_path.contains("withhole_01") else Vector2(-12.5, -65.0)
		var eye_size := eye_texture.get_size() * tree_scale
		var eye_rect := Rect2(texture_offset + eye_offset * tree_scale - eye_size * 0.5, eye_size)
		draw_texture_rect(eye_texture, eye_rect, false)

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
