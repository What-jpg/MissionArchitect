extends Node2D

const Sim = preload("res://scripts/sim.gd")
const CalcFormulas = preload("res://scripts/calc_formulas.gd")
const LANDER_SCENE = preload("res://scenes/vehicles/Lander.tscn")
const LEVEL_SCENES = [preload("res://scenes/world/Tranquility.tscn"),preload("res://scenes/world/Highlands.tscn"),preload("res://scenes/world/SouthPole.tscn")]
const SCREEN_NAMES = {"map":"MissionMap","lab":"Laboratory","archive":"Archive","guide":"Guide","report":"Report","settings":"Settings","ascent_report":"AscentReport","launch_confirm":"LaunchConfirm"}
const FONT = preload("res://assets/fonts/ui_font.tres")
const UI_SCALE := 6.0
const BG = Color("101a2b")
const INK = Color("e0e7e8")
const MUTED = Color("8d9cae")
const GOLD = Color("e5b85b")
const CYAN = Color("35b6e8")
var missions: Array
var parts: Dictionary
var reasons: Dictionary
var page := "title"
var ui: CanvasLayer
var root_ui: Control
var body: VBoxContainer
var live: Label
var resources: Label
var world: Node2D
var lander: LunarLander
var active_shell: Control
var landing_level: Node2D
@onready var hub: Node2D = $Hub
var elapsed := 0.0
var phase_time := 0.0
var run := {}
var logbook: Array = []
var event_index := 0
var current_event := 0
var event_open := false
var orbit_cursor := 0.0
var orbit_window := 0.12
var paused := false
var speed := 4.0
var settings_sandbox := false
var settings_difficulty := 1
var message := ""
var report: Dictionary = {}
var build_tab := 0
# Last constructor readings, so every change shows its ripple effect on all six resources.
var resource_prev: Array = []
var resource_delta: Array = []
var keep_scroll := -1
var boosting := false
# Ascent boost from tapping Space quickly; drains when the player stops.
var launch_boost := 0.0
# Big on-screen action prompt (keys + short words) and its optional progress bar.
var prompt_node: Control
var prompt_bar: ProgressBar
var landing_prompt_time := 0.0
var hub_prompt_station := ""
# Formula calculator state: chosen formula, its field values and the page to return to.
var calc_index := 0
var calc_values: Dictionary = {}
var calc_back := "constructor"
# Guided first mission (Young astronaut only): highlight frame + callout card.
var coach_host: Control
var coach_frame: Panel
var coach_card: Control
var coach_targets: Array = []
var tut_sub := 0
var launch_button: Button
var report_back_button: Button
const TUT_TOTAL := 7
# "How to calculate" boxes in the workshop: [Label, Callable(stats) -> String], refreshed live.
var calc_boxes: Array = []
const PART_ICONS := {"stages":"part_01_rocket_stage","engine":"part_02_rocket_engine_nozzle","fuel":"part_03_fuel_tank","panels":"part_04_solar_panel","batteries":"part_05_battery","antenna0":"part_06_small_antenna","antenna1":"part_06_small_antenna","antenna2":"part_07_large_dish_antenna","radar":"part_08_radar","camera":"part_09_camera","spectrometer":"part_10_spectrometer","seismometer":"part_11_seismometer","ice":"part_12_ice_detector_drill_with_frost_crystal","legs":"part_13_landing_legs","altimeter":"part_14_radar_altimeter","satellite":"part_15_small_satellite","quality":"part_16_interstage_ring"}
const RESEARCH_ICONS := {"part_spectrometer":1,"part_ice":2,"mission_1":3,"mission_2":4,"mission_3":5,"sat_2":6,"sat_3":7}
var report_sort := "points"

func t(uk: String,en: String) -> String:
	return uk if State.language=="uk" else en

func localized(value: Array) -> String:
	return str(value[0 if State.language=="uk" else 1])

func _ready() -> void:
	missions=Sim.load_json("res://data/missions.json")
	parts=Sim.load_json("res://data/parts.json")
	reasons=Sim.load_json("res://data/reasons.json")
	world=$World
	ui=$ScreenHost
	hub.interaction_requested.connect(func(action_id):
		if action_id=="launch": confirm_launch()
		elif action_id=="comms": show_page("comms")
		else: show_page(action_id))
	var theme: Theme = preload("res://assets/interface_theme.tres")
	root_ui=Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.theme=theme
	root_ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	show_page("title")

func wipe_ui() -> void:
	for node in root_ui.get_children():
		root_ui.remove_child(node)
		node.queue_free()
	live=null
	resources=null
	body=null
	active_shell=null
	coach_host=null
	coach_targets=[]

func label_at(text: String, x: float,y: float,width: float=300,size: int=8,color: Color=INK) -> Label:
	var label := Label.new()
	label.text=text
	label.position=Vector2(x,y)*UI_SCALE
	label.size.x=width*UI_SCALE
	label.add_theme_font_size_override("font_size",maxi(24,size*3))
	label.add_theme_color_override("font_color",color)
	root_ui.add_child(label)
	return label

func button_at(text: String, x: float,y: float,width: float,callback: Callable) -> Button:
	var button := Button.new()
	button.text=text
	root_ui.add_child(button)
	button.position=Vector2(x,y)*UI_SCALE
	button.size=Vector2(width,15)*UI_SCALE
	button.pressed.connect(callback)
	return button

func line(text: String,color: Color=INK) -> Label:
	var label: Label=preload("res://scenes/screens/BodyLabel.tscn").instantiate()
	label.text=text
	label.add_theme_color_override("font_color",color)
	body.add_child(label)
	return label

func action(text: String, callback: Callable, disabled: bool=false) -> Button:
	var button: Button=preload("res://scenes/screens/BodyButton.tscn").instantiate()
	button.text=text
	button.disabled=disabled
	button.pressed.connect(callback)
	body.add_child(button)
	return button

func mount_shell(name: String) -> Control:
	active_shell = load("res://scenes/screens/"+name+".tscn").instantiate()
	root_ui.add_child(active_shell)
	return active_shell

func panel(title: String,back: String="hub") -> void:
	var scene_name: String = "Event" if event_open else str(SCREEN_NAMES.get(page,"Panel"))
	mount_shell(scene_name)
	var heading: Label=active_shell.get_node("Title")
	heading.text = title.to_upper() if event_open or scene_name=="Panel" else (active_shell.title_uk if State.language=="uk" else active_shell.title_en).to_upper()
	var back_button: Button=active_shell.get_node("Back")
	back_button.text=t("Назад","Back")
	back_button.pressed.connect(func(): show_page(back))
	body=active_shell.get_node("Scroll/Body")
	active_shell.get_node("Footer").text="MISSION ARCHITECT   /   "+t("ОФЛАЙН","OFFLINE")
	if not message.is_empty(): line(message,GOLD)

func show_page(next: String) -> void:
	if next=="flight" and State.mission==0:
		coast_end()
		return
	page=next
	$Hub.visible=page=="hub"
	$LaunchWorld.visible=page=="launch"
	$FlightWorld.visible=page=="flight"
	$OrbitWorld.visible=page=="orbit"
	message=""
	wipe_ui()
	if page!="landing" and is_instance_valid(lander):
		lander.queue_free()
		lander=null
	if page!="landing" and is_instance_valid(landing_level):
		landing_level.queue_free()
		landing_level=null
	world.position=Vector2.ZERO
	match page:
		"title": title_ui()
		"hub": hub_ui()
		"map": State.tutorial.map=true; map_ui()
		"constructor": State.tutorial.workshop=true; resource_prev=[]; resource_delta=[]; constructor_ui()
		"lab": State.tutorial.lab=false; lab_ui()
		"archive": archive_ui()
		"guide": guide_ui()
		"launch": phase_time=0; speed=4.0; flight_ui()
		"ascent_report": ascent_report_ui()
		"flight": phase_time=0; speed=4.0; event_index=0; flight_ui()
		"orbit": phase_time=0; orbit_ui()
		"landing": landing_ui()
		"report": report_ui()
		"settings": settings_ui()
		"comms": comms_ui()
		"sound": sound_ui()
		"calculator": calculator_ui()
	apply_tutorial()
	var music_for: String="music_flight" if page in ["launch","flight","orbit","ascent_report"] else ("music_landing" if page=="landing" else "music_base")
	Audio.music(music_for)
	# Soft fade between screens.
	if page!="landing" and is_inside_tree():
		root_ui.modulate.a=0.0
		create_tween().tween_property(root_ui,"modulate:a",1.0,0.18)
	queue_redraw()

func title_ui() -> void:
	mount_shell("Title")
	active_shell.get_node("Subtitle").text=t("СПРОЄКТУЙ. ЗАПУСТИ. ДОСЛІДИ.","DESIGN. LAUNCH. DISCOVER.")
	var resume: Button=active_shell.get_node("Continue")
	resume.text=t("Продовжити","Continue")
	resume.disabled=not State.campaign
	resume.pressed.connect(func(): show_page("hub"))
	var fresh: Button=active_shell.get_node("NewGame")
	fresh.text=t("Нова експедиція","New expedition")
	fresh.pressed.connect(func(): show_page("settings"))
	active_shell.get_node("Language").pressed.connect(func(): State.language="en" if State.language=="uk" else "uk"; State.save_game(); show_page("title"))
	var language_button: Button=active_shell.get_node("Language")
	language_button.size.x=250
	var sound_button:=Button.new()
	sound_button.text=t("Звук","Sound")
	sound_button.position=Vector2(397,906)
	sound_button.size=Vector2(250,90)
	sound_button.pressed.connect(func(): show_page("sound"))
	active_shell.add_child(sound_button)
	var exit_button:=Button.new()
	exit_button.text=t("Вийти","Quit")
	exit_button.position=Vector2(674,906)
	exit_button.size=Vector2(250,90)
	exit_button.pressed.connect(func(): State.save_game(); get_tree().quit())
	active_shell.add_child(exit_button)

func calculator_allowed() -> bool:
	# Young astronauts and engineers may use it; mission directors calculate on their own.
	return State.difficulty<=1

func open_calculator(back: String) -> void:
	calc_back=back
	show_page("calculator")

func calc_formula_list() -> Array:
	return CalcFormulas.list(t,parts,missions,Sim.stats(State.design,State.mission),State.design,State.mission,State.orbit)

func calculator_ui() -> void:
	panel(t("Калькулятор формул","Formula calculator"),calc_back)
	if not calculator_allowed():
		line(t("На рівні «Директор місії» розрахунки робиш сам.","At the Mission director level you do the maths yourself."),GOLD)
		return
	if State.difficulty==0: line(t("Калькулятор — необов’язковий помічник: гру можна пройти й без нього.","The calculator is an optional helper: you can finish the game without it."),MUTED)
	var formulas: Array=calc_formula_list()
	calc_index=clampi(calc_index,0,formulas.size()-1)
	var formula: Dictionary=formulas[calc_index]
	# 1. Pick the formula
	var titles: Array=formulas.map(func(f): return f.title)
	choose(t("1. Формула","1. Formula"),titles,calc_index,func(i): calc_index=i; calc_values={}; show_page("calculator"))
	var explain:=Label.new()
	explain.text=formula.formula
	explain.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	explain.add_theme_color_override("font_color",Color("c9d3dc"))
	body.add_child(explain)
	# 2. Fill the fields (defaults come from the current rocket)
	line(t("2. Підстав дані","2. Fill in the data"),CYAN)
	for field in formula.fields:
		if not calc_values.has(field.id): calc_values[field.id]=field.default
	var result_label:=Label.new()
	var hint_label:=Label.new()
	var recompute:=func():
		var r: Dictionary=formula.compute.call(calc_values)
		result_label.text="= "+str(r.text)
		hint_label.text=str(r.hint)
	for field in formula.fields: calc_field(field,recompute)
	# 3. Result
	line(t("3. Результат","3. Result"),CYAN)
	result_label.add_theme_font_size_override("font_size",34)
	result_label.add_theme_color_override("font_color",GOLD)
	result_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result_label)
	hint_label.add_theme_color_override("font_color",MUTED)
	hint_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	recompute.call()
	action(t("Взяти числа з моєї ракети","Use numbers from my rocket"),func(): calc_values={}; show_page("calculator"))
	var save_row:=HBoxContainer.new()
	save_row.add_theme_constant_override("separation",16)
	var name_edit:=LineEdit.new()
	name_edit.placeholder_text=t("Назва розрахунку (необов’язково)","Calculation name (optional)")
	name_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	name_edit.max_length=40
	save_row.add_child(name_edit)
	var save_button:=Button.new()
	save_button.text=t("Зберегти розрахунок","Save calculation")
	save_button.pressed.connect(func():
		var r: Dictionary=formula.compute.call(calc_values)
		var title: String=name_edit.text.strip_edges()
		State.calculations.append({"formula":formula.id,"title":title if not title.is_empty() else formula.title,"values":calc_values.duplicate(true),"text":str(r.text)})
		if State.calculations.size()>50: State.calculations.pop_front()
		State.save_game()
		show_page("calculator"))
	save_row.add_child(save_button)
	body.add_child(save_row)
	# Saved results: open again or delete
	line(t("Збережені розрахунки","Saved calculations"),CYAN)
	if State.calculations.is_empty(): line(t("Поки порожньо.","Empty for now."),MUTED)
	for i in range(State.calculations.size()-1,-1,-1):
		var index:=i
		var saved: Dictionary=State.calculations[i]
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		var text:=Label.new()
		text.text="%s:  %s"%[saved.title,saved.text]
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size",22)
		row.add_child(text)
		var open_button:=Button.new()
		open_button.text=t("Відкрити","Open")
		open_button.pressed.connect(func():
			var ids: Array=formulas.map(func(f): return f.id)
			calc_index=maxi(0,ids.find(State.calculations[index].formula))
			calc_values=State.calculations[index].values.duplicate(true)
			show_page("calculator"))
		row.add_child(open_button)
		var delete_button:=Button.new()
		delete_button.text=t("Видалити","Delete")
		delete_button.pressed.connect(func():
			State.calculations.remove_at(index)
			State.save_game()
			show_page("calculator"))
		row.add_child(delete_button)
		body.add_child(row)

func calc_field(field: Dictionary, recompute: Callable) -> void:
	# One input row: parts come from lists, numbers from a spin box, instruments from check boxes.
	var id: String=field.id
	match field.type:
		"engine","antenna","quality","mission":
			var items: Array=[]
			match field.type:
				"engine": for e in parts.engines: items.append("%s • %d %s • Isp %d"%[localized(e.name),int(e.thrust),t("кН","kN"),int(e.isp)])
				"antenna": for a in parts.antennas: items.append("%s • %d %s"%[localized(a.name),int(a.rate),t("МБ/добу","MB/day")])
				"quality": for q in parts.quality: items.append("%s • %.3f"%[localized(q.name),float(q.reliability)])
				"mission": for mi in missions: items.append(localized(mi.name))
			choose(field.label,items,int(calc_values[id]),func(i): calc_values[id]=i; recompute.call(),{"engine":"engine","antenna":"antenna1","quality":"quality","mission":""}[field.type])
		"number":
			var row:=HBoxContainer.new()
			var label:=Label.new()
			label.text=field.label
			label.custom_minimum_size=Vector2(340,0)
			row.add_child(label)
			var spin:=SpinBox.new()
			spin.min_value=field.min
			spin.max_value=field.max
			spin.step=field.step
			spin.value=float(calc_values[id])
			spin.custom_minimum_size=Vector2(260,52)
			spin.value_changed.connect(func(v): calc_values[id]=v; recompute.call())
			row.add_child(spin)
			body.add_child(row)
		"instruments":
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",14)
			var label:=Label.new()
			label.text=field.label
			label.custom_minimum_size=Vector2(340,0)
			row.add_child(label)
			for item in parts.instruments:
				var item_id: String=item.id
				var box:=CheckBox.new()
				box.text=localized(item.name)
				box.button_pressed=item_id in calc_values[id]
				box.toggled.connect(func(on):
					var chosen: Array=calc_values[id].duplicate()
					if on and item_id not in chosen: chosen.append(item_id)
					elif not on: chosen.erase(item_id)
					calc_values[id]=chosen
					recompute.call())
				row.add_child(box)
			body.add_child(row)

func sound_controls(parent: Container) -> void:
	# Music and effects volume sliders plus a "mute everything" switch; changes apply and save instantly.
	var make_row:=func(title: String, value: float, setter: Callable) -> HSlider:
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",20)
		var name_label:=Label.new()
		name_label.text=title
		name_label.custom_minimum_size=Vector2(200,0)
		row.add_child(name_label)
		var slider_control:=HSlider.new()
		slider_control.min_value=0
		slider_control.max_value=100
		slider_control.step=5
		slider_control.value=roundf(value*100)
		slider_control.custom_minimum_size=Vector2(260,44)
		slider_control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		slider_control.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(slider_control)
		var amount:=Label.new()
		amount.custom_minimum_size=Vector2(90,0)
		amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		amount.text="%d%%"%int(slider_control.value)
		row.add_child(amount)
		slider_control.value_changed.connect(func(v):
			amount.text="%d%%"%int(v)
			setter.call(v/100.0))
		parent.add_child(row)
		return slider_control
	make_row.call(t("Музика","Music"),Audio.music_volume,Audio.set_music_volume)
	make_row.call(t("Звуки","Effects"),Audio.sfx_volume,func(v): Audio.set_sfx_volume(v); Audio.play("click"))
	var mute:=CheckBox.new()
	mute.text=t("Вимкнути весь звук","Mute all sound")
	mute.button_pressed=Audio.muted
	mute.toggled.connect(func(on): Audio.set_muted(on))
	# Keep the box in step with the M shortcut; drop the link when the screen closes.
	var sync:=func():
		mute.set_pressed_no_signal(Audio.muted)
	Audio.settings_changed.connect(sync)
	mute.tree_exiting.connect(func():
		Audio.settings_changed.disconnect(sync))
	parent.add_child(mute)

