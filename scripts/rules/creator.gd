class_name Creator
extends RefCounted
## Character-creation rules (PHB 2014): ability score methods, Ability Score Improvements, class and
## background skills, expertise, fighting styles, invocations/metamagic, spell counts and armor.
## The creator UI uses these to offer choices; the host uses `validate()` before building.
##
## A character definition ("def") looks like the entries in Pregens plus a few creation fields:
##   {name, race, class, level, color, method, rolled, abilities (base scores), flex_asi, asi: {4: {str: 2}},
##    background, skills (class picks), background_skills, race_skills, expertise, style, options,
##    ancestry, armor, shield, weapons, spells, race_cantrip}

const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
const POINT_BUY_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
const POINT_BUY_BUDGET := 27
const METHODS := ["standard", "pointbuy", "roll", "manual"]
const METHOD_NAMES := {"standard": "Standard array", "pointbuy": "Point buy (27)", "roll": "Roll 4d6, drop lowest", "manual": "Manual entry"}

const CLASS_SKILLS := {
	"barbarian": [2, ["animalHandling", "athletics", "intimidation", "nature", "perception", "survival"]],
	"bard": [3, []],  # any skills
	"cleric": [2, ["history", "insight", "medicine", "persuasion", "religion"]],
	"druid": [2, ["arcana", "animalHandling", "insight", "medicine", "nature", "perception", "religion", "survival"]],
	"fighter": [2, ["acrobatics", "animalHandling", "athletics", "history", "insight", "intimidation", "perception", "survival"]],
	"monk": [2, ["acrobatics", "athletics", "history", "insight", "religion", "stealth"]],
	"paladin": [2, ["athletics", "insight", "intimidation", "medicine", "persuasion", "religion"]],
	"ranger": [3, ["animalHandling", "athletics", "insight", "investigation", "nature", "perception", "stealth", "survival"]],
	"rogue": [4, ["acrobatics", "athletics", "deception", "insight", "intimidation", "investigation", "perception", "performance", "persuasion", "sleightOfHand", "stealth"]],
	"sorcerer": [2, ["arcana", "deception", "insight", "intimidation", "persuasion", "religion"]],
	"warlock": [2, ["arcana", "deception", "history", "intimidation", "investigation", "nature", "religion"]],
	"wizard": [2, ["arcana", "history", "insight", "investigation", "medicine", "religion"]],
}

# Background name -> its two skill proficiencies. "custom" lets the player pick any two (PHB p. 125).
const BACKGROUNDS := {
	"acolyte": ["Acolyte", ["insight", "religion"]],
	"charlatan": ["Charlatan", ["deception", "sleightOfHand"]],
	"criminal": ["Criminal", ["deception", "stealth"]],
	"entertainer": ["Entertainer", ["acrobatics", "performance"]],
	"folk_hero": ["Folk Hero", ["animalHandling", "survival"]],
	"guild_artisan": ["Guild Artisan", ["insight", "persuasion"]],
	"hermit": ["Hermit", ["medicine", "religion"]],
	"noble": ["Noble", ["history", "persuasion"]],
	"outlander": ["Outlander", ["athletics", "survival"]],
	"sage": ["Sage", ["arcana", "history"]],
	"sailor": ["Sailor", ["athletics", "perception"]],
	"soldier": ["Soldier", ["athletics", "intimidation"]],
	"urchin": ["Urchin", ["sleightOfHand", "stealth"]],
	"custom": ["Custom background", []],
}

const STYLES := {
	"fighter": ["archery", "defense", "dueling", "great_weapon", "two_weapon"],
	"paladin": ["defense", "dueling", "great_weapon"],
	"ranger": ["archery", "defense", "dueling", "two_weapon"],
}
const STYLE_NAMES := {"archery": "Archery (+2 ranged attacks)", "defense": "Defense (+1 AC in armor)", "dueling": "Dueling (+2 damage one-handed)",
	"great_weapon": "Great Weapon Fighting (reroll 1s and 2s)", "two_weapon": "Two-Weapon Fighting (add modifier to off-hand)"}
const TACTICS := {"escape_the_horde": "Escape the Horde (opportunity attacks against you have disadvantage)",
	"multiattack_defense": "Multiattack Defense (+4 AC against a creature's later attacks the turn it hits you)",
	"steel_will": "Steel Will (advantage on saves against being frightened)"}
