extends "res://tests/test_base.gd"
## Martial class features from 6th to 10th level.


func test_barbarian() -> void:
	fresh()
	var b := add("pregen", "barbarian", Vector2i(2, 2), 10)
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([b, o])
	must({"type": "feature", "actor_id": b, "feature": "rage"})
	engine().add_effect({"name": "Scared", "conditions": ["frightened"]}, o, b)
	ok(not engine().has_cond(c(b), "frightened"), "Mindless Rage: no fear while raging")
	Dice.forced = [20, 6, 6, 6]  # crit with the greataxe: 2d12 + 1 brutal die (not doubled)
	must({"type": "attack", "actor_id": b, "attack_id": "greataxe", "target_id": o})
	ok(log_has("brutal critical"), "Brutal Critical adds a die")
	ok(engine().find_power(c(b), "intimidating_presence").size() > 0, "Intimidating Presence available")
	Dice.forced = [1]
	must({"type": "endTurn", "actor_id": b})
	must({"type": "dmEndTurn"})
	Dice.forced = [1]
	must({"type": "power", "actor_id": b, "power_id": "intimidating_presence", "targets": [o]})
	ok(engine().has_cond(c(o), "frightened"), "ogre frightened by Intimidating Presence")


func test_fighter() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 10)
	eq(c(f).init_bonus, 2, "Remarkable Athlete adds half proficiency to initiative")
	Dice.forced = [2, 18]
	var s := engine().roll_save(c(f), "wis", 15)
	ok(s.success and engine().res_left(c(f), "indomitable") == 0, "Indomitable rerolls a failed save")
	var d := Creator.normalize(Pregens.ALL.fighter.duplicate(true).merged({"level": 10}))
	ok(d.has("style2") and d.style2 != d.style, "creator picks a second fighting style: %s" % str(d.get("style2")))
	var built := Builder.build_character(d.merged({"style2": "defense"}, true), 10, "x1")
	ok(built.options.has("dueling") and built.options.has("defense"), "both styles apply")


func test_monk() -> void:
	fresh()
	var m := add("pregen", "monk", Vector2i(2, 2), 10)
	var w := add("pregen", "wizard", Vector2i(8, 2), 10)
	ok(engine().find_attack(c(m), "unarmed").get("magical", false), "Ki-Empowered Strikes")
	ok(c(m).immunities.has("poison") and c(m).cond_immunities.has("poisoned"), "Purity of Body")
	c(m).hp = 1
	must({"type": "power", "actor_id": m, "power_id": "wholeness_of_body"})
	eq(c(m).hp, 31, "Wholeness of Body heals 3 x level")
	c(m).side = "enemy"
	Dice.forced = Array(range(8)).map(func(_i): return 6) + [20]  # damage is rolled first, then the monk's save succeeds
	must({"type": "cast", "actor_id": w, "spell_id": "fireball", "point": Vector2i(2, 2)})
	eq(c(m).hp, 31, "Evasion: no damage on a successful Dex save")
	engine().add_effect({"name": "Scared", "conditions": ["frightened"]}, w, m)
	must({"type": "power", "actor_id": m, "power_id": "stillness_of_mind"})
	ok(not engine().has_cond(c(m), "frightened"), "Stillness of Mind ends fear")


func test_paladin_auras() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2), 10)
	var ally := add("pregen", "rogue", Vector2i(3, 2), 10)
	var cha := maxi(1, Stats.mod(c(p).abilities.cha))
	Dice.forced = [10]
	var s := engine().roll_save(c(ally), "con", 1)
	eq(s.total, 10 + engine().save_mod(c(ally), "con") + cha, "Aura of Protection adds Cha to an ally's save")
	engine().add_effect({"name": "Charm", "conditions": ["charmed", "frightened"]}, p, ally)
	ok(not engine().has_cond(c(ally), "charmed") and not engine().has_cond(c(ally), "frightened"), "Auras of Devotion and Courage")
	must({"type": "teleport", "id": ally, "to": Vector2i(9, 9)})
	ok(engine().has_cond(c(ally), "charmed"), "only within 10 ft")
	c(p).hp = 0
	must({"type": "teleport", "id": ally, "to": Vector2i(3, 2)})
	ok(engine().has_cond(c(ally), "frightened"), "and only while the paladin is conscious")


func test_ranger_and_rogue() -> void:
	fresh()
	var r := add("pregen", "ranger", Vector2i(2, 2), 8)
	for x in range(3, 7):
		state.map.cells[2 * 16 + x] = Grid.DIFFICULT
	must({"type": "move", "actor_id": r, "to": Vector2i(8, 2)})
	eq(c(r).pos, Vector2i(8, 2), "Land's Stride: 30 ft through difficult terrain")
	c(r).options.append("escape_the_horde")
	var g := add("monster", "goblin", Vector2i(9, 2))
	ok(engine().attack_mode(c(g), c(r), "melee", {"opportunity": true}).dis.has("escape the horde"), "Escape the Horde")
	var rogue := add("pregen", "rogue", Vector2i(2, 8), 9)
	ok(c(rogue).features.has("evasion") and c(rogue).features.has("supremeSneak"), "rogue gets Evasion and Supreme Sneak")
	start([rogue, g, r])
	Dice.forced = [2, 15]
	must({"type": "action", "actor_id": rogue, "action": "hide"})
	ok(c(rogue).hidden >= 15, "Supreme Sneak: Stealth with advantage (%d)" % c(rogue).hidden)
	var d := Creator.normalize(Pregens.ALL.ranger.duplicate(true).merged({"level": 7}))
	ok(d.options.has("escape_the_horde") and Creator.validate(d).is_empty(), "creator gives 7th-level rangers a Defensive Tactic: %s" % str(Creator.validate(d)))
