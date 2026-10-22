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


## Weights in pounds (PHB 2014 tables). Shield: 6 lb.
const WEIGHT := {
	"club": 2, "dagger": 1, "greatclub": 10, "handaxe": 2, "javelin": 2, "light_hammer": 2, "mace": 4, "quarterstaff": 4,
	"sickle": 2, "spear": 3, "light_crossbow": 5, "dart": 0.25, "shortbow": 2, "sling": 0, "battleaxe": 4, "flail": 2,
	"glaive": 6, "greataxe": 7, "greatsword": 6, "halberd": 6, "lance": 6, "longsword": 3, "maul": 10, "morningstar": 4,
	"pike": 18, "rapier": 2, "scimitar": 3, "shortsword": 2, "trident": 4, "war_pick": 2, "warhammer": 2, "whip": 3,
	"hand_crossbow": 3, "heavy_crossbow": 18, "longbow": 2,
	"padded": 8, "leather": 10, "studded_leather": 12, "hide": 12, "chain_shirt": 20, "scale_mail": 45, "breastplate": 20,
	"half_plate": 40, "ring_mail": 40, "chain_mail": 55, "splint": 60, "plate": 65, "shield": 6, "potion": 0.5,
}
## Ammunition (DM option): the sheet field that counts it, starting count (PHB packs), weight per piece.
const AMMO := {
	"arrows": {"name": "Arrows", "start": 20, "lb": 0.05},
	"bolts": {"name": "Crossbow bolts", "start": 20, "lb": 0.075},
	"bullets": {"name": "Sling bullets", "start": 20, "lb": 0.075},
}
const AMMO_OF := {"shortbow": "arrows", "longbow": "arrows", "light_crossbow": "bolts", "hand_crossbow": "bolts", "heavy_crossbow": "bolts", "sling": "bullets"}
## Size multipliers for carrying capacity.
const CARRY_SIZE := {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 4.0, "gargantuan": 8.0}


## Ammunition left: the sheet field, or the starting count while it's blank.
static func ammo_left(c: Dictionary, kind: String) -> int:
	var v: String = str(c.get("notes", {}).get(kind, "")).strip_edges()
	return int(v) if v.is_valid_int() else AMMO[kind].start


## Pounds carried: armor, shield, weapons and potions (c.gear_lb), coins (50 to the pound),
## ammunition the character uses, and the sheet's "other gear" weight.
static func carried_lb(c: Dictionary) -> float:
	var n: Dictionary = c.get("notes", {})
	var lb: float = c.get("gear_lb", 0.0)
	for coin in ["cp", "sp", "ep", "gp", "pp"]:
		lb += maxi(0, str(n.get(coin, "")).to_int()) / 50.0
	var kinds := {}
	for a in c.get("attacks", []):
		if AMMO_OF.has(a.get("weapon_id", "")):
			kinds[AMMO_OF[a.weapon_id]] = true
	for k in kinds:
		lb += ammo_left(c, k) * AMMO[k].lb
	return lb + maxf(0.0, str(n.get("pack_lb", "")).to_float())


## Variant encumbrance (PHB p. 176): 0 = fine, 1 = encumbered (over 5 × Str), 2 = heavily encumbered
## (over 10 × Str), 3 = over carrying capacity (15 × Str, pushing or dragging: speed 5 ft), 4 = can't move (over 30 × Str).
static func encumbrance(c: Dictionary) -> int:
	var cap: float = c.abilities.str * CARRY_SIZE.get(c.get("csize", "medium"), 1.0)
	var lb := carried_lb(c)
	for i in [[30, 4], [15, 3], [10, 2], [5, 1]]:
		if lb > cap * i[0]:
			return i[1]
	return 0