func sound_ui() -> void:
	panel(t("Звук","Sound"),"title")
	line(t("Пересунь повзунок на 0, щоб вимкнути музику або звуки окремо.","Move a slider to 0 to switch music or effects off on their own."),MUTED)
	sound_controls(body)
	line(t("Швидко: клавіша M вимикає й вмикає весь звук будь-де в грі.","Shortcut: the M key toggles all sound anywhere in the game."),MUTED)

func settings_ui() -> void:
	panel(t("Нова експедиція","New expedition"),"title")
	line(t("Початок нової гри замінить поточний прогрес.","Starting a new game replaces current progress."))
	line(t("Звичайна гра — спільний баланс усіх місій.","Campaign — one shared balance for all missions."),MUTED)
	var levels:=[]
	for level in Sim.balance().difficulty: levels.append(localized(level.name))
	choose(t("Складність","Difficulty"),levels,settings_difficulty,func(i): settings_difficulty=i; show_page("settings"))
	var diff: Dictionary=Sim.difficulty(settings_difficulty)
	line([t("Бюджет щедрий • події вимкнені • автостабілізація • 2–3 деталі в категорії, один ступінь","Generous budget • no random events • auto-stabilisation • 2–3 parts per category, one stage"),t("Бюджет стандартний • події рідко • стандартні допуски посадки","Standard budget • occasional events • standard landing tolerances"),t("Бюджет жорсткий • події часто • вузькі допуски й глибокі тіні","Tight budget • frequent events • narrow tolerances and deep shadows")][settings_difficulty],MUTED)
	line(t("Стартовий бюджет: %.0f млн $","Starting budget: %.0f $M")%float(diff.start_money),MUTED)
	check(t("Пісочниця • усі місії й деталі","Sandbox • all missions and parts"),settings_sandbox,func(v): settings_sandbox=v)
	action(t("Почати експедицію","Start expedition"),func(): State.new_game(settings_sandbox,settings_difficulty); show_page("hub"))

func hub_ui() -> void:
	mount_shell("HubHUD")
	live=active_shell.get_node("Status")
	active_shell.get_node("Controls").text=t("A/D: рух   W/S: драбина   E: взаємодія   M: звук   Esc: меню","A/D: move   W/S: ladder   E: interact   M: sound   Esc: menu")
	active_shell.get_node("Title").text=t("НАУКОВИЙ КОМПЛЕКС","RESEARCH COMPLEX")
	var room_names: Array=[t("АРХІВ","ARCHIVE"),t("ЦЕНТР КЕРУВАННЯ","MISSION CONTROL"),t("ЗВ’ЯЗОК","COMMUNICATIONS"),t("СТАРТ","LAUNCH PAD"),t("ЛАБОРАТОРІЯ","LABORATORY"),t("МАЙСТЕРНЯ","WORKSHOP")]
	for i in room_names.size(): active_shell.get_node("RoomLabels").get_child(i).text=room_names[i]
	var hint:=Label.new()
	hint.name="NextStep"
	hint.position=Vector2(860,30)
	hint.size=Vector2(1012,80)
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",24)
	hint.add_theme_color_override("font_color",Color("f2c94c"))
	active_shell.add_child(hint)
	hub.get_node("Stations/LaunchPad/Assembly").build(State.design)
	var step: Array=next_step()
	hint.text=step[1]
	hint.visible=not tutorial_on()
	hub.hint_target=step[0]
	hub.tick(0)
	active_shell.get_node("Interaction").text=hub.prompt()
	active_shell.get_node("Interaction").visible=false
	hub_prompt_station="-"
	update_hub_prompt()

func update_hub_prompt() -> void:
	# Show "[E] OPEN: <station>" only while standing next to something usable.
	var station_name: String=hub.nearby.name if is_instance_valid(hub.nearby) else ""
	if station_name==hub_prompt_station: return
	hub_prompt_station=station_name
	if station_name.is_empty():
		hide_prompt()
		return
	show_prompt([[["E"],t("ВІДКРИТИ: ","OPEN: ")+hub.nearby.display_name().to_upper()]],190,"",false,false)

func tutorial_on() -> bool:
	return State.difficulty==0 and not State.sandbox and not bool(State.tutorial.get("done",false))

func tut_step() -> int:
	return int(State.tutorial.get("guide",0))

func set_tut_step(n: int) -> void:
	if tut_step()>=n: return
	State.tutorial.guide=n
	if n==2: tut_sub=0
	State.save_game()

func finish_tutorial() -> void:
	State.tutorial.done=true
	State.save_game()
	clear_coach()

func clear_coach() -> void:
	if is_instance_valid(coach_host): coach_host.queue_free()
	coach_host=null
	coach_targets=[]

func coach(targets: Array, step: int, title: String, text: String, next_text: String="", on_next: Callable=Callable(), corner: bool=false) -> void:
	# Pulsing gold frame around the targets and a card that says what to do and why.
	clear_coach()
	coach_targets=targets.filter(func(c): return c is Control and is_instance_valid(c))
	var host:=Control.new()
	host.name="Coach"
	host.mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame:=Panel.new()
	var frame_style:=StyleBoxFlat.new()
	frame_style.draw_center=false
	frame_style.set_border_width_all(4)
	frame_style.border_color=Color("f2c94c")
	frame_style.set_corner_radius_all(8)
	frame_style.shadow_color=Color(0.95,0.79,0.3,0.35)
	frame_style.shadow_size=10
	frame.add_theme_stylebox_override("panel",frame_style)
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame.visible=not coach_targets.is_empty()
	host.add_child(frame)
	var pulse:=frame.create_tween().set_loops()
	pulse.tween_property(frame,"modulate:a",0.45,0.55)
	pulse.tween_property(frame,"modulate:a",1.0,0.55)
	var card:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.04,0.07,0.12,0.95)
	style.border_color=Color("f2c94c")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left=26; style.content_margin_right=26; style.content_margin_top=16; style.content_margin_bottom=18
	card.add_theme_stylebox_override("panel",style)
	card.custom_minimum_size=Vector2(640,0)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	var head:=HBoxContainer.new()
	var badge:=Label.new()
	badge.text=t("НАВЧАННЯ • КРОК %d З %d","TUTORIAL • STEP %d OF %d")%[step,TUT_TOTAL]
	badge.add_theme_font_size_override("font_size",20)
	badge.add_theme_color_override("font_color",CYAN)
	badge.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(badge)
	var skip:=Button.new()
	skip.text=t("Пропустити навчання","Skip tutorial")
	skip.add_theme_font_size_override("font_size",18)
	skip.pressed.connect(finish_tutorial)
	head.add_child(skip)
	column.add_child(head)
	var title_label:=Label.new()
	title_label.text=title
	title_label.add_theme_font_size_override("font_size",32)
	title_label.add_theme_color_override("font_color",GOLD)
	title_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x=588
	column.add_child(title_label)
	var text_label:=Label.new()
	text_label.text=text
	text_label.add_theme_font_size_override("font_size",22)
	text_label.add_theme_color_override("font_color",Color("e6eef2"))
	text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x=588
	column.add_child(text_label)
	if not next_text.is_empty():
		var next:=Button.new()
		next.text=next_text+"  →"
		next.size_flags_horizontal=Control.SIZE_SHRINK_END
		next.pressed.connect(on_next)
		column.add_child(next)
	card.add_child(column)
	host.add_child(card)
	root_ui.add_child(host)
	coach_host=host
	coach_frame=frame
	coach_card=card
	card.set_meta("corner",corner)
	card.modulate.a=0.0
	card.create_tween().tween_property(card,"modulate:a",1.0,0.25)
	# Bring a target that sits inside a scroll list into view.
	for target in coach_targets:
		var parent: Node=target.get_parent()
		while parent and not parent is ScrollContainer: parent=parent.get_parent()
		if parent: parent.call_deferred("ensure_control_visible",target)
	update_coach()

func update_coach() -> void:
	if not is_instance_valid(coach_host): return
	var rect:=Rect2()
	var first:=true
	for target in coach_targets:
		if not is_instance_valid(target) or not target.is_visible_in_tree(): continue
		var r: Rect2=target.get_global_rect()
		rect=r if first else rect.merge(r)
		first=false
	coach_frame.visible=not first
	if not first:
		coach_frame.position=rect.position-Vector2(10,10)
		coach_frame.size=rect.size+Vector2(20,20)
	var card_size: Vector2=coach_card.get_combined_minimum_size()
	if first or coach_card.get_meta("corner",false):
		coach_card.position=Vector2(1920-card_size.x-40,1080-card_size.y-90)
		return
	var x: float=clampf(rect.position.x,40,1880-card_size.x)
	var y: float=rect.end.y+28
	if y+card_size.y>1060: y=rect.position.y-28-card_size.y
	if y<20: y=clampf(rect.end.y+28,20,1060-card_size.y)
	coach_card.position=Vector2(x,y).round()

func find_row(prefix: String) -> Control:
	# A workshop row whose title starts with the given text.
	if not is_instance_valid(body): return null
	for child in body.find_children("*","Label",true,false):
		if child.text.begins_with(prefix): return child.get_parent()
	return null

func apply_tutorial() -> void:
	clear_coach()
	if not tutorial_on(): return
	var s:=tut_step()
	match page:
		"hub":
			var texts: Array
			if s<=0: texts=[1,t("Іди до ЦЕНТРУ КЕРУВАННЯ","Go to MISSION CONTROL"),t("Іди клавішами A/D до комп’ютерів нагорі й натисни E. Там обирають, куди летить ракета.","Walk with A/D to the computers upstairs and press E. That is where you choose where the rocket flies.")]
			elif s<=2: texts=[3,t("Спускайся в МАЙСТЕРНЮ","Go down to the WORKSHOP"),t("Біля драбини натисни S, підійди до верстата й натисни E. Там збирають ракету.","At the ladder press S, walk to the workbench and press E. That is where rockets are built.")]
			elif s<=4: texts=[5,t("Час летіти! Іди до СТАРТУ","Time to fly! Go to the LAUNCH PAD"),t("Вийди надвір через двері праворуч, підійди до ракети й натисни E.","Go outside through the door on the right, walk to the rocket and press E.")]
			else: texts=[7,t("Іди в ЛАБОРАТОРІЮ","Go to the LABORATORY"),t("Ти привіз дані! У лабораторії їх можна продати за гроші або відкрити нові місії.","You brought back data! In the laboratory you can sell it for money or unlock new missions.")]
			coach([],texts[0],texts[1],texts[2],"",Callable(),true)
		"map":
			set_tut_step(1)
			if State.mission!=0:
				coach([active_shell.get_node("EarthMission")],2,t("Обери «Орбіту Землі»","Choose “Earth orbit”"),t("Це найлегша місія: вивести супутник навколо Землі. Місяць відкриється пізніше.","It is the easiest mission: put a satellite around Earth. The Moon unlocks later."))
			else:
				coach([active_shell.get_node("EarthMission"),active_shell.get_node("OrbitOptions")],2,t("Ціль обрано!","Target chosen!"),t("Низька орбіта — найдешевша: треба лише 9,5 км/с. Супутник рівня 1 — легкий і дешевий, для першого разу саме те. Тепер натисни «Хаб» і йди в майстерню.","Low orbit is the cheapest: only 9.5 km/s needed. A level 1 satellite is light and cheap, perfect for a first try. Now press “Hub” and go to the workshop."),t("Зрозуміло","Got it"),func(): coach([active_shell.get_node("Back")],2,t("Повертайся в хаб","Back to the hub"),t("Натисни «Хаб», потім спускайся в майстерню.","Press “Hub”, then go down to the workshop.")))
		"constructor":
			set_tut_step(2)
			if s<=2: workshop_coach()
		"launch_confirm":
			if is_instance_valid(launch_button):
				coach([launch_button],6,t("Запускай!","Launch!"),t("Тут видно, скільки коштує ракета і що вона готова. Гроші знімаються тільки зараз. Після старту швидко натискай Пробіл, щоб розігнатися, а на орбіті натисни Пробіл, коли риска в зеленому.","Here you see the price and that the rocket is ready. Money is spent only now. After liftoff tap Space quickly to speed up; in orbit press Space when the marker is in the green."),"",Callable(),true)
		"report":
			if is_instance_valid(report_back_button):
				var ok: bool=report.get("result","") in ["ideal","hard"]
				if ok: coach([report_back_button],7,t("Перша місія виконана!","First mission complete!"),t("Ти отримав %.1f МБ даних. Повертайся в хаб і йди в лабораторію — там дані перетворюються на гроші та нові місії.","You earned %.1f MB of data. Return to the hub and go to the laboratory: data turns into money and new missions there.")%float(report.get("data",0)),"",Callable(),true)
				else: coach([report_back_button],6,t("Не вийшло — це нормально","It didn’t work, and that’s fine"),t("Прочитай «Що змінити наступного разу» вгорі звіту, виправ ракету в майстерні й спробуй ще раз.","Read “What to change next time” above, fix the rocket in the workshop and try again."),"",Callable(),true)
		"lab":
			var research_button: Button=null
			for child in body.find_children("*","Button",true,false):
				if child.text.find(localized(missions[1].name))>=0: research_button=child
			var sell: Button=null
			for child in body.find_children("*","Button",true,false):
				if child.text==t("Продати половину","Sell half"): sell=child
			if research_button and not research_button.disabled:
				coach([research_button],7,t("Порада: відкрий Місяць","Tip: unlock the Moon"),t("Найкраще вкладення зараз — «Місія: Море Спокою». Решту даних продай: на гроші купиш потужніший двигун і більше палива для польоту на Місяць.","The best buy now is “Mission: Sea of Tranquility”. Sell the rest: the money buys a stronger engine and more fuel for the Moon."),t("Завершити навчання","Finish tutorial"),finish_tutorial)
			elif sell and not sell.disabled:
				coach([sell],7,t("Продай частину даних","Sell some data"),t("Дані можна продати за гроші. Курс змінюється кожні 10 секунд: якщо стрілка ↑ — курс росте. Збережи 12 МБ, щоб відкрити Місяць.","Data can be sold for money. The rate changes every 10 seconds: an ↑ arrow means it is rising. Keep 12 MB to unlock the Moon."),t("Завершити навчання","Finish tutorial"),finish_tutorial)
			else:
				coach([],7,t("Навчання завершено!","Tutorial complete!"),t("Далі вирішуєш сам. Підказки «Як порахувати» в майстерні та гайд в архіві завжди поруч.","From here it is your call. The workshop’s “How to check” notes and the guide in the archive are always there."),t("Завершити","Finish"),finish_tutorial)

func workshop_coach() -> void:
	var next:=func(n: int, tab: int):
		tut_sub=n
		if build_tab!=tab:
			build_tab=tab
			constructor_ui_refresh()
		else: workshop_coach()
	if (tut_sub in [1,2] and build_tab!=0) or (tut_sub==3 and build_tab!=2):
		next.call(tut_sub,0 if tut_sub<3 else 2)
		return
	var cards: Array=active_shell.get_node("ResourceCards").get_children()
	match tut_sub:
		0: coach(cards,4,t("Це приладова панель ракети","This is your rocket’s dashboard"),t("Маса, енергія, ціна, дані, зв’язок і час. Після кожної зміни під карткою з’являється, що стало краще (зелене) чи гірше (червоне).","Mass, power, cost, data, link and time. After every change, each card shows what got better (green) or worse (red)."),t("Далі","Next"),func(): next.call(1,0))
		1: coach([find_row(t("Двигун 1","Engine 1"))],4,t("Двигун — щоб злетіти","The engine lifts you"),t("«Базовий» має тягу 600 кН, а ракета важить ~31 т: 600 ÷ (31 × 9,81) ≈ 2. Це більше 1 — ракета злетить. Для орбіти його досить, не переплачуй.","“Basic” gives 600 kN and the rocket weighs ~31 t: 600 ÷ (31 × 9.81) ≈ 2. That is above 1, so it lifts off. Enough for orbit, no need to pay more."),t("Далі","Next"),func(): next.call(2,0))
		2: coach([find_row(t("Паливо 1","Fuel 1"))],4,t("Паливо — щоб долетіти","Fuel gets you there"),t("30 т палива дають ~11 км/с, а орбіта потребує 9,5 — є запас. Більше палива — дорожче й важче, менше — не долетиш. Залиш 30.","30 t of fuel gives ~11 km/s and orbit needs 9.5: a safe margin. More fuel costs more and weighs more, less won’t get you there. Keep 30."),t("Далі","Next"),func(): next.call(3,2))
		3: coach([find_row(t("Камера","Camera"))],4,t("Камера — для науки","The camera does the science"),t("Місія спостерігає Землю, тож потрібна камера: без неї буде лише 30% науки. Вона вже стоїть ✓. Інші прилади відкриваються в лабораторії.","This mission watches Earth, so it needs the camera: without it you get only 30% of the science. It is already on ✓. Other instruments unlock in the laboratory."),t("Далі","Next"),func(): next.call(4,2))
		4: coach([active_shell.get_node("PreviewPanel")],4,t("Перевір готовність","Check readiness"),t("Тут твоя ракета і список перевірки. Зелена галочка — усе гаразд, червоний хрестик підкаже, що виправити.","Here is your rocket and its checklist. A green tick means all good; a red cross tells you what to fix."),t("Далі","Next"),func(): next.call(5,build_tab))
		_:
			set_tut_step(3)
			coach([active_shell.get_node("Back")],5,t("Ракета готова!","The rocket is ready!"),t("Натисни «Хаб» і йди надвір до СТАРТУ.","Press “Hub” and go outside to the LAUNCH PAD."))

