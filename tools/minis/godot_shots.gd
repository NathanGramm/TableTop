extends SceneTree
# Renders each mini named on the command line to <out>/<id>.png (needs a real renderer, e.g. xvfb + opengl3).
var TokenScript = load("res://scripts/ui/token.gd")
var ids: Array
var out := ""
var i := -1
var wait := 0
var cur: Node3D
func _init():
	var args := OS.get_cmdline_user_args()
	out = args[0]
	ids = args.slice(1)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.84, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 26
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 1.25, 2.6), Vector3(0, 0.5, 0))
	root.size = Vector2i(420, 600)
func _process(_d):
	wait -= 1
	if wait > 0:
		return false
	if cur:
		root.get_texture().get_image().save_png(out.path_join(ids[i] + ".png"))
		cur.queue_free()
		cur = null
	i += 1
	if i >= ids.size():
		quit()
		return false
	cur = TokenScript.new()
	root.add_child(cur)
	var big: bool = ids[i] == "ogre"
	cur.setup({"id": ids[i], "csize": "large" if big else "medium", "ctype": "humanoid", "class_id": "", "template_id": "", "mini": ids[i]})
	cur.base_mat.albedo_color = Color(0.25, 0.55, 0.95)
	if big:
		cur.scale = Vector3.ONE * 0.5
	wait = 6
	return false
