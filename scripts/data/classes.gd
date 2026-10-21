class_name Classes
extends RefCounted
## The twelve PHB (2014) classes, with the SRD subclass for each.
## `features` lists what the class gets at each level; `auto` marks ones the engine runs for you.

const FULL_CASTER_SLOTS := [
	[], [2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2], [4, 3, 3, 3, 1],
	[4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1], [4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1],
]
const HALF_CASTER_SLOTS := [
	[], [], [2], [3], [3], [4, 2], [4, 2], [4, 3], [4, 3], [4, 3, 2], [4, 3, 2], [4, 3, 3], [4, 3, 3],
	[4, 3, 3, 1], [4, 3, 3, 1], [4, 3, 3, 2], [4, 3, 3, 2], [4, 3, 3, 3, 1], [4, 3, 3, 3, 1], [4, 3, 3, 3, 2], [4, 3, 3, 3, 2],
]
# [slot count, slot level]
const PACT_SLOTS := [
	[0, 0], [1, 1], [2, 1], [2, 2], [2, 2], [2, 3], [2, 3], [2, 4], [2, 4], [2, 5], [2, 5],
	[3, 5], [3, 5], [3, 5], [3, 5], [3, 5], [3, 5], [4, 5], [4, 5], [4, 5], [4, 5],
]

