extends Control
## In-game interface: initiative tracker, character sheet, action bar, log/chat and DM tools.
## Also the input controller: it decides what a click on the board means in the current mode.

const SheetScript := preload("res://scripts/ui/character_sheet.gd")
const CreatorScript := preload("res://scripts/ui/creator_panel.gd")
const HomebrewScript := preload("res://scripts/ui/homebrew_panel.gd")
const RAIL_W := 96
const PREFS := "user://prefs.cfg"
const SPELL_LEVEL_NAMES := ["Cantrips", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"]
const LOG_COLORS := {"turn": "f2c66d", "attack": "f0e6d2", "damage": "ff8a7a", "heal": "8fe39a", "roll": "c9b8ff",
	"chat": "ffffff", "death": "ff5a5a", "spell": "b0a0ff", "system": "9aa7b8", "info": "d8cfc0"}

var main: Node
var board: Node3D
var state: Dictionary = {}
var eng: RulesEngine
var selected := ""
var mode := ""             # "", attack, spell, power, target, paint, spawn, teleport
var mode_data: Dictionary = {}
var picked: Array = []
var opts := {"bonus": false, "power": false, "reckless": false, "smite": 0, "stunning": false, "open_hand": "", "slot": 0, "quickened": false, "careful": false, "heightened": false}
var paint_type := Grid.WALL  # terrain, or LIGHT_BRUSH + painted light value
const LIGHT_BRUSH := 10
var painting: Dictionary = {}
var spawn_choice := 0
var spawn_level := 3
var spawn_side := 1
var spawn_count := 1
var spawn_hidden := false
var map_px_per_square := 70
var dm_amount := 5
var dm_dc := 13
var dm_roll_choice := 0

var _init_bar: HBoxContainer
var _round_label: Label
var _top_buttons: HBoxContainer
var _sheet_panel: PanelContainer
var _creator: Control
var _homebrew: Control
var _give_choice := 0
var _give_base := 0
var _grant_choice := 0
var _expect_name := ""
var _rail: PanelContainer
var _rail_btns := {}
var _action_box: VBoxContainer
var _action_panel: PanelContainer
var _log: RichTextLabel
var _chat: LineEdit
var _tabs: TabContainer
var _dm_scroll: ScrollContainer
var _dm_box: VBoxContainer
var _party_box: VBoxContainer
var _prompt_panel: PanelContainer
var _prompt: Label
var _prompt_btns: HBoxContainer
var _toast: Label
var _toast_tween: Tween
var _reaction_panel: PanelContainer
var _reaction_text: Label
var _reaction_clock: Label
var _pending_key := ""
var _pending_since := 0.0
var _last_log_id := -1
var _hover_cell := Vector2i(-999, -999)
var _hover_token := ""
var _spawn_options: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.make_theme()
	if not InputMap.has_action("toggle_sheet"):
		InputMap.add_action("toggle_sheet")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_C
		InputMap.action_add_event("toggle_sheet", ev)
	_build_layout()
	Net.state_changed.connect(_on_state)
	Net.error_received.connect(func(msg):
		show_toast(msg, true)
		if not state.is_empty():
			_refresh_panels())  # put controls like the Light picker back to the real state
	Net.players_changed.connect(func(): if not state.is_empty(): _refresh_panels())
	Net.status_changed.connect(func(_s, detail): show_toast(detail))
	_rebuild_spawn_options()


## Built-in monsters, the campaign's homebrew monsters, then pregenerated heroes.
func _rebuild_spawn_options() -> void:
	_spawn_options = []
	for m in Homebrew.monsters:
		var hm: Dictionary = Homebrew.monsters[m]
		_spawn_options.append({"kind": "monster", "id": m, "label": "★ %s (CR %s)" % [hm.name, Monsters.cr_label(float(hm.cr))]})
	for m in Monsters.ALL:
		_spawn_options.append({"kind": "monster", "id": m, "label": "%s (CR %s)" % [Monsters.ALL[m].name, Monsters.cr_label(Monsters.ALL[m].cr)]})
	for p in Pregens.ALL:
		_spawn_options.append({"kind": "pregen", "id": p, "label": "%s — %s" % [Pregens.ALL[p].name, Classes.ALL[p].name]})
	spawn_choice = clampi(spawn_choice, 0, _spawn_options.size() - 1)


func _spawn_target() -> Dictionary:
	if mode_data.has("id"):
		return mode_data
	return _spawn_options[spawn_choice]


## Enter placement mode for a specific creature (used by the homebrew workshop).
func begin_spawn(kind: String, template: String) -> void:
	var label: String = Monsters.get_monster(template).get("name", template) if kind == "monster" else Pregens.ALL.get(template, {}).get("name", template)
	spawn_side = 1 if kind == "monster" else 0
	_set_mode("spawn", {"kind": kind, "id": template, "label": label})


func open_homebrew() -> void:
	if _homebrew == null:
		_homebrew = HomebrewScript.new()
		_homebrew.hud = self
		add_child(_homebrew)
	_homebrew.open()


func attach_board(b: Node3D) -> void:
	board = b
	board.cell_pressed.connect(_on_cell_pressed)
	board.cell_dragged.connect(_on_cell_dragged)
	board.cell_released.connect(_on_cell_released)
	board.cancel_pressed.connect(cancel_mode)
	board.hover_changed.connect(_on_hover)


# ---------------- Layout ----------------

func _build_layout() -> void:
	var top = UiKit.panel()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8
	top.offset_right = -8
	top.offset_top = 6
	top.custom_minimum_size.y = 52
	add_child(top)
	var th = UiKit.hbox(10)
	top.add_child(th)
	_round_label = UiKit.label("", 18, UiKit.GOLD)
	_round_label.custom_minimum_size.x = 120
	th.add_child(_round_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	th.add_child(scroll)
	_init_bar = UiKit.hbox(4)
	scroll.add_child(_init_bar)
	_top_buttons = UiKit.hbox(6)
	th.add_child(_top_buttons)

	_rail = UiKit.panel()
	_rail.offset_left = 8
	_rail.offset_top = 66
	_rail.offset_right = 8 + RAIL_W
	add_child(_rail)
	var rv := UiKit.vbox(6)
	_rail.add_child(rv)
	var rail_cap := UiKit.label("SHEET\n[C]", 11, UiKit.MUTED)
	rail_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(rail_cap)
	for p in SheetScript.PAGES:
		var b := UiKit.button(SheetScript.PAGE_TITLES[p], func(): toggle_sheet(p), "Show or hide the %s page" % SheetScript.PAGE_TITLES[p].to_lower())
		b.custom_minimum_size.x = RAIL_W - 16
		_rail_btns[p] = b
		rv.add_child(b)

	_sheet_panel = SheetScript.new()
	_sheet_panel.hud = self
	_sheet_panel.offset_left = 8 + RAIL_W + 8
	_sheet_panel.offset_top = 66
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	_sheet_panel.visible = cfg.get_value("hud", "sheet_visible", true)
	_sheet_panel.page = cfg.get_value("hud", "sheet_page", "stats")
	add_child(_sheet_panel)
	get_viewport().size_changed.connect(_layout_side)

	var right = UiKit.panel()
	right.anchor_left = 1
	right.anchor_right = 1
	right.anchor_top = 0
	right.anchor_bottom = 1
	right.offset_left = -378
	right.offset_right = -8
	right.offset_top = 66
	right.offset_bottom = -8
	add_child(right)
	_tabs = TabContainer.new()
	right.add_child(_tabs)
	var log_page = UiKit.vbox(6)
	log_page.name = "Log"
	_tabs.add_child(log_page)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_page.add_child(_log)
	_chat = LineEdit.new()
	_chat.placeholder_text = "Chat, or /r 1d20+5 to roll (/pr for a private roll)"
	_chat.text_submitted.connect(_on_chat)
	log_page.add_child(_chat)
	_dm_scroll = ScrollContainer.new()
	_dm_scroll.name = "DM"
	_dm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(_dm_scroll)
	_dm_box = UiKit.vbox(8)
	_dm_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dm_scroll.add_child(_dm_box)
	var party_scroll := ScrollContainer.new()
	party_scroll.name = "Table"
	_tabs.add_child(party_scroll)
	_party_box = UiKit.vbox(6)
	_party_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.add_child(_party_box)

	_action_panel = UiKit.panel()
	_action_panel.anchor_left = 0
	_action_panel.anchor_right = 1
	_action_panel.anchor_top = 1
	_action_panel.anchor_bottom = 1
	_action_panel.offset_left = 8 + RAIL_W + 8
	_action_panel.offset_right = -388
	_action_panel.offset_bottom = -8
	_action_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_action_panel)
	_action_panel.resized.connect(_layout_side)
	_action_panel.visibility_changed.connect(_layout_side)
	_action_box = UiKit.vbox(6)
	_action_panel.add_child(_action_box)

	_prompt_panel = UiKit.panel()
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.offset_top = 70
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.visible = false
	add_child(_prompt_panel)
	var ph = UiKit.hbox(10)
	_prompt_panel.add_child(ph)
	_prompt = UiKit.label("", 16, UiKit.GOLD)
	ph.add_child(_prompt)
	_prompt_btns = UiKit.hbox(6)
	ph.add_child(_prompt_btns)

	_reaction_panel = UiKit.panel()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.12, 0.08, 0.06, 0.98)
	rsb.border_color = UiKit.GOLD
	rsb.set_border_width_all(2)
	rsb.set_corner_radius_all(8)
	rsb.set_content_margin_all(14)
	_reaction_panel.add_theme_stylebox_override("panel", rsb)
	_reaction_panel.anchor_left = 0.5
	_reaction_panel.anchor_right = 0.5
	_reaction_panel.anchor_top = 0.35
	_reaction_panel.anchor_bottom = 0.35
	_reaction_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reaction_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_reaction_panel.custom_minimum_size.x = 460
	_reaction_panel.visible = false
	add_child(_reaction_panel)
	var react_box := UiKit.vbox(10)
	_reaction_panel.add_child(react_box)
	react_box.add_child(UiKit.label("Reaction!", 20, UiKit.GOLD))
	_reaction_text = UiKit.label("", 16)
	_reaction_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reaction_text.custom_minimum_size.x = 430
	react_box.add_child(_reaction_text)
	var rb := UiKit.hbox(10)
	var yes := UiKit.button("Yes, react", func(): send({"type": "react", "choice": true}))
	yes.modulate = UiKit.GOLD
	rb.add_child(yes)
	rb.add_child(UiKit.button("No", func(): send({"type": "react", "choice": false})))
	_reaction_clock = UiKit.label("", 13, UiKit.MUTED)
	rb.add_child(_reaction_clock)
	react_box.add_child(rb)

	_toast = UiKit.label("", 17, Color.WHITE)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 118
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.modulate.a = 0.0
	add_child(_toast)