func next_step() -> Array:
	# Gentle coaching: which station to visit next and why, in plain words.
	if State.tutorial.lab and State.science>0.05:
		return ["Laboratory",t("У тебе є дані! Спустись у ЛАБОРАТОРІЮ (S біля драбини) — продай їх або відкрий новий прилад.","You have data! Go down to the LABORATORY (S at the ladder) to sell it or unlock a new instrument.")]
	if not State.tutorial.map:
		return ["MissionConsole",t("Крок 1: підійди до ЦЕНТРУ КЕРУВАННЯ й натисни E — обери, куди летіти.","Step 1: walk to MISSION CONTROL and press E to choose where to fly.")]
	if not State.tutorial.workshop:
		return ["Workshop",t("Крок 2: спустись драбиною (S) у МАЙСТЕРНЮ й натисни E — збери ракету.","Step 2: climb down the ladder (S) to the WORKSHOP and press E to build your rocket.")]
	return ["LaunchPad",t("Крок 3: вийди надвір до СТАРТУ й натисни E — поїхали!","Step 3: go outside to the LAUNCH PAD and press E. Liftoff!")]

func calc_box(title: String, builder: Callable) -> void:
	# A framed "how to calculate" note: formula in plain words + this rocket's numbers + the target.
	var frame:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.07,0.12,0.19,1)
	style.border_width_left=4
	style.border_color=Color(0.95,0.79,0.3,0.8)
	style.content_margin_left=18
	style.content_margin_right=14
	style.content_margin_top=10
	style.content_margin_bottom=10
	frame.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	var head:=Label.new()
	head.text=title
	head.add_theme_font_size_override("font_size",22)
	head.add_theme_color_override("font_color",GOLD)
	column.add_child(head)
	var text:=Label.new()
	text.add_theme_font_size_override("font_size",22)
	text.add_theme_color_override("font_color",Color("c9d3dc"))
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	frame.add_child(column)
	body.add_child(frame)
	calc_boxes.append([text,builder])

func refresh_calc_boxes(stats: Dictionary) -> void:
	for entry in calc_boxes:
		if is_instance_valid(entry[0]): entry[0].text=entry[1].call(stats)

func part_shown(key: String) -> bool:
	# Young astronauts meet the workshop step by step; other levels see every part at once.
	if State.sandbox or State.difficulty!=0: return true
	match key:
		"batteries","days","radar": return State.unlocked>=1
		"quality": return State.unlocked>=1 and (State.mission>=1 or State.unlocked>=2)
	return true

func fuel_effect(key: String, amount: float) -> Dictionary:
	# What adding propellant does to this rocket: velocity budget gained and thrust-to-weight lost.
	var before:=Sim.stats(State.design,State.mission)
	var trial:=State.design.duplicate(true)
	trial[key]=float(trial[key])+amount
	var after:=Sim.stats(trial,State.mission)
	return {"dv":Sim.launch(after).dv-Sim.launch(before).dv,"twr0":before.twr,"twr1":after.twr}

func stage_numbers(s: Dictionary) -> Dictionary:
	# Same masses the simulation uses, so the player's own Tsiolkovsky sums match the game.
	var d: Dictionary=State.design
	var e: Dictionary=parts.engines[int(d.engine)]
	var out:={"isp1":float(e.isp),"thrust":float(e.thrust),"mass":s.mass}
	var upper:=0.0
	if int(d.stages)==2:
		var e2: Dictionary=parts.engines[int(d.engine2)]
		var upper_dry: float=s.dry+e2.mass+float(d.fuel2)*parts.tank_fraction
		upper=upper_dry+float(d.fuel2)
		out.isp2=float(e2.isp)
		out.m0_2=upper
		out.mf_2=upper_dry
	out.m0_1=s.mass
	out.mf_1=s.mass-float(d.fuel)
	return out

func need_text() -> String:
	var req: float=Sim.required_dv(missions[State.mission],State.mission,State.orbit)
	if State.mission==0: return t("Треба для цієї орбіти: %.1f км/с, краще на 5–15%% більше.","This orbit needs %.1f km/s, ideally 5–15%% more.")%req
	return t("Треба до Місяця: %.1f км/с. Усе, що понад це, лишиться паливом для посадки.","The Moon needs %.1f km/s. Anything above that becomes landing fuel.")%req

func design_checks(s: Dictionary) -> Array:
	# Plain-language readiness list: [level, text]; level 2 = will fail, 1 = risky, 0 = fine.
	var out: Array=[]
	var mission: Dictionary=missions[State.mission]
	# Engineers and directors work it out themselves: no verdicts outside the Young astronaut level.
	if State.difficulty>=1: return out
	if not State.sandbox and s.cost>State.money:
		out.append([2,t("Не вистачає грошей: %d млн $","Not enough money: %d $M")%roundi(s.cost-State.money)])
	var required: float=Sim.required_dv(mission,State.mission,State.orbit)
	var launch: Dictionary=Sim.launch(s)
	if not launch.lift:
		out.append([2,t("Не злетить: заважка для двигуна","Won't lift off: too heavy for the engine")])
	elif s.twr<1.2:
		out.append([1,t("Ледь злітає: двигун слабкий","Barely lifts: weak engine")])
	if launch.lift and launch.dv<required:
		out.append([2,t("Замало палива, щоб долетіти","Not enough fuel to get there")])
	elif launch.lift and State.mission>0 and Sim.remaining_fuel(State.design,s,required)<0.15:
		out.append([1,t("Мало палива на посадку","Little fuel left for landing")])
	if s.active_count<s.instrument_count:
		out.append([1,t("Бракує енергії: додай панелі","Not enough power: add panels")])
	if s.instrument_count==0:
		out.append([2,t("Немає жодного приладу — не буде даних","No instruments: no data")])
	if State.mission>=2 and str(mission.required) not in s.active_ids:
		var item_name:="?"
		for item in parts.instruments:
			if item.id==mission.required: item_name=localized(item.name)
		out.append([1,t("Для бонусу ×%.1f візьми: %s","For the ×%.1f bonus take: %s")%[float(mission.multiplier),item_name]])
	if State.mission>0 and not State.design.legs:
		out.append([1,t("Без опор сісти важче","Landing is harder without legs")])
	if out.is_empty(): out.append([0,t("Усе готово до запуску!","Ready for launch!")])
	return out

func map_ui() -> void:
	mount_shell("MissionMap")
	active_shell.get_node("Title").text=t("КАРТА МІСІЙ","MISSION MAP")
	active_shell.get_node("Eyebrow").text=t("01 / ОБЕРІТЬ НАПРЯМОК ДОСЛІДЖЕННЯ","01 / SELECT A RESEARCH DESTINATION")
	active_shell.get_node("Back").text=t("Хаб","Hub")
	active_shell.get_node("Back").pressed.connect(func(): show_page("hub"))
	var diagram: Control=active_shell.get_node("MapDiagram")
	diagram.lunar=State.mission>0
	diagram.get_node("EarthLabel").text=t("ЗЕМЛЯ / СТАРТ","EARTH / LAUNCH")
	diagram.get_node("MoonLabel").text=t("МІСЯЦЬ","MOON")
	var earth: Button=active_shell.get_node("EarthMission")
	earth.text=("●  " if State.mission==0 else "○  ")+localized(missions[0].name).to_upper()
	earth.pressed.connect(func(): select_mission(0))
	earth.icon=preload("res://assets/art/screens/mission_thumb_earth.png")
	earth.expand_icon=true
	earth.add_theme_constant_override("icon_max_width",110)
	var orbit: OptionButton=active_shell.get_node("OrbitOptions")
	orbit.clear()
	for item in Sim.balance().orbits: orbit.add_item(localized(item.name))
	orbit.selected=State.orbit
	orbit.disabled=State.mission!=0
	orbit.item_selected.connect(func(value): State.orbit=value; State.save_game())
	active_shell.get_node("MoonCluster/Title").text=t("МІСЯЦЬ","MOON")
	active_shell.get_node("MoonCluster/Subtitle").text=t("ТРИ ТОЧКИ ПОСАДКИ","THREE LANDING SITES")
	var site_descriptions: Array=[t("Рівнина / хороше освітлення","Plain / good lighting"),t("Нагір’я / спектрометр","Highlands / spectrometer"),t("Край кратера / детектор льоду","Crater rim / ice detector")]
	for i in range(1,4):
		var index:=i
		var button: Button=active_shell.get_node("MoonCluster/Missions").get_child(i-1)
		button.disabled=not State.available(i)
		button.text=("●  " if State.mission==i else "○  ")+localized(missions[i].name)+"\n"+site_descriptions[i-1]
		if button.disabled: button.text+="\n"+localized(State.lock_reason(i))
		button.icon=load("res://assets/art/screens/mission_thumb_%s.png"%["tranquility","highlands","pole"][i-1])
		button.expand_icon=true
		button.add_theme_font_size_override("font_size",22)
		button.add_theme_constant_override("icon_max_width",150)
		button.clip_text=true
		button.pressed.connect(func(): select_mission(index))
	active_shell.get_node("SelectedTitle").text=localized(missions[State.mission].name).to_upper()
	active_shell.get_node("Brief").text=localized(missions[State.mission].brief)
	# The map footer would collide with the satellite note; the title already names the screen.
	if active_shell.has_node("Footer"): active_shell.get_node("Footer").visible=State.mission!=0
	if State.mission==0: satellite_picker()

func satellite_picker() -> void:
	# The Earth-orbit payload is part of the mission plan: pick the satellite level here.
	var box:=VBoxContainer.new()
	box.position=Vector2(96,904)
	box.size=Vector2(980,0)
	box.add_theme_constant_override("separation",8)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	var icon:=icon_rect(part_icon("satellite"),48)
	row.add_child(icon)
	var title:=Label.new()
	title.text=t("Супутник","Satellite")
	title.custom_minimum_size=Vector2(170,0)
	title.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var levels: Array=[1]
	for level in [2,3]:
		if State.satellite_researched(level): levels.append(level)
	var option:=OptionButton.new()
	option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	option.custom_minimum_size=Vector2(0,58)
	for level in levels:
		option.add_item(t("Рівень %d • %.2f т • %d млн $ • наука ×%.2f","Level %d • %.2f t • %d $M • science ×%.2f")%[level,parts.satellite_mass[level-1],parts.satellite_cost[level-1],float(Sim.balance().satellite_science[level-1])])
	option.selected=maxi(0,levels.find(int(State.design.satellite)))
	option.item_selected.connect(func(i):
		State.design.satellite=levels[i]
		State.save_game())
	row.add_child(option)
	box.add_child(row)
	var note:=Label.new()
	note.text=t("Кращий супутник дає більше науки й надійнішу страховку, але він важчий і дорожчий. Рівні 2 і 3 відкриваються в лабораторії.","A better satellite gives more science and a stronger insurance net, but it is heavier and pricier. Levels 2 and 3 unlock in the laboratory.")
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size=Vector2(980,0)
	note.add_theme_font_size_override("font_size",22)
	note.add_theme_color_override("font_color",MUTED)
	box.add_child(note)
	active_shell.add_child(box)

func select_mission(index: int) -> void:
	if not State.available(index): return
	State.mission=index
	State.save_game()
	show_page("map")

func part_icon(key: String) -> Texture2D:
	if not PART_ICONS.has(key): return null
	return load("res://assets/art/part_icons/%s.png"%PART_ICONS[key])

func icon_rect(texture: Texture2D, size: float=44) -> TextureRect:
	var rect:=TextureRect.new()
	rect.texture=texture
	rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size=Vector2(size,size)
	rect.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return rect

func add_row_icon(row: Control, icon: String) -> void:
	var texture:=part_icon(icon)
	if texture==null: return
	var rect:=icon_rect(texture)
	row.add_child(rect)
	row.move_child(rect,0)
	var title:=row.get_node_or_null("Title")
	if title: title.custom_minimum_size.x=290

func choose(title: String, items: Array, selected: int, callback: Callable, icon: String="") -> void:
	var row: HBoxContainer=preload("res://scenes/screens/PartSelect.tscn").instantiate()
	body.add_child(row)
	add_row_icon(row,icon)
	row.get_node("Title").text=title
	var option: OptionButton=row.get_node("Options")
	option.clear()
	for item in items: option.add_item(str(item))
	option.selected=selected
	option.item_selected.connect(callback)

func slider(title: String,key: String,low: float,high: float,step: float=1.0,icon: String="") -> void:
	var row: HBoxContainer=preload("res://scenes/screens/NumberSlider.tscn").instantiate()
	body.add_child(row)
	add_row_icon(row,icon if not icon.is_empty() else key)
	var label: Label=row.get_node("Title")
	var shown: Callable=func(v): return "%s: %s"%[title,("%.0f"%v) if step>=1.0 else ("%.1f"%v)]
	label.text=shown.call(float(State.design[key]))
	var control: HSlider=row.get_node("Slider")
	control.min_value=low
	control.max_value=high
	control.step=step
	control.value=State.design[key]
	control.value_changed.connect(func(value): State.design[key]=value; label.text=shown.call(value); update_resources())
	control.drag_ended.connect(func(_changed): State.save_game())

func check(title: String,value: bool,callback: Callable,icon: String="") -> void:
	var box: CheckBox=preload("res://scenes/screens/InstrumentToggle.tscn").instantiate()
	box.text=title
	box.button_pressed=value
	box.toggled.connect(callback)
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var texture:=part_icon(icon)
	if texture==null:
		body.add_child(box)
		return
	var row:=HBoxContainer.new()
	row.add_child(icon_rect(texture))
	row.add_child(box)
	body.add_child(row)

func set_part(key: String,value) -> void:
	State.design[key]=value
	State.save_game()
	constructor_ui_refresh(true)

func constructor_ui_refresh(keep_position: bool=false) -> void:
	keep_scroll=-1
	if keep_position and is_instance_valid(active_shell) and active_shell.has_node("Scroll"):
		keep_scroll=active_shell.get_node("Scroll").scroll_vertical
	wipe_ui()
	constructor_ui()
	apply_tutorial()
	if keep_scroll>=0:
		var scroll: ScrollContainer=active_shell.get_node("Scroll")
		var target:=keep_scroll
		# Layout must settle before the old position can be restored.
		await get_tree().process_frame
		if is_instance_valid(scroll): scroll.scroll_vertical=target

