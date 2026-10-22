class_name EngineBase
extends RefCounted
## Shared state access and rules queries: modifiers, conditions, effects, saves and checks.
## The engine is split across a chain of classes to keep files manageable:
##   EngineBase -> EngineCombat -> EngineMagic -> RulesEngine

const INCAPACITATING := ["paralyzed", "stunned", "unconscious", "petrified"]

var state: Dictionary
var rng: RandomNumberGenerator
var events: Array = []
## Player answers to reaction prompts, consumed in order (see RulesEngine.apply).
var decisions: Array = []
var _decision_i := 0
## Set when a player must be asked; this run is then thrown away and replayed after they answer.
var prompt: Dictionary = {}


func _init(p_state: Dictionary, p_rng: RandomNumberGenerator = null) -> void:
	state = p_state
	rng = p_rng
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()


# ---------------- Basics ----------------

func get_c(id: String) -> Dictionary:
	return state.combatants.get(id, {})


func combatants() -> Array:
	return state.combatants.values()


func add_log(kind: String, text: String, detail: String = "", who: String = "") -> void:
	state.seq += 1
	state.log.append({"id": state.seq, "kind": kind, "text": text, "detail": detail, "who": who, "round": state.combat.round})
	if state.log.size() > 400:
		state.log = state.log.slice(state.log.size() - 400)


func next_id(prefix: String) -> String:
	state.seq += 1
	return "%s%d" % [prefix, state.seq]


func in_combat() -> bool:
	return state.combat.active


func current_id() -> String:
	if not in_combat() or state.combat.order.is_empty():
		return ""
	return state.combat.order[state.combat.turn_index]


func is_turn_of(c: Dictionary) -> bool:
	return current_id() == c.id


func mod(c: Dictionary, ability: String) -> int:
	return Stats.mod(c.abilities[ability])


## Levels in one class (a multiclass character's split; otherwise the whole level).
func class_lv(c: Dictionary, cls: String) -> int:
	return c.fdata.get("class_levels", {}).get(cls, c.level if c.class_id == cls else 0)


## Save DC, attack bonus and ability modifier for casting `sid` (multiclass spells use their own class's ability).
func spell_stats(c: Dictionary, sid: String) -> Dictionary:
	var sc: Dictionary = c.spellcasting
	var ab: String = sc.get("spell_ability", {}).get(sid, sc.ability)
	var shift := mod(c, ab) - mod(c, sc.ability)
	return {"dc": sc.dc + shift, "attack_bonus": sc.attack_bonus + shift, "mod": mod(c, ab)}


func hostile(a: Dictionary, b: Dictionary) -> bool:
	return Grid.hostile(a, b)


func dist(a: Dictionary, b: Dictionary) -> int:
	return Grid.distance(state, a, b)


func is_alive(c: Dictionary) -> bool:
	return not c.is_empty() and not c.dead


func is_dying(c: Dictionary) -> bool:
	return not c.dead and c.hp <= 0 and not c.stable


# ---------------- Effects & conditions ----------------

func effects_on(c: Dictionary) -> Array:
	return state.effects.filter(func(e): return e.target_id == c.id)


func effects_from(c: Dictionary) -> Array:
	return state.effects.filter(func(e): return e.source_id == c.id)


func find_effect(c: Dictionary, tag: String) -> Dictionary:
	for e in state.effects:
		if e.target_id == c.id and e.get("tag", "") == tag:
			return e
	return {}


func has_tag(c: Dictionary, tag: String) -> bool:
	return not find_effect(c, tag).is_empty()


func mods_of(c: Dictionary) -> Array:
	var out := []
	for e in state.effects:
		if e.target_id == c.id and e.has("mods"):
			out.append(e.mods)
	return out


func has_mod(c: Dictionary, key: String) -> bool:
	for m in mods_of(c):
		if m.has(key) and m[key]:
			return true
	return false


func has_cond(c: Dictionary, cond: String) -> bool:
	if c.is_empty():
		return false
	if cond == "incapacitated":
		for k in INCAPACITATING:
			if has_cond(c, k):
				return true
	if cond == "unconscious" and not c.dead and c.hp <= 0:
		return true
	if cond in ["charmed", "frightened"] and warded_from(c, cond):
		return false
	for e in state.effects:
		if e.target_id == c.id and e.get("conditions", []).has(cond):
			return true
	return false


