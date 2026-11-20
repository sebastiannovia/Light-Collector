extends Node2D

signal area_changed(area: MapArea)
signal light_count_changed(count: int)
signal health_changed(current: float, maximum: float)
signal sleep_changed(current: float, maximum: float)

const MINIMAP_SCRIPT = preload("res://minimap_control.gd")
const PLAYER_HUD_SCRIPT = preload("res://gameplay/player_hud.gd")
const DEFAULT_PLAYER_HUD_STYLE = preload("res://gameplay/player_hud_default.tres")
const LIGHT_MARKER_SCRIPT = preload("res://light_placement_marker.gd")
const PLAYER_FRONT_TEXTURE = preload("res://Assets/Player/Front.png")
const PLAYER_BACK_TEXTURE = preload("res://Assets/Player/Back.png")
const PLAYER_SIDE_TEXTURE = preload("res://Assets/Player/Side.png")
const PAUSE_MENU_SCENE = preload("res://gameplay/pause_menu/pause_menu.tscn")

@export var move_speed := 420.0
@export var transition_duration := 0.25
@export_range(0.0, 96.0, 1.0) var tree_collision_radius := 28.0

@export_group("Combat")
@export_range(1, 1000, 1) var attack_damage := 80
@export_range(24.0, 180.0, 1.0) var attack_reach := 104.0
@export_range(30.0, 180.0, 1.0) var attack_arc_degrees := 110.0
@export_range(0.05, 1.0, 0.01) var attack_duration := 0.30

@export_group("Dash")
@export_range(1.0, 1200.0, 1.0) var dash_speed := 900.0
@export_range(0.05, 0.5, 0.01) var dash_duration := 0.14
@export_range(0.0, 3.0, 0.05) var dash_cooldown := 0.55

const PLAYER_SIZE := Vector2(110.0, 185.0)
const PLAYER_FEET_OFFSET := Vector2(0.0, PLAYER_SIZE.y * 0.5)

@export_group("Minimap")
@export var minimap_enabled := true
@export_enum("Top Left", "Top Right", "Bottom Left", "Bottom Right") var minimap_corner := 1
@export var minimap_offset := Vector2(28.0, 28.0)
@export var minimap_panel_size := Vector2(360.0, 250.0)
@export_range(0.4, 3.0, 0.01) var minimap_map_scale := 1.0
@export_range(4.0, 36.0, 1.0) var minimap_padding := 16.0
@export_range(0.0, 24.0, 1.0) var minimap_room_gap := 7.0
@export_range(0.5, 6.0, 0.1) var minimap_line_width := 2.0
@export_range(0.0, 5.0, 0.1) var minimap_line_wobble := 1.4
@export_range(0.1, 3.0, 0.1) var minimap_reveal_duration := 0.8
@export var minimap_show_area_names := true
@export var minimap_show_unknown_paths := true
@export var minimap_handwritten_font: Font

@export_group("Player Status")
@export_range(1.0, 1000.0, 1.0) var health_max := 100.0
@export_range(0.0, 1000.0, 1.0) var health_current := 100.0
@export_range(1.0, 1000.0, 1.0) var sleep_max := 100.0
@export_range(0.0, 1000.0, 1.0) var sleep_current := 100.0
@export_range(0.0, 3.0, 0.05) var damage_invulnerability_duration := 0.65
@export_range(0, 999999, 1) var starting_light_count := 0

@export_group("Player HUD")
@export var player_hud_visible := true
@export var player_hud_style: PlayerHUDStyle = DEFAULT_PLAYER_HUD_STYLE

@onready var camera: Camera2D = $Camera2D
@onready var fade: ColorRect = get_node("../TransitionOverlay/Fade")
@onready var legacy_hitbox: Area2D = get_node_or_null("hitbox")
@onready var player_sprite: Sprite2D = $PlayerSprite

