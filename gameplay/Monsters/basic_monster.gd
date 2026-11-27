extends CharacterBody2D

enum AttackPattern { SWIPE, LEAP, CHARGE }

const WORLD_GLOW := preload("res://gameplay/world_glow.gd")
const LIGHT_CORE := preload("res://gameplay/Monsters/monster_light_core.gd")
const LIGHT_LOOK_AHEAD := 64.0
const AREA_MARGIN := 48.0
const ATTACK_PATH_STEP := 16.0

@export_group("Monster")
@export var display_name := "Monster"
@export_range(1, 10000, 1) var starting_health := 160
@export_range(0.0, 500.0, 1.0) var chase_speed := 100.0

@export_group("Roaming")
@export var roaming_enabled := true
@export_range(0.0, 2000.0, 16.0) var roaming_radius := 640.0
@export_range(0.0, 1.0, 0.05) var roaming_speed_multiplier := 0.38
@export_range(0.0, 15.0, 0.1) var roaming_pause_min := 1.2
@export_range(0.0, 30.0, 0.1) var roaming_pause_max := 4.0
@export_range(1, 40, 1) var roaming_destination_attempts := 16

@export_group("Attack")
@export_range(32.0, 400.0, 1.0) var sight_range := 320.0
@export_range(24.0, 256.0, 1.0) var attack_range := 110.0
@export_range(0.0, 100.0, 1.0) var attack_damage := 10.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown := 1.0
@export_range(0.15, 2.0, 0.01) var attack_windup := 0.48
@export var attack_pattern: AttackPattern = AttackPattern.SWIPE
@export_range(0.12, 1.5, 0.01) var attack_travel_time := 0.42
@export_range(16.0, 160.0, 1.0) var attack_impact_radius := 70.0
@export_range(16.0, 180.0, 1.0) var jump_height := 82.0
@export_range(100.0, 500.0, 1.0) var charge_distance := 300.0
@export_range(0.0, 160.0, 1.0) var charge_tusk_offset := 100.0

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

@export_group("Attack Animation")
@export_range(1.0, 24.0, 0.5) var attack_animation_fps := 12.0
@export var attack_side_frames: Array[Texture2D] = []
@export var attack_from_you_frames: Array[Texture2D] = []
@export var attack_to_you_frames: Array[Texture2D] = []
@export var attack_side_frames_face_left := false

@export_group("Light")
@export var glow_color := Color("83f1de")
@export_range(0.0, 1.5, 0.01) var glow_intensity := 0.46
@export_range(0, 24, 1) var core_light_amount := 2

var health := 0
var is_alive := true
var target: Node2D
var _attack_cooldown_left := 0.0
var _attack_windup_left := 0.0
var _attack_target: Node2D
var _attack_origin := Vector2.ZERO
var _attack_destination := Vector2.ZERO
var _attack_heading := Vector2.RIGHT
var _attack_travel_left := 0.0
var _charge_hit := false
var _leap_contact_hit := false
var _sprite_rest_position := Vector2.ZERO
var _body_rest_position := Vector2.ZERO
var _knockback_tween: Tween
var _idle_texture: Texture2D
var _active_animation_frames: Array[Texture2D] = []
var _animation_elapsed := 0.0
var _animation_frame := 0
var _attack_animation_frames: Array[Texture2D] = []
var _attack_animation_elapsed := 0.0
var _attack_animation_frame := -1
var _cycle: DayNightCycle
var _area: MapArea
var _spawn_position: Vector2
var _spawn_clear := true
var _active := false
var _glow: PointLight2D
var _glow_time := 0.0
var _roam_origin := Vector2.ZERO
var _roam_destination := Vector2.ZERO
var _roam_pause_left := 0.0
var _roam_stuck_left := 0.0
var _rng := RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sight_area: Area2D = $Sight
@onready var sight_shape: CollisionShape2D = $Sight/CollisionShape2D

