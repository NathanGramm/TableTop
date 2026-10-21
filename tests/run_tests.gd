extends SceneTree
## Headless test runner:
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every test_* method in tests/test_*.gd and exits non-zero on failure.

func _init() -> void:
	var total := 0
	var failed := 0
	var d := DirAccess.open("res://tests")
	var files := Array(d.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			Dice.forced.clear()
			t.call(name)
			total += 1
			if t.failures.is_empty():
				print("  ok   %s::%s" % [f.get_basename(), name])
			else:
				failed += 1
				print("  FAIL %s::%s" % [f.get_basename(), name])
				for msg in t.failures:
					print("         " + msg)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
