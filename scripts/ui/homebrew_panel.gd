extends Control
## The DM's Homebrew Workshop: make monsters, spells and magic items with a live stat-block
## preview. Saved entries live in the campaign (state.homebrew) and work exactly like built-in
## content; packs can be exported/imported as JSON to reuse across campaigns.

const SRD := {"monsters": Monsters.ALL, "spells": Spells.ALL, "items": Items.ALL}
const CR_LIST := [0.0, 0.125, 0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0,
	18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0, 29.0, 30.0]
const TRAIT_TEXT := {
	"packTactics": "Pack Tactics — advantage when an ally is within 5 ft of the target",
	"nimbleEscape": "Nimble Escape — Disengage or Hide as a bonus action",
	"undeadFortitude": "Undead Fortitude — Con save to drop to 1 HP instead of 0",
	"aggressive": "Aggressive — Dash toward an enemy as a bonus action",
	"parry": "Parry — reaction: +2 AC against a melee hit",
	"magicResistance": "Magic Resistance — advantage on saves against magic",
	"nonmagicalResistance": "Resistant to Nonmagical Weapons — half bludgeoning, piercing and slashing from nonmagical attacks",
	"nonmagicalImmunity": "Immune to Nonmagical Weapons — no bludgeoning, piercing or slashing damage from nonmagical attacks",
}

var hud: Control
var kind := "monsters"
var data: Dictionary = {}
var edit_id := ""
var _pending_name := ""
var _list: VBoxContainer
var _form: VBoxContainer
var _scroll: ScrollContainer
var _preview: RichTextLabel
var _errors: RichTextLabel
var _actions: VBoxContainer
var _kind_btns := {}
var _copy_opt: OptionButton
var _give_base := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.07, 0.995)
	sb.border_color = Color(0.55, 0.44, 0.26)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 20
	panel.offset_right = -24
	panel.offset_bottom = -20
	add_child(panel)
	var root := UiKit.vbox(10)
	panel.add_child(root)
	var head := UiKit.hbox(8)
	var title := UiKit.label("Homebrew Workshop", 24, UiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.button("Import pack…", _import_pack, "Add monsters, spells and items from a .json pack"))
	head.add_child(UiKit.button("Export pack…", _export_pack, "Save all of this campaign's homebrew to a .json pack"))
	head.add_child(UiKit.button("Close", close))
	root.add_child(head)
	var body := UiKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UiKit.vbox(6)
	left.custom_minimum_size.x = 230
	var kinds := UiKit.hbox(4)
	for k in Homebrew.KINDS:
		var b := UiKit.button(k.capitalize(), func(): _switch_kind(k))
		_kind_btns[k] = b
		kinds.add_child(b)
	left.add_child(kinds)
	left.add_child(UiKit.button("+ New", func(): _start(Homebrew.blank(kind), "")))
	var copy_row := UiKit.hbox(4)
	_copy_opt = OptionButton.new()
	_copy_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_opt.fit_to_longest_item = false
	copy_row.add_child(_copy_opt)
	copy_row.add_child(UiKit.button("Copy", _copy_srd, "Start from a built-in entry"))
	left.add_child(copy_row)
	left.add_child(UiKit.label("This campaign's homebrew", 13, UiKit.MUTED))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = UiKit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_list)
	left.add_child(ls)
	body.add_child(left)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form = UiKit.vbox(10)
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_form)
	body.add_child(_scroll)

	var side := UiKit.vbox(8)
	side.custom_minimum_size.x = 360
	var pv := ScrollContainer.new()
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preview = _rich()
	pv.add_child(_preview)
	side.add_child(_panel(pv))
	_errors = _rich()
	side.add_child(_errors)
	_actions = UiKit.vbox(6)
	side.add_child(_actions)
	body.add_child(side)


func open() -> void:
	visible = true
	_switch_kind(kind)


func close() -> void:
	visible = false


func _switch_kind(k: String) -> void:
	kind = k
	for x in _kind_btns:
		_kind_btns[x].modulate = UiKit.GOLD if x == kind else Color.WHITE
	_copy_opt.clear()
	var src: Dictionary = SRD[kind]
	for id in src:
		if kind == "spells" and src[id].has("special"):
			continue
		_copy_opt.add_item(src[id].name)
		_copy_opt.set_item_metadata(_copy_opt.item_count - 1, id)
	var hb: Dictionary = _hb()
	if not hb.is_empty():
		var first: String = hb.keys()[0]
		_start(hb[first].duplicate(true), first)
	else:
		_start(Homebrew.blank(kind), "")


func _hb() -> Dictionary:
	return hud.state.get("homebrew", {}).get(kind, {})


## Called when the game state changes (e.g. after saving).
func refresh() -> void:
	if not visible:
		return
	if _pending_name != "":
		for id in _hb():
			if _hb()[id].name == _pending_name and edit_id == "":
				edit_id = id
		_pending_name = ""
	_build_list()
	_build_actions()


func _start(d: Dictionary, id: String) -> void:
	data = d
	edit_id = id
	_build_list()
	_rebuild()
	_scroll.scroll_vertical = 0


func _copy_srd() -> void:
	if _copy_opt.selected < 0:
		return
	_start(Homebrew.from_srd(kind, _copy_opt.get_item_metadata(_copy_opt.selected)), "")


