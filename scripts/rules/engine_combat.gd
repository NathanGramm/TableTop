class_name EngineCombat
extends EngineBase
## Attacks, damage, healing, dying, movement (with opportunity attacks), grapple/shove and the
## standard actions (Dash, Disengage, Dodge, Help, Hide, ...).


# ---------------- Action economy ----------------

func economy_error(c: Dictionary, kind: String) -> String:
	if not in_combat():
		return ""
	if incapacitated(c):
		return "%s is incapacitated." % c.name
	match kind:
		"action":
			if c.turn.actions <= 0:
				return "No action left this turn."
		"bonus":
			if not c.turn.bonus:
				return "Bonus action already used this turn."
		"reaction":
			if not can_react(c):
				return "No reaction available."
	return ""


func spend_economy(c: Dictionary, kind: String) -> void:
	if not in_combat():
		return
	match kind:
		"action": c.turn.actions -= 1
		"bonus": c.turn.bonus = false
		"reaction": c.reaction_used = true


## Spends Haste's limited extra action once the normal action is gone.
func _use_haste_action(c: Dictionary) -> bool:
	if c.turn.actions > 0 or not c.turn.get("haste_action", false):
		return false
	c.turn.haste_action = false
	return true


func find_attack(c: Dictionary, attack_id: String) -> Dictionary:
	for a in c.attacks:
		if a.id == attack_id:
			return a
	return {}


## The profile actually used, after Shillelagh and similar effects.
func effective_profile(c: Dictionary, p: Dictionary) -> Dictionary:
	if p.has("shillelagh") and has_mod(c, "shillelagh"):
		var q: Dictionary = p.duplicate(true)
		q.to_hit = p.shillelagh.to_hit
		q.damage = [{"dice": p.shillelagh.dice, "bonus": p.shillelagh.bonus, "type": "bludgeoning"}]
		q.dmg_mod = p.shillelagh.dmg_mod
		q.name = p.name + " (Shillelagh)"
		return q
	return p


func validate_attack(a: Dictionary, t: Dictionary, p: Dictionary) -> String:
	if t.is_empty() or t.dead:
		return "Choose a living target."
	if t.id == a.id:
		return "You can't attack yourself."
	if incapacitated(a):
		return "%s is incapacitated." % a.name
	if charmed_by(a, t):
		return "%s is charmed by %s and can't attack it." % [a.name, t.name]
	if p.has("recharge") and not p.get("charged", true):
		return "%s hasn't recharged." % p.name
	var d := dist(a, t)
	if p.range == "melee":
		if d > p.reach:
			return "%s is out of reach (%d ft away, reach %d ft)." % [t.name, d, p.reach]
	else:
		var max_range: int = p.long if p.long > 0 else p.normal
		if d > max_range:
			return "%s is out of range (%d ft away, max %d ft)." % [t.name, d, max_range]
		# shortcut: underwater a shot past normal range automatically misses; refused here rather than spending the attack.
		if in_water(a) and d > p.normal:
			return "Underwater, a ranged weapon attack beyond its normal range (%d ft) automatically misses." % p.normal
	if Grid.cover(state, a, t) == -1:
		return "No line of effect to %s (total cover)." % t.name
	if p.props.has("loading") and a.turn.attack_action_weapons.has(p.id) and not a.features.has("crossbowExpert"):
		return "%s has the loading property: one shot per action." % p.name
	var wid: String = p.get("weapon_id", "")
	if wid != "" and hands_on(a):
		if not holds(a, wid):
			return "%s isn't holding a %s." % [a.name, Equipment.WEAPONS.get(wid, {}).get("name", wid).to_lower()]
		if p.props.has("twoHanded") and a.hands.count(wid) < 2:
			return "%s needs both hands." % p.name
	var ammo := ammo_kind(a, p)
	if ammo != "" and Equipment.ammo_left(a, ammo) <= 0:
		return "%s is out of %s." % [a.name, Equipment.AMMO[ammo].name.to_lower()]
	return ""


## The ammunition a weapon attack uses when the DM tracks ammunition (player characters only), or "".
func ammo_kind(a: Dictionary, p: Dictionary) -> String:
	if not state.settings.get("ammunition", false) or a.kind != "pc":
		return ""
	return Equipment.AMMO_OF.get(p.get("weapon_id", ""), "")


## Spends one attack from the Attack action (or starts it). Monsters use their multiattack list.
func use_attack_slot(c: Dictionary, p: Dictionary) -> String:
	if not in_combat():
		return "Start combat before attacking."
	if not p.is_empty() and p.get("standalone", false):
		if c.turn.actions <= 0:
			return "No action left this turn."
		c.turn.actions -= 1
		c.turn.attacks_left = 0
		c.turn.multiattack_left = []
		return ""
	if not c.multiattack.is_empty() and not p.is_empty():
		if c.turn.multiattack_left.has(p.id):
			c.turn.multiattack_left.erase(p.id)
			return ""
		if _use_haste_action(c):  # one attack only
			c.turn.attack_action_taken = true
			c.turn.multiattack_left = []
			return ""
		if c.turn.actions <= 0:
			return "No action left this turn." if c.turn.multiattack_left.is_empty() else "Multiattack remaining: %s." % ", ".join(c.turn.multiattack_left)
		c.turn.actions -= 1
		c.turn.attack_action_taken = true
		var left: Array = c.multiattack.duplicate()
		if left.has(p.id):
			left.erase(p.id)
		else:
			left = []
		c.turn.multiattack_left = left
		return ""
	if c.turn.attacks_left > 0:
		c.turn.attacks_left -= 1
		return ""
	if _use_haste_action(c):  # one attack only
		c.turn.attack_action_taken = true
		return ""
	if c.turn.actions <= 0:
		return "No action left this turn."
	c.turn.actions -= 1
	c.turn.attack_action_taken = true
	c.turn.attacks_left = c.attacks_per_action - 1
	return ""


## Bonus-action attacks: Two-Weapon Fighting, Martial Arts, Flurry of Blows, Frenzy.
func use_bonus_attack(c: Dictionary, p: Dictionary) -> String:
	if not in_combat():
		return "Start combat before attacking."
	var ba: Dictionary = c.turn.bonus_attack
	var unarmed: bool = p.props.has("unarmed")
	var light_melee: bool = p.range == "melee" and p.get("weapon", false) and _twf_weapon(c, p)
	if not ba.is_empty() and ba.left > 0:
		var ok := false
		match ba.kind:
			"flurry", "martialArts": ok = unarmed
			"offhand": ok = light_melee
			"frenzy": ok = p.range == "melee"
		if ok:
			ba.left -= 1
			return ""
	if not c.turn.bonus:
		return "Bonus action already used this turn."
	var feat_kind := _feat_bonus_attack(c, p)
	if feat_kind != "":
		c.turn.bonus = false
		c.fdata.erase("gwm_turn")
		c.turn.bonus_attack = {"kind": feat_kind, "left": 0}
		return ""
	if p.get("bonus_only", false):
		return "Polearm Master's butt-end attack follows an Attack action with a glaive, halberd, quarterstaff or spear."
	var used_light := false
	var used_monk := false
	for wid in c.turn.attack_action_weapons:
		var w := find_attack(c, wid)
		if not w.is_empty() and w.range == "melee" and _twf_weapon(c, w):
			used_light = true
		if not w.is_empty() and (w.props.has("monk") or w.props.has("unarmed")):
			used_monk = true
	if light_melee and used_light and c.fdata.get("light_melee_count", 0) >= 2:
		c.turn.bonus = false
		c.turn.bonus_attack = {"kind": "offhand", "left": 0}
		return ""
	if c.features.has("martialArts") and unarmed and used_monk:
		c.turn.bonus = false
		c.turn.bonus_attack = {"kind": "martialArts", "left": 0}
		return ""
	if c.fdata.get("frenzied", false) and c.fdata.get("frenzy_turn", -1) != state.turn_counter and p.range == "melee":
		c.turn.bonus = false
		c.turn.bonus_attack = {"kind": "frenzy", "left": 0}
		return ""
	if light_melee and not used_light:
		return "Two-Weapon Fighting needs an Attack action with a light melee weapon first."
	return "No bonus-action attack available (Two-Weapon Fighting, Martial Arts, Flurry of Blows or Frenzy)."


## Light weapons, or any one-handed melee weapon with Dual Wielder.
func _twf_weapon(c: Dictionary, w: Dictionary) -> bool:
	return w.props.has("light") or (c.features.has("dualWielder") and not w.props.has("twoHanded") and w.get("weapon_id", "") != "unarmed")


## Bonus-action attacks granted by feats: "gwm", "polearm", "charger", "crossbow" or "".
func _feat_bonus_attack(c: Dictionary, p: Dictionary) -> String:
	var melee_weapon: bool = p.range == "melee" and p.get("weapon", false)
	if c.fdata.get("gwm_turn", -1) == state.turn_counter and melee_weapon:
		return "gwm"
	if p.get("bonus_only", false):
		for wid in c.turn.attack_action_weapons:
			if find_attack(c, wid).get("weapon_id", "") in Builder.POLEARMS:
				return "polearm"
		return ""
	if c.features.has("charger") and c.turn.get("dashed_action", false) and melee_weapon:
		return "charger"
	if c.features.has("crossbowExpert") and p.get("weapon_id", "") == "hand_crossbow":
		for wid in c.turn.attack_action_weapons:
			var w := find_attack(c, wid)
			if not w.is_empty() and w.get("weapon", false) and not w.props.has("twoHanded"):
				return "crossbow"
	return ""


# ---------------- Attack rolls ----------------

## Works out advantage/disadvantage. ctx: reckless, profile.
## Underwater combat (PHB): melee weapons that work without a swim speed, and ranged weapons without disadvantage.
const UNDERWATER_MELEE := ["dagger", "javelin", "shortsword", "spear", "trident"]
const UNDERWATER_RANGED := ["light_crossbow", "hand_crossbow", "heavy_crossbow", "net", "javelin", "spear", "trident", "dart"]


