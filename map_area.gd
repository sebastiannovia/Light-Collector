@tool
extends Node2D
class_name MapArea

@export var area_label := "NEW AREA":
	set(value):
		area_label = value
		_redraw_layout()

@export var area_size := Vector2(3840, 2160):
	set(value):
		area_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_redraw_layout()
		if Engine.is_editor_hint():
			call_deferred("_snap_to_neighbor")

@export var grid_step := 256.0:
	set(value):
		grid_step = maxf(value, 1.0)
		_redraw_layout()

@export var show_grid := true:
	set(value):
		show_grid = value
		_redraw_layout()

@export_group("Side Paths")
@export var path_north := false:
	set(value):
		path_north = value
		_redraw_layout()

@export var path_east := false:
	set(value):
		path_east = value
		_redraw_layout()

@export var path_south := false:
	set(value):
		path_south = value
		_redraw_layout()

@export var path_west := false:
	set(value):
		path_west = value
		_redraw_layout()

@export var path_width := 220.0:
	set(value):
		path_width = maxf(value, 40.0)
		_redraw_layout()

@export_group("Editor Placement")
@export var snap_to_neighbors := true
@export_range(1.0, 512.0, 1.0) var snap_distance := 96.0

const MAJOR_GRID_EVERY := 4
var _snapping := false

func _ready() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and snap_to_neighbors and not _snapping:
		call_deferred("_snap_to_neighbor")

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var area_rect := Rect2(Vector2.ZERO, area_size)
	draw_rect(area_rect, Color("152231"))

	if show_grid:
		var index := 0
		var x := grid_step
		while x < area_size.x:
			var major := index % MAJOR_GRID_EVERY == MAJOR_GRID_EVERY - 1
			draw_line(Vector2(x, 0), Vector2(x, area_size.y), Color(0.35, 0.48, 0.60, 0.34 if major else 0.16), 2.0 if major else 1.0)
			x += grid_step
			index += 1
		index = 0
		var y := grid_step
		while y < area_size.y:
			var major := index % MAJOR_GRID_EVERY == MAJOR_GRID_EVERY - 1
			draw_line(Vector2(0, y), Vector2(area_size.x, y), Color(0.35, 0.48, 0.60, 0.34 if major else 0.16), 2.0 if major else 1.0)
			y += grid_step
			index += 1

	draw_rect(area_rect, Color("568699"), false, 5.0)
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(36, 58), area_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("d8e6ef"))
		draw_string(font, Vector2(36, area_size.y - 30), "AREA  %d × %d    •    GRID  %d" % [int(area_size.x), int(area_size.y), int(grid_step)], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("9bb0c7"))

func _redraw_layout() -> void:
	queue_redraw()
	var path_guides := get_node_or_null("PathGuides")
	if path_guides:
		path_guides.queue_redraw()

func _snap_to_neighbor() -> void:
	if _snapping or not is_inside_tree() or not snap_to_neighbors:
		return
	var nearest_position := global_position
	var nearest_distance := snap_distance
	for node in get_parent().get_children():
		var neighbor := node as MapArea
		if not neighbor or neighbor == self:
			continue
		var neighbor_position := neighbor.global_position
		var centered_x := neighbor_position.x + (neighbor.area_size.x - area_size.x) * 0.5
		var centered_y := neighbor_position.y + (neighbor.area_size.y - area_size.y) * 0.5
		var candidates := [
			Vector2(neighbor_position.x + neighbor.area_size.x, centered_y),
			Vector2(neighbor_position.x - area_size.x, centered_y),
			Vector2(centered_x, neighbor_position.y + neighbor.area_size.y),
			Vector2(centered_x, neighbor_position.y - area_size.y),
		]
		for candidate in candidates:
			var distance := global_position.distance_to(candidate)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_position = candidate
	if nearest_position != global_position:
		_snapping = true
		global_position = nearest_position
		_snapping = false
