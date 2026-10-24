extends Node3D
## The 3D table: map geometry, tokens, highlight overlays, mouse picking and combat animations.

signal cell_pressed(cell: Vector2i, token_id: String)
signal cell_dragged(cell: Vector2i)
signal cell_released(cell: Vector2i)
signal cancel_pressed
signal hover_changed(cell: Vector2i, token_id: String)

const TokenScript := preload("res://scripts/ui/token.gd")
const RigScript := preload("res://scripts/ui/camera_rig.gd")
const DAMAGE_COLORS := {
	"fire": Color(1.0, 0.45, 0.1), "cold": Color(0.55, 0.85, 1.0), "lightning": Color(1.0, 0.95, 0.35),
	"thunder": Color(0.7, 0.5, 1.0), "radiant": Color(1.0, 0.9, 0.5), "necrotic": Color(0.35, 0.6, 0.3),
	"poison": Color(0.4, 0.9, 0.3), "acid": Color(0.7, 1.0, 0.2), "psychic": Color(1.0, 0.45, 0.8),
	"force": Color(0.6, 0.6, 1.0),
}

var rig: Node3D
var tokens: Dictionary = {}
var hover_cell := Vector2i(-999, -999)
var hover_token := ""
var _map_key := ""
var _bg_key := 0
var _bg: MeshInstance3D
const MAX_BG_SIZE := 8192  # biggest texture side; larger images are scaled down
var _map_root: Node3D
var _layers: Dictionary = {}
var _hover_marker: MeshInstance3D
var _cost_label: Label3D
var _guides: MeshInstance3D  # range/area outlines and measuring lines, redrawn by the HUD
var _guide_verts := PackedVector3Array()
var _guide_cols := PackedColorArray()
var _left_down := false
var _right_press := Vector2.ZERO
var _state: Dictionary = {}
var _fog_root: Node3D
var _fog_key := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.055, 0.05, 0.065)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.6)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.07, 0.09)
	e.fog_density = 0.006
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-40, 140, 0)
	fill.light_color = Color(0.5, 0.6, 1.0)
	fill.light_energy = 0.25
	add_child(fill)

	rig = RigScript.new()
	add_child(rig)
	_map_root = Node3D.new()
	add_child(_map_root)
	for layer in ["reach", "area", "path", "paint", "targets"]:
		_layers[layer] = _make_layer(0.012 + _layers.size() * 0.003)
	_hover_marker = MeshInstance3D.new()
	var hm := PlaneMesh.new()
	hm.size = Vector2(0.98, 0.98)
	_hover_marker.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.albedo_color = Color(1, 1, 1, 0.18)
	_hover_marker.material_override = hmat
	_hover_marker.visible = false
	add_child(_hover_marker)
	_cost_label = Label3D.new()
	_cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cost_label.no_depth_test = true
	_cost_label.fixed_size = true
	_cost_label.pixel_size = 0.0012
	_cost_label.font_size = 28
	_cost_label.outline_size = 10
	_cost_label.modulate = Color(1, 0.9, 0.5)
	_cost_label.visible = false
	add_child(_cost_label)
	_guides = MeshInstance3D.new()
	_guides.mesh = ImmediateMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.vertex_color_use_as_albedo = true
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_guides.material_override = gmat
	_guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guides)


func _make_layer(y: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.9, 0.9)
	mm.mesh = quad
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mmi.material_override = mat
	mmi.position.y = y
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func set_layer(layer: String, cells: Array, color: Color) -> void:
	var mm: MultiMesh = _layers[layer].multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x + 0.5, 0, c.y + 0.5)))
		mm.set_instance_color(i, color)


func set_layer_colors(layer: String, cells: Array, colors: Array) -> void:
	var mm: MultiMesh = _layers[layer].multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i].x + 0.5, 0, cells[i].y + 0.5)))
		mm.set_instance_color(i, colors[i])


func clear_layer(layer: String) -> void:
	_layers[layer].multimesh.instance_count = 0


