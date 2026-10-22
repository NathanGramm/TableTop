class_name EngineMagic
extends EngineCombat
## Spells, innate powers (breath weapons, Channel Divinity) and class features used in combat.

const SLOT_COST := {1: 2, 2: 3, 3: 5, 4: 6, 5: 7}  # Font of Magic: sorcery points per created slot


func cantrip_multiplier(level: int) -> int:
	return 4 if level >= 17 else (3 if level >= 11 else (2 if level >= 5 else 1))


## Resolves who/where a spell affects. Returns {error, targets: [combatant...], cells, point}.
func spell_targets(c: Dictionary, sp: Dictionary, slot: int, target_ids: Array, point) -> Dictionary:
	var tgt: Dictionary = sp.target
	var out := {"error": "", "targets": [], "cells": [], "point": point}
	match tgt.type:
		"self":
			out.targets = [c]
		"point":
			if point == null:
				out.error = "Choose a destination square."
				return out
			var p: Vector2i = point
			if Grid.distance_to_cell(state, c, p) > sp.range:
				out.error = "That square is more than %d ft away." % sp.range
			elif not Grid.line_of_effect(state.map, Grid.center(c), p):
				out.error = "You can't see that square."
			else:
				for f in Grid.footprint(c, p):
					if Grid.cell_at(state.map, f.x, f.y) == Grid.WALL:
						out.error = "That space is blocked."
					for o in combatants():
						if o.id != c.id and not o.dead and Grid.footprint(o).has(f):
							out.error = "That space is occupied."
		"creature":
			var count: int = tgt.count + tgt.get("per_slot", 0) * maxi(0, slot - sp.level)
			if tgt.get("beams", false):
				count = cantrip_multiplier(c.level)
			if target_ids.is_empty():
				out.error = "Choose a target for %s." % sp.name
				return out
			if target_ids.size() > count:
				out.error = "%s can target at most %d creature%s." % [sp.name, count, "" if count == 1 else "s"]
				return out
			var seen := {}
			for tid in target_ids:
				var t := get_c(tid)
				if t.is_empty():
					out.error = "Unknown target."
					return out
				if seen.has(tid) and not tgt.get("repeat", false):
					out.error = "Each target can only be chosen once."
					return out
				seen[tid] = true
				if t.dead and not tgt.get("allow_dead", false):
					out.error = "%s is dead." % t.name
					return out
				var reach: int = maxi(5, sp.range)
				if t.id != c.id and dist(c, t) > reach:
					out.error = "%s is out of range (%d ft, range %d ft)." % [t.name, dist(c, t), reach]
					return out
				if t.id != c.id and Grid.cover(state, c, t) == -1:
					out.error = "No line of effect to %s." % t.name
					return out
				if tgt.has("only_types") and not tgt.only_types.has(t.ctype):
					out.error = "%s only affects %s." % [sp.name, ", ".join(tgt.only_types)]
					return out
				if tgt.get("unarmored", false) and t.armor != "none":
					out.error = "%s is wearing armor." % t.name
					return out
				if tgt.get("exclude_types", []).has(t.ctype):
					out.error = "%s has no effect on %s." % [sp.name, t.ctype]
					return out
				if tgt.get("filter", "any") == "enemy" and not hostile(c, t):
					out.error = "Target an enemy."
					return out
				out.targets.append(t)
			# Rays and darts: spread any leftovers over the chosen targets.
			if tgt.get("repeat", false):
				var i := 0
				var base: Array = out.targets.duplicate()
				while out.targets.size() < count:
					out.targets.append(base[i % base.size()])
					i += 1
		"area":
			var p: Vector2i
			if point == null:
				if tgt.origin == "point":
					out.error = "Choose where to center %s." % sp.name
					return out
				p = c.pos + Vector2i(1, 0)
			else:
				p = point
			if tgt.origin == "point":
				if Grid.distance_to_cell(state, c, p) > sp.range:
					out.error = "That point is more than %d ft away." % sp.range
					return out
				if not Grid.line_of_effect(state.map, Grid.center(c), p):
					out.error = "No line of effect to that point."
					return out
			out.point = p
			out.cells = Grid.area_cells(state, c, tgt, p)
			out.targets = Grid.creatures_in_cells(state, out.cells)
	return out


func cast_error(c: Dictionary, sp: Dictionary, slot: int, opts: Dictionary) -> String:
	if sp.is_empty():
		return "Unknown spell."
	if sp.time == "reaction":
		return "%s is cast automatically as a reaction when it helps." % sp.name
	if has_tag(c, "rage"):
		return "You can't cast spells while raging."
	if c.surprised and in_combat():
		return "%s is surprised and can't act this turn." % c.name
	var time: String = sp.time
	if opts.get("quickened", false):
		if not c.options.has("quickened") or sp.time != "action":
			return "Quickened Spell turns a 1-action spell into a bonus action."
		if res_left(c, "sorcery") < 2:
			return "Quickened Spell costs 2 sorcery points."
		time = "bonus"
	if opts.get("careful", false) and (not c.options.has("careful") or res_left(c, "sorcery") < 1):
		return "Careful Spell costs 1 sorcery point."
	if opts.get("heightened", false):
		if not c.options.has("heightened") or not sp.has("save"):
			return "Heightened Spell needs a spell that forces a saving throw."
		if res_left(c, "sorcery") < 3 + (1 if opts.get("careful", false) else 0) + (2 if opts.get("quickened", false) else 0):
			return "Not enough sorcery points (Heightened Spell costs 3)."
	var err := economy_error(c, time)
	if err != "":
		return err
	if in_combat():
		for prev in c.turn.spells_cast:
			if time == "bonus" and not (prev.time == "action" and prev.cantrip):
				return "After casting a spell this turn, a bonus-action spell isn't allowed (only alongside an action cantrip)."
			if prev.time == "bonus" and not (time == "action" and sp.level == 0):
				return "You cast a bonus-action spell this turn: your other spell must be a cantrip with a casting time of 1 action."
	if sp.level > 0:
		if slot < sp.level:
			return "%s needs a slot of level %d or higher." % [sp.name, sp.level]
		if slots_left(c, slot) <= 0:
			return "No level %d spell slots left." % slot
	return ""