const ALL := {
	"barbarian": {"name": "Barbarian", "hit_die": 12, "saves": ["str", "con"], "caster": "", "spell_ability": "",
		"armor": ["light", "medium", "shield"], "weapons": ["simple", "martial"],
		"subclass": {"id": "berserker", "name": "Path of the Berserker", "level": 3},
		"features": [
			[1, "Rage", "Bonus action: +2 melee damage with Strength, resistance to bludgeoning/piercing/slashing, advantage on Strength checks and saves. 1 minute.", true],
			[1, "Unarmored Defense", "AC = 10 + Dex + Con without armor.", true],
			[2, "Reckless Attack", "Advantage on Strength melee attacks this turn; attacks against you have advantage until your next turn.", true],
			[2, "Danger Sense", "Advantage on Dexterity saves against effects you can see.", true],
			[3, "Frenzy", "Rage in a frenzy: make a melee weapon attack as a bonus action each turn; gain exhaustion when it ends.", true],
			[4, "Ability Score Improvement", "", true],
			[5, "Extra Attack", "Attack twice with the Attack action.", true],
			[5, "Fast Movement", "+10 ft speed without heavy armor.", true],
		]},
	"bard": {"name": "Bard", "hit_die": 8, "saves": ["dex", "cha"], "caster": "full", "spell_ability": "cha",
		"armor": ["light"], "weapons": ["simple", "hand_crossbow", "longsword", "rapier", "shortsword"],
		"subclass": {"id": "lore", "name": "College of Lore", "level": 3},
		"features": [
			[1, "Spellcasting", "Charisma spellcasting.", true],
			[1, "Bardic Inspiration", "Bonus action: give a creature within 60 ft an inspiration die (d6, d8 at 5th) to add to an attack or save. Used automatically when it would help.", true],
			[2, "Jack of All Trades", "Add half proficiency to ability checks you aren't proficient in (including initiative).", true],
			[2, "Song of Rest", "Extra healing during short rests.", false],
			[3, "Cutting Words", "Reaction: subtract an inspiration die from an enemy's attack roll. Used automatically.", true],
			[3, "Expertise", "Double proficiency in two skills.", true],
			[4, "Ability Score Improvement", "", true],
			[5, "Font of Inspiration", "Bardic Inspiration recharges on a short rest.", true],
		]},
	"cleric": {"name": "Cleric", "hit_die": 8, "saves": ["wis", "cha"], "caster": "full", "spell_ability": "wis",
		"armor": ["light", "medium", "heavy", "shield"], "weapons": ["simple"],
		"subclass": {"id": "life", "name": "Life Domain", "level": 1},
		"features": [
			[1, "Spellcasting", "Wisdom spellcasting.", true],
			[1, "Disciple of Life", "Healing spells restore an extra 2 + spell level hit points.", true],
			[2, "Channel Divinity: Turn Undead", "Action: undead within 30 ft make a Wisdom save or are turned for 1 minute.", true],
			[2, "Channel Divinity: Preserve Life", "Action: restore 5 x cleric level hit points split among creatures within 30 ft (up to half their max).", true],
			[4, "Ability Score Improvement", "", true],
			[5, "Destroy Undead", "Turned undead of CR 1/2 or lower are destroyed.", true],
		]},
	"druid": {"name": "Druid", "hit_die": 8, "saves": ["int", "wis"], "caster": "full", "spell_ability": "wis",
		"armor": ["light", "medium", "shield"], "weapons": ["club", "dagger", "dart", "javelin", "mace", "quarterstaff", "scimitar", "sickle", "sling", "spear"],
		"subclass": {"id": "land", "name": "Circle of the Land", "level": 2},
		"features": [
			[1, "Spellcasting", "Wisdom spellcasting.", true],
			[2, "Wild Shape", "Turn into a beast. (Not automated yet: the DM can add a beast token.)", false],
			[2, "Natural Recovery", "Recover spell slots on a short rest.", false],
			[4, "Ability Score Improvement", "", true],
		]},
	"fighter": {"name": "Fighter", "hit_die": 10, "saves": ["str", "con"], "caster": "", "spell_ability": "",
		"armor": ["light", "medium", "heavy", "shield"], "weapons": ["simple", "martial"],
		"subclass": {"id": "champion", "name": "Champion", "level": 3},
		"features": [
			[1, "Fighting Style", "Archery, Defense, Dueling, Great Weapon Fighting or Two-Weapon Fighting.", true],
			[1, "Second Wind", "Bonus action: regain 1d10 + fighter level HP. Short rest.", true],
			[2, "Action Surge", "Take one additional action this turn. Short rest.", true],
			[3, "Improved Critical", "Critical hits on 19-20.", true],
			[4, "Ability Score Improvement", "", true],
			[5, "Extra Attack", "Attack twice with the Attack action.", true],
		]},
	"monk": {"name": "Monk", "hit_die": 8, "saves": ["str", "dex"], "caster": "", "spell_ability": "",
		"armor": [], "weapons": ["simple", "shortsword"],
		"subclass": {"id": "open_hand", "name": "Way of the Open Hand", "level": 3},
		"features": [
			[1, "Unarmored Defense", "AC = 10 + Dex + Wis without armor or shield.", true],
			[1, "Martial Arts", "Use Dex for unarmed strikes and monk weapons, martial arts die damage, bonus-action unarmed strike after the Attack action.", true],
			[2, "Ki", "Flurry of Blows, Patient Defense, Step of the Wind.", true],
			[2, "Unarmored Movement", "+10 ft speed without armor.", true],
			[3, "Deflect Missiles", "Reaction: reduce ranged weapon damage by 1d10 + Dex + monk level. Used automatically.", true],
			[3, "Open Hand Technique", "Flurry of Blows hits can knock prone, push 15 ft, or deny reactions.", true],
			[4, "Ability Score Improvement", "", true],
			[4, "Slow Fall", "", false],
			[5, "Extra Attack", "Attack twice with the Attack action.", true],
			[5, "Stunning Strike", "Spend 1 ki on a melee hit: Constitution save or stunned until the end of your next turn.", true],
		]},
	"paladin": {"name": "Paladin", "hit_die": 10, "saves": ["wis", "cha"], "caster": "half", "spell_ability": "cha",
		"armor": ["light", "medium", "heavy", "shield"], "weapons": ["simple", "martial"],
		"subclass": {"id": "devotion", "name": "Oath of Devotion", "level": 3},
		"features": [
			[1, "Divine Sense", "", false],
			[1, "Lay on Hands", "Action: heal from a pool of 5 x paladin level HP.", true],
			[2, "Fighting Style", "Defense, Dueling or Great Weapon Fighting.", true],
			[2, "Spellcasting", "Charisma spellcasting.", true],
			[2, "Divine Smite", "On a melee weapon hit, spend a slot: 2d8 radiant +1d8 per slot level above 1st (+1d8 vs undead/fiends).", true],
			[3, "Channel Divinity: Sacred Weapon", "Action: add Charisma to weapon attack rolls for 1 minute.", true],
			[3, "Divine Health", "", false],
			[4, "Ability Score Improvement", "", true],
			[5, "Extra Attack", "Attack twice with the Attack action.", true],
		]},
	"ranger": {"name": "Ranger", "hit_die": 10, "saves": ["str", "dex"], "caster": "half", "spell_ability": "wis",
		"armor": ["light", "medium", "shield"], "weapons": ["simple", "martial"],
		"subclass": {"id": "hunter", "name": "Hunter", "level": 3},
		"features": [
			[1, "Favored Enemy", "", false],
			[1, "Natural Explorer", "", false],
			[2, "Fighting Style", "Archery, Defense, Dueling or Two-Weapon Fighting.", true],
			[2, "Spellcasting", "Wisdom spellcasting.", true],
			[3, "Colossus Slayer", "Once per turn, +1d8 weapon damage against a creature below its HP maximum.", true],
			[4, "Ability Score Improvement", "", true],
			[5, "Extra Attack", "Attack twice with the Attack action.", true],
		]},
	"rogue": {"name": "Rogue", "hit_die": 8, "saves": ["dex", "int"], "caster": "", "spell_ability": "",
		"armor": ["light"], "weapons": ["simple", "hand_crossbow", "longsword", "rapier", "shortsword"],
		"subclass": {"id": "thief", "name": "Thief", "level": 3},
		"features": [
			[1, "Expertise", "Double proficiency in two skills.", true],
			[1, "Sneak Attack", "Once per turn, extra damage with a finesse or ranged weapon when you have advantage or an ally is next to the target.", true],
			[2, "Cunning Action", "Bonus action Dash, Disengage or Hide.", true],
			[3, "Fast Hands", "", false],
			[4, "Ability Score Improvement", "", true],
			[5, "Uncanny Dodge", "Reaction: halve the damage of an attack that hits you. Used automatically.", true],
		]},
	"sorcerer": {"name": "Sorcerer", "hit_die": 6, "saves": ["con", "cha"], "caster": "full", "spell_ability": "cha",
		"armor": [], "weapons": ["dagger", "dart", "sling", "quarterstaff", "light_crossbow"],
		"subclass": {"id": "draconic", "name": "Draconic Bloodline", "level": 1},
		"features": [
			[1, "Spellcasting", "Charisma spellcasting.", true],
			[1, "Draconic Resilience", "+1 HP per level; AC 13 + Dex without armor.", true],
			[2, "Font of Magic", "Sorcery points: convert to and from spell slots (bonus action).", true],
			[3, "Metamagic", "Quickened Spell (cast an action spell as a bonus action) and Careful Spell (allies auto-succeed your saves).", true],
			[4, "Ability Score Improvement", "", true],
		]},
	"warlock": {"name": "Warlock", "hit_die": 8, "saves": ["wis", "cha"], "caster": "pact", "spell_ability": "cha",
		"armor": ["light"], "weapons": ["simple"],
		"subclass": {"id": "fiend", "name": "The Fiend", "level": 1},
		"features": [
			[1, "Pact Magic", "Short-rest spell slots, always cast at your highest slot level.", true],
			[1, "Dark One's Blessing", "Reduce a hostile creature to 0 HP: gain Cha + warlock level temp HP.", true],
			[2, "Eldritch Invocations", "Agonizing Blast (+Cha to Eldritch Blast damage) and Repelling Blast (push 10 ft).", true],
			[3, "Pact Boon", "", false],
			[4, "Ability Score Improvement", "", true],
		]},
	"wizard": {"name": "Wizard", "hit_die": 6, "saves": ["int", "wis"], "caster": "full", "spell_ability": "int",
		"armor": [], "weapons": ["dagger", "dart", "sling", "quarterstaff", "light_crossbow"],
		"subclass": {"id": "evocation", "name": "School of Evocation", "level": 2},
		"features": [
			[1, "Spellcasting", "Intelligence spellcasting.", true],
			[1, "Arcane Recovery", "Recover spell slots on a short rest.", true],
			[2, "Sculpt Spells", "Allies in your evocation spells automatically succeed on their saves and take no damage.", true],
			[4, "Ability Score Improvement", "", true],
		]},
}

