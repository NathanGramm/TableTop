extends Control
## Character creator (and level-up/edit screen). Walks through the PHB steps — race & class,
## ability scores, background & skills, class features, equipment, spells — with a live preview,
## then sends `createCharacter` or `updateCharacter` to the host. The same rules in Creator.validate()
## run here and on the host.

const SheetScript := preload("res://scripts/ui/character_sheet.gd")
const STEPS := [["basics", "1. Race & Class"], ["abilities", "2. Ability Scores"], ["skills", "3. Background & Skills"],
	["features", "4. Class Features"], ["equipment", "5. Equipment"], ["spells", "6. Spells"], ["review", "7. Review"]]
const ANCESTRY_COLORS := {"black": "#3b3b3b", "blue": "#3a6fd8", "brass": "#c9a43a", "bronze": "#b07a3a", "copper": "#c06a3a",
	"gold": "#e0b83a", "green": "#3a9a4a", "red": "#c03a3a", "silver": "#c0c8d0", "white": "#e8e8f0"}

var hud: Control
var def: Dictionary = {}
var edit_id := ""
var step := "basics"
var _content: VBoxContainer
var _scroll: ScrollContainer
var _preview: RichTextLabel
var _errors: RichTextLabel
var _title: Label
var _step_btns := {}
var _create_btn: Button
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
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
	_title = UiKit.label("Create a Character", 24, UiKit.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(UiKit.button("Import…", _import, "Load a character saved as a .json file"))
	head.add_child(UiKit.button("Export…", _export, "Save this character to a .json file to use in other games"))
	head.add_child(UiKit.button("Cancel", close))
	root.add_child(head)
	var body := UiKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var steps := UiKit.vbox(6)
	steps.custom_minimum_size.x = 190
	for s in STEPS:
		var b := UiKit.button(s[1], func(): _go(s[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_step_btns[s[0]] = b
		steps.add_child(b)
	body.add_child(steps)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_content = UiKit.vbox(10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	var side := UiKit.vbox(8)
	side.custom_minimum_size.x = 330
	body.add_child(side)
	var pv := ScrollContainer.new()
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(_section_panel(pv))
	_preview = _rich_label()
	pv.add_child(_preview)
	_errors = _rich_label()
	side.add_child(_errors)
	var nav := UiKit.hbox(8)
	nav.alignment = BoxContainer.ALIGNMENT_END
	nav.add_child(UiKit.button("◀ Back", func(): _go(_neighbor(-1))))
	nav.add_child(UiKit.button("Next ▶", func(): _go(_neighbor(1))))
	_create_btn = UiKit.button("Create Character", _submit)
	_create_btn.modulate = UiKit.GOLD
	nav.add_child(_create_btn)
	side.add_child(nav)


func open_new() -> void:
	def = Creator.normalize(Creator.new_def("fighter", "human"))
	def.name = ""
	def.color = "#%s" % Color.from_hsv(_rng.randf(), 0.6, 0.85).to_html(false)
	def.armor = "chain_mail"
	def.weapons = ["longsword", "javelin"]
	def.shield = true
	edit_id = ""
	_title.text = "Create a Character"
	_create_btn.text = "Create Character"
	_go("basics")


func open_edit(c: Dictionary) -> void:
	def = Creator.normalize(c.def)
	def.level = c.level
	def.name = c.name
	edit_id = c.id
	_title.text = "Edit %s — level up or change choices" % c.name
	_create_btn.text = "Save Changes"
	_go("basics")


func close() -> void:
	visible = false
	if hud:
		hud.creator_closed()


func _neighbor(d: int) -> String:
	var ids := STEPS.map(func(s): return s[0])
	return ids[clampi(ids.find(step) + d, 0, ids.size() - 1)]


func _go(s: String) -> void:
	step = s
	for k in _step_btns:
		_step_btns[k].modulate = UiKit.GOLD if k == step else Color.WHITE
	_rebuild()
	_scroll.scroll_vertical = 0


## `structural` changes rebuild the step page; text edits only refresh the preview.
func _changed(structural: bool = true) -> void:
	if structural:
		_rebuild()
	else:
		_update_side()


func _rebuild() -> void:
	UiKit.clear(_content)
	match step:
		"basics": _step_basics()
		"abilities": _step_abilities()
		"skills": _step_skills()
		"features": _step_features()
		"equipment": _step_equipment()
		"spells": _step_spells()
		_: _step_review()
	_update_side()


# ---------------- Helpers ----------------

func _rich_label() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 13)
	r.add_theme_font_size_override("bold_font_size", 13)
	return r


func _section_panel(inner: Control) -> PanelContainer:
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
	v.add_child(UiKit.label(title, 18, UiKit.GOLD))
	if hint != "":
		var h := UiKit.label(hint, 13, UiKit.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(h)
	var p := _section_panel(v)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_content.add_child(p)
	return v


func _text(t: String, size: int = 13, color: Color = UiKit.PARCHMENT) -> Label:
	var l := UiKit.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _ability_option(selected: String, exclude: Array = []) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	var avail := Stats.ABILITIES.filter(func(a): return not exclude.has(a))
	for a in avail:
		o.add_item(Stats.ABILITY_NAMES[a])
		o.set_item_metadata(o.item_count - 1, a)
	o.select(maxi(0, avail.find(selected)))
	return o


func _cls() -> Dictionary:
	return Classes.ALL[def["class"]]


func _built() -> Dictionary:
	return Builder.build_character(def, int(def.level), "preview")


# ---------------- Step 1: race & class ----------------

func _step_basics() -> void:
	var v := _section("Who are you?")
	var row := UiKit.hbox(8)
	row.add_child(UiKit.label("Name"))
	var name_edit := LineEdit.new()
	name_edit.text = def.name
	name_edit.placeholder_text = "Character name"
	name_edit.max_length = 40
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t):
		def.name = t
		_changed(false))
	row.add_child(name_edit)
	row.add_child(UiKit.label("Token color"))
	var col := ColorPickerButton.new()
	col.color = Color.from_string(def.color, Color.STEEL_BLUE)
	col.custom_minimum_size = Vector2(60, 30)
	col.edit_alpha = false
	col.color_changed.connect(func(c):
		def.color = "#" + c.to_html(false))
	row.add_child(col)
	row.add_child(UiKit.label("Level"))
	var lvl := UiKit.spin(1, 20, int(def.level), 70)
	lvl.value_changed.connect(func(x):
		def.level = int(x)
		def = Creator.normalize(def)
		_changed())
	row.add_child(lvl)
	v.add_child(row)

	var rv := _section("Race", "Your race sets ability bonuses, speed, size and special traits.")
	var grid := GridContainer.new()
	grid.columns = 5
	for r in Classes.RACES:
		var rd: Dictionary = Classes.RACES[r]
		var b := UiKit.button(rd.name, func():
			def.race = r
			def = Creator.normalize(def)
			_changed())
		b.toggle_mode = true
		b.button_pressed = def.race == r
		b.custom_minimum_size.x = 150
		grid.add_child(b)
	rv.add_child(grid)
	var race: Dictionary = Classes.RACES[def.race]
	var asi := PackedStringArray()
	for a in race.asi:
		asi.append("%s +%d" % [a.to_upper(), race.asi[a]])
	if race.get("flex_asi", 0) > 0:
		asi.append("+1 to two others")
	var traits := PackedStringArray()
	for t in race.traits:
		if SheetScript.TRAITS.has(t):
			traits.append("%s: %s" % [SheetScript.TRAITS[t][0], SheetScript.TRAITS[t][1]])
	if race.has("resist"):
		traits.append("Resistance to %s damage" % ", ".join(race.resist))
	if race.has("skills"):
		traits.append("Proficient in %s" % ", ".join(race.skills.map(func(s): return Stats.skill_label(s))))
	if race.has("weapons"):
		traits.append("Weapon training: %s" % ", ".join(race.weapons.map(func(w): return Equipment.WEAPONS[w].name)))
	rv.add_child(_text("[%s]  %s, speed %d ft.  Languages: %s" % [", ".join(asi), race.size.capitalize(), race.speed, ", ".join(race.languages)], 13, UiKit.PARCHMENT))
	for t in traits:
		rv.add_child(_text("• " + t, 13, UiKit.MUTED))
	if def.race == "half_elf":
		var h := UiKit.hbox(8)
		h.add_child(UiKit.label("+1 to"))
		var flex: Array = def.flex_asi
		var a := _ability_option(flex[0] if flex.size() > 0 else "con", ["cha"])
		var b := _ability_option(flex[1] if flex.size() > 1 else "dex", ["cha"])
		var upd := func(_i):
			def.flex_asi = [a.get_item_metadata(a.selected), b.get_item_metadata(b.selected)]
			_changed(false)
		a.item_selected.connect(upd)
		b.item_selected.connect(upd)
		h.add_child(a)
		h.add_child(UiKit.label("and"))
		h.add_child(b)
		rv.add_child(h)
	if def.race == "dragonborn" or def["class"] == "sorcerer":
		var h := UiKit.hbox(8)
		h.add_child(UiKit.label("Draconic ancestry" if def.race == "dragonborn" else "Dragon ancestor (Draconic Bloodline)"))
		var o := OptionButton.new()
		var keys := Classes.DRACONIC_ANCESTRY.keys()
		for k in keys:
			var an: Dictionary = Classes.DRACONIC_ANCESTRY[k]
			o.add_item("%s — %s %s (%s save)" % [k.capitalize(), an.type, "15-ft cone" if an.shape == "cone" else "5×30-ft line", an.save.to_upper()])
		o.select(maxi(0, keys.find(def.ancestry)))
		o.item_selected.connect(func(i):
			def.ancestry = keys[i]
			def.color = ANCESTRY_COLORS.get(keys[i], def.color)
			_changed(false))
		h.add_child(o)
		rv.add_child(h)
	if def.race == "high_elf":
		var h := UiKit.hbox(8)
		h.add_child(UiKit.label("Bonus wizard cantrip"))
		var o := OptionButton.new()
		var ids := ["" ] + Spells.spells_for_class("wizard", 0)
		for id in ids:
			o.add_item("None" if id == "" else Spells.get_spell(id).name)
		o.select(maxi(0, ids.find(def.race_cantrip)))
		o.item_selected.connect(func(i):
			def.race_cantrip = ids[i]
			_changed(false))
		h.add_child(o)
		rv.add_child(h)

	var cv := _section("Class", "Each class comes with its SRD subclass.")
	var cg := GridContainer.new()
	cg.columns = 4
	for k in Classes.ALL:
		var cd: Dictionary = Classes.ALL[k]
		var b := UiKit.button("%s  (d%d)" % [cd.name, cd.hit_die], func():
			def["class"] = k
			def.skills = []
			def.spells = []
			def.options = []
			def.style = ""
			def.abilities = Creator.new_def(k, def.race).abilities if def.method == "standard" else def.abilities
			def = Creator.normalize(def)
			_default_equipment()
			_changed())
		b.toggle_mode = true
		b.button_pressed = def["class"] == k
		b.custom_minimum_size.x = 165
		cg.add_child(b)
	cv.add_child(cg)
	var cls := _cls()
	var caster = {"full": "Full spellcaster", "half": "Half spellcaster (from 2nd level)", "pact": "Pact Magic", "": "No spellcasting"}[cls.caster]
	cv.add_child(_text("Hit die d%d · Saving throws: %s · Armor: %s · Weapons: %s · %s" % [cls.hit_die,
		", ".join(cls.saves.map(func(s): return Stats.ABILITY_NAMES[s])),
		", ".join(cls.armor) if not cls.armor.is_empty() else "none",
		", ".join(cls.weapons.map(func(w): return w if w in ["simple", "martial"] else Equipment.WEAPONS[w].name)), caster]))
	cv.add_child(_text("Subclass: %s (gained at level %d)" % [cls.subclass.name, cls.subclass.level], 13, UiKit.MUTED))


## Reasonable gear when switching class.
func _default_equipment() -> void:
	var kits := {
		"barbarian": ["", false, ["greataxe", "handaxe", "handaxe", "javelin"]], "bard": ["leather", false, ["rapier", "dagger"]],
		"cleric": ["chain_mail", true, ["mace", "light_crossbow"]], "druid": ["hide", true, ["quarterstaff", "sling"]],
		"fighter": ["chain_mail", true, ["longsword", "javelin"]], "monk": ["", false, ["shortsword", "dart"]],
		"paladin": ["chain_mail", true, ["longsword", "javelin"]], "ranger": ["studded_leather", false, ["longbow", "shortsword", "shortsword"]],
		"rogue": ["leather", false, ["rapier", "shortbow", "dagger", "dagger"]], "sorcerer": ["", false, ["dagger", "light_crossbow"]],
		"warlock": ["leather", false, ["dagger", "light_crossbow"]], "wizard": ["", false, ["quarterstaff", "dagger"]],
	}
	var k: Array = kits[def["class"]]
	def.armor = k[0]
	def.shield = k[1]
	def.weapons = k[2].duplicate()


# ---------------- Step 2: ability scores ----------------

func _step_abilities() -> void:
	var v := _section("Ability Scores", "Pick a method, then assign scores. Racial bonuses and Ability Score Improvements are added on top.")
	var row := UiKit.hbox(8)
	row.add_child(UiKit.label("Method"))
	var mo := OptionButton.new()
	for m in Creator.METHODS:
		mo.add_item(Creator.METHOD_NAMES[m])
	mo.select(Creator.METHODS.find(def.method))
	mo.item_selected.connect(func(i):
		var m: String = Creator.METHODS[i]
		def.method = m
		if m == "standard" or m == "pointbuy":
			def.abilities = Creator.new_def(def["class"], def.race).abilities
		elif m == "roll":
			def.rolled = []
		_changed())
	row.add_child(mo)
	if def.method == "roll":
		row.add_child(UiKit.button("🎲 Roll 4d6 ×6" if def.rolled.is_empty() else "🎲 Reroll", _roll_scores, "Each score: roll 4d6 and drop the lowest die"))
	if def.method == "pointbuy":
		var spent := Creator.point_buy_spent(def.abilities)
		row.add_child(UiKit.label("Points spent: %d / %d" % [spent, Creator.POINT_BUY_BUDGET], 15, UiKit.RED if spent > 27 else UiKit.GOLD))
	v.add_child(row)
	if def.method == "roll":
		if def.rolled.is_empty():
			v.add_child(_text("Click Roll. Your results are posted to the table log when the character is created.", 13, UiKit.MUTED))
		else:
			v.add_child(_text("Rolled: %s — assign them below." % ", ".join(def.rolled.map(func(x): return str(x))), 14, UiKit.GOLD))
	if def.method == "manual":
		v.add_child(_text("Manual entry is for scores your DM has approved (3-20).", 13, UiKit.MUTED))

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	for h in ["Ability", "Base", "Race", "ASI", "Total", "Modifier"]:
		grid.add_child(UiKit.label(h, 12, UiKit.MUTED))
	var race := Creator.racial_bonus(def)
	var asi := Creator.asi_bonus(def, int(def.level))
	var final := Creator.final_abilities(def, int(def.level))
	var pool: Array = Creator.STANDARD_ARRAY if def.method == "standard" else def.rolled
	for ab in Stats.ABILITIES:
		grid.add_child(UiKit.label(Stats.ABILITY_NAMES[ab], 15))
		var base: int = def.abilities[ab]
		if def.method in ["standard", "roll"] and not pool.is_empty():
			var o := OptionButton.new()
			o.focus_mode = Control.FOCUS_NONE
			var values: Array = pool.duplicate()
			values.sort()
			values.reverse()
			for x in values:
				o.add_item(str(x))
			o.select(maxi(0, values.find(base)))
			o.item_selected.connect(func(i): _assign_score(ab, int(values[i])))
			grid.add_child(o)
		elif def.method == "roll":
			grid.add_child(UiKit.label("—", 15, UiKit.MUTED))
		else:
			var sp := UiKit.spin(8 if def.method == "pointbuy" else 3, 15 if def.method == "pointbuy" else 20, base, 80)
			sp.value_changed.connect(func(x):
				def.abilities[ab] = int(x)
				_changed())
			grid.add_child(sp)
		grid.add_child(UiKit.label(Dice.fmt_mod(race[ab]) if race[ab] != 0 else "—", 15, UiKit.MUTED))
		grid.add_child(UiKit.label(Dice.fmt_mod(asi[ab]) if asi[ab] != 0 else "—", 15, UiKit.MUTED))
		grid.add_child(UiKit.label(str(final[ab]), 18, UiKit.GOLD))
		grid.add_child(UiKit.label(Dice.fmt_mod(Stats.mod(final[ab])), 18))
	v.add_child(grid)

	var levels := Creator.asi_levels(def["class"]).filter(func(l): return l <= int(def.level))
	if not levels.is_empty():
		var av := _section("Ability Score Improvements", "At these levels, add +2 to one score or +1 to two (max 20). Pick the same ability twice for +2.")
		for lv in levels:
			var h := UiKit.hbox(8)
			h.add_child(UiKit.label("Level %d:" % lv))
			var inc := Creator.asi_at(def, lv)
			var picks := []
			for k in inc:
				for i in int(inc[k]):
					picks.append(k)
			while picks.size() < 2:
				picks.append(picks[0] if not picks.is_empty() else "str")
			var a := _ability_option(picks[0])
			var b := _ability_option(picks[1])
			var upd := func(_i):
				var x: String = a.get_item_metadata(a.selected)
				var y: String = b.get_item_metadata(b.selected)
				def.asi[lv] = {x: 2} if x == y else {x: 1, y: 1}
				def.asi.erase(str(lv))
				_changed()
			a.item_selected.connect(upd)
			b.item_selected.connect(upd)
			h.add_child(UiKit.label("+1"))
			h.add_child(a)
			h.add_child(UiKit.label("+1"))
			h.add_child(b)
			av.add_child(h)


func _assign_score(ab: String, value: int) -> void:
	# Swap with whichever ability currently holds that value.
	var old: int = def.abilities[ab]
	for other in Stats.ABILITIES:
		if other != ab and int(def.abilities[other]) == value:
			def.abilities[other] = old
			break
	def.abilities[ab] = value
	_changed()


func _roll_scores() -> void:
	var rolls := []
	for i in 6:
		rolls.append(Dice.roll(_rng, "4d6kh3").total)
	def.rolled = rolls
	var sorted := rolls.duplicate()
	sorted.sort()
	sorted.reverse()
	var order: Array = Creator._ability_priority(def["class"])
	for i in 6:
		def.abilities[order[i]] = sorted[i]
	_changed()


# ---------------- Step 3: background & skills ----------------

func _step_skills() -> void:
	var v := _section("Background", "Your background gives two skill proficiencies. Choose Custom to pick any two.")
	var bo := OptionButton.new()
	var keys := Creator.BACKGROUNDS.keys()
	for k in keys:
		var bg: Array = Creator.BACKGROUNDS[k]
		bo.add_item(bg[0] + ("" if bg[1].is_empty() else " (%s)" % ", ".join(bg[1].map(func(s): return Stats.skill_label(s)))))
	bo.select(maxi(0, keys.find(def.background)))
	bo.item_selected.connect(func(i):
		def.background = keys[i]
		def.background_skills = []
		var cs: Array = def.skills.filter(func(s): return not Creator.BACKGROUNDS[keys[i]][1].has(s))
		def.skills = cs
		_changed())
	v.add_child(bo)

	var pick := Creator.class_skill_choice(def["class"])
	var bg_fixed := Creator.background_skills(def) if def.background != "custom" else []
	var race_fixed := Creator.race_fixed_skills(def.race)
	var race_n := Creator.race_skill_choices(def.race)
	var exp_n := Creator.expertise_count(def["class"], int(def.level))
	var sv := _section("Skills", "Class: choose %d (%d chosen)%s%s." % [pick[0], def.skills.size(),
		(" · Half-elf: choose 2 (%d chosen)" % def.race_skills.size()) if race_n > 0 else "",
		(" · Expertise: choose %d (%d chosen)" % [exp_n, def.expertise.size()]) if exp_n > 0 else ""])
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 22)
	for h in ["Skill", _cls().name, "Background", "Race", "Expertise" if exp_n > 0 else ""]:
		grid.add_child(UiKit.label(h, 12, UiKit.MUTED))
	var all := Creator.all_skills(def)
	for sk in Stats.SKILLS:
		grid.add_child(UiKit.label("%s (%s)" % [Stats.skill_label(sk), Stats.SKILLS[sk].capitalize()], 14, UiKit.PARCHMENT if all.has(sk) else UiKit.MUTED))
		# Class column
		if pick[1].has(sk):
			var on: bool = def.skills.has(sk)
			var other = (bg_fixed.has(sk) or race_fixed.has(sk) or def.background_skills.has(sk) or def.race_skills.has(sk))
			var cb := UiKit.check("", on, func(t): _toggle_skill("skills", sk, t, pick[0]))
			cb.disabled = (not on and (def.skills.size() >= pick[0] or other))
			grid.add_child(cb)
		else:
			grid.add_child(UiKit.label("", 12))
		# Background column
		if def.background == "custom":
			var on: bool = def.background_skills.has(sk)
			var cb := UiKit.check("", on, func(t): _toggle_skill("background_skills", sk, t, 2))
			cb.disabled = not on and (def.background_skills.size() >= 2 or def.skills.has(sk) or race_fixed.has(sk) or def.race_skills.has(sk))
			grid.add_child(cb)
		else:
			grid.add_child(UiKit.label("●" if bg_fixed.has(sk) else "", 14, UiKit.GOLD))
		# Race column
		if race_fixed.has(sk):
			grid.add_child(UiKit.label("●", 14, UiKit.GOLD))
		elif race_n > 0:
			var on: bool = def.race_skills.has(sk)
			var cb := UiKit.check("", on, func(t): _toggle_skill("race_skills", sk, t, race_n))
			cb.disabled = not on and (def.race_skills.size() >= race_n or def.skills.has(sk) or bg_fixed.has(sk) or def.background_skills.has(sk))
			grid.add_child(cb)
		else:
			grid.add_child(UiKit.label("", 12))
		# Expertise column
		if exp_n > 0:
			var on: bool = def.expertise.has(sk)
			var cb := UiKit.check("", on, func(t): _toggle_skill("expertise", sk, t, exp_n))
			cb.disabled = not on and (def.expertise.size() >= exp_n or not all.has(sk))
			grid.add_child(cb)
		else:
			grid.add_child(UiKit.label("", 12))
	sv.add_child(grid)


func _toggle_skill(field: String, sk: String, on: bool, limit: int) -> void:
	var list: Array = def[field]
	if on and not list.has(sk) and list.size() < limit:
		list.append(sk)
	elif not on:
		list.erase(sk)
		if field != "expertise":
			def.expertise.erase(sk)
	_changed()


# ---------------- Step 4: class features ----------------

func _step_features() -> void:
	var lv := int(def.level)
	var cls := _cls()
	if Creator.needs_style(def["class"], lv):
		var v := _section("Fighting Style")
		var o := OptionButton.new()
		var styles: Array = Creator.STYLES[def["class"]]
		for s in styles:
			o.add_item(Creator.STYLE_NAMES[s])
		o.select(maxi(0, styles.find(def.style)))
		o.item_selected.connect(func(i):
			def.style = styles[i]
			_changed(false))
		v.add_child(o)
	if def["class"] == "fighter" and lv >= 10:
		var v2 := _section("Additional Fighting Style")
		var o2 := OptionButton.new()
		var others: Array = Creator.STYLES.fighter.filter(func(s): return s != def.style)
		for s in others:
			o2.add_item(Creator.STYLE_NAMES[s])
		o2.select(maxi(0, others.find(def.get("style2", ""))))
		o2.item_selected.connect(func(i):
			def.style2 = others[i]
			_changed(false))
		v2.add_child(o2)
	if def["class"] == "warlock" and lv >= 10:
		var v4 := _section("Fiendish Resilience", "Resistance to one damage type (you'd normally pick again after each rest).")
		var o4 := OptionButton.new()
		for t in Stats.DAMAGE_TYPES:
			o4.add_item(t.capitalize())
		o4.select(maxi(0, Stats.DAMAGE_TYPES.find(def.get("fiend_resist", "fire"))))
		o4.item_selected.connect(func(i):
			def.fiend_resist = Stats.DAMAGE_TYPES[i]
			_changed(false))
		v4.add_child(o4)
	if def["class"] == "ranger" and lv >= 7:
		var v3 := _section("Defensive Tactics")
		var o3 := OptionButton.new()
		var tacs: Array = Creator.TACTICS.keys()
		for t in tacs:
			o3.add_item(Creator.TACTICS[t])
		o3.select(maxi(0, tacs.find(def.options.filter(func(x): return Creator.TACTICS.has(x)).front() if def.options.any(func(x): return Creator.TACTICS.has(x)) else "")))
		o3.item_selected.connect(func(i):
			def.options = def.options.filter(func(x): return not Creator.TACTICS.has(x)) + [tacs[i]]
			_changed(false))
		v3.add_child(o3)
	if def["class"] == "warlock" and Creator.invocation_count(lv) > 0:
		_option_checks("Eldritch Invocations", Creator.INVOCATIONS, Creator.invocation_count(lv),
			"You know %d invocations; the two that matter in combat are automated." % Creator.invocation_count(lv))
	if def["class"] == "sorcerer" and Creator.metamagic_count(lv) > 0:
		_option_checks("Metamagic", Creator.METAMAGIC, Creator.metamagic_count(lv), "Choose up to %d." % Creator.metamagic_count(lv))
	var fv := _section("%s features through level %d" % [cls.name, lv], "★ = handled automatically by the game.")
	for f in cls.features:
		if f[0] <= lv:
			fv.add_child(_text("%s Level %d — %s%s" % ["★" if f[3] else "·", f[0], f[1], (": " + f[2]) if f[2] != "" else ""], 13,
				UiKit.PARCHMENT if f[3] else UiKit.MUTED))
	if lv > 10:
		fv.add_child(_text("Features above 10th level are listed on your sheet for reference but not automated yet (HP, proficiency, slots and scaling numbers are).", 12, UiKit.MUTED))


func _option_checks(title: String, choices: Dictionary, limit: int, hint: String) -> void:
	var v := _section(title, hint)
	for k in choices:
		var on: bool = def.options.has(k)
		var cb := UiKit.check(choices[k], on, func(t):
			if t and not def.options.has(k):
				def.options.append(k)
			elif not t:
				def.options.erase(k)
			_changed())
		var used = def.options.filter(func(o): return choices.has(o)).size()
		cb.disabled = not on and used >= limit
		v.add_child(cb)


# ---------------- Step 5: equipment ----------------

func _step_equipment() -> void:
	var cls := _cls()
	var v := _section("Armor & Shield", "Only armor your class is proficient with is listed.")
	var o := OptionButton.new()
	var ids := [""]
	for a in Equipment.ARMOR:
		if Creator.armor_allowed(def["class"], a):
			ids.append(a)
	for a in ids:
		var test := def.duplicate(true)
		test.armor = a
		var ac: int = Builder.build_character(test, int(def.level), "t").ac
		var armor_name: String = "No armor" if a == "" else Equipment.ARMOR[a].name
		var note := ""
		if a != "":
			var arm: Dictionary = Equipment.ARMOR[a]
			note = " — %s%s%s" % [arm.type, ", stealth disadvantage" if arm.stealth_dis else "", (", needs Str %d" % arm.str) if arm.has("str") else ""]
		o.add_item("%s (AC %d)%s" % [armor_name, ac, note])
	o.select(maxi(0, ids.find(def.armor)))
	o.item_selected.connect(func(i):
		def.armor = ids[i]
		_changed())
	v.add_child(o)
	if Creator.shield_allowed(def["class"]):
		v.add_child(UiKit.check("Shield (+2 AC, but no two-handed weapons or versatile grip)", def.shield, func(t):
			def.shield = t
			_changed()))

	var wv := _section("Weapons", "✓ = proficient (adds your proficiency bonus to hit). Thrown weapons can also be thrown.")
	var profs: Array = cls.weapons + Classes.RACES[def.race].get("weapons", [])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	for h in ["Weapon", "Damage", "Properties", "Carried"]:
		grid.add_child(UiKit.label(h, 12, UiKit.MUTED))
	var counts := {}
	for w in def.weapons:
		counts[w] = counts.get(w, 0) + 1
	for cat in ["simple", "martial"]:
		for wid in Equipment.WEAPONS:
			var w: Dictionary = Equipment.WEAPONS[wid]
			if w.cat != cat:
				continue
			var prof: bool = profs.has(cat) or profs.has(wid)
			grid.add_child(UiKit.label("%s %s" % ["✓" if prof else "  ", w.name], 14, UiKit.PARCHMENT if prof else UiKit.MUTED))
			grid.add_child(UiKit.label("%s %s%s" % [w.dice, w.type, (" (%s two-handed)" % w.versatile) if w.has("versatile") else ""], 13, UiKit.MUTED))
			var props: Array = w.props.duplicate()
			if w.has("range"):
				props.append("%d/%d ft" % w.range)
			grid.add_child(UiKit.label(", ".join(props), 12, UiKit.MUTED))
			var sp := UiKit.spin(0, 4, counts.get(wid, 0), 70)
			sp.value_changed.connect(func(x):
				var list: Array = def.weapons.filter(func(id): return id != wid)
				for i in int(x):
					list.append(wid)
				def.weapons = list
				_changed(false))
			grid.add_child(sp)
	wv.add_child(grid)


# ---------------- Step 6: spells ----------------

func _step_spells() -> void:
	var lv := int(def.level)
	var cls_id: String = def["class"]
	var max_lv := Creator.max_spell_level(cls_id, lv)
	if max_lv < 0:
		var v := _section("Spells")
		v.add_child(_text("%s doesn't cast spells%s." % [_cls().name, " until 2nd level" if _cls().caster == "half" else ""], 14))
		if def.race == "high_elf" and def.race_cantrip != "":
			v.add_child(_text("High elf cantrip: %s (chosen on the Race & Class step)." % Spells.get_spell(def.race_cantrip).name, 13, UiKit.MUTED))
		return
	var auto := Creator.always_prepared(def, lv)
	var chosen: Array = def.spells
	var n_cantrips := chosen.filter(func(s): return Spells.get_spell(s).level == 0).size()
	var n_spells := chosen.filter(func(s): return Spells.get_spell(s).level > 0 and not auto.has(s)).size()
	var c_lim := Creator.cantrip_limit(cls_id, lv)
	var s_lim := Creator.spell_limit(def, lv)
	var kind := "known" if Creator.SPELLS_KNOWN.has(cls_id) else "prepared"
	var head := _section("Spells", "Cantrips %d / %d · Spells %s %d / %d · Highest spell level %d. Only spells the game automates are listed." % [
		n_cantrips, c_lim, kind, n_spells, s_lim, max_lv])
	if def.race_cantrip != "":
		head.add_child(_text("High elf cantrip: %s (from your race, doesn't count against the limit)." % Spells.get_spell(def.race_cantrip).name, 13, UiKit.GOLD))
	if not auto.is_empty():
		head.add_child(_text("Always prepared (%s): %s" % [_cls().subclass.name, ", ".join(auto.map(func(s): return Spells.get_spell(s).name))], 13, UiKit.GOLD))
	var n_secrets: int = Creator.secrets_count(cls_id, lv)
	if n_secrets > 0:
		var used := chosen.filter(func(s): return not Spells.get_spell(s).get("classes", []).has(cls_id) and not auto.has(s)).size()
		var sv := _section("Magical Secrets %d / %d" % [used, n_secrets], "Spells from any class's list. The first %d leveled ones don't count against spells known." % Creator.free_secrets(cls_id, lv))
		var sflow := HFlowContainer.new()
		sflow.add_theme_constant_override("h_separation", 14)
		var others := []
		for sid in Spells.ALL.keys() + Homebrew.spells.keys():
			var sp := Spells.get_spell(sid)
			if sp.get("level", 99) <= max_lv and not sp.get("classes", []).has(cls_id) and sp.get("time", "") != "reaction" and not others.has(sid):
				others.append(sid)
		for sid in others:
			var sp := Spells.get_spell(sid)
			var on: bool = chosen.has(sid)
			var cb := UiKit.check("%s (%s)" % [sp.name, "cantrip" if sp.level == 0 else "lv %d" % sp.level], on, func(t):
				if t and not def.spells.has(sid):
					def.spells.append(sid)
				elif not t:
					def.spells.erase(sid)
				_changed())
			cb.disabled = not on and used >= n_secrets
			sflow.add_child(cb)
		sv.add_child(sflow)
	for sl in range(0, max_lv + 1):
		var ids := Spells.spells_for_class(cls_id, sl).filter(func(s): return Spells.get_spell(s).level == sl and not auto.has(s) and s != def.race_cantrip)
		if ids.is_empty() or (sl == 0 and c_lim == 0):
			continue
		var v := _section("Cantrips" if sl == 0 else "Level %d" % sl)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		for sid in ids:
			var sp := Spells.get_spell(sid)
			var on: bool = chosen.has(sid)
			var full: bool = (n_cantrips >= c_lim) if sl == 0 else (n_spells >= s_lim)
			var cb := UiKit.check("%s%s" % [sp.name, " (C)" if sp.get("concentration", false) else ""], on, func(t):
				if t and not def.spells.has(sid):
					def.spells.append(sid)
				elif not t:
					def.spells.erase(sid)
				_changed())
			cb.disabled = not on and full
			cb.tooltip_text = sp.desc
			cb.custom_minimum_size.x = 210
			flow.add_child(cb)
		v.add_child(flow)


# ---------------- Step 7: review ----------------

func _step_review() -> void:
	var c := _built()
	var v := _section("Review", "Check everything, then create. You can come back to edit or level up later from the character sheet.")
	var t := _rich_label()
	t.add_theme_font_size_override("normal_font_size", 15)
	t.add_theme_font_size_override("bold_font_size", 15)
	var skills := Creator.all_skills(def).map(func(s): return Stats.skill_label(s) + (" (expertise)" if def.expertise.has(s) else ""))
	var txt := "[b]%s[/b] — %s\n" % [def.name if def.name != "" else "(unnamed)", c.description]
	txt += "Background: %s\n\n" % Creator.BACKGROUNDS[def.background][0]
	txt += "HP %d · AC %d · Speed %d ft · Proficiency +%d\n" % [c.max_hp, c.ac, c.base_speed, c.prof]
	txt += "  ".join(Stats.ABILITIES.map(func(a): return "%s %d (%s)" % [a.to_upper(), c.abilities[a], Dice.fmt_mod(Stats.mod(c.abilities[a]))])) + "\n\n"
	txt += "Skills: %s\n" % ", ".join(skills)
	txt += "Equipment: %s\n" % ", ".join(c.equipment)
	if not c.spellcasting.is_empty():
		txt += "Spells: %s\n" % ", ".join(c.spellcasting.known.map(func(s): return Spells.get_spell(s).name))
	t.text = txt
	v.add_child(t)


# ---------------- Preview & submit ----------------

func _update_side() -> void:
	var c := _built()
	var t := "[font_size=18][b][color=#%s]%s[/color][/b][/font_size]\n[color=#a69f94]%s[/color]\n\n" % [
		Color.from_string(def.color, Color.WHITE).lightened(0.3).to_html(false), def.name if def.name != "" else "(unnamed)", c.description]
	t += "[b]HP[/b] %d   [b]AC[/b] %d   [b]Speed[/b] %d ft\n[b]Prof[/b] +%d   [b]Init[/b] %s   [b]Passive Perception[/b] %d\n\n" % [
		c.max_hp, c.ac, c.base_speed, c.prof, Dice.fmt_mod(Stats.mod(c.abilities.dex) + c.init_bonus), c.passive_perception]
	t += "[table=6]"
	for a in Stats.ABILITIES:
		t += "[cell][center][color=#a69f94]%s[/color][/center][/cell]" % a.to_upper()
	for a in Stats.ABILITIES:
		t += "[cell][center][b]%d[/b][/center][/cell]" % c.abilities[a]
	for a in Stats.ABILITIES:
		t += "[cell][center]%s[/center][/cell]" % Dice.fmt_mod(Stats.mod(c.abilities[a]))
	t += "[/table]\n\n[b]Saves[/b] %s\n" % ", ".join(c.save_profs.map(func(s): return s.to_upper()))
	var skills := PackedStringArray()
	for sk in c.skills:
		skills.append("%s%s" % [Stats.skill_label(sk), "★" if c.skills[sk] == 2 else ""])
	t += "[b]Skills[/b] %s\n\n[b]Attacks[/b]\n" % ", ".join(skills)
	for a in c.attacks:
		if a.id != "unarmed":
			t += " %s %s, %s\n" % [a.name, Dice.fmt_mod(a.to_hit), _dmg(a)]
	if not c.spellcasting.is_empty():
		var sc: Dictionary = c.spellcasting
		t += "\n[b]Spellcasting[/b] DC %d, %s to hit\n" % [sc.dc, Dice.fmt_mod(sc.attack_bonus)]
		t += "[color=#b0a0ff]%s[/color]\n" % ", ".join(sc.known.map(func(s): return Spells.get_spell(s).name))
	_preview.text = ""
	_preview.append_text(t)
	var errs := Creator.validate(def)
	_errors.text = ""
	if errs.is_empty():
		_errors.append_text("[color=#8fe39a]✓ Ready to %s.[/color]" % ("save" if edit_id != "" else "create"))
	else:
		_errors.append_text("[color=#ff8a7a]To finish:[/color]\n" + "\n".join(errs.slice(0, 6).map(func(e): return "• " + e)))
	_create_btn.disabled = not errs.is_empty()


func _dmg(a: Dictionary) -> String:
	var d: Dictionary = a.damage[0]
	return "%s%s %s" % [d.get("dice", ""), Dice.fmt_mod(d.get("bonus", 0)) if d.get("bonus", 0) != 0 else "", d.type]


func _submit() -> void:
	if not Creator.validate(def).is_empty():
		return
	if edit_id != "":
		hud.send({"type": "updateCharacter", "id": edit_id, "def": def.duplicate(true)})
	else:
		hud.expect_new_character(def.name)
		hud.send({"type": "createCharacter", "def": def.duplicate(true)})
	close()


func _export() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.json ; Character files"])
	d.current_file = (def.name if def.name != "" else "character").to_snake_case() + ".json"
	d.use_native_dialog = true
	d.file_selected.connect(func(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(def, "\t"))
			hud.show_toast("Saved %s" % path)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 520))


func _import() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.json ; Character files"])
	d.use_native_dialog = true
	d.file_selected.connect(func(path):
		import_text(FileAccess.get_file_as_string(path))
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(800, 520))


func import_text(text: String) -> bool:
	var data = JSON.parse_string(text)
	if not (data is Dictionary) or not Classes.ALL.has(data.get("class", "")):
		hud.show_toast("That file isn't a TableTop character.", true)
		return false
	def = Creator.normalize(data)
	_go("review")
	return true
