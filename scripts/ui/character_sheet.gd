extends PanelContainer
## Dark-mode take on the official 5e (2014) character sheet. Three pages laid out like the paper
## sheet: Character (stats), Spells, and Details. Computed values update live from the rules
## engine; the blank-on-paper fields (background, traits, equipment, backstory...) are editable by
## the DM and the character's player, and are saved with the game.

const PAGES := ["stats", "spells", "details"]
const PAGE_TITLES := {"stats": "Character", "spells": "Spells", "details": "Details"}
const BOX_BG := Color(0.1, 0.1, 0.11, 0.85)  # the dark gray and bronze of the UiKit theme
const BOX_BORDER := Color(0.54, 0.42, 0.23)
const CAPTION := Color(0.74, 0.63, 0.45)
const INK := Color(0.93, 0.88, 0.78)
const FAINT := Color(0.42, 0.39, 0.36)
const TRAITS := {
	"lucky": ["Lucky", "Reroll natural 1s on attacks, checks and saves."],
	"brave": ["Brave", "Advantage on saves against being frightened."],
	"halflingNimbleness": ["Halfling Nimbleness", "Move through the space of any larger creature."],
	"dwarvenResilience": ["Dwarven Resilience", "Advantage on saves against poison; resistance to poison damage."],
	"dwarvenToughness": ["Dwarven Toughness", "+1 hit point per level."],
	"heavyArmorSpeed": ["Dwarven Speed", "Heavy armor doesn't reduce your speed."],
	"feyAncestry": ["Fey Ancestry", "Advantage on saves against being charmed; magic can't put you to sleep."],
	"relentlessEndurance": ["Relentless Endurance", "Once per long rest, drop to 1 HP instead of 0."],
	"savageAttacks": ["Savage Attacks", "Roll one extra weapon die on melee critical hits."],
	"gnomeCunning": ["Gnome Cunning", "Advantage on Int, Wis and Cha saves against magic."],
	"infernalLegacy": ["Infernal Legacy", "Thaumaturgy cantrip; from 3rd level Hellish Rebuke (as 2nd level) and from 5th level Darkness, each once per long rest (Charisma)."],
	"breathWeapon": ["Breath Weapon", "Exhale your draconic ancestry's energy (once per short rest)."],
	"packTactics": ["Pack Tactics", "Advantage when an ally is within 5 ft of the target."],
	"trainedMount": ["Trained Mount", "Trained to accept a rider, who controls it: it acts on the rider's turn and can only move, Dash, Disengage or Dodge."],
	"nimbleEscape": ["Nimble Escape", "Disengage or Hide as a bonus action."],
	"undeadFortitude": ["Undead Fortitude", "Con save (DC 5 + damage) to drop to 1 HP instead of 0, unless radiant or a crit."],
	"aggressive": ["Aggressive", "Bonus action: move up to its speed toward an enemy."],
	"parry": ["Parry", "Reaction: +2 AC against a melee attack that would hit."],
	"magicResistance": ["Magic Resistance", "Advantage on saves against spells."],
	"nonmagicalResistance": ["Resistant to Nonmagical Weapons", "Half bludgeoning, piercing and slashing damage from nonmagical attacks."],
	"nonmagicalImmunity": ["Immune to Nonmagical Weapons", "No bludgeoning, piercing or slashing damage from nonmagical attacks."],
}
const OPTION_NAMES := {
	"dueling": "Fighting Style: Dueling", "defense": "Fighting Style: Defense", "archery": "Fighting Style: Archery",
	"great_weapon": "Fighting Style: Great Weapon Fighting", "two_weapon": "Fighting Style: Two-Weapon Fighting",
	"protection": "Fighting Style: Protection",
	"agonizing_blast": "Invocation: Agonizing Blast", "repelling_blast": "Invocation: Repelling Blast",
	"quickened": "Metamagic: Quickened Spell", "careful": "Metamagic: Careful Spell",
}

var hud: Control
var page := "stats"
var _built := ""
var _binds: Array = []
var _scroll: ScrollContainer
var _body: VBoxContainer
var _tab_btns := {}
var _edit_btn: Button


func _ready() -> void:
	var v := UiKit.vbox(8)
	add_child(v)
	var head := UiKit.hbox(6)
	v.add_child(head)
	var title := UiKit.label("CHARACTER SHEET", 13, CAPTION)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for p in PAGES:
		var b := UiKit.button(PAGE_TITLES[p], func(): show_page(p))
		_tab_btns[p] = b
		head.add_child(b)
	_edit_btn = UiKit.button("Edit / Level Up", func(): hud.open_creator(hud.sel()), "Open this character in the character creator")
	head.add_child(_edit_btn)
	head.add_child(UiKit.button("✕", func(): hud.toggle_sheet(""), "Hide the sheet (C)"))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = UiKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


func show_page(p: String) -> void:
	page = p
	refresh()