const RACES := {
	"human": {"name": "Human", "size": "medium", "speed": 30, "asi": {"str": 1, "dex": 1, "con": 1, "int": 1, "wis": 1, "cha": 1}, "traits": []},
	"hill_dwarf": {"name": "Hill Dwarf", "size": "medium", "speed": 25, "asi": {"con": 2, "wis": 1},
		"traits": ["dwarvenResilience", "dwarvenToughness", "heavyArmorSpeed"], "resist": ["poison"]},
	"high_elf": {"name": "High Elf", "size": "medium", "speed": 30, "asi": {"dex": 2, "int": 1},
		"traits": ["feyAncestry"], "skills": ["perception"], "weapons": ["longsword", "shortsword", "shortbow", "longbow"]},
	"lightfoot_halfling": {"name": "Lightfoot Halfling", "size": "small", "speed": 25, "asi": {"dex": 2, "cha": 1},
		"traits": ["lucky", "brave", "halflingNimbleness"]},
	"dragonborn": {"name": "Dragonborn", "size": "medium", "speed": 30, "asi": {"str": 2, "cha": 1}, "traits": ["breathWeapon"]},
	"rock_gnome": {"name": "Rock Gnome", "size": "small", "speed": 25, "asi": {"int": 2, "con": 1}, "traits": ["gnomeCunning"]},
	"half_elf": {"name": "Half-Elf", "size": "medium", "speed": 30, "asi": {"cha": 2}, "flex_asi": 2, "traits": ["feyAncestry"]},
	"half_orc": {"name": "Half-Orc", "size": "medium", "speed": 30, "asi": {"str": 2, "con": 1},
		"traits": ["relentlessEndurance", "savageAttacks"], "skills": ["intimidation"]},
	"tiefling": {"name": "Tiefling", "size": "medium", "speed": 30, "asi": {"cha": 2, "int": 1}, "traits": [], "resist": ["fire"]},
}

