class_name RulesEngine
extends EngineMagic
## Command dispatch, permissions, initiative and turn flow, rests, DM tools and a simple monster AI.
##
## Usage (host only — clients just send commands):
##   var result := RulesEngine.apply(state, {"type": "move", "actor_id": "c3", "to": Vector2i(4, 5)}, {"name": "Nathan", "is_dm": true})
##   if result.ok: state = result.state  # result.events drive animations

const DM_COMMANDS := ["startCombat", "endCombat", "spawn", "addCombatant", "removeCombatant", "teleport", "adjustHp", "setHp",
	"toggleCondition", "setExhaustion", "setCells", "resizeMap", "setController", "setSurprised", "setSide", "requestRoll",
	"rest", "settings", "dmEndTurn", "autoTurn", "clearMap", "homebrewSave", "homebrewDelete", "homebrewImport",
	"giveItem", "takeItem", "grantSpell"]
## Sheet edits: the DM, or the creature's player, any time.
const SHEET_COMMANDS := ["setNotes", "rename"]
const NOTE_KEYS := ["background", "alignment", "xp", "personality", "ideals", "bonds", "flaws", "proficiencies",
	"equipment", "cp", "sp", "ep", "gp", "pp", "inspiration", "age", "height", "weight", "eyes", "skin", "hair",
	"appearance", "backstory", "allies", "features", "treasure"]
const ACTOR_COMMANDS := ["move", "attack", "cast", "power", "action", "feature", "grapple", "shove", "endTurn", "setReactions", "useItem"]


static func new_state(width: int = 26, height: int = 18) -> Dictionary:
	var cells := []
	cells.resize(width * height)
	cells.fill(Grid.FLOOR)
	return {
		"version": 1,
		"map": {"width": width, "height": height, "cells": cells},
		"combatants": {},
		"effects": [],
		"combat": {"active": false, "round": 0, "turn_index": 0, "order": []},
		"turn_counter": 0,
		"seq": 0,
		"log": [],
		"settings": {"diagonal": "5", "npcs_die_at_zero": true, "auto_npc": false, "flanking": false},
		"homebrew": {"monsters": {}, "spells": {}, "items": {}},
	}


## A small ruined hall to start on.
static func demo_state() -> Dictionary:
	var s := new_state(26, 18)
	var m: Dictionary = s.map
	var put := func(x: int, y: int, v: int) -> void: m.cells[y * m.width + x] = v
	for x in range(6, 20):
		if x != 12 and x != 13:
			put.call(x, 3, Grid.WALL)
			put.call(x, 14, Grid.WALL)
	for y in range(3, 15):
		if y != 8 and y != 9:
			put.call(6, y, Grid.WALL)
			put.call(19, y, Grid.WALL)
	for p in [Vector2i(10, 6), Vector2i(15, 6), Vector2i(10, 11), Vector2i(15, 11)]:
		put.call(p.x, p.y, Grid.WALL)
	for y in range(7, 11):
		for x in range(1, 4):
			put.call(x, y, Grid.DIFFICULT)
	for p in [Vector2i(12, 8), Vector2i(13, 9), Vector2i(12, 9), Vector2i(22, 4), Vector2i(23, 4), Vector2i(22, 5)]:
		put.call(p.x, p.y, Grid.DIFFICULT)
	return s


## Applies a command on a copy of the state. Returns {ok, error, state, events}.
static func apply(state: Dictionary, cmd: Dictionary, user: Dictionary, p_rng: RandomNumberGenerator = null) -> Dictionary:
	var work: Dictionary = state.duplicate(true)
	Homebrew.ensure(work)
	Homebrew.sync(work)
	var eng := RulesEngine.new(work, p_rng)
	var err := eng.permission_error(cmd, user)
	if err == "":
		err = eng.execute(cmd, user)
	if err != "":
		Homebrew.sync(state)
		return {"ok": false, "error": err, "state": state, "events": []}
	eng.run_auto_npcs()
	return {"ok": true, "error": "", "state": work, "events": eng.events}


func permission_error(cmd: Dictionary, user: Dictionary) -> String:
	var t: String = cmd.get("type", "")
	var is_dm: bool = user.get("is_dm", false)
	if DM_COMMANDS.has(t):
		return "" if is_dm else "Only the DM can do that."
	if ACTOR_COMMANDS.has(t):
		var a := get_c(cmd.get("actor_id", ""))
		if a.is_empty():
			return "Select a creature first."
		if not is_dm and a.controller != user.get("name", ""):
			return "You don't control %s." % a.name
		if in_combat() and t != "setReactions" and current_id() != a.id:
			return "It's not %s's turn." % a.name
		if a.dead and t != "setReactions":
			return "%s is dead." % a.name
		return ""
	if t == "createCharacter":
		return ""
	if t == "updateCharacter":
		var target := get_c(cmd.get("id", ""))
		if target.is_empty():
			return "Unknown creature."
		if not is_dm and target.controller != user.get("name", ""):
			return "You can only edit your own character."
		if not is_dm and in_combat():
			return "You can level up or rebuild your character outside of combat."
		return ""
	if SHEET_COMMANDS.has(t):
		var target := get_c(cmd.get("id", ""))
		if target.is_empty():
			return "Unknown creature."
		return "" if is_dm or target.controller == user.get("name", "") else "You can only edit your own character sheet."
	if t in ["roll", "chat"]:
		return ""
	return "Unknown command '%s'." % t