## Rebuilds when the creature or page changes; otherwise just updates values in place,
## so typing into a field isn't interrupted by other players' turns.
func refresh() -> void:
	if hud == null or hud.eng == null:
		return
	for p in _tab_btns:
		_tab_btns[p].modulate = UiKit.GOLD if p == page else Color.WHITE
	var c: Dictionary = hud.sel()
	_edit_btn.visible = hud.can_edit_build(c)
	_edit_btn.disabled = hud.eng.in_combat() and not Net.me.is_dm
	_edit_btn.tooltip_text = "Level up or rebuild outside of combat" if _edit_btn.disabled else "Open this character in the character creator"
	var leveling: bool = c.get("pending_level", 0) > c.get("level", 0)
	_edit_btn.text = "Level Up!" if leveling else "Edit / Level Up"
	_edit_btn.modulate = UiKit.GOLD if leveling else Color.WHITE
	var key := "%s|%s|%s|%s" % [c.get("id", ""), page, c.get("redacted", false), hud.can_control(c)]
	if key != _built:
		_built = key
		_rebuild(c)
	_update(c)


func _rebuild(c: Dictionary) -> void:
	_binds.clear()
	UiKit.clear(_body)
	_scroll.scroll_vertical = 0
	if c.is_empty():
		var l := UiKit.label("Select a token to see its character sheet.\n\nRight-drag rotates the camera, middle-drag pans, the wheel zooms.\nWASD pans, Q/E rotate, F focuses the selected token, C toggles this sheet,\nR measures, Alt+click pings the map for everyone.", 15, FAINT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(l)
		return
	if c.get("redacted", false):
		_build_redacted(c)
		return
	match page:
		"spells": _build_spells(c)
		"details": _build_details(c)
		_: _build_stats(c)


func _update(c: Dictionary) -> void:
	if c.is_empty():
		return
	for b in _binds:
		var n = b.node
		if not is_instance_valid(n):
			continue
		match b.kind:
			"text":
				n.text = b.fn.call(c)
			"rich":
				var t: String = b.fn.call(c)
				if not n.has_meta("last") or n.get_meta("last") != t:
					n.set_meta("last", t)
					n.clear()
					n.append_text(t)
				if b.get("hide_box") != null:
					b.hide_box.visible = t != ""
			"field":
				if not n.has_focus():
					var t: String = b.fn.call(c)
					if n.text != t:
						n.text = t
			"check":
				n.set_pressed_no_signal(b.fn.call(c))
			"color":
				n.add_theme_color_override("font_color", b.fn.call(c))


# ---------------- Building blocks ----------------

func _box_style(radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BOX_BG
	sb.border_color = BOX_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb


func _caption(text: String, size: int = 10) -> Label:
	var l := UiKit.label(text.to_upper(), size, CAPTION)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A bordered box with its caption underneath, like the paper sheet.
func _box(caption: String, content: Control, min_h: int = 0, caption_top: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box_style())
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_h > 0:
		p.custom_minimum_size.y = min_h
	var v := UiKit.vbox(3)
	p.add_child(v)
	if caption_top and caption != "":
		v.add_child(_caption(caption))
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	if not caption_top and caption != "":
		v.add_child(_caption(caption))
	return p


func _value(fn: Callable, size: int = 22, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiKit.label("", size, INK)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_binds.append({"node": l, "fn": fn, "kind": "text"})
	return l


func _rich(fn: Callable, size: int = 13) -> RichTextLabel:
	var r := TipRichText.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.meta_underlined = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", INK)
	r.meta_clicked.connect(_on_meta)
	r.meta_hover_started.connect(func(m): r.tooltip_text = _meta_tooltip(str(m)))
	r.meta_hover_ended.connect(func(_m): r.tooltip_text = "")
	_binds.append({"node": r, "fn": fn, "kind": "rich"})
	return r


func _field_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.075)
	sb.border_color = Color(0.29, 0.22, 0.13)
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(4)
	return sb


## An editable sheet field backed by the creature's notes. `default_fn` fills it until edited.
func _field(key: String, multiline: bool, min_h: int = 0, default_fn: Callable = Callable(), size: int = 13) -> Control:
	var c: Dictionary = hud.sel()
	var getter := func(cc: Dictionary) -> String:
		var notes: Dictionary = cc.get("notes", {})
		if notes.has(key):
			return notes[key]
		return default_fn.call(cc) if default_fn.is_valid() else ""
	var editable: bool = hud.can_control(c)
	var commit := func(text: String) -> void:
		var cc: Dictionary = hud.sel()
		if cc.is_empty() or text == getter.call(cc):
			return
		hud.send({"type": "setNotes", "id": cc.id, "key": key, "value": text})
	var n: Control
	if multiline:
		var te := TextEdit.new()
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.editable = editable
		te.custom_minimum_size.y = maxi(min_h, 40)
		te.focus_exited.connect(func(): commit.call(te.text))
		n = te
	else:
		var le := LineEdit.new()
		le.editable = editable
		le.alignment = HORIZONTAL_ALIGNMENT_CENTER
		le.text_submitted.connect(func(t):
			commit.call(t)
			le.release_focus())
		le.focus_exited.connect(func(): commit.call(le.text))
		n = le
	for st in ["normal", "focus", "read_only"]:
		n.add_theme_stylebox_override(st, _field_style())
	n.add_theme_font_size_override("font_size", size)
	n.add_theme_color_override("font_color", INK)
	n.add_theme_color_override("font_readonly_color", INK)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not editable:
		n.tooltip_text = "Only the DM and this character's player can edit this."
	_binds.append({"node": n, "fn": getter, "kind": "field"})
	return n


func _labeled_cell(content: Control, caption: String) -> VBoxContainer:
	var v := UiKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	var cap := UiKit.label(caption.to_upper(), 10, CAPTION)
	v.add_child(cap)
	return v


func _col() -> VBoxContainer:
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _roll(c: Dictionary, bonus: int, label: String) -> void:
	hud.send({"type": "roll", "expr": "1d20%s" % Dice.fmt_mod(bonus), "label": "%s — %s" % [c.name, label]})


func _clickable(ctrl: Control, tip: String, cb: Callable) -> void:
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ctrl.tooltip_text = tip
	ctrl.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			cb.call())


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _dots(filled: int, total: int) -> String:
	return "[color=#f2c66d]%s[/color][color=#5a534a]%s[/color]" % ["●".repeat(maxi(0, filled)), "○".repeat(maxi(0, total - filled))]


# ---------------- Header ----------------

func _name_box(c: Dictionary) -> PanelContainer:
	var v := UiKit.vbox(2)
	var editable: bool = hud.can_control(c)
	var le := LineEdit.new()
	le.editable = editable
	le.add_theme_font_size_override("font_size", 24)
	le.add_theme_color_override("font_color", Color.from_string(c.color, INK).lightened(0.35))
	le.add_theme_color_override("font_readonly_color", Color.from_string(c.color, INK).lightened(0.35))
	for st in ["normal", "focus", "read_only"]:
		le.add_theme_stylebox_override(st, _field_style())
	var commit := func(t: String) -> void:
		if t.strip_edges() != "" and t != hud.sel().get("name", ""):
			hud.send({"type": "rename", "id": hud.sel().id, "name": t})
	le.text_submitted.connect(func(t):
		commit.call(t)
		le.release_focus())
	le.focus_exited.connect(func(): commit.call(le.text))
	_binds.append({"node": le, "fn": func(cc): return cc.name, "kind": "field"})
	v.add_child(le)
	var cap := UiKit.label("CHARACTER NAME", 10, CAPTION)
	v.add_child(cap)
	var p := _box("", v)
	p.size_flags_stretch_ratio = 1.0
	return p


func _class_level(c: Dictionary) -> String:
	if c.kind == "npc" and c.class_id == "":
		return "%s, CR %s" % [c.ctype.capitalize(), Monsters.cr_label(c.cr)]
	var cls: Dictionary = Classes.ALL.get(c.class_id, {})
	var sub := ""
	if c.subclass_id != "":
		sub = " (%s)" % cls.subclass.name
	return "%s %d%s" % [cls.get("name", "?"), c.level, sub]


func _build_header(c: Dictionary, cells: Array) -> void:
	var head := UiKit.hbox(8)
	head.add_child(_name_box(c))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for cell in cells:
		grid.add_child(_labeled_cell(cell[1], cell[0]))
	var info := _box("", grid)
	info.size_flags_stretch_ratio = 2.0
	head.add_child(info)
	_body.add_child(head)


# ---------------- Page 1: Character ----------------

func _build_stats(c: Dictionary) -> void:
	var eng: EngineBase = hud.eng
	var race_name: String = Classes.RACES.get(c.race_id, {}).get("name", c.ctype.capitalize() if c.kind == "npc" else "")
	_build_header(c, [
		["Class & Level", _value(_class_level, 14, HORIZONTAL_ALIGNMENT_LEFT)],
		["Background", _field("background", false, 0, Callable(), 14)],
		["Player Name", _value(func(cc): return cc.controller if cc.controller != "" else "DM", 14, HORIZONTAL_ALIGNMENT_LEFT)],
		["Race", _value(func(_cc): return race_name, 14, HORIZONTAL_ALIGNMENT_LEFT)],
		["Alignment", _field("alignment", false, 0, Callable(), 14)],
		["Experience Points", _field("xp", false, 0, func(cc): return str(cc.xp) if cc.kind == "npc" else "", 14)],
	])

	# Conditions strip (not on the paper sheet, but essential at the table).
	var strip_text := func(cc: Dictionary) -> String:
		var bits := PackedStringArray()
		for k in eng.conditions_of(cc):
			if k != "incapacitated" or eng.conditions_of(cc).size() == 1:
				bits.append("[color=#ff9a6a]%s[/color]" % k.capitalize())
		if cc.exhaustion > 0:
			bits.append("[color=#ff9a6a]Exhaustion %d[/color]" % cc.exhaustion)
		if not cc.concentration.is_empty():
			bits.append("[color=#b0a0ff]Concentrating: %s[/color] [url=drop](drop)[/url]" % cc.concentration.name)
		if cc.inspiration_die != "":
			bits.append("[color=#f2c66d]Bardic Inspiration %s[/color]" % cc.inspiration_die)
		for e in eng.effects_on(cc):
			if e.get("conditions", []).is_empty():
				var src := eng.get_c(e.source_id)
				bits.append("%s%s" % [_esc(e.name), (" [color=#8a8478](%s)[/color]" % _esc(src.name)) if not src.is_empty() and src.id != cc.id else ""])
		return "  ·  ".join(bits)
	var strip := _rich(strip_text, 13)
	var strip_box := _box("Conditions & effects", strip)
	_binds[-1]["hide_box"] = strip_box
	_body.add_child(strip_box)

	var cols := UiKit.hbox(8)
	_body.add_child(cols)
	var col1 := _col()
	var col2 := _col()
	var col3 := _col()
	cols.add_child(col1)
	cols.add_child(col2)
	cols.add_child(col3)

	# ---- Column 1: abilities, inspiration, proficiency, saves, skills
	var top := UiKit.hbox(6)
	col1.add_child(top)
	var abil := UiKit.vbox(6)
	top.add_child(abil)
	for ab in Stats.ABILITIES:
		abil.add_child(_ability_box(c, ab))
	var right := UiKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	var insp := CheckBox.new()
	insp.focus_mode = Control.FOCUS_NONE
	insp.disabled = not hud.can_control(c)
	insp.tooltip_text = "Inspiration (awarded by the DM)"
	insp.toggled.connect(func(on): hud.send({"type": "setNotes", "id": hud.sel().id, "key": "inspiration", "value": "1" if on else ""}))
	_binds.append({"node": insp, "fn": func(cc): return cc.get("notes", {}).get("inspiration", "") == "1", "kind": "check"})
	right.add_child(_pill(insp, "Inspiration"))
	right.add_child(_pill(_value(func(cc): return Dice.fmt_mod(cc.prof), 18), "Proficiency Bonus"))
	var _fn1 := func(cc: Dictionary) -> String:
		var t := ""
		for ab in Stats.ABILITIES:
			var mark := "[color=#f2c66d]●[/color]" if cc.save_profs.has(ab) else "[color=#5a534a]○[/color]"
			t += "%s [url=save:%s][b]%s[/b]  %s[/url]\n" % [mark, ab, Dice.fmt_mod(eng.save_mod(cc, ab)), Stats.ABILITY_NAMES[ab]]
		return t.strip_edges()
	var saves := _rich(_fn1, 13)
	right.add_child(_box("Saving Throws", saves))
	var _fn2 := func(cc: Dictionary) -> String:
		var t := ""
		for sk in Stats.SKILLS:
			var p: int = cc.skills.get(sk, 0)
			var mark := "[color=#f2c66d]◉[/color]" if p == 2 else ("[color=#f2c66d]●[/color]" if p == 1 or cc.skill_bonus.has(sk) else "[color=#5a534a]○[/color]")
			t += "%s [url=skill:%s][b]%s[/b]  %s [color=#7d766b](%s)[/color][/url]\n" % [mark, sk, Dice.fmt_mod(eng.skill_mod(cc, sk)), Stats.skill_label(sk),
				Stats.SKILLS[sk].capitalize()]
		return t.strip_edges()
	var skills := _rich(_fn2, 12)
	right.add_child(_box("Skills", skills))
	col1.add_child(_pill(_value(func(cc): return str(cc.passive_perception), 18), "Passive Wisdom (Perception)"))
	col1.add_child(_pill(_value(func(cc): return _senses(cc), 14), "Senses"))
	col1.add_child(_pill(_value(func(cc): return _speeds(cc), 14), "Other speeds"))
	col1.add_child(_box("Other Proficiencies & Languages", _field("proficiencies", true, 120, _default_proficiencies, 12)))

	# ---- Column 2: AC / initiative / speed, HP, hit dice, death saves, attacks, equipment
	var trio := UiKit.hbox(6)
	trio.add_child(_box("Armor Class", _value(func(cc): return str(eng.ac_of(cc)), 26), 74))
	trio.add_child(_box("Initiative", _value(func(cc): return Dice.fmt_mod(eng.mod(cc, "dex") + cc.init_bonus), 26), 74))
	trio.add_child(_box("Speed", _value(func(cc): return "%d ft" % eng.speed_of(cc), 22), 74))
	col2.add_child(trio)
	var hp := UiKit.vbox(2)
	var maxline := UiKit.hbox(6)
	maxline.add_child(UiKit.label("Hit Point Maximum", 11, FAINT))
	var mx := _value(func(cc): return str(cc.max_hp), 14, HORIZONTAL_ALIGNMENT_LEFT)
	maxline.add_child(mx)
	hp.add_child(maxline)
	var cur := _value(func(cc): return ("DEAD" if cc.dead else str(cc.hp)), 34)
	_binds.append({"node": cur, "fn": func(cc): return Color(1, 0.4, 0.35) if cc.hp <= cc.max_hp / 4 else (Color(0.95, 0.78, 0.42) if cc.hp <= cc.max_hp / 2 else Color(0.6, 0.92, 0.65)), "kind": "color"})
	hp.add_child(cur)
	col2.add_child(_box("Current Hit Points", hp, 96))
	col2.add_child(_box("Temporary Hit Points", _value(func(cc): return str(cc.temp_hp) if cc.temp_hp > 0 else "—", 24), 64))
	var pair := UiKit.hbox(6)
	var _fn3 := func(cc: Dictionary) -> String:
		var hd: Dictionary = cc.resources.get("hit_dice", {})
		if hd.is_empty():
			return "[center]%s[/center]" % cc.fdata.get("hit_dice", "—")
		return "[color=#8a8478]Total[/color] %dd%d\n[color=#8a8478]Left[/color] [b]%d[/b]" % [hd.max, cc.fdata.get("hit_die", 8), hd.max - hd.used]
	pair.add_child(_box("Hit Dice", _rich(_fn3, 13), 70))
	var _fn4 := func(cc: Dictionary) -> String:
		var t := "[color=#8a8478]Successes[/color] %s\n[color=#8a8478]Failures[/color]  %s" % [_dots(cc.death_saves.successes, 3), _dots(cc.death_saves.failures, 3)]
		if cc.stable:
			t += "\n[color=#8fe39a]Stable[/color]"
		return t
	pair.add_child(_box("Death Saves", _rich(_fn4, 13), 70))
	col2.add_child(pair)
	col2.add_child(_box("Attacks & Spellcasting", _rich(_attacks_text, 12), 150))
	var equip := UiKit.hbox(6)
	var coins := UiKit.vbox(3)
	for coin in ["cp", "sp", "ep", "gp", "pp"]:
		var row := UiKit.hbox(3)
		var cl := UiKit.label(coin.to_upper(), 10, CAPTION)
		cl.custom_minimum_size.x = 20
		row.add_child(cl)
		var f := _field(coin, false, 0, Callable(), 12)
		f.custom_minimum_size.x = 54
		row.add_child(f)
		coins.add_child(row)
	# Weight of gear not listed as weapons or armor (packs, rope, rations): counts toward encumbrance.
	var extra := [["pack_lb", "Other gear (lb)", Callable()]]
	if hud.state.settings.get("ammunition", false):
		for a in c.get("attacks", []):
			var k: String = Equipment.AMMO_OF.get(a.get("weapon_id", ""), "")
			if k != "" and not extra.any(func(e): return e[0] == k):
				extra.append([k, Equipment.AMMO[k].name, func(cc): return str(Equipment.ammo_left(cc, k))])
	for e in extra:
		coins.add_child(UiKit.label(e[1], 10, CAPTION))
		var f := _field(e[0], false, 0, e[2], 12)
		f.custom_minimum_size.x = 74
		coins.add_child(f)
	if hud.state.settings.get("encumbrance", false):
		coins.add_child(_rich(func(cc): return "%.1f lb\n[color=#e3a08f]%s[/color]" % [Equipment.carried_lb(cc),
			["", "Encumbered", "Heavily encumbered", "Over capacity", "Can't move"][Equipment.encumbrance(cc)]], 11))
	equip.add_child(coins)
	equip.add_child(_field("equipment", true, 140, func(cc): return "\n".join(cc.get("equipment", [])), 12))
	col2.add_child(_box("Equipment", equip))

	# ---- Column 3: personality, features
	col3.add_child(_box("Personality Traits", _field("personality", true, 64, Callable(), 12)))
	col3.add_child(_box("Ideals", _field("ideals", true, 52, Callable(), 12)))
	col3.add_child(_box("Bonds", _field("bonds", true, 52, Callable(), 12)))
	col3.add_child(_box("Flaws", _field("flaws", true, 52, Callable(), 12)))
	col3.add_child(_box("Features & Traits", _rich(_features_text, 12), 300))


static func _senses(cc: Dictionary) -> String:
	var out := []
	if cc.get("blindsight", 0) > 0:
		out.append("Blindsight %d ft" % cc.blindsight)
	if cc.get("darkvision", 0) > 0:
		out.append("Darkvision %d ft" % cc.darkvision)
	return ", ".join(out) if not out.is_empty() else "—"


func _speeds(cc: Dictionary) -> String:
	var out := []
	var sp: Dictionary = cc.get("speeds", {})
	var fly: int = (hud.eng as EngineBase).fly_speed(cc)
	if fly > 0:
		out.append("Fly %d ft%s" % [fly, " (hover)" if sp.get("hover", false) else ""])
	for k in ["swim", "climb"]:
		if sp.get(k, 0) > 0:
			out.append("%s %d ft" % [k.capitalize(), sp[k]])
	return ", ".join(out) if not out.is_empty() else "—"


func _pill(content: Control, caption: String) -> HBoxContainer:
	var h := UiKit.hbox(4)
	var small := PanelContainer.new()
	small.add_theme_stylebox_override("panel", _box_style(14))
	small.custom_minimum_size = Vector2(52, 34)
	small.add_child(content)
	h.add_child(small)
	var lab := PanelContainer.new()
	lab.add_theme_stylebox_override("panel", _box_style(4))
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := _caption(caption)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_child(l)
	h.add_child(lab)
	return h


func _ability_box(c: Dictionary, ab: String) -> PanelContainer:
	var eng: EngineBase = hud.eng
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box_style(8))
	p.custom_minimum_size = Vector2(86, 0)
	var v := UiKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(_caption(Stats.ABILITY_NAMES[ab], 9))
	v.add_child(_value(func(cc): return Dice.fmt_mod(eng.mod(cc, ab)), 26))
	var oval := PanelContainer.new()
	var os := _box_style(10)
	os.bg_color = Color(0.07, 0.07, 0.075)
	os.content_margin_top = 1
	os.content_margin_bottom = 1
	oval.add_theme_stylebox_override("panel", os)
	oval.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	oval.custom_minimum_size.x = 46
	oval.add_child(_value(func(cc): return str(cc.abilities[ab]), 14))
	v.add_child(oval)
	for ch in v.get_children():
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clickable(p, "Click to roll a %s check" % Stats.ABILITY_NAMES[ab], func():
		var cc: Dictionary = hud.sel()
		_roll(cc, eng.mod(cc, ab) + ((cc.prof / 2) if cc.joat else 0), "%s check" % Stats.ABILITY_NAMES[ab]))
	return p


