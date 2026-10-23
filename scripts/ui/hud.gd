extends Control
## In-game interface: initiative tracker, character sheet, action bar, log/chat and DM tools.
## Also the input controller: it decides what a click on the board means in the current mode.

const SheetScript := preload("res://scripts/ui/character_sheet.gd")
const CreatorScript := preload("res://scripts/ui/creator_panel.gd")
const HomebrewScript := preload("res://scripts/ui/homebrew_panel.gd")
const BoardScript := preload("res://scripts/ui/board.gd")
const RAIL_W := 96
const SIDE_W := 370
const SLOT_GAP := 3
const BAR_SHARE := 0.15  # of the screen height, with the default 3 rows of slots
const BAR_CHROME := 40  # bar height that isn't slots: panel margins, the status line
const TokenScript := preload("res://scripts/ui/token.gd")
const PREFS := "user://prefs.cfg"
const SPELL_LEVEL_NAMES := ["Cantrips", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"]
const SPELL_RANGE_COLOR := Color(0.65, 0.55, 1.0, 0.75)
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
var opts := {"bonus": false, "power": false, "maneuver": "", "reckless": false, "smite": 0, "stunning": false, "open_hand": "", "slot": 0, "quickened": false, "careful": false, "heightened": false, "ritual": false}
var paint_type := Grid.WALL  # terrain, or LIGHT_BRUSH + painted light value
const LIGHT_BRUSH := 10
var painting: Dictionary = {}
var spawn_choice := 0
var spawn_level := 3
var spawn_side := 1
var spawn_count := 1
var spawn_hidden := false
var prop_kit := 0
var prop_model := 0
var prop_rot := 0
var prop_h := 0
var _prop_catalog := {}  # kit -> model names, from assets/kenney
var map_px_per_square := 70
var dm_amount := 5
var dm_dc := 13
var dm_roll_choice := 0

var _init_bar: HBoxContainer
var _top_turn := ""  # whose turn the strip last showed, to pan from it
var _pan: Tween
var _round_label: Label
var _top_buttons: HBoxContainer
var _sheet_panel: PanelContainer
var _creator: Control
var _homebrew: Control
var _give_choice := 0
var _give_base := 0
var _grant_choice := 0
var _expect_name := ""
var _level_up_offered := {}
var _rail: PanelContainer
var _rail_btns := {}
var _action_box: HBoxContainer
var _action_panel: PanelContainer  # the action bar, fixed along the bottom edge
var _opts_panel: PanelContainer  # attack/casting options, opened from the bar's ⚙ button
var _opts_box: VBoxContainer
var _bar_keys: Array = []  # tile keys in the order the bar shows them, for drag-to-reorder
var _slot := 46  # icon slot size, fitted so 3 rows fill BAR_SHARE of the screen
var _bar_rows := 3  # button area size in slots, set by dragging its edges while unlocked
var _bar_cols := 12
var _bar_unlocked := false
var _resize := {}  # edge drag in progress: from, rows, cols, top, right
var _log: RichTextLabel
var _chat: LineEdit
var _tabs: TabContainer
var _side: PanelContainer  # log / DM / table / plan panel, opened from the right rail like the sheet
var _rrail: PanelContainer
var _side_btns: Array = []
var _dm_scroll: ScrollContainer
var _dm_box: VBoxContainer
var _party_box: VBoxContainer
var _plan_box: VBoxContainer
var _plan_quiet := false  # set while a text box commits, so the planner isn't rebuilt under the DM
var plan_session := 0
var plan_scene := 0
var plan_add := 0
var plan_count := 1
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
	var strip := Control.new()  # clips the turn-order cards as they pan left
	strip.clip_contents = true
	strip.custom_minimum_size.y = 40
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(strip)
	_init_bar = UiKit.hbox(4)
	strip.add_child(_init_bar)
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
	get_viewport().size_changed.connect(func(): if not state.is_empty(): _build_actions())

	_rrail = UiKit.panel()
	_rrail.anchor_left = 1
	_rrail.anchor_right = 1
	_rrail.offset_left = -8 - RAIL_W
	_rrail.offset_right = -8
	_rrail.offset_top = 66
	add_child(_rrail)
	var rrv := UiKit.vbox(6)
	_rrail.add_child(rrv)
	_side = UiKit.panel()
	_side.anchor_left = 1
	_side.anchor_right = 1
	_side.anchor_top = 0
	_side.anchor_bottom = 1
	_side.offset_left = -8 - RAIL_W - 8 - SIDE_W
	_side.offset_right = -8 - RAIL_W - 8
	_side.offset_top = 66
	_side.offset_bottom = -8
	add_child(_side)
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_side.add_child(_tabs)
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
	var plan_scroll := ScrollContainer.new()
	plan_scroll.name = "Plan"
	plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(plan_scroll)
	_plan_box = UiKit.vbox(6)
	_plan_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan_scroll.add_child(_plan_box)
	var side_cap := UiKit.label("MENU", 11, UiKit.MUTED)
	side_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rrv.add_child(side_cap)
	for i in _tabs.get_child_count():
		var b := UiKit.button(_tabs.get_child(i).name, func(): toggle_side(i), "Show or hide the %s panel" % _tabs.get_child(i).name)
		b.custom_minimum_size.x = RAIL_W - 16
		_side_btns.append(b)
		rrv.add_child(b)
	_side.visible = cfg.get_value("hud", "side_visible", false)
	_tabs.current_tab = cfg.get_value("hud", "side_tab", 0)

	_bar_rows = cfg.get_value("hud", "bar_rows", 3)
	_bar_cols = cfg.get_value("hud", "bar_cols", 12)
	_action_panel = UiKit.panel()
	var bsb := _tex_box("bar.png", 0)  # one painted texture (smoke on black) stretched over the whole bar
	bsb.texture_margin_top = 30  # the gold trim keeps its thickness
	bsb.set_content_margin_all(8)
	bsb.content_margin_top = 16
	bsb.content_margin_bottom = 6
	_action_panel.add_theme_stylebox_override("panel", bsb)
	_action_panel.theme = _bar_theme()
	_action_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_action_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_action_panel)
	_action_panel.resized.connect(_layout_side)
	var caps := Control.new()  # gold corner pieces, behind the bar's contents
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_panel.add_child(caps)
	for right in [false, true]:
		var cap := TextureRect.new()
		cap.texture = load("res://assets/ui/bar_cap.png")
		cap.flip_h = right
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.anchor_left = 1.0 if right else 0.0
		cap.anchor_right = cap.anchor_left
		cap.offset_left = -56.0 if right else -8.0
		cap.offset_top = -16
		caps.add_child(cap)
	_action_box = UiKit.hbox(10)
	_action_panel.add_child(_action_box)
	_opts_panel = UiKit.panel()
	_opts_panel.anchor_left = 1
	_opts_panel.anchor_right = 1
	_opts_panel.anchor_top = 1
	_opts_panel.anchor_bottom = 1
	_opts_panel.offset_right = -8
	_opts_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_opts_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_opts_panel.visible = false
	add_child(_opts_panel)
	_opts_panel.theme = _action_panel.theme
	_opts_panel.add_theme_stylebox_override("panel", bsb)
	_opts_box = UiKit.vbox(6)
	_opts_panel.add_child(_opts_box)

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
	_offer_level_up()
	board.sync(state, eng, selected, picked, events)
	_refresh_panels()


## Opens the level-up screen once for each DM-granted level on a character you play, outside combat.
func _offer_level_up() -> void:
	if eng.in_combat() or creator_open():
		return
	for c in state.combatants.values():
		var key := "%s@%d" % [c.id, c.get("pending_level", 0)]
		if c.get("pending_level", 0) > c.level and (c.controller == Net.me.name or (Net.me.is_dm and c.controller == "")) and not _level_up_offered.has(key):
			_level_up_offered[key] = true
			selected = c.id
			open_creator(c)
			return


func _refresh_panels() -> void:
	if state.is_empty():
		return
	_build_top()
	_build_sheet()
	_build_actions()
	_build_dm()
	_build_party()
	_build_plan()
	_update_log()
	_update_overlays()
	_layout_side()
	if _homebrew != null and _homebrew.visible:
		_homebrew.refresh()


func sel() -> Dictionary:
	return eng.get_c(selected) if eng else {}


## A controlled mount answers to its rider's player and acts on the rider's turn.
func can_control(c: Dictionary) -> bool:
	return not c.is_empty() and (Net.me.is_dm or c.controller == Net.me.name \
		or (c.get("controlled", false) and eng.get_c(c.rider).get("controller", "") == Net.me.name))