var current_area: MapArea
var transitioning := false
var minimap_view: Control
var light_count := 0
var player_hud: Control
var is_attacking := false
var _hit_targets: Dictionary = {}
var facing_direction := Vector2.DOWN
var _swing_direction := Vector2.DOWN
var _swing_progress := -1.0
var _dash_direction := Vector2.DOWN
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _damage_invulnerability_left := 0.0
var _sword_hit_shape := CircleShape2D.new()

func _ready() -> void:
	var pause_layer := CanvasLayer.new()
	pause_layer.name = "PauseMenuLayer"
	pause_layer.layer = 20
	get_tree().root.add_child(pause_layer)
	pause_layer.add_child(PAUSE_MENU_SCENE.instantiate())
	z_as_relative = false
	if legacy_hitbox:
		legacy_hitbox.monitoring = false
		legacy_hitbox.monitorable = false
	_sword_hit_shape.radius = 30.0
	_update_player_sprite()
	add_to_group("map_player")
	light_count = starting_light_count
	health_current = clampf(health_current, 0.0, health_max)
	sleep_current = clampf(sleep_current, 0.0, sleep_max)
	current_area = _area_at(global_position)
	if current_area:
		_set_active_area(current_area)
		_set_camera_bounds(current_area)
	_update_depth_order()
	if minimap_enabled:
		call_deferred("_create_minimap")
	if player_hud_visible:
		call_deferred("_create_player_hud")

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		attack()
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)
	_dash_time_left = maxf(0.0, _dash_time_left - delta)
	_damage_invulnerability_left = maxf(0.0, _damage_invulnerability_left - delta)
	if transitioning or not current_area:
		return
	var horizontal := int(Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)) - int(Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A))
	var vertical := int(Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)) - int(Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W))
	var direction := Vector2(horizontal, vertical).normalized()
	if not direction.is_zero_approx():
		facing_direction = direction
		_update_player_sprite()
	var movement := direction * move_speed
	if _dash_time_left > 0.0:
		movement = _dash_direction * dash_speed
	var destination := global_position + movement * delta

	if destination.x < current_area.global_position.x:
		var neighbor := _neighbor_for_exit(current_area, "west", destination)
		if neighbor:
			await _transition_to_area(neighbor, "west", destination)
			return
		destination.x = current_area.global_position.x + 0.1
	elif destination.x > current_area.global_position.x + current_area.area_size.x:
		var neighbor := _neighbor_for_exit(current_area, "east", destination)
		if neighbor:
			await _transition_to_area(neighbor, "east", destination)
			return
		destination.x = current_area.global_position.x + current_area.area_size.x - 0.1

	if destination.y < current_area.global_position.y:
		var neighbor := _neighbor_for_exit(current_area, "north", destination)
		if neighbor:
			await _transition_to_area(neighbor, "north", destination)
			return
		destination.y = current_area.global_position.y + 0.1
	elif destination.y > current_area.global_position.y + current_area.area_size.y:
		var neighbor := _neighbor_for_exit(current_area, "south", destination)
		if neighbor:
			await _transition_to_area(neighbor, "south", destination)
			return
		destination.y = current_area.global_position.y + current_area.area_size.y - 0.1

	global_position = _resolve_tree_collisions(destination)
	_update_depth_order()
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if is_attacking:
		_apply_sword_hit()

func get_depth_sort_y() -> float:
	return global_position.y + PLAYER_SIZE.y * 0.5

func get_visual_size() -> Vector2:
	return PLAYER_SIZE

func _update_depth_order() -> void:
	var sort_y := get_depth_sort_y()
	var area := current_area if current_area else _area_at(global_position)
	if area:
		sort_y -= area.global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)

func _resolve_tree_collisions(destination: Vector2) -> Vector2:
	if not _tree_blocks_motion(global_position, destination):
		return destination
	var horizontal_step := Vector2(destination.x, global_position.y)
	var vertical_step := Vector2(global_position.x, destination.y)
	var horizontal_blocked := _tree_blocks_motion(global_position, horizontal_step)
	var vertical_blocked := _tree_blocks_motion(global_position, vertical_step)
	if not horizontal_blocked and not vertical_blocked:
		return horizontal_step if absf(destination.x - global_position.x) >= absf(destination.y - global_position.y) else vertical_step
	if not horizontal_blocked:
		return horizontal_step
	if not vertical_blocked:
		return vertical_step
	return global_position

