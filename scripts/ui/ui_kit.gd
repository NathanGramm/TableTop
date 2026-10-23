class_name UiKit
extends RefCounted
## Theme and small widget helpers so the UI code stays readable.

const GOLD := Color(0.95, 0.78, 0.42)
const PARCHMENT := Color(0.93, 0.88, 0.78)
const MUTED := Color(0.65, 0.62, 0.58)
const PANEL := Color(0.09, 0.08, 0.1, 0.985)
const PANEL_LIGHT := Color(0.16, 0.14, 0.17, 0.95)
const RED := Color(0.9, 0.35, 0.3)
const GREEN := Color(0.45, 0.85, 0.5)
const BLUE := Color(0.5, 0.7, 1.0)


## The BG3-like look shared by every screen (art in assets/ui from tools/ui/bar_art.py): fog-on-dark-gray
## panels in a bronze and gold frame, bronze-framed buttons, sunken "Inset" boxes, and "BarIcon"
## buttons that are just their icon with a gold ring on hover.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := tex_box("panel.png", 30)
	panel.set_content_margin_all(16)
	for kind in ["PanelContainer", "Panel", "PopupPanel", "TooltipPanel"]:
		t.set_stylebox("panel", kind, panel)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("panel", "AcceptDialog", panel)
	t.set_stylebox("embedded_border", "Window", panel)
	t.set_stylebox("embedded_unfocused_border", "Window", panel)
	t.set_color("title_color", "Window", GOLD)
	t.set_constant("title_height", "Window", 30)
	var inset := tex_box("inset.png", 8)
	inset.set_content_margin_all(10)
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", inset)
	var looks := {"normal": "button.png", "hover": "button_hover.png", "pressed": "button_pressed.png", "disabled": "button.png"}
	var boxes := {}
	for st in looks:
		var sb := tex_box(looks[st], 12)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if st == "disabled":
			sb.modulate_color = Color(0.6, 0.6, 0.6)
		boxes[st] = sb
	for kind in ["Button", "MenuButton", "OptionButton"]:
		for st in boxes:
			t.set_stylebox(st, kind, boxes[st])
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_color("font_color", kind, PARCHMENT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, Color(0.5, 0.46, 0.4))
	t.set_stylebox("hover_pressed", "Button", boxes.pressed)
	t.set_stylebox("tab_unselected", "TabContainer", boxes.normal)
	t.set_stylebox("tab_hovered", "TabContainer", boxes.hover)
	t.set_stylebox("tab_selected", "TabContainer", boxes.pressed)
	t.set_stylebox("tab_disabled", "TabContainer", boxes.disabled)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", PARCHMENT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	var edit := tex_box("inset.png", 8)
	edit.set_content_margin_all(6)
	var edit_focus := edit.duplicate()
	edit_focus.modulate_color = Color(1.25, 1.15, 1.0)  # a warmer frame while typing
	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, edit)
		t.set_stylebox("read_only", kind, edit)
		t.set_stylebox("focus", kind, edit_focus)
		t.set_color("font_color", kind, PARCHMENT)
		t.set_color("caret_color", kind, GOLD)
		t.set_color("selection_color", kind, Color(0.55, 0.42, 0.2, 0.6))
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	for kind in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", kind, PARCHMENT)
		t.set_color("font_hover_color", kind, Color.WHITE)
	t.set_color("font_color", "TooltipLabel", PARCHMENT)
	t.set_color("font_color", "PopupMenu", PARCHMENT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var hl := tex_box("button_hover.png", 12)
	hl.set_content_margin_all(2)
	t.set_stylebox("hover", "PopupMenu", hl)
	var sep := StyleBoxLine.new()
	sep.color = Color(0.54, 0.42, 0.23, 0.7)
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("separator", "PopupMenu", sep)
	var vsep := sep.duplicate()
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	var grab := StyleBoxFlat.new()  # scroll bars: thin bronze grabbers on a dark track
	grab.bg_color = Color(0.54, 0.42, 0.23)
	grab.set_corner_radius_all(4)
	grab.set_content_margin_all(4)
	var grab_hi := grab.duplicate()
	grab_hi.bg_color = GOLD
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.35)
	track.set_corner_radius_all(4)
	track.set_content_margin_all(4)
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", kind, grab)
		t.set_stylebox("grabber_highlight", kind, grab_hi)
		t.set_stylebox("grabber_pressed", kind, grab_hi)
		t.set_stylebox("scroll", kind, track)
	t.set_type_variation("BarIcon", "Button")
	var none := StyleBoxEmpty.new()
	none.set_content_margin_all(1)
	var ring := tex_box("slot_ring.png", 12)
	ring.set_content_margin_all(1)
	for st in ["normal", "disabled", "focus"]:
		t.set_stylebox(st, "BarIcon", none)
	t.set_stylebox("hover", "BarIcon", ring)
	t.set_stylebox("pressed", "BarIcon", ring)
	t.set_stylebox("hover_pressed", "BarIcon", ring)
	t.set_color("icon_disabled_color", "BarIcon", Color(0.38, 0.36, 0.34))
	t.set_color("icon_normal_color", "BarIcon", Color.WHITE)
	return t


## A 9-slice of one of the assets/ui textures.
static func tex_box(file: String, margin: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/" + file)
	sb.set_texture_margin_all(margin)
	return sb


static func label(text: String, size: int = 15, color: Color = PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, tooltip: String = "", disabled: bool = false) -> Button:
	var b := TipButton.new()
	b.text = text
	b.tooltip_text = tooltip
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


## The hover card behind TipButton/TipRichText tooltips: BBCode, wrapped to a readable width.
static func tip_card(text: String) -> Control:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = 420
	r.text = text
	return r


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel() -> PanelContainer:
	return PanelContainer.new()


## A sunken box for a section inside a panel.
static func inset() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Inset"
	return p


static func spin(min_v: int, max_v: int, value: int, width: int = 80) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	s.custom_minimum_size.x = width
	return s


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(str(it))
	if items.size() > 0:
		o.select(selected)
	return o


static func check(text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func hex(c: Color) -> String:
	return c.to_html(false)
