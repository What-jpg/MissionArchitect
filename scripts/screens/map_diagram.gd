@tool
extends Control

@export var lunar := false:
	set(value):
		lunar=value
		if is_node_ready(): update_route()

func _ready() -> void:
	update_route()

func update_route() -> void:
	$EarthOrbitDots.visible=not lunar
	$Trajectory.visible=lunar
	$ArrowHead.visible=lunar