func attack_mode(a: Dictionary, t: Dictionary, kind: String, ctx: Dictionary = {}) -> Dictionary:
	var adv := []
	var dis := []
	var d := dist(a, t)
	if not can_see(a, t):
		dis.append("can't see target")
	if not can_see(t, a) and not t.features.has("alert"):
		adv.append("unseen attacker")
	if ctx.get("opportunity", false) and t.options.has("escape_the_horde"):
		dis.append("escape the horde")
	if has_cond(a, "poisoned"): dis.append("poisoned")
	if has_cond(a, "prone"): dis.append("prone")
	if has_cond(a, "restrained"): dis.append("restrained")
	if fear_in_sight(a): dis.append("frightened")
	if a.exhaustion >= 3: dis.append("exhaustion")
	if ctx.get("profile", {}).get("ability", "") in ["str", "dex", "con"] and encumbrance(a) >= 2: dis.append("heavily encumbered")
	for m in mods_of(a):
		if m.get("disadvantage_on_attacks", false): dis.append("mocked")
		if m.get("advantage_on_attacks", false): adv.append("effect")
	for k in ["paralyzed", "stunned", "unconscious", "petrified", "restrained"]:
		if has_cond(t, k):
			adv.append("target " + k)
			break
	if has_cond(t, "prone"):
		if d <= 5: adv.append("target prone")
		else: dis.append("target prone")
	if has_mod(t, "dodge") and can_see(t, a) and not incapacitated(t) and speed_of(t) > 0:
		dis.append("target dodging")
	for e in effects_on(t):
		var m: Dictionary = e.get("mods", {})
		if m.get("advantage_against", false):
			adv.append(e.name.to_lower())
		if m.get("disadvantage_against", false):
			dis.append(e.name.to_lower())
		if e.get("tag", "") == "help" and m.get("help_side", "") == a.side:
			adv.append("help")
	if ctx.get("reckless", false):
		adv.append("reckless")
	if has_tag(a, "inspired"):
		adv.append("inspiration")
	var steed := get_c(a.get("mounted_on", ""))
	if kind == "melee" and a.features.has("mountedCombatant") and not steed.is_empty() and t.get("mounted_on", "") == "" \
			and Grid.size_index(t.csize) < Grid.size_index(steed.csize):
		adv.append("mounted combatant")
	if a.features.has("grappler") and effects_on(t).any(func(e): return e.get("tag", "") == "grapple" and e.source_id == a.id):
		adv.append("grappler")
	if a.traits.has("packTactics"):
		for o in combatants():
			if o.id != a.id and o.side == a.side and is_alive(o) and o.hp > 0 and not incapacitated(o) and dist(o, t) <= 5:
				adv.append("pack tactics")
				break
	if state.settings.get("flanking", false) and kind == "melee" and d <= 5:
		var ac := Grid.center(a)
		var tc := Grid.center(t)
		for o in combatants():
			if o.id != a.id and o.side == a.side and is_alive(o) and not incapacitated(o) and dist(o, t) <= 5:
				if (Grid.center(o) - tc).normalized().dot((ac - tc).normalized()) < -0.9:
					adv.append("flanking")
					break
	var p: Dictionary = ctx.get("profile", {})
	if p.get("props", []).has("heavy") and a.csize in ["small", "tiny"]:
		dis.append("heavy weapon")
	if not p.is_empty() and in_water(a):
		var wid: String = p.get("weapon_id", "")
		if kind == "melee" and a.get("speeds", {}).get("swim", 0) == 0 and not wid in UNDERWATER_MELEE:
			dis.append("underwater")
		elif kind == "ranged" and not wid in UNDERWATER_RANGED:
			dis.append("underwater")
	if kind == "ranged":
		var normal: int = p.get("normal", 0)
		if normal > 0 and d > normal and not a.features.has("sharpshooter"):
			dis.append("long range")
		for o in [] if a.features.has("crossbowExpert") else combatants():
			if o.id != a.id and hostile(o, a) and is_alive(o) and o.hp > 0 and not incapacitated(o) and dist(o, a) <= 5 and can_see(o, a):
				dis.append("enemy adjacent")
				break
	if t.features.has("elusive") and not incapacitated(t):
		adv.clear()  # Elusive: no attack roll has advantage against you
	return {"mode": Dice.combine(not adv.is_empty(), not dis.is_empty()), "adv": adv, "dis": dis}


## One attack roll against a target, including defensive reactions.
## ctx: profile, weapon, spell, crit_range, reckless, label.
## Returns {hit, crit, natural, total, ac, mode}.
func attack_roll(a: Dictionary, t: Dictionary, kind: String, to_hit: int, ctx: Dictionary = {}) -> Dictionary:
	var m := attack_mode(a, t, kind, ctx)
	var mode: int = m.mode
	if ctx.get("spell_adv", false) and mode != Dice.ADVANTAGE:
		mode = Dice.ADVANTAGE if mode == Dice.NORMAL else Dice.NORMAL
		m.adv.append("metal armor")
	if mode != Dice.DISADVANTAGE:
		# Protection fighting style: an ally with a shield within 5 ft of the target imposes disadvantage.
		for pr in combatants():
			if pr.id != t.id and pr.options.has("protection") and pr.get("shield", false) and not hostile(pr, t) and hostile(pr, a) \
					and can_react(pr) and dist(pr, t) <= 5 and can_see(pr, a) \
					and decide(pr, "%s attacks %s. Use Protection to impose disadvantage?" % [a.name, t.name]):
				pr.reaction_used = true
				m.dis.append("protection")
				mode = Dice.combine(not m.adv.is_empty(), true)
				add_log("info", "%s raises a shield to protect %s." % [pr.name, t.name])
				break
	var r := Dice.d20(rng, mode, a.traits.has("lucky"))
	var total: int = r.value + to_hit
	var text := "%s %s" % [r.text, Dice.fmt_mod(to_hit)]
	for mm in mods_of(a):
		if mm.has("attack_die"):
			var b := Dice.roll(rng, mm.attack_die)
			total += b.total; text += " +%s(bless)" % b.text
		if mm.has("attack_penalty_die"):
			var b := Dice.roll(rng, mm.attack_penalty_die)
			total -= b.total; text += " -%s(bane)" % b.text
		if ctx.get("weapon", false) and mm.has("attack_bonus"):
			total += mm.attack_bonus; text += " +%d(sacred weapon)" % mm.attack_bonus
	var cover := 0 if ctx.get("ignore_cover", false) else Grid.cover(state, a, t)
	var mad_key := "%s@%d" % [a.id, state.turn_counter]
	var ac := ac_of(t) + maxi(0, cover) + (4 if t.fdata.get("multiattack_defense", "") == mad_key else 0)
	var nat: int = r.value
	var crit_range: int = ctx.get("crit_range", 20)
	var crit := nat >= crit_range
	var hit := crit or (nat != 1 and total >= ac)
	if not hit and a.features.has("lucky") and res_left(a, "luck") > 0 \
			and decide(a, "%s misses %s (%d vs AC %d). Spend a luck point to roll again?" % [a.name, t.name, total, ac]):
		spend_res(a, "luck")
		var r2 := Dice.d20(rng, Dice.NORMAL, a.traits.has("lucky"))
		text += " → luck %s" % r2.text
		if r2.value > nat:
			total += r2.value - nat
			nat = r2.value
			crit = nat >= crit_range
			hit = crit or (nat != 1 and total >= ac)
	if hit and t.features.has("lucky") and res_left(t, "luck") > 0 \
			and decide(t, "%s hits %s (%d vs AC %d). Spend a luck point to make %s roll again?" % [a.name, t.name, total, ac, a.name]):
		spend_res(t, "luck")
		var r3 := Dice.d20(rng, Dice.NORMAL)
		text += " → %s's luck %s" % [t.name, r3.text]
		if r3.value < nat:
			total += r3.value - nat
			nat = r3.value
			crit = nat >= crit_range
			hit = crit or (nat != 1 and total >= ac)
	if not hit and nat != 1 and ctx.get("weapon", false) and _maneuver_ready(a, "precision") and total + Dice.max_value(a.fdata.superiority_die) >= ac \
			and decide(a, "%s misses %s by %d. Use Precision Attack (+%s)?" % [a.name, t.name, ac - total, a.fdata.superiority_die]):
		spend_res(a, "superiority")
		var b := Dice.roll(rng, a.fdata.superiority_die)
		total += b.total; text += " +%s(precision)" % b.text
		hit = total >= ac
	if hit and t.options.has("multiattack_defense"):
		t.fdata["multiattack_defense"] = mad_key  # +4 AC against this attacker for the rest of the turn
	if not hit and nat != 1 and a.inspiration_die != "":
		var b := Dice.roll(rng, a.inspiration_die)
		total += b.total; text += " +%s(inspiration)" % b.text
		a.inspiration_die = ""
		hit = total >= ac
	if hit and not crit:
		# Shield (+5 AC), Parry (+2 AC), Cutting Words (-die) — used only if they turn a hit into a miss.
		var reacted := false
		if _knows_spell(t, "shield") and can_react(t) and lowest_slot(t, 1) > 0 and total < ac + 5 \
				and decide(t, "%s hits %s with %s (%d vs AC %d). Cast Shield for +5 AC (level %d slot)?" % [a.name, t.name, ctx.get("label", "an attack"), total, ac, lowest_slot(t, 1)]):
			reacted = true
			var lv := lowest_slot(t, 1)
			spend_slot(t, lv)
			t.reaction_used = true
			add_effect({"name": "Shield", "spell_id": "shield", "mods": {"ac_bonus": 5}, "expires_on": {"who": "target", "phase": "start", "count": 1}}, t.id, t.id)
			ac += 5
			add_log("spell", "%s casts Shield as a reaction (+5 AC)." % t.name)
			hit = total >= ac
		if not reacted and t.features.has("defensiveDuelist") and kind == "melee" and can_react(t) and total < ac + t.prof \
				and t.attacks.any(func(w): return w.props.has("finesse") and w.get("proficient", false)) \
				and decide(t, "%s hits %s (%d vs AC %d). Use Defensive Duelist for +%d AC?" % [a.name, t.name, total, ac, t.prof]):
			reacted = true
			t.reaction_used = true
			ac += t.prof
			add_log("info", "%s parries with Defensive Duelist (+%d AC)." % [t.name, t.prof])
			hit = total >= ac
		if not reacted and t.traits.has("parry") and kind == "melee" and can_react(t) and can_see(t, a) and total < ac + 2 \
				and decide(t, "%s hits %s (%d vs AC %d). Parry for +2 AC?" % [a.name, t.name, total, ac]):
			reacted = true
			t.reaction_used = true
			ac += 2
			add_log("info", "%s parries (+2 AC)." % t.name)
			hit = total >= ac
		if not reacted:
			for bard in combatants():
				if bard.features.has("cuttingWords") and not hostile(bard, t) and hostile(bard, a) and can_react(bard) \
						and res_left(bard, "inspiration") > 0 and dist(bard, a) <= 60 and can_see(bard, a):
					var die: String = bard.fdata.inspiration_die
					if total - ac < Dice.max_value(die) and decide(bard, "%s's attack on %s rolled %d vs AC %d. Use Cutting Words (−%s)?" % [a.name, t.name, total, ac, die]):
						spend_res(bard, "inspiration")
						bard.reaction_used = true
						var b := Dice.roll(rng, die)
						total -= b.total; text += " -%s(cutting words)" % b.text
						add_log("info", "%s uses Cutting Words on %s." % [bard.name, a.name])
						hit = total >= ac
					break
	if hit and (has_cond(t, "paralyzed") or has_cond(t, "unconscious")) and dist(a, t) <= 5:
		crit = true
	if not hit:
		crit = false
	# Consume one-shot effects.
	for e in effects_on(t):
		if e.get("consume", "") == "next_attack_against" or (e.get("tag", "") == "help" and e.mods.get("help_side", "") == a.side):
			remove_effect(e)
	for e in effects_on(a):
		if e.get("consume", "") == "next_own_attack" or e.get("tag", "") == "inspired":
			remove_effect(e)
	var mode_txt := ""
	if mode == Dice.ADVANTAGE:
		mode_txt = " [adv: %s]" % ", ".join(m.adv)
	elif mode == Dice.DISADVANTAGE:
		mode_txt = " [dis: %s]" % ", ".join(m.dis)
	elif not m.adv.is_empty():
		mode_txt = " [adv & dis cancel]"
	var cover_txt := (" (+%d cover)" % cover) if cover > 0 else ""
	var outcome := "CRITICAL HIT" if crit else ("HIT" if hit else "MISS")
	var ac_txt := (" vs AC %d" % ac) if t.kind == "pc" else ""
	add_log("attack", "%s → %s with %s: %d%s — %s" % [a.name, t.name, ctx.get("label", "an attack"), total, ac_txt, outcome],
		text + mode_txt + cover_txt, a.name)
	events.append({"kind": "attack", "attacker_id": a.id, "target_id": t.id, "ranged": kind == "ranged", "hit": hit, "crit": crit})
	if hit or kind != "ranged" or not a.features.has("skulker"):
		a.hidden = 0
	return {"hit": hit, "crit": crit, "natural": nat, "total": total, "ac": ac, "mode": mode}


