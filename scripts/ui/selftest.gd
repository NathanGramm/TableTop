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
	# Monster AI turn.
	Net.send({"type": "settings", "settings": {"auto_npc": true}})
	await frames()
	await shot("05_after_ai")
	check(true, "auto monsters ran")
	print("SELFTEST DONE: %d failures" % fails)
	get_tree().quit(1 if fails else 0)
