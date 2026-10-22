class_name Creator
extends RefCounted
## Character-creation rules (PHB 2014): ability score methods, Ability Score Improvements, class and
## background skills, expertise, fighting styles, invocations/metamagic, spell counts and armor.
## The creator UI uses these to offer choices; the host uses `validate()` before building.
##
## A character definition ("def") looks like the entries in Pregens plus a few creation fields:
##   {name, race, class, level, color, method, rolled, abilities (base scores), flex_asi, asi: {4: {str: 2}, 8: {feat: "alert"}},
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
	"fighter": ["archery", "defense", "dueling", "great_weapon", "protection", "two_weapon"],
	"paladin": ["defense", "dueling", "great_weapon", "protection"],
	"ranger": ["archery", "defense", "dueling", "two_weapon"],
}
const STYLE_NAMES := {"archery": "Archery (+2 ranged attacks)", "defense": "Defense (+1 AC in armor)", "dueling": "Dueling (+2 damage one-handed)",
	"great_weapon": "Great Weapon Fighting (reroll 1s and 2s)",
	"protection": "Protection (reaction: disadvantage on an attack against an adjacent ally; needs a shield)", "two_weapon": "Two-Weapon Fighting (add modifier to off-hand)"}
const TACTICS := {"escape_the_horde": "Escape the Horde (opportunity attacks against you have disadvantage)",
	"multiattack_defense": "Multiattack Defense (+4 AC against a creature's later attacks the turn it hits you)",
	"steel_will": "Steel Will (advantage on saves against being frightened)"}
const HUNTER_DEFENSES := {"superior_evasion": "Evasion (no damage on a successful Dexterity save, half on a failure)",
	"stand_against_the_tide": "Stand Against the Tide (reaction: a melee attack that misses you hits another creature instead)",
	"superior_uncanny_dodge": "Uncanny Dodge (reaction: halve the damage of an attack that hits you)"}
const PACT_BOONS := {"pact_blade": "Pact of the Blade (summon a magic melee weapon you're proficient with)",
	"pact_tome": "Pact of the Tome (three cantrips from any class)",
	"pact_chain": "Pact of the Chain (a familiar; the DM adds its token)"}
const FAVORED_ENEMIES := {"fe_beast": "Beasts", "fe_humanoid": "Humanoids", "fe_undead": "Undead", "fe_monstrosity": "Monstrosities",
	"fe_fiend": "Fiends", "fe_dragon": "Dragons", "fe_giant": "Giants", "fe_aberration": "Aberrations", "fe_celestial": "Celestials",
	"fe_construct": "Constructs", "fe_elemental": "Elementals", "fe_fey": "Fey", "fe_ooze": "Oozes", "fe_plant": "Plants"}
## Choices kept in def.options: [title, choices, class, from level, how many by level (index = level, last entry repeats)].
const OPTION_GROUPS := [
	["Favored Enemy", FAVORED_ENEMIES, "ranger", 1, [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3]],
	["Defensive Tactic", TACTICS, "ranger", 7, [1]],
	["Superior Hunter's Defense", HUNTER_DEFENSES, "ranger", 15, [1]],
	["Pact Boon", PACT_BOONS, "warlock", 3, [1]],
]


## How many choices from an OPTION_GROUPS row a class and level get.
static func group_count(g: Array, def: Dictionary) -> int:
	var level := lv_in(def, g[2])
	if level < g[3]:
		return 0
	var counts: Array = g[4]
	return counts[mini(level, counts.size() - 1)]
const INVOCATIONS := {"agonizing_blast": "Agonizing Blast (+Cha to Eldritch Blast damage)", "repelling_blast": "Repelling Blast (push 10 ft)",
	"devils_sight": "Devil's Sight (see normally in darkness, even magical, to 120 ft)", "eldritch_spear": "Eldritch Spear (Eldritch Blast range 300 ft)"}
const METAMAGIC := {"quickened": "Quickened Spell (2 SP: action spell as a bonus action)", "careful": "Careful Spell (1 SP: allies auto-succeed)",
	"heightened": "Heightened Spell (3 SP: one target has disadvantage on its first save)"}

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
	"life": [[1, "bless"], [1, "cure_wounds"], [3, "lesser_restoration"], [5, "revivify"], [7, "death_ward"], [9, "mass_cure_wounds"], [9, "raise_dead"]],
	"devotion": [[5, "lesser_restoration"], [9, "dispel_magic"]],
}