func show_toast(text: String, bad: bool = false) -> void:
	if text == "":
		return
	_toast.text = text
	_toast.add_theme_color_override("font_color", UiKit.RED if bad else UiKit.PARCHMENT)
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5 if bad else 3.5)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


# ---------------- State ----------------

func _on_state(events: Array) -> void:
	var first := state.is_empty()
	state = Net.state
	eng = RulesEngine.new(state)
	if selected != "" and not state.combatants.has(selected):
		selected = ""
	# Auto-select your creature when its turn comes up.
	var cur := eng.current_id()
	var new_turn := first
	for ev in events:
		if ev.kind == "turn":
			new_turn = true
	if cur != "" and new_turn:
		var c := eng.get_c(cur)
		if can_control(c) and (not Net.me.is_dm or c.kind == "npc" or c.controller == "" or c.controller == Net.me.name):
			selected = cur
			if mode in ["attack", "spell", "power", "target"]:
				cancel_mode()
			board.focus_on(cur)
	if first:
		board.center_camera(state.map)
		if selected == "":
			for c in state.combatants.values():
				if c.controller == Net.me.name:
					selected = c.id
					break
	if _expect_name != "":
		for c in state.combatants.values():
			if c.name == _expect_name and (c.controller == Net.me.name or (Net.me.is_dm and c.controller == "")):
				selected = c.id
				_expect_name = ""
				board.focus_on(c.id)
				if not _sheet_panel.visible:
					toggle_sheet("stats")
				break
	if mode == "attack" and not _attack_mode_still_valid():
		cancel_mode()
	board.sync(state, eng, selected, picked, events)
	_refresh_panels()


func _refresh_panels() -> void:
	if state.is_empty():
		return
	_build_top()
	_build_sheet()
	_build_actions()
	_build_dm()
	_build_party()
	_update_log()
	_update_overlays()
	_layout_side()
	if _homebrew != null and _homebrew.visible:
		_homebrew.refresh()


func sel() -> Dictionary:
	return eng.get_c(selected) if eng else {}


func can_control(c: Dictionary) -> bool:
	return not c.is_empty() and (Net.me.is_dm or c.controller == Net.me.name)


func can_act_now(c: Dictionary) -> bool:
	return can_control(c) and not c.dead and (not eng.in_combat() or eng.current_id() == c.id)


func send(cmd: Dictionary) -> void:
	Net.send(cmd)


func select(id: String) -> void:
	selected = id
	if mode in ["attack", "spell", "power", "target"]:
		cancel_mode()
	board.sync(state, eng, selected, picked, [])
	_refresh_panels()


# ---------------- Top bar ----------------

func _build_top() -> void:
	UiKit.clear(_init_bar)
	UiKit.clear(_top_buttons)
	if eng.in_combat():
		_round_label.text = "Round %d" % state.combat.round
		for id in state.combat.order:
			var c := eng.get_c(id)
			if c.is_empty():
				continue
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.text = "%d  %s" % [c.initiative, c.name]
			b.tooltip_text = "%s\n%s" % [c.name, c.description]
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.14, 0.12, 0.12)
			sb.set_corner_radius_all(4)
			sb.set_content_margin_all(5)
			sb.border_width_bottom = 3
			sb.border_color = Color(0.25, 0.55, 0.95) if c.side == "party" else (Color(0.9, 0.25, 0.2) if c.side == "enemy" else Color(0.8, 0.7, 0.3))
			if id == eng.current_id():
				sb.bg_color = Color(0.4, 0.3, 0.12)
				sb.set_border_width_all(2)
				sb.border_color = UiKit.GOLD
			if c.dead:
				b.modulate = Color(1, 1, 1, 0.4)
			elif c.hp <= 0:
				b.modulate = Color(1, 0.6, 0.6, 0.8)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.pressed.connect(func():
				select(id)
				board.focus_on(id))
			_init_bar.add_child(b)
			if id == eng.current_id():
				_scroll_to_current.call_deferred(b)
	else:
		_round_label.text = "Exploring"
		_init_bar.add_child(UiKit.label("Out of combat — move freely." + (" Press Start Combat to roll initiative." if Net.me.is_dm else ""), 15, UiKit.MUTED))
	if Net.me.is_dm:
		if eng.in_combat():
			_top_buttons.add_child(UiKit.button("Next Turn", func(): send({"type": "dmEndTurn"}), "End the current creature's turn"))
			_top_buttons.add_child(UiKit.button("End Combat", func(): send({"type": "endCombat"})))
		else:
			_top_buttons.add_child(UiKit.button("Start Combat", func(): send({"type": "startCombat"}), "Roll initiative for everyone on the map"))
	_top_buttons.add_child(UiKit.button("Ruler", toggle_ruler, "Measure distances (R). Alt+click the map to ping it for everyone."))
	_top_buttons.add_child(UiKit.button("New Character", func(): open_creator({}), "Create a character (you'll control it)"))
	_top_buttons.add_child(UiKit.button("Leave", func(): main.leave_game(), "Back to the main menu"))


func _process(_delta: float) -> void:
	if _reaction_panel != null and _reaction_panel.visible:
		var left := maxi(0, int(ceil(Net.REACTION_SECONDS - (Time.get_ticks_msec() / 1000.0 - _pending_since))))
		_reaction_clock.text = "%ds to decide" % left


func _scroll_to_current(b: Control) -> void:
	if is_instance_valid(b) and b.is_inside_tree():
		(_init_bar.get_parent() as ScrollContainer).ensure_control_visible(b)


# ---------------- Character sheet ----------------

func _build_sheet() -> void:
	if _sheet_panel.visible:
		_sheet_panel.refresh()
	for p in _rail_btns:
		_rail_btns[p].modulate = UiKit.GOLD if _sheet_panel.visible and _sheet_panel.page == p else Color.WHITE


## Show/hide the character sheet. With a page name, switches to that page (or hides it if it's
## already showing). Bound to the `toggle_sheet` input action (C by default).
func toggle_sheet(p: String = "") -> void:
	if p == "" or (_sheet_panel.visible and _sheet_panel.page == p):
		_sheet_panel.visible = not _sheet_panel.visible if p == "" else false
	else:
		_sheet_panel.visible = true
		_sheet_panel.page = p
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("hud", "sheet_visible", _sheet_panel.visible)
	cfg.set_value("hud", "sheet_page", _sheet_panel.page)
	cfg.save(PREFS)
	_layout_side()
	if not state.is_empty():
		_build_sheet()


## The sheet sits beside the rail, above the action bar, and never under the log panel.
func _layout_side() -> void:
	if _sheet_panel == null:
		return
	var vs := get_viewport_rect().size
	var left := 8.0 + RAIL_W + 8.0
	var width := clampf(vs.x - 388.0 - 10.0 - left, 520.0, 1000.0)
	var bottom := vs.y - 8.0
	if _action_panel.visible:
		bottom = vs.y - 8.0 - _action_panel.size.y - 8.0
	_sheet_panel.offset_left = left
	_sheet_panel.offset_right = left + width
	_sheet_panel.offset_top = 66
	_sheet_panel.offset_bottom = maxf(66.0 + 240.0, bottom)


