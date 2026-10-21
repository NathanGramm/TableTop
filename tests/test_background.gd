extends "res://tests/test_base.gd"


func _png(w: int, h: int) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.5, 0.2))
	return img.save_png_to_buffer()


func test_battle_map_image() -> void:
	fresh()
	var bob := {"name": "Bob", "is_dm": false}
	ok(not run({"type": "setBackground", "data": _png(350, 210)}, bob).ok, "only the DM sets the map")
	ok(not run({"type": "setBackground", "data": PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])}).ok, "garbage is rejected")
	must({"type": "setBackground", "data": _png(350, 210), "px_per_square": 35})
	eq([state.map.width, state.map.height], [10, 6], "grid sized to the image")
	eq([state.background.width, state.background.height], [350, 210], "image size recorded")
	var view := RulesEngine.redact_for(state, bob)
	ok(not view.background.has("data") and view.background.hash == state.background.hash, "players get the hash, not the bytes")
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	must({"type": "setBackground", "data": img.save_jpg_to_buffer()})
	eq(state.map.width, 10, "px 0 keeps the grid size")
	must({"type": "clearBackground"})
	ok(not state.has("background"), "removed")