## "great weapon master" or "sharpshooter" when -5/+10 applies to this attack, else "".
func power_attack_feat(a: Dictionary, p: Dictionary) -> String:
	if not p.get("weapon", false) or not p.get("proficient", false):
		return ""
	if p.range == "melee" and p.props.has("heavy") and a.features.has("greatWeaponMaster"):
		return "great weapon master"
	if p.range == "ranged" and a.features.has("sharpshooter"):
		return "sharpshooter"
	return ""


## Riposte (Martial Adept): when `a` misses `t` in melee, `t` may strike back.
func _riposte(t: Dictionary, a: Dictionary) -> void:
	if not _maneuver_ready(t, "riposte") or not can_react(t) or t.hp <= 0 or a.dead or a.hp <= 0:
		return
	var p := best_melee(t)
	if p.is_empty() or dist(t, a) > p.reach or not decide(t, "%s misses %s. Riposte with %s?" % [a.name, t.name, p.name]):
		return
	t.reaction_used = true
	spend_res(t, "superiority")
	add_log("attack", "%s ripostes!" % t.name)
	var q: Dictionary = p.duplicate(true)
	q.damage.append({"dice": t.fdata.superiority_die, "bonus": 0, "type": q.damage[0].type})
	weapon_attack(t, a, q)


## Mage Slayer: a reaction attack on a creature within 5 ft that casts a spell.
func mage_slayer(caster: Dictionary) -> void:
	for s in combatants():
		if caster.dead or caster.hp <= 0:
			return
		if s.features.has("mageSlayer") and hostile(s, caster) and can_react(s) and s.hp > 0 and dist(s, caster) <= 5:
			var p := best_melee(s)
			if not p.is_empty() and decide(s, "%s casts a spell next to %s. Use Mage Slayer to attack with %s?" % [caster.name, s.name, p.name]):
				s.reaction_used = true
				add_log("attack", "Mage Slayer: %s strikes %s!" % [s.name, caster.name])
				weapon_attack(s, caster, p)


## Sentinel: when a creature attacks someone else, a Sentinel within 5 ft of it may strike it as a reaction.
func sentinel_strike(a: Dictionary, t: Dictionary) -> void:
	if t.features.has("sentinel"):
		return
	for s in combatants():
		if a.dead or a.hp <= 0:
			return
		if s.id == a.id or s.id == t.id or not s.features.has("sentinel") or not hostile(s, a) or not can_react(s) or s.hp <= 0 or dist(s, a) > 5:
			continue
		var p := best_melee(s)
		if not p.is_empty() and decide(s, "%s attacks %s. Use Sentinel to strike %s with %s?" % [a.name, t.name, a.name, p.name]):
			s.reaction_used = true
			add_log("attack", "Sentinel: %s strikes %s!" % [s.name, a.name])
			weapon_attack(s, a, p)


func _maneuver_ready(c: Dictionary, m: String) -> bool:
	return c.fdata.get("maneuvers", []).has(m) and res_left(c, "superiority") > 0


func _knows_spell(c: Dictionary, sid: String) -> bool:
	return not c.spellcasting.is_empty() and c.spellcasting.known.has(sid)


# ---------------- Weapon attacks ----------------

