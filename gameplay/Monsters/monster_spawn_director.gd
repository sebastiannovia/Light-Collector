extends Node
class_name MonsterSpawnDirector

signal monster_spawned(monster: Node2D, area: MapArea)

@export_group("Spawn")
@export var spawning_enabled := true
@export_range(1.0, 600.0, 1.0) var spawn_interval := 18.0
@export_range(0.0, 120.0, 1.0) var first_spawn_delay := 4.0
@export_range(1, 10, 1) var minimum_per_wave := 1
@export_range(1, 10, 1) var maximum_per_wave := 2
@export_range(0, 100, 1) var maximum_alive_global := 18
@export_range(0.0, 1200.0, 16.0) var minimum_player_distance := 640.0
@export_range(32.0, 512.0, 16.0) var area_edge_margin := 160.0
@export_range(16.0, 160.0, 8.0) var spawn_clearance_radius := 64.0
@export_flags_2d_physics var spawn_collision_mask := 1
@export_range(1, 80, 1) var position_attempts := 24

@export_group("Monster Roster")
@export var monster_scenes: Array[PackedScene] = [
	preload("res://gameplay/Monsters/Jumper.tscn"),
	preload("res://gameplay/Monsters/Charger.tscn"),
	preload("res://gameplay/Monsters/Spinner.tscn")
]
@export var spawn_weights: Array[float] = [1.0, 1.0, 0.65]
@export var maximum_per_type_per_area: Array[int] = [4, 4, 2]

var _cycle: DayNightCycle
var _player: Node2D
var _spawn_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_player = get_tree().get_first_node_in_group("map_player") as Node2D
	_cycle = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	if _cycle:
		_cycle.night_changed.connect(_on_night_changed)
		_spawn_timer = first_spawn_delay if _cycle.is_night else spawn_interval
	set_process(true)


func _process(delta: float) -> void:
	if not spawning_enabled or not _cycle or not _cycle.is_night:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = maxf(spawn_interval, 1.0)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("map_player") as Node2D
	if not is_instance_valid(_player):
		return
	var area := _get_player_area()
	if not area or not area.monster_spawning_enabled:
		return
	if _alive_count_for_area(area) >= area.maximum_alive_monsters:
		return
	var wave_size := _rng.randi_range(minimum_per_wave, maximum_per_wave)
	for _index in range(wave_size):
		if _alive_count_for_area(area) >= area.maximum_alive_monsters:
			break
		if _alive_count_global() >= maximum_alive_global:
			break
		var scene_index := _choose_scene_index(area)
		if scene_index < 0:
			break
		var spawn_position := _find_spawn_position(area)
		if spawn_position == Vector2.INF:
			break
		_spawn_monster(area, monster_scenes[scene_index], spawn_position)


func _on_night_changed(is_night: bool) -> void:
	_spawn_timer = first_spawn_delay if is_night else spawn_interval


func _get_player_area() -> MapArea:
	var fallback: MapArea
	for node in get_tree().get_nodes_in_group("map_areas"):
		var area := node as MapArea
		if area and Rect2(Vector2.ZERO, area.area_size).has_point(area.to_local(_player.global_position)):
			if area.is_visible_in_tree():
				return area
			fallback = area
	return fallback


func _choose_scene_index(area: MapArea) -> int:
	var eligible: Array[int] = []
	var total_weight := 0.0
	for index in range(mini(monster_scenes.size(), spawn_weights.size())):
		var scene := monster_scenes[index]
		if not scene:
			continue
		if not area.allowed_monster_scenes.is_empty() and not area.allowed_monster_scenes.has(scene):
			continue
		var type_cap: int = maximum_per_type_per_area[index] if index < maximum_per_type_per_area.size() else area.maximum_alive_monsters
		if _alive_count_for_scene(area, scene) >= type_cap:
			continue
		var weight := maxf(spawn_weights[index], 0.0)
		if weight <= 0.0:
			continue
		eligible.append(index)
		total_weight += weight
	if eligible.is_empty():
		return -1
	var choice := _rng.randf_range(0.0, total_weight)
	for index in eligible:
		choice -= maxf(spawn_weights[index], 0.0)
		if choice <= 0.0:
			return index
	return eligible.back()


func _find_spawn_position(area: MapArea) -> Vector2:
	var margin_x := minf(area_edge_margin, area.area_size.x * 0.45)
	var margin_y := minf(area_edge_margin, area.area_size.y * 0.45)
	for _attempt in range(position_attempts):
		var local_point := Vector2(
			_rng.randf_range(margin_x, area.area_size.x - margin_x),
			_rng.randf_range(margin_y, area.area_size.y - margin_y)
		)
		var candidate := area.to_global(local_point)
		if candidate.distance_to(_player.global_position) < minimum_player_distance:
			continue
		if area.get_path_light_exposure(candidate) > 0.001:
			continue
		if _too_close_to_monster(candidate, 120.0):
			continue
		if not _is_spawn_clear(candidate):
			continue
		return candidate
	return Vector2.INF


func _spawn_monster(area: MapArea, scene: PackedScene, world_position: Vector2) -> void:
	var monster := scene.instantiate() as Node2D
	if not monster:
		return
	monster.set_meta("spawned_by_director", true)
	monster.position = area.to_local(world_position)
	area.add_child(monster)
	monster_spawned.emit(monster, area)


func _alive_count_for_area(area: MapArea) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		if node.get("is_alive") == true and area.is_ancestor_of(node):
			count += 1
	return count


func _alive_count_global() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		if node.get("is_alive") == true:
			count += 1
	return count


func _alive_count_for_scene(area: MapArea, scene: PackedScene) -> int:
	var count := 0
	var scene_path := scene.resource_path
	for node in get_tree().get_nodes_in_group("monsters"):
		if node.get("is_alive") != true or not area.is_ancestor_of(node):
			continue
		if node.scene_file_path == scene_path:
			count += 1
	return count


func _is_spawn_clear(point: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = spawn_clearance_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = spawn_collision_mask
	if is_instance_valid(_player) and _player is CollisionObject2D:
		query.exclude = [(_player as CollisionObject2D).get_rid()]
	return _player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _too_close_to_monster(point: Vector2, minimum_distance: float) -> bool:
	for node in get_tree().get_nodes_in_group("monsters"):
		if node.get("is_alive") == true and node is Node2D:
			if (node as Node2D).global_position.distance_to(point) < minimum_distance:
				return true
	return false
