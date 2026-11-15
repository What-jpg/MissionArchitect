extends Node2D
class_name RocketAssembly
# Draws the player's rocket from the workshop design, standing on y = 0 (nozzle down):
# first stage stretched by its propellant load, optional upper stage, payload fairing on top.
# Same proportions as the workshop preview, in world pixels (art at 1/3 scale).

const ROCKET := preload("res://assets/art/rocket.png")
const STAGE_1 := preload("res://assets/art/stage_1.png")
const STAGE_2 := preload("res://assets/art/stage_2.png")
const ART_SCALE := 1.0 / 3.0

var height := 0.0

func build(design: Dictionary) -> void:
	for child in get_children(): child.free()
	var top := 0.0
	var first: float = lerpf(0.7, 1.25, float(design.get("fuel", 30.0)) / 80.0)
	top = add_piece(STAGE_1, Rect2(0, 0, 48, 72), first, top)
	if int(design.get("stages", 1)) == 2:
		var second: float = lerpf(0.75, 1.2, float(design.get("fuel2", 12.0)) / 40.0)
		top = add_piece(STAGE_2, Rect2(0, 0, 36, 48), second, top)
	top = add_piece(ROCKET, Rect2(0, 0, 48, 44), 1.0, top)
	height = -top

func add_piece(texture: Texture2D, region: Rect2, stretch: float, top: float) -> float:
	var piece := Sprite2D.new()
	piece.texture = texture
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.region_enabled = true
	piece.region_rect = region
	piece.centered = false
	# Whole-pixel heights so the stacked pieces never leave a seam.
	var piece_height: float = roundf(region.size.y * ART_SCALE * stretch)
	piece.scale = Vector2(ART_SCALE, piece_height / region.size.y)
	piece.position = Vector2(-region.size.x * ART_SCALE / 2.0, top - piece_height).round()
	add_child(piece)
	return top - piece_height