func constructor_ui() -> void:
	mount_shell("Constructor")
	active_shell.get_node("Title").text=(active_shell.title_uk if State.language=="uk" else active_shell.title_en).to_upper()
	active_shell.get_node("Back").text=t("Хаб","Hub")
	active_shell.get_node("Back").pressed.connect(func(): State.save_game(); show_page("hub"))
	if calculator_allowed():
		var calc_button:=Button.new()
		calc_button.text=t("Калькулятор","Calculator")
		calc_button.position=Vector2(1380,48)
		calc_button.size=Vector2(270,64)
		calc_button.pressed.connect(func(): State.save_game(); open_calculator("constructor"))
		active_shell.add_child(calc_button)
	resources=active_shell.get_node("Resources")
	update_resources()
	var tabs := [t("Носій","Rocket"),t("Системи","Systems"),t("Наука","Science"),t("Файл","Design")]
	for i in 4:
		var index:=i
		var tab: Button=active_shell.get_node("Tabs").get_child(i)
		tab.text=tabs[i]
		tab.toggle_mode=true
		tab.button_pressed=build_tab==i
		tab.pressed.connect(func(): build_tab=index; constructor_ui_refresh())
		if build_tab==i:
			tab.add_theme_color_override("font_pressed_color",GOLD)
			tab.add_theme_color_override("font_hover_pressed_color",GOLD)
	body=active_shell.get_node("Scroll/Body")
	calc_boxes=[]
	var d: Dictionary=State.design
	match build_tab:
		0:
			if State.limited():
				line(t("Ступені: 1 (рівень «Юний астронавт»)","Stages: 1 (Young astronaut level)"),MUTED)
			else:
				choose(t("Ступені","Stages"),["1","2"],int(d.stages)-1,func(i): set_part("stages",i+1),"stages")
			engine_picker("engine",t("Двигун 1","Engine 1"))
			slider(t("Паливо 1, т","Fuel 1, t"),"fuel",0,80)
			line(t("Більше палива — більший запас швидкості, але важча ракета: потрібна сильніша тяга.","More propellant adds velocity budget but makes the rocket heavier: it needs more thrust."),MUTED)
			calc_box(t("Що дає паливо?","What does fuel give?"),func(st):
				var one:=fuel_effect("fuel",1.0)
				var ten:=fuel_effect("fuel",10.0)
				return t("Паливо — це запас швидкості: двигун «викидає» його назад і штовхає ракету вперед. Але паливо теж важке, тому кожна наступна тонна дає менше, а тяга/вага падає.\n+1 т: +%.2f км/с, тяга/вага %.2f → %.2f.\n+10 т: +%.2f км/с, тяга/вага %.2f → %.2f.","Fuel is velocity budget: the engine throws it backwards and pushes the rocket forwards. But fuel is heavy too, so each extra tonne adds less and thrust-to-weight drops.\n+1 t: +%.2f km/s, thrust/weight %.2f → %.2f.\n+10 t: +%.2f km/s, thrust/weight %.2f → %.2f.")%[one.dv,one.twr0,one.twr1,ten.dv,ten.twr0,ten.twr1])
			calc_box(t("Як порахувати: чи злетить ракета?","How to check: will it lift off?"),func(st):
				var n:=stage_numbers(st)
				return t("Тяга ÷ (маса × 9,81) — це «тяга на вагу». Більше 1 — ракета піднімається. Від 1,2 — летить на повну швидкість; нижче 1,2 гра забирає 10%% запасу швидкості.\nТвої числа: тяга %d кН, маса %.2f т.","Thrust ÷ (mass × 9.81) is the thrust-to-weight ratio. Above 1 the rocket rises. From 1.2 it flies at full speed; below 1.2 the game takes away 10%% of the velocity budget.\nYour numbers: thrust %d kN, mass %.2f t.")%[int(n.thrust),n.mass])
			if int(d.stages)==2:
				engine_picker("engine2",t("Двигун 2","Engine 2"))
				slider(t("Паливо 2, т","Fuel 2, t"),"fuel2",0,40,1.0,"fuel")
			calc_box(t("Як порахувати: чи вистачить швидкості?","How to check: is there enough speed?"),func(st):
				var n:=stage_numbers(st)
				var text: String=t("Для кожної ступені: Δv = Isp × 9,81 × ln(маса до ÷ маса після) ÷ 1000 (км/с). «Маса після» — без спаленого палива цієї ступені. Ступені складаються.\n","For each stage: Δv = Isp × 9.81 × ln(mass before ÷ mass after) ÷ 1000 (km/s). “Mass after” is without that stage's burnt fuel. Stages add up.\n")
				text+=t("Ступінь 1: Isp %d с, %.2f т → %.2f т.","Stage 1: Isp %d s, %.2f t → %.2f t.")%[int(n.isp1),n.m0_1,n.mf_1]
				if n.has("m0_2"): text+=t("\nСтупінь 2: Isp %d с, %.2f т → %.2f т (перший ступінь уже відкинуто).","\nStage 2: Isp %d s, %.2f t → %.2f t (stage 1 already dropped).")%[int(n.isp2),n.m0_2,n.mf_2]
				return text+"\n"+need_text())
			if State.mission>0:
				calc_box(t("Як порахувати: паливо й сила для посадки","How to check: landing fuel and braking"),func(st):
					return t("Паливо посадки = маса лендера × (e^(зайве Δv × 1000 ÷ (Isp × 9,81)) − 1). Зайве Δv — те, що лишилося понад потрібне до Місяця.\nГальмування = тяга × 0,012 ÷ (маса лендера + паливо). Має бути більше 1,62 (сила тяжіння Місяця), зручно — від 3.\nТвої числа: лендер %.2f т, Isp %d с, тяга двигуна посадки %d кН.","Landing fuel = lander mass × (e^(spare Δv × 1000 ÷ (Isp × 9.81)) − 1). Spare Δv is what remains above the Moon requirement.\nBraking = thrust × 0.012 ÷ (lander mass + fuel). It must exceed 1.62 (lunar gravity); 3+ feels comfortable.\nYour numbers: lander %.2f t, Isp %d s, landing engine thrust %d kN.")%[st.lander_mass,int(st.landing_isp),int(st.landing_thrust)])
			var names:=[]
			for q in parts.quality: names.append(localized(q.name))
			if part_shown("quality"):
				choose(t("Клас деталей","Part class"),names,int(d.quality),func(i): set_part("quality",i),"quality")
			var q: Dictionary=parts.quality[int(d.quality)]
			if part_shown("quality"): line(t("Ціна деталей ×%.2f • допуски посадки ×%.2f • надійність %.1f%% за 4 доби","Part price ×%.2f • landing tolerance ×%.2f • reliability %.1f%% per 4 days")%[q.price,q.tolerance,q.reliability*100],MUTED)
		1:
			slider(t("Панелі","Panels"),"panels",0,6)
			line(t("Панель: %.2f т • %d Вт • %d млн $","Panel: %.2f t • %d W • %d $M")%[parts.panel.mass,parts.panel.power,parts.panel.cost],MUTED)
			if part_shown("batteries"):
				slider(t("Батареї","Batteries"),"batteries",0,6)
				line(t("Батарея: %.2f т • %d Вт·год • %d млн $","Battery: %.2f t • %d Wh • %d $M")%[parts.battery.mass,parts.battery.capacity,parts.battery.cost],MUTED)
			calc_box(t("Як порахувати: чи вистачить енергії?","How to check: is there enough power?"),func(st):
				return t("Є = панелі × %d Вт + батареї × %d Вт·год ÷ (діб × 24).\nТреба = %d Вт (бортові системи) + антена + радар + усі прилади.\nЯкщо «є» менше за «треба», останній вибраний прилад вимкнеться. Твої числа: %d панелі, %d батареї, %d діб; споживання %.0f Вт.","Have = panels × %d W + batteries × %d Wh ÷ (days × 24).\nNeed = %d W (bus) + antenna + radar + all instruments.\nIf “have” is below “need”, the last chosen instrument switches off. Your numbers: %d panels, %d batteries, %d days; demand %.0f W.")%[int(parts.panel.power),int(parts.battery.capacity),int(parts.bus_power),int(State.design.panels),int(State.design.batteries),int(State.design.days),st.power])
			var names:=[]
			var antenna_count: int=2 if State.limited() else parts.antennas.size()
			for a in parts.antennas.slice(0,antenna_count): names.append(localized(a.name))
			choose(t("Антена","Antenna"),names,mini(int(d.antenna),antenna_count-1),func(i): set_part("antenna",i),"antenna%d"%int(d.antenna))
			var antenna: Dictionary=parts.antennas[int(d.antenna)]
			line(t("%.2f т • %d Вт • %d МБ/добу • %d млн $","%.2f t • %d W • %d MB/day • %d $M")%[antenna.mass,antenna.power,antenna.rate,antenna.cost],MUTED)
			calc_box(t("Як порахувати: чи встигне антена все передати?","How to check: can the antenna send everything?"),func(st):
				return t("Зв'язок буває не завжди: лише %d%% часу. Тому передається частка = швидкість антени × %.2f ÷ дані приладів за добу (максимум 100%%). Якщо апарат цілий після місії, він ще трохи допередає (+%.2f).\nТвої числа: антена %.0f МБ/добу, прилади %.0f МБ/добу.","Contact is not constant: only %d%% of the time. Sent share = antenna rate × %.2f ÷ instrument data per day (up to 100%%). A vehicle that survives sends a bit more afterwards (+%.2f).\nYour numbers: antenna %.0f MB/day, instruments %.0f MB/day.")%[roundi(float(Sim.balance().window_share)*100),float(Sim.balance().window_share),float(Sim.balance().post_share),st.link,st.data_rate])
			if part_shown("radar"): slider(t("Радар трекінгу / навігація","Tracking radar / navigation"),"radar",0,1 if State.limited() else 3)
			if part_shown("radar"): line(t("Рівень радара: %.3f т • %d Вт • %d млн $","Radar level: %.3f t • %d W • %d $M")%[parts.radar.mass,parts.radar.power,parts.radar.cost],MUTED)
			check(t("Опори • %.2f т • %d млн $","Legs • %.2f t • %d $M")%[parts.legs.mass,parts.legs.cost],d.legs,func(v): set_part("legs",v),"legs")
			line(t("Ширші допуски посадки (×1,3 швидкість, +6° нахил).","Wider landing tolerances (×1.3 speed, +6° tilt)."),MUTED)
			check(t("Альтіметр • %.2f т • %d млн $","Altimeter • %.2f t • %d $M")%[parts.altimeter.mass,parts.altimeter.cost],d.altimeter,func(v): set_part("altimeter",v),"altimeter")
			line(t("Показує висоту й швидкість під час посадки.","Shows altitude and speed during landing."),MUTED)
			if State.mission>0:
				calc_box(t("Як порахувати: з якою швидкістю можна торкнутися?","How to check: how fast may you touch down?"),func(st):
					var lim: Dictionary=Sim.landing_limits(State.design,State.difficulty)
					return t("Безпечно = базова межа × складність × клас деталей × 1,3 з опорами. Нахил: межа × клас + 6° з опорами.\nЗараз: вниз до %.1f м/с, вбік до %.1f м/с, нахил до %.0f°. До 1,5 від межі — жорстка посадка (70%% даних), більше — аварія.","Safe = base limit × difficulty × part class × 1.3 with legs. Tilt: limit × class + 6° with legs.\nNow: down up to %.1f m/s, sideways up to %.1f m/s, tilt up to %.0f°. Up to 1.5× the limit is a hard landing (70%% of data); beyond that is a crash.")%[lim.vertical,lim.horizontal,lim.angle])
		2:
			line(t("Порядок вибору = пріоритет живлення: останній обраний прилад вимикається першим.","Selection order = power priority: the last selected instrument shuts down first."),MUTED)
			for item in parts.instruments:
				var id: String=item.id
				if not State.part_available(id):
					line(localized(item.name)+" • "+t("дослідження в лабораторії","laboratory research"),MUTED)
					continue
				var order: int=d.instruments.find(id)
				check(localized(item.name)+("  #%d"%(order+1) if order>=0 else ""),order>=0,func(v):
					if v and id not in State.design.instruments: State.design.instruments.append(id)
					elif not v: State.design.instruments.erase(id)
					State.save_game(); constructor_ui_refresh(true),id)
				line(t("%.2f т • %d Вт • %d МБ/добу • наука %.1f • %d млн $","%.2f t • %d W • %d MB/day • science %.1f • %d $M")%[item.mass,item.power,item.data,item.value,item.cost],MUTED)
			calc_box(t("Як порахувати: скільки науки дадуть прилади?","How to check: how much science do the instruments give?"),func(st):
				var mission: Dictionary=missions[State.mission]
				var site: String=""
				if State.mission>=2: site=t("\nЦя точка множить науку на ×%.1f, лише якщо працює потрібний прилад.","\nThis site multiplies science by ×%.1f only if the required instrument is on.")%float(mission.multiplier)
				return t("Результат приладів = 1 − e^(−V ÷ V₀). V — сума «науки» увімкнених приладів, V₀ — складність цілі. Кожен наступний прилад додає менше.\nТвої числа: V = %.1f, V₀ = %.1f.","Instrument result = 1 − e^(−V ÷ V₀). V is the sum of “science” of powered instruments, V₀ is the target's difficulty. Each extra instrument adds less.\nYour numbers: V = %.1f, V₀ = %.1f.")%[st.value,float(mission.v0)]+site)
			if part_shown("days"):
				slider(t("Час, діб","Lifetime, days"),"days",1,90,1.0,"days")
				calc_box(t("Як порахувати: скільки діб працювати?","How to check: how many days to operate?"),func(st):
					var q: Dictionary=parts.quality[int(State.design.quality)]
					return t("Користь часу = (1 − e^(−діб ÷ %.0f)) × надійність^(діб ÷ %.0f). Спершу росте швидко, потім ледве.\nКожна доба: +%d млн $ керування і +%.0f кг палива орієнтації (маса ракети росте).\nТвої числа: %d діб, надійність класу %.3f за %.0f доби.","Time value = (1 − e^(−days ÷ %.0f)) × reliability^(days ÷ %.0f). It grows fast at first, then barely.\nEach day: +%d $M operations and +%.0f kg attitude propellant (the rocket gets heavier).\nYour numbers: %d days, class reliability %.3f per %.0f days.")%[float(Sim.balance().lifetime_tau),float(Sim.balance().reliability_days),int(Sim.balance().ops_cost_per_day),float(Sim.balance().consumables_per_day)*1000,int(State.design.days),float(q.reliability),float(Sim.balance().reliability_days)])
			if State.mission==0:
				line(t("Рівень супутника обирається на карті місій, у «Орбіті Землі».","The satellite level is chosen on the mission map, under “Earth orbit”."),MUTED)
		3:
			var name_edit:=LineEdit.new()
			name_edit.text=d.name
			name_edit.max_length=32
			name_edit.placeholder_text=t("Назва конструкції","Design name")
			name_edit.text_changed.connect(func(value): State.design.name=value)
			name_edit.focus_exited.connect(State.save_game)
			body.add_child(name_edit)
			action(t("Зберегти конструкцію в архів","Save design to archive"),func(): State.designs.append(State.design.duplicate(true)); State.save_game(); name_edit.text=State.design.name+" ✓")
			action(t("Копіювати код конструкції","Copy design code"),func(): DisplayServer.clipboard_set(State.export_code()))
			var code:=LineEdit.new()
			code.placeholder_text=t("Вставте MA1:…","Paste MA1:…")
			body.add_child(code)
			action(t("Імпортувати код","Import code"),func():
				if State.import_code(code.text.strip_edges()): constructor_ui_refresh()
				else: code.text=t("Некоректний або недоступний код","Invalid or unavailable design code"))
			line(t("Покупка всіх деталей і палива відбувається під час запуску.","Parts and fuel are purchased together when launching."),MUTED)
	if not State.sandbox and State.difficulty==0 and State.unlocked<1 and build_tab<3:
		line(t("Більше деталей (батареї, радар, тривалість, клас) відкриється після першої успішної місії.","More parts (batteries, radar, lifetime, class) unlock after your first successful mission."),GOLD)
	refresh_calc_boxes(Sim.stats(State.design,State.mission))
	active_shell.get_node("Footer").text=t("Порада: після кожної зміни дивись на картки вгорі — зелене допомагає місії, червоне коштує ресурсу.","Tip: after each change watch the cards on top: green helps the mission, red costs a resource.")

func engine_picker(key: String,title: String) -> void:
	var names:=[]
	var count: int=2 if State.limited() else parts.engines.size()
	for item in parts.engines.slice(0,count): names.append(localized(item.name))
	choose(title,names,mini(int(State.design[key]),count-1),func(i): set_part(key,i),"engine")
	var e: Dictionary=parts.engines[int(State.design[key])]
	line(t("%.2f т • тяга %d кН • Isp %d с • %d млн $","%.2f t • thrust %d kN • Isp %d s • %d $M")%[e.mass,e.thrust,e.isp,e.cost],MUTED)

func resource_text(s: Dictionary, paid: bool=false) -> String:
	# Six NASA resources as plain numbers: no verdicts, no derived Δv/TWR.
	var balance_text: String="∞" if State.sandbox else str(roundi(State.money if paid else State.money-s.cost))+" "+t("млн $","$M")
	return t("Маса %.2f т   Енергія: вироблення %.0f / споживання %.0f Вт\n%s %.0f млн $   Залишок %s\nДані %.0f МБ/добу   Зв’язок %.0f МБ/добу   Час %d діб","Mass %.2f t   Power: supply %.0f / demand %.0f W\n%s %.0f $M   Balance %s\nData %.0f MB/day   Link %.0f MB/day   Time %d days") % [s.mass,s.available_power,s.power,t("Оплачено","Paid") if paid else t("Вартість","Cost"),s.cost,balance_text,s.data_rate,s.link,State.design.days]

