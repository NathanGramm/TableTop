class_name Builder
extends RefCounted
## Turns character definitions (race/class/level/equipment) and monster stat blocks into combatants.
## A character creator only has to produce a definition dictionary like the ones in Pregens.


static func _base(id: String) -> Dictionary:
	return {
		"id": id, "name": "", "kind": "npc", "side": "enemy", "controller": "", "color": "#888888",
		"template_id": "", "description": "", "ctype": "humanoid", "csize": "medium", "pos": Vector2i.ZERO,
		"level": 1, "cr": 0.0, "xp": 0, "class_id": "", "subclass_id": "", "race_id": "",
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10},
		"prof": 2, "save_profs": [], "save_bonus": {}, "skills": {}, "skill_bonus": {}, "joat": false,
		"max_hp": 1, "hp": 1, "temp_hp": 0, "ac": 10, "base_speed": 30, "speeds": {}, "alt": 0, "mounted_on": "", "rider": "",
		"armor": "none", "stealth_dis": false, "metal_armor": false, "shield": false,
		"attacks": [], "attacks_per_action": 1, "multiattack": [], "spellcasting": {}, "powers": [], "legendary": [],
		"resources": {}, "features": [], "traits": [], "fdata": {},
		"resistances": [], "immunities": [], "vulnerabilities": [], "cond_immunities": [],
		"exhaustion": 0, "death_saves": {"successes": 0, "failures": 0}, "stable": false, "dead": false, "died_round": -1,
		"concentration": {}, "initiative": 0, "init_bonus": 0, "surprised": false, "hidden": 0,
		"auto_reactions": true, "reaction_used": false, "turn": Stats.fresh_turn(), "passive_perception": 10,
		"darkvision": 0, "blindsight": 0, "light": {},
		"inspiration_die": "", "used_on_turn": {}, "options": [], "took_damage": false,
		"notes": {}, "equipment": [], "languages": [], "items": [],
	}


static func _res(name: String, max_uses: int, reset: String) -> Dictionary:
	return {"name": name, "max": max_uses, "used": 0, "reset": reset}


# ---------------- Monsters ----------------

static func build_monster(monster_id: String, id: String, mdef: Dictionary = {}) -> Dictionary:
	var m: Dictionary = mdef if not mdef.is_empty() else Monsters.get_monster(monster_id)
	var c := _base(id)
	c.name = m.name
	c.template_id = monster_id
	c.kind = "npc"
	c.side = "enemy"
	c.color = m.get("color", "#888888")
	if m.has("mini"):
		c.mini = m.mini
	c.ctype = m.type
	c.csize = m.size
	c.cr = float(m.cr)
	c.xp = m.get("xp", 0)
	c.description = "%s %s, CR %s" % [m.size.capitalize(), m.type, Monsters.cr_label(c.cr)]
	c.abilities = m.abilities.duplicate()
	c.prof = maxi(2, 2 + (maxi(1, ceili(c.cr)) - 1) / 4)
	c.level = maxi(1, int(c.cr))
	c.save_profs = m.get("save_profs", []).duplicate()
	# Skills in stat blocks are totals; store the difference from the raw modifier.
	for sk in m.get("skills", {}):
		c.skill_bonus[sk] = m.skills[sk] - Stats.mod(c.abilities[Stats.SKILLS[sk]])
	c.max_hp = m.hp
	c.hp = m.hp
	c.fdata["hit_dice"] = m.get("hit_dice", "")
	c.ac = m.ac
	c.base_speed = m.speed
	c.speeds = m.get("speeds", {}).duplicate()
	c.passive_perception = m.get("passive", 10)
	c.darkvision = m.get("darkvision", 0)
	c.blindsight = m.get("blindsight", 0)
	c.traits = m.get("traits", []).duplicate()
	c.resistances = m.get("resistances", []).duplicate()
	c.immunities = m.get("immunities", []).duplicate()
	c.vulnerabilities = m.get("vulnerabilities", []).duplicate()
	c.cond_immunities = m.get("condition_immunities", []).duplicate()
	c.multiattack = m.get("multiattack", []).duplicate()
	for a in m.attacks:
		var p := {
			"id": a.id, "name": a.name, "range": a.range, "to_hit": a.to_hit, "reach": a.get("reach", 5),
			"normal": a.get("normal", 0), "long": a.get("long", 0), "damage": a.damage.duplicate(true),
			"props": a.get("props", []).duplicate(), "ability": "str" if a.range == "melee" else "dex",
			"weapon": not a.get("props", []).has("natural"), "dmg_mod": 0,
		}
		for k in ["on_hit", "hit_effect", "recharge", "standalone"]:
			if a.has(k):
				p[k] = a[k].duplicate(true) if a[k] is Dictionary else a[k]
		if a.has("recharge"):
			p["charged"] = true
		c.attacks.append(p)
	var msc: Dictionary = m.get("spellcasting", {})
	if not msc.is_empty() and not msc.get("spells", []).is_empty():
		var slots := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
		var src_slots: Array = msc.get("slots", [])
		for i in range(1, mini(10, src_slots.size())):
			slots[i] = int(src_slots[i])
		c.spellcasting = {"ability": msc.ability, "dc": msc.dc, "attack_bonus": msc.attack_bonus, "slots": slots,
			"slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pact": {}, "known": msc.spells.duplicate()}
	for pw in m.get("powers", []):
		var power: Dictionary = pw.duplicate(true)
		if power.has("recharge"):
			power["charged"] = true
		if power.has("uses"):
			c.resources[power.id] = _res(power.name, power.uses, "long")
			power["resource"] = power.id
		c.powers.append(power)
	var leg: Dictionary = m.get("legendary", {})
	if not leg.is_empty():
		c.resources["legendary"] = _res("Legendary Actions", leg.count, "turn")  # refilled at the start of its turn
		c.legendary = leg.actions.duplicate(true)
	if m.get("legendary_resistance", 0) > 0:
		c.resources["legendary_resistance"] = _res("Legendary Resistance", m.legendary_resistance, "long")
	if m.has("regen"):
		c.fdata["regen"] = m.regen.duplicate(true)
	return c


