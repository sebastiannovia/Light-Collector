extends Node2D
class_name LightPlacementMarker

const WORLD_GLOW := preload("res://gameplay/world_glow.gd")

@export var glow_color := Color("ffd166")
@export var flame_color := Color("fff4b0")
@export_range(64.0, 640.0, 1.0) var glow_radius := 310.0

var _light: PointLight2D
var _cycle: DayNightCycle


func _ready() -> void:
	_light = WORLD_GLOW.make_light(glow_radius, glow_color, 0.85)
	_light.position.y = -12.0
	add_child(_light)
	var flame_material := CanvasItemMaterial.new()
	flame_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = flame_material
	_cycle = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	if _cycle:
		_cycle.clock_changed.connect(_update_light)
		_update_light(_cycle.hour, _cycle.is_night, _cycle.day_number, _cycle.permanent_night)


func _update_light(_hour: float, _is_night: bool, _day_number: int, _permanent_night: bool) -> void:
	_light.energy = lerpf(0.85, 0.16, smoothstep(0.4, 0.9, _cycle.color.get_luminance()))


func _draw() -> void:
	draw_rect(Rect2(-7.0, 2.0, 14.0, 7.0), Color("805c48"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -30.0), Vector2(11.0, -13.0), Vector2(7.0, 3.0),
		Vector2(-7.0, 3.0), Vector2(-11.0, -13.0),
	]), glow_color)
	draw_circle(Vector2(0.0, -12.0), 5.0, flame_color, true, -1.0, true)
