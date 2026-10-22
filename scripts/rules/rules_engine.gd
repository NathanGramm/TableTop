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
	"giveItem", "takeItem", "grantSpell", "setHidden", "resetFog", "setBackground", "clearBackground", "placeProp", "removeProps", "levelUp"]
## Sheet edits: the DM, or the creature's player, any time.
const SHEET_COMMANDS := ["setNotes", "rename"]
const NOTE_KEYS := ["background", "alignment", "xp", "personality", "ideals", "bonds", "flaws", "proficiencies",
	"equipment", "cp", "sp", "ep", "gp", "pp", "inspiration", "age", "height", "weight", "eyes", "skin", "hair",
	"appearance", "backstory", "allies", "features", "treasure"]
## Carried light sources (PHB): radius of bright light, then this much further of dim light.
const LIGHT_SOURCES := {
	"torch": {"name": "Torch", "bright": 20, "dim": 20},
	"lantern": {"name": "Hooded lantern", "bright": 30, "dim": 30},
	"light": {"name": "Light cantrip", "bright": 20, "dim": 20},
}
const ACTOR_COMMANDS := ["move", "attack", "cast", "power", "action", "feature", "grapple", "shove", "endTurn", "setReactions", "useItem", "setLight", "ready", "door", "legendary"]


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
		"settings": {"diagonal": "5", "npcs_die_at_zero": true, "auto_npc": false, "flanking": false, "fog": false, "light": "bright"},
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
##
## Reaction prompts: when a player's creature could react (opportunity attack, Shield...), the run is
## thrown away and the state gets `pending` = {cmd, user, seed, decisions, prompt}. A `react` command
## replays the same command with the same dice seed plus the answer, so everything before the
## prompt happens exactly as before.
const MAX_BACKGROUND_BYTES := 8 * 1024 * 1024
const ALLOWED_WHILE_PENDING := ["react", "chat", "roll", "ping"]
## Log entries marked with this are only shown to the DM.
const DM_ONLY := "__dm__"


static func apply(state: Dictionary, cmd: Dictionary, user: Dictionary, p_rng: RandomNumberGenerator = null) -> Dictionary:
	var pending: Dictionary = state.get("pending", {})
	if cmd.get("type", "") == "react":
		return _react(state, cmd, user)
	if not pending.is_empty() and not ALLOWED_WHILE_PENDING.has(cmd.get("type", "")):
		return {"ok": false, "error": "Waiting for %s to decide on a reaction." % pending.prompt.name, "state": state, "events": []}
	var seed: int = p_rng.randi() if p_rng != null else randi()
	return _run(state, cmd, user, seed, [])


static func _run(state: Dictionary, cmd: Dictionary, user: Dictionary, seed: int, decisions: Array) -> Dictionary:
	var work: Dictionary = state.duplicate(true)
	Homebrew.ensure(work)
	Homebrew.sync(work)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var eng := RulesEngine.new(work, rng)
	eng.decisions = decisions
	var err := eng.permission_error(cmd, user)
	if err == "":
		err = eng.execute(cmd, user)
	if err != "" and eng.prompt.is_empty():
		Homebrew.sync(state)
		return {"ok": false, "error": err, "state": state, "events": []}
	if eng.prompt.is_empty():
		eng.run_auto_npcs()
	if not eng.prompt.is_empty():
		var held: Dictionary = state.duplicate(true)
		held["pending"] = {"cmd": cmd, "user": user, "seed": seed, "decisions": decisions, "prompt": eng.prompt}
		Homebrew.sync(held)
		return {"ok": true, "error": "", "state": held, "events": [], "pending": true}
	return {"ok": true, "error": "", "state": work, "events": eng.events}


