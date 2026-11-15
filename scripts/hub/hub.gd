@tool
extends Node2D

signal interaction_requested(action: String)
@export var walk_speed := 65.0
@export var upper_walk_range := Vector2(10,310)
@export var lower_walk_range := Vector2(62,178)
@export var stair_radius := 10.0
@export_range(0.3,2.0,0.1) var climb_duration := 0.75
var lower_floor := false
var climbing := false
var climb_progress := 0.0
var climb_direction := 1.0
var animation_time := 0.0
var nearby: Area2D
# Name of the station the bouncing arrow points at ("" hides it).
var hint_target := ""
# The door swings open while the astronaut is close to it on the upper floor.
@export var door_reach := 20.0
# World x of the doorway strip (the sprite centre sits to the right because the open leaf swings out).
@export var doorway_x := 119.5
var door_open := false

func tick(delta: float) -> void:
	var player: Node2D = $Player
	var entry: Vector2 = to_local($Stairs/UpperEntry.global_position)
	var exit: Vector2 = to_local($Stairs/LowerEntry.global_position)
	var sprite: AnimatedSprite2D = $Player/AnimatedSprite2D
	var direction := Input.get_axis("left","right")
	if not climbing:
		if not lower_floor and absf(player.position.x-entry.x)<stair_radius and Input.is_action_pressed("down"):
			climbing=true
			climb_direction=1.0
			climb_progress=0
		elif lower_floor and absf(player.position.x-exit.x)<stair_radius and Input.is_action_pressed("up"):
			climbing=true
			climb_direction=-1.0
			climb_progress=1
	if climbing:
		climb_progress=clampf(climb_progress+climb_direction*delta/climb_duration,0,1)
		player.position=entry.lerp(exit,climb_progress)
		# Back view on the ladder: going down plays the same cycle in reverse.
		sprite.flip_h=false
		if climb_direction>0: sprite.play_backwards("climb")
		else: sprite.play("climb")
		if (climb_direction>0 and climb_progress>=1) or (climb_direction<0 and climb_progress<=0):
			climbing=false
			lower_floor=climb_direction>0
	else:
		var limits := lower_walk_range if lower_floor else upper_walk_range
		player.position.x=clampf(player.position.x+direction*walk_speed*delta,limits.x,limits.y)
		player.position.y=exit.y if lower_floor else entry.y
		if absf(direction)>0.1:
			sprite.play("walk")
			sprite.flip_h=direction<0
		else: sprite.play("idle")
	animation_time+=delta
	nearby=null if climbing else find_station(player.global_position)
	for station in $Stations.get_children():
		station.modulate=Color(1.18,1.18,1.08) if station==nearby else Color.WHITE
	update_hint_arrow()
	update_door(player)

func update_hint_arrow() -> void:
	var arrow: Polygon2D=get_node_or_null("HintArrow")
	if arrow==null:
		arrow=Polygon2D.new()
		arrow.name="HintArrow"
		arrow.polygon=PackedVector2Array([Vector2(-4,-5),Vector2(4,-5),Vector2(0,0)])
		arrow.color=Color("f2c94c")
		arrow.z_index=3
		add_child(arrow)
	var station: Node2D=$Stations.get_node_or_null(hint_target) if not hint_target.is_empty() else null
	arrow.visible=station!=null and station!=nearby
	if not arrow.visible: return
	var sprite: Sprite2D=station.get_node("Sprite2D")
	var top: float=sprite.position.y-sprite.texture.get_height()*sprite.scale.y/2.0
	if station.has_node("Assembly"):
		# The launch pad shows the player's assembled rocket: point at its nose.
		var rocket: Node2D=station.get_node("Assembly")
		top=rocket.position.y-float(rocket.get("height"))*rocket.scale.y
	# Float just above the object, below its room label.
	arrow.position=(station.position+Vector2(0,top-4+sin(animation_time*5.0)*1.5)).round()

func find_station(point: Vector2) -> Area2D:
	var found: Area2D = null
	var nearest := INF
	for station in $Stations.get_children():
		if station.is_near(point):
			var distance: float=point.distance_to(station.global_position)
			if distance<nearest:
				nearest=distance
				found=station
	return found

func interact() -> void:
	if climbing: return
	var station := find_station($Player.global_position)
	if station: interaction_requested.emit(station.action_id)

func prompt() -> String:
	if is_instance_valid(nearby): return "E — "+nearby.display_name()
	return ""

func update_door(player: Node2D) -> void:
	var door: AnimatedSprite2D=get_node_or_null("Door")
	if door==null: return
	var near: bool=not lower_floor and not climbing and absf(player.position.x-doorway_x)<door_reach
	if near==door_open: return
	door_open=near
	if near: door.play("open")
	else: door.play_backwards("open")
	if not Engine.is_editor_hint() and has_node("/root/Audio"): get_node("/root/Audio").play("toggle")
