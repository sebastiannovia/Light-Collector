@tool
extends Node2D
class_name MapArea

signal layout_changed

const FLOOR_SATURATION_SHADER := preload("res://floor_saturation.gdshader")
const FOREST_PATH_ATLAS := "res://Tiles/Atlases/forest_paths.png"

@export var area_label := "NEW AREA":
	set(value):
		area_label = value
		_redraw_layout()

@export var area_size := Vector2(3840, 2160):
	set(value):
		area_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_redraw_layout()

@export_group("Minimap")
@export var minimap_color := Color("95702cff")

@export_group("Monster Spawning")
@export var monster_spawning_enabled := true
@export_range(0, 100, 1) var maximum_alive_monsters := 8
@export var allowed_monster_scenes: Array[PackedScene] = []

@export_group("Path Lights")
@export_range(0, 255, 1) var path_tile_source_id := 0
@export var path_tile_atlas_coords := Vector2i(0, 3)
@export_range(0.75, 2.0, 0.05) var path_light_repel_tiles := 1.35

@export_group("Ground Appearance")
@export_range(1.0, 1.5, 0.01) var floor_saturation := 1.15

@export var grid_step := 256.0:
	set(value):
		grid_step = maxf(value, 1.0)
		path_width = maxf(grid_step, roundf(path_width / grid_step) * grid_step)
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

@export var north_path_offset_tiles := 0:
	set(value):
		north_path_offset_tiles = value
		_redraw_layout()

@export var north_path_tiles: Array[int] = []:
	set(value):
		north_path_tiles = value
		_redraw_layout()

@export var path_east := false:
	set(value):
		path_east = value
		_redraw_layout()

@export var east_path_offset_tiles := 0:
	set(value):
		east_path_offset_tiles = value
		_redraw_layout()

@export var east_path_tiles: Array[int] = []:
	set(value):
		east_path_tiles = value
		_redraw_layout()

@export var path_south := false:
	set(value):
		path_south = value
		_redraw_layout()

@export var south_path_offset_tiles := 0:
	set(value):
		south_path_offset_tiles = value
		_redraw_layout()

@export var south_path_tiles: Array[int] = []:
	set(value):
		south_path_tiles = value
		_redraw_layout()

@export var path_west := false:
	set(value):
		path_west = value
		_redraw_layout()

@export var west_path_offset_tiles := 0:
	set(value):
		west_path_offset_tiles = value
		_redraw_layout()

@export var west_path_tiles: Array[int] = []:
	set(value):
		west_path_tiles = value
		_redraw_layout()

@export var path_width := 256.0:
	set(value):
		path_width = maxf(grid_step, roundf(value / grid_step) * grid_step)
		_redraw_layout()

@export_group("Editor Placement")
@export var snap_to_neighbors := true
@export_range(1.0, 512.0, 1.0) var snap_distance := 96.0

const MAJOR_GRID_EVERY := 4
var _snapping := false
var _lit_path_cells: Dictionary[Vector2i, bool] = {}

func is_path_tile(cell: Vector2i) -> bool:
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	if not ground:
		return false
	if _is_path_on_layer(ground, cell):
		return true
	var overlay := get_node_or_null("WorldArt") as TileMapLayer
	if not overlay:
		return false
	var center := ground.to_global(ground.map_to_local(cell))
	return _is_path_on_layer(overlay, overlay.local_to_map(overlay.to_local(center)))


func _is_path_on_layer(layer: TileMapLayer, cell: Vector2i) -> bool:
	var source_id := layer.get_cell_source_id(cell)
	if source_id < 0 or not layer.tile_set:
		return false
	var tile_data := layer.get_cell_tile_data(cell)
	var type_layer := layer.tile_set.get_custom_data_layer_by_name("tile_type")
	if tile_data and type_layer >= 0:
		var tile_type := str(tile_data.get_custom_data_by_layer_id(type_layer)).to_lower()
		if not tile_type.is_empty():
			return tile_type == "path"
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source and source.texture and source.texture.resource_path == FOREST_PATH_ATLAS:
		return true
	return source_id == path_tile_source_id and layer.get_cell_atlas_coords(cell) == path_tile_atlas_coords


