extends RefCounted
## Helpers shared by the test files.

const DM := {"name": "DM", "is_dm": true}

var failures: Array = []
var state: Dictionary


func ok(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(a, b, msg: String) -> void:
	if a != b:
		failures.append("%s (got %s, expected %s)" % [msg, str(a), str(b)])


func fresh(w: int = 16, h: int = 16) -> void:
	state = RulesEngine.new_state(w, h)


## Adds a creature directly and returns its id.
func add(kind: String, template: String, pos: Vector2i, level: int = 5, side: String = "") -> String:
	var eng := RulesEngine.new(state)
	var before: Array = state.combatants.keys()
	eng.spawn({"kind": kind, "template": template, "level": level, "pos": pos})
	for id in state.combatants:
		if not before.has(id):
			if side != "":
				state.combatants[id].side = side
			return id
	return ""


func c(id: String) -> Dictionary:
	return state.combatants[id]


## Applies a command as the DM (or `user`) and keeps the new state on success.
func run(cmd: Dictionary, user: Dictionary = DM) -> Dictionary:
	var r := RulesEngine.apply(state, cmd, user)
	if r.ok:
		state = r.state
	return r


func must(cmd: Dictionary, user: Dictionary = DM) -> Dictionary:
	var r := run(cmd, user)
	ok(r.ok, "command %s failed: %s" % [cmd.type, r.error])
	return r


## Starts combat with initiative forced in the order given (first id acts first).
func start(order: Array) -> void:
	var rolls := []
	for id in state.combatants:
		rolls.append(20 - 6 * order.find(id) if order.has(id) else 1)
	Dice.forced = rolls
	must({"type": "startCombat"})
	Dice.forced.clear()


func current() -> String:
	return state.combat.order[state.combat.turn_index]


func engine() -> RulesEngine:
	return RulesEngine.new(state)


func log_has(fragment: String) -> bool:
	for e in state.log:
		if fragment in e.text or fragment in e.get("detail", ""):
			return true
	return false
