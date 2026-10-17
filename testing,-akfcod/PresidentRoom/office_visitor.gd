extends Node3D
## A life-size visitor to the president's office.
##
## Built the same way as the city folk (QuakePerson, ConstructionWorker): flat
## colours on capsules, spheres and boxes, no textures, no imported meshes.
## The player sees these people from a couple of metres away, so they get the
## detail the tiny city people skip: knees, elbows and ankles, hands with
## fingers and thumbs, eyes with irises that blink and look at you, brows,
## nose, ears, lips that move when they talk, haircuts, glasses, and an outfit
## for each job (suits with lapels, ties and buttons, a uniform with ribbons,
## a steward's white jacket and bow tie).
##
## office_traffic.gd drives them: it gives each one a path in through a door,
## a job to do in the room, and a path back out.
##
## Facing: the model looks down local -Z, like the other people in the project.

signal finished(visitor: Node3D)

enum Role { AIDE, AGENT, GENERAL, STAFFER, STEWARD }
enum Act { BRIEF, GUARD, BROWSE, WARM, ADMIRE, SERVE }
enum State { WALK, ACT, GONE }

# ---------------------------------------------------------------- palette
# Same skin tones as the city folk, plus two in between.
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.9, 0.72, 0.57), Color(0.82, 0.6, 0.45),
	Color(0.7, 0.5, 0.36), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]
const HAIR := [Color(0.08, 0.06, 0.05), Color(0.18, 0.11, 0.07), Color(0.36, 0.22, 0.12),
	Color(0.55, 0.27, 0.12), Color(0.86, 0.7, 0.42), Color(0.58, 0.57, 0.55), Color(0.86, 0.86, 0.84)]
const IRIS := [Color(0.33, 0.2, 0.1), Color(0.18, 0.11, 0.06), Color(0.3, 0.5, 0.78),
	Color(0.33, 0.52, 0.32), Color(0.5, 0.4, 0.2)]
const SUITS := [Color(0.2, 0.21, 0.25), Color(0.12, 0.16, 0.32), Color(0.4, 0.41, 0.45), Color(0.32, 0.24, 0.17)]
const SHIRTS := [Color(0.97, 0.97, 0.95), Color(0.97, 0.97, 0.95), Color(0.78, 0.87, 0.98), Color(0.98, 0.87, 0.87)]
# city palette (weathering.gd / president_room.gd), slightly deepened for cloth
const TIES := [Color8(208, 83, 80), Color8(102, 148, 217), Color8(90, 95, 200), Color8(33, 141, 109),
	Color8(255, 192, 68), Color8(245, 104, 67)]
const BLAZERS := [Color8(245, 104, 67), Color8(102, 148, 217), Color8(33, 141, 109), Color8(208, 83, 80),
	Color8(90, 95, 200), Color(0.92, 0.9, 0.85)]
const GOLD := Color(0.95, 0.75, 0.2)
const NAVY := Color(0.07, 0.16, 0.42)

# ---------------------------------------------------------------- body sizes (metres)
const HIP_Y := 0.92        # hip joint height (before the per-person scale)
const THIGH := 0.43
const SHIN := 0.41
const UPPER_ARM := 0.28
const FOREARM := 0.26
const EYE_Y := 0.115       # eye height above the head joint

# ---------------------------------------------------------------- public state
var role := Role.AIDE
var act := Act.BRIEF
var state := State.WALK
var female := false
## The director (office_traffic.gd). Untyped so this file stands on its own.
var traffic
## Where to walk, in order (world XZ, y ignored), and which door (if any) each
## step goes through, so the visitor can wait for it to swing open.
var path: Array[Vector3] = []
var path_doors: Array[String] = []
var walk_speed := 1.05
## Activity: where to face, how long to do it.
var face_point := Vector3.ZERO
var face_camera := false
var act_time := 8.0
var id := 0
## Proposer: stay at the desk until decide() is called, however long that takes.
var wait_for_decision := false
## 0 = no decision yet, 1 = approved, -1 = denied.
var decision := 0

# ---------------------------------------------------------------- private state
var _i := 0
var _t := 0.0
var _state_t := 0.0
var _yaw := 0.0
var _phase := 0.0            # stride phase, advanced by distance walked
var _stride_amp := 0.42
var _moving := 0.0           # 0 standing .. 1 walking (blends the poses)
var _blocked_t := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _talk := 0.0             # mouth openness target 0..1
var _talking := false
var _glance_t := 0.0
var _glance := Vector3.ZERO  # idle gaze offset (yaw, pitch)
var _look_pos := Vector3.ZERO
var _has_look := false
var _gesture_seed := 0.0
var _served := false
var _cup: Node3D             # cup carried on the steward's tray
var _cup_from := Transform3D()
var _cup_to := Transform3D()
var _placing := false

var _rig: Node3D
var _j := {}                 # joint name -> Node3D
var _tp := {}                # joint name -> target rotation this frame
var _rig_y := 0.0
var _eyes: Array[Node3D] = []
var _irises: Array[Node3D] = []
var _mouth_inner: Node3D
var _lower_lip: Node3D
var _prop: Node3D            # folder / tablet held against the chest
var _tray: Node3D
var _cap: Node3D

static var _mats := {}
static var _meshes := {}


# ================================================================ setup

func _init() -> void:
	_phase = randf() * TAU
	_gesture_seed = randf() * 100.0
	_blink_t = randf_range(0.5, 3.0)


## Dress and build the visitor. Call once, before adding to the tree.
func build(p_role: Role, p_female: bool) -> void:
	role = p_role
	female = p_female
	walk_speed = randf_range(2.1, 2.4)
	if role == Role.STEWARD:
		walk_speed *= 0.9
	_build()


## Start walking the given path. The first point is where the visitor appears.
func begin(p_path: Array[Vector3], p_doors: Array[String]) -> void:
	path = p_path
	path_doors = p_doors
	_i = 1
	position = Vector3(path[0].x, 0.0, path[0].z)
	if path.size() > 1:
		_yaw = _yaw_to(path[1] - path[0])
	_rig.rotation.y = _yaw
	state = State.WALK


## Replace the remaining path (used for the way out).
func set_path(p_path: Array[Vector3], p_doors: Array[String]) -> void:
	path = p_path
	path_doors = p_doors
	_i = 0
	state = State.WALK
	_state_t = 0.0


## True when this visitor is about to go through (or is in) the named door.
func wants_door(door: String, centre: Vector3) -> bool:
	if state != State.WALK:
		return false
	var near := position.distance_to(Vector3(centre.x, 0, centre.z)) < 2.4
	if not near:
		return false
	for k in [_i - 1, _i, _i + 1]:
		if k >= 0 and k < path_doors.size() and path_doors[k] == door:
			return true
	return false


func is_walking() -> bool:
	return state == State.WALK and _moving > 0.3


func heading() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


# ================================================================ update

func _process(delta: float) -> void:
	if state == State.GONE:
		return
	_t += delta
	_state_t += delta
	_rest_pose()
	match state:
		State.WALK:
			_update_walk(delta)
		State.ACT:
			_update_act(delta)
	_update_gaze(delta)
	_update_face(delta)
	_apply_pose(delta)


