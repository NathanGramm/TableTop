extends "res://tests/test_base.gd"
## DM optional rules: encumbrance, costly components, ammunition.


func test_encumbrance_variant() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(1, 1))
	var lb := Equipment.carried_lb(c(f))
	var s: int = c(f).abilities.str
	eq(engine().speed_of(c(f)), c(f).base_speed, "off by default")
	must({"type": "settings", "settings": {"encumbrance": true}})
	c(f).notes["pack_lb"] = str(5 * s - lb + 1)
	eq(Equipment.encumbrance(c(f)), 1, "over 5 × Str")
	eq(engine().speed_of(c(f)), c(f).base_speed - 10, "encumbered: -10 ft")
	c(f).notes["pack_lb"] = str(10 * s - lb + 1)
	eq(engine().speed_of(c(f)), c(f).base_speed - 20, "heavily encumbered: -20 ft")
	var g := add("monster", "goblin", Vector2i(2, 1))
	ok(engine().attack_mode(c(f), c(g), "melee", {"profile": c(f).attacks[0]}).dis.has("heavily encumbered"), "disadvantage on Str attacks")
	c(f).notes["gp"] = str(50 * 5 * s)  # 5 × Str more pounds of gold
	eq(engine().speed_of(c(f)), 5, "over carrying capacity: 5 ft")
	c(f).notes["pack_lb"] = str(30 * s)
	eq(engine().speed_of(c(f)), 0, "can't move past twice capacity")


func test_costly_components() -> void:
	fresh()
	var cl := add("pregen", "cleric", Vector2i(1, 1))
	var sp := Spells.get_spell("revivify")
	eq(engine().cast_error(c(cl), sp, 3, {}), "", "no component needed with the rule off")
	must({"type": "settings", "settings": {"components": true}})
	ok("diamond" in engine().cast_error(c(cl), sp, 3, {}), "needs diamonds")
	must({"type": "giveItem", "id": cl, "item": {"id": "diamond_dust_100", "base": ""}})
	ok(engine().cast_error(c(cl), sp, 3, {}) != "", "diamond dust isn't diamonds")
	must({"type": "giveItem", "id": cl, "item": {"id": "diamond_500", "base": ""}})
	must({"type": "giveItem", "id": cl, "item": {"id": "diamond_300", "base": ""}})
	var e := engine()
	eq(Items.get_item(c(cl).items[e.component_index(c(cl), sp)].id).gp, 300, "uses the cheapest diamond worth enough")
	var dead := add("pregen", "fighter", Vector2i(2, 1))
	start([cl, dead])
	c(dead).hp = 0
	c(dead).dead = true
	c(dead)["died_round"] = state.combat.round
	must({"type": "cast", "actor_id": cl, "spell_id": "revivify", "slot": 3, "targets": [dead]})
	eq(c(cl).items.map(func(i): return i.id), ["diamond_dust_100", "diamond_500"], "the 300 gp diamonds are consumed")
	eq(c(cl).def.items.size(), 2, "and gone from the character")


func test_ammunition() -> void:
	fresh()
	var r := add("pregen", "ranger", Vector2i(1, 1))
	var g := add("monster", "goblin", Vector2i(6, 1))
	c(g).hp = 999
	c(g).max_hp = 999
	start([r, g])
	must({"type": "attack", "actor_id": r, "attack_id": "longbow", "target_id": g})
	ok(not c(r).notes.has("arrows"), "not tracked with the rule off")
	must({"type": "settings", "settings": {"ammunition": true}})
	c(r).notes["arrows"] = "3"
	must({"type": "attack", "actor_id": r, "attack_id": "longbow", "target_id": g})
	eq(c(r).notes.arrows, "2", "an arrow per shot")
	c(r).notes["arrows"] = "0"
	ok(not run({"type": "attack", "actor_id": r, "attack_id": "longbow", "target_id": g}).ok, "out of arrows")
	must({"type": "endCombat"})
	eq(c(r).notes.arrows, "0", "half of 1 spent rounds down")
	c(r)["ammo_spent"] = {"arrows": 5}
	start([r, g])
	must({"type": "endCombat"})
	eq(c(r).notes.arrows, "2", "recover half after the fight")
