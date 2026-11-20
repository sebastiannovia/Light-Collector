extends CharacterBody2D

@export_group("Movement")
@export_range(0.0, 500.0, 1.0) var chase_speed := 100.0
@export_range(32.0, 256.0, 1.0) var attack_range := 110.0

@export_group("Attack")
@export_range(0.0, 100.0, 1.0) var attack_damage := 10.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown := 1.0

@export_group("Health")
@export_range(1, 10000, 1) var starting_health := 160
@export_range(0.0, 500.0, 1.0) var knockback_force := 100.0
@export_range(0.05, 1.0, 0.05) var knockback_duration := 0.25

var target: Node2D
var health: int
var is_alive := true
var _attack_cooldown_left := 0.0
var _knockback_tween: Tween

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sight_shape: CollisionShape2D = $Sight/CollisionShape2D

func _ready() -> void:
	health = starting_health

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
		animated_sprite_2d.play("base")
		return
	_pursue_or_attack(delta)

func _pursue_or_attack(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	if distance > attack_range:
		velocity = to_target.normalized() * chase_speed
		move_and_slide()
		animated_sprite_2d.play("attack")
		return

	velocity = Vector2.ZERO
	if _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = attack_cooldown
		animated_sprite_2d.play("attack")
		if target.has_method("take_damage"):
			target.call("take_damage", attack_damage)

func take_damage(damage: int, attacker_position: Vector2) -> void:
	if not is_alive or damage <= 0:
		return
	health = maxi(0, health - damage)
	if health <= 0:
		_die()
		return

	var knockback_direction := global_position - attacker_position
	if knockback_direction.is_zero_approx():
		knockback_direction = Vector2.UP
	else:
		knockback_direction = knockback_direction.normalized()
	if _knockback_tween and _knockback_tween.is_running():
		_knockback_tween.kill()
	_knockback_tween = create_tween()
	_knockback_tween.set_ease(Tween.EASE_OUT)
	_knockback_tween.set_trans(Tween.TRANS_CUBIC)
	_knockback_tween.tween_property(self, "global_position", global_position + knockback_direction * knockback_force, knockback_duration)

func _die() -> void:
	is_alive = false
	target = null
	velocity = Vector2.ZERO
	animated_sprite_2d.play("die")
	body_shape.set_deferred("disabled", true)
	sight_shape.set_deferred("disabled", true)

func _on_sight_body_entered(body: Node2D) -> void:
	if is_alive and body.is_in_group("map_player"):
		target = body

func _on_sight_body_exited(body: Node2D) -> void:
	if body == target and is_alive:
		target = null
		velocity = Vector2.ZERO
		animated_sprite_2d.play("base")
