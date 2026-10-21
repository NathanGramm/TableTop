extends "res://tests/test_base.gd"


func _hb_id(kind: String, name: String) -> String:
	for id in state.homebrew[kind]:
		if state.homebrew[kind][id].name == name:
			return id
	return ""


func _gloom_stalker() -> Dictionary:
	var m := Homebrew.blank("monsters")
	m.name = "Gloom Stalker"
	m.ac = 14
	m.hp = 30
	m.cr = 2.0
	m.traits = ["packTactics"]
	m.attacks = [
		{"id": "a1", "name": "Claw", "range": "melee", "to_hit": 5, "reach": 5, "normal": 0, "long": 0, "props": [],
			"damage": [{"dice": "1d6", "bonus": 3, "type": "slashing"}]},
		{"id": "a2", "name": "Sting", "range": "melee", "to_hit": 5, "reach": 5, "normal": 0, "long": 0, "props": [],
			"damage": [{"dice": "1d4", "bonus": 3, "type": "piercing"}],
			"on_hit": {"ability": "con", "dc": 12, "damage": [{"dice": "2d6", "type": "poison"}], "half": true, "condition": "poisoned"}},
	]
	m.multiattack = ["a1", "a2"]
	m.powers = [{"id": "p1", "name": "Shadow Breath", "dc": 12, "recharge": 5,
		"spell": {"name": "Shadow Breath", "level": 0, "time": "action", "range": 0, "target": {"type": "area", "shape": "cone", "size": 15, "origin": "self"},
			"save": {"ability": "dex", "half": true}, "damage": [{"dice": "4d6", "type": "necrotic"}], "desc": ""}}]
	return m


func test_homebrew_monster_plays() -> void:
	fresh()
	must({"type": "homebrewSave", "kind": "monsters", "data": _gloom_stalker()})
	var mid := _hb_id("monsters", "Gloom Stalker")
	ok(mid.begins_with("hb_"), "saved with a homebrew id")
	eq(state.homebrew.monsters[mid].xp, 450, "XP filled in from CR 2")
	var f := add("pregen", "fighter", Vector2i(3, 2))
	must({"type": "spawn", "kind": "monster", "template": mid, "pos": Vector2i(2, 2)})
	var g := ""
	for id in state.combatants:
		if c(id).name == "Gloom Stalker":
			g = id
	ok(g != "", "spawned from homebrew")
	eq(c(g).prof, 2, "CR 2 proficiency")
	start([g, f])
	Dice.forced = [15, 3]
	must({"type": "attack", "actor_id": g, "attack_id": "a1", "target_id": f})
	eq(c(g).turn.multiattack_left, ["a2"], "multiattack works")
	Dice.forced = [15, 2, 1, 1, 1]  # sting hits for 5, Con save 1 fails: 2d6 poison + poisoned
	var hp: int = c(f).hp
	must({"type": "attack", "actor_id": g, "attack_id": "a2", "target_id": f})
	ok(engine().has_cond(c(f), "poisoned"), "on-hit condition applied")
	eq(c(f).hp, hp - 5 - 2, "sting 2+3 plus 2d6 poison (1+1)")
	must({"type": "endTurn", "actor_id": g})
	must({"type": "endTurn", "actor_id": f})
	Dice.forced = [6, 6, 6, 6, 1]
	must({"type": "power", "actor_id": g, "power_id": "p1", "point": Vector2i(3, 2)})
	ok(log_has("Shadow Breath"), "breath-style power used")


