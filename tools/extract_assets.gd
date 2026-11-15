extends SceneTree
# Deterministic sprite-import pipeline for the supplied labelled JPEG sheets.
# Crops use source pixels; target sizes are logical game pixels, never smoothed.
var sources: Dictionary = {}
var extracted := 0
func sprite(sheet: String, name: String, rect: Rect2i, size: Vector2i, transparent: bool = true) -> void:
	if not sources.has(sheet): sources[sheet] = Image.load_from_file(ProjectSettings.globalize_path("res://assets/source_sheets/"+sheet+".jpg"))
	var image: Image = sources[sheet].get_region(rect)
	image.convert(Image.FORMAT_RGBA8)
	size *= 3
	image.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
	if transparent:
		var pending: Array[Vector2i] = []
		for x in size.x:
			pending.append(Vector2i(x,0)); pending.append(Vector2i(x,size.y-1))
		for y in size.y:
			pending.append(Vector2i(0,y)); pending.append(Vector2i(size.x-1,y))
		var visited := {}
		while not pending.is_empty():
			var pos: Vector2i = pending.pop_back()
			if pos.x<0 or pos.y<0 or pos.x>=size.x or pos.y>=size.y or visited.has(pos): continue
			visited[pos] = true
			var c := image.get_pixelv(pos)
			if maxf(c.r,maxf(c.g,c.b))>0.25: continue
			image.set_pixelv(pos,Color(0,0,0,0))
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]: pending.append(pos+step)
	# Reduce JPEG colour noise without interpolating the pixel grid.
	for y in size.y:
		for x in size.x:
			var c := image.get_pixel(x,y)
			if c.a>0:
				image.set_pixel(x,y,Color(roundf(c.r*31)/31,roundf(c.g*31)/31,roundf(c.b*31)/31,1))
	if name.begins_with("button_"):
		# Remove baked English sample labels; Godot draws the localized text.
		var fill := Color("495563") if name!="button_hover" else Color("456950")
		image.fill_rect(Rect2i(6,6,size.x-12,size.y-12),fill)
	image.save_png("res://assets/art/"+name+".png")
	extracted += 1

func _initialize() -> void:
	sprite("vehicles","character_idle",Rect2i(89,177,142,245),Vector2i(16,24))
	for i in 3:
		sprite("vehicles","character_walk_%d"%i,Rect2i(276+i*180,183,138,239),Vector2i(16,24))
	for i in 2:
		sprite("vehicles","character_climb_%d"%i,Rect2i(108+i*182,497,137,268),Vector2i(16,24))
	sprite("vehicles","rocket",Rect2i(1039,177,190,641),Vector2i(16,48))
	sprite("vehicles","stage_1",Rect2i(1557,176,190,260),Vector2i(16,24))
	sprite("vehicles","stage_2",Rect2i(1350,178,128,183),Vector2i(12,16))
	sprite("vehicles","lander",Rect2i(1932,176,148,157),Vector2i(16,16))
	sprite("vehicles","lander_legs",Rect2i(2164,175,313,244),Vector2i(24,20))
	sprite("vehicles","rocket_exhaust",Rect2i(1335,551,145,265),Vector2i(12,24))
	sprite("vehicles","lander_exhaust",Rect2i(1965,648,76,129),Vector2i(6,12))
	sprite("vehicles","landing_dust",Rect2i(2162,553,319,226),Vector2i(32,16))
	sprite("vehicles","flag",Rect2i(1590,1040,74,108),Vector2i(8,16))
	sprite("vehicles","beacon",Rect2i(2188,1042,73,65),Vector2i(8,8))
	sprite("vehicles","landing_strip",Rect2i(1968,1041,139,35),Vector2i(16,4),false)
	for i in 4:
		sprite("vehicles","moon_tile_%d"%i,Rect2i(70+i*190,963,174,174),Vector2i(16,16),false)
	sprite("world","hub_far",Rect2i(76,172,854,252),Vector2i(320,96),false)
	sprite("world","hub_mid",Rect2i(987,173,852,250),Vector2i(320,96))
	sprite("world","mission_console",Rect2i(80,572,337,247),Vector2i(32,24))
	sprite("world","archive_shelf",Rect2i(499,559,179,265),Vector2i(24,32))
	sprite("world","workshop",Rect2i(994,575,316,248),Vector2i(32,24))
	sprite("world","laboratory",Rect2i(1385,562,484,261),Vector2i(48,26))
	sprite("world","ground_antenna",Rect2i(1544,967,301,381),Vector2i(32,40))
	sprite("world","launch_tower",Rect2i(80,962,338,391),Vector2i(40,48))
	sprite("world","metal_tile",Rect2i(834,963,173,173),Vector2i(16,16),false)
	sprite("world","earth",Rect2i(1927,178,241,241),Vector2i(64,64))
	sprite("world","moon",Rect2i(2273,192,203,214),Vector2i(64,64))
	sprite("world","atmosphere",Rect2i(1970,547,515,276),Vector2i(160,80),false)
	for i in 3:
		sprite("world","satellite_%d"%(i+1),Rect2i(1964+i*175,961,164,141),Vector2i(24,20))
	var xs := [88,199,311,438,540,651]
	var names := ["mass","energy","budget","data","signal","time"]
	for i in 6: sprite("interface","icon_"+names[i],Rect2i(xs[i],185,80,80),Vector2i(8,8))
	for i in 4: sprite("interface","button_"+["normal","hover","pressed","disabled"][i],Rect2i(1521+i*246,169,208,62),Vector2i(32,12),false)
	sprite("interface","logo",Rect2i(2146,1002,332,341),Vector2i(64,64))
	print("Extracted ",extracted," sprites from the supplied sheets.")
	quit()
