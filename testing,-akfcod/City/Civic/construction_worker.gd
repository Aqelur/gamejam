class_name ConstructionWorker
extends Node3D
## Tiny low-poly builder in a hard hat and hi-vis vest, used by Buildable.
## Same proportions as QuakePerson so they look like the same little city folk.
## Purely visual (no physics), so a dozen of them cost almost nothing.
##
## Jobs: HAMMER (bent over, swinging a hammer), SHOVEL (digging, kicks up dirt),
## CARRY (walks planks back and forth), SUPERVISE (clipboard, points at the build).

## Emitted every time a SHOVEL worker digs in, so the site can puff a bit of dirt.
signal dug(worker: ConstructionWorker)

enum Job { HAMMER, SHOVEL, CARRY, SUPERVISE }
enum State { WALK, WORK, CHEER, LEAVE }

const VESTS := [Color(1.0, 0.45, 0.05), Color(0.98, 0.85, 0.1), Color(0.75, 1.0, 0.15), Color(1.0, 0.32, 0.1)]
const HATS := [Color(1.0, 0.82, 0.05), Color(1.0, 0.82, 0.05), Color(1.0, 0.5, 0.05), Color(0.97, 0.97, 0.95)]
const SLEEVES := [Color(0.2, 0.35, 0.65), Color(0.85, 0.85, 0.85), Color(0.35, 0.37, 0.4), Color(0.55, 0.25, 0.2)]
const PANTS := [Color(0.18, 0.25, 0.45), Color(0.25, 0.22, 0.2), Color(0.35, 0.38, 0.45), Color(0.3, 0.27, 0.18)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]

var job := Job.HAMMER
var state := State.WALK
var walk_speed := 0.28
var ground_y := 0.0
## Point the worker faces while working (normally the middle of the building).
var look_target := Vector3.ZERO
## Callable() -> Vector3 that returns a new spot to work at.
var pick_point: Callable

var _target := Vector3.ZERO
var _work_left := 0.0
var _state_t := 0.0
var _phase := 0.0
var _yaw := 0.0
var _lean := 0.0
var _last_dig := 0
var _leave_dir := Vector3.FORWARD

var _rig: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _hammer: Node3D
var _shovel: Node3D
var _plank: Node3D
var _clipboard: Node3D

static var _mats := {}
static var _meshes := {}


func _init() -> void:
	_phase = randf() * TAU
	walk_speed = randf_range(0.24, 0.34)
	_build()


## Put the worker at `from` and send them to their first spot.
func start(p_job: Job, from: Vector3, to: Vector3, ground: float, look_at_point: Vector3) -> void:
	job = p_job
	ground_y = ground
	look_target = look_at_point
	position = Vector3(from.x, ground, from.z)
	_hammer.visible = job == Job.HAMMER
	_shovel.visible = job == Job.SHOVEL
	_plank.visible = job == Job.CARRY
	_clipboard.visible = job == Job.SUPERVISE
	_yaw = _yaw_to(to - from)
	_walk_to(to)


## Building is finished: stop, turn to it and cheer.
func cheer() -> void:
	_plank.visible = false
	_enter(State.CHEER)


## Walk away from the site (the site shrinks/frees us afterwards).
func leave(away_from: Vector3) -> void:
	var d := position - away_from
	d.y = 0.0
	_leave_dir = d.normalized() if d.length() > 0.001 else Vector3.BACK
	_enter(State.LEAVE)


# ------------------------------------------------------------------ behaviour

func _walk_to(p: Vector3) -> void:
	_target = Vector3(p.x, ground_y, p.z)
	_enter(State.WALK)


func _begin_work() -> void:
	match job:
		Job.CARRY:
			_work_left = randf_range(0.4, 0.9)   # pick up / drop off
		Job.SUPERVISE:
			_work_left = randf_range(3.0, 6.0)
		_:
			_work_left = randf_range(2.5, 5.5)
	_enter(State.WORK)


func _enter(s: State) -> void:
	state = s
	_state_t = 0.0


func _process(delta: float) -> void:
	_state_t += delta
	var t := _state_t + _phase
	match state:
		State.WALK:
			var to := _target - position
			to.y = 0.0
			if to.length() < 0.02:
				_begin_work()
			else:
				var dir := to.normalized()
				position += dir * minf(walk_speed * delta, to.length())
				position.y = ground_y
				_turn_to(dir, delta, 10.0)
				_walk_pose(t, -0.08)
		State.WORK:
			_turn_to(look_target - position, delta, 6.0)
			_work_pose(t)
			_work_left -= delta
			if _work_left <= 0.0 and pick_point.is_valid():
				_walk_to(pick_point.call())
		State.CHEER:
			_turn_to(look_target - position, delta, 6.0)
			_cheer_pose(t)
		State.LEAVE:
			position += _leave_dir * walk_speed * 1.6 * delta
			position.y = ground_y
			_turn_to(_leave_dir, delta, 10.0)
			_walk_pose(t * 1.4, -0.15)
	_rig.rotation = Vector3(_lean, _yaw, 0.0)