func _ready() -> void:
	health = starting_health
	_rng.randomize()
	_idle_texture = sprite.texture
	_sprite_rest_position = sprite.position
	_body_rest_position = body_shape.position
	add_to_group("monsters")
	if not sight_area.body_entered.is_connected(_on_sight_body_entered):
		sight_area.body_entered.connect(_on_sight_body_entered)
	if not sight_area.body_exited.is_connected(_on_sight_body_exited):
		sight_area.body_exited.connect(_on_sight_body_exited)
	set_collision_mask_value(1, true)
	set_collision_layer_value(2, true)
	var sight_circle := sight_shape.shape.duplicate() as CircleShape2D
	if sight_circle:
		sight_circle.radius = sight_range
		sight_shape.shape = sight_circle
	var ancestor := get_parent()
	while ancestor and not ancestor is MapArea:
		ancestor = ancestor.get_parent()
	_area = ancestor as MapArea
	_spawn_position = position
	_roam_origin = global_position
	z_as_relative = false
	_glow = WORLD_GLOW.make_light(158.0, glow_color, glow_intensity)
	sprite.add_child(_glow)
	_update_depth_order()
	_apply_active(false)
	_bind_cycle.call_deferred()


func _bind_cycle() -> void:
	_cycle = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	if not _cycle:
		return
	_cycle.night_changed.connect(_on_night_changed)
	if _area:
		_area.visibility_changed.connect(_refresh_active)
	_on_night_changed(_cycle.is_night)


func _on_night_changed(night: bool) -> void:
	if night:
		health = starting_health
		is_alive = true
		position = _spawn_position
		_target_safe_spawn()
		_attack_cooldown_left = 0.0
		_update_depth_order()
	_refresh_active()


func _target_safe_spawn() -> void:
	_spawn_clear = true
	if not _area or _area.get_path_light_exposure(global_position) <= 0.0:
		return
	var origin := global_position
	for radius in PackedFloat32Array([128.0, 256.0, 384.0, 512.0]):
		for index in range(12):
			var candidate := origin + Vector2.RIGHT.rotated(float(index) * TAU / 12.0) * radius
			if _inside_area(candidate) and _area.get_path_light_exposure(candidate) <= 0.0:
				global_position = candidate
				return
	_spawn_clear = false


func _refresh_active() -> void:
	var can_activate := is_alive and _spawn_clear and _cycle and _cycle.is_night and (not _area or _area.is_visible_in_tree())
	if can_activate != _active:
		_apply_active(can_activate)


func _apply_active(enabled: bool) -> void:
	_active = enabled
	if not enabled:
		_roam_destination = Vector2.ZERO
		_roam_pause_left = _random_roam_pause()
		_roam_stuck_left = 0.0
	sprite.visible = enabled
	_glow.enabled = enabled
	body_shape.set_deferred("disabled", not enabled)
	sight_shape.set_deferred("disabled", not enabled)
	sight_area.set_deferred("monitoring", enabled)
	set_physics_process(enabled)
	target = null
	velocity = Vector2.ZERO
	_clear_attack()
	if _knockback_tween and _knockback_tween.is_running():
		_knockback_tween.kill()
	_stop_movement_animation()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	_glow_time += delta
	_glow.energy = glow_intensity * (0.92 + 0.08 * sin(_glow_time * 3.0))
	_update_room_target()
	if _area and _area.get_path_light_exposure(global_position) > 0.0:
		_clear_attack()
		if _knockback_tween and _knockback_tween.is_running():
			_knockback_tween.kill()
		_move_in_direction(_direction_away_from_light(), delta)
		return
	if _knockback_tween and _knockback_tween.is_running():
		_move_in_direction(Vector2.ZERO, delta)
		return
	if _attack_windup_left > 0.0:
		_advance_windup(delta)
		return
	if _attack_travel_left > 0.0:
		_advance_attack_travel(delta)
		return
	if not is_instance_valid(target):
		target = null
		_update_roaming(delta)
		return
	if _attack_cooldown_left > 0.0:
		_move_in_direction(Vector2.ZERO, delta)
		return
	if _area and _area.get_path_light_exposure(target.global_position) > 0.0:
		_move_in_direction(Vector2.ZERO, delta)
		return
	var offset := target.global_position - global_position
	var distance := offset.length()
	if distance > attack_range or not _begin_attack(offset):
		_move_in_direction(_chase_direction(offset.normalized(), distance), delta)


func _update_room_target() -> void:
	var player := get_tree().get_first_node_in_group("map_player") as Node2D
	if not player:
		target = null
		return
	if _area:
		var player_area := player.get("current_area") as MapArea
		if player_area != _area or not _inside_area(player.global_position):
			target = null
			return
	target = player


