extends "res://PresidentRoom/office_visitor.gd"
## The one person in room_quake.gd: an office worker at their desk when the
## big one hits.
##
## Same body as the office visitors (office_visitor.gd: flat colours, joints,
## blinking eyes), with its own poses instead of walking paths. room_quake.gd
## tells it what to do; positions are in the room's metres (its parent is the
## room's scaled holder).
##
##   sit_at(p, yaw)     at the desk, typing
##   duck_under(p, yaw, back)  aware: step back from the desk to `back` and
##                      drop down there, then shuffle in under it to `p`:
##                      cover the neck, hold on. (Dropping in front of the
##                      desk first keeps the head out of the desk top.)
##   crawl_out(yaw)     aware: once it stops, back out the way she went in,
##                      stand up and turn to `yaw`
##   panic()            unaware: jump up, arms over the head, turning about
##   run_to(p)          unaware: run for it (then climb_out() at the window)
##   climb_out(sill, vel, ground)   onto the sill and out; falls to `ground`
##
## Facing: the model looks down local -Z, like the other people in the project.

signal jumped   # through the glass
signal landed   # hit the ground below

enum Pose { SIT, STAND, DUCK, HOLD, CRAWL, PANIC, RUN, CLIMB, FALL, LIE }

const GRAVITY := 9.8
const SEAT_HIP := 0.55      # hip joint height when sitting (metres)
const CROUCH_HIP := 0.3     # hip joint height crouched under the desk
## duck_under(): step back and squat, then bend over, then shuffle in (seconds).
const FLINCH_TIME := 0.22
const SQUAT_TIME := 0.4
const BEND_TIME := 0.4
const SHUFFLE_TIME := 0.75
const LIE_HIP := 0.13       # how far the body is off the ground lying flat

var pose := Pose.SIT
var pose_t := 0.0

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _move_time := 1.0
var _to_yaw := 0.0
var _vel := Vector3.ZERO
var _ground := 0.0
var _run_speed := 3.2
var _spin := 0.0
var _tilt := Vector3.ZERO          # extra lean of the whole body (falling, lying)
var _tilt_to := Vector3.ZERO
var _panic_yaw := 0.0
var _back := Vector3.ZERO          # where duck_under() drops down, clear of the desk
var _start := Vector3.ZERO
var _start_yaw := 0.0
var _hide_yaw := 0.0


## Dress and build. Call once, before adding to the tree.
func make(p_female := true) -> void:
	build(Role.STAFFER, p_female)
	if _prop:
		_prop.visible = false   # no folder at their own desk
	state = State.ACT
	_reskin()


func sit_at(p: Vector3, yaw: float) -> void:
	position = p
	_yaw = yaw
	_rig.rotation.y = yaw
	_go(Pose.SIT)


func duck_under(p: Vector3, yaw: float, back: Vector3) -> void:
	_start = position
	_start_yaw = _yaw
	_back = back
	_to = p
	_to_yaw = yaw
	_hide_yaw = yaw
	_go(Pose.DUCK)


func crawl_out(face_yaw: float) -> void:
	_from = position
	_to = _back
	_move_time = SHUFFLE_TIME * 1.4
	_to_yaw = face_yaw
	_go(Pose.CRAWL)


func panic() -> void:
	_panic_yaw = _yaw
	_go(Pose.PANIC)


func run_to(p: Vector3) -> void:
	_to = Vector3(p.x, 0.0, p.z)
	_moving = 1.0
	_stride_amp = 0.62
	_go(Pose.RUN)


## Up onto the sill (`sill`, room metres) and out with `vel`, down to `ground`.
func climb_out(sill: Vector3, vel: Vector3, ground: float) -> void:
	_from = position
	_to = sill
	_move_time = 0.38
	_vel = vel
	_ground = ground
	_spin = randf_range(-1.5, 1.5)
	_go(Pose.CLIMB)
	jumped.emit()


func is_hiding() -> bool:
	return pose == Pose.HOLD or pose == Pose.DUCK


func has_landed() -> bool:
	return pose == Pose.LIE


func _go(p: Pose) -> void:
	pose = p
	pose_t = 0.0


func _move(p: Vector3, yaw: float, time: float) -> void:
	_from = position
	_to = p
	_to_yaw = yaw
	_move_time = maxf(time, 0.01)


# ================================================================ update