func update_resources() -> void:
	if not is_instance_valid(resources): return
	var stats:=Sim.stats(State.design,State.mission)
	resources.text=resource_text(stats)
	if page=="constructor" and is_instance_valid(active_shell):
		var d: Dictionary=State.design
		var load_share: float=stats.active_power/maxf(stats.available_power,0.01)
		var link_share: float=Sim.transfer_share(stats,d.days,1.0,true)
		var money_left: float=State.money-stats.cost
		var names: Array=[t("Маса","Mass"),t("Енергія вир./спож.","Power gen/use"),t("Ціна / залишок","Cost / left"),t("Дані, МБ/добу","Data, MB/day"),t("Зв’язок, МБ/добу","Link, MB/day"),t("Час","Lifetime")]
		var data_text: String="%.0f"%stats.data_rate
		if stats.raw_data_rate>stats.data_rate+0.01: data_text+=t(" з %.0f"," of %.0f")%stats.raw_data_rate
		var values: Array=["%.2f %s"%[stats.mass,t("т","t")],"%.0f / %.0f %s"%[stats.available_power,stats.power,t("Вт","W")],"%.0f / %s"%[stats.cost,"∞" if State.sandbox else str(roundi(money_left))],data_text,"%.0f"%stats.link,"%d %s"%[d.days,t("діб","days")]]
		# Second line: what the number means for the rest of the mission.
		var notes: Array=[
			t("суха %.2f • запас %.2f т","dry %.2f • stores %.2f t")%[stats.dry,stats.consumables],
			(t("навантаження %d%%","load %d%%")%roundi(load_share*100)) if stats.active_count==stats.instrument_count else t("вимкнено приладів: %d","instruments off: %d")%(stats.instrument_count-stats.active_count),
			t("з них керування %d","incl. operations %d")%int(stats.ops_cost),
			t("працює приладів %d/%d","instruments on %d/%d")%[stats.active_count,stats.instrument_count],
			t("встигне передати %d%%","can downlink %d%%")%roundi(link_share*100),
			t("надійність %d%%","reliability %d%%")%roundi(stats.reliability*100)]
		# Bars show the same ratios as the notes, not arbitrary scales.
		var amounts: Array=[stats.fuel/maxf(stats.mass,0.01),load_share,stats.cost/maxf(State.money,1.0) if not State.sandbox else 0.0,stats.active_count/maxf(1.0,stats.instrument_count),link_share,stats.reliability]
		# Ripple effect of the last change: green = helps the mission, red = costs something.
		var readings: Array=[stats.mass,load_share*100,stats.cost,stats.data_rate,stats.link,float(d.days)]
		var better_up: Array=[false,false,false,true,true,true]
		var units: Array=[" "+t("т","t"),"%"," "+t("млн $","$M"),"","",""]
		if resource_prev.size()==6 and readings!=resource_prev:
			resource_delta=[]
			for i in 6:
				var diff: float=readings[i]-resource_prev[i]
				resource_delta.append(diff)
		resource_prev=readings
		var cards: Node=active_shell.get_node("ResourceCards")
		for i in 6:
			var card: Control=cards.get_child(i)
			card.get_node("Title").text=names[i]
			var value: Label=card.get_node("Value")
			value.text=values[i]
			value.offset_top=42
			value.offset_bottom=82
			value.remove_theme_color_override("font_color")
			if (i==2 and money_left<0 and not State.sandbox) or (i==1 and load_share>1.0): value.add_theme_color_override("font_color",Color("e8664f"))
			var note: Label=card.get_node_or_null("Note")
			if note==null:
				note=Label.new()
				note.name="Note"
				note.position=Vector2(16,84)
				note.size=Vector2(254,26)
				note.add_theme_font_size_override("font_size",20)
				note.add_theme_color_override("font_color",MUTED)
				note.clip_text=true
				card.add_child(note)
			note.text=notes[i]
			var delta: Label=card.get_node_or_null("Delta")
			if delta==null:
				delta=Label.new()
				delta.name="Delta"
				delta.position=Vector2(16,134)
				delta.size=Vector2(254,26)
				delta.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
				delta.add_theme_font_size_override("font_size",20)
				card.add_child(delta)
			delta.text=""
			if resource_delta.size()==6 and absf(resource_delta[i])>0.0049:
				var diff: float=resource_delta[i]
				var fmt: String="%+.2f" if i==0 else "%+.0f"
				delta.text=(fmt%diff)+units[i]
				var good: bool=(diff>0)==better_up[i]
				delta.add_theme_color_override("font_color",Color("6fcf7f") if good else Color("e8664f"))
				if i==5: delta.add_theme_color_override("font_color",GOLD)
			active_shell.get_node("ResourceBars").get_child(i).value=clampf(amounts[i]*100,0,100)
		active_shell.get_node("PreviewPanel/Name").text=State.design.name
		var name_label: Label=active_shell.get_node("PreviewPanel/Name")
		name_label.position=Vector2(40,70)
		name_label.add_theme_font_size_override("font_size",24)
		name_label.add_theme_color_override("font_color",MUTED)
		active_shell.get_node("PreviewPanel/Title").text=t("КОНСТРУКЦІЯ","VEHICLE")
		refresh_calc_boxes(stats)
		build_preview()

func build_preview() -> void:
	# The preview is assembled from the actual design: stages, tank length and installed parts.
	var panel_node: Control=active_shell.get_node("PreviewPanel")
	panel_node.get_node("Rocket").visible=false
	for old_name in ["Assembly","PayloadIcons"]:
		var old:=panel_node.get_node_or_null(old_name)
		if old: old.free()
	var d: Dictionary=State.design
	var box:=VBoxContainer.new()
	box.name="Assembly"
	box.add_theme_constant_override("separation",0)
	box.position=Vector2(0,104)
	box.size=Vector2(524,0)
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel_node.add_child(box)
	var rocket_tex: Texture2D=preload("res://assets/art/rocket.png")
	var piece:=func(texture: Texture2D,region: Rect2,height: float):
		var atlas:=AtlasTexture.new()
		atlas.atlas=texture
		atlas.region=region
		var rect:=TextureRect.new()
		rect.texture=atlas
		rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode=TextureRect.STRETCH_SCALE
		rect.custom_minimum_size=Vector2(region.size.x*1.6,height)
		rect.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)
	# Fairing (payload), optional upper stage, then the first stage stretched by its propellant load.
	piece.call(rocket_tex,Rect2(0,0,48,44),44*1.6)
	if int(d.stages)==2:
		piece.call(preload("res://assets/art/stage_2.png"),Rect2(0,0,36,48),(48*1.6)*lerpf(0.75,1.2,float(d.fuel2)/40.0))
	piece.call(preload("res://assets/art/stage_1.png"),Rect2(0,0,48,72),(72*1.6)*lerpf(0.7,1.25,float(d.fuel)/80.0))
	var flow:=HFlowContainer.new()
	flow.name="PayloadIcons"
	flow.position=Vector2(28,0)
	flow.size=Vector2(468,0)
	flow.alignment=FlowContainer.ALIGNMENT_CENTER
	flow.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var icons: Array=["engine"]
	if int(d.stages)==2: icons.append("stages")
	for id in d.instruments: icons.append(id)
	icons.append("antenna%d"%int(d.antenna))
	for i in int(d.panels): icons.append("panels")
	for i in int(d.batteries): icons.append("batteries")
	if int(d.radar)>0: icons.append("radar")
	if d.legs: icons.append("legs")
	if d.altimeter: icons.append("altimeter")
	if State.mission==0: icons.append("satellite")
	for key in icons:
		var texture:=part_icon(key)
		if texture: flow.add_child(icon_rect(texture,40))
	panel_node.add_child(flow)
	var old_checks:=panel_node.get_node_or_null("Checks")
	if old_checks: old_checks.free()
	var checks:=VBoxContainer.new()
	checks.name="Checks"
	checks.position=Vector2(32,0)
	checks.size=Vector2(460,0)
	checks.add_theme_constant_override("separation",2)
	checks.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for check_item in design_checks(Sim.stats(d,State.mission)).slice(0,4):
		var row_label:=Label.new()
		row_label.text=["✓ ","! ","✗ "][check_item[0]]+check_item[1]
		row_label.add_theme_font_size_override("font_size",20)
		row_label.add_theme_color_override("font_color",[Color("6fcf7f"),GOLD,Color("e8664f")][check_item[0]])
		row_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		row_label.custom_minimum_size.x=460
		checks.add_child(row_label)
	panel_node.add_child(checks)
	# Place the parts list below the assembled rocket.
	await get_tree().process_frame
	if is_instance_valid(flow) and is_instance_valid(box):
		flow.position.y=minf(box.position.y+box.size.y+10,470)
		if is_instance_valid(checks): checks.position.y=flow.position.y+flow.size.y+12

func lab_ui() -> void:
	panel(t("Лабораторія","Laboratory"))
	live=line("",GOLD)
	line(t("Конвертер: курс 70–130 млн $ за 1 МБ змінюється кожні 10 с у комплексі, під час місії заморожений. Комісії немає. Очки й ROI завжди рахуються за базовим курсом 100.","Converter: the 70–130 $M per MB rate changes every 10 s in the complex and freezes during missions. No fee. Score and ROI always use the base rate of 100."),MUTED)
	action(t("Продати всі дані","Sell all data"),func(): State.sell(State.science); Audio.play("coin"); show_page("lab"),State.science<=0)
	action(t("Продати половину","Sell half"),func(): State.sell(State.science/2); Audio.play("coin"); show_page("lab"),State.science<=0)
	line(t("Історія курсу (останні 10)","Rate history (last 10)"),MUTED)
	if State.rates.size()<2: line(t("Графік з’явиться, коли курс зміниться (кожні 10 с у комплексі).","The chart appears once the rate changes (every 10 s in the complex)."),MUTED)
	var graph:=Control.new()
	graph.name="RateGraph"
	graph.custom_minimum_size=Vector2(1200,120)
	graph.draw.connect(func():
		graph.draw_line(Vector2(0,60),Vector2(1200,60),Color("3b5267"))
		for i in range(1,State.rates.size()):
			graph.draw_line(Vector2((i-1)*120,120-(State.rates[i-1]-70)/60*120),Vector2(i*120,120-(State.rates[i]-70)/60*120),GOLD,3))
	body.add_child(graph)
	if not State.rate_changed.is_connected(graph.queue_redraw): State.rate_changed.connect(graph.queue_redraw)
	line(t("Дослідження за дані","Research with data"),CYAN)
	var entries: Array=[["part_spectrometer",localized(parts.instruments[1].name)],["part_ice",localized(parts.instruments[3].name)]]
	for i in range(1,4): entries.append(["mission_%d"%i,t("Місія: ","Mission: ")+localized(missions[i].name)])
	entries.append(["sat_2",t("Супутник-страховка рівня 2","Insurance satellite level 2")])
	entries.append(["sat_3",t("Супутник-страховка рівня 3","Insurance satellite level 3")])
	for entry in entries:
		var key: String=entry[0]
		var cost:=State.research_cost(key)
		var done: bool=key in State.research or (key.begins_with("part_") and State.part_available(key.substr(5)))
		var label: String=("✓ " if done else "")+entry[1]+" • %.0f "%cost+t("МБ","MB")
		if not done and not State.research_ready(key):
			label+="  ("+(t("спершу супутник рівня 2","satellite level 2 first") if key=="sat_3" else t("спершу успіх попередньої місії","succeed in the previous mission first"))+")"
		var research_button:=action(label,func():
			if State.buy_research(key):
				Audio.play("research")
				show_page("lab"),done or not State.research_ready(key) or (not State.sandbox and State.science<cost))
		if RESEARCH_ICONS.has(key):
			research_button.icon=load("res://assets/art/research_icons/research_%02d.png"%RESEARCH_ICONS[key])
			research_button.custom_minimum_size.y=60
	var net: Array=Sim.balance().satellite_net
	line(t("Страховка: супутник рівня %d на орбіті","Insurance: level %d satellite in orbit")%State.satellite_level if State.satellite_level>0 else t("Страховка: супутника ще немає (діє лише екстрений грант зі штрафом)","Insurance: no satellite yet (only an emergency grant with a penalty)"),CYAN)
	for level in 3:
		line(t("Рівень %d: якщо гроші + дані×100 < %d млн $ після місії, супутник надсилає дані до %d млн $","Level %d: if money + data×100 < %d $M after a mission, the satellite sends data up to %d $M")%[level+1,int(net[level].threshold),int(net[level].restore)],INK if State.satellite_level==level+1 else MUTED)

func comms_ui() -> void:
	# The ground station explains why data arrives only part of the time.
	panel(t("Центр зв’язку","Communications"))
	line(t("Ця велика антена ловить сигнали твоїх апаратів. Справжні станції (як мережа NASA DSN) стоять у різних куточках Землі, але апарат усе одно «чути» не весь час.","This big dish catches signals from your spacecraft. Real stations (like NASA's DSN) sit around the world, yet a craft is still not heard all the time."))
	var share: float=float(Sim.balance().window_share)
	line(t("Зв’язок є приблизно %d%% часу. Тож за добу антена апарата передає: швидкість антени × %.2f.","Contact exists about %d%% of the time, so per day the craft's antenna sends: antenna rate × %.2f.")%[roundi(share*100),share],CYAN)
	var s:=Sim.stats(State.design,State.mission)
	var per_day: float=s.link*share
	var total_share: float=Sim.transfer_share(s,State.design.days,1.0,true)
	line(t("Твоя ракета «%s»: антена %.0f МБ/добу × %.2f = %.1f МБ/добу передасть, прилади збирають %.1f МБ/добу.","Your rocket “%s”: antenna %.0f MB/day × %.2f = %.1f MB/day sent, instruments collect %.1f MB/day.")%[State.design.name,s.link,share,per_day,s.data_rate])
	if s.data_rate<=0: line(t("Приладів немає або їм бракує енергії — передавати нічого.","No powered instruments: nothing to send."),GOLD)
	else:
		line(t("Після місії вцілілий апарат ще допередає частину (+%.2f від швидкості антени).","After the mission a surviving craft sends a bit more (+%.2f of the antenna rate).")%float(Sim.balance().post_share),MUTED)
		if total_share>=0.999: line(t("✓ Разом антена встигає передати все.","✓ Altogether the antenna sends everything."),Color("6fcf7f"))
		else: line(t("! Разом антена передасть лише %d%% — решта даних пропаде. Більша антена або менше приладів вирівняють це.","! Altogether the antenna sends only %d%%: the rest is lost. A bigger antenna or fewer instruments fixes it.")%roundi(total_share*100),GOLD)
	line(t("Останні сеанси","Recent sessions"),CYAN)
	if State.reports.is_empty(): line(t("Ще не було жодної місії.","No missions yet."),MUTED)
	for r in State.reports.slice(-5):
		line("%s • %s • +%.1f %s"%[localized(missions[int(r.mission)].name),str(r.get("design","")),float(r.get("data",0)),t("МБ","MB")],MUTED)

func archive_ui() -> void:
	panel(t("Архів і Гайд","Archive and Guide"))
	line(t("Ім’я дослідника","Explorer name"),MUTED)
	var player_edit:=LineEdit.new()
	player_edit.text=State.player_name
	player_edit.max_length=24
	player_edit.text_changed.connect(func(value): State.player_name=value)
	player_edit.focus_exited.connect(State.save_game)
	body.add_child(player_edit)
	action(t("Відкрити Гайд","Open Guide"),func(): show_page("guide"))
	if calculator_allowed(): action(t("Калькулятор формул","Formula calculator"),func(): open_calculator("archive"))
	action(t("UK / EN • мова інтерфейсу","UK / EN • interface language"),func(): State.language="en" if State.language=="uk" else "uk"; State.save_game(); show_page("archive"))
	line(t("Збережені конструкції","Saved designs"),GOLD)
	for i in State.designs.size():
		var index:=i
		action(str(State.designs[i].name),func():
			if State.import_code(State.encode(State.designs[index])): show_page("constructor")
			else:
				message=t("Конструкція недоступна на цій складності або без досліджень","Design is unavailable at this difficulty or without research")
				show_page("archive"))
	if State.designs.is_empty(): line(t("Поки порожньо — збережи ракету у вкладці «Файл» майстерні.","Empty for now: save a rocket in the workshop's Design tab."),MUTED)
	line(t("Звіти • останні 30","Reports • last 30"),GOLD)
	if State.reports.is_empty(): line(t("Поки порожньо.","Empty for now."),MUTED)
	for i in range(State.reports.size()-1,-1,-1):
		var index:=i
		var r: Dictionary=State.reports[i]
		action("%s • %s • %s • %d"%[localized(missions[int(r.mission)].name),r.design,r.rank,r.points],func(): report=State.reports[index]; show_page("report"))
	line(t("Рекорди • топ 10 на місію • складність: %s","Records • top 10 per mission • difficulty: %s")%localized(State.settings().name),GOLD)
	action(t("Сортувати: очки / ROI","Sort: points / ROI"),func(): report_sort="roi" if report_sort=="points" else "points"; show_page("archive"))
	var sorted: Array=State.records.filter(func(r): return int(r.get("difficulty",1))==State.difficulty)
	sorted.sort_custom(func(a,b): return a[report_sort]>b[report_sort])
	var counts:={}
	for r in sorted:
		var key:=record_key(r)
		counts[key]=int(counts.get(key,0))+1
		if counts[key]<=10:
			var where: String=localized(missions[int(r.mission)].name)
			if int(r.mission)==0: where+=" / "+(t("ССО","SSO") if int(r.get("orbit",0))==1 else t("низька","LEO"))
			line(t("%s • %s • %s • %d балів • ROI %.2f","%s • %s • %s • %d pt • ROI %.2f")%[where,r.get("player","Explorer"),r.design,r.points,r.roi],MUTED)
	if sorted.is_empty(): line(t("Поки порожньо — заверши місію, щоб потрапити сюди.","Empty for now: finish a mission to appear here."),MUTED)
	action(t("Головне меню","Main menu"),func(): State.save_game(); show_page("title"))

func record_key(r: Dictionary) -> String:
	return "%d/%d/%d"%[int(r.mission),int(r.get("difficulty",1)),int(r.get("orbit",0)) if int(r.mission)==0 else 0]

func guide_ui() -> void:
	panel(t("Гайд","Guide"),"archive")
	var content: Array=Sim.load_json("res://data/guide.json")
	for item in content:
		line(localized(item.title),GOLD)
		line(localized(item.text))

func confirm_launch() -> void:
	page="launch_confirm"
	hub.visible=false
	wipe_ui()
	panel(t("Запустити?","Launch?"))
	var where: String=localized(missions[State.mission].name)
	if State.mission==0: where+=" • "+localized(Sim.orbit_info(State.orbit).name)
	line(where,GOLD)
	var s:=Sim.stats(State.design,State.mission)
	line(resource_text(s))
	line(t("Деталі %.0f млн $ • паливо %.0f млн $ • плата за запуск %.0f млн $ • керування %d діб %.0f млн $","Parts %.0f $M • fuel %.0f $M • launch fee %.0f $M • operations %d days %.0f $M")%[s.parts_cost,s.fuel_cost,s.launch_fee,int(s.days),s.ops_cost],MUTED)
	for check_item in design_checks(s):
		line(["✓ ","! ","✗ "][check_item[0]]+check_item[1],[Color("6fcf7f"),GOLD,Color("e8664f")][check_item[0]])
	if not State.sandbox and s.cost>State.money:
		line(t("Для покупки бракує грошей: %.0f млн $","Purchase needs %.0f $M more")%(s.cost-State.money),GOLD)
	else:
		launch_button=action(t("Так, запустити","Yes, launch"),begin_mission)
	action(t("Повернутися","Return"),func(): show_page("hub"))
	apply_tutorial()

