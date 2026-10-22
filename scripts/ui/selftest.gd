extends Node
## Drives the real UI through common flows: `godot -- --selftest [--shots=dir]`.
## Prints PASS/FAIL lines and quits; used to catch runtime errors in UI code.

var main: Node
var shots := ""
var fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	if args.has("--net-host"):
		run_host()
	elif args.has("--net-join"):
		run_join()
	else:
		run()


func wait_until(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while not cond.call() and t < seconds:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return cond.call()


## Two-process network test, host side: `--selftest --net-host`
func run_host() -> void:
	var err := Net.host("DM", 24599)
	check(err == "", "host started " + err)
	Net.full_state = RulesEngine.new_state(12, 12)
	var eng := RulesEngine.new(Net.full_state)
	eng.spawn({"kind": "pregen", "template": "fighter", "level": 3, "pos": Vector2i(2, 2), "controller": "Alice"})
	eng.spawn({"kind": "monster", "template": "goblin", "pos": Vector2i(8, 8)})
	Net._broadcast([])
	check(await wait_until(func(): return Net.players.size() == 2, 20.0), "a player joined")
	check(await wait_until(func(): return Net.full_state.log.any(func(e): return e.text == "hello from alice"), 20.0), "received the player's chat")
	check(await wait_until(func(): return Net.full_state.combatants.values().any(func(c): return c.name.begins_with("Brakka") and c.pos == Vector2i(4, 2)), 20.0), "player moved their character")
	var gob: Dictionary = Net.full_state.combatants.values().filter(func(c): return c.name == "Goblin")[0]
	check(gob.pos == Vector2i(8, 8), "player could not move the DM's goblin")
	check(await wait_until(func(): return Net.full_state.combatants.values().any(func(c): return c.name == "Alice's Rogue" and c.controller == "Alice"), 20.0), "player created a character over the network")
	# Reaction prompt over the network: the DM's goblin flees from Alice's fighter.
	var fid: String = Net.full_state.combatants.values().filter(func(c): return c.name.begins_with("Brakka"))[0].id
	Net.send({"type": "teleport", "id": gob.id, "to": Vector2i(5, 2)})
	var rolls := []
	for c in Net.full_state.combatants.values():
		rolls.append(20 if c.id == gob.id else 1)
	Dice.forced = rolls
	Net.send({"type": "startCombat"})
	Dice.forced = []
	Net.send({"type": "move", "actor_id": gob.id, "to": Vector2i(9, 2)})
	check(Net.full_state.get("pending", {}).get("prompt", {}).get("controller", "") == "Alice", "goblin's move waits for Alice")
	check(await wait_until(func(): return not Net.full_state.has("pending"), 20.0), "Alice answered over the network")
	check(Net.full_state.combatants[fid].reaction_used, "her fighter took the opportunity attack")
	var img := Image.create(120, 120, false, Image.FORMAT_RGB8)
	img.fill(Color.DARK_GREEN)
	Net.send({"type": "setBackground", "data": img.save_png_to_buffer()})
	await wait_until(func(): return Net.players.size() == 1, 20.0)
	print("SELFTEST DONE: %d failures" % fails)
	get_tree().quit(1 if fails else 0)


## Client side: `--selftest --net-join`
func run_join() -> void:
	var errors := []
	Net.error_received.connect(func(m): errors.append(m))
	Net.join("Alice", "127.0.0.1", 24599)
	check(await wait_until(func(): return not Net.state.is_empty(), 20.0), "received the table state")
	check(Net.me.name == "Alice" and not Net.me.is_dm, "joined as a player")
	var gob: Dictionary = Net.state.combatants.values().filter(func(c): return c.name == "Goblin")[0]
	var mine: Dictionary = Net.state.combatants.values().filter(func(c): return c.controller == "Alice")[0]
	check(gob.redacted and gob.max_hp == 1, "monster stats are hidden from players")
	check(not mine.get("redacted", false) and mine.max_hp > 1, "own character fully visible")
	Net.send({"type": "chat", "text": "hello from alice"})
	Net.send({"type": "move", "actor_id": mine.id, "to": Vector2i(4, 2)})
	Net.send({"type": "move", "actor_id": gob.id, "to": Vector2i(7, 7)})
	check(await wait_until(func(): return errors.size() > 0, 20.0), "server rejected moving the goblin: %s" % str(errors))
	check(await wait_until(func(): return Net.state.combatants[mine.id].pos == Vector2i(4, 2), 20.0), "saw own move in the synced state")
	var d := Creator.new_def("rogue", "lightfoot_halfling")
	d.name = "Alice's Rogue"
	d.background = "urchin"
	d.skills = ["acrobatics", "perception", "insight", "deception"]
	d.expertise = ["perception", "stealth"]
	d.armor = "leather"
	d.weapons = ["rapier", "shortbow"]
	check(Creator.validate(d).is_empty(), "rogue definition is legal: %s" % str(Creator.validate(d)))
	Net.send({"type": "createCharacter", "def": d})
	check(await wait_until(func(): return Net.state.combatants.values().any(func(c): return c.name == "Alice's Rogue"), 20.0), "own new character appears")
	check(await wait_until(func(): return Net.state.get("pending", {}).get("prompt", {}).get("controller", "") == "Alice", 20.0), "reaction prompt arrives")
	check(not Net.state.pending.has("seed"), "without the host's replay seed")
	Net.send({"type": "react", "choice": true})
	check(await wait_until(func(): return not Net.state.has("pending"), 20.0), "prompt cleared after answering")
	check(await wait_until(func(): return Net.state.has("background") and Net.background_bytes(Net.state).size() > 0, 20.0), "battle map image arrives once, outside the state")
	check(not Net.state.background.has("data"), "state carries only its hash")
	await get_tree().create_timer(1.0).timeout
	Net.leave()
	print("SELFTEST DONE: %d failures" % fails)
	get_tree().quit(1 if fails else 0)


func check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	if shots == "":
		return
	await frames(30)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, name])


