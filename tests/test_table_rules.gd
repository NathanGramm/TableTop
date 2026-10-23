extends "res://tests/test_base.gd"
## Rituals, DM Inspiration, underwater combat and mounted combat (PHB chapters 9-10).

const BOB := {"name": "Bob", "is_dm": false}


func test_ritual_casting() -> void:
	fresh()
	var w := add("pregen", "wizard", Vector2i(2, 2), 3)
	var f := add("pregen", "fighter", Vector2i(3, 2), 3)
	var g := add("monster", "goblin", Vector2i(12, 12))
	c(w).spellcasting.known.append("detect_magic")
	var slots: int = engine().slots_left(c(w), 1)
	must({"type": "cast", "actor_id": w, "spell_id": "detect_magic", "options": {"ritual": true}})
	eq(engine().slots_left(c(w), 1), slots, "a ritual uses no slot")
	ok(log_has("Detect Magic as a ritual"), "logged as a ritual")
	ok(not run({"type": "cast", "actor_id": w, "spell_id": "magic_missile", "targets": [g], "options": {"ritual": true}}).ok, "Magic Missile isn't a ritual")
	c(f).spellcasting = c(w).spellcasting.duplicate(true)
	ok(not run({"type": "cast", "actor_id": f, "spell_id": "detect_magic", "options": {"ritual": true}}).ok, "fighters have no Ritual Casting")
	c(w).fdata.class_levels = {"wizard": 3, "fighter": 1}
	c(w).spellcasting.known.append("alarm")
	must({"type": "cast", "actor_id": w, "spell_id": "alarm", "options": {"ritual": true}})
	c(w).fdata.class_levels = {"sorcerer": 3, "cleric": 1}
	c(w).class_id = "sorcerer"
	ok(not run({"type": "cast", "actor_id": w, "spell_id": "alarm", "options": {"ritual": true}}).ok, "a sorcerer/cleric can't ritual-cast a wizard spell")
	must({"type": "cast", "actor_id": w, "spell_id": "detect_magic", "options": {"ritual": true}})
	start([w, f, g])
	ok(not run({"type": "cast", "actor_id": w, "spell_id": "detect_magic", "options": {"ritual": true}}).ok, "too slow for combat")


func test_inspiration() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 3)
	var w := add("pregen", "wizard", Vector2i(3, 2), 3)
	var g := add("monster", "goblin", Vector2i(2, 3))
	c(f).controller = "Bob"
	ok(not run({"type": "setNotes", "id": f, "key": "inspiration", "value": "1"}, BOB).ok, "players can't award it")
	must({"type": "setNotes", "id": f, "key": "inspiration", "value": "1"})
	must({"type": "inspiration", "actor_id": f}, BOB)
	eq(c(f).notes.inspiration, "", "spent")
	Dice.forced = [2, 18]
	eq(engine().roll_save(c(f), "wis", 10).natural, 18, "advantage on the next save")
	Dice.forced = [2, 18]
	eq(engine().roll_save(c(f), "wis", 10).natural, 2, "only once")
	must({"type": "setNotes", "id": f, "key": "inspiration", "value": "1"})
	ok(not run({"type": "inspiration", "actor_id": f, "target_id": g}, BOB).ok, "only to player characters")
	must({"type": "inspiration", "actor_id": f, "target_id": w}, BOB)
	eq([c(f).notes.inspiration, c(w).notes.inspiration], ["", "1"], "passed to the wizard")
	start([w, f, g])
	must({"type": "inspiration", "actor_id": w})
	ok(engine().attack_mode(c(w), c(g), "ranged").adv.has("inspiration"), "shown on the attack")
	Dice.forced = [3, 3, 17]
	engine().attack_roll(c(w), c(g), "ranged", 5)
	ok(not engine().has_tag(c(w), "inspired"), "used up by the attack roll")


func test_underwater_combat() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 3)
	var g := add("monster", "goblin", Vector2i(3, 2))
	var cr := add("monster", "crocodile", Vector2i(2, 5))
	for y in range(0, 10):
		for x in range(0, 10):
			state.map.cells[y * state.map.width + x] = Grid.WATER
	var e := engine()
	ok(e.in_water(c(f)), "standing in water")
	ok(e.attack_mode(c(f), c(g), "melee", {"profile": {"weapon_id": "longsword"}}).dis.has("underwater"), "longsword: disadvantage")
	ok(not e.attack_mode(c(f), c(g), "melee", {"profile": {"weapon_id": "shortsword"}}).dis.has("underwater"), "shortsword is fine")
	ok(not e.attack_mode(c(cr), c(g), "melee", {"profile": {"weapon_id": ""}}).dis.has("underwater"), "swimmers fight normally")
	ok(e.attack_mode(c(f), c(g), "ranged", {"profile": {"weapon_id": "longbow"}}).dis.has("underwater"), "longbow: disadvantage")
	ok(not e.attack_mode(c(f), c(g), "ranged", {"profile": {"weapon_id": "light_crossbow"}}).dis.has("underwater"), "crossbows work")
	c(g).pos = Vector2i(9, 2)
	var xbow := {"name": "Light crossbow", "range": "ranged", "normal": 20, "long": 80, "props": [], "weapon_id": "light_crossbow"}
	ok(e.validate_attack(c(f), c(g), xbow) == "", "a long-range shot is still allowed")
	ok(not e.weapon_attack(c(f), c(g), xbow).hit and log_has("automatically misses"), "but misses past normal range")
	var hp: int = c(g).hp
	e.deal_damage(c(g), [{"amount": 6, "type": "fire"}])
	eq(c(g).hp, hp - 3, "fire resistance when immersed")