## Resolves a weapon (or natural) attack that has already been validated and paid for.
func weapon_attack(a: Dictionary, t: Dictionary, base_p: Dictionary, opts: Dictionary = {}, offhand: bool = false) -> Dictionary:
	var p := effective_profile(a, base_p)
	var melee: bool = p.range == "melee"
	if opts.get("reckless", false) and a.features.has("recklessAttack") and melee and p.ability == "str" and is_turn_of(a) and not a.turn.first_attack_made:
		a.fdata["reckless_turn"] = state.turn_counter
		add_effect({"name": "Reckless", "tag": "reckless", "mods": {"advantage_against": true}, "expires_on": {"who": "source", "phase": "start", "count": 1}}, a.id, a.id)
		add_log("info", "%s attacks recklessly!" % a.name)
	var reckless: bool = a.fdata.get("reckless_turn", -1) == state.turn_counter and melee and p.ability == "str"
	if is_turn_of(a):
		a.turn.first_attack_made = true
		if not offhand:
			a.turn.attack_action_weapons.append(base_p.id)
	if hostile(a, t):
		a.turn.attacked_hostile = true
	var ammo := ammo_kind(a, p)
	if ammo != "":
		a.notes[ammo] = str(maxi(0, Equipment.ammo_left(a, ammo) - 1))
		if not a.has("ammo_spent"):
			a["ammo_spent"] = {}
		a.ammo_spent[ammo] = a.ammo_spent.get(ammo, 0) + 1
	if p.has("recharge"):
		base_p.charged = false
	if melee and a.features.has("mobile") and is_turn_of(a):
		a.turn["mobile_ids"] = a.turn.get("mobile_ids", []) + [t.id]
	var power: bool = opts.get("power", false) and power_attack_feat(a, p) != ""
	var r := attack_roll(a, t, p.range, p.to_hit - (5 if power else 0), {"profile": p, "weapon": p.get("weapon", true), "crit_range": p.get("crit_range", 20), "reckless": reckless, "label": p.name,
		"opportunity": opts.get("opportunity", false), "ignore_cover": not melee and a.features.has("sharpshooter") and p.get("weapon", true)})
	if not r.hit:
		events.append({"kind": "miss", "id": t.id})
		if melee and t.features.has("standAgainstTheTide") and can_react(t) and can_see(t, a) and not opts.get("redirected", false):
			for o in combatants():
				if o.id != a.id and o.id != t.id and hostile(t, o) and is_alive(o) and dist(a, o) <= p.get("reach", 5) \
						and decide(t, "%s misses %s. Stand Against the Tide: turn the attack on %s?" % [a.name, t.name, o.name]):
					t.reaction_used = true
					add_log("info", "%s turns %s's attack onto %s (Stand Against the Tide)." % [t.name, a.name, o.name])
					return weapon_attack(a, o, base_p, opts.merged({"redirected": true}), offhand)
		if melee:
			_riposte(t, a)
		return r
	var crit: bool = r.crit
	var specs := []  # {dice, bonus, type, weapon_die}
	for part in p.damage:
		var bonus: int = part.get("bonus", 0)
		if offhand and a.turn.bonus_attack.get("kind", "") == "offhand" and p.get("dmg_mod", 0) > 0 and not a.options.has("two_weapon"):
			bonus -= p.dmg_mod
		specs.append({"dice": part.get("dice", ""), "bonus": bonus, "type": part.type, "reroll": p.get("reroll_low", 0)})
	var wtype: String = p.damage[0].type if not p.damage.is_empty() else "bludgeoning"
	var extras := PackedStringArray()
	if power:
		specs.append({"dice": "", "bonus": 10, "type": wtype}); extras.append(power_attack_feat(a, p))
	if offhand and a.turn.bonus_attack.get("kind", "") == "charger" and a.turn.movement_used >= 10:
		specs.append({"dice": "", "bonus": 5, "type": wtype}); extras.append("charger")
	var maneuver: String = opts.get("maneuver", "")
	if maneuver in ["trip", "pushing", "menacing", "distracting"] and _maneuver_ready(a, maneuver) and p.get("weapon", true):
		spend_res(a, "superiority")
		specs.append({"dice": a.fdata.superiority_die, "bonus": 0, "type": wtype}); extras.append(Creator.MANEUVERS[maneuver][0].to_lower())
	else:
		maneuver = ""
	# Savage Attacker: the weapon's damage dice twice, keep the higher.
	var savage: bool = melee and a.features.has("savageAttacker") and p.get("weapon", true) and a.used_on_turn.get("savage", -1) != state.turn_counter
	# Rage
	if melee and p.ability == "str" and p.get("weapon", true):
		for mm in mods_of(a):
			if mm.has("rage_damage"):
				specs.append({"dice": "", "bonus": mm.rage_damage, "type": wtype}); extras.append("rage")
	# Sneak Attack
	if a.features.has("sneakAttack") and a.used_on_turn.get("sneak", -1) != state.turn_counter \
			and (p.props.has("finesse") or p.range == "ranged") and r.mode != Dice.DISADVANTAGE:
		var ally_adjacent := false
		for o in combatants():
			if o.id != a.id and hostile(o, t) and is_alive(o) and o.hp > 0 and not incapacitated(o) and dist(o, t) <= 5:
				ally_adjacent = true
				break
		if r.mode == Dice.ADVANTAGE or ally_adjacent:
			a.used_on_turn["sneak"] = state.turn_counter
			specs.append({"dice": "%dd6" % a.fdata.sneak_dice, "bonus": 0, "type": wtype}); extras.append("sneak attack")
	# Divine Smite: chosen after the hit. opts.smite is the preferred slot level (0 = lowest available).
	var pref: int = opts.get("smite", 0)
	var smite: int = pref if pref > 0 and slots_left(a, pref) > 0 else lowest_slot(a, 1)
	if smite > 0 and melee and p.get("weapon", true) and a.features.has("divineSmite") \
			and (pref > 0 if reaction_mode(a) == "never" else decide(a, "%s hits %s%s. Divine Smite with a level %d slot?" % [a.name, t.name, " (critical hit!)" if crit else "", smite], pref > 0 or crit)):
		spend_slot(a, smite)
		var n := mini(5, 1 + smite)
		if t.ctype in ["undead", "fiend"]:
			n += 1
		specs.append({"dice": "%dd8" % n, "bonus": 0, "type": "radiant"}); extras.append("divine smite (level %d)" % smite)
	if melee and p.get("weapon", true) and a.features.has("improvedSmite"):
		specs.append({"dice": "1d8", "bonus": 0, "type": "radiant"}); extras.append("improved divine smite")
	if a.features.has("foeSlayer") and a.fdata.get("favored_enemies", []).has(t.ctype) and a.used_on_turn.get("foe_slayer", -1) != state.turn_counter:
		a.used_on_turn["foe_slayer"] = state.turn_counter
		specs.append({"dice": "", "bonus": maxi(0, mod(a, "wis")), "type": wtype}); extras.append("foe slayer")
	# Hunter's Mark / Hex
	for e in effects_on(t):
		var mk: Dictionary = e.get("mods", {}).get("mark_damage", {})
		if not mk.is_empty() and e.source_id == a.id:
			specs.append({"dice": mk.dice, "bonus": 0, "type": wtype if mk.type == "weapon" else mk.type}); extras.append(e.name.to_lower())
	# Colossus Slayer
	if a.features.has("colossusSlayer") and t.hp < t.max_hp and a.used_on_turn.get("colossus", -1) != state.turn_counter:
		a.used_on_turn["colossus"] = state.turn_counter
		specs.append({"dice": "1d8", "bonus": 0, "type": wtype}); extras.append("colossus slayer")
	# Divine Strike
	if a.fdata.get("divine_strike", "") != "" and p.get("weapon", true) and is_turn_of(a) and a.used_on_turn.get("divine_strike", -1) != state.turn_counter:
		a.used_on_turn["divine_strike"] = state.turn_counter
		specs.append({"dice": a.fdata.divine_strike, "bonus": 0, "type": "radiant"}); extras.append("divine strike")
	# Savage Attacks
	if crit and melee and a.traits.has("savageAttacks") and not p.damage.is_empty() and p.damage[0].get("dice", "") != "":
		specs.append({"dice": Dice.first_die(p.damage[0].dice), "bonus": 0, "type": wtype, "no_crit": true}); extras.append("savage attacks")
	if crit and melee and a.fdata.get("brutal_dice", 0) > 0 and not p.damage.is_empty() and p.damage[0].get("dice", "") != "":
		specs.append({"dice": Dice.scale(Dice.first_die(p.damage[0].dice), a.fdata.brutal_dice), "bonus": 0, "type": wtype, "no_crit": true}); extras.append("brutal critical")
	var parts := roll_damage(specs, crit)
	if savage:
		a.used_on_turn["savage"] = state.turn_counter
		var n: int = p.damage.size()
		var again := roll_damage(specs.slice(0, n), crit)
		var first := 0
		var second := 0
		for i in n:
			first += parts[i].amount
			second += again[i].amount
		if second > first:
			for i in n:
				parts[i] = again[i]
		parts[0].text += " (savage attacker: %d vs %d)" % [first, second]
	if p.props.has("unarmed") and a.features.has("tavernBrawler") and is_turn_of(a):
		a.fdata["brawler_turn"] = state.turn_counter
	deal_damage(t, parts, {"source_id": a.id, "crit": crit, "attack": true, "melee": melee, "ranged_weapon": not melee and p.get("weapon", true),
		"nonmagical": not p.get("magical", false),
		"label": p.name + ((" + " + ", ".join(extras)) if extras.size() else "")})
	if a.features.has("greatWeaponMaster") and melee and is_turn_of(a) and (crit or t.hp <= 0) and a.turn.bonus:
		a.fdata["gwm_turn"] = state.turn_counter
		add_log("info", "Great Weapon Master: %s can make a melee attack as a bonus action." % a.name)
	if t.dead or t.hp <= 0 and t.kind == "npc":
		return r
	# Riders
	match maneuver:
		"trip", "pushing":
			if Grid.size_index(t.csize) <= Grid.size_index("large") and not roll_save(t, "str", a.fdata.maneuver_dc, {"label": Creator.MANEUVERS[maneuver][0]}).success:
				if maneuver == "trip":
					knock_prone(t)
				else:
					push_creature(t, a, 15)
		"menacing":
			if not roll_save(t, "wis", a.fdata.maneuver_dc, {"label": "Menacing Attack", "frighten": true}).success:
				add_effect({"name": "Frightened", "conditions": ["frightened"], "expires_on": {"who": "source", "phase": "end", "count": 2}}, a.id, t.id)
				add_log("info", "%s is frightened of %s." % [t.name, a.name])
		"distracting":
			add_effect({"name": "Distracted", "mods": {"advantage_against": true}, "consume": "next_attack_against", "expires_on": {"who": "source", "phase": "start", "count": 1}}, a.id, t.id)
	if p.has("on_hit"):
		apply_save_rider(a, t, p.on_hit, p.name)
	if p.has("hit_effect"):
		add_effect(p.hit_effect, a.id, t.id)
		add_log("info", "%s is %s." % [t.name, p.hit_effect.name.to_lower()])
	if opts.get("stunning_strike", false) and melee and a.features.has("stunningStrike") and spend_res(a, "ki"):
		var s := roll_save(t, "con", a.fdata.ki_dc, {"label": "Stunning Strike"})
		if not s.success:
			add_effect({"name": "Stunned", "conditions": ["stunned"], "expires_on": {"who": "source", "phase": "end", "count": 1}}, a.id, t.id)
			add_log("info", "%s is stunned!" % t.name)
	if offhand and a.turn.bonus_attack.get("kind", "") == "flurry" and a.features.has("openHand"):
		match opts.get("open_hand", ""):
			"prone":
				if not roll_save(t, "dex", a.fdata.ki_dc, {"label": "Open Hand"}).success:
					knock_prone(t)
			"push":
				if not roll_save(t, "str", a.fdata.ki_dc, {"label": "Open Hand"}).success:
					push_creature(t, a, 15)
			"reactions":
				add_effect({"name": "Open Hand", "mods": {"no_reactions": true}, "expires_on": {"who": "source", "phase": "end", "count": 1}}, a.id, t.id)
	return r


func apply_save_rider(src: Dictionary, t: Dictionary, rider: Dictionary, label: String) -> void:
	if not is_alive(t) or t.hp <= 0:
		return
	if rider.get("immune_types", []).has(t.ctype):
		return
	for tr in rider.get("immune_traits", []):
		if t.traits.has(tr):
			return
	var s := roll_save(t, rider.ability, rider.dc, {"label": label, "poison": rider.get("damage", []).any(func(d): return d.type == "poison")})
	if rider.has("damage"):
		var parts := roll_damage(rider.damage, false)
		if s.success:
			if rider.get("half", false):
				for pp in parts:
					pp.amount = pp.amount / 2
			else:
				parts = []
		if not parts.is_empty():
			deal_damage(t, parts, {"source_id": src.id, "label": label})
	if not s.success and is_alive(t):
		if rider.has("condition"):
			if rider.condition == "prone":
				knock_prone(t)
			else:
				add_effect({"name": rider.condition.capitalize(), "conditions": [rider.condition]}, src.id, t.id)
		if rider.has("effect"):
			add_effect(rider.effect, src.id, t.id)
			add_log("info", "%s is affected by %s." % [t.name, rider.effect.name])


# ---------------- Damage & healing ----------------

## specs: [{dice, bonus, type, reroll}] -> [{amount, type, text}]
func roll_damage(specs: Array, crit: bool) -> Array:
	var out := []
	for s in specs:
		var amount: int = s.get("bonus", 0)
		var text := ""
		if s.get("dice", "") != "":
			var r := Dice.roll(rng, s.dice, {"crit": crit and not s.get("no_crit", false), "reroll_low": s.get("reroll", 0), "min_die": s.get("min_die", 0)})  # extra crit dice aren't doubled
			amount += r.total
			text = r.text
		if s.get("bonus", 0) != 0:
			text += (" " if text else "") + Dice.fmt_mod(s.bonus)
		out.append({"amount": maxi(0, amount), "type": s.type, "text": text})
	return out


func _resists(t: Dictionary, dtype: String) -> bool:
	if t.resistances.has(dtype) or has_cond(t, "petrified") or (dtype == "fire" and in_water(t)):
		return true
	for m in mods_of(t):
		if m.get("resist", []).has(dtype):
			return true
	return false