func _update_roaming(delta: float) -> void:
	if not roaming_enabled or roaming_radius <= 0.0:
		_move_in_direction(Vector2.ZERO, delta)
		return
	if _roam_destination == Vector2.ZERO:
		_roam_pause_left = maxf(0.0, _roam_pause_left - delta)
		if _roam_pause_left <= 0.0:
			_choose_roam_destination()
		if _roam_destination == Vector2.ZERO:
			_move_in_direction(Vector2.ZERO, delta)
			return
	var offset := _roam_destination - global_position
	if offset.length() <= 20.0:
		_roam_destination = Vector2.ZERO
		_roam_pause_left = _random_roam_pause()
		_roam_stuck_left = 0.0
		_move_in_direction(Vector2.ZERO, delta)
		return
	var direction := offset.normalized()
	var next_position := global_position + direction * chase_speed * roaming_speed_multiplier * delta
	if not _inside_area(next_position) or (_area and _area.get_path_light_exposure(next_position) > 0.0):
		_roam_destination = Vector2.ZERO
		_roam_pause_left = _random_roam_pause()
		_move_in_direction(Vector2.ZERO, delta)
		return
	var previous_position := global_position
	_move_in_direction(direction, delta, roaming_speed_multiplier)
	if global_position.distance_squared_to(previous_position) < 1.0:
		_roam_stuck_left += delta
		if _roam_stuck_left >= 0.45:
			_roam_destination = Vector2.ZERO
			_roam_pause_left = _random_roam_pause()
			_roam_stuck_left = 0.0
	else:
		_roam_stuck_left = 0.0


func _choose_roam_destination() -> void:
	if not _area:
		return
	for _attempt in range(roaming_destination_attempts):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(roaming_radius * 0.25, roaming_radius)
		var candidate := _roam_origin + Vector2.RIGHT.rotated(angle) * distance
		if _inside_area(candidate) and _area.get_path_light_exposure(candidate) <= 0.0:
			_roam_destination = candidate
			return
	_roam_pause_left = _random_roam_pause()


func _random_roam_pause() -> float:
	return _rng.randf_range(roaming_pause_min, maxf(roaming_pause_min, roaming_pause_max))


func _begin_attack(offset: Vector2) -> bool:
	_attack_origin = global_position
	_attack_destination = global_position
	_attack_heading = offset.normalized() if not offset.is_zero_approx() else Vector2.RIGHT
	match attack_pattern:
		AttackPattern.LEAP:
			_attack_destination = _clear_attack_path(_attack_origin, _attack_origin + offset)
			if _attack_destination.distance_to(target.global_position) > attack_impact_radius:
				return false
		AttackPattern.CHARGE:
			_attack_destination = _clear_attack_path(_attack_origin, _attack_origin + _attack_heading * charge_distance)
			if _attack_destination.distance_squared_to(_attack_origin) < ATTACK_PATH_STEP * ATTACK_PATH_STEP:
				return false
	_attack_target = target
	_attack_windup_left = attack_windup
	_charge_hit = false
	_leap_contact_hit = false
	if attack_pattern == AttackPattern.LEAP:
		_start_attack_animation(_attack_heading)
	_hold_attack_pose()
	return true


func _start_attack_animation(direction: Vector2) -> void:
	_attack_animation_frames = []
	_attack_animation_elapsed = 0.0
	_attack_animation_frame = -1
	sprite.flip_h = false
	if absf(direction.x) > absf(direction.y):
		_attack_animation_frames = attack_side_frames
		if not _attack_animation_frames.is_empty():
			sprite.flip_h = direction.x > 0.0 if attack_side_frames_face_left else direction.x < 0.0
	elif direction.y < 0.0:
		_attack_animation_frames = attack_from_you_frames
	else:
		_attack_animation_frames = attack_to_you_frames
	if _attack_animation_frames.is_empty():
		return
	_attack_animation_frame = 0
	sprite.texture = _attack_animation_frames[0]


func _advance_attack_animation(delta: float) -> void:
	if _attack_animation_frames.is_empty():
		return
	_attack_animation_elapsed += delta
	var frame_index := mini(
		floori(_attack_animation_elapsed * attack_animation_fps),
		_attack_animation_frames.size() - 1
	)
	if frame_index != _attack_animation_frame:
		_attack_animation_frame = frame_index
		sprite.texture = _attack_animation_frames[_attack_animation_frame]


