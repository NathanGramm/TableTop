extends "res://tests/test_base.gd"


func _valid_fighter() -> Dictionary:
	var d := Creator.new_def("fighter", "human")
	d.name = "Test Fighter"
	d.skills = ["athletics", "perception"]
	d.background = "sage"
	d.armor = "chain_mail"
	d.shield = true
	d.weapons = ["longsword", "javelin"]
	return d


func test_new_character_validates() -> void:
	var d := _valid_fighter()
	eq(Creator.validate(d), [], "a complete fighter is legal")
	var c := Builder.build_character(d, 1, "x")
	eq(c.abilities.str, 16, "standard array 15 + human 1")
	ok(c.skills.has("arcana") and c.skills.has("history"), "background skills applied")
	eq(c.ac, 18, "chain mail + shield")


func test_ability_methods() -> void:
	var d := _valid_fighter()
	d.method = "pointbuy"
	d.abilities = {"str": 15, "dex": 15, "con": 15, "int": 8, "wis": 8, "cha": 8}
	eq(Creator.point_buy_spent(d.abilities), 27, "three 15s cost 27")
	eq(Creator.validate(d), [], "27 points is legal")
	d.abilities.wis = 9
	ok(not Creator.validate(d).is_empty(), "28 points is too many")
	d.method = "standard"
	d.abilities = {"str": 15, "dex": 15, "con": 13, "int": 12, "wis": 10, "cha": 8}
	ok(not Creator.validate(d).is_empty(), "standard array values must each be used once")
	d.method = "roll"
	d.rolled = [17, 12, 11, 10, 9, 6]
	d.abilities = {"str": 17, "dex": 12, "con": 11, "int": 10, "wis": 9, "cha": 6}
	eq(Creator.validate(d), [], "rolled scores assigned")
	d.abilities.str = 18
	ok(not Creator.validate(d).is_empty(), "can't use a score you didn't roll")


func test_asi_and_levels() -> void:
	var d := _valid_fighter()
	d.level = 6
	ok(Creator.validate(d).size() == 2, "fighter needs ASIs at 4 and 6")
	d.asi = {4: {"str": 2}, 6: {"con": 1, "dex": 1}}
	eq(Creator.validate(d), [], "ASIs chosen")
	var c := Builder.build_character(d, 6, "x")
	eq(c.abilities.str, 18, "+2 str")
	eq(c.abilities.con, 16, "14 + human 1 + ASI 1")
	d.asi = {4: {"str": 2}, 6: {"str": 2}}
	d.abilities = {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}
	eq(Builder.build_character(d, 6, "x").abilities.str, 20, "capped at 20")


func test_skill_rules() -> void:
	var d := _valid_fighter()
	d.skills = ["athletics", "arcana"]
	ok(not Creator.validate(d).is_empty(), "arcana isn't a fighter skill")
	d.skills = ["athletics", "history"]
	ok(not Creator.validate(d).is_empty(), "history is already from the Sage background")
	var r := Creator.new_def("rogue", "half_elf")
	r.name = "Rogue"
	r.skills = ["stealth", "acrobatics", "perception", "deception"]
	r.background = "criminal"
	ok(Creator.validate(r).any(func(e): return "chosen twice" in e), "criminal's stealth/deception overlap with class picks")
	r.background = "sage"
	r.flex_asi = ["dex", "con"]
	r.race_skills = ["insight", "medicine"]
	r.expertise = ["stealth", "perception"]
	eq(Creator.validate(r), [], "half-elf rogue with expertise")
	r.expertise = ["stealth", "athletics"]
	ok(not Creator.validate(r).is_empty(), "expertise needs proficiency")


func test_spell_limits() -> void:
	var w := Creator.new_def("wizard", "high_elf")
	w.name = "Wiz"
	w.skills = ["arcana", "investigation"]
	w.background = "noble"
	w.spells = ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "shield", "sleep"]
	w.race_cantrip = "chill_touch"
	eq(Creator.validate(w), [], "3 cantrips, 4 spells (int 16 +3, level 1) and a high elf cantrip")
	w.spells.append("fireball")
	ok(Creator.validate(w).any(func(e): return "too high level" in e), "fireball needs level 5")
	var c := Builder.build_character(Creator.normalize(w), 1, "x")
	ok(c.spellcasting.known.has("chill_touch"), "racial cantrip known")
	var cl := Creator.new_def("cleric", "hill_dwarf")
	eq(Creator.always_prepared(cl, 5), ["bless", "cure_wounds", "lesser_restoration", "revivify"], "Life domain spells by level 5")
	var built := Builder.build_character(Creator.normalize(cl), 3, "y")
	ok(built.spellcasting.known.has("lesser_restoration"), "domain spells always prepared")


func test_pregens_normalize_to_legal_characters() -> void:
	for p in Pregens.ALL:
		for lv in [1, 5, 20]:
			var d: Dictionary = Pregens.ALL[p].duplicate(true)
			d["level"] = lv
			var n := Creator.normalize(d)
			eq(Creator.validate(n), [], "%s at level %d normalizes to a legal character" % [p, lv])


func test_create_and_level_up_through_engine() -> void:
	fresh()
	add("pregen", "cleric", Vector2i(3, 3))
	var bob := {"name": "Bob", "is_dm": false}
	var d := _valid_fighter()
	must({"type": "createCharacter", "def": d}, bob)
	var id := ""
	for cid in state.combatants:
		if c(cid).name == "Test Fighter":
			id = cid
	ok(id != "", "character created")
	eq(c(id).controller, "Bob", "the creator controls it")
	eq(c(id).notes.get("background", ""), "Sage", "background written to the sheet")
	ok(Grid.distance(state, c(id), state.combatants.values()[0]) <= 10, "placed near the party")
	must({"type": "adjustHp", "id": id, "amount": -5})
	var pos: Vector2i = c(id).pos
	var up: Dictionary = c(id).def.duplicate(true)
	up.level = 2
	must({"type": "updateCharacter", "id": id, "def": up}, bob)
	eq(c(id).level, 2, "leveled up")
	eq(c(id).hp, c(id).max_hp - 5, "damage carried over")
	eq(c(id).pos, pos, "stayed put")
	ok(c(id).features.has("actionSurge"), "gained Action Surge")
	var bad := up.duplicate(true)
	bad.skills = ["arcana", "athletics"]
	ok(not run({"type": "updateCharacter", "id": id, "def": bad}, bob).ok, "illegal edits are rejected")
	ok(not run({"type": "updateCharacter", "id": id, "def": up}, {"name": "Eve", "is_dm": false}).ok, "others can't edit it")


func test_json_round_trip() -> void:
	var d := _valid_fighter()
	d.level = 4
	d.asi = {4: {"str": 2}}
	var back = JSON.parse_string(JSON.stringify(d))
	eq(Creator.validate(back), [], "a definition survives export/import as JSON")
	eq(Builder.build_character(back, 4, "x").abilities.str, 18, "string ASI keys still apply")