func _attacks_text(c: Dictionary) -> String:
	var eng: EngineCombat = hud.eng
	var t := "[table=3][cell][color=#bca173][font_size=10]NAME[/font_size][/color][/cell][cell][color=#bca173][font_size=10]ATK BONUS  [/font_size][/color][/cell][cell][color=#bca173][font_size=10]DAMAGE/TYPE[/font_size][/color][/cell]"
	for a in c.attacks:
		var p := eng.effective_profile(c, a)
		var rng := ""
		if p.range == "ranged":
			rng = " [color=#7d766b](%d/%d)[/color]" % [p.normal, p.long]
		elif p.reach > 5:
			rng = " [color=#7d766b](reach)[/color]"
		t += "[cell]%s%s  [/cell][cell][b]%s[/b][/cell][cell]%s[/cell]" % [_esc(p.name), rng, Dice.fmt_mod(p.to_hit), _esc(hud._dmg_text(p))]
	t += "[/table]"
	if not c.multiattack.is_empty():
		t += "\n[color=#8a8478]Multiattack: %s[/color]" % ", ".join(c.multiattack)
	var sc: Dictionary = c.spellcasting
	if not sc.is_empty():
		t += "\n[color=#b0a0ff]Spellcasting (%s): save DC %d, spell attack %s[/color]" % [sc.ability.to_upper(), sc.dc, Dice.fmt_mod(sc.attack_bonus)]
	for pw in c.powers:
		t += "\n[color=#f2c66d]%s[/color] [color=#8a8478]%s[/color]" % [_esc(pw.name), _esc(pw.spell.get("desc", ""))]
	return t


