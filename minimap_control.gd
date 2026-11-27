extends Control
class_name HandDrawnMinimap

const WORLD_ROOM_SIZE := Vector2(3840.0, 2160.0)
const ROOM_SIZE := 32.0

var map_player: Node2D
var panel_size := Vector2(248.0, 176.0)
var map_scale: float = 1.0
var padding := 16.0
var room_gap := 7.0
var line_width := 2.0
var line_wobble := 1.4
var reveal_duration := 0.8
var show_area_names := true
var show_unknown_paths := true
var paper_color := Color("99703fff")
var ink_color := Color("0f0f0fff")
var current_color := Color("b25f42")
var handwritten_font: Font

var _areas: Array[MapArea] = []
var _discovered: Dictionary = {}
var _reveal_progress: Dictionary = {}
var _active_area: MapArea
var _screen_scale := Vector2.ONE
var _screen_origin := Vector2.ZERO
var _clip_rect := Rect2()

func configure(map_owner: Node2D, settings: Dictionary) -> void:
	map_player = map_owner
	panel_size = settings.get("panel_size", panel_size)
	map_scale = settings.get("map_scale", map_scale)
	padding = settings.get("padding", padding)
	room_gap = settings.get("room_gap", room_gap)
	line_width = settings.get("line_width", line_width)
	line_wobble = settings.get("line_wobble", line_wobble)
	reveal_duration = settings.get("reveal_duration", reveal_duration)
	show_area_names = settings.get("show_area_names", show_area_names)
	show_unknown_paths = settings.get("show_unknown_paths", show_unknown_paths)
	paper_color = settings.get("paper_color", paper_color)
	ink_color = settings.get("ink_color", ink_color)
	current_color = settings.get("current_color", current_color)
	handwritten_font = settings.get("handwritten_font", handwritten_font)
	_custom_place(settings.get("corner", 1), settings.get("offset", Vector2(28.0, 28.0)))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_areas()
	if map_player and map_player.has_signal("area_changed"):
		map_player.connect("area_changed", _on_area_changed)
	var starting_area := map_player.get("current_area") as MapArea if map_player else null
	if starting_area:
		_on_area_changed(starting_area)
	queue_redraw()

func _custom_place(corner: int, margin: Vector2) -> void:
	custom_minimum_size = panel_size
	size = panel_size
	var horizontal_right := corner == 1 or corner == 3
	var vertical_bottom := corner == 2 or corner == 3
	anchor_left = 1.0 if horizontal_right else 0.0
	anchor_right = anchor_left
	anchor_top = 1.0 if vertical_bottom else 0.0
	anchor_bottom = anchor_top
	if horizontal_right:
		offset_left = -panel_size.x - margin.x
		offset_right = -margin.x
	else:
		offset_left = margin.x
		offset_right = margin.x + panel_size.x
	if vertical_bottom:
		offset_top = -panel_size.y - margin.y
		offset_bottom = -margin.y
	else:
		offset_top = margin.y
		offset_bottom = margin.y + panel_size.y

func _refresh_areas() -> void:
	_areas.clear()
	for node in get_tree().get_nodes_in_group("map_areas"):
		var area := node as MapArea
		if area:
			_areas.append(area)

func _on_area_changed(area: MapArea) -> void:
	if not is_instance_valid(area):
		return
	_active_area = area
	var area_id := area.get_instance_id()
	if _discovered.has(area_id):
		queue_redraw()
		return
	_discovered[area_id] = area
	_reveal_progress[area_id] = 0.0
	var tween := create_tween()
	tween.tween_method(Callable(self, "_set_reveal_progress").bind(area_id), 0.0, 1.0, reveal_duration)
	queue_redraw()

func _set_reveal_progress(value: float, area_id: int) -> void:
	_reveal_progress[area_id] = value
	queue_redraw()

