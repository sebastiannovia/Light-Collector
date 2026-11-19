extends Resource
class_name ItemDefinition

@export var item_id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export_range(1, 999999, 1) var max_stack_size := 99
@export_range(1, 999999, 1) var max_carry_quantity := 99
@export var icon: Texture2D
@export_range(0.1, 1.0, 0.05) var inventory_icon_scale := 1.0
@export var world_texture: Texture2D
@export_range(0.1, 4.0, 0.05) var world_texture_scale := 1.0
@export var world_texture_offset := Vector2.ZERO
@export var world_color := Color("d69a55")
@export var drop_scene: PackedScene
