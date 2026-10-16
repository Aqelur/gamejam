class_name QuakeCameraShake
extends Node
## Shakes whatever Camera3D is current, without fighting camera scripts:
## it only uses the camera's h_offset / v_offset and a small roll that it
## adds and removes itself. Created on demand - just call the static helpers:
##   QuakeCameraShake.kick(self, 0.6)          # sudden jolt (decays)
##   QuakeCameraShake.rumble(self, 0.3, 5.0)   # sustained ground rumble

## World units of sideways/vertical camera offset at full shake.
@export var max_offset := 0.14
## Degrees of camera roll at full shake.
@export var max_roll := 1.6
@export var frequency := 22.0
## Set false to disable all camera shake globally.
static var enabled := true

var trauma := 0.0
var _rumble := 0.0
var _rumble_time := 0.0
var _t := 0.0
var _cam: Camera3D
var _roll := 0.0
var _noise := FastNoiseLite.new()

static var _inst: QuakeCameraShake


static func get_shaker(from: Node) -> QuakeCameraShake:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	_inst = QuakeCameraShake.new()
	_inst.name = "QuakeCameraShake"
	from.get_tree().root.add_child.call_deferred(_inst)
	return _inst


static func kick(from: Node, amount: float) -> void:
	if not enabled or from == null or not from.is_inside_tree():
		return
	var s := get_shaker(from)
	s.trauma = clampf(s.trauma + amount, 0.0, 1.0)


static func rumble(from: Node, level: float, seconds: float) -> void:
	if not enabled or from == null or not from.is_inside_tree():
		return
	var s := get_shaker(from)
	s._rumble = maxf(s._rumble, clampf(level, 0.0, 1.0))
	s._rumble_time = maxf(s._rumble_time, seconds)


static func stop(from: Node) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.trauma = 0.0
		_inst._rumble = 0.0
		_inst._rumble_time = 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()


func _exit_tree() -> void:
	_release()


func _release() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
		_cam.rotation.z -= _roll
	_roll = 0.0
	_cam = null


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - delta * 0.8)
	_rumble_time -= delta
	if _rumble_time <= 0.0:
		_rumble = move_toward(_rumble, 0.0, delta * 0.4)
	var s := clampf(maxf(trauma * trauma, _rumble), 0.0, 1.0)
	if not enabled:
		s = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != _cam:
		_release()
		_cam = cam
	if _cam == null:
		return
	_t += delta * frequency
	var ox := _noise.get_noise_2d(_t, 0.0) * max_offset * s
	var oy := _noise.get_noise_2d(0.0, _t) * max_offset * s
	var roll := deg_to_rad(_noise.get_noise_2d(_t * 0.7, 50.0) * max_roll * s)
	_cam.h_offset = ox
	_cam.v_offset = oy
	_cam.rotation.z += roll - _roll
	_roll = roll