## Applies damage parts. info: source_id, crit, attack, melee, ranged_weapon, label.
func deal_damage(t: Dictionary, parts: Array, info: Dictionary = {}) -> int:
	if t.is_empty() or t.dead:
		return 0
	var src := get_c(info.get("source_id", ""))
	var notes := PackedStringArray()
	var raw := 0
	for p in parts:
		raw += p.amount
	# Damage-reducing reactions.
	if info.get("attack", false) and raw > 0 and can_react(t):
		var by: String = src.get("name", "An attack")
		if info.get("ranged_weapon", false) and t.features.has("deflectMissiles") \
				and decide(t, "%s's missile hits %s for %d. Use Deflect Missiles to reduce it?" % [by, t.name, raw]):
			var red: int = Dice.roll(rng, "1d10").total + mod(t, "dex") + class_lv(t, "monk")
			t.reaction_used = true
			_reduce_parts(parts, red)
			notes.append("deflect missiles -%d" % red)
		elif t.features.has("uncannyDodge") and not src.is_empty() and can_see(t, src) \
				and decide(t, "%s hits %s for %d. Use Uncanny Dodge to halve it?" % [by, t.name, raw]):
			t.reaction_used = true
			_reduce_parts(parts, raw - raw / 2)
			notes.append("uncanny dodge (halved)")
		elif info.get("melee", false) and _maneuver_ready(t, "parry") \
				and decide(t, "%s hits %s for %d. Use Parry (−%s − Dex)?" % [by, t.name, raw, t.fdata.superiority_die]):
			t.reaction_used = true
			spend_res(t, "superiority")
			var red: int = Dice.roll(rng, t.fdata.superiority_die).total + mod(t, "dex")
			_reduce_parts(parts, red)
			notes.append("parry -%d" % red)
	var total := 0
	var breakdown := PackedStringArray()
	var types := []
	for p in parts:
		var amt: int = p.amount
		var tag := ""
		var mundane: bool = info.get("nonmagical", false) and p.type in ["bludgeoning", "piercing", "slashing"]
		if mundane and t.features.has("heavyArmorMaster") and t.armor == "heavy" and amt > 0:
			amt = maxi(0, amt - 3); tag = " heavy armor master −3"
		var adept: bool = info.get("spell", false) and src.get("fdata", {}).get("adept_types", []).has(p.type)
		if t.immunities.has(p.type) or (p.type == "thunder" and silenced(t)) or (mundane and t.traits.has("nonmagicalImmunity")):
			amt = 0; tag = " immune"
		else:
			if (_resists(t, p.type) and not adept) or (mundane and t.traits.has("nonmagicalResistance")):
				amt = amt / 2; tag = " resisted"
			if t.vulnerabilities.has(p.type):
				amt *= 2; tag += " vulnerable"
		total += amt
		types.append(p.type)
		if amt > 0 and t.fdata.get("regen", {}).get("blocked_by", []).has(p.type):
			t.fdata["regen_blocked"] = true
		breakdown.append("%d %s%s%s" % [amt, p.type, tag, (" (" + p.text + ")") if p.get("text", "") != "" else ""])
	var label: String = info.get("label", "")
	if total <= 0:
		add_log("damage", "%s takes no damage%s." % [t.name, (" from " + label) if label else ""], ", ".join(breakdown))
		return 0
	var absorbed := mini(t.temp_hp, total)
	t.temp_hp -= absorbed
	if absorbed > 0:
		notes.append("%d absorbed by temp HP" % absorbed)
	var rem := total - absorbed
	var was_down: bool = t.hp <= 0
	t.hp -= rem
	t.took_damage = true
	events.append({"kind": "damage", "id": t.id, "amount": total, "crit": info.get("crit", false)})
	add_log("damage", "%s takes %d damage%s." % [t.name, total, (" from " + label) if label else ""],
		", ".join(breakdown) + ((" — " + ", ".join(notes)) if notes.size() else ""), t.name)
	if not was_down and t.hp <= 0 and t.fdata.has("wild_shape"):
		var carry: int = -t.hp
		end_wild_shape(t, " (its beast form drops to 0 HP)")
		t.hp -= carry
	if was_down:
		t.hp = 0
		if rem >= t.max_hp:
			kill(t, "massive damage")
		elif rem > 0:
			t.stable = false
			t.death_saves.failures += 2 if info.get("crit", false) else 1
			add_log("death", "%s suffers %s death save failure%s (%d/3)." % [t.name, "two" if info.get("crit", false) else "a", "s" if info.get("crit", false) else "", mini(3, t.death_saves.failures)])
			if t.death_saves.failures >= 3:
				kill(t, "")
	elif t.hp <= 0:
		var overflow: int = -t.hp
		t.hp = 0
		_drop_to_zero(t, overflow, total, types, info)
		check_fall(t)
	if t.dead:
		return total
	remove_effects_where(func(e): return e.target_id == t.id and e.get("ends_on_damage", false), " (took damage)")
	if t.hp > 0 and not t.concentration.is_empty():
		var s := roll_save(t, "con", maxi(10, total / 2), {"label": "concentration", "concentration": true,
			"dis": src.get("features", []).has("mageSlayer"), "dis_note": "mage slayer"})
		if not s.success:
			end_concentration(t, " (lost concentration)")
	if t.hp > 0 and not src.is_empty() and src.id != t.id:
		_hellish_rebuke(t, src)
	return total


## Hellish Rebuke: the tiefling's once-a-day racial casting (as a 2nd-level spell, Charisma) or a warlock's slot.
func _hellish_rebuke(t: Dictionary, src: Dictionary) -> void:
	if src.dead or not can_react(t) or dist(t, src) > 60 or not can_see(t, src):
		return
	var racial := res_left(t, "infernal_rebuke") > 0
	var slot := 2 if racial else 0
	if not racial and _knows_spell(t, "hellish_rebuke"):
		var sc: Dictionary = t.spellcasting
		slot = sc.pact.level if not sc.pact.is_empty() and sc.pact.used < sc.pact.max else lowest_slot(t, 1)
	if slot == 0 or not decide(t, "%s damaged %s. Cast Hellish Rebuke (level %d%s)?" % [src.name, t.name, slot, ", Infernal Legacy" if racial else " slot"]):
		return
	t.reaction_used = true
	var dc: int = 8 + t.prof + mod(t, "cha") if racial else t.spellcasting.dc
	if racial:
		spend_res(t, "infernal_rebuke")
	else:
		spend_slot(t, slot)
	add_log("spell", "%s casts Hellish Rebuke at %s!" % [t.name, src.name], "", t.name)
	var dmg := Dice.roll(rng, "%dd10" % (slot + 1))
	var save := roll_save(src, "dex", dc, {"label": "Hellish Rebuke"})
	deal_damage(src, [{"amount": dmg.total / 2 if save.success else dmg.total, "type": "fire", "text": dmg.text}], {"source_id": t.id, "label": "Hellish Rebuke"})


func _reduce_parts(parts: Array, amount: int) -> void:
	var left := amount
	for p in parts:
		var take := mini(left, p.amount)
		p.amount -= take
		left -= take


func _drop_to_zero(t: Dictionary, overflow: int, total: int, types: Array, info: Dictionary) -> void:
	var src := get_c(info.get("source_id", ""))
	if not src.is_empty() and src.features.has("darkOnesBlessing") and hostile(src, t) and not src.dead:
		var thp := maxi(1, mod(src, "cha") + class_lv(src, "warlock"))
		if thp > src.temp_hp:
			src.temp_hp = thp
			add_log("heal", "%s gains %d temporary hit points (Dark One's Blessing)." % [src.name, thp])
	var ward := find_effect(t, "death_ward")
	if not ward.is_empty():
		t.hp = 1
		remove_effect(ward, "")
		add_log("heal", "Death Ward holds: %s drops to 1 hit point instead." % t.name)
		return
	if overflow >= t.max_hp:
		kill(t, "massive damage")
		return
	if t.features.has("relentlessRage") and has_tag(t, "rage"):
		var uses: int = t.fdata.get("relentless_uses", 0)
		t.fdata["relentless_uses"] = uses + 1
		if roll_save(t, "con", 10 + 5 * uses, {"label": "Relentless Rage"}).success:
			t.hp = 1
			add_log("heal", "%s keeps fighting through the rage! (Relentless Rage: drops to 1 HP)" % t.name)
			return
	if t.traits.has("relentlessEndurance") and spend_res(t, "relentless"):
		t.hp = 1
		add_log("heal", "%s refuses to fall! (Relentless Endurance: drops to 1 HP)" % t.name)
		return
	if t.traits.has("undeadFortitude") and not types.has("radiant") and not info.get("crit", false):
		if roll_save(t, "con", 5 + total, {"label": "Undead Fortitude"}).success:
			t.hp = 1
			add_log("heal", "%s refuses to die (Undead Fortitude)." % t.name)
			return
	if t.kind == "npc" and state.settings.npcs_die_at_zero:
		kill(t, "")
		return
	t.death_saves = {"successes": 0, "failures": 0}
	t.stable = false
	remove_effects_where(func(e): return e.target_id == t.id and e.get("tag", "") == "rage")
	if not t.concentration.is_empty():
		end_concentration(t, " (unconscious)")
	knock_prone(t, true)
	_on_incapacitated_check(t)
	add_log("death", "%s falls unconscious and is dying!" % t.name)


func knock_prone(t: Dictionary, quiet: bool = false) -> void:
	if has_cond(t, "prone") or t.cond_immunities.has("prone"):
		return
	add_effect({"name": "Prone", "tag": "prone", "conditions": ["prone"]}, t.id, t.id)
	if not quiet:
		add_log("info", "%s is knocked prone." % t.name)


func kill(t: Dictionary, reason: String) -> void:
	if t.dead:
		return
	t.dead = true
	t.hp = 0
	t.died_round = state.combat.round
	if t.get("rider", "") != "":
		mount_falls(t)
	if t.get("mounted_on", "") != "":
		unseat(t, true)
	if t.get("alt", 0) > 0:
		t.alt = 0
		events.append({"kind": "fall", "id": t.id})
	if not t.concentration.is_empty():
		end_concentration(t, "")
	remove_effects_where(func(e): return e.target_id == t.id or (e.source_id == t.id and e.get("tag", "") == "grapple"))
	events.append({"kind": "death", "id": t.id})
	add_log("death", "%s dies%s!" % [t.name, (" (" + reason + ")") if reason else ""])


func heal(t: Dictionary, amount: int, label: String = "") -> int:
	if t.is_empty() or t.dead or amount <= 0:
		return 0
	if has_mod(t, "no_healing"):
		add_log("heal", "%s can't regain hit points right now." % t.name)
		return 0
	var was: int = t.hp
	t.hp = mini(hp_cap(t), maxi(0, t.hp) + amount)
	var gained: int = t.hp - maxi(0, was)
	if was <= 0 and t.hp > 0:
		t.death_saves = {"successes": 0, "failures": 0}
		t.stable = false
		add_log("heal", "%s regains consciousness!" % t.name)
	events.append({"kind": "heal", "id": t.id, "amount": gained})
	add_log("heal", "%s regains %d HP%s." % [t.name, gained, (" from " + label) if label else ""], "", t.name)
	return gained


func death_save(c: Dictionary) -> void:
	var r := Dice.d20(rng, Dice.ADVANTAGE if spend_inspired(c) else Dice.NORMAL, c.traits.has("lucky"))
	var total: int = r.value
	var text: String = r.text
	for m in mods_of(c):
		if m.has("save_die"):
			var b := Dice.roll(rng, m.save_die)
			total += b.total; text += " +%s(bless)" % b.text
	var aura := _aura_from(c, "auraOfProtection")
	if not aura.is_empty():
		total += maxi(1, mod(aura, "cha")); text += " +%d(aura of protection)" % maxi(1, mod(aura, "cha"))
	if r.value == 20:
		add_log("death", "%s rolls a natural 20 on a death save and regains 1 HP!" % c.name, text)
		heal(c, 1, "")
		return
	if r.value == 1:
		c.death_saves.failures += 2
	elif total >= 10:
		c.death_saves.successes += 1
	else:
		c.death_saves.failures += 1
	add_log("death", "%s death save: %d — %s (successes %d, failures %d)" % [c.name, total, "success" if total >= 10 and r.value != 1 else "failure",
		c.death_saves.successes, mini(3, c.death_saves.failures)], text)
	if c.death_saves.failures >= 3:
		kill(c, "")
	elif c.death_saves.successes >= 3:
		c.stable = true
		add_log("death", "%s is stable." % c.name)


# ---------------- Movement ----------------