func _clear_attack_path(from: Vector2, to: Vector2) -> Vector2:
	if not _area:
		return to
	var steps := maxi(1, ceili(from.distance_to(to) / ATTACK_PATH_STEP))
	var last_clear := from
	for index in range(1, steps + 1):
		var sample := from.lerp(to, float(index) / float(steps))
		if not _inside_area(sample) or _area.get_path_light_exposure(sample) > 0.0:
			break
		last_clear = sample
	return last_clear


func _hold_attack_pose() -> void:
	velocity = Vector2.ZERO
	if attack_pattern == AttackPattern.CHARGE:
		_update_movement_animation(0.0, _attack_heading)
	elif _attack_animation_frames.is_empty():
		_stop_movement_animation()
	_update_depth_order()


func _advance_windup(delta: float) -> void:
	_hold_attack_pose()
	if attack_pattern == AttackPattern.LEAP:
		_check_leap_player_contact()
	_attack_windup_left = maxf(0.0, _attack_windup_left - delta)
	_advance_attack_animation(delta)
	if _attack_windup_left == 0.0:
		if attack_pattern == AttackPattern.SWIPE:
			_hit_attack_circle(global_position, attack_range)
			_finish_attack()
			return
		_attack_travel_left = attack_travel_time


func _advance_attack_travel(delta: float) -> void:
	_attack_travel_left = maxf(0.0, _attack_travel_left - delta)
	_advance_attack_animation(delta)
	var progress := 1.0 - _attack_travel_left / attack_travel_time
	var previous := global_position
	var intended := _attack_origin.lerp(_attack_destination, progress)
	var safe_point := _clear_attack_path(previous, intended)
	if attack_pattern == AttackPattern.LEAP:
		var jump_offset := -sin(PI * progress) * jump_height
		sprite.position = _sprite_rest_position + Vector2(0.0, jump_offset)
		body_shape.position = _body_rest_position + Vector2(0.0, jump_offset)
		_check_leap_player_contact()
	var collision := move_and_collide(safe_point - previous)
	var blocked := collision != null or not safe_point.is_equal_approx(intended)
	if attack_pattern == AttackPattern.LEAP:
		if collision:
			_handle_leap_contact(collision.get_collider())
		_check_leap_player_contact()
	else:
		_update_movement_animation(delta, _attack_heading)
		_hit_charge_path(previous, global_position)
	_update_depth_order()
	if blocked or _attack_travel_left <= 0.0:
		if attack_pattern == AttackPattern.LEAP:
			_attack_destination = global_position
			_hit_attack_circle(global_position, attack_impact_radius)
		_finish_attack()
		return


func _hit_attack_circle(center: Vector2, radius: float) -> void:
	if attack_pattern == AttackPattern.LEAP and _leap_contact_hit:
		return
	if _can_hit_attack_target() and _attack_target.global_position.distance_squared_to(center) <= radius * radius:
		if attack_pattern == AttackPattern.LEAP:
			_leap_contact_hit = true
		_attack_target.call("take_damage", attack_damage, global_position)


func _check_leap_player_contact() -> void:
	if _leap_contact_hit or not is_instance_valid(_attack_target):
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = body_shape.global_transform
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var collider := result.get("collider") as Node2D
		if collider == _attack_target:
			_handle_leap_contact(collider)
			return


func _handle_leap_contact(collider: Object) -> void:
	if _leap_contact_hit or not collider is Node2D:
		return
	var player := collider as Node2D
	if not player.is_in_group("map_player"):
		return
	if player.has_method("is_dashing") and bool(player.call("is_dashing")):
		return
	_leap_contact_hit = true
	if player.has_method("take_damage"):
		player.call("take_damage", attack_damage, global_position)


func _hit_charge_path(previous: Vector2, current: Vector2) -> void:
	if _charge_hit or not _can_hit_attack_target():
		return
	var lead := _attack_heading * charge_tusk_offset
	var closest := previous + lead
	if not previous.is_equal_approx(current):
		closest = Geometry2D.get_closest_point_to_segment(_attack_target.global_position, previous + lead, current + lead)
	if closest.distance_squared_to(_attack_target.global_position) <= attack_impact_radius * attack_impact_radius:
		_charge_hit = true
		_attack_target.call("take_damage", attack_damage, global_position)


