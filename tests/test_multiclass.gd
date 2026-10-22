extends "res://tests/test_base.gd"
## Multiclassing: def.class is the first class, def.classes lists the rest, def.level is the character level.


func _fighter_wizard(fighter: int, wizard: int) -> Dictionary:
	var d: Dictionary = Pregens.ALL.fighter.duplicate(true)
	d.abilities.int = 13
	d.asi = {}
	d.level = fighter + wizard
	d.classes = [{"class": "wizard", "levels": wizard}]
	d.spells = ["fire_bolt", "magic_missile", "shield"]
	return d


func test_prerequisites() -> void:
	var d := _fighter_wizard(2, 1)
	eq(Creator.multiclass_errors(d), [], "Str 15 and Int 13 qualify")
	d.abilities.int = 11
	eq(Creator.multiclass_errors(d).size(), 1, "Int 12 is too low for wizard")
	ok(not Creator.validate(d).is_empty(), "validate reports it")


func test_levels_hp_and_features() -> void:
	var d := Creator.normalize(_fighter_wizard(2, 3))
	eq(Creator.validate(d), [], "valid: %s" % str(Creator.validate(d)))
	eq(Creator.class_levels(d), {"fighter": 2, "wizard": 3}, "class split")
	var c := Builder.build_character(d, 5, "x")
	var con: int = Stats.mod(c.abilities.con)
	eq(c.max_hp, 10 + con + (6 + con) + 3 * (4 + con), "d10 max, then a d10 and three d6 averages")
	eq(c.prof, 3, "proficiency from character level")
	eq(c.attacks_per_action, 1, "no Extra Attack at fighter 2")
	ok(c.resources.has("action_surge") and c.resources.has("arcane_recovery"), "features from both classes")
	eq(c.subclass_id, "", "no fighter subclass before fighter 3")
	eq(c.spellcasting.slots.slice(1, 3), [4, 2], "wizard 3 slots")
	ok(c.spellcasting.known.has("magic_missile") and c.spellcasting.ability == "int", "wizard spells on Int")
	ok(c.description.contains("Wizard 3"), c.description)
	eq(Creator.asi_char_levels(d.merged({"level": 8, "classes": [{"class": "wizard", "levels": 4}]}, true)), [4, 8], "fighter 4 + wizard 4")


func test_extra_attack_does_not_stack_and_slots_combine() -> void:
	var d: Dictionary = Pregens.ALL.paladin.duplicate(true)
	d.abilities.wis = 13
	d.level = 11
	d.classes = [{"class": "cleric", "levels": 5}]
	var c := Builder.build_character(d, 11, "x")
	eq(c.attacks_per_action, 2, "Extra Attack once")
	# paladin 6 counts as 3 caster levels, cleric 5 as 5: an 8th-level caster.
	eq(c.spellcasting.slots.slice(1, 5), [4, 3, 3, 2], "combined slot table")


func test_spells_use_their_own_ability() -> void:
	var d: Dictionary = Pregens.ALL.cleric.duplicate(true)
	d.abilities.merge({"int": 13, "con": 10}, true)
	d.level = 3
	d.classes = [{"class": "wizard", "levels": 2}]
	d.spells = ["sacred_flame", "guiding_bolt", "fire_bolt", "magic_missile"]
	d = Creator.normalize(d)
	eq(d.spells, ["sacred_flame", "guiding_bolt", "fire_bolt", "magic_missile"], "normalize keeps the spells")
	eq(Creator.validate(d), [], "valid: %s" % str(Creator.validate(d)))
	fresh()
	var p := add("pregen", "cleric", Vector2i(2, 2), 3)
	state.combatants[p] = Builder.build_character(d, 3, p).merged({"pos": c(p).pos}, true)
	var sc: Dictionary = c(p).spellcasting
	ok(sc.known.has("magic_missile") and sc.known.has("bless"), "both lists")
	eq(sc.spell_ability.get("fire_bolt", ""), "int", "fire bolt uses Int")
	var e := engine()
	eq(e.spell_stats(c(p), "fire_bolt").attack_bonus, sc.attack_bonus + e.mod(c(p), "int") - e.mod(c(p), "wis"), "Int to hit")
	eq(e.spell_stats(c(p), "sacred_flame").dc, sc.dc, "cleric spells keep the Wis DC")
	ok(not Creator.validate(d.merged({"spells": d.spells + ["fireball"]}, true)).is_empty(), "no 3rd-level wizard spells at wizard 2")


func test_level_up_into_a_new_class() -> void:
	fresh()
	var bob := {"name": "Bob", "is_dm": false}
	var d := Creator.new_def("fighter", "human")
	d.merge({"name": "Test", "skills": ["athletics", "perception"], "background": "sage", "armor": "chain_mail", "shield": true, "weapons": ["longsword"]}, true)
	var thirteen: String = d.abilities.keys().filter(func(k): return d.abilities[k] == 13)[0]
	d.abilities[thirteen] = d.abilities.int
	d.abilities.int = 13
	must({"type": "createCharacter", "def": d}, bob)
	var id: String = state.combatants.keys()[0]
	must({"type": "levelUp"})
	var up: Dictionary = c(id).def.duplicate(true)
	up.level = 2
	up.classes = [{"class": "wizard", "levels": 1}]
	up.spells = ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "shield"]
	must({"type": "updateCharacter", "id": id, "def": Creator.normalize(up), "roll_hp": true}, bob)
	eq(Creator.class_levels(c(id).def), {"fighter": 1, "wizard": 1}, "fighter 1 / wizard 1")
	var roll: int = c(id).def.hp_rolls["2"]
	ok(roll >= 1 and roll <= 6, "the new level rolls a wizard d6: %d" % roll)
	ok(not c(id).resources.has("action_surge") and c(id).resources.has("arcane_recovery"), "wizard features, not fighter 2")
	ok(c(id).spellcasting.known.has("magic_missile"), "wizard spells")
