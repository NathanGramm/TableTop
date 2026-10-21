extends Node3D
## A creature on the board: team-coloured base, a pawn whose silhouette depends on creature
## type, a name/HP label, and rings for "selected", "current turn" and "targeted".

const PARTY_COLOR := Color(0.25, 0.55, 0.95)
const ENEMY_COLOR := Color(0.9, 0.22, 0.2)
const NEUTRAL_COLOR := Color(0.85, 0.75, 0.3)

var cid := ""
var cells := 1
var body: Node3D
var base_mat: StandardMaterial3D
var body_mat: StandardMaterial3D
var name_label: Label3D
var info_label: Label3D
var select_ring: MeshInstance3D
var turn_ring: MeshInstance3D
var target_ring: MeshInstance3D
var glow: OmniLight3D
var _pose := ""
var _tween: Tween
var _time := 0.0


func setup(c: Dictionary) -> void:
	cid = c.id
	cells = Grid.size_cells(c.csize)
	var r := 0.42 * cells
	var scale_f := 1.0 if cells == 1 else 0.75 * cells
	if c.csize in ["small", "tiny"]:
		scale_f = 0.8

	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r * 1.04
	cyl.height = 0.1
	cyl.radial_segments = 32
	base.mesh = cyl
	base.position.y = 0.05
	base_mat = StandardMaterial3D.new()
	base_mat.roughness = 0.4
	base_mat.metallic = 0.3
	base.material_override = base_mat
	add_child(base)

	body = Node3D.new()
	body.position.y = 0.1
	add_child(body)
	body_mat = StandardMaterial3D.new()
	body_mat.roughness = 0.55
	_build_body(c.ctype, scale_f)

	select_ring = _ring(r + 0.06, Color(1, 1, 1, 0.95))
	turn_ring = _ring(r + 0.14, Color(1.0, 0.82, 0.25))
	target_ring = _ring(r + 0.1, Color(1.0, 0.25, 0.2))

	name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.fixed_size = true
	name_label.pixel_size = 0.001
	name_label.font_size = 19
	name_label.outline_size = 7
	name_label.position.y = 1.45 * scale_f + 0.15
	add_child(name_label)
	info_label = Label3D.new()
	info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info_label.no_depth_test = true
	info_label.fixed_size = true
	info_label.pixel_size = 0.001
	info_label.font_size = 15
	info_label.outline_size = 6
	info_label.position.y = name_label.position.y
	info_label.offset = Vector2(0, -22)
	add_child(info_label)