func _default_proficiencies(c: Dictionary) -> String:
	if c.class_id == "":
		return ""
	var cls: Dictionary = Classes.ALL[c.class_id]
	var armor: Array = cls.armor.map(func(a): return "shields" if a == "shield" else a + " armor")
	var weapons: Array = cls.weapons.map(func(w): return (w + " weapons") if w in ["simple", "martial"] else Equipment.WEAPONS.get(w, {}).get("name", w).to_lower() + "s")
	weapons.append_array(Classes.RACES.get(c.race_id, {}).get("weapons", []).map(func(w): return Equipment.WEAPONS[w].name.to_lower() + "s"))
	var t := "Armor: %s\nWeapons: %s\nLanguages: %s" % [", ".join(armor) if not armor.is_empty() else "none", ", ".join(weapons), ", ".join(c.get("languages", ["Common"]))]
	return t


func _features_text(c: Dictionary) -> String:
	var t := ""
	if not c.resources.is_empty():
		t += "[color=#bca173][font_size=10]RESOURCES[/font_size][/color]\n"
		for k in c.resources:
			var r: Dictionary = c.resources[k]
			if r.max <= 8:
				t += "%s  %s\n" % [r.name, _dots(r.max - r.used, r.max)]
			else:
				t += "%s  [b]%d[/b]/%d\n" % [r.name, r.max - r.used, r.max]
		t += "\n"
	if c.class_id != "":
		var levels: Dictionary = c.fdata.get("class_levels", {c.class_id: c.level})
		for k in levels:
			var cls: Dictionary = Classes.ALL[k]
			t += "[color=#bca173][font_size=10]%s FEATURES[/font_size][/color]\n" % cls.name.to_upper()
			for f in cls.features:
				if f[0] <= levels[k] and f[1] != "Ability Score Improvement":
					t += "[b]%s[/b] [color=#7d766b](%d)[/color]%s%s\n" % [f[1], f[0], (" — " + _esc(f[2])) if f[2] != "" else "",
						"" if f[3] else " [color=#c77b5a](not automated)[/color]"]
		for o in c.options:
			if OPTION_NAMES.has(o):
				t += "[b]%s[/b]\n" % OPTION_NAMES[o]
		t += "\n"
	var feats: Array = c.features.filter(func(f): return Creator.FEATS.has(f))
	if not feats.is_empty():
		t += "[color=#bca173][font_size=10]FEATS[/font_size][/color]\n"
		for f in feats:
			var fd: Dictionary = Creator.FEATS[f]
			t += "[b]%s[/b] — %s%s\n" % [fd.name, _esc(fd.desc), (" [color=#7d766b](DM: %s)[/color]" % _esc(fd.dm)) if fd.has("dm") else ""]
		t += "\n"
	var carried: Array = c.get("items", [])
	if not carried.is_empty():
		t += "[color=#bca173][font_size=10]MAGIC ITEMS[/font_size][/color]\n"
		for e in carried:
			var it := Items.get_item(e.get("id", ""))
			t += "[b]%s[/b]%s — %s\n" % [_esc(Items.display_name(e)), " (attuned)" if it.get("attunement", false) else "", _esc(it.get("desc", ""))]
		t += "\n"
	var traits = c.traits.filter(func(k): return TRAITS.has(k))
	if not traits.is_empty():
		var race_name: String = Classes.RACES.get(c.race_id, {}).get("name", "")
		t += "[color=#bca173][font_size=10]%s TRAITS[/font_size][/color]\n" % (race_name.to_upper() if race_name != "" else "SPECIAL")
		for k in traits:
			t += "[b]%s[/b] — %s\n" % [TRAITS[k][0], TRAITS[k][1]]
		t += "\n"
	var def := PackedStringArray()
	if not c.resistances.is_empty(): def.append("Resistant to " + ", ".join(c.resistances))
	if not c.immunities.is_empty(): def.append("Immune to " + ", ".join(c.immunities))
	if not c.vulnerabilities.is_empty(): def.append("Vulnerable to " + ", ".join(c.vulnerabilities))
	if not c.cond_immunities.is_empty(): def.append("Can't be " + ", ".join(c.cond_immunities))
	if not def.is_empty():
		t += "[color=#bca173][font_size=10]DEFENSES[/font_size][/color]\n" + "\n".join(def)
	return t.strip_edges()


