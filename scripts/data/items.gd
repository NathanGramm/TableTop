class_name Items
extends RefCounted
## Magic items (SRD 5.1) in the same format DMs use for homebrew items.
##
## kind: weapon | armor | shield | wondrous | potion
## base: what the DM picks when handing it out — "weapon" (any weapon), "melee" (melee weapon),
##       "armor" (any armor), "damage_type" (e.g. Ring of Resistance), or "" for nothing.
## Effects: attack_bonus, damage_bonus, extra_damage [{dice, type}], ac_bonus, ac_unarmored_bonus
## (only without armor and shield), save_bonus (all saves), resist [types] (or the chosen damage type),
## ability_min {ability: score}, speed_bonus, heal (potions; drinking is an action).
## A character's def.items holds entries like {"id": "weapon_plus_1", "base": "longsword"}.

const ALL := {
	"weapon_plus_1": {"name": "+1 Weapon", "kind": "weapon", "base": "weapon", "rarity": "uncommon", "attack_bonus": 1, "damage_bonus": 1,
		"desc": "+1 to attack and damage rolls made with this magic weapon."},
	"weapon_plus_2": {"name": "+2 Weapon", "kind": "weapon", "base": "weapon", "rarity": "rare", "attack_bonus": 2, "damage_bonus": 2,
		"desc": "+2 to attack and damage rolls made with this magic weapon."},
	"weapon_plus_3": {"name": "+3 Weapon", "kind": "weapon", "base": "weapon", "rarity": "very rare", "attack_bonus": 3, "damage_bonus": 3,
		"desc": "+3 to attack and damage rolls made with this magic weapon."},
	"flame_tongue": {"name": "Flame Tongue", "kind": "weapon", "base": "melee", "rarity": "rare", "attunement": true,
		"extra_damage": [{"dice": "2d6", "type": "fire"}], "desc": "While ablaze, deals an extra 2d6 fire damage on a hit."},
	"frost_brand": {"name": "Frost Brand", "kind": "weapon", "base": "melee", "rarity": "very rare", "attunement": true,
		"extra_damage": [{"dice": "1d6", "type": "cold"}], "resist": ["fire"], "desc": "Extra 1d6 cold damage on a hit; resistance to fire damage."},
	"armor_plus_1": {"name": "+1 Armor", "kind": "armor", "base": "armor", "rarity": "rare", "ac_bonus": 1, "desc": "+1 bonus to AC while wearing this armor."},
	"armor_plus_2": {"name": "+2 Armor", "kind": "armor", "base": "armor", "rarity": "very rare", "ac_bonus": 2, "desc": "+2 bonus to AC while wearing this armor."},
	"armor_plus_3": {"name": "+3 Armor", "kind": "armor", "base": "armor", "rarity": "legendary", "ac_bonus": 3, "desc": "+3 bonus to AC while wearing this armor."},
	"shield_plus_1": {"name": "+1 Shield", "kind": "shield", "base": "", "rarity": "uncommon", "ac_bonus": 1, "desc": "+1 AC on top of the shield's normal bonus."},
	"shield_plus_2": {"name": "+2 Shield", "kind": "shield", "base": "", "rarity": "rare", "ac_bonus": 2, "desc": "+2 AC on top of the shield's normal bonus."},
	"shield_plus_3": {"name": "+3 Shield", "kind": "shield", "base": "", "rarity": "very rare", "ac_bonus": 3, "desc": "+3 AC on top of the shield's normal bonus."},
	"ring_of_protection": {"name": "Ring of Protection", "kind": "wondrous", "base": "", "rarity": "rare", "attunement": true, "ac_bonus": 1, "save_bonus": 1,
		"desc": "+1 bonus to AC and saving throws."},
	"cloak_of_protection": {"name": "Cloak of Protection", "kind": "wondrous", "base": "", "rarity": "uncommon", "attunement": true, "ac_bonus": 1, "save_bonus": 1,
		"desc": "+1 bonus to AC and saving throws."},
	"bracers_of_defense": {"name": "Bracers of Defense", "kind": "wondrous", "base": "", "rarity": "rare", "attunement": true, "ac_unarmored_bonus": 2,
		"desc": "+2 AC while you wear no armor and use no shield."},
	"ring_of_resistance": {"name": "Ring of Resistance", "kind": "wondrous", "base": "damage_type", "rarity": "rare", "attunement": true,
		"desc": "Resistance to one damage type."},
	"gauntlets_of_ogre_power": {"name": "Gauntlets of Ogre Power", "kind": "wondrous", "base": "", "rarity": "uncommon", "attunement": true,
		"ability_min": {"str": 19}, "desc": "Your Strength score is 19 (unless it's already higher)."},
	"headband_of_intellect": {"name": "Headband of Intellect", "kind": "wondrous", "base": "", "rarity": "uncommon", "attunement": true,
		"ability_min": {"int": 19}, "desc": "Your Intelligence score is 19 (unless it's already higher)."},
	"amulet_of_health": {"name": "Amulet of Health", "kind": "wondrous", "base": "", "rarity": "rare", "attunement": true,
		"ability_min": {"con": 19}, "desc": "Your Constitution score is 19 (unless it's already higher)."},
	"belt_of_hill_giant_strength": {"name": "Belt of Hill Giant Strength", "kind": "wondrous", "base": "", "rarity": "rare", "attunement": true,
		"ability_min": {"str": 21}, "desc": "Your Strength score is 21 (unless it's already higher)."},
	"boots_of_striding_and_springing": {"name": "Boots of Striding and Springing", "kind": "wondrous", "base": "", "rarity": "uncommon", "attunement": true,
		"speed_min": 30, "desc": "Your walking speed is at least 30 ft, and armor doesn't slow you."},
	"potion_of_healing": {"name": "Potion of Healing", "kind": "potion", "base": "", "rarity": "common", "heal": "2d4+2", "desc": "Drink (action): regain 2d4 + 2 HP."},
	"potion_of_greater_healing": {"name": "Potion of Greater Healing", "kind": "potion", "base": "", "rarity": "uncommon", "heal": "4d4+4", "desc": "Drink (action): regain 4d4 + 4 HP."},
	"potion_of_superior_healing": {"name": "Potion of Superior Healing", "kind": "potion", "base": "", "rarity": "rare", "heal": "8d4+8", "desc": "Drink (action): regain 8d4 + 8 HP."},
	"potion_of_supreme_healing": {"name": "Potion of Supreme Healing", "kind": "potion", "base": "", "rarity": "very rare", "heal": "10d4+20", "desc": "Drink (action): regain 10d4 + 20 HP."},
}