func can_act_now(c: Dictionary) -> bool:
	return can_control(c) and not c.dead and (not eng.in_combat() or eng.current_id() == (c.rider if c.get("controlled", false) else c.id))


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
		# The current creature is leftmost. When the turn passes, the last one stays in front and
		# the strip pans left one card so the next slides into place.
		var order: Array = state.combat.order
		var cur := eng.current_id()
		var prev := _top_turn if _top_turn != cur and not eng.get_c(_top_turn).is_empty() and order.has(_top_turn) else ""
		_top_turn = cur
		var at := maxi(0, order.find(prev if prev != "" else cur))
		for i in order.size():
			var c := eng.get_c(order[(at + i) % order.size()])
			if not c.is_empty():
				_init_bar.add_child(_init_card(c, c.id == cur))
		if _pan != null:
			_pan.kill()
		_init_bar.position.x = 0
		if prev != "":
			_pan = create_tween()
			_pan.tween_property(_init_bar, "position:x", -(_init_bar.get_child(0).custom_minimum_size.x + 4), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	var menu := MenuButton.new()
	menu.text = "☰"
	menu.flat = false
	menu.tooltip_text = "New character, leave the game"
	menu.get_popup().add_item("New Character", 0)
	menu.get_popup().add_item("Leave game", 1)
	menu.get_popup().id_pressed.connect(func(i): open_creator({}) if i == 0 else main.leave_game())
	_top_buttons.add_child(menu)


## A turn-order card: initiative, name, and an HP bar (just a health word for monsters you can't see the numbers of).
func _init_card(c: Dictionary, current: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(124 if current else 104, 40)
	b.tooltip_text = "%s\n%s" % [c.name, c.description]
	var side_col: Color = UiKit.BLUE if c.side == "party" else (UiKit.RED if c.side == "enemy" else UiKit.GOLD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.4, 0.3, 0.12) if current else Color(0.14, 0.12, 0.12)
	sb.set_corner_radius_all(4)
	sb.border_width_bottom = 3
	sb.border_color = side_col
	if current:
		sb.set_border_width_all(2)
		sb.border_color = UiKit.GOLD
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	if c.dead:
		b.modulate = Color(1, 1, 1, 0.4)
	var v := UiKit.vbox(3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 6)
	b.add_child(v)
	var top := UiKit.hbox(5)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	top.add_child(UiKit.label(str(c.initiative), 12, UiKit.GOLD))
	var nm := UiKit.label(c.name + (" ✝" if c.dead else ""), 13)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if c.get("redacted", false):
		v.add_child(UiKit.label(c.get("hp_status", ""), 11, UiKit.MUTED))
	else:
		var bar := ColorRect.new()
		bar.color = Color(0.25, 0.08, 0.08)
		bar.custom_minimum_size.y = 6
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := ColorRect.new()
		fill.color = UiKit.GREEN if c.side == "party" else UiKit.RED
		fill.anchor_bottom = 1
		fill.anchor_right = 0.0 if c.max_hp <= 0 else clampf(float(c.hp) / c.max_hp, 0.0, 1.0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(fill)
		v.add_child(bar)
	b.pressed.connect(func():
		select(c.id)
		board.focus_on(c.id))
	return b


func _process(_delta: float) -> void:
	if _reaction_panel != null and _reaction_panel.visible:
		var left := maxi(0, int(ceil(Net.REACTION_SECONDS - (Time.get_ticks_msec() / 1000.0 - _pending_since))))
		_reaction_clock.text = "%ds to decide" % left


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


## Show/hide the right-hand panel on tab `i` (Log, DM, Table, Plan); hides it if that tab is already showing.
func toggle_side(i: int) -> void:
	_side.visible = not (_side.visible and _tabs.current_tab == i)
	_tabs.current_tab = i
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	cfg.set_value("hud", "side_visible", _side.visible)
	cfg.set_value("hud", "side_tab", i)
	cfg.save(PREFS)
	_layout_side()


## The action bar spans the bottom edge; the sheet sits beside the left rail above it, and the
## right panel beside the right rail.
func _layout_side() -> void:
	if _sheet_panel == null:
		return
	var vs := get_viewport_rect().size
	var left := 8.0 + RAIL_W + 8.0
	var right_edge := vs.x - 8.0 - RAIL_W - 8.0 - (SIDE_W + 8.0 if _side.visible else 0.0)
	for i in _side_btns.size():
		_side_btns[i].modulate = UiKit.GOLD if _side.visible and _tabs.current_tab == i else Color.WHITE
	var width := clampf(right_edge - 10.0 - left, 520.0, 1000.0)
	var bottom := vs.y - _action_panel.size.y - 8.0
	_side.offset_bottom = -_action_panel.size.y - 8.0
	_opts_panel.offset_bottom = -_action_panel.size.y - 8.0
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
	elif c.get("pending_level", 0) > c.level:
		_creator.open_level_up(c)
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
	var err := eng.cast_error(c, sp, _slot_for(c, sp), _cast_opts(sp))
	if err != "":
		show_toast(err, true)
		return
	_begin_spell(spell_id)


## Hover card for an attack: to-hit, damage, reach or range, weapon properties.
func _attack_tip(p: Dictionary) -> String:
	var t := "[b][color=#f2c66d]%s[/color][/b]\n[color=#a69f94]%s attack[/color]\n" % [_esc(p.name), "Melee" if p.range == "melee" else "Ranged"]
	t += "To hit [b]%s[/b]   Damage [b]%s[/b]\n" % [Dice.fmt_mod(p.to_hit), _dmg_text(p)]
	t += ("Reach %d ft" % p.reach) if p.range == "melee" else ("Range %d/%d ft" % [p.normal, p.long] if p.long > p.normal else "Range %d ft" % p.normal)
	for prop in p.get("props", []):
		var rule: String = SrdText.WEAPON_PROPERTIES.get(prop.to_snake_case().replace("_", "-"), "")
		t += "\n[b]%s.[/b] [color=#a69f94]%s[/color]" % [prop.capitalize(), _esc(rule)]
	if p.get("desc", "") != "":
		t += "\n" + _esc(p.desc)
	return t


## Hover card for a spell (or a power shaped like one): the SRD's casting time, range, components,
## duration and rules text when it has the spell, plus this caster's attack bonus or save DC.
func spell_tip(c: Dictionary, sp: Dictionary, dc: int = 0, sid: String = "") -> String:
	var sc: Dictionary = c.get("spellcasting", {})
	var raw: Dictionary = SrdText.SPELLS.get(sid, {})
	var head: String = "Cantrip" if sp.level == 0 else "Level %d" % sp.level
	if sp.has("school"):
		head += " " + sp.school
	var rows := PackedStringArray()
	if not raw.is_empty():
		for k in [["Casting time", "casting_time"], ["Range", "range"], ["Components", "components"], ["Duration", "duration"]]:
			rows.append("%s [b]%s[/b]" % [k[0], _esc(raw[k[1]])])
	else:
		var times := {"action": "1 action", "bonus": "1 bonus action", "reaction": "1 reaction"}
		rows.append("Casting time [b]%s[/b]" % times.get(sp.get("time", "action"), sp.get("time", "")))
		rows.append("Range [b]%s[/b]" % ("self" if sp.range == 0 else ("touch" if sp.range == 5 else "%d ft" % sp.range)))
		var tgt: Dictionary = sp.get("target", {})
		if tgt.get("type", "") == "area":
			rows.append("Area [b]%d-ft %s[/b]" % [tgt.size, {"sphere": "radius"}.get(tgt.shape, tgt.shape)])
		for d in sp.get("damage", []):
			rows.append("Damage [b]%s %s[/b]%s" % [d.get("dice", ""), d.type, (" (+%s per slot level)" % d.per_slot) if d.has("per_slot") else ""])
		if sp.get("concentration", false):
			rows.append("[color=#b0a0ff]Concentration[/color]")
	if sp.has("attack") and sc.has("attack_bonus"):
		rows.append("Your spell attack [b]%s[/b]" % Dice.fmt_mod(sc.attack_bonus))
	if sp.has("save"):
		var save_dc: int = dc if dc > 0 else sc.get("dc", 0)
		if save_dc > 0:
			rows.append("%s save [b]DC %d[/b]" % [Stats.ABILITY_NAMES.get(sp.save.ability, sp.save.ability), save_dc])
	var body: String
	if raw.is_empty():
		body = _esc(sp.get("desc", "")) + ("\n[color=#7d766b](Summary. This spell isn't in the SRD, so its full text isn't included.)[/color]" if sid != "" and Spells.ALL.has(sid) else "")
	else:
		body = _esc(raw.text) + (("\n[b]At Higher Levels.[/b] " + _esc(raw.higher)) if raw.higher != "" else "")
	return "[b][color=#f2c66d]%s[/color][/b]\n[color=#a69f94]%s[/color]\n%s\n%s" % [_esc(sp.name), head, "\n".join(rows), body]


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

## The action bar, left to right: portrait with HP, weapon slots with one button per attack mode,
## the button area (actions | spells | items, reorderable by dragging), End Turn, and ⚙ options.
func _build_actions() -> void:
	UiKit.clear(_action_box)
	UiKit.clear(_opts_box)
	var vh := get_viewport_rect().size.y
	_slot = clampi(int((vh * BAR_SHARE - BAR_CHROME) / 3) - SLOT_GAP, 24, 72)
	_action_panel.custom_minimum_size.y = BAR_CHROME + _bar_rows * (_slot + SLOT_GAP)
	var c := sel()
	if c.is_empty() or not can_control(c) or c.get("redacted", false):
		_opts_panel.visible = false
		var hint := UiKit.label("Select one of your characters to see its actions.", 15, UiKit.MUTED)
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_action_box.add_child(hint)
		return
	var turn: Dictionary = c.turn
	_action_box.add_child(_portrait(c))
	var wbox := UiKit.hbox(8)
	_action_box.add_child(wbox)
	var mid := UiKit.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_box.add_child(mid)
	var status := UiKit.hbox(14)
	mid.add_child(status)
	var econ := RichTextLabel.new()
	econ.bbcode_enabled = true
	econ.fit_content = true
	econ.scroll_active = false
	econ.autowrap_mode = TextServer.AUTOWRAP_OFF
	econ.clip_contents = true
	econ.add_theme_font_size_override("normal_font_size", 12)
	econ.add_theme_font_size_override("bold_font_size", 12)
	var dot := func(on: bool) -> String: return "[color=#8fe39a]●[/color]" if on else "[color=#555]○[/color]"
	var head := "[b]%s[/b]   " % _esc(c.name)
	var mine := can_act_now(c)
	if eng.in_combat():
		if eng.current_id() == c.id:
			head += "Action %s  Bonus %s  Reaction %s  Move [b]%d[/b]/%d ft" % [dot.call(turn.actions > 0 or turn.get("haste_action", false)), dot.call(turn.bonus), dot.call(eng.can_react(c)),
				eng.movement_left(c), eng.speed_of(c) * (1 + turn.dashes)]
			if turn.attacks_left > 0:
				head += "   [color=#f2c66d]%d attack%s left[/color]" % [turn.attacks_left, "s" if turn.attacks_left > 1 else ""]
			if not turn.multiattack_left.is_empty():
				head += "   [color=#f2c66d]Multiattack: %s[/color]" % ", ".join(turn.multiattack_left)
			if not turn.bonus_attack.is_empty() and turn.bonus_attack.left > 0:
				head += "   [color=#f2c66d]%d bonus strike%s[/color]" % [turn.bonus_attack.left, "s" if turn.bonus_attack.left > 1 else ""]
		else:
			head += "[color=#a69f94]Waiting for your turn. Reaction %s[/color]" % dot.call(eng.can_react(c))
			if c.resources.has("legendary"):
				head += "   [color=#f2c66d]Legendary actions %d/%d[/color]" % [eng.res_left(c, "legendary"), c.resources.legendary.max]
	else:
		head += "[color=#a69f94]Exploring: move freely, cast utility spells, rest.[/color]"
	econ.append_text(head)
	status.add_child(econ)
	var vitals := TipRichText.new()
	vitals.bbcode_enabled = true
	vitals.meta_underlined = false
	vitals.meta_hover_started.connect(func(m): vitals.tooltip_text = "[b][color=#f2c66d]%s[/color][/b]\n%s" % [str(m).substr(5).capitalize(), _esc(SrdText.CONDITIONS.get(str(m).substr(5), ""))])
	vitals.meta_hover_ended.connect(func(_m): vitals.tooltip_text = "")
	vitals.fit_content = true
	vitals.scroll_active = false
	vitals.autowrap_mode = TextServer.AUTOWRAP_OFF
	vitals.clip_contents = true
	vitals.add_theme_font_size_override("normal_font_size", 12)
	vitals.add_theme_font_size_override("bold_font_size", 12)
	vitals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vitals.append_text(_vitals_text(c))
	status.add_child(vitals)
	if c.dead:
		_opts_panel.visible = false
		return

	var row_opts := _opts_box
	var cats := {"Actions": [], "Spells": [], "Items": []}

	# Weapon slots: one per weapon (or natural attack), with a button for each way to attack with it.
	var slots := {}
	for a in c.attacks:
		var p := eng.effective_profile(c, a)
		var key: String = a.id.trim_suffix("_thrown")
		if not slots.has(key):
			var slot := UiKit.vbox(2)
			var hrow := UiKit.hbox(4)
			var ic := TextureRect.new()
			ic.texture = Icons.item_tex(a.weapon_id) if a.has("weapon_id") else Icons.tex("actions", a.id)
			if ic.texture == null:
				ic.texture = Icons.tex("actions", "attack_ranged" if a.get("range", "") == "ranged" else "attack_melee")
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.custom_minimum_size = Vector2(22, 22)
			hrow.add_child(ic)
			var nm := UiKit.label(p.name.trim_suffix(" (thrown)"), 12, UiKit.GOLD)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hrow.add_child(nm)
			slot.add_child(hrow)
			slots[key] = UiKit.hbox(3)
			slot.add_child(slots[key])
			wbox.add_child(slot)
		var tip := _attack_tip(p)
		if a.has("recharge"):
			tip += "\nRecharge %d-6 (%s)" % [a.recharge, "ready" if a.get("charged", true) else "not ready"]
		var d0: Dictionary = p.damage[0] if not p.damage.is_empty() else {}
		var how: String = "Thrown" if a.id.ends_with("_thrown") else str(d0.get("type", "attack")).capitalize()
		var dmg: String = d0.get("dice", "") + (Dice.fmt_mod(d0.get("bonus", 0)) if d0.get("dice", "") != "" else str(d0.get("bonus", 0)))
		var b = UiKit.button("%s\n%s" % [how, dmg], func(): _begin_attack(a.id), tip, not mine or not eng.in_combat() or (a.has("recharge") and not a.get("charged", true)))
		b.custom_minimum_size = Vector2(80, 44)
		b.add_theme_font_size_override("font_size", 12)
		if mode == "attack" and mode_data.get("attack_id", "") == a.id:
			b.modulate = UiKit.GOLD
		slots[key].add_child(b)
	# Spells: one tile each, cantrips first.
	var sc: Dictionary = c.spellcasting
	if not sc.is_empty():
		var known: Array = sc.known.filter(func(sid): return Spells.get_spell(sid).time != "reaction")
		known.sort_custom(func(x, y): return Spells.get_spell(x).level < Spells.get_spell(y).level)
		for sid in known:
			var sp := Spells.get_spell(sid)
			var slot := _slot_for(c, sp)
			var cant: bool = eng.cast_error(c, sp, slot, _cast_opts(sp)) != "" or (sp.level > 0 and slot == 0)
			var tag: String = ("Cantrip" if sp.level == 0 else SPELL_LEVEL_NAMES[sp.level]) + (" · bonus" if sp.time == "bonus" else "")
			var sicon := Icons.tex("spells", sid)  # with an icon the hover card gives the level
			cats.Spells.append(_ico(sicon, _tile(UiKit.button(sp.name if sicon else "✦ %s\n%s" % [tag, sp.name], func(): _begin_spell(sid), spell_tip(c, sp, 0, sid), not mine or cant))))
	# Powers
	for pw in c.powers:
		var usable: bool = mine and ((not pw.has("resource")) or eng.res_left(c, pw.resource) > 0) and pw.get("charged", true)
		cats.Actions.append(_ico(Icons.tex("actions", pw.id), _tile(UiKit.button("✸ " + pw.name, func(): _begin_power(pw.id), spell_tip(c, pw.spell, pw.get("dc", 0)), not usable))))
	# Legendary actions: between other creatures' turns
	var leg_ok: bool = can_control(c) and eng.in_combat() and eng.current_id() != c.id
	for la in c.get("legendary", []):
		var cost: int = la.get("cost", 1)
		var tip: String = la.spell.get("desc", "") if la.has("spell") else "Make a %s attack." % la.name
		cats.Actions.append(_ico(Icons.tex("actions", "legendary"), _tile(UiKit.button("★ %s (%d)" % [la.name, cost], func(): _begin_legendary(la), "Legendary action, costs %d: %s" % [cost, tip],
			not leg_ok or eng.res_left(c, "legendary") < cost))))
	# Standard actions
	var in_combat := eng.in_combat()
	var acts := [["Dash", "dash"], ["Disengage", "disengage"], ["Dodge", "dodge"], ["Hide", "hide"]]
	for a in acts:
		cats.Actions.append(_ico(Icons.tex("actions", a[1]), _tile(UiKit.button(a[0], func(): send({"type": "action", "actor_id": c.id, "action": a[1]}), "Action", not mine or not in_combat))))
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
	cats.Actions.append(_ico(Icons.tex("actions", "ready"), _tile(ready_mb)))
	cats.Actions.append(_ico(Icons.tex("actions", "help"), _tile(UiKit.button("Help", func(): _begin_target("help", "Help: choose an enemy within 5 ft"), "Action: your allies' next attack against an enemy next to you has advantage", not mine or not in_combat))))
	cats.Actions.append(_ico(Icons.tex("actions", "grapple"), _tile(UiKit.button("Grapple", func(): _begin_target("grapple", "Grapple: choose a creature within 5 ft"), "Replaces one attack: Athletics vs Athletics/Acrobatics", not mine or not in_combat))))
	cats.Actions.append(_ico(Icons.tex("actions", "shove_prone"), _tile(UiKit.button("Shove", func(): _begin_target("shove_prone", "Shove prone: choose a creature within 5 ft"), "Replaces one attack: knock prone", not mine or not in_combat))))
	cats.Actions.append(_ico(Icons.tex("actions", "shove_push"), _tile(UiKit.button("Push", func(): _begin_target("shove_push", "Shove away: choose a creature within 5 ft"), "Replaces one attack: push 5 ft", not mine or not in_combat))))
	cats.Actions.append(_ico(Icons.tex("actions", "door"), _tile(UiKit.button("Door", func(): _begin_target("door", "Door: click a door within 5 ft to open or close it"), "Free: open or close a door next to you", not mine))))
	if c.get("alt", 0) == 0 and c.get("mounted_on", "") == "":
		cats.Actions.append(_ico(Icons.tex("actions", "jump"), _tile(UiKit.button("Jump", func(): _begin_target("jump", "Long jump: click the square to land on"),
			"Free (uses movement): leap in a straight line over water, rough ground or creatures. Up to your Strength score in feet after moving 10 ft, half from standing.", not mine))))
	if eng.fly_speed(c) > 0:
		var alt: int = c.get("alt", 0)
		cats.Actions.append(_ico(Icons.tex("actions", "fly_up"), _tile(UiKit.button("Fly Up", func(): send({"type": "altitude", "actor_id": c.id, "alt": alt + 10}), "Rise 10 ft (costs 10 ft of flying speed). Now %d ft up." % alt, not mine))))
		if alt > 0:
			cats.Actions.append(_ico(Icons.tex("actions", "fly_down"), _tile(UiKit.button("Fly Down", func(): send({"type": "altitude", "actor_id": c.id, "alt": alt - 10}), "Descend 10 ft (costs 10 ft)", not mine))))
			cats.Actions.append(_ico(Icons.tex("actions", "land"), _tile(UiKit.button("Land", func(): send({"type": "altitude", "actor_id": c.id, "alt": 0}), "Descend to the ground (costs %d ft)" % alt, not mine))))
	if c.get("mounted_on", "") != "":
		cats.Actions.append(_ico(Icons.tex("actions", "mountedCombatant"), _tile(UiKit.button("Dismount", func(): send({"type": "dismount", "actor_id": c.id}), "Costs half your speed: step off into an open space next to your mount", not mine))))
	elif c.get("rider", "") == "" and c.get("alt", 0) == 0:
		cats.Actions.append(_ico(Icons.tex("actions", "charger"), _tile(UiKit.button("Mount", func(): _begin_target("mount", "Mount: choose a willing creature within 5 ft, at least one size larger"),
			"Costs half your speed. A trained mount (horse, pony...) acts on your turn and can only move, Dash, Disengage or Dodge; any other mount acts on its own.", not mine))))
	if c.get("notes", {}).get("inspiration", "") == "1":
		var ok: bool = can_control(c) and not c.dead
		cats.Actions.append(_ico(Icons.tex("actions", "lucky"), _tile(UiKit.button("★ Use Inspiration", func(): send({"type": "inspiration", "actor_id": c.id}),
			"Spend your Inspiration: advantage on your next attack roll, saving throw or ability check (works on other turns too)", not ok))))
		cats.Actions.append(_ico(Icons.tex("actions", "inspiringLeader"), _tile(UiKit.button("★ Give Inspiration", func(): _begin_target("give_inspiration", "Give Inspiration: choose another player character"),
			"Pass your Inspiration to another player character who doesn't have it", not ok))))
	if eng.hands_on(c):
		var hands_col := UiKit.vbox(3)
		wbox.add_child(hands_col)
		var opts: Array = [""] + eng.hand_options(c)
		var label := func(h: String) -> String:
			return {"": "Empty", "shield": "Shield", "focus": "Focus"}.get(h, Equipment.WEAPONS.get(h, {}).get("name", h))
		for hi in 2:
			var hb := MenuButton.new()
			hb.text = "%s: %s ▾" % [["Main", "Off"][hi], label.call(c.hands[hi])]
			hb.flat = false
			hb.disabled = not mine
			hb.tooltip_text = "What this hand holds. Drawing or stowing one item is free each turn; a second, or a shield, takes your action. Somatic spells need a free hand; a focus covers material components."
			for i in opts.size():
				hb.get_popup().add_item(label.call(opts[i]), i)
			hb.get_popup().id_pressed.connect(func(i):
				var want: Array = c.hands.duplicate()
				want[hi] = opts[i]
				if Equipment.WEAPONS.get(opts[i], {}).get("props", []).has("twoHanded"):
					want = [opts[i], opts[i]]
				elif Equipment.WEAPONS.get(want[1 - hi], {}).get("props", []).has("twoHanded"):
					want[1 - hi] = ""
				send({"type": "hands", "actor_id": c.id, "hands": want}))
			hb.custom_minimum_size = Vector2(110, 0)
			hb.add_theme_font_size_override("font_size", 12)
			hands_col.add_child(hb)
	if eng.has_cond(c, "prone"):
		cats.Actions.append(_ico(Icons.tex("actions", "standUp"), _tile(UiKit.button("Stand Up", func(): send({"type": "action", "actor_id": c.id, "action": "standUp"}), "Costs half your speed", not mine))))
	if eng.has_cond(c, "grappled") or eng.has_cond(c, "restrained"):
		cats.Actions.append(_ico(Icons.tex("actions", "escape"), _tile(UiKit.button("Escape", func(): send({"type": "action", "actor_id": c.id, "action": "escape"}), "Action: break free", not mine))))
	cats.Actions.append(_ico(Icons.tex("actions", "stabilize"), _tile(UiKit.button("Stabilize", func(): _begin_target("stabilize", "Stabilize: choose a dying creature within 5 ft"), "Action: DC 10 Medicine check", not mine or not in_combat))))
	cats.Actions.append(_ico(Icons.tex("actions", "wake"), _tile(UiKit.button("Wake", func(): _begin_target("wake", "Wake: choose a sleeping creature within 5 ft"), "Action: shake awake a creature under Sleep", not mine or not in_combat))))
	for a in eng.bonus_actions_allowed(c):
		cats.Actions.append(_ico(Icons.tex("actions", a), _tile(UiKit.button("⚡" + a.capitalize(), func(): send({"type": "action", "actor_id": c.id, "action": a, "via": "bonus"}), "Bonus action (%s)" % ("Cunning Action" if c.features.has("cunningAction") else "trait"), not mine or not in_combat))))
	# Items: potions can be drunk from the bar; the rest are listed for reference.
	var carried: Array = c.get("items", [])
	for i in carried.size():
		var it := Items.get_item(carried[i].get("id", ""))
		if it.is_empty():
			continue
		if it.get("kind", "") == "potion":
			cats.Items.append(_ico(Icons.item_tex(carried[i].get("id", "")), _tile(UiKit.button("🧪 " + it.name, func(): send({"type": "useItem", "actor_id": c.id, "index": i}), it.get("desc", "") + "\nTakes an action.", not mine))))
		else:
			cats.Items.append(_ico(Icons.item_tex(carried[i].get("id", "")), _tile(UiKit.button(carried[i].get("name", it.name), func(): pass, it.get("desc", ""), true))))
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
		cats.Actions.append(_ico(Icons.tex("actions", f[1]), _tile(UiKit.button("★ " + f[0], func(): send({"type": "feature", "actor_id": c.id, "feature": f[1], "choice": f[2]}), f[3], not mine))))
	if c.features.has("layOnHands"):
		cats.Actions.append(_ico(Icons.tex("actions", "layOnHands"), _tile(UiKit.button("★ Lay on Hands", func(): _begin_target("layOnHands", "Lay on Hands: choose a creature to touch"), "Action: heal from your pool (%d left)" % eng.res_left(c, "lay_on_hands"), not mine))))
	if eng.has_tag(c, "spiritual_weapon"):
		cats.Actions.append(_ico(Icons.tex("actions", "spiritualWeapon"), _tile(UiKit.button("★ Spiritual Weapon", func(): _begin_target("spiritualWeapon", "Spiritual Weapon: choose a creature within 60 ft"), "Bonus: attack with your spiritual weapon", not mine))))
	if c.features.has("healer"):
		cats.Actions.append(_ico(Icons.tex("actions", "healerKit"), _tile(UiKit.button("★ Healer's Kit", func(): _begin_target("healerKit", "Healer's kit: choose a creature to touch"), "Action: heal 1d6 + 4 + its level, once per creature per rest", not mine))))
	if c.features.has("grappler"):
		cats.Actions.append(_ico(Icons.tex("actions", "pin"), _tile(UiKit.button("★ Pin", func(): _begin_target("pin", "Pin: choose the creature you're grappling"), "Action: grapple check to restrain you both", not mine or not in_combat))))
	if c.features.has("inspiringLeader"):
		cats.Actions.append(_ico(Icons.tex("actions", "inspiringLeader"), _tile(UiKit.button("★ Inspiring Speech", func(): send({"type": "feature", "actor_id": c.id, "feature": "inspiringLeader"}), "Out of combat: you and up to 5 allies within 30 ft gain temp HP", not mine or in_combat))))
	if c.features.has("bardicInspiration"):
		cats.Actions.append(_ico(Icons.tex("actions", "bardicInspiration"), _tile(UiKit.button("★ Inspire", func(): _begin_target("bardicInspiration", "Bardic Inspiration: choose an ally within 60 ft"), "Bonus: give an inspiration die", not mine))))
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
		cats.Actions.append(_ico(Icons.tex("actions", "fontOfMagic"), _tile(mb)))
	if c.fdata.has("wild_shape"):
		cats.Actions.append(_ico(Icons.tex("actions", "revertShape"), _tile(UiKit.button("★ Revert Form", func(): send({"type": "feature", "actor_id": c.id, "feature": "revertShape"}), "Bonus: return to your normal form", not mine))))
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
		cats.Actions.append(_ico(Icons.tex("actions", "wildShape"), _tile(ws)))
	var side := UiKit.vbox(5)
	if Net.me.is_dm and c.kind == "npc" and mine and in_combat:
		side.add_child(UiKit.button("Auto-play turn", func(): send({"type": "autoTurn"}), "Let the simple AI run this monster's turn"))
	var end_btn = UiKit.button("End Turn ⏎", func(): send({"type": "endTurn", "actor_id": c.id}), "", not (in_combat and mine))
	end_btn.modulate = UiKit.GOLD
	end_btn.custom_minimum_size = Vector2(110, 64)
	end_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(end_btn)

	# Options (bonus attack, smite, slot level, reactions, light...) live behind the ⚙ tab.
	row_opts.add_child(UiKit.check("Bonus-action attack", opts.bonus, func(on): opts.bonus = on))
	var hit_maneuvers: Array = c.fdata.get("maneuvers", []).filter(func(m): return m in ["trip", "pushing", "menacing", "distracting"])
	if not hit_maneuvers.is_empty():
		var mitems: Array = ["Maneuver: —"] + hit_maneuvers.map(func(m): return Creator.MANEUVERS[m][0])
		var mo = UiKit.option(mitems, hit_maneuvers.find(opts.maneuver) + 1)
		mo.item_selected.connect(func(i): opts.maneuver = "" if i == 0 else hit_maneuvers[i - 1])
		mo.tooltip_text = "Spend a superiority die (%d left) when the attack hits" % eng.res_left(c, "superiority")
		row_opts.add_child(mo)
	if c.features.has("greatWeaponMaster") or c.features.has("sharpshooter"):
		row_opts.add_child(UiKit.check("−5/+10", opts.power, func(on): opts.power = on))
	if c.features.has("recklessAttack"):
		row_opts.add_child(UiKit.check("Reckless", opts.reckless, func(on): opts.reckless = on))
	if c.features.has("divineSmite") and not sc.is_empty():
		var items := ["Smite: lowest slot"]
		for lv in range(1, 6):
			if eng.slots_left(c, lv) > 0:
				items.append("Smite lv %d" % lv)
		var ob = UiKit.option(items)
		for i in items.size():
			if items[i] == "Smite lv %d" % opts.smite:
				ob.select(i)
		ob.item_selected.connect(func(i): opts.smite = 0 if i == 0 else int(items[i].split(" ")[-1]))
		ob.tooltip_text = "Divine Smite is offered after a melee hit; this picks the slot level it offers"
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
	if not sc.is_empty() and ["bard", "cleric", "druid", "wizard"].any(func(k): return eng.class_lv(c, k) > 0):
		var rc := UiKit.check("Cast rituals as rituals", opts.ritual, func(on):
			opts.ritual = on
			_build_actions())
		rc.tooltip_text = "Ritual Casting: a ritual spell takes 10 minutes longer and uses no spell slot (outside combat only)."
		row_opts.add_child(rc)
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

	# Button area: actions | spells | items in a rows x cols grid of icon slots, in the player's own
	# order. Empty slots fill the rest; past the last column it scrolls.
	var area := PanelContainer.new()
	var edge := StyleBoxFlat.new()
	edge.bg_color = Color(0, 0, 0, 0)
	if _bar_unlocked:
		edge.border_color = UiKit.GOLD
		edge.set_border_width_all(1)
	area.add_theme_stylebox_override("panel", edge)
	area.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mid.add_child(area)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 0)
	area.add_child(av)
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 0)
	if _bar_unlocked:
		av.add_child(_grip(true))
	av.add_child(ah)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # the wheel scrolls it; a bar would cost a row's height
	var step := _slot + SLOT_GAP
	scroll.custom_minimum_size = Vector2(_bar_cols * step + 12, _bar_rows * step)
	ah.add_child(scroll)
	if _bar_unlocked:
		ah.add_child(_grip(false))
	var sections := UiKit.hbox(4)
	scroll.add_child(sections)
	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	var order: Array = cfg.get_value("bar_order", c.name, [])
	_bar_keys = []
	var used := 0
	for k in cats:
		var tiles: Array = cats[k]
		if tiles.is_empty():
			continue
		var rank := func(t: Control) -> int:
			var at := order.find(_key(t))
			return at if at >= 0 else order.size() + tiles.find(t)
		tiles.sort_custom(func(x, y): return rank.call(x) < rank.call(y))
		if sections.get_child_count() > 0:
			sections.add_child(_divider())
		var grid := _slot_grid(ceili(tiles.size() / float(_bar_rows)))
		grid.tooltip_text = k
		sections.add_child(grid)
		used += grid.columns
		for t in tiles:
			_bar_keys.append(_key(t))
			_draggable(t, c.name)
			grid.add_child(t)
		for i in grid.columns * _bar_rows - tiles.size():
			grid.add_child(_empty_slot())
	if used < _bar_cols:
		var empty := _slot_grid(_bar_cols - used)
		for i in empty.columns * _bar_rows:
			empty.add_child(_empty_slot())
		sections.add_child(empty)
	_action_box.add_child(side)
	var corner := UiKit.vbox(6)
	corner.size_flags_vertical = Control.SIZE_SHRINK_END
	var lock_btn := UiKit.button("Lock" if _bar_unlocked else "Unlock", func():
		_bar_unlocked = not _bar_unlocked
		_build_actions(), "Unlock the hotbar, then drag its gold top or right edge to resize it (more rows or columns of slots)")
	lock_btn.add_theme_font_size_override("font_size", 12)
	if _bar_unlocked:
		lock_btn.modulate = UiKit.GOLD
	corner.add_child(lock_btn)
	var opt_btn := UiKit.button("⚙", func():
		_opts_panel.visible = not _opts_panel.visible, "Options: bonus-action attacks, smite and slot levels, reactions, light")
	opt_btn.custom_minimum_size = Vector2(52, 52)
	if _opts_panel.visible:
		opt_btn.modulate = UiKit.GOLD
	corner.add_child(opt_btn)
	_action_box.add_child(corner)


func _slot_grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = maxi(1, cols)
	g.add_theme_constant_override("h_separation", SLOT_GAP)
	g.add_theme_constant_override("v_separation", SLOT_GAP)
	return g


func _empty_slot() -> Control:
	var e := TextureRect.new()
	e.texture = load("res://assets/ui/slot.png")
	e.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	e.custom_minimum_size = Vector2(_slot, _slot)
	return e


## The red line between the actions, spells and items sections.
func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(0.55, 0.1, 0.08)
	d.custom_minimum_size = Vector2(3, _bar_rows * (_slot + SLOT_GAP) - SLOT_GAP)
	return d


## A gold strip along the button area's top (rows) or right (columns) edge; pressing it starts a
## resize, which _input follows even as the bar rebuilds under the mouse.
func _grip(top: bool) -> Control:
	var g := ColorRect.new()
	g.color = UiKit.GOLD
	g.custom_minimum_size = Vector2(0, 5) if top else Vector2(5, 0)
	g.mouse_default_cursor_shape = Control.CURSOR_VSIZE if top else Control.CURSOR_HSIZE
	g.tooltip_text = "Drag to change the number of %s" % ("rows" if top else "columns")
	g.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_resize = {"from": e.global_position, "rows": _bar_rows, "cols": _bar_cols, "top": top})
	return g


