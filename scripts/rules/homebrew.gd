class_name Homebrew
extends RefCounted
## DM-made monsters, spells and items. They live in the game state (state.homebrew) so they save
## with the campaign and sync to players; this class mirrors them into static registries so
## Monsters.get_monster / Spells.get_spell / Items.get_item resolve homebrew ids like built-in ones.

const KINDS := ["monsters", "spells", "items"]
const KIND_NAMES := {"monsters": "Monster", "spells": "Spell", "items": "Magic Item"}
const TRAITS := ["packTactics", "nimbleEscape", "undeadFortitude", "aggressive", "parry", "magicResistance"]
const CREATURE_TYPES := ["aberration", "beast", "celestial", "construct", "dragon", "elemental", "fey", "fiend", "giant",
	"humanoid", "monstrosity", "ooze", "plant", "undead"]
const SCHOOLS := ["abjuration", "conjuration", "divination", "enchantment", "evocation", "illusion", "necromancy", "transmutation"]
const ITEM_KINDS := ["weapon", "armor", "shield", "wondrous", "potion"]
const XP_BY_CR := {0.0: 10, 0.125: 25, 0.25: 50, 0.5: 100, 1.0: 200, 2.0: 450, 3.0: 700, 4.0: 1100, 5.0: 1800, 6.0: 2300, 7.0: 2900,
	8.0: 3900, 9.0: 5000, 10.0: 5900, 11.0: 7200, 12.0: 8400, 13.0: 10000, 14.0: 11500, 15.0: 13000, 16.0: 15000, 17.0: 18000,
	18.0: 20000, 19.0: 22000, 20.0: 25000, 21.0: 33000, 22.0: 41000, 23.0: 50000, 24.0: 62000, 25.0: 75000, 26.0: 90000,
	27.0: 105000, 28.0: 120000, 29.0: 135000, 30.0: 155000}
## Effect modifiers a homebrew spell may grant (the engine understands all of these).
const EFFECT_MODS := {
	"ac_bonus": "int", "speed_bonus": "int", "attack_die": "dice", "save_die": "dice", "attack_penalty_die": "dice",
	"save_penalty_die": "dice", "advantage_against": "bool", "disadvantage_against": "bool", "advantage_on_attacks": "bool",
	"disadvantage_on_attacks": "bool", "no_reactions": "bool", "no_healing": "bool",
}

static var monsters: Dictionary = {}
static var spells: Dictionary = {}
static var items: Dictionary = {}


## Point the registries at a state's homebrew (call whenever the state is replaced).
static func sync(state: Dictionary) -> void:
	var hb: Dictionary = state.get("homebrew", {})
	monsters = hb.get("monsters", {})
	spells = hb.get("spells", {})
	items = hb.get("items", {})


static func ensure(state: Dictionary) -> Dictionary:
	if not state.has("homebrew"):
		state["homebrew"] = {"monsters": {}, "spells": {}, "items": {}}
	for k in KINDS:
		if not state.homebrew.has(k):
			state.homebrew[k] = {}
	return state.homebrew