func _draw() -> void:
	if _areas.is_empty():
		_refresh_areas()
	if _areas.is_empty():
		return
	_draw_paper()
	_update_transform()
	if not _clip_rect.has_area():
		return
	_draw_connections()
	_draw_rooms()
	_draw_player_marker()
	_draw_active_label()

func _draw_paper() -> void:
	draw_rect(Rect2(Vector2.ZERO, panel_size), paper_color)
	var border := _wobbly_rect(Rect2(Vector2(3, 3), panel_size - Vector2(6, 6)), 8182, 1.4)
	draw_polyline(border, ink_color, 1.8, true)
	var inner_border := _wobbly_rect(Rect2(Vector2(7, 7), panel_size - Vector2(14, 14)), 6147, 0.65)
	draw_polyline(inner_border, Color(ink_color, 0.35), 1.0, true)

func _update_transform() -> void:
	var label_height := 20.0 if show_area_names else 0.0
	var content_size := panel_size - Vector2(padding * 2.0, padding * 2.0 + label_height)
	_clip_rect = Rect2(Vector2(padding, padding), content_size)
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		_clip_rect.size = Vector2.ZERO
		return
	var active := _active_area if is_instance_valid(_active_area) else _areas[0]
	var focus_point := active.global_position + active.area_size * 0.5
	_screen_scale = Vector2.ONE * ROOM_SIZE * map_scale / WORLD_ROOM_SIZE
	_screen_origin = _clip_rect.get_center() - focus_point * _screen_scale

func _world_to_screen(world_position: Vector2) -> Vector2:
	return _screen_origin + world_position * _screen_scale

func _map_rect(area: MapArea) -> Rect2:
	var raw_rect := Rect2(_world_to_screen(area.global_position), area.area_size * _screen_scale)
	var inset := minf(room_gap * 0.5, minf(raw_rect.size.x, raw_rect.size.y) * 0.2)
	return raw_rect.grow(-inset)

func _draw_rooms() -> void:
	for area in _areas:
		var area_id := area.get_instance_id()
		var room_rect := _map_rect(area)
		if not _discovered.has(area_id) or not _clip_rect.intersects(room_rect):
			continue
		var progress: float = _reveal_progress.get(area_id, 1.0)
		var seed_value := hash(str(area.get_path()))
		var outline := _wobbly_rect(room_rect, seed_value, line_wobble)
		var fill := area.minimap_color
		fill.a *= 0.45 * progress * progress
		var clipped_outline := _clip_polygon(outline, _clip_rect)
		if clipped_outline.size() >= 3:
			draw_colored_polygon(clipped_outline, fill)
		_draw_partial_line(outline, progress, ink_color, line_width)
		var inset := minf(1.8, minf(room_rect.size.x, room_rect.size.y) * 0.2)
		var second_line := _wobbly_rect(room_rect.grow(-inset), seed_value + 743, line_wobble * 0.75)
		var second_ink := current_color if area == _active_area else Color(ink_color, 0.45)
		var second_progress := clampf((progress - 0.15) / 0.85, 0.0, 1.0)
		_draw_partial_line(second_line, second_progress, second_ink, maxf(1.0, line_width * 0.65))

func _draw_connections() -> void:
	var drawn_connections: Dictionary = {}
	for area in _areas:
		var area_id := area.get_instance_id()
		if not _discovered.has(area_id):
			continue
		for side in ["north", "east", "south", "west"]:
			for center in area.get_pathway_centers(side):
				var neighbor := _neighbor_for_path(area, side, center)
				if not neighbor:
					continue
				var neighbor_id := neighbor.get_instance_id()
				var axis := "horizontal" if side == "north" or side == "south" else "vertical"
				var connection_key := "%d:%d:%s:%d" % [mini(area_id, neighbor_id), maxi(area_id, neighbor_id), axis, roundi(center * 100.0)]
				if drawn_connections.has(connection_key):
					continue
				drawn_connections[connection_key] = true
				var other_side := _opposite_side(side)
				var matched_center := false
				for other_center in neighbor.get_pathway_centers(other_side):
					if is_equal_approx(center, other_center):
						matched_center = true
						break
				if not matched_center:
					continue
				var from := _edge_point(area, side, center)
				var known := _discovered.has(neighbor_id)
				if known:
					var to := _edge_point(neighbor, other_side, center)
					_draw_door(from, to, hash(connection_key))
				elif area == _active_area and show_unknown_paths:
					_draw_exit_mark(from, side)

