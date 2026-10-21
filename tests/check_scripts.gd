extends SceneTree
## Loads every script so parse errors surface. Run: godot --headless --script res://tests/check_scripts.gd
func _init() -> void:
	var bad := 0
	for dir in ["res://scripts/rules", "res://scripts/data", "res://scripts/net", "res://scripts/ui", "res://tests"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".gd"):
				var s = load(dir + "/" + f)
				if s == null or not s.can_instantiate():
					printerr("FAILED: ", dir + "/" + f)
					bad += 1
	printerr("checked, failures: ", bad)
	quit(1 if bad else 0)
