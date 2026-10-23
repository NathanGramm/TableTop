extends "res://tests/test_base.gd"
## Every spell has an icon, and every school has a fallback for homebrew spells (tools/icons/spells.py).

func test_every_spell_has_an_icon() -> void:
	for sid in Spells.ALL:
		ok(ResourceLoader.exists("res://assets/icons/spells/%s.png" % sid), "icon for " + sid)
		ok(ResourceLoader.exists("res://assets/icons/spells/school_%s.png" % Spells.ALL[sid].school), "school icon for " + sid)
