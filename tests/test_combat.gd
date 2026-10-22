extends "res://tests/test_base.gd"


func test_initiative_and_turn_order() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 8))
	start([g, f])
	eq(current(), g, "highest initiative acts first")
	eq(state.combat.round, 1, "round 1")
	must({"type": "endTurn", "actor_id": g})
	eq(current(), f, "turn passes on")
	must({"type": "endTurn", "actor_id": f})
	eq(state.combat.round, 2, "new round after everyone acts")
	eq(current(), g, "back to the top")


func test_weapon_attack_hit_and_kill() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [15, 5]  # 15+7 = 22 vs AC 15; longsword 5+4 str +2 dueling = 11
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g})
	ok(c(g).dead, "goblin dies at 0 HP")
	eq(c(f).turn.actions, 0, "Attack action used")
	eq(c(f).turn.attacks_left, 1, "Extra Attack leaves one more attack")


func test_natural_one_misses_and_crits() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, o])
	Dice.forced = [1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	eq(c(o).hp, 59, "natural 1 always misses")
	Dice.forced = [19, 3, 4]  # Champion crits on 19: 2d8 (3+4) + 6
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	eq(c(o).hp, 59 - 13, "improved critical doubles the dice")
	var r := run({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	ok(not r.ok, "no third attack without Action Surge")
	must({"type": "feature", "actor_id": f, "feature": "actionSurge"})
	Dice.forced = [10, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	eq(c(o).hp, 46 - 7, "Action Surge grants another Attack action")


func test_advantage_against_prone_and_ranged_disadvantage() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, o])
	must({"type": "toggleCondition", "id": o, "condition": "prone"})
	Dice.forced = [2, 15, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	ok(c(o).hp < 59, "advantage vs prone target in melee uses the higher die")
	ok(log_has("adv: target prone"), "log explains advantage")
	# Thrown at a prone target within 5 ft (advantage) with an enemy adjacent (disadvantage): they cancel.
	Dice.forced = [18, 3]
	must({"type": "attack", "actor_id": f, "attack_id": "javelin_thrown", "target_id": o})
	ok(log_has("adv & dis cancel"), "advantage and disadvantage cancel")


func test_death_saves_and_massive_damage() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 8))
	start([f, g])
	must({"type": "setHp", "id": f, "hp": 3})
	must({"type": "adjustHp", "id": f, "amount": -5})
	ok(not c(f).dead, "PC at 0 HP is dying, not dead")
	ok(engine().has_cond(c(f), "unconscious"), "unconscious at 0 HP")
	ok(engine().has_cond(c(f), "prone"), "falls prone")
	must({"type": "endTurn", "actor_id": f})
	Dice.forced = [5]
	must({"type": "endTurn", "actor_id": g})  # fighter's turn: death save, then auto-skip
	eq(c(f).death_saves.failures, 1, "rolled a 5: one failure")
	eq(current(), g, "an unconscious creature's turn is skipped")
	must({"type": "adjustHp", "id": f, "amount": -1})
	eq(c(f).death_saves.failures, 2, "damage at 0 HP adds a failure")
	must({"type": "adjustHp", "id": f, "amount": 4})
	eq(c(f).hp, 4, "healing brings you back")
	eq(c(f).death_saves.failures, 0, "and resets death saves")
	must({"type": "setHp", "id": f, "hp": 10})
	must({"type": "adjustHp", "id": f, "amount": -60})
	ok(c(f).dead, "damage beyond 0 that's >= max HP kills outright")


func test_natural_20_death_save() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 8))
	start([g, f])
	must({"type": "setHp", "id": f, "hp": 0})
	ok(engine().is_dying(c(f)), "dying")
	Dice.forced = [20]
	must({"type": "endTurn", "actor_id": g})
	eq(c(f).hp, 1, "natural 20 on a death save: regain 1 HP")
	eq(current(), f, "and you can act")


func test_opportunity_attacks_and_disengage() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([g, f])
	Dice.forced = [15, 5]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(c(f).reaction_used, "fighter used its reaction")
	ok(c(g).dead, "the opportunity attack killed the goblin before it got away")
	eq(c(g).pos, Vector2i(3, 2), "it never left")
	fresh()
	f = add("pregen", "fighter", Vector2i(2, 2))
	g = add("monster", "goblin", Vector2i(3, 2))
	start([g, f])
	must({"type": "action", "actor_id": g, "action": "disengage", "via": "bonus"})
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(not c(f).reaction_used, "Disengage (Nimble Escape) prevents opportunity attacks")
	eq(c(g).pos, Vector2i(7, 2), "goblin escaped")
	ok(c(g).turn.actions == 1, "Nimble Escape used the bonus action, not the action")