## Opens the character creator; pass a combatant to edit or level it up.
func open_creator(c: Dictionary) -> void:
	if _creator == null:
		_creator = CreatorScript.new()
		_creator.hud = self
		add_child(_creator)
	_creator.visible = true
	if c.is_empty():
		_creator.open_new()
	else:
		_creator.open_edit(c)


func creator_closed() -> void:
	pass


func creator_open() -> bool:
	return _creator != null and _creator.visible


func expect_new_character(char_name: String) -> void:
	_expect_name = char_name


func can_edit_build(c: Dictionary) -> bool:
	return not c.is_empty() and c.kind == "pc" and c.has("def") and can_control(c) and not c.get("redacted", false)


func _build_dm_items(c: Dictionary) -> void:
	var items: Array = c.get("items", [])
	for i in items.size():
		var r := UiKit.hbox()
		r.add_child(UiKit.label("• " + Items.display_name(items[i]), 13))
		r.add_child(UiKit.button("Take", func(): send({"type": "takeItem", "id": c.id, "index": i}), "Remove this item"))
		_dm_box.add_child(r)
	var ids := Items.all_ids()
	_give_choice = clampi(_give_choice, 0, ids.size() - 1)
	var r2 := UiKit.hbox()
	var io := UiKit.option(ids.map(func(id): return ("★ " if Homebrew.items.has(id) else "") + Items.get_item(id).name), _give_choice)
	io.item_selected.connect(func(i):
		_give_choice = i
		_give_base = 0
		_build_dm())
	r2.add_child(io)
	var choices := Items.base_choices(Items.get_item(ids[_give_choice]))
	if not choices.is_empty():
		_give_base = clampi(_give_base, 0, choices.size() - 1)
		var bo := UiKit.option(choices.map(func(ch): return Equipment.WEAPONS.get(ch, Equipment.ARMOR.get(ch, {})).get("name", str(ch).capitalize())), _give_base)
		bo.item_selected.connect(func(i): _give_base = i)
		r2.add_child(bo)
	r2.add_child(UiKit.button("Give item", func():
		send({"type": "giveItem", "id": c.id, "item": {"id": ids[_give_choice], "base": choices[_give_base] if not choices.is_empty() else ""}})))
	_dm_box.add_child(r2)


func cast_from_sheet(spell_id: String) -> void:
	var c := sel()
	if not can_act_now(c):
		show_toast(Spells.get_spell(spell_id).get("desc", ""))
		return
	var sp := Spells.get_spell(spell_id)
	var err := eng.cast_error(c, sp, _slot_for(c, sp), _cast_opts())
	if err != "":
		show_toast(err, true)
		return
	_begin_spell(spell_id)


func _dmg_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	for d in a.damage:
		var dice: String = d.get("dice", "")
		var b: int = d.get("bonus", 0)
		parts.append("%s%s %s" % [dice, (Dice.fmt_mod(b) if dice != "" else str(b)) if b != 0 or dice == "" else "", d.type])
	return " + ".join(parts) if not parts.is_empty() else "special"


func _on_sheet_meta(meta) -> void:
	var c := sel()
	if c.is_empty():
		return
	var s := str(meta)
	if s == "drop":
		send({"type": "feature", "actor_id": c.id, "feature": "endConcentration"})
	elif s.begins_with("save:") or s.begins_with("skill:"):
		var bonus := eng.save_mod(c, s.substr(5)) if s.begins_with("save:") else eng.skill_mod(c, s.substr(6))
		var label := (s.substr(5).to_upper() + " save") if s.begins_with("save:") else Stats.skill_label(s.substr(6))
		send({"type": "roll", "expr": "1d20%s" % Dice.fmt_mod(bonus), "label": "%s — %s" % [c.name, label]})


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


# ---------------- Action bar ----------------

