@tool
extends Node2D

const FLOOR_ATLAS := preload("res://Tiles/Atlases/catacomb_floor_grassy_atlas.png")

@export var floor_atlas: Texture2D = FLOOR_ATLAS
@export var random_seed := 41931
@export_range(0.0, 256.0, 4.0) var spacing := 36.0
@export_range(0.0, 1024.0, 16.0) var entrance_depth := 420.0
@export_range(0.25, 2.0, 0.05) var prop_scale := 1.0

@export_group("Rocks")
@export_range(0, 150, 1) var rock_count := 10
@export var rock_textures: Array[Texture2D] = [
	preload("res://Assets/Rocks/rock_02.png"),
	preload("res://Assets/Rocks/rock_03.png"),
	preload("res://Assets/Rocks/rock_04.png"),
	preload("res://Assets/Rocks/rock_09.png"),
	preload("res://Assets/Rocks/rock_10.png"),
]
@export_range(0, 150, 1) var mineable_rock_count := 6
@export var mineable_rock_textures: Array[Texture2D] = [
	preload("res://Assets/Rocks/rock_01.png"),
	preload("res://Assets/Rocks/rock_05.png"),
	preload("res://Assets/Rocks/rock_06.png"),
	preload("res://Assets/Rocks/rock_07.png"),
	preload("res://Assets/Rocks/rock_08.png"),
]

@export_group("Bones")
@export_range(0, 150, 1) var bone_count := 12
@export var bone_textures: Array[Texture2D] = [
	preload("res://Assets/Bones and skulls/bone_01.png"),
	preload("res://Assets/Bones and skulls/bone_02.png"),
]

@export_group("Skulls")
@export_range(0, 150, 1) var skull_count := 8
@export var skull_textures: Array[Texture2D] = [
	preload("res://Assets/Bones and skulls/skull_01.png"),
	preload("res://Assets/Bones and skulls/skull_02.png"),
	preload("res://Assets/Bones and skulls/skull_03.png"),
]

@export_group("Bone Piles")
@export_range(0, 150, 1) var bone_pile_count := 10
@export var bone_pile_textures: Array[Texture2D] = [
	preload("res://Assets/Bones and skulls/bonepile_01.png"),
	preload("res://Assets/Bones and skulls/bonepile_02.png"),
	preload("res://Assets/Bones and skulls/bonepile_03.png"),
	preload("res://Assets/Bones and skulls/bonepile_04.png"),
	preload("res://Assets/Bones and skulls/bonepile_05.png"),
	preload("res://Assets/Bones and skulls/bonepile_06.png"),
	preload("res://Assets/Bones and skulls/bonepile_07.png"),
	preload("res://Assets/Bones and skulls/bonepile_08.png"),
	preload("res://Assets/Bones and skulls/bonepile_09.png"),
	preload("res://Assets/Bones and skulls/bonepile_10.png"),
	preload("res://Assets/Bones and skulls/bonepile_11.png"),
	preload("res://Assets/Bones and skulls/bonepile_12.png"),
	preload("res://Assets/Bones and skulls/bonepile_13.png"),
	preload("res://Assets/Bones and skulls/bonepile_14.png"),
	preload("res://Assets/Bones and skulls/bonepile_15.png"),
	preload("res://Assets/Bones and skulls/bonepile_16.png"),
	preload("res://Assets/Bones and skulls/bonepile_17.png"),
	preload("res://Assets/Bones and skulls/bonepile_18.png"),
	preload("res://Assets/Bones and skulls/bonepile_19.png"),
	preload("res://Assets/Bones and skulls/bonepile_20.png"),
	preload("res://Assets/Bones and skulls/bonespile_01.png"),
]

@export_group("")
@export_tool_button("Regenerate catacomb scenery", "Reload")
var regenerate_action: Callable = _rebuild

var _area: MapArea
var _ground: TileMapLayer
var _walls: TileMapLayer
var _preview: Node2D
var _rebuild_queued := false
var _rng := RandomNumberGenerator.new()
var _floor_cells: Array[Vector2i] = []
var _floor_lookup: Dictionary[Vector2i, bool] = {}
var _entrances: Array[Rect2] = []
var _occupied: Array[Rect2] = []
var _bounds: Rect2
var _to_ground: Transform2D
var _to_walls: Transform2D


func _ready() -> void:
	_area = get_parent() as MapArea
	if not _area:
		return
	_ground = _area.get_node_or_null("GroundArt") as TileMapLayer
	_walls = _area.get_node_or_null("WorldArt") as TileMapLayer
	if Engine.is_editor_hint():
		_area.layout_changed.connect(_queue_rebuild)
		if _ground:
			_ground.changed.connect(_queue_rebuild)
		if _walls:
			_walls.changed.connect(_queue_rebuild)
	_queue_rebuild()