## Mindless Rage, and a paladin's Aura of Devotion (charm) or Courage (fear), keep the condition off.
func warded_from(c: Dictionary, cond: String) -> bool:
	if c.features.has("mindlessRage") and has_tag(c, "rage"):
		return true
	return not _aura_from(c, "auraOfDevotion" if cond == "charmed" else "auraOfCourage").is_empty()


## A conscious, friendly paladin (possibly `c` itself) whose `feature` aura reaches `c`; the one with the best Charisma.
func _aura_from(c: Dictionary, feature: String) -> Dictionary:
	var best := {}
	for p in state.combatants.values():
		if p.features.has(feature) and not p.dead and p.hp > 0 and not hostile(p, c) and dist(p, c) <= p.fdata.get("aura_range", 10) \
				and (best.is_empty() or mod(p, "cha") > mod(best, "cha")):
			best = p
	return best


func conditions_of(c: Dictionary) -> Array:
	var out := []
	for cond in Stats.CONDITIONS:
		if has_cond(c, cond):
			out.append(cond)
	return out


func incapacitated(c: Dictionary) -> bool:
	return c.dead or has_cond(c, "incapacitated")


func can_react(c: Dictionary) -> bool:
	return is_alive(c) and not incapacitated(c) and not c.reaction_used and not c.surprised and not has_mod(c, "no_reactions") \
		and not c.get("dm_hidden", false)


## "ask" (prompt the player), "auto" (use it whenever it helps) or "never".
## Player-controlled creatures ask by default; the DM's creatures react automatically.
func reaction_mode(c: Dictionary) -> String:
	var m: String = c.get("reaction_mode", "")
	if m != "":
		return m
	if not c.auto_reactions:
		return "never"
	return "ask" if c.controller != "" else "auto"


## Should `reactor` spend its reaction? Only called where the reaction would help.
func decide(reactor: Dictionary, text: String, default_yes: bool = true) -> bool:
	match reaction_mode(reactor):
		"never": return false
		"auto": return default_yes
	if _decision_i < decisions.size():
		_decision_i += 1
		return bool(decisions[_decision_i - 1])
	if prompt.is_empty():
		prompt = {"reactor_id": reactor.id, "controller": reactor.controller, "name": reactor.name, "text": text, "default": default_yes}
	return false  # the rest of this run is discarded


## Can `observer` see `target`? (blindsight, blindness, invisibility, darkness, hiding, walls)
func can_see(observer: Dictionary, target: Dictionary) -> bool:
	if has_cond(observer, "unconscious"):
		return false
	# Blindsight perceives without sight: darkness, invisibility and being blinded don't matter, walls do.
	var bs: int = observer.get("blindsight", 0)
	if bs > 0 and dist(observer, target) <= bs and Grid.line_of_sight(state, observer, target):
		return true
	if has_cond(observer, "blinded"):
		return false
	if has_cond(target, "invisible"):
		return false
	var lv := Grid.DARK
	for p in Grid.footprint(target):
		lv = maxi(lv, Grid.seen_light(state, observer, p))
	if lv == Grid.DARK:
		return false  # heavily obscured
	# Dim light is lightly obscured: disadvantage (-5 passive) on Perception to spot a hidden creature.
	if target.hidden > 0 and hostile(observer, target) and observer.passive_perception - (5 if lv == Grid.DIM else 0) < target.hidden:
		return false
	return Grid.line_of_sight(state, observer, target) and Grid.sight_clear(state, observer, target)


func frightened_of(c: Dictionary) -> Array:
	var out := []
	if warded_from(c, "frightened"):
		return out
	for e in state.effects:
		if e.target_id == c.id and e.get("conditions", []).has("frightened"):
			var src := get_c(e.source_id)
			if is_alive(src):
				out.append(src)
	return out