static func _react(state: Dictionary, cmd: Dictionary, user: Dictionary) -> Dictionary:
	var p: Dictionary = state.get("pending", {})
	if p.is_empty():
		return {"ok": false, "error": "There's no reaction to decide.", "state": state, "events": []}
	if not user.get("is_dm", false) and user.get("name", "") != p.prompt.controller:
		return {"ok": false, "error": "That decision belongs to %s." % (p.prompt.controller if p.prompt.controller != "" else "the DM"), "state": state, "events": []}
	var base: Dictionary = state.duplicate(true)
	base.erase("pending")
	var choice := bool(cmd.get("choice", false))
	var r := _run(base, p.cmd, p.user, p.seed, p.decisions + [choice])
	if r.ok and cmd.get("timeout", false):
		RulesEngine.new(r.state).add_log("system", "No answer from %s in time, so %s %s." % [p.prompt.controller if p.prompt.controller != "" else "the DM",
			p.prompt.name, "reacts" if choice else "doesn't react"])
	return r


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
		if in_combat() and not t in ["setReactions", "setLight", "legendary"] and current_id() != a.id:
			return "It's not %s's turn." % a.name
		if a.dead and not t in ["setReactions", "setLight", "endTurn"]:
			return "%s is dead." % a.name
		if a.get("dm_hidden", false) and not t in ["move", "setReactions", "endTurn", "setLight"]:
			return "%s is hidden from the players; reveal it first." % a.name
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
		if not is_dm and int(cmd.get("def", {}).get("level", 1)) > maxi(target.level, target.get("pending_level", 0)):
			return "Your DM grants new levels."
		return ""
	if SHEET_COMMANDS.has(t):
		var target := get_c(cmd.get("id", ""))
		if target.is_empty():
			return "Unknown creature."
		return "" if is_dm or target.controller == user.get("name", "") else "You can only edit your own character sheet."
	if t in ["roll", "chat", "ping"]:
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
			if p.get("bonus_only", false) and not bonus:
				return "%s is a bonus-action attack." % p.name
			err = use_bonus_attack(a, p) if bonus else use_attack_slot(a, p)
			if err != "":
				return err
			weapon_attack(a, t, p, opts, bonus)
			sentinel_strike(a, t)
			return ""
		"cast":
			return cast(a, cmd.spell_id, cmd.get("slot", 0), cmd.get("targets", []), cmd.get("point", null), cmd.get("options", {}))
		"power":
			return use_power(a, cmd.power_id, cmd.get("targets", []), cmd.get("point", null))
		"legendary":
			return legendary_action(a, cmd.get("action_id", ""), cmd.get("targets", []), cmd.get("point", null))
		"action":
			return do_action(a, cmd.action, cmd.get("target_id", ""), cmd.get("via", "action"))
		"ready":
			return ready_attack(a, cmd.get("attack_id", ""))
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
			if cmd.has("mode"):
				if not cmd.mode in ["ask", "auto", "never"]:
					return "Unknown reaction setting."
				a["reaction_mode"] = cmd.mode
			else:
				a["reaction_mode"] = "auto" if cmd.get("auto", true) else "never"
			return ""
		"door":
			# shortcut: opening a door is free and not limited to one object interaction per turn; track it if players abuse it.
			var cell := Vector2i(cmd.x, cmd.y)
			if not Grid.in_bounds(state.map, cell.x, cell.y):
				return "That's off the map."
			var i: int = cell.y * state.map.width + cell.x
			var v: int = state.map.cells[i]
			if v != Grid.DOOR and v != Grid.DOOR_OPEN:
				return "There's no door there."
			if Grid.distance_to_cell(state, a, cell) > Grid.FT:
				return "%s must be next to the door." % a.name
			if v == Grid.DOOR_OPEN and state.combatants.values().any(func(o): return not o.dead and Grid.footprint(o).has(cell)):
				return "Something is standing in the doorway."
			if incapacitated(a):
				return "%s can't act." % a.name
			state.map.cells[i] = Grid.DOOR_OPEN if v == Grid.DOOR else Grid.DOOR
			add_log("system", "%s %s a door." % [a.name, "opens" if v == Grid.DOOR else "closes"])
			return ""
		"setLight":
			# Dousing is free at any time; lighting a torch or lantern (tinderbox) or casting Light takes an action.
			var src: String = cmd.get("source", "none")
			if src == "none":
				a["light"] = {}
				return ""
			if not LIGHT_SOURCES.has(src):
				return "Unknown light source."
			if in_combat() and current_id() != a.id:
				return "It's not %s's turn." % a.name
			var err := economy_error(a, "action")
			if err != "":
				return err
			spend_economy(a, "action")
			a["light"] = LIGHT_SOURCES[src].duplicate()
			a.light["id"] = src
			add_log("system", "%s casts Light." % a.name if src == "light" else "%s holds up a %s." % [a.name, a.light.name.to_lower()])
			if a.get("dm_hidden", false):
				state.log[-1]["private"] = DM_ONLY
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
			c.hp = mini(c.hp, hp_cap(c))
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
			c.hp = mini(c.hp, hp_cap(c))
			add_log("system", "%s exhaustion: %d." % [c.name, c.exhaustion])
			if c.exhaustion >= 6:
				kill(c, "exhaustion")
			return ""
		"setCells":
			for cell in cmd.cells:
				if not Grid.in_bounds(state.map, cell.x, cell.y):
					continue
				var i: int = cell.y * state.map.width + cell.x
				if cell.has("light"):
					_light_layer()[i] = clampi(cell.light, 0, Grid.BRIGHT + 1)
				else:
					state.map.cells[i] = cell.v
			return ""
		"clearMap":
			state.map.cells.fill(Grid.FLOOR)
			state.map.erase("light")
			state.map.erase("props")
			return ""
		"placeProp":
			# Scenery only: the DM paints walls, cover or difficult terrain under a prop for the rules.
			var m: String = str(cmd.get("m", ""))
			if m.length() > 80 or RegEx.create_from_string("^[a-z0-9-]+/[A-Za-z0-9_-]+$").search(m) == null:
				return "Unknown prop."
			if not Grid.in_bounds(state.map, cmd.x, cmd.y):
				return "That's off the map."
			if not state.map.has("props"):
				state.map["props"] = []
			state.map.props.append({"m": m, "x": int(cmd.x), "y": int(cmd.y), "r": posmod(int(cmd.get("r", 0)), 4), "h": clampi(int(cmd.get("h", 0)), 0, 8)})
			return ""
		"removeProps":
			var at := {}
			for cell in cmd.cells:
				at[Vector2i(cell.x, cell.y)] = true
			state.map["props"] = state.map.get("props", []).filter(func(p): return not at.has(Vector2i(p.x, p.y)))
			return ""
		"resizeMap":
			var w := clampi(cmd.width, 5, 80)
			var h := clampi(cmd.height, 5, 80)
			var cells := []
			cells.resize(w * h)
			cells.fill(Grid.FLOOR)
			var light := []
			light.resize(w * h)
			light.fill(0)
			var old_light: Array = state.map.get("light", [])
			for y in mini(h, state.map.height):
				for x in mini(w, state.map.width):
					cells[y * w + x] = state.map.cells[y * state.map.width + x]
					if not old_light.is_empty():
						light[y * w + x] = old_light[y * state.map.width + x]
			var props: Array = state.map.get("props", []).filter(func(p): return p.x < w and p.y < h)
			state.map = {"width": w, "height": h, "cells": cells, "light": light, "props": props}
			for c in combatants():
				c.pos = Vector2i(clampi(c.pos.x, 0, w - 1), clampi(c.pos.y, 0, h - 1))
			return ""
		"setController":
			var c := get_c(cmd.id)
			c.controller = cmd.get("controller", "")
			add_log("system", "%s is now controlled by %s." % [c.name, c.controller if c.controller else "the DM"])
			return ""
		"setSurprised":
			get_c(cmd.id).surprised = cmd.surprised and not get_c(cmd.id).features.has("alert")
			return ""
		"setSide":
			get_c(cmd.id).side = cmd.side
			return ""
		"createCharacter":
			return create_character(cmd.get("def", {}), user, cmd.get("pos", null))
		"updateCharacter":
			return update_character(cmd.id, cmd.get("def", {}), user, cmd.get("roll_hp", false))
		"levelUp":
			return level_up(cmd.get("ids", []))
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
		"setHidden":
			return set_hidden(cmd.id, cmd.get("hidden", true))
		"resetFog":
			state["fog_explored"] = {}
			return ""
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
				if k == "light" and not Grid.AMBIENT.has(cmd.settings[k]):
					return "Light must be bright, dim or dark."
				if k in ["diagonal", "npcs_die_at_zero", "auto_npc", "flanking", "fog", "light"]:
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
		"setBackground":
			var data: PackedByteArray = cmd.get("data", PackedByteArray())
			if data.size() > MAX_BACKGROUND_BYTES:
				return "That image is over 8 MB; export a smaller one."
			var img := image_from_bytes(data)
			if img == null:
				return "That isn't a PNG, JPG or WebP image."
			state["background"] = {"data": data, "hash": hash(data), "width": img.get_width(), "height": img.get_height()}
			var px: int = cmd.get("px_per_square", 0)
			if px > 0:
				execute({"type": "resizeMap", "width": ceili(img.get_width() / float(px)), "height": ceili(img.get_height() / float(px))}, user)
			add_log("system", "The DM puts down a battle map (%d×%d px, %d×%d squares)." % [img.get_width(), img.get_height(), state.map.width, state.map.height])
			return ""
		"clearBackground":
			state.erase("background")
			return ""
		"ping":
			var p: Vector2i = cmd.get("pos", Vector2i(-1, -1))
			if not Grid.in_bounds(state.map, p.x, p.y):
				return "Ping a square on the map."
			events.append({"kind": "ping", "pos": p, "who": user.get("name", "?")})
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
	var living := combatants().filter(func(c): return not c.dead and not c.get("dm_hidden", false))
	if living.is_empty():
		return "Add some creatures first."
	var lines := PackedStringArray()
	for c in living:
		var r := _init_roll(c)
		c.initiative = r.value + mod(c, "dex") + c.init_bonus
		c.fdata["init_tiebreak"] = rng.randf()
		lines.append("%s %d (%s %s)" % [c.name, c.initiative, r.text, Dice.fmt_mod(mod(c, "dex") + c.init_bonus)])
		c.turn = Stats.fresh_turn()
		c.reaction_used = c.surprised
		c.took_damage = false
		if c.features.has("superiorInspiration") and res_left(c, "inspiration") == 0:
			c.resources.inspiration.used -= 1
			add_log("info", "%s regains a Bardic Inspiration (Superior Inspiration)." % c.name)
		if c.features.has("perfectSelf") and res_left(c, "ki") == 0:
			c.resources.ki.used = maxi(0, c.resources.ki.used - 4)
			add_log("info", "%s regains 4 ki (Perfect Self)." % c.name)
	living.sort_custom(_init_order)
	state.combat = {"active": true, "round": 1, "turn_index": 0, "order": living.map(func(c): return c.id)}
	add_log("turn", "Roll for initiative! Combat begins.", "\n".join(lines))
	begin_turn(0)
	return ""