func _tree_blocks_motion(from_position: Vector2, to_position: Vector2) -> bool:
	var feet_from := from_position + PLAYER_FEET_OFFSET
	var feet_to := to_position + PLAYER_FEET_OFFSET
	for tree in get_tree().get_nodes_in_group("solid_tree_obstacles"):
		if tree.has_method("blocks_player_motion") and tree.call("blocks_player_motion", feet_from, feet_to, tree_collision_radius):
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SHIFT:
		_start_dash()
	elif event.keycode == KEY_M and minimap_view:
		minimap_view.visible = not minimap_view.visible
	elif event.keycode == KEY_I:
		var inventory := get_node_or_null("PlayerInventory") as PlayerInventory
		if inventory:
			inventory.toggle_ui()
	elif event.keycode == KEY_E:
		_try_interact_with_nearby_object()
	elif event.keycode == KEY_F:
		_try_place_path_lights()

func _try_interact_with_nearby_object() -> bool:
	for interaction_group in ["construction_sites", "e_interactables"]:
		for node in get_tree().get_nodes_in_group(interaction_group):
			if not node.has_method("is_player_nearby") or not node.has_method("interact"):
				continue
			if bool(node.call("is_player_nearby")):
				node.call("interact", self)
				return true
	return false

func add_light(amount: int = 1) -> void:
	if amount <= 0:
		return
	light_count += amount
	light_count_changed.emit(light_count)
	if player_hud:
		player_hud.call("set_lights", light_count)

func set_light_count(count: int) -> void:
	light_count = maxi(0, count)
	light_count_changed.emit(light_count)
	if player_hud:
		player_hud.call("set_lights", light_count)

func set_health(value: float) -> void:
	health_current = clampf(value, 0.0, health_max)
	health_changed.emit(health_current, health_max)
	if player_hud:
		player_hud.call("set_health", health_current, health_max)

func take_damage(amount: float) -> void:
	if amount <= 0.0 or health_current <= 0.0 or _damage_invulnerability_left > 0.0:
		return
	set_health(health_current - amount)
	_damage_invulnerability_left = damage_invulnerability_duration

func set_sleep(value: float) -> void:
	sleep_current = clampf(value, 0.0, sleep_max)
	sleep_changed.emit(sleep_current, sleep_max)
	if player_hud:
		player_hud.call("set_sleep", sleep_current, sleep_max)

func _try_place_path_lights() -> void:
	if not current_area:
		return
	var ground := current_area.get_node_or_null("GroundArt") as TileMapLayer
	if not ground:
		return
	var path_cell := ground.local_to_map(ground.to_local(global_position))
	if not current_area.is_path_tile(path_cell) or current_area.has_light_pair_for_path(path_cell):
		return
	var has_up := current_area.is_path_tile(path_cell + Vector2i.UP)
	var has_right := current_area.is_path_tile(path_cell + Vector2i.RIGHT)
	var has_down := current_area.is_path_tile(path_cell + Vector2i.DOWN)
	var has_left := current_area.is_path_tile(path_cell + Vector2i.LEFT)
	var neighbor_count := int(has_up) + int(has_right) + int(has_down) + int(has_left)
	var light_offsets: Array[Vector2]
	if neighbor_count == 4:
		light_offsets = [Vector2(-1.25, -1.25), Vector2(1.25, -1.25), Vector2(1.25, 1.25), Vector2(-1.25, 1.25)]
	elif neighbor_count == 3:
		if not has_up:
			light_offsets = [Vector2.UP]
		elif not has_right:
			light_offsets = [Vector2.RIGHT]
		elif not has_down:
			light_offsets = [Vector2.DOWN]
		else:
			light_offsets = [Vector2.LEFT]
	else:
		var horizontal_neighbors := int(has_left) + int(has_right)
		var vertical_neighbors := int(has_up) + int(has_down)
		if horizontal_neighbors > vertical_neighbors:
			light_offsets = [Vector2.UP, Vector2.DOWN]
		else:
			light_offsets = [Vector2.LEFT, Vector2.RIGHT]
	if light_count < light_offsets.size():
		return
	var container := current_area.get_light_container()
	if not container:
		return
	var tile_size := Vector2(ground.tile_set.tile_size)
	var path_center := ground.map_to_local(path_cell)
	for offset in light_offsets:
		var marker := Node2D.new()
		marker.set_script(LIGHT_MARKER_SCRIPT)
		marker.position = path_center + offset * tile_size * 0.30
		container.add_child(marker)
	current_area.mark_path_lit(path_cell)
	set_light_count(light_count - light_offsets.size())

