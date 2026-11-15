@tool
extends Control
# Static layout lives in the scene. Mission-specific lists are populated by main.gd.
@export var title_uk := "Місія"
@export var title_en := "Mission"

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and has_node("Title"):
		$Title.text=title_uk.to_upper()
