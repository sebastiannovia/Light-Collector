extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_continue_pressed() -> void:
	visible = false
	get_tree().paused = false


func _on_button_exit_pressed() -> void:
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_pause"):
		toggle_menu()
		get_viewport().set_input_as_handled()

func toggle_menu() -> void:
	visible = !visible
	get_tree().paused = visible