static func new_id(kind: String, name: String, existing: Dictionary) -> String:
	var base := "hb_" + (name.to_snake_case().replace(" ", "_") if name.strip_edges() != "" else kind.left(5))
	base = base.left(40)
	var id := base
	var n := 2
	while existing.has(id) or (kind == "monsters" and Monsters.ALL.has(id)) or (kind == "spells" and Spells.ALL.has(id)) or (kind == "items" and Items.ALL.has(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


## JSON turns every number into a float; turn whole numbers back into ints (CR keeps fractions).
static func coerce(v):
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1e9:
		return int(roundf(v))
	if v is Array:
		return v.map(func(x): return coerce(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = coerce(v[k]) if k != "cr" else float(v[k])
		return out
	return v


# ---------------- Templates ----------------

static func blank(kind: String) -> Dictionary:
	match kind:
		"monsters":
			return {"name": "New Monster", "size": "medium", "type": "humanoid", "ac": 12, "hp": 11, "hit_dice": "2d8+2", "speed": 30,
				"cr": 0.25, "abilities": {"str": 12, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 10}, "save_profs": [],
				"skills": {}, "passive": 10, "traits": [], "resistances": [], "immunities": [], "vulnerabilities": [],
				"condition_immunities": [], "color": "#8b3a3a", "multiattack": [], "powers": [], "spellcasting": {}, "desc": "",
				"attacks": [{"id": "a1", "name": "Club", "range": "melee", "to_hit": 3, "reach": 5, "normal": 0, "long": 0,
					"damage": [{"dice": "1d4", "bonus": 1, "type": "bludgeoning"}], "props": []}]}
		"spells":
			return {"name": "New Spell", "level": 1, "school": "evocation", "time": "action", "range": 60, "concentration": false,
				"classes": ["wizard", "sorcerer"], "desc": "", "mode": "attack", "attack": "ranged",
				"target": {"type": "creature", "count": 1}, "damage": [{"dice": "2d8", "type": "force", "per_slot": "1d8"}]}
		_:
			return {"name": "New Item", "kind": "wondrous", "base": "", "rarity": "uncommon", "desc": "", "ac_bonus": 1}


static func from_srd(kind: String, id: String) -> Dictionary:
	match kind:
		"monsters":
			var m: Dictionary = Monsters.get_monster(id).duplicate(true)
			var i := 1
			for a in m.get("attacks", []):
				for k in ["reach", "normal", "long"]:
					if not a.has(k):
						a[k] = 5 if k == "reach" else 0
			for p in m.get("powers", []):
				p["id"] = "p%d" % i
				i += 1
			m.name = "%s (copy)" % m.name
			for k in ["save_profs", "skills", "traits", "resistances", "immunities", "vulnerabilities", "condition_immunities", "multiattack", "powers"]:
				if not m.has(k):
					m[k] = [] if k != "skills" else {}
			m["spellcasting"] = m.get("spellcasting", {})
			m["desc"] = m.get("desc", "")
			return m
		"spells":
			var s: Dictionary = Spells.get_spell(id).duplicate(true)
			s.name = "%s (copy)" % s.name
			s.erase("special")
			s["mode"] = "attack" if s.has("attack") else ("save" if s.has("save") else "auto")
			return s
		_:
			var it: Dictionary = Items.get_item(id).duplicate(true)
			it.name = "%s (copy)" % it.name
			return it


## Cleans an editor copy into what the engine reads (drops fields that don't apply).
static func normalize(kind: String, d: Dictionary) -> Dictionary:
	var x: Dictionary = coerce(d.duplicate(true))
	match kind:
		"monsters":
			x["xp"] = XP_BY_CR.get(float(x.get("cr", 0)), 0)
			var ids := []
			for a in x.get("attacks", []):
				ids.append(a.get("id", ""))
				if a.get("recharge", 0) == 0:
					a.erase("recharge")
					a.erase("standalone")
				else:
					a["standalone"] = true
				if a.has("on_hit") and a.on_hit.is_empty():
					a.erase("on_hit")
			x["multiattack"] = x.get("multiattack", []).filter(func(i): return ids.has(i))
			for p in x.get("powers", []):
				if p.get("recharge", 0) == 0:
					p.erase("recharge")
		"spells":
			var mode: String = x.get("mode", "auto")
			if mode != "attack":
				x.erase("attack")
			elif not x.has("attack"):
				x["attack"] = "ranged"
			if mode != "save":
				x.erase("save")
			elif not x.has("save"):
				x["save"] = {"ability": "dex", "half": true}
			for k in ["damage", "heal", "effect", "push"]:
				if x.has(k) and (x[k] is Array or x[k] is Dictionary) and x[k].is_empty():
					x.erase(k)
			if x.has("effect"):
				var e: Dictionary = x.effect
				if mode == "attack" and e.get("on", "") == "fail":
					e.on = "hit"
				if mode == "save" and e.get("on", "") == "hit":
					e.on = "fail"
				if mode == "auto":
					e.on = "always"
				if not e.has("name") or str(e.name).strip_edges() == "":
					e["name"] = x.name
				if e.has("mods"):
					for k in e.mods.keys():
						var v = e.mods[k]
						if v is bool and not v or v is int and v == 0 or v is String and v == "":
							e.mods.erase(k)
			if x.get("target", {}).get("type", "") != "creature":
				for k in ["count", "per_slot", "repeat", "filter"]:
					x.target.erase(k)
	return x


# ---------------- Validation ----------------

static func validate(kind: String, d: Dictionary) -> Array:
	match kind:
		"monsters": return validate_monster(d)
		"spells": return validate_spell(d)
		"items": return validate_item(d)
	return ["Unknown homebrew type."]


static func _name_err(d: Dictionary, errs: Array) -> void:
	var n := str(d.get("name", "")).strip_edges()
	if n.is_empty():
		errs.append("Give it a name.")
	elif n.length() > 48:
		errs.append("Name is too long (48 characters max).")


static func _dmg_errs(parts: Array, errs: Array, where: String) -> void:
	for p in parts:
		var dice: String = str(p.get("dice", ""))
		if dice != "" and not Dice.is_valid(dice):
			errs.append("%s: \"%s\" isn't a dice expression (try 2d6)." % [where, dice])
		if not Stats.DAMAGE_TYPES.has(p.get("type", "")):
			errs.append("%s: choose a damage type." % where)
		if p.has("per_slot") and str(p.per_slot) != "" and not Dice.is_valid(str(p.per_slot)):
			errs.append("%s: upcast dice \"%s\" isn't valid." % [where, p.per_slot])


static func _range(v, lo: float, hi: float) -> bool:
	return (v is int or v is float) and v >= lo and v <= hi


static func validate_monster(d: Dictionary) -> Array:
	var errs := []
	_name_err(d, errs)
	if not Grid.SIZES.has(d.get("size", "")):
		errs.append("Choose a size.")
	if not CREATURE_TYPES.has(d.get("type", "")):
		errs.append("Choose a creature type.")
	if not _range(d.get("ac"), 1, 30): errs.append("AC must be 1-30.")
	if not _range(d.get("hp"), 1, 2000): errs.append("Hit points must be 1-2000.")
	if not _range(d.get("speed"), 0, 200): errs.append("Speed must be 0-200 ft.")
	if not XP_BY_CR.has(float(d.get("cr", -1))): errs.append("Choose a challenge rating.")
	if str(d.get("hit_dice", "")) != "" and not Dice.is_valid(str(d.hit_dice)): errs.append("Hit dice should look like 4d8+8.")
	for ab in Stats.ABILITIES:
		if not _range(d.get("abilities", {}).get(ab), 1, 30):
			errs.append("%s must be 1-30." % Stats.ABILITY_NAMES[ab])
	for t in d.get("traits", []):
		if not TRAITS.has(t):
			errs.append("Unknown trait %s." % t)
	for k in ["resistances", "immunities", "vulnerabilities"]:
		for t in d.get(k, []):
			if not Stats.DAMAGE_TYPES.has(t):
				errs.append("Unknown damage type %s." % t)
	for t in d.get("condition_immunities", []):
		if not Stats.CONDITIONS.has(t):
			errs.append("Unknown condition %s." % t)
	var ids := []
	var attacks: Array = d.get("attacks", [])
	if attacks.size() > 8: errs.append("At most 8 attacks.")
	for a in attacks:
		var where := "Attack \"%s\"" % a.get("name", "?")
		if str(a.get("name", "")).strip_edges() == "": errs.append("Every attack needs a name.")
		ids.append(a.get("id", ""))
		if not a.get("range", "") in ["melee", "ranged"]: errs.append("%s: melee or ranged?" % where)
		if not _range(a.get("to_hit"), -5, 25): errs.append("%s: attack bonus must be -5 to +25." % where)
		if a.get("range", "") == "melee" and not _range(a.get("reach", 5), 5, 30): errs.append("%s: reach must be 5-30 ft." % where)
		if a.get("range", "") == "ranged":
			if not _range(a.get("normal", 0), 5, 1000) or not _range(a.get("long", 0), 5, 2000) or a.get("long", 0) < a.get("normal", 0):
				errs.append("%s: set normal and long range (long at least normal)." % where)
		var dmg: Array = a.get("damage", [])
		if dmg.is_empty() and not a.has("hit_effect"): errs.append("%s: add damage." % where)
		_dmg_errs(dmg, errs, where)
		if a.has("on_hit") and not a.on_hit.is_empty():
			var oh: Dictionary = a.on_hit
			if not Stats.ABILITIES.has(oh.get("ability", "")): errs.append("%s: on-hit save needs an ability." % where)
			if not _range(oh.get("dc"), 1, 30): errs.append("%s: on-hit save DC must be 1-30." % where)
			_dmg_errs(oh.get("damage", []), errs, where + " on-hit")
			if oh.has("condition") and not Stats.CONDITIONS.has(oh.condition): errs.append("%s: unknown condition." % where)
		if a.has("recharge") and not _range(a.recharge, 0, 6): errs.append("%s: recharge must be 2-6 (or 0 for none)." % where)
	var multi: Array = d.get("multiattack", [])
	if multi.size() > 6: errs.append("Multiattack can have at most 6 attacks.")
	for m in multi:
		if not ids.has(m): errs.append("Multiattack refers to a missing attack.")
	for p in d.get("powers", []):
		var where := "Ability \"%s\"" % p.get("name", "?")
		var sp: Dictionary = p.get("spell", {})
		if str(p.get("name", "")).strip_edges() == "": errs.append("Every special ability needs a name.")
		if not _range(p.get("dc"), 1, 30): errs.append("%s: save DC must be 1-30." % where)
		var tgt: Dictionary = sp.get("target", {})
		if not tgt.get("shape", "") in ["cone", "line", "sphere", "cube"]: errs.append("%s: choose an area shape." % where)
		if not _range(tgt.get("size"), 5, 300): errs.append("%s: area size must be 5-300 ft." % where)
		if not Stats.ABILITIES.has(sp.get("save", {}).get("ability", "")): errs.append("%s: choose the saving throw." % where)
		_dmg_errs(sp.get("damage", []), errs, where)
	var sc: Dictionary = d.get("spellcasting", {})
	if not sc.is_empty():
		if not Stats.ABILITIES.has(sc.get("ability", "")): errs.append("Spellcasting needs an ability.")
		if not _range(sc.get("dc"), 1, 30): errs.append("Spell save DC must be 1-30.")
		if not _range(sc.get("attack_bonus"), -5, 25): errs.append("Spell attack bonus must be -5 to +25.")
		for sid in sc.get("spells", []):
			if Spells.get_spell(sid).is_empty(): errs.append("Unknown spell %s." % sid)
		for n in sc.get("slots", []):
			if not _range(n, 0, 9): errs.append("Spell slots must be 0-9 per level.")
	if attacks.is_empty() and d.get("powers", []).is_empty() and sc.get("spells", []).is_empty():
		errs.append("Give it at least one attack, special ability or spell.")
	return errs


static func validate_spell(d: Dictionary) -> Array:
	var errs := []
	_name_err(d, errs)
	if not _range(d.get("level"), 0, 9): errs.append("Level must be 0 (cantrip) to 9.")
	if not d.get("time", "") in ["action", "bonus"]: errs.append("Casting time must be an action or a bonus action.")
	if not _range(d.get("range"), 0, 1000): errs.append("Range must be 0-1000 ft.")
	if not SCHOOLS.has(d.get("school", "")): errs.append("Choose a school of magic.")
	for c in d.get("classes", []):
		if not Classes.ALL.has(c): errs.append("Unknown class %s." % c)
	var tgt: Dictionary = d.get("target", {})
	match tgt.get("type", ""):
		"self":
			pass
		"creature":
			if not _range(tgt.get("count", 1), 1, 20): errs.append("Targets must be 1-20.")
			if not _range(tgt.get("per_slot", 0), 0, 5): errs.append("Extra targets per slot level must be 0-5.")
			if d.get("range", 0) == 0: errs.append("A spell that targets creatures needs a range (5 = touch).")
		"area":
			if not tgt.get("shape", "") in ["sphere", "cube", "cone", "line"]: errs.append("Choose an area shape.")
			if not _range(tgt.get("size"), 5, 500): errs.append("Area size must be 5-500 ft.")
			if not tgt.get("origin", "") in ["self", "point"]: errs.append("Choose where the area starts.")
			if tgt.get("origin", "") == "point" and d.get("range", 0) == 0: errs.append("An area centered on a point needs a range.")
		_:
			errs.append("Choose what the spell targets.")
	var mode: String = d.get("mode", "auto")
	if mode == "attack" and tgt.get("type", "") != "creature": errs.append("Spell attacks need creature targets.")
	if mode == "save" and not Stats.ABILITIES.has(d.get("save", {}).get("ability", "")): errs.append("Choose the saving throw ability.")
	_dmg_errs(d.get("damage", []), errs, "Damage")
	var h: Dictionary = d.get("heal", {})
	if not h.is_empty():
		if not Dice.is_valid(str(h.get("dice", ""))): errs.append("Healing dice should look like 1d8.")
		if str(h.get("per_slot", "")) != "" and not Dice.is_valid(str(h.per_slot)): errs.append("Healing upcast dice isn't valid.")
	var e: Dictionary = d.get("effect", {})
	if not e.is_empty():
		for cond in e.get("conditions", []):
			if not Stats.CONDITIONS.has(cond): errs.append("Unknown condition %s." % cond)
		for k in e.get("mods", {}):
			if not EFFECT_MODS.has(k): errs.append("Unknown effect %s." % k)
			elif EFFECT_MODS[k] == "dice" and e.mods[k] != "" and not Dice.is_valid(str(e.mods[k])): errs.append("Effect dice \"%s\" isn't valid." % e.mods[k])
			elif EFFECT_MODS[k] == "int" and not _range(e.mods[k], -30, 30): errs.append("Effect bonus is out of range.")
		var count: int = e.get("expires_on", {}).get("count", 10)
		if count < 1 or count > 14400: errs.append("Duration must be 1-14400 rounds.")
		if e.has("repeat_save") and not Stats.ABILITIES.has(e.repeat_save.get("ability", "")): errs.append("Repeat save needs an ability.")
	if d.get("damage", []).is_empty() and h.is_empty() and e.is_empty() and not d.has("push"):
		errs.append("The spell needs to do something: damage, healing or an effect.")
	if mode == "attack" and d.get("damage", []).is_empty():
		errs.append("A spell attack should deal damage.")
	return errs


static func validate_item(d: Dictionary) -> Array:
	var errs := []
	_name_err(d, errs)
	var kind: String = d.get("kind", "")
	if not ITEM_KINDS.has(kind):
		errs.append("Choose what kind of item it is.")
		return errs
	var base: String = d.get("base", "")
	var ok_bases := {"weapon": ["weapon", "melee"], "armor": ["armor"], "shield": [""], "wondrous": ["", "damage_type"], "potion": [""]}
	if not ok_bases[kind].has(base): errs.append("That base doesn't fit a %s." % kind)
	for k in ["attack_bonus", "damage_bonus", "ac_bonus", "ac_unarmored_bonus", "save_bonus"]:
		if d.has(k) and not _range(d[k], -5, 5): errs.append("%s must be -5 to +5." % k.capitalize())
	_dmg_errs(d.get("extra_damage", []), errs, "Extra damage")
	for t in d.get("resist", []):
		if not Stats.DAMAGE_TYPES.has(t): errs.append("Unknown damage type %s." % t)
	for ab in d.get("ability_min", {}):
		if not Stats.ABILITIES.has(ab) or not _range(d.ability_min[ab], 1, 30): errs.append("Ability scores must be 1-30.")
	if d.has("speed_min") and not _range(d.speed_min, 0, 120): errs.append("Speed must be 0-120 ft.")
	if kind == "potion" and not Dice.is_valid(str(d.get("heal", ""))): errs.append("A potion needs healing dice like 2d4+2.")
	return errs


# ---------------- Packs ----------------

static func export_pack(state: Dictionary) -> String:
	var hb: Dictionary = state.get("homebrew", {})
	return JSON.stringify({"tabletop_homebrew": 1, "monsters": hb.get("monsters", {}), "spells": hb.get("spells", {}), "items": hb.get("items", {})}, "\t")


## Parses a pack file. Returns {ok, error, pack}.
static func parse_pack(text: String) -> Dictionary:
	var data = JSON.parse_string(text)
	if not (data is Dictionary) or not data.has("tabletop_homebrew"):
		return {"ok": false, "error": "That file isn't a TableTop homebrew pack."}
	var pack := {}
	for k in KINDS:
		pack[k] = {}
		for id in data.get(k, {}):
			pack[k][str(id)] = coerce(data[k][id])
	return {"ok": true, "error": "", "pack": pack}
