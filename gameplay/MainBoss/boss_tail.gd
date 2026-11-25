extends StaticBody2D

signal defeated

@export var eye_texture: Texture2D
@export var mouth_texture: Texture2D
@export var eye_color := Color("78e9e3")
@export var mouth_color := Color("ffa496")

var health := 0
var maximum_health := 1
var _tail_name := ""
var _color := Color.WHITE
var _flash: Tween

@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_shape: CollisionShape2D = $CollisionShape2D


func set_active(active: bool) -> void:
	visible = active
	hit_shape.set_deferred("disabled", not active)


func set_swipe_angle(angle: float) -> void:
	sprite.rotation = angle


func summon(new_health: int, is_eye: bool) -> void:
	maximum_health = new_health
	health = new_health
	_tail_name = "EYE TAIL" if is_eye else "MOUTH TAIL"
	_color = eye_color if is_eye else mouth_color
	sprite.texture = eye_texture if is_eye else mouth_texture
	if _flash and _flash.is_running():
		_flash.kill()
	sprite.self_modulate = _color
	set_active(true)
	queue_redraw()


func take_damage(amount: int, _attacker_position: Vector2) -> void:
	if not is_visible_in_tree() or health <= 0 or amount <= 0:
		return
	health = maxi(0, health - amount)
	queue_redraw()
	if health == 0:
		set_active(false)
		defeated.emit()
		return
	if _flash and _flash.is_running():
		_flash.kill()
	sprite.self_modulate = Color(1.7, 1.7, 1.7)
	_flash = create_tween()
	_flash.tween_property(sprite, "self_modulate", _color, 0.17)


func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-118, -269), _tail_name, HORIZONTAL_ALIGNMENT_CENTER, 236, 22, _color)
	var bar := Rect2(-118, -255, 236, 15)
	draw_rect(bar.grow(3.0), Color("170f25"))
	bar.size.x *= float(health) / float(maximum_health)
	draw_rect(bar, _color)