func execute(cmd: Dictionary, user: Dictionary) -> String:
	var a := get_c(cmd.get("actor_id", ""))
	match cmd.type:
		"move":
			return move_to(a, cmd.to, cmd.get("crawl", false))
		"attack":
			var p := find_attack(a, cmd.get("attack_id", ""))
			if p.is_empty():
				return "Unknown attack."
			var t := get_c(cmd.get("target_id", ""))
			var opts: Dictionary = cmd.get("options", {})
			var err := validate_attack(a, t, effective_profile(a, p))
			if err != "":
				return err
			if a.surprised:
				return "%s is surprised and can't act this turn." % a.name
			var bonus: bool = opts.get("bonus", false)
			err = use_bonus_attack(a, p) if bonus else use_attack_slot(a, p)
			if err != "":
				return err
			weapon_attack(a, t, p, opts, bonus)
			return ""
		"cast":
			return cast(a, cmd.spell_id, cmd.get("slot", 0), cmd.get("targets", []), cmd.get("point", null), cmd.get("options", {}))
		"power":
			return use_power(a, cmd.power_id, cmd.get("targets", []), cmd.get("point", null))
		"action":
			return do_action(a, cmd.action, cmd.get("target_id", ""), cmd.get("via", "action"))
		"feature":
			return use_feature(a, cmd.feature, cmd.get("target_id", ""), cmd.get("amount", 0), cmd.get("choice", ""))
		"grapple":
			return do_grapple(a, get_c(cmd.target_id))
		"shove":
			return do_shove(a, get_c(cmd.target_id), cmd.get("mode", "prone"))
		"endTurn", "dmEndTurn":
			if not in_combat():
				return "Combat hasn't started."
			end_turn()
			return ""
		"setReactions":
			a.auto_reactions = cmd.auto
			return ""
		"autoTurn":
			var cur := get_c(current_id())
			if cur.is_empty():
				return "Combat hasn't started."
			ai_turn(cur)
			return ""
		"startCombat":
			return start_combat()
		"endCombat":
			return end_combat()
		"spawn":
			return spawn(cmd)
		"addCombatant":
			var c: Dictionary = cmd.combatant.duplicate(true)
			c.id = next_id("c")
			c.pos = free_spot(c, c.pos)
			state.combatants[c.id] = c
			_join_initiative(c)
			add_log("system", "%s joins the table." % c.name)
			return ""
		"removeCombatant":
			return remove_combatant(cmd.id)
		"teleport":
			var c := get_c(cmd.id)
			if c.is_empty():
				return "Unknown creature."
			for f in Grid.footprint(c, cmd.to):
				if Grid.cell_at(state.map, f.x, f.y) == Grid.WALL:
					return "That space is blocked."
			var from: Vector2i = c.pos
			c.pos = cmd.to
			events.append({"kind": "teleport", "id": c.id, "to": c.pos, "from": from})
			return ""
		"adjustHp":
			var c := get_c(cmd.id)
			if c.is_empty():
				return "Unknown creature."
			var n: int = cmd.amount
			if n < 0:
				deal_damage(c, [{"amount": -n, "type": cmd.get("damage_type", "untyped"), "text": ""}], {"label": "the DM"})
			elif n > 0:
				if c.dead:
					return "%s is dead (use Revivify, or set HP)." % c.name
				heal(c, n, "the DM")
			return ""
		"setHp":
			var c := get_c(cmd.id)
			if c.is_empty():
				return "Unknown creature."
			c.hp = clampi(cmd.hp, 0, c.max_hp)
			c.temp_hp = maxi(0, cmd.get("temp_hp", c.temp_hp))
			if c.hp > 0:
				c.dead = false
				c.stable = false
				c.death_saves = {"successes": 0, "failures": 0}
			if cmd.has("max_hp"):
				c.max_hp = maxi(1, cmd.max_hp)
			add_log("system", "DM sets %s to %d HP." % [c.name, c.hp])
			return ""
		"toggleCondition":
			var c := get_c(cmd.id)
			if c.is_empty():
				return "Unknown creature."
			var cond: String = cmd.condition
			if has_cond(c, cond):
				remove_effects_where(func(e): return e.target_id == c.id and e.get("conditions", []).has(cond))
				add_log("system", "%s is no longer %s." % [c.name, cond])
			else:
				add_effect({"name": cond.capitalize(), "tag": "prone" if cond == "prone" else "dm_" + cond, "conditions": [cond]}, c.id, c.id)
				add_log("system", "%s is now %s." % [c.name, cond])
			return ""
		"setExhaustion":
			var c := get_c(cmd.id)
			c.exhaustion = clampi(cmd.level, 0, 6)
			add_log("system", "%s exhaustion: %d." % [c.name, c.exhaustion])
			if c.exhaustion >= 6:
				kill(c, "exhaustion")
			return ""
		"setCells":
			for cell in cmd.cells:
				if Grid.in_bounds(state.map, cell.x, cell.y):
					state.map.cells[cell.y * state.map.width + cell.x] = cell.v
			return ""
		"clearMap":
			state.map.cells.fill(Grid.FLOOR)
			return ""
		"resizeMap":
			var w := clampi(cmd.width, 5, 80)
			var h := clampi(cmd.height, 5, 80)
			var cells := []
			cells.resize(w * h)
			cells.fill(Grid.FLOOR)
			for y in mini(h, state.map.height):
				for x in mini(w, state.map.width):
					cells[y * w + x] = state.map.cells[y * state.map.width + x]
			state.map = {"width": w, "height": h, "cells": cells}
			for c in combatants():
				c.pos = Vector2i(clampi(c.pos.x, 0, w - 1), clampi(c.pos.y, 0, h - 1))
			return ""
		"setController":
			var c := get_c(cmd.id)
			c.controller = cmd.get("controller", "")
			add_log("system", "%s is now controlled by %s." % [c.name, c.controller if c.controller else "the DM"])
			return ""
		"setSurprised":
			get_c(cmd.id).surprised = cmd.surprised
			return ""
		"setSide":
			get_c(cmd.id).side = cmd.side
			return ""
		"createCharacter":
			return create_character(cmd.get("def", {}), user, cmd.get("pos", null))
		"updateCharacter":
			return update_character(cmd.id, cmd.get("def", {}), user)
		"homebrewSave":
			return homebrew_save(cmd.get("kind", ""), cmd.get("id", ""), cmd.get("data", {}))
		"homebrewDelete":
			return homebrew_delete(cmd.get("kind", ""), cmd.get("id", ""))
		"homebrewImport":
			return homebrew_import(cmd.get("pack", {}))
		"giveItem":
			return give_item(cmd.id, cmd.get("item", {}))
		"takeItem":
			return take_item(cmd.id, int(cmd.get("index", -1)))
		"grantSpell":
			return grant_spell(cmd.id, cmd.get("spell_id", ""))
		"useItem":
			return use_item(a, int(cmd.get("index", -1)), cmd.get("target_id", ""))
		"setNotes":
			var key: String = str(cmd.get("key", ""))
			if not NOTE_KEYS.has(key):
				return "Unknown sheet field."
			var c := get_c(cmd.id)
			if not c.has("notes"):
				c["notes"] = {}
			c.notes[key] = str(cmd.get("value", "")).left(4000)
			return ""
		"rename":
			var c := get_c(cmd.id)
			if str(cmd.name).strip_edges() != "":
				c.name = str(cmd.name).strip_edges().left(40)
			return ""
		"requestRoll":
			var c := get_c(cmd.id)
			if c.is_empty():
				return "Unknown creature."
			match cmd.roll:
				"save":
					roll_save(c, cmd.ability, cmd.get("dc", 10), {"label": "DM request"})
				"skill":
					roll_check(c, Stats.SKILLS[cmd.skill], cmd.skill)
				_:
					roll_check(c, cmd.ability)
			return ""
		"rest":
			return rest(cmd.kind, cmd.get("ids", []))
		"settings":
			for k in cmd.settings:
				if state.settings.has(k):
					state.settings[k] = cmd.settings[k]
			return ""
		"roll":
			var expr: String = str(cmd.expr).strip_edges()
			if not Dice.is_valid(expr):
				return "Can't roll \"%s\" (try 1d20+5, 2d6, 4d6kh3)." % expr
			var r := Dice.roll(rng, expr)
			var label: String = cmd.get("label", "")
			add_log("roll", "%s rolls %s%s: %d" % [user.get("name", "?"), expr, (" (" + label + ")") if label else "", r.total], r.text, user.get("name", ""))
			if cmd.get("private", false):
				state.log[-1]["private"] = user.get("name", "")
			return ""
		"chat":
			var text: String = str(cmd.text).strip_edges().left(500)
			if text.is_empty():
				return "Empty message."
			add_log("chat", text, "", user.get("name", "?"))
			return ""
	return "Unknown command."