# Initiative is a Dexterity check, so poisoned and exhaustion impose disadvantage.
func _init_roll(c: Dictionary) -> Dictionary:
	var dis: bool = has_cond(c, "poisoned") or c.exhaustion >= 1
	return Dice.d20(rng, Dice.combine(c.features.has("feralInstinct"), dis), c.traits.has("lucky"))


func _init_order(a: Dictionary, b: Dictionary) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if a.abilities.dex != b.abilities.dex:
		return a.abilities.dex > b.abilities.dex
	return a.fdata.get("init_tiebreak", 0.0) > b.fdata.get("init_tiebreak", 0.0)


func _join_initiative(c: Dictionary) -> void:
	if not in_combat():
		return
	var r := _init_roll(c)
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
		c.erase("readied")
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
	c.erase("readied")  # an unused readied action is lost
	if has_mod(c, "haste_action"):
		c.turn.actions += 1  # shortcut: Haste's action is a full action, not just Attack (one attack)/Dash/Disengage/Hide/Use an Object
	events.append({"kind": "turn", "id": c.id, "round": state.combat.round})
	add_log("turn", "%s's turn." % c.name, "", c.name)
	process_phase(c.id, "start")
	if c.features.has("survivor") and c.hp > 0 and c.hp <= c.max_hp / 2:
		heal(c, 5 + mod(c, "con"), "Survivor")
	if c.resources.has("legendary"):
		c.resources.legendary.used = 0
	var regen: Dictionary = c.fdata.get("regen", {})
	if not regen.is_empty():
		if c.fdata.get("regen_blocked", false):
			add_log("info", "%s doesn't regenerate this turn." % c.name)
		elif c.hp > 0:
			heal(c, regen.amount, "Regeneration")
		c.fdata.erase("regen_blocked")
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
		if not rage.is_empty() and not c.turn.attacked_hostile and not c.took_damage and not c.features.has("persistentRage"):
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
	_ai_legendary(c)
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
		if cmd.get("hidden", false):
			c["dm_hidden"] = true
			add_log("system", "%s placed hidden (%s)." % [c.name, c.description])
			state.log[-1]["private"] = DM_ONLY
		else:
			_join_initiative(c)
			add_log("system", "%s joins the table (%s)." % [c.name, c.description])
	return ""


