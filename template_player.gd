extends Node2D

@export var move_speed := 420.0
@export var transition_duration := 0.25

@onready var camera: Camera2D = $Camera2D
@onready var fade: ColorRect = get_node("../TransitionOverlay/Fade")

var current_area: MapArea
var transitioning := false

func _ready() -> void:
	current_area = _area_at(global_position)
	if current_area:
		_set_active_area(current_area)
		_set_camera_bounds(current_area)

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
			await _transition_to_area(neighbor, "west")
			return
		destination.x = current_area.global_position.x + 0.1
	elif destination.x > current_area.global_position.x + current_area.area_size.x:
		var neighbor := _neighbor_for_exit(current_area, "east", destination)
		if neighbor:
			await _transition_to_area(neighbor, "east")
			return
		destination.x = current_area.global_position.x + current_area.area_size.x - 0.1

	if destination.y < current_area.global_position.y:
		var neighbor := _neighbor_for_exit(current_area, "north", destination)
		if neighbor:
			await _transition_to_area(neighbor, "north")
			return
		destination.y = current_area.global_position.y + 0.1
	elif destination.y > current_area.global_position.y + current_area.area_size.y:
		var neighbor := _neighbor_for_exit(current_area, "south", destination)
		if neighbor:
			await _transition_to_area(neighbor, "south")
			return
		destination.y = current_area.global_position.y + current_area.area_size.y - 0.1

	global_position = destination
	queue_redraw()

func _area_at(point: Vector2) -> MapArea:
	for node in get_tree().get_nodes_in_group("map_areas"):
		var area := node as MapArea
		if area and Rect2(area.global_position, area.area_size).has_point(point):
			return area
	return null

func _neighbor_for_exit(area: MapArea, direction: String, crossing_point: Vector2) -> MapArea:
	var enabled := false
	var probe := crossing_point
	match direction:
		"north":
			enabled = area.path_north
			probe.y = area.global_position.y - 1.0
		"east":
			enabled = area.path_east
			probe.x = area.global_position.x + area.area_size.x + 1.0
		"south":
			enabled = area.path_south
			probe.y = area.global_position.y + area.area_size.y + 1.0
		"west":
			enabled = area.path_west
			probe.x = area.global_position.x - 1.0
	if not enabled:
		return null
	var neighbor := _area_at(probe)
	if not neighbor:
		return null
	var matched := false
	match direction:
		"north":
			matched = neighbor.path_south and absf(crossing_point.x - (area.global_position.x + area.area_size.x * 0.5)) <= area.path_width * 0.5 and absf(crossing_point.x - (neighbor.global_position.x + neighbor.area_size.x * 0.5)) <= neighbor.path_width * 0.5
		"east":
			matched = neighbor.path_west and absf(crossing_point.y - (area.global_position.y + area.area_size.y * 0.5)) <= area.path_width * 0.5 and absf(crossing_point.y - (neighbor.global_position.y + neighbor.area_size.y * 0.5)) <= neighbor.path_width * 0.5
		"south":
			matched = neighbor.path_north and absf(crossing_point.x - (area.global_position.x + area.area_size.x * 0.5)) <= area.path_width * 0.5 and absf(crossing_point.x - (neighbor.global_position.x + neighbor.area_size.x * 0.5)) <= neighbor.path_width * 0.5
		"west":
			matched = neighbor.path_east and absf(crossing_point.y - (area.global_position.y + area.area_size.y * 0.5)) <= area.path_width * 0.5 and absf(crossing_point.y - (neighbor.global_position.y + neighbor.area_size.y * 0.5)) <= neighbor.path_width * 0.5
	return neighbor if matched else null

func _transition_to_area(next_area: MapArea, exit_direction: String) -> void:
	transitioning = true
	var close_tween := create_tween()
	close_tween.tween_property(fade, "modulate:a", 1.0, transition_duration)
	await close_tween.finished

	_set_active_area(next_area)
	current_area = next_area
	global_position = _entry_position(next_area, exit_direction)
	_set_camera_bounds(next_area)
	await get_tree().process_frame

	var open_tween := create_tween()
	open_tween.tween_property(fade, "modulate:a", 0.0, transition_duration)
	await open_tween.finished
	transitioning = false

func _entry_position(area: MapArea, exit_direction: String) -> Vector2:
	match exit_direction:
		"north":
			return area.global_position + Vector2(area.area_size.x * 0.5, area.area_size.y - 96.0)
		"east":
			return area.global_position + Vector2(96.0, area.area_size.y * 0.5)
		"south":
			return area.global_position + Vector2(area.area_size.x * 0.5, 96.0)
		"west":
			return area.global_position + Vector2(area.area_size.x - 96.0, area.area_size.y * 0.5)
	return area.global_position + area.area_size * 0.5

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