## PHB feats, each taken in place of an Ability Score Improvement and stored as
## asi: {lv: {feat, ability (half feats), picks (skills, languages, weapons, maneuvers, spells, damage type), class (spell feats)}}.
## half: abilities a half feat may raise by 1. req: prerequisites. pick: [kind, count]. dm: parts the DM adjudicates.
const ALL_ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const FEATS := {
	"actor": {"name": "Actor", "half": ["cha"], "desc": "+1 Cha.", "dm": "Advantage on Deception and Performance while disguised; mimic voices."},
	"alert": {"name": "Alert", "desc": "+5 initiative, can't be surprised, and unseen attackers don't get advantage against you."},
	"athlete": {"name": "Athlete", "half": ["str", "dex"], "desc": "+1 Str or Dex. Standing up costs only 5 ft.", "dm": "Climbing costs no extra movement; running jumps after 5 ft."},
	"charger": {"name": "Charger", "desc": "After taking the Dash action and moving 10 ft, make a bonus-action melee attack with +5 damage."},
	"crossbowExpert": {"name": "Crossbow Expert", "desc": "Ignore loading, an adjacent enemy doesn't give your ranged attacks disadvantage, and after attacking with a one-handed weapon, make a bonus-action hand crossbow attack."},
	"defensiveDuelist": {"name": "Defensive Duelist", "req": {"dex": 13}, "desc": "Reaction: when hit by a melee attack while holding a finesse weapon, add your proficiency bonus to AC."},
	"dualWielder": {"name": "Dual Wielder", "desc": "+1 AC with a melee weapon in each hand, and two-weapon fighting works with any one-handed melee weapons."},
	"dungeonDelver": {"name": "Dungeon Delver", "desc": "", "dm": "Advantage to find secret doors and on saves against traps; resist trap damage; search for traps at normal pace."},
	"durable": {"name": "Durable", "half": ["con"], "desc": "+1 Con. Each hit die you spend heals at least twice your Con modifier."},
	"elementalAdept": {"name": "Elemental Adept", "req": {"caster": true}, "pick": ["damage_type", 1], "desc": "Your spells ignore resistance to the chosen type and treat 1s on its damage dice as 2s."},
	"grappler": {"name": "Grappler", "req": {"str": 13}, "desc": "Advantage on attacks against a creature you're grappling. Action: pin it (another grapple check), restraining you both until the grapple ends."},
	"greatWeaponMaster": {"name": "Great Weapon Master", "desc": "Heavy melee weapons: take −5 to hit for +10 damage. A crit or a kill gives a bonus-action melee attack."},
	"healer": {"name": "Healer", "desc": "Stabilizing a dying creature also gives it 1 HP. Action: heal a creature 1d6 + 4 + its level, once per creature per rest."},
	"heavilyArmored": {"name": "Heavily Armored", "half": ["str"], "req": {"armor": "medium"}, "desc": "+1 Str and heavy armor proficiency."},
	"heavyArmorMaster": {"name": "Heavy Armor Master", "half": ["str"], "req": {"armor": "heavy"}, "desc": "+1 Str. In heavy armor, nonmagical bludgeoning, piercing and slashing damage is reduced by 3."},
	"inspiringLeader": {"name": "Inspiring Leader", "req": {"cha": 13}, "desc": "Out of combat, once per rest: you and up to five allies within 30 ft gain temp HP equal to your level + Cha modifier."},
	"keenMind": {"name": "Keen Mind", "half": ["int"], "desc": "+1 Int.", "dm": "Always know north and the hours until sunrise; recall anything from the past month."},
	"lightlyArmored": {"name": "Lightly Armored", "half": ["str", "dex"], "desc": "+1 Str or Dex and light armor proficiency."},
	"linguist": {"name": "Linguist", "half": ["int"], "pick": ["languages", 3], "desc": "+1 Int and three languages.", "dm": "Write ciphers (Int check DC = Int score + prof to crack)."},
	"lucky": {"name": "Lucky", "desc": "3 luck points per long rest: roll again after missing an attack, failing a save or losing a grapple/shove contest, or make an attacker that hit you roll again."},
	"mageSlayer": {"name": "Mage Slayer", "desc": "Reaction attack when an adjacent creature casts a spell; creatures you damage have disadvantage on concentration saves; advantage on saves against spells cast within 5 ft."},
	"magicInitiate": {"name": "Magic Initiate", "pick": ["initiate", 3], "desc": "Two cantrips and a 1st-level spell (once per long rest) from one class's list."},
	"martialAdept": {"name": "Martial Adept", "pick": ["maneuvers", 2], "desc": "Two Battle Master maneuvers and one d6 superiority die per short rest."},
	"mediumArmorMaster": {"name": "Medium Armor Master", "req": {"armor": "medium"}, "desc": "Medium armor doesn't hurt Stealth, and its Dex bonus cap is +3."},
	"mobile": {"name": "Mobile", "desc": "+10 ft speed, Dash ignores difficult terrain, and a creature you make a melee attack against can't make opportunity attacks against you this turn."},
	"moderatelyArmored": {"name": "Moderately Armored", "half": ["str", "dex"], "req": {"armor": "light"}, "desc": "+1 Str or Dex, medium armor and shield proficiency."},
	"mountedCombatant": {"name": "Mounted Combatant", "desc": "", "dm": "The table has no mounts yet: advantage against unmounted creatures smaller than your mount, redirect attacks to you, mount gets evasion."},
	"observant": {"name": "Observant", "half": ["int", "wis"], "desc": "+1 Int or Wis and +5 passive Perception.", "dm": "Read lips; +5 passive Investigation."},
	"polearmMaster": {"name": "Polearm Master", "desc": "Glaive, halberd, quarterstaff or spear: a bonus-action 1d4 butt-end attack, and an opportunity attack when an enemy enters your reach."},
	"resilient": {"name": "Resilient", "half": ALL_ABILITIES, "desc": "+1 to an ability and proficiency in its saving throws."},
	"ritualCaster": {"name": "Ritual Caster", "req": {"int_or_wis": 13}, "pick": ["rituals", 2], "desc": "A ritual book with two 1st-level rituals from one class's list, cast outside combat without a slot."},
	"savageAttacker": {"name": "Savage Attacker", "desc": "Once per turn, roll a melee weapon's damage dice twice and use the higher total."},
	"sentinel": {"name": "Sentinel", "desc": "Opportunity attacks ignore Disengage and drop the target's speed to 0; react with an attack when an adjacent enemy attacks someone else."},
	"sharpshooter": {"name": "Sharpshooter", "desc": "No long-range disadvantage, ignore half and three-quarters cover, and take −5 to hit for +10 damage with ranged weapons."},
	"shieldMaster": {"name": "Shield Master", "desc": "With a shield: a bonus-action shove after the Attack action, +2 to Dex saves against spells that target only you, and a reaction to take no damage when you succeed on a Dex save for half."},
	"skilled": {"name": "Skilled", "pick": ["skills", 3], "desc": "Proficiency in three skills."},
	"skulker": {"name": "Skulker", "req": {"dex": 13}, "desc": "Missing with a ranged attack doesn't reveal you while hidden.", "dm": "Hide when only lightly obscured; dim light doesn't hurt your Perception."},
	"spellSniper": {"name": "Spell Sniper", "req": {"caster": true}, "pick": ["sniper", 1], "desc": "Spell attacks have double range and ignore half and three-quarters cover; learn one attack cantrip."},
	"tavernBrawler": {"name": "Tavern Brawler", "half": ["str", "con"], "desc": "+1 Str or Con. Unarmed strikes deal 1d4, and after hitting with one on your turn you can grapple as a bonus action."},
	"tough": {"name": "Tough", "desc": "+2 hit points per level."},
	"warCaster": {"name": "War Caster", "req": {"caster": true}, "desc": "Advantage on concentration saves, and opportunity attacks can be a damaging cantrip instead of a weapon attack."},
	"weaponMaster": {"name": "Weapon Master", "half": ["str", "dex"], "pick": ["weapons", 4], "desc": "+1 Str or Dex and proficiency with four weapons."},
}
const LANGUAGES := ["Common", "Dwarvish", "Elvish", "Giant", "Gnomish", "Goblin", "Halfling", "Orc",
	"Abyssal", "Celestial", "Draconic", "Deep Speech", "Infernal", "Primordial", "Sylvan", "Undercommon"]
