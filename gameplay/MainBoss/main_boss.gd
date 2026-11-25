@tool
extends Node2D

signal fight_won

enum Attack { NONE, EYE, SWIPE }

const PlayerController = preload("res://template_player.gd")
const BossTail = preload("res://gameplay/MainBoss/boss_tail.gd")
const EYE := 0
const MOUTH := 1
const ATTACK_ROTATION := [Attack.EYE, Attack.SWIPE, Attack.SWIPE]
const EYE_COLOR := Color("78e9e3")

@export_group("Arena")
@export var arena := Rect2(-1100, -665, 2200, 1530):
	set(value):
		arena = value.abs()
		queue_redraw()
@export_group("Tails")
@export_range(1, 12, 1) var tails_per_side := 3
@export_range(1, 3000, 1) var tail_health := 240
@export_range(0.1, 5.0, 0.05) var replacement_delay := 1.15
@export_group("Attacks")
@export_range(0.1, 6.0, 0.05) var attack_pause := 1.15
@export_range(0.1, 5.0, 0.05) var eye_aim_time := 0.62
@export_range(0.1, 5.0, 0.05) var eye_lock_time := 0.78
@export_range(24.0, 350.0, 1.0) var eye_radius := 120.0
@export_range(0.0, 100.0, 1.0) var eye_damage := 20.0
@export_range(0.1, 5.0, 0.05) var swipe_windup := 0.72
@export_range(0.2, 6.0, 0.05) var swipe_duration := 1.95
@export_range(12.0, 160.0, 1.0) var swipe_width := 112.0
@export_range(0.0, 100.0, 1.0) var swipe_damage := 25.0

var _player: PlayerController
var _fighting := false
var _won := false
var _hud_time := 0.0
var _remaining := [0, 0]
var _replacement_time := [0.0, 0.0]
var _attack := Attack.NONE
var _attack_time := 0.0
var _delay := 0.0
var _next_attack := 0
var _next_swipe_side := MOUTH
var _attacking_tail := -1
var _attack_hit := false
var _eye_target := Vector2.ZERO
var _swipe_direction := 1.0

@onready var _tails: Array[BossTail] = [$EyeTail, $MouthTail]
@onready var _back_tails: Sprite2D = $BackTails
@onready var _effects: Node2D = $AttackEffects
@onready var _panel: Control = $HUD/BossPanel
@onready var _title: Label = $HUD/BossPanel/Content/Title
@onready var _detail: Label = $HUD/BossPanel/Content/Detail


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	for side in range(_tails.size()):
		_tails[side].defeated.connect(_on_tail_defeated.bind(side))
		_tails[side].set_active(false)
	_effects.draw.connect(_draw_attack_effects)
	_panel.hide()
	_player = get_tree().get_first_node_in_group("map_player") as PlayerController
	if not _player:
		_find_player.call_deferred()


func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("map_player") as PlayerController


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if _hud_time > 0.0:
		_hud_time = maxf(0.0, _hud_time - delta)
		if _hud_time == 0.0:
			_panel.hide()
	if _won:
		return
	if not _fighting:
		var entry_margin := minf(80.0, minf(arena.size.x, arena.size.y) * 0.15)
		if not _player.transitioning and _player.health_current > 0.0 and is_visible_in_tree() and arena.grow(-entry_margin).has_point(to_local(_player.global_position)):
			_begin_fight()
		return
	if _player.health_current <= 0.0:
		_retry()
		return
	for side in range(_tails.size()):
		if _replacement_time[side] > 0.0:
			_replacement_time[side] = maxf(0.0, _replacement_time[side] - delta)
			if _replacement_time[side] == 0.0:
				_tails[side].summon(tail_health, side == EYE)
	if _attack == Attack.NONE:
		_delay = maxf(0.0, _delay - delta)
		if _delay == 0.0:
			_begin_attack()
	else:
		_advance_attack(delta)


func _begin_fight() -> void:
	_fighting = true
	_hud_time = 0.0
	_player.movement_bounds = Rect2(to_global(arena.position), arena.size)
	for side in range(_tails.size()):
		_remaining[side] = tails_per_side
		_replacement_time[side] = 0.0
		_tails[side].summon(tail_health, side == EYE)
	_next_attack = 0
	_next_swipe_side = MOUTH
	_delay = 1.35
	_title.text = "The Hollow Fox"
	_update_tail_count()
	_panel.show()