func test_movement_budget_dash_and_difficult_terrain() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(0, 0))
	start([cl])
	var r := run({"type": "move", "actor_id": cl, "to": Vector2i(6, 0)})
	ok(not r.ok and "Not enough movement" in r.error, "speed 25 can't go 30 ft: " + r.error)
	must({"type": "move", "actor_id": cl, "to": Vector2i(5, 0)})
	eq(c(cl).turn.movement_used, 25, "25 ft used")
	must({"type": "action", "actor_id": cl, "action": "dash"})
	must({"type": "move", "actor_id": cl, "to": Vector2i(10, 0)})
	eq(c(cl).turn.movement_used, 50, "Dash doubles movement")
	fresh()
	cl = add("pregen", "cleric", Vector2i(0, 0))
	for x in range(1, 16):
		state.map.cells[x] = Grid.DIFFICULT
		state.map.cells[16 + x] = Grid.WALL
	state.map.cells[16] = Grid.WALL
	start([cl])
	r = run({"type": "move", "actor_id": cl, "to": Vector2i(3, 0)})
	ok(not r.ok, "difficult terrain costs double (3 squares = 30 ft > 25)")


func test_prone_stand_up_costs_half_speed() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(0, 0))
	start([f])
	must({"type": "toggleCondition", "id": f, "condition": "prone"})
	must({"type": "move", "actor_id": f, "to": Vector2i(3, 0)})
	ok(not engine().has_cond(c(f), "prone"), "moving stands you up")
	eq(c(f).turn.movement_used, 30, "15 ft to stand + 15 ft moved")


func test_grapple_and_escape() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [15, 2]
	must({"type": "grapple", "actor_id": f, "target_id": g})
	ok(engine().has_cond(c(g), "grappled"), "grappled")
	eq(engine().speed_of(c(g)), 0, "grappled creatures have speed 0")
	eq(c(f).turn.attacks_left, 1, "grapple replaced one attack")
	must({"type": "endTurn", "actor_id": f})
	Dice.forced = [20, 1]
	must({"type": "action", "actor_id": g, "action": "escape"})
	ok(not engine().has_cond(c(g), "grappled"), "escaped the grapple")