func show_cost(cell: Vector2i, text: String) -> void:
	show_label(Vector3(cell.x + 0.5, 0.6, cell.y + 0.5), text)


func show_label(pos: Vector3, text: String) -> void:
	_cost_label.visible = text != ""
	_cost_label.text = text
	_cost_label.position = pos


func clear_guides() -> void:
	_guide_verts.clear()
	_guide_cols.clear()
	_flush_guides()


## A flat band from `a` to `b`, `w` wide; vertical bands turn to face along x.
func guide_line(a: Vector3, b: Vector3, color: Color, w: float = 0.06) -> void:
	_band(a, b, color, w)
	_flush_guides()


## Outlines the border of a set of squares on the floor.
func outline_cells(cells: Array, color: Color) -> void:
	var inside := {}
	for c in cells:
		inside[c] = true
	var y := 0.035
	for c: Vector2i in cells:
		if not inside.has(c + Vector2i(0, -1)): _band(Vector3(c.x, y, c.y), Vector3(c.x + 1, y, c.y), color)
		if not inside.has(c + Vector2i(0, 1)): _band(Vector3(c.x, y, c.y + 1), Vector3(c.x + 1, y, c.y + 1), color)
		if not inside.has(c + Vector2i(-1, 0)): _band(Vector3(c.x, y, c.y), Vector3(c.x, y, c.y + 1), color)
		if not inside.has(c + Vector2i(1, 0)): _band(Vector3(c.x + 1, y, c.y), Vector3(c.x + 1, y, c.y + 1), color)
	_flush_guides()


func _band(a: Vector3, b: Vector3, color: Color, w: float = 0.05) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	side = (Vector3.RIGHT if side.length() < 0.01 else side.normalized()) * w / 2
	a -= dir * w / 2
	b += dir * w / 2
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_guide_verts.append(v)
		_guide_cols.append(color)


func _flush_guides() -> void:
	var im: ImmediateMesh = _guides.mesh
	im.clear_surfaces()
	if _guide_verts.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _guide_verts.size():
		im.surface_set_color(_guide_cols[i])
		im.surface_add_vertex(_guide_verts[i])
	im.surface_end()


# ---------------- Map ----------------