static func get_item(id: String) -> Dictionary:
	if ALL.has(id):
		return ALL[id]
	return Homebrew.items.get(id, {})


static func all_ids() -> Array:
	return ALL.keys() + Homebrew.items.keys()


## "+1 Weapon" with base longsword -> "+1 Longsword"; Flame Tongue + longsword -> "Flame Tongue Longsword".
static func display_name(entry: Dictionary) -> String:
	var it := get_item(entry.get("id", ""))
	if it.is_empty():
		return "Unknown item"
	var base: String = entry.get("base", "")
	var base_name := ""
	if Equipment.WEAPONS.has(base):
		base_name = Equipment.WEAPONS[base].name
	elif Equipment.ARMOR.has(base):
		base_name = Equipment.ARMOR[base].name
	elif base != "":
		base_name = base.capitalize()
	if base_name == "":
		return it.name
	if "Weapon" in it.name:
		return it.name.replace("Weapon", base_name)
	if "Armor" in it.name:
		return it.name.replace("Armor", base_name + " Armor")
	if it.base == "damage_type":
		return "%s (%s)" % [it.name, base]
	return "%s %s" % [it.name, base_name]


## Which bases an item can be given with.
static func base_choices(item: Dictionary) -> Array:
	match item.get("base", ""):
		"weapon": return Equipment.WEAPONS.keys()
		"melee": return Equipment.WEAPONS.keys().filter(func(w): return Equipment.WEAPONS[w].kind == "melee")
		"armor": return Equipment.ARMOR.keys()
		"damage_type": return Stats.DAMAGE_TYPES.duplicate()
	return []