# ---------------- Initiative & turns ----------------

func start_combat() -> String:
	if in_combat():
		return "Combat is already running."
	var living := combatants().filter(func(c): return not c.dead)
	if living.is_empty():
		return "Add some creatures first."
	var lines := PackedStringArray()
	for c in living:
		var r := Dice.d20(rng, Dice.NORMAL, c.traits.has("lucky"))
		c.initiative = r.value + mod(c, "dex") + c.init_bonus
		c.fdata["init_tiebreak"] = rng.randf()
		lines.append("%s %d (%s %s)" % [c.name, c.initiative, r.text, Dice.fmt_mod(mod(c, "dex") + c.init_bonus)])
		c.turn = Stats.fresh_turn()
		c.reaction_used = c.surprised
		c.took_damage = false
	living.sort_custom(_init_order)
	state.combat = {"active": true, "round": 1, "turn_index": 0, "order": living.map(func(c): return c.id)}
	add_log("turn", "Roll for initiative! Combat begins.", "\n".join(lines))
	begin_turn(0)
	return ""


func _init_order(a: Dictionary, b: Dictionary) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if a.abilities.dex != b.abilities.dex:
		return a.abilities.dex > b.abilities.dex
	return a.fdata.get("init_tiebreak", 0.0) > b.fdata.get("init_tiebreak", 0.0)


