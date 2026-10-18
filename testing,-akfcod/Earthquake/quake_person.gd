class_name QuakePerson
extends Node3D
## Tiny low-poly civilian used by the earthquake VFX.
## start_run(): runs away from a building, then stops and waves for help.
## start_jump(): leaps out of a window, flails, lands, gets up and runs.
## Purely visual (no physics) so dozens of them cost almost nothing.

signal landed(person: QuakePerson)

enum State { FALL, LAND, RUN, PANIC }

const SHIRTS := [Color(0.85, 0.2, 0.2), Color(0.2, 0.45, 0.85), Color(0.95, 0.75, 0.2),
	Color(0.25, 0.65, 0.35), Color(0.9, 0.5, 0.15), Color(0.6, 0.3, 0.7), Color(0.95, 0.95, 0.95),
	Color(0.15, 0.7, 0.75), Color(0.9, 0.45, 0.6)]
const PANTS := [Color(0.15, 0.17, 0.25), Color(0.25, 0.22, 0.2), Color(0.35, 0.38, 0.45), Color(0.12, 0.12, 0.13)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]

var state := State.RUN
var velocity := Vector3.ZERO
var ground_y := 0.0
var gravity := 5.0
var run_dir := Vector3.FORWARD
var run_speed := 0.55
var run_time := 4.0
## Optional: points (in the parent's space) to run through in order, e.g. out
## of a door and along an alley. While it has points the person follows them
## (ignoring run_time) and stops to wave at the last one.
var route: Array[Vector3] = []
## How far (radians) the run zig-zags either side of its heading.
var wobble := 0.25

var _state_t := 0.0
var _phase := 0.0
var _yaw := 0.0
var _spin := 0.0
var _rig: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

static var _mats := {}
static var _meshes := {}


func _init() -> void:
	_phase = randf() * TAU
	_build()


func start_run(pos: Vector3, dir: Vector3, ground: float) -> void:
	ground_y = ground
	position = Vector3(pos.x, ground, pos.z)
	_set_dir(dir)
	run_speed = randf_range(0.45, 0.75)
	run_time = randf_range(2.5, 5.5)
	_enter(State.RUN)


func start_jump(pos: Vector3, vel: Vector3, ground: float) -> void:
	ground_y = ground
	position = pos
	velocity = vel
	_set_dir(Vector3(vel.x, 0, vel.z))
	_spin = randf_range(-3.0, 3.0)
	_enter(State.FALL)


func _set_dir(d: Vector3) -> void:
	d.y = 0.0
	if d.length() < 0.001:
		d = Vector3.FORWARD
	run_dir = d.normalized()
	_yaw = atan2(-run_dir.x, -run_dir.z)


func _enter(s: State) -> void:
	state = s
	_state_t = 0.0


