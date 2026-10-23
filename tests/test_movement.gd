extends "res://tests/test_base.gd"
## Flying (altitude), falling, swimming through water, and long jumps.


func test_flying_altitude_and_reach() -> void:
	fresh()
	var w := add("monster", "red_dragon_wyrmling", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(3, 2), 5)
	start([w, f])
	must({"type": "altitude", "actor_id": w, "alt": 20})
	eq(c(w).alt, 20, "aloft at 20 ft")
	eq(c(w).turn.movement_used, 20, "climbing cost 20 ft of its 60 ft fly speed")
	eq(engine().movement_left(c(w)), 40, "flying speed left")
	eq(engine().dist(c(w), c(f)), 20, "20 ft above the fighter")
	must({"type": "move", "actor_id": w, "to": Vector2i(3, 2)})
	eq(c(w).pos, Vector2i(3, 2), "flies over the fighter's square")
	must({"type": "endTurn", "actor_id": w})
	var err: String = run({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": w}).get("error", "")
	ok(err != "", "out of longsword reach: %s" % err)
	ok(not run({"type": "altitude", "actor_id": f, "alt": 10}).ok, "the fighter can't fly")


func test_falling_and_slow_fall() -> void:
	fresh()
	var w := add("monster", "red_dragon_wyrmling", Vector2i(2, 2))
	var m := add("pregen", "monk", Vector2i(6, 6), 5)
	start([w, m])
	must({"type": "altitude", "actor_id": w, "alt": 30})
	var hp: int = c(w).hp
	Dice.forced = [4, 4, 4]
	engine().knock_prone(c(w))
	eq(c(w).alt, 0, "knocked prone in the air: it falls")
	eq(c(w).hp, hp - 12, "3d6 for 30 ft")
	ok(engine().has_cond(c(w), "prone"), "lands prone")
	c(m).alt = 40
	hp = c(m).hp
	Dice.forced = [6, 6, 6, 6]
	engine().fall(c(m), 40)
	eq(c(m).hp, hp, "Slow Fall (25 at monk 5) soaks all 24")
	ok(not engine().has_cond(c(m), "prone"), "no damage, not prone")


func test_fly_spell_ends_and_target_falls() -> void:
	fresh()
	var wz := add("pregen", "wizard", Vector2i(2, 2), 5)
	var f := add("pregen", "fighter", Vector2i(3, 2), 5)
	var g := add("monster", "goblin", Vector2i(12, 12))
	start([wz, f, g])
	c(wz).spellcasting.known.append("fly")
	must({"type": "cast", "actor_id": wz, "spell_id": "fly", "slot": 3, "targets": [f]})
	must({"type": "endTurn", "actor_id": wz})
	must({"type": "altitude", "actor_id": f, "alt": 30})
	eq(engine().speed_of(c(f)), 60, "flies at 60 ft")
	var hp: int = c(f).hp
	Dice.forced = [1, 1, 1]
	engine().end_concentration(c(wz), " (test)")
	eq(c(f).alt, 0, "falls when Fly ends")
	eq(c(f).hp, hp - 3, "3d6 falling damage")


func test_water_costs_double_without_swim_speed() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var cr := add("monster", "crocodile", Vector2i(2, 6))
	for x in range(3, 8):
		for y in [1, 2, 3, 6]:
			state.map.cells[y * state.map.width + x] = Grid.WATER
	start([f, cr])
	must({"type": "move", "actor_id": f, "to": Vector2i(4, 2)})
	eq(c(f).turn.movement_used, 20, "two squares of water cost 20 ft")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "move", "actor_id": cr, "to": Vector2i(4, 6)})
	eq(c(cr).turn.movement_used, 10, "the crocodile swims at normal cost")


