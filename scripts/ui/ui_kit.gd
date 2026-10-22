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


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color(0.45, 0.36, 0.22, 0.9)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.2, 0.17, 0.15)
	btn.border_color = Color(0.5, 0.4, 0.25)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(4)
	btn.content_margin_left = 9
	btn.content_margin_right = 9
	btn.content_margin_top = 4
	btn.content_margin_bottom = 4
	var hover := btn.duplicate()
	hover.bg_color = Color(0.3, 0.24, 0.18)
	hover.border_color = GOLD
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.42, 0.3, 0.16)
	var disabled := btn.duplicate()
	disabled.bg_color = Color(0.13, 0.12, 0.12)
	disabled.border_color = Color(0.25, 0.22, 0.2)
	for kind in ["Button", "MenuButton", "OptionButton"]:
		t.set_stylebox("normal", kind, btn)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("disabled", kind, disabled)
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
		t.set_color("font_color", kind, PARCHMENT)
		t.set_color("font_hover_color", kind, Color.WHITE)
		t.set_color("font_disabled_color", kind, Color(0.45, 0.42, 0.4))
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.05, 0.05, 0.06)
	edit.border_color = Color(0.4, 0.33, 0.22)
	edit.set_border_width_all(1)
	edit.set_corner_radius_all(4)
	edit.set_content_margin_all(5)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit)
	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_color("font_color", "CheckBox", PARCHMENT)
	var tab := btn.duplicate()
	var tab_sel := pressed.duplicate()
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", hover)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	var tpanel := panel.duplicate()
	tpanel.bg_color = Color(0, 0, 0, 0)
	tpanel.set_border_width_all(0)
	t.set_stylebox("panel", "TabContainer", tpanel)
	var tip := panel.duplicate()
	tip.bg_color = Color(0.06, 0.05, 0.07, 0.97)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", PARCHMENT)
	return t


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
