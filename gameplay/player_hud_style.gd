@tool
extends Resource
class_name PlayerHUDStyle

@export_group("Status HUD - Layout")
@export var status_position := Vector2(28.0, 28.0)
@export var status_panel_size := Vector2(320.0, 174.0)
@export var status_padding := 14.0
@export var status_row_spacing := 9.0
@export var status_bar_size := Vector2(250.0, 18.0)
@export var status_label_bar_gap := 4.0
@export var status_corner_radius := 8
@export var status_border_width := 2
@export_range(0.0, 24.0, 1.0) var lights_icon_radius := 9.0
@export_range(0.0, 24.0, 1.0) var lights_icon_center_radius := 4.0

@export_group("Status HUD - Text")
@export var health_label := "Health"
@export var sleep_label := "Sleep"
@export var lights_label := "Lights"
@export var status_font: Font
@export_range(8, 48, 1) var status_font_size := 15
@export_range(8, 48, 1) var status_value_font_size := 14
@export var status_text_color := Color("f4f0df")
@export var status_value_color := Color("ffffff")

@export_group("Status HUD - Colors")
@export var status_panel_color := Color("14202ddd")
@export var status_border_color := Color("ffd166")
@export var status_bar_background := Color("28343d")
@export var health_bar_color := Color("d95757")
@export var sleep_bar_color := Color("617bd5")
@export var lights_icon_color := Color("ffd166")

@export_group("Collection Notifications - Layout")
@export var notifications_enabled := true
@export var notification_left_margin := 24.0
@export var notification_vertical_offset := 0.0
@export var notification_size := Vector2(300.0, 58.0)
@export var notification_spacing := 9.0
@export var notification_icon_size := 36.0
@export var notification_horizontal_padding := 10.0
@export var notification_text_gap := 12.0
@export_range(0.0, 1.0, 0.01) var notification_fallback_icon_radius_ratio := 0.32
@export_range(1, 8, 1) var notification_limit := 4
@export_range(0.2, 10.0, 0.1) var notification_duration := 2.4
@export_range(0.0, 3.0, 0.05) var notification_fade_time := 0.35
@export var notification_corner_radius := 8
@export var notification_border_width := 1

@export_group("Collection Notifications - Style")
@export var notification_panel_color := Color("14202de8")
@export var notification_border_color := Color("d69a55")
@export var notification_text_color := Color("f4f0df")
@export var notification_font: Font
@export_range(8, 48, 1) var notification_font_size := 16