func move_rules(c: Dictionary) -> Dictionary:
	# Crawling and dragging each add 1 extra foot per foot, so both together cost 3x.
	var mult := 1
	if has_cond(c, "prone"):
		mult += 1
	for e in effects_from(c):
		if e.get("tag", "") == "grapple":
			var g := get_c(e.target_id)
			if not g.is_empty() and Grid.size_index(g.csize) > Grid.size_index(c.csize) - 2:
				mult += 1
				break
	var mobile_dash: bool = c.features.has("mobile") and in_combat() and c.turn.get("dashed_action", false)
	var water_walk: bool = c.features.has("waterWalk") and c.armor == "none" and not c.shield
	return {"cost_multiplier": mult, "ignore_difficult": c.features.has("landsStride") or mobile_dash,
		"swim": c.get("speeds", {}).get("swim", 0) > 0 or water_walk}


## Fly up or down to `alt` feet. Each 5 ft of height costs 5 ft of flying movement.
## shortcut: rising out of an enemy's reach doesn't provoke an opportunity attack.
func change_altitude(c: Dictionary, alt: int) -> String:
	if mover_of(c).id != c.id:
		return change_altitude(mover_of(c), alt)
	var was: int = c.get("alt", 0)
	alt = clampi(alt / Grid.FT * Grid.FT, 0, 500)
	if alt == was:
		return ""
	if fly_speed(c) == 0:
		return "%s can't fly." % c.name
	if alt > was and has_cond(c, "prone"):
		return "Stand up first."
	c.alt = maxi(5, maxi(alt, was))  # flying movement is measured against the flying speed
	var left := movement_left(c)
	c.alt = was
	var cost := absi(alt - was)
	if left < cost:
		return "Not enough movement: that costs %d ft, you have %d ft of flying left." % [cost, left]
	if in_combat():
		c.turn.movement_used += cost
	c.alt = alt
	_carry_rider(c)
	events.append({"kind": "alt", "id": c.id, "alt": alt})
	add_log("info", "%s %s." % [c.name, "lands" if alt == 0 else ("flies %s to %d ft" % ["up" if alt > was else "down", alt])])
	return ""


## Long jump in a straight line, clearing anything on the way but walls (difficult terrain, water, low walls, creatures).
## Up to the Strength score in feet after moving 10 ft this turn (5 ft with Athlete), half that from a standing start.
func jump(c: Dictionary, to: Vector2i) -> String:
	if c.get("mounted_on", "") != "":
		return "Dismount first."
	if c.get("alt", 0) > 0:
		return "%s is flying." % c.name
	if speed_of(c) == 0 or has_cond(c, "prone"):
		return "%s can't jump right now." % c.name
	var run_up := 5 if c.features.has("athlete") else 10
	var running: bool = not in_combat() or c.turn.movement_used >= run_up
	var max_ft: int = (c.abilities.str if running else c.abilities.str / 2) / Grid.FT * Grid.FT
	var d := Grid.distance_to_cell(state, c, to)
	if d == 0:
		return "Pick a square to jump to."
	if d > max_ft:
		return "%s can jump %d ft%s; that's %d ft." % [c.name, max_ft, "" if running else " from a standing start (move %d ft first for a running jump)" % run_up, d]
	if d > movement_left(c):
		return "Not enough movement: the jump costs %d ft, you have %d ft left." % [d, movement_left(c)]
	if Grid.segment_blocked(state.map, Grid.center(c), Grid.center(c, to)):
		return "A wall is in the way."
	for f in Grid.footprint(c, to):
		if Grid.cell_at(state.map, f.x, f.y) == Grid.WALL:
			return "You can't land there."
		for o in combatants():
			if o.id != c.id and not o.dead and o.get("alt", 0) == 0 and Grid.footprint(o).has(f):
				return "That space is taken."
	var from: Vector2i = c.pos
	_opportunity_attacks(c, from, to)
	if c.dead or c.hp <= 0 or incapacitated(c):
		return ""
	c.pos = to
	_carry_rider(c)
	if in_combat():
		c.turn.movement_used += d
	events.append({"kind": "move", "id": c.id, "path": [from, to]})
	add_log("info", "%s jumps %d ft." % [c.name, d])
	return ""


func stand_up(c: Dictionary) -> String:
	if not has_cond(c, "prone"):
		return "%s isn't prone." % c.name
	var cost := 5 if c.features.has("athlete") else speed_of(c) / 2
	if speed_of(c) == 0 or movement_left(c) < cost:
		return "Standing up costs %d ft of movement." % cost
	if in_combat():
		c.turn.movement_used += cost
	remove_effects_where(func(e): return e.target_id == c.id and e.get("tag", "") == "prone")
	add_log("info", "%s stands up." % c.name)
	return ""


func move_to(c: Dictionary, to: Vector2i, crawl: bool = false) -> String:
	if c.get("mounted_on", "") != "":
		var steed := mover_of(c)
		if steed.id == c.id:
			return "%s moves on its own; dismount to move yourself." % get_c(c.mounted_on).name
		return move_to(steed, to)
	if speed_of(c) == 0:
		return "%s can't move (speed 0)." % c.name
	if c.surprised and in_combat():
		return "%s is surprised and can't move this turn." % c.name
	if has_cond(c, "prone") and not crawl:
		if movement_left(c) >= (5 if c.features.has("athlete") else speed_of(c) / 2):
			stand_up(c)
	var rules := move_rules(c)
	var budget := movement_left(c)
	var reach := Grid.reachable(state, c, budget, rules)
	if not reach.cells.has(to):
		var far := Grid.reachable(state, c, 9999, rules)
		if far.cells.has(to):
			return "Not enough movement: that square costs %d ft, you have %d ft left." % [far.cells[to], budget]
		return "You can't move there."
	var path := Grid.path_to(reach, to)
	var fears := frightened_of(c)
	if not fears.is_empty():
		var p0: Vector2i = c.pos
		for step in path:
			for f in fears:
				if Grid.distance(state, c, f, step.pos) < Grid.distance(state, c, f, p0):
					return "%s is frightened of %s and can't move closer." % [c.name, f.name]
			p0 = step.pos
	var traveled := [c.pos]
	var prev_cost := 0
	for step in path:
		var from: Vector2i = c.pos
		_opportunity_attacks(c, from, step.pos)
		if c.dead or c.hp <= 0 or incapacitated(c) or speed_of(c) == 0:
			break
		c.pos = step.pos
		_carry_rider(c)
		if in_combat():
			c.turn.movement_used += step.cost - prev_cost
		prev_cost = step.cost
		traveled.append(step.pos)
		_drag_grappled(c, from)
		_readied_attacks(c, from, c.pos)
		_polearm_attacks(c, from, c.pos)
		if in_combat() and is_alive(c) and c.hp > 0:
			_aura_damage(c, from)
		if c.dead or c.hp <= 0 or incapacitated(c):
			break
	if traveled.size() > 1:
		events.append({"kind": "move", "id": c.id, "path": traveled})
		if c.get("rider", "") != "":
			events.append({"kind": "move", "id": c.rider, "path": traveled})
		add_log("info", "%s moves %d ft%s." % [c.name, prev_cost, " (crawling)" if has_cond(c, "prone") else ""])
	return ""


## Spirit Guardians and similar auras: hostile creatures that start their turn in the area, or enter it
## for the first time on a turn (`from` is the square they came from), save or take damage, once per turn.
func _aura_damage(c: Dictionary, from = null) -> void:
	for e in state.effects.duplicate():
		var aura: Dictionary = e.get("mods", {}).get("aura", {})
		if aura.is_empty() or not state.effects.has(e):
			continue
		var bearer := get_c(e.target_id)
		var src := get_c(e.source_id)
		if bearer.is_empty() or bearer.id == c.id or not hostile(src, c) or dist(bearer, c) > aura.radius:
			continue
		if from != null and Grid.distance(state, bearer, c, null, from) <= aura.radius:
			continue  # already inside
		var hits: Dictionary = e.get_or_add("aura_hits", {})
		if hits.get(c.id, -1) == state.turn_counter:
			continue
		hits[c.id] = state.turn_counter
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


func _drag_grappled(c: Dictionary, vacated: Vector2i) -> void:
	for e in effects_from(c):
		if e.get("tag", "") != "grapple":
			continue
		var g := get_c(e.target_id)
		if g.is_empty() or dist(c, g) <= 5:
			continue
		var old: Vector2i = g.pos
		g.pos = vacated
		var ok := true
		for f in Grid.footprint(g):
			if Grid.cell_at(state.map, f.x, f.y) == Grid.WALL:
				ok = false
			for o in combatants():
				if o.id != g.id and o.id != c.id and not o.dead and Grid.footprint(o).has(f):
					ok = false
		if ok and dist(c, g) <= 5:
			events.append({"kind": "move", "id": g.id, "path": [old, g.pos]})
		else:
			g.pos = old
			remove_effect(e, " (grapple broken)")


func best_melee(c: Dictionary) -> Dictionary:
	var best := {}
	var best_avg := -1.0
	for a in c.attacks:
		if a.range != "melee" or a.get("standalone", false) or a.get("bonus_only", false):
			continue
		var avg := 0.0
		for d in a.damage:
			avg += Dice.average(d.get("dice", "")) if d.get("dice", "") != "" else 0.0
			avg += d.get("bonus", 0)
		if a.props.has("unarmed"):
			avg -= 0.5
		if avg > best_avg:
			best_avg = avg
			best = a
	return best


