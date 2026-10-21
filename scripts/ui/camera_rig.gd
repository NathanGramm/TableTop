extends Node3D
## Orbit camera. Right-drag rotates, middle-drag (or Shift+right-drag) pans, wheel zooms,
## WASD/arrow keys pan, Q/E rotate.

var camera: Camera3D
var yaw := deg_to_rad(-30.0)
var pitch := deg_to_rad(55.0)
var distance := 22.0
var target := Vector3.ZERO
var _goal_target := Vector3.ZERO
var _rotating := false
var _panning := false
var bounds := Rect2(0, 0, 26, 18)


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)
	_apply()


func look_at_cell(p: Vector3, instant: bool = false) -> void:
	_goal_target = p
	if instant:
		target = p
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = clampf(distance * 0.9, 5.0, 70.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = clampf(distance * 1.1, 5.0, 70.0)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, deg_to_rad(15.0), deg_to_rad(88.0))
		elif _panning:
			var right := camera.global_transform.basis.x
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			_goal_target += (-right * mm.relative.x + fwd * mm.relative.y) * distance * 0.0015
			target = _goal_target


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
		if Input.is_key_pressed(KEY_Q): yaw += delta * 1.6
		if Input.is_key_pressed(KEY_E): yaw -= delta * 1.6
	if move != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		_goal_target += (right * move.x - fwd * move.y) * delta * distance * 0.8
	_goal_target.x = clampf(_goal_target.x, bounds.position.x - 4, bounds.end.x + 4)
	_goal_target.z = clampf(_goal_target.z, bounds.position.y - 4, bounds.end.y + 4)
	target = target.lerp(_goal_target, clampf(delta * 8.0, 0.0, 1.0))
	_apply()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func _apply() -> void:
	if camera == null:
		return
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)