func _area_at(point: Vector2) -> MapArea:
	for node in get_tree().get_nodes_in_group("map_areas"):
		var area := node as MapArea
		if area and Rect2(area.global_position, area.area_size).has_point(point):
			return area
	return null

func _neighbor_for_exit(area: MapArea, direction: String, crossing_point: Vector2) -> MapArea:
	var own_centers := area.get_pathway_centers(direction)
	if own_centers.is_empty():
		return null

	var probe := crossing_point
	match direction:
		"north":
			probe.y = area.global_position.y - 1.0
		"east":
			probe.x = area.global_position.x + area.area_size.x + 1.0
		"south":
			probe.y = area.global_position.y + area.area_size.y + 1.0
		"west":
			probe.x = area.global_position.x - 1.0
	var neighbor := _area_at(probe)
	if not neighbor:
		return null

	var opposite_side := ""
	match direction:
		"north":
			opposite_side = "south"
		"east":
			opposite_side = "west"
		"south":
			opposite_side = "north"
		"west":
			opposite_side = "east"
	var neighbor_centers := neighbor.get_pathway_centers(opposite_side)
	var crossing_coordinate := crossing_point.x if direction == "north" or direction == "south" else crossing_point.y
	for own_center in own_centers:
		if absf(crossing_coordinate - own_center) > area.path_width * 0.5:
			continue
		for neighbor_center in neighbor_centers:
			if not is_equal_approx(own_center, neighbor_center):
				continue
			if absf(crossing_coordinate - neighbor_center) <= neighbor.path_width * 0.5:
				return neighbor
	return null

func _transition_to_area(next_area: MapArea, exit_direction: String, crossing_point: Vector2) -> void:
	transitioning = true
	var close_tween := create_tween()
	close_tween.tween_property(fade, "modulate:a", 1.0, transition_duration)
	await close_tween.finished

	_set_active_area(next_area)
	current_area = next_area
	global_position = _entry_position(next_area, exit_direction, crossing_point)
	_set_camera_bounds(next_area)
	await get_tree().process_frame

	var open_tween := create_tween()
	open_tween.tween_property(fade, "modulate:a", 0.0, transition_duration)
	await open_tween.finished
	area_changed.emit(next_area)
	transitioning = false

func _create_minimap() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HandDrawnMinimapLayer"
	canvas.layer = 5
	get_parent().add_child(canvas)
	minimap_view = Control.new()
	minimap_view.name = "HandDrawnMinimap"
	minimap_view.set_script(MINIMAP_SCRIPT)
	canvas.add_child(minimap_view)
	minimap_view.call("configure", self, {
		"corner": minimap_corner,
		"offset": minimap_offset,
		"panel_size": minimap_panel_size,
		"map_scale": minimap_map_scale,
		"padding": minimap_padding,
		"room_gap": minimap_room_gap,
		"line_width": minimap_line_width,
		"line_wobble": minimap_line_wobble,
		"reveal_duration": minimap_reveal_duration,
		"show_area_names": minimap_show_area_names,
		"show_unknown_paths": minimap_show_unknown_paths,
		"handwritten_font": minimap_handwritten_font,
	})

