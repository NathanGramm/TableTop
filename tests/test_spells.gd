extends "res://tests/test_base.gd"


func test_attack_cantrip_scales_with_level() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(8, 2))
	start([w, o])
	Dice.forced = [15, 5, 5]  # fire bolt is 2d10 at level 5
	must({"type": "cast", "actor_id": w, "spell_id": "fire_bolt", "targets": [o]})
	eq(c(o).hp, 49, "2d10 fire bolt")
	eq(c(w).turn.actions, 0, "used the action")


func test_bonus_action_spell_rule() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(3, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([cl, f, g])
	must({"type": "cast", "actor_id": cl, "spell_id": "healing_word", "targets": [f]})
	var r := run({"type": "cast", "actor_id": cl, "spell_id": "guiding_bolt", "targets": [g]})
	ok(not r.ok and "cantrip" in r.error, "after a bonus-action spell only a cantrip is allowed: " + r.error)
	Dice.forced = [1, 4]
	must({"type": "cast", "actor_id": cl, "spell_id": "sacred_flame", "targets": [g]})
	eq(c(cl).spellcasting.slots_used[1], 1, "one slot spent")


func test_concentration_breaks_on_failed_save() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(3, 2))
	start([cl, f])
	must({"type": "cast", "actor_id": cl, "spell_id": "bless", "targets": [cl, f]})
	eq(state.effects.size(), 2, "two blessed creatures")
	eq(c(cl).concentration.spell_id, "bless", "concentrating")
	Dice.forced = [1, 1]
	must({"type": "adjustHp", "id": cl, "amount": -10})
	eq(state.effects.size(), 0, "failed concentration ends Bless on everyone")
	ok(c(cl).concentration.is_empty(), "no longer concentrating")


func test_bless_adds_to_attacks() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 5))
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([cl, f, o])
	must({"type": "cast", "actor_id": cl, "spell_id": "bless", "targets": [f]})
	must({"type": "endTurn", "actor_id": cl})
	Dice.forced = [3, 4, 2]  # 3 + 7 + 1d4(4) = 14 >= AC 11
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	ok(c(o).hp < 59, "Bless die turned a miss into a hit")
	ok(log_has("(bless)"), "logged")


func test_fireball_half_damage_and_sculpt_spells() -> void:
	fresh(30, 30)
	var w := add("pregen", "wizard", Vector2i(2, 15))
	var g1 := add("monster", "ogre", Vector2i(15, 15))
	var g2 := add("monster", "bandit_captain", Vector2i(18, 15))
	var f := add("pregen", "fighter", Vector2i(15, 17))
	start([w, g1, g2, f])
	Dice.forced = [3, 3, 3, 3, 3, 3, 3, 3, 1, 20]  # 24 fire; ogre fails, captain saves
	must({"type": "cast", "actor_id": w, "spell_id": "fireball", "point": Vector2i(16, 16)})
	eq(c(g1).hp, 59 - 24, "failed save: full damage")
	eq(c(g2).hp, 65 - 12, "successful save: half damage")
	eq(c(f).hp, c(f).max_hp, "Sculpt Spells protects the ally")
	eq(c(w).spellcasting.slots_used[3], 1, "3rd-level slot used")


func test_magic_missile_and_shield() -> void:
	fresh()
	var s := add("pregen", "sorcerer", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(8, 2))
	start([s, o])
	Dice.forced = [3]
	must({"type": "cast", "actor_id": s, "spell_id": "magic_missile", "targets": [o]})
	eq(c(o).hp, 59 - 12, "three darts of 1d4+1 always hit")
	fresh()
	s = add("pregen", "sorcerer", Vector2i(2, 2))
	var w := add("pregen", "wizard", Vector2i(8, 2), 5, "enemy")
	start([s, w])
	must({"type": "cast", "actor_id": s, "spell_id": "magic_missile", "targets": [w]})
	eq(c(w).hp, c(w).max_hp, "Shield blocks magic missile")
	ok(c(w).reaction_used, "using the wizard's reaction")
	eq(c(w).spellcasting.slots_used[1], 1, "and a slot")