const ADEPT_TYPES := ["acid", "cold", "fire", "lightning", "thunder"]
const SPELL_FEAT_CLASSES := ["bard", "cleric", "druid", "sorcerer", "warlock", "wizard"]
## Battle Master maneuvers the engine runs (Martial Adept).
const MANEUVERS := {
	"distracting": ["Distracting Strike", "On a hit: +die damage, and the next attack against the target by someone else has advantage."],
	"menacing": ["Menacing Attack", "On a hit: +die damage, and a Wis save or frightened of you until the end of your next turn."],
	"parry": ["Parry", "Reaction when hit in melee: reduce the damage by the die + your Dex modifier."],
	"precision": ["Precision Attack", "After missing a weapon attack, add the die to the roll."],
	"pushing": ["Pushing Attack", "On a hit: +die damage, and a Str save or pushed 15 ft (Large or smaller)."],
	"riposte": ["Riposte", "Reaction when a creature misses you in melee: attack it and add the die to the damage."],
	"trip": ["Trip Attack", "On a hit: +die damage, and a Str save or knocked prone (Large or smaller)."],
}


## Ability increases from one ASI entry; a half feat gives +1 to its chosen ability.
static func asi_scores(inc: Dictionary) -> Dictionary:
	if not inc.has("feat"):
		return inc
	var ab: String = inc.get("ability", "")
	return {ab: 1} if FEATS.get(inc.feat, {}).get("half", []).has(ab) else {}


## Armor types the character's feats and later classes add (light, medium, heavy, shield).
static func feat_armor(def: Dictionary) -> Array:
	var out := []
	for e in def.get("classes", []):
		out.append_array(MULTICLASS_PROFS.get(e.get("class", ""), [[]])[0])
	var feats := feats_of(def, int(def.get("level", 1)))
	if feats.has("lightlyArmored"): out.append("light")
	if feats.has("moderatelyArmored"): out.append_array(["medium", "shield"])
	if feats.has("heavilyArmored"): out.append("heavy")
	return out


