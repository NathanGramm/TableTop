class_name Stats
extends RefCounted
## Small shared rules helpers.

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := {"str": "Strength", "dex": "Dexterity", "con": "Constitution", "int": "Intelligence", "wis": "Wisdom", "cha": "Charisma"}
const SKILLS := {
	"acrobatics": "dex", "animalHandling": "wis", "arcana": "int", "athletics": "str", "deception": "cha",
	"history": "int", "insight": "wis", "intimidation": "cha", "investigation": "int", "medicine": "wis",
	"nature": "int", "perception": "wis", "performance": "cha", "persuasion": "cha", "religion": "int",
	"sleightOfHand": "dex", "stealth": "dex", "survival": "wis",
}
const CONDITIONS := ["blinded", "charmed", "deafened", "frightened", "grappled", "incapacitated", "invisible",
	"paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious"]
const DAMAGE_TYPES := ["acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic", "piercing",
	"poison", "psychic", "radiant", "slashing", "thunder"]


static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func fresh_turn() -> Dictionary:
	return {
		"actions": 1, "bonus": true, "movement_used": 0, "dashes": 0,
		"attacks_left": 0, "multiattack_left": [], "attack_action_taken": false, "attack_action_weapons": [],
		"bonus_attack": {}, "spells_cast": [], "attacked_hostile": false, "disengaged": false, "first_attack_made": false,
		"surged": false,
	}


static func hp_status(c: Dictionary) -> String:
	if c.dead:
		return "Dead"
	if c.hp <= 0:
		return "Down"
	var f := float(c.hp) / maxf(1.0, c.max_hp)
	if f >= 1.0:
		return "Unhurt"
	if f > 0.5:
		return "Injured"
	if f > 0.25:
		return "Bloodied"
	return "Critical"


static func skill_label(id: String) -> String:
	var out := ""
	for i in id.length():
		var ch := id[i]
		if i == 0:
			out += ch.to_upper()
		elif ch == ch.to_upper() and ch != ch.to_lower():
			out += " " + ch
		else:
			out += ch
	return out
