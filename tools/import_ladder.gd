extends SceneTree
func _initialize() -> void:
	var source:=Image.load_from_file(ProjectSettings.globalize_path("res://assets/source_sheets/ladder.jpg"))
	var image:=source.get_region(Rect2i(1200,184,345,1180))
	image.convert(Image.FORMAT_RGBA8)
	image.resize(48,168,Image.INTERPOLATE_NEAREST)
	# The checkerboard is baked into this JPEG; key its dark blue background,
	# including the enclosed spaces between the ladder's rungs.
	for y in image.get_height():
		for x in image.get_width():
			var color:=image.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b))<0.24:
				image.set_pixel(x,y,Color.TRANSPARENT)
			else:
				image.set_pixel(x,y,Color(roundf(color.r*31)/31,roundf(color.g*31)/31,roundf(color.b*31)/31,1))
	image.save_png("res://assets/art/ladder.png")
	print("Imported supplied ladder as a transparent 48x168 sprite")
	quit()
