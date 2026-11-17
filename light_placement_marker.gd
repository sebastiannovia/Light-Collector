extends Node2D
class_name LightPlacementMarker

@export var glow_color := Color("ffd166")
@export var flame_color := Color("fff4b0")

func _draw() -> void:
	draw_circle(Vector2.ZERO, 52.0, Color(glow_color, 0.10))
	draw_circle(Vector2.ZERO, 30.0, Color(glow_color, 0.18))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -30.0), Vector2(13.0, -8.0), Vector2(8.0, 7.0),
		Vector2(-8.0, 7.0), Vector2(-13.0, -8.0),
	]), flame_color)
	draw_circle(Vector2.ZERO, 5.0, Color.WHITE)