## Hide a creature from the players (it sits out of initiative) or reveal it.
## The DM's painted light layer (level + 1 per square, 0 = ambient), created on first use.
func _light_layer() -> Array:
	if state.map.get("light", []).size() != state.map.cells.size():
		var light := []
		light.resize(state.map.cells.size())
		light.fill(0)
		state.map["light"] = light
	return state.map.light


func set_hidden(id: String, hidden: bool) -> String:
	var c := get_c(id)
	if c.is_empty():
		return "Unknown creature."
	if c.get("dm_hidden", false) == hidden:
		return ""
	c["dm_hidden"] = hidden
	var order: Array = state.combat.order
	if hidden:
		if order.has(id):
			if current_id() == id:
				return "Finish %s's turn before hiding it." % c.name
			var cur := current_id()
			order.erase(id)
			state.combat.turn_index = maxi(0, order.find(cur))
		add_log("system", "%s is now hidden from the players." % c.name)
		state.log[-1]["private"] = DM_ONLY
	else:
		add_log("system", "%s appears!" % c.name)
		if not order.has(id):
			_join_initiative(c)
	return ""


func create_character(def: Dictionary, user: Dictionary, pos) -> String:
	if not user.get("is_dm", false):
		def = def.duplicate()
		def.erase("hp_rolls")  # rolled hit points only come from update_character's host-side rolls
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
func update_character(id: String, def: Dictionary, user: Dictionary, roll_hp: bool = false) -> String:
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
	# Hit point rolls are made here on the host; the client only asks for them.
	def = def.duplicate(true)
	var rolls := {}
	var old_rolls: Dictionary = old.get("def", {}).get("hp_rolls", {})
	for k in old_rolls:
		if int(k) <= int(def.level):
			rolls[str(k)] = old_rolls[k]
	if roll_hp:
		var hd: int = Classes.get_class_def(def["class"]).hit_die
		for lv in range(lv_before + 1, int(def.level) + 1):
			rolls[str(lv)] = Dice.die(rng, hd)
			add_log("roll", "%s rolls hit points for level %d: d%d = %d" % [old.name, lv, hd, rolls[str(lv)]])
	def["hp_rolls"] = rolls
	_rebuild_character(id, def)
	var c := get_c(id)
	if c.level >= c.get("pending_level", 0):
		c.erase("pending_level")
	if c.level != lv_before:
		add_log("system", "%s is now level %d! (%d max HP)" % [c.name, c.level, c.max_hp])
	else:
		add_log("system", "%s's character was updated." % c.name)
	return ""


