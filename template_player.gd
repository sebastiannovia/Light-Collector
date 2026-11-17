extends Node2D

signal area_changed(area: MapArea)

const MINIMAP_SCRIPT = preload("res://minimap_control.gd")

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

@onready var camera: Camera2D = $Camera2D
@onready var fade: ColorRect = get_node("../TransitionOverlay/Fade")

var current_area: MapArea
var transitioning := false
var minimap_view: Control

func _ready() -> void:
	add_to_group("map_player")
	current_area = _area_at(global_position)
	if current_area:
		_set_active_area(current_area)
		_set_camera_bounds(current_area)
	if minimap_enabled:
		call_deferred("_create_minimap")

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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and minimap_view:
		minimap_view.visible = not minimap_view.visible

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
