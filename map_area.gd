@tool
extends Node2D
class_name MapArea

const FLOOR_SATURATION_SHADER := preload("res://floor_saturation.gdshader")
const DEFAULT_TREE_SCENE := preload("res://gameplay/Gatherables/harvestable_tree.tscn")

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

@export_group("Path Lights")
@export_range(0, 255, 1) var path_tile_source_id := 0
@export var path_tile_atlas_coords := Vector2i(0, 3)

@export_group("Ground Appearance")
@export_range(1.0, 1.5, 0.01) var floor_saturation := 1.15

@export_group("Forest Scatter")
@export_range(0, 255, 1) var forest_atlas_source_id := 1
@export var forest_tile_names: Array[StringName] = [
	&"straight_grass", &"small_grass", &"small_ball_grass", &"mini_grass",
	&"mini_grass_02", &"mini_ball_grass", &"long_grass_01", &"long_grass_02",
	&"long_grass_03", &"long_ball_grass_01", &"long_ball_grass_02", &"long_ball_grass_03",
]
@export_range(0, 500, 1) var forest_tree_count := 20
@export_range(0.0, 2048.0, 16.0) var forest_min_tree_spacing := 560.0
@export_range(0.0, 120.0, 4.0) var forest_tile_edge_margin := 32.0
@export_range(0.1, 4.0, 0.05) var forest_min_tree_scale := 0.85
@export_range(0.1, 4.0, 0.05) var forest_max_tree_scale := 1.15
@export_range(0.0, 20.0, 0.5) var forest_random_rotation_degrees := 5.0
@export var forest_scatter_seed := 0
@export var forest_tree_scene: PackedScene = DEFAULT_TREE_SCENE
@export_tool_button("Scatter Trees on Matching Tiles") var scatter_forest_trees_action: Callable:
	get:
		return Callable(self, "_scatter_forest_trees")
@export_tool_button("Clear Scattered Trees") var clear_forest_trees_action: Callable:
	get:
		return Callable(self, "_clear_scattered_forest_trees")

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

func is_path_tile(cell: Vector2i) -> bool:
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	if not ground or ground.get_cell_source_id(cell) == -1:
		return false
	var tile_data := ground.get_cell_tile_data(cell)
	if tile_data and ground.tile_set:
		var type_layer := ground.tile_set.get_custom_data_layer_by_name("tile_type")
		if type_layer >= 0:
			return str(tile_data.get_custom_data("tile_type")).to_lower() == "path"
	return ground.get_cell_source_id(cell) == path_tile_source_id and ground.get_cell_atlas_coords(cell) == path_tile_atlas_coords

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
	var container := get_light_container()
	if not container:
		return false
	var cells: Array = container.get_meta("lit_path_cells", [])
	return cells.has(cell)

func mark_path_lit(cell: Vector2i) -> void:
	var container := get_light_container()
	if not container:
		return
	var cells: Array = container.get_meta("lit_path_cells", [])
	if not cells.has(cell):
		cells.append(cell)
	container.set_meta("lit_path_cells", cells)

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
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SATURATION_SHADER
	material.set_shader_parameter("saturation", floor_saturation)
	ground.material = material

func _scatter_forest_trees() -> void:
	if not Engine.is_editor_hint():
		return
	var ground := get_node_or_null("GroundArt") as TileMapLayer
	var world_art := get_node_or_null("WorldArt") as TileMapLayer
	if not ground or not world_art or not ground.tile_set or not forest_tree_scene:
		push_warning("Forest scatter needs GroundArt with a TileSet, WorldArt and a tree scene.")
		return
	var variant_layer := ground.tile_set.get_custom_data_layer_by_name("forest_variant")
	if variant_layer < 0:
		push_warning("The GroundArt TileSet needs a custom data layer named 'forest_variant'.")
		return
	_clear_scattered_forest_trees()
	var matching_cells: Array[Vector2i] = []
	for cell in ground.get_used_cells():
		if ground.get_cell_source_id(cell) != forest_atlas_source_id:
			continue
		var tile_data := ground.get_cell_tile_data(cell)
		if not tile_data:
			continue
		var variant_name := StringName(str(tile_data.get_custom_data("forest_variant")))
		if forest_tile_names.is_empty() or forest_tile_names.has(variant_name):
			matching_cells.append(cell)
	if matching_cells.is_empty() or forest_tree_count <= 0:
		push_warning("No GroundArt cells match the selected Forest atlas source and tile names.")
		return
	var rng := RandomNumberGenerator.new()
	if forest_scatter_seed == 0:
		rng.randomize()
	else:
		rng.seed = forest_scatter_seed
	var scene_owner: Node = world_art.owner if world_art.owner else owner if owner else self
	var occupied_positions: Array[Vector2] = []
	for child in world_art.get_children():
		if child is Node2D:
			occupied_positions.append((child as Node2D).global_position)
	var tile_size := Vector2(ground.tile_set.tile_size)
	var margin := minf(forest_tile_edge_margin, minf(tile_size.x, tile_size.y) * 0.45)
	var min_spacing_squared := forest_min_tree_spacing * forest_min_tree_spacing
	var placed := 0
	var attempt_limit := forest_tree_count * 50
	for attempt in range(attempt_limit):
		if placed >= forest_tree_count:
			break
		var cell := matching_cells[rng.randi_range(0, matching_cells.size() - 1)]
		var cell_center := ground.map_to_local(cell)
		var cell_offset := Vector2(
			rng.randf_range(-tile_size.x * 0.5 + margin, tile_size.x * 0.5 - margin),
			rng.randf_range(-tile_size.y * 0.5 + margin, tile_size.y * 0.5 - margin)
		)
		var world_position := ground.to_global(cell_center + cell_offset)
		var too_close := false
		for existing_position in occupied_positions:
			if world_position.distance_squared_to(existing_position) < min_spacing_squared:
				too_close = true
				break
		if too_close:
			continue
		var tree := forest_tree_scene.instantiate() as Node2D
		if not tree:
			continue
		tree.name = "ForestTree_%02d" % placed
		tree.set("tree_scale", rng.randf_range(minf(forest_min_tree_scale, forest_max_tree_scale), maxf(forest_min_tree_scale, forest_max_tree_scale)))
		tree.rotation = deg_to_rad(rng.randf_range(-forest_random_rotation_degrees, forest_random_rotation_degrees))
		world_art.add_child(tree)
		tree.owner = scene_owner
		tree.position = world_art.to_local(world_position)
		tree.set_meta("forest_scatter_generated", true)
		occupied_positions.append(world_position)
		placed += 1
	if placed > 0:
		EditorInterface.mark_scene_as_unsaved()
	print("Scattered %d / %d tree(s) in %s." % [placed, forest_tree_count, name])

func _clear_scattered_forest_trees(mark_unsaved: bool = true) -> void:
	if not Engine.is_editor_hint():
		return
	var world_art := get_node_or_null("WorldArt") as TileMapLayer
	if not world_art:
		return
	var removed := 0
	for child in world_art.get_children():
		if child.has_meta("forest_scatter_generated"):
			world_art.remove_child(child)
			child.free()
			removed += 1
	if removed > 0:
		if mark_unsaved:
			EditorInterface.mark_scene_as_unsaved()
		print("Removed %d scattered tree(s) from %s." % [removed, name])

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