func test_homebrew_spell_cast_and_effects() -> void:
	fresh()
	var sp := Homebrew.blank("spells")
	sp.name = "Grasping Shadows"
	sp.mode = "save"
	sp.save = {"ability": "str", "half": true}
	sp.target = {"type": "area", "shape": "sphere", "size": 10, "origin": "point"}
	sp.range = 60
	sp.concentration = true
	sp.damage = [{"dice": "3d6", "type": "necrotic", "per_slot": "1d6"}]
	sp.effect = {"on": "fail", "name": "", "conditions": ["restrained"], "mods": {"speed_bonus": 0},
		"repeat_save": {"ability": "str", "phase": "end"}, "expires_on": {"who": "source", "phase": "start", "count": 10}}
	must({"type": "homebrewSave", "kind": "spells", "data": sp})
	var sid := _hb_id("spells", "Grasping Shadows")
	ok(Spells.spells_for_class("wizard", 1).has(sid), "homebrew spell is on the wizard list")
	ok(not state.homebrew.spells[sid].has("attack"), "save spells drop the attack field")
	eq(state.homebrew.spells[sid].effect.name, "Grasping Shadows", "effect named after the spell")
	var w := add("pregen", "wizard", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(10, 2))
	must({"type": "grantSpell", "id": w, "spell_id": sid})
	ok(c(w).spellcasting.known.has(sid), "DM granted the spell")
	start([w, o])
	Dice.forced = [4, 4, 4, 1]
	must({"type": "cast", "actor_id": w, "spell_id": sid, "slot": 1, "point": Vector2i(10, 2)})
	eq(c(o).hp, 59 - 12, "3d6 necrotic on a failed save")
	ok(engine().has_cond(c(o), "restrained"), "restrained on a failed save")
	eq(c(w).concentration.get("spell_id", ""), sid, "concentrating")
	ok(not run({"type": "homebrewDelete", "kind": "spells", "id": sid}).ok, "can't delete a spell someone knows")


func test_homebrew_validation() -> void:
	var m := _gloom_stalker()
	m.attacks[0].damage[0].dice = "two dice"
	ok(Homebrew.validate("monsters", Homebrew.normalize("monsters", m)).any(func(e): return "dice expression" in e), "bad dice caught")
	m = _gloom_stalker()
	m.multiattack = ["a1", "a9"]
	eq(Homebrew.normalize("monsters", m).multiattack, ["a1"], "missing multiattack ids dropped")
	var sp := Homebrew.blank("spells")
	sp.mode = "attack"
	sp.target = {"type": "self"}
	ok(not Homebrew.validate("spells", Homebrew.normalize("spells", sp)).is_empty(), "spell attacks need creature targets")
	var it := Homebrew.blank("items")
	it.kind = "potion"
	ok(not Homebrew.validate("items", it).is_empty(), "potions need healing dice")
	fresh()
	ok(not run({"type": "homebrewSave", "kind": "monsters", "data": {}}, {"name": "Bob", "is_dm": false}).ok, "players can't make homebrew")


func test_magic_items() -> void:
	fresh()
	var f := add("pregen", "fighter", Vector2i(2, 2), 1)
	var base_hit: int = engine().find_attack(c(f), "longsword").to_hit
	var base_ac: int = c(f).ac
	must({"type": "giveItem", "id": f, "item": {"id": "weapon_plus_1", "base": "longsword"}})
	var sword := {}
	for a in c(f).attacks:
		if a.name == "+1 Longsword":
			sword = a
	ok(not sword.is_empty(), "named +1 Longsword")
	eq(sword.get("to_hit", 0), base_hit + 1, "+1 to hit")
	ok(engine().find_attack(c(f), "longsword").is_empty(), "replaces the mundane longsword")
	must({"type": "giveItem", "id": f, "item": {"id": "armor_plus_1", "base": "chain_mail"}})
	eq(c(f).ac, base_ac + 1, "+1 chain mail")
	must({"type": "giveItem", "id": f, "item": {"id": "ring_of_protection", "base": ""}})
	eq(c(f).ac, base_ac + 2, "ring of protection +1 AC")
	eq(c(f).save_bonus.get("dex", 0), 1, "and +1 saves")
	must({"type": "giveItem", "id": f, "item": {"id": "gauntlets_of_ogre_power", "base": ""}})
	eq(c(f).abilities.str, 19, "gauntlets set Str 19")
	must({"type": "giveItem", "id": f, "item": {"id": "ring_of_resistance", "base": "fire"}})
	ok(c(f).resistances.has("fire"), "ring of resistance (fire)")
	ok(not run({"type": "giveItem", "id": f, "item": {"id": "flame_tongue", "base": ""}}).ok, "flame tongue needs a weapon")
	must({"type": "giveItem", "id": f, "item": {"id": "flame_tongue", "base": "greatsword"}})
	var ft := {}
	for a in c(f).attacks:
		if a.name == "Flame Tongue Greatsword":
			ft = a
	eq(ft.get("damage", []).size(), 2, "flame tongue adds fire damage")
	must({"type": "giveItem", "id": f, "item": {"id": "potion_of_healing", "base": ""}})
	must({"type": "setHp", "id": f, "hp": 1})
	var g := add("monster", "goblin", Vector2i(9, 9))
	start([f, g])
	var idx: int = c(f).items.size() - 1
	Dice.forced = [4, 4]
	must({"type": "useItem", "actor_id": f, "index": idx})
	eq(c(f).hp, 11, "potion heals 2d4+2")
	eq(c(f).turn.actions, 0, "drinking takes an action")
	ok(not c(f).items.any(func(e): return e.id == "potion_of_healing"), "potion used up")
	must({"type": "endCombat"})
	must({"type": "takeItem", "id": f, "index": 0})
	ok(engine().find_attack(c(f), "longsword") != {}, "taking the +1 sword back restores the mundane one")