## Spells a spell feat may choose for `cls`: "cantrip", "first" (1st level), "ritual" or "attack_cantrip".
static func feat_spells(cls: String, kind: String) -> Array:
	var out := []
	for sid in Spells.spells_for_class(cls, 1):
		var sp := Spells.get_spell(sid)
		var ok: bool = sp.level == 0 if kind in ["cantrip", "attack_cantrip"] else sp.level == 1
		if kind == "ritual": ok = ok and sp.get("ritual", false)
		if kind == "attack_cantrip": ok = ok and sp.has("attack")
		if ok:
			out.append(sid)
	return out


## Slot kinds of a spell feat's picks, in order.
static func feat_spell_slots(feat: String) -> Array:
	match feat:
		"magicInitiate": return ["cantrip", "cantrip", "first"]
		"ritualCaster": return ["ritual", "ritual"]
		"spellSniper": return ["attack_cantrip"]
	return []


## Choices for pick `i` of a feat entry, as ids.
static func feat_pick_options(inc: Dictionary, i: int) -> Array:
	match FEATS.get(inc.get("feat", ""), {}).get("pick", [""])[0]:
		"skills": return Stats.SKILLS.keys()
		"languages": return LANGUAGES
		"weapons": return Equipment.WEAPONS.keys()
		"damage_type": return ADEPT_TYPES
		"maneuvers": return MANEUVERS.keys()
		"initiate", "rituals", "sniper": return feat_spells(inc.get("class", "wizard"), feat_spell_slots(inc.feat)[i])
	return []


static func feat_pick_label(inc: Dictionary, id: String) -> String:
	match FEATS.get(inc.get("feat", ""), {}).get("pick", [""])[0]:
		"skills": return Stats.skill_label(id)
		"weapons": return Equipment.WEAPONS.get(id, {}).get("name", id)
		"damage_type": return id.capitalize()
		"maneuvers": return MANEUVERS.get(id, [id])[0]
		"initiate", "rituals", "sniper": return Spells.get_spell(id).get("name", id)
	return id


## A feat entry with legal default choices, for the creator to start from.
static func new_feat_entry(feat: String, cls: String = "wizard") -> Dictionary:
	var f: Dictionary = FEATS[feat]
	var e := {"feat": feat}
	if not f.get("half", []).is_empty():
		e["ability"] = f.half[0]
	if not f.has("pick"):
		return e
	if f.pick[0] in ["initiate", "rituals", "sniper"]:
		e["class"] = cls if SPELL_FEAT_CLASSES.has(cls) else "wizard"
	e["picks"] = []
	for i in f.pick[1]:
		for x in feat_pick_options(e, i):
			if not e.picks.has(x):
				e.picks.append(x)
				break
	return e


## Problems with one feat entry taken at `lv`.
static func feat_errors(def: Dictionary, lv: int, inc: Dictionary) -> Array:
	var errs := []
	var f: Dictionary = FEATS.get(inc.feat, {})
	if f.is_empty():
		return ["Unknown feat at level %d." % lv]
	if feats_of(def, lv).count(inc.feat) > 1:
		errs.append("%s can only be taken once." % f.name)
	var half: Array = f.get("half", [])
	if not half.is_empty() and not half.has(inc.get("ability", "")):
		errs.append("%s: choose which ability gets +1." % f.name)
	var req: Dictionary = f.get("req", {})
	var ab := final_abilities(def, lv - 1)
	for k in req:
		match k:
			"caster":
				if Classes.ALL.get(def.get("class", ""), {}).get("caster", "") == "" and not feats_of(def, lv - 1).has("magicInitiate"):
					errs.append("%s needs the ability to cast a spell." % f.name)
			"armor":
				if not armor_type_allowed(def, req.armor, lv - 1):
					errs.append("%s needs %s armor proficiency." % [f.name, req.armor])
			"int_or_wis":
				if ab.int < 13 and ab.wis < 13:
					errs.append("%s needs Intelligence or Wisdom 13." % f.name)
			_:
				if ab.get(k, 0) < int(req[k]):
					errs.append("%s needs %s %d." % [f.name, Stats.ABILITY_NAMES[k], req[k]])
	var picks: Array = inc.get("picks", [])
	var pick: Array = f.get("pick", [])
	if pick.is_empty():
		return errs
	var unique := {}
	for x in picks:
		unique[x] = true
	if picks.size() != pick[1] or unique.size() != picks.size():
		errs.append("%s: choose %d different options." % [f.name, pick[1]])
		return errs
	for i in picks.size():
		var x: String = picks[i]
		var ok := true
		match pick[0]:
			"skills": ok = Stats.SKILLS.has(x)
			"languages": ok = LANGUAGES.has(x)
			"weapons": ok = Equipment.WEAPONS.has(x)
			"damage_type": ok = ADEPT_TYPES.has(x)
			"maneuvers": ok = MANEUVERS.has(x)
			_: ok = SPELL_FEAT_CLASSES.has(inc.get("class", "")) and feat_spells(inc.class, feat_spell_slots(inc.feat)[i]).has(x)
		if not ok:
			errs.append("%s: %s isn't a valid choice." % [f.name, x])
	return errs


