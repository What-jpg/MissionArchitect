extends Node

const Sim = preload("res://scripts/sim.gd")
const SAVE_PATH = "user://mission_architect_v1.json"
const SAVE_VERSION = 3
const SAVE_KEYS = ["money","science","unlocked","research","language","player_name","sandbox","difficulty","satellite_level","campaign","mission","orbit","rate","rate_left","rates","reports","records","designs","design","grant","mission_pending","tutorial","calculations"]
const RESEARCH_KEYS = ["part_spectrometer","part_ice","sat_2","sat_3","mission_1","mission_2","mission_3"]
signal rate_changed

var money := 3500.0
var science := 0.0
var unlocked := 0
var research: Array = []
var language := "uk"
var player_name := "Explorer"
var sandbox := false
var difficulty := 1
var satellite_level := 0
var campaign := false
var mission := 0
var orbit := 0
var rate := 100.0
var rate_left := 30.0
var rates: Array = [100.0]
var reports: Array = []
var records: Array = []
var designs: Array = []
var design: Dictionary = Sim.default_design()
var grant := false
var in_mission := false
var loaded := false
var mission_pending: Dictionary = {}
# First-steps coaching progress: visited mission control / workshop, fresh data waiting for the lab.
var tutorial: Dictionary = {"map":false,"workshop":false,"lab":false}
# Saved formula-calculator results: {formula, title, values, text}.
var calculations: Array = []
var save_error := ""
var restored_from_backup := false

func _ready() -> void:
	load_game()
	recover_interrupted()
	setup_input()