func _update_walk(delta: float) -> void:
	if _i >= path.size():
		_arrived()
		return
	var target := path[_i]
	var to := target - position
	to.y = 0.0
	var dist := to.length()
	var door: String = path_doors[_i] if _i < path_doors.size() else ""
	var go := true
	# wait at a closed door until it has swung open
	if door != "" and traffic != null:
		var amount: float = traffic.door_amount(door)
		var centre: Vector3 = traffic.door_centre(door)
		var dc := Vector3(centre.x - position.x, 0, centre.z - position.z).length()
		if amount < 0.8 and dc < 1.25:
			go = false
	# give way to someone right in front
	if go and traffic != null and traffic.is_blocked(self, to.normalized() if dist > 0.001 else heading()):
		_blocked_t += delta
		go = _blocked_t > 2.5   # don't stand there forever
	else:
		_blocked_t = 0.0
	if dist < 0.04:
		_i += 1
		return
	var dir := to / maxf(dist, 0.0001)
	var want_yaw := _yaw_to(dir)
	var turn := absf(wrapf(want_yaw - _yaw, -PI, PI))
	_yaw = lerp_angle(_yaw, want_yaw, minf(1.0, delta * 7.0))
	var target_move := 1.0 if go else 0.0
	_moving = move_toward(_moving, target_move, delta * 3.0)
	if go:
		# slow down for sharp turns so nobody walks sideways
		var spd := walk_speed * clampf(cos(turn), 0.25, 1.0) * (0.35 + 0.65 * _moving)
		var step := minf(spd * delta, dist)
		position += dir * step
		_phase += step / 1.45 * TAU
	_walk_pose()
	# when walking near the player, glance at them now and then
	_has_look = false
	if traffic != null:
		var cam: Vector3 = traffic.camera_pos()
		var d := cam - position
		d.y = 0.0
		if d.length() < 4.5 and heading().dot(d.normalized()) > 0.2 and fposmod(_t + _gesture_seed, 7.0) < 2.5:
			_look_pos = cam
			_has_look = true


func _arrived() -> void:
	if _leaving:
		state = State.GONE
		finished.emit(self)
		return
	state = State.ACT
	_state_t = 0.0


var _leaving := false


## Steward only: true = arrive with a fresh coffee, false = come to collect the cup.
func bring_cup(yes: bool) -> void:
	if not yes and _cup:
		_cup.queue_free()
		_cup = null

## Proposer: the player stamped the proposal. React, then leave.
func decide(approved: bool) -> void:
	decision = 1 if approved else -1
	wait_for_decision = false
	# finish the current gesture, react, and go (_brief_pose times the reaction
	# against act_time)
	act_time = maxf(_state_t, 0.0) + 2.4


## Called by the director when the job is done.
func leave(p_path: Array[Vector3], p_doors: Array[String]) -> void:
	_leaving = true
	_talking = false
	set_path(p_path, p_doors)


# ================================================================ activities

func _update_act(delta: float) -> void:
	_moving = move_toward(_moving, 0.0, delta * 3.0)
	var face := face_point
	if face_camera and traffic != null:
		face = traffic.camera_pos()
	var d := face - position
	d.y = 0.0
	if d.length() > 0.01:
		_yaw = lerp_angle(_yaw, _yaw_to(d), minf(1.0, delta * 4.0))
	_idle_pose()
	_has_look = false
	var t := _state_t
	match act:
		Act.BRIEF:
			_brief_pose(t)
		Act.GUARD:
			_guard_pose(t)
		Act.BROWSE:
			_browse_pose(t)
		Act.WARM:
			_warm_pose(t)
		Act.ADMIRE:
			_admire_pose(t)
		Act.SERVE:
			_serve_pose(t, delta)
	if t > act_time and traffic != null and not _leaving and not wait_for_decision:
		traffic.visitor_done(self)


func _brief_pose(t: float) -> void:
	_look_pos = traffic.camera_pos() if traffic else face_point
	_has_look = true
	var start := 0.0
	if role == Role.GENERAL:
		# snap a salute first
		start = 2.0
		if t < start:
			var k := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(1.55, 1.95, t))
			_tp.arm_r = _tp.arm_r.lerp(Vector3(1.05, 0.5, 1.15), k)
			_tp.elbow_r = _tp.elbow_r.lerp(Vector3(2.25, 0, 0), k)
			_tp.hand_r = _tp.hand_r.lerp(Vector3(0, -0.4, 0.2), k)
			_tp.spine.x += 0.04 * k
			return
	var tt := t - start
	# A proposer pitches for a few phrases, then waits quietly for the stamp,
	# picking the pitch up again now and then.
	var pitch := 1.0
	if wait_for_decision or decision != 0:
		var cycle := fposmod(tt, 16.0)
		pitch = 1.0 - smoothstep(8.0, 9.0, cycle) * (1.0 - smoothstep(15.0, 16.0, cycle))
		if decision != 0:
			pitch = 0.0
	# talk in phrases with short pauses
	var phrase := fposmod(tt + _gesture_seed, 4.2)
	_talking = phrase > 0.3 and phrase < 3.4 and t < act_time - 1.2 and pitch > 0.5
	# right hand gestures while talking
	var g := sin(tt * 2.1 + _gesture_seed) * 0.5 + 0.5
	var g2 := sin(tt * 3.3 + _gesture_seed * 2.0)
	var on := smoothstep(0.0, 0.6, tt) * (1.0 - smoothstep(act_time - start - 1.6, act_time - start - 0.9, tt))
	if wait_for_decision or decision != 0:
		on = smoothstep(0.0, 0.6, tt) * pitch
	if _prop and _prop.visible:
		_hold_prop_pose(1.0)
	else:
		_tp.arm_l = _tp.arm_l.lerp(Vector3(0.25 + 0.1 * g2, 0, -0.12), on * 0.6)
		_tp.elbow_l = _tp.elbow_l.lerp(Vector3(1.0 + 0.2 * g, 0, 0), on * 0.6)
	_tp.arm_r = _tp.arm_r.lerp(Vector3(0.35 + 0.18 * g, 0, 0.18 + 0.1 * g2), on)
	_tp.elbow_r = _tp.elbow_r.lerp(Vector3(1.25 + 0.3 * g2, 0, 0), on)
	_tp.hand_r = _tp.hand_r.lerp(Vector3(0.1, 0.5 + 0.3 * g, -0.4), on)
	_tp.fingers_r = Vector3(0, 0, -0.1)
	# head bobs along with the words
	_tp.head.x += 0.04 * sin(tt * 4.5) * (1.0 if _talking else 0.0)
	if decision < 0:
		# denied: shake the head, shoulders drop
		var k := smoothstep(act_time - 2.3, act_time - 1.9, t) * (1.0 - smoothstep(act_time - 0.5, act_time, t))
		_tp.head.y += sin(t * 11.0) * 0.32 * k
		_tp.head.x -= 0.12 * k
		_tp.spine.x -= 0.08 * k
		_tp.arm_l.z -= 0.05 * k
		_tp.arm_r.z += 0.05 * k
		return
	# a small bow before leaving (deeper when the proposal was approved)
	var depth := 1.6 if decision > 0 else 1.0
	var bow := smoothstep(act_time - 1.0, act_time - 0.6, t) * (1.0 - smoothstep(act_time - 0.3, act_time, t))
	_tp.spine.x -= 0.28 * bow * depth
	_tp.head.x -= 0.25 * bow * depth


func _guard_pose(t: float) -> void:
	# feet apart, hands clasped in front, scanning the room
	_tp.leg_l.z = -0.07
	_tp.leg_r.z = 0.07
	_tp.arm_l = Vector3(0.28, 0.0, 0.36)
	_tp.arm_r = Vector3(0.28, 0.0, -0.36)
	_tp.elbow_l = Vector3(0.95, 0, 0)
	_tp.elbow_r = Vector3(0.95, 0, 0)
	_tp.hand_l = Vector3(0, 0.6, 0)
	_tp.hand_r = Vector3(0, -0.6, 0)
	_tp.fingers_l = Vector3(0, 0, 0.45)
	_tp.fingers_r = Vector3(0, 0, -0.45)
	var scan := fposmod(t * 0.23 + _gesture_seed, 1.0)
	if scan < 0.3:
		# look at the president for a while
		_look_pos = traffic.camera_pos() if traffic else face_point
		_has_look = true
	else:
		_tp.head.y += sin(t * 0.55 + _gesture_seed) * 0.75
	# touch the earpiece now and then
	var ear := fposmod(t + _gesture_seed, 9.0)
	if ear > 6.0 and ear < 8.0:
		var k := smoothstep(6.0, 6.4, ear) * (1.0 - smoothstep(7.6, 8.0, ear))
		_tp.arm_r = _tp.arm_r.lerp(Vector3(0.4, -0.3, 0.55), k)
		_tp.elbow_r = _tp.elbow_r.lerp(Vector3(2.45, 0, 0), k)
		_tp.hand_r = _tp.hand_r.lerp(Vector3(0, 0.2, 0.3), k)
		_tp.head.z -= 0.12 * k


