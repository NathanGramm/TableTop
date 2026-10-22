extends "res://tests/test_base.gd"
## Class features from 11th to 20th level.


func test_barbarian() -> void:
	fresh()
	var b := add("pregen", "barbarian", Vector2i(2, 2), 20)
	ok(c(b).abilities.str > 20 and c(b).abilities.con > 16, "Primal Champion raises Str/Con past 20: %s" % str(c(b).abilities))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([b, o])
	must({"type": "feature", "actor_id": b, "feature": "rage"})
	Dice.forced = [15]
	engine().deal_damage(c(b), [{"amount": c(b).hp, "type": "fire"}], {"label": "test"})
	eq(c(b).hp, 1, "Relentless Rage: DC 10 save keeps it at 1 HP")
	ok(engine().has_tag(c(b), "rage"), "still raging")
	must({"type": "endTurn", "actor_id": b})
	ok(engine().has_tag(c(b), "rage"), "Persistent Rage: doesn't end without attacking")


func test_fighter_survivor() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 18)
	var g := add("monster", "goblin", Vector2i(9, 9))
	c(f).hp = 10
	start([f, g])
	eq(c(f).hp, 15 + engine().mod(c(f), "con"), "Survivor heals 5 + Con at the start of the turn")


func test_paladin_improved_smite_and_rogue_elusive() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2), 11)
	var r := add("pregen", "rogue", Vector2i(3, 2), 18)
	c(r).side = "enemy"
	start([p, r])
	Dice.forced = [15]
	must({"type": "attack", "actor_id": p, "attack_id": "longsword", "target_id": r})
	ok(log_has("improved divine smite"), "Improved Divine Smite adds 1d8 radiant")
	engine().add_effect({"name": "Faerie Fire", "mods": {"advantage_against": true}}, p, r)
	eq(engine().attack_mode(c(p), c(r), "melee").mode, Dice.NORMAL, "Elusive: no advantage against the rogue")
	ok(c(r).save_profs.has("wis"), "Slippery Mind: Wisdom saves")


func test_casters_capstones() -> void:
	fresh()
	var d := add("pregen", "druid", Vector2i(2, 2), 20)
	var bard := add("pregen", "bard", Vector2i(4, 4), 20)
	var m := add("pregen", "monk", Vector2i(6, 6), 20)
	var s := add("pregen", "sorcerer", Vector2i(8, 8), 20)
	var g := add("monster", "goblin", Vector2i(12, 12))
	eq(c(m).save_profs.size(), 6, "Diamond Soul: every save")
	c(bard).resources.inspiration.used = c(bard).resources.inspiration.max
	c(m).resources.ki.used = c(m).resources.ki.max
	c(s).resources.sorcery.used = 10
	must({"type": "rest", "kind": "short", "ids": [s]})
	eq(c(s).resources.sorcery.used, 6, "Sorcerous Restoration: 4 points back")
	start([d, g, bard, m, s])
	eq(engine().res_left(c(bard), "inspiration"), 1, "Superior Inspiration")
	eq(engine().res_left(c(m), "ki"), 4, "Perfect Self")
	c(d).resources.wild_shape.used = 2
	must({"type": "feature", "actor_id": d, "feature": "wildShape", "choice": "wolf"})
	ok(c(d).fdata.has("wild_shape"), "Archdruid: Wild Shape with no uses left")
	must({"type": "endTurn", "actor_id": d})
	must({"type": "dmEndTurn"})
	must({"type": "endTurn", "actor_id": bard})
	must({"type": "endTurn", "actor_id": m})
	must({"type": "endTurn", "actor_id": s})
	ok(run({"type": "cast", "actor_id": d, "spell_id": "healing_word", "targets": [d]}).ok, "Beast Spells: casting as a wolf")


func test_superior_hunters_defense() -> void:
	var d := Creator.normalize(Pregens.ALL.ranger.duplicate(true).merged({"level": 15}))
	ok(d.options.has("superior_evasion"), "creator defaults to Evasion")
	eq(Creator.validate(d), [], "valid with one defense")
	eq(Creator.validate(d.merged({"options": d.options + ["superior_uncanny_dodge"]}, true)).size(), 1, "only one defense")
	ok(Builder.build_character(d, 15, "x").features.has("evasion"), "Evasion")
	var ud := d.merged({"options": d.options.filter(func(o): return o != "superior_evasion") + ["superior_uncanny_dodge"]}, true)
	ok(Builder.build_character(ud, 15, "x").features.has("uncannyDodge"), "Uncanny Dodge")
	fresh()
	var r := add("pregen", "ranger", Vector2i(3, 2), 15)
	c(r).features.append("standAgainstTheTide")
	var g1 := add("monster", "goblin", Vector2i(4, 2))
	var g2 := add("monster", "goblin", Vector2i(4, 3))
	start([g1, r, g2])
	Dice.forced = [1, 20, 6]
	must({"type": "attack", "actor_id": g1, "attack_id": "scimitar", "target_id": r})
	ok(c(r).reaction_used, "ranger used its reaction")
	ok(c(g2).hp < c(g2).max_hp, "the missed attack hit the other goblin")