func _rebuild_map(map: Dictionary) -> void:
	var key := "%d,%d,%d,%d" % [map.width, map.height, hash(map.cells), hash(map.get("props", []))]
	if key == _map_key:
		return
	_map_key = key
	for ch in _map_root.get_children():
		ch.queue_free()
	rig.bounds = Rect2(0, 0, map.width, map.height)
	var floors := []
	var rough := []
	var walls := []
	var low := []
	var doors := []
	var water := []
	for y in map.height:
		for x in map.width:
			var v := int(map.cells[y * map.width + x])
			match v:
				Grid.WALL: walls.append(Vector2i(x, y))
				Grid.DIFFICULT: rough.append(Vector2i(x, y))
				_: floors.append(Vector2i(x, y))
			if v == Grid.WATER:
				water.append(Vector2i(x, y))
			if v == Grid.LOW_WALL:
				low.append(Vector2i(x, y))
			elif v == Grid.DOOR or v == Grid.DOOR_OPEN:
				doors.append(Vector2i(x, y))
	var under := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(map.width + 40, map.height + 40)
	under.mesh = plane
	under.position = Vector3(map.width / 2.0, -0.09, map.height / 2.0)
	var umat := StandardMaterial3D.new()
	umat.albedo_color = Color(0.09, 0.08, 0.08)
	umat.roughness = 1.0
	under.material_override = umat
	_map_root.add_child(under)

	# Kenney Mini Dungeon pieces are one square each; see assets/kenney.
	var tiles := []
	var details := []
	for c in floors + rough:
		(details if hash(c) % 6 == 0 else tiles).append(_xf(c))
	_map_root.add_child(_kit_multimesh("mini-dungeon/floor", tiles))
	_map_root.add_child(_kit_multimesh("mini-dungeon/floor-detail", details))
	_map_root.add_child(_kit_multimesh("mini-dungeon/stones", rough.map(func(c): return _xf(c, hash(c) % 4))))
	_map_root.add_child(_kit_multimesh("mini-dungeon/wall", walls.map(func(c): return _xf(c))))
	_map_root.add_child(_kit_multimesh("mini-dungeon/wall", low.map(func(c): return _xf(c).scaled_local(Vector3(1, 0.4, 1)))))
	# Doors: the gate across the doorway when closed, swung against the hinge edge when open.
	var gates := []
	for c in doors:
		var across_x := Grid.cell_at(map, c.x - 1, c.y) == Grid.WALL or Grid.cell_at(map, c.x + 1, c.y) == Grid.WALL
		var basis := Basis() if across_x else Basis(Vector3.UP, PI / 2)
		var at := Vector3(c.x + 0.5, 0, c.y + 0.5)
		if int(map.cells[c.y * map.width + c.x]) == Grid.DOOR_OPEN:
			basis = basis.rotated(Vector3.UP, PI / 2)
			at += (Vector3(-0.4, 0, 0) if across_x else Vector3(0, 0, -0.4))
		gates.append(Transform3D(basis * Basis.from_scale(Vector3(1.25, 1.45, 1.0)), at))
	_map_root.add_child(_kit_multimesh("mini-dungeon/gate", gates))
	if not water.is_empty():
		var wm := MultiMesh.new()
		wm.transform_format = MultiMesh.TRANSFORM_3D
		var wp := PlaneMesh.new()
		wp.size = Vector2(1, 1)
		wm.mesh = wp
		wm.instance_count = water.size()
		for i in water.size():
			wm.set_instance_transform(i, Transform3D(Basis(), Vector3(water[i].x + 0.5, 0.03, water[i].y + 0.5)))
		var wmi := MultiMeshInstance3D.new()
		wmi.multimesh = wm
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.15, 0.4, 0.7, 0.72)
		wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wmat.roughness = 0.08
		wmat.metallic = 0.3
		wmi.material_override = wmat
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_map_root.add_child(wmi)
	for p in map.get("props", []):
		var prop := _prop(p.m)
		if prop != null:
			prop.position += Vector3(p.x + 0.5, p.h * 0.5, p.y + 0.5)
			prop.rotation.y = p.r * PI / 2
			_map_root.add_child(prop)

	# Grid lines.
	var lines := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in map.width + 1:
		im.surface_add_vertex(Vector3(x, 0.006, 0))
		im.surface_add_vertex(Vector3(x, 0.006, map.height))
	for y in map.height + 1:
		im.surface_add_vertex(Vector3(0, 0.006, y))
		im.surface_add_vertex(Vector3(map.width, 0.006, y))
	im.surface_end()
	lines.mesh = im
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.albedo_color = Color(0, 0, 0, 0.35)
	lines.material_override = lmat
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_map_root.add_child(lines)


const KIT_DIR := "res://assets/kenney/"


func _xf(c: Vector2i, quarter_turns: int = 0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, quarter_turns * PI / 2), Vector3(c.x + 0.5, 0, c.y + 0.5))


## One Kenney model drawn many times with its own textured material.
func _kit_multimesh(model: String, xforms: Array) -> MultiMeshInstance3D:
	var scene := (load(KIT_DIR + model + ".glb") as PackedScene).instantiate()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = (scene.find_children("*", "MeshInstance3D")[0] as MeshInstance3D).mesh
	scene.free()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _kit_tint(mm.mesh.surface_get_material(0))
	return mmi


const KIT_TINT := Color(0.66, 0.62, 0.56)
var _tinted := {}


## Kenney's bright pastels, dimmed and warmed to keep the table's dungeon mood and let minis stand out.
func _kit_tint(mat: Material) -> Material:
	if not _tinted.has(mat):
		var m: StandardMaterial3D = mat.duplicate()
		m.albedo_color *= KIT_TINT
		_tinted[mat] = m
	return _tinted[mat]