func _build_actions() -> void:
	UiKit.clear(_action_box)
	var c := sel()
	if c.is_empty() or not can_control(c) or c.get("redacted", false):
		_action_panel.visible = false
		return
	_action_panel.visible = true
	var turn: Dictionary = c.turn
	var econ := RichTextLabel.new()
	econ.bbcode_enabled = true
	econ.fit_content = true
	econ.scroll_active = false
	econ.custom_minimum_size.x = 400
	var dot := func(on: bool) -> String: return "[color=#8fe39a]●[/color]" if on else "[color=#555]○[/color]"
	var head := "[b]%s[/b]   " % _esc(c.name)
	var mine := can_act_now(c)
	if eng.in_combat():
		if eng.current_id() == c.id:
			head += "Action %s  Bonus %s  Reaction %s  Move [b]%d[/b]/%d ft" % [dot.call(turn.actions > 0), dot.call(turn.bonus), dot.call(eng.can_react(c)),
				eng.movement_left(c), eng.speed_of(c) * (1 + turn.dashes)]
			if turn.attacks_left > 0:
				head += "   [color=#f2c66d]%d attack%s left[/color]" % [turn.attacks_left, "s" if turn.attacks_left > 1 else ""]
			if not turn.multiattack_left.is_empty():
				head += "   [color=#f2c66d]Multiattack: %s[/color]" % ", ".join(turn.multiattack_left)
			if not turn.bonus_attack.is_empty() and turn.bonus_attack.left > 0:
				head += "   [color=#f2c66d]%d bonus strike%s[/color]" % [turn.bonus_attack.left, "s" if turn.bonus_attack.left > 1 else ""]
		else:
			head += "[color=#a69f94]Waiting for your turn. Reaction %s[/color]" % dot.call(eng.can_react(c))
	else:
		head += "[color=#a69f94]Exploring: move freely, cast utility spells, rest.[/color]"
	econ.append_text(head)
	_action_box.add_child(econ)
	if c.dead:
		return

	var row_opts = UiKit.hbox(10)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	_action_box.add_child(flow)

	# Attacks
	for a in c.attacks:
		var p := eng.effective_profile(c, a)
		var tip := "%s: %s to hit, %s%s" % [p.name, Dice.fmt_mod(p.to_hit), _dmg_text(p), ("\nRange %d/%d ft" % [p.normal, p.long]) if p.range == "ranged" else ""]
		if a.has("recharge"):
			tip += "\nRecharge %d-6 (%s)" % [a.recharge, "ready" if a.get("charged", true) else "not ready"]
		var b = UiKit.button("⚔ " + p.name, func(): _begin_attack(a.id), tip, not mine or not eng.in_combat() or (a.has("recharge") and not a.get("charged", true)))
		if mode == "attack" and mode_data.get("attack_id", "") == a.id:
			b.modulate = UiKit.GOLD
		flow.add_child(b)
	# Spells
	var sc: Dictionary = c.spellcasting
	if not sc.is_empty() and not sc.known.is_empty():
		var by_level := {}
		for sid in sc.known:
			var sp := Spells.get_spell(sid)
			if sp.time == "reaction":
				continue
			by_level[sp.level] = by_level.get(sp.level, []) + [sid]
		var levels := by_level.keys()
		levels.sort()
		for lv in levels:
			var mb := MenuButton.new()
			mb.text = "✦ " + SPELL_LEVEL_NAMES[lv] + ("" if lv == 0 else " (%d)" % _slots_at_or_above(c, lv))
			mb.disabled = not mine
			mb.flat = false
			var pop := mb.get_popup()
			var ids: Array = by_level[lv]
			for i in ids.size():
				var sp := Spells.get_spell(ids[i])
				pop.add_item("%s%s" % [sp.name, "  (bonus)" if sp.time == "bonus" else ""], i)
				pop.set_item_tooltip(i, sp.desc + ("\nConcentration" if sp.get("concentration", false) else ""))
				var slot := _slot_for(c, sp)
				if eng.cast_error(c, sp, slot, _cast_opts()) != "" or (sp.level > 0 and slot == 0):
					pop.set_item_disabled(i, true)
			pop.id_pressed.connect(func(i): _begin_spell(ids[i]))
			flow.add_child(mb)
	# Powers
	for pw in c.powers:
		var usable: bool = mine and ((not pw.has("resource")) or eng.res_left(c, pw.resource) > 0) and pw.get("charged", true)
		flow.add_child(UiKit.button("✸ " + pw.name, func(): _begin_power(pw.id), pw.spell.get("desc", ""), not usable))
	# Standard actions
	var in_combat := eng.in_combat()
	var acts := [["Dash", "dash"], ["Disengage", "disengage"], ["Dodge", "dodge"], ["Hide", "hide"]]
	for a in acts:
		flow.add_child(UiKit.button(a[0], func(): send({"type": "action", "actor_id": c.id, "action": a[1]}), "Action", not mine or not in_combat))
	var ready_mb := MenuButton.new()
	ready_mb.text = "Ready ▾"
	ready_mb.flat = false
	ready_mb.disabled = not mine or not in_combat
	ready_mb.tooltip_text = "Action: pick an attack; it fires as your reaction when an enemy comes within its range before your next turn."
	var ready_pop := ready_mb.get_popup()
	var ready_ids: Array = c.attacks.map(func(p): return p.id)
	for i in ready_ids.size():
		ready_pop.add_item("%s (%d ft)" % [c.attacks[i].name, eng.ready_range(c.attacks[i])], i)
	ready_pop.id_pressed.connect(func(i): send({"type": "ready", "actor_id": c.id, "attack_id": ready_ids[i]}))
	flow.add_child(ready_mb)
	flow.add_child(UiKit.button("Help", func(): _begin_target("help", "Help: choose an enemy within 5 ft"), "Action: your allies' next attack against an enemy next to you has advantage", not mine or not in_combat))
	flow.add_child(UiKit.button("Grapple", func(): _begin_target("grapple", "Grapple: choose a creature within 5 ft"), "Replaces one attack: Athletics vs Athletics/Acrobatics", not mine or not in_combat))
	flow.add_child(UiKit.button("Shove", func(): _begin_target("shove_prone", "Shove prone: choose a creature within 5 ft"), "Replaces one attack: knock prone", not mine or not in_combat))
	flow.add_child(UiKit.button("Push", func(): _begin_target("shove_push", "Shove away: choose a creature within 5 ft"), "Replaces one attack: push 5 ft", not mine or not in_combat))
	flow.add_child(UiKit.button("Door", func(): _begin_target("door", "Door: click a door within 5 ft to open or close it"), "Free: open or close a door next to you", not mine))
	if eng.has_cond(c, "prone"):
		flow.add_child(UiKit.button("Stand Up", func(): send({"type": "action", "actor_id": c.id, "action": "standUp"}), "Costs half your speed", not mine))
	if eng.has_cond(c, "grappled") or eng.has_cond(c, "restrained"):
		flow.add_child(UiKit.button("Escape", func(): send({"type": "action", "actor_id": c.id, "action": "escape"}), "Action: break free", not mine))
	flow.add_child(UiKit.button("Stabilize", func(): _begin_target("stabilize", "Stabilize: choose a dying creature within 5 ft"), "Action: DC 10 Medicine check", not mine or not in_combat))
	flow.add_child(UiKit.button("Wake", func(): _begin_target("wake", "Wake: choose a sleeping creature within 5 ft"), "Action: shake awake a creature under Sleep", not mine or not in_combat))
	for a in eng.bonus_actions_allowed(c):
		flow.add_child(UiKit.button("⚡" + a.capitalize(), func(): send({"type": "action", "actor_id": c.id, "action": a, "via": "bonus"}), "Bonus action (%s)" % ("Cunning Action" if c.features.has("cunningAction") else "trait"), not mine or not in_combat))
	# Potions
	var carried: Array = c.get("items", [])
	for i in carried.size():
		var it := Items.get_item(carried[i].get("id", ""))
		if it.get("kind", "") == "potion":
			flow.add_child(UiKit.button("🧪 " + it.name, func(): send({"type": "useItem", "actor_id": c.id, "index": i}), it.get("desc", "") + "\nTakes an action.", not mine))
	# Features
	var feats := []
	if c.features.has("secondWind"): feats.append(["Second Wind", "secondWind", "", "Bonus: heal 1d10 + level"])
	if c.features.has("actionSurge"): feats.append(["Action Surge", "actionSurge", "", "Take one extra action"])
	if c.features.has("rage"):
		if eng.has_tag(c, "rage"):
			feats.append(["End Rage", "endRage", "", "Bonus action"])
		else:
			feats.append(["Rage", "rage", "", "Bonus: +%d melee damage, resist B/P/S" % c.fdata.get("rage_damage", 2)])
			if c.features.has("frenzy"): feats.append(["Frenzy", "rage", "frenzy", "Rage with a bonus-action attack each turn; exhaustion afterwards"])
	if c.features.has("flurryOfBlows"):
		feats.append(["Flurry of Blows", "flurryOfBlows", "", "1 ki, after the Attack action: two unarmed strikes"])
		feats.append(["Patient Defense", "patientDefense", "", "1 ki: Dodge as a bonus action"])
		feats.append(["Step: Dash", "stepOfTheWind", "dash", "1 ki: Dash as a bonus action"])
		feats.append(["Step: Disengage", "stepOfTheWind", "disengage", "1 ki: Disengage as a bonus action"])
	if c.features.has("sacredWeapon"): feats.append(["Sacred Weapon", "sacredWeapon", "", "Channel Divinity: +Cha to attack rolls"])
	for f in feats:
		flow.add_child(UiKit.button("★ " + f[0], func(): send({"type": "feature", "actor_id": c.id, "feature": f[1], "choice": f[2]}), f[3], not mine))
	if c.features.has("layOnHands"):
		flow.add_child(UiKit.button("★ Lay on Hands", func(): _begin_target("layOnHands", "Lay on Hands: choose a creature to touch"), "Action: heal from your pool (%d left)" % eng.res_left(c, "lay_on_hands"), not mine))
	if eng.has_tag(c, "spiritual_weapon"):
		flow.add_child(UiKit.button("★ Spiritual Weapon", func(): _begin_target("spiritualWeapon", "Spiritual Weapon: choose a creature within 60 ft"), "Bonus: attack with your spiritual weapon", not mine))
	if c.features.has("bardicInspiration"):
		flow.add_child(UiKit.button("★ Inspire", func(): _begin_target("bardicInspiration", "Bardic Inspiration: choose an ally within 60 ft"), "Bonus: give an inspiration die", not mine))
	if c.features.has("fontOfMagic"):
		var mb := MenuButton.new()
		mb.text = "★ Font of Magic"
		mb.disabled = not mine
		var pop := mb.get_popup()
		for lv in range(1, 6):
			if c.spellcasting.slots[lv] > 0 or lv <= Classes.max_spell_level("full", c.level):
				pop.add_item("Create level %d slot (%d pts)" % [lv, EngineMagic.SLOT_COST[lv]], lv)
		for lv in range(1, 6):
			if eng.slots_left(c, lv) > 0:
				pop.add_item("Convert level %d slot → %d pts" % [lv, lv], 100 + lv)
		pop.id_pressed.connect(func(i):
			send({"type": "feature", "actor_id": c.id, "feature": "createSlot" if i < 100 else "convertSlot", "amount": i % 100}))
		flow.add_child(mb)
	if c.fdata.has("wild_shape"):
		flow.add_child(UiKit.button("★ Revert Form", func(): send({"type": "feature", "actor_id": c.id, "feature": "revertShape"}), "Bonus: return to your normal form", not mine))
	elif c.features.has("wildShape"):
		var ws := MenuButton.new()
		ws.text = "★ Wild Shape (%d)" % eng.res_left(c, "wild_shape")
		ws.disabled = not mine or eng.res_left(c, "wild_shape") <= 0
		var beasts := []
		for id in Monsters.ALL.keys() + Homebrew.monsters.keys():
			var b := Monsters.get_monster(id)
			if b.get("type", "") == "beast" and float(b.cr) <= c.fdata.wild_shape_cr:
				beasts.append(id)
				ws.get_popup().add_item("%s (CR %s, %d HP)" % [b.name, Monsters.cr_label(float(b.cr)), b.hp], beasts.size() - 1)
		ws.get_popup().id_pressed.connect(func(i): send({"type": "feature", "actor_id": c.id, "feature": "wildShape", "choice": beasts[i]}))
		flow.add_child(ws)
	if Net.me.is_dm and c.kind == "npc" and mine and in_combat:
		flow.add_child(UiKit.button("🎲 Auto-play turn", func(): send({"type": "autoTurn"}), "Let the simple AI run this monster's turn"))
	var end_btn = UiKit.button("End Turn ⏎", func(): send({"type": "endTurn", "actor_id": c.id}), "", not (in_combat and mine))
	end_btn.modulate = UiKit.GOLD
	flow.add_child(end_btn)

	# Options row
	_action_box.add_child(row_opts)
	row_opts.add_child(UiKit.check("Bonus-action attack", opts.bonus, func(on): opts.bonus = on))
	if c.features.has("greatWeaponMaster") or c.features.has("sharpshooter"):
		row_opts.add_child(UiKit.check("−5/+10", opts.power, func(on): opts.power = on))
	if c.features.has("recklessAttack"):
		row_opts.add_child(UiKit.check("Reckless", opts.reckless, func(on): opts.reckless = on))
	if c.features.has("divineSmite") and not sc.is_empty():
		var items := ["No smite"]
		for lv in range(1, 6):
			if eng.slots_left(c, lv) > 0:
				items.append("Smite lv %d" % lv)
		var ob = UiKit.option(items)
		for i in items.size():
			if items[i] == "Smite lv %d" % opts.smite:
				ob.select(i)
		ob.item_selected.connect(func(i): opts.smite = 0 if i == 0 else int(items[i].split(" ")[-1]))
		row_opts.add_child(ob)
	if c.features.has("stunningStrike"):
		row_opts.add_child(UiKit.check("Stunning Strike", opts.stunning, func(on): opts.stunning = on))
	if c.features.has("openHand"):
		var items2 := ["Open Hand: —", "prone", "push", "reactions"]
		var ob2 = UiKit.option(items2, maxi(0, items2.find(opts.open_hand)))
		ob2.item_selected.connect(func(i): opts.open_hand = "" if i == 0 else items2[i])
		row_opts.add_child(ob2)
	if not sc.is_empty():
		var slot_items := ["Slot: lowest"]
		for lv in range(1, 10):
			if eng.slots_left(c, lv) > 0:
				slot_items.append("Slot %d" % lv)
		var ob3 = UiKit.option(slot_items)
		for i in slot_items.size():
			if slot_items[i] == "Slot %d" % opts.slot:
				ob3.select(i)
		ob3.item_selected.connect(func(i):
			opts.slot = 0 if i == 0 else int(slot_items[i].split(" ")[-1])
			_build_actions())
		row_opts.add_child(ob3)
	if c.options.has("quickened"):
		row_opts.add_child(UiKit.check("Quickened (2 SP)", opts.quickened, func(on):
			opts.quickened = on
			_build_actions()))
	if c.options.has("careful"):
		row_opts.add_child(UiKit.check("Careful (1 SP)", opts.careful, func(on): opts.careful = on))
	if c.options.has("heightened"):
		row_opts.add_child(UiKit.check("Heightened (3 SP)", opts.heightened, func(on): opts.heightened = on))
	var modes := ["ask", "auto", "never"]
	var ro := UiKit.option(["Reactions: ask me", "Reactions: automatic", "Reactions: never"], modes.find(eng.reaction_mode(c)))
	ro.tooltip_text = "Opportunity attacks, Shield, Uncanny Dodge... Ask me pops up a choice when one could help."
	ro.item_selected.connect(func(i): send({"type": "setReactions", "actor_id": c.id, "mode": modes[i]}))
	row_opts.add_child(ro)
	var lights := ["none"] + RulesEngine.LIGHT_SOURCES.keys()
	var lo := UiKit.option(lights.map(func(k): return "Light: " + ("none" if k == "none" else RulesEngine.LIGHT_SOURCES[k].name)),
		maxi(0, lights.find(c.get("light", {}).get("id", "none"))))
	lo.tooltip_text = "Carry a light: bright light around you, then dim light as far again. Lighting one takes your action in combat; dousing is free."
	lo.item_selected.connect(func(i): send({"type": "setLight", "actor_id": c.id, "source": lights[i]}))
	row_opts.add_child(lo)