# ---------------- Multiclassing ----------------
# def.class is the first class and def.level the character level; def.classes lists any others as
# [{"class": id, "levels": n}]. The first class has whatever levels are left over.

## Ability scores (13+) needed to multiclass into or out of a class. A list inside means "any of".
const MULTICLASS_REQ := {
	"barbarian": ["str"], "bard": ["cha"], "cleric": ["wis"], "druid": ["wis"], "fighter": [["str", "dex"]],
	"monk": ["dex", "wis"], "paladin": ["str", "cha"], "ranger": ["dex", "wis"], "rogue": ["dex"],
	"sorcerer": ["cha"], "warlock": ["cha"], "wizard": ["int"],
}
## What a class grants when taken as a later class: [armor types, weapons, extra skills from its list].
const MULTICLASS_PROFS := {
	"barbarian": [["shield"], ["simple", "martial"], 0], "bard": [["light"], [], 1], "cleric": [["light", "medium", "shield"], [], 0],
	"druid": [["light", "medium", "shield"], [], 0], "fighter": [["light", "medium", "shield"], ["simple", "martial"], 0],
	"monk": [[], ["simple", "shortsword"], 0], "paladin": [["light", "medium", "shield"], ["simple", "martial"], 0],
	"ranger": [["light", "medium", "shield"], ["simple", "martial"], 1], "rogue": [["light"], [], 1],
	"sorcerer": [[], [], 0], "warlock": [["light"], ["simple"], 0], "wizard": [[], [], 0],
}


## {class id: levels}, first class first.
static func class_levels(def: Dictionary) -> Dictionary:
	var out := {}
	var rest := int(def.get("level", 1))
	for e in def.get("classes", []):
		rest -= int(e.get("levels", 0))
	out[def.get("class", "")] = rest
	for e in def.get("classes", []):
		out[e.get("class", "")] = out.get(e.get("class", ""), 0) + int(e.get("levels", 0))
	return out


## Levels the character has in `cls` (0 if none).
static func lv_in(def: Dictionary, cls: String) -> int:
	return class_levels(def).get(cls, 0)


static func is_multiclass(def: Dictionary) -> bool:
	return not def.get("classes", []).is_empty()


## Can a character with these scores take (or leave) `cls`? "" if so, else why not.
static func multiclass_req_error(scores: Dictionary, cls: String) -> String:
	for need in MULTICLASS_REQ.get(cls, []):
		var any: Array = need if need is Array else [need]
		if not any.any(func(k): return int(scores.get(k, 10)) >= 13):
			return "%s needs %s 13" % [Classes.ALL[cls].name, " or ".join(any.map(func(k): return Stats.ABILITY_NAMES[k]))]
	return ""


## Problems with def.classes, including the ability prerequisites for every class involved.
static func multiclass_errors(def: Dictionary) -> Array:
	if not is_multiclass(def):
		return []
	var errs := []
	var levels := class_levels(def)
	if levels.get(def.get("class", ""), 0) < 1:
		errs.append("Your first class needs at least one level.")
	var seen := [def.get("class", "")]
	for e in def.classes:
		var c: String = e.get("class", "")
		if not Classes.ALL.has(c) or seen.has(c) or int(e.get("levels", 0)) < 1:
			errs.append("Each extra class must be a different class with at least one level.")
			return errs
		seen.append(c)
	var scores := final_abilities(def, int(def.get("level", 1)))
	for c in levels:
		var why := multiclass_req_error(scores, c)
		if why != "":
			errs.append("Multiclassing: %s." % why)
	return errs


## Character levels at which ASIs fall. Shortcut: assumes the first class's levels were taken first,
## then each extra class in order; a level-up history would let a character interleave them.
static func asi_char_levels(def: Dictionary) -> Array:
	if not is_multiclass(def):
		return asi_levels(def.get("class", ""))
	var out := []
	var start := 0
	var levels := class_levels(def)
	for c in levels:
		for l in asi_levels(c):
			if l <= levels[c]:
				out.append(start + l)
		start += levels[c]
	out.sort()
	return out


## Class skill picks: [count, allowed list], including one extra skill from bard, ranger or rogue taken later.
static func skill_choice(def: Dictionary) -> Array:
	var pick := class_skill_choice(def.get("class", ""))
	var n: int = pick[0]
	var list: Array = pick[1].duplicate()
	for e in def.get("classes", []):
		var extra: int = MULTICLASS_PROFS.get(e.get("class", ""), [[], [], 0])[2]
		if extra > 0:
			n += extra
			for sk in class_skill_choice(e.class)[1]:
				if not list.has(sk):
					list.append(sk)
	return [n, list]


