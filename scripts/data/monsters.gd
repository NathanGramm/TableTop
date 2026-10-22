class_name Monsters
extends RefCounted
## SRD 5.1 monster stat blocks. Attack bonuses and damage are as printed.
## A DM-made monster is just another entry in this format.

const ALL := {
	"goblin": {"darkvision": 60, "name": "Goblin", "size": "small", "type": "humanoid", "ac": 15, "hp": 7, "hit_dice": "2d6", "speed": 30, "cr": 0.25, "xp": 50,
		"abilities": {"str": 8, "dex": 14, "con": 10, "int": 10, "wis": 8, "cha": 8}, "skills": {"stealth": 6}, "passive": 9,
		"traits": ["nimbleEscape"], "color": "#6b8e23",
		"attacks": [
			{"id": "scimitar", "name": "Scimitar", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "shortbow", "name": "Shortbow", "range": "ranged", "to_hit": 4, "normal": 80, "long": 320, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["ammunition"]},
		]},
	"kobold": {"darkvision": 60, "name": "Kobold", "size": "small", "type": "humanoid", "ac": 12, "hp": 5, "hit_dice": "2d6-2", "speed": 30, "cr": 0.125, "xp": 25,
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
	"skeleton": {"darkvision": 60, "name": "Skeleton", "size": "medium", "type": "undead", "ac": 13, "hp": 13, "hit_dice": "2d8+4", "speed": 30, "cr": 0.25, "xp": 50,
		"abilities": {"str": 10, "dex": 14, "con": 15, "int": 6, "wis": 8, "cha": 5}, "passive": 9, "color": "#d8d0b8",
		"vulnerabilities": ["bludgeoning"], "immunities": ["poison"], "condition_immunities": ["poisoned"],
		"attacks": [
			{"id": "shortsword", "name": "Shortsword", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "shortbow", "name": "Shortbow", "range": "ranged", "to_hit": 4, "normal": 80, "long": 320, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": []},
		]},
	"zombie": {"darkvision": 60, "name": "Zombie", "size": "medium", "type": "undead", "ac": 8, "hp": 22, "hit_dice": "3d8+9", "speed": 20, "cr": 0.25, "xp": 50,
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
	"orc": {"darkvision": 60, "name": "Orc", "size": "medium", "type": "humanoid", "ac": 13, "hp": 15, "hit_dice": "2d8+6", "speed": 30, "cr": 0.5, "xp": 100,
		"abilities": {"str": 16, "dex": 12, "con": 16, "int": 7, "wis": 11, "cha": 10}, "skills": {"intimidation": 2}, "passive": 10,
		"traits": ["aggressive"], "color": "#4f7942",
		"attacks": [
			{"id": "greataxe", "name": "Greataxe", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d12", "bonus": 3, "type": "slashing"}], "props": ["heavy", "twoHanded"]},
			{"id": "javelin", "name": "Javelin", "range": "ranged", "to_hit": 5, "normal": 30, "long": 120, "damage": [{"dice": "1d6", "bonus": 3, "type": "piercing"}], "props": ["thrown"]},
		]},
	"ghoul": {"darkvision": 60, "name": "Ghoul", "size": "medium", "type": "undead", "ac": 12, "hp": 22, "hit_dice": "5d8", "speed": 30, "cr": 1.0, "xp": 200,
		"abilities": {"str": 13, "dex": 15, "con": 10, "int": 7, "wis": 10, "cha": 6}, "passive": 10, "color": "#8f9779",
		"immunities": ["poison"], "condition_immunities": ["charmed", "poisoned"],
		"multiattack": ["bite", "claws"],
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "2d6", "bonus": 2, "type": "piercing"}], "props": ["natural"]},
			{"id": "claws", "name": "Claws", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "2d4", "bonus": 2, "type": "slashing"}], "props": ["natural"],
				"on_hit": {"ability": "con", "dc": 10, "immune_types": ["undead"], "immune_traits": ["feyAncestry"],
					"effect": {"name": "Ghoul Paralysis", "conditions": ["paralyzed"], "repeat_save": {"ability": "con", "dc": 10, "phase": "end"}, "expires_on": {"who": "target", "phase": "end", "count": 10}}}},
		]},
	"giant_spider": {"darkvision": 60, "blindsight": 10, "name": "Giant Spider", "size": "large", "type": "beast", "ac": 14, "hp": 26, "hit_dice": "4d10+4", "speed": 30, "cr": 1.0, "xp": 200,
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
	"ogre": {"darkvision": 60, "name": "Ogre", "size": "large", "type": "giant", "ac": 11, "hp": 59, "hit_dice": "7d10+21", "speed": 40, "cr": 2.0, "xp": 450,
		"abilities": {"str": 19, "dex": 8, "con": 16, "int": 5, "wis": 7, "cha": 7}, "passive": 8, "color": "#a0785a",
		"attacks": [
			{"id": "greatclub", "name": "Greatclub", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "2d8", "bonus": 4, "type": "bludgeoning"}], "props": ["twoHanded"]},
			{"id": "javelin", "name": "Javelin", "range": "ranged", "to_hit": 6, "normal": 30, "long": 120, "damage": [{"dice": "2d6", "bonus": 4, "type": "piercing"}], "props": ["thrown"]},
		]},
	"owlbear": {"darkvision": 60, "name": "Owlbear", "size": "large", "type": "monstrosity", "ac": 13, "hp": 59, "hit_dice": "7d10+21", "speed": 40, "cr": 3.0, "xp": 700,
		"abilities": {"str": 20, "dex": 12, "con": 17, "int": 3, "wis": 12, "cha": 7}, "skills": {"perception": 3}, "passive": 13, "color": "#8b6f47",
		"multiattack": ["beak", "claws"],
		"attacks": [
			{"id": "beak", "name": "Beak", "range": "melee", "to_hit": 7, "reach": 5, "damage": [{"dice": "1d10", "bonus": 5, "type": "piercing"}], "props": ["natural"]},
			{"id": "claws", "name": "Claws", "range": "melee", "to_hit": 7, "reach": 5, "damage": [{"dice": "2d8", "bonus": 5, "type": "slashing"}], "props": ["natural"]},
		]},
	"red_dragon_wyrmling": {"darkvision": 60, "blindsight": 10, "name": "Red Dragon Wyrmling", "size": "medium", "type": "dragon", "ac": 17, "hp": 75, "hit_dice": "10d8+30", "speed": 30, "cr": 4.0, "xp": 1100,
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
	# People and foes that match the painted minis (assets/minis). SRD 5.1 NPC stat blocks; where the SRD has
	# no such creature the closest one is re-themed (noted per entry). Traits the engine lacks are left out.
	"knight": {"name": "Knight", "size": "medium", "type": "humanoid", "ac": 18, "hp": 52, "hit_dice": "8d8+16", "speed": 30, "cr": 3.0, "xp": 700,
		"abilities": {"str": 16, "dex": 11, "con": 14, "int": 11, "wis": 11, "cha": 15}, "passive": 10,
		"save_profs": ["con", "wis"], "traits": ["brave", "parry"], "color": "#9aa4b1",
		"multiattack": ["greatsword", "greatsword"],
		"attacks": [
			{"id": "greatsword", "name": "Greatsword", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "2d6", "bonus": 3, "type": "slashing"}], "props": ["heavy", "twoHanded"]},
			{"id": "heavy_crossbow", "name": "Heavy Crossbow", "range": "ranged", "to_hit": 2, "normal": 100, "long": 400, "damage": [{"dice": "1d10", "type": "piercing"}], "props": ["heavy", "loading", "twoHanded"]},
		]},
	"innkeeper": {"name": "Innkeeper", "size": "medium", "type": "humanoid", "ac": 10, "hp": 4, "hit_dice": "1d8", "speed": 30, "cr": 0.0, "xp": 10,  # Commoner
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#a0522d",
		"attacks": [
			{"id": "club", "name": "Club", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "1d4", "type": "bludgeoning"}], "props": ["light"]},
		]},
	"barmaid": {"name": "Barmaid", "size": "medium", "type": "humanoid", "ac": 10, "hp": 4, "hit_dice": "1d8", "speed": 30, "cr": 0.0, "xp": 10,  # Commoner
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#c08552",
		"attacks": [
			{"id": "club", "name": "Club", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "1d4", "type": "bludgeoning"}], "props": ["light"]},
		]},
	"farmer": {"name": "Farmer", "size": "medium", "type": "humanoid", "ac": 10, "hp": 4, "hit_dice": "1d8", "speed": 30, "cr": 0.0, "xp": 10,  # Commoner
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#8f8a4a",
		"attacks": [
			{"id": "pitchfork", "name": "Pitchfork", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "1d4", "type": "piercing"}], "props": []},
		]},
	"merchant": {"name": "Merchant", "size": "medium", "type": "humanoid", "ac": 10, "hp": 4, "hit_dice": "1d8", "speed": 30, "cr": 0.0, "xp": 10,  # Commoner
		"abilities": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#c9a227",
		"attacks": [
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "1d4", "type": "piercing"}], "props": ["finesse", "light"]},
		]},
	"blacksmith": {"name": "Blacksmith", "size": "medium", "type": "humanoid", "ac": 11, "hp": 32, "hit_dice": "5d8+10", "speed": 30, "cr": 0.5, "xp": 100,  # Thug
		"abilities": {"str": 15, "dex": 11, "con": 14, "int": 10, "wis": 10, "cha": 11}, "skills": {"intimidation": 2}, "passive": 10,
		"traits": ["packTactics"], "color": "#5a4632",
		"multiattack": ["hammer", "hammer"],
		"attacks": [
			{"id": "hammer", "name": "Hammer", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "bludgeoning"}], "props": []},
		]},
	"noble": {"name": "Noble", "size": "medium", "type": "humanoid", "ac": 15, "hp": 9, "hit_dice": "2d8", "speed": 30, "cr": 0.125, "xp": 25,
		"abilities": {"str": 11, "dex": 12, "con": 11, "int": 12, "wis": 14, "cha": 16}, "skills": {"deception": 5, "insight": 4, "persuasion": 5}, "passive": 12,
		"traits": ["parry"], "color": "#6a1b9a",
		"attacks": [
			{"id": "rapier", "name": "Rapier", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["finesse"]},
		]},
	"noblewoman": {"name": "Noblewoman", "size": "medium", "type": "humanoid", "ac": 15, "hp": 9, "hit_dice": "2d8", "speed": 30, "cr": 0.125, "xp": 25,  # Noble
		"abilities": {"str": 11, "dex": 12, "con": 11, "int": 12, "wis": 14, "cha": 16}, "skills": {"deception": 5, "insight": 4, "persuasion": 5}, "passive": 12,
		"traits": ["parry"], "color": "#ad1457",
		"attacks": [
			{"id": "rapier", "name": "Rapier", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["finesse"]},
		]},
	"town_guard": {"name": "Town Guard", "size": "medium", "type": "humanoid", "ac": 16, "hp": 11, "hit_dice": "2d8+2", "speed": 30, "cr": 0.125, "xp": 25,  # Guard
		"abilities": {"str": 13, "dex": 12, "con": 12, "int": 10, "wis": 11, "cha": 10}, "skills": {"perception": 2}, "passive": 12, "color": "#4a6fa5",
		"attacks": [
			{"id": "spear", "name": "Spear", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d6", "bonus": 1, "type": "piercing"}], "props": ["versatile"]},
			{"id": "spear_thrown", "name": "Spear (thrown)", "range": "ranged", "to_hit": 3, "normal": 20, "long": 60, "damage": [{"dice": "1d6", "bonus": 1, "type": "piercing"}], "props": ["thrown"]},
		]},
	"guard_captain": {"name": "Guard Captain", "size": "medium", "type": "humanoid", "ac": 17, "hp": 58, "hit_dice": "9d8+18", "speed": 30, "cr": 3.0, "xp": 700,  # Veteran
		"abilities": {"str": 16, "dex": 13, "con": 14, "int": 10, "wis": 11, "cha": 10}, "skills": {"athletics": 5, "perception": 2}, "passive": 12, "color": "#2e4a7d",
		"multiattack": ["longsword", "longsword", "shortsword"],
		"attacks": [
			{"id": "longsword", "name": "Longsword", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d8", "bonus": 3, "type": "slashing"}], "props": ["versatile"]},
			{"id": "shortsword", "name": "Shortsword", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d6", "bonus": 3, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "heavy_crossbow", "name": "Heavy Crossbow", "range": "ranged", "to_hit": 3, "normal": 100, "long": 400, "damage": [{"dice": "1d10", "bonus": 1, "type": "piercing"}], "props": ["heavy", "loading", "twoHanded"]},
		]},
	"cultist": {"name": "Cultist", "size": "medium", "type": "humanoid", "ac": 12, "hp": 9, "hit_dice": "2d8", "speed": 30, "cr": 0.125, "xp": 25,
		"abilities": {"str": 11, "dex": 12, "con": 10, "int": 10, "wis": 11, "cha": 10}, "skills": {"deception": 2, "religion": 2}, "passive": 10, "color": "#5b1a1a",
		"attacks": [
			{"id": "scimitar", "name": "Scimitar", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d6", "bonus": 1, "type": "slashing"}], "props": ["finesse", "light"]},
		]},
	"witch": {"name": "Witch", "size": "medium", "type": "humanoid", "ac": 13, "hp": 33, "hit_dice": "6d8+6", "speed": 30, "cr": 2.0, "xp": 450,  # Cult Fanatic, hexes for spells
		"abilities": {"str": 11, "dex": 14, "con": 12, "int": 10, "wis": 13, "cha": 14}, "skills": {"deception": 4, "persuasion": 4, "religion": 2}, "passive": 11, "color": "#3d5c3a",
		"multiattack": ["dagger", "dagger"],
		"attacks": [
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d4", "bonus": 2, "type": "piercing"}], "props": ["finesse", "light"]},
		],
		"spellcasting": {"ability": "wis", "dc": 11, "attack_bonus": 3, "slots": [0, 4, 3, 0, 0, 0, 0, 0, 0, 0],
			"spells": ["poison_spray", "thaumaturgy", "bane", "hex", "inflict_wounds", "hold_person", "darkness"]}},
	"priestess": {"name": "Priestess", "size": "medium", "type": "humanoid", "ac": 13, "hp": 27, "hit_dice": "5d8+5", "speed": 30, "cr": 2.0, "xp": 450,  # Priest
		"abilities": {"str": 10, "dex": 10, "con": 12, "int": 13, "wis": 16, "cha": 13}, "skills": {"medicine": 7, "persuasion": 3, "religion": 4}, "passive": 13, "color": "#e8d9a8",
		"attacks": [
			{"id": "mace", "name": "Mace", "range": "melee", "to_hit": 2, "reach": 5, "damage": [{"dice": "1d6", "type": "bludgeoning"}], "props": []},
		],
		"spellcasting": {"ability": "wis", "dc": 13, "attack_bonus": 5, "slots": [0, 4, 3, 2, 0, 0, 0, 0, 0, 0],
			"spells": ["sacred_flame", "thaumaturgy", "cure_wounds", "guiding_bolt", "lesser_restoration", "spiritual_weapon", "dispel_magic", "spirit_guardians"]}},
	"necromancer": {"name": "Necromancer", "size": "medium", "type": "humanoid", "ac": 12, "hp": 40, "hit_dice": "9d8", "speed": 30, "cr": 6.0, "xp": 2300,  # Mage, necromantic spells
		"abilities": {"str": 9, "dex": 14, "con": 11, "int": 17, "wis": 12, "cha": 11}, "skills": {"arcana": 6, "history": 6}, "passive": 11, "color": "#2b2b3a",
		"save_profs": ["int", "wis"],
		"attacks": [
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d4", "bonus": 2, "type": "piercing"}], "props": ["finesse", "light"]},
		],
		"spellcasting": {"ability": "int", "dc": 14, "attack_bonus": 6, "slots": [0, 4, 3, 3, 3, 1, 0, 0, 0, 0],
			"spells": ["chill_touch", "ray_of_frost", "mage_armor", "magic_missile", "ray_of_sickness", "hold_person", "misty_step", "fear", "counterspell", "blight", "cone_of_cold"]}},
	"vampire": {"darkvision": 60, "name": "Vampire Spawn", "size": "medium", "type": "undead", "ac": 15, "hp": 82, "hit_dice": "11d8+33", "speed": 30, "cr": 5.0, "xp": 1800,
		"abilities": {"str": 16, "dex": 16, "con": 16, "int": 11, "wis": 10, "cha": 12}, "skills": {"perception": 3, "stealth": 6}, "passive": 13, "color": "#7a0f1f",
		"save_profs": ["dex", "wis"], "resistances": ["necrotic"], "traits": ["nonmagicalResistance"],
		"multiattack": ["bite", "claws"],
		"attacks": [
			{"id": "claws", "name": "Claws", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "2d4", "bonus": 3, "type": "slashing"}], "props": ["natural"]},
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "1d6", "bonus": 3, "type": "piercing"}, {"dice": "2d6", "type": "necrotic"}], "props": ["natural"]},
		]},
	"assassin": {"name": "Assassin", "size": "medium", "type": "humanoid", "ac": 15, "hp": 78, "hit_dice": "12d8+24", "speed": 30, "cr": 8.0, "xp": 3900,
		"abilities": {"str": 11, "dex": 16, "con": 14, "int": 13, "wis": 11, "cha": 10}, "skills": {"acrobatics": 6, "deception": 3, "perception": 3, "stealth": 9}, "passive": 13, "color": "#1c1c24",
		"save_profs": ["dex", "int"], "resistances": ["poison"],
		"multiattack": ["shortsword", "shortsword"],
		"attacks": [
			{"id": "shortsword", "name": "Shortsword", "range": "melee", "to_hit": 6, "reach": 5, "damage": [{"dice": "1d6", "bonus": 3, "type": "piercing"}], "props": ["finesse", "light"],
				"on_hit": {"ability": "con", "dc": 15, "damage": [{"dice": "7d6", "type": "poison"}], "half": true}},
			{"id": "light_crossbow", "name": "Light Crossbow", "range": "ranged", "to_hit": 6, "normal": 80, "long": 320, "damage": [{"dice": "1d8", "bonus": 3, "type": "piercing"}], "props": ["loading"],
				"on_hit": {"ability": "con", "dc": 15, "damage": [{"dice": "7d6", "type": "poison"}], "half": true}},
		]},
	"drow": {"darkvision": 120, "name": "Drow", "size": "medium", "type": "humanoid", "ac": 15, "hp": 13, "hit_dice": "3d8", "speed": 30, "cr": 0.25, "xp": 50,
		"abilities": {"str": 10, "dex": 14, "con": 10, "int": 11, "wis": 11, "cha": 12}, "skills": {"perception": 2, "stealth": 4}, "passive": 12,
		"traits": ["feyAncestry"], "color": "#3b2f5c",
		"attacks": [
			{"id": "shortsword", "name": "Shortsword", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "hand_crossbow", "name": "Hand Crossbow", "range": "ranged", "to_hit": 4, "normal": 30, "long": 120, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["light", "loading"],
				"on_hit": {"ability": "con", "dc": 13, "effect": {"name": "Drow Poison", "conditions": ["poisoned"], "expires_on": {"who": "target", "phase": "end", "count": 600}}}},
		],
		"spellcasting": {"ability": "cha", "dc": 11, "attack_bonus": 3, "slots": [0, 1, 1, 0, 0, 0, 0, 0, 0, 0], "spells": ["faerie_fire", "darkness"]}},
	"hobgoblin": {"darkvision": 60, "name": "Hobgoblin", "size": "medium", "type": "humanoid", "ac": 18, "hp": 11, "hit_dice": "2d8+2", "speed": 30, "cr": 0.5, "xp": 100,
		"abilities": {"str": 13, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 9}, "passive": 10, "color": "#b5562b",
		"attacks": [
			{"id": "longsword", "name": "Longsword", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d8", "bonus": 1, "type": "slashing"}], "props": ["versatile"]},
			{"id": "longbow", "name": "Longbow", "range": "ranged", "to_hit": 3, "normal": 150, "long": 600, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["ammunition", "heavy", "twoHanded"]},
		]},
	"gnoll": {"darkvision": 60, "name": "Gnoll", "size": "medium", "type": "humanoid", "ac": 15, "hp": 22, "hit_dice": "5d8", "speed": 30, "cr": 0.5, "xp": 100,
		"abilities": {"str": 14, "dex": 12, "con": 11, "int": 6, "wis": 10, "cha": 7}, "passive": 10, "color": "#a68a5b",
		"attacks": [
			{"id": "bite", "name": "Bite", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d4", "bonus": 2, "type": "piercing"}], "props": ["natural"]},
			{"id": "spear", "name": "Spear", "range": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d6", "bonus": 2, "type": "piercing"}], "props": ["versatile"]},
			{"id": "longbow", "name": "Longbow", "range": "ranged", "to_hit": 3, "normal": 150, "long": 600, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["ammunition", "heavy", "twoHanded"]},
		]},
	"pirate": {"name": "Pirate", "size": "medium", "type": "humanoid", "ac": 12, "hp": 11, "hit_dice": "2d8+2", "speed": 30, "cr": 0.125, "xp": 25,  # Bandit
		"abilities": {"str": 11, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 10}, "passive": 10, "color": "#1f4e79",
		"attacks": [
			{"id": "cutlass", "name": "Cutlass", "range": "melee", "to_hit": 3, "reach": 5, "damage": [{"dice": "1d6", "bonus": 1, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "light_crossbow", "name": "Light Crossbow", "range": "ranged", "to_hit": 3, "normal": 80, "long": 320, "damage": [{"dice": "1d8", "bonus": 1, "type": "piercing"}], "props": ["loading"]},
		]},
	"pirate_captain": {"name": "Pirate Captain", "size": "medium", "type": "humanoid", "ac": 15, "hp": 65, "hit_dice": "10d8+20", "speed": 30, "cr": 2.0, "xp": 450,  # Bandit Captain
		"abilities": {"str": 15, "dex": 16, "con": 14, "int": 14, "wis": 11, "cha": 14}, "skills": {"athletics": 4, "deception": 4}, "passive": 10,
		"save_profs": ["str", "dex", "wis"], "traits": ["parry"], "color": "#7b1e1e",
		"multiattack": ["cutlass", "cutlass", "dagger"],
		"attacks": [
			{"id": "cutlass", "name": "Cutlass", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d6", "bonus": 3, "type": "slashing"}], "props": ["finesse", "light"]},
			{"id": "dagger", "name": "Dagger", "range": "melee", "to_hit": 5, "reach": 5, "damage": [{"dice": "1d4", "bonus": 3, "type": "piercing"}], "props": ["finesse", "light"]},
			{"id": "dagger_thrown", "name": "Dagger (thrown)", "range": "ranged", "to_hit": 5, "normal": 20, "long": 60, "damage": [{"dice": "1d4", "bonus": 3, "type": "piercing"}], "props": ["thrown"]},
		]},
}


static func get_monster(id: String) -> Dictionary:
	if ALL.has(id):
		return ALL[id]
	return Homebrew.monsters.get(id, {})


static func cr_label(cr: float) -> String:
	if cr == 0.125:
		return "1/8"
	if cr == 0.25:
		return "1/4"
	if cr == 0.5:
		return "1/2"
	return str(int(cr))