func _neighbor_for_path(area: MapArea, side: String, center: float) -> MapArea:
	var probe := Vector2.ZERO
	match side:
		"north":
			probe = Vector2(center, area.global_position.y - 1.0)
		"east":
			probe = Vector2(area.global_position.x + area.area_size.x + 1.0, center)
		"south":
			probe = Vector2(center, area.global_position.y + area.area_size.y + 1.0)
		"west":
			probe = Vector2(area.global_position.x - 1.0, center)
	for candidate in _areas:
		if candidate != area and Rect2(candidate.global_position, candidate.area_size).has_point(probe):
			return candidate
	return null

func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"east": return "west"
		"south": return "north"
		"west": return "east"
	return ""

func _edge_point(area: MapArea, side: String, center: float) -> Vector2:
	var rect := _map_rect(area)
	match side:
		"north": return Vector2(_world_to_screen(Vector2(center, area.global_position.y)).x, rect.position.y)
		"east": return Vector2(rect.end.x, _world_to_screen(Vector2(area.global_position.x, center)).y)
		"south": return Vector2(_world_to_screen(Vector2(center, area.global_position.y + area.area_size.y)).x, rect.end.y)
		"west": return Vector2(rect.position.x, _world_to_screen(Vector2(area.global_position.x, center)).y)
	return rect.get_center()

func _draw_door(from: Vector2, to: Vector2, seed_value: int) -> void:
	if from.is_equal_approx(to):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var offset := (to - from).orthogonal().normalized()
	for sign_value: float in [-1.0, 1.0]:
		var edge: Vector2 = offset * (2.0 * sign_value)
		var wobble := offset * rng.randf_range(-line_wobble, line_wobble)
		var stroke := PackedVector2Array([from + edge, from.lerp(to, 0.5) + edge + wobble, to + edge])
		_draw_partial_line(stroke, 1.0, ink_color, maxf(1.0, line_width * 0.7))

func _draw_exit_mark(point: Vector2, side: String) -> void:
	var outward := Vector2.UP
	match side:
		"east": outward = Vector2.RIGHT
		"south": outward = Vector2.DOWN
		"west": outward = Vector2.LEFT
	var across := outward.orthogonal()
	var tip := point + outward * 5.0
	var mark := PackedVector2Array([point - across * 3.0, tip, point + across * 3.0])
	_draw_partial_line(mark, 1.0, ink_color, maxf(1.0, line_width * 0.85))