func _input(event: InputEvent) -> void:
	if _resize.is_empty():
		return
	if event is InputEventMouseMotion:
		_resize_bar(event.global_position - _resize.from)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_resize = {}
		var cfg := ConfigFile.new()
		cfg.load(PREFS)
		cfg.set_value("hud", "bar_rows", _bar_rows)
		cfg.set_value("hud", "bar_cols", _bar_cols)
		cfg.save(PREFS)
	get_viewport().set_input_as_handled()


## Dragging up adds rows, right adds columns: one per slot of mouse travel.
func _resize_bar(d: Vector2) -> void:
	var step := float(_slot + SLOT_GAP)
	var rows: int = clampi(_resize.rows + roundi(-d.y / step), 1, 6) if _resize.top else _bar_rows
	var cols: int = _bar_cols if _resize.top else clampi(_resize.cols + roundi(d.x / step), 4, 40)
	if rows != _bar_rows or cols != _bar_cols:
		_bar_rows = rows
		_bar_cols = cols
		_build_actions()


## A tile's identity for ordering: its name, which icon-only tiles keep in metadata.
func _key(t: Control) -> String:
	return t.get_meta("bar_key", t.text)


## Makes a tile icon-only: the icon is the button, its name moves to metadata (and the hover card).
func _ico(tex: Texture2D, t: Control) -> Control:
	if tex and t is Button:
		var name_: String = t.text
		for g in ["★\n", "✸\n", "⚔\n", "✦ ", "🧪 "]:
			name_ = name_.trim_prefix(g)
		t.set_meta("bar_key", name_)
		t.text = ""
		t.icon = tex
		t.expand_icon = true
		t.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		t.theme_type_variation = "BarIcon"
	return t