## DM grants one more level to these player characters (all of them if `ids` is empty); each player
## then picks their new choices on the level-up screen.
func level_up(ids: Array) -> String:
	var who := combatants().filter(func(c): return c.kind == "pc" and (ids.is_empty() or ids.has(c.id)))
	if who.is_empty():
		return "No player characters to level up."
	for c in who:
		var to := mini(20, maxi(c.level, c.get("pending_level", 0)) + 1)
		if to <= c.level:
			continue
		# multiclass hook: once multiclassing lands, the level-up screen picks which class gains this level.
		c.pending_level = to
		add_log("system", "%s can level up to %d!" % [c.name, to])
	return ""


## Rebuilds a character from a definition, keeping its place in the game (no rules check).
func _rebuild_character(id: String, def: Dictionary) -> void:
	var old := get_c(id)
	_carry_over(old, Builder.build_character(def, int(def.get("level", old.level)), id))


## Rebuilds a monster from its stat block plus magic items, keeping its place in the game.
func _rebuild_monster(id: String, items: Array) -> void:
	var old := get_c(id)
	var c := Builder.build_monster(old.template_id, id)
	Builder.apply_monster_items(c, items)
	c.name = old.name
	c.color = old.color
	if not old.spellcasting.is_empty() and not c.spellcasting.is_empty():
		c.spellcasting.known = old.spellcasting.known.duplicate()  # keeps spells the DM taught it
	for a in c.attacks + c.powers:
		for o in old.attacks + old.powers:
			if o.id == a.id and o.has("charged"):
				a.charged = o.charged
	_carry_over(old, c)