func _slots_at_or_above(c: Dictionary, lv: int) -> int:
	var n := 0
	for l in range(lv, 10):
		n += eng.slots_left(c, l)
	return n


func _slot_for(c: Dictionary, sp: Dictionary) -> int:
	if sp.level == 0:
		return 0
	if opts.slot >= sp.level and eng.slots_left(c, opts.slot) > 0:
		return opts.slot
	var pact: Dictionary = c.spellcasting.pact
	if not pact.is_empty() and pact.level >= sp.level and pact.used < pact.max:
		return pact.level
	return eng.lowest_slot(c, sp.level)


func _cast_opts() -> Dictionary:
	return {"quickened": opts.quickened, "careful": opts.careful, "heightened": opts.heightened}


# ---------------- Modes ----------------

func toggle_ruler() -> void:
	if mode == "ruler":
		cancel_mode()
	else:
		_set_mode("ruler", {})


func cancel_mode() -> void:
	mode = ""
	mode_data = {}
	picked = []
	painting = {}
	if board and eng:
		board.clear_layer("paint")
		board.sync(state, eng, selected, picked, [])
		_update_overlays()
		_build_actions()


func _set_mode(m: String, data: Dictionary) -> void:
	mode = m
	mode_data = data
	picked = []
	_update_overlays()
	_build_actions()


func _begin_attack(attack_id: String) -> void:
	_set_mode("attack", {"attack_id": attack_id})


func _attack_mode_still_valid() -> bool:
	var c := sel()
	if c.is_empty() or not can_act_now(c) or not eng.in_combat():
		return false
	var t: Dictionary = c.turn
	return t.actions > 0 or t.attacks_left > 0 or not t.multiattack_left.is_empty() or (not t.bonus_attack.is_empty() and t.bonus_attack.left > 0)


func _begin_spell(spell_id: String) -> void:
	var c := sel()
	var sp := Spells.get_spell(spell_id)
	if sp.target.type == "self":
		send({"type": "cast", "actor_id": c.id, "spell_id": spell_id, "slot": _slot_for(c, sp), "options": _cast_opts()})
		return
	_set_mode("spell", {"spell_id": spell_id, "spell": sp, "slot": _slot_for(c, sp)})


func _begin_power(power_id: String) -> void:
	var c := sel()
	var pw := eng.find_power(c, power_id)
	if pw.spell.target.type == "self" or (pw.spell.target.type == "area" and pw.spell.target.shape == "sphere" and pw.spell.target.origin == "self"):
		send({"type": "power", "actor_id": c.id, "power_id": power_id})
		return
	_set_mode("power", {"power_id": power_id, "spell": pw.spell, "slot": 0})


func _begin_target(kind: String, prompt: String) -> void:
	_set_mode("target", {"kind": kind, "prompt": prompt})


func _target_count() -> int:
	var sp: Dictionary = mode_data.get("spell", {})
	var tgt: Dictionary = sp.get("target", {})
	if tgt.get("beams", false):
		return eng.cantrip_multiplier(sel().level)
	return tgt.get("count", 1) + tgt.get("per_slot", 0) * maxi(0, mode_data.get("slot", 0) - sp.get("level", 0))


func _cast_now(point = null) -> void:
	var c := sel()
	if mode == "power":
		send({"type": "power", "actor_id": c.id, "power_id": mode_data.power_id, "targets": picked.duplicate(), "point": point})
	else:
		send({"type": "cast", "actor_id": c.id, "spell_id": mode_data.spell_id, "slot": mode_data.slot, "targets": picked.duplicate(), "point": point, "options": _cast_opts()})
	cancel_mode()


# ---------------- Board input ----------------

func _token_at(cell: Vector2i, token: String) -> String:
	if token != "":
		return token
	for c in state.combatants.values():
		if not c.dead and Grid.footprint(c).has(cell):
			return c.id
	return ""


func _on_cell_pressed(cell: Vector2i, token: String) -> void:
	if state.is_empty():
		return
	if Input.is_key_pressed(KEY_ALT):
		send({"type": "ping", "pos": cell})
		return
	var c := sel()
	var tid := _token_at(cell, token)
	match mode:
		"ruler":
			mode_data["start"] = cell
			_update_overlays()
		"paint":
			painting = {cell: paint_type}
			_update_overlays()
		"spawn":
			var o: Dictionary = _spawn_target()
			send({"type": "spawn", "kind": o.kind, "template": o.id, "level": spawn_level, "pos": cell, "count": spawn_count,
				"side": ["party", "enemy", "neutral"][spawn_side], "hidden": spawn_hidden})
		"teleport":
			send({"type": "teleport", "id": selected, "to": cell})
			cancel_mode()
		"attack":
			if tid == "" or tid == selected:
				return
			var o := opts.duplicate()
			send({"type": "attack", "actor_id": c.id, "attack_id": mode_data.attack_id, "target_id": tid,
				"options": {"bonus": o.bonus, "power": o.power, "reckless": o.reckless, "smite": o.smite, "stunning_strike": o.stunning, "open_hand": o.open_hand}})
		"spell", "power":
			var tgt: Dictionary = mode_data.spell.target
			if tgt.type == "creature":
				if tid == "":
					return
				if picked.has(tid) and not tgt.get("repeat", false):
					picked.erase(tid)
				else:
					picked.append(tid)
				if picked.size() >= _target_count():
					_cast_now()
				else:
					board.sync(state, eng, selected, picked, [])
					_update_overlays()
			else:
				_cast_now(cell)
		"target":
			if mode_data.kind == "door":
				send({"type": "door", "actor_id": c.id, "x": cell.x, "y": cell.y})
				cancel_mode()
				return
			if tid == "":
				return
			match mode_data.kind:
				"help", "wake", "stabilize":
					send({"type": "action", "actor_id": c.id, "action": mode_data.kind, "target_id": tid})
				"grapple":
					send({"type": "grapple", "actor_id": c.id, "target_id": tid})
				"shove_prone", "shove_push":
					send({"type": "shove", "actor_id": c.id, "target_id": tid, "mode": "prone" if mode_data.kind == "shove_prone" else "push"})
				"layOnHands", "bardicInspiration", "spiritualWeapon":
					send({"type": "feature", "actor_id": c.id, "feature": mode_data.kind, "target_id": tid})
			cancel_mode()
		_:
			if token != "" or (tid != "" and tid != selected):
				select(tid)
				return
			if not c.is_empty() and can_act_now(c) and Grid.in_bounds(state.map, cell.x, cell.y) and cell != c.pos:
				# A closed door can't be walked into, so clicking one means open it.
				if state.map.cells[cell.y * state.map.width + cell.x] == Grid.DOOR:
					send({"type": "door", "actor_id": c.id, "x": cell.x, "y": cell.y})
				else:
					send({"type": "move", "actor_id": c.id, "to": cell})