func _queue_rebuild() -> void:
	if not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if is_instance_valid(_preview):
		remove_child(_preview)
		_preview.queue_free()
	if not _ground or not _ground.tile_set or not floor_atlas:
		return

	_floor_cells.clear()
	_floor_lookup.clear()
	for cell in _ground.get_used_cells():
		var source := _ground.tile_set.get_source(_ground.get_cell_source_id(cell)) as TileSetAtlasSource
		if source and source.texture == floor_atlas and not _area.is_path_tile(cell):
			_floor_cells.append(cell)
			_floor_lookup[cell] = true
	if _floor_cells.is_empty():
		return
	_floor_cells.sort()

	_bounds = Rect2(Vector2.ZERO, _area.area_size).grow(-24.0)
	_to_ground = _ground.global_transform.affine_inverse() * _area.global_transform
	if _walls:
		_to_walls = _walls.global_transform.affine_inverse() * _area.global_transform
	_collect_entrances()
	_occupied.clear()
	_rng.seed = random_seed
	_preview = Node2D.new()
	_preview.name = "GeneratedProps"
	_preview.z_index = 1
	add_child(_preview)

	# Fit the larger props first while there is more open ground.
	_scatter(mineable_rock_textures, mineable_rock_count, "MineableRock", true)
	_scatter(bone_pile_textures, bone_pile_count, "BonePile")
	_scatter(rock_textures, rock_count, "Rock")
	_scatter(skull_textures, skull_count, "Skull")
	_scatter(bone_textures, bone_count, "Bone")


func _collect_entrances() -> void:
	_entrances.clear()
	var width := _area.path_width + 64.0
	var size := _area.area_size
	for center in _area.get_pathway_centers("north"):
		_entrances.append(Rect2(center - _area.global_position.x - width * 0.5, 0, width, entrance_depth))
	for center in _area.get_pathway_centers("south"):
		_entrances.append(Rect2(center - _area.global_position.x - width * 0.5, size.y - entrance_depth, width, entrance_depth))
	for center in _area.get_pathway_centers("west"):
		_entrances.append(Rect2(0, center - _area.global_position.y - width * 0.5, entrance_depth, width))
	for center in _area.get_pathway_centers("east"):
		_entrances.append(Rect2(size.x - entrance_depth, center - _area.global_position.y - width * 0.5, entrance_depth, width))


func _scatter(textures: Array[Texture2D], count: int, prefix: String, mineable := false) -> void:
	var available := textures.filter(func(texture: Texture2D) -> bool: return texture != null)
	if available.is_empty():
		return
	var from_ground := _to_ground.affine_inverse()
	var tile_size := Vector2(_ground.tile_set.tile_size)
	for index in count:
		var texture: Texture2D = available[_rng.randi_range(0, available.size() - 1)]
		var opaque := HarvestableTree.get_used_texture_rect(texture)
		var size := opaque.size * prop_scale * _rng.randf_range(0.85, 1.15)
		for attempt in 120:
			var cell := _floor_cells[_rng.randi_range(0, _floor_cells.size() - 1)]
			var jitter := Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * tile_size
			var point := from_ground * (_ground.map_to_local(cell) + jitter)
			var footprint := Rect2(point - size * 0.5, size)
			if not _can_place(footprint):
				continue
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.scale = size / opaque.size
			sprite.offset = texture.get_size() * 0.5 - opaque.get_center()
			var prop: Node2D = sprite
			if mineable:
				var rock := HarvestableRock.new()
				rock.art_height = size.y
				rock.add_child(sprite)
				prop = rock
			prop.name = "%s_%02d" % [prefix, index]
			prop.position = to_local(_area.to_global(point))
			_preview.add_child(prop)
			_occupied.append(footprint.grow(spacing))
			break


func _can_place(footprint: Rect2) -> bool:
	if not _bounds.encloses(footprint):
		return false
	for entrance in _entrances:
		if entrance.intersects(footprint):
			return false
	for existing in _occupied:
		if existing.intersects(footprint):
			return false
	var ground_rect := _to_ground * footprint
	var first := _ground.local_to_map(ground_rect.position)
	var last := _ground.local_to_map(ground_rect.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if not _floor_lookup.has(Vector2i(x, y)):
				return false
	if _walls and _walls.tile_set:
		var wall_rect := _to_walls * footprint
		first = _walls.local_to_map(wall_rect.position)
		last = _walls.local_to_map(wall_rect.end)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				if _walls.get_cell_source_id(Vector2i(x, y)) >= 0:
					return false
	return true