func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	pose_t += delta
	_rest_pose()
	_tilt_to = Vector3.ZERO
	match pose:
		Pose.SIT:
			_sit_pose()
		Pose.STAND:
			_stand_pose()
		Pose.DUCK:
			_duck()
		Pose.HOLD:
			_crouch_pose()
			# trembling, holding on to the desk leg
			_tp.spine.x += sin(_t * 23.0) * 0.025
			_tp.arm_r.x += sin(_t * 19.0 + 1.0) * 0.04
		Pose.CRAWL:
			# backing out: the duck's shuffle in reverse
			var k := smoothstep(0.0, 1.0, clampf(pose_t / _move_time, 0.0, 1.0))
			position = _from.lerp(_to, k)
			_yaw = lerp_angle(_hide_yaw, _start_yaw, k)
			_crouch_pose()
			if k >= 1.0:
				_go(Pose.STAND)
		Pose.PANIC:
			_panic_pose()
		Pose.RUN:
			_run(delta)
		Pose.CLIMB:
			_climb()
		Pose.FALL:
			_fall(delta)
		Pose.LIE:
			_lie_pose()
	_update_gaze(delta)
	_update_face(delta)
	_apply_pose(delta)
	if pose == Pose.FALL:
		_tilt = _tilt_to
	else:
		_tilt = _tilt.lerp(_tilt_to, 1.0 - exp(-delta * 10.0))
	_rig.rotation.x = _tilt.x
	_rig.rotation.z = _tilt.z


func _slide(_delta: float) -> void:
	var k := smoothstep(0.0, 1.0, clampf(pose_t / _move_time, 0.0, 1.0))
	position = _from.lerp(_to, k)
	_yaw = lerp_angle(_yaw, _to_yaw, minf(1.0, k * 1.5))


## Step back from the desk while squatting down, bend over, then shuffle in
## under it, turning to face along it.
func _duck() -> void:
	var t := pose_t - FLINCH_TIME
	if t < 0.0:
		# flinch: hands off the keyboard and in to the chest before dropping
		_sit_pose()
		_hands_in()
		_tp.head = Vector3(0.15, 0, 0)
	elif t < SQUAT_TIME:
		# back away from the desk first, then drop
		var u := t / SQUAT_TIME
		position = _start.lerp(_back, 1.0 - (1.0 - u) * (1.0 - u))
		_squat_pose()
		_rig_y = lerpf(_scaled_hip(SEAT_HIP), _rig_y, smoothstep(0.35, 1.0, u))
	elif t < SQUAT_TIME + BEND_TIME:
		position = _back
		_crouch_pose()
	else:
		var k := smoothstep(0.0, 1.0, clampf((t - SQUAT_TIME - BEND_TIME) / SHUFFLE_TIME, 0.0, 1.0))
		position = _back.lerp(_to, k)
		_yaw = lerp_angle(_start_yaw, _to_yaw, k)
		_crouch_pose()
		if k >= 1.0:
			_go(Pose.HOLD)


func _run(delta: float) -> void:
	var to := _to - position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.02:
		var dir := to / dist
		_yaw = lerp_angle(_yaw, _yaw_to(dir), minf(1.0, delta * 12.0))
		var step := minf(_run_speed * delta, dist)
		position += dir * step
		_phase += step / 1.6 * TAU
	_walk_pose()
	# arms up and flailing instead of swinging
	_tp.arm_l = Vector3(2.2 + sin(_t * 17.0) * 0.5, 0, -0.35)
	_tp.arm_r = Vector3(2.2 + sin(_t * 17.0 + 2.0) * 0.5, 0, 0.35)
	_tp.elbow_l = Vector3(0.6, 0, 0)
	_tp.elbow_r = Vector3(0.6, 0, 0)
	_tp.spine.x -= 0.15


func _climb() -> void:
	var k := clampf(pose_t / _move_time, 0.0, 1.0)
	var p := _from.lerp(_to, k)
	p.y += sin(k * PI) * 0.25
	position = p
	# one knee up onto the sill, arms out at the glass
	_tp.leg_l = Vector3(1.5, 0, -0.05)
	_tp.knee_l = Vector3(-1.7, 0, 0)
	_tp.leg_r = Vector3(-0.3, 0, 0.05)
	_tp.knee_r = Vector3(-0.4, 0, 0)
	_tp.arm_l = Vector3(1.6, 0, -0.3)
	_tp.arm_r = Vector3(1.6, 0, 0.3)
	_tp.elbow_l = Vector3(0.5, 0, 0)
	_tp.elbow_r = Vector3(0.5, 0, 0)
	_tp.spine = Vector3(-0.4, 0, 0)
	_tilt_to = Vector3(-0.5, 0, 0)   # ducking under the top of the frame
	if k >= 1.0:
		_go(Pose.FALL)