func _browse_pose(t: float) -> void:
	# look along the shelves, reach up to a book now and then
	_tp.head.x += 0.18 + 0.12 * sin(t * 0.4)
	_tp.head.y += sin(t * 0.5 + _gesture_seed) * 0.35
	var reach := fposmod(t + _gesture_seed, 6.0)
	var k := smoothstep(2.5, 3.2, reach) * (1.0 - smoothstep(4.8, 5.5, reach))
	_tp.arm_r = _tp.arm_r.lerp(Vector3(2.0, 0.0, 0.12), k)
	_tp.elbow_r = _tp.elbow_r.lerp(Vector3(0.55, 0, 0), k)
	_tp.hand_r = _tp.hand_r.lerp(Vector3(0.0, 0, -0.2), k)
	_tp.fingers_r = Vector3(0, 0, -0.5 * k - 0.1)
	_tp.spine.x += 0.05 * k
	if _prop and _prop.visible:
		_hold_prop_pose(1.0)
	else:
		_tp.arm_l = Vector3(-0.15, 0, -0.08)


func _warm_pose(t: float) -> void:
	# hands held out to the fire, rubbed together now and then
	var rub := fposmod(t + _gesture_seed, 5.0) > 3.4
	var r := sin(t * 14.0) * 0.08 if rub else 0.0
	_tp.arm_l = Vector3(0.75 + r, 0.0, 0.32)
	_tp.arm_r = Vector3(0.75 - r, 0.0, -0.32)
	_tp.elbow_l = Vector3(0.75, 0, 0)
	_tp.elbow_r = Vector3(0.75, 0, 0)
	_tp.hand_l = Vector3(0.0, 0.0, 1.2 if not rub else 0.3)
	_tp.hand_r = Vector3(0.0, 0.0, -1.2 if not rub else -0.3)
	_tp.spine.x -= 0.05
	_tp.head.x -= 0.15
	if fposmod(t * 0.17 + _gesture_seed, 1.0) < 0.25:
		_look_pos = traffic.camera_pos() if traffic else face_point
		_has_look = true


func _admire_pose(t: float) -> void:
	# chin in hand, studying the painting, head tilting
	_tp.head.x += 0.22
	_tp.head.z += sin(t * 0.6 + _gesture_seed) * 0.12
	_tp.arm_r = Vector3(0.35, 0.0, -0.3)
	_tp.elbow_r = Vector3(2.35, 0, 0)
	_tp.hand_r = Vector3(0.0, -0.3, 0.4)
	_tp.fingers_r = Vector3(0, 0, -0.6)
	_tp.arm_l = Vector3(0.3, 0.0, 0.42)
	_tp.elbow_l = Vector3(1.35, 0, 0)
	_tp.hand_l = Vector3(0.0, 0.4, 0.2)
	_tp.fingers_l = Vector3(0, 0, 0.6)
	_tp.spine.x += 0.03


func _serve_pose(t: float, delta: float) -> void:
	# carry the tray, lean over the desk, put the coffee down (or take it away)
	_tray_pose(1.0)
	var reach := smoothstep(0.9, 1.6, t) * (1.0 - smoothstep(2.5, 3.2, t))
	_tp.spine.x -= 0.32 * reach
	_tp.head.x -= 0.15 * reach
	_tp.arm_r = _tp.arm_r.lerp(Vector3(0.85, 0.0, -0.1), reach)
	_tp.elbow_r = _tp.elbow_r.lerp(Vector3(0.45, 0, 0), reach)
	_tp.hand_r = _tp.hand_r.lerp(Vector3(-0.5, 0, 0), reach)
	_tp.fingers_r = Vector3(0, 0, -0.35 * reach)
	if not _served and t > 1.0 and traffic != null:
		_served = true
		_start_cup_move()
	if _cup and (_placing or _cup_moving):
		var k := clampf((t - 1.0) / 0.8, 0.0, 1.0)
		var s := smoothstep(0.0, 1.0, k)
		var from := _cup_from if _placing else _cup_to
		var to := _cup_to if _placing else _tray_slot()
		var o := from.origin.lerp(to.origin, s) + Vector3.UP * sin(k * PI) * 0.06
		var q := from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), s)
		_cup.global_transform = Transform3D(Basis(q), o)
		if k >= 1.0:
			_finish_cup_move()
	if t > 3.0:
		_look_pos = traffic.camera_pos() if traffic else face_point
		_has_look = true
	var bow := smoothstep(3.4, 3.7, t) * (1.0 - smoothstep(3.9, 4.3, t))
	_tp.spine.x -= 0.18 * bow
	_tp.head.x -= 0.2 * bow


var _cup_moving := false

func _start_cup_move() -> void:
	var desk_cup: Node3D = traffic.desk_cup
	var spot: Transform3D = traffic.cup_spot()
	_cup_to = spot
	if desk_cup == null and _cup != null:
		# put ours down
		_placing = true
		_cup_from = _cup.global_transform
		var keep := _cup.global_transform
		_cup.get_parent().remove_child(_cup)
		traffic.cup_parent().add_child(_cup)
		_cup.global_transform = keep
	elif desk_cup != null:
		# take the old one away on the tray
		_placing = false
		_cup_moving = true
		_cup = desk_cup
		traffic.desk_cup = null
		_cup_to = _cup.global_transform


func _finish_cup_move() -> void:
	if _placing:
		_cup.global_transform = _cup_to
		_cup.scale = Vector3.ONE
		traffic.desk_cup = _cup
		_cup = null
		_placing = false
	else:
		_cup.get_parent().remove_child(_cup)
		_tray.add_child(_cup)
		_cup.transform = Transform3D(Basis(), Vector3(0.06, 0.012, 0.02))
		_cup_moving = false


func _tray_slot() -> Transform3D:
	return _tray.global_transform * Transform3D(Basis(), Vector3(0.06, 0.012, 0.02))


# ================================================================ poses
# Every frame each joint gets a target rotation in _tp; _apply_pose eases the
# real joints toward it, so walking, standing and gestures blend smoothly.

func _rest_pose() -> void:
	var breathe := sin(_t * 1.7 + _gesture_seed) * 0.012
	_tp.hips = Vector3.ZERO
	_tp.spine = Vector3(breathe, 0, 0)
	_tp.head = Vector3.ZERO
	_tp.arm_l = Vector3(0.02, 0, -0.07)
	_tp.arm_r = Vector3(0.02, 0, 0.07)
	_tp.elbow_l = Vector3(0.14, 0, 0)
	_tp.elbow_r = Vector3(0.14, 0, 0)
	_tp.hand_l = Vector3(0, 0, 0.08)
	_tp.hand_r = Vector3(0, 0, -0.08)
	_tp.fingers_l = Vector3(0, 0, 0.18)
	_tp.fingers_r = Vector3(0, 0, -0.18)
	_tp.leg_l = Vector3(0, 0, -0.02)
	_tp.leg_r = Vector3(0, 0, 0.02)
	_tp.knee_l = Vector3(-0.03, 0, 0)
	_tp.knee_r = Vector3(-0.03, 0, 0)
	_tp.foot_l = Vector3(0.03, 0, 0)
	_tp.foot_r = Vector3(0.03, 0, 0)
	_rig_y = 0.0
	_talking = _talking and state == State.ACT


func _idle_pose() -> void:
	# a slow weight shift so nobody stands like a statue
	var w := sin(_t * 0.45 + _gesture_seed)
	_tp.hips.z = 0.025 * w
	_tp.spine.z = -0.02 * w
	_tp.leg_l.z -= 0.025 * w
	_tp.leg_r.z -= 0.025 * w
	if role == Role.STEWARD:
		_tray_pose(1.0)
	elif _prop and _prop.visible:
		_hold_prop_pose(1.0)


