extends "res://tests/test_base.gd"


## A level-5 pregen who took `feat` instead of the level-4 ASI. `changes` are merged into the definition.
func pc(feat: String, cls: String, pos: Vector2i, weapons: Array = [], changes: Dictionary = {}, side: String = "") -> String:
	var d: Dictionary = Pregens.ALL[cls].duplicate(true)
	d.asi = {4: changes.get("entry", Creator.new_feat_entry(feat, cls))}
	if not weapons.is_empty():
		d.weapons = weapons
		d.shield = false
	for k in changes:
		if k != "entry":
			d[k] = changes[k]
	var id := "pc_%d" % state.combatants.size()
	var ch := Builder.build_character(d, 5, id)
	ch.pos = pos
	if side != "":
		ch.side = side
	state.combatants[id] = ch
	return id


func test_feat_replaces_an_asi_in_the_creator() -> void:
	var d := Creator.new_def("fighter", "human")
	d.name = "Feat Taker"
	d.skills = ["athletics", "perception"]
	d.background = "sage"
	d.armor = "chain_mail"
	d.weapons = ["greatsword"]
	d.style = "defense"
	d.level = 6
	d.asi = {4: {"feat": "tough"}, 6: {"feat": "alert"}}
	eq(Creator.validate(d), [], "two different feats are legal")
	eq(Creator.asi_bonus(d, 6).str, 0, "a feat adds no ability scores")
	eq(Creator.feats_of(d, 5), ["tough"], "only feats up to the level count")
	d.asi[6] = {"feat": "tough"}
	ok(Creator.validate(d).any(func(e): return "once" in e), "the same feat twice is rejected")
	d.asi[6] = {"feat": "nope"}
	ok(Creator.validate(d).any(func(e): return "Unknown feat" in e), "unknown feats are rejected")


func test_tough_alert_mobile_and_lucky_numbers() -> void:
	fresh()
	var base := Builder.build_character(Pregens.ALL.fighter, 5, "x")
	var t := c(pc("tough", "fighter", Vector2i(1, 1)))
	eq(t.max_hp - base.max_hp, 10, "Tough: +2 HP per level")
	var a := c(pc("alert", "fighter", Vector2i(2, 1)))
	eq(a.init_bonus - base.init_bonus, 5, "Alert: +5 initiative")
	must({"type": "setSurprised", "id": a.id, "surprised": true})
	ok(not c(a.id).surprised, "Alert: can't be surprised")
	eq(c(pc("mobile", "fighter", Vector2i(3, 1))).base_speed - base.base_speed, 10, "Mobile: +10 ft")
	eq(c(pc("lucky", "fighter", Vector2i(4, 1))).resources.luck.max, 3, "Lucky: 3 luck points")
	ok(c(pc("alert", "fighter", Vector2i(5, 1))).features.has("alert"), "feats show up as features")


func test_great_weapon_master() -> void:
	fresh()
	var f := pc("greatWeaponMaster", "fighter", Vector2i(2, 2), ["greatsword"])
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, o])
	var hp: int = c(o).hp
	Dice.forced = [10, 1, 1]  # +6 to hit -5 = 11 vs AC 11
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"power": true}})
	eq(hp - c(o).hp, 1 + 1 + 3 + 10, "−5 to hit, +10 damage")
	ok(not run({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"bonus": true}}).ok, "no bonus attack yet")
	Dice.forced = [20, 1, 1, 1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o})
	Dice.forced = [1]
	must({"type": "attack", "actor_id": f, "attack_id": "greatsword", "target_id": o, "options": {"bonus": true}})
	Dice.forced.clear()


func test_sharpshooter_and_crossbow_expert() -> void:
	fresh()
	var s := pc("sharpshooter", "fighter", Vector2i(1, 1), ["longbow"])
	var g := add("monster", "goblin", Vector2i(14, 14))
	var eng := engine()
	var bow := eng.find_attack(c(s), "longbow")
	bow.normal = 20  # make the goblin "long range" on a small map
	ok(not eng.attack_mode(c(s), c(g), "ranged", {"profile": bow}).dis.has("long range"), "Sharpshooter: no long-range disadvantage")
	eq(eng.power_attack_feat(c(s), bow), "sharpshooter", "ranged power attack")
	var x := pc("crossbowExpert", "fighter", Vector2i(13, 14), ["heavy_crossbow"])
	var xb := eng.find_attack(c(x), "heavy_crossbow")
	ok(not eng.attack_mode(c(x), c(g), "ranged", {"profile": xb}).dis.has("enemy adjacent"), "Crossbow Expert: adjacent enemy is fine")
	c(x).turn.attack_action_weapons = ["heavy_crossbow"]
	eq(eng.validate_attack(c(x), c(g), xb), "", "Crossbow Expert ignores loading")