func _create_player_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PlayerHUDLayer"
	canvas.layer = 6
	get_parent().add_child(canvas)
	player_hud = Control.new()
	player_hud.name = "PlayerHUD"
	player_hud.set_script(PLAYER_HUD_SCRIPT)
	canvas.add_child(player_hud)
	player_hud.call("configure", player_hud_style, health_current, health_max, sleep_current, sleep_max, light_count)
	var inventory := get_node_or_null("PlayerInventory") as PlayerInventory
	if inventory and not inventory.item_added.is_connected(_on_inventory_item_added):
		inventory.item_added.connect(_on_inventory_item_added)
	var controls_hint := Label.new()
	controls_hint.name = "ControlsHint"
	controls_hint.text = "WASD / Arrow Keys: Move   •   Space: Attack   •   Shift: Dash   •   E: Interact / Chop   •   F: Place Lights   •   I: Inventory   •   M: Toggle Map"
	controls_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls_hint.offset_left = 20.0
	controls_hint.offset_top = -46.0
	controls_hint.offset_right = -20.0
	controls_hint.offset_bottom = -14.0
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls_hint.add_theme_font_size_override("font_size", 16)
	controls_hint.add_theme_color_override("font_color", Color("f4f0df"))
	controls_hint.add_theme_color_override("font_outline_color", Color("101923"))
	controls_hint.add_theme_constant_override("outline_size", 4)
	controls_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(controls_hint)

func _on_inventory_item_added(item_id: StringName, quantity: int) -> void:
	if not player_hud:
		return
	var inventory := get_node_or_null("PlayerInventory") as PlayerInventory
	var definition := inventory.get_item_definition(item_id) if inventory else null
	var display_name := definition.display_name if definition and not definition.display_name.is_empty() else String(item_id)
	var icon: Texture2D = definition.icon if definition and definition.icon else definition.world_texture if definition else null
	var fallback_color := definition.world_color if definition else Color("d69a55")
	player_hud.call("notify_item", display_name, quantity, icon, fallback_color)

func _entry_position(area: MapArea, exit_direction: String, crossing_point: Vector2) -> Vector2:
	match exit_direction:
		"north":
			return Vector2(_closest_pathway_center(area, "south", crossing_point.x), area.global_position.y + area.area_size.y - 96.0)
		"east":
			return Vector2(area.global_position.x + 96.0, _closest_pathway_center(area, "west", crossing_point.y))
		"south":
			return Vector2(_closest_pathway_center(area, "north", crossing_point.x), area.global_position.y + 96.0)
		"west":
			return Vector2(area.global_position.x + area.area_size.x - 96.0, _closest_pathway_center(area, "east", crossing_point.y))
	return area.global_position + area.area_size * 0.5

func _closest_pathway_center(area: MapArea, side: String, coordinate: float) -> float:
	var centers := area.get_pathway_centers(side)
	var closest_center := coordinate
	var closest_distance := INF
	for center in centers:
		var distance := absf(center - coordinate)
		if distance < closest_distance:
			closest_distance = distance
			closest_center = center
	return closest_center

func _set_active_area(active_area: MapArea) -> void:
	for node in get_tree().get_nodes_in_group("map_areas"):
		var area := node as MapArea
		if area:
			area.visible = area == active_area

func _set_camera_bounds(area: MapArea) -> void:
	camera.limit_left = int(area.global_position.x)
	camera.limit_top = int(area.global_position.y)
	camera.limit_right = int(area.global_position.x + area.area_size.x)
	camera.limit_bottom = int(area.global_position.y + area.area_size.y)

func _draw() -> void:
	_draw_sword_swing()