func _turn_to(d: Vector3, delta: float, rate: float) -> void:
	d.y = 0.0
	if d.length() > 0.001:
		_yaw = lerp_angle(_yaw, _yaw_to(d), minf(1.0, delta * rate))


func _yaw_to(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


# ------------------------------------------------------------------ poses

func _reset_limbs() -> void:
	_rig.position.y = 0.0
	_arm_l.rotation = Vector3(0, 0, 0.12)
	_arm_r.rotation = Vector3(0, 0, -0.12)
	_leg_l.rotation = Vector3.ZERO
	_leg_r.rotation = Vector3.ZERO


func _walk_pose(t: float, lean: float) -> void:
	var stride := t * 11.0
	_lean = lean
	_rig.position.y = absf(sin(stride)) * 0.008
	_leg_l.rotation = Vector3(sin(stride) * 0.7, 0, 0)
	_leg_r.rotation = Vector3(-sin(stride) * 0.7, 0, 0)
	_arm_l.rotation = Vector3(-sin(stride) * 0.6, 0, 0.12)
	if job == Job.CARRY and _plank.visible:
		_arm_r.rotation = Vector3(2.75, 0, -0.25)   # hand up, steadying the plank
	else:
		_arm_r.rotation = Vector3(sin(stride) * 0.6, 0, -0.12)


func _work_pose(t: float) -> void:
	_reset_limbs()
	match job:
		Job.HAMMER:
			# bent over, slow wind-up then a quick whack
			_lean = -0.32
			_leg_l.rotation.z = -0.12
			_leg_r.rotation.z = 0.12
			var s := fposmod(t * 1.9, 1.0)
			var a := lerpf(0.55, 2.5, smoothstep(0.0, 0.72, s)) if s < 0.72 else lerpf(2.5, 0.55, (s - 0.72) / 0.28)
			_arm_r.rotation = Vector3(a, 0, -0.1)
			_arm_l.rotation = Vector3(0.9, 0, 0.25)   # holding the nail
			_rig.position.y = -0.004 if s > 0.95 else 0.0
		Job.SHOVEL:
			var c := t * 3.2
			_lean = -0.22 - 0.16 * sin(c)
			var swing := 0.75 + 0.5 * sin(c)
			_arm_r.rotation = Vector3(swing, 0, -0.05)
			_arm_l.rotation = Vector3(swing + 0.25, 0, 0.3)
			_leg_l.rotation.x = 0.25
			_leg_r.rotation.x = -0.15
			var n := int(floor((c + PI * 0.5) / TAU))
			if n != _last_dig:
				_last_dig = n
				dug.emit(self)
		Job.CARRY:
			# crouch to pick up / put down
			var k := sin(clampf(_state_t / maxf(_work_left + _state_t, 0.01), 0.0, 1.0) * PI)
			_lean = -0.45 * k
			_rig.position.y = -0.012 * k
			_arm_r.rotation = Vector3(2.75 - 1.6 * k, 0, -0.25)
			_arm_l.rotation = Vector3(1.2 * k, 0, 0.12)
		Job.SUPERVISE:
			# clipboard in one hand, every few seconds points up at the building
			_lean = 0.03
			_arm_l.rotation = Vector3(1.15, 0, 0.35)
			var pointing := fposmod(t * 0.35, 1.0) < 0.45
			if pointing:
				_arm_r.rotation = Vector3(2.35 + sin(t * 2.5) * 0.12, 0, -0.15)
			else:
				_arm_r.rotation = Vector3(0.1, 0, -0.15)
			_rig.position.y = absf(sin(t * 1.5)) * 0.002


func _cheer_pose(t: float) -> void:
	_lean = 0.08
	_rig.position.y = absf(sin(t * 7.0)) * 0.025
	_leg_l.rotation = Vector3(0, 0, -0.1)
	_leg_r.rotation = Vector3(0, 0, 0.1)
	_arm_l.rotation = Vector3(PI * 0.92, 0, 0.35 + sin(t * 12.0) * 0.3)
	_arm_r.rotation = Vector3(PI * 0.92, 0, -0.35 - sin(t * 12.0 + 1.3) * 0.3)


# ------------------------------------------------------------------ model

func _build() -> void:
	var vest: Color = VESTS.pick_random()
	var hat: Color = HATS.pick_random()
	var sleeve: Color = SLEEVES.pick_random()
	var pants: Color = PANTS.pick_random()
	var skin: Color = SKIN.pick_random()
	var reflect := _mat(Color(0.92, 0.94, 0.95), 0.6)
	var wood := _mat(Color(0.62, 0.44, 0.26))
	var steel := _mat(Color(0.32, 0.33, 0.36))

	_rig = Node3D.new()
	add_child(_rig)
	# legs (pivot at hip) + boots
	_leg_l = _limb(_rig, Vector3(-0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	_leg_r = _limb(_rig, Vector3(0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), pants)
	for leg in [_leg_l, _leg_r]:
		_box_at(leg, Vector3(0.019, 0.012, 0.026), Vector3(0, -0.062, -0.003), _mat(Color(0.28, 0.18, 0.1)))
	# torso = hi-vis vest with two reflective stripes
	_shape(_rig, "torso", Vector3(0, 0.1, 0), _mat(vest, 0.15))
	_shape(_rig, "stripe", Vector3(0, 0.093, 0), reflect)
	_shape(_rig, "stripe", Vector3(0, 0.108, 0), reflect)
	# head + hard hat (dome + brim)
	_shape(_rig, "head", Vector3(0, 0.152, 0), _mat(skin))
	_shape(_rig, "hat", Vector3(0, 0.158, 0), _mat(hat, 0.1))
	_shape(_rig, "brim", Vector3(0, 0.158, -0.002), _mat(hat, 0.1))
	# arms (pivot at shoulder) + hands
	_arm_l = _limb(_rig, Vector3(-0.032, 0.128, 0), Vector3(0.013, 0.058, 0.014), sleeve)
	_arm_r = _limb(_rig, Vector3(0.032, 0.128, 0), Vector3(0.013, 0.058, 0.014), sleeve)
	_box_at(_arm_l, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.062, 0), _mat(skin))
	_box_at(_arm_r, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.062, 0), _mat(skin))

	# tools (only the one for this worker's job is shown)
	_hammer = Node3D.new()
	_arm_r.add_child(_hammer)
	_box_at(_hammer, Vector3(0.005, 0.005, 0.034), Vector3(0, -0.062, -0.014), wood)
	_box_at(_hammer, Vector3(0.016, 0.009, 0.009), Vector3(0, -0.062, -0.031), steel)

	_shovel = Node3D.new()
	_arm_r.add_child(_shovel)
	_box_at(_shovel, Vector3(0.005, 0.085, 0.005), Vector3(0, -0.095, -0.004), wood)
	_box_at(_shovel, Vector3(0.024, 0.028, 0.004), Vector3(0, -0.148, -0.006), steel)

	_plank = Node3D.new()
	_rig.add_child(_plank)
	_plank.position = Vector3(0.026, 0.148, 0.0)
	_plank.rotation = Vector3(0.12, 0, 0)
	_box_at(_plank, Vector3(0.012, 0.007, 0.17), Vector3.ZERO, wood)
	_box_at(_plank, Vector3(0.012, 0.007, 0.15), Vector3(0, 0.007, 0.01), _mat(Color(0.7, 0.52, 0.32)))

	_clipboard = Node3D.new()
	_arm_l.add_child(_clipboard)
	_box_at(_clipboard, Vector3(0.024, 0.032, 0.003), Vector3(0, -0.066, -0.01), _mat(Color(0.5, 0.34, 0.2)))
	_box_at(_clipboard, Vector3(0.02, 0.026, 0.001), Vector3(0, -0.066, -0.0118), _mat(Color(0.97, 0.97, 0.95)))


func _limb(parent: Node3D, pivot: Vector3, size: Vector3, c: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box_at(p, size, Vector3(0, -size.y * 0.5, 0), _mat(c))
	return p


func _box_at(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size)
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _shape(parent: Node3D, kind: String, pos: Vector3, m: Material) -> void:
	if not _meshes.has(kind):
		match kind:
			"torso":
				var cm := CapsuleMesh.new()
				cm.radius = 0.02
				cm.height = 0.07
				cm.radial_segments = 8
				cm.rings = 2
				_meshes[kind] = cm
			"stripe":
				var sm := CylinderMesh.new()
				sm.top_radius = 0.0208
				sm.bottom_radius = 0.0208
				sm.height = 0.005
				sm.radial_segments = 8
				sm.rings = 1
				_meshes[kind] = sm
			"head":
				var hm := SphereMesh.new()
				hm.radius = 0.017
				hm.height = 0.034
				hm.radial_segments = 8
				hm.rings = 4
				_meshes[kind] = hm
			"hat":
				var dm := SphereMesh.new()
				dm.radius = 0.0205
				dm.height = 0.0205
				dm.radial_segments = 10
				dm.rings = 3
				dm.is_hemisphere = true
				_meshes[kind] = dm
			"brim":
				var bm := CylinderMesh.new()
				bm.top_radius = 0.026
				bm.bottom_radius = 0.026
				bm.height = 0.003
				bm.radial_segments = 12
				bm.rings = 1
				_meshes[kind] = bm
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[kind]
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _box(size: Vector3) -> BoxMesh:
	var key := str(size)
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]


static func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), emit]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]