func test_sentinel_stops_and_punishes() -> void:
	fresh()
	var f := pc("sentinel", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	var w := add("pregen", "wizard", Vector2i(3, 3))
	start([g, f, w])
	must({"type": "action", "actor_id": g, "action": "disengage"})
	Dice.forced = [15, 1]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	Dice.forced.clear()
	ok(c(f).reaction_used, "opportunity attack despite Disengage")
	eq(c(g).pos, Vector2i(3, 2), "the hit dropped the goblin's speed to 0")
	c(f).reaction_used = false
	c(g).turn = Stats.fresh_turn()
	Dice.forced = [1, 1]  # goblin misses the wizard, Sentinel misses the goblin
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": w})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("Sentinel: "), "Sentinel strikes when the goblin attacks someone else")


func test_mobile_avoids_opportunity_attacks() -> void:
	fresh()
	var f := pc("mobile", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g})
	must({"type": "move", "actor_id": f, "to": Vector2i(2, 6)})
	Dice.forced.clear()
	ok(not c(g).reaction_used, "no opportunity attack after a melee attack")


func test_polearm_master() -> void:
	fresh()
	var f := pc("polearmMaster", "fighter", Vector2i(2, 2), ["glaive"])
	var g := add("monster", "goblin", Vector2i(6, 2))
	start([g, f])
	Dice.forced = [1]
	must({"type": "move", "actor_id": g, "to": Vector2i(4, 2)})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("Polearm Master"), "attack when the goblin enters reach")
	must({"type": "endTurn", "actor_id": g})
	var butt := {"type": "attack", "actor_id": f, "attack_id": "glaive_butt", "target_id": g, "options": {"bonus": true}}
	ok(not run(butt).ok, "butt end needs the Attack action first")
	Dice.forced = [1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "glaive", "target_id": g})
	must(butt)
	Dice.forced.clear()