## Expertise picks from every class.
static func expertise_total(def: Dictionary) -> int:
	var n := 0
	var levels := class_levels(def)
	for c in levels:
		n += expertise_count(c, levels[c])
	return n


## The class whose Fighting Style list applies ("" if none needs a style).
static func style_class(def: Dictionary) -> String:
	var levels := class_levels(def)
	for c in levels:
		if needs_style(c, levels[c]):
			return c
	return ""


## Casting classes and their levels, first class first.
static func casting_classes(def: Dictionary) -> Dictionary:
	var out := {}
	var levels := class_levels(def)
	for c in levels:
		if max_spell_level(c, levels[c]) >= 0 or cantrip_limit(c, levels[c]) > 0:
			out[c] = levels[c]
	return out


## Which of the character's casting classes knows `sid` ("" if none can). Lists are tried in order.
static func spell_owner(def: Dictionary, sid: String) -> String:
	var sp := Spells.get_spell(sid)
	var casters := casting_classes(def)
	for c in casters:
		if sp.get("classes", []).has(c) and sp.get("level", 99) <= maxi(0, max_spell_level(c, casters[c])) \
				and (sp.level > 0 or cantrip_limit(c, casters[c]) > 0):
			return c
	return ""


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


## Feats taken through `level`, in level order.
static func feats_of(def: Dictionary, level: int) -> Array:
	var out := []
	for lv in asi_char_levels(def):
		if lv <= level and asi_at(def, lv).has("feat"):
			out.append(asi_at(def, lv).feat)
	return out


## The ASI entry where a feat was taken through `level` ({} if it wasn't).
static func feat_entry(def: Dictionary, level: int, feat: String) -> Dictionary:
	for lv in asi_char_levels(def):
		if lv <= level and asi_at(def, lv).get("feat", "") == feat:
			return asi_at(def, lv)
	return {}


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
	for lv in asi_char_levels(def):
		if lv > level:
			continue
		var inc := asi_scores(asi_at(def, lv))
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
	for lv in asi_char_levels(def):
		if lv > level:
			continue
		var inc := asi_scores(asi_at(def, lv))
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


## Spells a bard may take from any class's list (Magical Secrets), and how many of those don't
## count against spells known (Lore's Additional Magical Secrets).
static func secrets_count(cls: String, level: int) -> int:
	if cls != "bard":
		return 0
	return (2 if level >= 6 else 0) + (2 if level >= 10 else 0) + (2 if level >= 14 else 0) + (2 if level >= 18 else 0)


static func free_secrets(cls: String, level: int) -> int:
	return 2 if cls == "bard" and level >= 6 else 0


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
static func spell_limit(def: Dictionary, level: int, cls: String = "") -> int:
	var ab := final_abilities(def, int(def.get("level", level)) if cls != "" else level)
	if cls == "":
		cls = def.get("class", "")
	if SPELLS_KNOWN.has(cls):
		return SPELLS_KNOWN[cls][clampi(level, 1, 20)]
	match cls:
		"cleric", "druid": return maxi(1, Stats.mod(ab.wis) + level)
		"wizard": return maxi(1, Stats.mod(ab.int) + level)
		"paladin": return 0 if level < 2 else maxi(1, Stats.mod(ab.cha) + level / 2)
	return 0


static func always_prepared(def: Dictionary, level: int) -> Array:
	var out := []
	var levels := class_levels(def.merged({"level": level}, true))
	for id in levels:
		var cls: Dictionary = Classes.ALL.get(id, {})
		if cls.is_empty() or levels[id] < cls.subclass.level:
			continue
		for row in ALWAYS_PREPARED.get(cls.subclass.id, []):
			if levels[id] >= row[0] and not out.has(row[1]):
				out.append(row[1])
	return out


## `extra`: armor types granted by feats (see feat_armor).
static func armor_allowed(cls: String, armor_id: String, extra: Array = []) -> bool:
	if armor_id == "":
		return true
	var a: Dictionary = Equipment.ARMOR.get(armor_id, {})
	return not a.is_empty() and (Classes.ALL.get(cls, {}).get("armor", []).has(a.type) or extra.has(a.type))


static func shield_allowed(cls: String, extra: Array = []) -> bool:
	return Classes.ALL.get(cls, {}).get("armor", []).has("shield") or extra.has("shield")


