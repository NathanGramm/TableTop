class_name Equipment
extends RefCounted
## SRD 5.1 weapons and armor (PHB 2014 tables).

# props: finesse, light, heavy, thrown, twoHanded, versatile, reach, loading, ammunition
const WEAPONS := {
	# Simple melee
	"club": {"name": "Club", "cat": "simple", "kind": "melee", "dice": "1d4", "type": "bludgeoning", "props": ["light"]},
	"dagger": {"name": "Dagger", "cat": "simple", "kind": "melee", "dice": "1d4", "type": "piercing", "props": ["finesse", "light", "thrown"], "range": [20, 60]},
	"greatclub": {"name": "Greatclub", "cat": "simple", "kind": "melee", "dice": "1d8", "type": "bludgeoning", "props": ["twoHanded"]},
	"handaxe": {"name": "Handaxe", "cat": "simple", "kind": "melee", "dice": "1d6", "type": "slashing", "props": ["light", "thrown"], "range": [20, 60]},
	"javelin": {"name": "Javelin", "cat": "simple", "kind": "melee", "dice": "1d6", "type": "piercing", "props": ["thrown"], "range": [30, 120]},
	"light_hammer": {"name": "Light Hammer", "cat": "simple", "kind": "melee", "dice": "1d4", "type": "bludgeoning", "props": ["light", "thrown"], "range": [20, 60]},
	"mace": {"name": "Mace", "cat": "simple", "kind": "melee", "dice": "1d6", "type": "bludgeoning", "props": []},
	"quarterstaff": {"name": "Quarterstaff", "cat": "simple", "kind": "melee", "dice": "1d6", "type": "bludgeoning", "props": ["versatile"], "versatile": "1d8"},
	"sickle": {"name": "Sickle", "cat": "simple", "kind": "melee", "dice": "1d4", "type": "slashing", "props": ["light"]},
	"spear": {"name": "Spear", "cat": "simple", "kind": "melee", "dice": "1d6", "type": "piercing", "props": ["thrown", "versatile"], "versatile": "1d8", "range": [20, 60]},
	# Simple ranged
	"light_crossbow": {"name": "Light Crossbow", "cat": "simple", "kind": "ranged", "dice": "1d8", "type": "piercing", "props": ["ammunition", "loading", "twoHanded"], "range": [80, 320]},
	"dart": {"name": "Dart", "cat": "simple", "kind": "ranged", "dice": "1d4", "type": "piercing", "props": ["finesse", "thrown"], "range": [20, 60]},
	"shortbow": {"name": "Shortbow", "cat": "simple", "kind": "ranged", "dice": "1d6", "type": "piercing", "props": ["ammunition", "twoHanded"], "range": [80, 320]},
	"sling": {"name": "Sling", "cat": "simple", "kind": "ranged", "dice": "1d4", "type": "bludgeoning", "props": ["ammunition"], "range": [30, 120]},
	# Martial melee
	"battleaxe": {"name": "Battleaxe", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "slashing", "props": ["versatile"], "versatile": "1d10"},
	"flail": {"name": "Flail", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "bludgeoning", "props": []},
	"glaive": {"name": "Glaive", "cat": "martial", "kind": "melee", "dice": "1d10", "type": "slashing", "props": ["heavy", "reach", "twoHanded"]},
	"greataxe": {"name": "Greataxe", "cat": "martial", "kind": "melee", "dice": "1d12", "type": "slashing", "props": ["heavy", "twoHanded"]},
	"greatsword": {"name": "Greatsword", "cat": "martial", "kind": "melee", "dice": "2d6", "type": "slashing", "props": ["heavy", "twoHanded"]},
	"halberd": {"name": "Halberd", "cat": "martial", "kind": "melee", "dice": "1d10", "type": "slashing", "props": ["heavy", "reach", "twoHanded"]},
	"lance": {"name": "Lance", "cat": "martial", "kind": "melee", "dice": "1d12", "type": "piercing", "props": ["reach"]},
	"longsword": {"name": "Longsword", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "slashing", "props": ["versatile"], "versatile": "1d10"},
	"maul": {"name": "Maul", "cat": "martial", "kind": "melee", "dice": "2d6", "type": "bludgeoning", "props": ["heavy", "twoHanded"]},
	"morningstar": {"name": "Morningstar", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "piercing", "props": []},
	"pike": {"name": "Pike", "cat": "martial", "kind": "melee", "dice": "1d10", "type": "piercing", "props": ["heavy", "reach", "twoHanded"]},
	"rapier": {"name": "Rapier", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "piercing", "props": ["finesse"]},
	"scimitar": {"name": "Scimitar", "cat": "martial", "kind": "melee", "dice": "1d6", "type": "slashing", "props": ["finesse", "light"]},
	"shortsword": {"name": "Shortsword", "cat": "martial", "kind": "melee", "dice": "1d6", "type": "piercing", "props": ["finesse", "light"]},
	"trident": {"name": "Trident", "cat": "martial", "kind": "melee", "dice": "1d6", "type": "piercing", "props": ["thrown", "versatile"], "versatile": "1d8", "range": [20, 60]},
	"war_pick": {"name": "War Pick", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "piercing", "props": []},
	"warhammer": {"name": "Warhammer", "cat": "martial", "kind": "melee", "dice": "1d8", "type": "bludgeoning", "props": ["versatile"], "versatile": "1d10"},
	"whip": {"name": "Whip", "cat": "martial", "kind": "melee", "dice": "1d4", "type": "slashing", "props": ["finesse", "reach"]},
	# Martial ranged
	"hand_crossbow": {"name": "Hand Crossbow", "cat": "martial", "kind": "ranged", "dice": "1d6", "type": "piercing", "props": ["ammunition", "light", "loading"], "range": [30, 120]},
	"heavy_crossbow": {"name": "Heavy Crossbow", "cat": "martial", "kind": "ranged", "dice": "1d10", "type": "piercing", "props": ["ammunition", "heavy", "loading", "twoHanded"], "range": [100, 400]},
	"longbow": {"name": "Longbow", "cat": "martial", "kind": "ranged", "dice": "1d8", "type": "piercing", "props": ["ammunition", "heavy", "twoHanded"], "range": [150, 600]},
}