func _update_player_sprite() -> void:
	if not player_sprite:
		return
	if absf(facing_direction.x) > absf(facing_direction.y):
		player_sprite.texture = PLAYER_SIDE_TEXTURE
		player_sprite.flip_h = facing_direction.x < 0.0
	else:
		player_sprite.flip_h = false
		player_sprite.texture = PLAYER_BACK_TEXTURE if facing_direction.y < 0.0 else PLAYER_FRONT_TEXTURE


func attack() -> void:
	if is_attacking:
		return
	is_attacking = true
	_swing_direction = facing_direction
	_swing_progress = 0.0
	_hit_targets.clear()
	var swing_tween := create_tween()
	swing_tween.tween_method(_set_swing_progress, 0.0, 1.0, attack_duration)
	swing_tween.finished.connect(_finish_swing)

func _apply_sword_hit() -> void:
	if _swing_progress < 0.0:
		return
	var facing_angle := _swing_direction.angle()
	var swing_start := facing_angle - deg_to_rad(attack_arc_degrees * 0.5)
	var swing_end := facing_angle + deg_to_rad(attack_arc_degrees * 0.5)
	var blade_angle := lerpf(swing_start, swing_end, clampf(_swing_progress, 0.0, 1.0))
	var blade_radius := attack_reach * (0.74 + 0.08 * sin(_swing_progress * PI))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _sword_hit_shape
	query.transform = Transform2D(0.0, global_position + Vector2.RIGHT.rotated(blade_angle) * blade_radius)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var body := result.get("collider") as Node2D
		if not body or not body.name.to_lower().begins_with("monster") or not body.has_method("take_damage"):
			continue
		var target_id := body.get_instance_id()
		if _hit_targets.has(target_id):
			continue
		var to_target := body.global_position - global_position
		if to_target.is_zero_approx():
			continue
		if to_target.normalized().dot(_swing_direction) < cos(deg_to_rad(attack_arc_degrees * 0.5 + 20.0)):
			continue
		_hit_targets[target_id] = true
		body.call("take_damage", attack_damage, global_position)

func _set_swing_progress(value: float) -> void:
	_swing_progress = value
	queue_redraw()

func _finish_swing() -> void:
	is_attacking = false
	_swing_progress = -1.0
	queue_redraw()

func _draw_sword_swing() -> void:
	if _swing_progress < 0.0:
		return
	var facing_angle := _swing_direction.angle()
	var start_angle := facing_angle - deg_to_rad(attack_arc_degrees * 0.5)
	var end_angle := facing_angle + deg_to_rad(attack_arc_degrees * 0.5)
	var trail_radius := attack_reach * (0.74 + 0.08 * sin(_swing_progress * PI))
	var trail_alpha := 0.85 * (1.0 - _swing_progress * 0.55)
	var center := _swing_direction * 22.0
	draw_arc(center, trail_radius, start_angle, end_angle, 28, Color(0.45, 0.88, 1.0, trail_alpha), 12.0, true)
	var blade_angle := lerpf(start_angle, end_angle, _swing_progress)
	var blade_direction := Vector2.RIGHT.rotated(blade_angle)
	var blade_start := center + blade_direction * (trail_radius - 18.0)
	var blade_end := center + blade_direction * (trail_radius + 22.0)
	draw_line(blade_start, blade_end, Color(0.08, 0.14, 0.2, trail_alpha), 10.0, true)
	draw_line(blade_start, blade_end, Color(0.9, 0.98, 1.0, trail_alpha), 5.0, true)

func _start_dash() -> void:
	if _dash_cooldown_left > 0.0 or _dash_time_left > 0.0 or transitioning:
		return
	var horizontal := int(Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)) - int(Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A))
	var vertical := int(Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)) - int(Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W))
	var input_direction := Vector2(horizontal, vertical).normalized()
	_dash_direction = input_direction if not input_direction.is_zero_approx() else facing_direction
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown

func _on_hitbox_body_entered(_body: Node2D) -> void:
	# The old rectangular Area2D is kept disabled for existing player scenes.
	pass