## Lets a bar tile be dragged onto another to move it there; the order is saved per character.
func _draggable(t: Control, who: String) -> void:
	if not t is Button or t is MenuButton:
		return
	var key := _key(t)
	t.set_drag_forwarding(func(_at):
		var pv := TextureRect.new()
		pv.texture = t.icon
		pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pv.size = Vector2(_slot, _slot)
		t.set_drag_preview(pv if t.icon else UiKit.label(key, 14, UiKit.GOLD))
		return {"bar_tile": key},
		func(_at, data): return data is Dictionary and data.has("bar_tile") and data.bar_tile != key,
		func(_at, data):
			var keys: Array = _bar_keys.duplicate()
			keys.erase(data.bar_tile)
			keys.insert(keys.find(key), data.bar_tile)
			var cfg := ConfigFile.new()
			cfg.load(PREFS)
			cfg.set_value("bar_order", who, keys)
			cfg.save(PREFS)
			_build_actions())


func _tex_box(file: String, margin: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/" + file)
	sb.set_texture_margin_all(margin)
	return sb


## BG3-like look for the bar (assets/ui from tools/ui/bar_art.py): bronze-framed buttons on dark
## leather, and "BarIcon" buttons that are just their icon with a gold ring on hover.
func _bar_theme() -> Theme:
	var t := Theme.new()
	var looks := {"normal": "button.png", "hover": "button_hover.png", "pressed": "button_pressed.png", "disabled": "button.png"}
	for kind in ["Button", "MenuButton", "OptionButton"]:
		for st in looks:
			var sb := _tex_box(looks[st], 12)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			if st == "disabled":
				sb.modulate_color = Color(0.6, 0.6, 0.6)
			t.set_stylebox(st, kind, sb)
		t.set_color("font_color", kind, Color(0.93, 0.86, 0.7))
		t.set_color("font_disabled_color", kind, Color(0.5, 0.46, 0.4))
	t.set_type_variation("BarIcon", "Button")
	var none := StyleBoxEmpty.new()
	none.set_content_margin_all(1)
	var ring := _tex_box("slot_ring.png", 12)
	ring.set_content_margin_all(1)
	for st in ["normal", "disabled", "focus"]:
		t.set_stylebox(st, "BarIcon", none)
	t.set_stylebox("hover", "BarIcon", ring)
	t.set_stylebox("pressed", "BarIcon", ring)
	t.set_color("icon_disabled_color", "BarIcon", Color(0.38, 0.36, 0.34))
	t.set_color("icon_normal_color", "BarIcon", Color.WHITE)
	return t


## Portrait framed in gold; red rises from the bottom as HP is lost, with HP/max over it.
func _portrait(c: Dictionary) -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.09)
	sb.border_color = UiKit.GOLD.darkened(0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", sb)
	var box := Control.new()
	var side := _action_panel.custom_minimum_size.y - 26  # the bar's height inside its margins and this frame
	box.custom_minimum_size = Vector2(side, side)
	box.clip_contents = true
	frame.add_child(box)
	var pic := TextureRect.new()
	pic.texture = TokenScript.portrait_of(c)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(pic)
	if pic.texture == null:  # no mini to show: the token colour and an initial
		sb.bg_color = Color.from_string(c.get("color", "#555555"), Color.DIM_GRAY).darkened(0.4)
		var ini := UiKit.label(c.name.left(1), 54, UiKit.PARCHMENT)
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ini.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(ini)
	var lost := 0.0 if c.max_hp <= 0 else clampf(1.0 - float(c.hp) / c.max_hp, 0.0, 1.0)
	var red := ColorRect.new()
	red.color = Color(0.7, 0.04, 0.04, 0.6)
	red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	red.anchor_top = 1.0 - lost
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(red)
	var hp := UiKit.label("%d/%d%s" % [c.hp, c.max_hp, (" +%d" % c.temp_hp) if c.temp_hp > 0 else ""], 17, Color.WHITE)
	hp.add_theme_constant_override("outline_size", 6)
	hp.add_theme_color_override("font_outline_color", Color.BLACK)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_child(hp)
	frame.tooltip_text = "%s: %d of %d hit points" % [c.name, c.hp, c.max_hp]
	return frame


## Shapes a hotbar button into a square-ish tile with its name wrapped under the icon, and gives
## a plain tooltip a title so every hover card reads the same.
func _tile(b: Control) -> Control:
	b.custom_minimum_size = Vector2(_slot, _slot)
	if b.tooltip_text != "" and not b.tooltip_text.begins_with("[b]"):
		var title: String = b.text.trim_prefix("⚔ ").trim_prefix("★ ").trim_prefix("✸ ").trim_prefix("🧪 ").trim_suffix(" ▾")
		var raw: String = SrdText.TILES.get(title.get_slice(" (", 0), "")
		if raw != "":
			b.tooltip_text = "[b][color=#f2c66d]%s[/color][/b]\n%s\n[color=#7d766b]In this game: %s[/color]" % [_esc(title), _esc(raw), b.tooltip_text]
		else:
			b.tooltip_text = "[b][color=#f2c66d]%s[/color][/b]\n%s" % [_esc(title), b.tooltip_text]
	b.add_theme_font_size_override("font_size", 10)
	b.clip_contents = true
	if b is Button:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		if not b is MenuButton:
			b.text = b.text.replace("⚔ ", "⚔\n").replace("★ ", "★\n").replace("✸ ", "✸\n").replace("🧪 ", "")
	return b


## The numbers a player checks every turn: HP, AC, speed, death saves, slots, conditions and effects.
func _vitals_text(c: Dictionary) -> String:
	var bits := PackedStringArray()
	var f: float = 0.0 if c.max_hp <= 0 else float(c.hp) / c.max_hp
	var hp_col := "8fe39a" if f > 0.5 else ("f2c66d" if f > 0.25 else "ff5a5a")
	bits.append("HP [color=#%s][b]%d[/b][/color]/%d%s" % [hp_col, c.hp, c.max_hp, (" [color=#8fd3ff]+%d temp[/color]" % c.temp_hp) if c.temp_hp > 0 else ""])
	bits.append("AC [b]%d[/b]" % eng.ac_of(c))
	bits.append("Speed %d ft" % eng.speed_of(c))
	if eng.is_dying(c):
		var ds: Dictionary = c.death_saves
		bits.append("Death saves [color=#8fe39a]%s[/color][color=#555]%s[/color] [color=#ff5a5a]%s[/color][color=#555]%s[/color]" % [
			"✓".repeat(ds.successes), "○".repeat(3 - ds.successes), "✗".repeat(ds.failures), "○".repeat(3 - ds.failures)])
	var sc: Dictionary = c.spellcasting
	if not sc.is_empty():
		for lv in range(1, 10):
			var total: int = sc.slots[lv] + (sc.pact.max if not sc.pact.is_empty() and sc.pact.level == lv else 0)
			if total > 0:
				var left := eng.slots_left(c, lv)
				bits.append("%s [color=#b0a0ff]%s[/color][color=#555]%s[/color]" % [SPELL_LEVEL_NAMES[lv], "●".repeat(left), "○".repeat(total - left)])
	for k in eng.conditions_of(c):
		if k != "incapacitated" or eng.conditions_of(c).size() == 1:
			bits.append("[url=cond:%s][color=#ff9a6a]%s[/color][/url]" % [k, k.capitalize()])
	if c.exhaustion > 0:
		bits.append("[url=cond:exhaustion][color=#ff9a6a]Exhaustion %d[/color][/url]" % c.exhaustion)
	if not c.concentration.is_empty():
		bits.append("[color=#b0a0ff]Concentrating: %s[/color]" % _esc(c.concentration.name))
	for e in eng.effects_on(c):
		if e.get("conditions", []).is_empty():
			bits.append("[color=#c9b8ff]%s[/color]" % _esc(e.name))
	return "   ".join(bits)


func _slot_for(c: Dictionary, sp: Dictionary) -> int:
	if sp.level == 0 or _cast_opts(sp).ritual:
		return sp.level
	if opts.slot >= sp.level and eng.slots_left(c, opts.slot) > 0:
		return opts.slot
	var pact: Dictionary = c.spellcasting.pact
	if not pact.is_empty() and pact.level >= sp.level and pact.used < pact.max:
		return pact.level
	return eng.lowest_slot(c, sp.level)


func _cast_opts(sp: Dictionary) -> Dictionary:
	return {"quickened": opts.quickened, "careful": opts.careful, "heightened": opts.heightened, "ritual": opts.ritual and sp.get("ritual", false)}


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


## Kenney kits under assets/kenney: kit name -> sorted model names.
func _props() -> Dictionary:
	if _prop_catalog.is_empty():
		for kit in ResourceLoader.list_directory(BoardScript.KIT_DIR):
			if kit.ends_with("/"):
				var models := Array(ResourceLoader.list_directory(BoardScript.KIT_DIR + kit)).filter(func(f): return f.ends_with(".glb")).map(func(f): return f.get_basename())
				models.sort()
				_prop_catalog[kit.trim_suffix("/")] = models
	return _prop_catalog


func _prop_name() -> String:
	var kit: String = _props().keys()[prop_kit]
	return kit + "/" + _props()[kit][prop_model]


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
		send({"type": "cast", "actor_id": c.id, "spell_id": spell_id, "slot": _slot_for(c, sp), "options": _cast_opts(sp)})
		return
	_set_mode("spell", {"spell_id": spell_id, "spell": sp, "slot": _slot_for(c, sp)})


func _begin_power(power_id: String) -> void:
	var c := sel()
	var pw := eng.find_power(c, power_id)
	if pw.spell.target.type == "self" or (pw.spell.target.type == "area" and pw.spell.target.shape == "sphere" and pw.spell.target.origin == "self"):
		send({"type": "power", "actor_id": c.id, "power_id": power_id})
		return
	_set_mode("power", {"power_id": power_id, "spell": pw.spell, "slot": 0})


func _begin_legendary(la: Dictionary) -> void:
	var c := sel()
	var sp: Dictionary = la.get("spell", {})
	if la.has("attack"):
		var p := eng.find_attack(c, la.attack)
		sp = {"name": la.name, "range": p.reach if p.range == "melee" else p.long, "target": {"type": "creature", "count": 1}}
	if sp.target.type in ["self", "area"] and sp.target.get("origin", "self") == "self":
		send({"type": "legendary", "actor_id": c.id, "action_id": la.id})
		return
	_set_mode("power", {"legendary_id": la.id, "spell": sp, "slot": 0})


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
	if mode_data.has("legendary_id"):
		send({"type": "legendary", "actor_id": c.id, "action_id": mode_data.legendary_id, "targets": picked.duplicate(), "point": point})
	elif mode == "power":
		send({"type": "power", "actor_id": c.id, "power_id": mode_data.power_id, "targets": picked.duplicate(), "point": point})
	else:
		send({"type": "cast", "actor_id": c.id, "spell_id": mode_data.spell_id, "slot": mode_data.slot, "targets": picked.duplicate(), "point": point, "options": _cast_opts(mode_data.spell)})
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
		"prop":
			if mode_data.erase:
				send({"type": "removeProps", "cells": [{"x": cell.x, "y": cell.y}]})
			else:
				send({"type": "placeProp", "m": _prop_name(), "x": cell.x, "y": cell.y, "r": prop_rot, "h": prop_h})
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
				"options": {"bonus": o.bonus, "power": o.power, "maneuver": o.maneuver, "reckless": o.reckless, "smite": o.smite, "stunning_strike": o.stunning, "open_hand": o.open_hand}})
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
			if mode_data.kind == "jump":
				send({"type": "jump", "actor_id": c.id, "to": cell})
				cancel_mode()
				return
			if tid == "":
				return
			match mode_data.kind:
				"help", "wake", "stabilize":
					send({"type": "action", "actor_id": c.id, "action": mode_data.kind, "target_id": tid})
				"mount":
					send({"type": "mount", "actor_id": c.id, "target_id": tid})
				"give_inspiration":
					send({"type": "inspiration", "actor_id": c.id, "target_id": tid})
				"grapple":
					send({"type": "grapple", "actor_id": c.id, "target_id": tid, "bonus": opts.bonus})
				"shove_prone", "shove_push":
					send({"type": "shove", "actor_id": c.id, "target_id": tid, "mode": "prone" if mode_data.kind == "shove_prone" else "push", "bonus": opts.bonus})
				"layOnHands", "bardicInspiration", "spiritualWeapon", "healerKit", "pin":
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
		elif mode == "ruler" and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			mode_data["rise"] = mode_data.get("rise", 0) + (Grid.FT if event.keycode == KEY_PAGEUP else -Grid.FT)
			_update_overlays()