# type: light/medium/heavy. dex_cap: -1 = unlimited.
const ARMOR := {
	"padded": {"name": "Padded", "type": "light", "ac": 11, "dex_cap": -1, "stealth_dis": true, "metal": false},
	"leather": {"name": "Leather", "type": "light", "ac": 11, "dex_cap": -1, "stealth_dis": false, "metal": false},
	"studded_leather": {"name": "Studded Leather", "type": "light", "ac": 12, "dex_cap": -1, "stealth_dis": false, "metal": false},
	"hide": {"name": "Hide", "type": "medium", "ac": 12, "dex_cap": 2, "stealth_dis": false, "metal": false},
	"chain_shirt": {"name": "Chain Shirt", "type": "medium", "ac": 13, "dex_cap": 2, "stealth_dis": false, "metal": true},
	"scale_mail": {"name": "Scale Mail", "type": "medium", "ac": 14, "dex_cap": 2, "stealth_dis": true, "metal": true},
	"breastplate": {"name": "Breastplate", "type": "medium", "ac": 14, "dex_cap": 2, "stealth_dis": false, "metal": true},
	"half_plate": {"name": "Half Plate", "type": "medium", "ac": 15, "dex_cap": 2, "stealth_dis": true, "metal": true},
	"ring_mail": {"name": "Ring Mail", "type": "heavy", "ac": 14, "dex_cap": 0, "stealth_dis": true, "metal": true},
	"chain_mail": {"name": "Chain Mail", "type": "heavy", "ac": 16, "dex_cap": 0, "stealth_dis": true, "metal": true, "str": 13},
	"splint": {"name": "Splint", "type": "heavy", "ac": 17, "dex_cap": 0, "stealth_dis": true, "metal": true, "str": 15},
	"plate": {"name": "Plate", "type": "heavy", "ac": 18, "dex_cap": 0, "stealth_dis": true, "metal": true, "str": 15},
}

## Monk weapons: shortswords and simple melee weapons without two-handed or heavy.
static func is_monk_weapon(id: String) -> bool:
	if id == "shortsword":
		return true
	var w: Dictionary = WEAPONS.get(id, {})
	return not w.is_empty() and w.cat == "simple" and w.kind == "melee" and not w.props.has("twoHanded") and not w.props.has("heavy")