func _carry_over(old: Dictionary, c: Dictionary) -> void:
	for k in ["pos", "side", "controller", "notes", "hidden", "initiative", "surprised", "reaction_used", "turn", "concentration",
			"death_saves", "dead", "stable", "exhaustion", "temp_hp", "inspiration_die", "used_on_turn", "auto_reactions", "reaction_mode", "died_round", "took_damage", "pending_level"]:
		if not old.has(k):
			continue
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
	state.combatants[c.id] = c


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
	var pc: bool = c.kind == "pc" and c.has("def")
	if not pc and Monsters.get_monster(c.template_id).is_empty():
		return "%s's stat block no longer exists, so it can't be re-equipped." % c.name
	var it := Items.get_item(entry.get("id", ""))
	if it.is_empty():
		return "Unknown item."
	var choices := Items.base_choices(it)
	if not choices.is_empty() and not choices.has(entry.get("base", "")):
		return "Choose what kind of %s it is." % ("weapon" if it.kind == "weapon" else ("armor" if it.kind == "armor" else "damage type"))
	if it.kind == "armor" and c.class_id != "" and not Creator.armor_allowed(c.class_id, entry.base):
		add_log("info", "Note: %s isn't proficient with %s." % [c.name, Equipment.ARMOR[entry.base].name])
	if it.get("attunement", false) and Items.attuned_count(c.get("items", [])) >= Items.MAX_ATTUNED:
		return "%s is already attuned to %d items; take one back first." % [c.name, Items.MAX_ATTUNED]
	var e := {"id": entry.id, "base": entry.get("base", "")}
	if not pc:
		_rebuild_monster(id, c.get("items", []) + [e])
		add_log("system", "%s receives %s." % [c.name, Items.display_name(entry)])
		return ""
	var def: Dictionary = c.def.duplicate(true)
	if not def.has("items"):
		def["items"] = []
	def.items.append(e)
	_rebuild_character(id, def)
	add_log("system", "%s receives %s." % [c.name, Items.display_name(entry)])
	return ""


func take_item(id: String, index: int) -> String:
	var c := get_c(id)
	if c.is_empty() or index < 0 or index >= c.get("items", []).size():
		return "Nothing to take."
	if not (c.kind == "pc" and c.has("def")):
		if Monsters.get_monster(c.template_id).is_empty():
			return "%s's stat block no longer exists, so it can't be re-equipped." % c.name
		var left: Array = c.items.duplicate(true)
		var gone: Dictionary = left.pop_at(index)
		_rebuild_monster(id, left)
		add_log("system", "%s no longer has %s." % [c.name, Items.display_name(gone)])
		return ""
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

## The best Song of Rest die among conscious resting bards, or "".
func _song_of_rest(who: Array) -> String:
	var best := ""
	for b in who:
		var d: String = b.fdata.get("song_of_rest", "")
		if d != "" and b.hp > 0 and (best == "" or int(d.substr(2)) > int(best.substr(2))):
			best = d
	return best