func _walk_pose() -> void:
	var s := sin(_phase)
	var c := cos(_phase)
	var m := _moving
	var a := _stride_amp * m
	_tp.leg_l = Vector3(s * a, 0, -0.02)
	_tp.leg_r = Vector3(-s * a, 0, 0.02)
	# the knee bends while that leg swings forward, straightens to land
	_tp.knee_l = Vector3(-(0.06 + 0.95 * maxf(0.0, c)) * m - 0.03, 0, 0)
	_tp.knee_r = Vector3(-(0.06 + 0.95 * maxf(0.0, -c)) * m - 0.03, 0, 0)
	_tp.foot_l = Vector3(-(_tp.leg_l.x + _tp.knee_l.x) * 0.55 + 0.03, 0, 0)
	_tp.foot_r = Vector3(-(_tp.leg_r.x + _tp.knee_r.x) * 0.55 + 0.03, 0, 0)
	_tp.hips = Vector3(0, s * 0.09 * m, -c * 0.03 * m)
	_tp.spine = Vector3(-0.03 * m, -s * 0.12 * m, c * 0.025 * m)
	_tp.head = Vector3(0.02 * m, s * 0.05 * m, 0)
	_rig_y = 0.022 * (absf(c) - 1.0) * m
	var arm := 0.3 * m
	_tp.arm_l = Vector3(-s * arm + 0.02, 0, -0.07)
	_tp.arm_r = Vector3(s * arm + 0.02, 0, 0.07)
	_tp.elbow_l = Vector3(0.18 + maxf(0.0, -s) * 0.35 * m, 0, 0)
	_tp.elbow_r = Vector3(0.18 + maxf(0.0, s) * 0.35 * m, 0, 0)
	if role == Role.STEWARD:
		_tray_pose(1.0)
	elif _prop and _prop.visible:
		_hold_prop_pose(1.0)


## Left arm folded up, holding the folder / tablet against the chest.
func _hold_prop_pose(k: float) -> void:
	_tp.arm_l = _tp.arm_l.lerp(Vector3(0.12, 0.0, 0.22), k)
	_tp.elbow_l = _tp.elbow_l.lerp(Vector3(1.75, 0.0, 0.0), k)
	_tp.hand_l = _tp.hand_l.lerp(Vector3(0.0, 0.0, -0.15), k)
	_tp.fingers_l = Vector3(0, 0, 0.5)


## Both forearms forward under the tray.
func _tray_pose(k: float) -> void:
	_tp.arm_l = _tp.arm_l.lerp(Vector3(0.32, 0.0, 0.06), k)
	_tp.arm_r = _tp.arm_r.lerp(Vector3(0.32, 0.0, -0.06), k)
	_tp.elbow_l = _tp.elbow_l.lerp(Vector3(1.3, 0.0, 0.0), k)
	_tp.elbow_r = _tp.elbow_r.lerp(Vector3(1.3, 0.0, 0.0), k)
	_tp.hand_l = _tp.hand_l.lerp(Vector3(0.0, 0.0, 1.0), k)
	_tp.hand_r = _tp.hand_r.lerp(Vector3(0.0, 0.0, -1.0), k)
	_tp.fingers_l = Vector3(0, 0, 0.1)
	_tp.fingers_r = Vector3(0, 0, -0.1)


func _apply_pose(delta: float) -> void:
	var k := 1.0 - exp(-delta * (16.0 if state == State.WALK else 9.0))
	for key: String in _tp:
		var n: Node3D = _j.get(key)
		if n:
			n.rotation = n.rotation.lerp(_tp[key], k)
	_rig.position.y = lerpf(_rig.position.y, _rig_y, k)
	_rig.rotation.y = _yaw


# ================================================================ eyes, mouth, gaze

func _update_gaze(delta: float) -> void:
	# idle glances: pick a new spot to look at every couple of seconds
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_t = randf_range(1.2, 3.5)
		_glance = Vector3(randf_range(-0.35, 0.35), randf_range(-0.12, 0.1), 0)
	var head_yaw := 0.0
	var head_pitch := 0.0
	var eye_yaw := _glance.x * 0.6
	var eye_pitch := _glance.y * 0.6
	if _has_look:
		# _look_pos is in the same space as our position (the director's)
		var eye := (get_parent() as Node3D).to_local(_j.head.global_position) + Vector3.UP * EYE_Y * scale.y
		var d := _look_pos - eye
		var flat := Vector2(d.x, d.z).length()
		var want := wrapf(_yaw_to(d) - _yaw, -PI, PI)
		head_yaw = clampf(want, -1.1, 1.1)
		head_pitch = clampf(atan2(d.y, flat), -0.55, 0.45)
		eye_yaw = clampf(want - head_yaw, -0.5, 0.5)
		eye_pitch = 0.0
	elif state == State.WALK:
		head_yaw = _glance.x * 0.3
	_tp.head = _tp.head + Vector3(head_pitch, head_yaw, 0.0)
	# irises slide within the eye whites
	for ir in _irises:
		ir.position.x = lerpf(ir.position.x, -sin(eye_yaw) * 0.0055, minf(1.0, delta * 14.0))
		ir.position.y = lerpf(ir.position.y, sin(eye_pitch) * 0.004, minf(1.0, delta * 14.0))


func _update_face(delta: float) -> void:
	# blinking
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(2.0, 5.0)
		if randf() < 0.15:
			_blink_t = 0.25   # double blink
	_blink = maxf(0.0, _blink - delta * 7.0)
	var open := 1.0 - sin(_blink * PI)
	for e in _eyes:
		e.scale.y = lerpf(0.08, 1.0, open)
	# mouth: open/close in syllables while talking
	var target := 0.0
	if _talking:
		target = clampf(0.5 + 0.5 * sin(_t * 15.0) * sin(_t * 4.3 + 1.0), 0.0, 1.0)
	_talk = move_toward(_talk, target, delta * 10.0)
	if _mouth_inner:
		_mouth_inner.scale.y = 1.0 + _talk * 3.5
		_mouth_inner.position.y = -_talk * 0.0045
		_lower_lip.position.y = -0.0045 - _talk * 0.009


# ================================================================ helpers