func _on_tail_defeated(side: int) -> void:
	_remaining[side] -= 1
	if _attacking_tail == side:
		_end_attack()
	if _remaining[EYE] + _remaining[MOUTH] == 0:
		_finish_fight()
		return
	if _remaining[side] > 0:
		_replacement_time[side] = replacement_delay
	_update_tail_count()


func _update_tail_count() -> void:
	_detail.text = "Eye tails: %d     •     Mouth tails: %d" % [_remaining[EYE], _remaining[MOUTH]]


func _begin_attack() -> void:
	if not _tails[EYE].visible and not _tails[MOUTH].visible:
		return
	# Preserve the rotation while skipping attacks whose tail is absent.
	for _step in range(ATTACK_ROTATION.size()):
		var candidate: Attack = ATTACK_ROTATION[_next_attack]
		_next_attack = (_next_attack + 1) % ATTACK_ROTATION.size()
		match candidate:
			Attack.EYE:
				if not _tails[EYE].visible:
					continue
				_attacking_tail = EYE
			Attack.SWIPE:
				var side := _next_swipe_side
				if not _tails[side].visible:
					side = 1 - side
				if not _tails[side].visible:
					continue
				_attacking_tail = side
				_next_swipe_side = 1 - side
				_swipe_direction = 1.0 if _tails[side].position.x < arena.get_center().x else -1.0
		_attack = candidate
		break
	_attack_time = 0.0
	_attack_hit = false
	_eye_target = to_local(_player.global_position)
	_effects.queue_redraw()


func _advance_attack(delta: float) -> void:
	_attack_time += delta
	var player_point := to_local(_player.global_position)
	match _attack:
		Attack.EYE:
			if _attack_time < eye_aim_time:
				_eye_target = player_point
			var impact_time := eye_aim_time + eye_lock_time
			if _attack_time >= impact_time and not _attack_hit:
				_attack_hit = true
				if player_point.distance_to(_eye_target) <= eye_radius:
					_player.take_damage(eye_damage)
			if _attack_time >= impact_time + 0.22:
				_end_attack()
		Attack.SWIPE:
			_advance_swipe(delta, player_point)
	_effects.queue_redraw()


func _advance_swipe(delta: float, player_point: Vector2) -> void:
	var tail := _tails[_attacking_tail]
	if _attack_time < swipe_windup:
		tail.set_swipe_angle(-_swipe_direction * 0.35 * (_attack_time / swipe_windup))
		return
	var progress := _swipe_progress(_attack_time)
	tail.set_swipe_angle(_swipe_direction * lerpf(-0.35, 0.45, progress))
	if not _attack_hit:
		var y_fraction := clampf(inverse_lerp(arena.position.y, arena.end.y, player_point.y), 0.0, 1.0)
		var previous_x := _swipe_x(_swipe_progress(_attack_time - delta), y_fraction)
		var current_x := _swipe_x(progress, y_fraction)
		var half_width := _swipe_half_width(y_fraction)
		if player_point.x >= minf(previous_x, current_x) - half_width and player_point.x <= maxf(previous_x, current_x) + half_width:
			_attack_hit = true
			_player.take_damage(swipe_damage)
	if progress >= 1.0:
		_end_attack()


func _swipe_progress(time: float) -> float:
	return clampf((time - swipe_windup) / swipe_duration, 0.0, 1.0)


func _swipe_x(progress: float, y_fraction: float) -> float:
	var travel := lerpf(-1.0, 1.0, progress) * (arena.size.x * 0.5 + swipe_width)
	var bend := sin(progress * PI) * sin(y_fraction * PI) * minf(145.0, arena.size.x * 0.1)
	return arena.get_center().x + _swipe_direction * (travel + bend)


func _swipe_half_width(y_fraction: float) -> float:
	return swipe_width * 0.5 * lerpf(1.0, 0.38, y_fraction)


func _end_attack() -> void:
	if _attack == Attack.SWIPE:
		_tails[_attacking_tail].set_swipe_angle(0.0)
	_attacking_tail = -1
	_attack = Attack.NONE
	_delay = attack_pause
	_effects.queue_redraw()


