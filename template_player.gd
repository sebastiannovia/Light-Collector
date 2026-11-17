extends Node2D

signal area_changed(area: MapArea)
signal light_count_changed(count: int)

const MINIMAP_SCRIPT = preload("res://minimap_control.gd")
const LIGHT_HUD_SCRIPT = preload("res://light_hud.gd")
const LIGHT_MARKER_SCRIPT = preload("res://light_placement_marker.gd")

@export var move_speed := 420.0
@export var transition_duration := 0.25

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

@export_group("Light HUD")
@export var light_hud_visible := true
@export var light_hud_position := Vector2(28.0, 28.0)
@export_range(0, 999999, 1) var starting_light_count := 0

@onready var camera: Camera2D = $Camera2D
@onready var fade: ColorRect = get_node("../TransitionOverlay/Fade")

var current_area: MapArea
var transitioning := false
var minimap_view: Control
var light_count := 0
var light_hud: Control

func _ready() -> void:
	add_to_group("map_player")
	light_count = starting_light_count
	current_area = _area_at(global_position)
	if current_area:
		_set_active_area(current_area)
		_set_camera_bounds(current_area)
	if minimap_enabled:
		call_deferred("_create_minimap")
	if light_hud_visible:
		call_deferred("_create_light_hud")

func _process(delta: float) -> void:
	if transitioning or not current_area:
		return
	var horizontal := int(Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)) - int(Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A))
	var vertical := int(Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)) - int(Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W))
	var direction := Vector2(horizontal, vertical).normalized()
	var destination := global_position + direction * move_speed * delta

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

	global_position = destination
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M and minimap_view:
		minimap_view.visible = not minimap_view.visible
	elif event.keycode == KEY_E:
		_try_place_path_lights()

func add_light(amount: int = 1) -> void:
	if amount <= 0:
		return
	light_count += amount
	light_count_changed.emit(light_count)
	if light_hud:
		light_hud.call("set_count", light_count)

func set_light_count(count: int) -> void:
	light_count = maxi(0, count)
	light_count_changed.emit(light_count)
	if light_hud:
		light_hud.call("set_count", light_count)

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

func _create_light_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "LightHUDLayer"
	canvas.layer = 6
	get_parent().add_child(canvas)
	light_hud = Control.new()
	light_hud.name = "LightHUD"
	light_hud.set_script(LIGHT_HUD_SCRIPT)
	canvas.add_child(light_hud)
	light_hud.call("configure", light_count, light_hud_position)

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
	draw_circle(Vector2.ZERO, 24.0, Color("ffd166"))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 48, Color("101923"), 4.0)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color("101923"), 3.0)
	draw_line(Vector2(0, -10), Vector2(0, 10), Color("101923"), 3.0)
