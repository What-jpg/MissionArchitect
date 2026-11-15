@tool
extends Node2D

# Edit Terrain's polygon with Godot's polygon handles. The same points feed physics.
@export var site_name := "Море Спокою"
@export var base_pad_width := 64.0
# Backdrop layers follow the camera at these fractions (1 = fixed to the screen).
@export var far_follow := 0.88
@export var mid_follow := 0.7
var backdrop_base := {}

func _ready() -> void:
	if has_node("Backdrop"):
		for layer in $Backdrop.get_children(): backdrop_base[layer.name]=layer.position

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or backdrop_base.is_empty() or not get_parent(): return
	# The world node is shifted by -camera; partially undo that for depth.
	var camera: Vector2=-get_parent().position
	$Backdrop/Far.position=(backdrop_base["Far"]+camera*far_follow).round()
	$Backdrop/Mid.position=(backdrop_base["Mid"]+camera*mid_follow).round()

func get_ground() -> PackedVector2Array:
	var polygon: PackedVector2Array = $Terrain.polygon
	var points: Array=Array(polygon.slice(0,polygon.size()-2))
	points.sort_custom(func(a,b): return a.x<b.x)
	return PackedVector2Array(points)

func set_geometry(points: PackedVector2Array, pad: Rect2) -> void:
	var polygon := points.duplicate()
	polygon.append(Vector2(points[-1].x,310))
	polygon.append(Vector2(points[0].x,310))
	$Terrain.polygon = polygon
	$TerrainBody/CollisionPolygon2D.polygon = polygon
	$LandingPad.position = pad.position
	$LandingPad/Strip.polygon = PackedVector2Array([Vector2.ZERO,Vector2(pad.size.x,0),Vector2(pad.size.x,4),Vector2(0,4)])
	$LandingPad/RightFlag.position.x=pad.size.x
	$LandingPad/Beacon.position.x=pad.size.x/2

func apply_lighting(polar: bool, strength: float = 0.45) -> void:
	# Shadow depth depends on difficulty: none / moderate / deep.
	if not polar or strength <= 0: return
	var ground := get_ground()
	for index in range(0,ground.size()-12,12):
		var origin: Vector2=ground[index]
		var shadow:=PackedVector2Array([origin,origin+Vector2(70,45),origin+Vector2(95,45)])
		for clipped in Geometry2D.intersect_polygons(shadow,$Terrain.polygon):
			var polygon:=Polygon2D.new()
			polygon.polygon=clipped
			polygon.color=Color(0.035,0.06,0.1,strength)
			$Shadows.add_child(polygon)
