extends "res://tests/test_base.gd"

const BOB := {"name": "Bob", "is_dm": false}


func test_walls_block_vision() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(1, 5))
	for y in range(0, 16):
		if y != 5:
			state.map.cells[y * 16 + 6] = Grid.WALL
	var vis := Grid.visible_cells(state, [c(f)])
	ok(vis[5 * 16 + 10] > 0, "straight through the doorway")
	ok(vis[2 * 16 + 6] > 0, "the wall itself is visible")
	eq(vis[1 * 16 + 10], 0, "behind the wall is not")
	fresh()
	f = add("pregen", "fighter", Vector2i(2, 2))
	state.map.cells[2 * 16 + 3] = Grid.WALL
	state.map.cells[3 * 16 + 2] = Grid.WALL
	eq(Grid.visible_cells(state, [c(f)])[3 * 16 + 3], 0, "can't peek between diagonal walls")


func test_fog_hides_unseen_enemies_and_remembers_the_map() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(1, 5))
	c(f).controller = "Bob"
	var seen := add("monster", "goblin", Vector2i(10, 5))
	var lurker := add("monster", "goblin", Vector2i(10, 1))
	for y in range(0, 16):
		if y != 5:
			state.map.cells[y * 16 + 6] = Grid.WALL
	must({"type": "settings", "settings": {"fog": true}})
	var fog := RulesEngine.update_fog(state, BOB)
	var view := RulesEngine.redact_for(state, BOB, fog)
	ok(view.combatants.has(seen), "goblin in sight is sent")
	ok(not view.combatants.has(lurker), "goblin behind the wall is not")
	ok(view.combatants.has(f), "own character always")
	ok(view.has("fog") and not view.has("fog_explored"), "player gets their fog, not everyone's")
	eq(RulesEngine.redact_for(state, {"name": "DM", "is_dm": true}).combatants.size(), 3, "DM sees everything")
	must({"type": "teleport", "id": f, "to": Vector2i(1, 12)})
	fog = RulesEngine.update_fog(state, BOB)
	eq(fog.visible[5 * 16 + 10], 0, "no longer visible after moving")
	eq(fog.explored[5 * 16 + 10], 1, "but remembered")
	ok(not RulesEngine.redact_for(state, BOB, fog).combatants.has(seen), "creatures in remembered fog aren't shown")
	must({"type": "resetFog"})
	eq(RulesEngine.update_fog(state, BOB).explored[5 * 16 + 10], 0, "DM can reset the explored map")
	must({"type": "settings", "settings": {"fog": false}})
	ok(RulesEngine.update_fog(state, BOB).is_empty(), "fog off")


func test_hidden_tokens() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	c(f).controller = "Bob"
	must({"type": "spawn", "kind": "monster", "template": "orc", "pos": Vector2i(3, 2), "hidden": true})
	var o := ""
	for id in state.combatants:
		if c(id).name == "Orc":
			o = id
	var view := RulesEngine.redact_for(state, BOB)
	ok(not view.combatants.has(o), "hidden orc not sent to players")
	ok(not view.log.any(func(e): return "Orc" in e.text), "nor mentioned in their log")
	var g := add("monster", "goblin", Vector2i(9, 9))
	start([f, g])
	ok(not state.combat.order.has(o), "hidden creatures sit out of initiative")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "move", "actor_id": g, "to": Vector2i(9, 10)})
	must({"type": "setHidden", "id": o, "hidden": false})
	ok(state.combat.order.has(o), "revealed: joins initiative")
	ok(log_has("Orc appears!"), "announced")
	ok(RulesEngine.redact_for(state, BOB).combatants.has(o), "players see it now")
	ok(not run({"type": "setHidden", "id": g, "hidden": true}).ok, "can't hide the creature whose turn it is")
	must({"type": "setHidden", "id": o, "hidden": true})
	ok(not state.combat.order.has(o), "hidden again: leaves initiative")
	ok(not engine().can_react(c(o)), "hidden creatures don't take reactions")
