class_name Monsters
extends RefCounted
## SRD 5.1 monster stat blocks. Attack bonuses and damage are as printed.
## A DM-made monster is just another entry in this format.

const ALL := {
	"goblin": {"name": "Goblin", "size": "small", "type": "humanoid", "ac": 15, "hp": 7, "hit_dice": "2d6", "speed": 30, "cr": 0.25, "xp": 50,
		"abilities": {"str": 8, "dex": 14, "con": 10, "int": 10, "wis": 8, "cha": 8}, "skills": {"stealth": 6}, "passive": 9,
		"traits": ["nimbleEscape"], "color": "#6b8e23",
		"attacks": [
			{"id": "scimitar", "name": "Scimitar", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "shortbow", "name": "Shortbow", "range": "ranged", "to_hit": 4, "normal": 80, "long": 320, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["ammunition"]},
		]},
	"kobold": {"name": "Kobold", "size": "small", "type": "humanoid", "ac": 12, "hp": 5, "hit_dice": "2d6-2", "speed": 30, "cr": 0.125, "xp": 25,
		"abilities": {"str": 7, "dex": 15, "con": 9, "int": 8, "wis": 7, "cha": 8}, "passive": 8,
		"traits": ["packTactics"], "color": "#b8860b",
		"attacks": [
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d4", "bonus": 2, "type": "piercing"}], "props": ["finesse"]},
			{"id": "sling", "name": "Sling", "range": "ranged", "to_hit": 4, "normal": 30, "long": 120, "damage": [{"dice": "1d4", "bonus": 2, "type": "bludgeoning"}], "props": []},
		]},
	"bandit": {"name": "Bandit", "size": "medium", "type": "humanoid", "ac": 12, "hp": 11, "hit_dice": "2d8+2", "speed": 30, "cr": 0.125, "xp": 25,
		"abilities": {"str": 11, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#8b5a2b",
		"attacks": [
			{"id": "scimitar", "name": "Scimitar", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d6", "bonus": 1, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "light_crossbow", "name": "Light Crossbow", "range": "ranged", "to_hit": 3, "normal": 80, "long": 320, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["loading"]},
		]},
	"skeleton": {"name": "Skeleton", "size": "medium", "type": "undead", "ac": 13, "hp": 13, "hit_dice": "2d8+4", "speed": 30, "cr": 0.25, "xp": 50,
		"abilities": {"str": 10, "dex": 14, "con": 15, "int": 6, "wis": 8, "cha": 5}, "passive": 9, "color": "#d8d0b8",
		"vulnerabilities": ["bludgeoning"], "immunities": ["poison"], "condition_immunities": ["poisoned"],
		"attacks": [
			{"id": "shortsword", "name": "Shortsword", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "shortbow", "name": "Shortbow", "range": "ranged", "to_hit": 4, "normal": 80, "long": 320, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": []},
		]},
	"zombie": {"name": "Zombie", "size": "medium", "type": "undead", "ac": 8, "hp": 22, "hit_dice": "3d8+9", "speed": 20, "cr": 0.25, "xp": 50,
		"abilities": {"str": 13, "dex": 6, "con": 16, "int": 3, "wis": 6, "cha": 5}, "passive": 8, "color": "#5f7a5a",
		"save_profs": ["wis"], "immunities": ["poison"], "condition_immunities": ["poisoned"], "traits": ["undeadFortitude"],
		"attacks": [
			{"id": "slam", "name": "Slam", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d6", "bonus": 1, "type": "bludgeoning"}], "props": ["natural"]},
		]},
	"wolf": {"name": "Wolf", "size": "medium", "type": "beast", "ac": 13, "hp": 11, "hit_dice": "2d8+2", "speed": 40, "cr": 0.25, "xp": 50,
		"abilities": {"str": 12, "dex": 15, "con": 12, "int": 3, "wis": 12, "cha": 6}, "skills": {"perception": 3, "stealth": 4}, "passive": 13,
		"traits": ["packTactics"], "color": "#7d7d7d",
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "2d4", "bonus": 2, "type": "piercing"}], "props": ["natural"],
				"on_hit": {"ability": "str", "dc": 11, "condition": "prone"}},
		]},
	"orc": {"name": "Orc", "size": "medium", "type": "humanoid", "ac": 13, "hp": 15, "hit_dice": "2d8+6", "speed": 30, "cr": 0.5, "xp": 100,
		"abilities": {"str": 16, "dex": 12, "con": 16, "int": 7, "wis": 11, "cha": 10}, "skills": {"intimidation": 2}, "passive": 10,
		"traits": ["aggressive"], "color": "#4f7942",
		"attacks": [
			{"id": "greataxe", "name": "Greataxe", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d12", "bonus": 3, "type": "slashing"}], "props": ["heavy", "twoHanded"]},
			{"id": "javelin", "name": "Javelin", "range": "ranged", "to_hit": 5, "normal": 30, "long": 120, "damage": [{"dice": "1d6", "bonus": 3, "type": "piercing"}], "props": ["thrown"]},
		]},
	"ghoul": {"name": "Ghoul", "size": "medium", "type": "undead", "ac": 12, "hp": 22, "hit_dice": "5d8", "speed": 30, "cr": 1.0, "xp": 200,
		"abilities": {"str": 13, "dex": 15, "con": 10, "int": 7, "wis": 10, "cha": 6}, "passive": 10, "color": "#8f9779",
		"immunities": ["poison"], "condition_immunities": ["charmed", "poisoned"],
		"multiattack": ["bite", "claws"],
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "2d6", "bonus": 2, "type": "piercing"}], "props": ["natural"]},
			{"id": "claws", "name": "Claws", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "2d4", "bonus": 2, "type": "slashing"}], "props": ["natural"],
				"on_hit": {"ability": "con", "dc": 10, "immune_types": ["undead"], "immune_traits": ["feyAncestry"],
					"effect": {"name": "Ghoul Paralysis", "conditions": ["paralyzed"], "repeat_save": {"ability": "con", "dc": 10, "phase": "end"}, "expires_on": {"who": "target", "phase": "end", "count": 10}}}},
		]},
	"giant_spider": {"name": "Giant Spider", "size": "large", "type": "beast", "ac": 14, "hp": 26, "hit_dice": "4d10+4", "speed": 30, "cr": 1.0, "xp": 200,
		"abilities": {"str": 14, "dex": 16, "con": 12, "int": 2, "wis": 11, "cha": 4}, "skills": {"stealth": 7}, "passive": 10, "color": "#2f2f3f",
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d8", "bonus": 3, "type": "piercing"}], "props": ["natural"],
				"on_hit": {"ability": "con", "dc": 11, "damage": [{"dice": "2d8", "type": "poison"}], "half": true}},
			{"id": "web", "name": "Web (Recharge 5-6)", "range": "ranged", "to_hit": 5, "normal": 30, "long": 60, "damage": [], "props": [], "recharge": 5, "standalone": true,
				"hit_effect": {"name": "Webbed", "conditions": ["restrained"], "escape": {"dc": 12, "abilities": ["str"]}}},
		]},
	"bandit_captain": {"name": "Bandit Captain", "size": "medium", "type": "humanoid", "ac": 15, "hp": 65, "hit_dice": "10d8+20", "speed": 30, "cr": 2.0, "xp": 450,
		"abilities": {"str": 15, "dex": 16, "con": 14, "int": 14, "wis": 11, "cha": 14}, "skills": {"athletics": 4, "deception": 4}, "passive": 10,
		"save_profs": ["str", "dex", "wis"], "traits": ["parry"], "color": "#8b0000",
		"multiattack": ["scimitar", "scimitar", "dagger"],
		"attacks": [
			{"id": "scimitar", "name": "Scimitar", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d6", "bonus": 3, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d4", "bonus": 3, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "dagger_thrown", "name": "Dagger (thrown)", "range": "ranged", "to_hit": 5, "normal": 20, "long": 60, "damage": [{"dice": "1d4", "bonus": 3, "type": "piercing"}], "props": ["thrown"]},
		]},
	"ogre": {"name": "Ogre", "size": "large", "type": "giant", "ac": 11, "hp": 59, "hit_dice": "7d10+21", "speed": 40, "cr": 2.0, "xp": 450,
		"abilities": {"str": 19, "dex": 8, "con": 16, "int": 5, "wis": 7, "cha": 7}, "passive": 8, "color": "#a0785a",
		"attacks": [
			{"id": "greatclub", "name": "Greatclub", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "2d8", "bonus": 4, "type": "bludgeoning"}], "props": ["twoHanded"]},
			{"id": "javelin", "name": "Javelin", "range": "ranged", "to_hit": 6, "normal": 30, "long": 120, "damage": [{"dice": "2d6", "bonus": 4, "type": "piercing"}], "props": ["thrown"]},
		]},
	"owlbear": {"name": "Owlbear", "size": "large", "type": "monstrosity", "ac": 13, "hp": 59, "hit_dice": "7d10+21", "speed": 40, "cr": 3.0, "xp": 700,
		"abilities": {"str": 20, "dex": 12, "con": 17, "int": 3, "wis": 12, "cha": 7}, "skills": {"perception": 3}, "passive": 13, "color": "#8b6f47",
		"multiattack": ["beak", "claws"],
		"attacks": [
			{"id": "beak", "name": "Beak", "range": "melee", "to_hit": 7, "reach": 5, "damage": [{"dice": "1d10", "bonus": 5, "type": "piercing"}], "props": ["natural"]},
			{"id": "claws", "name": "Claws", "range": "melee", "to_hit": 7, "reach": 5, "damage": [{"dice": "2d8", "bonus": 5, "type": "slashing"}], "props": ["natural"]},
		]},
	"red_dragon_wyrmling": {"name": "Red Dragon Wyrmling", "size": "medium", "type": "dragon", "ac": 17, "hp": 75, "hit_dice": "10d8+30", "speed": 30, "cr": 4.0, "xp": 1100,
		"abilities": {"str": 19, "dex": 10, "con": 17, "int": 12, "wis": 11, "cha": 15}, "skills": {"perception": 4, "stealth": 2}, "passive": 14,
		"save_profs": ["dex", "con", "wis", "cha"], "immunities": ["fire"], "color": "#b22222",
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "1d10", "bonus": 4, "type": "piercing"}, {"dice": "1d6", "type": "fire"}], "props": ["natural"]},
		],
		"powers": [
			{"id": "fire_breath", "name": "Fire Breath (Recharge 5-6)", "dc": 13, "recharge": 5,
				"spell": {"name": "Fire Breath", "level": 0, "time": "action", "range": 0, "target": {"type": "area", "shape": "cone", "size": 15, "origin": "self"},
					"save": {"ability": "dex", "half": true}, "damage": [{"dice": "7d6", "type": "fire"}], "desc": "15-ft cone, DC 13 Dexterity save, 7d6 fire."}},
		]},
}


static func get_monster(id: String) -> Dictionary:
	return ALL.get(id, {})


static func cr_label(cr: float) -> String:
	if cr == 0.125:
		return "1/8"
	if cr == 0.25:
		return "1/4"
	if cr == 0.5:
		return "1/2"
	return str(int(cr))
