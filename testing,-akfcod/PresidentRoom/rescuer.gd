extends Node3D
## A little figure who digs people out of the rubble in the earthquake ending
## (police_rescue.gd). Same size and build as the Earthquake folder's
## QuakePerson (0.17 units tall; scale it up to the city).
##
##   police = true    a police officer: navy uniform, peaked cap and a bright
##                    yellow hi-vis vest so they read from up high
##   police = false   a neighbour in everyday clothes, digging by hand
##
##   walk_to(p)       walk there at walk_speed (signal `arrived`)
##   dig(face)        stand there bent over the rubble, hauling at it
##   wave()           arms up, calling for help
##
## Purely visual, no physics.

signal arrived(who: Node3D)

enum State { IDLE, WALK, DIG, WAVE }

const NAVY := Color(0.1, 0.14, 0.3)
const NAVY_DARK := Color(0.06, 0.07, 0.12)
const VEST := Color(0.86, 0.95, 0.18)
const SHIRTS := [Color(0.7, 0.25, 0.22), Color(0.3, 0.45, 0.7), Color(0.75, 0.62, 0.3),
	Color(0.35, 0.55, 0.38), Color(0.55, 0.38, 0.58), Color(0.85, 0.85, 0.82)]
const PANTS := [Color(0.15, 0.17, 0.25), Color(0.28, 0.24, 0.2), Color(0.35, 0.38, 0.45)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]

var police := true
var state := State.IDLE
## In world units a second (set it after scaling: ~0.9 tiles a second).
var walk_speed := 0.9
var ground_y := 0.0
## How hard they dig (neighbours tire; officers keep at it).
var effort := 1.0

var _target := Vector3.ZERO
var _yaw := 0.0
var _t := 0.0
var _phase := 0.0
var _rig: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D

static var _mats := {}
static var _meshes := {}


func _init(p_police := true) -> void:
	police = p_police
	_phase = randf() * TAU
	_build()


func place(pos: Vector3, ground: float, face: Vector3 = Vector3.FORWARD) -> void:
	ground_y = ground
	global_position = Vector3(pos.x, ground, pos.z)
	_face(face)


func walk_to(p: Vector3) -> void:
	_target = Vector3(p.x, ground_y, p.z)
	_face(_target - global_position)
	state = State.WALK


func dig(face: Vector3) -> void:
	_face(face)
	state = State.DIG


func wave() -> void:
	state = State.WAVE


func _face(d: Vector3) -> void:
	d.y = 0.0
	if d.length() > 0.0001:
		_yaw = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	_t += delta
	var t := _t + _phase
	match state:
		State.IDLE:
			_pose(0.0, 0.0, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0)
		State.WALK:
			var to := _target - global_position
			to.y = 0.0
			var step := walk_speed * delta
			if to.length() <= step:
				global_position = _target
				state = State.IDLE
				arrived.emit(self)
			else:
				global_position += to.normalized() * step
				_face(to)
			var stride := t * 13.0
			_rig.position.y = absf(sin(stride)) * 0.008
			_pose(-0.12, 0.0, Vector3(-sin(stride) * 0.8, 0, 0.12), Vector3(sin(stride) * 0.8, 0, -0.12),
				sin(stride) * 0.75, -sin(stride) * 0.75)
		State.DIG:
			# bent over the pile, both arms hauling at the rubble, a heave every stroke
			var k := t * 5.5 * effort
			var heave := sin(k)
			_rig.position.y = -0.012
			_pose(-0.85 - heave * 0.15, 0.0, Vector3(-1.9 - heave * 0.7, 0, 0.1),
				Vector3(-1.9 - sin(k + 0.6) * 0.7, 0, -0.1), 0.45, -0.25)
		State.WAVE:
			_rig.position.y = maxf(0.0, sin(t * 9.0)) * 0.006
			_pose(0.0, 0.0, Vector3(PI * 0.9, 0, 0.35 + sin(t * 10.0) * 0.35),
				Vector3(PI * 0.9, 0, -0.35 - sin(t * 10.0 + 1.5) * 0.35), 0.0, 0.0)


func _pose(lean: float, _roll: float, arm_l: Vector3, arm_r: Vector3, leg_l: float, leg_r: float) -> void:
	_rig.rotation = Vector3(lean, _yaw, 0.0)
	_arm_l.rotation = arm_l
	_arm_r.rotation = arm_r
	_leg_l.rotation.x = leg_l
	_leg_r.rotation.x = leg_r


# ------------------------------------------------------------------ model

func _build() -> void:
	var shirt: Color = NAVY if police else SHIRTS.pick_random()
	var pants: Color = NAVY_DARK if police else PANTS.pick_random()
	var skin: Color = SKIN.pick_random()
	_rig = Node3D.new()
	add_child(_rig)
	_leg_l = _limb(_rig, Vector3(-0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	_leg_r = _limb(_rig, Vector3(0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	_part(_rig, "torso", Vector3(0, 0.1, 0), shirt)
	if police:
		_part(_rig, "vest", Vector3(0, 0.1, 0), VEST, true)
	_part(_rig, "head", Vector3(0, 0.152, 0), skin)
	if police:
		_part(_rig, "cap", Vector3(0, 0.166, 0), NAVY)
		_part(_rig, "peak", Vector3(0, 0.161, -0.017), NAVY_DARK)
	else:
		_part(_rig, "hair", Vector3(0, 0.162, 0.002), Color(0.12, 0.08, 0.05).lerp(Color(0.6, 0.45, 0.2), randf() * randf()))
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


func _part(parent: Node3D, kind: String, pos: Vector3, c: Color, glow := false) -> void:
	if not _meshes.has(kind):
		match kind:
			"torso":
				var m := CapsuleMesh.new()
				m.radius = 0.02
				m.height = 0.07
				m.radial_segments = 8
				m.rings = 2
				_meshes[kind] = m
			"vest":
				var m := CapsuleMesh.new()
				m.radius = 0.0215
				m.height = 0.056
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
			"cap":
				var m := CylinderMesh.new()
				m.top_radius = 0.02
				m.bottom_radius = 0.018
				m.height = 0.012
				m.radial_segments = 8
				_meshes[kind] = m
			"peak":
				var m := BoxMesh.new()
				m.size = Vector3(0.026, 0.003, 0.014)
				_meshes[kind] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	mi.position = pos
	mi.material_override = _mat(c, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _box(size: Vector3) -> BoxMesh:
	var key := str(size)
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var key := c.to_html() + ("g" if glow else "")
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		if glow:
			# a hint of glow so the vests read from the camera high above
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.35
		_mats[key] = m
	return _mats[key]
