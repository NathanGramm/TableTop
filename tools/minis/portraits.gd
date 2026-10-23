extends SceneTree
# Renders a head-and-shoulders portrait of every mini to res://assets/portraits/<id>.png, for the action bar.
# Needs a real renderer: xvfb-run godot --rendering-driver opengl3 --path . --script res://tools/minis/portraits.gd
var TokenScript = load("res://scripts/ui/token.gd")
const OUT := "res://assets/portraits/"
const SIZE := 160
var ids: Array
var i := -1
var wait := 0
var cur: Node3D
var cam: Camera3D


func _init():
	ids = TokenScript.mini_ids()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.12, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(1.0, 0.85, 0.6)
	root.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	root.size = Vector2i(SIZE, SIZE)


func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Centre of the "eye"/"eye_white" surfaces (skulls and helms have them too), or null.
func _eyes(n: Node):
	var pts := PackedVector3Array()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		for si in m.mesh.get_surface_count():
			var mat: Material = m.mesh.surface_get_material(si)
			if mat and mat.resource_name.begins_with("eye"):
				for v in m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					pts.append(m.global_transform * v)
	if pts.is_empty():
		return null
	var sum := Vector3.ZERO
	for v in pts:
		sum += v
	return sum / pts.size()


func _process(_d):
	wait -= 1
	if wait > 0:
		return false
	if cur:
		# The window may not take root.size, so crop the centre square (the camera keeps height) and scale it.
		var img := root.get_texture().get_image()
		var side := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		img.save_png(ProjectSettings.globalize_path(OUT + ids[i] + ".png"))
		cur.queue_free()
		cur = null
	i += 1
	if i >= ids.size():
		quit()
		return false
	cur = TokenScript.new()
	root.add_child(cur)
	cur.setup({"id": ids[i], "csize": "medium", "ctype": "humanoid", "class_id": "", "template_id": "", "mini": ids[i], "hp": 1, "max_hp": 1})
	for n in [cur.name_label, cur.info_label]:
		if n:
			n.visible = false
	# Frame the top of the figure (head and shoulders), looking from the front and a little to the side.
	var box := _bounds(cur.body if cur.body else cur)
	var h := box.size.y
	var aim := Vector3(box.get_center().x, box.position.y + h * 0.8, box.get_center().z + box.size.z * 0.25)
	var tall: bool = Monsters.get_monster(ids[i]).get("type", "") != "beast"  # beasts are shown whole
	var span := h * 0.2 if tall else maxf(h * 0.42, minf(box.size.x, box.size.z) * 0.45)
	var eyes = _eyes(cur)
	if not tall:
		aim.y = box.position.y + h * 0.55
	elif eyes != null:
		aim = eyes + Vector3(0, -h * 0.06, 0)
	var dist := span / tan(deg_to_rad(cam.fov / 2))
	cam.look_at_from_position(aim + Vector3(0.35, 0.15, 1.0).normalized() * dist, aim)
	wait = 6
	return false