func _yaw_to(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


# ================================================================ model

func _build() -> void:
	var skin: Color = SKIN.pick_random()
	var hair: Color = HAIR.pick_random()
	if role == Role.GENERAL:
		hair = [HAIR[5], HAIR[6], HAIR[1]].pick_random()
	var suit: Color = SUITS.pick_random()
	var shirt: Color = SHIRTS.pick_random()
	var tie: Color = TIES.pick_random()
	var trousers := suit
	var shoes := Color(0.1, 0.07, 0.05) if randf() < 0.6 else Color(0.25, 0.14, 0.08)
	var tie_kind := "tie"
	var buttons := suit.darkened(0.45)
	match role:
		Role.AGENT:
			suit = Color(0.08, 0.08, 0.09)
			trousers = suit
			shirt = SHIRTS[0]
			tie = Color(0.06, 0.06, 0.07)
			shoes = Color(0.05, 0.05, 0.05)
		Role.GENERAL:
			suit = Color(0.3, 0.36, 0.24)
			trousers = suit
			shirt = Color(0.78, 0.72, 0.56)
			tie = Color(0.4, 0.38, 0.28)
			buttons = GOLD
			shoes = Color(0.05, 0.05, 0.05)
		Role.STEWARD:
			suit = Color(0.96, 0.95, 0.91)
			trousers = Color(0.08, 0.08, 0.09)
			shirt = SHIRTS[0]
			tie = Color(0.06, 0.06, 0.07)
			tie_kind = "bow"
			buttons = GOLD
			shoes = Color(0.05, 0.05, 0.05)
		Role.STAFFER:
			suit = BLAZERS.pick_random()
			trousers = [Color(0.15, 0.15, 0.18), Color(0.25, 0.26, 0.3), suit.darkened(0.3)].pick_random()
			shirt = [SHIRTS[0], Color(0.98, 0.95, 0.86)].pick_random()
			buttons = GOLD if randf() < 0.5 else suit.darkened(0.4)
	if female:
		tie_kind = "bow" if role == Role.STEWARD else "none"
	var skirt := female and role != Role.AGENT and role != Role.GENERAL and randf() < 0.6

	var s := randf_range(0.97, 1.05) * (0.94 if female else 1.0)
	scale = Vector3(s, s, s)
	_stride_amp = 0.3 if skirt else 0.42

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var hips := _joint("hips", _rig, Vector3(0, HIP_Y, 0))
	var spine := _joint("spine", hips, Vector3(0, 0.05, 0))
	# ---------------------------------------------------------- legs
	var leg_col := trousers
	var lower_col := trousers
	if skirt:
		leg_col = skin.darkened(0.12)
		lower_col = leg_col
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var leg := _joint("leg" + sfx, hips, Vector3(0.088 * side, -0.02, 0))
		_capsule(leg, 0.075, THIGH + 0.08, Vector3(0, -THIGH * 0.5 + 0.02, 0), _mat(leg_col))
		var knee := _joint("knee" + sfx, leg, Vector3(0, -THIGH, 0))
		_capsule(knee, 0.062, SHIN + 0.06, Vector3(0, -SHIN * 0.5 + 0.01, 0), _mat(lower_col))
		if not skirt:
			# trouser hem, a touch wider than the shin
			_cyl(knee, 0.07, 0.072, 0.07, Vector3(0, -SHIN + 0.05, 0), _mat(trousers))
			_cyl(knee, 0.052, 0.052, 0.03, Vector3(0, -SHIN + 0.005, 0), _mat(Color(0.1, 0.1, 0.12)))  # sock
		var foot := _joint("foot" + sfx, knee, Vector3(0, -SHIN, 0))
		_shoe(foot, shoes, female)
	# pelvis
	_cyl(hips, 0.16, 0.165, 0.2, Vector3(0, -0.04, 0), _mat(trousers), Vector3(1.0, 1.0, 0.7))
	if skirt:
		_cyl(hips, 0.165, 0.215, 0.5, Vector3(0, -0.2, 0), _mat(trousers), Vector3(1.0, 1.0, 0.74))
		_cyl(hips, 0.216, 0.216, 0.02, Vector3(0, -0.44, 0), _mat(trousers.darkened(0.15)), Vector3(1.0, 1.0, 0.74))
	# ---------------------------------------------------------- torso
	var jacket := _mat(suit)
	var top_r := 0.18 if female else 0.195
	_cyl(spine, top_r, 0.17, 0.5, Vector3(0, 0.2, 0), jacket, Vector3(1.0, 1.0, 0.64))
	# jacket skirt flares a little at the hem
	_cyl(spine, 0.172, 0.182, 0.12, Vector3(0, -0.01, 0), jacket, Vector3(1.0, 1.0, 0.66))
	# shoulders and upper back
	var sh := _capsule(spine, 0.07, 0.42 if female else 0.45, Vector3(0, 0.425, 0.0), jacket)
	sh.rotation.z = PI * 0.5
	sh.scale = Vector3(1.0, 1.0, 0.95)
	_sphere(spine, 0.16, Vector3(0, 0.43, 0.005), jacket, Vector3(1.12, 0.45, 0.76))
	# neck and shirt collar
	var neck_r := 0.048 if female else 0.056
	_cyl(spine, neck_r, neck_r + 0.004, 0.14, Vector3(0, 0.54, 0.008), _mat(skin))
	# shirt collar: higher at the back, dipping at the front to the tie knot
	_cyl(spine, neck_r + 0.01, neck_r + 0.014, 0.06, Vector3(0, 0.512, 0.01), _mat(shirt)).rotation.x = -0.4
	# jacket collar rolling round the back of the neck
	_cyl(spine, neck_r + 0.022, neck_r + 0.035, 0.055, Vector3(0, 0.49, 0.016), jacket, Vector3(1.0, 1.0, 0.92))
	# shirt front showing in the jacket's V
	var v := _prism(spine, Vector3(0.13, 0.2, 0.012), Vector3(0, 0.37, -0.122), _mat(shirt))
	v.rotation.z = PI
	v.rotation.x = -0.12
	# collar points
	for side in [-1.0, 1.0]:
		var cp := _prism(spine, Vector3(0.032, 0.036, 0.008), Vector3(0.02 * side, 0.478, -0.122), _mat(shirt))
		cp.rotation = Vector3(-0.25, 0, PI + 0.45 * side)
	# tie / bow tie / necklace
	match tie_kind:
		"tie":
			_box(spine, Vector3(0.032, 0.028, 0.02), Vector3(0, 0.455, -0.13), _mat(tie)).rotation.x = -0.15
			var blade := _box(spine, Vector3(0.048, 0.17, 0.008), Vector3(0, 0.355, -0.133), _mat(tie))
			blade.rotation.x = -0.12
			var tip := _prism(spine, Vector3(0.048, 0.03, 0.008), Vector3(0, 0.255, -0.12), _mat(tie))
			tip.rotation = Vector3(-0.12, 0, PI)
		"bow":
			for side in [-1.0, 1.0]:
				var w := _prism(spine, Vector3(0.04, 0.045, 0.014), Vector3(0.022 * side, 0.462, -0.132), _mat(tie))
				w.rotation.z = PI * 0.5 * side
			_box(spine, Vector3(0.016, 0.02, 0.016), Vector3(0, 0.462, -0.137), _mat(tie))
		"none":
			for k in 7:
				var a := (k - 3) * 0.26
				_sphere(spine, 0.006, Vector3(sin(a) * 0.05, 0.43 - cos(a) * 0.035 + 0.035, -0.126), _mat(GOLD, 0.0, 0.3, 0.6))
	# lapels
	var lapel := _mat(suit.darkened(0.12))
	for side in [-1.0, 1.0]:
		# a long triangle each side of the V, wide at the collar, to a point at the button
		var lp := _prism(spine, Vector3(0.07, 0.21, 0.01), Vector3(0.07 * side, 0.365, -0.124), lapel, 0.0 if side < 0.0 else 1.0)
		lp.rotation = Vector3(-0.12, 0.3 * side, PI + 0.22 * side)
	# buttons
	var n_buttons := 4 if role == Role.GENERAL else (1 if female else 2)
	for k in n_buttons:
		var by := 0.32 - k * 0.09 if role == Role.GENERAL else 0.225 - k * 0.09
		_disc(spine, 0.011, 0.006, Vector3(0, by, -0.119 + (0.22 - by) * 0.03), _mat(buttons, 0.0, 0.35, 0.4 if buttons == GOLD else 0.0))
	# pocket flaps and breast pocket
	for side in [-1.0, 1.0]:
		var pf := _box(spine, Vector3(0.1, 0.016, 0.012), Vector3(0.085 * side, 0.085, -0.104), lapel)
		pf.rotation.y = 0.42 * side
	_box(spine, Vector3(0.075, 0.012, 0.01), Vector3(-0.085, 0.31, -0.112), lapel).rotation.y = -0.4
	match role:
		Role.AIDE, Role.STAFFER:
			if randf() < 0.6:
				var sq := _prism(spine, Vector3(0.04, 0.025, 0.01), Vector3(-0.085, 0.327, -0.112), _mat(TIES.pick_random()))
				sq.rotation.y = -0.4
		Role.AGENT:
			# flag lapel pin
			_disc(spine, 0.007, 0.004, Vector3(-0.075, 0.395, -0.13), _mat(GOLD, 0.0, 0.3, 0.6))
		Role.GENERAL:
			# ribbon rack, badge, shoulder boards with stars
			var ribbons := [TIES[0], TIES[1], GOLD, TIES[3], Color(0.9, 0.9, 0.9), TIES[2], TIES[5], NAVY, TIES[4]]
			for k in 9:
				var rx := -0.105 + (k % 3) * 0.024
				var ry := 0.335 + floorf(k / 3.0) * 0.013
				_box(spine, Vector3(0.023, 0.012, 0.008), Vector3(rx, ry, -0.115 + rx * -0.15), _mat(ribbons[k])).rotation.y = -0.35
			_disc(spine, 0.016, 0.005, Vector3(-0.085, 0.29, -0.113), _mat(GOLD, 0.0, 0.3, 0.6)).rotation.y = -0.4
			for side in [-1.0, 1.0]:
				_box(spine, Vector3(0.1, 0.014, 0.065), Vector3(0.15 * side, 0.488, 0.0), _mat(suit.darkened(0.25)))
				for k in 2:
					_sphere(spine, 0.009, Vector3((0.12 + k * 0.035) * side, 0.497, 0.0), _mat(GOLD, 0.3, 0.3, 0.6))
			# belt
			_cyl(spine, 0.176, 0.176, 0.035, Vector3(0, 0.07, 0), _mat(Color(0.25, 0.17, 0.1)), Vector3(1.0, 1.0, 0.66))
			_box(spine, Vector3(0.04, 0.03, 0.01), Vector3(0, 0.073, -0.118), _mat(GOLD, 0.0, 0.3, 0.6))
	# ---------------------------------------------------------- arms
	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var arm := _joint("arm" + sfx, spine, Vector3((0.2 if female else 0.215) * side, 0.425, 0))
		_capsule(arm, 0.056, UPPER_ARM + 0.08, Vector3(0, -UPPER_ARM * 0.5 + 0.02, 0), jacket)
		var elbow := _joint("elbow" + sfx, arm, Vector3(0, -UPPER_ARM, 0))
		_capsule(elbow, 0.05, FOREARM + 0.06, Vector3(0, -FOREARM * 0.5 + 0.005, 0), jacket)
		_cyl(elbow, 0.051, 0.052, 0.025, Vector3(0, -FOREARM + 0.03, 0), jacket)   # sleeve hem
		_cyl(elbow, 0.045, 0.045, 0.03, Vector3(0, -FOREARM + 0.012, 0), _mat(shirt))  # shirt cuff
		if role == Role.GENERAL:
			_cyl(elbow, 0.0525, 0.0525, 0.01, Vector3(0, -FOREARM + 0.06, 0), _mat(GOLD, 0.0, 0.3, 0.6))
		var hand := _joint("hand" + sfx, elbow, Vector3(0, -FOREARM, 0))
		_hand(hand, side, skin)
	# ---------------------------------------------------------- head
	var head := _joint("head", spine, Vector3(0, 0.575, -0.008))
	_head(head, skin, hair)
	# ---------------------------------------------------------- props
	match role:
		Role.AIDE:
			_prop = _folder(spine, [Color(0.85, 0.75, 0.5), NAVY, TIES[0]].pick_random())
		Role.STAFFER:
			_prop = _tablet(spine) if randf() < 0.5 else _folder(spine, [NAVY, TIES[3], Color(0.85, 0.75, 0.5)].pick_random())
		Role.STEWARD:
			_tray = Node3D.new()
			_tray.name = "Tray"
			_tray.position = Vector3(0, 0.08, -0.36)
			spine.add_child(_tray)
			var silver := _mat(Color(0.78, 0.78, 0.8), 0.0, 0.25, 0.8)
			_cyl(_tray, 0.2, 0.2, 0.012, Vector3.ZERO, silver)
			var rim := _torus(_tray, 0.19, 0.205, Vector3(0, 0.012, 0), silver)
			rim.scale = Vector3(1.0, 1.0, 1.0)
			_cyl(_tray, 0.06, 0.055, 0.03, Vector3(-0.09, 0.006, 0.03), _mat(Color(0.95, 0.95, 0.95), 0.0, 0.2))   # sugar
			_sphere(_tray, 0.012, Vector3(-0.09, 0.04, 0.03), _mat(Color(0.95, 0.95, 0.95), 0.0, 0.2))
			_box(_tray, Vector3(0.012, 0.003, 0.12), Vector3(-0.02, 0.008, -0.06), silver).rotation.y = 0.3  # spoon
			_cup = make_cup()
			_tray.add_child(_cup)
			_cup.transform = Transform3D(Basis(), Vector3(0.06, 0.012, 0.02))


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	_j[n] = j
	return j


func _shoe(foot: Node3D, c: Color, heeled: bool) -> void:
	var leather := _mat(c, 0.0, 0.3)
	var sole := _mat(Color(0.06, 0.05, 0.04), 0.0, 0.8)
	var w := 0.085 if heeled else 0.1
	var body := _capsule(foot, w * 0.5, 0.25 if heeled else 0.275, Vector3(0, -0.035, -0.045), leather)
	body.rotation.x = PI * 0.5
	body.scale = Vector3(1.0, 1.0, 0.62)   # flattened (capsule axis is along Z after the turn)
	_box(foot, Vector3(w * 0.96, 0.012, 0.25 if heeled else 0.27), Vector3(0, -0.066, -0.045), sole)
	if heeled:
		_box(foot, Vector3(0.03, 0.035, 0.03), Vector3(0, -0.07, 0.05), sole)
	else:
		# laces
		_box(foot, Vector3(0.03, 0.004, 0.05), Vector3(0, -0.012, -0.09), _mat(c.darkened(0.4))).rotation.x = -0.25


## Palm faces the body (+X for the left hand, -X for the right); thumb in front.
func _hand(hand: Node3D, side: float, skin: Color) -> void:
	var m := _mat(skin, 0.0, 0.6)
	var inward := -side
	_box(hand, Vector3(0.03, 0.085, 0.078), Vector3(0, -0.045, 0), m)
	_sphere(hand, 0.03, Vector3(0, -0.012, 0), m, Vector3(0.6, 0.9, 1.25))   # wrist / heel of hand
	var fingers := _joint("fingers" + ("_l" if side < 0.0 else "_r"), hand, Vector3(0, -0.085, 0))
	var lengths := [0.068, 0.074, 0.07, 0.056]
	for k in 4:
		var z := -0.027 + k * 0.018
		var f := Node3D.new()
		f.position = Vector3(0, 0, z)
		f.rotation.z = 0.12 * inward * k * 0.3
		fingers.add_child(f)
		var flen: float = lengths[k]
		_capsule(f, 0.0085, flen, Vector3(0, -flen * 0.5 + 0.006, 0), m)
		# fingernail
		_box(f, Vector3(0.002, 0.012, 0.011), Vector3(-0.0088 * inward, -flen + 0.016, 0), _mat(skin.lightened(0.25), 0.0, 0.4))
	var thumb := _capsule(hand, 0.0105, 0.058, Vector3(0.008 * inward, -0.05, -0.044), m)
	thumb.rotation = Vector3(0.55, 0, 0.25 * inward)


func _head(head: Node3D, skin: Color, hair: Color) -> void:
	var sk := _mat(skin, 0.0, 0.6)
	var dark := hair.darkened(0.25)
	# skull, jaw and chin
	_sphere(head, 0.1, Vector3(0, 0.105, 0), sk, Vector3(0.9, 1.08, 0.98) * (0.97 if female else 1.0))
	_sphere(head, 0.078, Vector3(0, 0.052, -0.013), sk, Vector3(0.98 if not female else 0.9, 0.75, 1.0))
	_sphere(head, 0.02, Vector3(0, 0.02, -0.064), sk, Vector3(1.3 if not female else 1.0, 0.9, 1.0))
	_sphere(head, 0.06, Vector3(0, 0.035, 0.02), sk, Vector3(1.0, 1.0, 1.0))   # under the jaw into the neck
	# ears
	for side in [-1.0, 1.0]:
		var ear := _sphere(head, 0.028, Vector3(0.089 * side, 0.1, 0.008), sk, Vector3(0.4, 1.0, 0.68))
		ear.rotation.y = -0.25 * side
		_sphere(head, 0.016, Vector3(0.093 * side, 0.1, 0.003), _mat(skin.darkened(0.2), 0.0, 0.7), Vector3(0.3, 1.0, 0.7))
	# nose: a ridge (prism pointing forward), round tip, nostrils
	var nose := _prism(head, Vector3(0.026, 0.02, 0.048), Vector3(0, 0.09, -0.09), sk)
	nose.rotation.x = -PI * 0.5 + 0.2
	_sphere(head, 0.0115, Vector3(0, 0.07, -0.098), sk, Vector3(1.25, 0.85, 1.0))
	for side in [-1.0, 1.0]:
		_sphere(head, 0.0035, Vector3(0.0065 * side, 0.0635, -0.0985), _mat(skin.darkened(0.45)))
	# eyes: white, iris, pupil, a glint; blink by squashing the whole eye
	var iris_col: Color = IRIS.pick_random()
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.036 * side, EYE_Y, -0.082)
		head.add_child(eye)
		_eyes.append(eye)
		_sphere(eye, 0.016, Vector3.ZERO, _mat(Color(0.97, 0.96, 0.93), 0.0, 0.2), Vector3(1.0, 0.78, 0.62))
		var iris := Node3D.new()
		eye.add_child(iris)
		_irises.append(iris)
		_disc(iris, 0.0078, 0.002, Vector3(0, 0, -0.0094), _mat(iris_col, 0.0, 0.2))
		_disc(iris, 0.0042, 0.002, Vector3(0, 0, -0.0105), _mat(Color(0.03, 0.03, 0.03), 0.0, 0.1))
		_sphere(iris, 0.0016, Vector3(0.002, 0.0025, -0.0118), _mat(Color.WHITE, 1.5, 0.1))
		# upper lid crease and lashes line
		var lid := _box(head, Vector3(0.034, 0.004, 0.008), Vector3(0.036 * side, EYE_Y + 0.0125, -0.088), _mat(skin.darkened(0.18)))
		lid.rotation.z = -0.08 * side
		if female:
			_box(head, Vector3(0.03, 0.003, 0.006), Vector3(0.037 * side, EYE_Y + 0.009, -0.093), _mat(Color(0.05, 0.04, 0.04)))
		# brow
		var brow := _box(head, Vector3(0.036, 0.0075 if not female else 0.005, 0.012), Vector3(0.037 * side, EYE_Y + 0.027, -0.087), _mat(dark))
		brow.rotation = Vector3(0, -0.2 * side, -0.1 * side)
	# mouth: upper lip, lower lip and the dark inside that shows when talking
	var lip := _mat(skin.lerp(Color(0.62, 0.25, 0.26), 0.45 if female else 0.3), 0.0, 0.5)
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.043, -0.0895)
	head.add_child(mouth)
	var upper := _capsule(mouth, 0.0036, 0.04, Vector3(0, 0.0025, 0), lip)
	upper.rotation.z = PI * 0.5
	upper.scale = Vector3(1.0, 1.0, 1.25)
	_lower_lip = Node3D.new()
	_lower_lip.position = Vector3(0, -0.0045, 0)
	mouth.add_child(_lower_lip)
	var lower := _capsule(_lower_lip, 0.0045, 0.034, Vector3(0, -0.003, 0.0), lip)
	lower.rotation.z = PI * 0.5
	lower.scale = Vector3(1.0, 1.0, 1.2)
	_mouth_inner = Node3D.new()
	mouth.add_child(_mouth_inner)
	_box(_mouth_inner, Vector3(0.034, 0.0035, 0.008), Vector3(0, -0.0015, 0.003), _mat(Color(0.25, 0.08, 0.08)))
	# hair
	var hm := _mat(hair, 0.0, 0.75)
	var styles := ["short", "side", "bald", "short"] if not female else ["bun", "long", "bob"]
	if role == Role.AGENT and not female:
		styles = ["short", "short", "bald"]
	var style: String = styles.pick_random()
	if role == Role.GENERAL and style == "side":
		style = "short"
	if style != "bald":
		# The hair is the top of a slightly larger copy of the skull, cut on a
		# slope: high on the forehead, down over the ears, low at the nape.
		# A softer mound on top gives it some volume and hides the cut edge.
		var slope := {"side": 0.95, "short": 0.9, "bun": 0.82, "long": 0.74, "bob": 0.7}[style] as float
		var skull_scale := Vector3(0.9, 1.08, 0.98) * (0.97 if female else 1.0)
		var shell := _sphere(head, 0.1, Vector3(0, 0.105, 0), hm, skull_scale * 1.055, true)
		shell.rotation.x = slope
		_sphere(head, 0.085, Vector3(0, 0.148, 0.012), hm, Vector3(1.04, 0.9, 1.1))
		_sphere(head, 0.094, Vector3(0, 0.088, 0.03), hm, Vector3(0.98, 0.95, 0.92))   # back of the head
		for side in [-1.0, 1.0]:   # sideburns
			_box(head, Vector3(0.012, 0.035, 0.02), Vector3(0.0865 * side, 0.098, -0.01), hm)
	match style:
		"side":
			# a swept quiff over the forehead and a parting line
			var fr := _capsule(head, 0.03, 0.15, Vector3(0.012, 0.19, -0.06), hm)
			fr.rotation = Vector3(0.0, 0.0, PI * 0.5 - 0.15)
			fr.scale = Vector3(0.75, 1.0, 1.0)
			_box(head, Vector3(0.004, 0.006, 0.1), Vector3(-0.042, 0.226, 0.0), _mat(hair.darkened(0.5))).rotation.x = 0.15
		"bald":
			_sphere(head, 0.098, Vector3(0, 0.085, 0.03), hm, Vector3(0.96, 0.52, 0.92))
		"bun":
			_sphere(head, 0.042, Vector3(0, 0.16, 0.1), hm)
			var band := _torus(head, 0.028, 0.034, Vector3(0, 0.155, 0.075), _mat(dark))
			band.rotation.x = 1.1
		"long":
			# hair falling down the back, framing the face behind the ears
			var back := _capsule(head, 0.095, 0.34, Vector3(0, -0.01, 0.048), hm)
			back.scale = Vector3(1.0, 1.0, 0.5)
			for side in [-1.0, 1.0]:
				var strand := _capsule(head, 0.024, 0.2, Vector3(0.082 * side, 0.03, 0.022), hm)
				strand.scale = Vector3(0.8, 1.0, 1.0)
		"bob":
			for side in [-1.0, 1.0]:
				var b := _capsule(head, 0.032, 0.15, Vector3(0.084 * side, 0.068, 0.002), hm)
				b.rotation.x = -0.2
			_sphere(head, 0.098, Vector3(0, 0.06, 0.035), hm, Vector3(1.03, 0.75, 0.9))

	# facial hair (some men)
	if not female and role != Role.AGENT and randf() < 0.35:
		if randf() < 0.5:
			_box(head, Vector3(0.052, 0.012, 0.016), Vector3(0, 0.054, -0.103), _mat(dark))
		else:
			_sphere(head, 0.076, Vector3(0, 0.038, -0.02), _mat(hair, 0.0, 0.85), Vector3(1.02, 0.8, 1.0))
			_box(head, Vector3(0.05, 0.012, 0.016), Vector3(0, 0.055, -0.103), _mat(dark))
			mouth.position.z -= 0.006
	# glasses / sunglasses
	if role == Role.AGENT:
		var frame := _mat(Color(0.05, 0.05, 0.05), 0.0, 0.3)
		for side in [-1.0, 1.0]:
			var lens := _box(head, Vector3(0.038, 0.024, 0.004), Vector3(0.036 * side, EYE_Y, -0.1), _mat(Color(0.04, 0.05, 0.07), 0.0, 0.05, 0.3))
			lens.rotation.y = 0.12 * side
			_box(head, Vector3(0.004, 0.004, 0.09), Vector3(0.088 * side, EYE_Y + 0.008, -0.055), frame)
		_box(head, Vector3(0.09, 0.006, 0.006), Vector3(0, EYE_Y + 0.012, -0.102), frame)
		# earpiece and its clear coiled wire into the collar
		_sphere(head, 0.008, Vector3(0.092, 0.1, -0.005), _mat(Color(0.75, 0.75, 0.72), 0.0, 0.3))
		var wire := _cyl(head, 0.003, 0.003, 0.15, Vector3(0.085, 0.02, 0.025), _mat(Color(0.8, 0.82, 0.84), 0.0, 0.2))
		wire.rotation.x = 0.35
	elif randf() < 0.3 and role != Role.GENERAL:
		var frame := _mat([Color(0.1, 0.08, 0.06), GOLD, Color(0.35, 0.2, 0.12)].pick_random(), 0.0, 0.3, 0.3)
		for side in [-1.0, 1.0]:
			var ring := _torus(head, 0.0135, 0.0165, Vector3(0.036 * side, EYE_Y, -0.1), frame)
			ring.rotation.x = PI * 0.5
			_box(head, Vector3(0.003, 0.003, 0.09), Vector3(0.088 * side, EYE_Y + 0.004, -0.055), frame)
		_box(head, Vector3(0.024, 0.003, 0.003), Vector3(0, EYE_Y + 0.004, -0.102), frame)
	# general's peaked cap
	if role == Role.GENERAL:
		_cap = Node3D.new()
		_cap.position = Vector3(0, 0.185, 0.0)
		_cap.rotation.x = -0.06
		head.add_child(_cap)
		var cloth := _mat(Color(0.3, 0.36, 0.24))
		_cyl(_cap, 0.104, 0.098, 0.05, Vector3(0, 0.0, 0), cloth)
		_cyl(_cap, 0.125, 0.104, 0.035, Vector3(0, 0.05, -0.01), cloth, Vector3(1.0, 1.0, 1.08))
		_cyl(_cap, 0.105, 0.105, 0.022, Vector3(0, 0.005, 0), _mat(Color(0.12, 0.1, 0.08)))
		var visor := _cyl(_cap, 0.075, 0.075, 0.008, Vector3(0, -0.005, -0.085), _mat(Color(0.04, 0.04, 0.04), 0.0, 0.15), Vector3(1.0, 1.0, 0.65))
		visor.rotation.x = 0.25
		_box(_cap, Vector3(0.12, 0.006, 0.006), Vector3(0, 0.022, -0.1), _mat(GOLD, 0.2, 0.3, 0.6))   # chin cord
		_disc(_cap, 0.02, 0.006, Vector3(0, 0.05, -0.115), _mat(GOLD, 0.2, 0.3, 0.6))   # badge