func add_log(stage: int,code: String,details: String="") -> void:
	logbook.append({"stage":stage,"code":code,"details":details})

func final_stage() -> int:
	return 2 if State.mission==0 else 3

func build_rockets() -> void:
	# The flying rocket is the one designed in the workshop.
	for path in ["LaunchWorld/Rocket/Assembly","FlightWorld/Rocket/Assembly"]:
		get_node(path).build(State.design)

func begin_mission() -> void:
	var s:=Sim.stats(State.design,State.mission)
	if not State.sandbox and s.cost>State.money: return
	if not State.sandbox: State.money-=s.cost
	State.mission_pending={"mission":State.mission,"design":State.design.name,"cost":s.cost}
	State.in_mission=true
	logbook=[]
	paused=false
	speed=4.0
	var required:=Sim.required_dv(missions[State.mission],State.mission,State.orbit)
	run={"stats":s,"actual_cost":s.cost,"required":required,"fuel":Sim.remaining_fuel(State.design,s,required),"start_fuel":0.0,"unstable":false,"stored":0.0,"sent":0.0,"battery":s.energy,"events_ok":0.0,"events_total":0,"loss_factor":1.0,"transfer_factor":1.0,"result":"","grant":State.grant,"failure_roll":randf(),"young":State.difficulty==0}
	run.start_fuel=run.fuel
	State.grant=false
	State.save_game()
	if s.active_count<s.instrument_count: add_log(1,"power","%d / %d"%[s.active_count,s.instrument_count])
	build_rockets()
	if tutorial_on(): set_tut_step(4)
	show_page("launch")

func flight_ui() -> void:
	mount_shell("FlightHUD")
	active_shell.get_node("Title").text=t("01 ВИЛІТ   /   02 ВИХІД НА ОРБІТУ","01 ASCENT   /   02 ORBIT INSERTION") if State.mission==0 else t("01 ВИЛІТ   /   02 ПЕРЕЛІТ   /   03 ПОСАДКА","01 ASCENT   /   02 TRANSFER   /   03 LANDING")
	live=active_shell.get_node("Status")
	resources=active_shell.get_node("Resources")
	resources.text=resource_text(run.stats,true)
	active_shell.get_node("Pause").pressed.connect(toggle_pause)
	active_shell.get_node("Speed").pressed.connect(toggle_flight_speed)
	# During ascent the only way to go faster is tapping Space.
	active_shell.get_node("Speed").visible=page!="launch"
	active_shell.get_node("Pause").text=t("Пауза • Esc","Pause • Esc")
	if page=="launch":
		launch_boost=0.0
		show_prompt([[["space"],t("НАТИСКАЙ ПРОБІЛ ДЛЯ ПРИСКОРЕННЯ","TAP SPACE TO SPEED UP")]],250,t("Чим частіше натискаєш — тим швидше летить ракета","The faster you tap, the faster the rocket climbs"),true)
	elif page=="flight":
		show_prompt([[[],t("ЛЕТИМО ДО МІСЯЦЯ","FLYING TO THE MOON")]],250,t("Чекай або натисни «×1» → «×2», щоб летіти швидше","Wait, or press “×1” → “×2” to fly faster"),false,false)
	update_speed_label()
	active_shell.get_node("SpeedMarkers").visible=page=="launch"
	if page=="launch":
		var sc:=ascent_scale()
		var labels: Array=[active_shell.get_node("SpeedMarkers/FirstCosmicSpeed"),active_shell.get_node("SpeedMarkers/EscapeSpeed")]
		for i in 2:
			var mark: Array=sc.marks[i]
			var label: Label=labels[i]
			label.text=mark[1]
			label.size.x=220
			label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			label.position.x=(20+float(mark[0])/sc.max*170)*6-110
			label.position.y=726 if i==0 else 812

func ascent_scale() -> Dictionary:
	# Honest velocity bar: what orbit speed is, and what the mission really needs including losses.
	var need: float=run.required
	if State.mission==0:
		return {"max":12.0,"fill":need,"marks":[[7.9,t("7,9 орбіта","7.9 orbit")],[need,t("%.1f треба","%.1f needed")%need]]}
	return {"max":17.0,"fill":float(Sim.balance().orbit_insertion_dv),"marks":[[7.9,t("7,9 орбіта","7.9 orbit")],[need,t("%.1f до Місяця","%.1f to the Moon")%need]]}

func key_cap(key: String) -> Control:
	# A drawn keyboard key with its letter, e.g. [E] or a wide [SPACE].
	var wide: bool=key=="space"
	var cap:=TextureRect.new()
	cap.texture=load("res://assets/art/ui/key_space.png" if wide else "res://assets/art/ui/key_square.png")
	cap.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	cap.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	cap.stretch_mode=TextureRect.STRETCH_SCALE
	cap.custom_minimum_size=Vector2(192,64) if wide else Vector2(64,64)
	cap.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var letter:=Label.new()
	letter.text=t("ПРОБІЛ","SPACE") if wide else key
	letter.add_theme_font_size_override("font_size",24 if wide else 32)
	letter.add_theme_color_override("font_color",Color("101a2b"))
	letter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letter.offset_top=-4
	cap.add_child(letter)
	return cap