func cast(c: Dictionary, spell_id: String, slot: int, target_ids: Array, point, opts: Dictionary = {}) -> String:
	if c.fdata.has("wild_shape") and not c.features.has("beastSpells"):
		return "%s can't cast spells in Wild Shape." % c.name
	if not _knows_spell(c, spell_id):
		return "%s doesn't have %s prepared." % [c.name, Spells.get_spell(spell_id).get("name", spell_id)]
	var sp := Spells.get_spell(spell_id)
	if spell_id == "eldritch_blast" and c.options.has("eldritch_spear"):
		sp = sp.duplicate(true)
		sp.range = 300
	if c.features.has("spellSniper") and sp.has("attack") and sp.get("range", 0) > 5:
		sp = sp.duplicate(true)
		sp.range *= 2
	if sp.level > 0 and slot <= 0:
		var sc: Dictionary = c.spellcasting
		slot = sc.pact.level if not sc.pact.is_empty() and sc.pact.level >= sp.level and sc.pact.used < sc.pact.max else lowest_slot(c, sp.level)
		if slot == 0:
			return "No spell slots left for %s." % sp.name
	if sp.level == 0:
		slot = 0
	var err := cast_error(c, sp, slot, opts)
	if err != "":
		return err
	var tr := spell_targets(c, sp, slot, target_ids, point)
	if tr.error != "":
		return tr.error
	var time: String = "bonus" if opts.get("quickened", false) else sp.time
	spend_economy(c, time)
	if sp.level > 0:
		spend_slot(c, slot)
	if opts.get("quickened", false):
		c.resources.sorcery.used += 2
	var heightened_id := ""
	if opts.get("heightened", false) and sp.has("save"):
		c.resources.sorcery.used += 3
		for t in tr.targets:
			if hostile(c, t):
				heightened_id = t.id
				break
	var careful_ids := []
	if opts.get("careful", false) and sp.has("save"):
		c.resources.sorcery.used += 1
		for t in tr.targets:
			if t.id != c.id and not hostile(c, t) and careful_ids.size() < maxi(1, mod(c, "cha")):
				careful_ids.append(t.id)
	if in_combat():
		c.turn.spells_cast.append({"time": time, "cantrip": sp.level == 0})
	c.hidden = 0
	if _countered(c, sp, slot):
		return ""
	mage_slayer(c)
	if c.dead or c.hp <= 0 or incapacitated(c):
		return ""
	if sp.get("concentration", false):
		end_concentration(c, " (cast %s)" % sp.name)
		c.concentration = {"spell_id": spell_id, "name": sp.name}
	add_log("spell", "%s casts %s%s%s." % [c.name, sp.name, (" (level %d slot)" % slot) if slot > sp.level else "", " (quickened)" if opts.get("quickened", false) else ""], sp.get("desc", ""), c.name)
	var sc: Dictionary = c.spellcasting
	var sculpt: bool = c.features.has("sculptSpells") and sp.get("school", "") == "evocation"
	if sculpt:
		for t in tr.targets:
			if t.id != c.id and not hostile(c, t) and careful_ids.size() < 1 + sp.level:
				careful_ids.append(t.id)
	resolve_spell(c, sp, slot, tr, {"dc": sc.dc, "attack_bonus": sc.attack_bonus, "mod": mod(c, sc.ability),
		"level": c.level, "spell_id": spell_id, "auto_ids": careful_ids, "sculpt": sculpt, "heightened_id": heightened_id})
	return ""


## Counterspell: an enemy who can see the caster within 60 ft may spend its reaction to stop the spell.
func _countered(c: Dictionary, sp: Dictionary, slot: int) -> bool:
	for t in combatants():
		if not hostile(t, c) or not _knows_spell(t, "counterspell") or not can_react(t) or dist(t, c) > 60 or not can_see(t, c):
			continue
		var lv := lowest_slot(t, maxi(3, slot))
		if lv == 0:
			lv = lowest_slot(t, 3)
		# Auto-reacting creatures don't waste a 3rd-level slot on a cantrip.
		if lv == 0 or not decide(t, "%s is casting %s. Cast Counterspell (level %d slot)?" % [c.name, sp.name, lv], sp.level > 0):
			continue
		spend_slot(t, lv)
		t.reaction_used = true
		add_log("spell", "%s casts Counterspell at %s's %s." % [t.name, c.name, sp.name], "", t.name)
		if slot > lv:
			var dc := 10 + slot
			var r := roll_check(t, t.spellcasting.ability, "", {"quiet": true})
			if r.total < dc:
				add_log("spell", "%s's Counterspell fails (%d vs DC %d)." % [t.name, r.total, dc], r.text, t.name)
				continue
		add_log("spell", "%s's %s is countered!" % [c.name, sp.name])
		return true
	return false


