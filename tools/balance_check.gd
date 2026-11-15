extends SceneTree

# Headless balance check (section 13 of the concept):
#   godot --headless --path . -s res://tools/balance_check.gd
# Samples thousands of random designs per mission with the pure Sim module and prints
# expected ROI/profit leaders, the cheapest working rocket and the A/B/C reference designs.
const Sim = preload("res://scripts/sim.gd")
const SITE_EASE := [1.0, 0.86, 0.72, 0.58]

func _init() -> void:
	seed(7)
	var missions: Array = Sim.load_json("res://data/missions.json")
	var parts: Dictionary = Sim.load_json("res://data/parts.json")
	print("== Reference designs, mission 1 (engineer) ==")
	for spec in reference_designs():
		var r := evaluate(spec[1], 0, missions[0], parts, 1)
		print("%s cost %.0f  income@success %.0f  p %.2f  E[profit] %.0f  E[ROI] %.2f" % [spec[0], r.cost, r.income, r.p, r.profit, r.roi])
	for m in 4:
		var pool: Array = []
		var cheapest := 1e9
		var cheapest_design := {}
		for i in 20000:
			var d := random_design(m, i)
			var r := evaluate(d, m, missions[m], parts, 1)
			if r.is_empty(): continue
			r["design"] = d
			pool.append(r)
			if r.income > 0 and r.cost < cheapest:
				cheapest = r.cost
				cheapest_design = d
		var simple := 1e9
		var simple_design := {}
		for r in pool:
			if r.design.quality == 1 and r.p >= 0.6 and r.income > 0 and r.cost < simple and (m == 0 or r.design.legs) and (m < 2 or missions[m].required in r.design.instruments):
				simple = r.cost
				simple_design = r.design
		pool.sort_custom(func(a,b): return a.roi > b.roi)
		print("\n== Mission %d: %d working of 20000; cheapest working rocket %.0f ==" % [m+1, pool.size(), cheapest])
		print("  simple working rocket (standard parts) %.0f: %s" % [simple, describe(simple_design)])
		print("  cheapest: ", describe(cheapest_design))
		print("  top-5 by expected ROI:")
		for r in pool.slice(0, 5):
			print("    ROI %.2f profit %6.0f cost %5.0f p %.2f | %s" % [r.roi, r.profit, r.cost, r.p, describe(r.design)])
		var by_profit := pool.duplicate()
		by_profit.sort_custom(func(a,b): return a.profit > b.profit)
		print("  top-5 by expected profit:")
		for r in by_profit.slice(0, 5):
			print("    profit %6.0f ROI %.2f cost %5.0f p %.2f | %s" % [r.profit, r.roi, r.cost, r.p, describe(r.design)])
		var best := {}
		for r in pool:
			var k := str(r.design.instruments.size())
			if not best.has(k): best[k] = r
		for k in ["1","2","3","4"]:
			if best.has(k): print("  best ROI with %s instrument(s): %.2f (profit %.0f, cost %.0f)" % [k, best[k].roi, best[k].profit, best[k].cost])
	var rate := 100.0
	var total := 0.0
	var low := 999.0
	var high := 0.0
	for i in 100000:
		rate = Sim.next_rate(rate, randf_range(-10, 10))
		total += rate
		low = minf(low, rate)
		high = maxf(high, rate)
	print("\nRate: mean %.2f, min %.1f, max %.1f" % [total/100000, low, high])
	quit()

func reference_designs() -> Array:
	var a := Sim.default_design()
	var b := a.duplicate(true)
	b.instruments = ["camera","seismometer"]
	b.antenna = 1
	b.panels = 2
	b.fuel = 40
	b.batteries = 1
	var c := b.duplicate(true)
	c.instruments = ["camera","seismometer","spectrometer","ice"]
	c.antenna = 2
	c.panels = 4
	c.batteries = 2
	c.engine = 1
	c.fuel = 70
	c.quality = 2
	return [["A light   ", a], ["B balanced", b], ["C heavy   ", c]]

func random_design(m: int, i: int) -> Dictionary:
	var d := Sim.default_design()
	d.stages = 1 if i % 3 else 2
	d.engine = randi_range(0, 1)
	d.engine2 = randi_range(0, 2)
	d.fuel = snappedf(randf_range(15, 80), 1)
	d.fuel2 = snappedf(randf_range(4, 40), 1)
	d.panels = randi_range(0, 5)
	d.batteries = randi_range(0, 3)
	d.antenna = randi_range(0, 2)
	d.radar = randi_range(0, 2)
	d.quality = randi_range(0, 2)
	d.days = [5, 8, 10, 15, 20, 30][randi() % 6]
	d.legs = m > 0 and randf() < 0.6
	d.altimeter = m > 0 and randf() < 0.6
	d.satellite = 1
	var pool := ["camera","seismometer","spectrometer","ice"]
	pool.shuffle()
	d.instruments = pool.slice(0, randi_range(1, 4))
	return d

func evaluate(d: Dictionary, m: int, mission: Dictionary, parts: Dictionary, level: int) -> Dictionary:
	var s := Sim.stats(d, m)
	var required := Sim.required_dv(mission, m, 0)
	if s.twr < 1.0 or s.dv < required * (0.95 if m == 0 else 1.0): return {}
	var fuel := Sim.remaining_fuel(d, s, required)
	var reliability: float = parts.quality[int(d.quality)].reliability
	var p: float
	if m == 0:
		var window := clampf(0.06 + fuel * 0.025 + 0.10, 0.06, 0.38)
		p = reliability * clampf(0.55 + window * 1.6, 0, 0.98)
	else:
		if fuel < 0.03: return {}
		var limits := Sim.landing_limits(d, level)
		var ease: float = SITE_EASE[m] * (1.0 - exp(-fuel / 0.12)) * clampf(sqrt(limits.vertical / 3.0), 0.5, 1.2) * (1.08 if d.altimeter else 1.0)
		p = reliability * clampf(ease, 0, 0.97)
	var science := Sim.science_potential(d, s, mission, m, 0)
	var t := Sim.transfer_share(s, d.days, 1.0, true)
	var success_data: float = Sim.mission_data(science.potential, 0.85, t, 1.0) # mix of ideal and hard outcomes
	var crash_data: float = Sim.mission_data(science.potential, 0.08, t, 1.0)
	var expected: float = p * success_data + (1 - p) * crash_data
	var profit: float = expected * 100 - s.cost
	return {"cost":s.cost,"income":success_data*100,"p":p,"profit":profit,"roi":profit/s.cost}

func describe(d: Dictionary) -> String:
	if d.is_empty(): return "-"
	return "st%d e%d f%.0f/%.0f pan%d bat%d ant%d rad%d q%d %dd %s%s%s" % [d.stages, d.engine, d.fuel, d.fuel2 if d.stages == 2 else 0, d.panels, d.batteries, d.antenna, d.radar, d.quality, d.days, ",".join(d.instruments), " legs" if d.legs else "", " alt" if d.altimeter else ""]
