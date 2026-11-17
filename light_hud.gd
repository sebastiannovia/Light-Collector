extends Control
class_name LightHUD

var count := 0
var hud_position := Vector2(28.0, 28.0)
var panel_size := Vector2(220.0, 64.0)
var panel_color := Color("14202ddd")
var border_color := Color("ffd166")
var text_color := Color("f4f0df")
var light_color := Color("ffd166")

func configure(initial_count: int, position_on_screen: Vector2) -> void:
	count = maxi(0, initial_count)
	hud_position = position_on_screen
	position = hud_position
	size = panel_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_count(new_count: int) -> void:
	count = maxi(0, new_count)
	queue_redraw()

func _draw() -> void:
	draw_style_box(_make_panel_style(), Rect2(Vector2.ZERO, panel_size))
	var center := Vector2(34.0, panel_size.y * 0.5)
	draw_circle(center, 13.0, light_color)
	draw_circle(center, 7.0, Color("fff5bf"))
	draw_string(ThemeDB.fallback_font, Vector2(58.0, 28.0), "Light", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, text_color)
	draw_string(ThemeDB.fallback_font, Vector2(58.0, 51.0), str(count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, border_color)

func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style
