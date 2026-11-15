class_name LunarLander
extends Node2D

signal finished(result: String, velocity: Vector2, angle: float)
const Sim = preload("res://scripts/sim.gd")
var velocity := Vector2(5,0)
var fuel := 0.0
var angle := 0.0
var terrain := PackedVector2Array()
var pad := Rect2()
var limits := {}
var mass := 1.0
var dry_mass := 1.0
var force := 7.0
var isp := 350.0
var thrust := 22.0
var auto_stabilize := true
var legs := false
var resting := false
var active := true
var burning := false
var elapsed := 0.0
var camera_x := 0.0
var camera_y := 0.0
var terrain_body: StaticBody2D
var owns_terrain := true
var collision: CollisionPolygon2D
var footprint := PackedVector2Array([Vector2(-7,-7),Vector2(7,-7),Vector2(10,8),Vector2(-10,8)])

func configure(d: Dictionary, stats: Dictionary, mission: Dictionary, remaining: float, level: Node2D = null, settings: Dictionary = {}, difficulty_level: int = 0) -> void:
	if settings.is_empty(): settings = Sim.difficulty(difficulty_level)
	fuel = maxf(0,remaining)
	# Lander mass includes the remaining propellant: a light lander responds faster.
	dry_mass = stats.lander_mass
	force = stats.landing_thrust*0.012
	isp = stats.landing_isp
	update_mass()
	limits = Sim.landing_limits(d, difficulty_level)
	legs = d.legs
	position = Vector2(330,70)
	auto_stabilize=bool(settings.auto_stabilize)
	var pad_factor: float=float(settings.pad_factor)
	var width: float = mission.pad_width*pad_factor
	pad = Rect2(mission.pad_x-width/2,142,width,2)
	if level!=null:
		terrain=level.get_ground()
		position=level.get_node("Spawn").position
		width=level.base_pad_width*pad_factor
		pad=Rect2(level.get_node("LandingPad").position.x+level.base_pad_width/2-width/2,level.get_node("LandingPad").position.y,width,2)
		for i in terrain.size():
			if absf(terrain[i].x-pad.get_center().x)<width/2+8: terrain[i].y=pad.position.y
		level.set_geometry(terrain,pad)
		terrain_body=level.get_node("TerrainBody")
		collision=level.get_node("TerrainBody/CollisionPolygon2D")
		owns_terrain=false
	else:
		for x in range(0,961,8): terrain.append(Vector2(x,142))
		terrain_body=StaticBody2D.new()
		collision=CollisionPolygon2D.new()
		var polygon:=terrain.duplicate()
		polygon.append(Vector2(960,310))
		polygon.append(Vector2(0,310))
		collision.polygon=polygon
		terrain_body.add_child(collision)
		get_parent().add_child(terrain_body)
	$Visuals/Body.visible=not legs
	$Visuals/Legs.visible=legs

func update_mass() -> void:
	mass = dry_mass + fuel
	thrust = clampf(force/mass,1.6,18)

func _exit_tree() -> void:
	if owns_terrain and is_instance_valid(terrain_body): terrain_body.queue_free()

func ground(x: float) -> float:
	var low := 0
	var high := terrain.size()-1
	while high-low>1:
		var mid := (low+high)/2
		if terrain[mid].x<=x: low=mid
		else: high=mid
	var a := terrain[low]
	var b := terrain[high]
	return lerpf(a.y,b.y,clampf((x-a.x)/maxf(0.001,b.x-a.x),0,1))

func _physics_process(delta: float) -> void:
	if not active or get_tree().paused: return
	elapsed += delta
	var steering := Input.get_axis("left","right")
	angle = wrapf(angle+steering*1.75*delta,-PI,PI)
	if auto_stabilize and absf(steering)<0.1:
		angle = move_toward(angle,0,delta*0.8)
	burning = Input.is_action_pressed("thrust") and fuel>0
	if resting and not burning:
		queue_redraw()
		return
	if burning:
		resting = false
		velocity += Vector2(sin(angle),-cos(angle))*thrust*delta
		# Propellant flow follows the engine Isp (game-scaled): the vacuum engine burns slower.
		fuel = maxf(0,fuel-(thrust*mass/1700.0)*(350.0/isp)*delta)
		update_mass()
	velocity.y += 1.62*delta
	var motion := velocity*5.0*delta
	# Substeps plus convex-shape queries prevent tunnelling and account for all four hull corners.
	var steps := maxi(1,ceili(motion.length()/2))
	for i in steps:
		var next := position+motion/steps
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := ConvexPolygonShape2D.new()
		shape.points = footprint
		query.shape = shape
		query.transform = get_parent().global_transform * Transform2D(angle,next)
		query.collision_mask = 1
		query.margin = 0.2
		var hit := get_world_2d().direct_space_state.intersect_shape(query,1)
		if not hit.is_empty():
			var on_pad: bool = position.x-10>=pad.position.x and position.x+10<=pad.end.x and absf(ground(position.x)-pad.position.y)<1
			var result := Sim.touchdown(velocity,angle,limits,on_pad)
			if result=="rest":
				velocity = Vector2.ZERO
				angle = 0
				position.y = minf(ground(position.x-10),ground(position.x+10))-9
				resting = true
				if fuel<=0:
					active=false
					finished.emit("stranded",Vector2.ZERO,angle)
			else:
				active=false
				finished.emit(result,velocity,angle)
			break
		position = next
	if position.x<terrain[0].x+12 or position.x>terrain[-1].x-12 or position.y>300:
		active=false
		finished.emit("crash",velocity,angle)
	if position.y < -150: velocity.y = maxf(velocity.y,0)
	queue_redraw()

func _draw() -> void:
	$Visuals.rotation=angle
	$Visuals/Exhaust.visible=burning
	# Dust is kicked up only while the engine fires close to the surface.
	var dust: AnimatedSprite2D=$Dust
	var height: float=ground(position.x)-position.y
	dust.visible=burning and active and height<30
	if dust.visible:
		dust.position=Vector2(0,height)
		dust.modulate.a=clampf(1.3-height/30.0,0,1)
		if not dust.is_playing():
			dust.sprite_frames.set_animation_loop("landing_dust",true)
			dust.play("landing_dust")