## Creates an effect from a template. `expires_on.who` decides whose turn ends it.
func add_effect(tmpl: Dictionary, source_id: String, target_id: String) -> Dictionary:
	var e: Dictionary = tmpl.duplicate(true)
	e.erase("on")
	e["id"] = next_id("e")
	e["source_id"] = source_id
	e["target_id"] = target_id
	var conds: Array = e.get("conditions", [])
	var tgt := get_c(target_id)
	if not tgt.is_empty():
		conds = conds.filter(func(k): return not tgt.cond_immunities.has(k))
		e["conditions"] = conds
	if e.has("expires_on"):
		var ex: Dictionary = e.expires_on
		var who := source_id if ex.get("who", "source") == "source" else target_id
		var count: int = ex.get("count", 1)
		# "Until the end of your next turn" during your own turn means skipping the current end.
		if ex.phase == "end" and is_turn_of(get_c(who)):
			count += 1
		e["expires"] = {"combatant_id": who, "phase": ex.phase, "count": count}
		e.erase("expires_on")
	state.effects.append(e)
	if conds.has("prone") or conds.has("unconscious") or conds.has("paralyzed") or conds.has("stunned"):
		_on_incapacitated_check(tgt)
	return e


func remove_effect(e: Dictionary, reason: String = "") -> void:
	var idx := -1
	for i in state.effects.size():
		if state.effects[i].id == e.id:
			idx = i
			break
	if idx < 0:
		return
	state.effects.remove_at(idx)
	var tgt := get_c(e.target_id)
	match e.get("tag", ""):
		"grapple":
			remove_effects_where(func(x): return x.get("tag", "") == "pin" and x.source_id == e.source_id)
		"rage":
			if not tgt.is_empty():
				add_log("info", "%s's rage ends%s." % [tgt.name, reason])
				if tgt.fdata.get("frenzied", false):
					tgt.fdata.frenzied = false
					if tgt.exhaustion < 6:
						tgt.exhaustion += 1
						tgt.hp = mini(tgt.hp, hp_cap(tgt))
						add_log("info", "%s suffers a level of exhaustion from the frenzy (now %d)." % [tgt.name, tgt.exhaustion])
		"aid":
			if not tgt.is_empty():
				var amt: int = e.mods.get("max_hp_bonus", 0)
				tgt.max_hp -= amt
				tgt.hp = mini(tgt.hp, tgt.max_hp)
	if e.has("spell_id") and e.get("tag", "") == "" and not tgt.is_empty() and reason != "":
		add_log("info", "%s on %s ends%s." % [e.name, tgt.name, reason])


func remove_effects_where(pred: Callable, reason: String = "") -> void:
	for e in state.effects.duplicate():
		if pred.call(e):
			remove_effect(e, reason)


func end_concentration(c: Dictionary, reason: String = "") -> void:
	if c.is_empty() or c.concentration.is_empty():
		return
	var name: String = c.concentration.name
	c.concentration = {}
	remove_effects_where(func(e): return e.source_id == c.id and e.get("concentration", false))
	add_log("spell", "%s stops concentrating on %s%s." % [c.name, name, reason])


func _on_incapacitated_check(c: Dictionary) -> void:
	if c.is_empty():
		return
	if incapacitated(c):
		if not c.concentration.is_empty():
			end_concentration(c, " (incapacitated)")
		# A grappler that becomes incapacitated releases its grapple.
		remove_effects_where(func(e): return e.source_id == c.id and e.get("tag", "") == "grapple")


## Turn-phase bookkeeping: expire effects and make repeat saves.
func process_phase(cid: String, phase: String) -> void:
	for e in state.effects.duplicate():
		if not state.effects.has(e):
			continue
		if e.has("repeat_save") and e.target_id == cid and e.repeat_save.phase == phase:
			var tgt := get_c(cid)
			if is_alive(tgt):
				var r := roll_save(tgt, e.repeat_save.ability, e.repeat_save.dc, {"magical": e.has("spell_id"), "label": e.name})
				if r.success:
					remove_effect(e, " (save succeeded)")
					continue
		if e.has("expires") and e.expires.combatant_id == cid and e.expires.phase == phase:
			e.expires.count -= 1
			if e.expires.count <= 0:
				remove_effect(e, "")


# ---------------- Derived stats ----------------

func ac_of(c: Dictionary) -> int:
	var ac: int = c.ac
	if c.armor == "none" and has_mod(c, "mage_armor"):
		ac = maxi(ac, 13 + mod(c, "dex") + (2 if c.shield else 0))
	for m in mods_of(c):
		ac += m.get("ac_bonus", 0)
	return ac


