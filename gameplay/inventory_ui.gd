extends Control
class_name InventoryUI

const WINDOW_SIZE := Vector2(520, 390)
const SLOT_SIZE := Vector2(64, 64)
const SLOT_GAP := 8.0
const GRID_ORIGIN := Vector2(18, 66)
const HEADER_HEIGHT := 48.0
const PANEL_COLOR := Color("152231ee")
const BORDER_COLOR := Color("d69a55")
const TEXT_COLOR := Color("f4f0df")
const MUTED_COLOR := Color("8998a5")

var inventory: PlayerInventory
var _dragging_window := false
var _dragging_slot := -1
var _hovered_slot := -1
var _drag_offset := Vector2.ZERO
var _mouse_position := Vector2.ZERO

func configure(source: PlayerInventory) -> void:
	inventory = source
	size = WINDOW_SIZE
	position = (get_viewport_rect().size - size) * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	if inventory and not inventory.inventory_changed.is_connected(queue_redraw):
		inventory.inventory_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.border_color = BORDER_COLOR
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(9)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(0, 0, size.x, HEADER_HEIGHT), Color("263746"))
	draw_string(ThemeDB.fallback_font, Vector2(18, 31), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, TEXT_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 112, 30), "Drag window", HORIZONTAL_ALIGNMENT_RIGHT, 72, 12, MUTED_COLOR)
	_draw_close_button()
	if not inventory:
		return

	var slots := inventory.get_slots()
	for row in inventory.rows:
		for column in inventory.columns:
			var index := row * inventory.columns + column
			var origin := _slot_origin(index)
			var filled: bool = index < slots.size() and slots[index].quantity > 0
			var slot_style := StyleBoxFlat.new()
			slot_style.bg_color = Color("38424a") if filled else Color("202b33")
			slot_style.border_color = Color("ffd166") if index == _hovered_slot else Color("9d7347") if filled else Color("59636a")
			slot_style.set_border_width_all(2 if index == _hovered_slot else 1)
			slot_style.set_corner_radius_all(5)
			draw_style_box(slot_style, Rect2(origin, SLOT_SIZE))
			if filled:
				var definition := inventory.get_item_definition(slots[index].item_id)
				if definition and definition.icon:
					draw_texture_rect(definition.icon, _item_icon_rect(origin, definition), false)
				elif definition:
					draw_circle(origin + SLOT_SIZE * 0.5, 13.0, definition.world_color)
				draw_string(ThemeDB.fallback_font, origin + Vector2(4, 58), str(slots[index].quantity), HORIZONTAL_ALIGNMENT_RIGHT, 56, 14, TEXT_COLOR)

	var feedback := inventory.get_feedback()
	if not feedback.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(18, size.y - 12), feedback, HORIZONTAL_ALIGNMENT_LEFT, size.x - 36, 14, Color("ffd166"))
	if _dragging_slot < 0:
		_draw_item_tooltip(slots)
	else:
		_draw_dragged_item(slots)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if Rect2(size.x - 40, 6, 32, 32).has_point(event.position):
				visible = false
				accept_event()
				return
			if event.position.y <= HEADER_HEIGHT:
				_dragging_window = true
				_drag_offset = event.global_position - global_position
				accept_event()
				return
			var pressed_slot := _slot_at(event.position)
			if pressed_slot >= 0 and _has_item_at(pressed_slot):
				_dragging_slot = pressed_slot
				_mouse_position = event.position
				_hovered_slot = pressed_slot
				queue_redraw()
				accept_event()
		else:
			if _dragging_window:
				_dragging_window = false
				accept_event()
			elif _dragging_slot >= 0:
				var destination := _slot_at(event.position)
				if destination >= 0:
					inventory.move_item(_dragging_slot, destination)
				_dragging_slot = -1
				_hovered_slot = destination
				queue_redraw()
				accept_event()
	elif event is InputEventMouseMotion:
		_mouse_position = event.position
		if _dragging_window:
			position = event.global_position - _drag_offset
			var viewport := get_viewport_rect().size
			position.x = clampf(position.x, 0.0, maxf(0.0, viewport.x - size.x))
			position.y = clampf(position.y, 0.0, maxf(0.0, viewport.y - size.y))
			accept_event()
		else:
			var hovered := _slot_at(event.position)
			if hovered != _hovered_slot:
				_hovered_slot = hovered
				queue_redraw()
			if _dragging_slot >= 0:
				queue_redraw()

func _draw_close_button() -> void:
	var button_rect := Rect2(size.x - 40, 6, 32, 32)
	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color("513b3e")
	button_style.border_color = Color("d69a55")
	button_style.set_border_width_all(1)
	button_style.set_corner_radius_all(5)
	draw_style_box(button_style, button_rect)
	var center := button_rect.position + button_rect.size * 0.5
	draw_line(center + Vector2(-5, -5), center + Vector2(5, 5), TEXT_COLOR, 2.0)
	draw_line(center + Vector2(5, -5), center + Vector2(-5, 5), TEXT_COLOR, 2.0)