func test_lucky_and_war_caster() -> void:
	fresh()
	var f := pc("lucky", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [2, 15, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": g})
	Dice.forced.clear()
	eq(c(f).resources.luck.used, 1, "a luck point turned the miss around")
	ok(c(g).hp < c(g).max_hp, "and the reroll hit")
	var w := c(pc("warCaster", "wizard", Vector2i(6, 6)))
	Dice.forced = [1, 20]
	ok(engine().roll_save(w, "con", 15, {"concentration": true}).success, "War Caster: advantage on concentration saves")
	Dice.forced.clear()


func test_every_feat_has_legal_defaults() -> void:
	for fid in Creator.FEATS:
		var d := Creator.new_def("wizard", "human")
		d.level = 4
		d.asi = {4: Creator.new_feat_entry(fid, "wizard")}
		var errs := Creator.feat_errors(d, 4, d.asi[4]).filter(func(e): return not "needs" in e)
		eq(errs, [], "%s defaults are legal" % fid)
	var w := Creator.new_def("wizard", "human")
	w.level = 4
	w.asi = {4: {"feat": "grappler"}}
	ok(Creator.feat_errors(w, 4, w.asi[4]).any(func(e): return "Strength 13" in e), "Grappler needs Str 13")
	w.asi = {4: {"feat": "heavyArmorMaster", "ability": "str"}}
	ok(Creator.feat_errors(w, 4, w.asi[4]).any(func(e): return "heavy armor" in e), "Heavy Armor Master needs heavy armor")
	w.asi = {4: {"feat": "resilient", "ability": "con"}}
	eq(Creator.asi_bonus(w, 4).con, 1, "a half feat adds +1")
	w.asi = {4: {"feat": "skilled", "picks": ["arcana", "arcana", "history"]}}
	ok(not Creator.feat_errors(w, 4, w.asi[4]).is_empty(), "picks must differ")
	w.asi = {4: {"feat": "lightlyArmored", "ability": "dex"}}
	w.armor = "leather"
	ok(not Creator.validate(w).any(func(e): return "armor" in e), "Lightly Armored lets a wizard wear leather")


func test_proficiency_and_number_feats() -> void:
	fresh()
	var base := Builder.build_character(Pregens.ALL.fighter, 5, "x")
	var r := c(pc("resilient", "fighter", Vector2i(1, 1), [], {"entry": {"feat": "resilient", "ability": "wis"}}))
	ok(r.save_profs.has("wis"), "Resilient: Wis save proficiency")
	eq(r.abilities.wis, base.abilities.wis + 1, "Resilient: +1 Wis")
	var sk := c(pc("skilled", "fighter", Vector2i(2, 1), [], {"entry": {"feat": "skilled", "picks": ["arcana", "stealth", "history"]}}))
	ok(sk.skills.has("arcana") and sk.skills.has("stealth"), "Skilled: three skills")
	var li := c(pc("linguist", "fighter", Vector2i(3, 1), [], {"entry": {"feat": "linguist", "ability": "int", "picks": ["Elvish", "Giant", "Orc"]}}))
	ok(li.languages.has("Giant"), "Linguist: languages")
	var wm := c(pc("weaponMaster", "wizard", Vector2i(4, 1), ["longsword"], {"entry": {"feat": "weaponMaster", "ability": "str", "picks": ["longsword", "longbow", "rapier", "whip"]}}))
	ok(engine().find_attack(wm, "longsword").proficient, "Weapon Master: proficient")
	eq(c(pc("observant", "fighter", Vector2i(5, 1))).passive_perception - base.passive_perception, 5, "Observant: +5 passive Perception")
	var mam := c(pc("mediumArmorMaster", "fighter", Vector2i(6, 1), [], {"armor": "scale_mail", "abilities": {"str": 15, "dex": 16, "con": 13, "int": 8, "wis": 12, "cha": 10}}))
	eq(mam.ac, 14 + 3 + 2, "Medium Armor Master: Dex cap 3 (scale mail + shield)")
	ok(not mam.stealth_dis, "and no Stealth disadvantage")
	var dw := c(pc("dualWielder", "fighter", Vector2i(7, 1), ["longsword", "longsword"]))
	var plain := c(pc("tough", "fighter", Vector2i(8, 1), ["longsword", "longsword"]))
	eq(dw.ac - plain.ac, 1, "Dual Wielder: +1 AC with two melee weapons")
	var tb := c(pc("tavernBrawler", "fighter", Vector2i(9, 1)))
	eq(engine().find_attack(tb, "unarmed").damage[0].dice, "1d4", "Tavern Brawler: d4 unarmed strikes")


func test_dual_wielder_and_crossbow_expert_bonus_attacks() -> void:
	fresh()
	var f := pc("dualWielder", "fighter", Vector2i(2, 2), ["longsword", "longsword"])
	var x := pc("crossbowExpert", "fighter", Vector2i(2, 4), ["shortsword", "hand_crossbow"])
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, x, o])
	Dice.forced = [1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o})
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o, "options": {"bonus": true}})
	must({"type": "endTurn", "actor_id": f})
	must({"type": "attack", "actor_id": x, "attack_id": "shortsword", "target_id": o})
	must({"type": "attack", "actor_id": x, "attack_id": "hand_crossbow", "target_id": o, "options": {"bonus": true}})
	Dice.forced.clear()