func setup_input() -> void:
	for action in ["left","right","thrust","interact","pause","down","up"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	InputMap.action_erase_events("interact")
	var keys := {"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"thrust":[KEY_W,KEY_UP,KEY_SPACE],"interact":[KEY_E],"pause":[KEY_ESCAPE],"down":[KEY_S,KEY_DOWN],"up":[KEY_W,KEY_UP]}
	for action in keys:
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action,event)
	for pair in [["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0],["thrust",JOY_AXIS_TRIGGER_RIGHT,1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = pair[1]
		event.axis_value = pair[2]
		InputMap.action_add_event(pair[0],event)
	for pair in [["thrust",JOY_BUTTON_A],["pause",JOY_BUTTON_START]]:
		var event := InputEventJoypadButton.new()
		event.button_index = pair[1]
		InputMap.action_add_event(pair[0],event)

func settings() -> Dictionary:
	return Sim.difficulty(difficulty)

func limited() -> bool:
	# "Young astronaut": 2–3 options per category and a single stage. Sandbox lifts every limit.
	return not sandbox and bool(settings().limited_parts)

func tick(delta: float) -> void:
	# The converter rate is frozen during missions and only moves in the complex.
	if in_mission: return
	rate_left -= delta
	if rate_left <= 0:
		rate_left += float(Sim.balance().rate_period)
		rate = Sim.next_rate(rate,randf_range(-float(Sim.balance().rate_step),float(Sim.balance().rate_step)))
		rates.append(rate)
		if rates.size()>10: rates.pop_front()
		rate_changed.emit()
		if campaign: save_game()

func new_game(free_mode: bool, level: int = 1) -> void:
	sandbox = free_mode
	difficulty = clampi(level,0,2)
	money = float(settings().start_money)
	science = 0
	unlocked = 0
	research = []
	satellite_level = 0
	design = fit_design(Sim.default_design())
	reports = []
	records = []
	designs = []
	rate = 100
	rates = [100.0]
	rate_left = float(Sim.balance().rate_period)
	mission = 0
	orbit = 0
	grant = false
	in_mission = false
	mission_pending = {}
	tutorial = {"map":false,"workshop":false,"lab":false}
	calculations = []
	campaign = true
	save_game()

func fit_design(value: Dictionary) -> Dictionary:
	var d := value.duplicate(true)
	if limited():
		d.stages = 1
		d.engine = mini(int(d.engine),1)
		d.antenna = mini(int(d.antenna),1)
		d.radar = mini(int(d.radar),1)
	if int(d.satellite)>1 and not satellite_researched(int(d.satellite)): d.satellite = 1
	d.instruments = d.instruments.filter(func(id): return part_available(id))
	return d

func within_limits(value: Dictionary) -> bool:
	if not limited(): return true
	return int(value.stages)==1 and int(value.engine)<=1 and int(value.antenna)<=1 and int(value.radar)<=1

func satellite_researched(level: int) -> bool:
	return level<=1 or sandbox or ("sat_%d"%level) in research

func save_game() -> void:
	var payload := {}
	for key in SAVE_KEYS:
		payload[key] = get(key)
	payload["version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH+".tmp",FileAccess.WRITE)
	if f == null:
		save_error = "open"
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	# Only a readable, valid main file may replace the backup.
	if FileAccess.file_exists(SAVE_PATH) and sanitize(read_json(SAVE_PATH)) != null:
		if DirAccess.copy_absolute(SAVE_PATH,SAVE_PATH+".bak") != OK:
			save_error = "backup"
	var error := DirAccess.rename_absolute(SAVE_PATH+".tmp",SAVE_PATH)
	if error != OK:
		save_error = "write"
		return
	if save_error != "backup": save_error = ""
	loaded = true

func read_json(path: String):
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func load_game() -> void:
	restored_from_backup = false
	for path in [SAVE_PATH,SAVE_PATH+".bak"]:
		var clean = sanitize(read_json(path))
		if clean == null: continue
		for key in clean: set(key,clean[key])
		loaded = true
		if path.ends_with(".bak"):
			restored_from_backup = true
			save_game()
		return

func number(payload: Dictionary, key: String, low: float, high: float, fallback: float) -> float:
	var value = payload.get(key,fallback)
	if not (value is int or value is float) or not is_finite(float(value)): return fallback
	return clampf(float(value),low,high)

func sanitize(payload):
	# Returns a fully checked state dictionary, or null when the file cannot be trusted.
	if not payload is Dictionary: return null
	var version := int(payload.get("version",0))
	if version < 1 or version > SAVE_VERSION: return null
	for key in ["money","science"]:
		var raw = payload.get(key)
		if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) < 0: return null
	for key in ["mission","unlocked"]:
		var raw = payload.get(key,0)
		if not (raw is int or raw is float) or float(raw) < 0 or float(raw) > 3: return null
	if not valid_design(payload.get("design")): return null
	var clean := {}
	clean.money = float(payload.money)
	clean.science = float(payload.science)
	clean.mission = int(payload.get("mission",0))
	clean.unlocked = int(payload.get("unlocked",0))
	clean.design = payload.design
	clean.research = (payload.get("research",[]) if payload.get("research",[]) is Array else []).filter(func(item): return item is String and item in RESEARCH_KEYS)
	clean.language = "en" if payload.get("language","uk") == "en" else "uk"
	clean.player_name = str(payload.get("player_name","Explorer")).left(24)
	clean.sandbox = payload.get("sandbox",false) == true
	clean.difficulty = int(number(payload,"difficulty",0,2,1))
	# Profiles before v3 had no insurance satellite; earned data and money are preserved.
	clean.satellite_level = int(number(payload,"satellite_level",0,3,0)) if version >= 3 else 0
	clean.campaign = payload.get("campaign",true) == true if version >= 3 else true
	clean.orbit = int(number(payload,"orbit",0,1,0))
	clean.rate = number(payload,"rate",70,130,100)
	clean.rate_left = number(payload,"rate_left",0,30,30)
	var history: Array = (payload.get("rates",[]) if payload.get("rates",[]) is Array else []).filter(func(v): return (v is int or v is float) and float(v) >= 70 and float(v) <= 130)
	clean.rates = history.slice(-10) if not history.is_empty() else [clean.rate]
	for key in ["reports","records"]:
		var list = payload.get(key,[])
		clean[key] = (list if list is Array else []).filter(func(r): return r is Dictionary and r.has("mission") and r.has("points") and r.has("roi") and r.has("design"))
	var saved = payload.get("designs",[])
	clean.designs = (saved if saved is Array else []).filter(func(item): return valid_design(item))
	clean.grant = payload.get("grant",false) == true
	clean.mission_pending = payload.get("mission_pending",{}) if payload.get("mission_pending",{}) is Dictionary else {}
	var calcs = payload.get("calculations",[])
	clean.calculations = (calcs if calcs is Array else []).filter(func(c): return c is Dictionary and c.get("formula") is String and c.get("values") is Dictionary and c.get("text") is String).slice(-50)
	var coach = payload.get("tutorial",{})
	clean.tutorial = {}
	for key in ["map","workshop","lab"]:
		clean.tutorial[key] = coach is Dictionary and coach.get(key,false) == true
	clean.tutorial.done = coach is Dictionary and coach.get("done",false) == true
	var guide = coach.get("guide",0) if coach is Dictionary else 0
	clean.tutorial.guide = clampi(int(guide),0,7) if (guide is int or guide is float) else 0
	return clean

func available(index: int) -> bool:
	return sandbox or (index<=unlocked and (index==0 or ("mission_%d"%index) in research))

func lock_reason(index: int) -> Array:
	# [uk, en] explanation for a locked mission.
	if index>unlocked: return ["завершіть попередню місію","complete the previous mission"]
	return ["дослідіть у лабораторії за %d МБ"%int(Sim.load_json("res://data/missions.json")[index].research),"research it in the laboratory for %d MB"%int(Sim.load_json("res://data/missions.json")[index].research)]

func sell(amount: float) -> void:
	var count := clampf(amount,0,science)
	science -= count
	money += count*rate
	save_game()

func research_cost(key: String) -> float:
	var table: Dictionary = Sim.balance().research
	if table.has(key): return float(table[key])
	if key.begins_with("mission_"): return float(Sim.load_json("res://data/missions.json")[int(key.substr(8))].research)
	return 0.0

func research_ready(key: String) -> bool:
	if sandbox: return true
	if key=="sat_3": return "sat_2" in research
	if key.begins_with("mission_"): return unlocked>=int(key.substr(8))
	return true

func buy_research(key: String) -> bool:
	if key in research: return true
	if not research_ready(key): return false
	var cost := research_cost(key)
	if not sandbox and science<cost: return false
	if not sandbox: science -= cost
	research.append(key)
	save_game()
	return true

func award_mission_data(amount: float) -> void:
	science+=maxf(0,amount)

func install_satellite(level: int) -> bool:
	# One active satellite: a higher level replaces the current one, a lower one never downgrades it.
	if level>satellite_level:
		satellite_level=level
		return true
	return false

func after_mission() -> Dictionary:
	# Checked only after a report, never after purchases: the insurance cannot be farmed by spending.
	var outcome := {"satellite":0.0,"grant":0.0}
	if sandbox: return outcome
	var topup := Sim.satellite_topup(satellite_level,money,science)
	if topup>0:
		science+=topup
		outcome.satellite=topup
	elif Sim.needs_grant(satellite_level,money,science):
		var amount: float=float(Sim.balance().grant)-(money+science*float(Sim.balance().base_rate))
		money+=amount
		grant=true
		outcome.grant=amount
	return outcome

func valid_design(value) -> bool:
	if not value is Dictionary: return false
	var base := Sim.default_design()
	for key in base:
		if not value.has(key): return false
	for key in ["stages","engine","engine2","fuel","fuel2","panels","batteries","antenna","radar","satellite","quality","days"]:
		if not (value[key] is int or value[key] is float): return false
		if not is_finite(float(value[key])): return false
	var limits := {"stages":[1,2],"engine":[0,2],"engine2":[0,2],"fuel":[0,80],"fuel2":[0,40],"panels":[0,6],"batteries":[0,6],"antenna":[0,2],"radar":[0,3],"satellite":[1,3],"quality":[0,2],"days":[1,90]}
	for key in limits:
		if value[key]<limits[key][0] or value[key]>limits[key][1]: return false
		if key not in ["fuel","fuel2"] and float(value[key])!=floorf(float(value[key])): return false
	if not value.instruments is Array or value.instruments.size()>4: return false
	var seen := []
	for item in value.instruments:
		if item not in ["camera","spectrometer","seismometer","ice"] or item in seen: return false
		seen.append(item)
	return value.name is String and value.name.length()<=32 and value.legs is bool and value.altimeter is bool

func export_code() -> String:
	return encode(design)

func encode(value: Dictionary) -> String:
	return "MA1:"+Marshalls.utf8_to_base64(JSON.stringify(value))

func import_code(code: String) -> bool:
	if code.length()>6000 or not code.begins_with("MA1:"): return false
	var value = JSON.parse_string(Marshalls.base64_to_utf8(code.substr(4)))
	if not valid_design(value): return false
	for key in ["stages","engine","engine2","panels","batteries","antenna","radar","satellite","quality","days"]: value[key]=int(value[key])
	if not satellite_researched(int(value.satellite)): return false
	if not within_limits(value): return false
	for id in value.instruments:
		if not part_available(id): return false
	design = value
	save_game()
	return true

func recover_interrupted() -> void:
	if mission_pending.is_empty(): return
	in_mission=false
	var r: Dictionary={"mission":mission_pending.get("mission",mission),"difficulty":difficulty,"orbit":orbit,"design":mission_pending.get("design",design.name),"result":"crash","data":0.0,"cost":mission_pending.get("cost",0),"points":0,"rank":"C","roi":-1.0,"logs":[{"stage":0,"code":"interrupted","details":""}],"player":player_name}
	mission_pending={}
	var outcome := after_mission()
	if outcome.satellite>0: r.logs.append({"stage":0,"code":"satellite","details":"+%.1f D"%outcome.satellite})
	if outcome.grant>0: r.logs.append({"stage":0,"code":"grant","details":"+%.0f $M"%outcome.grant})
	reports.append(r)
	if reports.size()>30: reports.pop_front()
	save_game()

func part_available(id: String) -> bool:
	return sandbox or id in ["camera","seismometer"] or ("part_"+id) in research