# ---------------- Page 2: Details ----------------

func _build_details(c: Dictionary) -> void:
	var cells := []
	for k in ["age", "height", "weight", "eyes", "skin", "hair"]:
		cells.append([k.capitalize(), _field(k, false, 0, Callable(), 14)])
	_build_header(c, cells)
	var cols := UiKit.hbox(8)
	_body.add_child(cols)
	var left := _col()
	var right := _col()
	right.size_flags_stretch_ratio = 2.0
	cols.add_child(left)
	cols.add_child(right)
	left.add_child(_box("Character Appearance", _field("appearance", true, 220)))
	left.add_child(_box("Character Backstory", _field("backstory", true, 420)))
	right.add_child(_box("Allies & Organizations", _field("allies", true, 220)))
	right.add_child(_box("Additional Features & Traits", _field("features", true, 230)))
	right.add_child(_box("Treasure", _field("treasure", true, 170)))


# ---------------- Page 3: Spells ----------------

func _build_spells(c: Dictionary) -> void:
	var head := UiKit.hbox(8)
	var cls_name: String = Classes.ALL.get(c.class_id, {}).get("name", "—")
	head.add_child(_box("Spellcasting Class", _value(func(cc): return cls_name if not cc.spellcasting.is_empty() else "—", 20), 70))
	head.add_child(_box("Spellcasting Ability", _value(func(cc): return Stats.ABILITY_NAMES.get(cc.spellcasting.get("ability", ""), "—"), 18), 70))
	head.add_child(_box("Spell Save DC", _value(func(cc): return str(cc.spellcasting.dc) if not cc.spellcasting.is_empty() else "—", 26), 70))
	head.add_child(_box("Spell Attack Bonus", _value(func(cc): return Dice.fmt_mod(cc.spellcasting.attack_bonus) if not cc.spellcasting.is_empty() else "—", 26), 70))
	_body.add_child(head)
	if c.spellcasting.is_empty():
		var l := UiKit.label("%s has no spellcasting%s." % [c.name, " yet (paladins and rangers start at 2nd level)" if c.class_id in ["paladin", "ranger"] else ""], 14, FAINT)
		_body.add_child(l)
	var cols := UiKit.hbox(8)
	_body.add_child(cols)
	for group in [[0, 1, 2], [3, 4, 5], [6, 7, 8, 9]]:
		var col := _col()
		cols.add_child(col)
		for lv in group:
			col.add_child(_spell_level_block(lv))


