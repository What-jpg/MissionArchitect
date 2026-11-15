@tool
extends Area2D

@export_enum("archive", "map", "constructor", "lab", "launch", "comms") var action_id: String = "map"
@export var title_uk := "Консоль місій"
@export var title_en := "Mission console"

func is_near(point: Vector2) -> bool:
	# Foot positions, rather than sprite size, determine the floor and proximity.
	var local_point := to_local(point)
	return absf(local_point.y)<10 and local_point.length()<=$InteractionRadius.shape.radius

func display_name() -> String:
	return title_uk if State.language=="uk" else title_en
