extends "res://tests/test_base.gd"


func test_wild_shape_takes_beast_form_and_carries_damage_over() -> void:
	fresh()
	var d := add("pregen", "druid", Vector2i(2, 2), 4)
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([d, g])
	var wis: int = c(d).abilities.wis
	var str_score: int = c(d).abilities.str
	var hp: int = c(d).hp
	ok(not run({"type": "feature", "actor_id": d, "feature": "wildShape", "choice": "giant_spider"}).ok, "CR 1 is too high at 4th level")
	ok(not run({"type": "feature", "actor_id": d, "feature": "wildShape", "choice": "goblin"}).ok, "only beasts")
	must({"type": "feature", "actor_id": d, "feature": "wildShape", "choice": "wolf"})
	eq(c(d).hp, 11, "wolf HP")
	eq(c(d).abilities.str, 12, "wolf Strength")
	eq(c(d).abilities.wis, wis, "keeps its own Wisdom")
	eq(c(d).get("mini", ""), "wolf", "token shows the wolf")
	eq(c(d).resources.wild_shape.used, 1, "one use spent")
	ok(not run({"type": "cast", "actor_id": d, "spell_id": "produce_flame", "targets": [g]}).ok, "no spellcasting as a beast")
	engine().deal_damage(c(d), [{"amount": 16, "type": "slashing"}], {"label": "test"})
	ok(not c(d).fdata.has("wild_shape"), "reverts at 0 HP")
	eq(c(d).hp, hp - 5, "the extra 5 damage carries over")
	ok(not c(d).has("mini"), "normal mini again")
	eq(c(d).abilities.str, str_score, "own Strength back")


func test_revert_and_natural_recovery() -> void:
	fresh()
	var d := add("pregen", "druid", Vector2i(2, 2), 4)
	var g := add("monster", "goblin", Vector2i(9, 9))
	start([d, g])
	must({"type": "feature", "actor_id": d, "feature": "wildShape", "choice": "wolf"})
	must({"type": "feature", "actor_id": d, "feature": "revertShape"})
	ok(not c(d).fdata.has("wild_shape"), "reverted as a bonus action")
	must({"type": "endCombat"})
	c(d).spellcasting.slots_used[1] = 2
	c(d).spellcasting.slots_used[2] = 1
	must({"type": "rest", "kind": "short"})
	eq(c(d).spellcasting.slots_used[2], 0, "Natural Recovery: 2nd-level slot back")
	eq(c(d).spellcasting.slots_used[1], 2, "budget of 2 spent")
	eq(c(d).resources.natural_recovery.used, 1, "once per long rest")
	eq(c(d).resources.wild_shape.used, 0, "Wild Shape back after a short rest")
