extends "res://tests/test_base.gd"

const BOB := {"name": "Bob", "is_dm": false}
const EVE := {"name": "Eve", "is_dm": false}


func _setup_oa() -> Array:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	c(f).controller = "Bob"
	start([g, f])
	return [f, g]


func test_player_is_asked_before_opportunity_attack() -> void:
	var ids := _setup_oa()
	var f: String = ids[0]
	var g: String = ids[1]
	var r := must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(r.get("pending", false), "move pauses for a decision")
	eq(c(g).pos, Vector2i(3, 2), "nothing happens until Bob answers")
	eq(state.pending.prompt.controller, "Bob", "Bob is asked")
	ok("opportunity attack" in state.pending.prompt.text, "prompt explains the trigger: " + state.pending.prompt.text)
	ok(not run({"type": "endTurn", "actor_id": g}).ok, "the game waits")
	ok(not run({"type": "react", "choice": true}, EVE).ok, "only Bob (or the DM) answers")
	ok(run({"type": "chat", "text": "hurry up"}, EVE).ok, "chat still works")
	Dice.forced = [15, 5]
	must({"type": "react", "choice": true}, BOB)
	ok(not state.has("pending"), "decision resolved")
	ok(c(f).reaction_used, "fighter used its reaction")
	ok(c(g).dead, "and killed the fleeing goblin")


func test_declining_lets_the_creature_go() -> void:
	var ids := _setup_oa()
	var f: String = ids[0]
	var g: String = ids[1]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	must({"type": "react", "choice": false}, BOB)
	eq(c(g).pos, Vector2i(7, 2), "goblin got away")
	ok(not c(f).reaction_used, "reaction kept")


func test_replay_keeps_earlier_rolls_and_asks_again() -> void:
	fresh()
	var f1 := add("pregen", "fighter", Vector2i(2, 1))
	var f2 := add("pregen", "barbarian", Vector2i(2, 3))
	var g := add("monster", "ogre", Vector2i(3, 2))
	c(f1).controller = "Bob"
	c(f2).controller = "Eve"
	start([g, f1, f2])
	must({"type": "move", "actor_id": g, "to": Vector2i(8, 2)})
	eq(state.pending.prompt.controller, "Bob", "first Bob")
	must({"type": "react", "choice": true}, BOB)
	eq(state.pending.prompt.controller, "Eve", "then Eve, in the same move")
	var ogre_hp: int = c(g).hp
	eq(ogre_hp, 59, "still nothing applied while waiting")
	must({"type": "react", "choice": false}, EVE)
	ok(c(f1).reaction_used and not c(f2).reaction_used, "each answer applied")
	ok(c(g).pos == Vector2i(8, 2) or c(g).dead or c(g).hp < 59, "move finished")


func test_shield_prompt_for_a_player_wizard() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "orc", Vector2i(3, 2))
	c(w).controller = "Bob"
	start([o, w])
	Dice.forced = [9, 6]  # 9 + 5 = 14 vs AC 13 hits; Shield makes it AC 18 -> miss
	must({"type": "attack", "actor_id": o, "attack_id": "greataxe", "target_id": w})
	ok("Cast Shield" in state.get("pending", {}).get("prompt", {}).get("text", ""), "asked about Shield")
	Dice.forced = [9, 6]
	must({"type": "react", "choice": true}, BOB)
	eq(c(w).hp, c(w).max_hp, "Shield turned the hit into a miss")
	eq(c(w).spellcasting.slots_used[1], 1, "and used a slot")


func test_reaction_settings() -> void:
	var ids := _setup_oa()
	var f: String = ids[0]
	var g: String = ids[1]
	must({"type": "setReactions", "actor_id": f, "mode": "never"}, BOB)
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(not state.has("pending") and not c(f).reaction_used, "never: no prompt, no reaction")
	ids = _setup_oa()
	f = ids[0]
	g = ids[1]
	must({"type": "setReactions", "actor_id": f, "mode": "auto"}, BOB)
	Dice.forced = [15, 5]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(not state.has("pending") and c(f).reaction_used, "auto: reacts without asking")
	var view := RulesEngine.redact_for({"pending": {"seed": 1, "cmd": {}, "user": {}, "decisions": [], "prompt": {"name": "x"}}, "combatants": {}, "log": []}, BOB)
	ok(not view.pending.has("seed"), "players never see the replay seed")


func test_timeout_uses_the_default() -> void:
	var ids := _setup_oa()
	var g: String = ids[1]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	Dice.forced = [15, 5]
	must({"type": "react", "choice": state.pending.prompt.default, "timeout": true})
	ok(c(g).dead, "default is to take the opportunity attack")
	ok(log_has("No answer from Bob in time"), "timeout logged")


func test_monster_ai_waits_for_player_reaction() -> void:
	var ids := _setup_oa()
	var f: String = ids[0]
	var g: String = ids[1]
	# A turned goblin's AI flees, provoking Bob's fighter.
	engine().add_effect({"name": "Turned", "tag": "turned", "conditions": ["frightened"]}, f, g)
	must({"type": "autoTurn"})
	ok(state.has("pending") and state.pending.prompt.controller == "Bob", "AI move paused for Bob's decision")
	must({"type": "react", "choice": false}, BOB)
	ok(not state.has("pending"), "resolved")
	ok(c(g).pos != Vector2i(3, 2), "goblin fled")
	eq(current(), f, "AI finished its turn after the answer")
