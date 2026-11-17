extends Node
class_name ItemDatabase

@export var definitions: Array[ItemDefinition] = []
@export var definition_paths: Array[String] = []

func _ready() -> void:
	if definitions.is_empty():
		for resource_path in definition_paths:
			var definition := load(resource_path) as ItemDefinition
			if definition:
				definitions.append(definition)
	add_to_group("item_database")

func get_definition(item_id: StringName) -> ItemDefinition:
	for definition in definitions:
		if definition and definition.item_id == item_id:
			return definition
	return null

func get_all_definitions() -> Array[ItemDefinition]:
	return definitions.duplicate()