func _join_initiative(c: Dictionary) -> void:
	if not in_combat():
		return
	var r := Dice.d20(rng)
	c.initiative = r.value + mod(c, "dex") + c.init_bonus
	c.fdata["init_tiebreak"] = rng.randf()
	var order: Array = state.combat.order
	var cur := current_id()
	var idx := order.size()
	for i in order.size():
		if _init_order(c, get_c(order[i])):
			idx = i
			break
	order.insert(idx, c.id)
	state.combat.turn_index = order.find(cur)
	add_log("turn", "%s joins initiative at %d." % [c.name, c.initiative], r.text)


func end_combat() -> String:
	if not in_combat():
		return "Combat isn't running."
	state.combat = {"active": false, "round": 0, "turn_index": 0, "order": []}
	# Effects lasting a minute or less end with the fight.
	remove_effects_where(func(e): return e.has("expires") and e.expires.count <= 10)
	remove_effects_where(func(e): return e.get("tag", "") in ["dodge", "help", "reckless"])
	for c in combatants():
		c.turn = Stats.fresh_turn()
		c.reaction_used = false
		c.surprised = false
		if not c.concentration.is_empty() and not state.effects.any(func(e): return e.source_id == c.id and e.get("concentration", false)):
			c.concentration = {}
	add_log("turn", "Combat ends.")
	return ""


func begin_turn(depth: int) -> void:
	if depth > state.combat.order.size() * 2 + 2:
		return
	var c := get_c(current_id())
	state.turn_counter += 1
	if c.is_empty() or c.dead:
		if not c.is_empty():
			process_phase(c.id, "start")
			process_phase(c.id, "end")
		_advance(depth + 1)
		return
	c.turn = Stats.fresh_turn()
	if not c.surprised:
		c.reaction_used = false
	events.append({"kind": "turn", "id": c.id, "round": state.combat.round})
	add_log("turn", "%s's turn." % c.name, "", c.name)
	process_phase(c.id, "start")
	for a in c.attacks + c.powers:
		if a.has("recharge") and not a.get("charged", true):
			var r := Dice.die(rng, 6)
			if r >= a.recharge:
				a.charged = true
				add_log("info", "%s's %s recharges (rolled %d)." % [c.name, a.name, r])
	_aura_damage(c)
	if not c.dead and c.hp <= 0 and not c.stable:
		death_save(c)
	if c.dead or has_cond(c, "unconscious") or has_cond(c, "paralyzed") or has_cond(c, "stunned") or has_cond(c, "petrified") or c.surprised:
		var why := "surprised" if c.surprised else ("dead" if c.dead else ", ".join(conditions_of(c).filter(func(k): return k != "incapacitated" and k != "prone")))
		add_log("turn", "%s can't act this turn (%s)." % [c.name, why])
		end_turn(depth + 1)


func _aura_damage(c: Dictionary) -> void:
	for e in state.effects.duplicate():
		var aura: Dictionary = e.get("mods", {}).get("aura", {})
		if aura.is_empty() or not state.effects.has(e):
			continue
		var bearer := get_c(e.target_id)
		var src := get_c(e.source_id)
		if bearer.is_empty() or bearer.id == c.id or not hostile(src, c) or dist(bearer, c) > aura.radius:
			continue
		var s := roll_save(c, aura.ability, aura.dc, {"magical": true, "label": e.name})
		var parts := roll_damage(aura.damage, false)
		if s.success:
			if aura.half:
				for p in parts:
					p.amount = p.amount / 2
			else:
				parts = []
		if not parts.is_empty():
			deal_damage(c, parts, {"source_id": src.id, "label": e.name})


func end_turn(depth: int = 0) -> void:
	var c := get_c(current_id())
	if not c.is_empty() and not c.dead:
		process_phase(c.id, "end")
		var rage := find_effect(c, "rage")
		if not rage.is_empty() and not c.turn.attacked_hostile and not c.took_damage:
			remove_effect(rage, " (didn't attack or take damage)")
		c.took_damage = false
		if c.surprised:
			c.surprised = false
			c.reaction_used = false
		# Grapples break if the grappler is out of reach.
		for e in effects_on(c) + effects_from(c):
			if e.get("tag", "") == "grapple":
				var g := get_c(e.source_id)
				var t := get_c(e.target_id)
				if g.is_empty() or t.is_empty() or dist(g, t) > 5 or incapacitated(g):
					remove_effect(e, " (grapple broken)")
	_advance(depth)