func test_sneak_attack_with_adjacent_ally() -> void:
	fresh()
	var r := add("pregen", "rogue", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	add("pregen", "fighter", Vector2i(3, 4))
	start([r, o])
	Dice.forced = [15, 4, 3, 3, 3]  # rapier 4 + 4 dex, sneak attack 3d6 = 9
	must({"type": "attack", "actor_id": r, "attack_id": "rapier", "target_id": o})
	eq(c(o).hp, 59 - 17, "sneak attack adds 3d6 at level 5")
	ok(log_has("sneak attack"), "logged")


func test_two_weapon_fighting_offhand_has_no_modifier() -> void:
	fresh()
	var r := add("pregen", "rogue", Vector2i(2, 2), 1)
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([r, o])
	var bad := run({"type": "attack", "actor_id": r, "attack_id": "dagger", "target_id": o, "options": {"bonus": true}})
	ok(not bad.ok, "offhand attack needs an Attack action first")
	Dice.forced = [2]  # (a natural 1 would be rerolled by halfling Lucky)
	must({"type": "attack", "actor_id": r, "attack_id": "dagger", "target_id": o})
	Dice.forced = [15, 3]
	must({"type": "attack", "actor_id": r, "attack_id": "dagger", "target_id": o, "options": {"bonus": true}})
	eq(c(o).hp, 59 - 3, "offhand dagger deals just the die (no sneak attack without advantage/ally)")


func test_rage_resistance_and_damage() -> void:
	fresh()
	var b := add("pregen", "barbarian", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([b, o])
	must({"type": "feature", "actor_id": b, "feature": "rage"})
	Dice.forced = [15, 6]  # greataxe 6 + 4 str + 2 rage
	must({"type": "attack", "actor_id": b, "attack_id": "greataxe", "target_id": o})
	eq(c(o).hp, 59 - 12, "rage adds +2 melee damage")
	var hp: int = c(b).hp
	engine().deal_damage(c(b), [{"amount": 10, "type": "bludgeoning"}])
	eq(c(b).hp, hp - 5, "raging barbarian resists bludgeoning")


func test_multiattack() -> void:
	fresh()
	var ob := add("monster", "owlbear", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(4, 2))
	start([ob, f])
	Dice.forced = [1]
	must({"type": "attack", "actor_id": ob, "attack_id": "beak", "target_id": f})
	eq(c(ob).turn.multiattack_left, ["claws"], "claws remain")
	Dice.forced = [1]
	must({"type": "attack", "actor_id": ob, "attack_id": "claws", "target_id": f})
	ok(not run({"type": "attack", "actor_id": ob, "attack_id": "claws", "target_id": f}).ok, "multiattack is spent")


func test_unconscious_target_auto_crit_in_melee() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var b := add("monster", "bandit", Vector2i(3, 2))
	start([f, b])
	must({"type": "toggleCondition", "id": b, "condition": "paralyzed"})
	Dice.forced = [10, 10, 1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": b})
	eq(c(b).hp, 11 - 8, "hit on a paralyzed creature within 5 ft is a critical hit (1+1+6)")


func test_uncanny_dodge_halves_damage() -> void:
	fresh()
	var r := add("pregen", "rogue", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([o, r])
	var hp: int = c(r).hp
	Dice.forced = [15, 4, 4]  # greatclub 2d8+4 = 12 -> 6
	must({"type": "attack", "actor_id": o, "attack_id": "greatclub", "target_id": r})
	eq(c(r).hp, hp - 6, "Uncanny Dodge halves the hit")
	ok(c(r).reaction_used, "uses the reaction")


func test_permissions() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 8))
	c(f).controller = "Bob"
	var bob := {"name": "Bob", "is_dm": false}
	ok(not run({"type": "move", "actor_id": g, "to": Vector2i(8, 9)}, bob).ok, "players can't move monsters")
	ok(run({"type": "move", "actor_id": f, "to": Vector2i(2, 3)}, bob).ok, "players move their own character outside combat")
	ok(not run({"type": "startCombat"}, bob).ok, "only the DM starts combat")
	start([g, f])
	ok(not run({"type": "move", "actor_id": f, "to": Vector2i(2, 4)}, bob).ok, "not your turn")
	var view := RulesEngine.redact_for(state, bob)
	ok(view.combatants[g].redacted and view.combatants[g].max_hp == 1, "monster HP hidden from players")
	eq(view.combatants[f].max_hp, c(f).max_hp, "your own HP visible")


func test_monster_ai_takes_a_turn() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([g, f])
	must({"type": "autoTurn"})
	eq(Grid.distance(state, c(g), c(f)), 5, "goblin closed to melee")
	ok(log_has("Goblin → Brakka"), "and attacked")
	eq(current(), f, "then ended its turn")


func test_auto_npc_setting_runs_monster_turns() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([f, g])
	must({"type": "settings", "settings": {"auto_npc": true}})
	must({"type": "endTurn", "actor_id": f})
	eq(current(), f, "monster turn played automatically")
	eq(state.combat.round, 2, "round advanced")


func test_ghoul_paralysis_repeats_save() -> void:
	fresh()
	var gh := add("monster", "ghoul", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(3, 2))
	start([gh, f])
	Dice.forced = [1]
	must({"type": "attack", "actor_id": gh, "attack_id": "bite", "target_id": f})
	Dice.forced = [15, 1, 1, 2]  # claws hit 2+2+2=... then Con save 2 fails
	must({"type": "attack", "actor_id": gh, "attack_id": "claws", "target_id": f})
	ok(engine().has_cond(c(f), "paralyzed"), "ghoul claws paralyze")
	must({"type": "endTurn", "actor_id": gh})
	eq(current(), gh, "paralyzed fighter's turn is skipped")
	Dice.forced = [20]
	must({"type": "endTurn", "actor_id": gh})
	ok(not engine().has_cond(c(f), "paralyzed"), "repeat save at end of its turn ends paralysis")


func test_short_and_long_rest() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	c(f).resources.second_wind.used = 1
	c(f).resources.action_surge.used = 1
	c(f).hp = 10
	must({"type": "rest", "kind": "short"})
	eq(c(f).resources.second_wind.used, 0, "short rest restores Second Wind")
	ok(c(f).hp > 10, "spent hit dice")
	c(f).hp = 1
	must({"type": "rest", "kind": "long"})
	eq(c(f).hp, c(f).max_hp, "long rest restores HP")


func test_sheet_notes_permissions() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 8))
	c(f).controller = "Bob"
	var bob := {"name": "Bob", "is_dm": false}
	ok(run({"type": "setNotes", "id": f, "key": "backstory", "value": "Raised by wolves."}, bob).ok, "players edit their own sheet")
	eq(c(f).notes.backstory, "Raised by wolves.", "saved")
	ok(not run({"type": "setNotes", "id": g, "key": "backstory", "value": "x"}, bob).ok, "but not other creatures'")
	ok(not run({"type": "setNotes", "id": f, "key": "hp", "value": "999"}, bob).ok, "only sheet text fields can be set")
	ok(run({"type": "rename", "id": f, "name": "Brakka the Bold"}, bob).ok, "players can rename their character")
	eq(c(f).name, "Brakka the Bold", "renamed")
	c(g).notes = {"secret": "boss"}
	ok(RulesEngine.redact_for(state, bob).combatants[g].notes.is_empty(), "monster notes hidden from players")
	ok(c(f).equipment.has("Chain Mail armor") and c(f).equipment.has("Shield"), "equipment listed from the build")