## Armor proficiency of a type by `level`, from class or earlier feats.
static func armor_type_allowed(def: Dictionary, type: String, level: int) -> bool:
	var d := def.duplicate()
	d["level"] = level
	return Classes.ALL.get(def.get("class", ""), {}).get("armor", []).has(type) or feat_armor(d).has(type)


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
	errs.append_array(multiclass_errors(def))
	var clv := lv_in(def, cls)  # levels in the first class

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
	for lv in asi_char_levels(def):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		if inc.has("feat"):
			errs.append_array(feat_errors(def, lv, inc))
			continue
		var total := 0
		for ab in inc:
			if not Stats.ABILITIES.has(ab) or int(inc[ab]) < 0 or int(inc[ab]) > 2:
				errs.append("Invalid Ability Score Improvement at level %d." % lv)
			total += int(inc[ab])
		if total != 2:
			errs.append("Level %d: choose your Ability Score Improvement (+2 to one, or +1 to two)." % lv)

	# Skills.
	var pick: Array = skill_choice(def)
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
	if exp.size() != expertise_total(def):
		errs.append("Choose %d skills for Expertise." % expertise_total(def))
	for sk in exp:
		if not seen.has(sk):
			errs.append("Expertise needs a skill you're proficient in (%s)." % Stats.skill_label(sk))

	# Class options.
	var sty := style_class(def)
	if sty != "" and not STYLES[sty].has(def.get("style", "")):
		errs.append("Choose a fighting style.")
	if lv_in(def, "fighter") >= 10 and (not STYLES.fighter.has(def.get("style2", "")) or def.get("style2", "") == def.get("style", "")):
		errs.append("Choose a different second fighting style.")
	var opts: Array = def.get("options", [])
	var inv := opts.filter(func(o): return INVOCATIONS.has(o))
	var meta := opts.filter(func(o): return METAMAGIC.has(o))
	if inv.size() > invocation_count(lv_in(def, "warlock")):
		errs.append("Too many invocations (%d allowed)." % invocation_count(lv_in(def, "warlock")))
	if lv_in(def, "warlock") == 0 and not inv.is_empty():
		errs.append("Only warlocks take invocations.")
	for g in OPTION_GROUPS:
		var n := opts.filter(func(o): return g[1].has(o)).size()
		var want := group_count(g, def)
		if n != want:
			errs.append("Choose %d %s option%s." % [want, g[0], "" if want == 1 else "s"] if want > 0 else "Only %s of level %d+ choose a %s." % [Classes.ALL[g[2]].name.to_lower() + "s", g[3], g[0]])
	if def.has("pact_weapon") and not (Equipment.WEAPONS.get(def.pact_weapon, {}).get("kind", "") == "melee"):
		errs.append("The pact weapon must be a melee weapon.")
	var tome: Array = def.get("tome_cantrips", [])
	if tome.size() > (3 if opts.has("pact_tome") else 0) or tome.any(func(s): return Spells.get_spell(s).get("level", 1) != 0):
		errs.append("Pact of the Tome gives three cantrips from any class.")
	if meta.size() > metamagic_count(lv_in(def, "sorcerer")):
		errs.append("Too many metamagic options (%d allowed)." % metamagic_count(lv_in(def, "sorcerer")))
	if lv_in(def, "sorcerer") == 0 and not meta.is_empty():
		errs.append("Only sorcerers take metamagic.")
	if (race == "dragonborn" or lv_in(def, "sorcerer") > 0) and not Classes.DRACONIC_ANCESTRY.has(def.get("ancestry", "")):
		errs.append("Choose a draconic ancestry.")
	if lv_in(def, "warlock") >= 10 and not Stats.DAMAGE_TYPES.has(def.get("fiend_resist", "fire")):
		errs.append("Choose a damage type for Fiendish Resilience.")

	# Equipment.
	if not armor_allowed(cls, def.get("armor", ""), feat_armor(def)):
		errs.append("%s isn't proficient with that armor." % Classes.ALL[cls].name)
	if def.get("shield", false) and not shield_allowed(cls, feat_armor(def)):
		errs.append("%s isn't proficient with shields." % Classes.ALL[cls].name)
	var weapons: Array = def.get("weapons", [])
	if weapons.size() > 8:
		errs.append("Carry at most 8 weapons.")
	for w in weapons:
		if not Equipment.WEAPONS.has(w):
			errs.append("Unknown weapon %s." % w)

	# Spells.
	if is_multiclass(def):
		errs.append_array(_multiclass_spell_errors(def))
	else:
		var max_lv := max_spell_level(cls, level)
		var auto := always_prepared(def, level)
		var cantrips := 0
		var leveled := 0
		var secrets := 0
		var free_left := free_secrets(cls, level)
		for sid in def.get("spells", []):
			var sp := Spells.get_spell(sid)
			if sp.is_empty():
				errs.append("Unknown spell %s." % sid)
				continue
			if not sp.classes.has(cls) and not auto.has(sid):
				secrets += 1
				if secrets > secrets_count(cls, level):
					errs.append("%s isn't on the %s spell list." % [sp.name, Classes.ALL[cls].name])
				elif sp.level > 0 and free_left > 0:
					free_left -= 1
					leveled -= 1  # Additional Magical Secrets don't count against spells known
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
	if Items.attuned_count(def.get("items", [])) > Items.MAX_ATTUNED:
		errs.append("A character can be attuned to at most %d magic items." % Items.MAX_ATTUNED)
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
	var mc := []
	var taken := level - 1  # the first class keeps at least one level
	for e in def.get("classes", []):
		var c: String = e.get("class", "") if e is Dictionary else ""
		var lv := mini(int(e.get("levels", 0)) if e is Dictionary else 0, taken)
		if Classes.ALL.has(c) and c != cls and lv > 0 and not mc.any(func(x): return x.class == c):
			mc.append({"class": c, "levels": lv})
			taken -= lv
	if mc.is_empty():
		def.erase("classes")
	else:
		def["classes"] = mc
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
	for lv in asi_char_levels(def):
		if lv > level:
			continue
		var inc := asi_at(def, lv)
		if FEATS.has(inc.get("feat", "")):
			asi[lv] = inc
			continue
		var total := 0
		for ab in inc:
			total += int(inc[ab])
		asi[lv] = inc if total == 2 else {_ability_priority(cls)[0]: 2}
	def["asi"] = asi
	# Skills: split the old flat list into class picks, then background, then race choices.
	var pool: Array = src.get("skills", []).duplicate()
	var pick := skill_choice(def)
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
		if exp.size() < expertise_total(def) and used.has(sk) and not exp.has(sk):
			exp.append(sk)
	def["expertise"] = exp
	var sty := style_class(def)
	if sty != "" and not STYLES[sty].has(def.get("style", "")):
		def["style"] = STYLES[sty][0]
	if lv_in(def, "fighter") >= 10:
		if not STYLES.fighter.has(def.get("style2", "")) or def.style2 == def.style:
			def["style2"] = STYLES.fighter.filter(func(s): return s != def.style)[0]
	else:
		def.erase("style2")
	var opts := []
	var inv_n := 0
	var meta_n := 0
	for o in def.get("options", []):
		if INVOCATIONS.has(o) and inv_n < invocation_count(lv_in(def, "warlock")):
			opts.append(o)
			inv_n += 1
		elif METAMAGIC.has(o) and meta_n < metamagic_count(lv_in(def, "sorcerer")):
			opts.append(o)
			meta_n += 1
	for g in OPTION_GROUPS:
		var want := group_count(g, def)
		var picked: Array = def.get("options", []).filter(func(o): return g[1].has(o)).slice(0, want)
		for k in g[1]:  # fill missing picks in the order the choices are listed
			if picked.size() < want and not picked.has(k):
				picked.append(k)
		opts.append_array(picked)
	if not opts.has("pact_tome"):
		def.erase("tome_cantrips")
	if not opts.has("pact_blade"):
		def.erase("pact_weapon")
	elif Equipment.WEAPONS.get(def.get("pact_weapon", ""), {}).get("kind", "") != "melee":
		def["pact_weapon"] = "longsword"
	def["options"] = opts
	if not armor_allowed(cls, def.get("armor", ""), feat_armor(def)):
		def["armor"] = ""
	if def.get("shield", false) and not shield_allowed(cls, feat_armor(def)):
		def["shield"] = false
	# Spells: keep legal ones up to the limits, in order.
	var spells := []
	if is_multiclass(def):
		spells = _multiclass_spells(def)
	else:
		var auto := always_prepared(def, level)
		var max_lv := max_spell_level(cls, level)
		var n_cantrips := 0
		var n_spells := 0
		var n_secrets := 0
		var free_left := free_secrets(cls, level)
		for sid in def.get("spells", []):
			var sp := Spells.get_spell(sid)
			if sp.is_empty() or sp.level > max_lv or spells.has(sid) or auto.has(sid):
				continue
			if not sp.classes.has(cls):
				if n_secrets >= secrets_count(cls, level):
					continue
				n_secrets += 1
				if sp.level > 0 and free_left > 0:
					free_left -= 1
					spells.append(sid)
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