## War Caster: the best damaging single-target cantrip to use for an opportunity attack, or "".
func _war_caster_cantrip(c: Dictionary) -> String:
	if not c.features.has("warCaster") or c.spellcasting.is_empty():
		return ""
	var best := ""
	var best_avg := -1.0
	for sid in c.spellcasting.known:
		var sp := Spells.get_spell(sid)
		if sp.get("level", 1) == 0 and sp.get("time", "") == "action" and sp.get("target", {}).get("type", "") == "creature" \
				and int(sp.target.get("count", 1)) == 1 and not sp.get("damage", []).is_empty():
			var avg := Dice.average(Dice.scale(sp.damage[0].dice, cantrip_multiplier(c.level)))
			if avg > best_avg:
				best_avg = avg
				best = sid
	return best


func war_caster_strike(r: Dictionary, mover: Dictionary) -> bool:
	var cantrip := _war_caster_cantrip(r)
	if cantrip == "" or not decide(r, "%s is leaving %s's reach. Cast %s at it (War Caster)?" % [mover.name, r.name, Spells.get_spell(cantrip).name]):
		return false
	r.reaction_used = true
	add_log("spell", "War Caster: %s casts %s at %s as it leaves!" % [r.name, Spells.get_spell(cantrip).name, mover.name])
	var sc: Dictionary = r.spellcasting
	resolve_spell(r, Spells.get_spell(cantrip), 0, {"targets": [mover], "cells": [], "point": null},
		{"dc": sc.dc, "attack_bonus": sc.attack_bonus, "mod": mod(r, sc.ability), "level": r.level, "spell_id": cantrip, "auto_ids": [], "sculpt": false})
	return true


func find_power(c: Dictionary, power_id: String) -> Dictionary:
	for p in c.powers:
		if p.id == power_id:
			return p
	return {}


func use_power(c: Dictionary, power_id: String, target_ids: Array, point) -> String:
	var pw := find_power(c, power_id)
	if pw.is_empty():
		return "Unknown ability."
	var sp: Dictionary = pw.spell
	if pw.has("resource") and res_left(c, pw.resource) <= 0:
		return "%s has no uses left." % pw.name
	if pw.has("recharge") and not pw.get("charged", true):
		return "%s hasn't recharged." % pw.name
	if pw.get("ritual", false) and in_combat():
		return "%s is a ritual: cast it outside combat." % pw.name
	if c.surprised and in_combat():
		return "%s is surprised and can't act this turn." % c.name
	var err := economy_error(c, sp.time)
	if err != "":
		return err
	var tr := spell_targets(c, sp, 0, target_ids, point)
	if tr.error != "":
		return tr.error
	spend_economy(c, sp.time)
	if pw.has("resource"):
		spend_res(c, pw.resource)
	if pw.has("recharge"):
		pw.charged = false
	c.hidden = 0
	if sp.get("concentration", false):
		end_concentration(c, " (used %s)" % pw.name)
		c.concentration = {"spell_id": "", "name": pw.name}
	add_log("spell", "%s uses %s." % [c.name, pw.name], sp.get("desc", ""), c.name)
	var sc: Dictionary = c.spellcasting
	resolve_spell(c, sp, 0, tr, {"dc": pw.get("dc", sc.get("dc", 10)), "attack_bonus": pw.get("attack_bonus", sc.get("attack_bonus", 0)),
		"mod": mod(c, sc.ability) if not sc.is_empty() else 0, "level": 0, "spell_id": pw.get("spell_id", ""), "auto_ids": [], "sculpt": false})
	return ""


func _damage_specs(sp: Dictionary, slot: int, char_level: int) -> Array:
	var specs := []
	for d in sp.get("damage", []):
		var dice: String = d.dice
		if d.get("cantrip", false):
			dice = Dice.scale(dice, cantrip_multiplier(char_level))
		var extra = (slot - sp.level) / d.get("slot_step", 1)
		if d.has("per_slot") and extra > 0:
			dice = Dice.join([dice, Dice.scale(d.per_slot, extra)])
		specs.append({"dice": dice, "bonus": 0, "type": d.type})
	return specs


