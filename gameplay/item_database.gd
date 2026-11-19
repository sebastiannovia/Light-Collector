extends Node
class_name ItemDatabase

const DEFAULT_DEFINITION_PATHS: Array[String] = [
	"res://gameplay/items/wood.tres",
	"res://gameplay/items/stone.tres",
	"res://gameplay/items/iron.tres",
	"res://gameplay/items/wild_berry.tres",
	"res://gameplay/items/forest_mushroom.tres",
	"res://gameplay/items/glow_herb.tres",
	"res://gameplay/items/tablet_1.tres",
]

@export var definitions: Array[ItemDefinition] = []
@export var definition_paths: Array[String] = []

func _ready() -> void:
	var paths := DEFAULT_DEFINITION_PATHS.duplicate()
	for resource_path in definition_paths:
		if not paths.has(resource_path):
			paths.append(resource_path)
	for resource_path in paths:
		var definition := load(resource_path) as ItemDefinition
		if definition and not get_definition(definition.item_id):
			definitions.append(definition)
	add_to_group("item_database")

func get_definition(item_id: StringName) -> ItemDefinition:
	for definition in definitions:
		if definition and definition.item_id == item_id:
			return definition
	return null

func get_all_definitions() -> Array[ItemDefinition]:
	return definitions.duplicate()
