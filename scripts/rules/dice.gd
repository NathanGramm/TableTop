class_name Dice
extends RefCounted
## Dice rolling. All randomness goes through a RandomNumberGenerator so tests are deterministic.

const NORMAL := 0
const ADVANTAGE := 1
const DISADVANTAGE := -1

static var _term_re: RegEx
## Test hook: queued values are returned by the next die rolls instead of random ones.
static var forced: Array = []


static func die(rng: RandomNumberGenerator, sides: int) -> int:
	if not forced.is_empty():
		return clampi(int(forced.pop_front()), 1, sides)
	return rng.randi_range(1, sides)


static func _re() -> RegEx:
	if _term_re == null:
		_term_re = RegEx.new()
		_term_re.compile("([+-]?)(?:(\\d*)d(\\d+)(?:k([hl])(\\d+))?|(\\d+))")
	return _term_re


## Parses "2d6+1d4-1", "d20", "4d6kh3". Returns {ok, terms:[{sign,count,sides,keep,keep_n}], flat, error}.
static func parse(expr: String) -> Dictionary:
	var s := expr.replace(" ", "").to_lower()
	if s.is_empty():
		return {"ok": false, "error": "Empty dice expression"}
	var terms := []
	var flat := 0
	var pos := 0
	for m in _re().search_all(s):
		if m.get_start() != pos:
			return {"ok": false, "error": "Can't parse \"%s\"" % expr}
		if pos > 0 and m.get_string(1).is_empty():
			return {"ok": false, "error": "Can't parse \"%s\"" % expr}
		var sign := -1 if m.get_string(1) == "-" else 1
		if not m.get_string(3).is_empty():
			var count := 1 if m.get_string(2).is_empty() else int(m.get_string(2))
			var sides := int(m.get_string(3))
			if count > 100 or sides > 1000 or sides < 1:
				return {"ok": false, "error": "Too many dice"}
			var term := {"sign": sign, "count": count, "sides": sides, "keep": "", "keep_n": 0}
			if not m.get_string(4).is_empty():
				term.keep = m.get_string(4)
				term.keep_n = int(m.get_string(5))
			terms.append(term)
		else:
			flat += sign * int(m.get_string(6))
		pos = m.get_end()
	if pos != s.length():
		return {"ok": false, "error": "Can't parse \"%s\"" % expr}
	return {"ok": true, "terms": terms, "flat": flat}


static func is_valid(expr: String) -> bool:
	return parse(expr).ok


## Rolls an expression. opts: crit (double dice), reroll_low (Great Weapon Fighting).
## Returns {total, text, rolls}.
static func roll(rng: RandomNumberGenerator, expr: String, opts: Dictionary = {}) -> Dictionary:
	var p := parse(expr)
	if not p.ok:
		return {"total": 0, "text": "invalid(%s)" % expr, "rolls": []}
	var total: int = p.flat
	var parts := PackedStringArray()
	var all := []
	var reroll_low: int = opts.get("reroll_low", 0)
	var min_die: int = opts.get("min_die", 0)  # Elemental Adept: 1s count as 2s
	for t in p.terms:
		var count: int = t.count * (2 if opts.get("crit", false) else 1)
		var rolls := []
		var shown := PackedStringArray()
		for i in count:
			var r := die(rng, t.sides)
			if reroll_low > 0 and r <= reroll_low:
				var r2 := die(rng, t.sides)
				shown.append("%d→%d" % [r, r2])
				r = r2
			else:
				shown.append(str(r))
			if r < min_die:
				shown[-1] += "→%d" % min_die
				r = min_die
			rolls.append(r)
		var kept := rolls.duplicate()
		if t.keep != "":
			kept.sort()
			if t.keep == "h":
				kept.reverse()
			kept = kept.slice(0, t.keep_n)
		var sum := 0
		for k in kept:
			sum += k
		total += t.sign * sum
		all.append_array(rolls)
		var label := "%dd%d%s" % [count, t.sides, ("k%s%d" % [t.keep, t.keep_n]) if t.keep != "" else ""]
		var sign_txt := "-" if t.sign < 0 else ("+" if parts.size() > 0 else "")
		parts.append("%s%s[%s]" % [sign_txt, label, ", ".join(shown)])
	if p.flat != 0:
		parts.append("%s%d" % ["-" if p.flat < 0 else ("+" if parts.size() > 0 else ""), absi(p.flat)])
	return {"total": total, "text": " ".join(parts), "rolls": all}


## Rolls a d20 with advantage/disadvantage. `lucky` = halfling Lucky (reroll natural 1s).
## Returns {value, rolls, text, mode}.
static func d20(rng: RandomNumberGenerator, mode: int = NORMAL, lucky: bool = false) -> Dictionary:
	var a := _one(rng, lucky)
	if mode == NORMAL:
		return {"value": a[0], "rolls": [a[0]], "text": "d20[%s]" % a[1], "mode": mode}
	var b := _one(rng, lucky)
	var value: int = maxi(a[0], b[0]) if mode == ADVANTAGE else mini(a[0], b[0])
	return {"value": value, "rolls": [a[0], b[0]], "text": "d20[%s, %s %s]" % [a[1], b[1], "adv" if mode == ADVANTAGE else "dis"], "mode": mode}


static func _one(rng: RandomNumberGenerator, lucky: bool) -> Array:
	var r := die(rng, 20)
	if lucky and r == 1:
		var r2 := die(rng, 20)
		return [r2, "1→%d lucky" % r2]
	return [r, str(r)]


static func combine(adv: bool, dis: bool) -> int:
	if adv and not dis:
		return ADVANTAGE
	if dis and not adv:
		return DISADVANTAGE
	return NORMAL


static func average(expr: String) -> float:
	var p := parse(expr)
	if not p.ok:
		return 0.0
	var total := float(p.flat)
	for t in p.terms:
		total += t.sign * t.count * (t.sides + 1) / 2.0
	return total


static func max_value(expr: String) -> int:
	var p := parse(expr)
	if not p.ok:
		return 0
	var total: int = p.flat
	for t in p.terms:
		total += t.sign * t.count * t.sides
	return total


## "1d8" * 3 -> "3d8"
static func scale(expr: String, n: int) -> String:
	var p := parse(expr)
	if not p.ok or p.terms.size() != 1:
		return expr
	var t: Dictionary = p.terms[0]
	return "%dd%d" % [t.count * n, t.sides]


## Die size of the first term ("2d6" -> 6), used for Savage Attacks.
static func first_die(expr: String) -> String:
	var p := parse(expr)
	if not p.ok or p.terms.is_empty():
		return ""
	return "1d%d" % p.terms[0].sides


## Joins non-empty dice expressions: ["2d6", "", "1d8"] -> "2d6+1d8"
static func join(exprs: Array) -> String:
	var parts := PackedStringArray()
	for e in exprs:
		if str(e) != "":
			parts.append(str(e))
	return "+".join(parts)


static func fmt_mod(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)