func _spell_level_block(lv: int) -> PanelContainer:
	var v := UiKit.vbox(4)
	var head := UiKit.hbox(6)
	var badge := PanelContainer.new()
	var bs := _box_style(4)
	bs.bg_color = Color(0.2, 0.16, 0.1)
	bs.border_color = UiKit.GOLD
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(30, 30)
	var num := UiKit.label(str(lv), 18, UiKit.GOLD)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(num)
	head.add_child(badge)
	if lv == 0:
		var cap := _caption("Cantrips", 12)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(cap)
	else:
		head.add_child(_labeled_cell(_value(func(cc): return str(_slot_total(cc, lv)), 15, HORIZONTAL_ALIGNMENT_LEFT), "Slots total"))
		var _fn5 := func(cc: Dictionary) -> String:
			var total := _slot_total(cc, lv)
			if total == 0:
				return "[color=#5a534a]—[/color]"
			var left: int = hud.eng.slots_left(cc, lv)
			return "[color=#f2c66d]%s[/color][color=#5a534a]%s[/color]" % ["●".repeat(total - left), "○".repeat(left)]
		var used := _rich(_fn5, 15)
		used.custom_minimum_size.x = 80
		head.add_child(_labeled_cell(used, "Slots expended"))
	v.add_child(head)
	var _fn6 := func(cc: Dictionary) -> String:
		var t := ""
		var n := 0
		for sid in cc.spellcasting.get("known", []):
			var sp := Spells.get_spell(sid)
			if sp.level != lv:
				continue
			n += 1
			var tags := ""
			if sp.time == "bonus":
				tags += " [color=#7d766b]bonus[/color]"
			elif sp.time == "reaction":
				tags += " [color=#7d766b]reaction[/color]"
			if sp.get("concentration", false):
				tags += " [color=#7d766b]C[/color]"
			t += "%s[url=spell:%s]%s[/url]%s\n" % ["" if lv == 0 else "[color=#f2c66d]●[/color] ", sid, sp.name, tags]
		for i in range(n, 4 if lv == 0 else 3):
			t += "[color=#3a3530]%s________________[/color]\n" % ("" if lv == 0 else "○ ")
		return t.strip_edges()
	v.add_child(_rich(_fn6, 13))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box_style())
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(v)
	return p


