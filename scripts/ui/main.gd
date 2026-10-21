extends Node
## Root of the app: shows the menu, then the 3D table once a session starts.

const MenuScript := preload("res://scripts/ui/menu.gd")
const BoardScript := preload("res://scripts/ui/board.gd")
const HudScript := preload("res://scripts/ui/hud.gd")

var menu: Control
var board: Node3D
var hud: Control
var _ui_layer: CanvasLayer
var _menu_layer: CanvasLayer


func _ready() -> void:
	get_window().title = "TableTop — D&D 5e"
	get_window().min_size = Vector2i(1280, 720)
	Net.status_changed.connect(_on_status)
	Net.state_changed.connect(_on_state)
	_show_menu()
	# Debug helpers: `godot -- --offline` skips the menu; `--screenshot=path.png` saves a frame and quits.
	var args := OS.get_cmdline_user_args()
	if args.has("--offline"):
		Net.play_offline("DM")
		if args.has("--fresh"):
			Net.new_game()
		if args.has("--combat"):
			Dice.forced = [20, 18, 15, 12, 5, 4, 3]
			Net.send({"type": "startCombat"})
		if args.has("--attack-mode") and hud != null:
			hud._begin_attack(hud.sel().attacks[0].id)
	if args.has("--selftest"):
		var t: Node = load("res://scripts/ui/selftest.gd").new()
		t.main = self
		add_child(t)
	for a in args:
		if a.begins_with("--screenshot="):
			_screenshot_later(a.get_slice("=", 1))


func _screenshot_later(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _show_menu(message: String = "", bad: bool = false) -> void:
	_free_game()
	if menu == null:
		_menu_layer = CanvasLayer.new()
		add_child(_menu_layer)
		menu = MenuScript.new()
		menu.theme = UiKit.make_theme()
		_menu_layer.add_child(menu)
	menu.show_status(message, bad)


func _start_game() -> void:
	if board != null:
		return
	if menu != null:
		_menu_layer.queue_free()
		menu = null
	board = BoardScript.new()
	add_child(board)
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	hud = HudScript.new()
	hud.main = self
	_ui_layer.add_child(hud)
	hud.attach_board(board)


func _free_game() -> void:
	if board != null:
		board.queue_free()
		board = null
	if _ui_layer != null:
		_ui_layer.queue_free()
		_ui_layer = null
		hud = null


func _on_state(_events: Array) -> void:
	if board == null and not Net.state.is_empty():
		_start_game()
		hud._on_state(_events)


func _on_status(status: String, detail: String) -> void:
	match status:
		"failed", "disconnected":
			Net.leave()
			_show_menu(detail, true)


func leave_game() -> void:
	Net.leave()
	_show_menu("Left the game.")


func save_dialog() -> void:
	var d := _dialog(FileDialog.FILE_MODE_SAVE_FILE)
	d.file_selected.connect(func(path):
		if Net.save_game(path):
			hud.show_toast("Saved to " + path)
		else:
			hud.show_toast("Couldn't save.", true))
	d.popup_centered(Vector2i(800, 520))


func load_dialog() -> void:
	var d := _dialog(FileDialog.FILE_MODE_OPEN_FILE)
	d.file_selected.connect(func(path):
		if not Net.load_game(path):
			hud.show_toast("That isn't a TableTop save.", true))
	d.popup_centered(Vector2i(800, 520))


func _dialog(file_mode: FileDialog.FileMode) -> FileDialog:
	var d := FileDialog.new()
	d.file_mode = file_mode
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.filters = PackedStringArray(["*.save ; TableTop saves"])
	d.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	d.use_native_dialog = true
	d.close_requested.connect(d.queue_free)
	d.file_selected.connect(func(_p): d.queue_free())
	add_child(d)
	return d