## A DM-placed prop ("kit/model"), centred on its square, or null if the model is missing.
func _prop(model: String) -> Node3D:
	var path := KIT_DIR + model + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	var scene: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(scene)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D"):
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _kit_tint(mi.mesh.surface_get_material(i)))
	# Furniture kit models sit on a corner, not their centre.
	if model.begins_with("furniture/"):
		var meshes := scene.find_children("*", "MeshInstance3D")
		var box: AABB = meshes[0].transform * meshes[0].get_aabb()
		for mi in meshes:
			box = box.merge(mi.transform * mi.get_aabb())
		scene.position = -Vector3(box.get_center().x, 0, box.get_center().z)
	return holder


func _multimesh(mesh: Mesh, cells: Array, y: float, color_fn: Callable) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector2i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x + 0.5, y, c.y + 0.5)))
		mm.set_instance_color(i, color_fn.call(c))
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mmi.material_override = mat
	return mmi


## The DM's battle map image, stretched over the whole grid.
func _update_background(state: Dictionary) -> void:
	var bg: Dictionary = state.get("background", {})
	var bytes := Net.background_bytes(state)
	var key := 0 if bytes.is_empty() else hash([bg.hash, state.map.width, state.map.height])
	if key == _bg_key:
		return
	_bg_key = key
	if _bg != null:
		_bg.queue_free()
		_bg = null
	if bytes.is_empty():
		return
	var img := RulesEngine.image_from_bytes(bytes)
	if img == null:
		return
	if maxi(img.get_width(), img.get_height()) > MAX_BG_SIZE:
		var f := float(MAX_BG_SIZE) / maxi(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * f), int(img.get_height() * f))
	img.generate_mipmaps()
	var plane := PlaneMesh.new()
	plane.size = Vector2(state.map.width, state.map.height)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 1.0
	_bg = MeshInstance3D.new()
	_bg.mesh = plane
	_bg.material_override = mat
	_bg.position = Vector3(state.map.width / 2.0, 0.003, state.map.height / 2.0)
	add_child(_bg)


# ---------------- Fog of war ----------------

## Fog of war and light: black blocks over unexplored squares, veils over remembered, dim and dark ones.
func _update_fog(state: Dictionary) -> void:
	var fog: Dictionary = state.get("fog", {})
	var w: int = state.map.width
	# Under fog a player gets what the party sees (1 + light level, 0 = unseen); otherwise show the real light.
	var light: PackedByteArray = Grid.light_map(state) if fog.is_empty() else fog.visible
	var magic_dark := Grid.magic_dark(state)
	var key := hash([light, fog.get("explored", null), w, magic_dark.keys()])
	if key == _fog_key:
		return
	_fog_key = key
	if _fog_root != null:
		_fog_root.queue_free()
		_fog_root = null
	var unseen := []
	var remembered := []
	var dim := []
	var dark := []
	var magic := []
	for i in light.size():
		var cell := Vector2i(i % w, i / w)
		var lv: int = light[i] if fog.is_empty() else light[i] - 1
		if fog.is_empty() and magic_dark.has(cell):
			magic.append(cell)
		elif lv < 0:
			(remembered if fog.explored[i] else unseen).append(cell)
		elif lv == Grid.DIM:
			dim.append(cell)
		elif lv == Grid.DARK:
			dark.append(cell)
	if unseen.size() + remembered.size() + dim.size() + dark.size() + magic.size() == 0:
		return
	_fog_root = Node3D.new()
	add_child(_fog_root)
	var block := BoxMesh.new()
	block.size = Vector3(1.01, 2.6, 1.01)  # tall enough to hide trees and towers
	var black := _multimesh(block, unseen, 1.25, func(_c): return Color(0.02, 0.02, 0.03))
	var bm: StandardMaterial3D = black.material_override
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_root.add_child(black)
	_fog_root.add_child(_veil(remembered, Color(0.0, 0.0, 0.02, 0.6)))
	_fog_root.add_child(_veil(dim, Color(0.02, 0.02, 0.08, 0.35)))
	_fog_root.add_child(_veil(dark, Color(0.0, 0.0, 0.03, 0.7)))
	_fog_root.add_child(_veil(magic, Color(0.0, 0.0, 0.0, 0.92)))


