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
		"max_hp": 1, "hp": 1, "temp_hp": 0, "ac": 10, "base_speed": 30,
		"armor": "none", "stealth_dis": false, "metal_armor": false, "shield": false,
		"attacks": [], "attacks_per_action": 1, "multiattack": [], "spellcasting": {}, "powers": [],
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
		c.powers.append(power)
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
	var c := _base(id)
	c.name = def.name
	c.kind = "pc"
	c.side = "party"
	c.color = def.get("color", "#3498db")
	c.template_id = def["class"]
	c.class_id = def["class"]
	c.subclass_id = cls.subclass.id if lv >= cls.subclass.level else ""
	c.race_id = def.race
	c.level = lv
	c.csize = race.size
	c.prof = Classes.prof_bonus(lv)
	c.options = def.get("options", []).duplicate()
	c.description = "Level %d %s %s%s" % [lv, race.name, cls.name, (" (%s)" % cls.subclass.name) if c.subclass_id != "" else ""]

	# Ability scores: base + racial + ASIs (capped at 20).
	var ab: Dictionary = {}
	for k in Stats.ABILITIES:
		ab[k] = int(def.abilities.get(k, 10))
	for k in race.asi:
		ab[k] += race.asi[k]
	for k in def.get("flex_asi", []):
		ab[k] += 1
	for asi_level in Creator.asi_levels(def["class"]):
		if lv < asi_level:
			continue
		var inc: Dictionary = Creator.asi_at(def, asi_level)
		if inc.is_empty():
			var primary: String = cls.get("primary", _primary(def["class"]))
			inc = {primary: 2}
		for k in inc:
			ab[k] = mini(20, ab[k] + int(inc[k]))
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
	c.traits = race.traits.duplicate()
	c.darkvision = race.get("darkvision", 0)
	c.resistances = race.get("resist", []).duplicate()
	for sk in def.get("skills", []) + Creator.background_skills(def) + def.get("race_skills", []):
		c.skills[sk] = 1
	for sk in race.get("skills", []):
		c.skills[sk] = 1
	for sk in def.get("expertise", []):
		c.skills[sk] = 2

	# Hit points: max at 1st level, average after.
	var hd: int = cls.hit_die
	var hp: int = hd + m.call("con") + (lv - 1) * (hd / 2 + 1 + m.call("con"))
	if c.traits.has("dwarvenToughness"):
		hp += lv
	if c.subclass_id == "draconic":
		hp += lv
	c.max_hp = maxi(lv, hp)
	c.hp = c.max_hp
	c.resources["hit_dice"] = _res("Hit Dice (d%d)" % hd, lv, "long")
	c.fdata["hit_die"] = hd

	c.languages = race.get("languages", ["Common"]).duplicate()

	# Armor class.
	var armor_id: String = def.get("armor", "")
	c.shield = def.get("shield", false)
	var magic_ac := 0
	var magic_armor := ""
	var magic_shield := ""
	var weapon_list: Array = def.get("weapons", []).duplicate()
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
			"weapon":
				weapon_list.erase(r.base)  # the magic weapon replaces a mundane one of the same kind
			"wondrous", "potion":
				pass
	var armor: Dictionary = Equipment.ARMOR.get(armor_id, {})
	if not armor.is_empty():
		c.equipment.append(magic_armor if magic_armor != "" else "%s armor" % armor.name)
	if c.shield:
		c.equipment.append(magic_shield if magic_shield != "" else "Shield")
	for r in items:
		if r.item.kind in ["weapon", "wondrous", "potion"]:
			c.equipment.append(r.name)
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
		ac = armor.ac + (m.call("dex") if armor.dex_cap < 0 else mini(m.call("dex"), armor.dex_cap))
	else:
		match def["class"]:
			"barbarian": ac = 10 + m.call("dex") + m.call("con")
			"monk":
				if not c.shield:
					ac = 10 + m.call("dex") + m.call("wis")
			"sorcerer":
				if c.subclass_id == "draconic":
					ac = 13 + m.call("dex")
	if c.shield:
		ac += 2
	var style: String = def.get("style", "")
	var has_style: bool = (def["class"] == "fighter") or (def["class"] in ["paladin", "ranger"] and lv >= 2)
	if not has_style:
		style = ""
	if style == "defense" and not armor.is_empty():
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
	if style != "":
		c.options.append(style)

	# Speed.
	var speed: int = race.speed
	if c.armor == "heavy" and armor.get("str", 0) > ab.str and not c.traits.has("heavyArmorSpeed"):
		speed -= 10
	if def["class"] == "barbarian" and lv >= 5 and c.armor != "heavy":
		speed += 10
	if def["class"] == "monk" and lv >= 2 and armor.is_empty() and not c.shield:
		speed += [0, 0, 10, 10, 10, 10, 15, 15, 15, 15, 20, 20, 20, 20, 25, 25, 25, 25, 30, 30, 30][lv]
	for r in items:
		var smin: int = r.item.get("speed_min", 0)
		if smin > 0:
			speed = maxi(speed, smin)
	c.base_speed = speed

	# Class features and resources.
	_apply_class_features(c, def, lv, m)

	# Weapons.
	var weapon_profs: Array = cls.weapons.duplicate()
	weapon_profs.append_array(race.get("weapons", []))
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
		var monk_weapon: bool = def["class"] == "monk" and Equipment.is_monk_weapon(wid)
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
		if style == "dueling" and w.kind == "melee" and not two_handed_grip:
			bonus += 2
		var props: Array = w.props.duplicate()
		if monk_weapon:
			props.append("monk")
		var base := {
			"id": wid, "name": w.name, "range": w.kind, "to_hit": to_hit + (2 if style == "archery" and w.kind == "ranged" else 0),
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
		if style == "great_weapon" and w.kind == "melee" and two_handed_grip:
			base["reroll_low"] = 2
		if def["class"] == "druid" and wid in ["club", "quarterstaff"]:
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
		if Equipment.WEAPONS.has(wid) and Equipment.WEAPONS[wid].kind == "melee" and Equipment.WEAPONS[wid].props.has("light"):
			c.fdata.light_melee_count += 1
	# Unarmed strike.
	var unarmed_ability := "str"
	var unarmed_die := ""
	if def["class"] == "monk":
		unarmed_ability = "dex" if m.call("dex") > m.call("str") else "str"
		unarmed_die = c.fdata.martial_arts_die
	var um: int = m.call(unarmed_ability)
	c.attacks.append({
		"id": "unarmed", "name": "Unarmed Strike", "range": "melee", "to_hit": um + c.prof, "reach": 5, "normal": 0, "long": 0,
		"damage": [{"dice": unarmed_die, "bonus": (um if unarmed_die != "" else 1 + um), "type": "bludgeoning"}],
		"props": ["unarmed"] + (["monk"] if def["class"] == "monk" else []), "ability": unarmed_ability,
		"weapon": true, "weapon_id": "unarmed", "dmg_mod": um, "proficient": true, "crit_range": c.fdata.get("crit_range", 20),
	})

	# Spellcasting.
	if cls.caster != "":
		_apply_spellcasting(c, def, cls, lv, m)
	for sid in def.get("extra_spells", []):
		if not c.spellcasting.is_empty() and not Spells.get_spell(sid).is_empty() and not c.spellcasting.known.has(sid):
			c.spellcasting.known.append(sid)
	var rc: String = def.get("race_cantrip", "")
	if rc != "" and not Spells.get_spell(rc).is_empty():
		if c.spellcasting.is_empty():
			# High elf cantrip on a non-caster: Intelligence is its spellcasting ability.
			c.spellcasting = {"ability": "int", "dc": 8 + c.prof + m.call("int"), "attack_bonus": c.prof + m.call("int"),
				"slots": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "pact": {}, "known": []}
		if not c.spellcasting.known.has(rc):
			c.spellcasting.known.append(rc)

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
	c.passive_perception = 10 + perc
	if c.joat:
		c.init_bonus = c.prof / 2
	if c.features.has("relentlessEndurance") or c.traits.has("relentlessEndurance"):
		c.resources["relentless"] = _res("Relentless Endurance", 1, "long")
	return c


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
		"bard":
			c.resources["inspiration"] = _res("Bardic Inspiration", maxi(1, m.call("cha")), "short" if lv >= 5 else "long")
			c.fdata["inspiration_die"] = "1d6" if lv < 5 else ("1d8" if lv < 10 else ("1d10" if lv < 15 else "1d12"))
			f.append("bardicInspiration")
			if lv >= 2:
				c.joat = true
			if lv >= 3: f.append("cuttingWords")
		"cleric":
			f.append("discipleOfLife")
			if lv >= 2:
				c.resources["channel"] = _res("Channel Divinity", 1 if lv < 6 else (2 if lv < 18 else 3), "short")
				f.append_array(["turnUndead", "preserveLife"])
				c.powers.append(_turn_undead_power())
				c.powers.append({"id": "preserve_life", "name": "Preserve Life", "resource": "channel",
					"spell": {"name": "Preserve Life", "level": 0, "time": "action", "range": 0, "target": {"type": "self"}, "special": "preserveLife",
						"desc": "Restore %d HP divided among creatures within 30 ft (each up to half its maximum)." % (5 * lv)}})
			if lv >= 5:
				c.fdata["destroy_undead_cr"] = 0.5 if lv < 8 else (1.0 if lv < 11 else (2.0 if lv < 14 else (3.0 if lv < 17 else 4.0)))
		"druid":
			if lv >= 2:
				c.resources["wild_shape"] = _res("Wild Shape", 2, "short")
		"fighter":
			c.resources["second_wind"] = _res("Second Wind", 1, "short")
			f.append("secondWind")
			if lv >= 2:
				c.resources["action_surge"] = _res("Action Surge", 1 if lv < 17 else 2, "short")
				f.append("actionSurge")
			if lv >= 3:
				c.fdata["crit_range"] = 19 if lv < 15 else 18
			c.attacks_per_action = 1 if lv < 5 else (2 if lv < 11 else (3 if lv < 20 else 4))
		"monk":
			c.fdata["martial_arts_die"] = "1d4" if lv < 5 else ("1d6" if lv < 11 else ("1d8" if lv < 17 else "1d10"))
			f.append("martialArts")
			if lv >= 2:
				c.resources["ki"] = _res("Ki", lv, "short")
				f.append_array(["flurryOfBlows", "patientDefense", "stepOfTheWind"])
				c.fdata["ki_dc"] = 8 + c.prof + m.call("wis")
			if lv >= 3: f.append_array(["deflectMissiles", "openHand"])
			if lv >= 5:
				f.append("stunningStrike")
				c.attacks_per_action = 2
		"paladin":
			c.resources["lay_on_hands"] = _res("Lay on Hands (HP)", 5 * lv, "long")
			f.append("layOnHands")
			if lv >= 2: f.append("divineSmite")
			if lv >= 3:
				c.resources["channel"] = _res("Channel Divinity", 1, "short")
				f.append("sacredWeapon")
			if lv >= 5: c.attacks_per_action = 2
		"ranger":
			if lv >= 3: f.append("colossusSlayer")
			if lv >= 5: c.attacks_per_action = 2
		"rogue":
			c.fdata["sneak_dice"] = (lv + 1) / 2
			f.append("sneakAttack")
			if lv >= 2: f.append("cunningAction")
			if lv >= 5: f.append("uncannyDodge")
		"sorcerer":
			if lv >= 2:
				c.resources["sorcery"] = _res("Sorcery Points", lv, "long")
				f.append("fontOfMagic")
			if lv < 3:
				c.options = c.options.filter(func(o): return not (o in ["quickened", "careful", "twinned"]))
		"warlock":
			f.append("darkOnesBlessing")
			if lv < 2:
				c.options = c.options.filter(func(o): return not (o in ["agonizing_blast", "repelling_blast"]))
		"wizard":
			c.resources["arcane_recovery"] = _res("Arcane Recovery", 1, "long")
			if lv >= 2: f.append("sculptSpells")


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