## Exhaustion level 4 halves the hit point maximum.
func hp_cap(c: Dictionary) -> int:
	return maxi(1, c.max_hp / 2) if c.exhaustion >= 4 else c.max_hp


## Variant encumbrance level (Equipment.encumbrance) when the DM turns it on; player characters only.
func encumbrance(c: Dictionary) -> int:
	return Equipment.encumbrance(c) if state.settings.get("encumbrance", false) and c.kind == "pc" else 0


func speed_of(c: Dictionary) -> int:
	if c.dead or c.hp <= 0 or c.exhaustion >= 5:
		return 0
	for k in ["grappled", "restrained", "paralyzed", "stunned", "petrified", "unconscious"]:
		if has_cond(c, k):
			return 0
	if has_mod(c, "no_speed"):
		return 0
	var s: int = c.base_speed
	for m in mods_of(c):
		s += m.get("speed_bonus", 0)
	for m in mods_of(c):
		s *= m.get("speed_mult", 1)
		s /= m.get("speed_div", 1)
	match encumbrance(c):
		1: s -= 10
		2: s -= 20
		3: s = mini(s, 5)
		4: s = 0
	if c.exhaustion >= 2:
		s /= 2
	return maxi(0, s)


func movement_left(c: Dictionary) -> int:
	if not in_combat():
		return 9999 if speed_of(c) > 0 else 0
	return maxi(0, speed_of(c) * (1 + c.turn.dashes) - c.turn.movement_used)


func save_mod(c: Dictionary, ability: String) -> int:
	var v := mod(c, ability)
	if c.save_profs.has(ability):
		v += c.prof
	v += c.save_bonus.get(ability, 0)
	return v


func skill_mod(c: Dictionary, skill: String) -> int:
	var ability: String = Stats.SKILLS[skill]
	var v := mod(c, ability)
	var p: int = c.skills.get(skill, 0)
	if p > 0:
		v += c.prof * p
	elif c.joat:
		v += c.prof / 2
	elif c.features.has("remarkableAthlete") and ability in ["str", "dex", "con"]:
		v += (c.prof + 1) / 2
	v += c.skill_bonus.get(skill, 0)
	return v


func max_melee_reach(c: Dictionary) -> int:
	var r := 0
	for a in c.attacks:
		if a.range == "melee":
			r = maxi(r, a.reach)
	return r


# ---------------- Saves & checks ----------------