# ---------------- Overlays & prompt ----------------

func _update_overlays() -> void:
	if board == null or state.is_empty():
		return
	for l in ["reach", "area", "path", "targets"]:
		board.clear_layer(l)
	board.clear_guides()
	board.show_cost(Vector2i.ZERO, "")
	var c := sel()
	var prompt := ""
	var buttons := []
	match mode:
		"paint":
			var names := {Grid.FLOOR: "floor", Grid.WALL: "walls", Grid.DIFFICULT: "difficult terrain", Grid.WATER: "water (double cost without a swim speed)", Grid.DOOR: "doors", Grid.LOW_WALL: "low walls (half cover)", LIGHT_BRUSH: "ambient light",
				LIGHT_BRUSH + 1 + Grid.DARK: "darkness", LIGHT_BRUSH + 1 + Grid.DIM: "dim light", LIGHT_BRUSH + 1 + Grid.BRIGHT: "bright light"}
			prompt = "Painting %s — click or drag on the map. Right-click to stop." % names[paint_type]
			var cells := painting.keys()
			var colors := cells.map(func(p): return {Grid.FLOOR: Color(0.6, 0.6, 0.6, 0.5), Grid.WALL: Color(0.2, 0.2, 0.25, 0.8),
				Grid.DIFFICULT: Color(0.3, 0.6, 0.2, 0.6), Grid.WATER: Color(0.15, 0.4, 0.75, 0.6), Grid.DOOR: Color(0.55, 0.35, 0.15, 0.8), Grid.LOW_WALL: Color(0.45, 0.42, 0.4, 0.7), LIGHT_BRUSH: Color(0.5, 0.5, 0.6, 0.4), LIGHT_BRUSH + 1 + Grid.DARK: Color(0.05, 0.05, 0.1, 0.7),
				LIGHT_BRUSH + 1 + Grid.DIM: Color(0.5, 0.45, 0.3, 0.5), LIGHT_BRUSH + 1 + Grid.BRIGHT: Color(1.0, 0.9, 0.5, 0.5)}[painting[p]])
			board.set_layer_colors("paint", cells, colors)
		"ruler":
			# Measures from the clicked square, or from the selected creature until one is clicked.
			var start = mode_data.get("start")
			var rise: int = mode_data.get("rise", 0)
			prompt = "Ruler: click a starting square. R or right-click to stop."
			if (start != null or not c.is_empty()) and Grid.in_bounds(state.map, _hover_cell.x, _hover_cell.y):
				var g: Vector2i = Grid._gap(c.pos, Grid.size_cells(c.csize), _hover_cell, 1) if start == null else (_hover_cell - (start as Vector2i)).abs()
				var ft := Grid.grid_distance_3d(g.x, g.y, rise / Grid.FT, state.settings.diagonal)
				var a: Vector2 = Grid.center(c) if start == null else Vector2(start) + Vector2(0.5, 0.5)
				var top := Vector3(_hover_cell.x + 0.5, rise / float(Grid.FT), _hover_cell.y + 0.5)
				var gold := Color(1.0, 0.85, 0.3, 0.9)
				board.guide_line(Vector3(a.x, 0.06, a.y), top + Vector3(0, 0.06, 0), gold, 0.1)
				if rise != 0:
					board.guide_line(Vector3(top.x, 0.06, top.z), top, Color(gold, 0.6), 0.05)
				board.set_layer("path", ([] if start == null else [start]) + [_hover_cell], Color(1.0, 0.85, 0.3, 0.5))
				var h: String = "" if rise == 0 else " (%s%d ft)" % ["up " if rise > 0 else "down ", absi(rise)]
				board.show_label(top + Vector3(0, 0.6, 0), "%d ft%s" % [ft, h])
				prompt = "Ruler: %d ft (%d squares)%s from %s. Click to set the start; PgUp/PgDn changes height; R or right-click to stop." % [
					ft, ft / Grid.FT, h, "there" if start != null else c.name]
		"prop":
			prompt = ("Click squares to remove their props." if mode_data.erase else "Click the map to place %s." % _prop_name()) + " Right-click to stop."
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
			board.outline_cells(_cells_within(c, p.normal if p.range == "ranged" else p.reach), Color(1, 0.45, 0.3, 0.85))
			if p.range == "ranged" and p.long > p.normal:
				board.outline_cells(_cells_within(c, p.long), Color(1, 0.45, 0.3, 0.35))
			var hid := _token_at(_hover_cell, _hover_token)
			if hid != "" and hid != c.id:
				var t := eng.get_c(hid)
				var err := eng.validate_attack(c, t, p)
				_aim(c, Grid.center(t), eng.dist(c, t), err == "")
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
					board.outline_cells(_cells_within(c, maxi(5, sp.range)), SPELL_RANGE_COLOR)
					var hid := _token_at(_hover_cell, _hover_token)
					if hid != "" and hid != c.id:
						var t := eng.get_c(hid)
						_aim(c, Grid.center(t), eng.dist(c, t), eng.dist(c, t) <= maxi(5, sp.range))
					if not picked.is_empty():
						buttons.append(["Cast now", func(): _cast_now()])
				"point":
					prompt = "%s: choose a destination within %d ft." % [sp.name, sp.range]
					var r := _cells_within(c, sp.range).filter(func(p): return Grid.cell_at(state.map, p.x, p.y) != Grid.WALL)
					board.set_layer("reach", r, Color(0.5, 0.4, 1.0, 0.25))
					board.outline_cells(r, SPELL_RANGE_COLOR)
				"area":
					prompt = "%s: aim with the mouse and click." % sp.name if tgt.origin == "self" else "%s: choose the center (range %d ft)." % [sp.name, sp.range]
					if Grid.in_bounds(state.map, _hover_cell.x, _hover_cell.y):
						var cells := Grid.area_cells(state, c, tgt, _hover_cell)
						var dtype: String = sp.damage[0].type if sp.has("damage") else ""
						var col: Color = board.DAMAGE_COLORS.get(dtype, Color(0.7, 0.6, 1.0))
						var out_of_range: bool = tgt.origin == "point" and Grid.distance_to_cell(state, c, _hover_cell) > sp.range
						board.set_layer("area", cells, Color(col, 0.2) if out_of_range else Color(col, 0.5))
						board.outline_cells(cells, Color(col, 0.4) if out_of_range else Color(col, 0.95))
						if tgt.origin == "point":
							board.outline_cells(_cells_within(c, sp.range), SPELL_RANGE_COLOR)
							_aim(c, Vector2(_hover_cell) + Vector2(0.5, 0.5), Grid.distance_to_cell(state, c, _hover_cell), not out_of_range)
						var hit := Grid.creatures_in_cells(state, cells).map(func(o): return o.name)
						if not hit.is_empty():
							prompt += "  Hits: " + ", ".join(hit)
						if out_of_range:
							prompt += "  (out of range)"
		"target":
			prompt = mode_data.prompt
		_:
			var mover: Dictionary = {} if c.is_empty() else eng.mover_of(c)
			if not c.is_empty() and can_act_now(c) and eng.speed_of(mover) > 0 and not c.dead and (mover.id != c.id or c.get("mounted_on", "") == ""):
				var budget := eng.movement_left(mover) if eng.in_combat() else 60
				if budget > 0:
					var reach := Grid.reachable(state, mover, budget, eng.move_rules(mover))
					var cells: Array = reach.cells.keys().filter(func(p): return p != c.pos)
					board.set_layer("reach", cells, Color(0.3, 0.6, 1.0, 0.22))
					if reach.cells.has(_hover_cell) and _hover_cell != c.pos and _token_at(_hover_cell, _hover_token) == "":
						var path := Grid.path_to(reach, _hover_cell)
						board.set_layer("path", path.map(func(s): return s.pos), Color(1.0, 0.85, 0.3, 0.55))
						board.show_cost(_hover_cell, "%d ft" % reach.cells[_hover_cell])
	if mode != "" and mode != "paint" and mode != "spawn" and mode != "prop":
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


