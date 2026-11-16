@tool
extends Node2D

const GUIDE_DEPTH := 180.0

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var area := get_parent() as MapArea
	if not area:
		return
	_draw_side(area, "north", Vector2.UP)
	_draw_side(area, "east", Vector2.RIGHT)
	_draw_side(area, "south", Vector2.DOWN)
	_draw_side(area, "west", Vector2.LEFT)

func _draw_side(area: MapArea, side: String, direction: Vector2) -> void:
	var centers := area.get_pathway_centers(side)
	if centers.is_empty():
		_draw_exit(area, side, area.get_default_pathway_center(side), false, direction)
		return
	for center in centers:
		_draw_exit(area, side, center, true, direction)

func _draw_exit(area: MapArea, side: String, world_center: float, is_open: bool, direction: Vector2) -> void:
	var center := world_center - (area.global_position.x if side == "north" or side == "south" else area.global_position.y)
	var origin := Vector2.ZERO
	var size := Vector2.ZERO
	match side:
		"north":
			origin = Vector2(center - area.path_width * 0.5, -GUIDE_DEPTH * 0.5)
			size = Vector2(area.path_width, GUIDE_DEPTH)
		"east":
			origin = Vector2(area.area_size.x - GUIDE_DEPTH * 0.5, center - area.path_width * 0.5)
			size = Vector2(GUIDE_DEPTH, area.path_width)
		"south":
			origin = Vector2(center - area.path_width * 0.5, area.area_size.y - GUIDE_DEPTH * 0.5)
			size = Vector2(area.path_width, GUIDE_DEPTH)
		"west":
			origin = Vector2(-GUIDE_DEPTH * 0.5, center - area.path_width * 0.5)
			size = Vector2(GUIDE_DEPTH, area.path_width)

	var color := Color("55d7cb", 0.82) if is_open else Color("d96c69", 0.66)
	draw_rect(Rect2(origin, size), color)
	draw_rect(Rect2(origin, size), color.lightened(0.35), false, 5.0)
	var exit_center := origin + size * 0.5
	var tip := exit_center + direction * 42.0
	var back := exit_center - direction * 26.0
	var perpendicular := Vector2(-direction.y, direction.x) * 22.0
	draw_line(back - perpendicular, tip, Color.WHITE, 7.0)
	draw_line(back + perpendicular, tip, Color.WHITE, 7.0)