# Dragonborn ancestry -> breath weapon.
const DRACONIC_ANCESTRY := {
	"black": {"type": "acid", "shape": "line", "save": "dex"},
	"blue": {"type": "lightning", "shape": "line", "save": "dex"},
	"brass": {"type": "fire", "shape": "line", "save": "dex"},
	"bronze": {"type": "lightning", "shape": "line", "save": "dex"},
	"copper": {"type": "acid", "shape": "line", "save": "dex"},
	"gold": {"type": "fire", "shape": "cone", "save": "dex"},
	"green": {"type": "poison", "shape": "cone", "save": "con"},
	"red": {"type": "fire", "shape": "cone", "save": "dex"},
	"silver": {"type": "cold", "shape": "cone", "save": "con"},
	"white": {"type": "cold", "shape": "cone", "save": "con"},
}


static func get_class_def(id: String) -> Dictionary:
	return ALL.get(id, {})


static func prof_bonus(level: int) -> int:
	return 2 + (maxi(level, 1) - 1) / 4


static func slots_for(caster: String, level: int) -> Array:
	var lv := clampi(level, 0, 20)
	var row: Array = []
	match caster:
		"full": row = FULL_CASTER_SLOTS[lv]
		"half": row = HALF_CASTER_SLOTS[lv]
	var out := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for i in row.size():
		out[i + 1] = row[i]
	return out


static func max_spell_level(caster: String, level: int) -> int:
	if caster == "pact":
		return PACT_SLOTS[clampi(level, 0, 20)][1]
	var slots := slots_for(caster, level)
	for i in range(9, 0, -1):
		if slots[i] > 0:
			return i
	return 0