func test_hold_person_paralyzes_humanoids_only() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var b := add("monster", "bandit", Vector2i(5, 2))
	var wolf := add("monster", "wolf", Vector2i(5, 4))
	start([cl, b, wolf])
	ok(not run({"type": "cast", "actor_id": cl, "spell_id": "hold_person", "targets": [wolf]}).ok, "Hold Person fails on beasts")
	Dice.forced = [2]
	must({"type": "cast", "actor_id": cl, "spell_id": "hold_person", "targets": [b]})
	ok(engine().has_cond(c(b), "paralyzed"), "bandit is paralyzed")
	ok(engine().has_cond(c(b), "incapacitated"), "paralysis implies incapacitated")


func test_thunderwave_pushes() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "orc", Vector2i(3, 2))
	start([w, o])
	Dice.forced = [1, 1, 1, 1, 1]
	must({"type": "cast", "actor_id": w, "spell_id": "thunderwave", "point": Vector2i(3, 2)})
	eq(c(o).pos, Vector2i(5, 2), "failed save: pushed 10 ft")


func test_sleep_affects_lowest_hp_first() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(1, 1))
	var g1 := add("monster", "goblin", Vector2i(8, 8))
	var g2 := add("monster", "goblin", Vector2i(9, 8))
	var o := add("monster", "ogre", Vector2i(8, 10))
	start([w, g1, g2, o])
	Dice.forced = [3, 3, 3, 3, 3]  # 15 HP of sleep
	must({"type": "cast", "actor_id": w, "spell_id": "sleep", "point": Vector2i(9, 9)})
	ok(engine().has_cond(c(g1), "unconscious") and engine().has_cond(c(g2), "unconscious"), "both goblins sleep (7+7 <= 15)")
	ok(not engine().has_cond(c(o), "unconscious"), "ogre is too tough")
	engine().deal_damage(c(g1), [{"amount": 1, "type": "piercing"}])
	ok(not engine().has_cond(c(g1), "unconscious"), "damage wakes a sleeper")


func test_eldritch_blast_beams_and_agonizing() -> void:
	fresh()
	var wl := add("pregen", "warlock", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(10, 2))
	start([wl, o])
	Dice.forced = [15, 5, 15, 5]  # two beams at level 5, each 5 + 4 (agonizing)
	must({"type": "cast", "actor_id": wl, "spell_id": "eldritch_blast", "targets": [o]})
	eq(c(o).hp, 59 - 18, "two beams with Agonizing Blast")
	eq(c(o).pos, Vector2i(14, 2), "Repelling Blast pushes 10 ft per beam")


func test_hex_and_hunters_mark() -> void:
	fresh()
	var rg := add("pregen", "ranger", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(10, 2))
	start([rg, o])
	must({"type": "cast", "actor_id": rg, "spell_id": "hunters_mark", "targets": [o]})
	Dice.forced = [15, 4, 3, 2]  # longbow 4 + 4 dex, mark 3, colossus slayer doesn't apply (full HP)
	must({"type": "attack", "actor_id": rg, "attack_id": "longbow", "target_id": o})
	eq(c(o).hp, 59 - 11, "Hunter's Mark adds 1d6 to weapon hits")


func test_divine_smite_on_hit() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2))
	var sk := add("monster", "skeleton", Vector2i(3, 2))
	start([p, sk])
	Dice.forced = [15, 1, 1, 1, 1]  # 1d8 longsword + 3d8 smite vs undead (2 + 1 undead) -> 1+4 str+... dueling? paladin uses Defense
	must({"type": "attack", "actor_id": p, "attack_id": "longsword", "target_id": sk, "options": {"smite": 1}})
	eq(c(p).spellcasting.slots_used[1], 1, "smite spends a slot on a hit")
	ok(log_has("divine smite"), "smite logged")


func test_healing_word_revives_dying_ally() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(6, 2))
	start([cl, f])
	must({"type": "setHp", "id": f, "hp": 0})
	Dice.forced = [2]
	must({"type": "cast", "actor_id": cl, "spell_id": "healing_word", "targets": [f]})
	eq(c(f).hp, 2 + 4 + 3, "1d4 + Wis 4 + Disciple of Life (2 + 1)")
	ok(not engine().is_dying(c(f)), "back on their feet")


func test_spirit_guardians_damages_enemies_starting_turn_nearby() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(4, 2))
	start([cl, o])
	must({"type": "cast", "actor_id": cl, "spell_id": "spirit_guardians"})
	Dice.forced = [2, 4, 4, 4]
	must({"type": "endTurn", "actor_id": cl})
	eq(c(o).hp, 59 - 12, "3d8 radiant on a failed Wisdom save at start of turn")