const INVOCATIONS := {"agonizing_blast": "Agonizing Blast (+Cha to Eldritch Blast damage)", "repelling_blast": "Repelling Blast (push 10 ft)"}
const METAMAGIC := {"quickened": "Quickened Spell (2 SP: action spell as a bonus action)", "careful": "Careful Spell (1 SP: allies auto-succeed)"}

# Cantrips known by level (index = level).
const CANTRIPS := {
	"bard": [0, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
	"cleric": [0, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
	"druid": [0, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
	"sorcerer": [0, 4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
	"warlock": [0, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4],
	"wizard": [0, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
}
# Spells known by level for "known" casters.
const SPELLS_KNOWN := {
	"bard": [0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 15, 16, 18, 19, 19, 20, 22, 22, 22],
	"ranger": [0, 0, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11],
	"sorcerer": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15],
	"warlock": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15],
}
# Subclass spells that are always prepared and don't count against the limit: [class level, spell].
const ALWAYS_PREPARED := {
	"life": [[1, "bless"], [1, "cure_wounds"], [3, "lesser_restoration"], [5, "revivify"]],
	"devotion": [[5, "lesser_restoration"]],
}


static func asi_levels(cls: String) -> Array:
	match cls:
		"fighter": return [4, 6, 8, 12, 14, 16, 19]
		"rogue": return [4, 8, 10, 12, 16, 19]
	return [4, 8, 12, 16, 19]


## ASI choice for a level, accepting int or string keys (JSON turns keys into strings).
static func asi_at(def: Dictionary, level: int) -> Dictionary:
	var asi: Dictionary = def.get("asi", {})
	if asi.has(level):
		return asi[level]
	return asi.get(str(level), {})


static func racial_bonus(def: Dictionary) -> Dictionary:
	var race: Dictionary = Classes.RACES.get(def.get("race", ""), {})
	var out := {}
	for ab in Stats.ABILITIES:
		out[ab] = race.get("asi", {}).get(ab, 0)
	for ab in def.get("flex_asi", []):
		out[ab] += 1
	return out


static func asi_bonus(def: Dictionary, level: int) -> Dictionary:
	var out := {}
	for ab in Stats.ABILITIES:
		out[ab] = 0
	for lv in asi_levels(def.get("class", "")):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		for ab in inc:
			out[ab] += int(inc[ab])
	return out


## Final scores: base + racial + ASIs, capped at 20 (racial bonuses may exceed 20 only from base 20, which point buy can't reach).
static func final_abilities(def: Dictionary, level: int) -> Dictionary:
	var base: Dictionary = def.get("abilities", {})
	var race := racial_bonus(def)
	var out := {}
	for ab in Stats.ABILITIES:
		out[ab] = int(base.get(ab, 10)) + race[ab]
	for lv in asi_levels(def.get("class", "")):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		for ab in inc:
			out[ab] = mini(20, out[ab] + int(inc[ab]))
	return out


static func point_buy_spent(base: Dictionary) -> int:
	var total := 0
	for ab in Stats.ABILITIES:
		total += POINT_BUY_COST.get(int(base.get(ab, 8)), 99)
	return total


static func class_skill_choice(cls: String) -> Array:
	var row: Array = CLASS_SKILLS.get(cls, [2, []])
	var list: Array = row[1] if not row[1].is_empty() else Stats.SKILLS.keys()
	return [row[0], list]


static func background_skills(def: Dictionary) -> Array:
	var bg: String = def.get("background", "custom")
	if bg == "custom" or not BACKGROUNDS.has(bg):
		return def.get("background_skills", [])
	return BACKGROUNDS[bg][1]


static func race_fixed_skills(race: String) -> Array:
	return Classes.RACES.get(race, {}).get("skills", [])


static func race_skill_choices(race: String) -> int:
	return 2 if race == "half_elf" else 0


static func all_skills(def: Dictionary) -> Array:
	var out := []
	for sk in def.get("skills", []) + background_skills(def) + race_fixed_skills(def.get("race", "")) + def.get("race_skills", []):
		if not out.has(sk):
			out.append(sk)
	return out


static func expertise_count(cls: String, level: int) -> int:
	match cls:
		"rogue": return 4 if level >= 6 else 2
		"bard": return 0 if level < 3 else (2 if level < 10 else 4)
	return 0


static func invocation_count(level: int) -> int:
	if level < 2:
		return 0
	for row in [[18, 8], [15, 7], [12, 6], [9, 5], [7, 4], [5, 3], [2, 2]]:
		if level >= row[0]:
			return row[1]
	return 0


static func metamagic_count(level: int) -> int:
	return 0 if level < 3 else (2 if level < 10 else (3 if level < 17 else 4))


static func needs_style(cls: String, level: int) -> bool:
	return cls == "fighter" or (cls in ["paladin", "ranger"] and level >= 2)


static func max_spell_level(cls: String, level: int) -> int:
	var c: Dictionary = Classes.ALL.get(cls, {})
	if c.get("caster", "") == "":
		return -1
	if c.caster == "half" and level < 2:
		return -1
	return Classes.max_spell_level(c.caster, level)


static func cantrip_limit(cls: String, level: int) -> int:
	return CANTRIPS[cls][clampi(level, 1, 20)] if CANTRIPS.has(cls) else 0


## How many leveled spells the character may know or prepare.
static func spell_limit(def: Dictionary, level: int) -> int:
	var cls: String = def.get("class", "")
	if SPELLS_KNOWN.has(cls):
		return SPELLS_KNOWN[cls][clampi(level, 1, 20)]
	var ab := final_abilities(def, level)
	match cls:
		"cleric", "druid": return maxi(1, Stats.mod(ab.wis) + level)
		"wizard": return maxi(1, Stats.mod(ab.int) + level)
		"paladin": return 0 if level < 2 else maxi(1, Stats.mod(ab.cha) + level / 2)
	return 0


static func always_prepared(def: Dictionary, level: int) -> Array:
	var cls: Dictionary = Classes.ALL.get(def.get("class", ""), {})
	if cls.is_empty() or level < cls.subclass.level:
		return []
	var out := []
	for row in ALWAYS_PREPARED.get(cls.subclass.id, []):
		if level >= row[0]:
			out.append(row[1])
	return out


static func armor_allowed(cls: String, armor_id: String) -> bool:
	if armor_id == "":
		return true
	var a: Dictionary = Equipment.ARMOR.get(armor_id, {})
	return not a.is_empty() and Classes.ALL.get(cls, {}).get("armor", []).has(a.type)


static func shield_allowed(cls: String) -> bool:
	return Classes.ALL.get(cls, {}).get("armor", []).has("shield")


## A sensible starting definition for a race/class.
static func new_def(cls: String = "fighter", race: String = "human") -> Dictionary:
	var arr := STANDARD_ARRAY.duplicate()
	var order: Array = _ability_priority(cls)
	var abilities := {}
	for i in 6:
		abilities[order[i]] = arr[i]
	var def := {
		"name": "", "race": race, "class": cls, "level": 1, "color": "#3a7bd5", "method": "standard", "rolled": [],
		"abilities": abilities, "flex_asi": [], "asi": {}, "background": "soldier", "background_skills": [],
		"skills": [], "race_skills": [], "expertise": [], "style": STYLES.get(cls, [""])[0] if STYLES.has(cls) else "",
		"options": [], "ancestry": "red", "armor": "", "shield": false, "weapons": [], "spells": [], "race_cantrip": "",
	}
	return def


static func _ability_priority(cls: String) -> Array:
	return {
		"barbarian": ["str", "con", "dex", "wis", "cha", "int"], "bard": ["cha", "dex", "con", "wis", "int", "str"],
		"cleric": ["wis", "con", "str", "cha", "int", "dex"], "druid": ["wis", "con", "dex", "int", "cha", "str"],
		"fighter": ["str", "con", "dex", "wis", "cha", "int"], "monk": ["dex", "wis", "con", "str", "int", "cha"],
		"paladin": ["str", "cha", "con", "wis", "dex", "int"], "ranger": ["dex", "wis", "con", "str", "int", "cha"],
		"rogue": ["dex", "con", "int", "wis", "cha", "str"], "sorcerer": ["cha", "con", "dex", "wis", "int", "str"],
		"warlock": ["cha", "con", "dex", "wis", "int", "str"], "wizard": ["int", "con", "dex", "wis", "cha", "str"],
	}.get(cls, Stats.ABILITIES)


## Returns a list of problems; empty means the character is legal.
static func validate(def: Dictionary) -> Array:
	var errs := []
	var name := str(def.get("name", "")).strip_edges()
	if name.is_empty():
		errs.append("Give your character a name.")
	elif name.length() > 40:
		errs.append("Name is too long (40 characters max).")
	var cls: String = def.get("class", "")
	var race: String = def.get("race", "")
	if not Classes.ALL.has(cls):
		errs.append("Choose a class.")
		return errs
	if not Classes.RACES.has(race):
		errs.append("Choose a race.")
		return errs
	var level: int = int(def.get("level", 1))
	if level < 1 or level > 20:
		errs.append("Level must be 1-20.")
		return errs

	# Ability scores.
	var base: Dictionary = def.get("abilities", {})
	var vals := []
	for ab in Stats.ABILITIES:
		if not base.has(ab):
			errs.append("Missing %s score." % Stats.ABILITY_NAMES[ab])
			return errs
		vals.append(int(base[ab]))
	var sorted := vals.duplicate()
	sorted.sort()
	match def.get("method", "standard"):
		"standard":
			var arr := STANDARD_ARRAY.duplicate()
			arr.sort()
			if sorted != arr:
				errs.append("Standard array: use 15, 14, 13, 12, 10 and 8 once each.")
		"pointbuy":
			for v in vals:
				if v < 8 or v > 15:
					errs.append("Point buy scores must be 8-15 before racial bonuses.")
					break
			if point_buy_spent(base) > POINT_BUY_BUDGET:
				errs.append("Point buy: %d of %d points spent." % [point_buy_spent(base), POINT_BUY_BUDGET])
		"roll":
			var rolled: Array = def.get("rolled", []).map(func(x): return int(x))
			rolled.sort()
			if rolled.size() != 6:
				errs.append("Roll your six ability scores.")
			elif rolled != sorted:
				errs.append("Assign each rolled score to one ability.")
		"manual":
			for v in vals:
				if v < 3 or v > 20:
					errs.append("Manual scores must be 3-20.")
					break
		_:
			errs.append("Unknown ability score method.")
	var flex: Array = def.get("flex_asi", [])
	var flex_n: int = Classes.RACES[race].get("flex_asi", 0)
	if flex.size() != flex_n:
		errs.append("Half-elf: choose two different abilities (not Charisma) for +1." if flex_n > 0 else "Only half-elves get floating +1s.")
	elif flex_n > 0 and (flex.has("cha") or flex[0] == flex[1]):
		errs.append("Half-elf: the two +1s must go to different abilities other than Charisma.")
	for lv in asi_levels(cls):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		var total := 0
		for ab in inc:
			if not Stats.ABILITIES.has(ab) or int(inc[ab]) < 0 or int(inc[ab]) > 2:
				errs.append("Invalid Ability Score Improvement at level %d." % lv)
			total += int(inc[ab])
		if total != 2:
			errs.append("Level %d: choose your Ability Score Improvement (+2 to one, or +1 to two)." % lv)

	# Skills.
	var pick: Array = class_skill_choice(cls)
	var class_skills: Array = def.get("skills", [])
	if class_skills.size() != pick[0]:
		errs.append("Choose %d class skills (%d chosen)." % [pick[0], class_skills.size()])
	for sk in class_skills:
		if not pick[1].has(sk):
			errs.append("%s isn't a %s skill." % [Stats.skill_label(sk), Classes.ALL[cls].name])
	var bg: String = def.get("background", "")
	if not BACKGROUNDS.has(bg):
		errs.append("Choose a background.")
	elif bg == "custom" and def.get("background_skills", []).size() != 2:
		errs.append("Custom background: choose two skills.")
	if def.get("race_skills", []).size() != race_skill_choices(race):
		errs.append("Half-elf Skill Versatility: choose two skills." if race_skill_choices(race) > 0 else "Only half-elves pick racial skills.")
	var seen := {}
	for sk in class_skills + background_skills(def) + race_fixed_skills(race) + def.get("race_skills", []):
		if not Stats.SKILLS.has(sk):
			errs.append("Unknown skill %s." % sk)
		elif seen.has(sk):
			errs.append("%s is chosen twice; pick a different skill." % Stats.skill_label(sk))
		seen[sk] = true
	var exp: Array = def.get("expertise", [])
	if exp.size() != expertise_count(cls, level):
		errs.append("Choose %d skills for Expertise." % expertise_count(cls, level))
	for sk in exp:
		if not seen.has(sk):
			errs.append("Expertise needs a skill you're proficient in (%s)." % Stats.skill_label(sk))

	# Class options.
	if needs_style(cls, level):
		if not STYLES[cls].has(def.get("style", "")):
			errs.append("Choose a fighting style.")
	if cls == "fighter" and level >= 10 and (not STYLES.fighter.has(def.get("style2", "")) or def.get("style2", "") == def.get("style", "")):
		errs.append("Choose a different second fighting style.")
	var opts: Array = def.get("options", [])
	var inv := opts.filter(func(o): return INVOCATIONS.has(o))
	var meta := opts.filter(func(o): return METAMAGIC.has(o))
	if cls == "warlock" and inv.size() > invocation_count(level):
		errs.append("Too many invocations (%d allowed)." % invocation_count(level))
	if cls != "warlock" and not inv.is_empty():
		errs.append("Only warlocks take invocations.")
	var tac := opts.filter(func(o): return TACTICS.has(o))
	if tac.size() != (1 if cls == "ranger" and level >= 7 else 0):
		errs.append("Choose one Defensive Tactic." if cls == "ranger" and level >= 7 else "Only 7th-level rangers take Defensive Tactics.")
	if cls == "sorcerer" and meta.size() > metamagic_count(level):
		errs.append("Too many metamagic options (%d allowed)." % metamagic_count(level))
	if cls != "sorcerer" and not meta.is_empty():
		errs.append("Only sorcerers take metamagic.")
	if race == "dragonborn" and not Classes.DRACONIC_ANCESTRY.has(def.get("ancestry", "")):
		errs.append("Choose a draconic ancestry.")

	# Equipment.
	if not armor_allowed(cls, def.get("armor", "")):
		errs.append("%s isn't proficient with that armor." % Classes.ALL[cls].name)
	if def.get("shield", false) and not shield_allowed(cls):
		errs.append("%s isn't proficient with shields." % Classes.ALL[cls].name)
	var weapons: Array = def.get("weapons", [])
	if weapons.size() > 8:
		errs.append("Carry at most 8 weapons.")
	for w in weapons:
		if not Equipment.WEAPONS.has(w):
			errs.append("Unknown weapon %s." % w)

	# Spells.
	var max_lv := max_spell_level(cls, level)
	var auto := always_prepared(def, level)
	var cantrips := 0
	var leveled := 0
	for sid in def.get("spells", []):
		var sp := Spells.get_spell(sid)
		if sp.is_empty():
			errs.append("Unknown spell %s." % sid)
			continue
		if not sp.classes.has(cls) and not auto.has(sid):
			errs.append("%s isn't on the %s spell list." % [sp.name, Classes.ALL[cls].name])
		if sp.level > max_lv:
			errs.append("%s is too high level for you." % sp.name)
		if sp.level == 0:
			cantrips += 1
		elif not auto.has(sid):
			leveled += 1
	if cantrips > cantrip_limit(cls, level):
		errs.append("Too many cantrips (%d of %d)." % [cantrips, cantrip_limit(cls, level)])
	if leveled > spell_limit(def, level):
		errs.append("Too many spells (%d of %d)." % [leveled, spell_limit(def, level)])
	for e in def.get("items", []):
		if Items.get_item(e.get("id", "")).is_empty():
			errs.append("Unknown magic item %s." % e.get("id", "?"))
	for sid in def.get("extra_spells", []):
		if Spells.get_spell(sid).is_empty():
			errs.append("Unknown granted spell %s." % sid)
	var rc: String = def.get("race_cantrip", "")
	if rc != "" and def.get("spells", []).has(rc):
		errs.append("%s is already your racial cantrip; choose a different class cantrip." % Spells.get_spell(rc).get("name", rc))
	if rc != "":
		if race != "high_elf":
			errs.append("Only high elves get a bonus wizard cantrip.")
		elif Spells.get_spell(rc).get("level", 1) != 0 or not Spells.get_spell(rc).get("classes", []).has("wizard"):
			errs.append("The high elf cantrip must be a wizard cantrip.")
	return errs


## Fills in creation fields for older definitions (pregens, imported files) so they can be edited.
## Keeps every choice that's still legal and fills the gaps with sensible defaults.
static func normalize(src: Dictionary) -> Dictionary:
	var cls: String = src.get("class", "fighter")
	var race: String = src.get("race", "human")
	var def := new_def(cls, race)
	for k in src:
		def[k] = src[k].duplicate(true) if (src[k] is Dictionary or src[k] is Array) else src[k]
	def["level"] = clampi(int(def.get("level", 1)), 1, 20)
	var level: int = def.level
	var abilities := {}
	for ab in Stats.ABILITIES:
		abilities[ab] = int(def.abilities.get(ab, 10))
	def["abilities"] = abilities
	if not src.has("method"):
		var vals: Array = abilities.values()
		vals.sort()
		var arr := STANDARD_ARRAY.duplicate()
		arr.sort()
		def["method"] = "standard" if vals == arr else "manual"
	if race == "half_elf" and def.flex_asi.size() != 2:
		def["flex_asi"] = ["con", "dex"]
	elif Classes.RACES.get(race, {}).get("flex_asi", 0) == 0:
		def["flex_asi"] = []
	# ASIs: keep what's there, default to +2 in the class's main ability.
	var asi := {}
	for lv in asi_levels(cls):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		var total := 0
		for ab in inc:
			total += int(inc[ab])
		asi[lv] = inc if total == 2 else {_ability_priority(cls)[0]: 2}
	def["asi"] = asi
	# Skills: split the old flat list into class picks, then background, then race choices.
	var pool: Array = src.get("skills", []).duplicate()
	var pick := class_skill_choice(cls)
	var fixed := race_fixed_skills(race)
	var used := fixed.duplicate()
	var class_sk := []
	for sk in pool:
		if class_sk.size() < pick[0] and pick[1].has(sk) and not used.has(sk):
			class_sk.append(sk)
			used.append(sk)
	for sk in pick[1]:
		if class_sk.size() >= pick[0]:
			break
		if not used.has(sk):
			class_sk.append(sk)
			used.append(sk)
	def["skills"] = class_sk
	if not src.has("background"):
		def["background"] = "custom"
	var bg_sk := []
	if def.background == "custom":
		for sk in src.get("background_skills", []) + pool + Stats.SKILLS.keys():
			if bg_sk.size() < 2 and not used.has(sk):
				bg_sk.append(sk)
				used.append(sk)
	else:
		for sk in BACKGROUNDS[def.background][1]:
			if used.has(sk):
				def["background"] = "custom"
		if def.background == "custom":
			return normalize(def)
		used.append_array(BACKGROUNDS[def.background][1])
	def["background_skills"] = bg_sk
	var race_sk := []
	for sk in src.get("race_skills", []) + pool + Stats.SKILLS.keys():
		if race_sk.size() < race_skill_choices(race) and not used.has(sk):
			race_sk.append(sk)
			used.append(sk)
	def["race_skills"] = race_sk
	var exp := []
	for sk in src.get("expertise", []) + used:
		if exp.size() < expertise_count(cls, level) and used.has(sk) and not exp.has(sk):
			exp.append(sk)
	def["expertise"] = exp
	if needs_style(cls, level) and not STYLES[cls].has(def.get("style", "")):
		def["style"] = STYLES[cls][0]
	if cls == "fighter" and level >= 10:
		if not STYLES.fighter.has(def.get("style2", "")) or def.style2 == def.style:
			def["style2"] = STYLES.fighter.filter(func(s): return s != def.style)[0]
	else:
		def.erase("style2")
	var opts := []
	var inv_n := 0
	var meta_n := 0
	for o in def.get("options", []):
		if INVOCATIONS.has(o) and cls == "warlock" and inv_n < invocation_count(level):
			opts.append(o)
			inv_n += 1
		elif METAMAGIC.has(o) and cls == "sorcerer" and meta_n < metamagic_count(level):
			opts.append(o)
			meta_n += 1
		elif TACTICS.has(o) and cls == "ranger" and level >= 7 and not opts.any(func(x): return TACTICS.has(x)):
			opts.append(o)
	if cls == "ranger" and level >= 7 and not opts.any(func(x): return TACTICS.has(x)):
		opts.append("escape_the_horde")
	def["options"] = opts
	if not armor_allowed(cls, def.get("armor", "")):
		def["armor"] = ""
	if def.get("shield", false) and not shield_allowed(cls):
		def["shield"] = false
	# Spells: keep legal ones up to the limits, in order.
	var auto := always_prepared(def, level)
	var max_lv := max_spell_level(cls, level)
	var spells := []
	var n_cantrips := 0
	var n_spells := 0
	for sid in def.get("spells", []):
		var sp := Spells.get_spell(sid)
		if sp.is_empty() or sp.level > max_lv or spells.has(sid) or auto.has(sid):
			continue
		if not sp.classes.has(cls):
			continue
		if sp.level == 0:
			if n_cantrips >= cantrip_limit(cls, level):
				continue
			n_cantrips += 1
		else:
			if n_spells >= spell_limit(def, level):
				continue
			n_spells += 1
		spells.append(sid)
	def["spells"] = spells
	if race != "high_elf":
		def["race_cantrip"] = ""
	return def