func _release_arena() -> void:
	_fighting = false
	_end_attack()
	_player.movement_bounds = Rect2()
	for tail in _tails:
		tail.set_active(false)


func _retry() -> void:
	_release_arena()
	# Stay in the cave and restart when the player steps back into the arena.
	_player.global_position = to_global(Vector2(arena.get_center().x, arena.end.y + 180.0))
	_player.camera.reset_smoothing()
	_player.set_health(_player.health_max)
	_title.text = "Defeated"
	_detail.text = "Enter the arena to try again."
	_hud_time = 4.0


func _finish_fight() -> void:
	_release_arena()
	_won = true
	_title.text = "The Hollow Fox defeated"
	_detail.text = "All tails destroyed."
	_hud_time = 5.0
	fight_won.emit()


func _draw() -> void:
	var floor_style := StyleBoxFlat.new()
	floor_style.bg_color = Color("29213b")
	floor_style.border_color = Color("78618f")
	floor_style.set_border_width_all(7)
	floor_style.set_corner_radius_all(52)
	draw_style_box(floor_style, arena)
	draw_arc(arena.get_center(), minf(arena.size.x, arena.size.y) * 0.36, 0, TAU, 80, Color("584772"), 4.0, true)
	if is_instance_valid(_back_tails) and not _back_tails.texture:
		_draw_back_tails()


func _draw_back_tails() -> void:
	# Silhouettes fill the 790 x 600 slot until the rear sprite is assigned.
	for direction in [-1.0, 1.0]:
		var points := PackedVector2Array()
		for point: Vector2 in [Vector2(0, 300), Vector2(185, 130), Vector2(255, -130), Vector2(395, -300), Vector2(344, -22), Vector2(309, 190), Vector2(130, 300)]:
			points.append(_back_tails.position + Vector2(point.x * direction, point.y))
		draw_colored_polygon(points, Color("4b355f"))


func _draw_attack_effects() -> void:
	match _attack:
		Attack.EYE:
			var impact := _attack_time >= eye_aim_time + eye_lock_time
			var color := EYE_COLOR if _attack_time < eye_aim_time else Color("fff1ba")
			_effects.draw_circle(_eye_target, eye_radius, Color(color, 0.55 if impact else 0.16))
			_effects.draw_arc(_eye_target, eye_radius, 0, TAU, 48, color, 5.0, true)
			_effects.draw_line(_eye_target - Vector2(34, 0), _eye_target + Vector2(34, 0), color, 4.0, true)
			_effects.draw_line(_eye_target - Vector2(0, 34), _eye_target + Vector2(0, 34), color, 4.0, true)
		Attack.SWIPE:
			if _attack_time >= swipe_windup:
				_draw_swipe(_swipe_progress(_attack_time))


func _draw_swipe(progress: float) -> void:
	var tail := _tails[_attacking_tail]
	var color := tail.eye_color if _attacking_tail == EYE else tail.mouth_color
	var fill := color.darkened(0.50)
	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var center := PackedVector2Array()
	const SEGMENTS := 24
	for index in range(SEGMENTS + 1):
		var fraction := float(index) / float(SEGMENTS)
		var point := Vector2(_swipe_x(progress, fraction), lerpf(arena.position.y, arena.end.y, fraction))
		var half_width := _swipe_half_width(fraction)
		left_edge.append(point - Vector2(half_width, 0))
		right_edge.append(point + Vector2(half_width, 0))
		center.append(point)
	var origin := tail.position + Vector2(0, -115)
	var root := center[0]
	var attachment := PackedVector2Array([origin, Vector2(origin.x, root.y - 110), root])
	_effects.draw_polyline(attachment, Color(fill, 0.68), swipe_width * 0.55, true)
	var reversed_edge := right_edge.duplicate()
	reversed_edge.reverse()
	_effects.draw_colored_polygon(left_edge + reversed_edge, fill)
	var leading_edge := right_edge if _swipe_direction > 0.0 else left_edge
	_effects.draw_polyline(leading_edge, color, 8.0, true)
	_effects.draw_polyline(center, Color(color, 0.65), 5.0, true)
