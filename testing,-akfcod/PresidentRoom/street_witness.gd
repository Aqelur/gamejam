extends CharacterBody3D
## Ten seconds in the street as the quake hits. The city camera sits in the
## head. move_left / move_right / move_up / move_down walk. The mouse aims.
## Looking down shows the arms and legs; they swing while walking.


const SECONDS := 10.0
const LOOK_SENS := 0.0022
const PITCH_MIN := -1.15
const PITCH_MAX := 1.05

var speed := 12.0
var _tile := 27.0
var _phase := 0.0
var _cam: Camera3D
var _cam_parent: Node
var _cam_near := 0.5
var _cam_fov := 48.0
var _floor: StaticBody3D
var _head: Node3D
var _visual: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D


func setup(city: Node3D, cam: Camera3D, eye: Vector3, look: Vector3, ground_y: float, tile: float) -> void:
	_tile = tile
	speed = 1.44 * tile
	var height := 0.187 * tile
	_build_body(height)
	_build_floor(city, Vector3(eye.x, ground_y, eye.z), tile)
	city.add_child(self)
	global_position = Vector3(eye.x, ground_y, eye.z)
	var flat := Vector3(look.x - eye.x, 0.0, look.z - eye.z)
	if flat.length() > 0.01:
		rotation.y = atan2(-flat.x, -flat.z)
	_head.look_at(look, Vector3.UP)
	_head.rotation = Vector3(_head.rotation.x, 0.0, 0.0)
	_cam = cam
	_cam_parent = cam.get_parent()
	_cam_near = cam.near
	_cam_fov = cam.fov
	cam.reparent(_head)
	cam.position = Vector3.ZERO
	cam.rotation = Vector3.ZERO
	cam.near = 0.08
	cam.fov = 62.0
	cam.make_current()


func add_look(relative: Vector2) -> void:
	rotate_y(-relative.x * LOOK_SENS)
	_head.rotation.x = clampf(_head.rotation.x - relative.y * LOOK_SENS, PITCH_MIN, PITCH_MAX)


func finish() -> void:
	if _cam and is_instance_valid(_cam) and _cam_parent and is_instance_valid(_cam_parent):
		var kept := _cam.global_transform
		_cam.reparent(_cam_parent)
		_cam.global_transform = kept
		_cam.near = _cam_near
		_cam.fov = _cam_fov
		_cam.make_current()
	_cam = null
	if _floor and is_instance_valid(_floor):
		_floor.queue_free()
	_floor = null
	queue_free()


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_basis.x
	right.y = 0.0
	right = right.normalized()
	var wish := right * stick.x + forward * -stick.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	if is_on_floor():
		velocity.y = -0.4
	else:
		velocity.y -= 30.0 * delta
	move_and_slide()
	_step(delta, wish.length())


func _build_floor(city: Node3D, at: Vector3, tile: float) -> void:
	_floor = StaticBody3D.new()
	_floor.name = "WitnessFloor"
	_floor.collision_layer = 2
	_floor.collision_mask = 0
	city.add_child(_floor)
	_floor.global_position = Vector3(at.x, at.y - 2.0, at.z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160.0 * tile, 4.0, 160.0 * tile)
	shape.shape = box
	_floor.add_child(shape)


func _build_body(height: float) -> void:
	collision_layer = 2
	collision_mask = 2
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.028 * _tile
	shape.height = height * 0.62
	capsule.shape = shape
	capsule.position.y = shape.height * 0.5
	add_child(capsule)

	_visual = Node3D.new()
	add_child(_visual)
	var shirt := Color(0.22, 0.38, 0.62)
	var pants := Color(0.14, 0.15, 0.2)
	var skin := Color(0.84, 0.66, 0.5)
	_box(_visual, Vector3(0, 0.64 * height, 0.06 * height), Vector3(0.28 * height, 0.28 * height, 0.14 * height), shirt)
	_leg_l = _limb(_visual, Vector3(-0.07 * height, 0.48 * height, 0), Vector3(0.09 * height, 0.46 * height, 0.1 * height), pants, skin)
	_leg_r = _limb(_visual, Vector3(0.07 * height, 0.48 * height, 0), Vector3(0.09 * height, 0.46 * height, 0.1 * height), pants, skin)
	_arm_l = _limb(_visual, Vector3(-0.18 * height, 0.8 * height, -0.16 * height), Vector3(0.07 * height, 0.4 * height, 0.08 * height), shirt, skin)
	_arm_r = _limb(_visual, Vector3(0.18 * height, 0.8 * height, -0.16 * height), Vector3(0.07 * height, 0.4 * height, 0.08 * height), shirt, skin)
	_arm_l.rotation.x = -0.4
	_arm_r.rotation.x = -0.4
	_head = Node3D.new()
	_head.position = Vector3(0, 0.155 / 0.187 * height, -0.04 * height)
	_visual.add_child(_head)


func _limb(parent: Node3D, pivot: Vector3, size: Vector3, cloth: Color, skin: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = pivot
	parent.add_child(joint)
	_box(joint, Vector3(0, -size.y * 0.42, 0), size, cloth)
	_box(joint, Vector3(0, -size.y * 0.92, 0.01 * size.y), Vector3(size.x * 1.05, size.y * 0.22, size.z * 1.15), skin)
	return joint


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


func _step(delta: float, amount: float) -> void:
	var moving := amount > 0.2
	if moving:
		_phase += delta * 9.0
	else:
		_phase = lerpf(_phase, 0.0, minf(1.0, delta * 6.0))
	var swing := sin(_phase) * (0.75 if moving else 0.0)
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm_l.rotation.x = -0.4 - swing
	_arm_r.rotation.x = -0.4 + swing
	_visual.position.y = absf(sin(_phase)) * 0.025 * _tile if moving else 0.0