func test_long_jump() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var g := add("monster", "goblin", Vector2i(15, 15))
	start([f, g])
	var str_score: int = c(f).abilities.str
	ok(not run({"type": "jump", "actor_id": f, "to": Vector2i(2 + str_score / 5, 2)}).ok, "a standing jump only goes half as far")
	must({"type": "move", "actor_id": f, "to": Vector2i(4, 2)})
	for x in range(5, 7):
		state.map.cells[2 * state.map.width + x] = Grid.WATER
	must({"type": "jump", "actor_id": f, "to": Vector2i(7, 2)})
	eq(c(f).pos, Vector2i(7, 2), "jumped over the water")
	eq(c(f).turn.movement_used, 25, "10 ft run-up + 15 ft jump")
	state.map.cells[2 * state.map.width + 8] = Grid.WALL
	ok(not run({"type": "jump", "actor_id": f, "to": Vector2i(9, 2)}).ok, "walls block a jump")


func test_climbing_costs_double_without_climb_speed() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var sp := add("monster", "giant_spider", Vector2i(2, 6))
	for x in range(3, 8):
		for y in [1, 2, 3, 6, 7, 8]:
			state.map.cells[y * state.map.width + x] = Grid.CLIMB
	start([f, sp])
	must({"type": "move", "actor_id": f, "to": Vector2i(4, 2)})
	eq(c(f).turn.movement_used, 20, "two squares of cliff cost 20 ft")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "move", "actor_id": sp, "to": Vector2i(4, 6)})
	eq(c(sp).turn.movement_used, 10, "the spider climbs at normal cost")


func test_high_jump() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var g := add("monster", "goblin", Vector2i(15, 15))
	start([f, g])
	c(f).abilities.str = 16  # 3 + 3 = 6 ft running, 3 ft standing
	ok(not run({"type": "jump", "actor_id": f, "high": true}).ok, "3 ft from standing is too little for the grid")
	must({"type": "move", "actor_id": f, "to": Vector2i(4, 2)})
	must({"type": "jump", "actor_id": f, "high": true})
	eq([c(f).alt, c(f).turn.movement_used], [5, 16], "5 ft up for 6 ft of movement")
	must({"type": "move", "actor_id": f, "to": Vector2i(5, 2)})
	eq(c(f).alt, 0, "lands before walking on")
	must({"type": "jump", "actor_id": f, "high": true})
	must({"type": "endTurn", "actor_id": f})
	eq(c(f).alt, 0, "and at the end of the turn")


func test_long_jump_checks() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var g := add("monster", "goblin", Vector2i(15, 15))
	start([f, g])
	must({"type": "move", "actor_id": f, "to": Vector2i(4, 2)})
	state.map.cells[2 * state.map.width + 6] = Grid.LOW_WALL
	Dice.forced = [1]
	must({"type": "jump", "actor_id": f, "to": Vector2i(7, 2)})
	eq(c(f).pos, Vector2i(5, 2), "failed Athletics: stops in front of the low wall")
	state.map.cells[2 * state.map.width + 3] = Grid.DIFFICULT
	Dice.forced = [1]
	must({"type": "jump", "actor_id": f, "to": Vector2i(3, 2)})
	ok(engine().has_cond(c(f), "prone"), "failed Acrobatics landing on rough ground: prone")


func test_suffocation() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 5)
	var cr := add("monster", "crocodile", Vector2i(8, 2))
	var g := add("monster", "goblin", Vector2i(15, 15))
	for y in range(0, 6):
		for x in range(0, 12):
			state.map.cells[y * state.map.width + x] = Grid.WATER
	c(f).abilities.con = 10  # 1 minute of breath (10 rounds), then 1 round of choking
	start([f, cr, g])
	for i in 10:
		must({"type": "endTurn", "actor_id": f})
		must({"type": "endTurn", "actor_id": cr})
		must({"type": "endTurn", "actor_id": g})
	ok(log_has("out of breath"), "out of breath after a minute")
	eq(c(f).hp > 0, true, "still conscious while choking")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "endTurn", "actor_id": cr})
	must({"type": "endTurn", "actor_id": g})
	eq(c(f).hp, 0, "then drops to 0 hit points")
	ok(c(cr).hp == c(cr).max_hp and not log_has("Crocodile is out of breath"), "the crocodile holds its breath 15 minutes")
	eq(engine().heal(c(f), 5), 0, "no healing while suffocating")
	c(f).pos = Vector2i(14, 14)
	engine().breathe(c(f))
	eq(engine().heal(c(f), 5), 5, "can be healed once it breathes again")