func _on_cell_dragged(cell: Vector2i) -> void:
	if mode == "paint" and not painting.is_empty():
		painting[cell] = paint_type
		_update_overlays()


func _on_cell_released(_cell: Vector2i) -> void:
	if mode == "paint" and not painting.is_empty():
		var cells := []
		for p in painting:
			if painting[p] >= LIGHT_BRUSH:
				cells.append({"x": p.x, "y": p.y, "light": painting[p] - LIGHT_BRUSH})
			else:
				cells.append({"x": p.x, "y": p.y, "v": painting[p]})
		send({"type": "setCells", "cells": cells})
		painting = {}
		board.clear_layer("paint")


func _on_hover(cell: Vector2i, token: String) -> void:
	_hover_cell = cell
	_hover_token = token
	_update_overlays()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if creator_open():
			if event.keycode == KEY_ESCAPE:
				_creator.close()
			return
		if _homebrew != null and _homebrew.visible:
			if event.keycode == KEY_ESCAPE:
				_homebrew.close()
			return
		if event.is_action("toggle_sheet"):
			toggle_sheet("")
		elif event.keycode == KEY_ESCAPE:
			cancel_mode()
		elif event.keycode == KEY_F and sel() != {}:
			board.focus_on(selected)
		elif event.keycode == KEY_R:
			toggle_ruler()


# ---------------- Overlays & prompt ----------------

func _update_overlays() -> void:
	if board == null or state.is_empty():
		return
	for l in ["reach", "area", "path", "targets"]:
		board.clear_layer(l)
	board.show_cost(Vector2i.ZERO, "")
	var c := sel()
	var prompt := ""
	var buttons := []
	match mode:
		"paint":
			var names := {Grid.FLOOR: "floor", Grid.WALL: "walls", Grid.DIFFICULT: "difficult terrain", Grid.DOOR: "doors", Grid.LOW_WALL: "low walls (half cover)", LIGHT_BRUSH: "ambient light",
				LIGHT_BRUSH + 1 + Grid.DARK: "darkness", LIGHT_BRUSH + 1 + Grid.DIM: "dim light", LIGHT_BRUSH + 1 + Grid.BRIGHT: "bright light"}
			prompt = "Painting %s — click or drag on the map. Right-click to stop." % names[paint_type]
			var cells := painting.keys()
			var colors := cells.map(func(p): return {Grid.FLOOR: Color(0.6, 0.6, 0.6, 0.5), Grid.WALL: Color(0.2, 0.2, 0.25, 0.8),
				Grid.DIFFICULT: Color(0.3, 0.6, 0.2, 0.6), Grid.DOOR: Color(0.55, 0.35, 0.15, 0.8), Grid.LOW_WALL: Color(0.45, 0.42, 0.4, 0.7), LIGHT_BRUSH: Color(0.5, 0.5, 0.6, 0.4), LIGHT_BRUSH + 1 + Grid.DARK: Color(0.05, 0.05, 0.1, 0.7),
				LIGHT_BRUSH + 1 + Grid.DIM: Color(0.5, 0.45, 0.3, 0.5), LIGHT_BRUSH + 1 + Grid.BRIGHT: Color(1.0, 0.9, 0.5, 0.5)}[painting[p]])
			board.set_layer_colors("paint", cells, colors)
		"ruler":
			var start = mode_data.get("start")
			prompt = "Ruler: click a starting square. R or right-click to stop."
			if start != null and Grid.in_bounds(state.map, _hover_cell.x, _hover_cell.y):
				var d := _hover_cell - (start as Vector2i)
				var ft := Grid.grid_distance(d.x, d.y, state.settings.diagonal)
				prompt = "Ruler: %d ft (%d squares). Click to start again; R or right-click to stop." % [ft, ft / Grid.FT]
				board.set_layer("path", [start, _hover_cell], Color(1.0, 0.85, 0.3, 0.5))
				board.show_cost(_hover_cell, "%d ft" % ft)
		"spawn":
			prompt = "Click the map to place %s. Right-click to stop." % _spawn_target().label
		"teleport":
			prompt = "Click where %s should go." % c.get("name", "")
		"attack":
			var p := eng.find_attack(c, mode_data.attack_id)
			p = eng.effective_profile(c, p)
			prompt = "%s: choose a target." % p.name
			var valid := []
			for o in state.combatants.values():
				if o.id != c.id and not o.dead and eng.validate_attack(c, o, p) == "":
					valid.append_array(Grid.footprint(o))
			board.set_layer("targets", valid, Color(1, 0.3, 0.25, 0.35))
			var hid := _token_at(_hover_cell, _hover_token)
			if hid != "" and hid != c.id:
				var t := eng.get_c(hid)
				var err := eng.validate_attack(c, t, p)
				if err != "":
					prompt = err
				else:
					var reckless: bool = opts.reckless or c.fdata.get("reckless_turn", -1) == state.turn_counter
					var m := eng.attack_mode(c, t, p.range, {"profile": p, "reckless": reckless and p.range == "melee" and p.ability == "str"})
					var how := "normal roll"
					if m.mode == Dice.ADVANTAGE: how = "[advantage: %s]" % ", ".join(m.adv)
					elif m.mode == Dice.DISADVANTAGE: how = "[disadvantage: %s]" % ", ".join(m.dis)
					elif not m.adv.is_empty(): how = "advantage and disadvantage cancel"
					var cover := Grid.cover(state, c, t)
					prompt = "%s → %s (%d ft): %s%s" % [p.name, t.name, eng.dist(c, t), how, (" · target has +%d cover" % cover) if cover > 0 else ""]
		"spell", "power":
			var sp: Dictionary = mode_data.spell
			var tgt: Dictionary = sp.target
			match tgt.type:
				"creature":
					prompt = "%s: choose targets (%d/%d)." % [sp.name, picked.size(), _target_count()]
					var in_range := []
					for o in state.combatants.values():
						if (not o.dead or tgt.get("allow_dead", false)) and (o.id == c.id or eng.dist(c, o) <= maxi(5, sp.range)):
							in_range.append_array(Grid.footprint(o))
					board.set_layer("targets", in_range, Color(0.6, 0.5, 1.0, 0.3))
					if not picked.is_empty():
						buttons.append(["Cast now", func(): _cast_now()])
				"point":
					prompt = "%s: choose a destination within %d ft." % [sp.name, sp.range]
					var r := []
					for y in range(c.pos.y - sp.range / 5, c.pos.y + sp.range / 5 + 1):
						for x in range(c.pos.x - sp.range / 5, c.pos.x + sp.range / 5 + 1):
							if Grid.in_bounds(state.map, x, y) and Grid.cell_at(state.map, x, y) != Grid.WALL and Grid.distance_to_cell(state, c, Vector2i(x, y)) <= sp.range:
								r.append(Vector2i(x, y))
					board.set_layer("reach", r, Color(0.5, 0.4, 1.0, 0.25))
				"area":
					prompt = "%s: aim with the mouse and click." % sp.name if tgt.origin == "self" else "%s: choose the center (range %d ft)." % [sp.name, sp.range]
					if Grid.in_bounds(state.map, _hover_cell.x, _hover_cell.y):
						var cells := Grid.area_cells(state, c, tgt, _hover_cell)
						var dtype: String = sp.damage[0].type if sp.has("damage") else ""
						var col: Color = board.DAMAGE_COLORS.get(dtype, Color(0.7, 0.6, 1.0))
						var out_of_range: bool = tgt.origin == "point" and Grid.distance_to_cell(state, c, _hover_cell) > sp.range
						board.set_layer("area", cells, Color(col, 0.2) if out_of_range else Color(col, 0.5))
						var hit := Grid.creatures_in_cells(state, cells).map(func(o): return o.name)
						if not hit.is_empty():
							prompt += "  Hits: " + ", ".join(hit)
						if out_of_range:
							prompt += "  (out of range)"
		"target":
			prompt = mode_data.prompt
		_:
			if not c.is_empty() and can_act_now(c) and eng.speed_of(c) > 0 and not c.dead:
				var budget := eng.movement_left(c) if eng.in_combat() else 60
				if budget > 0:
					var reach := Grid.reachable(state, c, budget, eng.move_rules(c))
					var cells: Array = reach.cells.keys().filter(func(p): return p != c.pos)
					board.set_layer("reach", cells, Color(0.3, 0.6, 1.0, 0.22))
					if reach.cells.has(_hover_cell) and _hover_cell != c.pos and _token_at(_hover_cell, _hover_token) == "":
						var path := Grid.path_to(reach, _hover_cell)
						board.set_layer("path", path.map(func(s): return s.pos), Color(1.0, 0.85, 0.3, 0.55))
						board.show_cost(_hover_cell, "%d ft" % reach.cells[_hover_cell])
	if mode != "" and mode != "paint" and mode != "spawn":
		buttons.append(["Cancel", cancel_mode])
	var pending: Dictionary = state.get("pending", {})
	_reaction_panel.visible = false
	if not pending.is_empty():
		var pr: Dictionary = pending.prompt
		var key: String = pr.reactor_id + pr.text
		if key != _pending_key:
			_pending_key = key
			_pending_since = Time.get_ticks_msec() / 1000.0
		var mine: bool = pr.controller == Net.me.name or (pr.controller == "" and Net.me.is_dm)
		if mine:
			_reaction_panel.visible = true
			_reaction_text.text = pr.text
		else:
			prompt = "Waiting for %s: %s" % [pr.controller if pr.controller != "" else "the DM", pr.text]
			buttons = []
			if Net.me.is_dm:
				buttons = [["Decide: yes", func(): send({"type": "react", "choice": true})], ["Decide: no", func(): send({"type": "react", "choice": false})]]
	else:
		_pending_key = ""
	_prompt_panel.visible = prompt != ""
	_prompt.text = prompt
	UiKit.clear(_prompt_btns)
	for b in buttons:
		_prompt_btns.add_child(UiKit.button(b[0], b[1]))
	_prompt_panel.reset_size()
	_prompt_panel.offset_left = -_prompt_panel.size.x / 2
	_prompt_panel.offset_right = _prompt_panel.size.x / 2