## Squares within `ft` of creature `c` by the table's diagonal rule, clipped to the map.
func _cells_within(c: Dictionary, ft: int) -> Array:
	var out := []
	var n := ft / Grid.FT
	var size := Grid.size_cells(c.csize)
	for y in range(maxi(0, c.pos.y - n), mini(state.map.height, c.pos.y + size + n)):
		for x in range(maxi(0, c.pos.x - n), mini(state.map.width, c.pos.x + size + n)):
			if Grid.distance_to_cell(state, c, Vector2i(x, y)) <= ft:
				out.append(Vector2i(x, y))
	return out


## A line from `c` to the aimed point with the distance over it; red when it's out of reach.
func _aim(c: Dictionary, to: Vector2, ft: int, ok: bool) -> void:
	var a := Grid.center(c)
	board.guide_line(Vector3(a.x, 0.06, a.y), Vector3(to.x, 0.06, to.y), Color(1, 0.95, 0.8, 0.85) if ok else Color(1, 0.3, 0.25, 0.85))
	board.show_label(Vector3(to.x, 0.9, to.y), "%d ft" % ft)


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
	_side_btns[1].visible = Net.me.is_dm
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
		if c.kind == "pc" and c.level < 20:
			r.add_child(UiKit.button("Grant Level", func(): send({"type": "levelUp", "ids": [c.id]}), "Let this character's player level up"))
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
	for pair in [["Wall", Grid.WALL], ["Low wall", Grid.LOW_WALL], ["Door", Grid.DOOR], ["Difficult", Grid.DIFFICULT], ["Water", Grid.WATER], ["Floor", Grid.FLOOR]]:
		var b = UiKit.button(pair[0], func():
			paint_type = pair[1]
			_set_mode("paint", {}))
		if mode == "paint" and paint_type == pair[1]:
			b.modulate = UiKit.GOLD
		r3.add_child(b)
	r3.add_child(UiKit.button("Clear", func(): send({"type": "clearMap"})))
	_dm_box.add_child(r3)
	# Props: Kenney models placed as scenery. They don't change the rules; paint terrain under them for that.
	var cat := _props()
	var kits: Array = cat.keys()
	if not kits.is_empty():
		var rp = UiKit.hbox()
		var ko := UiKit.option(kits, prop_kit)
		ko.item_selected.connect(func(i):
			prop_kit = i
			prop_model = 0
			_build_dm())
		rp.add_child(ko)
		var mo := UiKit.option(cat[kits[prop_kit]], prop_model)
		mo.item_selected.connect(func(i):
			prop_model = i
			if mode == "prop":
				_update_overlays())
		rp.add_child(mo)
		var place = UiKit.button("Place", func(): _set_mode("prop", {"erase": false}), "Click the map to place this prop")
		var erase = UiKit.button("Erase", func(): _set_mode("prop", {"erase": true}), "Click squares to remove their props")
		if mode == "prop":
			(erase if mode_data.erase else place).modulate = UiKit.GOLD
		rp.add_child(place)
		rp.add_child(erase)
		_dm_box.add_child(rp)
		var rr = UiKit.hbox()
		rr.add_child(UiKit.button("Turn %d°" % (prop_rot * 90), func():
			prop_rot = (prop_rot + 1) % 4
			_build_dm(), "Rotate the next prop a quarter turn"))
		var hs = UiKit.spin(0, 8, prop_h, 60)
		hs.tooltip_text = "Raise the next prop in half-square steps, e.g. a roof on a wall"
		hs.value_changed.connect(func(v): prop_h = int(v))
		rr.add_child(UiKit.label("Height"))
		rr.add_child(hs)
		_dm_box.add_child(rr)
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
	_dm_box.add_child(UiKit.label("Optional rules", 14, UiKit.GOLD))
	for opt in [["encumbrance", "Encumbrance (PHB variant: slower over 5× and 10× Strength in lb)"],
			["components", "Costly spell components (Revivify needs its diamonds, etc.)"],
			["ammunition", "Track ammunition (recover half after a fight)"],
			["hands", "Track hands: draw and stow weapons, free hand for somatic and material components"]]:
		var k: String = opt[0]
		_dm_box.add_child(UiKit.check(opt[1], st.get(k, false), func(on): send({"type": "settings", "settings": {k: on}})))
	var r5 = UiKit.hbox()
	r5.add_child(UiKit.button("Short Rest", func(): send({"type": "rest", "kind": "short"}), "Party: recover short-rest features, spend hit dice"))
	r5.add_child(UiKit.button("Long Rest", func(): send({"type": "rest", "kind": "long"}), "Party: full HP, spell slots and features"))
	r5.add_child(UiKit.button("Level Up Party", func(): send({"type": "levelUp"}), "Every player character gains a level; each player picks their new choices"))
	_dm_box.add_child(r5)
	var r6 = UiKit.hbox()
	r6.add_child(UiKit.button("Save…", func(): main.save_dialog()))
	r6.add_child(UiKit.button("Load…", func(): main.load_dialog()))
	r6.add_child(UiKit.button("New Game", func(): Net.new_game()))
	_dm_box.add_child(r6)