## Applies a spell (or power) to its resolved targets. src: dc, attack_bonus, mod, level, spell_id, auto_ids, sculpt.
func resolve_spell(c: Dictionary, sp: Dictionary, slot: int, tr: Dictionary, src: Dictionary) -> void:
	var targets: Array = tr.targets
	var dtype: String = sp.damage[0].type if sp.has("damage") and not sp.damage.is_empty() else ""
	events.append({"kind": "spell", "caster_id": c.id, "name": sp.name, "cells": tr.cells, "target_ids": targets.map(func(t): return t.id), "damage_type": dtype,
		"point": tr.point if tr.point != null else c.pos})
	var special: String = sp.get("special", "")
	if special != "":
		_special(c, sp, slot, tr, src, special)
		return
	var unique := []
	for t in targets:
		if not unique.has(t):
			unique.append(t)
	var specs := _damage_specs(sp, slot, src.level)
	for i in specs.size():
		if sp.damage[i].get("add_mod", false):
			specs[i].bonus += src.mod
	for sx in specs:
		if src.spell_id != "" and c.fdata.get("adept_types", []).has(sx.type):
			sx["min_die"] = 2  # Elemental Adept
	var spell_id: String = src.spell_id
	if spell_id != "" and not specs.is_empty():
		if c.features.has("empoweredEvocation") and sp.get("school", "") == "evocation" and sp.get("classes", []).has("wizard"):
			specs[0].bonus += mod(c, "int")
		var aff: String = c.fdata.get("affinity", "")
		for sx in specs:
			if aff != "" and sx.type == aff:
				sx.bonus += mod(c, "cha")  # Elemental Affinity
				break

	if sp.has("missiles"):
		var ms: Dictionary = sp.missiles
		var dart: Dictionary = Dice.roll(rng, ms.dice)
		var each: int = dart.total + ms.bonus
		var shielded := {}
		for t in unique:
			if _knows_spell(t, "shield") and can_react(t) and lowest_slot(t, 1) > 0 \
					and decide(t, "%s fires Magic Missile at %s. Cast Shield to block the darts (level %d slot)?" % [c.name, t.name, lowest_slot(t, 1)]):
				spend_slot(t, lowest_slot(t, 1))
				t.reaction_used = true
				add_effect({"name": "Shield", "spell_id": "shield", "mods": {"ac_bonus": 5}, "expires_on": {"who": "target", "phase": "start", "count": 1}}, t.id, t.id)
				add_log("spell", "%s casts Shield, blocking the darts." % t.name)
				shielded[t.id] = true
		for t in targets:
			if shielded.has(t.id) or t.dead:
				continue
			deal_damage(t, [{"amount": each, "type": ms.type, "text": "%s+%d" % [dart.text, ms.bonus]}], {"source_id": c.id, "label": "a dart of " + sp.name, "spell": src.spell_id != ""})
	elif sp.has("attack"):
		for t in targets:
			if t.dead:
				continue
			var r := attack_roll(c, t, sp.attack, src.attack_bonus, {"spell": true, "label": sp.name, "spell_adv": sp.get("adv_vs_metal", false) and t.metal_armor,
				"ignore_cover": c.features.has("spellSniper")})
			if hostile(c, t):
				c.turn.attacked_hostile = true
			if not r.hit:
				events.append({"kind": "miss", "id": t.id})
				continue
			var s := specs.duplicate(true)
			if spell_id == "eldritch_blast" and c.options.has("agonizing_blast"):
				s.append({"dice": "", "bonus": mod(c, "cha"), "type": "force"})
			for e in effects_on(t):
				var mk: Dictionary = e.get("mods", {}).get("mark_damage", {})
				if not mk.is_empty() and e.source_id == c.id and not mk.get("weapon_only", false):
					s.append({"dice": mk.dice, "bonus": 0, "type": mk.type})
			deal_damage(t, roll_damage(s, r.crit), {"source_id": c.id, "crit": r.crit, "attack": true, "label": sp.name, "spell": src.spell_id != "",
				"melee": sp.attack == "melee"})
			if t.dead:
				continue
			if sp.has("effect") and sp.effect.on == "hit":
				_spell_effect(c, t, sp, src)
			if sp.has("push") and sp.push.on == "hit":
				push_creature(t, c, sp.push.ft)
			if spell_id == "eldritch_blast" and c.options.has("repelling_blast") and Grid.size_index(t.csize) <= Grid.size_index("large"):
				push_creature(t, c, 10)
		if not targets.is_empty():
			sentinel_strike(c, targets[0])
	elif sp.has("save"):
		var parts := roll_damage(specs, false) if not specs.is_empty() else []
		var origin = null
		if sp.target.type == "area" and sp.target.origin == "point" and tr.point != null:
			origin = [Vector2(tr.point) + Vector2(0.5, 0.5)]
		for t in unique:
			if t.dead:
				continue
			var cover_bonus := 0
			if sp.save.ability == "dex" and not sp.get("ignores_cover", false) and t.id != c.id:
				cover_bonus = maxi(0, Grid.cover(state, c, t, origin))
			var auto: bool = src.auto_ids.has(t.id)
			var s := roll_save(t, sp.save.ability, src.dc, {"magical": true, "poison": sp.get("poison", false), "label": sp.name,
				"auto_success": auto, "bonus": cover_bonus, "charm": sp.get("school", "") == "enchantment",
				"frighten": sp.get("effect", {}).get("conditions", []).has("frightened"),
				"dis": t.id == src.get("heightened_id", ""), "dis_note": "heightened spell", "source_id": c.id, "single_target": unique.size() == 1})
			if not parts.is_empty():
				var mine := parts.duplicate(true)
				var evade: bool = sp.save.ability == "dex" and sp.save.get("half", false) and t.features.has("evasion") and not incapacitated(t)
				if s.success and not evade and sp.save.ability == "dex" and sp.save.get("half", false) and t.features.has("shieldMaster") and t.shield \
						and can_react(t) and decide(t, "%s makes the Dex save against %s. Use Shield Master to take no damage?" % [t.name, sp.name]):
					t.reaction_used = true
					evade = true
					add_log("info", "%s ducks behind a shield (Shield Master)." % t.name)
				var half_on_save: bool = sp.save.get("half", false) or (sp.level == 0 and c.features.has("potentCantrip"))
				if s.success:
					if half_on_save and not (auto and src.sculpt) and not evade:
						for p in mine:
							p.amount = p.amount / 2
					else:
						mine = []
				elif evade:
					for p in mine:
						p.amount = p.amount / 2
				if not mine.is_empty():
					deal_damage(t, mine, {"source_id": c.id, "label": sp.name, "spell": src.spell_id != ""})
			if not s.success and not t.dead:
				if sp.has("effect") and sp.effect.on == "fail":
					_spell_effect(c, t, sp, src)
				if sp.has("push") and sp.push.on == "fail":
					push_creature(t, c, sp.push.ft)
				if sp.get("prone_on_fail", false):
					knock_prone(t)
	if sp.has("heal"):
		var h: Dictionary = sp.heal
		for t in unique:
			var dice: String = h.dice
			if h.has("per_slot") and slot > sp.level:
				dice = Dice.join([dice, Dice.scale(h.per_slot, slot - sp.level)])
			var r := Dice.roll(rng, dice)
			if c.features.has("supremeHealing"):
				r.total = Dice.max_value(dice)
			var amount: int = r.total + (src.mod if h.get("add_mod", false) else 0)
			if t.id != c.id and slot > 0 and c.features.has("blessedHealer") and not src.get("blessed_done", false):
				src["blessed_done"] = true
				heal(c, 2 + slot, "Blessed Healer")
			if c.features.has("discipleOfLife") and slot > 0:
				amount += 2 + slot
			heal(t, amount, sp.name)
	if sp.has("temp_hp"):
		var th: Dictionary = sp.temp_hp
		var amt: int = Dice.roll(rng, th.dice).total + th.bonus + th.per_slot * maxi(0, slot - sp.level)
		for t in unique:
			t.temp_hp = maxi(t.temp_hp, amt)  # temporary hit points don't stack
			add_log("heal", "%s has %d temporary hit points." % [t.name, t.temp_hp])
	if sp.has("max_hp_bonus"):
		var amt: int = sp.max_hp_bonus.amount + sp.max_hp_bonus.per_slot * maxi(0, slot - sp.level)
		for t in unique:
			if has_tag(t, "aid"):
				continue
			t.max_hp += amt
			t.hp += amt
			add_effect({"name": sp.name, "tag": "aid", "spell_id": spell_id, "mods": {"max_hp_bonus": amt}}, c.id, t.id)
			add_log("heal", "%s's hit point maximum increases by %d." % [t.name, amt])
	if sp.has("effect") and sp.effect.on == "always":
		for t in unique:
			_spell_effect(c, t, sp, src)
	if sp.has("self_effect"):
		var tmpl: Dictionary = sp.self_effect.duplicate(true)
		if tmpl.get("mods", {}).has("aura"):
			var aura: Dictionary = tmpl.mods.aura
			aura["dc"] = src.dc
			if sp.has("aura_per_slot") and slot > sp.level:
				aura.damage[0].dice = Dice.join([aura.damage[0].dice, Dice.scale(sp.aura_per_slot, slot - sp.level)])
		tmpl["spell_id"] = spell_id
		tmpl["slot"] = slot
		tmpl["concentration"] = sp.get("concentration", false)
		if tmpl.get("tag", "") != "":
			remove_effects_where(func(e): return e.target_id == c.id and e.get("tag", "") == tmpl.tag)
		if tmpl.get("tag", "") == "darkness":
			tmpl["cells"] = tr.cells
			_darkness_dispels_light(tr.cells)
		add_effect(tmpl, c.id, c.id)


