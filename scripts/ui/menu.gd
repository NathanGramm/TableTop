extends Control
## Title screen: host a game (you're the DM), join a friend's game, or play offline.

const PREFS := "user://prefs.cfg"

var name_edit: LineEdit
var port_spin: SpinBox
var upnp_check: CheckBox
var addr_edit: LineEdit
var join_port: SpinBox
var status_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.055)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = UiKit.panel()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v = UiKit.vbox(10)
	panel.add_child(v)

	var title = UiKit.label("TableTop", 44, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub = UiKit.label("A 3D tabletop for D&D 5th Edition (2014 rules)", 15, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())

	var cfg := ConfigFile.new()
	cfg.load(PREFS)
	var row = UiKit.hbox()
	row.add_child(UiKit.label("Your name"))
	name_edit = LineEdit.new()
	name_edit.text = cfg.get_value("menu", "name", "")
	name_edit.placeholder_text = "e.g. Nathan"
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	v.add_child(row)

	v.add_child(UiKit.label("Host a game — you're the Dungeon Master", 18, UiKit.GOLD))
	row = UiKit.hbox()
	row.add_child(UiKit.label("Port"))
	port_spin = UiKit.spin(1024, 65535, cfg.get_value("menu", "port", Net.DEFAULT_PORT), 110)
	row.add_child(port_spin)
	upnp_check = UiKit.check("Try automatic port forwarding (UPnP)", cfg.get_value("menu", "upnp", true), func(_on): pass)
	row.add_child(upnp_check)
	v.add_child(row)
	var host_btn = UiKit.button("Host Game", _on_host)
	host_btn.custom_minimum_size.y = 38
	v.add_child(host_btn)

	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("Join a friend's game", 18, UiKit.GOLD))
	row = UiKit.hbox()
	row.add_child(UiKit.label("Address"))
	addr_edit = LineEdit.new()
	addr_edit.text = cfg.get_value("menu", "address", "127.0.0.1")
	addr_edit.placeholder_text = "host's IP address"
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(addr_edit)
	row.add_child(UiKit.label("Port"))
	join_port = UiKit.spin(1024, 65535, cfg.get_value("menu", "join_port", Net.DEFAULT_PORT), 110)
	row.add_child(join_port)
	v.add_child(row)
	var join_btn = UiKit.button("Join Game", _on_join)
	join_btn.custom_minimum_size.y = 38
	v.add_child(join_btn)

	v.add_child(HSeparator.new())
	v.add_child(UiKit.button("Play Offline (solo / testing)", _on_offline))
	status_label = UiKit.label("", 14, UiKit.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status_label)


func show_status(text: String, bad: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", UiKit.RED if bad else UiKit.MUTED)


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Player"


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "name", name_edit.text.strip_edges())
	cfg.set_value("menu", "port", int(port_spin.value))
	cfg.set_value("menu", "upnp", upnp_check.button_pressed)
	cfg.set_value("menu", "address", addr_edit.text.strip_edges())
	cfg.set_value("menu", "join_port", int(join_port.value))
	cfg.save(PREFS)


func _on_host() -> void:
	_save_prefs()
	var err := Net.host(_player_name(), int(port_spin.value), upnp_check.button_pressed)
	if err != "":
		show_status(err, true)


func _on_join() -> void:
	_save_prefs()
	if addr_edit.text.strip_edges() == "":
		show_status("Enter the host's address.", true)
		return
	var err := Net.join(_player_name(), addr_edit.text, int(join_port.value))
	if err != "":
		show_status(err, true)
	else:
		show_status("Connecting...")


func _on_offline() -> void:
	_save_prefs()
	Net.play_offline(_player_name())