func _fall(delta: float) -> void:
	_vel.y -= GRAVITY * delta
	position += _vel * delta
	_yaw += _spin * delta
	var t := _t
	# flailing: arms windmill overhead, legs kick (like QuakePerson)
	_tp.arm_l = Vector3(PI * 0.85 + sin(t * 20.0) * 0.6, 0, -0.5)
	_tp.arm_r = Vector3(PI * 0.85 + sin(t * 20.0 + 2.0) * 0.6, 0, 0.5)
	_tp.elbow_l = Vector3(0.4, 0, 0)
	_tp.elbow_r = Vector3(0.4, 0, 0)
	_tp.leg_l = Vector3(sin(t * 16.0) * 0.9, 0, -0.1)
	_tp.leg_r = Vector3(-sin(t * 16.0) * 0.9, 0, 0.1)
	_tp.knee_l = Vector3(-0.6, 0, 0)
	_tp.knee_r = Vector3(-0.6, 0, 0)
	_tp.head = Vector3(0.4, 0, 0)
	_rig_y = 0.0
	_tilt_to = Vector3(-minf(pose_t * 1.1, 1.3), 0, 0)
	if position.y <= _ground:
		position.y = _ground
		_go(Pose.LIE)
		landed.emit()


# ================================================================ poses

func _scaled_hip(h: float) -> float:
	return h / maxf(scale.y, 0.01) - HIP_Y


func _sit_pose() -> void:
	_rig_y = _scaled_hip(SEAT_HIP)
	_tp.spine = Vector3(-0.08, 0, 0)
	_tp.leg_l = Vector3(1.5, 0, -0.05)
	_tp.leg_r = Vector3(1.5, 0, 0.05)
	_tp.knee_l = Vector3(-1.45, 0, 0)
	_tp.knee_r = Vector3(-1.45, 0, 0)
	_tp.foot_l = Vector3(0.0, 0, 0)
	_tp.foot_r = Vector3(0.0, 0, 0)
	# forearms out to the keyboard, fingers tapping
	# (upper arms well forward so the forearms float just over the desk top)
	_tp.arm_l = Vector3(1.05, 0, -0.12)
	_tp.arm_r = Vector3(1.05, 0, 0.12)
	_tp.elbow_l = Vector3(0.64 + sin(_t * 13.0) * 0.03, 0, 0)
	_tp.elbow_r = Vector3(0.64 + sin(_t * 11.0 + 1.3) * 0.03, 0, 0)
	_tp.hand_l = Vector3(-0.1, 0, 0.1)
	_tp.hand_r = Vector3(-0.1, 0, -0.1)
	_tp.fingers_l = Vector3(-0.15, 0, 0.1)
	_tp.fingers_r = Vector3(-0.15, 0, -0.1)
	_tp.head = Vector3(-0.1, 0, 0)


func _stand_pose() -> void:
	# shaken, looking round the room
	_rig_y = 0.0
	_tp.arm_l = Vector3(0.15, 0, -0.18)
	_tp.arm_r = Vector3(0.15, 0, 0.18)
	_tp.head = Vector3(0.05, sin(_t * 0.9) * 0.5, 0)
	_yaw = lerp_angle(_yaw, _to_yaw, minf(1.0, get_process_delta_time() * 3.0))


## Drop, cover, hold on: down on the heels, bent right over with the back
## flat and low, the left arm over the back of the neck and the right hand
## down on the floor by the desk leg. Kept under the desk top (0.74 m).
func _crouch_pose() -> void:
	_rig_y = _scaled_hip(CROUCH_HIP)
	_tp.hips = Vector3.ZERO
	_tp.spine = Vector3(-1.3, 0, 0)
	_tp.head = Vector3(-0.45, 0, 0)
	_tp.leg_l = Vector3(1.4, 0, -0.14)
	_tp.leg_r = Vector3(1.4, 0, 0.14)
	_tp.knee_l = Vector3(-2.6, 0, 0)
	_tp.knee_r = Vector3(-2.6, 0, 0)
	_tp.foot_l = Vector3(1.15, 0, 0)
	_tp.foot_r = Vector3(1.15, 0, 0)
	# left forearm over the back of the neck, hand on the nape
	_tp.arm_l = Vector3(1.75, 0, 0.55)
	_tp.elbow_l = Vector3(1.9, 0, 0)
	_tp.hand_l = Vector3(0.3, 0, 0.4)
	_tp.fingers_l = Vector3(0, 0, 0.4)
	# right arm down to the floor, holding on
	_tp.arm_r = Vector3(0.75, 0, 0.3)
	_tp.elbow_r = Vector3(0.35, 0, 0)
	_tp.hand_r = Vector3(0.4, 0, 0)
	_tp.fingers_r = Vector3(0, 0, -0.9)