func rest(kind: String, ids: Array) -> String:
	if in_combat():
		return "You can't rest during combat."
	var who := combatants().filter(func(c): return (ids.is_empty() and c.kind == "pc" or ids.has(c.id)) and not c.dead)
	for c in who:
		end_wild_shape(c, " to rest")
		c.fdata.erase("relentless_uses")
		if kind == "short":
			for k in c.resources:
				if c.resources[k].reset == "short":
					c.resources[k].used = 0
			if not c.spellcasting.is_empty() and not c.spellcasting.pact.is_empty():
				c.spellcasting.pact.used = 0
			# Spend hit dice while it's worth it.
			var hd: int = c.fdata.get("hit_die", 8)
			var spent := 0
			while c.hp < hp_cap(c) and res_left(c, "hit_dice") > 0 and hp_cap(c) - c.hp >= hd / 2:
				spend_res(c, "hit_dice")
				var gained := maxi(1, Dice.die(rng, hd) + mod(c, "con"))
				c.hp = mini(hp_cap(c), maxi(0, c.hp) + gained)
				spent += 1
			var bard := _song_of_rest(who)
			if spent > 0 and bard != "":
				var song := Dice.roll(rng, bard)
				c.hp = mini(hp_cap(c), c.hp + song.total)
				add_log("heal", "Song of Rest: %s regains %d more." % [c.name, song.total], song.text)
			if spent > 0:
				add_log("heal", "%s spends %d hit dice and is at %d/%d HP." % [c.name, spent, c.hp, hp_cap(c)])
			if c.features.has("sorcerousRestoration"):
				c.resources.sorcery.used = maxi(0, c.resources.sorcery.used - 4)
			if (c.class_id == "wizard" and spend_res(c, "arcane_recovery")) or spend_res(c, "natural_recovery"):
				var budget = (c.level + 1) / 2
				var sc: Dictionary = c.spellcasting
				for lv in range(5, 0, -1):
					while budget >= lv and sc.slots_used[lv] > 0:
						sc.slots_used[lv] -= 1
						budget -= lv
				add_log("spell", "%s uses %s." % [c.name, "Arcane Recovery" if c.class_id == "wizard" else "Natural Recovery"])
		else:
			remove_effects_where(func(e): return e.target_id == c.id)
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
			c.hp = hp_cap(c)
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


## Legendary actions: spent between other creatures' turns, cost points that refill on its own turn.
## shortcut: allowed any time during another creature's turn, not only at its end.
func legendary_action(a: Dictionary, action_id: String, target_ids: Array, point) -> String:
	var la := {}
	for x in a.get("legendary", []):
		if x.id == action_id:
			la = x
	if la.is_empty():
		return "Unknown legendary action."
	if not in_combat():
		return "Legendary actions are only taken in combat."
	if current_id() == a.id:
		return "Legendary actions are taken at the end of other creatures' turns."
	if incapacitated(a) or a.surprised or a.hp <= 0:
		return "%s can't take legendary actions right now." % a.name
	var cost: int = la.get("cost", 1)
	if res_left(a, "legendary") < cost:
		return "%s costs %d legendary actions; %d left." % [la.name, cost, res_left(a, "legendary")]
	if la.has("attack"):
		var p := find_attack(a, la.attack)
		var t := get_c(target_ids[0] if not target_ids.is_empty() else "")
		var err := validate_attack(a, t, effective_profile(a, p))
		if err != "":
			return err
		spend_res(a, "legendary", cost)
		add_log("info", "%s takes a legendary action: %s." % [a.name, la.name], "", a.name)
		weapon_attack(a, t, p, {})
		return ""
	var tr := spell_targets(a, la.spell, 0, target_ids, point)
	if tr.error != "":
		return tr.error
	spend_res(a, "legendary", cost)
	add_log("spell", "%s takes a legendary action: %s." % [a.name, la.name], la.spell.get("desc", ""), a.name)
	resolve_spell(a, la.spell, 0, tr, {"dc": la.get("dc", 10), "attack_bonus": 0, "mod": 0, "level": 0, "spell_id": "", "auto_ids": [], "sculpt": false})
	return ""