## A translucent shade lying on the floor of `cells`.
func _veil(cells: Array, color: Color) -> MultiMeshInstance3D:
	var veil := PlaneMesh.new()
	veil.size = Vector2(1.0, 1.0)
	var mm := _multimesh(veil, cells, 0.05, func(_c): return color)
	var m: StandardMaterial3D = mm.material_override
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mm


# ---------------- Tokens ----------------

## Brings the board in line with `state`, animating `events`.
func sync(state: Dictionary, eng: EngineBase, selected_id: String, targeted: Array, events: Array) -> void:
	_state = state
	_rebuild_map(state.map)
	_update_background(state)
	_update_fog(state)
	var current := eng.current_id()
	for id in tokens.keys():
		if not state.combatants.has(id):
			tokens[id].queue_free()
			tokens.erase(id)
	var animated := {}
	for ev in events:
		if ev.kind in ["move", "teleport"]:
			animated[ev.id] = true
	for id in state.combatants:
		var c: Dictionary = state.combatants[id]
		var t = tokens.get(id)
		var look := "%s/%s" % [c.get("mini", ""), c.csize]  # Wild Shape swaps both
		if t != null and t.get_meta("look", "") != look:
			t.queue_free()
			t = null
		if t == null:
			t = TokenScript.new()
			add_child(t)
			t.setup(c)
			t.set_meta("look", look)
			t.position = t.world_pos_for(c.pos)
			tokens[id] = t
		elif not animated.has(id) and t.position.distance_to(t.world_pos_for(c.pos)) > 0.01:
			t.position = t.world_pos_for(c.pos)
		t.refresh(c, eng, id == selected_id, id == current, targeted.has(id))
	_play(events)


func _play(events: Array) -> void:
	var delay := 0.0
	for ev in events:
		match ev.kind:
			"move":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func(): t.move_along(ev.path))
					delay += 0.14 * (ev.path.size() - 1)
			"teleport":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func(): t.teleport_to(ev.to))
			"attack":
				var a = tokens.get(ev.attacker_id)
				var t = tokens.get(ev.target_id)
				if a and t:
					if ev.ranged:
						_after(delay, func(): _projectile(a.position + Vector3(0, 0.7, 0), t.position + Vector3(0, 0.6, 0), Color(1, 0.95, 0.8)))
					else:
						_after(delay, func(): a.lunge(t.position))
					delay += 0.3
			"damage":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func():
						t.hit_flash()
						_float_text(t.position + Vector3(0, 1.2, 0), ("%d!" if ev.get("crit", false) else "%d") % ev.amount, Color(1, 0.35, 0.3) if not ev.get("crit", false) else Color(1, 0.8, 0.2)))
			"heal":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func(): _float_text(t.position + Vector3(0, 1.2, 0), "+%d" % ev.amount, Color(0.4, 1, 0.5)))
			"miss":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func(): _float_text(t.position + Vector3(0, 1.2, 0), "miss", Color(0.8, 0.8, 0.8)))
			"save":
				var t = tokens.get(ev.id)
				if t:
					_after(delay, func(): _float_text(t.position + Vector3(0, 1.55, 0), "save" if ev.success else "failed save", Color(0.6, 0.8, 1.0) if ev.success else Color(1, 0.6, 0.3), 0.7))
			"spell":
				var col: Color = DAMAGE_COLORS.get(ev.get("damage_type", ""), Color(0.7, 0.6, 1.0))
				var caster = tokens.get(ev.caster_id)
				if not ev.get("cells", []).is_empty():
					_after(delay, func(): _flash_cells(ev.cells, col))
				elif caster:
					for tid in ev.target_ids:
						var t = tokens.get(tid)
						if t and t != caster:
							_after(delay, func(): _projectile(caster.position + Vector3(0, 0.8, 0), t.position + Vector3(0, 0.6, 0), col))
				delay += 0.3
			"ping":
				_ping(ev.pos, ev.who)
			"death":
				pass