## Squatting down on the way under: back fairly straight, hands in.
func _squat_pose() -> void:
	_rig_y = _scaled_hip(CROUCH_HIP)
	_tp.spine = Vector3(-0.35, 0, 0)
	_tp.head = Vector3(0.1, 0, 0)
	_tp.leg_l = Vector3(1.4, 0, -0.14)
	_tp.leg_r = Vector3(1.4, 0, 0.14)
	_tp.knee_l = Vector3(-2.6, 0, 0)
	_tp.knee_r = Vector3(-2.6, 0, 0)
	_tp.foot_l = Vector3(1.15, 0, 0)
	_tp.foot_r = Vector3(1.15, 0, 0)
	_hands_in()


## Forearms folded up, hands at the chest: lifts them off the desk without
## dragging the elbows through its edge.
func _hands_in() -> void:
	_tp.arm_l = Vector3(0.5, 0, -0.15)
	_tp.arm_r = Vector3(0.5, 0, 0.15)
	_tp.elbow_l = Vector3(2.3, 0, 0)
	_tp.elbow_r = Vector3(2.3, 0, 0)


func _panic_pose() -> void:
	# up out of the chair, hands on the head, turning one way then the other
	_rig_y = maxf(0.0, sin(_t * 9.0)) * 0.03
	var t := _t
	_tp.arm_l = Vector3(PI * 0.85 + sin(t * 12.0) * 0.35, 0, -0.4)
	_tp.arm_r = Vector3(PI * 0.85 + sin(t * 12.0 + 1.5) * 0.35, 0, 0.4)
	_tp.elbow_l = Vector3(0.9, 0, 0)
	_tp.elbow_r = Vector3(0.9, 0, 0)
	_tp.head = Vector3(0.1, sin(t * 6.0) * 0.6, 0)
	_tp.spine = Vector3(0.05, sin(t * 3.0) * 0.2, 0)
	_yaw = _panic_yaw + sin(pose_t * 4.5) * 1.1


## Face down on the pavement, one leg twisted out to the side, an arm moving
## now and then.
func _lie_pose() -> void:
	_rig_y = LIE_HIP / maxf(scale.y, 0.01)
	_tilt_to = Vector3(-PI * 0.5, 0, 0)
	_tp.spine = Vector3(0, 0, 0.1)
	_tp.head = Vector3(0.3, 1.1, 0)
	_tp.arm_l = Vector3(PI * 0.8, 0, -0.5 + sin(_t * 0.7) * 0.06)
	_tp.elbow_l = Vector3(0.5, 0, 0)
	_tp.arm_r = Vector3(0.1, 0, 0.6)
	_tp.elbow_r = Vector3(0.3, 0, 0)
	_tp.leg_l = Vector3(0.0, 0, -0.15)
	_tp.knee_l = Vector3(0.0, 0, 0)
	_tp.leg_r = Vector3(0.0, 0.6, 0.55)
	_tp.knee_r = Vector3(0.0, 0, -0.6)
	_tp.foot_l = Vector3(-0.8, 0, 0)
	_tp.foot_r = Vector3(-0.8, 0, 0)


# ================================================================ her face

## Her look is fixed: medium skin, straight black hair.
const SKIN_TONE := Color(0.78, 0.56, 0.42)
const HAIR_BLACK := Color(0.05, 0.04, 0.045)
## An oval face: narrow, long, rounded.
const HEAD_SCALE := Vector3(0.8, 1.12, 0.92)

var _picked_skin := Color.BLACK   # the skin the visitor code chose, swapped in _reskin()


## The visitor code picks a random skin for the hands, neck and legs; swap
## every piece of it for SKIN_TONE so the body matches the face.
func _reskin() -> void:
	var from := [_picked_skin, _picked_skin.darkened(0.12)]
	var to := [SKIN_TONE, SKIN_TONE.darkened(0.12)]
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		for i in from.size():
			if m.albedo_color.is_equal_approx(from[i]):
				(mi as MeshInstance3D).material_override = _mat(to[i], 0.0, m.roughness)