## Applies magic items to a monster built from its stat block. Stat blocks already include the
## monster's own gear, so items add on top: a magic weapon improves the matching attack (or adds one).
static func apply_monster_items(c: Dictionary, entries: Array) -> void:
	c.items = entries.duplicate(true)
	for ei in entries.size():
		var e: Dictionary = entries[ei]
		var it := Items.get_item(e.get("id", ""))
		if it.is_empty():
			continue
		var name := Items.display_name(e)
		var base: String = e.get("base", "")
		c.equipment.append(name)
		match it.kind:
			"weapon":
				var found := false
				for a in c.attacks:
					if a.id == base or a.id == base + "_thrown":
						_magic_attack(a, it, name + (" (thrown)" if a.id.ends_with("_thrown") else ""))
						found = true
				if not found and Equipment.WEAPONS.has(base):
					var w: Dictionary = Equipment.WEAPONS[base]
					var ab := "dex" if w.kind == "ranged" else "str"
					if w.props.has("finesse") and c.abilities.dex > c.abilities.str:
						ab = "dex"
					var mod := Stats.mod(c.abilities[ab])
					var a := {"id": "item%d_%s" % [ei, base], "name": w.name, "range": w.kind, "to_hit": mod + c.prof,
						"reach": 10 if w.props.has("reach") else 5, "normal": w.get("range", [0, 0])[0], "long": w.get("range", [0, 0])[1],
						"damage": [{"dice": w.dice, "bonus": mod, "type": w.type}], "props": w.props.duplicate(), "ability": ab,
						"weapon": true, "weapon_id": base, "dmg_mod": mod}
					_magic_attack(a, it, name)
					if w.kind == "melee" and w.props.has("thrown"):
						var thrown: Dictionary = a.duplicate(true)
						thrown.id = a.id + "_thrown"
						thrown.name = name + " (thrown)"
						thrown.range = "ranged"
						a.normal = 0
						a.long = 0
						c.attacks.append(a)
						c.attacks.append(thrown)
					else:
						c.attacks.append(a)
			"armor", "shield", "wondrous":
				c.ac += int(it.get("ac_bonus", 0))
		var sb: int = it.get("save_bonus", 0)
		if sb != 0:
			for k in Stats.ABILITIES:
				c.save_bonus[k] = c.save_bonus.get(k, 0) + sb
		for t in it.get("resist", []) + ([base] if it.get("base", "") == "damage_type" else []):
			if Stats.DAMAGE_TYPES.has(t) and not c.resistances.has(t):
				c.resistances.append(t)
		for k in it.get("ability_min", {}):
			c.abilities[k] = maxi(c.abilities[k], int(it.ability_min[k]))
		c.base_speed = maxi(c.base_speed, int(it.get("speed_min", 0)))


static func _magic_attack(a: Dictionary, it: Dictionary, name: String) -> void:
	a.name = name
	a.to_hit += int(it.get("attack_bonus", 0))
	if not a.damage.is_empty():
		a.damage[0].bonus = a.damage[0].get("bonus", 0) + int(it.get("damage_bonus", 0))
	for x in it.get("extra_damage", []):
		a.damage.append({"dice": x.dice, "bonus": 0, "type": x.type})
	a["magical"] = true


# ---------------- Characters ----------------