# ---------------- Log & chat ----------------

func _update_log() -> void:
	var entries: Array = state.log
	if entries.is_empty():
		return
	var first_id: int = entries[0].id
	if _last_log_id < first_id - 1 or _last_log_id > entries[-1].id:
		_log.clear()
		_last_log_id = first_id - 1
	for e in entries:
		if e.id <= _last_log_id:
			continue
		_last_log_id = e.id
		var col: String = LOG_COLORS.get(e.kind, "d8cfc0")
		var line := ""
		if e.kind == "chat":
			line = "[b][color=#f2c66d]%s:[/color][/b] %s" % [_esc(e.who), _esc(e.text)]
		elif e.kind == "turn":
			line = "[b][color=#%s]%s[/color][/b]" % [col, _esc(e.text)]
		else:
			line = "[color=#%s]%s[/color]" % [col, _esc(e.text)]
		if e.get("private", "") != "":
			line = "[i](private)[/i] " + line
		if e.get("detail", "") != "":
			line += "\n   [font_size=12][color=#8a8478]%s[/color][/font_size]" % _esc(e.detail)
		_log.append_text(line + "\n")


func _on_chat(text: String) -> void:
	_chat.clear()
	text = text.strip_edges()
	if text.is_empty():
		return
	var lower := text.to_lower()
	for prefix in ["/roll ", "/r ", "/pr "]:
		if lower.begins_with(prefix):
			var rest := text.substr(prefix.length()).strip_edges()
			var parts := rest.split(" ", false, 1)
			send({"type": "roll", "expr": parts[0] if parts.size() > 0 else "1d20", "label": parts[1] if parts.size() > 1 else "", "private": prefix == "/pr "})
			return
	send({"type": "chat", "text": text})


# ---------------- Table tab ----------------

