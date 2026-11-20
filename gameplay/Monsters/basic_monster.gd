extends CharacterBody2D

@export_group("Monster")
@export var display_name := "Monster"
@export_range(1, 10000, 1) var starting_health := 160
@export_range(0.0, 500.0, 1.0) var chase_speed := 100.0

@export_group("Attack")
@export_range(32.0, 400.0, 1.0) var sight_range := 320.0
@export_range(24.0, 256.0, 1.0) var attack_range := 110.0
@export_range(0.0, 100.0, 1.0) var attack_damage := 10.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown := 1.0

@export_group("Knockback")
@export_range(0.0, 500.0, 1.0) var knockback_force := 100.0
@export_range(0.05, 1.0, 0.05) var knockback_duration := 0.25

var health := 0
var is_alive := true
var target: Node2D
var _attack_cooldown_left := 0.0
var _knockback_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sight_area: Area2D = $Sight
@onready var sight_shape: CollisionShape2D = $Sight/CollisionShape2D

func _ready() -> void:
	health = starting_health
	add_to_group("monsters")
	if not sight_area.body_entered.is_connected(_on_sight_body_entered):
		sight_area.body_entered.connect(_on_sight_body_entered)
	if not sight_area.body_exited.is_connected(_on_sight_body_exited):
		sight_area.body_exited.connect(_on_sight_body_exited)
	set_collision_mask_value(1, true)
	set_collision_layer_value(2, true)
	var sight_circle := sight_shape.shape as CircleShape2D
	if sight_circle:
		sight_circle.radius = sight_range
	z_as_relative = false
	_update_depth_order()

func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if not is_alive:
		return
	if _knockback_tween and _knockback_tween.is_running():
		velocity = Vector2.ZERO
		return
	if not is_instance_valid(target):
		target = null
		velocity = Vector2.ZERO
		_update_depth_order()
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if absf(offset.x) > 0.1:
		sprite.flip_h = offset.x < 0.0
	if distance > attack_range:
		velocity = offset.normalized() * chase_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		if _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = attack_cooldown
			if target.has_method("take_damage"):
				target.call("take_damage", attack_damage)
	_update_depth_order()

func take_damage(damage: int, attacker_position: Vector2) -> void:
	if not is_alive or damage <= 0:
		return
	health = maxi(0, health - damage)
	if health == 0:
		_die()
		return
	var direction := global_position - attacker_position
	if direction.is_zero_approx():
		direction = Vector2.UP
	else:
		direction = direction.normalized()
	if _knockback_tween and _knockback_tween.is_running():
		_knockback_tween.kill()
	_knockback_tween = create_tween()
	_knockback_tween.set_ease(Tween.EASE_OUT)
	_knockback_tween.set_trans(Tween.TRANS_CUBIC)
	_knockback_tween.tween_property(self, "global_position", global_position + direction * knockback_force, knockback_duration)

func _die() -> void:
	is_alive = false
	target = null
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)
	sight_shape.set_deferred("disabled", true)
	sprite.visible = false

func _on_sight_body_entered(body: Node2D) -> void:
	if is_alive and body.is_in_group("map_player"):
		target = body

func _on_sight_body_exited(body: Node2D) -> void:
	if body == target and is_alive:
		target = null
		velocity = Vector2.ZERO

func _update_depth_order() -> void:
	var sprite_bottom := sprite.position.y + sprite.texture.get_height() * sprite.scale.y * 0.5
	var sort_y := global_position.y + sprite_bottom
	var ancestor := get_parent()
	while ancestor and not ancestor is MapArea:
		ancestor = ancestor.get_parent()
	if ancestor is MapArea:
		sort_y -= (ancestor as MapArea).global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)
