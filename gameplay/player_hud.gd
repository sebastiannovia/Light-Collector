extends Control
class_name PlayerHUD

var style: PlayerHUDStyle
var health := 100.0
var health_max := 100.0
var sleep := 100.0
var sleep_max := 100.0
var lights := 0
var _notifications: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(queue_redraw)

func configure(hud_style: PlayerHUDStyle, initial_health: float, maximum_health: float, initial_sleep: float, maximum_sleep: float, initial_lights: int) -> void:
	style = hud_style
	set_health(initial_health, maximum_health)
	set_sleep(initial_sleep, maximum_sleep)
	set_lights(initial_lights)
	queue_redraw()

func set_health(value: float, maximum: float) -> void:
	health_max = maxf(maximum, 0.0)
	health = clampf(value, 0.0, health_max)
	queue_redraw()

func set_sleep(value: float, maximum: float) -> void:
	sleep_max = maxf(maximum, 0.0)
	sleep = clampf(value, 0.0, sleep_max)
	queue_redraw()

func set_lights(value: int) -> void:
	lights = maxi(0, value)
	queue_redraw()

func notify_item(item_name: String, quantity: int, icon: Texture2D = null, fallback_color: Color = Color("d69a55")) -> void:
	if not style or not style.notifications_enabled or quantity <= 0:
		return
	_notifications.append({
		"text": "+%d %s" % [quantity, item_name],
		"icon": icon,
		"color": fallback_color,
		"remaining": style.notification_duration,
	})
	while _notifications.size() > style.notification_limit:
		_notifications.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	if _notifications.is_empty():
		return
	for index in range(_notifications.size() - 1, -1, -1):
		_notifications[index].remaining = float(_notifications[index].remaining) - delta
		if _notifications[index].remaining <= 0.0:
			_notifications.remove_at(index)
	queue_redraw()

func _draw() -> void:
	if not style:
		return
	_draw_status_hud()
	_draw_notifications()

func _draw_status_hud() -> void:
	var panel_rect := Rect2(style.status_position, style.status_panel_size)
	draw_style_box(_make_panel_style(style.status_panel_color, style.status_border_color, style.status_border_width, style.status_corner_radius), panel_rect)
	var font: Font = style.status_font if style.status_font else ThemeDB.fallback_font
	var inner_width := maxf(1.0, style.status_panel_size.x - style.status_padding * 2.0)
	var bar_width := minf(style.status_bar_size.x, inner_width)
	var bar_size := Vector2(bar_width, style.status_bar_size.y)
	var row_pitch := bar_size.y + style.status_row_spacing + style.status_font_size + 2.0
	var first_row_y := style.status_position.y + style.status_padding
	_draw_status_bar(font, style.health_label, health, health_max, style.health_bar_color, first_row_y, bar_size, inner_width)
	_draw_status_bar(font, style.sleep_label, sleep, sleep_max, style.sleep_bar_color, first_row_y + row_pitch, bar_size, inner_width)
	var light_y := first_row_y + row_pitch * 2.0 + style.status_font_size
	var left := style.status_position.x + style.status_padding
	var right := style.status_position.x + style.status_panel_size.x - style.status_padding
	draw_string(font, Vector2(left, light_y), style.lights_label, HORIZONTAL_ALIGNMENT_LEFT, inner_width * 0.55, style.status_font_size, style.status_text_color)
	var icon_center := Vector2(right - 48.0, light_y - style.status_font_size * 0.38)
	draw_circle(icon_center, style.lights_icon_radius, style.lights_icon_color)
	draw_circle(icon_center, style.lights_icon_center_radius, Color("fff5bf"))
	draw_string(font, Vector2(right - 32.0, light_y), str(lights), HORIZONTAL_ALIGNMENT_RIGHT, 32.0, style.status_value_font_size, style.status_value_color)

func _draw_status_bar(font: Font, label: String, value: float, maximum: float, fill_color: Color, row_y: float, bar_size: Vector2, inner_width: float) -> void:
	var left := style.status_position.x + style.status_padding
	var right := style.status_position.x + style.status_panel_size.x - style.status_padding
	var label_y := row_y + style.status_font_size
	var value_text := "%d / %d" % [roundi(value), roundi(maximum)]
	draw_string(font, Vector2(left, label_y), label, HORIZONTAL_ALIGNMENT_LEFT, inner_width * 0.58, style.status_font_size, style.status_text_color)
	draw_string(font, Vector2(left, label_y), value_text, HORIZONTAL_ALIGNMENT_RIGHT, inner_width, style.status_value_font_size, style.status_value_color)
	var bar_position := Vector2(left, label_y + style.status_label_bar_gap)
	var bar_rect := Rect2(bar_position, bar_size)
	draw_style_box(_make_panel_style(style.status_bar_background, style.status_border_color.darkened(0.45), 1, style.status_corner_radius), bar_rect)
	var ratio := clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if ratio > 0.0:
		var fill_rect := Rect2(bar_position, Vector2(bar_size.x * ratio, bar_size.y))
		draw_style_box(_make_panel_style(fill_color, fill_color, 0, style.status_corner_radius), fill_rect)

func _draw_notifications() -> void:
	if not style.notifications_enabled or _notifications.is_empty():
		return
	var notification_height := style.notification_size.y
	var block_height := _notifications.size() * notification_height + maxi(0, _notifications.size() - 1) * style.notification_spacing
	var first_y := size.y * 0.5 + style.notification_vertical_offset - block_height * 0.5
	var font: Font = style.notification_font if style.notification_font else ThemeDB.fallback_font
	for index in _notifications.size():
		var notification: Dictionary = _notifications[index]
		var remaining: float = notification.remaining
		var fade_alpha := 1.0
		if style.notification_fade_time > 0.0:
			fade_alpha = clampf(remaining / style.notification_fade_time, 0.0, 1.0)
		var background := style.notification_panel_color
		background.a *= fade_alpha
		var border := style.notification_border_color
		border.a *= fade_alpha
		var origin := Vector2(style.notification_left_margin, first_y + index * (notification_height + style.notification_spacing))
		var panel := _make_panel_style(background, border, style.notification_border_width, style.notification_corner_radius)
		draw_style_box(panel, Rect2(origin, style.notification_size))
		var item_icon: Texture2D = notification.icon
		var icon_size := minf(style.notification_icon_size, notification_height - 16.0)
		var icon_rect := Rect2(origin + Vector2(style.notification_horizontal_padding, (notification_height - icon_size) * 0.5), Vector2(icon_size, icon_size))
		if item_icon:
			draw_texture_rect(item_icon, icon_rect, false, Color(1.0, 1.0, 1.0, fade_alpha))
		else:
			draw_circle(icon_rect.get_center(), icon_size * style.notification_fallback_icon_radius_ratio, notification.color)
		var text_color := style.notification_text_color
		text_color.a *= fade_alpha
		var text_left := origin.x + style.notification_horizontal_padding + icon_size + style.notification_text_gap
		draw_string(font, Vector2(text_left, origin.y + notification_height * 0.5 + style.notification_font_size * 0.35), notification.text, HORIZONTAL_ALIGNMENT_LEFT, style.notification_size.x - (text_left - origin.x) - style.notification_horizontal_padding, style.notification_font_size, text_color)

func _make_panel_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = background
	panel.border_color = border
	panel.set_border_width_all(border_width)
	panel.set_corner_radius_all(radius)
	return panel