## Darkness dispels the Light cantrip (a spell of 2nd level or lower) wherever their areas overlap.
func _darkness_dispels_light(cells: Array) -> void:
	for o in combatants():
		var l: Dictionary = o.get("light", {})
		if l.get("id", "") == "light" and cells.any(func(p): return Grid.distance_to_cell(state, o, p) <= l.bright + l.dim):
			o.light = {}
			add_log("spell", "The darkness dispels %s's Light." % o.name)


func _spell_effect(c: Dictionary, t: Dictionary, sp: Dictionary, src: Dictionary) -> void:
	var tmpl: Dictionary = sp.effect.duplicate(true)
	tmpl["spell_id"] = src.spell_id
	tmpl["concentration"] = sp.get("concentration", false)
	if tmpl.has("repeat_save") and not tmpl.repeat_save.has("dc"):
		tmpl.repeat_save["dc"] = src.dc
	if tmpl.has("escape") and not tmpl.escape.has("dc"):
		tmpl.escape["dc"] = src.dc
	for cond in tmpl.get("conditions", []):
		if t.cond_immunities.has(cond):
			add_log("info", "%s is immune to being %s." % [t.name, cond])
			return
	add_effect(tmpl, c.id, t.id)
	if tmpl.get("conditions", []).size() > 0:
		add_log("info", "%s is %s." % [t.name, ", ".join(tmpl.conditions)])


