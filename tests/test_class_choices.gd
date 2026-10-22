extends "res://tests/test_base.gd"
## Low-level class features that were text only: Pact Boon, Favored Enemy, Divine Sense, Fast Hands.


func test_pact_boons() -> void:
	var d := Creator.normalize(Pregens.ALL.warlock.duplicate(true).merged({"level": 3}))
	ok(d.options.has("pact_blade") and d.pact_weapon == "longsword", "creator defaults to a pact longsword: %s" % str(d.options))
	eq(Creator.validate(d), [], "valid")
	var w := Builder.build_character(d, 3, "x")
	var pact: Array = w.attacks.filter(func(a): return a.name == "Pact Longsword")
	ok(pact.size() == 1 and pact[0].magical and pact[0].proficient, "proficient, magical pact weapon")
	var t := Creator.normalize(d.merged({"options": d.options.filter(func(o): return o != "pact_blade") + ["pact_tome"], "tome_cantrips": ["sacred_flame", "vicious_mockery", "shillelagh"]}, true))
	ok(not t.has("pact_weapon"), "no pact weapon without the Blade")
	eq(Creator.validate(t), [], "Tome valid: %s" % str(Creator.validate(t)))
	ok(Builder.build_character(t, 3, "x").spellcasting.known.has("sacred_flame"), "Book of Shadows cantrip known")
	ok(not Creator.validate(t.merged({"tome_cantrips": t.tome_cantrips + ["fire_bolt"]}, true)).is_empty(), "only three")
	var lv2 := Creator.normalize(Pregens.ALL.warlock.duplicate(true).merged({"level": 2}))
	ok(not lv2.options.any(func(o): return Creator.PACT_BOONS.has(o)), "no boon before 3rd level")


func test_favored_enemy_and_foe_slayer() -> void:
	var d := Creator.normalize(Pregens.ALL.ranger.duplicate(true).merged({"level": 6}))
	eq(d.options.filter(func(o): return Creator.FAVORED_ENEMIES.has(o)).size(), 2, "two favored enemies at 6th")
	eq(Creator.validate(d), [], "valid")
	fresh()
	var r := add("pregen", "ranger", Vector2i(2, 2), 20)
	c(r).fdata.favored_enemies = ["humanoid"]
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([r, g])
	Dice.forced = [15]
	must({"type": "attack", "actor_id": r, "attack_id": "shortsword", "target_id": g})
	ok(log_has("foe slayer"), "Foe Slayer adds Wisdom against a favored enemy")


func test_divine_sense_and_fast_hands() -> void:
	fresh()
	var p := add("pregen", "paladin", Vector2i(2, 2), 1)
	add("monster", "zombie", Vector2i(6, 2))
	var rg := add("pregen", "rogue", Vector2i(2, 6), 3)
	start([p, rg])
	must({"type": "power", "actor_id": p, "power_id": "divine_sense"})
	ok(log_has("Zombie (undead"), "Divine Sense finds the zombie")
	must({"type": "endTurn", "actor_id": p})
	must({"type": "giveItem", "id": rg, "item": {"id": "potion_of_healing", "base": ""}})
	must({"type": "useItem", "actor_id": rg, "index": c(rg).items.size() - 1})
	ok(not c(rg).turn.bonus and c(rg).turn.actions == 1, "Fast Hands: the potion took the bonus action")