func _rider_and_horse() -> Array:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 3)
	var h := add("monster", "warhorse", Vector2i(3, 2), 1, c(f).side)
	var g := add("monster", "goblin", Vector2i(14, 14))
	start([f, g, h])
	return [f, h, g]


func test_mount_and_ride() -> void:
	var ids := _rider_and_horse()
	var f: String = ids[0]
	var h: String = ids[1]
	var g: String = ids[2]
	must({"type": "mount", "actor_id": f, "target_id": h})
	eq(c(f).mounted_on, h, "mounted")
	eq(c(f).turn.movement_used, 15, "half the rider's speed")
	ok(c(h).controlled and not state.combat.order.has(h), "a trained horse joins the rider's turn")
	must({"type": "move", "actor_id": f, "to": Vector2i(9, 2)})
	eq([c(h).pos, c(f).pos], [Vector2i(9, 2), Vector2i(9, 2)], "the horse carries its rider")
	eq(c(h).turn.movement_used, 30, "the horse's own 60 ft")
	eq(c(f).turn.movement_used, 15, "not the rider's")
	must({"type": "action", "actor_id": h, "action": "dash"})
	ok(not run({"type": "attack", "actor_id": h, "attack_id": "hooves", "target_id": g}).ok, "a controlled mount can't attack")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "endTurn", "actor_id": g})
	eq(current(), f, "back to the rider")
	eq(c(h).turn.movement_used, 0, "the horse is fresh on the rider's turn")
	must({"type": "dismount", "actor_id": f})
	ok(c(f).mounted_on == "" and c(h).rider == "" and engine().dist(c(f), c(h)) <= 5, "steps off next to it")
	eq(state.combat.order.find(h), state.combat.order.find(f) + 1, "the horse acts right after its rider again")


func test_falling_from_the_saddle() -> void:
	var ids := _rider_and_horse()
	var f: String = ids[0]
	var h: String = ids[1]
	must({"type": "mount", "actor_id": f, "target_id": h})
	Dice.forced = [1]
	engine().knock_prone(c(f))
	ok(c(f).mounted_on == "" and engine().has_cond(c(f), "prone"), "failed the DC 10 Dex save: thrown off, prone")
	ok(state.combat.order.has(h), "the horse acts on its own again")
	engine().remove_effects_where(func(e): return e.target_id == f)
	c(f).turn.movement_used = 0
	must({"type": "mount", "actor_id": f, "target_id": h})
	c(f).reaction_mode = "auto"
	engine().kill(c(h), "test")
	ok(c(f).mounted_on == "" and not engine().has_cond(c(f), "prone") and c(f).reaction_used, "reaction: lands on its feet")


func test_independent_mount_and_mounted_combatant() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 3)
	var b := add("monster", "brown_bear", Vector2i(3, 2), 1, c(f).side)
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([f, b, g])
	must({"type": "mount", "actor_id": f, "target_id": b})
	ok(not c(b).get("controlled", false) and state.combat.order.has(b), "an untrained mount keeps its own turn")
	ok(not run({"type": "move", "actor_id": f, "to": Vector2i(5, 2)}).ok, "and goes where it likes")
	c(f).features.append("mountedCombatant")
	ok(engine().attack_mode(c(f), c(g), "melee").adv.has("mounted combatant"), "advantage on smaller foes on foot")
	must({"type": "endTurn", "actor_id": f})
	must({"type": "move", "actor_id": b, "to": Vector2i(4, 2)})
	eq(c(f).pos, c(b).pos, "the rider goes along")


func test_rider_shares_the_mount_space() -> void:
	var ids := _rider_and_horse()
	var f: String = ids[0]
	var h: String = ids[1]
	var g: String = ids[2]
	must({"type": "mount", "actor_id": f, "target_id": h})
	c(g).pos = Vector2i(5, 3)
	eq(engine().dist(c(f), c(g)), 5, "reach counts from the far side of the horse")
	engine().push_creature(c(f), c(g), 5)
	ok(c(f).mounted_on == "" and not Grid.footprint(c(h)).has(c(f).pos), "shoved out of the saddle, beside the horse")
	ok(not engine().has_cond(c(f), "prone"), "lands on its feet")


func test_opportunity_attack_on_the_rider() -> void:
	var ids := _rider_and_horse()
	var f: String = ids[0]
	var h: String = ids[1]
	var g: String = ids[2]
	must({"type": "mount", "actor_id": f, "target_id": h})
	c(g).pos = Vector2i(5, 2)
	c(g).reaction_mode = "auto"
	c(h).hp = 50  # the goblin goes for the weaker one
	must({"type": "move", "actor_id": f, "to": Vector2i(3, 8)})
	ok(log_has("opportunity attack against %s" % c(f).name), "the goblin strikes the rider, not the horse")


func test_trampling_charge() -> void:
	fresh()
	var h := add("monster", "warhorse", Vector2i(2, 2))
	var f := add("pregen", "fighter", Vector2i(9, 2), 3)
	start([h, f])
	must({"type": "move", "actor_id": h, "to": Vector2i(7, 2)})
	eq(engine().charged_ft(c(h), c(f)), 25, "25 ft straight at the fighter")
	Dice.forced = [19, 1, 1, 1]
	must({"type": "attack", "actor_id": h, "attack_id": "hooves", "target_id": f})
	ok(log_has("Trampling Charge") and engine().has_cond(c(f), "prone"), "DC 14 Str save failed: prone")
	ok(log_has("follows up") and not c(h).turn.bonus, "bonus hooves attack")
