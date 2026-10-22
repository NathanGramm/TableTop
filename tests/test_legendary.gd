extends "res://tests/test_base.gd"


func test_legendary_actions_between_turns() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var d := add("monster", "adult_white_dragon", Vector2i(3, 2))
	start([f, d])
	eq(current(), f, "fighter first")
	eq(engine().res_left(c(d), "legendary"), 3, "three legendary actions")
	must({"type": "legendary", "actor_id": d, "action_id": "tail", "targets": [f]})
	eq(engine().res_left(c(d), "legendary"), 2, "tail costs 1")
	must({"type": "legendary", "actor_id": d, "action_id": "wing_attack"})
	eq(engine().res_left(c(d), "legendary"), 0, "wing attack costs 2")
	ok(log_has("Fighter") and log_has("DEX save vs Wing Attack"), "wing attack resolved")
	ok(not log_has("Adult White Dragon DEX save"), "the dragon isn't caught in its own wings")
	ok(not run({"type": "legendary", "actor_id": d, "action_id": "tail", "targets": [f]}).ok, "none left")
	must({"type": "endTurn", "actor_id": f})
	eq(current(), d, "dragon's turn")
	eq(engine().res_left(c(d), "legendary"), 3, "refilled on its own turn")
	ok(not run({"type": "legendary", "actor_id": d, "action_id": "tail", "targets": [f]}).ok, "not on its own turn")


func test_legendary_resistance_turns_a_failed_save() -> void:
	fresh()
	var d := add("monster", "adult_white_dragon", Vector2i(3, 2))
	var e := engine()
	Dice.forced = [1]
	var s := e.roll_save(e.get_c(d), "wis", 30)
	ok(s.success, "legendary resistance makes it a success")
	eq(e.res_left(e.get_c(d), "legendary_resistance"), 2, "one use spent")


func test_auto_npc_uses_legendary_action() -> void:
	fresh()
	state.settings.auto_npc = true
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var u := add("monster", "unicorn", Vector2i(3, 2))
	start([f, u])
	must({"type": "endTurn", "actor_id": f})
	ok(log_has("legendary action: Hooves"), "unicorn kicks as the fighter's turn ends")


func test_troll_regenerates_unless_burned() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var t := add("monster", "troll", Vector2i(9, 9))
	start([f, t])
	engine().deal_damage(c(t), [{"amount": 30, "type": "slashing"}], {"label": "test"})
	must({"type": "endTurn", "actor_id": f})
	eq(c(t).hp, 84 - 30 + 10, "regains 10")
	must({"type": "endTurn", "actor_id": t})
	engine().deal_damage(c(t), [{"amount": 5, "type": "fire"}], {"label": "test"})
	must({"type": "endTurn", "actor_id": f})
	eq(c(t).hp, 84 - 30 + 10 - 5, "fire stops it")


func test_unicorn_healing_touch_has_three_uses() -> void:
	fresh()
	var u := add("monster", "unicorn", Vector2i(3, 2))
	eq(engine().res_left(c(u), "healing_touch"), 3, "3/day")