## Her own head, replacing the visitors': one smooth oval (no separate chin,
## jaw or nose lumps), big almond eyes with lashes, a small soft nose, tinted
## lips, and plain straight black hair, nothing on top. Keeps the eyes /
## irises / mouth the visitor code blinks, glances and talks with.
func _head(head: Node3D, skin: Color, _hair: Color) -> void:
	_picked_skin = skin
	var sk := _mat(SKIN_TONE, 0.0, 0.55)
	# the face: a single smooth oval
	_sphere(head, 0.1, Vector3(0, 0.1, -0.004), sk, HEAD_SCALE)
	# nose: small, soft, barely rising from the face
	_sphere(head, 0.009, Vector3(0, 0.085, -0.093), sk, Vector3(0.7, 1.3, 0.7))
	_sphere(head, 0.0075, Vector3(0, 0.075, -0.0955), sk, Vector3(1.1, 0.8, 0.85))
	# big almond eyes: white, iris, pupil, a glint; blink by squashing the eye
	var lash := _mat(Color(0.04, 0.03, 0.03), 0.0, 0.5)
	var iris_col := Color(0.3, 0.18, 0.1)
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.03 * side, EYE_Y, -0.0785)
		head.add_child(eye)
		_eyes.append(eye)
		_sphere(eye, 0.0185, Vector3.ZERO, _mat(Color(0.97, 0.96, 0.94), 0.0, 0.2), Vector3(1.05, 0.8, 0.55))
		var iris := Node3D.new()
		eye.add_child(iris)
		_irises.append(iris)
		_disc(iris, 0.0105, 0.002, Vector3(0, 0, -0.0095), _mat(iris_col, 0.0, 0.2))
		_disc(iris, 0.0055, 0.002, Vector3(0, 0, -0.0106), _mat(Color(0.02, 0.02, 0.02), 0.0, 0.1))
		_sphere(iris, 0.002, Vector3(0.003, 0.0035, -0.012), _mat(Color.WHITE, 1.5, 0.1))
		# upper lash line, flicked up at the outer corner
		var l1 := _box(eye, Vector3(0.039, 0.0036, 0.007), Vector3(0, 0.0135, -0.006), lash)
		l1.rotation.z = -0.08 * side
		var l2 := _box(eye, Vector3(0.01, 0.0034, 0.006), Vector3(0.021 * side, 0.016, -0.003), lash)
		l2.rotation.z = 0.55 * side
		# thin arched brow
		var brow := _capsule(head, 0.0017, 0.032, Vector3(0.032 * side, EYE_Y + 0.027, -0.085), _mat(HAIR_BLACK, 0.0, 0.7))
		brow.rotation = Vector3(0.0, -0.25 * side, PI * 0.5 + 0.1 * side)
	# a hint of blush
	for side in [-1.0, 1.0]:
		_disc(head, 0.01, 0.001, Vector3(0.046 * side, 0.07, -0.08), _mat(SKIN_TONE.lerp(Color(0.9, 0.45, 0.45), 0.15), 0.0, 0.7)) \
			.rotation = Vector3(PI * 0.5, -0.55 * side, 0)
	# mouth: tinted lips and the dark inside that shows when talking
	var lip := _mat(SKIN_TONE.lerp(Color(0.72, 0.3, 0.33), 0.5), 0.0, 0.45)
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.043, -0.083)
	head.add_child(mouth)
	var upper := _capsule(mouth, 0.0033, 0.03, Vector3(0, 0.0022, 0), lip)
	upper.rotation.z = PI * 0.5
	_lower_lip = Node3D.new()
	_lower_lip.position = Vector3(0, -0.004, 0)
	mouth.add_child(_lower_lip)
	var lower := _capsule(_lower_lip, 0.004, 0.026, Vector3(0, -0.002, 0.001), lip)
	lower.rotation.z = PI * 0.5
	_mouth_inner = Node3D.new()
	mouth.add_child(_mouth_inner)
	_box(_mouth_inner, Vector3(0.026, 0.003, 0.006), Vector3(0, -0.001, 0.003), _mat(Color(0.3, 0.1, 0.1)))
	# straight black hair: one smooth shell a little bigger than the head and
	# set back, so the face comes through it at the hairline; then straight
	# lengths down the back and either side of the face to the shoulders
	var hm := _mat(HAIR_BLACK, 0.0, 0.45)
	_sphere(head, 0.1, Vector3(0, 0.112, 0.016), hm, HEAD_SCALE * Vector3(1.1, 1.05, 1.06))
	var back := _box(head, Vector3(0.17, 0.3, 0.05), Vector3(0, -0.06, 0.05), hm)
	back.rotation.x = -0.08
	for side in [-1.0, 1.0]:
		var length := _box(head, Vector3(0.025, 0.27, 0.07), Vector3(0.078 * side, -0.02, 0.0), hm)
		length.rotation.z = 0.03 * side