static func build_character(def: Dictionary, level: int, id: String) -> Dictionary:
	var cls: Dictionary = Classes.get_class_def(def["class"])
	var race: Dictionary = Classes.RACES.get(def.race, Classes.RACES.human)
	var lv := clampi(level, 1, 20)
	# Class levels: the first class gets whatever def.classes leaves over.
	var levels := Creator.class_levels(def.merged({"level": lv}, true))
	var plv := clampi(levels[def["class"]], 1, lv)
	levels[def["class"]] = plv
	var lv_of := func(k: String) -> int: return levels.get(k, 0)
	var c := _base(id)
	c.name = def.name
	c.kind = "pc"
	c.side = "party"
	c.color = def.get("color", "#3498db")
	c.mini_paint = def.get("mini_paint", false)
	c.template_id = def["class"]
	c.class_id = def["class"]
	c.subclass_id = cls.subclass.id if plv >= cls.subclass.level else ""
	c.race_id = def.race
	c.level = lv
	c.csize = race.size
	c.prof = Classes.prof_bonus(lv)
	c.options = def.get("options", []).duplicate()
	c.description = "Level %d %s %s%s" % [lv, race.name, cls.name, (" (%s)" % cls.subclass.name) if c.subclass_id != "" else ""]
	if levels.size() > 1:
		c.description += " / " + " / ".join(levels.keys().slice(1).map(func(k): return "%s %d" % [Classes.ALL[k].name, levels[k]]))
	c.fdata["class_levels"] = levels

	# Ability scores: base + racial + ASIs (capped at 20).
	var ab: Dictionary = {}
	for k in Stats.ABILITIES:
		ab[k] = int(def.abilities.get(k, 10))
	for k in race.asi:
		ab[k] += race.asi[k]
	for k in def.get("flex_asi", []):
		ab[k] += 1
	for asi_level in Creator.asi_char_levels(def.merged({"level": lv}, true)):
		if lv < asi_level:
			continue
		var inc: Dictionary = Creator.asi_at(def, asi_level)
		if inc.is_empty():
			var primary: String = cls.get("primary", _primary(def["class"]))
			inc = {primary: 2}
		inc = Creator.asi_scores(inc)
		for k in inc:
			ab[k] = mini(20, ab[k] + int(inc[k]))
	if lv_of.call("barbarian") >= 20:
		for k in ["str", "con"]:
			ab[k] = mini(24, ab[k] + 4)  # Primal Champion
	var feats := Creator.feats_of(def, lv)
	var feat_picks := func(f: String) -> Array: return Creator.feat_entry(def, lv, f).get("picks", [])
	# Magic items.
	var items := []
	for e in def.get("items", []):
		var it := Items.get_item(e.get("id", ""))
		if not it.is_empty():
			items.append({"entry": e, "item": it, "base": e.get("base", ""), "name": Items.display_name(e)})
	for r in items:
		for k in r.item.get("ability_min", {}):
			ab[k] = maxi(ab[k], int(r.item.ability_min[k]))
	c.items = def.get("items", []).duplicate(true)
	c.abilities = ab
	c["def"] = def.duplicate(true)
	c.def["level"] = lv
	var m := func(k: String) -> int: return Stats.mod(ab[k])

	c.save_profs = cls.saves.duplicate()
	var res_ab: String = Creator.feat_entry(def, lv, "resilient").get("ability", "")
	if res_ab != "" and not c.save_profs.has(res_ab):
		c.save_profs.append(res_ab)
	c.traits = race.traits.duplicate()
	c.darkvision = race.get("darkvision", 0)
	c.resistances = race.get("resist", []).duplicate()
	for sk in def.get("skills", []) + Creator.background_skills(def) + def.get("race_skills", []):
		c.skills[sk] = 1
	for sk in race.get("skills", []):
		c.skills[sk] = 1
	for sk in feat_picks.call("skilled"):
		c.skills[sk] = maxi(1, c.skills.get(sk, 0))
	for sk in def.get("expertise", []):
		c.skills[sk] = 2

	# Hit points: max at 1st level, then the rolled value (def.hp_rolls, level -> roll) or the average.
	# Levels go first class first, then def.classes in order, each with its own die.
	var hd: int = cls.hit_die
	var hit_dice := Creator.level_dice(def.merged({"level": lv, "class": def["class"]}, true))
	var rolls: Dictionary = def.get("hp_rolls", {})
	var hp: int = hd + m.call("con")
	for l in range(2, lv + 1):
		hp += int(rolls.get(str(l), hit_dice[l - 1] / 2 + 1)) + m.call("con")
		hd = maxi(hd, hit_dice[l - 1])
	if c.traits.has("dwarvenToughness"):
		hp += lv
	if lv_of.call("sorcerer") >= 1:
		hp += lv_of.call("sorcerer")  # Draconic Resilience
	c.max_hp = maxi(lv, hp)
	c.hp = c.max_hp
	# shortcut: one pool of the largest die for multiclass hit dice; track per-die pools if short rests need it.
	c.resources["hit_dice"] = _res("Hit Dice (d%d)" % hd, lv, "long")
	c.fdata["hit_die"] = hd

	c.languages = race.get("languages", ["Common"]).duplicate()
	c.languages.append_array(feat_picks.call("linguist"))

	# Armor class.
	var armor_id: String = def.get("armor", "")
	c.shield = def.get("shield", false)
	var magic_ac := 0
	var magic_armor := ""
	var magic_shield := ""
	var weapon_list: Array = def.get("weapons", []).duplicate()
	var pact_weapon: String = def.get("pact_weapon", "") if c.options.has("pact_blade") else ""
	if pact_weapon != "" and not weapon_list.has(pact_weapon):
		weapon_list.append(pact_weapon)
	for r in items:
		match r.item.kind:
			"armor":
				if Equipment.ARMOR.has(r.base):
					armor_id = r.base
					magic_armor = r.name
					magic_ac += int(r.item.get("ac_bonus", 0))
			"shield":
				c.shield = true
				magic_shield = r.name
				magic_ac += int(r.item.get("ac_bonus", 0))
				c["shield_ac"] = 2 + int(r.item.get("ac_bonus", 0))
			"weapon":
				weapon_list.erase(r.base)  # the magic weapon replaces a mundane one of the same kind
			"wondrous", "potion", "component":
				pass
	var armor: Dictionary = Equipment.ARMOR.get(armor_id, {})
	if not armor.is_empty():
		c.equipment.append(magic_armor if magic_armor != "" else "%s armor" % armor.name)
	if c.shield:
		c.equipment.append(magic_shield if magic_shield != "" else "Shield")
	for r in items:
		if r.item.kind in ["weapon", "wondrous", "potion", "component"]:
			c.equipment.append(r.name)
	# shortcut: wondrous items and components count as weightless; most weigh a pound or less.
	var lb: float = Equipment.WEIGHT.get(armor_id, 0) + (Equipment.WEIGHT.shield if c.shield else 0)
	for wid in weapon_list + items.filter(func(r): return r.item.kind == "weapon").map(func(r): return r.base):
		lb += Equipment.WEIGHT.get(wid, 0)
	c["gear_lb"] = lb + Equipment.WEIGHT.potion * items.filter(func(r): return r.item.kind == "potion").size()
	# What's in hand (used when the DM tracks hands): the first weapon, then a shield or a free hand.
	var main: String = def.get("weapons", [""])[0] if not def.get("weapons", []).is_empty() else ""
	c["hands"] = [main, main if Equipment.WEAPONS.get(main, {}).get("props", []).has("twoHanded") else ("shield" if c.shield else "")]
	var counts := {}
	for wid in weapon_list:
		counts[wid] = counts.get(wid, 0) + 1
	for wid in counts:
		if Equipment.WEAPONS.has(wid):
			c.equipment.append(("%s ×%d" % [Equipment.WEAPONS[wid].name, counts[wid]]) if counts[wid] > 1 else Equipment.WEAPONS[wid].name)
	var ac: int = 10 + m.call("dex")
	if not armor.is_empty():
		c.armor = armor.type
		c.stealth_dis = armor.stealth_dis
		c.metal_armor = armor.metal
		var dex_cap: int = armor.dex_cap
		if feats.has("mediumArmorMaster") and armor.type == "medium":
			dex_cap = 3
			c.stealth_dis = false
		ac = armor.ac + (m.call("dex") if dex_cap < 0 else mini(m.call("dex"), dex_cap))
	else:
		# Unarmored Defense from any class; they don't stack, so take the best.
		if levels.has("barbarian"):
			ac = maxi(ac, 10 + m.call("dex") + m.call("con"))
		if levels.has("monk") and not c.shield:
			ac = maxi(ac, 10 + m.call("dex") + m.call("wis"))
		if levels.has("sorcerer"):
			ac = maxi(ac, 13 + m.call("dex"))
	if c.shield:
		ac += 2
	if feats.has("dualWielder") and not c.shield and weapon_list.filter(func(w): return Equipment.WEAPONS.has(w) and Equipment.WEAPONS[w].kind == "melee" and not Equipment.WEAPONS[w].props.has("twoHanded")).size() >= 2:
		ac += 1
	var style: String = def.get("style", "")
	var style_from := Creator.style_class(def.merged({"level": lv}, true))
	var has_style: bool = style_from != ""

	if not has_style:
		style = ""
	var styles := [style]
	if lv_of.call("fighter") >= 10 and def.get("style2", "") != "":
		styles.append(def.style2)  # Additional Fighting Style
	if styles.has("defense") and not armor.is_empty():
		ac += 1
	ac += magic_ac
	for r in items:
		if r.item.kind == "wondrous":
			ac += int(r.item.get("ac_bonus", 0))
			if armor.is_empty() and not c.shield:
				ac += int(r.item.get("ac_unarmored_bonus", 0))
			var sb: int = r.item.get("save_bonus", 0)
			if sb != 0:
				for k in Stats.ABILITIES:
					c.save_bonus[k] = c.save_bonus.get(k, 0) + sb
		for t in r.item.get("resist", []):
			if not c.resistances.has(t):
				c.resistances.append(t)
		if r.item.get("base", "") == "damage_type" and Stats.DAMAGE_TYPES.has(r.base) and not c.resistances.has(r.base):
			c.resistances.append(r.base)
	c.ac = ac
	for st in styles:
		if st != "":
			c.options.append(st)

	# Speed.
	var speed: int = race.speed
	if c.armor == "heavy" and armor.get("str", 0) > ab.str and not c.traits.has("heavyArmorSpeed"):
		speed -= 10
	if lv_of.call("barbarian") >= 5 and c.armor != "heavy":
		speed += 10
	if lv_of.call("monk") >= 2 and armor.is_empty() and not c.shield:
		speed += [0, 0, 10, 10, 10, 10, 15, 15, 15, 15, 20, 20, 20, 20, 25, 25, 25, 25, 30, 30, 30][lv_of.call("monk")]
	for r in items:
		var smin: int = r.item.get("speed_min", 0)
		if smin > 0:
			speed = maxi(speed, smin)
	c.base_speed = speed

	# Class features and resources.
	_apply_class_features(c, def, plv, m)
	var weapon_profs: Array = cls.weapons.duplicate()
	for k in levels.keys().slice(1):
		# Extra Attack from two classes doesn't stack.
		var apa: int = c.attacks_per_action
		_apply_class_features(c, def.merged({"class": k}, true), levels[k], m)
		c.attacks_per_action = maxi(apa, c.attacks_per_action)
		weapon_profs.append_array(Creator.MULTICLASS_PROFS[k][1])

	# Weapons.
	weapon_profs.append_array(race.get("weapons", []))
	if pact_weapon != "":
		weapon_profs.append(pact_weapon)
	weapon_profs.append_array(feat_picks.call("weaponMaster"))
	var weapons: Array = weapon_list
	var entries := []  # [weapon id, magic item record or {}]
	for wid in weapons:
		entries.append([wid, {}])
	for r in items:
		if r.item.kind == "weapon" and Equipment.WEAPONS.has(r.base):
			entries.append([r.base, r])
			weapons = weapons + [r.base]
	var melee_count := 0
	for wid in weapons:
		if Equipment.WEAPONS.has(wid) and Equipment.WEAPONS[wid].kind == "melee":
			melee_count += 1
	var seen := {}
	for ei in entries.size():
		var wid: String = entries[ei][0]
		var magic: Dictionary = entries[ei][1]
		var key: String = wid if magic.is_empty() else "item%d" % ei
		if seen.has(key) or not Equipment.WEAPONS.has(wid):
			continue
		seen[key] = true
		var w: Dictionary = Equipment.WEAPONS[wid]
		var proficient: bool = weapon_profs.has(w.cat) or weapon_profs.has(wid)
		var monk_weapon: bool = levels.has("monk") and Equipment.is_monk_weapon(wid)
		var ability := "dex" if w.kind == "ranged" else "str"
		if w.props.has("finesse") or monk_weapon:
			ability = "dex" if m.call("dex") > m.call("str") else "str"
		var amod: int = m.call(ability)
		var to_hit: int = amod + (c.prof if proficient else 0)
		var dice: String = w.dice
		var two_handed_grip: bool = w.props.has("twoHanded")
		if w.props.has("versatile") and not c.shield and melee_count == 1:
			dice = w.versatile
			two_handed_grip = true
		if monk_weapon:
			dice = _bigger_die(dice, c.fdata.get("martial_arts_die", "1d4"))
		var bonus := amod
		if styles.has("dueling") and w.kind == "melee" and not two_handed_grip:
			bonus += 2
		var props: Array = w.props.duplicate()
		if monk_weapon:
			props.append("monk")
		var base := {
			"id": wid, "name": w.name, "range": w.kind, "to_hit": to_hit + (2 if styles.has("archery") and w.kind == "ranged" else 0),
			"reach": 10 if w.props.has("reach") else 5, "normal": w.get("range", [0, 0])[0], "long": w.get("range", [0, 0])[1],
			"damage": [{"dice": dice, "bonus": bonus, "type": w.type}], "props": props, "ability": ability,
			"weapon": true, "weapon_id": wid, "dmg_mod": amod, "proficient": proficient,
			"crit_range": c.fdata.get("crit_range", 20),
		}
		if not magic.is_empty():
			var ab_: int = magic.item.get("attack_bonus", 0)
			var db_: int = magic.item.get("damage_bonus", 0)
			base.id = "item%d_%s" % [ei, wid]
			base.name = magic.name
			base.to_hit += ab_
			base.damage[0].bonus += db_
			base["magic_bonus"] = db_
			for x in magic.item.get("extra_damage", []):
				base.damage.append({"dice": x.dice, "bonus": 0, "type": x.type})
			base["magical"] = true
		if wid == pact_weapon and magic.is_empty():
			base.name = "Pact " + w.name
			base["magical"] = true
		if styles.has("great_weapon") and w.kind == "melee" and two_handed_grip:
			base["reroll_low"] = 2
		if levels.has("druid") and wid in ["club", "quarterstaff"]:
			var wm: int = m.call("wis")
			base["shillelagh"] = {"to_hit": wm + c.prof, "dice": "1d8", "bonus": wm, "dmg_mod": wm}
		if w.kind == "melee" and w.props.has("thrown"):
			var thrown := base.duplicate(true)
			thrown.id = base.id + "_thrown"
			thrown.name = base.name + " (thrown)"
			thrown.range = "ranged"
			thrown.damage[0] = {"dice": w.dice, "bonus": amod + base.get("magic_bonus", 0), "type": w.type}
			thrown.erase("reroll_low")
			thrown.erase("shillelagh")
			base.normal = 0
			base.long = 0
			c.attacks.append(base)
			c.attacks.append(thrown)
		else:
			c.attacks.append(base)
	c.fdata["light_melee_count"] = 0
	for wid in weapons:
		if Equipment.WEAPONS.has(wid) and Equipment.WEAPONS[wid].kind == "melee" and (Equipment.WEAPONS[wid].props.has("light") \
				or (feats.has("dualWielder") and not Equipment.WEAPONS[wid].props.has("twoHanded"))):
			c.fdata.light_melee_count += 1
	# Unarmed strike.
	var unarmed_ability := "str"
	var unarmed_die := ""
	if levels.has("monk"):
		unarmed_ability = "dex" if m.call("dex") > m.call("str") else "str"
		unarmed_die = c.fdata.martial_arts_die
	if feats.has("tavernBrawler") and unarmed_die == "":
		unarmed_die = "1d4"
	var um: int = m.call(unarmed_ability)
	c.attacks.append({
		"id": "unarmed", "name": "Unarmed Strike", "range": "melee", "to_hit": um + c.prof, "reach": 5, "normal": 0, "long": 0,
		"damage": [{"dice": unarmed_die, "bonus": (um if unarmed_die != "" else 1 + um), "type": "bludgeoning"}],
		"props": ["unarmed"] + (["monk"] if levels.has("monk") else []), "ability": unarmed_ability,
		"magical": lv_of.call("monk") >= 6,  # Ki-Empowered Strikes
		"weapon": true, "weapon_id": "unarmed", "dmg_mod": um, "proficient": true, "crit_range": c.fdata.get("crit_range", 20),
	})

	# Spellcasting.
	if levels.size() > 1:
		_apply_multiclass_spellcasting(c, def, levels, lv, m)
	elif cls.caster != "":
		_apply_spellcasting(c, def, cls, lv, m)
	for sid in def.get("extra_spells", []) + (def.get("tome_cantrips", []) if c.options.has("pact_tome") else []):
		if not c.spellcasting.is_empty() and not Spells.get_spell(sid).is_empty() and not c.spellcasting.known.has(sid):
			c.spellcasting.known.append(sid)
	var rc: String = def.get("race_cantrip", "")
	if rc != "" and not Spells.get_spell(rc).is_empty():
		_racial_spell(c, rc, "int", m)  # high elf: Intelligence
	if c.traits.has("infernalLegacy"):
		_racial_spell(c, "thaumaturgy", "cha", m)
		if lv >= 3:
			c.resources["infernal_rebuke"] = _res("Hellish Rebuke (Infernal Legacy)", 1, "long")

	# Dragonborn breath weapon.
	if c.traits.has("breathWeapon"):
		var anc: Dictionary = Classes.DRACONIC_ANCESTRY.get(def.get("ancestry", "red"), Classes.DRACONIC_ANCESTRY.red)
		var dice := "2d6" if lv < 6 else ("3d6" if lv < 11 else ("4d6" if lv < 16 else "5d6"))
		var shape := {"type": "area", "shape": anc.shape, "size": 15 if anc.shape == "cone" else 30, "width": 5, "origin": "self"}
		c.resistances.append(anc.type)
		c.resources["breath"] = _res("Breath Weapon", 1, "short")
		c.powers.append({"id": "breath_weapon", "name": "Breath Weapon (%s)" % anc.type, "resource": "breath",
			"dc": 8 + m.call("con") + c.prof,
			"spell": {"name": "Breath Weapon", "level": 0, "time": "action", "range": 0, "target": shape,
				"save": {"ability": anc.save, "half": true}, "damage": [{"dice": dice, "type": anc.type}],
				"desc": "Exhale destructive energy: %s save, %s %s (half on success). Once per short rest." % [anc.save.to_upper(), dice, anc.type]}})

	# Tiefling Infernal Legacy: Darkness once per long rest from 5th level, Charisma-based.
	if c.traits.has("infernalLegacy") and lv >= 5:
		c.resources["infernal_darkness"] = _res("Infernal Legacy", 1, "long")
		c.powers.append({"id": "infernal_darkness", "name": "Darkness (Infernal Legacy)", "resource": "infernal_darkness",
			"spell": Spells.get_spell("darkness").duplicate(true)})

	# Passive Perception and initiative.
	var perc: int = m.call("wis") + c.prof * int(c.skills.get("perception", 0))
	if c.joat and not c.skills.has("perception"):
		perc += c.prof / 2
	c.passive_perception = 10 + perc + (5 if feats.has("observant") else 0)
	if c.joat:
		c.init_bonus = c.prof / 2
	if c.features.has("remarkableAthlete"):
		c.init_bonus = (c.prof + 1) / 2
	if c.features.has("relentlessEndurance") or c.traits.has("relentlessEndurance"):
		c.resources["relentless"] = _res("Relentless Endurance", 1, "long")
	_apply_feats(c, def, feats, lv, m)
	return c


