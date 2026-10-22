extends "res://tests/test_base.gd"
## Rules-as-written fixes from the engine audit.

const BOB := {"name": "Bob", "is_dm": false}


func test_divine_smite_is_chosen_after_the_hit() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2))
	var sk := add("monster", "skeleton", Vector2i(3, 2))
	c(p).controller = "Bob"
	start([p, sk])
	Dice.forced = [2]
	var r := must({"type": "attack", "actor_id": p, "attack_id": "longsword", "target_id": sk})
	ok(not r.get("pending", false), "a miss offers no smite")
	eq(c(p).spellcasting.slots_used[1], 0, "no slot spent on a miss")
	Dice.forced = [15]
	r = must({"type": "attack", "actor_id": p, "attack_id": "longsword", "target_id": sk})
	ok(r.get("pending", false) and "Divine Smite" in state.pending.prompt.text, "the hit asks whether to smite")
	Dice.forced = [15, 1, 1, 1, 1]
	must({"type": "react", "choice": true}, BOB)
	eq(c(p).spellcasting.slots_used[1], 1, "smiting spends the slot")
	ok(log_has("divine smite"), "smite logged")


func test_frightened_rules() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([f, g])
	var eng := engine()
	eng.add_effect({"name": "Frightened", "conditions": ["frightened"]}, g, f)
	eng.add_effect({"name": "Blinded", "conditions": ["blinded"]}, f, f)
	ok(eng.attack_mode(c(f), c(g), "melee").dis.has("frightened"), "disadvantage while the source is in line of sight")
	ok(not eng.can_see(c(f), c(g)), "blinded fighter can't see the goblin")
	ok(eng.move_to(c(f), Vector2i(4, 2)) != "", "still can't move closer to a source it can't see")


func test_charmed_creature_cant_attack_its_charmer() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	engine().add_effect({"name": "Charmed", "conditions": ["charmed"]}, g, f)
	ok(not run({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g}).ok, "attack on the charmer refused")


func test_haste_action_is_one_attack_and_ends_in_lethargy() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	engine().add_effect({"name": "Hasted", "spell_id": "haste", "mods": {"haste_action": true}}, f, f)
	start([f, o])
	for i in 3:
		must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	ok(not run({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o}).ok, "Haste's action allows a single attack")
	ok(not run({"type": "action", "actor_id": f, "action": "dash"}).ok, "and it is spent")
	var eng := engine()
	eng.remove_effect(state.effects.filter(func(e): return e.name == "Hasted")[0], " (ended)")
	ok(eng.has_mod(c(f), "lethargic") and eng.speed_of(c(f)) == 0, "lethargy when Haste ends")


func test_evasion_still_works_when_stunned() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(1, 1))
	var r := add("pregen", "rogue", Vector2i(10, 10), 7, "enemy")  # not an ally, so Sculpt Spells stays out of it
	start([w, r])
	engine().add_effect({"name": "Stunned", "conditions": ["stunned"]}, w, r)
	var hp: int = c(r).hp
	Dice.forced = [3, 3, 3, 3, 3, 3, 3, 3]
	must({"type": "cast", "actor_id": w, "spell_id": "fireball", "point": Vector2i(10, 10)})
	eq(c(r).hp, hp - 12, "auto-failed Dex save still only half with Evasion")


func test_petrified_resists_all_damage() -> void:
	fresh()
	var o := add("monster", "ogre", Vector2i(3, 3))
	var eng := engine()
	eng.add_effect({"name": "Petrified", "conditions": ["petrified"]}, o, o)
	eq(eng.deal_damage(c(o), [{"amount": 10, "type": "fire"}]), 5, "petrified halves damage")


func test_long_rest_needs_one_hit_point() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	c(f).hp = 0
	c(f).stable = true
	must({"type": "rest", "kind": "long", "ids": [f]})
	eq(c(f).hp, 0, "no long rest benefits at 0 HP")


func test_spirit_guardians_hit_on_entering() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(12, 2))
	start([cl, o])
	must({"type": "cast", "actor_id": cl, "spell_id": "spirit_guardians"})
	must({"type": "endTurn", "actor_id": cl})
	var hp: int = c(o).hp
	must({"type": "move", "actor_id": o, "to": Vector2i(5, 2)})
	ok(log_has("vs Spirit Guardians") and c(o).hp < hp, "entering the aura triggers the save")


func test_dispel_magic_checks_higher_level_spells() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(1, 1))
	var g := add("monster", "goblin", Vector2i(4, 1))
	start([w, g])
	var eng := engine()
	eng.add_effect({"name": "Big Spell", "spell_id": "hold_monster", "slot": 5}, w, g)
	eng.add_effect({"name": "Small Spell", "spell_id": "hold_person", "slot": 2}, w, g)
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "dispel_magic", "targets": [g]})
	var names: Array = state.effects.filter(func(e): return e.target_id == g).map(func(e): return e.name)
	ok(names.has("Big Spell") and not names.has("Small Spell"), "5th-level spell survives a failed check, 2nd-level one ends: %s" % str(names))