func _wobbly_rect(rect: Rect2, seed_value: int, amount: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points := PackedVector2Array()
	var top_left := rect.position
	var top_right := Vector2(rect.end.x, rect.position.y)
	var bottom_right := rect.end
	var bottom_left := Vector2(rect.position.x, rect.end.y)
	var corners := [top_left, top_right, bottom_right, bottom_left]
	for side_index in range(4):
		var start: Vector2 = corners[side_index]
		var finish: Vector2 = corners[(side_index + 1) % 4]
		var edge := finish - start
		var normal := Vector2(-edge.y, edge.x).normalized()
		for step in range(4):
			var fraction := float(step) / 4.0
			var jitter := rng.randf_range(-amount, amount) if step > 0 else 0.0
			points.append(start.lerp(finish, fraction) + normal * jitter)
	points.append(top_left)
	return points

func _draw_partial_line(points: PackedVector2Array, progress: float, color: Color, width: float) -> void:
	if points.size() < 2 or progress <= 0.0:
		return
	var lengths := PackedFloat32Array()
	var total_length := 0.0
	for index in range(points.size() - 1):
		var segment_length := points[index].distance_to(points[index + 1])
		lengths.append(segment_length)
		total_length += segment_length
	var remaining := total_length * progress
	var visible_points := PackedVector2Array([points[0]])
	for index in range(lengths.size()):
		var segment_length := lengths[index]
		if remaining >= segment_length:
			visible_points.append(points[index + 1])
			remaining -= segment_length
		else:
			if segment_length > 0.0:
				visible_points.append(points[index].lerp(points[index + 1], remaining / segment_length))
			break
	if visible_points.size() > 1:
		for index in range(visible_points.size() - 1):
			var clipped := _clip_segment(visible_points[index], visible_points[index + 1], _clip_rect)
			if clipped.size() == 2:
				draw_line(clipped[0], clipped[1], color, width, true)

func _clip_polygon(source: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for point in source:
		points.append(point)
	for edge in range(4):
		if points.is_empty():
			break
		var output: Array[Vector2] = []
		var previous: Vector2 = points[-1]
		for current in points:
			var previous_inside := _inside_clip_edge(previous, rect, edge)
			var current_inside := _inside_clip_edge(current, rect, edge)
			if current_inside != previous_inside:
				output.append(_clip_edge_intersection(previous, current, rect, edge))
			if current_inside:
				output.append(current)
			previous = current
		points = output
	var result := PackedVector2Array()
	for point in points:
		result.append(point)
	return result

func _inside_clip_edge(point: Vector2, rect: Rect2, edge: int) -> bool:
	match edge:
		0: return point.x >= rect.position.x
		1: return point.x <= rect.end.x
		2: return point.y >= rect.position.y
		_: return point.y <= rect.end.y

func _clip_edge_intersection(from: Vector2, to: Vector2, rect: Rect2, edge: int) -> Vector2:
	if edge < 2:
		var x := rect.position.x if edge == 0 else rect.end.x
		var t := (x - from.x) / (to.x - from.x) if not is_equal_approx(from.x, to.x) else 0.0
		return Vector2(x, lerpf(from.y, to.y, t))
	var y := rect.position.y if edge == 2 else rect.end.y
	var vertical_t := (y - from.y) / (to.y - from.y) if not is_equal_approx(from.y, to.y) else 0.0
	return Vector2(lerpf(from.x, to.x, vertical_t), y)

func _clip_segment(from: Vector2, to: Vector2, rect: Rect2) -> PackedVector2Array:
	var delta := to - from
	var t0 := 0.0
	var t1 := 1.0
	var p := [-delta.x, delta.x, -delta.y, delta.y]
	var q := [from.x - rect.position.x, rect.end.x - from.x, from.y - rect.position.y, rect.end.y - from.y]
	for index in range(4):
		if is_zero_approx(p[index]):
			if q[index] < 0.0:
				return PackedVector2Array()
			continue
		var ratio: float = q[index] / p[index]
		if p[index] < 0.0:
			t0 = maxf(t0, ratio)
		else:
			t1 = minf(t1, ratio)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([from + delta * t0, from + delta * t1])

func _draw_player_marker() -> void:
	if not is_instance_valid(_active_area):
		return
	var rect := _map_rect(_active_area)
	var point := rect.get_center()
	if not _clip_rect.has_point(point):
		return
	var radius := clampf(minf(rect.size.x, rect.size.y) * 0.2, 1.0, 5.0)
	draw_circle(point, radius + 1.2, ink_color)
	draw_circle(point, radius, current_color.lightened(0.35))

func _draw_active_label() -> void:
	if not show_area_names or not is_instance_valid(_active_area):
		return
	var font := handwritten_font if handwritten_font else ThemeDB.fallback_font
	draw_string(font, Vector2(_clip_rect.position.x, _clip_rect.end.y + 15.0),
		_active_area.area_label, HORIZONTAL_ALIGNMENT_CENTER, _clip_rect.size.x, 13, ink_color)