func _advance(depth: int) -> void:
	if not in_combat() or state.combat.order.is_empty():
		return
	state.combat.turn_index += 1
	if state.combat.turn_index >= state.combat.order.size():
		state.combat.turn_index = 0
		state.combat.round += 1
		add_log("turn", "— Round %d —" % state.combat.round)
	begin_turn(depth)


# ---------------- Creatures ----------------

func free_spot(c: Dictionary, want: Vector2i) -> Vector2i:
	var map: Dictionary = state.map
	for r in range(0, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := want + Vector2i(dx, dy)
				var ok := true
				for f in Grid.footprint(c, p):
					if Grid.cell_at(map, f.x, f.y) == Grid.WALL:
						ok = false
						break
					for o in combatants():
						if o.id != c.id and not o.dead and Grid.footprint(o).has(f):
							ok = false
							break
				if ok:
					return p
	return want


## cmd: {kind: pregen|monster, template, level, pos, side, count, controller}
func spawn(cmd: Dictionary) -> String:
	var count := clampi(cmd.get("count", 1), 1, 20)
	var kind: String = cmd.get("kind", "monster")
	var template: String = cmd.get("template", "")
	var names := {}
	for c in combatants():
		names[c.name] = true
	for i in count:
		var id := next_id("c")
		var c: Dictionary
		if kind == "pregen":
			if not Pregens.ALL.has(template):
				return "Unknown character."
			c = Builder.build_character(Pregens.ALL[template], cmd.get("level", 3), id)
		else:
			if Monsters.get_monster(template).is_empty():
				return "Unknown monster."
			c = Builder.build_monster(template, id)
		if cmd.has("side"):
			c.side = cmd.side
		c.controller = cmd.get("controller", "")
		var base_name: String = c.name
		var n := 1
		while names.has(c.name):
			n += 1
			c.name = "%s %d" % [base_name, n]
		names[c.name] = true
		c.pos = free_spot(c, cmd.get("pos", Vector2i(1, 1)))
		state.combatants[id] = c
		_join_initiative(c)
		add_log("system", "%s joins the table (%s)." % [c.name, c.description])
	return ""


func create_character(def: Dictionary, user: Dictionary, pos) -> String:
	var errs := Creator.validate(def)
	if not errs.is_empty():
		return "Can't create this character: %s" % errs[0]
	if not user.get("is_dm", false) and (not def.get("items", []).is_empty() or not def.get("extra_spells", []).is_empty()):
		return "Magic items and extra spells come from the DM."
	var id := next_id("c")
	var c := Builder.build_character(def, int(def.level), id)
	c.controller = "" if user.get("is_dm", false) else user.get("name", "")
	var bg: String = def.get("background", "custom")
	if bg != "custom":
		c.notes["background"] = Creator.BACKGROUNDS[bg][0]
	var want: Vector2i = pos if pos is Vector2i else Vector2i(1, 1)
	if not pos is Vector2i:
		for o in combatants():
			if o.side == "party" and not o.dead:
				want = o.pos
				break
	c.pos = free_spot(c, want)
	state.combatants[id] = c
	_join_initiative(c)
	var how := ""
	match def.get("method", ""):
		"roll": how = " Rolled scores: %s." % ", ".join(def.rolled.map(func(v): return str(v)))
		"manual": how = " (ability scores entered manually)"
	add_log("system", "%s creates %s, a %s.%s" % [user.get("name", "?"), c.name, c.description.to_lower(), how])
	return ""


## Rebuilds a character from an edited definition (level up, respec), keeping its place in the game.
func update_character(id: String, def: Dictionary, user: Dictionary) -> String:
	var old := get_c(id)
	if old.is_empty():
		return "Unknown creature."
	var errs := Creator.validate(def)
	if not errs.is_empty():
		return "Can't save these changes: %s" % errs[0]
	if not user.get("is_dm", false):
		var od: Dictionary = old.get("def", {})
		if def.get("items", []) != od.get("items", []) or def.get("extra_spells", []) != od.get("extra_spells", []):
			return "Magic items and extra spells come from the DM."
	var lv_before: int = old.level
	_rebuild_character(id, def)
	var c := get_c(id)
	if c.level != lv_before:
		add_log("system", "%s is now level %d! (%d max HP)" % [c.name, c.level, c.max_hp])
	else:
		add_log("system", "%s's character was updated." % c.name)
	return ""


## Rebuilds a character from a definition, keeping its place in the game (no rules check).
func _rebuild_character(id: String, def: Dictionary) -> void:
	var old := get_c(id)
	var c := Builder.build_character(def, int(def.get("level", old.level)), id)
	for k in ["pos", "side", "controller", "notes", "hidden", "initiative", "surprised", "reaction_used", "turn", "concentration",
			"death_saves", "dead", "stable", "exhaustion", "temp_hp", "inspiration_die", "used_on_turn", "auto_reactions", "died_round", "took_damage"]:
		c[k] = old[k] if not (old[k] is Dictionary or old[k] is Array) else old[k].duplicate(true)
	c.fdata["init_tiebreak"] = old.fdata.get("init_tiebreak", 0.0)
	var damage: int = old.max_hp - old.hp
	c.hp = 0 if old.dead else clampi(c.max_hp - damage, 0, c.max_hp)
	for k in c.resources:
		if old.resources.has(k):
			c.resources[k].used = mini(old.resources[k].used, c.resources[k].max)
	if not c.spellcasting.is_empty() and not old.spellcasting.is_empty():
		for lv in range(1, 10):
			c.spellcasting.slots_used[lv] = mini(old.spellcasting.slots_used[lv], c.spellcasting.slots[lv])
		if not c.spellcasting.pact.is_empty() and not old.spellcasting.pact.is_empty():
			c.spellcasting.pact.used = mini(old.spellcasting.pact.used, c.spellcasting.pact.max)
	state.combatants[id] = c


# ---------------- Homebrew & items ----------------

func homebrew_save(kind: String, id: String, data: Dictionary) -> String:
	if not Homebrew.KINDS.has(kind):
		return "Unknown homebrew type."
	var hb := Homebrew.ensure(state)
	var clean := Homebrew.normalize(kind, data)
	var errs := Homebrew.validate(kind, clean)
	if not errs.is_empty():
		return errs[0]
	if id == "" or not hb[kind].has(id):
		id = Homebrew.new_id(kind, clean.name, hb[kind])
	hb[kind][id] = clean
	Homebrew.sync(state)
	add_log("system", "DM saved homebrew %s: %s." % [Homebrew.KIND_NAMES[kind].to_lower(), clean.name])
	return ""


func homebrew_delete(kind: String, id: String) -> String:
	var hb := Homebrew.ensure(state)
	if not hb.get(kind, {}).has(id):
		return "Nothing to delete."
	for c in combatants():
		if kind == "spells" and not c.spellcasting.is_empty() and c.spellcasting.known.has(id):
			return "%s knows this spell; remove it from them first." % c.name
		if kind == "items" and c.get("items", []).any(func(e): return e.get("id", "") == id):
			return "%s is carrying this item; take it back first." % c.name
	var name: String = hb[kind][id].get("name", id)
	hb[kind].erase(id)
	Homebrew.sync(state)
	add_log("system", "DM deleted homebrew %s." % name)
	return ""


func homebrew_import(pack: Dictionary) -> String:
	var hb := Homebrew.ensure(state)
	var added := 0
	var skipped := []
	# Spells first, so monsters that cast them validate.
	for kind in ["spells", "items", "monsters"]:
		for id in pack.get(kind, {}):
			var clean := Homebrew.normalize(kind, pack[kind][id])
			var errs := Homebrew.validate(kind, clean)
			if not errs.is_empty():
				skipped.append("%s (%s)" % [clean.get("name", id), errs[0]])
				continue
			hb[kind][str(id)] = clean
			Homebrew.sync(state)
			added += 1
	add_log("system", "DM imported %d homebrew entries%s." % [added, (", skipped: " + "; ".join(skipped)) if not skipped.is_empty() else ""])
	return "" if added > 0 or skipped.is_empty() else "Nothing in that pack was valid: %s" % skipped[0]


func give_item(id: String, entry: Dictionary) -> String:
	var c := get_c(id)
	if c.is_empty():
		return "Unknown creature."
	if c.kind != "pc" or not c.has("def"):
		return "Only player characters can carry magic items for now."
	var it := Items.get_item(entry.get("id", ""))
	if it.is_empty():
		return "Unknown item."
	var choices := Items.base_choices(it)
	if not choices.is_empty() and not choices.has(entry.get("base", "")):
		return "Choose what kind of %s it is." % ("weapon" if it.kind == "weapon" else ("armor" if it.kind == "armor" else "damage type"))
	if it.kind == "armor" and not Creator.armor_allowed(c.class_id, entry.base) and c.class_id != "":
		add_log("info", "Note: %s isn't proficient with %s." % [c.name, Equipment.ARMOR[entry.base].name])
	var def: Dictionary = c.def.duplicate(true)
	if not def.has("items"):
		def["items"] = []
	def.items.append({"id": entry.id, "base": entry.get("base", "")})
	_rebuild_character(id, def)
	add_log("system", "%s receives %s." % [c.name, Items.display_name(entry)])
	return ""


func take_item(id: String, index: int) -> String:
	var c := get_c(id)
	if c.is_empty() or not c.has("def") or index < 0 or index >= c.def.get("items", []).size():
		return "Nothing to take."
	var def: Dictionary = c.def.duplicate(true)
	var e: Dictionary = def.items[index]
	def.items.remove_at(index)
	_rebuild_character(id, def)
	add_log("system", "%s no longer has %s." % [c.name, Items.display_name(e)])
	return ""


func grant_spell(id: String, spell_id: String) -> String:
	var c := get_c(id)
	var sp := Spells.get_spell(spell_id)
	if c.is_empty() or sp.is_empty():
		return "Choose a creature and a spell."
	if c.spellcasting.is_empty():
		return "%s can't cast spells." % c.name
	if c.spellcasting.known.has(spell_id):
		return "%s already knows %s." % [c.name, sp.name]
	if c.kind == "pc" and c.has("def"):
		var def: Dictionary = c.def.duplicate(true)
		def["extra_spells"] = def.get("extra_spells", []) + [spell_id]
		_rebuild_character(id, def)
	else:
		c.spellcasting.known.append(spell_id)
	add_log("system", "%s learns %s." % [c.name, sp.name])
	return ""


## Drinking or administering a potion takes an action.
func use_item(c: Dictionary, index: int, target_id: String) -> String:
	var list: Array = c.get("items", [])
	if index < 0 or index >= list.size():
		return "No such item."
	var it := Items.get_item(list[index].get("id", ""))
	if it.get("kind", "") != "potion":
		return "%s isn't something you can use like that." % it.get("name", "That")
	var t := get_c(target_id) if target_id != "" else c
	if t.id != c.id and dist(c, t) > 5:
		return "You can only give a potion to someone within 5 ft."
	var err := economy_error(c, "action")
	if err != "":
		return err
	spend_economy(c, "action")
	var r := Dice.roll(rng, it.heal)
	add_log("heal", "%s %s %s." % [c.name, "drinks" if t.id == c.id else "gives %s" % t.name, it.name], r.text)
	heal(t, r.total, it.name)
	list.remove_at(index)
	if c.has("def") and c.def.has("items"):
		c.def.items.remove_at(index)
	c.equipment.erase(it.name)
	return ""


func remove_combatant(id: String) -> String:
	var c := get_c(id)
	if c.is_empty():
		return "Unknown creature."
	var was_current := current_id() == id
	end_concentration(c, "")
	remove_effects_where(func(e): return e.target_id == id or e.source_id == id)
	var order: Array = state.combat.order
	var idx := order.find(id)
	state.combatants.erase(id)
	if idx >= 0:
		order.remove_at(idx)
		if order.is_empty():
			state.combat = {"active": false, "round": 0, "turn_index": 0, "order": []}
		else:
			if idx < state.combat.turn_index:
				state.combat.turn_index -= 1
			if state.combat.turn_index >= order.size():
				state.combat.turn_index = 0
				state.combat.round += 1
			if was_current:
				begin_turn(0)
	add_log("system", "%s leaves the table." % c.name)
	return ""


# ---------------- Rests ----------------

func rest(kind: String, ids: Array) -> String:
	if in_combat():
		return "You can't rest during combat."
	var who := combatants().filter(func(c): return (ids.is_empty() and c.kind == "pc" or ids.has(c.id)) and not c.dead)
	for c in who:
		if kind == "short":
			for k in c.resources:
				if c.resources[k].reset == "short":
					c.resources[k].used = 0
			if not c.spellcasting.is_empty() and not c.spellcasting.pact.is_empty():
				c.spellcasting.pact.used = 0
			# Spend hit dice while it's worth it.
			var hd: int = c.fdata.get("hit_die", 8)
			var spent := 0
			while c.hp < c.max_hp and res_left(c, "hit_dice") > 0 and c.max_hp - c.hp >= hd / 2:
				spend_res(c, "hit_dice")
				var gained := maxi(1, Dice.die(rng, hd) + mod(c, "con"))
				c.hp = mini(c.max_hp, maxi(0, c.hp) + gained)
				spent += 1
			if spent > 0:
				add_log("heal", "%s spends %d hit dice and is at %d/%d HP." % [c.name, spent, c.hp, c.max_hp])
			if c.class_id == "wizard" and spend_res(c, "arcane_recovery"):
				var budget = (c.level + 1) / 2
				var sc: Dictionary = c.spellcasting
				for lv in range(5, 0, -1):
					while budget >= lv and sc.slots_used[lv] > 0:
						sc.slots_used[lv] -= 1
						budget -= lv
				add_log("spell", "%s uses Arcane Recovery." % c.name)
		else:
			remove_effects_where(func(e): return e.target_id == c.id)
			c.hp = c.max_hp
			c.temp_hp = 0
			for k in c.resources:
				if k == "hit_dice":
					c.resources[k].used = maxi(0, c.resources[k].used - maxi(1, c.level / 2))
				else:
					c.resources[k].used = 0
			if not c.spellcasting.is_empty():
				var sc: Dictionary = c.spellcasting
				sc.slots_used = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
				for lv in c.fdata.get("extra_slots", {}):
					sc.slots[lv] -= c.fdata.extra_slots[lv]
				c.fdata.erase("extra_slots")
				if not sc.pact.is_empty():
					sc.pact.used = 0
			c.exhaustion = maxi(0, c.exhaustion - 1)
			c.death_saves = {"successes": 0, "failures": 0}
			c.stable = false
			c.concentration = {}
			c.inspiration_die = ""
	add_log("system", "The party takes a %s rest." % kind)
	return ""


# ---------------- Monster AI ----------------

func run_auto_npcs() -> void:
	if not state.settings.get("auto_npc", false):
		return
	for i in 40:
		if not in_combat():
			return
		var c := get_c(current_id())
		if c.is_empty() or c.kind != "npc" or c.controller != "":
			return
		ai_turn(c)


## A straightforward brute: close in on the nearest conscious enemy and hit it with everything.
func ai_turn(c: Dictionary) -> void:
	if not is_turn_of(c):
		return
	var enemies := combatants().filter(func(o): return hostile(c, o) and not o.dead)
	var awake := enemies.filter(func(o): return o.hp > 0)
	if awake.is_empty() or incapacitated(c):
		end_turn()
		return
	awake.sort_custom(func(a, b): return dist(c, a) < dist(c, b))
	var target: Dictionary = awake[0]
	var melee := best_melee(c)
	var ranged := {}
	for a in c.attacks:
		if a.range == "ranged" and not a.get("standalone", false):
			ranged = a
			break
	if has_tag(c, "turned"):
		_ai_flee(c, target)
		end_turn()
		return
	# Breath weapons and other recharge powers.
	for pw in c.powers:
		if pw.get("charged", false) or (pw.has("resource") and res_left(c, pw.resource) > 0):
			var tr := spell_targets(c, pw.spell, 0, [], target.pos)
			if tr.error == "" and tr.targets.any(func(t): return hostile(c, t)) and not tr.targets.any(func(t): return not hostile(c, t)):
				if Grid.distance(state, c, target) <= pw.spell.target.get("size", 15):
					use_power(c, pw.id, [], target.pos)
					break
	# Move into reach (or as close as possible).
	var in_reach = not melee.is_empty() and dist(c, target) <= melee.reach
	var want_melee = not melee.is_empty() and (ranged.is_empty() or dist(c, target) <= movement_left(c) + melee.reach)
	if want_melee and not in_reach and speed_of(c) > 0:
		var reach := Grid.reachable(state, c, movement_left(c), move_rules(c))
		var best = null
		var best_score := 99999
		for cell in reach.cells:
			var d := Grid.distance(state, c, target, cell)
			var score: int = d * 100 + reach.cells[cell] if d > melee.reach else reach.cells[cell]
			if d <= melee.reach:
				score -= 50000
			if score < best_score:
				best_score = score
				best = cell
		if best != null and best != c.pos:
			move_to(c, best)
	if c.dead or c.hp <= 0 or not is_turn_of(c):
		return
	# Spider webs etc.
	for a in c.attacks:
		if a.get("standalone", false) and a.get("charged", false) and c.turn.actions > 0 and validate_attack(c, target, a) == "" and not has_cond(target, "restrained"):
			use_attack_slot(c, a)
			weapon_attack(c, target, a, {})
			break
	for i in 8:
		if c.dead or c.hp <= 0 or not is_turn_of(c):
			return
		awake = enemies.filter(func(o): return not o.dead and o.hp > 0)
		if awake.is_empty():
			break
		awake.sort_custom(func(a, b): return dist(c, a) < dist(c, b))
		target = awake[0]
		var p := {}
		var candidates := []
		if not c.turn.multiattack_left.is_empty():
			for id in c.turn.multiattack_left:
				candidates.append(find_attack(c, id))
		elif c.turn.actions > 0 or c.turn.attacks_left > 0:
			candidates = [melee, ranged]
			if not c.multiattack.is_empty():
				candidates = [find_attack(c, c.multiattack[0]), melee, ranged]
		for cand in candidates:
			if not cand.is_empty() and validate_attack(c, target, cand) == "":
				p = cand
				break
		if p.is_empty():
			break
		if use_attack_slot(c, p) != "":
			break
		weapon_attack(c, target, p, {})
	if is_turn_of(c):
		end_turn()


func _ai_flee(c: Dictionary, from: Dictionary) -> void:
	var reach := Grid.reachable(state, c, movement_left(c) * 2, move_rules(c))
	if c.turn.actions > 0:
		c.turn.actions -= 1
		c.turn.dashes += 1
	var best: Vector2i = c.pos
	for cell in reach.cells:
		if reach.cells[cell] <= movement_left(c) and Grid.distance(state, c, from, cell) > Grid.distance(state, c, from, best):
			best = cell
	if best != c.pos:
		move_to(c, best)


# ---------------- Views ----------------

## What a player is allowed to see: monster HP, AC and private rolls are hidden.
static func redact_for(state: Dictionary, user: Dictionary) -> Dictionary:
	if user.get("is_dm", false):
		return state
	var out: Dictionary = state.duplicate(true)
	var name: String = user.get("name", "")
	for c in out.combatants.values():
		if c.kind == "npc" and c.controller != name:
			c.hp_status = Stats.hp_status(c)
			c.redacted = true
			c.hp = 1 if c.hp > 0 else 0
			c.max_hp = 1
			c.temp_hp = 0
			c.ac = 0
			c.notes = {}
	out.log = out.log.filter(func(e): return e.get("private", "") == "" or e.private == name)
	if out.has("homebrew"):
		out.homebrew.monsters = {}
	return out
