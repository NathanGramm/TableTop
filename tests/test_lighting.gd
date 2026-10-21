extends "res://tests/test_base.gd"

const BOB := {"name": "Bob", "is_dm": false}
const EVE := {"name": "Eve", "is_dm": false}


func test_darkness_and_darkvision() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))  # human: no darkvision
	var g := add("monster", "goblin", Vector2i(6, 2))  # darkvision 60 ft
	must({"type": "settings", "settings": {"light": "dark"}})
	var eng := engine()
	ok(not eng.can_see(c(f), c(g)), "human can't see in the dark")
	ok(eng.can_see(c(g), c(f)), "goblin sees with darkvision")
	ok(eng.attack_mode(c(f), c(g), "melee").dis.has("can't see target"), "attacking blind has disadvantage")
	ok(eng.attack_mode(c(g), c(f), "ranged").adv.has("unseen attacker"), "the unseen goblin has advantage")
	must({"type": "teleport", "id": g, "to": Vector2i(15, 2)})
	ok(not engine().can_see(c(g), c(f)), "darkvision only reaches 60 ft")
	eq(c(add("pregen", "wizard", Vector2i(1, 1))).darkvision, 60, "high elf has darkvision")
	ok(not run({"type": "settings", "settings": {"light": "pitch"}}).ok, "ambient light is validated")


func test_carried_light() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	c(f).controller = "Bob"
	must({"type": "settings", "settings": {"light": "dark"}})
	ok(not run({"type": "setLight", "actor_id": f, "source": "torch"}, EVE).ok, "only Bob lights Bob's torch")
	must({"type": "setLight", "actor_id": f, "source": "torch"}, BOB)
	eq(Grid.light_at(state, Vector2i(6, 2)), Grid.BRIGHT, "bright within 20 ft")
	eq(Grid.light_at(state, Vector2i(9, 2)), Grid.DIM, "dim for 20 ft more")
	eq(Grid.light_at(state, Vector2i(12, 2)), Grid.DARK, "dark beyond")
	ok(engine().can_see(c(f), c(g)), "the torch shows the goblin")
	for y in 16:
		state.map.cells[y * 16 + 4] = Grid.WALL
	eq(Grid.light_at(state, Vector2i(6, 2)), Grid.DARK, "walls block light")
	eq(Grid.light_map(state), _per_cell(), "the map and per-square light agree")
	start([g, f])
	ok(not run({"type": "setLight", "actor_id": f, "source": "lantern"}, BOB).ok, "can't light up on someone else's turn")
	must({"type": "setLight", "actor_id": f, "source": "none"}, BOB)
	ok(c(f).light.is_empty(), "doused off-turn")
	must({"type": "endTurn", "actor_id": g})
	must({"type": "setLight", "actor_id": f, "source": "torch"}, BOB)
	eq(c(f).turn.actions, 0, "lighting a torch takes the action")
	ok(not run({"type": "setLight", "actor_id": f, "source": "lantern"}, BOB).ok, "no second action to light another")


func _per_cell() -> PackedByteArray:
	var out := PackedByteArray()
	for y in state.map.height:
		for x in state.map.width:
			out.append(Grid.light_at(state, Vector2i(x, y)))
	return out


func test_painted_light_dim_and_hiding() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	c(g).hidden = c(f).passive_perception + 2
	ok(not engine().can_see(c(f), c(g)), "a good hider stays hidden")
	c(g).hidden = c(f).passive_perception - 2
	ok(engine().can_see(c(f), c(g)), "a poor hider is spotted in bright light")
	must({"type": "setCells", "cells": [{"x": 6, "y": 2, "light": 1 + Grid.DIM}]})
	eq(Grid.light_at(state, Vector2i(6, 2)), Grid.DIM, "DM painted dim light")
	ok(not engine().can_see(c(f), c(g)), "dim light: -5 passive Perception")
	must({"type": "resizeMap", "width": 20, "height": 20})
	eq(Grid.light_at(state, Vector2i(6, 2)), Grid.DIM, "painted light survives a resize")
	must({"type": "clearMap"})
	eq(Grid.light_at(state, Vector2i(6, 2)), Grid.BRIGHT, "cleared")