func _folder(parent: Node3D, c: Color) -> Node3D:
	var f := Node3D.new()
	f.name = "Folder"
	f.position = Vector3(-0.03, 0.2, -0.17)
	f.rotation = Vector3(0.3, 0.25, -0.35)
	parent.add_child(f)
	_box(f, Vector3(0.23, 0.31, 0.012), Vector3.ZERO, _mat(c))
	_box(f, Vector3(0.22, 0.3, 0.004), Vector3(0.006, 0.004, 0.0), _mat(Color(0.98, 0.97, 0.93)))   # papers
	_disc(f, 0.035, 0.003, Vector3(0.0, 0.05, -0.007), _mat(GOLD, 0.0, 0.3, 0.5))
	_box(f, Vector3(0.12, 0.012, 0.002), Vector3(0, -0.04, -0.007), _mat(Color(0.98, 0.97, 0.93)))   # label
	return f


func _tablet(parent: Node3D) -> Node3D:
	var f := Node3D.new()
	f.name = "Tablet"
	f.position = Vector3(-0.03, 0.2, -0.17)
	f.rotation = Vector3(0.3, 0.25, -0.35)
	parent.add_child(f)
	_box(f, Vector3(0.18, 0.25, 0.01), Vector3.ZERO, _mat(Color(0.12, 0.12, 0.14), 0.0, 0.3))
	_box(f, Vector3(0.165, 0.228, 0.002), Vector3(0, 0, -0.0055), _mat(Color(0.55, 0.75, 0.95), 0.8, 0.1))
	return f