func _ring(radius: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius
	t.outer_radius = radius + 0.06
	t.rings = 48
	m.mesh = t
	m.position.y = 0.04
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	m.material_override = mat
	m.visible = false
	add_child(m)
	return m


func _part(mesh: Mesh, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	m.material_override = body_mat
	body.add_child(m)
	return m


func _build_body(ctype: String, s: float) -> void:
	match ctype:
		"beast", "monstrosity":
			# Four-legged: long body, head, legs.
			var torso := CapsuleMesh.new()
			torso.radius = 0.17 * s
			torso.height = 0.7 * s
			_part(torso, Vector3(0, 0.32 * s, 0), Vector3(0, 0, PI / 2))
			var head := SphereMesh.new()
			head.radius = 0.15 * s
			head.height = 0.28 * s
			_part(head, Vector3(0.36 * s, 0.46 * s, 0))
			var leg := CylinderMesh.new()
			leg.top_radius = 0.045 * s
			leg.bottom_radius = 0.04 * s
			leg.height = 0.26 * s
			for p in [Vector3(0.2, 0.13, 0.1), Vector3(0.2, 0.13, -0.1), Vector3(-0.2, 0.13, 0.1), Vector3(-0.2, 0.13, -0.1)]:
				_part(leg, p * s)
		"dragon":
			_pawn(s, 0.32)
			var wing := PrismMesh.new()
			wing.size = Vector3(0.55 * s, 0.4 * s, 0.04 * s)
			_part(wing, Vector3(0, 0.75 * s, 0.22 * s), Vector3(0, 0, -0.5))
			_part(wing, Vector3(0, 0.75 * s, -0.22 * s), Vector3(0, 0, -0.5))
			var horn := CylinderMesh.new()
			horn.top_radius = 0.0
			horn.bottom_radius = 0.04 * s
			horn.height = 0.2 * s
			_part(horn, Vector3(0, 1.12 * s, 0.07 * s), Vector3(-0.4, 0, 0))
			_part(horn, Vector3(0, 1.12 * s, -0.07 * s), Vector3(0.4, 0, 0))
		"undead":
			_pawn(s, 0.24)
			var hood := CylinderMesh.new()
			hood.top_radius = 0.0
			hood.bottom_radius = 0.2 * s
			hood.height = 0.3 * s
			_part(hood, Vector3(0, 1.08 * s, 0))
		"giant":
			_pawn(s * 1.05, 0.36)
		_:
			_pawn(s, 0.3)


func _pawn(s: float, bottom: float) -> void:
	var torso := CylinderMesh.new()
	torso.top_radius = 0.14 * s
	torso.bottom_radius = bottom * s
	torso.height = 0.62 * s
	_part(torso, Vector3(0, 0.31 * s, 0))
	var collar := CylinderMesh.new()
	collar.top_radius = 0.2 * s
	collar.bottom_radius = 0.2 * s
	collar.height = 0.06 * s
	_part(collar, Vector3(0, 0.64 * s, 0))
	var head := SphereMesh.new()
	head.radius = 0.17 * s
	head.height = 0.34 * s
	_part(head, Vector3(0, 0.84 * s, 0))


func world_pos_for(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + cells / 2.0, 0, cell.y + cells / 2.0)


## Refresh appearance from combatant data. `eng` answers condition queries.
func refresh(c: Dictionary, eng: EngineBase, selected: bool, current: bool, targeted: bool) -> void:
	var team := PARTY_COLOR if c.side == "party" else (ENEMY_COLOR if c.side == "enemy" else NEUTRAL_COLOR)
	base_mat.albedo_color = team
	var col := Color.from_string(c.color, Color.GRAY)
	if c.dead:
		col = col.darkened(0.55)
	body_mat.albedo_color = col
	select_ring.visible = selected
	turn_ring.visible = current
	target_ring.visible = targeted
	name_label.text = c.name
	name_label.modulate = Color(1, 0.9, 0.6) if current else Color.WHITE
	var info := ""
	if c.dead:
		info = "dead"
	elif c.get("redacted", false):
		info = c.hp_status
	else:
		info = "%d/%d HP" % [c.hp, c.max_hp] + ((" +%d" % c.temp_hp) if c.temp_hp > 0 else "")
	var conds := eng.conditions_of(c).filter(func(k): return k != "incapacitated")
	if not c.concentration.is_empty():
		conds.append("concentrating")
	if c.hidden > 0:
		conds.append("hidden")
	var l: Dictionary = c.get("light", {})
	if not l.is_empty():
		conds.append(l.name.to_lower())
	if not conds.is_empty():
		info += "\n" + ", ".join(conds)
	if glow == null and not l.is_empty():
		glow = OmniLight3D.new()
		glow.light_color = Color(1.0, 0.75, 0.45)
		glow.light_energy = 1.5
		glow.position = Vector3(0, 1.4, 0)
		body.add_child(glow)
	if glow != null:
		glow.visible = not l.is_empty()
		glow.omni_range = (l.get("bright", 0) + l.get("dim", 0)) / float(Grid.FT)
	info_label.text = info
	var hp_frac: float = 1.0 if c.max_hp <= 0 else clampf(float(c.hp) / c.max_hp, 0.0, 1.0)
	info_label.modulate = Color(1.0, 0.45, 0.4) if hp_frac <= 0.5 and not c.get("redacted", false) else Color(0.85, 0.95, 0.85)
	var pose := "dead" if c.dead else ("down" if c.hp <= 0 or eng.has_cond(c, "unconscious") else ("prone" if eng.has_cond(c, "prone") else "up"))
	if pose != _pose:
		_pose = pose
		var rot := Vector3.ZERO
		match pose:
			"dead", "down": rot = Vector3(0, 0, PI / 2 * 0.95)
			"prone": rot = Vector3(0, 0, PI / 3)
		var tw := create_tween()
		tw.tween_property(body, "rotation", rot, 0.35).set_trans(Tween.TRANS_BACK)
	body.visible = true
	var invisible: bool = eng.has_cond(c, "invisible") or c.get("dm_hidden", false)
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if invisible else BaseMaterial3D.TRANSPARENCY_DISABLED
	if invisible:
		body_mat.albedo_color.a = 0.35
	if c.get("dm_hidden", false):
		info_label.text = "(hidden from players)\n" + info_label.text


func _process(delta: float) -> void:
	_time += delta
	if turn_ring.visible:
		var p := 1.0 + sin(_time * 4.0) * 0.06
		turn_ring.scale = Vector3(p, 1, p)
	if target_ring.visible:
		target_ring.rotation.y += delta * 2.0


func move_along(path: Array) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	for i in range(1, path.size()):
		var p := world_pos_for(path[i])
		_tween.tween_property(self, "position", p + Vector3(0, 0.18, 0), 0.07)
		_tween.tween_property(self, "position", p, 0.07)


func teleport_to(cell: Vector2i) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.15)
	_tween.tween_callback(func(): position = world_pos_for(cell))
	_tween.tween_property(self, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK)


func lunge(toward: Vector3) -> void:
	var home := position
	var dir := (toward - position)
	dir.y = 0
	if dir.length() < 0.01:
		return
	var tw := create_tween()
	tw.tween_property(self, "position", home + dir.normalized() * 0.35, 0.09)
	tw.tween_property(self, "position", home, 0.16)


func hit_flash() -> void:
	var tw := create_tween()
	var orig := body_mat.albedo_color
	tw.tween_property(body_mat, "albedo_color", Color(1, 0.3, 0.3), 0.06)
	tw.tween_property(body_mat, "albedo_color", orig, 0.25)