## A pulsing ring everyone sees, with who pinged.
func _ping(cell: Vector2i, who: String) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.5
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	ring.material_override = mat
	ring.position = Vector3(cell.x + 0.5, 0.15, cell.y + 0.5)
	add_child(ring)
	var tw := create_tween().set_loops(3)
	tw.tween_property(ring, "scale", Vector3(2.5, 1, 2.5), 0.6).from(Vector3(0.6, 1, 0.6))
	get_tree().create_timer(1.8).timeout.connect(ring.queue_free)
	_float_text(ring.position + Vector3(0, 0.8, 0), who, Color(1.0, 0.85, 0.3))


func _after(delay: float, fn: Callable) -> void:
	if delay <= 0.0:
		fn.call()
	else:
		get_tree().create_timer(delay).timeout.connect(fn)


func _float_text(pos: Vector3, text: String, color: Color, scale_f: float = 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016 * scale_f
	l.font_size = 40
	l.outline_size = 12
	l.modulate = color
	l.position = pos
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", pos + Vector3(0, 1.0, 0), 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _projectile(from: Vector3, to: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.08
	s.height = 0.16
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	m.material_override = mat
	m.position = from
	add_child(m)
	var tw := create_tween()
	tw.tween_property(m, "position", to, clampf(from.distance_to(to) * 0.03, 0.12, 0.4))
	tw.tween_callback(m.queue_free)


func _flash_cells(cells: Array, color: Color) -> void:
	var mmi := _make_layer(0.05)
	var mm := mmi.multimesh
	mm.instance_count = cells.size()
	for i in cells.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i].x + 0.5, 0, cells[i].y + 0.5)))
		mm.set_instance_color(i, Color(color, 0.75))
	var tw := create_tween()
	tw.tween_property(mmi, "transparency", 1.0, 0.9).set_delay(0.25)
	tw.tween_callback(mmi.queue_free)


func focus_on(id: String) -> void:
	var t = tokens.get(id)
	if t:
		rig.look_at_cell(t.position)


func center_camera(map: Dictionary) -> void:
	rig.look_at_cell(Vector3(map.width / 2.0, 0, map.height / 2.0), true)


# ---------------- Picking ----------------

func pick(screen_pos: Vector2) -> Dictionary:
	var cam: Camera3D = rig.camera
	var best := ""
	var best_d := INF
	for id in tokens:
		var t: Node3D = tokens[id]
		var dead: bool = _state.get("combatants", {}).get(id, {}).get("dead", false)
		var center := t.global_position + Vector3(0, 0.45 * t.cells, 0)
		if cam.is_position_behind(center):
			continue
		var sp := cam.unproject_position(center)
		var edge := cam.unproject_position(center + cam.global_transform.basis.x * 0.42 * t.cells)
		var radius := maxf(10.0, (edge - sp).length() * 1.15)
		var d := sp.distance_to(screen_pos) + (radius if dead else 0.0)
		if sp.distance_to(screen_pos) < radius and d < best_d:
			best_d = d
			best = id
	var cell := Vector2i(-999, -999)
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) > 0.0001:
		var hit := from + dir * (-from.y / dir.y)
		cell = Vector2i(floori(hit.x), floori(hit.z))
	return {"cell": cell, "token": best}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p := pick(event.position)
		if p.cell != hover_cell or p.token != hover_token:
			hover_cell = p.cell
			hover_token = p.token
			for id in tokens:
				tokens[id].hovered = id == hover_token
			_hover_marker.visible = Grid.in_bounds(_state.get("map", {"width": 0, "height": 0}), hover_cell.x, hover_cell.y)
			_hover_marker.position = Vector3(hover_cell.x + 0.5, 0.02, hover_cell.y + 0.5)
			hover_changed.emit(hover_cell, hover_token)
			if _left_down:
				cell_dragged.emit(hover_cell)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p := pick(mb.position)
			if mb.pressed:
				_left_down = true
				cell_pressed.emit(p.cell, p.token)
			else:
				_left_down = false
				cell_released.emit(p.cell)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_press = mb.position
			elif mb.position.distance_to(_right_press) < 6.0:
				cancel_pressed.emit()