func test_damage_feats() -> void:
	fresh()
	var f := pc("heavyArmorMaster", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([g, f])
	Dice.forced = [15, 6]
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": f})
	eq(c(f).max_hp - c(f).hp, 6 + 2 - 3, "Heavy Armor Master: −3")
	fresh()
	var w := pc("elementalAdept", "wizard", Vector2i(2, 2), [], {"entry": {"feat": "elementalAdept", "picks": ["fire"]}})
	g = add("monster", "goblin", Vector2i(5, 2))
	c(g).resistances.append("fire")
	start([w, g])
	Dice.forced = [15, 1, 1]
	must({"type": "cast", "actor_id": w, "spell_id": "fire_bolt", "targets": [g]})
	eq(c(g).max_hp - c(g).hp, 4, "Elemental Adept: 1s become 2s and fire resistance is ignored")
	fresh()
	var s := pc("savageAttacker", "fighter", Vector2i(2, 2), ["greatsword"])
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([s, o])
	Dice.forced = [15, 1, 1, 6, 6]
	must({"type": "attack", "actor_id": s, "attack_id": "greatsword", "target_id": o})
	eq(c(o).max_hp - c(o).hp, 6 + 6 + 3, "Savage Attacker keeps the better damage roll")
	Dice.forced.clear()


func test_charger_brawler_and_shield_master() -> void:
	fresh()
	var f := pc("charger", "fighter", Vector2i(2, 2))
	var o := add("monster", "ogre", Vector2i(6, 2))
	start([f, o])
	must({"type": "action", "actor_id": f, "action": "dash"})
	must({"type": "move", "actor_id": f, "to": Vector2i(5, 2)})
	Dice.forced = [15, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o, "options": {"bonus": true}})
	eq(c(o).max_hp - c(o).hp, 1 + 3 + 2 + 5, "Charger: bonus attack with +5 damage")
	fresh()
	var b := pc("tavernBrawler", "fighter", Vector2i(2, 2), [], {"entry": {"feat": "tavernBrawler", "ability": "str"}})
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([b, g])
	ok(not run({"type": "grapple", "actor_id": b, "target_id": g, "bonus": true}).ok, "no bonus grapple before an unarmed hit")
	Dice.forced = [15, 1, 20, 1]
	must({"type": "attack", "actor_id": b, "attack_id": "unarmed", "target_id": g})
	must({"type": "grapple", "actor_id": b, "target_id": g, "bonus": true})
	ok(engine().has_tag(c(g), "grapple"), "Tavern Brawler: bonus-action grapple")
	fresh()
	var sm := pc("shieldMaster", "fighter", Vector2i(2, 2))
	g = add("monster", "goblin", Vector2i(3, 2))
	start([sm, g])
	Dice.forced = [1, 20, 1]
	must({"type": "attack", "actor_id": sm, "attack_id": "longsword", "target_id": g})
	must({"type": "shove", "actor_id": sm, "target_id": g, "mode": "prone", "bonus": true})
	ok(engine().has_cond(c(g), "prone"), "Shield Master: bonus-action shove")
	Dice.forced.clear()


func test_healer_inspiring_leader_and_durable() -> void:
	fresh()
	var f := pc("healer", "fighter", Vector2i(2, 2))
	var w := add("pregen", "wizard", Vector2i(3, 2))
	c(w).hp = 5
	Dice.forced = [3]
	must({"type": "feature", "actor_id": f, "feature": "healerKit", "target_id": w})
	eq(c(w).hp, mini(c(w).max_hp, 5 + 3 + 4 + 5), "Healer: 1d6 + 4 + level")
	ok(not run({"type": "feature", "actor_id": f, "feature": "healerKit", "target_id": w}).ok, "once per rest")
	c(w).hp = 0
	must({"type": "action", "actor_id": f, "action": "stabilize", "target_id": w})
	eq(c(w).hp, 1, "Healer: stabilizing gives 1 HP")
	var l := pc("inspiringLeader", "fighter", Vector2i(4, 4))
	must({"type": "feature", "actor_id": l, "feature": "inspiringLeader"})
	eq(c(w).temp_hp, 5 + engine().mod(c(l), "cha"), "Inspiring Leader: level + Cha temp HP")
	var d := pc("durable", "fighter", Vector2i(8, 8), [], {"entry": {"feat": "durable", "ability": "con"}})
	var con: int = engine().mod(c(d), "con")
	c(d).hp = c(d).max_hp - 2 * con
	Dice.forced = [1]
	must({"type": "rest", "kind": "short"})
	Dice.forced.clear()
	eq(c(d).hp, c(d).max_hp, "Durable: a hit die heals at least twice the Con modifier")


func test_spell_feats() -> void:
	fresh(60, 6)
	var f := pc("magicInitiate", "fighter", Vector2i(1, 1), [], {"entry": {"feat": "magicInitiate", "class": "wizard", "picks": ["fire_bolt", "ray_of_frost", "magic_missile"]}})
	ok(c(f).spellcasting.known.has("fire_bolt"), "Magic Initiate: cantrips")
	ok(not engine().find_power(c(f), "feat_magic_missile").is_empty() and c(f).resources.has("feat_magic_missile"), "and a 1st-level spell once per long rest")
	var r := pc("ritualCaster", "fighter", Vector2i(1, 3), [], {"entry": Creator.new_feat_entry("ritualCaster", "wizard")})
	var rid: String = c(r).powers.filter(func(p): return p.get("ritual", false))[0].id
	must({"type": "power", "actor_id": r, "power_id": rid, "targets": []})
	var w := pc("spellSniper", "wizard", Vector2i(1, 5), [], {"entry": {"feat": "spellSniper", "class": "wizard", "picks": ["fire_bolt"]}})
	var g := add("monster", "goblin", Vector2i(48, 5))
	Dice.forced = [1]
	must({"type": "cast", "actor_id": w, "spell_id": "fire_bolt", "targets": [g]})
	Dice.forced.clear()
	start([r, w, g, f])
	ok(not run({"type": "power", "actor_id": r, "power_id": rid, "targets": []}).ok, "rituals only outside combat")