const POLEARMS := ["glaive", "halberd", "quarterstaff", "spear"]


## Feats live in c.features; the engine checks them where they apply.
static func _apply_feats(c: Dictionary, def: Dictionary, feats: Array, lv: int, m: Callable) -> void:
	for ft in feats:
		c.features.append(ft)
		var entry := Creator.feat_entry(def, lv, ft)
		var picks: Array = entry.get("picks", [])
		match ft:
			"elementalAdept":
				c.fdata["adept_types"] = c.fdata.get("adept_types", []) + picks
			"martialAdept":
				c.resources["superiority"] = _res("Superiority Dice (d6)", 1, "short")
				c.fdata["superiority_die"] = "1d6"
				c.fdata["maneuvers"] = picks.duplicate()
				c.fdata["maneuver_dc"] = 8 + c.prof + maxi(m.call("str"), m.call("dex"))
			"inspiringLeader":
				c.resources["inspiring_leader"] = _res("Inspiring Leader", 1, "short")
			"magicInitiate", "ritualCaster", "spellSniper":
				var ability: String = Classes.ALL.get(entry.get("class", ""), {}).get("spell_ability", "int")
				for sid in picks:
					var sp := Spells.get_spell(sid)
					if sp.is_empty():
						continue
					if sp.level == 0:
						_racial_spell(c, sid, ability, m)  # shortcut: an existing caster casts it with their own ability
					else:
						# Once per long rest (Magic Initiate) or as a ritual outside combat (Ritual Caster).
						var key: String = "feat_" + sid
						var pw := {"id": key, "name": "%s (%s)" % [sp.name, Creator.FEATS[ft].name], "spell": sp.duplicate(true), "spell_id": sid,
							"dc": 8 + c.prof + m.call(ability), "attack_bonus": c.prof + m.call(ability)}
						if ft == "ritualCaster":
							pw["ritual"] = true
						else:
							c.resources[key] = _res(pw.name, 1, "long")
							pw["resource"] = key
						c.powers.append(pw)
			"alert":
				c.init_bonus += 5
			"tough":
				c.max_hp += 2 * lv
				c.hp = c.max_hp
			"mobile":
				c.base_speed += 10
			"lucky":
				c.resources["luck"] = _res("Luck Points", 3, "long")
			"polearmMaster":
				for a in c.attacks.duplicate():
					if a.get("weapon_id", "") in POLEARMS:
						var b: Dictionary = a.duplicate(true)
						b.id = a.id + "_butt"
						b.name = a.name + " (butt end)"
						b.damage = [{"dice": "1d4", "bonus": a.damage[0].bonus, "type": "bludgeoning"}]
						b.erase("shillelagh")
						b["bonus_only"] = true
						c.attacks.append(b)
						break