func test_turn_undead_destroys_weak_undead() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(2, 2))
	var sk := add("monster", "skeleton", Vector2i(4, 2))
	var z := add("monster", "ghoul", Vector2i(2, 5))
	start([cl, sk, z])
	Dice.forced = [1, 1]
	must({"type": "power", "actor_id": cl, "power_id": "turn_undead"})
	ok(c(sk).dead, "Destroy Undead: CR 1/4 skeleton destroyed")
	ok(engine().has_tag(c(z), "turned"), "CR 1 ghoul is turned")


func test_breath_weapon() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([p, g])
	Dice.forced = [6, 6, 1]
	must({"type": "power", "actor_id": p, "power_id": "breath_weapon", "point": Vector2i(4, 2)})
	ok(c(g).dead, "12 fire kills the goblin")
	eq(c(p).resources.breath.used, 1, "once per short rest")


func test_higher_level_spells() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(1, 1), 10)
	var cl := add("pregen", "cleric", Vector2i(1, 3), 10)
	var o := add("monster", "ogre", Vector2i(6, 6))
	var g := add("monster", "goblin", Vector2i(12, 12))
	for sid in ["haste", "ice_storm", "hold_monster", "hypnotic_pattern", "cone_of_cold", "dimension_door"]:
		c(w).spellcasting.known.append(sid)
	for sid in ["death_ward", "mass_cure_wounds", "raise_dead", "greater_restoration", "flame_strike"]:
		ok(c(cl).spellcasting.known.has(sid) or sid in ["greater_restoration", "flame_strike"], "life cleric has %s prepared" % sid)
		if not c(cl).spellcasting.known.has(sid):
			c(cl).spellcasting.known.append(sid)
	var speed := engine().speed_of(c(cl))
	must({"type": "cast", "actor_id": w, "spell_id": "haste", "targets": [cl]})
	eq(engine().speed_of(c(cl)), speed * 2, "Haste doubles speed")
	eq(engine().ac_of(c(cl)), c(cl).ac + 2, "and gives +2 AC")
	Dice.forced = Array(range(6)).map(func(_i): return 4) + [1]
	must({"type": "cast", "actor_id": w, "spell_id": "ice_storm", "point": Vector2i(6, 6)})
	ok(log_has("bludgeoning") and log_has("cold"), "Ice Storm deals two damage types")
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "hold_monster", "targets": [o]})
	ok(engine().has_cond(c(o), "paralyzed"), "Hold Monster works on an ogre")
	must({"type": "cast", "actor_id": cl, "spell_id": "death_ward", "targets": [cl]})
	engine().deal_damage(c(cl), [{"amount": 999, "type": "fire"}])
	ok(c(cl).hp == 1 and not c(cl).dead, "Death Ward: 1 HP instead of 0 (even past massive damage)")
	c(cl).exhaustion = 2
	must({"type": "cast", "actor_id": cl, "spell_id": "greater_restoration", "targets": [cl]})
	eq(c(cl).exhaustion, 1, "Greater Restoration removes a level of exhaustion")
	c(g).pos = Vector2i(2, 3)
	engine().kill(c(g), "")
	must({"type": "cast", "actor_id": cl, "spell_id": "raise_dead", "targets": [g]})
	ok(not c(g).dead and c(g).hp == 1, "Raise Dead")
	must({"type": "cast", "actor_id": w, "spell_id": "dimension_door", "point": Vector2i(14, 1)})
	eq(c(w).pos, Vector2i(14, 1), "Dimension Door")


func test_hypnotic_pattern_ends_on_damage() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(1, 1), 10)
	var g := add("monster", "goblin", Vector2i(8, 8))
	c(w).spellcasting.known.append("hypnotic_pattern")
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "hypnotic_pattern", "point": Vector2i(8, 8)})
	ok(engine().has_cond(c(g), "incapacitated") and engine().speed_of(c(g)) == 0, "entranced: incapacitated, speed 0")
	engine().deal_damage(c(g), [{"amount": 1, "type": "fire"}])
	ok(not engine().has_cond(c(g), "incapacitated"), "damage snaps it out")
