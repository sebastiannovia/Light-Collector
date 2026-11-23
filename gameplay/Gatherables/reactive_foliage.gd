extends Sprite2D

const MAX_SWAY_DEGREES := 5.0

@export_range(16.0, 120.0, 1.0) var touch_radius := 65.0

var _player: Node2D
var _was_touched := false
var _sway: Tween


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		_was_touched = false
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("map_player") as Node2D
	if not _player:
		return
	var feet := _player.global_position
	if _player.has_method("get_depth_sort_y"):
		feet.y = float(_player.call("get_depth_sort_y"))
	var delta_to_player := feet - to_global(Vector2(0.0, -20.0))
	var touched := delta_to_player.length_squared() <= touch_radius * touch_radius
	if touched and not _was_touched:
		var direction := 1.0 if delta_to_player.x < 0.0 else -1.0
		_play_sway(direction)
	_was_touched = touched


func _play_sway(direction: float) -> void:
	if _sway and _sway.is_running():
		_sway.kill()
	_sway = create_tween().set_trans(Tween.TRANS_SINE)
	_sway.tween_property(self, "rotation_degrees", direction * MAX_SWAY_DEGREES, 0.11).set_ease(Tween.EASE_OUT)
	_sway.tween_property(self, "rotation_degrees", -direction * 1.5, 0.19).set_ease(Tween.EASE_IN_OUT)
	_sway.tween_property(self, "rotation_degrees", 0.0, 0.21).set_ease(Tween.EASE_OUT)