func get_light_container() -> Node2D:
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	if not ground:
		return null
	var container := ground.get_node_or_null("PlacedLights") as Node2D
	if not container:
		container = Node2D.new()
		container.name = "PlacedLights"
		container.y_sort_enabled = true
		ground.add_child(container)
	return container

func has_light_pair_for_path(cell: Vector2i) -> bool:
	return _lit_path_cells.has(cell)


func mark_path_lit(cell: Vector2i) -> void:
	_lit_path_cells[cell] = true


func get_path_light_exposure(world_point: Vector2) -> float:
	if _lit_path_cells.is_empty():
		return 0.0
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	if not ground or not ground.tile_set:
		return 0.0
	var point := ground.to_local(world_point)
	var cell := ground.local_to_map(point)
	var tile_size := Vector2(ground.tile_set.tile_size)
	var radius := maxf(tile_size.x, tile_size.y) * path_light_repel_tiles
	var search := Vector2i((Vector2.ONE * radius / tile_size).ceil())
	var exposure := 0.0
	for y in range(cell.y - search.y, cell.y + search.y + 1):
		for x in range(cell.x - search.x, cell.x + search.x + 1):
			var nearby := Vector2i(x, y)
			if _lit_path_cells.has(nearby):
				exposure = maxf(exposure, maxf(0.0, 1.0 - point.distance_to(ground.map_to_local(nearby)) / radius))
	return exposure


func get_pathway_centers(side: String) -> Array[float]:
	var centers: Array[float] = []
	var tile_indices: Array[int] = []
	var side_length := 0.0
	var global_origin := 0.0
	var path_offset_tiles := 0
	match side:
		"north":
			side_length = area_size.x
			global_origin = global_position.x
			path_offset_tiles = north_path_offset_tiles
			if path_north:
				centers.append(global_origin + _path_center_from_tile_offset(side_length, path_offset_tiles))
			tile_indices.append_array(north_path_tiles)
		"east":
			side_length = area_size.y
			global_origin = global_position.y
			path_offset_tiles = east_path_offset_tiles
			if path_east:
				centers.append(global_origin + _path_center_from_tile_offset(side_length, path_offset_tiles))
			tile_indices.append_array(east_path_tiles)
		"south":
			side_length = area_size.x
			global_origin = global_position.x
			path_offset_tiles = south_path_offset_tiles
			if path_south:
				centers.append(global_origin + _path_center_from_tile_offset(side_length, path_offset_tiles))
			tile_indices.append_array(south_path_tiles)
		"west":
			side_length = area_size.y
			global_origin = global_position.y
			path_offset_tiles = west_path_offset_tiles
			if path_west:
				centers.append(global_origin + _path_center_from_tile_offset(side_length, path_offset_tiles))
			tile_indices.append_array(west_path_tiles)
		_:
			return centers

	for tile_index in tile_indices:
		if tile_index < 0:
			continue
		var local_center := (float(tile_index) + 0.5) * grid_step
		if local_center >= side_length:
			continue
		var world_center := global_origin + local_center
		if not centers.has(world_center):
			centers.append(world_center)
	return centers

func get_default_pathway_center(side: String) -> float:
	var side_length := area_size.x if side == "north" or side == "south" else area_size.y
	var global_origin := global_position.x if side == "north" or side == "south" else global_position.y
	return global_origin + _path_center_from_tile_offset(side_length, 0)

func _path_center_from_tile_offset(side_length: float, offset_tiles: int) -> float:
	var half_width := minf(path_width * 0.5, side_length * 0.5)
	var max_tile_offset := maxi(0, floori(maxf(0.0, side_length * 0.5 - half_width) / grid_step))
	var safe_offset := clampi(offset_tiles, -max_tile_offset, max_tile_offset)
	return side_length * 0.5 + float(safe_offset) * grid_step

func _ready() -> void:
	set_notify_transform(true)
	if not Engine.is_editor_hint():
		_apply_floor_saturation()

func _apply_floor_saturation() -> void:
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	if not ground:
		return
	var floor_material := ShaderMaterial.new()
	floor_material.shader = FLOOR_SATURATION_SHADER
	floor_material.set_shader_parameter("saturation", floor_saturation)
	ground.material = floor_material

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
	layout_changed.emit()

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
