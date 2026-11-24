extends Node2D

const WORLD_GLOW := preload("res://gameplay/world_glow.gd")

var light_amount := 2
var glow_color := Color("83f1de")
var collection_radius := 82.0
var _light: PointLight2D
var _elapsed := 0.0


func _ready() -> void:
	add_to_group("monster_light_cores")
	var core_material := CanvasItemMaterial.new()
	core_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = core_material
	_light = WORLD_GLOW.make_light(120.0, glow_color, 0.56)
	add_child(_light)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_elapsed += delta
	_light.position.y = _float_offset()
	_light.energy = 0.49 + 0.09 * sin(_elapsed * 4.0)
	queue_redraw()
	var player := get_tree().get_first_node_in_group("map_player") as Node2D
	if not player or not player.has_method("add_light"):
		return
	if global_position.distance_squared_to(player.global_position) > collection_radius * collection_radius:
		return
	player.call("add_light", light_amount)
	queue_free()


func _float_offset() -> float:
	return -16.0 + sin(_elapsed * 3.0) * 5.0


func _draw() -> void:
	draw_set_transform(Vector2(0.0, _float_offset()))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -15), Vector2(11, -5), Vector2(8, 9),
		Vector2(0, 15), Vector2(-8, 9), Vector2(-11, -5),
	]), glow_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -11), Vector2(6, -4), Vector2(0, 10), Vector2(-5, -4),
	]), glow_color.lightened(0.62))