## A coffee cup on a saucer, origin at the bottom of the saucer.
static func make_cup() -> Node3D:
	var c := Node3D.new()
	c.name = "CoffeeCup"
	var china := _mat(Color(0.97, 0.97, 0.95), 0.0, 0.2)
	var gold_m := _mat(GOLD, 0.0, 0.3, 0.6)
	_cyl_s(c, 0.065, 0.05, 0.012, Vector3(0, 0.006, 0), china)
	_cyl_s(c, 0.066, 0.066, 0.003, Vector3(0, 0.0115, 0), gold_m)
	_cyl_s(c, 0.04, 0.03, 0.06, Vector3(0, 0.042, 0), china)
	_cyl_s(c, 0.0405, 0.0405, 0.005, Vector3(0, 0.07, 0), gold_m)
	_cyl_s(c, 0.036, 0.036, 0.002, Vector3(0, 0.067, 0), _mat(Color(0.25, 0.13, 0.06), 0.0, 0.1))
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.011
	tm.outer_radius = 0.018
	tm.rings = 12
	tm.ring_segments = 6
	handle.mesh = tm
	handle.material_override = china
	handle.position = Vector3(0.045, 0.045, 0)
	handle.rotation.x = PI * 0.5
	c.add_child(handle)
	return c


# ---------------------------------------------------------------- mesh helpers

