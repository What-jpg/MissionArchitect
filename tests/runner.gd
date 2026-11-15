extends Node
const Sim=preload("res://scripts/sim.gd")
var failed:=0
var checked:=0
var game: Node
var capture:=false

func expect(value: bool, description: String) -> void:
	checked+=1
	if not value:
		failed+=1
		push_error("FAIL: "+description)

func _ready() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func screenshot(name: String) -> void:
	if not capture: return
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("res://build/qa/"+name+".png")

func run() -> void:
	var d:=Sim.default_design()
	var s:=Sim.stats(d)
	print("Default stats: ",s)
	expect(s.dv>9.5 and s.twr>1.2,"default vehicle can reach first orbit")
	var lighter:=d.duplicate(true)
	lighter.instruments=[]
	expect(Sim.stats(lighter).mass<s.mass,"payload adds mass")
	expect(Sim.stats(lighter).dv>s.dv,"payload reduces velocity budget")
	var empty:=d.duplicate(true)
	empty.fuel=0
	expect(not Sim.launch(Sim.stats(empty)).orbit,"empty tank fails ascent")
	var heavy:=d.duplicate(true)
	heavy.fuel=80
	expect(not Sim.launch(Sim.stats(heavy)).lift,"overweight vehicle does not lift")
	var low_power:=d.duplicate(true)
	low_power.panels=0
	low_power.batteries=0
	expect(Sim.stats(low_power).data_rate==0,"powerless instruments generate no science")
	var limits:=Sim.landing_limits(d)
	expect(Sim.touchdown(Vector2(0,1),0,limits,true)=="ideal","soft touchdown succeeds")
	expect(Sim.touchdown(Vector2(0,limits.vertical*1.2),0,limits,true)=="hard","hard touchdown preserves damaged lander")
	expect(Sim.touchdown(Vector2(0,20),0,limits,true)=="crash","high velocity crashes")
	expect(Sim.touchdown(Vector2(0,1),0,limits,false)=="rest","soft non-pad contact allows relaunch")
	expect(Sim.touchdown(Vector2(0,1),PI,limits,true)=="crash","inverted lander crashes")
	var rate:=100.0
	var total:=0.0
	seed(2048)
	for i in 20000:
		rate=Sim.next_rate(rate,randf_range(-10,10))
		expect(rate>=70 and rate<=130,"rate bounded")
		total+=rate
	expect(absf(total/20000-100)<2,"rate mean near 100")
	State.new_game(false)
	expect(State.import_code(State.export_code()),"design code round trip")
	expect(not State.import_code("garbage"),"malformed import rejected")
	var invalid:=d.duplicate(true)
	invalid.engine=400
	expect(not State.valid_design(invalid),"invalid part index rejected")
	invalid=d.duplicate(true)
	invalid.instruments=["camera","camera"]
	expect(not State.valid_design(invalid),"duplicate instruments rejected")
	await economy_checks()
	State.new_game(false)
	State.money=0
	State.science=0
	State.after_mission()
	expect(State.money>=float(Sim.balance().cheapest_rocket) and State.grant,"emergency grant restores first attempt before any satellite")
	State.save_game()
	State.money=0
	State.load_game()
	expect(State.money>=float(Sim.balance().cheapest_rocket),"progress JSON round trip")
	game=preload("res://scenes/Main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await screenshot("title")
	for screen in ["hub","map","constructor","lab","archive","guide","settings"]:
		game.show_page(screen)
		await get_tree().process_frame
		await screenshot(screen)
	expect(get_viewport().get_visible_rect().size==Vector2(1920,1080),"native rendering resolution is 1920x1080")
	var pixel_font=load("res://assets/fonts/MissionPixel.ttf")
	for letter in "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯабвгґдеєжзиіїйклмнопрстуфхцчшщьюя":
		expect(pixel_font.has_char(letter.unicode_at(0)),"pixel font contains "+letter)
	State.new_game(true)
	for mission_index in 4:
		game.select_mission(mission_index)
		var diagram=game.active_shell.get_node("MapDiagram")
		expect(diagram.get_node("EarthOrbitDots").visible==(mission_index==0),"Earth orbit dots are mission-specific")
		expect(diagram.get_node("Trajectory").visible==(mission_index>0),"Moon route is mission-specific")
		expect(game.active_shell.get_node("MoonCluster/Missions").get_child_count()==3,"three lunar sites share one cluster")
		var points: PackedVector2Array=diagram.get_node("Trajectory").points
		expect(points.size()==2,"Moon route is one straight segment")
		await screenshot("map_earth" if mission_index==0 else "map_moon_%d"%mission_index)
	State.mission=0
	# Editor-owned scenes and E-only interaction must stay usable after moving objects.
	for path in ["res://scenes/Hub.tscn","res://scenes/vehicles/Lander.tscn","res://scenes/screens/Constructor.tscn","res://scenes/screens/MissionMap.tscn","res://scenes/screens/NumberSlider.tscn"]:
		var packed=load(path)
		expect(packed is PackedScene,"editable scene loads: "+path)
	game.show_page("hub")
	expect(game.active_shell.find_children("*","Button",true,false).is_empty(),"hub HUD contains no menu buttons")
	var key_events:=InputMap.action_get_events("interact")
	expect(key_events.size()==1 and key_events[0] is InputEventKey and key_events[0].physical_keycode==KEY_E,"only E triggers hub interactions")
	for spec in [[Vector2(16,120),"archive"],[Vector2(86,120),"map"],[Vector2(140,166),"constructor"],[Vector2(88,166),"lab"],[Vector2(175,120),"launch_confirm"]]:
		game.show_page("hub")
		game.hub.get_node("Player").position=spec[0]
		game.hub.interact()
		expect(game.page==spec[1],"nearby station opens "+spec[1])
	game.show_page("hub")
	game.hub.get_node("Player").position=Vector2(240,120)
	game.hub.interact()
	expect(game.page=="hub","E away from objects opens nothing")
	expect(game.hub.find_station(game.hub.to_global(Vector2(88,120)))!=game.hub.get_node("Stations/Laboratory"),"laboratory cannot be used from upper floor")
	var station=game.hub.get_node("Stations/MissionConsole")
	var old_position: Vector2=station.position
	station.position.x=220
	expect(game.hub.find_station(game.hub.to_global(Vector2(220,120)))==station,"moving station in editor changes interaction position")
	station.position=old_position
	game.hub.get_node("Player").position=Vector2(40,120)
	Input.action_press("down")
	for step in 60: game.hub.tick(1.0/60.0)
	Input.action_release("down")
	expect(game.hub.get_node("Player").position.y==166,"stairs reach laboratory floor")
	Input.action_press("up")
	for step in 60: game.hub.tick(1.0/60.0)
	Input.action_release("up")
	expect(game.hub.get_node("Player").position.y==120,"stairs return to upper floor")
	game.show_page("constructor")
	for tab in 4:
		game.build_tab=tab
		game.constructor_ui_refresh()
		await get_tree().process_frame
	State.language="en"
	for screen in ["hub","map","constructor","lab","archive","guide"]:
		game.show_page(screen)
		await get_tree().process_frame
	State.language="uk"
	State.new_game(true)
	game.begin_mission()
	expect(game.phase_time==0 and Sim.launch(game.run.stats).lift,"default rocket lifts")
	expect(game.speed==4,"launch defaults to 4x actual pace")
	game.toggle_flight_speed()
	expect(game.speed==8 and game.active_shell.get_node("Speed").text=="×2","2x display selects 8x actual pace")
	game.run.failure_roll=0
	game.phase_time=8
	await get_tree().process_frame
	await screenshot("ascent")
	game.ascent_end()
	expect(game.page=="ascent_report","valid ascent reaches intermediate report")
	game.continue_after_ascent()
	expect(game.page=="orbit","Earth mission skips flight map and opens orbit insertion")
	expect(not game.get_node("FlightWorld").visible,"Earth mission never displays transfer map")
	game.show_page("flight")
	expect(game.page=="orbit","alternate Earth flight entry also skips transfer")
	game.set_process(false)
	game.phase_time=0
	game.speed=4
	game._process(0.125)
	var cursor_at_four: float=game.orbit_cursor
	game.phase_time=0
	game.speed=8
	game._process(0.125)
	expect(is_equal_approx(cursor_at_four,game.orbit_cursor),"insertion speed is independent of launch/transfer pace")
	game.set_process(true)
	game.orbit_cursor=0.5
	game.perform_burn()
	expect(State.unlocked==1 and State.science>0,"orbital mission awards result data and unlocks next mission")
	await screenshot("report")
	# Integration: physical landing on the far side of a scrolling world.
	State.mission=1
	game.begin_mission()
	game.run.fuel=1
	game.run.stats=Sim.stats(State.design,1)
	game.show_page("landing")
	await get_tree().physics_frame
	var vehicle=game.lander
	vehicle.position=Vector2(520,80)
	vehicle.velocity=Vector2.ZERO
	await get_tree().process_frame
	await screenshot("landing")
	vehicle.position=Vector2(520,132)
	vehicle.velocity=Vector2(0,0.5)
	for i in 120:
		await get_tree().physics_frame
		if game.page=="report": break
	expect(game.page=="report" and game.report.result=="ideal","swept polygon collision lands on pad after camera scroll")
	State.mission=1
	game.begin_mission()
	game.show_page("flight")
	game.phase_time=7
	await get_tree().process_frame
	await screenshot("transfer")
	var route:=PackedVector2Array([Vector2(0,0),Vector2(50,0),Vector2(50,30),Vector2(90,30)])
	expect(game.route_point(route,0)==route[0] and game.route_point(route,1)==route[-1],"transfer route reaches both endpoints")
	expect(game.route_point(route,0.5)==Vector2(50,10),"route interpolation remains correct")
	# Event cards for both outcomes run without errors.
	for kind in 3:
		for choice in 2:
			game.begin_mission()
			game.show_page("flight")
			game.event_index=kind
			game.open_event()
			game.resolve_event(kind,choice)
			await get_tree().process_frame
			# The outcome screen waits for "Continue"; pressing it resumes the flight.
			if game.event_open and game.page=="flight": game.close_event_result()
			expect(not game.event_open,"event resolved")
	# Touchdown classification on all three physical terrain variants.
	for level in [0,2]:
		State.new_game(true,level)
		for m in [1,2,3]:
			for outcome in ["ideal","hard","crash"]:
				State.mission=m
				game.begin_mission()
				game.run.fuel=1.0
				game.show_page("landing")
				await get_tree().physics_frame
				var craft=game.lander
				craft.position=Vector2(game.missions[m].pad_x,132)
				craft.velocity=Vector2(0,{"ideal":0.4,"hard":1.2,"crash":30.0}[outcome]*(1.0 if outcome=="crash" else craft.limits.vertical))
				for frame in 180:
					await get_tree().physics_frame
					if game.page=="report": break
				expect(game.page=="report" and game.report.result==outcome,"physical %s on lunar site %d, difficulty %d"%[outcome,m,level])
	State.new_game(true)
	# Non-pad soft contact, relaunch, pause and zero-fuel stranded state.
	for reserve in [1.0,0.0]:
		State.mission=1
		game.begin_mission()
		game.run.fuel=reserve
		game.show_page("landing")
		await get_tree().physics_frame
		var craft=game.lander
		craft.position.x=200
		craft.position.y=minf(craft.ground(190),craft.ground(210))-9.1
		craft.velocity=Vector2(0,0.5)
		for frame in 180:
			await get_tree().physics_frame
			if game.page=="report" or craft.resting: break
		if reserve==0:
			expect(game.page=="report" and game.report.result=="stranded","no fuel outside pad ends as stranded")
		else:
			expect(craft.resting and game.page=="landing","soft contact on sloped terrain survives")
			var before: float=craft.position.y
			Input.action_press("thrust")
			for frame in 25: await get_tree().physics_frame
			Input.action_release("thrust")
			expect(not craft.resting and craft.position.y<before-1,"lander relaunches from non-pad terrain")
			game.toggle_pause()
			var frozen: Vector2=craft.position
			for frame in 10: await get_tree().physics_frame
			expect(craft.position==frozen,"pause freezes landing physics")
			game.toggle_pause()
			game.finish_mission("crash")
	State.new_game(false)
	State.money=0
	State.science=0
	State.mission_pending={"mission":0,"design":"Interrupted","cost":3700}
	State.save_game()
	State.load_game()
	State.recover_interrupted()
	expect(State.mission_pending.is_empty() and State.science==0 and State.money>0,"interrupted mission without a satellite grants cash only")
	expect(State.reports[-1].logs[0].code=="interrupted","interrupted mission recorded in archive")
	State.new_game(true)
	State.mission=0
	game.begin_mission()
	var bank_before: float=State.science
	game._process(0.25)
	expect(State.science==bank_before,"data is not credited while a mission is in flight")
	game.run.sent=3.0
	game.finish_mission("crash")
	var first_data: float=game.report.data
	expect(first_data>0 and is_equal_approx(State.science,first_data),"failed satellite mission adds telemetry only at result")
	game.finish_mission("crash")
	expect(is_equal_approx(State.science,first_data),"duplicate completion cannot duplicate data")
	State.mission=1
	State.design.engine=1
	State.design.fuel=80
	State.design.panels=2
	State.design.legs=true
	State.design.altimeter=true
	game.begin_mission()
	game.finish_mission("ideal")
	var total_data: float=first_data+float(game.report.data)
	expect(is_equal_approx(State.science,total_data),"orbital and lunar results share one bank in sandbox")
	State.save_game()
	State.science=0
	State.load_game()
	expect(is_equal_approx(State.science,total_data),"shared bank persists across save and reload")
	State.tick(120)
	expect(is_equal_approx(State.science,total_data),"idle research complex never produces satellite income")
	game.show_page("settings")
	expect(game.active_shell.find_children("*","OptionButton",true,false).size()==1,"settings offer a difficulty selector")
	State.new_game(false)
	State.mission=0
	game.begin_mission()
	game.run.sent=2.0
	game.finish_mission("crash")
	expect(game.report.data>0 and is_equal_approx(State.science,game.report.data),"campaign failure credits only its own downlinked data")
	State.save_game()
	var payload=JSON.parse_string(FileAccess.get_file_as_string(State.SAVE_PATH))
	expect(payload.has("science") and payload.has("difficulty") and payload.has("satellite_level") and payload.has("campaign"),"profile stores difficulty, insurance level and campaign flag")
	# Version-one profile migration keeps earned data and ignores obsolete insurance/difficulty.
	var old_profile: Dictionary={"version":1,"science":42.5,"money":6500,"satellite":3,"difficulty":2,"sandbox":false,"mission":0,"design":Sim.default_design()}
	var saved:=FileAccess.open(State.SAVE_PATH,FileAccess.WRITE)
	saved.store_string(JSON.stringify(old_profile))
	saved.close()
	State.load_game()
	expect(State.science==42.5 and State.satellite_level==0,"legacy profile keeps science and starts without an insurance satellite")
	State.tick(60)
	expect(State.science==42.5,"satellite never creates passive data on a timer")
	# Seeded construction sampling: multiple viable launch/transfers for every mission.
	var viable: Array=[0,0,0,0]
	var young_viable: Array=[0,0,0,0]
	var minimal: Array=[1e9,1e9,1e9,1e9]
	for m in 4:
		for i in 3000:
			var sample:=Sim.default_design()
			sample.stages=1 if i%2==0 else 2
			sample.engine=randi_range(0,1)
			sample.engine2=2
			sample.fuel=randf_range(15,80)
			sample.fuel2=randf_range(5,40)
			sample.panels=randi_range(1,4)
			sample.antenna=randi_range(0,2)
			sample.legs=m>0
			if m==2: sample.instruments.append("spectrometer")
			if m==3: sample.instruments.append("ice")
			var stats:=Sim.stats(sample,m)
			if stats.twr>=1.2 and stats.dv>=game.missions[m].dv and Sim.remaining_fuel(sample,stats,game.missions[m].dv)>0.10:
				viable[m]+=1
				if sample.stages==1: young_viable[m]+=1
				minimal[m]=minf(minimal[m],stats.cost)
		expect(viable[m]>10,"multiple viable vehicles for mission %d"%m)
		expect(young_viable[m]>5,"single-stage vehicles can reach mission %d"%m)
	print("Viable in 3000 samples per mission: ",viable,"; minimum sampled cost: ",minimal)
	print("Single-stage viable: ",young_viable)
	await regression_checks()
	print("CHECKS: ",checked,"; FAILURES: ",failed)
	get_tree().quit(1 if failed else 0)


func economy_checks() -> void:
	var missions: Array=Sim.load_json("res://data/missions.json")
	var b: Dictionary=Sim.balance()
	# Insurance satellite: thresholds T and restore levels R, data instead of money.
	State.new_game(false)
	State.satellite_level=1
	State.money=0
	State.science=0
	var outcome:=State.after_mission()
	expect(is_equal_approx(State.science,float(b.satellite_net[0].restore)/100.0) and outcome.grant==0,"satellite 1 restores wealth to R1 with data")
	State.money=float(b.satellite_net[0].threshold)+1
	State.science=0
	expect(State.after_mission().satellite==0,"satellite stays silent above its threshold")
	expect(State.install_satellite(3) and State.satellite_level==3,"higher satellite replaces the active one")
	expect(not State.install_satellite(1) and State.satellite_level==3,"lower satellite does not downgrade insurance")
	State.money=0
	State.science=0
	State.after_mission()
	expect(not State.grant and is_equal_approx(State.science*100,float(b.satellite_net[2].restore)),"with a satellite no emergency grant is used")
	for level in 3:
		expect(float(b.satellite_net[level].restore)>=float(b.cheapest_rocket),"restore level %d covers the simplest rocket"%(level+1))
	# Start budget: only a simple rocket for mission 1 on the standard level.
	var simple:=Sim.stats(Sim.default_design(),0)
	expect(simple.cost<=float(Sim.difficulty(1).start_money),"standard budget buys the simple mission-1 rocket")
	expect(simple.cost*1.6>float(Sim.difficulty(1).start_money),"standard budget does not buy a heavy first rocket")
	expect(simple.cost<=float(b.cheapest_rocket),"grant level covers the default rocket")
	# Trade-off: a light rocket has the best efficiency, a heavy one hits the science ceiling.
	var light:=Sim.default_design()
	var heavy:=light.duplicate(true)
	heavy.instruments=["camera","seismometer","spectrometer","ice"]
	heavy.antenna=2
	heavy.panels=4
	heavy.batteries=2
	heavy.engine=1
	heavy.fuel=70
	var roi_light:=success_roi(light,0,missions[0])
	var roi_heavy:=success_roi(heavy,0,missions[0])
	expect(roi_light>roi_heavy and roi_light>0.5,"light satellite rocket is more efficient than a heavy one (%.2f vs %.2f)"%[roi_light,roi_heavy])
	# Pole: the ×1.6 multiplier needs the ice detector, and a richer set pays off there.
	var pole:=Sim.default_design()
	pole.stages=2
	pole.engine=1
	pole.engine2=1
	pole.fuel=50
	pole.fuel2=30
	pole.panels=3
	pole.antenna=1
	pole.legs=true
	pole.instruments=["camera"]
	var pole_ice:=pole.duplicate(true)
	pole_ice.instruments=["ice"]
	var pole_rich:=pole.duplicate(true)
	pole_rich.instruments=["ice","spectrometer","seismometer"]
	pole_rich.panels=5
	pole_rich.antenna=2
	var cam: Dictionary=Sim.science_potential(pole,Sim.stats(pole,3),missions[3],3,0)
	var ice: Dictionary=Sim.science_potential(pole_ice,Sim.stats(pole_ice,3),missions[3],3,0)
	expect(cam.multiplier==1.0 and is_equal_approx(ice.multiplier,1.6),"pole multiplier requires the ice detector")
	expect(success_profit(pole_rich,3,missions[3])>success_profit(pole_ice,3,missions[3]),"a richer instrument set earns more at the pole")
	# Priority follows design order (#9).
	var order_a:=Sim.default_design()
	order_a.panels=1
	order_a.batteries=0
	order_a.instruments=["ice","camera"]
	var order_b:=order_a.duplicate(true)
	order_b.instruments=["camera","ice"]
	expect(Sim.stats(order_a).active_ids!=Sim.stats(order_b).active_ids,"power priority follows instrument order")
	# Reserve score rewards a 5–15% margin over both a deficit and over-building.
	expect(Sim.band(0.1)>Sim.band(0.01) and Sim.band(0.1)>Sim.band(0.9),"reserve band rewards a reasonable margin")
	# Event score is normalised by events that actually happened (#18).
	var no_events:=Sim.score({"result":"ideal","data":500,"reference":100,"cost":1000,"reserve":10,"event_ok":0,"event_total":0,"young":false,"grant":false})
	expect(no_events.points>=90,"rank S is reachable without random events")

func success_roi(d: Dictionary, m: int, mission: Dictionary) -> float:
	var s:=Sim.stats(d,m)
	var sci:=Sim.science_potential(d,s,mission,m,0)
	return Sim.roi(Sim.mission_data(sci.potential,1.0,Sim.transfer_share(s,d.days,1.0,true),1.0),s.cost)

func success_profit(d: Dictionary, m: int, mission: Dictionary) -> float:
	var s:=Sim.stats(d,m)
	var sci:=Sim.science_potential(d,s,mission,m,0)
	return Sim.mission_data(sci.potential,1.0,Sim.transfer_share(s,d.days,1.0,true),1.0)*100-s.cost

func regression_checks() -> void:
	# #1: both Earth orbits enforce Δv; a ≤5% shortfall gives an unstable, narrower window.
	State.new_game(true)
	State.mission=0
	State.orbit=0
	var short:=Sim.default_design()
	for fuel in range(10,40):
		short.fuel=float(fuel)
		var probe: float=Sim.launch(Sim.stats(short,0)).dv
		if probe>=9.5*0.95 and probe<9.5: break
	State.design=short
	game.begin_mission()
	var dv: float=Sim.launch(game.run.stats).dv
	game.coast_end()
	expect(dv>=9.5*0.95 and dv<9.5 and game.page=="orbit" and game.run.unstable and game.orbit_window<=0.12,"small Δv shortfall gives an unstable orbit (Δv %.2f)"%dv)
	game.finish_mission("crash")
	short.fuel=float(short.fuel)-3
	State.design=short
	game.begin_mission()
	game.coast_end()
	expect(game.page=="report" and game.report.result=="crash","low orbit without the Δv requirement fails")
	game.show_page("hub")
	# #7: new game resets orbit.
	State.orbit=1
	State.new_game(false)
	expect(State.orbit==0 and State.satellite_level==0 and State.campaign,"new game resets orbit and insurance")
	# #8: orbit cursor starts outside the green zone.
	State.new_game(true)
	State.mission=0
	game.begin_mission()
	game.ascent_end()
	game.continue_after_ascent()
	game.set_process(false)
	game._process(0.002)
	expect(absf(game.orbit_cursor-0.5)>game.orbit_window,"insertion cursor does not start inside the window")
	game.set_process(true)
	game.finish_mission("crash")
	# #2: satellite level choice keeps real IDs when research is sparse.
	State.new_game(false)
	State.research=["sat_3"]
	State.mission=0
	# The satellite level is now picked on the mission map, next to the Earth-orbit brief.
	game.show_page("map")
	var picker: OptionButton=null
	for option in game.active_shell.find_children("*","OptionButton",true,false):
		if option.item_count==2 and (option.get_item_text(0).begins_with("Рівень") or option.get_item_text(0).begins_with("Level")): picker=option
	expect(picker!=null,"satellite picker lists researched levels")
	if picker: picker.item_selected.emit(1)
	expect(int(State.design.satellite)==3,"picking level 3 installs level 3, not 2")
	game.build_tab=0
	game.show_page("hub")
	# Sequential satellite research.
	State.research=[]
	State.science=100
	expect(not State.buy_research("sat_3") and State.buy_research("sat_2") and State.buy_research("sat_3"),"satellite research is sequential")
	# Young astronaut part limits; sandbox lifts them (#13).
	State.new_game(false,0)
	var two:=Sim.default_design()
	two.stages=2
	expect(not State.import_code(State.encode(two)),"young astronaut rejects a two-stage design")
	State.new_game(true,0)
	expect(State.import_code(State.encode(two)),"sandbox accepts every part")
	# #3/#4: corrupted saves are rejected, backup is used and stays valid.
	State.new_game(false)
	State.money=1234
	State.save_game()
	State.save_game()
	var broken:={"version":3,"money":10,"science":0,"mission":999,"design":{}}
	var f:=FileAccess.open(State.SAVE_PATH,FileAccess.WRITE)
	f.store_string(JSON.stringify(broken))
	f.close()
	State.load_game()
	expect(State.restored_from_backup and is_equal_approx(State.money,1234) and State.mission==0,"invalid save falls back to the backup")
	expect(State.sanitize(State.read_json(State.SAVE_PATH+".bak"))!=null,"backup remains valid after recovery")
	f=FileAccess.open(State.SAVE_PATH,FileAccess.WRITE)
	f.store_string("broken json")
	f.close()
	State.save_game()
	expect(State.sanitize(State.read_json(State.SAVE_PATH+".bak"))!=null,"a broken main file never overwrites the backup")
	# #15: changing language alone does not create a campaign.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(State.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(State.SAVE_PATH+".bak"))
	State.campaign=false
	game.show_page("title")
	expect(game.active_shell.get_node("Continue").disabled,"continue stays disabled without a campaign")
	# #6: flight HUD shows the paid cost once.
	State.new_game(false)
	var before: float=State.money
	game.begin_mission()
	expect(game.resources.text.contains(str(roundi(before-game.run.stats.cost))),"flight balance subtracts the rocket once")
	game.finish_mission("crash")
	# Records are separated by difficulty and orbit (#19).
	expect(game.record_key({"mission":0,"difficulty":2,"orbit":1})!=game.record_key({"mission":0,"difficulty":1,"orbit":1}),"records split by difficulty")
