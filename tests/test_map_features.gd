extends "res://tests/test_base.gd"
## Doors and low walls.


func test_doors_block_until_opened() -> void:
	fresh()
	for y in 16:
		state.map.cells[y * 16 + 5] = Grid.WALL
	state.map.cells[5 * 16 + 5] = Grid.DOOR
	var f := add("pregen", "fighter", Vector2i(4, 5))
	var g := add("monster", "goblin", Vector2i(8, 5))
	ok(not Grid.line_of_sight(state, c(f), c(g)), "a closed door blocks sight")
	ok(not Grid.reachable(state, c(f), 30).cells.has(Vector2i(6, 5)), "a closed door blocks movement")
	ok(not run({"type": "door", "actor_id": g, "x": 5, "y": 5}).ok, "the goblin is too far to reach the door")
	must({"type": "door", "actor_id": f, "x": 5, "y": 5})
	eq(state.map.cells[5 * 16 + 5], Grid.DOOR_OPEN, "the fighter opens the door")
	ok(Grid.line_of_sight(state, c(f), c(g)), "sight through the open door")
	ok(Grid.reachable(state, c(f), 30).cells.has(Vector2i(6, 5)), "walk through the open door")
	c(f).pos = Vector2i(5, 5)
	ok(not run({"type": "door", "actor_id": f, "x": 5, "y": 5}).ok, "can't close a door on someone standing in it")
	c(f).pos = Vector2i(6, 5)
	must({"type": "door", "actor_id": f, "x": 5, "y": 5})
	eq(state.map.cells[5 * 16 + 5], Grid.DOOR, "and closes it behind them")
	ok(not run({"type": "door", "actor_id": f, "x": 6, "y": 6}).ok, "no door there")


func test_low_wall_half_cover() -> void:
	fresh()
	var a := add("pregen", "ranger", Vector2i(1, 5))
	var t := add("monster", "goblin", Vector2i(8, 5))
	for y in range(3, 8):
		state.map.cells[y * 16 + 7] = Grid.LOW_WALL
	ok(Grid.line_of_sight(state, c(a), c(t)), "low walls don't block sight")
	eq(Grid.cover(state, c(a), c(t)), 2, "a low wall gives half cover")
	eq(Grid.cell_at(state.map, 7, 5), Grid.DIFFICULT, "climbing over is difficult terrain")
	c(t).pos = Vector2i(7, 5)
	eq(Grid.cover(state, c(a), c(t)), 0, "standing on the low wall gives no cover")


func test_props() -> void:
	fresh()
	must({"type": "placeProp", "m": "mini-dungeon/barrel", "x": 3, "y": 4, "r": 5, "h": 1})
	must({"type": "placeProp", "m": "nature/tree_default", "x": 10, "y": 10})
	eq(state.map.props[0], {"m": "mini-dungeon/barrel", "x": 3, "y": 4, "r": 1, "h": 1}, "prop stored with its turn and height")
	ok(not run({"type": "placeProp", "m": "../secrets", "x": 1, "y": 1}).ok, "prop names are checked")
	ok(not run({"type": "placeProp", "m": "nature/rock", "x": 1, "y": 1}, {"name": "Alice", "is_dm": false}).ok, "only the DM places props")
	ok(Grid.cell_at(state.map, 3, 4) == Grid.FLOOR, "props don't change the rules")
	must({"type": "removeProps", "cells": [{"x": 3, "y": 4}]})
	eq(state.map.props.size(), 1, "erased the barrel")
	must({"type": "resizeMap", "width": 8, "height": 8})
	eq(state.map.props.size(), 0, "props off a shrunk map are dropped")
	must({"type": "placeProp", "m": "nature/rock", "x": 1, "y": 1})
	must({"type": "clearMap"})
	ok(not state.map.has("props"), "clearing the map clears props")
