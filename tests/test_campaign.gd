extends "res://tests/test_base.gd"
## The DM's notes and session planner.


func test_campaign_plan_is_dm_only() -> void:
	fresh()
	var plan := {"notes": "The lich is the baker.", "sessions": [{"name": "Session 1", "notes": "", "scenes": []}]}
	ok(not run({"type": "campaign", "campaign": plan}, {"name": "Ann", "is_dm": false}).ok, "players can't write the plan")
	ok(not run({"type": "campaign", "campaign": "junk"}).ok, "the plan must be a dictionary")
	must({"type": "campaign", "campaign": plan})
	eq(state.campaign.notes, "The lich is the baker.", "the DM's plan is kept in the game state")
	ok(not RulesEngine.redact_for(state, {"name": "Ann", "is_dm": false}).has("campaign"), "players never receive the plan")
	ok(RulesEngine.redact_for(state, DM).has("campaign"), "the DM does")


func test_scene_map_loads() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(12, 12))
	var saved: Dictionary = RulesEngine.new_state(8, 6).map
	saved.cells[3] = Grid.WALL
	ok(not run({"type": "setMap", "map": {"width": 8, "height": 6, "cells": []}}).ok, "a broken map is refused")
	must({"type": "setMap", "map": saved})
	eq([state.map.width, state.map.height, state.map.cells[3]], [8, 6, Grid.WALL], "the scene's map replaces the board")
	eq(c(f).pos, Vector2i(7, 5), "creatures off the new map are pulled onto it")