func _process(delta: float) -> void:
	_state_t += delta
	var t := _state_t * 1.0 + _phase
	match state:
		State.FALL:
			velocity.y -= gravity * delta
			position += velocity * delta
			_yaw += _spin * delta
			# flailing: arms windmill overhead, legs kick
			_arm_l.rotation.x = PI * 0.85 + sin(t * 22.0) * 0.6
			_arm_r.rotation.x = PI * 0.85 + sin(t * 22.0 + 2.0) * 0.6
			_arm_l.rotation.z = 0.5
			_arm_r.rotation.z = -0.5
			_leg_l.rotation.x = sin(t * 18.0) * 0.9
			_leg_r.rotation.x = -sin(t * 18.0) * 0.9
			_rig.rotation = Vector3(-minf(_state_t * 1.2, 0.9), _yaw, 0.0)
			if position.y <= ground_y:
				position.y = ground_y
				_enter(State.LAND)
				landed.emit(self)
		State.LAND:
			# thud onto hands and knees, then scramble up
			var k := clampf(1.0 - (_state_t - 0.35) / 0.4, 0.0, 1.0)
			_rig.rotation = Vector3(-1.2 * k, _yaw, 0.0)
			_rig.position.y = -0.03 * k
			_arm_l.rotation = Vector3(-1.4 * k, 0, 0)
			_arm_r.rotation = Vector3(-1.4 * k, 0, 0)
			_leg_l.rotation.x = 0.8 * k
			_leg_r.rotation.x = 0.8 * k
			if _state_t > 0.8:
				_rig.position.y = 0.0
				run_speed = randf_range(0.5, 0.8)
				run_time = randf_range(2.0, 4.5)
				_enter(State.RUN)
		State.RUN:
			var on_route := not route.is_empty()
			if on_route:
				var to := route[0] - position
				to.y = 0.0
				if to.length() <= run_speed * delta * 1.5:
					route.remove_at(0)
					if route.is_empty():
						_enter(State.PANIC)
						return
					to = route[0] - position
					to.y = 0.0
				if to.length() > 0.0001:
					run_dir = to.normalized()
					_yaw = atan2(-run_dir.x, -run_dir.z)
			# a little zig-zag so crowds don't move in straight lines
			var dir := run_dir.rotated(Vector3.UP, sin(t * 1.7) * wobble)
			position += dir * run_speed * delta
			position.y = ground_y
			var stride := t * 16.0
			_rig.position.y = absf(sin(stride)) * 0.012
			_rig.rotation = Vector3(-0.22, atan2(-dir.x, -dir.z), 0.0)
			_leg_l.rotation.x = sin(stride) * 0.9
			_leg_r.rotation.x = -sin(stride) * 0.9
			_arm_l.rotation = Vector3(-sin(stride) * 1.0, 0, 0.15)
			_arm_r.rotation = Vector3(sin(stride) * 1.0, 0, -0.15)
			if not on_route and _state_t > run_time:
				_enter(State.PANIC)
		State.PANIC:
			# stop, turn around and wave arms overhead
			_rig.position.y = maxf(0.0, sin(t * 9.0)) * 0.008
			_rig.rotation = Vector3(0.0, lerp_angle(_rig.rotation.y, _yaw + PI, delta * 3.0), 0.0)
			_leg_l.rotation.x = 0.0
			_leg_r.rotation.x = 0.0
			_arm_l.rotation = Vector3(PI * 0.9, 0, 0.35 + sin(t * 10.0) * 0.35)
			_arm_r.rotation = Vector3(PI * 0.9, 0, -0.35 - sin(t * 10.0 + 1.5) * 0.35)


# ------------------------------------------------------------------ model

func _build() -> void:
	var shirt: Color = SHIRTS.pick_random()
	var pants: Color = PANTS.pick_random()
	var skin: Color = SKIN.pick_random()
	var hair := Color(0.12, 0.08, 0.05).lerp(Color(0.6, 0.45, 0.2), randf() * randf())
	_rig = Node3D.new()
	add_child(_rig)
	# legs (pivot at hip)
	_leg_l = _limb(_rig, Vector3(-0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	_leg_r = _limb(_rig, Vector3(0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	# torso
	_part(_rig, "torso", Vector3(0, 0.1, 0), shirt)
	# head + hair
	_part(_rig, "head", Vector3(0, 0.152, 0), skin)
	_part(_rig, "hair", Vector3(0, 0.162, 0.002), hair)
	# arms (pivot at shoulder)
	_arm_l = _limb(_rig, Vector3(-0.032, 0.128, 0), Vector3(0.013, 0.058, 0.014), shirt)
	_arm_r = _limb(_rig, Vector3(0.032, 0.128, 0), Vector3(0.013, 0.058, 0.014), shirt)


func _limb(parent: Node3D, pivot: Vector3, size: Vector3, c: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size)
	mi.position = Vector3(0, -size.y * 0.5, 0)
	mi.material_override = _mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	return p


func _part(parent: Node3D, kind: String, pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	if not _meshes.has(kind):
		match kind:
			"torso":
				var m := CapsuleMesh.new()
				m.radius = 0.02
				m.height = 0.07
				m.radial_segments = 8
				m.rings = 2
				_meshes[kind] = m
			"head":
				var m := SphereMesh.new()
				m.radius = 0.017
				m.height = 0.034
				m.radial_segments = 8
				m.rings = 4
				_meshes[kind] = m
			"hair":
				var m := SphereMesh.new()
				m.radius = 0.018
				m.height = 0.02
				m.radial_segments = 8
				m.rings = 3
				m.is_hemisphere = true
				_meshes[kind] = m
	mi.mesh = _meshes[kind]
	mi.position = pos
	mi.material_override = _mat(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _box(size: Vector3) -> BoxMesh:
	var key := str(size)
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]
