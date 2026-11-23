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

@export_group("Movement Animation")
@export_range(1.0, 24.0, 0.5) var movement_animation_fps := 8.0
@export var walk_frames: Array[Texture2D] = []
@export var walk_forward_frames: Array[Texture2D] = []
@export var walk_backward_frames: Array[Texture2D] = []
@export var walk_sideways_frames: Array[Texture2D] = []
@export var sideways_frames_face_left := false

var health := 0
var is_alive := true
var target: Node2D
var _attack_cooldown_left := 0.0
var _knockback_tween: Tween
var _idle_texture: Texture2D
var _active_animation_frames: Array[Texture2D] = []
var _animation_elapsed := 0.0
var _animation_frame := 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sight_area: Area2D = $Sight
@onready var sight_shape: CollisionShape2D = $Sight/CollisionShape2D

func _ready() -> void:
	health = starting_health
	_idle_texture = sprite.texture
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
		_stop_movement_animation()
		return
	if not is_instance_valid(target):
		target = null
		velocity = Vector2.ZERO
		_stop_movement_animation()
		_update_depth_order()
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if absf(offset.x) > 0.1:
		sprite.flip_h = offset.x > 0.0 if sideways_frames_face_left else offset.x < 0.0
	if distance > attack_range:
		velocity = offset.normalized() * chase_speed
		move_and_slide()
		_update_movement_animation(delta, velocity)
	else:
		velocity = Vector2.ZERO
		_stop_movement_animation()
		if _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = attack_cooldown
			if target.has_method("take_damage"):
				target.call("take_damage", attack_damage)
	_update_depth_order()

func _update_movement_animation(delta: float, move_direction: Vector2) -> void:
	if move_direction.is_zero_approx():
		_stop_movement_animation()
		return

	var selected_frames: Array[Texture2D] = walk_frames
	var uses_directional_frames := not walk_forward_frames.is_empty() or not walk_backward_frames.is_empty() or not walk_sideways_frames.is_empty()
	if uses_directional_frames:
		if absf(move_direction.x) > absf(move_direction.y):
			selected_frames = walk_sideways_frames
		elif move_direction.y < 0.0:
			selected_frames = walk_backward_frames
		else:
			selected_frames = walk_forward_frames
		if selected_frames.is_empty():
			selected_frames = walk_frames

	if selected_frames.is_empty():
		_stop_movement_animation()
		return

	if selected_frames != _active_animation_frames:
		_active_animation_frames = selected_frames
		_animation_elapsed = 0.0
		_animation_frame = 0
	else:
		_animation_elapsed += delta
		var frame_duration := 1.0 / maxf(movement_animation_fps, 1.0)
		if _animation_elapsed >= frame_duration:
			var frames_to_advance := floori(_animation_elapsed / frame_duration)
			_animation_elapsed = fmod(_animation_elapsed, frame_duration)
			_animation_frame = (_animation_frame + frames_to_advance) % selected_frames.size()

	sprite.texture = selected_frames[_animation_frame]
	if uses_directional_frames:
		sprite.flip_h = selected_frames == walk_sideways_frames and (move_direction.x > 0.0 if sideways_frames_face_left else move_direction.x < 0.0)
	else:
		sprite.flip_h = move_direction.x < 0.0

func _stop_movement_animation() -> void:
	_active_animation_frames = []
	_animation_elapsed = 0.0
	_animation_frame = 0
	sprite.texture = _idle_texture

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
		_stop_movement_animation()

func _on_sight_body_exited(body: Node2D) -> void:
	if body == target and is_alive:
		target = null
		velocity = Vector2.ZERO
		_stop_movement_animation()

func _update_depth_order() -> void:
	var sprite_bottom := sprite.position.y + sprite.texture.get_height() * sprite.scale.y * 0.5
	var sort_y := global_position.y + sprite_bottom
	var ancestor := get_parent()
	while ancestor and not ancestor is MapArea:
		ancestor = ancestor.get_parent()
	if ancestor is MapArea:
		sort_y -= (ancestor as MapArea).global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)