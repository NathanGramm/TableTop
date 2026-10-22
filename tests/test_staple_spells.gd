extends "res://tests/test_base.gd"


func learn(id: String, spells: Array) -> void:
	c(id).spellcasting.known.append_array(spells)


func test_mage_armor_sets_base_ac() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(3, 2))
	learn(w, ["mage_armor"])
	var r := run({"type": "cast", "actor_id": w, "spell_id": "mage_armor", "targets": [f]})
	ok(not r.ok and "armor" in r.error, "armored targets are refused: " + r.error)
	must({"type": "cast", "actor_id": w, "spell_id": "mage_armor", "targets": [w]})
	eq(engine().ac_of(c(w)), 13 + engine().mod(c(w), "dex"), "AC is 13 + Dex")


func test_counterspell_stops_a_leveled_spell() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var e := add("pregen", "sorcerer", Vector2i(2, 8), 5, "enemy")
	var o := add("monster", "ogre", Vector2i(8, 2))
	learn(e, ["counterspell"])
	start([w, e, o])
	must({"type": "cast", "actor_id": w, "spell_id": "magic_missile", "targets": [o]})
	eq(c(o).hp, 59, "the darts never fire")
	eq(c(w).spellcasting.slots_used[1], 1, "the caster's slot is still spent")
	eq(c(e).spellcasting.slots_used[3], 1, "counterspell used a 3rd-level slot")
	ok(c(e).reaction_used, "counterspell used the reaction")
	ok(log_has("is countered"), "logged")


func test_counterspell_needs_a_check_against_higher_spells() -> void:
	fresh(30, 30)
	var w := add("pregen", "wizard", Vector2i(2, 2), 9)
	var e := add("pregen", "sorcerer", Vector2i(2, 10), 5, "enemy")
	var o := add("monster", "ogre", Vector2i(6, 2))
	learn(w, ["cone_of_cold"])
	learn(e, ["counterspell"])
	start([w, e, o])
	Dice.forced = [1]  # the counterspeller's check fails against DC 15
	must({"type": "cast", "actor_id": w, "spell_id": "cone_of_cold", "slot": 5, "point": Vector2i(6, 2)})
	ok(log_has("Counterspell fails"), "the check failed")
	ok(c(o).hp < 59, "the cone goes off")
	eq(c(e).spellcasting.slots_used[3], 1, "the counterspell slot is still spent")


func test_auto_counterspell_ignores_cantrips() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var e := add("pregen", "sorcerer", Vector2i(2, 8), 5, "enemy")
	var o := add("monster", "ogre", Vector2i(8, 2))
	learn(e, ["counterspell"])
	start([w, e, o])
	Dice.forced = [15, 5, 5]
	must({"type": "cast", "actor_id": w, "spell_id": "fire_bolt", "targets": [o]})
	eq(c(o).hp, 49, "fire bolt lands")
	ok(not c(e).reaction_used, "no reaction spent on a cantrip")


func test_spiritual_weapon_attacks_again_as_a_bonus_action() -> void:
	fresh(30, 30)
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(10, 2))
	learn(cl, ["spiritual_weapon"])
	start([cl, o])
	var wis := engine().mod(c(cl), "wis")
	Dice.forced = [15, 5]
	must({"type": "cast", "actor_id": cl, "spell_id": "spiritual_weapon", "targets": [o]})
	eq(c(o).hp, 59 - 5 - wis, "1d8 + Wisdom force")
	ok(engine().has_tag(c(cl), "spiritual_weapon"), "the weapon lingers")
	var r := run({"type": "feature", "actor_id": cl, "feature": "spiritualWeapon", "target_id": o})
	ok(not r.ok, "only one bonus action a turn")
	must({"type": "endTurn", "actor_id": cl})
	must({"type": "endTurn", "actor_id": o})
	Dice.forced = [15, 4]
	must({"type": "feature", "actor_id": cl, "feature": "spiritualWeapon", "target_id": o})
	eq(c(o).hp, 59 - 9 - 2 * wis, "second strike")
	eq(engine()._damage_specs(Spells.get_spell("spiritual_weapon"), 3, 5)[0].dice, "1d8", "no extra die at 3rd level")
	ok(engine()._damage_specs(Spells.get_spell("spiritual_weapon"), 4, 5)[0].dice != "1d8", "an extra die at 4th level")


func test_slow_lowers_ac_and_speed() -> void:
	fresh(30, 30)
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(12, 2))
	learn(w, ["slow"])
	start([w, o])
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "slow", "point": Vector2i(12, 3)})
	eq(engine().ac_of(c(o)), 9, "-2 AC")
	eq(engine().speed_of(c(o)), 20, "half speed")
	ok(not engine().can_react(c(o)), "no reactions")


func test_false_life_and_hideous_laughter() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(6, 2))
	learn(w, ["false_life", "tashas_hideous_laughter"])
	Dice.forced = [3]
	must({"type": "cast", "actor_id": w, "spell_id": "false_life"})
	eq(c(w).temp_hp, 7, "1d4 + 4 temporary hit points")
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "tashas_hideous_laughter", "targets": [o]})
	ok(engine().has_cond(c(o), "prone") and engine().incapacitated(c(o)), "laughing on the floor")