func test_fog_uses_light_and_darkvision() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(1, 1))
	c(f).controller = "Bob"
	var g := add("monster", "goblin", Vector2i(8, 1))
	var lit := add("monster", "goblin", Vector2i(14, 14))
	must({"type": "settings", "settings": {"fog": true, "light": "dark"}})
	var view := RulesEngine.redact_for(state, BOB, RulesEngine.update_fog(state, BOB))
	ok(not view.combatants.has(g), "goblin in the dark is not sent")
	eq(view.fog.visible[1 * 16 + 1], 1, "own square: there, but dark")
	eq(view.fog.visible[1 * 16 + 3], 0, "the dark around is unseen")
	must({"type": "setLight", "actor_id": lit, "source": "torch"})
	view = RulesEngine.redact_for(state, BOB, RulesEngine.update_fog(state, BOB))
	ok(view.combatants.has(lit), "a torch-bearer is seen from afar")
	var elf := add("pregen", "wizard", Vector2i(1, 3))
	view = RulesEngine.redact_for(state, BOB, RulesEngine.update_fog(state, BOB))
	ok(view.combatants.has(g), "the party's elf sees the goblin with darkvision")
	eq(view.fog.visible[3 * 16 + 5], 1 + Grid.DIM, "darkvision sees darkness as dim")
	ok(c(elf).side == "party", "elf is party")


func test_homebrew_monster_darkvision() -> void:
	var m := Homebrew.blank("monsters")
	m.darkvision = 120
	eq(Homebrew.validate_monster(m), [], "darkvision is valid")
	eq(Builder.build_monster("x", "m1", m).darkvision, 120, "and carried onto the creature")
	m.darkvision = 999
	ok(not Homebrew.validate_monster(m).is_empty(), "range checked")


func test_blindsight() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var s := add("monster", "giant_spider", Vector2i(3, 2))
	eq(c(s).blindsight, 10, "giant spider has blindsight")
	must({"type": "settings", "settings": {"light": "dark"}})
	must({"type": "toggleCondition", "id": s, "condition": "blinded"})
	must({"type": "toggleCondition", "id": f, "condition": "invisible"})
	ok(engine().can_see(c(s), c(f)), "blindsight: blinded, in the dark, target invisible, still perceived")
	must({"type": "teleport", "id": s, "to": Vector2i(8, 2)})
	ok(not engine().can_see(c(s), c(f)), "only within 10 ft")
	must({"type": "teleport", "id": s, "to": Vector2i(2, 4)})
	state.map.cells[3 * 16 + 2] = Grid.WALL
	state.map.cells[3 * 16 + 1] = Grid.WALL
	state.map.cells[3 * 16 + 3] = Grid.WALL
	ok(not engine().can_see(c(s), c(f)), "walls still block it")


func test_darkness_spell() -> void:
	fresh()
	var w := add("pregen", "warlock", Vector2i(1, 8))
	var elf := add("pregen", "wizard", Vector2i(2, 2))  # darkvision
	var g := add("monster", "goblin", Vector2i(8, 2))
	var beyond := add("monster", "goblin", Vector2i(14, 2))
	c(elf).light = {"id": "light", "name": "Light cantrip", "bright": 20, "dim": 20}
	ok(engine().can_see(c(elf), c(beyond)), "clear view before")
	must({"type": "cast", "actor_id": w, "spell_id": "darkness", "point": Vector2i(8, 2)})
	ok(c(w).concentration.get("name", "") == "Darkness", "concentrating")
	eq(Grid.light_at(state, Vector2i(8, 2)), Grid.DARK, "magical darkness")
	ok(c(elf).light.is_empty() and log_has("dispels Elowen Starweave's Light"), "overlapping Light is dispelled")
	c(elf).light = {"id": "torch", "name": "Torch", "bright": 20, "dim": 20}
	eq(Grid.light_at(state, Vector2i(8, 2)), Grid.DARK, "a torch can't light it")
	ok(not engine().can_see(c(elf), c(g)), "darkvision can't see into it")
	ok(not engine().can_see(c(elf), c(beyond)), "nor through it")
	ok(not engine().can_see(c(g), c(elf)), "and the goblin inside can't see out")
	ok(engine().attack_mode(c(elf), c(g), "ranged").dis.has("can't see target"), "attacks into it have disadvantage")
	c(w).controller = "Bob"
	must({"type": "settings", "settings": {"fog": true}})
	var view := RulesEngine.redact_for(state, BOB, RulesEngine.update_fog(state, BOB))
	ok(not view.combatants.has(g) and not view.combatants.has(beyond), "fog hides creatures in and behind it")
	engine().end_concentration(c(w))
	ok(engine().can_see(c(elf), c(g)), "gone when concentration ends")