func _special(c: Dictionary, sp: Dictionary, slot: int, tr: Dictionary, src: Dictionary, special: String) -> void:
	match special:
		"divineSense":
			var found := combatants().filter(func(t): return t.ctype in ["celestial", "fiend", "undead"] and not t.dead \
				and dist(c, t) <= 60 and Grid.line_of_sight(state, c, t))
			add_log("info", "%s's Divine Sense: %s." % [c.name, ", ".join(found.map(func(t): return "%s (%s, %d ft)" % [t.name, t.ctype, dist(c, t)])) if not found.is_empty() else "no celestials, fiends or undead nearby"])
		"divineIntervention":
			var r := Dice.roll(rng, "1d100")
			if r.total <= c.level:
				add_log("spell", "%s's god answers! (d100 %d ≤ %d) The DM decides how it intervenes." % [c.name, r.total, c.level], r.text, c.name)
			else:
				add_log("spell", "%s's plea goes unanswered (d100 %d > %d)." % [c.name, r.total, c.level], r.text, c.name)
		"stillness":
			var ended := false
			for e in effects_on(c):
				if e.get("conditions", []).has("charmed") or e.get("conditions", []).has("frightened"):
					remove_effect(e, " (Stillness of Mind)")
					ended = true
					break
			if not ended:
				add_log("info", "%s is already calm." % c.name)
		"sleep":
			var pool: int = Dice.roll(rng, Dice.join(["5d8", Dice.scale("2d8", maxi(0, slot - 1))])).total
			add_log("spell", "Sleep rolls %d hit points." % pool)
			var cands: Array = tr.targets.filter(func(t): return t.hp > 0 and not has_cond(t, "unconscious") and t.ctype not in ["undead", "construct"] \
				and not t.traits.has("feyAncestry") and not t.cond_immunities.has("charmed"))
			cands.sort_custom(func(a, b): return a.hp < b.hp)
			for t in cands:
				if t.hp > pool:
					break
				pool -= t.hp
				add_effect({"name": "Asleep", "tag": "sleep", "spell_id": "sleep", "conditions": ["unconscious"], "ends_on_damage": true,
					"expires_on": {"who": "source", "phase": "start", "count": 10}}, c.id, t.id)
				knock_prone(t, true)
				add_log("info", "%s falls asleep." % t.name)
		"mistyStep":
			var from: Vector2i = c.pos
			c.pos = tr.point
			events.append({"kind": "teleport", "id": c.id, "to": c.pos})
			add_log("info", "%s teleports %d ft." % [c.name, Grid.grid_distance(c.pos.x - from.x, c.pos.y - from.y, state.settings.diagonal)])
		"revivify":
			var t: Dictionary = tr.targets[0]
			if not t.dead:
				add_log("info", "%s isn't dead." % t.name)
			elif t.died_round >= 0 and state.combat.round - t.died_round > 10:
				add_log("info", "%s has been dead too long for Revivify." % t.name)
			else:
				t.dead = false
				t.hp = 1
				t.stable = false
				t.death_saves = {"successes": 0, "failures": 0}
				events.append({"kind": "heal", "id": t.id, "amount": 1})
				add_log("heal", "%s returns to life with 1 hit point!" % t.name)
		"raiseDead":
			var t: Dictionary = tr.targets[0]
			if not t.dead:
				add_log("info", "%s isn't dead." % t.name)
			else:
				t.dead = false
				t.hp = 1
				t.stable = false
				t.death_saves = {"successes": 0, "failures": 0}
				events.append({"kind": "heal", "id": t.id, "amount": 1})
				add_log("heal", "%s is raised from the dead with 1 hit point!" % t.name)
		"greaterRestoration":
			var t: Dictionary = tr.targets[0]
			for e in effects_on(t):
				if e.get("conditions", []).has("charmed") or e.get("conditions", []).has("petrified"):
					remove_effect(e)
					add_log("heal", "%s is freed from %s." % [t.name, e.name])
					return
			if t.exhaustion > 0:
				t.exhaustion -= 1
				add_log("heal", "%s's exhaustion eases (level %d)." % [t.name, t.exhaustion])
				return
			add_log("info", "%s had nothing to cure." % t.name)
		"dispel":
			var t: Dictionary = tr.targets[0]
			var n := 0
			for e in effects_on(t):
				if e.has("spell_id") and Spells.get_spell(e.spell_id).get("level", 0) <= 3:
					remove_effect(e, " (dispelled)")
					n += 1
			if n == 0:
				add_log("info", "No spells to dispel on %s." % t.name)
		"restoration":
			var t: Dictionary = tr.targets[0]
			for cond in ["paralyzed", "blinded", "poisoned", "deafened"]:
				for e in effects_on(t):
					if e.get("conditions", []).has(cond):
						remove_effect(e)
						add_log("heal", "%s is no longer %s." % [t.name, cond])
						return
			add_log("info", "%s had nothing to cure." % t.name)
		"turnUndead":
			for t in tr.targets:
				if t.ctype != "undead" or t.dead or not can_see(t, c):
					continue
				var s := roll_save(t, "wis", src.dc, {"magical": true, "label": "Turn Undead"})
				if s.success:
					continue
				var thr: float = c.fdata.get("destroy_undead_cr", -1.0)
				if thr >= 0.0 and t.get("cr", 99.0) <= thr:
					kill(t, "destroyed by Turn Undead")
					continue
				add_effect({"name": "Turned", "tag": "turned", "conditions": ["frightened"], "mods": {"no_reactions": true}, "ends_on_damage": true,
					"expires_on": {"who": "source", "phase": "start", "count": 10}}, c.id, t.id)
				add_log("info", "%s is turned and must flee!" % t.name)
		"preserveLife":
			var pool: int = 5 * c.level
			var allies := combatants().filter(func(t): return not t.dead and not hostile(c, t) and dist(c, t) <= 30 \
				and t.ctype not in ["undead", "construct"] and t.hp < t.max_hp / 2)
			while pool > 0 and not allies.is_empty():
				allies.sort_custom(func(a, b): return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
				var t: Dictionary = allies[0]
				var amount := mini(pool, t.max_hp / 2 - maxi(0, t.hp))
				if amount <= 0:
					allies.pop_front()
					continue
				pool -= heal(t, amount, "Preserve Life")
				allies.pop_front()


# ---------------- Class features ----------------

func use_feature(c: Dictionary, feature: String, target_id: String, amount: int, choice: String) -> String:
	var t := get_c(target_id)
	var err := ""
	match feature:
		"wildShape":
			if not c.features.has("wildShape"): return "No Wild Shape."
			if c.fdata.has("wild_shape"): return "Already in Wild Shape."
			var beast := Monsters.get_monster(choice)
			if beast.get("type", "") != "beast": return "Choose a beast."
			if float(beast.cr) > c.fdata.wild_shape_cr:
				return "%s can only become beasts of CR %s or lower." % [c.name, Monsters.cr_label(c.fdata.wild_shape_cr)]
			err = economy_error(c, "action")
			if err == "" and res_left(c, "wild_shape") <= 0 and not c.features.has("archdruid"): err = "Wild Shape is used up until a short rest."
			if err != "": return err
			spend_economy(c, "action")
			spend_res(c, "wild_shape")  # Archdruid: unlimited, so a failed spend is fine
			start_wild_shape(c, choice)
		"revertShape":
			if not c.fdata.has("wild_shape"): return "Not in Wild Shape."
			err = economy_error(c, "bonus")
			if err != "": return err
			spend_economy(c, "bonus")
			end_wild_shape(c)
		"secondWind":
			if not c.features.has("secondWind"): return "No Second Wind."
			err = economy_error(c, "bonus")
			if err == "" and not spend_res(c, "second_wind"): err = "Second Wind is used up until a short rest."
			if err != "": return err
			spend_economy(c, "bonus")
			var r := Dice.roll(rng, "1d10")
			add_log("info", "%s uses Second Wind." % c.name, r.text + " +%d" % c.level)
			heal(c, r.total + c.level, "Second Wind")
		"actionSurge":
			if not c.features.has("actionSurge"): return "No Action Surge."
			if not in_combat(): return "Action Surge is only useful in combat."
			if c.turn.surged: return "Action Surge can only be used once per turn."
			if not spend_res(c, "action_surge"): return "Action Surge is used up until a short rest."
			c.turn.actions += 1
			c.turn.surged = true
			add_log("info", "%s surges into action! (+1 action)" % c.name)
		"rage":
			if not c.features.has("rage"): return "Can't rage."
			if has_tag(c, "rage"): return "Already raging."
			if c.armor == "heavy": return "Can't rage in heavy armor."
			err = economy_error(c, "bonus")
			if err == "" and res_left(c, "rage") <= 0: err = "No rages left until a long rest."
			if err != "": return err
			spend_economy(c, "bonus")
			spend_res(c, "rage")
			if not c.concentration.is_empty():
				end_concentration(c, " (raging)")
			add_effect({"name": "Rage", "tag": "rage", "mods": {"rage_damage": c.fdata.rage_damage, "resist": ["bludgeoning", "piercing", "slashing"]},
				"expires_on": {"who": "source", "phase": "start", "count": 10}}, c.id, c.id)
			c.took_damage = false
			if choice == "frenzy" and c.features.has("frenzy"):
				c.fdata["frenzied"] = true
				c.fdata["frenzy_turn"] = state.turn_counter
			add_log("info", "%s flies into a %s!" % [c.name, "frenzied rage" if choice == "frenzy" and c.features.has("frenzy") else "rage"])
		"endRage":
			var e := find_effect(c, "rage")
			if e.is_empty(): return "Not raging."
			err = economy_error(c, "bonus")
			if err != "": return err
			spend_economy(c, "bonus")
			remove_effect(e)
		"flurryOfBlows", "patientDefense", "stepOfTheWind":
			if not c.features.has(feature): return "Not available."
			err = economy_error(c, "bonus")
			if err == "" and res_left(c, "ki") <= 0: err = "No ki points left."
			if err == "" and feature == "flurryOfBlows" and not c.turn.attack_action_taken: err = "Flurry of Blows follows the Attack action."
			if err == "" and feature == "stepOfTheWind" and not choice in ["dash", "disengage"]: err = "Choose dash or disengage."
			if err != "": return err
			spend_economy(c, "bonus")
			spend_res(c, "ki")
			match feature:
				"flurryOfBlows":
					c.turn.bonus_attack = {"kind": "flurry", "left": 2}
					add_log("info", "%s unleashes a Flurry of Blows (2 unarmed strikes)." % c.name)
				"patientDefense":
					add_effect({"name": "Dodging", "tag": "dodge", "mods": {"dodge": true}, "expires_on": {"who": "source", "phase": "start", "count": 1}}, c.id, c.id)
					add_log("info", "%s uses Patient Defense (Dodge)." % c.name)
				"stepOfTheWind":
					if choice == "dash":
						c.turn.dashes += 1
					else:
						c.turn.disengaged = true
					add_log("info", "%s uses Step of the Wind (%s)." % [c.name, choice])
		"layOnHands":
			if not c.features.has("layOnHands"): return "No Lay on Hands."
			if t.is_empty() or t.dead: return "Choose a living creature to touch."
			if t.id != c.id and dist(c, t) > 5: return "Lay on Hands needs touch (5 ft)."
			if t.ctype in ["undead", "construct"]: return "Lay on Hands has no effect on undead or constructs."
			var pool := res_left(c, "lay_on_hands")
			var want := amount if amount > 0 else mini(pool, hp_cap(t) - maxi(0, t.hp))
			want = mini(want, pool)
			if want <= 0: return "The pool is empty or the target is unhurt."
			err = economy_error(c, "action")
			if err != "": return err
			spend_economy(c, "action")
			spend_res(c, "lay_on_hands", want)
			heal(t, want, "Lay on Hands")
		"healerKit":
			if not c.features.has("healer"): return "No Healer feat."
			if t.is_empty() or t.dead or t.hp <= 0: return "Choose a living creature with at least 1 HP."
			if t.id != c.id and dist(c, t) > 5: return "The healer's kit needs touch (5 ft)."
			if t.fdata.get("healer_healed", false): return "%s has already been patched up since their last rest." % t.name
			err = economy_error(c, "action")
			if err != "": return err
			spend_economy(c, "action")
			t.fdata["healer_healed"] = true
			var hr := Dice.roll(rng, "1d6")
			heal(t, hr.total + 4 + maxi(1, t.level), "a healer's kit")
		"inspiringLeader":
			if not c.features.has("inspiringLeader"): return "No Inspiring Leader feat."
			if in_combat(): return "Inspiring Leader takes a 10-minute speech: use it outside combat."
			if not spend_res(c, "inspiring_leader"): return "Already used since your last rest."
			var thp: int = c.level + mod(c, "cha")
			var allies := combatants().filter(func(o): return is_alive(o) and not hostile(c, o) and dist(c, o) <= 30)
			allies.sort_custom(func(x, y): return dist(c, x) < dist(c, y))
			for o in allies.slice(0, 6):
				o.temp_hp = maxi(o.temp_hp, thp)
			add_log("heal", "%s's speech inspires %d allies (%d temp HP each)." % [c.name, mini(6, allies.size()), thp])
		"pin":
			if not c.features.has("grappler"): return "No Grappler feat."
			var g := find_effect(t, "grapple") if not t.is_empty() else {}
			if g.is_empty() or g.source_id != c.id: return "Pin a creature you're grappling."
			err = economy_error(c, "action")
			if err != "": return err
			spend_economy(c, "action")
			if _contest_check(c, t, "tries to pin"):
				for who in [t, c]:
					add_effect({"name": "Pinned", "tag": "pin", "conditions": ["restrained"]}, c.id, who.id)
				add_log("info", "%s pins %s: both are restrained until the grapple ends." % [c.name, t.name])
		"bardicInspiration":
			if not c.features.has("bardicInspiration"): return "No Bardic Inspiration."
			if t.is_empty() or t.id == c.id or t.dead or hostile(c, t): return "Choose an ally other than yourself."
			if dist(c, t) > 60: return "%s must be within 60 ft." % t.name
			if t.inspiration_die != "": return "%s already has an inspiration die." % t.name
			err = economy_error(c, "bonus")
			if err == "" and res_left(c, "inspiration") <= 0: err = "No Bardic Inspiration left."
			if err != "": return err
			spend_economy(c, "bonus")
			spend_res(c, "inspiration")
			t.inspiration_die = c.fdata.inspiration_die
			add_log("info", "%s inspires %s (%s)." % [c.name, t.name, t.inspiration_die])
		"sacredWeapon":
			if not c.features.has("sacredWeapon"): return "No Sacred Weapon."
			err = economy_error(c, "action")
			if err == "" and res_left(c, "channel") <= 0: err = "Channel Divinity is used up until a short rest."
			if err != "": return err
			spend_economy(c, "action")
			spend_res(c, "channel")
			add_effect({"name": "Sacred Weapon", "tag": "sacred_weapon", "mods": {"attack_bonus": maxi(1, mod(c, "cha"))},
				"expires_on": {"who": "source", "phase": "start", "count": 10}}, c.id, c.id)
			add_log("info", "%s's weapon blazes with holy light (+%d to attack)." % [c.name, maxi(1, mod(c, "cha"))])
		"createSlot":
			if not c.features.has("fontOfMagic"): return "No Font of Magic."
			var lv := amount
			if not SLOT_COST.has(lv): return "You can create slots of level 1-5."
			if res_left(c, "sorcery") < SLOT_COST[lv]: return "Need %d sorcery points." % SLOT_COST[lv]
			err = economy_error(c, "bonus")
			if err != "": return err
			spend_economy(c, "bonus")
			spend_res(c, "sorcery", SLOT_COST[lv])
			var sc: Dictionary = c.spellcasting
			if sc.slots_used[lv] > 0:
				sc.slots_used[lv] -= 1
			else:
				sc.slots[lv] += 1
				var extra: Dictionary = c.fdata.get("extra_slots", {})
				extra[lv] = extra.get(lv, 0) + 1
				c.fdata["extra_slots"] = extra
			add_log("info", "%s creates a level %d spell slot." % [c.name, lv])
		"convertSlot":
			if not c.features.has("fontOfMagic"): return "No Font of Magic."
			var lv := amount
			if lv < 1 or slots_left(c, lv) <= 0: return "No level %d slot to convert." % lv
			err = economy_error(c, "bonus")
			if err != "": return err
			spend_economy(c, "bonus")
			spend_slot(c, lv)
			var r: Dictionary = c.resources.sorcery
			r.used = maxi(0, r.used - lv)
			add_log("info", "%s converts a level %d slot into %d sorcery points." % [c.name, lv, lv])
		"spiritualWeapon":
			var sw := find_effect(c, "spiritual_weapon")
			if sw.is_empty(): return "No Spiritual Weapon."
			if t.is_empty() or t.dead or t.id == c.id: return "Choose a creature to attack."
			# shortcut: the weapon's square isn't tracked; it can strike anything within 60 ft of you. Track a weapon token if players need positioning.
			if dist(c, t) > 60: return "%s is more than 60 ft away." % t.name
			err = economy_error(c, "bonus")
			if err != "": return err
			spend_economy(c, "bonus")
			var sp: Dictionary = Spells.get_spell("spiritual_weapon").duplicate()
			sp.erase("self_effect")
			var sc: Dictionary = c.spellcasting
			add_log("spell", "%s's spiritual weapon strikes at %s." % [c.name, t.name], "", c.name)
			resolve_spell(c, sp, sw.slot, {"targets": [t], "cells": [], "point": null}, {"dc": sc.dc, "attack_bonus": sc.attack_bonus,
				"mod": mod(c, sc.ability), "level": c.level, "spell_id": "spiritual_weapon", "auto_ids": [], "sculpt": false})
		"endConcentration":
			if c.concentration.is_empty(): return "Not concentrating."
			end_concentration(c, "")
		_:
			return "Unknown feature."
	return ""