## Rolls a saving throw. ctx: magical, poison, frighten, charm, source_id, label, auto_success.
## Returns {success, total, natural, text}.
func roll_save(c: Dictionary, ability: String, dc: int, ctx: Dictionary = {}) -> Dictionary:
	var label: String = ctx.get("label", "")
	if ctx.get("auto_success", false):
		add_log("roll", "%s automatically succeeds on the %s save%s." % [c.name, ability.to_upper(), (" vs " + label) if label else ""])
		events.append({"kind": "save", "id": c.id, "success": true})
		return {"success": true, "total": dc, "natural": 0, "text": "auto"}
	if ability in ["str", "dex"] and (has_cond(c, "paralyzed") or has_cond(c, "stunned") or has_cond(c, "unconscious") or has_cond(c, "petrified")):
		add_log("roll", "%s automatically fails the %s save%s." % [c.name, ability.to_upper(), (" vs " + label) if label else ""])
		events.append({"kind": "save", "id": c.id, "success": false})
		return {"success": false, "total": 0, "natural": 0, "text": "auto-fail"}
	var adv := false
	var dis := false
	var notes := []
	if ability == "str" and has_tag(c, "rage"):
		adv = true; notes.append("rage")
	if ability == "dex":
		if has_mod(c, "dodge") and speed_of(c) > 0:
			adv = true; notes.append("dodging")
		if c.features.has("dangerSense") and not has_cond(c, "blinded") and not has_cond(c, "deafened") and not incapacitated(c):
			adv = true; notes.append("danger sense")
		if has_cond(c, "restrained"):
			dis = true; notes.append("restrained")
		if has_mod(c, "dex_save_adv"):
			adv = true; notes.append("haste")
	if c.exhaustion >= 3:
		dis = true; notes.append("exhaustion")
	if ability in ["str", "dex", "con"] and encumbrance(c) >= 2:
		dis = true; notes.append("heavily encumbered")
	if ctx.get("magical", false):
		if c.traits.has("gnomeCunning") and ability in ["int", "wis", "cha"]:
			adv = true; notes.append("gnome cunning")
		if c.traits.has("magicResistance"):
			adv = true; notes.append("magic resistance")
	if ctx.get("poison", false) and c.traits.has("dwarvenResilience"):
		adv = true; notes.append("dwarven resilience")
	if ctx.get("frighten", false) and c.traits.has("brave"):
		adv = true; notes.append("brave")
	if ctx.get("frighten", false) and c.options.has("steel_will"):
		adv = true; notes.append("steel will")
	if (ctx.get("frighten", false) or ctx.get("charm", false)) and combatants().any(func(b): return has_tag(b, "countercharm") and not hostile(b, c) and dist(b, c) <= 30):
		adv = true; notes.append("countercharm")
	if ctx.get("dis", false):
		dis = true; notes.append(ctx.get("dis_note", "disadvantage"))
	if ctx.get("concentration", false) and c.features.has("warCaster"):
		adv = true; notes.append("war caster")
	var src := get_c(ctx.get("source_id", ""))
	if ctx.get("magical", false) and c.features.has("mageSlayer") and not src.is_empty() and dist(c, src) <= 5:
		adv = true; notes.append("mage slayer")
	if ctx.get("charm", false) and c.traits.has("feyAncestry"):
		adv = true; notes.append("fey ancestry")
	var mode := Dice.combine(adv, dis)
	var r := Dice.d20(rng, mode, c.traits.has("lucky"))
	var bonus := save_mod(c, ability)
	var cover_bonus: int = ctx.get("bonus", 0)
	if ability == "dex" and ctx.get("single_target", false) and c.features.has("shieldMaster") and c.shield:
		cover_bonus += 2  # Shield Master
	var total: int = r.value + bonus + cover_bonus
	var text := "%s %s%s" % [r.text, Dice.fmt_mod(bonus), (" +%d(cover)" % cover_bonus) if cover_bonus > 0 else ""]
	for m in mods_of(c):
		if m.has("save_die"):
			var b := Dice.roll(rng, m.save_die)
			total += b.total; text += " +%s(bless)" % b.text
		if m.has("save_penalty_die"):
			var b := Dice.roll(rng, m.save_penalty_die)
			total -= b.total; text += " -%s(bane)" % b.text
	var aura := _aura_from(c, "auraOfProtection")
	if not aura.is_empty():
		var ab: int = maxi(1, mod(aura, "cha"))
		total += ab; text += " +%d(aura of protection)" % ab
	if total < dc and c.inspiration_die != "":
		var b := Dice.roll(rng, c.inspiration_die)
		total += b.total; text += " +%s(inspiration)" % b.text
		c.inspiration_die = ""
	if total < dc and total + 10 >= dc and c.features.has("darkOnesOwnLuck") and res_left(c, "dark_luck") > 0 \
			and decide(c, "%s fails a %s save%s by %d. Use Dark One's Own Luck to add a d10?" % [c.name, ability.to_upper(), (" vs " + label) if label else "", dc - total]):
		spend_res(c, "dark_luck")
		var b := Dice.roll(rng, "1d10")
		total += b.total; text += " +%s(dark one's own luck)" % b.text
	if total < dc and c.features.has("indomitable") and res_left(c, "indomitable") > 0 \
			and decide(c, "%s fails a %s save%s (%d vs DC %d). Use Indomitable to reroll it?" % [c.name, ability.to_upper(), (" vs " + label) if label else "", total, dc]):
		spend_res(c, "indomitable")
		var r2 := Dice.d20(rng, mode, c.traits.has("lucky"))
		total += r2.value - r.value
		text += " → Indomitable reroll %s" % r2.text
		r = r2
	if total < dc and c.features.has("lucky") and res_left(c, "luck") > 0 \
			and decide(c, "%s fails a %s save%s (%d vs DC %d). Spend a luck point to roll again?" % [c.name, ability.to_upper(), (" vs " + label) if label else "", total, dc]):
		spend_res(c, "luck")
		var r2 := Dice.d20(rng, Dice.NORMAL, c.traits.has("lucky"))
		text += " → luck %s" % r2.text
		if r2.value > r.value:
			total += r2.value - r.value
			r = r2
	var success := total >= dc
	if not success and res_left(c, "legendary_resistance") > 0 \
			and decide(c, "%s fails a %s save%s (%d vs DC %d). Use Legendary Resistance to succeed instead (%d left)?" % [c.name, ability.to_upper(), (" vs " + label) if label else "", total, dc, res_left(c, "legendary_resistance")]):
		spend_res(c, "legendary_resistance")
		success = true
		text += " → Legendary Resistance (%d left)" % res_left(c, "legendary_resistance")
	add_log("roll", "%s %s save%s: %d vs DC %d — %s" % [c.name, ability.to_upper(), (" vs " + label) if label else "", total, dc, "success" if success else "fail"],
		"%s%s" % [text, (" (" + ", ".join(notes) + ")") if notes.size() else ""], c.name)
	events.append({"kind": "save", "id": c.id, "success": success})
	return {"success": success, "total": total, "natural": r.value, "text": text}


