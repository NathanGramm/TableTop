extends "res://tests/test_base.gd"


## A level-5 pregen who took `feat` instead of the level-4 ASI.
func pc(feat: String, cls: String, pos: Vector2i, weapons: Array = []) -> String:
	var d: Dictionary = Pregens.ALL[cls].duplicate(true)
	d.asi = {4: {"feat": feat}}
	if not weapons.is_empty():
		d.weapons = weapons
		d.shield = false
	var id := "pc_%d" % state.combatants.size()
	var ch := Builder.build_character(d, 5, id)
	ch.pos = pos
	state.combatants[id] = ch
	return id


func test_feat_replaces_an_asi_in_the_creator() -> void:
	var d := Creator.new_def("fighter", "human")
	d.name = "Feat Taker"
	d.skills = ["athletics", "perception"]
	d.background = "sage"
	d.armor = "chain_mail"
	d.weapons = ["greatsword"]
	d.style = "defense"
	d.level = 6
	d.asi = {4: {"feat": "tough"}, 6: {"feat": "alert"}}
	eq(Creator.validate(d), [], "two different feats are legal")
	eq(Creator.asi_bonus(d, 6).str, 0, "a feat adds no ability scores")
	eq(Creator.feats_of(d, 5), ["tough"], "only feats up to the level count")
	d.asi[6] = {"feat": "tough"}
	ok(Creator.validate(d).any(func(e): return "once" in e), "the same feat twice is rejected")
	d.asi[6] = {"feat": "nope"}
	ok(Creator.validate(d).any(func(e): return "Unknown feat" in e), "unknown feats are rejected")


func test_tough_alert_mobile_and_lucky_numbers() -> void:
	fresh()
	var base := Builder.build_character(Pregens.ALL.fighter, 5, "x")
	var t := c(pc("tough", "fighter", Vector2i(1, 1)))
	eq(t.max_hp - base.max_hp, 10, "Tough: +2 HP per level")
	var a := c(pc("alert", "fighter", Vector2i(2, 1)))
	eq(a.init_bonus - base.init_bonus, 5, "Alert: +5 initiative")
	must({"type": "setSurprised", "id": a.id, "surprised": true})
	ok(not c(a.id).surprised, "Alert: can't be surprised")
	eq(c(pc("mobile", "fighter", Vector2i(3, 1))).base_speed - base.base_speed, 10, "Mobile: +10 ft")
	eq(c(pc("lucky", "fighter", Vector2i(4, 1))).resources.luck.max, 3, "Lucky: 3 luck points")
	ok(c(pc("alert", "fighter", Vector2i(5, 1))).features.has("alert"), "feats show up as features")


func test_great_weapon_master() -> void:
	fresh()
	var f := pc("greatWeaponMaster", "fighter", Vector2i(2, 2), ["greatsword"])
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, o])
	var hp: int = c(o).hp
	Dice.forced = [10, 1, 1]  # +6 to hit -5 = 11 vs AC 11
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"power": true}})
	eq(hp - c(o).hp, 1 + 1 + 3 + 10, "−5 to hit, +10 damage")
	ok(not run({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"bonus": true}}).ok, "no bonus attack yet")
	Dice.forced = [20, 1, 1, 1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o})
	Dice.forced = [1]
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"bonus": true}})
	Dice.forced.clear()


func test_sharpshooter_and_crossbow_expert() -> void:
	fresh()
	var s := pc("sharpshooter", "fighter", Vector2i(1, 1), ["longbow"])
	var g := add("monster", "goblin", Vector2i(14, 14))
	var eng := engine()
	var bow := eng.find_attack(c(s), "longbow")
	bow.normal = 20  # make the goblin "long range" on a small map
	ok(not eng.attack_mode(c(s), c(g), "ranged", {"profile": bow}).dis.has("long range"), "Sharpshooter: no long-range disadvantage")
	eq(eng.power_attack_feat(c(s), bow), "sharpshooter", "ranged power attack")
	var x := pc("crossbowExpert", "fighter", Vector2i(13, 14), ["heavy_crossbow"])
	var xb := eng.find_attack(c(x), "heavy_crossbow")
	ok(not eng.attack_mode(c(x), c(g), "ranged", {"profile": xb}).dis.has("enemy adjacent"), "Crossbow Expert: adjacent enemy is fine")
	c(x).turn.attack_action_weapons = ["heavy_crossbow"]
	eq(eng.validate_attack(c(x), c(g), xb), "", "Crossbow Expert ignores loading")


func test_sentinel_stops_and_punishes() -> void:
	fresh()
	var f := pc("sentinel", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	var w := add("pregen", "wizard", Vector2i(3, 3))
	start([g, f, w])
	must({"type": "action", "actor_id": g, "action": "disengage"})
	Dice.forced = [15, 1]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	Dice.forced.clear()
	ok(c(f).reaction_used, "opportunity attack despite Disengage")
	eq(c(g).pos, Vector2i(3, 2), "the hit dropped the goblin's speed to 0")
	c(f).reaction_used = false
	c(g).turn = Stats.fresh_turn()
	Dice.forced = [1, 1]  # goblin misses the wizard, Sentinel misses the goblin
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": w})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("Sentinel: "), "Sentinel strikes when the goblin attacks someone else")


func test_mobile_avoids_opportunity_attacks() -> void:
	fresh()
	var f := pc("mobile", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g})
	must({"type": "move", "actor_id": f, "to": Vector2i(2, 6)})
	Dice.forced.clear()
	ok(not c(g).reaction_used, "no opportunity attack after a melee attack")


func test_polearm_master() -> void:
	fresh()
	var f := pc("polearmMaster", "fighter", Vector2i(2, 2), ["glaive"])
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([g, f])
	Dice.forced = [1]
	must({"type": "move", "actor_id": g, "to": Vector2i(4, 2)})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("Polearm Master"), "attack when the goblin enters reach")
	must({"type": "endTurn", "actor_id": g})
	var butt := {"type": "attack", "actor_id": f, "attack_id": "glaive_butt", "target_id": g, "options": {"bonus": true}}
	ok(not run(butt).ok, "butt end needs the Attack action first")
	Dice.forced = [1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "glaive", "target_id": g})
	must(butt)
	Dice.forced.clear()


func test_lucky_and_war_caster() -> void:
	fresh()
	var f := pc("lucky", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [2, 15, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g})
	Dice.forced.clear()
	eq(c(f).resources.luck.used, 1, "a luck point turned the miss around")
	ok(c(g).hp < c(g).max_hp, "and the reroll hit")
	var w := c(pc("warCaster", "wizard", Vector2i(6, 6)))
	Dice.forced = [1, 20]
	ok(engine().roll_save(w, "con", 15, {"concentration": true}).success, "War Caster: advantage on concentration saves")
	Dice.forced.clear()