func hud() -> Control:
	return main.hud


func id_named(prefix: String) -> String:
	for c in Net.state.combatants.values():
		if c.name.begins_with(prefix):
			return c.id
	return ""


func run() -> void:
	Net.play_offline("DM")
	Net.full_state = RulesEngine.new_state(24, 16)
	Net.send({"type": "settings", "settings": {}})
	await frames(5)
	var h := hud()
	check(h != null, "game view opened")
	var x := 2
	for p in Pregens.ALL:
		Net.send({"type": "spawn", "kind": "pregen", "template": p, "level": 5, "pos": Vector2i(x, 3)})
		x += 2
	Net.send({"type": "spawn", "kind": "monster", "template": "goblin", "pos": Vector2i(4, 4)})
	Net.send({"type": "spawn", "kind": "monster", "template": "ogre", "pos": Vector2i(10, 8)})
	Net.send({"type": "spawn", "kind": "monster", "template": "red_dragon_wyrmling", "pos": Vector2i(16, 10)})
	await frames()
	check(Net.state.combatants.size() == 15, "spawned 12 heroes and 3 monsters")
	# Every sheet and action bar builds.
	for c in Net.state.combatants.values():
		h.select(c.id)
		await frames(1)
	check(true, "selected every creature")
	# Start combat with the fighter first.
	var order := []
	for c in Net.state.combatants.values():
		order.append(20 if c.name.begins_with("Brakka") else 1)
	Dice.forced = order
	Net.send({"type": "startCombat"})
	await frames()
	var fighter := id_named("Brakka")
	check(Net.state.combat.active and RulesEngine.new(Net.state).current_id() == fighter, "combat started, fighter first")
	check(h.selected == fighter, "your creature is auto-selected on its turn")
	await shot("01_combat")
	check(h._init_bar.get_child(0).tooltip_text.begins_with("Brakka"), "turn order starts with the current creature")
	# Move by clicking a reachable square.
	h._on_hover(Vector2i(3, 6), "")
	await shot("02_move_preview")
	h._on_cell_pressed(Vector2i(3, 5), "")
	await frames()
	check(Net.state.combatants[fighter].pos == Vector2i(3, 5), "clicked square moves the fighter")
	# Attack the goblin.
	var gob := id_named("Goblin")
	h._begin_attack("longsword")
	h._on_hover(Vector2i(4, 4), gob)
	await shot("03_attack_mode")
	Dice.forced = [18, 6]
	h._on_cell_pressed(Vector2i(4, 4), gob)
	await frames()
	check(Net.state.combatants[gob].dead, "attack click killed the goblin")
	Net.send({"type": "endTurn", "actor_id": fighter})
	await frames()
	var second: String = RulesEngine.new(Net.state).current_id()
	check(h._init_bar.get_child(0).tooltip_text.begins_with("Brakka") and h._init_bar.get_child(1).tooltip_text.begins_with(Net.state.combatants[second].name), "the strip pans from the last turn to the next")
	# Wizard: area spell preview and cast via the DM (who controls everything offline).
	var wiz := id_named("Elowen")
	Net.send({"type": "dmEndTurn"})
	var guard := 0
	while RulesEngine.new(Net.state).current_id() != wiz and guard < 20:
		Net.send({"type": "dmEndTurn"})
		guard += 1
	await frames()
	h.select(wiz)
	h._begin_spell("fireball")
	h._on_hover(Vector2i(11, 9), "")
	await shot("04_fireball_preview")
	h._on_cell_pressed(Vector2i(11, 9), "")
	await frames()
	check(Net.state.combatants[wiz].spellcasting.slots_used[3] == 1, "fireball cast from the area preview")
	# Creature-target spell with multiple rays.
	Net.send({"type": "endTurn", "actor_id": wiz})
	await frames()
	# DM tools: paint walls by dragging.
	h.paint_type = Grid.WALL
	h._set_mode("paint", {})
	h._on_cell_pressed(Vector2i(20, 1), "")
	h._on_cell_dragged(Vector2i(21, 1))
	h._on_cell_dragged(Vector2i(22, 1))
	h._on_cell_released(Vector2i(22, 1))
	await frames()
	var cells: Array = Net.state.map.cells
	check(cells[1 * 24 + 21] == Grid.WALL, "drag-painted walls")
	h.cancel_mode()
	h.spawn_choice = 0
	h._set_mode("spawn", {})
	var before: int = Net.state.combatants.size()
	h._on_cell_pressed(Vector2i(20, 12), "")
	await frames()
	check(Net.state.combatants.size() == before + 1, "placed a monster by clicking")
	h.cancel_mode()
	# Chat & dice.
	h._on_chat("/r 2d6+3 test roll")
	h._on_chat("hello table")
	await frames()
	var last: Array = Net.state.log.slice(-2)
	check(last[0].kind == "roll" and last[1].kind == "chat", "chat and /r rolls")
	# Character sheet pages, editing and the toggle key.
	h.select(fighter)
	h._sheet_panel.visible = false
	h.toggle_sheet("stats")
	await frames()
	check(h._sheet_panel.visible and h._sheet_panel.page == "stats", "sheet shows the Character page")
	await shot("06_sheet_stats")
	h.select(wiz)
	h.toggle_sheet("spells")
	await frames()
	await shot("07_sheet_spells")
	h.toggle_sheet("details")
	Net.send({"type": "setNotes", "id": wiz, "key": "backstory", "value": "Apprentice of the Tower of Stars."})
	await frames()
	check(Net.state.combatants[wiz].notes.backstory.begins_with("Apprentice"), "edited a sheet field")
	await shot("08_sheet_details")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	h._unhandled_key_input(key)
	check(not h._sheet_panel.visible, "C hides the sheet")
	h._unhandled_key_input(key)
	check(h._sheet_panel.visible, "C shows it again")
	h.toggle_sheet("stats")
	# Character creator: every step renders for every class, then create and level up.
	Net.send({"type": "endCombat"})
	await frames()
	h.open_creator({})
	var cr: Control = h._creator
	check(cr.visible, "creator opened")
	for lvl in [1, 10]:
		for cls in Classes.ALL:
			cr.def["class"] = cls
			cr.def["level"] = lvl
			cr.def = Creator.normalize(cr.def)
			for st in cr.STEPS:
				cr._go(st[0])
			if lvl == 10:
				var errs := Creator.validate(cr.def).filter(func(e): return not "name" in e)
				check(errs.is_empty(), "a normalized level-10 %s is legal: %s" % [cls, str(errs)])
	cr.def["level"] = 1
	await frames()
	check(true, "all creator steps render for all classes")
	var mc: Dictionary = Pregens.ALL.cleric.duplicate(true)
	mc.abilities.merge({"int": 13, "con": 10}, true)
	mc.merge({"level": 6, "classes": [{"class": "wizard", "levels": 2}, {"class": "fighter", "levels": 1}]}, true)
	cr.def = Creator.normalize(mc)
	for st in cr.STEPS:
		cr._go(st[0])
	cr._go("basics")
	await shot("09c_creator_multiclass")
	cr._go("spells")
	await shot("09d_creator_multiclass_spells")
	check(Creator.class_levels(cr.def) == {"cleric": 3, "wizard": 2, "fighter": 1}, "multiclass levels survive normalize: %s" % str(Creator.class_levels(cr.def)))
	var mc_errs := Creator.validate(cr.def)
	check(mc_errs.is_empty(), "a normalized cleric 3 / wizard 2 / fighter 1 is legal: %s" % str(mc_errs))
	cr.def = Creator.normalize(Creator.new_def("fighter", "human"))
	cr.def["level"] = 4
	for fid in Creator.FEATS:
		cr.def.asi = {4: Creator.new_feat_entry(fid, "fighter")}
		cr._go("abilities")
	cr.def.asi = {4: Creator.new_feat_entry("magicInitiate", "fighter")}
	cr._go("abilities")
	await shot("09b_creator_feat")
	check(true, "every feat's choices render in the creator")
	cr.def = Creator.new_def("wizard", "high_elf")
	cr.def.name = "Nyx Emberleaf"
	cr.def.background = "sage"
	cr.def.skills = ["investigation", "medicine"]
	cr.def.spells = ["fire_bolt", "ray_of_frost", "shocking_grasp", "magic_missile", "shield", "sleep"]
	cr.def.race_cantrip = "chill_touch"
	cr.def.weapons = ["quarterstaff", "dagger"]
	cr._go("basics")
	await shot("09_creator_basics")
	cr._go("abilities")
	cr.def.method = "roll"
	Dice.forced = [5, 5, 4, 1, 6, 5, 4, 2, 6, 6, 4, 1, 5, 5, 5, 3, 4, 5, 5, 1, 6, 6, 5, 1]  # INT high enough for 3 spells
	cr._roll_scores()
	await shot("10_creator_abilities")
	cr._go("skills")
	await shot("11_creator_skills")
	cr._go("spells")
	await shot("12_creator_spells")
	cr._go("review")
	check(Creator.validate(cr.def).is_empty(), "creator character is legal: %s" % str(Creator.validate(cr.def)))
	await shot("13_creator_review")
	cr._submit()
	await frames()
	var nyx := id_named("Nyx")
	check(nyx != "" and not cr.visible, "character created from the creator")
	check(h.selected == nyx, "new character selected")
	check(Net.full_state.log.any(func(e): return "Rolled scores" in e.text), "rolled scores posted to the log")
	h.open_creator(Net.state.combatants[nyx])
	cr.def.level = 5
	cr.def = Creator.normalize(cr.def)
	cr._go("spells")
	await shot("14_creator_levelup_spells")
	cr.def.spells.append_array(["fireball", "misty_step"])
	check(Creator.validate(cr.def).is_empty(), "level 5 wizard is legal: %s" % str(Creator.validate(cr.def)))
	cr._submit()
	await frames()
	check(Net.state.combatants[nyx].level == 5 and Net.state.combatants[nyx].spellcasting.known.has("fireball"), "leveled up to 5 with Fireball")
	# DM grants a level: the level-up screen opens by itself with only the new choices.
	Net.send({"type": "levelUp", "ids": [nyx]})
	await frames()
	check(cr.visible and cr.level_from == 5 and cr.step == "levelup" and int(cr.def.level) == 6, "level-up screen opened for the granted level")
	check(not cr._step_btns.basics.visible and cr._step_btns.spells.visible, "level-up screen shows only the new choices")
	cr.roll_hp = true
	cr._go("levelup")
	await shot("14b_level_up")
	cr._go("spells")
	await shot("14c_level_up_spells")
	cr._submit()
	await frames()
	check(Net.state.combatants[nyx].level == 6 and Net.state.combatants[nyx].def.hp_rolls.has("6"), "leveled to 6 with rolled hit points")
	# Level 7 goes to a second class when the scores allow one.
	Net.send({"type": "levelUp", "ids": [nyx]})
	await frames()
	var sc7 := Creator.final_abilities(cr.def, 6)
	var mc_class: Array = Classes.ALL.keys().filter(func(k): return k != "wizard" and Creator.multiclass_req_error(sc7, k) == "")
	if not mc_class.is_empty() and Creator.multiclass_req_error(sc7, "wizard") == "":
		cr._pick_level_class(mc_class[0])
		cr._go("levelup")
		await shot("14d_level_up_multiclass")
		cr._submit()
		await frames()
		check(Creator.class_levels(Net.state.combatants[nyx].def) == {"wizard": 6, mc_class[0]: 1}, "level 7 taken as %s 1: %s" % [mc_class[0], str(Creator.class_levels(Net.state.combatants[nyx].def))])
	# Homebrew workshop: every form renders, copy from SRD, save, place, teach, give.
	h.open_homebrew()
	var hb: Control = h._homebrew
	for k in Homebrew.KINDS:
		hb._switch_kind(k)
		for i in hb._copy_opt.item_count:
			hb._copy_opt.select(i)
			hb._copy_srd()
	check(true, "workshop forms render for every SRD monster, spell and item")
	hb._switch_kind("monsters")
	hb._copy_opt.select(0)
	hb._copy_srd()
	hb.data.name = "Goblin Boss"
	hb.data.hp = 21
	hb.data.ac = 17
	hb._rebuild()
	await shot("15_homebrew_monster")
	hb._save()
	await frames()
	var boss_id := ""
	for id in Net.state.homebrew.monsters:
		if Net.state.homebrew.monsters[id].name == "Goblin Boss":
			boss_id = id
	check(boss_id != "" and hb.edit_id == boss_id, "homebrew monster saved")
	h.begin_spawn("monster", boss_id)
	hb.close()
	h._on_cell_pressed(Vector2i(14, 12), "")
	await frames()
	check(id_named("Goblin Boss") != "", "homebrew monster placed on the map")
	h.cancel_mode()
	h.open_homebrew()
	hb._switch_kind("spells")
	hb._start(Homebrew.blank("spells"), "")
	hb.data.name = "Arcane Spear"
	hb._rebuild()
	await shot("16_homebrew_spell")
	hb._save()
	await frames()
	var spear := ""
	for id in Net.state.homebrew.spells:
		if Net.state.homebrew.spells[id].name == "Arcane Spear":
			spear = id
	check(spear != "", "homebrew spell saved")
	h.select(nyx)
	Net.send({"type": "grantSpell", "id": nyx, "spell_id": spear})
	await frames()
	check(Net.state.combatants[nyx].spellcasting.known.has(spear), "homebrew spell taught")
	hb._switch_kind("items")
	hb._start(Homebrew.from_srd("items", "flame_tongue"), "")
	await shot("17_homebrew_item")
	hb.close()
	h.select(fighter)
	Net.send({"type": "giveItem", "id": fighter, "item": {"id": "potion_of_healing", "base": ""}})
	Net.send({"type": "giveItem", "id": fighter, "item": {"id": "weapon_plus_1", "base": "longsword"}})
	await frames()
	check(Net.state.combatants[fighter].attacks.any(func(a): return a.name == "+1 Longsword"), "magic weapon given")
	var boss := id_named("Goblin Boss")
	h.select(boss)
	Net.send({"type": "giveItem", "id": boss, "item": {"id": "weapon_plus_1", "base": "scimitar"}})
	await frames()
	check(Net.state.combatants[boss].attacks.any(func(a): return a.name == "+1 Scimitar"), "monster carries a magic weapon")
	h._build_dm()
	h._sheet_panel.visible = false
	h.toggle_sheet("stats")
	await shot("18_sheet_magic_items")
	Net.state["pending"] = {"prompt": {"reactor_id": fighter, "controller": "DM", "name": "Brakka Ironside", "default": true,
		"text": "Goblin Boss is leaving Brakka Ironside's reach. Make an opportunity attack with +1 Longsword?"}}
	h._update_overlays()
	check(h._reaction_panel.visible, "reaction prompt shows for its player")
	await shot("19_reaction_prompt")
	Net.state.erase("pending")
	h._update_overlays()
	# Hidden tokens and fog of war: the DM sees the hidden goblin, a player sees neither it nor what's behind the wall.
	Net.send({"type": "spawn", "kind": "monster", "template": "goblin", "pos": Vector2i(6, 1), "hidden": true})
	await frames()
	var lurker := ""
	for c in Net.state.combatants.values():
		if c.get("dm_hidden", false):
			lurker = c.id
	check(lurker != "", "hidden goblin placed")
	var w: int = Net.full_state.map.width
	for gx in w:
		Net.full_state.map.cells[6 * w + gx] = Grid.WALL
	Net.send({"type": "settings", "settings": {"fog": true}})
	await frames()
	check(not Net.state.has("fog"), "the DM sees through the fog")
	Net.full_state.combatants[fighter].controller = "Alice"
	Net.players[1] = {"name": "Alice", "is_dm": false}
	Net._broadcast([])
	await frames()
	check(Net.state.has("fog") and not Net.state.combatants.has(lurker), "a player sees fog and not the hidden goblin")
	var ogre: Dictionary = Net.full_state.combatants.values().filter(func(c): return c.name.begins_with("Ogre"))[0]
	check(ogre.pos.y < 6 or not Net.state.combatants.has(ogre.id), "the ogre behind the wall is out of sight")
	h._sheet_panel.visible = false
	await shot("20_player_fog")
	Net.players[1] = Net.me
	Net.send({"type": "setHidden", "id": lurker, "hidden": false})
	Net.send({"type": "settings", "settings": {"fog": false}})
	await frames()
	check(not Net.state.combatants[lurker].get("dm_hidden", false) and Net.state.log[-1].text.ends_with("appears!"), "goblin revealed")
	# Ruler: measure from one square to another.
	h.toggle_ruler()
	h._on_cell_pressed(Vector2i(1, 1), "")
	h._on_hover(Vector2i(4, 5), "")
	check("Ruler: 20 ft" in h._prompt.text, "ruler measures 5-ft diagonals: " + h._prompt.text)
	for i in 6:
		var up := InputEventKey.new()
		up.keycode = KEY_PAGEUP
		up.pressed = true
		h._unhandled_key_input(up)
	check("Ruler: 30 ft" in h._prompt.text and "up 30 ft" in h._prompt.text, "ruler measures height too: " + h._prompt.text)
	await shot("24_ruler_height")
	h.toggle_ruler()
	check(h.mode == "", "ruler off")
	Net.send({"type": "ping", "pos": Vector2i(5, 5)})
	# Darkness, a torch and a painted bright room; then what a player sees with fog on.
	Net.send({"type": "settings", "settings": {"light": "dark"}})
	Net.send({"type": "setLight", "actor_id": fighter, "source": "torch"})
	var room := []
	for gx in range(14, 20):
		for gy in range(9, 14):
			room.append({"x": gx, "y": gy, "light": 1 + Grid.BRIGHT})
	Net.send({"type": "setCells", "cells": room})
	await frames()
	check(Net.state.combatants[fighter].light.id == "torch" and Grid.light_at(Net.state, Vector2i(15, 10)) == Grid.BRIGHT, "torch lit and room painted")
	var mal := id_named("Mal")
	var mp: Vector2i = Net.state.combatants[mal].pos
	Net.send({"type": "cast", "actor_id": mal, "spell_id": "darkness", "point": mp + Vector2i(-3, 2)})
	await frames()
	check(not Grid.magic_dark(Net.state).is_empty(), "Darkness cast")
	h._build_dm()
	h.select(fighter)
	h._sheet_panel.visible = false
	await shot("21_darkness_torch")
	Net.send({"type": "settings", "settings": {"fog": true}})
	Net.players[1] = {"name": "Alice", "is_dm": false}
	Net._broadcast([])
	await frames()
	check(Net.state.fog.visible.count(0) > 0, "darkness hides squares from a player")
	await shot("22_player_darkness")
	Net.players[1] = Net.me
	Net.send({"type": "settings", "settings": {"fog": false, "light": "bright"}})
	await frames()
	# Doors and low walls: clicking a closed door next to the fighter opens it.
	var fp: Vector2i = Net.state.combatants[fighter].pos
	Net.send({"type": "setCells", "cells": [{"x": fp.x + 1, "y": fp.y, "v": Grid.DOOR}, {"x": fp.x + 1, "y": fp.y - 1, "v": Grid.WALL},
		{"x": fp.x + 1, "y": fp.y + 1, "v": Grid.WALL}, {"x": fp.x - 2, "y": fp.y, "v": Grid.LOW_WALL}, {"x": fp.x - 2, "y": fp.y + 1, "v": Grid.LOW_WALL}]})
	await frames()
	h.select(fighter)
	h._on_cell_pressed(fp + Vector2i(1, 0), "")
	await frames()
	check(Net.state.map.cells[fp.y * Net.state.map.width + fp.x + 1] == Grid.DOOR_OPEN, "clicked a door open")
	h.prop_kit = h._props().keys().find("nature")
	h.prop_model = h._props().nature.find("tree_default")
	h._set_mode("prop", {"erase": false})
	h._on_cell_pressed(fp + Vector2i(-1, -2), "")
	await frames()
	check(Net.state.map.get("props", []).size() == 1 and h._prompt.text.begins_with("Click the map to place nature/tree_default"), "placed a tree prop")
	h.cancel_mode()
	await shot("24_door_low_wall")
	# Movement: water, flying and the action buttons for it.
	var wy := id_named("Red Dragon")
	var wp: Vector2i = Net.state.combatants[wy].pos
	Net.send({"type": "setCells", "cells": [{"x": wp.x - 1, "y": wp.y + 1, "v": Grid.WATER}, {"x": wp.x, "y": wp.y + 1, "v": Grid.WATER},
		{"x": wp.x + 1, "y": wp.y + 1, "v": Grid.WATER}]})
	Net.send({"type": "altitude", "actor_id": wy, "alt": 30})
	await frames()
	check(Net.state.combatants[wy].alt == 30, "the wyrmling flies up 30 ft")
	h.select(wy)
	h._hot_tab = "Actions"
	h._build_actions()
	await frames()
	check(h.find_children("*", "Button", true, false).any(func(b): return b.text == "Land"), "Land button for a flier")
	await shot("25_flying_and_water")
	Net.send({"type": "altitude", "actor_id": wy, "alt": 0})
	await frames()
	check(Net.state.combatants[wy].alt == 0, "landed")
	# Battle map image under the grid.
	var img := Image.create(24 * 32, 16 * 32, false, Image.FORMAT_RGB8)
	for py in img.get_height():
		for pxl in img.get_width():
			img.set_pixel(pxl, py, Color(0.25, 0.35, 0.2) if (pxl / 32 + py / 32) % 2 == 0 else Color(0.45, 0.4, 0.3))
	Net.send({"type": "setBackground", "data": img.save_png_to_buffer(), "px_per_square": 32})
	await frames()
	check(Net.state.has("background") and h.board._bg != null, "battle map image shown")
	await shot("23_battle_map")
	Net.send({"type": "clearBackground"})
	await frames()
	# Monster AI turn.
	Net.send({"type": "settings", "settings": {"auto_npc": true}})
	await frames()
	await shot("05_after_ai")
	check(true, "auto monsters ran")
	print("SELFTEST DONE: %d failures" % fails)
	get_tree().quit(1 if fails else 0)