func test_homebrew_items_and_permissions() -> void:
	fresh()
	var it := Homebrew.blank("items")
	it.name = "Sunblade of the Dawn"
	it.kind = "weapon"
	it.base = "melee"
	it.attack_bonus = 2
	it.damage_bonus = 2
	it.extra_damage = [{"dice": "1d8", "type": "radiant"}]
	it.erase("ac_bonus")
	must({"type": "homebrewSave", "kind": "items", "data": it})
	var iid := _hb_id("items", "Sunblade of the Dawn")
	var p := add("pregen", "paladin", Vector2i(2, 2), 3)
	c(p).controller = "Bob"
	must({"type": "giveItem", "id": p, "item": {"id": iid, "base": "longsword"}})
	ok(c(p).attacks.any(func(a): return a.name == "Sunblade of the Dawn Longsword"), "homebrew magic weapon")
	var bob := {"name": "Bob", "is_dm": false}
	var cheat: Dictionary = c(p).def.duplicate(true)
	cheat.items.append({"id": "ring_of_protection", "base": ""})
	ok(not run({"type": "updateCharacter", "id": p, "def": Creator.normalize(cheat)}, bob).ok, "players can't add items to themselves")
	ok(not run({"type": "homebrewDelete", "kind": "items", "id": iid}).ok, "can't delete an item someone carries")
	must({"type": "homebrewSave", "kind": "monsters", "data": _gloom_stalker()})
	var view := RulesEngine.redact_for(state, bob)
	ok(view.homebrew.monsters.is_empty(), "homebrew stat blocks hidden from players")
	ok(view.homebrew.items.has(iid), "items stay visible")


func test_pack_round_trip() -> void:
	fresh()
	must({"type": "homebrewSave", "kind": "monsters", "data": _gloom_stalker()})
	var sp := Homebrew.blank("spells")
	sp.name = "Arc Lash"
	must({"type": "homebrewSave", "kind": "spells", "data": sp})
	var text := Homebrew.export_pack(state)
	fresh()
	var parsed := Homebrew.parse_pack(text)
	ok(parsed.ok, "pack parses")
	must({"type": "homebrewImport", "pack": parsed.pack})
	eq(state.homebrew.monsters.size(), 1, "monster imported")
	eq(state.homebrew.spells.size(), 1, "spell imported")
	var mid: String = state.homebrew.monsters.keys()[0]
	ok(state.homebrew.monsters[mid].ac is int, "JSON floats turned back into ints")
	must({"type": "spawn", "kind": "monster", "template": mid, "pos": Vector2i(4, 4)})
	ok(state.combatants.values().any(func(x): return x.name == "Gloom Stalker"), "imported monster spawns")
	ok(not Homebrew.parse_pack("{\"hello\": 1}").ok, "rejects non-packs")


func test_monster_spellcasting() -> void:
	fresh()
	var m := Homebrew.blank("monsters")
	m.name = "Cult Adept"
	m.spellcasting = {"ability": "wis", "dc": 12, "attack_bonus": 4, "slots": [0, 3, 0, 0, 0, 0, 0, 0, 0, 0], "spells": ["sacred_flame", "inflict_wounds"]}
	must({"type": "homebrewSave", "kind": "monsters", "data": m})
	must({"type": "spawn", "kind": "monster", "template": _hb_id("monsters", "Cult Adept"), "pos": Vector2i(2, 2)})
	var cid := ""
	for id in state.combatants:
		cid = id
	var f := add("pregen", "fighter", Vector2i(3, 2))
	start([cid, f])
	Dice.forced = [15, 5, 5, 5]
	must({"type": "cast", "actor_id": cid, "spell_id": "inflict_wounds", "targets": [f]})
	eq(c(cid).spellcasting.slots_used[1], 1, "monster spent a slot")
	ok(c(f).hp < c(f).max_hp, "inflict wounds hit")