func _build_party() -> void:
	UiKit.clear(_party_box)
	_party_box.add_child(UiKit.label("Players", 18, UiKit.GOLD))
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		var chars = state.combatants.values().filter(func(c): return c.controller == p.name).map(func(c): return c.name)
		_party_box.add_child(UiKit.label("%s%s%s" % [p.name, " (DM)" if p.is_dm else "", (" — " + ", ".join(chars)) if not chars.is_empty() else ""], 15))
	if Net.is_host and Net.is_online():
		var addrs := Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"))
		var info := "Friends on your network can join at: %s (port %d)." % [", ".join(addrs), Net.DEFAULT_PORT]
		if Net.external_address != "":
			info += "\nOver the internet: %s" % Net.external_address
		else:
			info += "\nOver the internet: forward UDP port %d to this PC, or use a VPN like Tailscale/ZeroTier." % Net.DEFAULT_PORT
		var l = UiKit.label(info, 13, UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 330
		_party_box.add_child(l)
	_party_box.add_child(HSeparator.new())
	_party_box.add_child(UiKit.label("Creatures", 18, UiKit.GOLD))
	for c in state.combatants.values():
		var b = UiKit.button("%s%s" % [c.name, " ✝" if c.dead else ""], func(): select(c.id); board.focus_on(c.id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_party_box.add_child(b)


# ---------------- DM tab ----------------

func _build_dm() -> void:
	_tabs.set_tab_hidden(1, not Net.me.is_dm)
	if not Net.me.is_dm:
		return
	UiKit.clear(_dm_box)
	var c := sel()
	if not c.is_empty():
		_dm_box.add_child(UiKit.label("Selected: " + c.name, 18, UiKit.GOLD))
		var r = UiKit.hbox()
		var amt = UiKit.spin(1, 999, dm_amount, 80)
		amt.value_changed.connect(func(v): dm_amount = int(v))
		r.add_child(amt)
		r.add_child(UiKit.button("Damage", func(): send({"type": "adjustHp", "id": c.id, "amount": -dm_amount})))
		r.add_child(UiKit.button("Heal", func(): send({"type": "adjustHp", "id": c.id, "amount": dm_amount})))
		r.add_child(UiKit.button("Full HP", func(): send({"type": "setHp", "id": c.id, "hp": c.max_hp})))
		_dm_box.add_child(r)
		r = UiKit.hbox()
		var cm := MenuButton.new()
		cm.text = "Conditions ▾"
		cm.flat = false
		var pop := cm.get_popup()
		pop.hide_on_checkable_item_selection = false
		for i in Stats.CONDITIONS.size():
			var k: String = Stats.CONDITIONS[i]
			if k == "incapacitated":
				continue
			pop.add_check_item(k.capitalize(), i)
			pop.set_item_checked(pop.get_item_index(i), eng.has_cond(c, k))
		pop.id_pressed.connect(func(i): send({"type": "toggleCondition", "id": c.id, "condition": Stats.CONDITIONS[i]}))
		r.add_child(cm)
		r.add_child(UiKit.label("Exhaustion"))
		var ex = UiKit.spin(0, 6, c.exhaustion, 60)
		ex.value_changed.connect(func(v): send({"type": "setExhaustion", "id": c.id, "level": int(v)}))
		r.add_child(ex)
		_dm_box.add_child(r)
		r = UiKit.hbox()
		r.add_child(UiKit.label("Player"))
		var names := ["(DM)"]
		for pid in Net.players:
			if not Net.players[pid].is_dm:
				names.append(Net.players[pid].name)
		if c.controller != "" and not names.has(c.controller):
			names.append(c.controller)
		var ctl = UiKit.option(names, maxi(0, names.find(c.controller)))
		ctl.item_selected.connect(func(i): send({"type": "setController", "id": c.id, "controller": "" if i == 0 else names[i]}))
		r.add_child(ctl)
		var sides := ["party", "enemy", "neutral"]
		var so = UiKit.option(sides, maxi(0, sides.find(c.side)))
		so.item_selected.connect(func(i): send({"type": "setSide", "id": c.id, "side": sides[i]}))
		r.add_child(so)
		_dm_box.add_child(r)
		r = UiKit.hbox()
		r.add_child(UiKit.check("Surprised", c.surprised, func(on): send({"type": "setSurprised", "id": c.id, "surprised": on})))
		r.add_child(UiKit.check("Hidden", c.get("dm_hidden", false), func(on): send({"type": "setHidden", "id": c.id, "hidden": on})))
		r.add_child(UiKit.button("Teleport", func(): _set_mode("teleport", {}), "Move this token anywhere (no movement cost)"))
		r.add_child(UiKit.button("Remove", func(): send({"type": "removeCombatant", "id": c.id})))
		_dm_box.add_child(r)
		r = UiKit.hbox()
		var roll_items := []
		for ab in Stats.ABILITIES:
			roll_items.append(ab.to_upper() + " save")
		for sk in Stats.SKILLS:
			roll_items.append(Stats.skill_label(sk))
		var ro = UiKit.option(roll_items, dm_roll_choice)
		ro.item_selected.connect(func(i): dm_roll_choice = i)
		r.add_child(ro)
		r.add_child(UiKit.label("DC"))
		var dc = UiKit.spin(1, 30, dm_dc, 60)
		dc.value_changed.connect(func(v): dm_dc = int(v))
		r.add_child(dc)
		r.add_child(UiKit.button("Roll", func():
			if dm_roll_choice < 6:
				send({"type": "requestRoll", "id": c.id, "roll": "save", "ability": Stats.ABILITIES[dm_roll_choice], "dc": dm_dc})
			else:
				send({"type": "requestRoll", "id": c.id, "roll": "skill", "skill": Stats.SKILLS.keys()[dm_roll_choice - 6]})))
		_dm_box.add_child(r)
		_build_dm_items(c)
		if not c.spellcasting.is_empty():
			r = UiKit.hbox()
			var spell_ids: Array = Spells.ALL.keys().filter(func(sid): return not c.spellcasting.known.has(sid) and Spells.ALL[sid].time != "reaction") + \
				Homebrew.spells.keys().filter(func(sid): return not c.spellcasting.known.has(sid))
			if not spell_ids.is_empty():
				_grant_choice = clampi(_grant_choice, 0, spell_ids.size() - 1)
				var so2 := UiKit.option(spell_ids.map(func(sid): return ("★ " if Homebrew.spells.has(sid) else "") + Spells.get_spell(sid).name), _grant_choice)
				so2.item_selected.connect(func(i): _grant_choice = i)
				r.add_child(so2)
				r.add_child(UiKit.button("Teach spell", func(): send({"type": "grantSpell", "id": c.id, "spell_id": spell_ids[_grant_choice]}),
					"Add a spell to this creature's list (doesn't count against its limits)"))
				_dm_box.add_child(r)
		_dm_box.add_child(HSeparator.new())

	var hb_row := UiKit.hbox()
	hb_row.add_child(UiKit.button("Homebrew Workshop…", open_homebrew, "Make your own monsters, spells and magic items"))
	_dm_box.add_child(hb_row)
	_rebuild_spawn_options()
	_dm_box.add_child(UiKit.label("Add creatures", 18, UiKit.GOLD))
	var sp = UiKit.option(_spawn_options.map(func(o): return o.label), spawn_choice)
	sp.item_selected.connect(func(i):
		spawn_choice = i
		spawn_side = 0 if _spawn_options[i].kind == "pregen" else 1
		_build_dm())
	_dm_box.add_child(sp)
	var r2 = UiKit.hbox()
	if _spawn_options[spawn_choice].kind == "pregen":
		r2.add_child(UiKit.label("Level"))
		var lvl = UiKit.spin(1, 20, spawn_level, 60)
		lvl.value_changed.connect(func(v): spawn_level = int(v))
		r2.add_child(lvl)
	r2.add_child(UiKit.label("×"))
	var cnt = UiKit.spin(1, 10, spawn_count, 60)
	cnt.value_changed.connect(func(v): spawn_count = int(v))
	r2.add_child(cnt)
	var side_o = UiKit.option(["party", "enemy", "neutral"], spawn_side)
	side_o.item_selected.connect(func(i): spawn_side = i)
	r2.add_child(side_o)
	r2.add_child(UiKit.check("Hidden", spawn_hidden, func(on): spawn_hidden = on))
	r2.add_child(UiKit.button("Place…", func(): _set_mode("spawn", {}), "Then click the map"))
	_dm_box.add_child(r2)
	_dm_box.add_child(HSeparator.new())

	_dm_box.add_child(UiKit.label("Map", 18, UiKit.GOLD))
	var r3 = UiKit.hbox()
	for pair in [["Wall", Grid.WALL], ["Low wall", Grid.LOW_WALL], ["Door", Grid.DOOR], ["Difficult", Grid.DIFFICULT], ["Floor", Grid.FLOOR]]:
		var b = UiKit.button(pair[0], func():
			paint_type = pair[1]
			_set_mode("paint", {}))
		if mode == "paint" and paint_type == pair[1]:
			b.modulate = UiKit.GOLD
		r3.add_child(b)
	r3.add_child(UiKit.button("Clear", func(): send({"type": "clearMap"})))
	_dm_box.add_child(r3)
	var rb = UiKit.hbox()
	var px = UiKit.spin(0, 400, map_px_per_square, 70)
	px.tooltip_text = "Pixels per grid square in the image (70 is common). The map is resized to fit; 0 keeps the current size."
	px.value_changed.connect(func(v): map_px_per_square = int(v))
	rb.add_child(UiKit.button("Map image…", func(): main.background_dialog(map_px_per_square), "Put a PNG, JPG or WebP battle map under the grid"))
	rb.add_child(UiKit.label("px/square"))
	rb.add_child(px)
	if state.has("background"):
		rb.add_child(UiKit.button("Remove image", func(): send({"type": "clearBackground"})))
	_dm_box.add_child(rb)
	var rl = UiKit.hbox()
	var ambient := ["bright", "dim", "dark"]
	var ao := UiKit.option(["Ambient: bright", "Ambient: dim", "Ambient: dark"], ambient.find(state.settings.get("light", "bright")))
	ao.tooltip_text = "Light everywhere the DM hasn't painted. Darkvision sees dark as dim within range."
	ao.item_selected.connect(func(i): send({"type": "settings", "settings": {"light": ambient[i]}}))
	rl.add_child(ao)
	for pair in [["Bright", LIGHT_BRUSH + 1 + Grid.BRIGHT], ["Dim", LIGHT_BRUSH + 1 + Grid.DIM], ["Dark", LIGHT_BRUSH + 1 + Grid.DARK], ["Unpaint", LIGHT_BRUSH]]:
		var b = UiKit.button(pair[0], func():
			paint_type = pair[1]
			_set_mode("paint", {}), "Paint light on the map" if pair[1] != LIGHT_BRUSH else "Back to the ambient light")
		if mode == "paint" and paint_type == pair[1]:
			b.modulate = UiKit.GOLD
		rl.add_child(b)
	_dm_box.add_child(rl)
	var r4 = UiKit.hbox()
	var w = UiKit.spin(5, 80, state.map.width, 70)
	var h = UiKit.spin(5, 80, state.map.height, 70)
	r4.add_child(UiKit.label("Size"))
	r4.add_child(w)
	r4.add_child(UiKit.label("×"))
	r4.add_child(h)
	r4.add_child(UiKit.button("Resize", func(): send({"type": "resizeMap", "width": int(w.value), "height": int(h.value)})))
	_dm_box.add_child(r4)
	_dm_box.add_child(HSeparator.new())

	_dm_box.add_child(UiKit.label("Rules & session", 18, UiKit.GOLD))
	var st: Dictionary = state.settings
	_dm_box.add_child(UiKit.check("Monsters play themselves (simple AI)", st.auto_npc, func(on): send({"type": "settings", "settings": {"auto_npc": on}})))
	_dm_box.add_child(UiKit.check("Diagonals cost 5-10-5 (DMG variant)", st.diagonal == "5-10-5", func(on): send({"type": "settings", "settings": {"diagonal": "5-10-5" if on else "5"}})))
	_dm_box.add_child(UiKit.check("Flanking gives advantage (DMG variant)", st.flanking, func(on): send({"type": "settings", "settings": {"flanking": on}})))
	var fog_row := UiKit.hbox()
	fog_row.add_child(UiKit.check("Fog of war for players", st.get("fog", false), func(on): send({"type": "settings", "settings": {"fog": on}})))
	fog_row.add_child(UiKit.button("Reset explored", func(): send({"type": "resetFog"}), "Players forget the parts of the map they've seen"))
	_dm_box.add_child(fog_row)
	_dm_box.add_child(UiKit.check("Monsters die at 0 HP", st.npcs_die_at_zero, func(on): send({"type": "settings", "settings": {"npcs_die_at_zero": on}})))
	var r5 = UiKit.hbox()
	r5.add_child(UiKit.button("Short Rest", func(): send({"type": "rest", "kind": "short"}), "Party: recover short-rest features, spend hit dice"))
	r5.add_child(UiKit.button("Long Rest", func(): send({"type": "rest", "kind": "long"}), "Party: full HP, spell slots and features"))
	_dm_box.add_child(r5)
	var r6 = UiKit.hbox()
	r6.add_child(UiKit.button("Save…", func(): main.save_dialog()))
	r6.add_child(UiKit.button("Load…", func(): main.load_dialog()))
	r6.add_child(UiKit.button("New Game", func(): Net.new_game()))
	_dm_box.add_child(r6)
