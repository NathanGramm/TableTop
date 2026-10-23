extends "res://tests/test_base.gd"


func test_every_item_has_an_icon() -> void:
	for id in Equipment.WEAPONS.keys() + Equipment.ARMOR.keys() + Items.ALL.keys() + Equipment.AMMO.keys() + ["shield", "focus", "unarmed", "wondrous"]:
		ok(Icons.tex("items", id) != null, "no icon for item " + id)


func test_homebrew_items_fall_back_by_kind() -> void:
	ok(Icons.item_tex("no_such_item") == Icons.tex("items", "wondrous"), "unknown item uses the wondrous icon")
	eq(Icons.item_tex("longsword").get_width(), 64, "icons are 64 px")