## Multiclass spells: each spell belongs to the first of your casting classes that can know it, and
## counts against that class's own limits (cantrips and spells known/prepared at its class level).
static func _multiclass_spell_tally(def: Dictionary) -> Dictionary:
	var casters := casting_classes(def)
	var auto := always_prepared(def, int(def.level))
	var used := {}
	for c in casters:
		used[c] = [0, 0]
	var kept := []
	var errs := []
	for sid in def.get("spells", []):
		var sp := Spells.get_spell(sid)
		var owner := spell_owner(def, sid)
		if sp.is_empty() or owner == "":
			errs.append("%s isn't a spell any of your classes can know at their levels." % sp.get("name", sid))
			continue
		if kept.has(sid) or auto.has(sid):
			continue
		var k := 0 if sp.level == 0 else 1
		var limit := cantrip_limit(owner, casters[owner]) if k == 0 else spell_limit(def, casters[owner], owner)
		if used[owner][k] >= limit:
			errs.append("Too many %s %s (%d allowed)." % [Classes.ALL[owner].name, "cantrips" if k == 0 else "spells", limit])
			continue
		used[owner][k] += 1
		kept.append(sid)
	return {"spells": kept, "errors": errs}


static func _multiclass_spell_errors(def: Dictionary) -> Array:
	return _multiclass_spell_tally(def).errors


static func _multiclass_spells(def: Dictionary) -> Array:
	return _multiclass_spell_tally(def).spells