func _build_list() -> void:
	UiKit.clear(_list)
	var hb := _hb()
	if hb.is_empty():
		_list.add_child(UiKit.label("Nothing yet — click + New or copy an SRD entry.", 12, UiKit.MUTED))
	for id in hb:
		var b := UiKit.button(hb[id].name, func(): _start(hb[id].duplicate(true), id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == edit_id:
			b.modulate = UiKit.GOLD
		_list.add_child(b)


## Fills fields the engine needs when a choice changes (e.g. switching an attack to ranged).
func _fill_defaults() -> void:
	match kind:
		"monsters":
			for a in data.get("attacks", []):
				if a.get("range", "melee") == "ranged" and int(a.get("normal", 0)) < 5:
					a["normal"] = 80
					a["long"] = 320
				if a.get("range", "melee") == "melee" and int(a.get("reach", 0)) < 5:
					a["reach"] = 5
		"spells":
			var tg: Dictionary = data.get("target", {})
			match tg.get("type", ""):
				"creature":
					if not tg.has("count"):
						tg["count"] = 1
				"area":
					if not tg.has("shape"):
						tg["shape"] = "sphere"
					if not tg.has("size"):
						tg["size"] = 20
					if not tg.has("origin"):
						tg["origin"] = "point"
			if data.get("mode", "") == "save" and not data.has("save"):
				data["save"] = {"ability": "dex", "half": true}
			if data.get("mode", "") == "attack" and not data.has("attack"):
				data["attack"] = "ranged"


func _rebuild() -> void:
	_fill_defaults()
	UiKit.clear(_form)
	match kind:
		"monsters": _monster_form()
		"spells": _spell_form()
		_: _item_form()
	_update_side()


# ---------------- Form helpers (bound to paths inside `data`) ----------------

func _val(path: Array, default = null):
	var cur = data
	for k in path:
		if cur is Dictionary and cur.has(k):
			cur = cur[k]
		elif cur is Array and k is int and k < cur.size():
			cur = cur[k]
		else:
			return default
	return cur


func _put(path: Array, v, structural: bool = false) -> void:
	var cur = data
	for i in path.size() - 1:
		var k = path[i]
		if cur is Dictionary and not cur.has(k):
			cur[k] = {}
		cur = cur[k]
	cur[path[-1]] = v
	if structural:
		_rebuild()
	else:
		_update_side()


func _drop(path: Array) -> void:
	var cur = data
	for i in path.size() - 1:
		cur = cur.get(path[i], {}) if cur is Dictionary else cur[path[i]]
	if cur is Dictionary:
		cur.erase(path[-1])
	_rebuild()


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 13)
	r.add_theme_font_size_override("bold_font_size", 13)
	return r


func _panel(inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.105, 0.095, 0.115)
	sb.border_color = Color(0.4, 0.32, 0.21)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(inner)
	return p


func _section(title: String, hint: String = "") -> VBoxContainer:
	var v := UiKit.vbox(6)
	v.add_child(UiKit.label(title, 17, UiKit.GOLD))
	if hint != "":
		var h := UiKit.label(hint, 12, UiKit.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(h)
	var p := _panel(v)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_form.add_child(p)
	return v


func _row(parent: Control) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 6)
	parent.add_child(h)
	return h


func _labeled(parent: Control, label: String, ctrl: Control) -> void:
	var h := UiKit.hbox(4)
	h.add_child(UiKit.label(label, 13, UiKit.MUTED))
	h.add_child(ctrl)
	parent.add_child(h)


func _line(parent: Control, label: String, path: Array, width: int = 220, validate_dice: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.text = str(_val(path, ""))
	e.custom_minimum_size.x = width
	e.text_changed.connect(func(t):
		if validate_dice:
			e.add_theme_color_override("font_color", UiKit.PARCHMENT if t == "" or Dice.is_valid(t) else UiKit.RED)
		_put(path, t))
	if label != "":
		_labeled(parent, label, e)
	else:
		parent.add_child(e)
	return e


func _int(parent: Control, label: String, path: Array, lo: int, hi: int, width: int = 80, structural: bool = false) -> SpinBox:
	var s := UiKit.spin(lo, hi, int(_val(path, clampi(0, lo, hi))), width)
	s.value_changed.connect(func(v): _put(path, int(v), structural))
	if label != "":
		_labeled(parent, label, s)
	else:
		parent.add_child(s)
	return s


func _choice(parent: Control, label: String, path: Array, values: Array, labels: Array = [], structural: bool = false) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for i in values.size():
		o.add_item(str(labels[i]) if i < labels.size() else str(values[i]).capitalize())
	o.select(maxi(0, values.find(_val(path, values[0] if not values.is_empty() else ""))))
	o.item_selected.connect(func(i): _put(path, values[i], structural))
	if label != "":
		_labeled(parent, label, o)
	else:
		parent.add_child(o)
	return o


func _bool(parent: Control, label: String, path: Array, structural: bool = false) -> CheckBox:
	var c := UiKit.check(label, bool(_val(path, false)), func(on): _put(path, on, structural))
	parent.add_child(c)
	return c


func _multi(parent: Control, path: Array, values: Array, labels: Array = []) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	var cur: Array = _val(path, [])
	for i in values.size():
		var v = values[i]
		var cb := UiKit.check(str(labels[i]) if i < labels.size() else str(v).capitalize(), cur.has(v), func(on):
			var list: Array = _val(path, []).duplicate()
			if on and not list.has(v):
				list.append(v)
			elif not on:
				list.erase(v)
			_put(path, list))
		flow.add_child(cb)
	parent.add_child(flow)


func _text_area(parent: Control, path: Array, height: int = 70) -> void:
	var t := TextEdit.new()
	t.text = str(_val(path, ""))
	t.custom_minimum_size.y = height
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.text_changed.connect(func(): _put(path, t.text))
	parent.add_child(t)


## Rows of {dice, bonus?, type, per_slot?} with add/remove.
func _damage_rows(parent: Control, path: Array, with_bonus: bool, with_upcast: bool, max_rows: int = 3) -> void:
	var rows: Array = _val(path, [])
	for i in rows.size():
		var r := _row(parent)
		_line(r, "Dice", path + [i, "dice"], 80, true)
		if with_bonus:
			_int(r, "+", path + [i, "bonus"], -10, 30, 70)
		_choice(r, "Type", path + [i, "type"], Stats.DAMAGE_TYPES)
		if with_upcast:
			_line(r, "Per slot above", path + [i, "per_slot"], 70, true)
			_bool(r, "Cantrip scaling", path + [i, "cantrip"])
		r.add_child(UiKit.button("✕", func():
			var list: Array = _val(path, [])
			list.remove_at(i)
			_rebuild(), "Remove"))
	if rows.size() < max_rows:
		parent.add_child(UiKit.button("+ Damage", func():
			var list: Array = _val(path, [])
			list.append({"dice": "1d6", "bonus": 0, "type": "slashing"} if with_bonus else {"dice": "1d6", "type": "fire"})
			_put(path, list, true)))


# ---------------- Monster form ----------------

func _prof() -> int:
	var cr: float = float(_val(["cr"], 0.0))
	return 2 + (maxi(1, ceili(cr)) - 1) / 4


func _monster_form() -> void:
	var v := _section("Basics")
	var r := _row(v)
	_line(r, "Name", ["name"], 260)
	_choice(r, "Size", ["size"], Grid.SIZES)
	_choice(r, "Type", ["type"], Homebrew.CREATURE_TYPES)
	_choice(r, "CR", ["cr"], CR_LIST, CR_LIST.map(func(c): return Monsters.cr_label(c)), true)
	r = _row(v)
	_int(r, "AC", ["ac"], 1, 30, 70)
	_int(r, "HP", ["hp"], 1, 2000, 90)
	_line(r, "Hit dice", ["hit_dice"], 100, true)
	_int(r, "Speed", ["speed"], 0, 200, 80)
	_int(r, "Passive Perception", ["passive"], 1, 40, 70)
	var col := ColorPickerButton.new()
	col.color = Color.from_string(str(_val(["color"], "#8b3a3a")), Color.DARK_RED)
	col.custom_minimum_size = Vector2(50, 28)
	col.color_changed.connect(func(c): _put(["color"], "#" + c.to_html(false)))
	_labeled(r, "Token", col)
	v.add_child(UiKit.label("Description / lore (DM notes)", 12, UiKit.MUTED))
	_text_area(v, ["desc"], 50)

	var av := _section("Ability scores & proficiencies", "Proficiency bonus for CR %s is +%d." % [Monsters.cr_label(float(_val(["cr"], 0.0))), _prof()])
	r = _row(av)
	for ab in Stats.ABILITIES:
		_int(r, ab.to_upper(), ["abilities", ab], 1, 30, 70)
	av.add_child(UiKit.label("Saving throw proficiencies", 12, UiKit.MUTED))
	_multi(av, ["save_profs"], Stats.ABILITIES, Stats.ABILITIES.map(func(a): return a.to_upper()))
	av.add_child(UiKit.label("Skills (total bonus as printed; 0 = not listed)", 12, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 6
	for sk in Stats.SKILLS:
		grid.add_child(UiKit.label(Stats.skill_label(sk), 12))
		var s := UiKit.spin(0, 30, int(_val(["skills", sk], 0)), 64)
		s.value_changed.connect(func(x):
			var skills: Dictionary = _val(["skills"], {})
			if int(x) == 0:
				skills.erase(sk)
			else:
				skills[sk] = int(x)
			_put(["skills"], skills))
		grid.add_child(s)
	av.add_child(grid)

	var dv := _section("Defenses & traits")
	for pair in [["Resistances", "resistances"], ["Immunities", "immunities"], ["Vulnerabilities", "vulnerabilities"]]:
		dv.add_child(UiKit.label(pair[0], 12, UiKit.MUTED))
		_multi(dv, [pair[1]], Stats.DAMAGE_TYPES)
	dv.add_child(UiKit.label("Condition immunities", 12, UiKit.MUTED))
	_multi(dv, ["condition_immunities"], Stats.CONDITIONS.filter(func(c): return c != "incapacitated"))
	dv.add_child(UiKit.label("Special traits (automated)", 12, UiKit.MUTED))
	_multi(dv, ["traits"], Homebrew.TRAITS, Homebrew.TRAITS.map(func(t): return TRAIT_TEXT[t]))

	var atk := _section("Attacks", "To-hit suggestion: ability modifier + proficiency (+%d)." % _prof())
	var attacks: Array = _val(["attacks"], [])
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		var box := UiKit.vbox(4)
		var p := _panel(box)
		p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		atk.add_child(p)
		var ar := _row(box)
		_line(ar, "Name", ["attacks", i, "name"], 180)
		_choice(ar, "", ["attacks", i, "range"], ["melee", "ranged"], ["Melee", "Ranged"], true)
		var str_hit: int = Stats.mod(int(_val(["abilities", "str"], 10))) + _prof()
		var dex_hit: int = Stats.mod(int(_val(["abilities", "dex"], 10))) + _prof()
		var sp := _int(ar, "To hit", ["attacks", i, "to_hit"], -5, 25, 70)
		sp.tooltip_text = "Str-based: %s, Dex-based: %s" % [Dice.fmt_mod(str_hit), Dice.fmt_mod(dex_hit)]
		if a.get("range", "melee") == "melee":
			_int(ar, "Reach", ["attacks", i, "reach"], 5, 30, 70)
		else:
			_int(ar, "Range", ["attacks", i, "normal"], 5, 1000, 80)
			_int(ar, "/", ["attacks", i, "long"], 5, 2000, 80)
		_choice(ar, "Recharge", ["attacks", i, "recharge"], [0, 6, 5, 4], ["—", "6", "5-6", "4-6"])
		ar.add_child(UiKit.button("✕ Remove", func():
			var list: Array = _val(["attacks"], [])
			list.remove_at(i)
			_rebuild()))
		_damage_rows(box, ["attacks", i, "damage"], true, false)
		var has_rider: bool = not a.get("on_hit", {}).is_empty()
		box.add_child(UiKit.check("On a hit, the target makes a saving throw", has_rider, func(on):
			if on:
				_put(["attacks", i, "on_hit"], {"ability": "con", "dc": 8 + _prof() + Stats.mod(int(_val(["abilities", "con"], 10))), "damage": [], "half": true}, true)
			else:
				_drop(["attacks", i, "on_hit"])))
		if has_rider:
			var rr := _row(box)
			_choice(rr, "Save", ["attacks", i, "on_hit", "ability"], Stats.ABILITIES, Stats.ABILITIES.map(func(x): return x.to_upper()))
			_int(rr, "DC", ["attacks", i, "on_hit", "dc"], 1, 30, 70)
			_bool(rr, "Half damage on success", ["attacks", i, "on_hit", "half"])
			var conds := [""] + Stats.CONDITIONS.filter(func(c): return c != "incapacitated")
			_choice(rr, "On a failed save", ["attacks", i, "on_hit", "condition"], conds, conds.map(func(c): return "no condition" if c == "" else c))
			_damage_rows(box, ["attacks", i, "on_hit", "damage"], false, false, 2)
	if attacks.size() < 8:
		atk.add_child(UiKit.button("+ Attack", func():
			var list: Array = _val(["attacks"], [])
			var n := 1
			var ids := list.map(func(x): return x.id)
			while ids.has("a%d" % n):
				n += 1
			list.append({"id": "a%d" % n, "name": "Bite", "range": "melee", "to_hit": Stats.mod(int(_val(["abilities", "str"], 10))) + _prof(),
				"reach": 5, "normal": 0, "long": 0, "props": [], "damage": [{"dice": "1d6", "bonus": Stats.mod(int(_val(["abilities", "str"], 10))), "type": "piercing"}]})
			_put(["attacks"], list, true)))

	if attacks.size() > 0:
		var mv := _section("Multiattack", "How many of each attack it makes with one action (0 everywhere = no multiattack).")
		var mr := _row(mv)
		for a in attacks:
			var count: int = _val(["multiattack"], []).count(a.id)
			var s := UiKit.spin(0, 4, count, 60)
			s.value_changed.connect(func(x):
				var list: Array = _val(["multiattack"], []).filter(func(id): return id != a.id)
				for k in int(x):
					list.append(a.id)
				_put(["multiattack"], list))
			_labeled(mr, a.name, s)

	var pv := _section("Special abilities (breath weapons, auras of doom...)", "An area that forces a saving throw, like a dragon's breath.")
	var powers: Array = _val(["powers"], [])
	for i in powers.size():
		var box := UiKit.vbox(4)
		var p := _panel(box)
		p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pv.add_child(p)
		var pr := _row(box)
		var name_e := _line(pr, "Name", ["powers", i, "name"], 180)
		name_e.text_changed.connect(func(t): _put(["powers", i, "spell", "name"], t))
		_choice(pr, "Shape", ["powers", i, "spell", "target", "shape"], ["cone", "line", "sphere", "cube"], ["Cone", "Line (5 ft wide)", "Burst around itself", "Cube in front"])
		_int(pr, "Size (ft)", ["powers", i, "spell", "target", "size"], 5, 300, 70)
		_choice(pr, "Save", ["powers", i, "spell", "save", "ability"], Stats.ABILITIES, Stats.ABILITIES.map(func(x): return x.to_upper()))
		_int(pr, "DC", ["powers", i, "dc"], 1, 30, 70)
		_bool(pr, "Half on success", ["powers", i, "spell", "save", "half"])
		_choice(pr, "Recharge", ["powers", i, "recharge"], [0, 6, 5, 4], ["at will", "6", "5-6", "4-6"])
		pr.add_child(UiKit.button("✕ Remove", func():
			var list: Array = _val(["powers"], [])
			list.remove_at(i)
			_rebuild()))
		_damage_rows(box, ["powers", i, "spell", "damage"], false, false, 2)
	pv.add_child(UiKit.button("+ Special ability", func():
		var list: Array = _val(["powers"], [])
		var con: int = Stats.mod(int(_val(["abilities", "con"], 10)))
		list.append({"id": "p%d" % (list.size() + 1), "name": "Breath", "dc": 8 + _prof() + con, "recharge": 5,
			"spell": {"name": "Breath", "level": 0, "time": "action", "range": 0, "desc": "",
				"target": {"type": "area", "shape": "cone", "size": 15, "origin": "self"},
				"save": {"ability": "dex", "half": true}, "damage": [{"dice": "4d6", "type": "fire"}]}})
		_put(["powers"], list, true)))

	var sv := _section("Spellcasting")
	var has_sc: bool = not _val(["spellcasting"], {}).is_empty()
	sv.add_child(UiKit.check("This creature casts spells", has_sc, func(on):
		if on:
			var wis: int = Stats.mod(int(_val(["abilities", "wis"], 10)))
			_put(["spellcasting"], {"ability": "wis", "dc": 8 + _prof() + wis, "attack_bonus": _prof() + wis,
				"slots": [0, 2, 0, 0, 0, 0, 0, 0, 0, 0], "spells": []}, true)
		else:
			_put(["spellcasting"], {}, true)))
	if has_sc:
		var sr := _row(sv)
		_choice(sr, "Ability", ["spellcasting", "ability"], Stats.ABILITIES, Stats.ABILITIES.map(func(x): return x.to_upper()))
		_int(sr, "Save DC", ["spellcasting", "dc"], 1, 30, 70)
		_int(sr, "Spell attack +", ["spellcasting", "attack_bonus"], -5, 25, 70)
		var slr := _row(sv)
		for lv in range(1, 10):
			_int(slr, "Lv%d slots" % lv, ["spellcasting", "slots", lv], 0, 9, 60)
		sv.add_child(UiKit.label("Spells (cantrips are at will)", 12, UiKit.MUTED))
		var ids: Array = Spells.ALL.keys().filter(func(s): return not Spells.ALL[s].get("special", "") in ["shield"]) + Homebrew.spells.keys()
		ids.sort_custom(func(a, b): return Spells.get_spell(a).level < Spells.get_spell(b).level or (Spells.get_spell(a).level == Spells.get_spell(b).level and Spells.get_spell(a).name < Spells.get_spell(b).name))
		_multi(sv, ["spellcasting", "spells"], ids, ids.map(func(s): return "%s (%s)" % [Spells.get_spell(s).name, "C" if Spells.get_spell(s).level == 0 else str(Spells.get_spell(s).level)]))


# ---------------- Spell form ----------------

func _spell_form() -> void:
	var v := _section("Basics")
	var r := _row(v)
	_line(r, "Name", ["name"], 240)
	_int(r, "Level", ["level"], 0, 9, 60)
	_choice(r, "School", ["school"], Homebrew.SCHOOLS)
	_choice(r, "Casting time", ["time"], ["action", "bonus"], ["1 action", "Bonus action"])
	r = _row(v)
	var rng := _int(r, "Range (ft)", ["range"], 0, 1000, 80)
	rng.tooltip_text = "0 = self, 5 = touch"
	_bool(r, "Concentration", ["concentration"])
	v.add_child(UiKit.label("Class spell lists", 12, UiKit.MUTED))
	_multi(v, ["classes"], Classes.ALL.keys().filter(func(k): return Classes.ALL[k].caster != ""),
		Classes.ALL.keys().filter(func(k): return Classes.ALL[k].caster != "").map(func(k): return Classes.ALL[k].name))
	v.add_child(UiKit.label("Description", 12, UiKit.MUTED))
	_text_area(v, ["desc"], 50)

	var tv := _section("Targets")
	var tr := _row(tv)
	_choice(tr, "Targets", ["target", "type"], ["creature", "area", "self"], ["Creatures", "An area", "Only the caster"], true)
	match _val(["target", "type"], "creature"):
		"creature":
			_int(tr, "How many", ["target", "count"], 1, 20, 60)
			_int(tr, "+ per slot above", ["target", "per_slot"], 0, 5, 60)
			_bool(tr, "Same target can be picked again (rays)", ["target", "repeat"])
			var only_enemies: bool = _val(["target", "filter"], "any") == "enemy"
			tr.add_child(UiKit.check("Enemies only", only_enemies, func(on): _put(["target", "filter"], "enemy" if on else "any")))
		"area":
			_choice(tr, "Shape", ["target", "shape"], ["sphere", "cube", "cone", "line"], ["Sphere (radius)", "Cube", "Cone", "Line (5 ft wide)"])
			_int(tr, "Size (ft)", ["target", "size"], 5, 500, 70)
			_choice(tr, "Starts at", ["target", "origin"], ["point", "self"], ["A point in range", "The caster"])
			_bool(tr, "Also catches the caster", ["target", "include_self"])

	var mv := _section("How it lands")
	var mr := _row(mv)
	_choice(mr, "", ["mode"], ["attack", "save", "auto"], ["Spell attack roll", "Saving throw", "No roll (buff, heal, auto-hit)"], true)
	match _val(["mode"], "auto"):
		"attack":
			_choice(mr, "", ["attack"], ["ranged", "melee"], ["Ranged spell attack", "Melee spell attack"])
		"save":
			_choice(mr, "Save", ["save", "ability"], Stats.ABILITIES, Stats.ABILITIES.map(func(x): return x.to_upper()))
			_bool(mr, "Half damage on success", ["save", "half"])

	var dv := _section("Damage")
	_damage_rows(dv, ["damage"], false, true)

	var hv := _section("Healing")
	var has_heal: bool = not _val(["heal"], {}).is_empty()
	hv.add_child(UiKit.check("Heals its targets", has_heal, func(on):
		if on:
			_put(["heal"], {"dice": "1d8", "per_slot": "1d8", "add_mod": true}, true)
		else:
			_drop(["heal"])))
	if has_heal:
		var hr := _row(hv)
		_line(hr, "Dice", ["heal", "dice"], 80, true)
		_line(hr, "Per slot above", ["heal", "per_slot"], 70, true)
		_bool(hr, "Add spellcasting modifier", ["heal", "add_mod"])

	var ev := _section("Effect", "Conditions or modifiers applied %s." % {"attack": "on a hit", "save": "on a failed save", "auto": "to every target"}[_val(["mode"], "auto")])
	var has_eff: bool = not _val(["effect"], {}).is_empty()
	ev.add_child(UiKit.check("Applies a lasting effect", has_eff, func(on):
		if on:
			_put(["effect"], {"on": "always", "name": "", "conditions": [], "mods": {}, "expires_on": {"who": "source", "phase": "start", "count": 10}}, true)
		else:
			_drop(["effect"])))
	if has_eff:
		var er := _row(ev)
		_line(er, "Effect name", ["effect", "name"], 180)
		_int(er, "Lasts (rounds)", ["effect", "expires_on", "count"], 1, 14400, 80)
		_bool(er, "Ends if the target takes damage", ["effect", "ends_on_damage"])
		ev.add_child(UiKit.label("Conditions", 12, UiKit.MUTED))
		_multi(ev, ["effect", "conditions"], Stats.CONDITIONS.filter(func(c): return c != "incapacitated"))
		var mr2 := _row(ev)
		_int(mr2, "AC bonus", ["effect", "mods", "ac_bonus"], -10, 10, 60)
		_int(mr2, "Speed change", ["effect", "mods", "speed_bonus"], -60, 60, 70)
		_line(mr2, "+die to attacks", ["effect", "mods", "attack_die"], 60, true)
		_line(mr2, "+die to saves", ["effect", "mods", "save_die"], 60, true)
		_line(mr2, "−die to attacks", ["effect", "mods", "attack_penalty_die"], 60, true)
		_line(mr2, "−die to saves", ["effect", "mods", "save_penalty_die"], 60, true)
		var mr3 := _row(ev)
		_bool(mr3, "Attacks against it have advantage", ["effect", "mods", "advantage_against"])
		_bool(mr3, "Attacks against it have disadvantage", ["effect", "mods", "disadvantage_against"])
		_bool(mr3, "Its attacks have advantage", ["effect", "mods", "advantage_on_attacks"])
		_bool(mr3, "Its attacks have disadvantage", ["effect", "mods", "disadvantage_on_attacks"])
		_bool(mr3, "No reactions", ["effect", "mods", "no_reactions"])
		_bool(mr3, "Can't regain HP", ["effect", "mods", "no_healing"])
		var has_rs: bool = not _val(["effect", "repeat_save"], {}).is_empty()
		ev.add_child(UiKit.check("Target repeats the save at the end of each of its turns", has_rs, func(on):
			if on:
				_put(["effect", "repeat_save"], {"ability": _val(["save", "ability"], "wis"), "phase": "end"}, true)
			else:
				_drop(["effect", "repeat_save"])))
		if has_rs:
			_choice(ev, "Repeat save", ["effect", "repeat_save", "ability"], Stats.ABILITIES, Stats.ABILITIES.map(func(x): return x.to_upper()))

	var pv := _section("Forced movement")
	var has_push: bool = _val(["push"], {}) is Dictionary and not _val(["push"], {}).is_empty()
	pv.add_child(UiKit.check("Pushes targets away from the caster", has_push, func(on):
		if on:
			_put(["push"], {"ft": 10, "on": "fail" if _val(["mode"], "") == "save" else "hit"}, true)
		else:
			_drop(["push"])))
	if has_push:
		_int(pv, "Distance (ft)", ["push", "ft"], 5, 60, 70)


# ---------------- Item form ----------------

func _item_form() -> void:
	var v := _section("Basics")
	var r := _row(v)
	_line(r, "Name", ["name"], 240)
	_choice(r, "Kind", ["kind"], Homebrew.ITEM_KINDS, ["Weapon", "Armor", "Shield", "Wondrous item", "Potion"], true)
	_choice(r, "Rarity", ["rarity"], ["common", "uncommon", "rare", "very rare", "legendary", "artifact"])
	_bool(r, "Requires attunement", ["attunement"])
	v.add_child(UiKit.label("Description", 12, UiKit.MUTED))
	_text_area(v, ["desc"], 50)
	var k: String = _val(["kind"], "wondrous")
	var bases := {"weapon": [["weapon", "melee"], ["Any weapon", "Melee weapons only"]], "armor": [["armor"], ["Any armor"]],
		"wondrous": [["", "damage_type"], ["Nothing to choose", "Choose a damage type (like Ring of Resistance)"]]}
	if bases.has(k):
		if not bases[k][0].has(_val(["base"], "")):
			data.base = bases[k][0][0]
		_choice(v, "When handed out, the DM picks", ["base"], bases[k][0], bases[k][1])
	else:
		data.base = ""
	var bv := _section("Magic")
	match k:
		"weapon":
			var br := _row(bv)
			_int(br, "Attack bonus", ["attack_bonus"], -5, 5, 60)
			_int(br, "Damage bonus", ["damage_bonus"], -5, 5, 60)
			bv.add_child(UiKit.label("Extra damage on a hit", 12, UiKit.MUTED))
			_damage_rows(bv, ["extra_damage"], false, false, 2)
		"armor", "shield":
			_int(bv, "AC bonus", ["ac_bonus"], -5, 5, 60)
		"potion":
			_line(bv, "Healing when drunk", ["heal"], 100, true)
	if k in ["wondrous", "weapon", "armor"]:
		var wr := _row(bv)
		if k == "wondrous":
			_int(wr, "AC bonus", ["ac_bonus"], -5, 5, 60)
			_int(wr, "AC bonus without armor/shield", ["ac_unarmored_bonus"], -5, 5, 60)
		_int(wr, "Bonus to all saves", ["save_bonus"], -5, 5, 60)
		_int(wr, "Speed at least", ["speed_min"], 0, 120, 70)
		bv.add_child(UiKit.label("Resistances", 12, UiKit.MUTED))
		_multi(bv, ["resist"], Stats.DAMAGE_TYPES)
		bv.add_child(UiKit.label("Sets an ability score to at least (0 = no change)", 12, UiKit.MUTED))
		var ar := _row(bv)
		for ab in Stats.ABILITIES:
			var s := UiKit.spin(0, 30, int(_val(["ability_min", ab], 0)), 64)
			s.value_changed.connect(func(x):
				var am: Dictionary = _val(["ability_min"], {})
				if int(x) == 0:
					am.erase(ab)
				else:
					am[ab] = int(x)
				_put(["ability_min"], am))
			_labeled(ar, ab.to_upper(), s)


# ---------------- Preview, checks and actions ----------------

func _clean() -> Dictionary:
	var d := Homebrew.normalize(kind, data)
	# Drop zero bonuses and empty lists so previews read like the printed thing.
	for key in ["attack_bonus", "damage_bonus", "ac_bonus", "ac_unarmored_bonus", "save_bonus", "speed_min"]:
		if d.get(key, 1) == 0:
			d.erase(key)
	return d


func _update_side() -> void:
	var d := _clean()
	_preview.text = ""
	match kind:
		"monsters": _preview.append_text(_monster_block(d))
		"spells": _preview.append_text(_spell_card(d))
		_: _preview.append_text(_item_card(d))
	var errs := Homebrew.validate(kind, d)
	_errors.text = ""
	if errs.is_empty():
		_errors.append_text("[color=#8fe39a]✓ Ready to save.[/color]")
	else:
		_errors.append_text("[color=#ff8a7a]To finish:[/color]\n" + "\n".join(errs.slice(0, 6).map(func(e): return "• " + e)))
	_build_actions()


func _build_actions() -> void:
	UiKit.clear(_actions)
	var errs := Homebrew.validate(kind, _clean())
	var row := UiKit.hbox(6)
	var save := UiKit.button("Save" if edit_id != "" else "Save new", _save, "", not errs.is_empty())
	save.modulate = UiKit.GOLD
	row.add_child(save)
	if edit_id != "":
		row.add_child(UiKit.button("Save as copy", func():
			edit_id = ""
			_save(), "", not errs.is_empty()))
		row.add_child(UiKit.button("Delete", func():
			hud.send({"type": "homebrewDelete", "kind": kind, "id": edit_id})
			_start(Homebrew.blank(kind), "")))
	_actions.add_child(row)
	if edit_id == "":
		_actions.add_child(UiKit.label("Save first to use it in the game.", 12, UiKit.MUTED))
		return
	var sel: Dictionary = hud.sel()
	match kind:
		"monsters":
			_actions.add_child(UiKit.button("Place on map…", func():
				close()
				hud.begin_spawn("monster", edit_id), "Close the workshop and click the map to place it"))
		"items":
			var it: Dictionary = Homebrew.items.get(edit_id, {})
			var choices := Items.base_choices(it)
			var gr := UiKit.hbox(6)
			if not choices.is_empty():
				var o := OptionButton.new()
				for ch in choices:
					o.add_item(Equipment.WEAPONS.get(ch, Equipment.ARMOR.get(ch, {})).get("name", str(ch).capitalize()))
				var idx := maxi(0, choices.find(_give_base))
				o.select(idx)
				_give_base = choices[idx]
				o.item_selected.connect(func(i): _give_base = choices[i])
				gr.add_child(o)
			var ok_target: bool = not sel.is_empty() and not sel.get("redacted", false)
			gr.add_child(UiKit.button("Give to %s" % (sel.name if ok_target else "selected creature"), func():
				hud.send({"type": "giveItem", "id": sel.id, "item": {"id": edit_id, "base": _give_base if not choices.is_empty() else ""}}),
				"Select a creature on the map first", not ok_target))
			_actions.add_child(gr)
		"spells":
			var ok_caster: bool = not sel.is_empty() and not sel.get("spellcasting", {}).is_empty()
			_actions.add_child(UiKit.button("Teach to %s" % (sel.name if ok_caster else "selected caster"), func():
				hud.send({"type": "grantSpell", "id": sel.id, "spell_id": edit_id}), "Select a spellcaster on the map first", not ok_caster))


func _save() -> void:
	var d := _clean()
	if not Homebrew.validate(kind, d).is_empty():
		return
	if edit_id == "":
		_pending_name = d.name
	hud.send({"type": "homebrewSave", "kind": kind, "id": edit_id, "data": d})


func _monster_block(m: Dictionary) -> String:
	var t := "[font_size=20][b][color=#e0b070]%s[/color][/b][/font_size]\n[i]%s %s[/i]\n" % [m.get("name", ""), str(m.get("size", "")).capitalize(), m.get("type", "")]
	t += "[color=#7a2a1a]━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	t += "[b]Armor Class[/b] %d\n[b]Hit Points[/b] %d%s\n[b]Speed[/b] %d ft.\n" % [m.get("ac", 0), m.get("hp", 0),
		(" (%s)" % m.hit_dice) if str(m.get("hit_dice", "")) != "" else "", m.get("speed", 0)]
	t += "[color=#7a2a1a]━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n[table=6]"
	for ab in Stats.ABILITIES:
		t += "[cell][center][b]%s[/b][/center][/cell]" % ab.to_upper()
	for ab in Stats.ABILITIES:
		var sc: int = m.get("abilities", {}).get(ab, 10)
		t += "[cell][center]%d (%s)[/center][/cell]" % [sc, Dice.fmt_mod(Stats.mod(sc))]
	t += "[/table]\n[color=#7a2a1a]━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	var prof := 2 + (maxi(1, ceili(float(m.get("cr", 0)))) - 1) / 4
	if not m.get("save_profs", []).is_empty():
		t += "[b]Saving Throws[/b] %s\n" % ", ".join(m.save_profs.map(func(a): return "%s %s" % [a.capitalize(), Dice.fmt_mod(Stats.mod(m.abilities[a]) + prof)]))
	if not m.get("skills", {}).is_empty():
		t += "[b]Skills[/b] %s\n" % ", ".join(m.skills.keys().map(func(s): return "%s %s" % [Stats.skill_label(s), Dice.fmt_mod(m.skills[s])]))
	for pair in [["Damage Vulnerabilities", "vulnerabilities"], ["Damage Resistances", "resistances"], ["Damage Immunities", "immunities"], ["Condition Immunities", "condition_immunities"]]:
		if not m.get(pair[1], []).is_empty():
			t += "[b]%s[/b] %s\n" % [pair[0], ", ".join(m[pair[1]])]
	t += "[b]Senses[/b] passive Perception %d\n[b]Challenge[/b] %s (%d XP)\n" % [m.get("passive", 10), Monsters.cr_label(float(m.get("cr", 0))), m.get("xp", 0)]
	t += "[color=#7a2a1a]━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n"
	for tr in m.get("traits", []):
		t += "[b][i]%s.[/i][/b] %s\n" % [TRAIT_TEXT.get(tr, tr).get_slice(" — ", 0), TRAIT_TEXT.get(tr, "").get_slice(" — ", 1)]
	var sc: Dictionary = m.get("spellcasting", {})
	if not sc.is_empty():
		t += "[b][i]Spellcasting.[/i][/b] Spell save DC %d, %s to hit with spell attacks (%s). %s\n" % [sc.dc, Dice.fmt_mod(sc.attack_bonus), str(sc.ability).to_upper(),
			", ".join(sc.get("spells", []).map(func(s): return Spells.get_spell(s).get("name", s)))]
		var slots := PackedStringArray()
		for lv in range(1, 10):
			if lv < sc.get("slots", []).size() and sc.slots[lv] > 0:
				slots.append("level %d (%d)" % [lv, sc.slots[lv]])
		if not slots.is_empty():
			t += "   Slots: %s\n" % ", ".join(slots)
	t += "\n[font_size=16][color=#e0b070]Actions[/color][/font_size]\n"
	var multi: Array = m.get("multiattack", [])
	if not multi.is_empty():
		var names := {}
		for a in m.get("attacks", []):
			names[a.id] = a.name
		var counts := {}
		for id in multi:
			counts[id] = counts.get(id, 0) + 1
		t += "[b][i]Multiattack.[/i][/b] It makes %d attacks: %s.\n" % [multi.size(), ", ".join(counts.keys().map(func(id): return "%s%s" % [names.get(id, id), (" ×%d" % counts[id]) if counts[id] > 1 else ""]))]
	for a in m.get("attacks", []):
		var dmg := PackedStringArray()
		for d in a.get("damage", []):
			var avg = int(Dice.average(d.get("dice", "")) + d.get("bonus", 0)) if d.get("dice", "") != "" else d.get("bonus", 0)
			dmg.append("%d (%s%s) %s" % [avg, d.get("dice", ""), Dice.fmt_mod(d.get("bonus", 0)) if d.get("bonus", 0) != 0 else "", d.type])
		var reach: String = ("reach %d ft." % a.get("reach", 5)) if a.get("range", "melee") == "melee" else ("range %d/%d ft." % [a.get("normal", 0), a.get("long", 0)])
		t += "[b][i]%s%s.[/i][/b] %s Weapon Attack: %s to hit, %s, one target. [i]Hit:[/i] %s damage." % [a.get("name", ""),
			(" (Recharge %d-6)" % a.recharge) if a.has("recharge") else "", a.get("range", "melee").capitalize(), Dice.fmt_mod(a.get("to_hit", 0)), reach, " plus ".join(dmg)]
		var oh: Dictionary = a.get("on_hit", {})
		if not oh.is_empty():
			var rider := PackedStringArray()
			for d in oh.get("damage", []):
				rider.append("%s %s damage" % [d.dice, d.type])
			if oh.get("condition", "") != "":
				rider.append("is %s" % oh.condition)
			t += " The target must succeed on a DC %d %s saving throw or %s%s." % [oh.dc, Stats.ABILITY_NAMES.get(oh.ability, "?"),
				"take " + " and ".join(rider) if not rider.is_empty() else "suffer the effect", ", half on a success" if oh.get("half", false) and not oh.get("damage", []).is_empty() else ""]
		t += "\n"
	for p in m.get("powers", []):
		var sp: Dictionary = p.get("spell", {})
		var tg: Dictionary = sp.get("target", {})
		var shape = {"cone": "%d-foot cone", "line": "%d-foot line that is 5 feet wide", "sphere": "%d-foot radius around it", "cube": "%d-foot cube"}.get(tg.get("shape", ""), "%d-foot area") % tg.get("size", 0)
		var dmg := ", ".join(sp.get("damage", []).map(func(d): return "%s %s" % [d.dice, d.type]))
		t += "[b][i]%s%s.[/i][/b] Each creature in a %s makes a DC %d %s saving throw, taking %s damage on a failed save%s.\n" % [p.get("name", ""),
			(" (Recharge %d-6)" % p.recharge) if p.has("recharge") else "", shape, p.get("dc", 10), Stats.ABILITY_NAMES.get(sp.get("save", {}).get("ability", ""), "?"),
			dmg, ", or half as much on a success" if sp.get("save", {}).get("half", false) else ""]
	if str(m.get("desc", "")) != "":
		t += "\n[color=#a69f94]%s[/color]" % m.desc
	return t


func _spell_card(s: Dictionary) -> String:
	var lv: int = s.get("level", 0)
	var t := "[font_size=20][b][color=#b0a0ff]%s[/color][/b][/font_size]\n[i]%s[/i]\n\n" % [s.get("name", ""),
		("%s cantrip" % str(s.get("school", "")).capitalize()) if lv == 0 else ("%s-level %s" % [["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"][lv], s.get("school", "")])]
	var rng: int = s.get("range", 0)
	var tg: Dictionary = s.get("target", {})
	var area := ""
	if tg.get("type", "") == "area":
		area = " (%d-ft %s)" % [tg.get("size", 0), tg.get("shape", "")]
	t += "[b]Casting Time:[/b] %s\n[b]Range:[/b] %s%s\n[b]Duration:[/b] %s\n" % ["1 bonus action" if s.get("time", "") == "bonus" else "1 action",
		"Self" if rng == 0 else ("Touch" if rng == 5 else "%d feet" % rng), area,
		("Concentration, up to %d rounds" % s.get("effect", {}).get("expires_on", {}).get("count", 10)) if s.get("concentration", false) else ("%d rounds" % s.effect.expires_on.count if s.has("effect") else "Instantaneous")]
	t += "[b]Classes:[/b] %s\n\n" % ", ".join(s.get("classes", []).map(func(c): return Classes.ALL.get(c, {}).get("name", c)))
	var how := ""
	if s.has("attack"):
		how = "Make a %s spell attack" % s.attack
	elif s.has("save"):
		how = "Each target makes a %s saving throw" % Stats.ABILITY_NAMES.get(s.save.get("ability", ""), "?")
	if tg.get("type", "") == "creature":
		t += "Targets: %d creature%s%s%s.\n" % [tg.get("count", 1), "" if tg.get("count", 1) == 1 else "s",
			(" (+%d per slot level above %s)" % [tg.per_slot, ["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"][lv]]) if tg.get("per_slot", 0) > 0 and lv > 0 else "",
			", enemies only" if tg.get("filter", "") == "enemy" else ""]
	if how != "":
		t += how + ".\n"
	for d in s.get("damage", []):
		t += "Damage: %s %s%s%s.\n" % [d.dice, d.type, (" (+%s per slot level above)" % d.per_slot) if str(d.get("per_slot", "")) != "" else "", " (scales at 5th, 11th, 17th)" if d.get("cantrip", false) else ""]
	if s.has("save") and s.has("damage"):
		t += "On a success: %s.\n" % ("half damage" if s.save.get("half", false) else "no damage")
	if s.has("heal"):
		t += "Healing: %s%s.\n" % [s.heal.dice, " + modifier" if s.heal.get("add_mod", false) else ""]
	if s.has("effect"):
		var e: Dictionary = s.effect
		var bits := PackedStringArray(e.get("conditions", []))
		for k in e.get("mods", {}):
			bits.append("%s %s" % [k.replace("_", " "), str(e.mods[k]) if not e.mods[k] is bool else ""])
		t += "Effect (%s): %s for %d rounds%s%s.\n" % [{"hit": "on a hit", "fail": "on a failed save", "always": "on every target"}.get(e.get("on", ""), ""),
			", ".join(bits) if not bits.is_empty() else "named effect", e.get("expires_on", {}).get("count", 10),
			(", repeat %s save at end of each turn" % e.repeat_save.ability.to_upper()) if e.has("repeat_save") else "", ", ends on damage" if e.get("ends_on_damage", false) else ""]
	if s.has("push"):
		t += "Pushes %d ft.\n" % s.push.ft
	if str(s.get("desc", "")) != "":
		t += "\n[color=#a69f94]%s[/color]" % s.desc
	return t


func _item_card(it: Dictionary) -> String:
	var t := "[font_size=20][b][color=#f2c66d]%s[/color][/b][/font_size]\n[i]%s, %s%s[/i]\n\n" % [it.get("name", ""), {"weapon": "Weapon", "armor": "Armor",
		"shield": "Shield", "wondrous": "Wondrous item", "potion": "Potion"}.get(it.get("kind", ""), "Item"), it.get("rarity", ""),
		" (requires attunement)" if it.get("attunement", false) else ""]
	var bits := PackedStringArray()
	if it.has("attack_bonus") or it.has("damage_bonus"):
		bits.append("%s to attack, %s to damage" % [Dice.fmt_mod(it.get("attack_bonus", 0)), Dice.fmt_mod(it.get("damage_bonus", 0))])
	for d in it.get("extra_damage", []):
		bits.append("+%s %s damage on a hit" % [d.dice, d.type])
	if it.has("ac_bonus"): bits.append("%s AC" % Dice.fmt_mod(it.ac_bonus))
	if it.has("ac_unarmored_bonus"): bits.append("%s AC without armor or shield" % Dice.fmt_mod(it.ac_unarmored_bonus))
	if it.has("save_bonus"): bits.append("%s to saving throws" % Dice.fmt_mod(it.save_bonus))
	if not it.get("resist", []).is_empty(): bits.append("resistance to %s" % ", ".join(it.resist))
	for ab in it.get("ability_min", {}):
		bits.append("%s becomes %d" % [Stats.ABILITY_NAMES[ab], it.ability_min[ab]])
	if it.has("speed_min"): bits.append("speed at least %d ft" % it.speed_min)
	if it.get("kind", "") == "potion": bits.append("drink (action): regain %s HP" % it.get("heal", "?"))
	if it.get("base", "") == "damage_type": bits.append("resistance to a damage type chosen when given")
	for b in bits:
		t += "• %s\n" % b
	if str(it.get("desc", "")) != "":
		t += "\n[color=#a69f94]%s[/color]" % it.desc
	return t


# ---------------- Packs ----------------

func _export_pack() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.json ; Homebrew packs"])
	d.current_file = "homebrew.json"
	d.use_native_dialog = true
	d.file_selected.connect(func(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(Homebrew.export_pack(hud.state))
			hud.show_toast("Exported homebrew to %s" % path)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 520))


func _import_pack() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.json ; Homebrew packs"])
	d.use_native_dialog = true
	d.file_selected.connect(func(path):
		import_text(FileAccess.get_file_as_string(path))
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 520))


func import_text(text: String) -> bool:
	var r := Homebrew.parse_pack(text)
	if not r.ok:
		hud.show_toast(r.error, true)
		return false
	hud.send({"type": "homebrewImport", "pack": r.pack})
	return true