func _can_hit_attack_target() -> bool:
	if not is_instance_valid(_attack_target) or not _attack_target.has_method("take_damage"):
		return false
	if _area and (not Rect2(Vector2.ZERO, _area.area_size).has_point(_area.to_local(_attack_target.global_position)) or
		_area.get_path_light_exposure(_attack_target.global_position) > 0.0):
		return false
	return true


func _finish_attack() -> void:
	_clear_attack()
	_stop_movement_animation()
	_attack_cooldown_left = attack_cooldown
	_update_depth_order()


func _clear_attack() -> void:
	sprite.position = _sprite_rest_position
	body_shape.position = _body_rest_position
	_attack_target = null
	_attack_windup_left = 0.0
	_attack_travel_left = 0.0
	_leap_contact_hit = false
	if not _attack_animation_frames.is_empty():
		sprite.texture = _idle_texture
		sprite.flip_h = false
	_attack_animation_frames = []
	_attack_animation_elapsed = 0.0
	_attack_animation_frame = -1
	sprite.position = _sprite_rest_position


func _move_in_direction(direction: Vector2, delta: float, speed_multiplier: float = 1.0) -> void:
	velocity = direction * chase_speed * speed_multiplier
	if not direction.is_zero_approx():
		move_and_slide()
	_update_movement_animation(delta, velocity)
	_update_depth_order()


func _chase_direction(heading: Vector2, distance: float) -> Vector2:
	if not _area:
		return heading
	var look_ahead := minf(LIGHT_LOOK_AHEAD, distance)
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
		var direction := heading.rotated(angle)
		var probe := global_position + direction * look_ahead
		if _inside_area(probe) and _area.get_path_light_exposure(probe) <= 0.0:
			return direction
	return Vector2.ZERO


func _direction_away_from_light() -> Vector2:
	var preferred := velocity.normalized() if not velocity.is_zero_approx() else Vector2.UP
	var best_direction := Vector2.ZERO
	var best_exposure := INF
	for index in range(8):
		var direction := preferred.rotated(float(index) * TAU / 8.0)
		var probe := global_position + direction * LIGHT_LOOK_AHEAD
		if not _inside_area(probe):
			continue
		var exposure := _area.get_path_light_exposure(probe)
		if exposure < best_exposure - 0.001:
			best_exposure = exposure
			best_direction = direction
	return best_direction


func _inside_area(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, _area.area_size).grow(-AREA_MARGIN).has_point(_area.to_local(point))


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
	if not _active or not is_alive or damage <= 0:
		return
	_clear_attack()
	health = maxi(0, health - damage)
	_show_damage_feedback(damage)
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


func _show_damage_feedback(damage: int) -> void:
	var popup := Label.new()
	popup.name = "DamageNumber"
	popup.text = str(damage)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 30)
	popup.add_theme_color_override("font_color", Color("fff0bd"))
	popup.add_theme_color_override("font_outline_color", Color("26182c"))
	popup.add_theme_constant_override("outline_size", 6)
	popup.z_as_relative = false
	popup.z_index = 350
	popup.position = global_position + Vector2(-36.0, -sprite.texture.get_height() * sprite.scale.y * 0.45)
	get_tree().current_scene.add_child(popup)
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y - 52.0, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.62).set_delay(0.28)
	tween.chain().tween_callback(popup.queue_free)


func _die() -> void:
	is_alive = false
	_apply_active(false)
	if core_light_amount <= 0:
		return
	var core := LIGHT_CORE.new()
	var core_parent := _area if _area else get_parent() as Node2D
	if not core_parent:
		core.free()
		return
	core.name = "LightCore"
	core.light_amount = core_light_amount
	core.glow_color = glow_color
	core.z_as_relative = false
	core.z_index = z_index + 1
	core.position = core_parent.to_local(global_position)
	core_parent.add_child(core, true)


func _on_sight_body_entered(body: Node2D) -> void:
	if _active and is_alive and body.is_in_group("map_player"):
		target = body
		_stop_movement_animation()

func _on_sight_body_exited(body: Node2D) -> void:
	if body == target:
		target = null
		velocity = Vector2.ZERO
		_stop_movement_animation()

func _update_depth_order() -> void:
	var sprite_bottom := _sprite_rest_position.y + sprite.texture.get_height() * sprite.scale.y * 0.5
	var sort_y := global_position.y + sprite_bottom
	if _area:
		sort_y -= _area.global_position.y
	z_index = clampi(roundi(sort_y / 8.0), 1, 256)
