class_name MissionSim
extends RefCounted

# Pure mission maths. No UI and no global state: every input is passed in.
const G0 := 9.80665
static var cache: Dictionary = {}

static func load_json(path: String):
	if not cache.has(path):
		cache[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return cache[path]

static func balance() -> Dictionary:
	return load_json("res://data/balance.json")

static func difficulty(level: int) -> Dictionary:
	var list: Array = balance().difficulty
	return list[clampi(level,0,list.size()-1)]

static func orbit_info(index: int) -> Dictionary:
	var list: Array = balance().orbits
	return list[clampi(index,0,list.size()-1)]

static func default_design() -> Dictionary:
	# Simple working rocket for mission 1: one stage, one camera, small antenna.
	return {"stages":1,"engine":0,"engine2":2,"fuel":30.0,"fuel2":12.0,"panels":1,"batteries":0,"antenna":0,"radar":0,"instruments":["camera"],"legs":false,"altimeter":false,"satellite":1,"quality":1,"days":10,"name":"Aurora"}

static func stats(d: Dictionary, mission: int = 0) -> Dictionary:
	var p: Dictionary = load_json("res://data/parts.json")
	var e: Dictionary = p.engines[int(d.engine)]
	var a: Dictionary = p.antennas[int(d.antenna)]
	var dry: float = p.structure_mass + a.mass + d.panels * p.panel.mass + d.batteries * p.battery.mass + d.radar * p.radar.mass
	var hardware: float = p.structure_cost + a.cost + d.panels * p.panel.cost + d.batteries * p.battery.cost + d.radar * p.radar.cost
	var base_power: float = p.bus_power + a.power + d.radar * p.radar.power
	var power: float = base_power
	var value := 0.0
	var selected: Array = []
	# Priority follows the order in the design: the last selected instrument shuts down first.
	for id in d.instruments:
		for item in p.instruments:
			if item.id == id:
				selected.append(item)
				dry += item.mass
				hardware += item.cost
				power += item.power
	if mission == 0:
		dry += p.satellite_mass[int(d.satellite)-1]
		hardware += p.satellite_cost[int(d.satellite)-1]
	if d.legs:
		dry += p.legs.mass
		hardware += p.legs.cost
	if d.altimeter:
		dry += p.altimeter.mass
		hardware += p.altimeter.cost
	# Mission length is not free: attitude-control propellant grows with every day of operations.
	var b: Dictionary = balance()
	var days_planned: float = maxf(1, d.days)
	var consumables: float = days_planned * float(b.consumables_per_day)
	dry += consumables
	var fuel: float = d.fuel
	var upper := 0.0
	var dv := 0.0
	var engine_cost: float = e.cost
	if int(d.stages) == 2:
		var e2: Dictionary = p.engines[int(d.engine2)]
		var upper_dry: float = dry + e2.mass + d.fuel2 * p.tank_fraction
		upper = upper_dry + d.fuel2
		dv += e2.isp * G0 * log(upper / upper_dry) / 1000.0
		engine_cost += e2.cost + p.stage_cost
		fuel += d.fuel2
	var lower_dry: float = e.mass + d.fuel * p.tank_fraction + (dry if int(d.stages) == 1 else p.interstage_mass)
	var mass: float = lower_dry + d.fuel + upper
	dv += e.isp * G0 * log(mass / (lower_dry + upper)) / 1000.0
	engine_cost += p.stage_cost
	hardware += engine_cost
	var q: Dictionary = p.quality[int(d.quality)]
	var parts_cost: float = round(hardware * q.price)
	var fuel_cost: float = round(fuel * p.fuel_cost)
	# Ground stations and the control team are paid for each planned day.
	var ops_cost: float = round(days_planned * float(b.ops_cost_per_day))
	var cost: float = parts_cost + fuel_cost + p.launch_fee + ops_cost
	var reliability: float = pow(float(q.reliability), days_planned / float(b.reliability_days))
	# Energy: panels supply continuously, batteries are spread over the planned lifetime.
	var run_days: float = days_planned
	var supply: float = d.panels * p.panel.power
	var energy: float = d.batteries * p.battery.capacity
	var available: float = supply + energy / (run_days * 24.0)
	var active: Array = selected.duplicate()
	var active_power := power
	while active_power > available and not active.is_empty():
		var off: Dictionary = active.pop_back()
		active_power -= off.power
	var generated := 0.0
	var raw := 0.0
	for item in selected: raw += item.data
	for item in active:
		generated += item.data
		value += item.value
	var uptime: float = clampf(available / maxf(base_power, 1), 0, 1)
	var landing_engine: Dictionary = p.engines[int(d.engine2) if int(d.stages)==2 else int(d.engine)]
	return {"mass":mass,"dry":dry,"cost":cost,"parts_cost":parts_cost,"fuel_cost":fuel_cost,"launch_fee":float(p.launch_fee),"ops_cost":ops_cost,"consumables":consumables,"reliability":reliability,"days":days_planned,"hardware":parts_cost,"fuel":fuel,"first_fuel":float(d.fuel),"dv":dv,"twr":e.thrust/(mass*G0),"power":power,"supply":supply,"energy":energy,"available_power":available,"active_power":active_power,"power_margin":(available-active_power)/maxf(active_power,1),"data_rate":generated*uptime,"raw_data_rate":raw,"link":a.rate*uptime,"value":value,"lander_mass":dry+landing_engine.mass*0.5,"thrust":e.thrust,"landing_thrust":landing_engine.thrust,"landing_isp":landing_engine.isp,"active_ids":active.map(func(item): return item.id),"active_count":active.size(),"instrument_count":d.instruments.size()}

static func launch(s: Dictionary) -> Dictionary:
	var target: float = balance().orbit_insertion_dv
	var dv: float = s.dv * (0.9 if s.twr < 1.2 else 1.0)
	return {"lift":s.twr >= 1.0 and s.first_fuel > 0,"orbit":dv >= target*0.95,"unstable":dv < target,"dv":dv}

static func required_dv(mission: Dictionary, mission_index: int, orbit: int) -> float:
	return float(orbit_info(orbit).dv) if mission_index == 0 else float(mission.dv)

static func remaining_fuel(d: Dictionary, s: Dictionary, required: float) -> float:
	# Propellant equivalent of the velocity budget left after ascent and transfer, in tonnes.
	var excess: float = maxf(0, launch(s).dv - required)
	return s.lander_mass * (exp(excess*1000/(s.landing_isp*G0))-1.0)

static func landing_limits(d: Dictionary, level: int = 0) -> Dictionary:
	var b: Dictionary = balance()
	var diff: Dictionary = difficulty(level)
	var p: Dictionary = load_json("res://data/parts.json")
	var factor: float = diff.speed_factor * p.quality[int(d.quality)].tolerance * (1.3 if d.legs else 1.0)
	var angle: float = diff.landing_angle * p.quality[int(d.quality)].tolerance + (6 if d.legs else 0)
	return {"vertical":b.base_vertical*factor,"horizontal":b.base_horizontal*factor,"angle":angle}

static func touchdown(velocity: Vector2, angle: float, limits: Dictionary, on_pad: bool) -> String:
	var ratio: float = touchdown_ratio(velocity, angle, limits)
	if ratio > 1.5:
		return "crash"
	if on_pad:
		return "ideal" if ratio <= 1 else "hard"
	return "rest"

static func touchdown_ratio(velocity: Vector2, angle: float, limits: Dictionary) -> float:
	return maxf(absf(velocity.y)/limits.vertical, maxf(absf(velocity.x)/limits.horizontal, absf(rad_to_deg(wrapf(angle,-PI,PI)))/limits.angle))

static func next_rate(rate: float, step: float) -> float:
	var b: Dictionary = balance()
	return clampf(rate + step + (b.base_rate-rate)*b.rate_pull, b.rate_min, b.rate_max)

# ---------- Science and economy ----------

static func site_multiplier(d: Dictionary, s: Dictionary, mission: Dictionary, mission_index: int, orbit: int) -> float:
	if mission_index == 0:
		# Earth observation is imaging: without a working camera most of the value is lost.
		var imaging: float = 1.0 if mission.required in s.active_ids else float(balance().earth_without_camera)
		return float(orbit_info(orbit).multiplier) * float(balance().satellite_science[int(d.satellite)-1]) * imaging
	return float(mission.multiplier) if mission.required in s.active_ids else 1.0

static func science_potential(d: Dictionary, s: Dictionary, mission: Dictionary, mission_index: int, orbit: int) -> Dictionary:
	# Data = D_base · M · (1 − e^(−V/V0)) · L  before K (result) and T (transfer) are applied.
	var b: Dictionary = balance()
	var p: Dictionary = load_json("res://data/parts.json")
	var multiplier: float = site_multiplier(d, s, mission, mission_index, orbit)
	var saturation: float = 1.0 - exp(-s.value / float(mission.v0))
	var days: float = maxf(1, d.days)
	var lifetime: float = (1.0 - exp(-days / b.lifetime_tau)) * pow(float(p.quality[int(d.quality)].reliability), days / float(b.reliability_days))
	return {"potential":mission.base_data*multiplier*saturation*lifetime,"multiplier":multiplier,"saturation":saturation,"lifetime":lifetime}

static func transfer_share(s: Dictionary, days: float, transfer_factor: float, after_final: bool, link_factor: float = 1.0) -> float:
	# T: share of generated data that fits through the antenna in communication windows.
	var b: Dictionary = balance()
	var generated: float = s.data_rate * maxf(1, days)
	if generated <= 0: return 0.0
	var windows: float = b.window_share * transfer_factor + (b.post_share if after_final else 0.0)
	return clampf(s.link * link_factor * maxf(1, days) * windows / generated, 0, 1)

static func result_factor(result: String, crash_share: float) -> float:
	# K: 1.0 ideal, 0.7 hard/unstable, otherwise only what was downlinked in flight.
	match result:
		"ideal": return 1.0
		"hard": return 0.7
	return clampf(crash_share, 0, 1)

static func mission_data(potential: float, k: float, t: float, loss_factor: float) -> float:
	return maxf(0, potential * k * t * loss_factor)

static func roi(data: float, cost: float) -> float:
	return (data * float(balance().base_rate) - cost) / maxf(cost, 1)

static func band(margin: float) -> float:
	# Full credit for a reasonable 5–15% margin, partial for over-building, none for a deficit.
	var b: Dictionary = balance()
	var low: float = b.reserve_band[0]
	var high: float = b.reserve_band[1]
	if margin <= 0: return 0.0
	if margin < low: return margin / low
	if margin <= high: return 1.0
	return maxf(b.reserve_overbuilt, 1.0 - (margin - high) / 0.5 * (1.0 - b.reserve_overbuilt))

static func reserve_score(dv_margin: float, power_margin: float, twr: float) -> float:
	return 10.0 * (band(dv_margin) + band(power_margin) + band(twr / 1.2 - 1.0)) / 3.0

static func score(p: Dictionary) -> Dictionary:
	# p: result, data, reference, cost, reserve, event_ok, event_total, young, grant
	var b: Dictionary = balance()
	var success: bool = p.result in ["ideal","hard"]
	var goal: float = 35.0 if p.result == "ideal" else (24.5 if p.result == "hard" else 0.0)
	var events := 0.0
	if p.young:
		goal += 15.0 * goal / 35.0
	elif int(p.event_total) > 0:
		events = 15.0 * float(p.event_ok) / float(p.event_total) * (1.0 if success else 0.5)
	else:
		events = 15.0 * goal / 35.0
	var science: float = 15.0 * clampf(p.data / maxf(0.01, p.reference), 0, 1)
	var r: float = roi(p.data, p.cost)
	var economy: float = 25.0 * clampf(r / b.roi_full_score, 0, 1)
	var reserve: float = clampf(p.reserve, 0, 10) if success else 0.0
	var points: int = roundi(clampf(goal + science + economy + reserve + events - (b.grant_penalty if p.grant else 0), 0, 100))
	return {"points":points,"rank":"S" if points>=90 else ("A" if points>=75 else ("B" if points>=55 else "C")),"roi":r,"parts":{"goal":goal,"science":science,"economy":economy,"reserve":reserve,"events":events}}

static func satellite_topup(level: int, money: float, science: float) -> float:
	# Data the insurance satellite sends after a mission; valued at the base rate, sold at the live rate.
	if level <= 0: return 0.0
	var b: Dictionary = balance()
	var net: Dictionary = b.satellite_net[clampi(level,1,3)-1]
	var wealth: float = money + science * b.base_rate
	if wealth >= net.threshold: return 0.0
	return (float(net.restore) - wealth) / b.base_rate

static func needs_grant(level: int, money: float, science: float) -> bool:
	var b: Dictionary = balance()
	return level <= 0 and money + science * b.base_rate < b.cheapest_rocket

static func debris_hit_chance(radar: int, orbit: int) -> float:
	var b: Dictionary = balance()
	return b.debris_p0 * (1.0 - minf(b.debris_radar_max, radar * b.debris_radar_step)) * float(orbit_info(orbit).debris)