func show_prompt(parts_list: Array, y: float, subtitle: String="", with_bar: bool=false, pulse: bool=true) -> void:
	# parts_list: [[["A","D"], "TILT"], [["space"], "ENGINE"]] — keys followed by a big word.
	hide_prompt()
	var host:=CenterContainer.new()
	host.name="Prompt"
	host.position=Vector2(0,y)
	host.size=Vector2(1920,0)
	host.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var frame:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.04,0.07,0.12,0.88)
	style.border_color=Color(0.95,0.79,0.3,0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left=28; style.content_margin_right=28; style.content_margin_top=14; style.content_margin_bottom=14
	frame.add_theme_stylebox_override("panel",style)
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	column.alignment=BoxContainer.ALIGNMENT_CENTER
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	row.alignment=BoxContainer.ALIGNMENT_CENTER
	for i in parts_list.size():
		var part: Array=parts_list[i]
		if i>0:
			var gap:=Control.new()
			gap.custom_minimum_size=Vector2(36,0)
			row.add_child(gap)
		for key in part[0]: row.add_child(key_cap(key))
		var word:=Label.new()
		word.text=part[1]
		word.add_theme_font_size_override("font_size",40)
		word.add_theme_color_override("font_color",Color("f2c94c"))
		word.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(word)
	column.add_child(row)
	if not subtitle.is_empty():
		var sub:=Label.new()
		sub.text=subtitle
		sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size",24)
		sub.add_theme_color_override("font_color",Color("e6eef2"))
		column.add_child(sub)
	prompt_bar=null
	if with_bar:
		var bar:=ProgressBar.new()
		bar.show_percentage=false
		bar.custom_minimum_size=Vector2(520,20)
		var bg:=StyleBoxFlat.new(); bg.bg_color=Color(0.12,0.18,0.25,1)
		var fill:=StyleBoxFlat.new(); fill.bg_color=Color("f2994a")
		bar.add_theme_stylebox_override("background",bg)
		bar.add_theme_stylebox_override("fill",fill)
		bar.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		column.add_child(bar)
		prompt_bar=bar
	frame.add_child(column)
	host.add_child(frame)
	active_shell.add_child(host)
	prompt_node=host
	if pulse:
		var tween:=host.create_tween().set_loops()
		tween.tween_property(frame,"modulate:a",0.7,0.5)
		tween.tween_property(frame,"modulate:a",1.0,0.5)

func hide_prompt() -> void:
	if is_instance_valid(prompt_node): prompt_node.queue_free()
	prompt_node=null
	prompt_bar=null

func toggle_flight_speed() -> void:
	speed=8.0 if speed==4.0 else 4.0
	update_speed_label()

func update_speed_label() -> void:
	if is_instance_valid(active_shell) and active_shell.has_node("Speed"):
		active_shell.get_node("Speed").text="×1" if speed==4.0 else "×2"

func ascent_end() -> void:
	var result:=Sim.launch(run.stats)
	if not result.lift:
		# TWR < 1: fuel and launch fee are lost, hardware returns to the warehouse.
		if not State.sandbox: State.money+=run.stats.parts_cost
		run.actual_cost=run.stats.cost-run.stats.parts_cost
		add_log(1,"no_lift","TWR %.2f"%run.stats.twr)
		finish_mission("crash")
		return
	add_log(1,"lift","TWR %.2f"%run.stats.twr)
	if run.stats.twr<1.2: add_log(1,"drag","Δv %.2f → %.2f км/с"%[run.stats.dv,result.dv])
	if not result.orbit:
		add_log(1,"orbit_fail","Δv %.2f км/с"%result.dv)
		finish_mission("crash")
		return
	if result.unstable:
		run.fuel*=0.8
		add_log(1,"unstable","Δv %.2f км/с"%result.dv)
	if run.failure_roll>parts.quality[int(State.design.quality)].reliability:
		add_log(1,"failure",localized(parts.quality[int(State.design.quality)].name))
		finish_mission("crash")
		return
	show_page("ascent_report")

func ascent_report_ui() -> void:
	panel(t("Результат вильоту","Ascent result"))
	# No return to hub during a live mission.
	active_shell.get_node("Back").hide()
	var dv: float=Sim.launch(run.stats).dv
	line(t("Запас швидкості ракети: %.2f км/с. Для цієї місії треба %.1f км/с.","The rocket's velocity budget: %.2f km/s. This mission needs %.1f km/s.")%[dv,run.required],GOLD)
	line(t("Чому більше за 7,9? Бо ракета ще бореться з тяжінням і повітрям, поки піднімається.","Why more than 7.9? The rocket also fights gravity and air while it climbs."),MUTED)
	line(t("Паливо, що лишилось для фіналу: %.3f т","Fuel left for the final stage: %.3f t")%run.fuel)
	action(t("До виходу на орбіту","Orbit insertion") if State.mission==0 else t("Продовжити політ","Continue flight"),continue_after_ascent)

func continue_after_ascent() -> void:
	if State.mission==0: coast_end()
	else: show_page("flight")

func event_kind(checkpoint: int) -> int:
	# Debris near Earth, flares anywhere, downlink outages at long range.
	return [0,1,2,randi_range(1,2)][clampi(checkpoint-1,0,3)]

func open_event(kind: int=-1) -> void:
	event_open=true
	current_event=kind if kind>=0 else event_kind(event_index)
	wipe_ui()
	panel([t("Космічне сміття","Orbital debris"),t("Сонячний спалах","Solar flare"),t("Збій зв’язку","Downlink outage")][current_event])
	Audio.play("alert")
	active_shell.get_node("Back").hide()
	var d: Dictionary=State.design
	line(t("На борту: паливо %.3f т • батареї %.0f Вт·год","On board: fuel %.3f t • batteries %.0f Wh")%[run.fuel,run.battery],MUTED)
	var hit: int=roundi(Sim.debris_hit_chance(int(d.radar),0)*100)
	if current_event==0:
		line(t("Уламки старих ракет летять назустріч. Що робимо?","Pieces of old rockets are heading your way. What do we do?"))
		action(t("Ухилитися двигуном • −0,03 т палива • сміття точно не влучить","Dodge with the engine • −0.03 t fuel • the debris surely misses"),func(): resolve_event(0,0))
		action(t("Захисний режим • −12%% даних • ризик удару %d%% (радар зменшує)","Safe mode • −12%% data • %d%% hit risk (radar lowers it)")%hit,func(): resolve_event(0,1))
	elif current_event==1:
		var flare_ok: int=roundi(float(parts.quality[int(d.quality)].reliability)*100)
		line(t("Сонце викинуло потік частинок. Електроніка може збоїти.","The Sun threw out a stream of particles. Electronics may glitch."))
		action(t("Працювати далі від батарей • −40 Вт·год • успіх %d%% (клас деталей)","Keep working on batteries • −40 Wh • %d%% success (part class)")%flare_ok,func(): resolve_event(1,0),run.battery<40)
		action(t("Захисний режим • −12% даних • безпечно","Safe mode • −12% data • safe"),func(): resolve_event(1,1))
	else:
		var link_ok: int=roundi(minf(1,0.55+int(d.antenna)*0.2)*100)
		line(t("Сеанс зв’язку із Землею обірвався.","The contact session with Earth dropped."))
		action(t("Повторити передачу • −25 Вт·год • успіх %d%% (антена)","Retry the downlink • −25 Wh • %d%% success (antenna)")%link_ok,func(): resolve_event(2,0),run.battery<25)
		action(t("Зберегти на борту • −15% переданих даних • безпечно","Store on board • −15% of sent data • safe"),func(): resolve_event(2,1))
	if run.battery<25 and current_event>0:
		line(t("Батарей замало для першого варіанта — у майстерні можна взяти більше.","Not enough battery for the first option: take more in the workshop."),GOLD)

func resolve_event(kind: int,choice: int) -> void:
	if paused: return
	run.events_total+=1
	var d: Dictionary=State.design
	var outcome:=""
	if choice==1:
		# Cautious choice: a known, smaller loss.
		if kind==2: run.transfer_factor*=0.85
		else: run.loss_factor*=0.88
		run.events_ok+=0.6
		add_log(2,"safe")
		outcome=t("Обережний вибір: апарат у безпеці, але частину даних втрачено (%s).","A careful choice: the craft is safe, but some data is lost (%s).")%("−15%" if kind==2 else "−12%")
		if kind==0 and randf()<Sim.debris_hit_chance(int(d.radar),0):
			run.loss_factor*=0.85
			add_log(2,"damage")
			outcome+="\n"+t("Але дрібний уламок усе ж зачепив апарат: ще −15% даних. Радар зменшує такий ризик.","But a small fragment still hit the craft: another −15% data. Radar lowers this risk.")
	elif kind==0:
		if run.fuel>=0.03:
			run.fuel-=0.03
			add_log(2,"debris_burn")
			run.events_ok+=1.0
			outcome=t("Двигун відвів апарат убік — сміття пролетіло повз. Витрачено 0,03 т палива.","The engine moved the craft aside and the debris flew by. 0.03 t of fuel used.")
		elif randf()<Sim.debris_hit_chance(int(d.radar),0):
			add_log(2,"debris_crash")
			event_open=false
			finish_mission("crash")
			return
		else:
			add_log(2,"debris_miss")
			run.events_ok+=0.5
			outcome=t("Палива на маневр не вистачило, але пощастило: сміття пролетіло повз.","There was no fuel to dodge, but you were lucky: the debris missed.")
	else:
		var energy:=40.0 if kind==1 else 25.0
		var protection: float=parts.quality[int(d.quality)].reliability if kind==1 else minf(1,0.55+int(d.antenna)*0.2)
		var had_energy: bool=run.battery>=energy
		if had_energy and randf()<protection:
			run.battery-=energy
			add_log(2,"contact" if kind==2 else "flare_ok")
			run.events_ok+=1.0
			outcome=t("Вдалося! Батареї віддали %.0f Вт·год, усе працює далі.","Success! The batteries gave %.0f Wh and everything keeps working.")%energy
		else:
			if kind==2: run.transfer_factor*=0.75
			else: run.loss_factor*=0.75
			run.battery=maxf(0,run.battery-energy)
			add_log(2,"damage")
			outcome=t("Не вийшло: втрачено 25% даних. ","It failed: 25% of data lost. ")+(t("Батарей було замало — візьми більше.","There was not enough battery: take more.") if not had_energy else (t("Надійніший клас деталей підвищує шанс.","A more reliable part class raises the chance.") if kind==1 else t("Більша антена підвищує шанс.","A bigger antenna raises the chance.")))
	# Show what happened before the flight continues.
	wipe_ui()
	panel(t("Що сталося","What happened"))
	active_shell.get_node("Back").hide()
	line(outcome)
	action(t("Летимо далі","Continue the flight"),close_event_result)

func close_event_result() -> void:
	event_open=false
	wipe_ui()
	flight_ui()

func coast_end() -> void:
	var dv: float=Sim.launch(run.stats).dv
	var required: float=run.required
	if State.mission==0:
		# Both Earth orbits enforce their own velocity requirement; a ≤5% shortfall leaves an unstable orbit.
		if dv<required*0.95:
			add_log(2,"transfer_fail","Δv %.2f < %.2f км/с"%[dv,required])
			finish_mission("crash")
			return
		run.unstable=dv<required
		var diff: Dictionary=State.settings()
		orbit_window=clampf(0.08+0.12*(1-exp(-run.fuel/0.3))+float(diff.orbit_window_bonus),0.05,0.38)
		if run.unstable:
			orbit_window=maxf(0.05,orbit_window*0.6)
			add_log(2,"unstable_orbit","Δv %.2f < %.2f км/с"%[dv,required])
		show_page("orbit")
		return
	if dv<required:
		add_log(2,"transfer_fail","Δv %.2f < %.2f км/с"%[dv,required])
		finish_mission("crash")
		return
	show_page("landing")

func orbit_ui() -> void:
	mount_shell("OrbitHUD")
	active_shell.get_node("Title").text=t("02 / ВИХІД НА ОРБІТУ","02 / ORBIT INSERTION")
	active_shell.get_node("Controls").text=t("Імпульс: Пробіл","Burn: Space")
	live=active_shell.get_node("Status")
	active_shell.get_node("Burn").text=t("ІМПУЛЬС • Пробіл","BURN • Space")
	active_shell.get_node("Burn").pressed.connect(perform_burn)
	active_shell.get_node("Pause").pressed.connect(toggle_pause)
	active_shell.get_node("Pause").text=t("Пауза • Esc","Pause • Esc")
	show_prompt([[["space"],t("НАТИСНИ, КОЛИ РИСКА В ЗЕЛЕНОМУ","PRESS WHEN THE MARKER IS IN THE GREEN")]],200,t("Яскраво-зелене — ідеально, темно-зелене — теж орбіта, але менше даних","Bright green is perfect; dark green still reaches orbit with less data"))
	orbit_cursor=0.0

func perform_burn() -> void:
	if page!="orbit" or paused: return
	var miss:=absf(orbit_cursor-0.5)
	var result:="ideal" if miss<=orbit_window/2 else ("hard" if miss<=orbit_window else "crash")
	add_log(2,"orbit_"+result,"%.0f%%"%(orbit_window*100))
	finish_mission(result)

func landing_ui() -> void:
	var diff: Dictionary=State.settings()
	landing_level=LEVEL_SCENES[State.mission-1].instantiate()
	world.add_child(landing_level)
	lander=LANDER_SCENE.instantiate()
	world.add_child(lander)
	lander.configure(State.design,run.stats,missions[State.mission],run.fuel,landing_level,diff,State.difficulty)
	landing_level.apply_lighting(State.mission==3,float(diff.shadow))
	lander.finished.connect(on_landing_finished)
	mount_shell("LandingHUD")
	active_shell.get_node("Title").text="03 / "+localized(missions[State.mission].name).to_upper()
	live=active_shell.get_node("Status")
	active_shell.get_node("Controls").text=t("A D / ← →: поворот   W / ↑ / Пробіл: тяга","A D / ← →: rotate   W / ↑ / Space: thrust")
	active_shell.get_node("Pause").pressed.connect(toggle_pause)
	active_shell.get_node("Pause").text=t("Пауза • Esc","Pause • Esc")
	landing_prompt_time=0.0
	show_prompt([[["A","D"],t("НАХИЛ","TILT")],[["W"],t("ДВИГУН","ENGINE")]],800,t("Гальмуй двигуном і сідай повільно та рівно на золоту смугу між прапорцями","Brake with the engine and land slowly and level on the gold strip between the flags"),false,false)

func on_landing_finished(result: String,v: Vector2,a: float) -> void:
	run.fuel=lander.fuel
	var limits: Dictionary=lander.limits
	run.touch={"vx":absf(v.x),"vy":absf(v.y),"angle":absf(rad_to_deg(wrapf(a,-PI,PI))),"limits":limits.duplicate()}
	add_log(3,result,"vx %.1f / %.1f • vy %.1f / %.1f м/с • %.0f° / %.0f°"%[absf(v.x),limits.horizontal,absf(v.y),limits.vertical,absf(rad_to_deg(wrapf(a,-PI,PI))),limits.angle])
	if result=="crash" and is_instance_valid(lander):
		# Show the loss before the report: a short explosion where the lander hit.
		var boom:=AnimatedSprite2D.new()
		boom.sprite_frames=preload("res://assets/art/animations/explosion.tres")
		boom.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		boom.scale=Vector2.ONE*0.5
		boom.position=lander.position+Vector2(0,-6)
		world.add_child(boom)
		boom.play("explosion")
		boom.animation_finished.connect(boom.queue_free)
		lander.get_node("Visuals").visible=false
		lander.get_node("Dust").visible=false
		Audio.play("crash")
		await get_tree().create_timer(1.3).timeout
	elif result in ["ideal","hard"]:
		Audio.play("touchdown")
	finish_mission(result)

func extra_fuel_needed(required: float) -> int:
	# Smallest first-stage top-up (t) that reaches the required velocity budget, or -1 if none does.
	var d: Dictionary=State.design
	for extra in range(1,int(80-float(d.fuel))+1):
		var trial:=d.duplicate(true)
		trial.fuel=float(d.fuel)+extra
		var launch:=Sim.launch(Sim.stats(trial,State.mission))
		if not launch.lift: return -1
		if launch.dv>=required: return extra
	return -1

func mission_advice(result: String, s: Dictionary, share: float) -> Array:
	# Plain-language "what to change next time", stored as [uk, en] pairs in the report.
	var out: Array=[]
	var codes: Array=logbook.map(func(entry): return entry.code)
	var d: Dictionary=State.design
	var launch:=Sim.launch(s)
	var required: float=run.required
	if "no_lift" in codes:
		out.append(["Ракета не відірвалася: тяга %d кН менша за вагу (%.1f т × 9,81 = %d кН). Візьми потужніший двигун або менше палива."%[int(s.thrust),s.mass,roundi(s.mass*9.81)],"The rocket did not lift off: %d kN of thrust is less than its weight (%.1f t × 9.81 = %d kN). Pick a stronger engine or less fuel."%[int(s.thrust),s.mass,roundi(s.mass*9.81)]])
	elif launch.dv<required and ("transfer_fail" in codes or "orbit_fail" in codes):
		var extra:=extra_fuel_needed(required)
		var gap: float=required-launch.dv
		if extra>0: out.append(["Бракувало %.2f км/с запасу швидкості. Приблизно +%d т палива в перший ступінь це виправить."%[gap,extra],"You were %.2f km/s short. About +%d t of fuel in stage 1 fixes it."%[gap,extra]])
		else: out.append(["Бракувало %.2f км/с, і повний бак цього не дасть: спробуй дві ступені або двигун з більшим Isp."%gap,"You were %.2f km/s short and a full tank won't cover it: try two stages or an engine with higher Isp."%gap])
	if "unstable_orbit" in codes:
		out.append(["Орбіта вийшла хиткою: бракувало %.2f км/с. Трохи більше палива — і вона буде стабільною."%(required-launch.dv),"The orbit was shaky: %.2f km/s short. A little more fuel makes it stable."%(required-launch.dv)])
	if State.mission==0 and ("orbit_crash" in codes or "orbit_hard" in codes):
		out.append(["Імпульс не влучив у зелену зону. Тисни Пробіл, коли риска в центрі. Більше палива після вильоту = ширша зелена зона.","The burn missed the green zone. Press Space when the marker is centred. More fuel left after ascent = a wider green zone."])
	if State.mission>0 and run.has("touch") and result in ["hard","crash"]:
		var touch: Dictionary=run.touch
		var lim: Dictionary=touch.limits
		var rv: float=touch.vy/lim.vertical
		var rh: float=touch.vx/lim.horizontal
		var ra: float=touch.angle/lim.angle
		if rv>=rh and rv>=ra and rv>1:
			out.append(["Посадка надто швидка: %.1f м/с вниз, а безпечно до %.1f. Гальмуй раніше й довше тримай тягу."%[touch.vy,lim.vertical],"Landing too fast: %.1f m/s down, safe is up to %.1f. Brake earlier and hold thrust longer."%[touch.vy,lim.vertical]])
		elif rh>=ra and rh>1:
			out.append(["Лендер ковзав убік: %.1f м/с, безпечно до %.1f. Нахиляй його проти руху, щоб погасити бічну швидкість."%[touch.vx,lim.horizontal],"The lander slid sideways: %.1f m/s, safe is up to %.1f. Tilt against the motion to cancel it."%[touch.vx,lim.horizontal]])
		elif ra>1:
			out.append(["Лендер сів похило: %.0f°, безпечно до %.0f°. Вирівняй його клавішами A/D перед дотиком."%[touch.angle,lim.angle],"The lander touched down tilted: %.0f°, safe is up to %.0f°. Straighten it with A/D before contact."%[touch.angle,lim.angle]])
		elif run.fuel<=0.001:
			out.append(["Скінчилося паливо посадки. Потрібен більший запас швидкості понад шлях до Місяця — додай палива.","Landing fuel ran out. You need more velocity budget beyond the trip to the Moon: add fuel."])
		if not d.legs: out.append(["Опори зробили б безпечні межі на 30% ширшими.","Landing legs would make the safe limits 30% wider."])
	if result=="stranded":
		out.append(["Ти сів м’яко, але не на майданчик, і паливо скінчилося. Цілься на золоту смугу, поки ще високо.","A soft touchdown, but off the pad and out of fuel. Aim for the gold strip while still high."])
	if "power" in codes:
		out.append(["Частині приладів бракувало енергії, і вони вимкнулися. Додай сонячну панель.","Some instruments lacked power and switched off. Add a solar panel."])
	if result in ["ideal","hard"] and share<0.999 and share>0:
		out.append(["Антена встигла передати лише %d%% даних. Більша антена передасть усе."%roundi(share*100),"The antenna sent only %d%% of the data. A bigger antenna sends it all."%roundi(share*100)])
	if "camera_missing" in codes or "site_missing" in codes:
		var needed: String=str(missions[State.mission].required)
		var names:=["?","?"]
		for item in parts.instruments:
			if item.id==needed: names=item.name
		out.append(["Візьми прилад «%s» — тут він дає головний бонус до науки."%names[0],"Take the “%s”: here it gives the main science bonus."%names[1]])
	if out.is_empty() and result in ["ideal","hard"]:
		out.append(["Чудова місія! Спробуй дешевшу ракету — прибуток і бали стануть ще вищими.","Great mission! Try a cheaper rocket: profit and score will climb even higher."])
	return out.slice(0,4)

func finish_mission(result: String) -> void:
	if not State.in_mission: return
	var stage:=final_stage()
	State.in_mission=false
	State.mission_pending={}
	event_open=false
	var success: bool=result in ["ideal","hard"]
	var index: int=State.mission
	var mission: Dictionary=missions[index]
	var d: Dictionary=State.design
	var s: Dictionary=run.stats
	if index==0 and success:
		if not run.young and randf()<Sim.debris_hit_chance(int(d.radar),State.orbit):
			run.loss_factor*=0.7
			add_log(2,"debris_hit",t("радар %d","radar %d")%int(d.radar))
		if State.install_satellite(int(d.satellite)): add_log(2,"satellite_up",t("рівень %d","level %d")%int(d.satellite))
	if index>0 and is_instance_valid(lander):
		add_log(3,"fuel_left","%.0f%%"%(100*clampf(run.fuel/maxf(0.001,run.start_fuel),0,1)))
	# Data = D_base · M · (1 − e^(−V/V0)) · L · K · T
	var science: Dictionary=Sim.science_potential(d,s,mission,index,State.orbit)
	if index>=2:
		add_log(stage,"site_bonus" if science.multiplier>1 else "site_missing","×%.1f"%science.multiplier)
	elif index==0 and "camera" not in s.active_ids:
		add_log(stage,"camera_missing","×%.1f"%float(Sim.balance().earth_without_camera))
	elif index==0 and science.multiplier>1:
		add_log(stage,"orbit_bonus","×%.2f"%science.multiplier)
	add_log(stage,"saturation","V %.1f → %.0f%%"%[s.value,science.saturation*100])
	add_log(stage,"lifetime",t("%d діб → %.0f%%","%d days → %.0f%%")%[int(d.days),science.lifetime*100])
	var link_factor: float=float(Sim.orbit_info(State.orbit).link) if index==0 else 1.0
	var energy_left: bool=run.battery>0 or s.supply>=s.active_power
	var share: float=Sim.transfer_share(s,d.days,run.transfer_factor,success and energy_left,link_factor)
	var generated: float=s.data_rate*maxf(1,d.days)
	var k: float=Sim.result_factor(result,run.sent/maxf(generated,0.001))
	var data: float=Sim.mission_data(science.potential,k,share if success else 1.0,run.loss_factor)
	if success and share<0.999: add_log(stage,"transfer_cap","%.0f%%"%(share*100))
	if not success: add_log(stage,"telemetry","%.0f%%"%(k*100))
	State.award_mission_data(data)
	if tutorial_on():
		if success: set_tut_step(5)
		else:
			State.tutorial.guide=3
			State.save_game()
	if data>0.05: State.tutorial.lab=true
	if success: State.unlocked=maxi(State.unlocked,mini(3,index+1))
	var dv_margin: float=(Sim.launch(s).dv-run.required)/maxf(run.required,0.1)
	var reserve: float=Sim.reserve_score(dv_margin,s.power_margin,s.twr)
	var reference: float=mission.base_data*(science.multiplier if index==0 else float(mission.multiplier))*float(Sim.balance().science_reference)
	var result_score:=Sim.score({"result":result,"data":data,"reference":reference,"cost":run.actual_cost,"reserve":reserve,"event_ok":run.events_ok,"event_total":run.events_total,"young":run.young,"grant":run.grant})
	if run.grant: add_log(stage,"grant_penalty","−%d"%int(Sim.balance().grant_penalty))
	var outcome:=State.after_mission()
	if outcome.satellite>0: add_log(stage,"satellite","+%.1f %s"%[outcome.satellite,t("МБ","MB")])
	if outcome.grant>0: add_log(stage,"grant","+%.0f %s"%[outcome.grant,t("млн $","$M")])
	report={"mission":index,"difficulty":State.difficulty,"orbit":State.orbit,"design":d.name,"result":result,"data":data,"cost":run.actual_cost,"costs":[s.parts_cost,s.fuel_cost,s.launch_fee,s.get("ops_cost",0.0)],"profit":data*float(Sim.balance().base_rate)-run.actual_cost,"points":result_score.points,"rank":result_score.rank,"roi":result_score.roi,"score_parts":result_score.parts,"satellite":outcome.satellite,"grant":outcome.grant,"satellite_level":State.satellite_level,"logs":logbook.duplicate(true),"player":State.player_name,"advice":mission_advice(result,s,share)}
	State.reports.append(report.duplicate(true))
	if State.reports.size()>30: State.reports.pop_front()
	if not State.sandbox:
		State.records.append(report.duplicate(true))
		# Bound storage while preserving leaders by both score and ROI for each mission/difficulty/orbit.
		var kept:=[]
		var keys:={}
		for r in State.records: keys[record_key(r)]=true
		for key in keys:
			var subset: Array=State.records.filter(func(r): return record_key(r)==key)
			for field in ["points","roi"]:
				subset.sort_custom(func(a,b): return a[field]>b[field])
				for r in subset.slice(0,10):
					if r not in kept: kept.append(r)
		State.records=kept
	State.save_game()
	show_page("report")

func report_ui() -> void:
	panel(t("Звіт місії","Mission report"))
	var outcomes:={"ideal":t("Мета виконана","Objective complete"),"hard":t("Мета виконана з пошкодженням (70% даних)","Objective complete with damage (70% of data)"),"crash":t("Апарат втрачено","Vehicle lost"),"stranded":t("Посадка поза ціллю","Landed outside objective")}
	Audio.play("success" if report.result in ["ideal","hard"] else "fail")
	var badge:=HBoxContainer.new()
	badge.add_theme_constant_override("separation",24)
	var rank_label:=Label.new()
	rank_label.text=str(report.rank)
	rank_label.add_theme_font_size_override("font_size",80)
	rank_label.add_theme_color_override("font_color",{"S":Color("f2c94c"),"A":Color("6fcf7f"),"B":Color("35b6e8")}.get(str(report.rank),MUTED))
	badge.add_child(rank_label)
	var summary:=Label.new()
	summary.text="%d / 100\n%s"%[report.points,outcomes.get(report.result,report.result)]
	summary.add_theme_color_override("font_color",GOLD)
	summary.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	badge.add_child(summary)
	body.add_child(badge)
	var picture:=TextureRect.new()
	var success_result: bool=report.result in ["ideal","hard"]
	if int(report.get("mission",0))==0:
		picture.texture=preload("res://assets/art/screens/mission_thumb_earth.png")
		if not success_result: picture.modulate=Color(0.75,0.45,0.42)
	else:
		picture.texture=preload("res://assets/art/screens/report_success.png") if success_result or report.result=="stranded" else preload("res://assets/art/screens/report_fail.png")
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size=Vector2(0,300)
	body.add_child(picture)
	var advice: Array=report.get("advice",[])
	if not advice.is_empty():
		line(t("Що змінити наступного разу","What to change next time"),CYAN)
		for tip in advice:
			if tip is Array and tip.size()==2: line("→ "+str(tip[0 if State.language=="uk" else 1]),Color("e6eef2"))
	var costs: Array=report.get("costs",[report.cost,0,0])
	if costs.size()<4: costs.append(0.0)
	line(t("Дані +%.1f МБ • витрати %.0f млн $ (деталі %.0f, паливо %.0f, запуск %.0f, керування %.0f)","Data +%.1f MB • cost %.0f $M (parts %.0f, fuel %.0f, launch %.0f, operations %.0f)")%[report.data,report.cost,costs[0],costs[1],costs[2],costs[3]])
	line(t("Прибуток за базовим курсом 100: %.0f млн $ • ROI %.2f","Profit at base rate 100: %.0f $M • ROI %.2f")%[report.get("profit",report.data*100-report.cost),report.roi])
	if report.has("score_parts"):
		var p: Dictionary=report.score_parts
		line(t("Мета %.0f • наука %.0f • ефективність %.0f • запас %.0f • рішення %.0f","Goal %.0f • science %.0f • efficiency %.0f • reserve %.0f • decisions %.0f")%[p.goal,p.science,p.economy,p.reserve,p.events],MUTED)
	if report.get("satellite",0.0)>0: line(t("Супутник рівня %d надіслав %.1f МБ (продайте в лабораторії)","Level %d satellite sent %.1f MB (sell in the laboratory)")%[int(report.satellite_level),report.satellite],CYAN)
	if report.get("grant",0.0)>0: line(t("Екстрений грант %.0f млн $ • наступна місія −10 балів","Emergency grant %.0f $M • next mission −10 points")%report.grant,CYAN)
	if State.sandbox: line(t("Пісочниця • результат не записується","Sandbox • result is not ranked"),MUTED)
	line(t("Хронологія та причини","Timeline and causes"),CYAN)
	for entry in report.logs:
		var text: String=localized(reasons.get(entry.code,[entry.code,entry.code]))
		line("%d / %s %s"%[entry.stage,text,("["+entry.details+"]") if not str(entry.details).is_empty() else ""])
	report_back_button=action(t("Повернутися в хаб","Return to hub"),func(): show_page("hub"))

func toggle_pause() -> void:
	if page not in ["launch","flight","orbit","landing"]: return
	paused=not paused
	if is_instance_valid(lander): lander.active=not paused
	if paused:
		var overlay: Control=preload("res://scenes/screens/PauseOverlay.tscn").instantiate()
		root_ui.add_child(overlay)
		overlay.get_node("Title").text=t("ПАУЗА","PAUSED")
		overlay.get_node("Resume").text=t("Продовжити","Resume")
		overlay.get_node("Abort").text=t("Завершити місію (апарат буде втрачено)","End mission (vehicle is lost)")
		overlay.get_node("Resume").pressed.connect(toggle_pause)
		# Volume can be adjusted mid-mission without leaving the flight.
		overlay.get_node("Panel").size.y=640
		var sound_box:=VBoxContainer.new()
		sound_box.position=Vector2(660,700)
		sound_box.size=Vector2(600,0)
		sound_box.add_theme_constant_override("separation",10)
		overlay.add_child(sound_box)
		sound_controls(sound_box)
		overlay.get_node("Abort").pressed.connect(func():
			paused=false
			add_log({"launch":1,"flight":2,"orbit":2,"landing":3}[page],"abort")
			finish_mission("crash"))
	else:
		var overlay:=root_ui.get_node_or_null("PauseOverlay")
		if overlay: overlay.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if page=="launch" and not paused and event.is_action_pressed("thrust") and not event.is_echo():
		# Each separate press adds speed; holding the key does nothing more.
		launch_boost=minf(3.0,launch_boost+0.45)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_M:
		Audio.toggle_mute()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F11:
		var fullscreen: bool=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if event.is_action_pressed("pause"):
		if page in ["launch","flight","orbit","landing"]: toggle_pause()
		elif page=="hub": show_page("title")
		elif page!="title" and page!="ascent_report": show_page("hub")
	if page=="orbit" and event.is_action_pressed("thrust") and not event.is_echo(): perform_burn()
	if page=="hub" and event.is_action_pressed("interact") and not event.is_echo():
		hub.interact()

func _process(delta: float) -> void:
	elapsed+=delta
	if not paused: State.tick(delta)
	Audio.engine(page=="launch" and not paused and not event_open and is_instance_valid(active_shell) and not run.is_empty() and Sim.launch(run.stats).lift)
	Audio.thruster(page=="landing" and not paused and is_instance_valid(lander) and lander.burning and lander.active)
	update_coach()
	if page=="hub":
		hub.tick(delta)
		if is_instance_valid(active_shell):
			active_shell.get_node("Interaction").text=hub.prompt()
			update_hub_prompt()
		if is_instance_valid(live):
			live.text=(t("Пісочниця","Sandbox") if State.sandbox else "%.0f %s"%[State.money,t("млн $","$M")])+"   %.2f %s   %s %d/3   /   %s"%[State.science,t("МБ","MB"),t("Супутник","Satellite"),State.satellite_level,localized(missions[State.mission].name)]
			if not State.save_error.is_empty(): live.text+="\n"+t("Помилка збереження: ","Save error: ")+State.save_error
	elif page=="lab" and is_instance_valid(live):
		var trend:="↑" if State.rates.size()>1 and State.rate>=State.rates[-2] else "↓"
		live.text=t("1 МБ = %.1f млн $ %s   •   %d с   •   у тебе %.2f МБ і %.0f млн $","1 MB = %.1f $M %s   •   %d s   •   you have %.2f MB and %.0f $M")%[State.rate,trend,ceili(State.rate_left),State.science,State.money]
	elif page in ["launch","flight","orbit"] and not paused and not event_open:
		if page=="launch":
			launch_boost=maxf(0.0,launch_boost-delta*1.6)
		boosting=page=="launch" and launch_boost>0.15
		phase_time+=delta*(speed if page in ["launch","flight"] else 1.0)*((1.0+launch_boost) if page=="launch" else 1.0)
		if page=="launch":
			var ascent:=Sim.launch(run.stats)
			if ascent.lift:
				run.sent+=minf(run.stats.link,run.stats.data_rate)*delta*speed/15.0*0.25
			# Telemetry follows the simulated result: a rocket that cannot lift stays on the pad.
			var climb: float=phase_time/15 if ascent.lift else 0.0
			var sc:=ascent_scale()
			if is_instance_valid(live):
				live.text=t("Висота %.0f км  •  швидкість %.2f км/с","Altitude %.0f km  •  speed %.2f km/s")%[pow(climb,2)*400,minf(climb*float(sc.fill),ascent.dv)]
				live.text+="\n"+t("7,9 км/с — швидкість польоту по орбіті. Ще ~1,6 км/с «з’їдають» тяжіння й повітря під час підйому.","7.9 km/s is the speed of flying in orbit. About 1.6 km/s more is “eaten” by gravity and air on the way up.")
				if is_instance_valid(prompt_bar): prompt_bar.value=launch_boost/3.0*100
			if phase_time>=15: ascent_end()
		elif page=="flight":
			var duration: float=missions[State.mission].duration
			var fraction:=clampf(phase_time/duration,0,1)
			var flight_days: float=fraction*(3 if State.mission>0 else 0.2)
			var day_step: float=delta*speed/duration*(3 if State.mission>0 else 0.2)
			run.stored+=run.stats.data_rate*day_step*run.loss_factor
			if sin(fraction*TAU*3)>0:
				var sent: float=minf(run.stored,run.stats.link*day_step*run.transfer_factor)
				run.stored-=sent
				run.sent+=sent
			run.battery=maxf(0,run.battery-maxf(0,run.stats.active_power-run.stats.supply)*day_step*24)
			if is_instance_valid(live): live.text=t("Доба %.2f  •  паливо %.3f т\nБатарея %.0f Вт·год  •  передано %.2f МБ","Day %.2f  •  fuel %.3f t\nBattery %.0f Wh  •  downlinked %.2f MB")%[flight_days,run.fuel,run.battery,run.sent]
			if fraction>=(event_index+1)*0.2 and event_index<4:
				event_index+=1
				if randf()<float(State.settings().event_chance): open_event()
			if phase_time>=duration and not event_open: coast_end()
		elif page=="orbit":
			# Starts at the left edge (outside the green zone); navigation slows the cursor.
			orbit_cursor=(sin(phase_time*(1.8/(1+State.design.radar*0.18))-PI/2)+1)/2
			if is_instance_valid(live):
				live.text=t("Паливо %.3f т • навігація %d","Fuel %.3f t • navigation %d")%[run.fuel,State.design.radar]
	elif page=="landing" and is_instance_valid(lander):
		landing_prompt_time+=delta
		if is_instance_valid(prompt_node) and (landing_prompt_time>8.0 or (lander.burning and landing_prompt_time>1.5)):
			var fading:=prompt_node
			prompt_node=null
			var fade:=fading.create_tween()
			fade.tween_property(fading,"modulate:a",0.0,0.6)
			fade.tween_callback(fading.queue_free)
		lander.camera_x=clampf(lander.position.x-160,0,maxf(0,lander.terrain[-1].x-320))
		lander.camera_y=minf(0,lander.position.y-65)
		world.position=-Vector2(lander.camera_x,lander.camera_y)
		if is_instance_valid(live):
			live.text=t("Паливо %.3f т","Fuel %.3f t")%lander.fuel
			if State.design.altimeter or State.settings().hud_always:
				live.text+=t(" • h %.0f м • vx %.1f • vy %.1f м/с"," • h %.0f m • vx %.1f • vy %.1f m/s")%[maxf(0,(lander.ground(lander.position.x)-lander.position.y-8)/5),lander.velocity.x,lander.velocity.y]
				# Plain-language touchdown gauge: would landing right now be soft enough?
				var ratio: float=Sim.touchdown_ratio(lander.velocity,lander.angle,lander.limits)
				var height_m: float=maxf(0,(lander.ground(lander.position.x)-lander.position.y-8)/5)
				# The verdict only matters near the surface; high up it would just alarm the player.
				if height_m>6:
					live.text+="   "+t("ще високо","still high")
					live.remove_theme_color_override("font_color")
				else:
					live.text+="   "+(t("✓ безпечно","✓ safe") if ratio<=1.0 else (t("! повільніше","! slow down") if ratio<=1.5 else t("✗ надто швидко","✗ too fast")))
					live.add_theme_color_override("font_color",Color("6fcf7f") if ratio<=1.0 else (GOLD if ratio<=1.5 else Color("e8664f")))
			if lander.resting: live.text+="\n"+t("Контакт із поверхнею","Surface contact")
	queue_redraw()

func stars(offset: float=0) -> void:
	for i in 85:
		var x:=fposmod(i*73.0+offset*(0.15+(i%3)*0.1),320)
		var y:=fposmod(i*43.0+17,180)
		draw_rect(Rect2(x,y,1,1),MUTED if i%4 else INK)

func planet(center: Vector2,radius: float,moon: bool=false) -> void:
	var texture: Texture2D=preload("res://assets/art/moon.png") if moon else preload("res://assets/art/earth.png")
	draw_texture_rect(texture,Rect2((center-Vector2.ONE*radius).round(),Vector2.ONE*radius*2),false)

func rocket(pos: Vector2,burn: bool=false,scale_factor: float=1.0) -> void:
	var body_texture: Texture2D=preload("res://assets/art/rocket.png")
	draw_texture_rect(body_texture,Rect2((pos-Vector2(8,31)*scale_factor).round(),Vector2(16,48)*scale_factor),false)
	if burn: draw_texture_rect(preload("res://assets/art/rocket_exhaust.png"),Rect2((pos+Vector2(-6,8)*scale_factor).round(),Vector2(12,24)*scale_factor),false)

func _draw() -> void:
	draw_rect(Rect2(0,0,320,180),BG)
	stars(-elapsed*1.2)
	match page:
		"hub": pass
		"launch": draw_launch()
		"flight": draw_flight()
		"orbit":
			draw_arc(Vector2(160,97),31,0,TAU,64,Color("3b5267"))
			draw_rect(Rect2(30,120,260,6),Color("203147"))
			draw_rect(Rect2(30+(0.5-orbit_window)*260,120,orbit_window*2*260,6),Color("2e5a3a"))
			draw_rect(Rect2(30+(0.5-orbit_window/2)*260,120,orbit_window*260,6),Color("4caf50"))
			draw_line(Vector2(30+orbit_cursor*260,117),Vector2(30+orbit_cursor*260,129),GOLD,2)
			# The satellite rides the orbit in step with the timing marker.
			var sat_angle: float=PI+orbit_cursor*PI
			var sat_pos: Vector2=Vector2(160,97)+Vector2(cos(sat_angle),sin(sat_angle))*31
			draw_texture_rect(preload("res://assets/art/part_icons/part_15_small_satellite.png"),Rect2((sat_pos-Vector2(6,6)).round(),Vector2(12,12)),false)
		"landing": draw_landing()
		_:
			draw_rect(Rect2(4,3,312,162),Color("121e30"))
			draw_line(Vector2(5,3),Vector2(315,3),Color("3b5267"))

func draw_hub() -> void:
	# Scene-owned sprites replace the original procedural hub.
	pass

func draw_launch() -> void:
	var lift: bool=Sim.launch(run.stats).lift
	var progress:=clampf(phase_time/15,0,1) if lift else 0.0
	var launch: Node2D=$LaunchWorld
	launch.get_node("Atmosphere").modulate.a=1-smoothstep(0.75,1.0,progress)
	# Sky drifts down as the rocket climbs; upper layers fade in on top.
	var sky_shift: float=180-progress*50
	for layer_name in ["Sky1","Sky2","Sky3"]:
		var layer: Sprite2D=launch.get_node("Atmosphere/"+layer_name)
		layer.region_rect.position.y=sky_shift
	launch.get_node("Atmosphere/Sky2").modulate.a=smoothstep(0.2,0.5,progress)
	launch.get_node("Atmosphere/Sky3").modulate.a=smoothstep(0.45,0.75,progress)
	var smoke: AnimatedSprite2D=launch.get_node("Atmosphere/Smoke")
	smoke.visible=lift and progress<0.3
	smoke.modulate.a=clampf(1.0-progress/0.3,0,1)
	if smoke.visible and not smoke.is_playing():
		smoke.sprite_frames.set_animation_loop("smoke_trail",true)
		smoke.play("smoke_trail")
	smoke.position.y=111+progress*120
	for cloud in launch.get_node("Atmosphere/Clouds").get_children():
		# Clouds slide down past the rocket as it climbs through the weather.
		var base_y: float=cloud.get_meta("base_y")
		cloud.position.y=base_y+progress*420
		cloud.visible=cloud.position.y>46 and cloud.position.y<114 and progress<0.6
	var pad: Sprite2D=launch.get_node("Atmosphere/Pad")
	pad.position.y=42.7+progress*120
	pad.region_rect.size.y=clampf((120-pad.position.y)*6,0,464)
	pad.visible=pad.region_rect.size.y>0
	launch.get_node("Rocket/Exhaust").visible=Sim.launch(run.stats).lift
	launch.get_node("Rocket/Exhaust").scale=Vector2.ONE*(0.45 if boosting else 0.33333334)
	# The rocket stays in one piece on screen; staging only affects the maths.
	launch.get_node("SeparatedStage").visible=false
	draw_rect(Rect2(20,130,170,4),Color("203147"))
	var sc:=ascent_scale()
	var velocity:=minf(progress*float(sc.fill),Sim.launch(run.stats).dv)
	draw_rect(Rect2(20,130,clampf(velocity/sc.max,0,1)*170,4),CYAN)
	for value in [sc.marks[0][0],sc.marks[1][0]]:
		var x:float=20+float(value)/sc.max*170
		draw_line(Vector2(x,128),Vector2(x,136),GOLD)


func route_point(points: PackedVector2Array, fraction: float) -> Vector2:
	var length:=0.0
	for i in range(1,points.size()): length+=points[i-1].distance_to(points[i])
	var remaining:=clampf(fraction,0,1)*length
	for i in range(1,points.size()):
		var segment:=points[i-1].distance_to(points[i])
		if remaining<=segment: return points[i-1].lerp(points[i],remaining/maxf(segment,0.001))
		remaining-=segment
	return points[-1]

func draw_flight() -> void:
	var flight: Node2D=$FlightWorld
	var start: Vector2=flight.get_node("Departure").position
	var end: Vector2=flight.get_node("Arrival").position
	var route:=PackedVector2Array([start,end])
	draw_polyline(route,CYAN,1.0)
	var heading: Vector2=(end-start).normalized()
	var normal:=Vector2(-heading.y,heading.x)
	draw_polyline(PackedVector2Array([end-heading*3+normal*2,end,end-heading*3-normal*2]),CYAN,1.0)
	var progress:=clampf(phase_time/float(missions[State.mission].duration),0,1)
	var position_on_route:=route_point(route,progress)
	var tangent:=route_point(route,minf(1,progress+0.001))-route_point(route,maxf(0,progress-0.001))
	var ship: Node2D=flight.get_node("Rocket")
	ship.rotation=tangent.angle()+PI/2
	var body_offset: Vector2=ship.get_node("Body").position*ship.scale
	ship.position=(position_on_route-body_offset.rotated(ship.rotation)).round()
	flight.get_node("Rocket/Exhaust").visible=false
	for i in 4:
		var marker:=route_point(route,(i+1)*0.2)
		draw_rect(Rect2(marker-Vector2.ONE,Vector2(2,2)),GOLD)

func draw_landing() -> void:
	if not is_instance_valid(lander): return
	planet(Vector2(268,51),11)
	var fuel_ratio:float=clampf(lander.fuel/maxf(0.001,run.fuel),0,1)
	draw_rect(Rect2(8,35,70,3),Color("203147"))
	draw_rect(Rect2(8,35,70*fuel_ratio,3),GOLD)
	draw_line(Vector2(180,36),Vector2(310,36),MUTED)
	draw_rect(Rect2(180+lander.pad.position.x/960*130,33,3,6),GOLD)
	draw_rect(Rect2(180+lander.position.x/960*130,33,2,6),CYAN)