func test_martial_adept() -> void:
	fresh()
	var f := pc("martialAdept", "fighter", Vector2i(2, 2), [], {"entry": {"feat": "martialAdept", "picks": ["trip", "riposte"]}})
	var o := add("monster", "ogre", Vector2i(3, 2))
	start([f, o])
	Dice.forced = [15, 1, 1, 1]
	must({"type": "attack", "actor_id": f, "attack_id": "longsword", "target_id": o, "options": {"maneuver": "trip"}})
	Dice.forced.clear()
	ok(engine().has_cond(c(o), "prone"), "Trip Attack knocks the ogre prone")
	eq(c(f).resources.superiority.used, 1, "spent the superiority die")
	fresh()
	f = pc("martialAdept", "fighter", Vector2i(2, 2), [], {"entry": {"feat": "martialAdept", "picks": ["riposte", "parry"]}})
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([g, f])
	Dice.forced = [1, 1, 1, 1]
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": f})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("ripostes"), "Riposte after a miss")


func test_reaction_feats() -> void:
	fresh()
	var f := pc("mageSlayer", "fighter", Vector2i(2, 2))
	var w := add("pregen", "wizard", Vector2i(3, 2), 5, "enemy")
	var ally := add("pregen", "cleric", Vector2i(6, 6))
	start([w, f, ally])
	Dice.forced = [15, 1, 1]
	must({"type": "cast", "actor_id": w, "spell_id": "fire_bolt", "targets": [ally]})
	Dice.forced.clear()
	ok(c(f).reaction_used and log_has("Mage Slayer"), "Mage Slayer strikes the caster")
	fresh()
	var r := pc("defensiveDuelist", "rogue", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([g, r])
	Dice.forced = [11]
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": r})
	Dice.forced.clear()
	ok(c(r).reaction_used and c(r).hp == c(r).max_hp, "Defensive Duelist turns the hit into a miss")
	fresh()
	var l := pc("lucky", "fighter", Vector2i(2, 2))
	g = add("monster", "goblin", Vector2i(3, 2))
	start([g, l])
	Dice.forced = [18, 2]
	must({"type": "attack", "actor_id": g, "attack_id": "scimitar", "target_id": l})
	Dice.forced.clear()
	eq(c(l).resources.luck.used, 1, "Lucky: the attacker rolls again")
	eq(c(l).hp, c(l).max_hp, "and misses")
	fresh()
	var wc := pc("warCaster", "wizard", Vector2i(2, 2))
	g = add("monster", "goblin", Vector2i(3, 2))
	start([g, wc])
	Dice.forced = [1]
	must({"type": "move", "actor_id": g, "to": Vector2i(7, 2)})
	Dice.forced.clear()
	ok(log_has("War Caster"), "War Caster: a cantrip as the opportunity attack")


func test_grappler_athlete_and_mobile_dash() -> void:
	fresh()
	var f := pc("grappler", "fighter", Vector2i(2, 2))
	var g := add("monster", "goblin", Vector2i(3, 2))
	start([f, g])
	Dice.forced = [20, 1]
	must({"type": "grapple", "actor_id": f, "target_id": g})
	ok(engine().attack_mode(c(f), c(g), "melee").adv.has("grappler"), "Grappler: advantage on the grappled creature")
	c(f).turn = Stats.fresh_turn()
	Dice.forced = [20, 1]
	must({"type": "feature", "actor_id": f, "feature": "pin", "target_id": g})
	Dice.forced.clear()
	ok(engine().has_cond(c(g), "restrained") and engine().has_cond(c(f), "restrained"), "pinned: both restrained")
	var eng := engine()
	eng.remove_effect(eng.find_effect(c(g), "grapple"))
	ok(not eng.has_cond(c(g), "restrained"), "the pin ends with the grapple")
	fresh()
	var a := pc("athlete", "fighter", Vector2i(2, 2))
	start([a])
	engine().knock_prone(c(a), true)
	must({"type": "action", "actor_id": a, "action": "standUp"})
	eq(c(a).turn.movement_used, 5, "Athlete: standing up costs 5 ft")
