extends RefCounted
# Formula catalogue for the in-game calculator. Every formula is the one the simulation really uses,
# written for players: fields pick parts from lists or take numbers, compute() substitutes them.
const Sim = preload("res://scripts/sim.gd")
const G := 9.81

# tr: Callable(uk, en) -> String; stats/design: the player's current rocket for default values.
static func list(tr: Callable, parts: Dictionary, missions: Array, stats: Dictionary, design: Dictionary, mission: int, orbit: int) -> Array:
	var b: Dictionary = Sim.balance()
	var engines: Array = parts.engines
	var required := func(index: int) -> float: return Sim.required_dv(missions[index], index, orbit)
	var dv_now: float = Sim.launch(stats).dv
	var spare: float = maxf(0.0, dv_now - required.call(mission)) if mission > 0 else 0.0
	var landing_engine: int = int(design.engine2) if int(design.stages) == 2 else int(design.engine)
	var instrument_sum := func(ids: Array, key: String) -> float:
		var total := 0.0
		for item in parts.instruments:
			if item.id in ids: total += float(item[key])
		return total
	return [
		{"id": "twr", "title": tr.call("Чи злетить ракета? (тяга на вагу)", "Will it lift off? (thrust-to-weight)"),
		 "formula": tr.call("Тяга на вагу = тяга двигуна ÷ (маса ракети × 9,81). Більше 1 — злітає, від 1,2 — летить на повну.", "Thrust-to-weight = engine thrust ÷ (rocket mass × 9.81). Above 1 it lifts off, from 1.2 it flies at full speed."),
		 "fields": [
			{"id": "engine", "label": tr.call("Двигун", "Engine"), "type": "engine", "default": int(design.engine)},
			{"id": "mass", "label": tr.call("Маса ракети, т", "Rocket mass, t"), "type": "number", "min": 0.1, "max": 300.0, "step": 0.01, "default": snappedf(stats.mass, 0.01)}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var thrust: float = engines[int(v.engine)].thrust
			var r: float = thrust / (float(v.mass) * G)
			return {"value": r, "text": "%d ÷ (%.2f × 9,81) = %.2f" % [int(thrust), float(v.mass), r],
				"hint": tr.call("Не злетить — візьми сильніший двигун або менше палива." if r < 1.0 else ("Ледь злітає: нижче 1,2 гра забирає 10% запасу швидкості." if r < 1.2 else "Злітає на повну."), "Won't lift off: pick a stronger engine or less fuel." if r < 1.0 else ("Barely lifts: below 1.2 the game takes 10% of the velocity budget." if r < 1.2 else "Lifts off at full speed."))}},
		{"id": "dv", "title": tr.call("Запас швидкості ступені (Δv)", "Stage velocity budget (Δv)"),
		 "formula": tr.call("Δv = Isp × 9,81 × ln(маса до ÷ маса після) ÷ 1000, км/с. «Маса після» — без спаленого палива. Ступені складаються.", "Δv = Isp × 9.81 × ln(mass before ÷ mass after) ÷ 1000, km/s. “Mass after” is without the burnt fuel. Stages add up."),
		 "fields": [
			{"id": "engine", "label": tr.call("Двигун (Isp)", "Engine (Isp)"), "type": "engine", "default": int(design.engine)},
			{"id": "m0", "label": tr.call("Маса до, т", "Mass before, t"), "type": "number", "min": 0.1, "max": 300.0, "step": 0.01, "default": snappedf(stats.mass, 0.01)},
			{"id": "m1", "label": tr.call("Маса після, т", "Mass after, t"), "type": "number", "min": 0.1, "max": 300.0, "step": 0.01, "default": snappedf(maxf(0.1, stats.mass - float(design.fuel)), 0.01)},
			{"id": "mission", "label": tr.call("Ціль", "Target"), "type": "mission", "default": mission}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var isp: float = engines[int(v.engine)].isp
			var m0: float = float(v.m0)
			var m1: float = float(v.m1)
			if m1 >= m0: return {"value": 0.0, "text": tr.call("Маса після має бути меншою за масу до", "Mass after must be smaller than mass before"), "hint": ""}
			var dv: float = isp * G * log(m0 / m1) / 1000.0
			var need: float = required.call(int(v.mission))
			return {"value": dv, "text": "%d × 9,81 × ln(%.2f ÷ %.2f) ÷ 1000 = %.2f %s" % [int(isp), m0, m1, dv, tr.call("км/с", "km/s")],
				"hint": tr.call("Ціль потребує %.1f км/с (разом з усіма ступенями)." % need, "The target needs %.1f km/s (all stages together)." % need)}},
		{"id": "power_have", "title": tr.call("Скільки енергії є", "Power available"),
		 "formula": tr.call("Є = панелі × %d Вт + батареї × %d Вт·год ÷ (діб × 24)." % [int(parts.panel.power), int(parts.battery.capacity)], "Have = panels × %d W + batteries × %d Wh ÷ (days × 24)." % [int(parts.panel.power), int(parts.battery.capacity)]),
		 "fields": [
			{"id": "panels", "label": tr.call("Панелі", "Panels"), "type": "number", "min": 0, "max": 6, "step": 1, "default": int(design.panels)},
			{"id": "batteries", "label": tr.call("Батареї", "Batteries"), "type": "number", "min": 0, "max": 6, "step": 1, "default": int(design.batteries)},
			{"id": "days", "label": tr.call("Доби", "Days"), "type": "number", "min": 1, "max": 90, "step": 1, "default": int(design.days)}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var have: float = float(v.panels) * parts.panel.power + float(v.batteries) * parts.battery.capacity / (float(v.days) * 24.0)
			return {"value": have, "text": "%d × %d + %d × %d ÷ (%d × 24) = %.1f %s" % [int(v.panels), int(parts.panel.power), int(v.batteries), int(parts.battery.capacity), int(v.days), have, tr.call("Вт", "W")],
				"hint": tr.call("Порівняй з формулою «Скільки енергії треба».", "Compare with the “Power needed” formula.")}},
		{"id": "power_need", "title": tr.call("Скільки енергії треба", "Power needed"),
		 "formula": tr.call("Треба = %d Вт (бортові системи) + антена + радар × %d Вт + усі прилади." % [int(parts.bus_power), int(parts.radar.power)], "Need = %d W (bus) + antenna + radar × %d W + all instruments." % [int(parts.bus_power), int(parts.radar.power)]),
		 "fields": [
			{"id": "antenna", "label": tr.call("Антена", "Antenna"), "type": "antenna", "default": int(design.antenna)},
			{"id": "radar", "label": tr.call("Радар", "Radar"), "type": "number", "min": 0, "max": 3, "step": 1, "default": int(design.radar)},
			{"id": "instruments", "label": tr.call("Прилади", "Instruments"), "type": "instruments", "default": design.instruments.duplicate()}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var ant: float = parts.antennas[int(v.antenna)].power
			var inst: float = instrument_sum.call(v.instruments, "power")
			var need: float = parts.bus_power + ant + float(v.radar) * parts.radar.power + inst
			return {"value": need, "text": "%d + %d + %d × %d + %d = %d %s" % [int(parts.bus_power), int(ant), int(v.radar), int(parts.radar.power), int(inst), int(need), tr.call("Вт", "W")],
				"hint": tr.call("Якщо «є» менше, останній вибраний прилад вимкнеться.", "If “have” is lower, the last chosen instrument switches off.")}},
		{"id": "link", "title": tr.call("Чи встигне антена передати дані", "Can the antenna send the data"),
		 "formula": tr.call("Частка = швидкість антени × %.2f ÷ дані приладів за добу (не більше 100%%). Після місії вцілілий апарат додає ще × %.2f." % [float(b.window_share), float(b.post_share)], "Share = antenna rate × %.2f ÷ instrument data per day (up to 100%%). After the mission a surviving craft adds × %.2f." % [float(b.window_share), float(b.post_share)]),
		 "fields": [
			{"id": "antenna", "label": tr.call("Антена", "Antenna"), "type": "antenna", "default": int(design.antenna)},
			{"id": "instruments", "label": tr.call("Прилади", "Instruments"), "type": "instruments", "default": design.instruments.duplicate()}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var rate: float = parts.antennas[int(v.antenna)].rate
			var data: float = instrument_sum.call(v.instruments, "data")
			if data <= 0: return {"value": 0.0, "text": tr.call("Обери хоча б один прилад", "Choose at least one instrument"), "hint": ""}
			var share: float = minf(1.0, rate * float(b.window_share) / data)
			var total: float = minf(1.0, rate * (float(b.window_share) + float(b.post_share)) / data)
			return {"value": share, "text": "%d × %.2f ÷ %d = %d%%" % [int(rate), float(b.window_share), int(data), roundi(share * 100)],
				"hint": tr.call("Разом із передачею після місії: %d%%." % roundi(total * 100), "Including the after-mission downlink: %d%%." % roundi(total * 100))}},
		{"id": "science", "title": tr.call("Скільки науки дадуть прилади", "How much science instruments give"),
		 "formula": tr.call("Результат = 1 − e^(−V ÷ V₀). V — сума «науки» увімкнених приладів, V₀ — складність цілі.", "Result = 1 − e^(−V ÷ V₀). V is the science sum of powered instruments, V₀ is the target's difficulty."),
		 "fields": [
			{"id": "instruments", "label": tr.call("Прилади", "Instruments"), "type": "instruments", "default": design.instruments.duplicate()},
			{"id": "mission", "label": tr.call("Ціль", "Target"), "type": "mission", "default": mission}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var value: float = instrument_sum.call(v.instruments, "value")
			var v0: float = missions[int(v.mission)].v0
			var r: float = 1.0 - exp(-value / v0)
			return {"value": r, "text": "1 − e^(−%.1f ÷ %.1f) = %d%%" % [value, v0, roundi(r * 100)],
				"hint": tr.call("Кожен наступний прилад додає менше, ніж попередній.", "Each extra instrument adds less than the one before.")}},
		{"id": "lifetime", "title": tr.call("Користь від тривалості місії", "Value of mission length"),
		 "formula": tr.call("Користь = (1 − e^(−діб ÷ %.0f)) × надійність^(діб ÷ %.0f)." % [float(b.lifetime_tau), float(b.reliability_days)], "Value = (1 − e^(−days ÷ %.0f)) × reliability^(days ÷ %.0f)." % [float(b.lifetime_tau), float(b.reliability_days)]),
		 "fields": [
			{"id": "days", "label": tr.call("Доби", "Days"), "type": "number", "min": 1, "max": 90, "step": 1, "default": int(design.days)},
			{"id": "quality", "label": tr.call("Клас деталей", "Part class"), "type": "quality", "default": int(design.quality)}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var rel: float = parts.quality[int(v.quality)].reliability
			var d: float = float(v.days)
			var r: float = (1.0 - exp(-d / float(b.lifetime_tau))) * pow(rel, d / float(b.reliability_days))
			return {"value": r, "text": "(1 − e^(−%d ÷ %.0f)) × %.3f^(%d ÷ %.0f) = %d%%" % [int(d), float(b.lifetime_tau), rel, int(d), float(b.reliability_days), roundi(r * 100)],
				"hint": tr.call("Кожна доба ще коштує %d млн $ керування і %.0f кг палива орієнтації." % [int(b.ops_cost_per_day), float(b.consumables_per_day) * 1000], "Each day also costs $%dM of operations and %.0f kg of attitude propellant." % [int(b.ops_cost_per_day), float(b.consumables_per_day) * 1000])}},
		{"id": "landing_fuel", "title": tr.call("Паливо для посадки", "Landing fuel"),
		 "formula": tr.call("Паливо = маса лендера × (e^(зайве Δv × 1000 ÷ (Isp × 9,81)) − 1). Зайве Δv — запас понад потрібне до Місяця.", "Fuel = lander mass × (e^(spare Δv × 1000 ÷ (Isp × 9.81)) − 1). Spare Δv is the budget above the Moon requirement."),
		 "fields": [
			{"id": "lander", "label": tr.call("Маса лендера, т", "Lander mass, t"), "type": "number", "min": 0.1, "max": 10.0, "step": 0.01, "default": snappedf(stats.lander_mass, 0.01)},
			{"id": "engine", "label": tr.call("Двигун посадки (Isp)", "Landing engine (Isp)"), "type": "engine", "default": landing_engine},
			{"id": "spare", "label": tr.call("Зайве Δv, км/с", "Spare Δv, km/s"), "type": "number", "min": 0.0, "max": 10.0, "step": 0.01, "default": snappedf(spare, 0.01)}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var isp: float = engines[int(v.engine)].isp
			var fuel: float = float(v.lander) * (exp(float(v.spare) * 1000.0 / (isp * G)) - 1.0)
			return {"value": fuel, "text": "%.2f × (e^(%.2f × 1000 ÷ (%d × 9,81)) − 1) = %.3f %s" % [float(v.lander), float(v.spare), int(isp), fuel, tr.call("т", "t")],
				"hint": tr.call("Для спокійної посадки бажано від 0,15 т.", "About 0.15 t or more makes landing comfortable.")}},
		{"id": "braking", "title": tr.call("Сила гальмування лендера", "Lander braking"),
		 "formula": tr.call("Гальмування = тяга × 0,012 ÷ (маса лендера + паливо). Має бути більше 1,62 (тяжіння Місяця).", "Braking = thrust × 0.012 ÷ (lander mass + fuel). It must exceed 1.62 (lunar gravity)."),
		 "fields": [
			{"id": "engine", "label": tr.call("Двигун посадки", "Landing engine"), "type": "engine", "default": landing_engine},
			{"id": "lander", "label": tr.call("Маса лендера, т", "Lander mass, t"), "type": "number", "min": 0.1, "max": 10.0, "step": 0.01, "default": snappedf(stats.lander_mass, 0.01)},
			{"id": "fuel", "label": tr.call("Паливо, т", "Fuel, t"), "type": "number", "min": 0.0, "max": 5.0, "step": 0.01, "default": 0.2}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var thrust: float = engines[int(v.engine)].thrust
			var a: float = thrust * 0.012 / (float(v.lander) + float(v.fuel))
			return {"value": a, "text": "%d × 0,012 ÷ (%.2f + %.2f) = %.2f %s" % [int(thrust), float(v.lander), float(v.fuel), a, tr.call("м/с²", "m/s²")],
				"hint": tr.call("Не втримається — падає." if a <= 1.62 else ("Слабко, гальмуй дуже завчасно." if a < 3.0 else "Достатньо для спокійної посадки."), "Cannot hold it: it falls." if a <= 1.62 else ("Weak: brake very early." if a < 3.0 else "Enough for a calm landing."))}},
		{"id": "roi", "title": tr.call("Прибуток і ROI", "Profit and ROI"),
		 "formula": tr.call("Прибуток = дані × 100 − витрати. ROI = прибуток ÷ витрати.", "Profit = data × 100 − cost. ROI = profit ÷ cost."),
		 "fields": [
			{"id": "data", "label": tr.call("Дані, МБ", "Data, MB"), "type": "number", "min": 0.0, "max": 1000.0, "step": 0.1, "default": 50.0},
			{"id": "cost", "label": tr.call("Витрати, млн $", "Cost, $M"), "type": "number", "min": 1.0, "max": 50000.0, "step": 10.0, "default": snappedf(stats.cost, 1.0)}],
		 "compute": func(v: Dictionary) -> Dictionary:
			var profit: float = float(v.data) * float(b.base_rate) - float(v.cost)
			var r: float = profit / float(v.cost)
			return {"value": r, "text": "%.1f × 100 − %d = %d; %d ÷ %d = %.2f" % [float(v.data), int(v.cost), int(profit), int(profit), int(v.cost), r],
				"hint": tr.call("Повні бали за ефективність — від ROI %.1f." % float(b.roi_full_score), "Full efficiency points from ROI %.1f." % float(b.roi_full_score))}},
	]