func _opportunity_attacks(mover: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if not in_combat():
		return
	var disengaged: bool = mover.turn.disengaged and is_turn_of(mover)
	for r in combatants():
		if r.id == mover.id or not hostile(r, mover) or not can_react(r) or r.hp <= 0:
			continue
		if (disengaged and not r.features.has("sentinel")) or (is_turn_of(mover) and mover.turn.get("mobile_ids", []).has(r.id)):
			continue
		var p := best_melee(r)
		if p.is_empty():
			continue
		var reach: int = p.reach
		if Grid.distance(state, r, mover, null, from) <= reach and Grid.distance(state, r, mover, null, to) > reach and can_see(r, mover) \
				and war_caster_strike(r, mover):
			if mover.dead or mover.hp <= 0:
				return
			continue
		if Grid.distance(state, r, mover, null, from) <= reach and Grid.distance(state, r, mover, null, to) > reach and can_see(r, mover) \
				and decide(r, "%s is leaving %s's reach. Make an opportunity attack with %s?" % [mover.name, r.name, p.name]):
			r.reaction_used = true
			add_log("attack", "%s makes an opportunity attack against %s!" % [r.name, mover.name])
			var hit: bool = weapon_attack(r, mover, p, {"opportunity": true}).hit
			if mover.dead or mover.hp <= 0:
				return
			if hit and r.features.has("sentinel"):
				add_effect({"name": "Sentinel", "mods": {"no_speed": true}, "expires_on": {"who": "target", "phase": "end", "count": 1}}, r.id, mover.id)
				add_log("info", "Sentinel: %s's speed drops to 0." % mover.name)


## The Ready action, for an attack: spend the action now, attack with the reaction when an enemy
## comes within the weapon's reach (melee) or normal range (ranged) before your next turn.
func ready_attack(c: Dictionary, attack_id: String) -> String:
	if not in_combat():
		return "Ready only matters in combat."
	if c.surprised:
		return "%s is surprised and can't act this turn." % c.name
	var p := find_attack(c, attack_id)
	if p.is_empty():
		return "Unknown attack."
	var err := economy_error(c, "action")
	if err != "":
		return err
	spend_economy(c, "action")
	c["readied"] = {"attack_id": p.id, "name": p.name}
	add_log("info", "%s readies %s for when an enemy comes within %d ft." % [c.name, p.name, ready_range(p)], "", c.name)
	return ""


func ready_range(p: Dictionary) -> int:
	return p.reach if p.range == "melee" else p.normal


func _readied_attacks(mover: Dictionary, from: Vector2i, to: Vector2i) -> void:
	for r in combatants():
		var rd: Dictionary = r.get("readied", {})
		if rd.is_empty() or r.id == mover.id or not hostile(r, mover) or not can_react(r) or r.hp <= 0:
			continue
		var p := find_attack(r, rd.attack_id)
		if p.is_empty():
			continue
		var rng_ft := ready_range(p)
		if Grid.distance(state, r, mover, null, from) > rng_ft and Grid.distance(state, r, mover, null, to) <= rng_ft and can_see(r, mover) \
				and decide(r, "%s comes within %d ft of %s. Use the readied %s attack?" % [mover.name, rng_ft, r.name, p.name]):
			r.reaction_used = true
			r.erase("readied")
			add_log("attack", "%s's readied attack goes off against %s!" % [r.name, mover.name])
			weapon_attack(r, mover, p, {})
			if mover.dead or mover.hp <= 0:
				return


## War Caster: cast a cantrip at `mover` instead of an opportunity attack. EngineMagic fills this in.
func war_caster_strike(_r: Dictionary, _mover: Dictionary) -> bool:
	return false


## Polearm Master: an opportunity attack when an enemy enters the polearm's reach.
func _polearm_attacks(mover: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if not in_combat():
		return
	for r in combatants():
		if r.id == mover.id or not r.features.has("polearmMaster") or not hostile(r, mover) or not can_react(r) or r.hp <= 0:
			continue
		for p in r.attacks:
			if p.get("weapon_id", "") in Builder.POLEARMS and p.range == "melee" and not p.get("bonus_only", false):
				if Grid.distance(state, r, mover, null, from) > p.reach and Grid.distance(state, r, mover, null, to) <= p.reach and can_see(r, mover) \
						and decide(r, "%s enters %s's reach. Make a Polearm Master opportunity attack with %s?" % [mover.name, r.name, p.name]):
					r.reaction_used = true
					add_log("attack", "Polearm Master: %s strikes %s as it closes in!" % [r.name, mover.name])
					weapon_attack(r, mover, p, {"opportunity": true})
				break
		if mover.dead or mover.hp <= 0:
			return


## Forced movement straight away from `from_c`; doesn't provoke opportunity attacks.
func push_creature(t: Dictionary, from_c: Dictionary, ft: int) -> void:
	if t.get("mounted_on", "") != "":
		# shortcut: a push can't move a rider out of the saddle (knocking it prone can); rule it by hand if needed.
		add_log("info", "%s stays in the saddle." % t.name)
		return
	var v := Grid.center(t) - Grid.center(from_c)
	var step := Vector2i(signi(roundi(v.x * 10)), signi(roundi(v.y * 10)))
	if absf(v.x) > absf(v.y) * 2.4:
		step.y = 0
	elif absf(v.y) > absf(v.x) * 2.4:
		step.x = 0
	if step == Vector2i.ZERO:
		step = Vector2i(1, 0)
	var start: Vector2i = t.pos
	for i in ft / Grid.FT:
		var nxt: Vector2i = t.pos + step
		var blocked := false
		for f in Grid.footprint(t, nxt):
			if Grid.cell_at(state.map, f.x, f.y) == Grid.WALL:
				blocked = true
			for o in combatants():
				if o.id != t.id and o.id != t.get("rider", "") and not o.dead and Grid.footprint(o).has(f):
					blocked = true
		if blocked:
			break
		t.pos = nxt
	if t.pos != start:
		events.append({"kind": "move", "id": t.id, "path": [start, t.pos]})
		add_log("info", "%s is pushed %d ft." % [t.name, Grid.grid_distance(t.pos.x - start.x, t.pos.y - start.y, state.settings.diagonal)])
		var r := get_c(t.get("rider", ""))
		if not r.is_empty():
			_carry_rider(t)
			events.append({"kind": "move", "id": r.id, "path": [start, t.pos]})
			if not roll_save(r, "dex", 10, {"label": "staying mounted"}).success:
				add_log("info", "%s is thrown from %s." % [r.name, t.name])
				unseat(r, true)


# ---------------- Mounted combat (PHB) ----------------

## Who actually moves: a rider on a controlled mount moves the mount; everyone else moves themselves.
func mover_of(c: Dictionary) -> Dictionary:
	var m := get_c(c.get("mounted_on", ""))
	return m if m.get("controlled", false) else c


## Domesticated mounts (horses, ponies, mastiffs...) are trained to accept a rider who controls them;
## any other willing creature, or another player's character, acts independently.
func trainable_mount(m: Dictionary) -> bool:
	return m.traits.has("trainedMount") and m.kind != "pc"


func mount_error(r: Dictionary, m: Dictionary) -> String:
	if m.is_empty() or m.dead or m.id == r.id:
		return "Choose a creature to ride."
	if r.get("mounted_on", "") != "" or r.get("rider", "") != "":
		return "%s is already part of a mount and rider." % r.name
	if m.get("rider", "") != "" or m.get("mounted_on", "") != "":
		return "%s already has a rider." % m.name
	if hostile(r, m) or incapacitated(m):
		return "%s isn't a willing mount." % m.name
	if Grid.size_index(m.csize) <= Grid.size_index(r.csize):
		return "A mount must be at least one size larger than its rider."
	if dist(r, m) > 5:
		return "%s must be within 5 ft." % m.name
	var cost := speed_of(r) / 2
	if speed_of(r) == 0 or has_cond(r, "prone") or movement_left(r) < cost:
		return "Mounting costs %d ft of movement (half your speed)." % cost
	return ""


## Mount up (half your speed). A controlled mount's initiative changes to match yours: it leaves the turn order,
## acts on your turns (move, Dash, Disengage or Dodge only), and can act on the turn you mount it.
func mount_up(r: Dictionary, m: Dictionary) -> String:
	var err := mount_error(r, m)
	if err != "":
		return err
	if in_combat():
		r.turn.movement_used += speed_of(r) / 2
	r.mounted_on = m.id
	m.rider = r.id
	var from: Vector2i = r.pos
	_carry_rider(m)
	events.append({"kind": "move", "id": r.id, "path": [from, r.pos]})
	if trainable_mount(m):
		m.controlled = true
		m.initiative = r.initiative
		var order: Array = state.combat.order
		if order.has(m.id) and current_id() != m.id:
			var cur := current_id()
			order.erase(m.id)
			state.combat.turn_index = order.find(cur)
		if in_combat():
			m.turn = Stats.fresh_turn()
		add_log("info", "%s mounts %s and takes the reins." % [r.name, m.name])
	else:
		add_log("info", "%s climbs onto %s, which acts on its own." % [r.name, m.name])
	return ""


func dismount(r: Dictionary) -> String:
	if r.get("mounted_on", "") == "":
		return "%s isn't mounted." % r.name
	var cost := speed_of(r) / 2
	if speed_of(r) == 0 or movement_left(r) < cost:
		return "Dismounting costs %d ft of movement (half your speed)." % cost
	if in_combat():
		r.turn.movement_used += cost
	add_log("info", "%s dismounts." % r.name)
	unseat(r, false)
	return ""


## Takes a rider off its mount into the nearest open space, landing prone if `prone`.
## A controlled mount goes back into the turn order right after its former rider.
func unseat(r: Dictionary, prone: bool) -> void:
	var m := get_c(r.get("mounted_on", ""))
	r.mounted_on = ""
	if not m.is_empty():
		m.rider = ""
		if m.get("controlled", false):
			m.controlled = false
			var order: Array = state.combat.order
			if in_combat() and not order.has(m.id) and not m.dead:
				var cur := current_id()
				order.insert(order.find(r.id) + 1, m.id)
				state.combat.turn_index = order.find(cur)
	var from: Vector2i = r.pos
	r.pos = call("free_spot", r, r.pos)
	events.append({"kind": "move", "id": r.id, "path": [from, r.pos]})
	if prone and not r.dead:
		knock_prone(r, true)
	check_fall(r)


## A mount knocked prone (or killed) spills its rider: the rider can use its reaction to land on its feet.
func mount_falls(m: Dictionary) -> void:
	var r := get_c(m.get("rider", ""))
	if r.is_empty():
		return
	var feet := can_react(r) and decide(r, "%s goes down. Use your reaction to dismount and land on your feet?" % m.name)
	if feet:
		r.reaction_used = true
	add_log("info", "%s %s." % [r.name, "leaps clear and lands on their feet" if feet else "falls off %s and lands prone" % m.name])
	unseat(r, not feet)


## Called when a creature gains a condition: a rider knocked prone saves (DC 10 Dex) or falls off.
func saddle_check(c: Dictionary) -> void:
	if not has_cond(c, "prone"):
		return
	if c.get("rider", "") != "":
		mount_falls(c)
	if c.get("mounted_on", "") != "" and not roll_save(c, "dex", 10, {"label": "staying mounted"}).success:
		add_log("info", "%s falls off %s." % [c.name, get_c(c.mounted_on).name])
		unseat(c, true)


## Mounted Combatant: the rider can make an attack aimed at its mount target the rider instead.
func mount_guard(a: Dictionary, t: Dictionary) -> Dictionary:
	var r := get_c(t.get("rider", ""))
	if r.is_empty() or r.id == a.id or not r.features.has("mountedCombatant") or incapacitated(r) \
			or not decide(r, "%s attacks %s. Take the attack yourself (Mounted Combatant)?" % [a.name, t.name], false):
		return t
	add_log("info", "%s draws the attack meant for %s." % [r.name, t.name])
	return r


func _carry_rider(m: Dictionary) -> void:
	var r := get_c(m.get("rider", ""))
	if not r.is_empty():
		# shortcut: the rider sits in the mount's first square, so reach is measured from there, not the whole mount.
		r.pos = m.pos
		r.alt = m.get("alt", 0)


# ---------------- Grapple & Shove ----------------

func _contest_check(a: Dictionary, t: Dictionary, label: String) -> bool:
	var ra := roll_check(a, "str", "athletics", {"quiet": true})
	var use := "athletics" if skill_mod(t, "athletics") >= skill_mod(t, "acrobatics") else "acrobatics"
	var rt := roll_check(t, Stats.SKILLS[use], use, {"quiet": true})
	var won: bool = ra.total > rt.total
	var loser: Dictionary = t if won else a
	if loser.features.has("lucky") and res_left(loser, "luck") > 0 \
			and decide(loser, "%s loses the contest (%d vs %d). Spend a luck point to roll again?" % [loser.name, mini(ra.total, rt.total), maxi(ra.total, rt.total)]):
		spend_res(loser, "luck")
		var nr := roll_check(loser, "str", "athletics", {"quiet": true}) if loser == a else roll_check(t, Stats.SKILLS[use], use, {"quiet": true})
		if loser == a:
			ra = nr if nr.total > ra.total else ra
		else:
			rt = nr if nr.total > rt.total else rt
		won = ra.total > rt.total
	add_log("roll", "%s %s %s: Athletics %d vs %s %d — %s" % [a.name, label, t.name, ra.total, Stats.skill_label(use), rt.total, "success" if won else "failure"],
		"%s / %s" % [ra.text, rt.text], a.name)
	return won


func grapple_error(a: Dictionary, t: Dictionary) -> String:
	if t.is_empty() or t.dead or t.id == a.id:
		return "Choose a creature to grapple."
	if dist(a, t) > 5:
		return "%s must be within 5 ft." % t.name
	if Grid.size_index(t.csize) > Grid.size_index(a.csize) + 1:
		return "%s is too large to grapple or shove." % t.name
	return ""


## `bonus`: Tavern Brawler's grapple after an unarmed hit, or Shield Master's shove after the Attack action.
func _bonus_contest(a: Dictionary, ok: bool, why: String) -> String:
	if not in_combat() or not is_turn_of(a):
		return "Only on your turn in combat."
	if not a.turn.bonus:
		return "Bonus action already used this turn."
	if not ok:
		return why
	a.turn.bonus = false
	return ""


func do_grapple(a: Dictionary, t: Dictionary, bonus: bool = false) -> String:
	var err := grapple_error(a, t)
	if err == "":
		err = _bonus_contest(a, a.features.has("tavernBrawler") and a.fdata.get("brawler_turn", -1) == state.turn_counter,
			"Tavern Brawler: grapple as a bonus action after hitting with an unarmed strike this turn.") if bonus else use_attack_slot(a, {})
	if err != "":
		return err
	if has_tag(t, "grapple") and find_effect(t, "grapple").source_id == a.id:
		return "You're already grappling %s." % t.name
	a.hidden = 0
	if t.cond_immunities.has("grappled") or not _contest_check(a, t, "tries to grapple"):
		return ""
	add_effect({"name": "Grappled", "tag": "grapple", "conditions": ["grappled"]}, a.id, t.id)
	add_log("info", "%s grapples %s." % [a.name, t.name])
	return ""


func do_shove(a: Dictionary, t: Dictionary, mode: String, bonus: bool = false) -> String:
	var err := grapple_error(a, t)
	if err == "":
		err = _bonus_contest(a, a.features.has("shieldMaster") and a.shield and a.turn.attack_action_taken,
			"Shield Master: shove as a bonus action after taking the Attack action, with a shield.") if bonus else use_attack_slot(a, {})
	if err != "":
		return err
	a.hidden = 0
	if not _contest_check(a, t, "shoves"):
		return ""
	if mode == "prone":
		knock_prone(t)
	else:
		push_creature(t, a, 5)
	return ""


# ---------------- Standard actions ----------------

func bonus_actions_allowed(c: Dictionary) -> Array:
	var out := []
	if c.features.has("cunningAction"):
		out.append_array(["dash", "disengage", "hide"])
	if c.traits.has("nimbleEscape"):
		out.append_array(["disengage", "hide"])
	if c.features.has("vanish") and not out.has("hide"):
		out.append("hide")
	if c.traits.has("aggressive"):
		out.append("dash")
	return out


func do_action(c: Dictionary, action: String, target_id: String, via: String) -> String:
	var t := get_c(target_id)
	if action == "standUp":
		return stand_up(c)
	var kind := "bonus" if via == "bonus" else "action"
	if kind == "bonus" and not bonus_actions_allowed(c).has(action):
		return "%s can't %s as a bonus action." % [c.name, action]
	var haste: bool = kind == "action" and action in ["dash", "disengage", "hide"] and in_combat() and not incapacitated(c) \
		and c.turn.actions <= 0 and c.turn.haste_action
	var err := "" if haste else economy_error(c, kind)
	if err != "":
		return err
	if c.surprised and in_combat():
		return "%s is surprised and can't act this turn." % c.name
	match action:
		"dash":
			if in_combat():
				c.turn.dashes += 1
				if kind == "action":
					c.turn["dashed_action"] = true
			add_log("info", "%s dashes." % c.name)
		"disengage":
			c.turn.disengaged = true
			add_log("info", "%s disengages." % c.name)
		"dodge":
			add_effect({"name": "Dodging", "tag": "dodge", "mods": {"dodge": true}, "expires_on": {"who": "source", "phase": "start", "count": 1}}, c.id, c.id)
			add_log("info", "%s takes the Dodge action." % c.name)
		"help":
			if t.is_empty() or not hostile(c, t) or dist(c, t) > 5:
				return "Help: choose an enemy within 5 ft. Your allies' next attack against it has advantage."
			add_effect({"name": "Helped against", "tag": "help", "mods": {"help_side": c.side}, "expires_on": {"who": "source", "phase": "start", "count": 1}}, c.id, t.id)
			add_log("info", "%s helps the next attack against %s." % [c.name, t.name])
		"hide":
			var sneak: bool = c.features.has("supremeSneak") and (not in_combat() or c.turn.movement_used <= speed_of(c) / 2)
			var r := roll_check(c, "dex", "stealth", {"quiet": true, "adv": sneak})
			c.hidden = r.total
			var spotted := []
			for o in combatants():
				if hostile(o, c) and is_alive(o) and o.passive_perception >= r.total and Grid.line_of_sight(state, o, c):
					spotted.append(o.name)
			add_log("roll", "%s hides: Stealth %d%s" % [c.name, r.total, (" (spotted by " + ", ".join(spotted) + ")") if spotted.size() else ""], r.text, c.name)
		"escape":
			var done := false
			for e in effects_on(c):
				if e.get("tag", "") == "grapple":
					var g := get_c(e.source_id)
					var use := "athletics" if skill_mod(c, "athletics") >= skill_mod(c, "acrobatics") else "acrobatics"
					var rc := roll_check(c, Stats.SKILLS[use], use, {"quiet": true})
					var rg := roll_check(g, "str", "athletics", {"quiet": true})
					var ok: bool = rc.total > rg.total
					add_log("roll", "%s tries to escape %s's grapple: %d vs %d — %s" % [c.name, g.name, rc.total, rg.total, "escaped" if ok else "failed"], "%s / %s" % [rc.text, rg.text], c.name)
					if ok:
						remove_effect(e)
					done = true
					break
				if e.has("escape"):
					var esc: Dictionary = e.escape
					var ab: String = esc.abilities[0]
					for k in esc.abilities:
						if mod(c, k) > mod(c, ab):
							ab = k
					var rc := roll_check(c, ab, "athletics" if ab == "str" else ("acrobatics" if ab == "dex" else ""), {"quiet": true})
					var dc: int = esc.get("dc", 10)
					var ok: bool = rc.total >= dc
					add_log("roll", "%s tries to break free of %s: %d vs DC %d — %s" % [c.name, e.name, rc.total, dc, "free" if ok else "still stuck"], rc.text, c.name)
					if ok:
						remove_effect(e)
					done = true
					break
			if not done:
				return "%s isn't grappled or restrained by anything it can escape." % c.name
		"wake":
			if t.is_empty() or dist(c, t) > 5:
				return "Choose a sleeping creature within 5 ft."
			var woke := false
			for e in effects_on(t):
				if e.get("tag", "") == "sleep" or (e.get("ends_on_damage", false) and e.get("conditions", []).has("incapacitated")):
					remove_effect(e)
					woke = true
			if not woke:
				return "%s isn't magically asleep or entranced." % t.name
			add_log("info", "%s shakes %s awake." % [c.name, t.name])
		"stabilize":
			if t.is_empty() or dist(c, t) > 5 or not is_dying(t):
				return "Choose a dying creature within 5 ft."
			if c.features.has("healer"):
				t.stable = true
				t.hp = 1
				t.death_saves = {"successes": 0, "failures": 0}
				add_log("death", "%s uses a healer's kit: %s is stable at 1 HP." % [c.name, t.name])
				spend_economy(c, kind)
				return ""
			var r := roll_check(c, "wis", "medicine")
			if r.total >= 10:
				t.stable = true
				add_log("death", "%s stabilizes %s." % [c.name, t.name])
			else:
				add_log("info", "%s fails to stabilize %s." % [c.name, t.name])
		_:
			return "Unknown action."
	if haste:
		c.turn.haste_action = false
	else:
		spend_economy(c, kind)
	return ""


# ---------------- Wild Shape ----------------

## What a beast form replaces; the druid keeps everything else (Int/Wis/Cha, skills, saves, features).
const WILD_SHAPE_KEYS := ["hp", "max_hp", "ac", "abilities", "attacks", "multiattack", "attacks_per_action", "base_speed",
	"csize", "ctype", "darkvision", "blindsight", "traits", "speeds"]


func start_wild_shape(c: Dictionary, beast_id: String) -> void:
	var b := Builder.build_monster(beast_id, "wild_shape")
	var saved := {}
	for k in WILD_SHAPE_KEYS:
		var v = c.get(k, {})
		saved[k] = v.duplicate(true) if v is Dictionary or v is Array else v
		c[k] = b[k]
	for k in ["int", "wis", "cha"]:
		c.abilities[k] = saved.abilities[k]
	c.darkvision = maxi(saved.darkvision, b.darkvision)
	saved["beast"] = b.name
	saved["mini"] = c.get("mini", "")
	c["mini"] = beast_id  # the token shows the beast's mini
	c.fdata["wild_shape"] = saved
	# shortcut: the form lasts until it drops to 0 HP, the druid reverts or rests; the half-level-hours limit isn't tracked.
	add_log("info", "%s wild shapes into a %s (%d HP)." % [c.name, b.name, c.hp])
	check_fall(c)


func end_wild_shape(c: Dictionary, reason: String = "") -> void:
	var saved: Dictionary = c.fdata.get("wild_shape", {})
	if saved.is_empty():
		return
	c.fdata.erase("wild_shape")
	for k in WILD_SHAPE_KEYS:
		c[k] = saved[k]
	if saved.mini == "":
		c.erase("mini")
	else:
		c.mini = saved.mini
	add_log("info", "%s returns to their normal form%s." % [c.name, reason])
	check_fall(c)