# ---------------- Plan tab: the DM's notes and session planner ----------------
# Kept in state.campaign: {notes, sessions: [{name, notes, scenes: [{name, notes, loot, creatures: [{kind, id, count}], map}]}]}.
# Saved with the game; redact_for never sends it to players.

func _campaign() -> Dictionary:
	return state.get("campaign", {"notes": "", "sessions": []})


## Applies `fn` to a copy of the plan and sends it to the host.
func _plan_edit(fn: Callable, quiet: bool = false) -> void:
	var camp: Dictionary = _campaign().duplicate(true)
	fn.call(camp)
	_plan_quiet = quiet
	send({"type": "campaign", "campaign": camp})
	_plan_quiet = false


func _plan_confirm(text: String, fn: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = text
	d.confirmed.connect(fn)
	d.visibility_changed.connect(func():
		if not d.visible:
			d.queue_free())
	add_child(d)
	d.popup_centered()


## A text box that saves through `set_fn(plan, text)` when it loses focus.
func _plan_text(title: String, text: String, min_h: int, set_fn: Callable) -> void:
	_plan_box.add_child(UiKit.label(title, 14, UiKit.GOLD))
	var te := TextEdit.new()
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size.y = min_h
	te.text = text
	te.focus_exited.connect(func():
		if te.text != text:
			_plan_edit(func(cp): set_fn.call(cp, te.text), true))
	_plan_box.add_child(te)


func _plan_name(text: String, set_fn: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(_t): le.release_focus())
	le.focus_exited.connect(func():
		if le.text != text and le.text.strip_edges() != "":
			_plan_edit(func(cp): set_fn.call(cp, le.text.strip_edges())))
	return le


func _build_plan() -> void:
	_tabs.set_tab_hidden(3, not Net.me.is_dm)
	_side_btns[3].visible = Net.me.is_dm
	if not Net.me.is_dm or _plan_quiet:
		return
	var f := get_viewport().gui_get_focus_owner()
	if (f is TextEdit or f is LineEdit) and _plan_box.is_ancestor_of(f):
		return  # don't rebuild under the DM's typing
	UiKit.clear(_plan_box)
	var camp := _campaign()
	_plan_text("Campaign notes", camp.notes, 140, func(cp, t): cp.notes = t)
	_plan_box.add_child(HSeparator.new())

	var sessions: Array = camp.sessions
	_plan_box.add_child(UiKit.label("Sessions", 18, UiKit.GOLD))
	var r := UiKit.hbox()
	if not sessions.is_empty():
		plan_session = clampi(plan_session, 0, sessions.size() - 1)
		var so := UiKit.option(sessions.map(func(x): return x.name), plan_session)
		so.item_selected.connect(func(i):
			plan_session = i
			plan_scene = 0
			_build_plan())
		r.add_child(so)
	r.add_child(UiKit.button("New session", func():
		plan_session = sessions.size()
		plan_scene = 0
		_plan_edit(func(cp): cp.sessions.append({"name": "Session %d" % (sessions.size() + 1), "notes": "", "scenes": []}))))
	_plan_box.add_child(r)
	if sessions.is_empty():
		return
	var si := plan_session
	var ses: Dictionary = sessions[si]
	r = UiKit.hbox()
	r.add_child(_plan_name(ses.name, func(cp, t): cp.sessions[si].name = t))
	r.add_child(UiKit.button("Delete", func(): _plan_confirm("Delete %s and all its scenes?" % ses.name,
		func(): _plan_edit(func(cp): cp.sessions.remove_at(si)))))
	_plan_box.add_child(r)
	_plan_text("Session notes", ses.notes, 90, func(cp, t): cp.sessions[si].notes = t)

	var scenes: Array = ses.scenes
	_plan_box.add_child(UiKit.label("Scenes & encounters", 16, UiKit.GOLD))
	r = UiKit.hbox()
	if not scenes.is_empty():
		plan_scene = clampi(plan_scene, 0, scenes.size() - 1)
		var sco := UiKit.option(scenes.map(func(x): return x.name), plan_scene)
		sco.item_selected.connect(func(i):
			plan_scene = i
			_build_plan())
		r.add_child(sco)
	r.add_child(UiKit.button("New scene", func():
		plan_scene = scenes.size()
		_plan_edit(func(cp): cp.sessions[si].scenes.append({"name": "Scene %d" % (scenes.size() + 1), "notes": "", "loot": "", "creatures": [], "map": {}}))))
	_plan_box.add_child(r)
	if scenes.is_empty():
		return
	var ci := plan_scene
	var sc: Dictionary = scenes[ci]
	r = UiKit.hbox()
	r.add_child(_plan_name(sc.name, func(cp, t): cp.sessions[si].scenes[ci].name = t))
	r.add_child(UiKit.button("Delete", func(): _plan_confirm("Delete the scene %s?" % sc.name,
		func(): _plan_edit(func(cp): cp.sessions[si].scenes.remove_at(ci)))))
	_plan_box.add_child(r)
	_plan_text("Notes, read-aloud text, NPCs", sc.notes, 110, func(cp, t): cp.sessions[si].scenes[ci].notes = t)
	_plan_text("Loot", sc.loot, 50, func(cp, t): cp.sessions[si].scenes[ci].loot = t)

	_plan_box.add_child(UiKit.label("Creatures", 14, UiKit.GOLD))
	_rebuild_spawn_options()
	for k in sc.creatures.size():
		var e: Dictionary = sc.creatures[k]
		var opt: Array = _spawn_options.filter(func(o): return o.kind == e.kind and o.id == e.id)
		r = UiKit.hbox()
		var l := UiKit.label("%s ×%d" % [opt[0].label if not opt.is_empty() else e.id, e.count])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		r.add_child(UiKit.button("Place…", func():
			spawn_count = e.count
			begin_spawn(e.kind, e.id), "Then click the map"))
		r.add_child(UiKit.button("✕", func(): _plan_edit(func(cp): cp.sessions[si].scenes[ci].creatures.remove_at(k)), "Take off the list"))
		_plan_box.add_child(r)
	plan_add = clampi(plan_add, 0, _spawn_options.size() - 1)
	var ao := UiKit.option(_spawn_options.map(func(o): return o.label), plan_add)
	ao.item_selected.connect(func(i): plan_add = i)
	_plan_box.add_child(ao)
	r = UiKit.hbox()
	r.add_child(UiKit.label("×"))
	var cnt := UiKit.spin(1, 10, plan_count, 60)
	cnt.value_changed.connect(func(v): plan_count = int(v))
	r.add_child(cnt)
	r.add_child(UiKit.button("Add to scene", func():
		var o: Dictionary = _spawn_options[plan_add]
		_plan_edit(func(cp): cp.sessions[si].scenes[ci].creatures.append({"kind": o.kind, "id": o.id, "count": plan_count}))))
	_plan_box.add_child(r)

	_plan_box.add_child(UiKit.label("Map", 14, UiKit.GOLD))
	r = UiKit.hbox()
	r.add_child(UiKit.button("Save current map", func(): _plan_edit(func(cp): cp.sessions[si].scenes[ci].map = state.map.duplicate(true)),
		"Keep a copy of the board (terrain, light, props) with this scene"))
	if not sc.get("map", {}).is_empty():
		r.add_child(UiKit.button("Load scene map", func(): _plan_confirm("Replace the board with this scene's map?",
			func(): send({"type": "setMap", "map": sc.map})), "Put this scene's map on the board"))
	_plan_box.add_child(r)
