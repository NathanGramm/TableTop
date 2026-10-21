extends "res://tests/test_base.gd"


func test_exhaustion_four_halves_max_hp() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var full: int = c(f).max_hp
	must({"type": "setExhaustion", "id": f, "level": 4})
	eq(c(f).hp, full / 2, "HP drops to the halved maximum")
	c(f).hp = 1
	engine().heal(c(f), 999)
	eq(c(f).hp, full / 2, "healing stops at half")
	must({"type": "rest", "kind": "long"})
	eq(c(f).exhaustion, 3, "long rest removes a level")
	eq(c(f).hp, full, "and at level 3 the full maximum is back")


func test_protection_style_imposes_disadvantage() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(3, 2))
	var p := add("pregen", "paladin", Vector2i(2, 3))
	var g := add("monster", "goblin", Vector2i(4, 2))
	ok(c(p).shield, "paladin pregen carries a shield")
	c(p).options.append("protection")
	start([g, f, p])
	Dice.forced = [20, 1]
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": f})
	ok(c(p).reaction_used, "paladin spent its reaction")
	eq(c(f).hp, c(f).max_hp, "disadvantage took the 1, so the goblin missed")
	ok(log_has("protect"), "logged")


func test_protection_needs_a_shield_and_attunement_limit_in_creator() -> void:
	var d := Creator.new_def("fighter", "human")
	d.name = "Shieldwall"
	d.skills = ["athletics", "perception"]
	d.background = "sage"
	d.armor = "chain_mail"
	d.shield = true
	d.weapons = ["longsword"]
	d.style = "protection"
	eq(Creator.validate(d), [], "Protection is a legal fighter style")
	d["items"] = [{"id": "ring_of_protection"}, {"id": "cloak_of_protection"}, {"id": "amulet_of_health"}, {"id": "headband_of_intellect"}]
	ok(Creator.validate(d).any(func(e): return "attuned" in e), "four attuned items are rejected")
