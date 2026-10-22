extends "res://tests/test_base.gd"


func test_dice_parse_and_roll() -> void:
	ok(Dice.is_valid("2d6+3"), "2d6+3 parses")
	ok(Dice.is_valid("d20"), "d20 parses")
	ok(Dice.is_valid("4d6kh3"), "4d6kh3 parses")
	ok(not Dice.is_valid("2d6+"), "trailing + rejected")
	ok(not Dice.is_valid("hello"), "garbage rejected")
	var rng := RandomNumberGenerator.new()
	Dice.forced = [6, 1, 4, 3]
	eq(Dice.roll(rng, "4d6kh3").total, 13, "keep highest 3 of 6,1,4,3")
	Dice.forced = [2, 5]
	eq(Dice.roll(rng, "1d8+3", {"crit": true}).total, 10, "crit doubles dice, not modifier")
	Dice.forced = [1, 6]
	eq(Dice.roll(rng, "1d12", {"reroll_low": 2}).total, 6, "great weapon fighting rerolls a 1")
	Dice.forced = [4, 17]
	eq(Dice.d20(rng, Dice.ADVANTAGE).value, 17, "advantage takes higher")
	Dice.forced = [4, 17]
	eq(Dice.d20(rng, Dice.DISADVANTAGE).value, 4, "disadvantage takes lower")
	Dice.forced = [1, 12]
	eq(Dice.d20(rng, Dice.NORMAL, true).value, 12, "halfling lucky rerolls a natural 1")
	eq(Dice.combine(true, true), Dice.NORMAL, "advantage and disadvantage cancel")


func test_distance_rules() -> void:
	fresh()
	eq(Grid.grid_distance(3, 3, "5"), 15, "PHB: diagonals cost 5 ft")
	eq(Grid.grid_distance(3, 3, "5-10-5"), 20, "DMG: diagonals alternate 5/10")
	eq(Grid.grid_distance(4, 1, "5-10-5"), 20, "mixed move")
	eq(Grid.grid_distance_3d(3, 0, 4, "5"), 20, "PHB 3D: longest axis")
	eq(Grid.grid_distance_3d(2, 2, 2, "5-10-5"), 20, "DMG 3D: flat leg then height")
	eq(Grid.grid_distance_3d(0, 0, 3, "5"), 15, "straight up")
	var a := add("monster", "goblin", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(4, 2))
	eq(Grid.distance(state, c(a), c(o)), 10, "distance to nearest square of a large creature")
	c(o).pos = Vector2i(3, 2)
	eq(Grid.distance(state, c(a), c(o)), 5, "adjacent is 5 ft")


func test_line_of_sight_and_cover() -> void:
	fresh()
	var a := add("pregen", "ranger", Vector2i(1, 5))
	var t := add("monster", "goblin", Vector2i(8, 5))
	eq(Grid.cover(state, c(a), c(t)), 0, "open ground: no cover")
	# A wall column between them blocks sight completely.
	for y in range(0, 16):
		state.map.cells[y * 16 + 5] = Grid.WALL
	ok(not Grid.line_of_sight(state, c(a), c(t)), "wall blocks line of sight")
	eq(Grid.cover(state, c(a), c(t)), -1, "total cover")
	# A single wall square right in front of the target gives half cover (two of four lines blocked).
	fresh()
	a = add("pregen", "ranger", Vector2i(1, 5))
	t = add("monster", "goblin", Vector2i(8, 5))
	state.map.cells[5 * 16 + 7] = Grid.WALL
	eq(Grid.cover(state, c(a), c(t)), 2, "low wall in front: half cover")
	# Offset so the attacker can pick a corner that sees around it: no cover.
	state.map.cells[5 * 16 + 7] = Grid.FLOOR
	state.map.cells[4 * 16 + 7] = Grid.WALL
	c(t).pos = Vector2i(8, 6)
	eq(Grid.cover(state, c(a), c(t)), 0, "attacker uses the best corner")
	# Another creature in the way gives half cover.
	fresh()
	a = add("pregen", "ranger", Vector2i(1, 5))
	t = add("monster", "goblin", Vector2i(8, 5))
	add("monster", "goblin", Vector2i(5, 5))
	eq(Grid.cover(state, c(a), c(t)), 2, "intervening creature gives half cover")


