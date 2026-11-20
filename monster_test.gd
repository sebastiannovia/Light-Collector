extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _draw () -> void:
	draw_circle(Vector2.ZERO, 15.0, Color("ff0066ff"))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 15, Color("101923"), 4.0)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color("101923"), 3.0)
	draw_line(Vector2(0, -10), Vector2(0, 10), Color("101923"), 3.0)