func _draw_item_tooltip(slots: Array[Dictionary]) -> void:
	if _hovered_slot < 0 or _hovered_slot >= slots.size() or slots[_hovered_slot].quantity <= 0:
		return
	var item_id: StringName = slots[_hovered_slot].item_id
	var definition := inventory.get_item_definition(item_id)
	var item_name := definition.display_name if definition and not definition.display_name.is_empty() else String(item_id)
	var description: String = definition.description if definition and not definition.description.is_empty() else "No description available."
	var lines := _wrap_description(description, 30)
	var tooltip_size := Vector2(224, 43 + lines.size() * 15)
	var origin := _slot_origin(_hovered_slot)
	var tooltip_position := origin + Vector2(SLOT_SIZE.x + 10, 0)
	if tooltip_position.x + tooltip_size.x > size.x - 6:
		tooltip_position.x = origin.x - tooltip_size.x - 10
	if tooltip_position.y + tooltip_size.y > size.y - 6:
		tooltip_position.y = size.y - tooltip_size.y - 6
	tooltip_position.y = maxf(HEADER_HEIGHT + 2, tooltip_position.y)
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color("101923f5")
	tooltip_style.border_color = BORDER_COLOR
	tooltip_style.set_border_width_all(1)
	tooltip_style.set_corner_radius_all(6)
	draw_style_box(tooltip_style, Rect2(tooltip_position, tooltip_size))
	draw_string(ThemeDB.fallback_font, tooltip_position + Vector2(9, 18), item_name, HORIZONTAL_ALIGNMENT_LEFT, tooltip_size.x - 18, 14, Color("ffd166"))
	for line_index in lines.size():
		draw_string(ThemeDB.fallback_font, tooltip_position + Vector2(9, 36 + line_index * 15), lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, tooltip_size.x - 18, 12, TEXT_COLOR)

func _draw_dragged_item(slots: Array[Dictionary]) -> void:
	if _dragging_slot < 0 or _dragging_slot >= slots.size():
		return
	var stack: Dictionary = slots[_dragging_slot]
	var origin := _mouse_position - SLOT_SIZE * 0.5
	var ghost_style := StyleBoxFlat.new()
	ghost_style.bg_color = Color("38424aee")
	ghost_style.border_color = Color("ffd166")
	ghost_style.set_border_width_all(2)
	ghost_style.set_corner_radius_all(5)
	draw_style_box(ghost_style, Rect2(origin, SLOT_SIZE))
	var definition := inventory.get_item_definition(stack.item_id)
	if definition and definition.icon:
		draw_texture_rect(definition.icon, _item_icon_rect(origin, definition), false)
	elif definition:
		draw_circle(origin + SLOT_SIZE * 0.5, 13.0, definition.world_color)
	draw_string(ThemeDB.fallback_font, origin + Vector2(4, 58), str(stack.quantity), HORIZONTAL_ALIGNMENT_RIGHT, 56, 14, TEXT_COLOR)

func _item_icon_rect(origin: Vector2, definition: ItemDefinition) -> Rect2:
	var icon_size := Vector2(40.0, 40.0) * definition.inventory_icon_scale
	var icon_center := origin + Vector2(32.0, 28.0)
	return Rect2(icon_center - icon_size * 0.5, icon_size)

func _wrap_description(text: String, max_characters: int) -> Array[String]:
	var result: Array[String] = []
	var current := ""
	for word in text.split(" "):
		if current.is_empty():
			current = word
		elif current.length() + word.length() + 1 <= max_characters:
			current += " " + word
		else:
			result.append(current)
			current = word
	if not current.is_empty():
		result.append(current)
	return result

func _slot_origin(index: int) -> Vector2:
	var row := floori(float(index) / float(inventory.columns))
	var column := index % inventory.columns
	return GRID_ORIGIN + Vector2(column * (SLOT_SIZE.x + SLOT_GAP), row * (SLOT_SIZE.y + SLOT_GAP))

func _slot_at(local_position: Vector2) -> int:
	if not inventory:
		return -1
	var relative := local_position - GRID_ORIGIN
	if relative.x < 0.0 or relative.y < 0.0:
		return -1
	var stride := SLOT_SIZE + Vector2(SLOT_GAP, SLOT_GAP)
	var column := floori(relative.x / stride.x)
	var row := floori(relative.y / stride.y)
	if column < 0 or column >= inventory.columns or row < 0 or row >= inventory.rows:
		return -1
	var within_slot := Vector2(fmod(relative.x, stride.x), fmod(relative.y, stride.y))
	if within_slot.x >= SLOT_SIZE.x or within_slot.y >= SLOT_SIZE.y:
		return -1
	return row * inventory.columns + column

func _has_item_at(index: int) -> bool:
	var slots := inventory.get_slots()
	return index >= 0 and index < slots.size() and slots[index].quantity > 0