func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.material_override = m
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "box%s" % size
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _mi(parent, _meshes[key], pos, m)


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, scl := Vector3.ONE, hemi := false) -> MeshInstance3D:
	var key := "sph%s|%s" % [r, hemi]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r if hemi else r * 2.0
		s.is_hemisphere = hemi
		var segs := 40 if r > 0.07 else (24 if r > 0.03 else (16 if r > 0.012 else 8))
		s.radial_segments = segs
		s.rings = segs / 2
		_meshes[key] = s
	return _mi(parent, _meshes[key], pos, m, scl)


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "cap%s|%s" % [r, h]
	if not _meshes.has(key):
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(h, r * 2.0)
		c.radial_segments = 16 if r > 0.02 else 8
		c.rings = 4 if r > 0.02 else 2
		_meshes[key] = c
	return _mi(parent, _meshes[key], pos, m)


## Upright cylinder centred at pos.
func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	return _cyl_s(parent, r_top, r_bottom, h, pos, m, scl)


static func _cyl_s(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var key := "cyl%s|%s|%s" % [r_top, r_bottom, h]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = r_top
		c.bottom_radius = r_bottom
		c.height = h
		c.radial_segments = 20 if maxf(r_top, r_bottom) > 0.03 else 10
		c.rings = 1
		_meshes[key] = c
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.position = pos
	mi.scale = scl
	mi.material_override = m
	parent.add_child(mi)
	return mi


## Flat disc facing -Z (the way the person faces), centred at pos.
func _disc(parent: Node3D, r: float, thick: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := _cyl(parent, r, r, thick, pos, m)
	mi.rotation.x = PI * 0.5
	return mi


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "tor%s|%s" % [inner, outer]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 20
		t.ring_segments = 6
		_meshes[key] = t
	return _mi(parent, _meshes[key], pos, m)


## Triangle (apex up, at `apex` across the width: 0 left, 1 right) extruded along Z.
func _prism(parent: Node3D, size: Vector3, pos: Vector3, m: Material, apex := 0.5) -> MeshInstance3D:
	var key := "pri%s|%s" % [size, apex]
	if not _meshes.has(key):
		var p := PrismMesh.new()
		p.size = size
		p.left_to_right = apex
		_meshes[key] = p
	return _mi(parent, _meshes[key], pos, m)


static func _mat(c: Color, emit := 0.0, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c.to_html(), emit, rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]
