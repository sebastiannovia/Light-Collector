@tool
extends Node2D

const GUIDE_DEPTH := 180.0

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var area := get_parent() as MapArea
	if not area:
		return
	_draw_exit(Vector2(area.area_size.x * 0.5 - area.path_width * 0.5, 0), Vector2(area.path_width, GUIDE_DEPTH), area.path_north, Vector2.UP)
	_draw_exit(Vector2(area.area_size.x - GUIDE_DEPTH, area.area_size.y * 0.5 - area.path_width * 0.5), Vector2(GUIDE_DEPTH, area.path_width), area.path_east, Vector2.RIGHT)
	_draw_exit(Vector2(area.area_size.x * 0.5 - area.path_width * 0.5, area.area_size.y - GUIDE_DEPTH), Vector2(area.path_width, GUIDE_DEPTH), area.path_south, Vector2.DOWN)
	_draw_exit(Vector2(0, area.area_size.y * 0.5 - area.path_width * 0.5), Vector2(GUIDE_DEPTH, area.path_width), area.path_west, Vector2.LEFT)

func _draw_exit(origin: Vector2, size: Vector2, is_open: bool, direction: Vector2) -> void:
	var color := Color("55d7cb", 0.82) if is_open else Color("d96c69", 0.66)
	draw_rect(Rect2(origin, size), color)
	draw_rect(Rect2(origin, size), color.lightened(0.35), false, 5.0)
	var center := origin + size * 0.5
	var tip := center + direction * 42.0
	var back := center - direction * 26.0
	var perpendicular := Vector2(-direction.y, direction.x) * 22.0
	draw_line(back - perpendicular, tip, Color.WHITE, 7.0)
	draw_line(back + perpendicular, tip, Color.WHITE, 7.0)