func test_ready_an_attack() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(8, 2))
	var far := add("monster", "goblin", Vector2i(15, 15))
	start([f, g, far])
	must({"type": "ready", "actor_id": f, "attack_id": "longsword"})
	eq(c(f).turn.actions, 0, "readying takes the action")
	ok(not run({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g}).ok, "no attack left this turn")
	must({"type": "endTurn", "actor_id": f})
	Dice.forced = [15, 5]
	must({"type": "move", "actor_id": g, "to": Vector2i(3, 2)})
	ok(c(g).dead, "the readied longsword cut the goblin down as it closed in")
	ok(c(f).reaction_used and not c(f).has("readied"), "used the reaction")
	ok(log_has("readied attack goes off"), "logged")
	while current() != f:
		must({"type": "dmEndTurn"})
	must({"type": "ready", "actor_id": f, "attack_id": "longsword"})
	must({"type": "endTurn", "actor_id": f})
	ok(c(f).has("readied"), "still readied during others' turns")
	while current() != f:
		must({"type": "dmEndTurn"})
	ok(not c(f).has("readied"), "lapses at the start of your next turn")


func test_creature_killed_on_its_turn_can_end_it() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([g, f])
	Dice.forced = [15, 5]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	ok(c(g).dead, "opportunity attack killed the goblin")
	must({"type": "endTurn", "actor_id": g})
	eq(current(), f, "turn passes on from the dead goblin")


func test_initiative_has_disadvantage_when_poisoned() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	must({"type": "toggleCondition", "id": f, "condition": "poisoned"})
	Dice.forced = [15, 3]
	must({"type": "startCombat"})
	Dice.forced.clear()
	eq(c(f).initiative, 3 + engine().mod(c(f), "dex") + c(f).init_bonus, "poisoned takes the lower d20")


func test_ally_square_is_difficult_terrain() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(0, 0), 5, "party")
	add("pregen", "fighter", Vector2i(1, 0), 5, "party")
	for x in 16:
		state.map.cells[16 + x] = Grid.WALL
	start([cl])
	must({"type": "move", "actor_id": cl, "to": Vector2i(2, 0)})
	eq(c(cl).turn.movement_used, 15, "passing through an ally's square costs double")


func test_crawling_while_dragging_costs_triple() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [15, 2]
	must({"type": "grapple", "actor_id": f, "target_id": g})
	must({"type": "toggleCondition", "id": f, "condition": "prone"})
	eq(engine().move_rules(c(f)).cost_multiplier, 3, "crawl + drag is 1 + 1 + 1")


func test_every_mini_has_a_stat_block() -> void:
	for id in preload("res://scripts/ui/token.gd").mini_ids():
		ok(Classes.ALL.has(id) or Monsters.ALL.has(id), "%s mini has a class or monster" % id)


func test_built_in_monsters_are_complete() -> void:
	for id in Monsters.ALL:
		var m: Dictionary = Monsters.ALL[id]
		var ids: Array = m.attacks.map(func(a): return a.id)
		for a in m.get("multiattack", []):
			ok(ids.has(a), "%s multiattack uses its own %s" % [id, a])
		for s in m.get("spellcasting", {}).get("spells", []):
			ok(Spells.ALL.has(s), "%s knows real spell %s" % [id, s])
		var cc := Builder.build_monster(id, "t")
		eq(cc.max_hp, m.hp, "%s builds" % id)
		eq(cc.spellcasting.is_empty(), not m.has("spellcasting"), "%s spellcasting carried over" % id)


func test_npc_casters_and_poison() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2))
	var n := add("monster", "necromancer", Vector2i(6, 2))
	var a := add("monster", "assassin", Vector2i(3, 2))
	start([n, a, f])
	must({"type": "cast", "actor_id": n, "spell_id": "magic_missile", "targets": [f]})
	eq(c(n).spellcasting.slots_used[1], 1, "necromancer spends a 1st-level slot")
	must({"type": "endTurn", "actor_id": n})
	var hp: int = c(f).hp
	Dice.forced = [19, 4, 1, 1, 1, 1, 1, 1, 1, 1]  # hit, 4+3 piercing, fighter fails the DC 15 save, 7d6 poison
	must({"type": "attack", "actor_id": a, "attack_id": "shortsword", "target_id": f})
	ok(c(f).hp <= hp - 7 - 7, "assassin's poison lands on top of the blade")