## Adds a racial spell, giving a non-caster a spellcasting block in `ability` to cast it with.
static func _racial_spell(c: Dictionary, sid: String, ability: String, m: Callable) -> void:
	if c.spellcasting.is_empty():
		c.spellcasting = {"ability": ability, "dc": 8 + c.prof + m.call(ability), "attack_bonus": c.prof + m.call(ability),
			"slots": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pact": {}, "known": []}
	if not c.spellcasting.known.has(sid):
		c.spellcasting.known.append(sid)


static func _primary(cls: String) -> String:
	return {"barbarian": "str", "bard": "cha", "cleric": "wis", "druid": "wis", "fighter": "str", "monk": "dex",
		"paladin": "str", "ranger": "dex", "rogue": "dex", "sorcerer": "cha", "warlock": "cha", "wizard": "int"}.get(cls, "str")


static func _bigger_die(a: String, b: String) -> String:
	return a if Dice.max_value(a) >= Dice.max_value(b) else b


static func _apply_class_features(c: Dictionary, def: Dictionary, lv: int, m: Callable) -> void:
	var f: Array = c.features
	match def["class"]:
		"barbarian":
			var rages: int = [0, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 99][lv]
			c.resources["rage"] = _res("Rage", rages, "long")
			c.fdata["rage_damage"] = 2 if lv < 9 else (3 if lv < 16 else 4)
			f.append_array(["rage", "unarmoredDefense"])
			if lv >= 2: f.append_array(["recklessAttack", "dangerSense"])
			if lv >= 3: f.append("frenzy")
			if lv >= 5: c.attacks_per_action = 2
			if lv >= 6: f.append("mindlessRage")
			if lv >= 7: f.append("feralInstinct")
			if lv >= 9: c.fdata["brutal_dice"] = 1 if lv < 13 else (2 if lv < 17 else 3)
			if lv >= 11: f.append("relentlessRage")
			if lv >= 15: f.append("persistentRage")
			if lv >= 10:
				c.powers.append({"id": "intimidating_presence", "name": "Intimidating Presence", "dc": 8 + c.prof + m.call("cha"),
					"spell": {"name": "Intimidating Presence", "level": 0, "time": "action", "range": 30,
						"target": {"type": "creature", "count": 1, "filter": "enemy"}, "save": {"ability": "wis", "half": false},
						"effect": {"on": "fail", "name": "Intimidated", "conditions": ["frightened"], "expires_on": {"who": "source", "phase": "end", "count": 2}},
						"desc": "A creature within 30 ft makes a Wisdom save or is frightened of you until the end of your next turn."}})
		"bard":
			c.resources["inspiration"] = _res("Bardic Inspiration", maxi(1, m.call("cha")), "short" if lv >= 5 else "long")
			c.fdata["inspiration_die"] = "1d6" if lv < 5 else ("1d8" if lv < 10 else ("1d10" if lv < 15 else "1d12"))
			f.append("bardicInspiration")
			if lv >= 2:
				c.joat = true
			if lv >= 3: f.append("cuttingWords")
			if lv >= 20: f.append("superiorInspiration")
			if lv >= 2: c.fdata["song_of_rest"] = "1d6" if lv < 9 else ("1d8" if lv < 13 else ("1d10" if lv < 17 else "1d12"))
			if lv >= 6:
				c.powers.append({"id": "countercharm", "name": "Countercharm",
					"spell": {"name": "Countercharm", "level": 0, "time": "action", "range": 0, "target": {"type": "self"},
						"self_effect": {"name": "Countercharm", "tag": "countercharm", "expires_on": {"who": "source", "phase": "end", "count": 2}},
						"desc": "Until the end of your next turn, you and allies within 30 ft have advantage on saves against being frightened or charmed."}})
		"cleric":
			f.append("discipleOfLife")
			if lv >= 2:
				c.resources["channel"] = _res("Channel Divinity", 1 if lv < 6 else (2 if lv < 18 else 3), "short")
				f.append_array(["turnUndead", "preserveLife"])
				c.powers.append(_turn_undead_power())
				c.powers.append({"id": "preserve_life", "name": "Preserve Life", "resource": "channel",
					"spell": {"name": "Preserve Life", "level": 0, "time": "action", "range": 0, "target": {"type": "self"}, "special": "preserveLife",
						"desc": "Restore %d HP divided among creatures within 30 ft (each up to half its maximum)." % (5 * lv)}})
			if lv >= 6: f.append("blessedHealer")
			if lv >= 17: f.append("supremeHealing")
			if lv >= 8: c.fdata["divine_strike"] = "1d8" if lv < 14 else "2d8"
			if lv >= 10:
				c.resources["intervention"] = _res("Divine Intervention", 1, "long")
				c.powers.append({"id": "divine_intervention", "name": "Divine Intervention", "resource": "intervention",
					"spell": {"name": "Divine Intervention", "level": 0, "time": "action", "range": 0, "target": {"type": "self"}, "special": "divineIntervention",
						"desc": "Your god answers if d100 rolls %d or lower; the DM decides how." % lv}})
			if lv >= 5:
				c.fdata["destroy_undead_cr"] = 0.5 if lv < 8 else (1.0 if lv < 11 else (2.0 if lv < 14 else (3.0 if lv < 17 else 4.0)))
		"druid":
			if lv >= 2:
				c.resources["wild_shape"] = _res("Wild Shape", 2, "short")
				c.resources["natural_recovery"] = _res("Natural Recovery", 1, "long")
				f.append_array(["wildShape", "naturalRecovery"])
				c.fdata["wild_shape_cr"] = 0.25 if lv < 4 else (0.5 if lv < 8 else 1.0)
			if lv >= 6: f.append("landsStride")
			if lv >= 10:
				c.immunities.append("poison")
				c.cond_immunities.append("poisoned")
			if lv >= 18: f.append("beastSpells")
			if lv >= 20: f.append("archdruid")
		"fighter":
			c.resources["second_wind"] = _res("Second Wind", 1, "short")
			f.append("secondWind")
			if lv >= 2:
				c.resources["action_surge"] = _res("Action Surge", 1 if lv < 17 else 2, "short")
				f.append("actionSurge")
			if lv >= 3:
				c.fdata["crit_range"] = 19 if lv < 15 else 18
			c.attacks_per_action = 1 if lv < 5 else (2 if lv < 11 else (3 if lv < 20 else 4))
			if lv >= 7: f.append("remarkableAthlete")
			if lv >= 9:
				c.resources["indomitable"] = _res("Indomitable", 1 if lv < 13 else (2 if lv < 17 else 3), "long")
				f.append("indomitable")
			if lv >= 18: f.append("survivor")
		"monk":
			c.fdata["martial_arts_die"] = "1d4" if lv < 5 else ("1d6" if lv < 11 else ("1d8" if lv < 17 else "1d10"))
			f.append("martialArts")
			if lv >= 2:
				c.resources["ki"] = _res("Ki", lv, "short")
				f.append_array(["flurryOfBlows", "patientDefense", "stepOfTheWind"])
				c.fdata["ki_dc"] = 8 + c.prof + m.call("wis")
			if lv >= 3: f.append_array(["deflectMissiles", "openHand"])
			if lv >= 4: f.append("slowFall")
			if lv >= 9: f.append("waterWalk")
			if lv >= 5:
				f.append("stunningStrike")
				c.attacks_per_action = 2
			if lv >= 6:
				c.resources["wholeness"] = _res("Wholeness of Body", 1, "long")
				c.powers.append({"id": "wholeness_of_body", "name": "Wholeness of Body", "resource": "wholeness",
					"spell": {"name": "Wholeness of Body", "level": 0, "time": "action", "range": 0, "target": {"type": "self"},
						"heal": {"dice": str(3 * lv)}, "desc": "Regain %d hit points." % (3 * lv)}})
			if lv >= 7:
				f.append("evasion")
				c.powers.append({"id": "stillness_of_mind", "name": "Stillness of Mind",
					"spell": {"name": "Stillness of Mind", "level": 0, "time": "action", "range": 0, "target": {"type": "self"}, "special": "stillness",
						"desc": "End an effect that is charming or frightening you."}})
			if lv >= 10:
				c.immunities.append("poison")
				c.cond_immunities.append("poisoned")
			if lv >= 14: c.save_profs = Stats.ABILITIES.duplicate()  # Diamond Soul
			if lv >= 20: f.append("perfectSelf")
		"paladin":
			c.resources["lay_on_hands"] = _res("Lay on Hands (HP)", 5 * lv, "long")
			f.append("layOnHands")
			c.resources["divine_sense"] = _res("Divine Sense", 1 + maxi(0, m.call("cha")), "long")
			c.powers.append({"id": "divine_sense", "name": "Divine Sense", "resource": "divine_sense",
				"spell": {"name": "Divine Sense", "level": 0, "time": "action", "range": 0, "target": {"type": "self"}, "special": "divineSense",
					"desc": "Learn where every celestial, fiend and undead within 60 ft is, unless it's behind total cover."}})
			if lv >= 2: f.append("divineSmite")
			if lv >= 3:
				c.resources["channel"] = _res("Channel Divinity", 1, "short")
				f.append("sacredWeapon")
			if lv >= 5: c.attacks_per_action = 2
			if lv >= 6: f.append("auraOfProtection")
			if lv >= 7: f.append("auraOfDevotion")
			if lv >= 10: f.append("auraOfCourage")
			if lv >= 11: f.append("improvedSmite")
			c.fdata["aura_range"] = 10 if lv < 18 else 30
		"ranger":
			c.fdata["favored_enemies"] = c.options.filter(func(o): return Creator.FAVORED_ENEMIES.has(o)).map(func(o): return o.trim_prefix("fe_"))
			if lv >= 20: f.append("foeSlayer")
			if lv >= 3: f.append("colossusSlayer")
			if lv >= 5: c.attacks_per_action = 2
			if lv >= 8: f.append("landsStride")
			if lv >= 14: f.append("vanish")
			if lv >= 15:  # Superior Hunter's Defense
				var hd: Array = c.options.filter(func(o): return Creator.HUNTER_DEFENSES.has(o))
				f.append({"stand_against_the_tide": "standAgainstTheTide", "superior_uncanny_dodge": "uncannyDodge"}.get(hd.front() if not hd.is_empty() else "", "evasion"))
		"rogue":
			c.fdata["sneak_dice"] = (lv + 1) / 2
			f.append("sneakAttack")
			if lv >= 2: f.append("cunningAction")
			if lv >= 3: f.append("fastHands")
			if lv >= 5: f.append("uncannyDodge")
			if lv >= 7: f.append("evasion")
			if lv >= 9: f.append("supremeSneak")
			if lv >= 15 and not c.save_profs.has("wis"): c.save_profs.append("wis")  # Slippery Mind
			if lv >= 18: f.append("elusive")
		"sorcerer":
			if lv >= 2:
				c.resources["sorcery"] = _res("Sorcery Points", lv, "long")
				f.append("fontOfMagic")
			if lv >= 20: f.append("sorcerousRestoration")
			if lv < 3:
				c.options = c.options.filter(func(o): return not (o in ["quickened", "careful", "heightened"]))
			if lv >= 6:
				c.fdata["affinity"] = Classes.DRACONIC_ANCESTRY.get(def.get("ancestry", "red"), Classes.DRACONIC_ANCESTRY.red).type
		"warlock":
			f.append("darkOnesBlessing")
			if lv >= 6:
				c.resources["dark_luck"] = _res("Dark One's Own Luck", 1, "short")
				f.append("darkOnesOwnLuck")
			if lv >= 10 and not c.resistances.has(def.get("fiend_resist", "fire")):
				c.resistances.append(def.get("fiend_resist", "fire"))  # Fiendish Resilience
			if lv < 2:
				c.options = c.options.filter(func(o): return not (o in ["agonizing_blast", "repelling_blast"]))
		"wizard":
			c.resources["arcane_recovery"] = _res("Arcane Recovery", 1, "long")
			if lv >= 2: f.append("sculptSpells")
			if lv >= 6: f.append("potentCantrip")
			if lv >= 10: f.append("empoweredEvocation")


static func _turn_undead_power() -> Dictionary:
	return {"id": "turn_undead", "name": "Turn Undead", "resource": "channel",
		"spell": {"name": "Turn Undead", "level": 0, "time": "action", "range": 0,
			"target": {"type": "area", "shape": "sphere", "size": 30, "origin": "self"}, "special": "turnUndead",
			"save": {"ability": "wis", "half": false},
			"desc": "Undead within 30 ft make a Wisdom save or are turned for 1 minute (or until damaged)."}}


static func _apply_spellcasting(c: Dictionary, def: Dictionary, cls: Dictionary, lv: int, m: Callable) -> void:
	var ability: String = cls.spell_ability
	var smod: int = m.call(ability)
	var sc := {
		"ability": ability, "dc": 8 + c.prof + smod, "attack_bonus": c.prof + smod,
		"slots": Classes.slots_for(cls.caster, lv), "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pact": {}, "known": [],
	}
	if cls.caster == "pact":
		var row: Array = Classes.PACT_SLOTS[lv]
		sc.pact = {"level": row[1], "max": row[0], "used": 0}
	var max_lv := Classes.max_spell_level(cls.caster, lv)
	if cls.caster == "half" and lv < 2:
		max_lv = 0
	var known: Array = []
	for sid in def.get("spells", []) + Creator.always_prepared(def, lv):
		if known.has(sid):
			continue
		var sp := Spells.get_spell(sid)
		if sp.is_empty():
			continue
		if sp.level == 0 and cls.caster == "half":
			continue
		if sp.level <= max_lv:
			known.append(sid)
	if known.is_empty() and max_lv == 0 and cls.caster == "half":
		c.spellcasting = {}
		return
	sc.known = known
	c.spellcasting = sc


## Multiclass spellcasting: one slot table from the combined caster level (full + half/2), Pact Magic kept apart,
## and each spell cast with its own class's ability (sc.spell_ability).
static func _apply_multiclass_spellcasting(c: Dictionary, def: Dictionary, levels: Dictionary, lv: int, m: Callable) -> void:
	var d := def.merged({"level": lv}, true)
	var casters := Creator.casting_classes(d)
	if casters.is_empty():
		return
	var slot_classes: Array = casters.keys().filter(func(k): return Classes.ALL[k].caster in ["full", "half"])
	var slots := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	if slot_classes.size() == 1:
		slots = Classes.slots_for(Classes.ALL[slot_classes[0]].caster, casters[slot_classes[0]])
	elif slot_classes.size() > 1:
		var caster_lv := 0
		for k in slot_classes:
			caster_lv += casters[k] if Classes.ALL[k].caster == "full" else casters[k] / 2
		slots = Classes.slots_for("full", caster_lv)
	var main: String = casters.keys()[0]
	var ability: String = Classes.ALL[main].spell_ability
	var sc := {
		"ability": ability, "dc": 8 + c.prof + m.call(ability), "attack_bonus": c.prof + m.call(ability),
		"slots": slots, "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pact": {}, "known": [], "spell_ability": {},
	}
	if casters.has("warlock"):
		var row: Array = Classes.PACT_SLOTS[casters.warlock]
		sc.pact = {"level": row[1], "max": row[0], "used": 0}
	for sid in def.get("spells", []) + Creator.always_prepared(d, lv):
		var owner := Creator.spell_owner(d, sid)
		if owner == "" or sc.known.has(sid):
			continue
		sc.known.append(sid)
		if Classes.ALL[owner].spell_ability != ability:
			sc.spell_ability[sid] = Classes.ALL[owner].spell_ability
	c.spellcasting = sc
