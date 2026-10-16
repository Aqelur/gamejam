extends Camera3D
## Simple free camera for exploring the city.
## Hold right mouse to look around, WASD to move, Q/E down/up, Shift to go faster.
##
## Debug hotkeys (debug builds only, e.g. F5/F6 from the editor):
##   1 / 2 / 3 ...  jump to each buildable building (hospital, police, fire)
##   0              back to where the camera started
##   B              start building the nearest unbuilt building

@export var speed := 150.0
@export var mouse_sensitivity := 0.25
## The city is big; make sure the far clip plane always reaches across it.
@export var min_far := 6000.0
@export var debug_hotkeys := true

var _yaw := 0.0
var _pitch := 0.0
var _start: Transform3D

func _ready() -> void:
	far = maxf(far, min_far)
	_start = global_transform
	_sync_angles()
	if debug_hotkeys and OS.is_debug_build():
		_make_hint.call_deferred()

func _sync_angles() -> void:
	_yaw = rotation_degrees.y
	_pitch = rotation_degrees.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -89.0, 89.0)
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo and debug_hotkeys and OS.is_debug_build():
		var k: Key = event.physical_keycode
		if k == KEY_0:
			global_transform = _start
			_sync_angles()
		elif k >= KEY_1 and k <= KEY_9:
			_jump_to(k - KEY_1)
		elif k == KEY_B:
			_build_nearest()

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	var s := speed * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	if dir != Vector3.ZERO:
		global_position += dir.normalized() * s * delta

# ------------------------------------------------------------------ debug

func _buildables() -> Array:
	return get_tree().get_nodes_in_group("buildable")

## Put the camera in front of building `i`, looking at it.
func _jump_to(i: int) -> void:
	var list := _buildables()
	if i < 0 or i >= list.size():
		return
	var b := list[i] as Node3D
	var s := b.global_basis.get_scale().x
	var front := b.global_basis.z.normalized()   # civic buildings face local +Z
	var target := b.global_position + Vector3.UP * 1.0 * s
	global_position = b.global_position + front * 7.0 * s + Vector3.UP * 5.0 * s
	look_at(target, Vector3.UP)
	_sync_angles()

func _build_nearest() -> void:
	var best = null
	var best_d := INF
	for b in _buildables():
		if b.is_built() or b.stage != 0:
			continue
		var d := global_position.distance_to((b as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = b
	if best:
		best.build()

func _make_hint() -> void:
	var list := _buildables()
	if list.is_empty():
		return
	var parts: PackedStringArray = []
	for i in list.size():
		parts.append("%d %s" % [i + 1, list[i]._title().capitalize()])
	var layer := CanvasLayer.new()
	add_child(layer)
	var l := Label.new()
	l.text = "DEBUG   " + "   ".join(parts) + "   0 Overview   B Build nearest"
	l.position = Vector2(12, 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 16)
	layer.add_child(l)