## Ability check, optionally with a skill. Returns {total, natural, text}.
func roll_check(c: Dictionary, ability: String, skill: String = "", ctx: Dictionary = {}) -> Dictionary:
	var adv := false
	var dis := false
	if ability == "str" and has_tag(c, "rage"):
		adv = true
	if has_cond(c, "poisoned") or c.exhaustion >= 1:
		dis = true
	if skill == "stealth" and c.stealth_dis:
		dis = true
	if ability in ["str", "dex", "con"] and encumbrance(c) >= 2:
		dis = true
	if ctx.get("adv", false):
		adv = true
	var r := Dice.d20(rng, Dice.combine(adv, dis), c.traits.has("lucky"))
	var bonus = skill_mod(c, skill) if skill != "" else mod(c, ability) + ((c.prof / 2) if c.joat else 0) \
		+ (((c.prof + 1) / 2) if c.features.has("remarkableAthlete") and ability in ["str", "dex", "con"] and not c.joat else 0)
	var total: int = r.value + bonus
	var label = Stats.skill_label(skill) if skill != "" else Stats.ABILITY_NAMES[ability]
	if not ctx.get("quiet", false):
		add_log("roll", "%s %s check: %d" % [c.name, label, total], "%s %s" % [r.text, Dice.fmt_mod(bonus)], c.name)
	return {"total": total, "natural": r.value, "text": "%s %s" % [r.text, Dice.fmt_mod(bonus)]}


## Removes a used-up item (a drunk potion, a consumed component) without rebuilding the creature.
func remove_item(c: Dictionary, index: int) -> void:
	var name := Items.display_name(c.items[index])
	c.items.remove_at(index)
	if c.has("def") and c.def.has("items"):
		c.def.items.remove_at(index)
	c.equipment.erase(name)


# ---------------- Resources ----------------

func res_left(c: Dictionary, key: String) -> int:
	var r: Dictionary = c.resources.get(key, {})
	if r.is_empty():
		return 0
	return r.max - r.used


func spend_res(c: Dictionary, key: String, n: int = 1) -> bool:
	if res_left(c, key) < n:
		return false
	c.resources[key].used += n
	return true


func slots_left(c: Dictionary, level: int) -> int:
	var sc: Dictionary = c.spellcasting
	if sc.is_empty():
		return 0
	var n: int = sc.slots[level] - sc.slots_used[level] if level <= 9 else 0
	if not sc.pact.is_empty() and sc.pact.level == level:
		n += sc.pact.max - sc.pact.used
	return n


func spend_slot(c: Dictionary, level: int) -> bool:
	var sc: Dictionary = c.spellcasting
	if sc.is_empty():
		return false
	if not sc.pact.is_empty() and sc.pact.level == level and sc.pact.used < sc.pact.max:
		sc.pact.used += 1
		return true
	if sc.slots[level] - sc.slots_used[level] > 0:
		sc.slots_used[level] += 1
		return true
	return false


func lowest_slot(c: Dictionary, min_level: int) -> int:
	for lv in range(maxi(1, min_level), 10):
		if slots_left(c, lv) > 0:
			return lv
	return 0