func _slot_total(c: Dictionary, lv: int) -> int:
	var sc: Dictionary = c.spellcasting
	if sc.is_empty():
		return 0
	var n: int = sc.slots[lv]
	if not sc.pact.is_empty() and sc.pact.level == lv:
		n += sc.pact.max
	return n


# ---------------- Redacted (a monster seen by a player) ----------------

func _build_redacted(c: Dictionary) -> void:
	_build_header(c, [
		["Creature", _value(func(cc): return cc.description, 14, HORIZONTAL_ALIGNMENT_LEFT)],
		["Condition", _value(func(cc): return cc.hp_status, 14, HORIZONTAL_ALIGNMENT_LEFT)],
		["Size", _value(func(cc): return cc.csize.capitalize(), 14, HORIZONTAL_ALIGNMENT_LEFT)],
	])
	_body.add_child(_box("Conditions", _rich(func(cc): return ", ".join(hud.eng.conditions_of(cc)) if not hud.eng.conditions_of(cc).is_empty() else "[color=#7d766b]None visible[/color]", 13)))
	_body.add_child(UiKit.label("The DM keeps this creature's statistics hidden.", 13, FAINT))


# ---------------- Links ----------------

func _on_meta(meta) -> void:
	var s := str(meta)
	if s.begins_with("spell:"):
		hud.cast_from_sheet(s.substr(6))
	else:
		hud._on_sheet_meta(meta)


func _meta_tooltip(s: String) -> String:
	if s.begins_with("spell:"):
		return hud.spell_tip(hud.sel(), Spells.get_spell(s.substr(6)), 0, s.substr(6)) + "\n[color=#a69f94]Click to cast.[/color]"
	if s.begins_with("save:"):
		return "Click to roll a %s saving throw" % Stats.ABILITY_NAMES[s.substr(5)]
	if s.begins_with("skill:"):
		return "Click to roll %s" % Stats.skill_label(s.substr(6))
	if s == "drop":
		return "Stop concentrating"
	return ""