func test_pathfinding_costs() -> void:
	fresh()
	var id := add("pregen", "fighter", Vector2i(0, 0))
	var reach := Grid.reachable(state, c(id), 30)
	ok(reach.cells.has(Vector2i(6, 6)), "30 ft reaches 6 diagonal squares")
	ok(not reach.cells.has(Vector2i(7, 0)), "but not 7")
	for x in range(1, 4):
		state.map.cells[x] = Grid.DIFFICULT
	reach = Grid.reachable(state, c(id), 30)
	eq(reach.cells.get(Vector2i(3, 0), -1), 20, "diagonal around difficult terrain is cheaper (5+5+10? no: 20)")
	state.settings.diagonal = "5-10-5"
	reach = Grid.reachable(state, c(id), 30)
	ok(not reach.cells.has(Vector2i(6, 6)), "with 5-10-5, 6 diagonals cost 45 ft")
	ok(reach.cells.has(Vector2i(4, 4)), "4 diagonals cost 30 ft")


func test_creatures_block_movement() -> void:
	fresh()
	var me := add("pregen", "fighter", Vector2i(0, 1))
	add("pregen", "cleric", Vector2i(1, 1))
	var reach := Grid.reachable(state, c(me), 30)
	ok(not reach.cells.has(Vector2i(1, 1)), "can't end in an ally's space")
	for y in range(16):
		if y != 1:
			state.map.cells[y * 16 + 1] = Grid.WALL
	reach = Grid.reachable(state, c(me), 30)
	ok(reach.cells.has(Vector2i(2, 1)), "can move through an ally")
	var ally := c(me)
	ally.side = "enemy"
	reach = Grid.reachable(state, ally, 30)
	ok(not reach.cells.has(Vector2i(2, 1)), "can't move through a hostile creature of similar size")


func test_area_shapes() -> void:
	fresh(30, 30)
	var w := add("pregen", "wizard", Vector2i(5, 15))
	var sphere := Grid.area_cells(state, c(w), {"shape": "sphere", "size": 20, "origin": "point"}, Vector2i(15, 15))
	eq(sphere.size(), 81, "20-ft radius sphere on the PHB grid is 9x9")
	var cone := Grid.area_cells(state, c(w), {"shape": "cone", "size": 15, "origin": "self"}, Vector2i(8, 15))
	ok(cone.size() >= 6 and cone.size() <= 9, "15-ft cone covers 6-9 squares (got %d)" % cone.size())
	ok(cone.has(Vector2i(6, 15)) and cone.has(Vector2i(8, 15)), "cone starts adjacent and reaches 15 ft")
	ok(not cone.has(Vector2i(9, 15)), "cone stops at 15 ft")
	var line := Grid.area_cells(state, c(w), {"shape": "line", "size": 30, "width": 5, "origin": "self"}, Vector2i(20, 15))
	eq(line.size(), 6, "30-ft line is 6 squares")
	var cube := Grid.area_cells(state, c(w), {"shape": "cube", "size": 15, "origin": "self"}, Vector2i(9, 15))
	eq(cube.size(), 9, "15-ft cube is 3x3")
	ok(cube.has(Vector2i(6, 15)) and not cube.has(Vector2i(5, 15)), "cube is adjacent to the caster, not on it")


func test_ping_is_an_event_anyone_can_send() -> void:
	fresh()
	var r := run({"type": "ping", "pos": Vector2i(3, 4)}, {"name": "Bob", "is_dm": false})
	ok(r.ok, "players can ping")
	eq(r.events, [{"kind": "ping", "pos": Vector2i(3, 4), "who": "Bob"}], "everyone gets a ping event")
	eq(state.log.size(), 0, "pings don't clutter the log")
	ok(not run({"type": "ping", "pos": Vector2i(99, 4)}).ok, "must be on the map")
