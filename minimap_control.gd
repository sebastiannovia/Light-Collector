extends Control
class_name HandDrawnMinimap

var map_player: Node2D
var panel_size := Vector2(360.0, 250.0)
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
var _bounds := Rect2()
var _screen_scale := 1.0
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
	if _areas.is_empty():
		_bounds = Rect2()
		return
	_bounds = Rect2(_areas[0].global_position, _areas[0].area_size)
	for index in range(1, _areas.size()):
		_bounds = _bounds.merge(Rect2(_areas[index].global_position, _areas[index].area_size))

func _on_area_changed(area: MapArea) -> void:
	if not is_instance_valid(area):
		return
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

func _process(_delta: float) -> void:
	if map_player and is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if _areas.is_empty():
		_refresh_areas()
	if _areas.is_empty():
		return
	_draw_paper()
	_update_transform()
	_draw_connections()
	_draw_rooms()
	_draw_player_marker()

func _draw_paper() -> void:
	draw_rect(Rect2(Vector2.ZERO, panel_size), paper_color)
	var border := _wobbly_rect(Rect2(Vector2(3, 3), panel_size - Vector2(6, 6)), 8182, 1.4)
	draw_polyline(border, ink_color, 1.8, true)
	var inner_border := _wobbly_rect(Rect2(Vector2(7, 7), panel_size - Vector2(14, 14)), 6147, 0.65)
	draw_polyline(inner_border, Color(ink_color, 0.35), 1.0, true)

func _update_transform() -> void:
	var content_size := panel_size - Vector2(padding * 2.0, padding * 2.0)
	_clip_rect = Rect2(Vector2(padding, padding), content_size)
	if content_size.x <= 0.0 or content_size.y <= 0.0 or _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		_screen_scale = 1.0
		_screen_origin = Vector2(padding, padding)
		return
	var active := map_player.get("current_area") as MapArea if map_player else null
	var focus_size := active.area_size if active else _bounds.size
	var focus_point := map_player.global_position if map_player else _bounds.get_center()
	if focus_size.x <= 0.0 or focus_size.y <= 0.0:
		focus_size = _bounds.size
	_screen_scale = minf(content_size.x / focus_size.x, content_size.y / focus_size.y) * map_scale
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
		if not _discovered.has(area_id):
			continue
		var progress: float = _reveal_progress.get(area_id, 1.0)
		var room_rect := _map_rect(area)
		var outline := _wobbly_rect(room_rect, hash(str(area.get_path())), line_wobble)
		var fill := area.minimap_color
		fill.a *= 0.32 * progress
		var clipped_outline := _clip_polygon(outline, _clip_rect)
		if clipped_outline.size() >= 3:
			draw_colored_polygon(clipped_outline, fill)
		_draw_partial_line(outline, progress, ink_color, line_width)
		var second_line := _wobbly_rect(room_rect.grow(-1.0), hash(str(area.get_path())) + 743, line_wobble * 0.55)
		_draw_partial_line(second_line, progress * 0.82, Color(ink_color, 0.42), maxf(1.0, line_width * 0.55))
		if show_area_names and progress >= 0.75 and _clip_rect.encloses(room_rect) and room_rect.size.x > 30.0 and room_rect.size.y > 17.0:
			var font := handwritten_font if handwritten_font else ThemeDB.fallback_font
			if font:
				var font_size := clampi(roundi(room_rect.size.y * 0.28), 8, 13)
				draw_string(font, room_rect.position + Vector2(4, room_rect.size.y * 0.58), area.area_label, HORIZONTAL_ALIGNMENT_LEFT, room_rect.size.x - 8, font_size, ink_color)

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
				var to := _edge_point(neighbor, other_side, center)
				var known := _discovered.has(neighbor_id)
				if not known and not show_unknown_paths:
					continue
				var progress := 1.0 if known else 0.48
				var path_seed := hash(connection_key)
				_draw_hand_path(from, to, progress, path_seed)

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

func _draw_hand_path(from: Vector2, to: Vector2, progress: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var direction := to - from
	var normal := Vector2(-direction.y, direction.x).normalized()
	var points := PackedVector2Array([from])
	for index in range(1, 5):
		var fraction := float(index) / 5.0
		var jitter := rng.randf_range(-line_wobble, line_wobble)
		points.append(from.lerp(to, fraction) + normal * jitter)
	points.append(to)
	var light_ink := Color(ink_color, 0.52)
	_draw_partial_line(points, progress, light_ink, line_width * 2.2)
	_draw_partial_line(points, progress, ink_color, maxf(1.0, line_width * 0.72))

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
	if not map_player:
		return
	var current_area := map_player.get("current_area") as MapArea
	if not current_area or not _discovered.has(current_area.get_instance_id()):
		return
	var point := _world_to_screen(map_player.global_position)
	if not _clip_rect.has_point(point):
		return
	draw_circle(point, 5.0, current_color)
	draw_arc(point, 7.5, 0.0, TAU, 24, ink_color, 1.4, true)
