class_name Grid
extends RefCounted
## Grid geometry: distances, footprints, line of sight, cover, pathfinding and areas of effect.
## One square = 5 feet. A creature's `pos` is the top-left square of its footprint.

const FT := 5
const FLOOR := 0
const WALL := 1
const DIFFICULT := 2
# Light levels. A map's painted `light` layer stores level + 1 (0 = use the ambient light).
const DARK := 0
const DIM := 1
const BRIGHT := 2
const AMBIENT := {"dark": DARK, "dim": DIM, "bright": BRIGHT}
const SIZES := ["tiny", "small", "medium", "large", "huge", "gargantuan"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const EPS := 0.001


static func size_cells(sz: String) -> int:
	match sz:
		"large": return 2
		"huge": return 3
		"gargantuan": return 4
	return 1


static func size_index(sz: String) -> int:
	return SIZES.find(sz)


static func footprint(c: Dictionary, at = null) -> Array:
	var p: Vector2i = c.pos if at == null else at
	var n := size_cells(c.csize)
	var out := []
	for dy in n:
		for dx in n:
			out.append(Vector2i(p.x + dx, p.y + dy))
	return out


static func in_bounds(map: Dictionary, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < map.width and y < map.height


## Out-of-bounds squares behave like walls.
static func cell_at(map: Dictionary, x: int, y: int) -> int:
	if not in_bounds(map, x, y):
		return WALL
	return map.cells[y * map.width + x]


## Distance in feet for a square offset, honouring the diagonal rule ("5" or "5-10-5").
static func grid_distance(dx: int, dy: int, rule: String) -> int:
	var ax := absi(dx)
	var ay := absi(dy)
	var diag := mini(ax, ay)
	var straight := maxi(ax, ay) - diag
	if rule == "5":
		return (diag + straight) * FT
	return (diag + diag / 2 + straight) * FT


static func _gap(a_pos: Vector2i, a_n: int, b_pos: Vector2i, b_n: int) -> Vector2i:
	var dx := maxi(0, maxi(b_pos.x - (a_pos.x + a_n - 1), a_pos.x - (b_pos.x + b_n - 1)))
	var dy := maxi(0, maxi(b_pos.y - (a_pos.y + a_n - 1), a_pos.y - (b_pos.y + b_n - 1)))
	return Vector2i(dx, dy)


## Feet between two creatures' nearest squares. Adjacent creatures are 5 ft apart.
static func distance(state: Dictionary, a: Dictionary, b: Dictionary, a_pos = null, b_pos = null) -> int:
	var g := _gap(a.pos if a_pos == null else a_pos, size_cells(a.csize), b.pos if b_pos == null else b_pos, size_cells(b.csize))
	return grid_distance(g.x, g.y, state.settings.diagonal)


static func distance_to_cell(state: Dictionary, a: Dictionary, cell: Vector2i, a_pos = null) -> int:
	var g := _gap(a.pos if a_pos == null else a_pos, size_cells(a.csize), cell, 1)
	return grid_distance(g.x, g.y, state.settings.diagonal)


static func center(c: Dictionary, at = null) -> Vector2:
	var p: Vector2i = c.pos if at == null else at
	var n := size_cells(c.csize)
	return Vector2(p.x + n / 2.0, p.y + n / 2.0)


# ---------- Line of sight ----------

## Liang–Barsky: does the segment pass through the open rectangle?
static func segment_hits_rect(a: Vector2, b: Vector2, r0: Vector2, r1: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r0.x, r1.x - a.x, a.y - r0.y, r1.y - a.y]
	for i in 4:
		if p[i] == 0.0:
			if q[i] < 0.0:
				return false
		else:
			var t: float = q[i] / p[i]
			if p[i] < 0.0:
				if t > t1:
					return false
				t0 = maxf(t0, t)
			else:
				if t < t0:
					return false
				t1 = minf(t1, t)
	return t0 < t1


## True if a wall square lies across the segment (coordinates in square units).
static func segment_blocked(map: Dictionary, a: Vector2, b: Vector2) -> bool:
	for y in range(floori(minf(a.y, b.y)), floori(maxf(a.y, b.y)) + 1):
		for x in range(floori(minf(a.x, b.x)), floori(maxf(a.x, b.x)) + 1):
			if cell_at(map, x, y) != WALL:
				continue
			# Only shrink edges facing open floor, so lines can't slip along the seam between two walls.
			var r0 := Vector2(x + (0.0 if cell_at(map, x - 1, y) == WALL else EPS), y + (0.0 if cell_at(map, x, y - 1) == WALL else EPS))
			var r1 := Vector2(x + 1 - (0.0 if cell_at(map, x + 1, y) == WALL else EPS), y + 1 - (0.0 if cell_at(map, x, y + 1) == WALL else EPS))
			if segment_hits_rect(a, b, r0, r1):
				return true
	return false


static func line_of_sight(state: Dictionary, a: Dictionary, b: Dictionary, a_pos = null) -> bool:
	for ca in footprint(a, a_pos):
		for cb in footprint(b):
			if not segment_blocked(state.map, Vector2(ca) + Vector2(0.5, 0.5), Vector2(cb) + Vector2(0.5, 0.5)):
				return true
	return false


## Squares the viewers can see for fog of war, as 1 + the light level they see there (0 = unseen).
## Bresenham lines from each viewer's centre square; walls block what's behind them but are themselves
## visible, and diagonal seams don't leak. Dark squares are only seen within darkvision, magical
## darkness can't be seen into or through, and blindsight perceives (as dim) regardless of light.
static func visible_cells(state: Dictionary, viewers: Array) -> PackedByteArray:
	var map: Dictionary = state.map
	var w: int = map.width
	var light := light_map(state)
	var dark := magic_dark(state)
	var out := PackedByteArray()
	out.resize(w * map.height)
	for v in viewers:
		var n := size_cells(v.csize)
		var o: Vector2i = v.pos + Vector2i(n / 2, n / 2)
		for y in map.height:
			for x in w:
				var i: int = y * w + x
				var cell := Vector2i(x, y)
				if out[i] == BRIGHT + 1:
					continue
				var lv := _with_darkvision(state, v, cell, light[i], dark)
				var sees := lv > DARK or footprint(v).has(cell)
				var blind: bool = v.get("blindsight", 0) > 0 and distance_to_cell(state, v, cell) <= v.blindsight
				if blind:
					lv = maxi(lv, DIM)
				if lv + 1 > out[i] and (sees or blind) and _clear_line(map, o, cell, {} if blind else dark):
					out[i] = lv + 1
	return out


## Squares inside magical darkness (the Darkness spell), as a set.
static func magic_dark(state: Dictionary) -> Dictionary:
	var out := {}
	for e in state.get("effects", []):
		if e.get("tag", "") == "darkness":
			for p in e.get("cells", []):
				out[p] = true
	return out


## Is the view from `a` to `b` free of magical darkness (which nothing sees through)?
static func sight_clear(state: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	var dark := magic_dark(state)
	if dark.is_empty():
		return true
	var n := size_cells(a.csize)
	var o: Vector2i = a.pos + Vector2i(n / 2, n / 2)
	for cb in footprint(b):
		if _clear_line(state.map, o, cb, dark):
			return true
	return false


## Light level of one square: painted or ambient light, raised by creatures' light sources.
static func light_at(state: Dictionary, cell: Vector2i) -> int:
	if magic_dark(state).has(cell):
		return DARK
	var lv := _base_light(state, cell)
	for c in state.combatants.values():
		if lv == BRIGHT:
			break
		lv = maxi(lv, _source_light(state, c, cell))
	return lv


## Light level of every square (row-major).
static func light_map(state: Dictionary) -> PackedByteArray:
	var map: Dictionary = state.map
	var out := PackedByteArray()
	out.resize(map.width * map.height)
	for y in map.height:
		for x in map.width:
			out[y * map.width + x] = _base_light(state, Vector2i(x, y))
	for c in state.combatants.values():
		var l: Dictionary = c.get("light", {})
		if l.is_empty():
			continue
		var r: int = (l.bright + l.dim) / FT + size_cells(c.csize)
		for y in range(maxi(0, c.pos.y - r), mini(map.height, c.pos.y + r + 1)):
			for x in range(maxi(0, c.pos.x - r), mini(map.width, c.pos.x + r + 1)):
				var i: int = y * map.width + x
				out[i] = maxi(out[i], _source_light(state, c, Vector2i(x, y)))
	for p in magic_dark(state):
		if in_bounds(map, p.x, p.y):
			out[p.y * map.width + p.x] = DARK
	return out


## The light level `viewer` effectively sees at `cell`: darkvision treats dim as bright and dark as dim.
static func seen_light(state: Dictionary, viewer: Dictionary, cell: Vector2i) -> int:
	return _with_darkvision(state, viewer, cell, light_at(state, cell), magic_dark(state))


static func _with_darkvision(state: Dictionary, viewer: Dictionary, cell: Vector2i, lv: int, dark: Dictionary) -> int:
	if dark.has(cell):
		return DARK  # darkvision can't see through magical darkness
	if lv < BRIGHT and viewer.get("darkvision", 0) > 0 and distance_to_cell(state, viewer, cell) <= viewer.darkvision:
		return lv + 1
	return lv


static func _base_light(state: Dictionary, cell: Vector2i) -> int:
	var painted: Array = state.map.get("light", [])
	var i: int = cell.y * state.map.width + cell.x
	if i < painted.size() and int(painted[i]) > 0:
		return int(painted[i]) - 1
	return AMBIENT.get(state.settings.get("light", "bright"), BRIGHT)


## How brightly creature `c`'s light source (torch, lantern...) lights `cell`. Walls block light.
static func _source_light(state: Dictionary, c: Dictionary, cell: Vector2i) -> int:
	var l: Dictionary = c.get("light", {})
	if l.is_empty():
		return DARK
	var d := distance_to_cell(state, c, cell)
	if d > l.bright + l.dim:
		return DARK
	var n := size_cells(c.csize)
	if not _clear_line(state.map, c.pos + Vector2i(n / 2, n / 2), cell):
		return DARK
	return BRIGHT if d <= l.bright else DIM


## `dark`: squares (magical darkness) that block sight like walls, except the end square itself.
static func _clear_line(map: Dictionary, a: Vector2i, b: Vector2i, dark: Dictionary = {}) -> bool:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	while true:
		if x == b.x and y == b.y:
			return true
		if (x != a.x or y != a.y) and (cell_at(map, x, y) == WALL or dark.has(Vector2i(x, y))):
			return false
		var e2 := 2 * err
		var nx := x
		var ny := y
		if e2 >= dy:
			err += dy
			nx += sx
		if e2 <= dx:
			err += dx
			ny += sy
		if nx != x and ny != y and cell_at(map, nx, y) == WALL and cell_at(map, x, ny) == WALL:
			return false  # squeezing diagonally between two walls
		x = nx
		y = ny
	return true


static func line_of_effect(map: Dictionary, from: Vector2, cell: Vector2i) -> bool:
	return not segment_blocked(map, from, Vector2(cell) + Vector2(0.5, 0.5))


static func _corners(cells: Array) -> Array:
	var seen := {}
	var out := []
	for c in cells:
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var k: Vector2i = c + o
			if not seen.has(k):
				seen[k] = true
				out.append(Vector2(k))
	return out


## DMG grid cover: choose the attacker corner giving the least cover and trace lines to the four
## corners of a target square. 1–2 blocked = half (+2), 3–4 = three-quarters (+5), all = total (-1).
## Intervening creatures give at most half cover.
static func cover(state: Dictionary, attacker: Dictionary, target: Dictionary, origins = null) -> int:
	var from: Array = _corners(footprint(attacker)) if origins == null else origins
	var blockers := []
	for o in state.combatants.values():
		if o.id != attacker.id and o.id != target.id and not o.dead:
			blockers.append_array(footprint(o))
	var best := -1  # -1 total, else 0/2/5; lower rank wins
	var rank := func(cv: int) -> int: return 3 if cv == -1 else (2 if cv == 5 else (1 if cv == 2 else 0))
	for o in from:
		for tc in footprint(target):
			var walls := 0
			var creature := false
			for t in _corners([tc]):
				if segment_blocked(state.map, o, t):
					walls += 1
				elif not creature:
					for b in blockers:
						if segment_hits_rect(o, t, Vector2(b.x + EPS, b.y + EPS), Vector2(b.x + 1 - EPS, b.y + 1 - EPS)):
							creature = true
							break
			var cv := -1 if walls >= 4 else (5 if walls >= 3 else (2 if walls >= 1 else 0))
			if creature and rank.call(cv) < 1:
				cv = 2
			if rank.call(cv) < rank.call(best):
				best = cv
			if best == 0:
				return 0
	return best


# ---------- Pathfinding ----------

static func hostile(a: Dictionary, b: Dictionary) -> bool:
	return a.side != b.side and a.side != "neutral" and b.side != "neutral"


## Squares inside a hostile aura (Spirit Guardians) count as difficult terrain for the mover.
static func hostile_aura_squares(state: Dictionary, mover: Dictionary) -> Dictionary:
	var out := {}
	for e in state.effects:
		var mods: Dictionary = e.get("mods", {})
		if not mods.has("aura"):
			continue
		var bearer: Dictionary = state.combatants.get(e.target_id, {})
		var source: Dictionary = state.combatants.get(e.source_id, {})
		if bearer.is_empty() or source.is_empty() or not hostile(source, mover):
			continue
		var r: int = mods.aura.radius / FT
		var n := size_cells(bearer.csize)
		for y in range(bearer.pos.y - r, bearer.pos.y + n + r):
			for x in range(bearer.pos.x - r, bearer.pos.x + n + r):
				if distance_to_cell(state, bearer, Vector2i(x, y)) <= mods.aura.radius:
					out[Vector2i(x, y)] = true
	return out


## Dijkstra over squares (tracking diagonal parity for 5-10-5).
## Returns {cells: {Vector2i: cost}, graph, ends: {Vector2i: node_key}} for squares the mover can end in.
## rules: cost_multiplier (crawling/dragging), ignore_creatures.
static func reachable(state: Dictionary, mover: Dictionary, budget: int, rules: Dictionary = {}) -> Dictionary:
	var map: Dictionary = state.map
	var n := size_cells(mover.csize)
	var mult: int = rules.get("cost_multiplier", 1)
	var ignore: bool = rules.get("ignore_creatures", false)
	var occupied := {}
	for o in state.combatants.values():
		if o.id == mover.id or o.dead:
			continue
		for f in footprint(o):
			occupied[f] = o
	var auras := hostile_aura_squares(state, mover)
	var nimble: bool = mover.traits.has("halflingNimbleness")
	var rule: String = state.settings.diagonal

	# Returns null if blocked, else [difficult, endable].
	var pass_info := func(x: int, y: int):
		var difficult := false
		var endable := true
		for dy in n:
			for dx in n:
				var cx := x + dx
				var cy := y + dy
				var cell := cell_at(map, cx, cy)
				if cell == WALL:
					return null
				if (cell == DIFFICULT and not rules.get("ignore_difficult", false)) or auras.has(Vector2i(cx, cy)):
					difficult = true
				if ignore:
					continue
				var occ = occupied.get(Vector2i(cx, cy))
				if occ != null:
					endable = false
					if hostile(mover, occ):
						var diff := absi(size_index(occ.csize) - size_index(mover.csize))
						var larger := size_index(occ.csize) > size_index(mover.csize)
						if diff < 2 and not (nimble and larger):
							return null
						difficult = true
		return [difficult, endable]

	var start_key := Vector3i(mover.pos.x, mover.pos.y, 0)
	var graph := {start_key: {"cost": 0, "prev": null}}
	var open := [[0, start_key]]  # simple binary heap of [cost, key]
	while not open.is_empty():
		var top: Array = _heap_pop(open)
		var cur: Vector3i = top[1]
		var cur_cost: int = top[0]
		if cur_cost > graph[cur].cost:
			continue
		for d in DIRS:
			var x: int = cur.x + d.x
			var y: int = cur.y + d.y
			var info = pass_info.call(x, y)
			if info == null:
				continue
			var diagonal: bool = d.x != 0 and d.y != 0
			if diagonal and pass_info.call(cur.x + d.x, cur.y) == null and pass_info.call(cur.x, cur.y + d.y) == null:
				continue  # can't squeeze between two walls
			var step := FT
			var parity := cur.z
			if diagonal and rule == "5-10-5":
				step = FT * 2 if cur.z == 1 else FT
				parity = 1 - cur.z
			step *= mult + (1 if info[0] else 0)
			var cost := cur_cost + step
			if cost > budget:
				continue
			var k := Vector3i(x, y, parity)
			if not graph.has(k) or cost < graph[k].cost:
				graph[k] = {"cost": cost, "prev": cur}
				_heap_push(open, [cost, k])
	var cells := {}
	var ends := {}
	for k in graph:
		var p := Vector2i(k.x, k.y)
		var info = pass_info.call(k.x, k.y)
		var is_start: bool = p == mover.pos
		if not is_start and (info == null or not info[1]):
			continue
		if not cells.has(p) or graph[k].cost < cells[p]:
			cells[p] = graph[k].cost
			ends[p] = k
	return {"cells": cells, "graph": graph, "ends": ends}


## Path (excluding the start square) with the cumulative cost at each step: [{pos, cost}].
static func path_to(reach: Dictionary, to: Vector2i) -> Array:
	if not reach.ends.has(to):
		return []
	var out := []
	var k = reach.ends[to]
	while k != null:
		var node: Dictionary = reach.graph[k]
		out.append({"pos": Vector2i(k.x, k.y), "cost": node.cost})
		k = node.prev
	out.reverse()
	out.pop_front()
	return out


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var j := (i - 1) / 2
		if h[j][0] <= h[i][0]:
			break
		var t = h[i]; h[i] = h[j]; h[j] = t
		i = j


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < h.size() and h[l][0] < h[m][0]:
				m = l
			if r < h.size() and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var t = h[i]; h[i] = h[m]; h[m] = t
			i = m
	return top


# ---------- Areas of effect ----------

## Squares covered by an area. spec: {shape: sphere|cube|cone|line, size, width, origin: self|point}.
## `point` is the square the caster aimed at.
static func area_cells(state: Dictionary, caster: Dictionary, spec: Dictionary, point: Vector2i) -> Array:
	var map: Dictionary = state.map
	var out := []
	var size_ft: int = spec.size
	var n := maxi(1, roundi(size_ft / float(FT)))
	var cc := center(caster)
	var cn := size_cells(caster.csize)
	var add := func(x: int, y: int, from: Vector2) -> void:
		if not in_bounds(map, x, y) or cell_at(map, x, y) == WALL:
			return
		if not line_of_effect(map, from, Vector2i(x, y)):
			return
		out.append(Vector2i(x, y))
	var inside_caster := func(x: int, y: int) -> bool:
		return x >= caster.pos.x and x < caster.pos.x + cn and y >= caster.pos.y and y < caster.pos.y + cn
	match spec.shape:
		"sphere":
			var self_origin: bool = spec.origin == "self"
			var o_pos: Vector2i = caster.pos if self_origin else point
			var o_n := cn if self_origin else 1
			var from: Vector2 = cc if self_origin else Vector2(point) + Vector2(0.5, 0.5)
			for y in range(o_pos.y - n, o_pos.y + o_n + n):
				for x in range(o_pos.x - n, o_pos.x + o_n + n):
					var g := _gap(o_pos, o_n, Vector2i(x, y), 1)
					if grid_distance(g.x, g.y, state.settings.diagonal) <= size_ft:
						if self_origin and not spec.get("include_self", false) and inside_caster.call(x, y):
							continue
						add.call(x, y, from)
		"cube":
			if spec.origin == "point":
				var x0 := point.x - (n - 1) / 2
				var y0 := point.y - (n - 1) / 2
				for y in range(y0, y0 + n):
					for x in range(x0, x0 + n):
						add.call(x, y, Vector2(point) + Vector2(0.5, 0.5))
			else:
				# Cube adjacent to the caster, pushed out toward the aimed square.
				var dirx := signi(roundi((point.x + 0.5 - cc.x) * 2))
				var diry := signi(roundi((point.y + 0.5 - cc.y) * 2))
				if dirx == 0 and diry == 0:
					dirx = 1
				var span := func(p: int, dir: int) -> Vector2i:
					if dir > 0:
						return Vector2i(p + cn, p + cn + n - 1)
					if dir < 0:
						return Vector2i(p - n, p - 1)
					var s0 := p + (cn - n) / 2
					return Vector2i(s0, s0 + n - 1)
				var xs: Vector2i = span.call(caster.pos.x, dirx)
				var ys: Vector2i = span.call(caster.pos.y, diry)
				for y in range(ys.x, ys.y + 1):
					for x in range(xs.x, xs.y + 1):
						if not inside_caster.call(x, y):
							add.call(x, y, cc)
		_:
			# Cone & line, measured from the caster's centre toward the aimed square.
			var v := Vector2(point) + Vector2(0.5, 0.5) - cc
			if v.length() < 0.01:
				v = Vector2(1, 0)
			v = v.normalized()
			var reach := n + cn / 2.0 - 0.5
			var half_angle := atan(0.5) + 0.01
			var half_width: float = (spec.get("width", FT) / float(FT)) / 2.0
			for y in range(floori(cc.y - reach - 1), ceili(cc.y + reach + 1) + 1):
				for x in range(floori(cc.x - reach - 1), ceili(cc.x + reach + 1) + 1):
					if inside_caster.call(x, y):
						continue
					var w := Vector2(x + 0.5, y + 0.5) - cc
					var along := w.dot(v)
					if along <= 0.0 or along > reach + 0.01:
						continue
					if spec.shape == "cone":
						if acos(minf(1.0, along / w.length())) <= half_angle:
							add.call(x, y, cc)
					elif absf(w.cross(v)) <= half_width + 0.01:
						add.call(x, y, cc)
	return out


static func creatures_in_cells(state: Dictionary, cells: Array) -> Array:
	var set := {}
	for c in cells:
		set[c] = true
	var out := []
	for c in state.combatants.values():
		if c.dead:
			continue
		for f in footprint(c):
			if set.has(f):
				out.append(c)
				break
	return out