## Auto NPCs with legendary actions take one (the first in stat-block order that works) as each other turn ends.
func _ai_legendary(ending: Dictionary) -> void:
	if not in_combat() or not state.settings.get("auto_npc", false):
		return
	for l in combatants():
		if l.get("legendary", []).is_empty() or l.id == ending.get("id", "") or l.kind != "npc" or l.controller != "" or l.dead or res_left(l, "legendary") <= 0:
			continue
		var foes := combatants().filter(func(o): return hostile(l, o) and not o.dead and o.hp > 0)
		if foes.is_empty():
			continue
		foes.sort_custom(func(x, y): return dist(l, x) < dist(l, y))
		for la in l.legendary:
			var sp: Dictionary = la.get("spell", {})
			var ids := [foes[0].id]
			if sp.has("heal") and l.hp > l.max_hp / 2:
				continue
			if sp.has("effect") and not sp.has("save"):  # a buff: on itself, once
				if effects_on(l).any(func(e): return e.name == sp.effect.name):
					continue
				ids = [l.id]
			if sp.get("target", {}).get("type", "") in ["self", "area"]:
				ids = []
				if sp.target.type == "area":
					var tr := spell_targets(l, sp, 0, [], null)
					if tr.targets.is_empty() or tr.targets.any(func(t): return not hostile(l, t)):
						continue
			if legendary_action(l, la.id, ids, null) == "":
				break


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

## Fog of war for a player: what the party can see right now, plus everything seen before.
## Updates the remembered map in `state` (host only). Returns {} when fog is off.
static func update_fog(state: Dictionary, user: Dictionary) -> Dictionary:
	if not state.settings.get("fog", false) or user.get("is_dm", false):
		return {}
	var name: String = user.get("name", "")
	# shortcut: the whole party shares vision (each member's own darkvision and line of sight).
	# shortcut: a blinded viewer adds nothing to fog vision, even with blindsight.
	var viewers = state.combatants.values().filter(func(c): return (c.side == "party" or c.controller == name) and not c.dead \
		and not c.get("dm_hidden", false) and not RulesEngine.new(state).has_cond(c, "blinded"))
	var visible := Grid.visible_cells(state, viewers)
	if not state.has("fog_explored"):
		state["fog_explored"] = {}
	var explored: PackedByteArray = state.fog_explored.get(name, PackedByteArray())
	if explored.size() != visible.size():
		explored = PackedByteArray()
		explored.resize(visible.size())
	for i in visible.size():
		if visible[i]:
			explored[i] = 1
	state.fog_explored[name] = explored
	return {"visible": visible, "explored": explored}


## Decodes a PNG, JPG or WebP by its signature (null if it's none of them).
static func image_from_bytes(data: PackedByteArray) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data.size() > 12 and data.slice(0, 4) == PackedByteArray([0x89, 0x50, 0x4E, 0x47]):
		err = img.load_png_from_buffer(data)
	elif data.size() > 12 and data[0] == 0xFF and data[1] == 0xD8:
		err = img.load_jpg_from_buffer(data)
	elif data.size() > 12 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	return img if err == OK and not img.is_empty() else null


## What a player is allowed to see: monster HP, AC and private rolls are hidden.
static func redact_for(state: Dictionary, user: Dictionary, fog: Dictionary = {}) -> Dictionary:
	if user.get("is_dm", false):
		return state
	var out: Dictionary = state.duplicate(true)
	var name: String = user.get("name", "")
	out.erase("fog_explored")
	if out.has("background"):
		out.background.erase("data")  # sent once, separately (Net._recv_background)
	for id in out.combatants.keys():
		var c: Dictionary = out.combatants[id]
		var own: bool = c.controller == name or c.side == "party"
		if c.get("dm_hidden", false) and c.controller != name:
			out.combatants.erase(id)
		elif not fog.is_empty() and not own and not Grid.footprint(c).any(func(f): return fog.visible[f.y * out.map.width + f.x] > Grid.DARK + 1):
			out.combatants.erase(id)  # in the fog
	if not fog.is_empty():
		out["fog"] = fog
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
	if out.has("effects"):
		out.effects = out.effects.filter(func(e): return out.combatants.has(e.target_id))
	if out.has("homebrew"):
		out.homebrew.monsters = {}
	if out.has("pending"):
		out.pending = {"prompt": out.pending.prompt}  # the replay seed stays on the host
	return out
