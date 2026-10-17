extends Node3D
## One person, one room, when the big one hits: a place in the earthquake
## ending (earthquake_ending.gd, played by day_cycle.gd). Across town, on the
## third floor of an office block, someone is working through lunch at their
## desk. What they do next comes from one stat:
##
##   People's Awareness  AWARE_FROM (50) or more: they know what to do. Drop,
##                       cover, hold on: under the desk, one hand on its leg,
##                       the other over the neck. The books come off the shelf
##                       and the ceiling lamp crashes down where they were
##                       sitting; when it stops they crawl out unhurt. (The
##                       poster on the wall is the awareness campaign's.)
##                       Below it: nobody ever told them. They panic, run for
##                       the window and jump through it. Then the street below:
##                       the building they ran from is still standing, and they
##                       are lying on the pavement with a broken leg.
##
## Everything is built from code in the project's flat-colour style (boxes,
## cylinders, the city palette) out in empty space away from the city, at
## ORIGIN, so it can't get in the way of anything. Built in metres under a
## holder scaled by S, so the city camera's near plane doesn't cut into it.
##
## day_cycle.gd drives it:
##   setup(ending)                 build it; reads the awareness stat
##   calm_shot() / quake_shot() / after_shot() / street_shot()
##                                 [eye, look, creep] in world space for _glide
##   quake()                       the ground goes
##   is_done()                     the shaking is over and they've done it
##   recover()                     aware: crawl out from under the desk
##   intro_line() / react_line() / after_line()   the narration
##   signals shattered (window), crashed (the lamp)   for camera jolts

signal shattered
signal crashed

const RoomNpc := preload("res://PresidentRoom/room_quake_npc.gd")

## Awareness at or above this and they hide properly under the desk.
const AWARE_FROM := 50.0
## Where the room is, in the city's space: far out of the way of everything.
const ORIGIN := Vector3(-7000.0, 1800.0, 7000.0)
## World units per metre.
const S := 10.0
## How long the room shakes (seconds); day_cycle.gd rumbles for this long.
const SHAKE_TIME := 7.0
## The street is two floors down.
const GROUND := -6.0
const FLOOR_H := 3.0
## Room: x from -HALF_X (window wall) to HALF_X, z from -HALF_Z (desk wall) to HALF_Z.
const HALF_X := 2.2
const HALF_Z := 1.8
const CEIL := 2.7
## The window in the left wall (z range and height).
const WIN_Z0 := -0.9
const WIN_Z1 := 0.5
const SILL := 0.85
const WIN_TOP := 2.15
## Desk against the back wall.
const DESK_X := 0.5
const DESK_W := 1.4
const DESK_D := 0.72
const DESK_H := 0.78
const CHAIR := Vector3(0.3, 0.0, -0.75)
## Aware: hiding spot under the desk (facing +X, along it).
const HIDE_AT := Vector3(0.5, 0.0, -1.42)
## Aware: where she drops down before going under, and backs out to after.
const DUCK_FROM := Vector3(0.75, 0.0, -0.3)
## Aware: the camera on her when she comes back out.
const AFTER_EYE := Vector3(1.95, 1.45, 1.35)
## When things happen, in seconds after the quake starts.
const LAMP_DROP := 3.1
const MUG_DROP := 1.4

const NAMES_F := ["Selin", "Maya", "Leyla", "Nora", "Elif", "Hana"]

# flat colours, like president_room.gd and the civic buildings
const PALETTE := [
	Color8(97, 203, 140), Color8(33, 141, 109), Color8(255, 192, 68), Color8(255, 154, 50),
	Color8(254, 127, 68), Color8(245, 104, 67), Color8(208, 83, 80), Color8(102, 148, 217),
	Color8(90, 95, 200),
]
const WALL := Color(0.93, 0.9, 0.82)
const TRIM := Color(0.96, 0.95, 0.91)
const CEILING := Color(0.97, 0.96, 0.93)
const FLOOR_A := Color(0.62, 0.45, 0.28)
const FLOOR_B := Color(0.56, 0.4, 0.24)
const WOOD := Color(0.5, 0.33, 0.2)
const WOOD_DARK := Color(0.3, 0.19, 0.11)
const METAL := Color(0.16, 0.16, 0.18)
const GLASS := Color(0.7, 0.86, 0.96, 0.28)
const WINDOW_DARK := Color(0.22, 0.32, 0.45)
const FACADE := Color8(245, 104, 67)
const PAVEMENT := Color(0.74, 0.73, 0.7)
const ROAD := Color(0.24, 0.25, 0.28)
const FONT := "res://PresidentRoom/fonts/Montserrat-ExtraBold.ttf"

var aware := true
var person_name := "Selin"
var female := true

var _m: Node3D                # everything, in metres (scaled by S)
var _npc: RoomNpc
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _quake_t := -1.0
var _shaking := false
var _done := false
var _jumped := false
var _lamp_fallen := false
var _mug_fallen := false
var _recovered := false

var _light: OmniLight3D
var _light_energy := 1.6
var _lamp: Node3D
var _lamp_bulb: MeshInstance3D
var _chair: Node3D
var _mug: Node3D
var _monitor: Node3D
var _picture: Node3D
var _glass: MeshInstance3D
var _books: Array[Node3D] = []
var _falling: Array[Dictionary] = []   # {n, v, w, floor, flat}


## Build the room and the person. `ending` is earthquake_ending.gd.
func setup(ending) -> bool:
	_rng.randomize()
	aware = float(ending.stat("awareness")) >= AWARE_FROM
	female = true
	person_name = NAMES_F[_rng.randi() % NAMES_F.size()]
	position = ORIGIN
	_m = Node3D.new()
	_m.name = "Metres"
	_m.scale = Vector3.ONE * S
	add_child(_m)
	_build_room()
	_build_outside()
	_build_person()
	return true


# ================================================================ words

func _she() -> String:
	return "she" if female else "he"


func _her() -> String:
	return "her" if female else "his"


func intro_line() -> String:
	return "Across town, at the same moment. On the third floor of an office block, *%s* is working through lunch." \
		% person_name


## Read while it happens.
func react_line() -> String:
	if aware:
		return "*%s* knows exactly what to do, because *you* made sure this city learned it. *Drop, cover, hold on*: under the desk, one hand on its leg, the other over %s neck." \
			% [person_name, _her()]
	return "Nobody ever told *%s* what to do in an earthquake. %s panics, and runs for the *window*." \
		% [person_name, _she().capitalize()]


## Read once it's over.
func after_line() -> String:
	if aware:
		return "The ceiling lamp comes down right where %s was sitting. When the shaking stops, %s crawls out without a scratch. Your work on *public awareness* just saved %s life." \
			% [_she(), _she(), _her()]
	return "%s jumped from the third floor. The building %s ran from is still standing. It wasn't the earthquake that broke %s legs, it was the *fall*." \
		% [_she().capitalize(), _she(), _her()]


# ================================================================ camera

## [eye, look, creep] in world space.
func _shot(eye: Vector3, look: Vector3, creep := Vector3.ZERO) -> Array:
	return [to_global(eye * S), to_global(look * S), creep * S]


## The room from the corner by the door: the desk, the shelf, the window.
func calm_shot() -> Array:
	return _shot(Vector3(1.9, 1.75, 1.6), Vector3(-0.3, 0.95, -0.9), Vector3(-0.15, -0.05, -0.12))


## While it shakes: down low to see under the desk, or round to the window.
func quake_shot() -> Array:
	if aware:
		return _shot(Vector3(1.75, 0.95, 0.95), Vector3(0.55, 0.5, -1.35))
	return _shot(Vector3(1.8, 1.6, 1.4), Vector3(-1.7, 1.0, -0.35))


## Aware, afterwards: close on the desk as they come out.
func after_shot() -> Array:
	return _shot(AFTER_EYE, Vector3(0.6, 0.85, -0.9), Vector3(-0.1, 0.0, -0.1))


## Unaware, afterwards: across the street, the building and the pavement.
func street_shot() -> Array:
	return _shot(Vector3(-13.6, GROUND + 0.8, 5.0), Vector3(-4.6, GROUND + 3.0, -0.2), Vector3(0.5, 0.0, -0.3))


# ================================================================ the quake

func quake() -> void:
	_quake_t = 0.0
	_shaking = true


func is_done() -> bool:
	return _done


func recover() -> void:
	if _recovered or _npc == null:
		return
	_recovered = true
	if aware:
		var d := AFTER_EYE - DUCK_FROM
		_npc.crawl_out(atan2(-d.x, -d.z))


func _process(delta: float) -> void:
	_update_falling(delta)
	if _quake_t < 0.0:
		return
	_quake_t += delta
	var t := _quake_t
	var shake := 0.0
	if _shaking:
		shake = clampf(t / 0.6, 0.0, 1.0) * clampf((SHAKE_TIME - t) / 1.5, 0.0, 1.0)
		if t >= SHAKE_TIME:
			_shaking = false
			shake = 0.0

	_jitter(shake)
	_flicker(shake)
	_drop_things(t)
	_drive_person(t)

	if not _done and t >= SHAKE_TIME and (aware or _npc.has_landed()):
		_done = true


## Everything loose rattles: the monitor rocks, the picture swings, the lamp
## sways on its cord, the books shuffle on the shelf.
func _jitter(s: float) -> void:
	var t := _quake_t
	if _monitor:
		_monitor.rotation.z = sin(t * 17.0) * 0.06 * s
	if _picture:
		var crooked := 0.16 if t > 1.5 else 0.0
		_picture.rotation.z = lerpf(_picture.rotation.z, crooked + sin(t * 9.0) * 0.18 * s, 0.2)
	if _lamp and not _lamp_fallen:
		_lamp.rotation.x = sin(t * 5.3) * 0.35 * s
		_lamp.rotation.z = sin(t * 4.1 + 1.0) * 0.3 * s
	for b in _books:
		if not b.has_meta("fallen"):
			b.rotation.x = sin(t * 23.0 + b.position.z * 40.0) * 0.05 * s


func _flicker(s: float) -> void:
	if _light == null:
		return
	var on := _light_energy * (0.35 if _lamp_fallen else 1.0)
	if s > 0.05 and _rng.randf() < 0.12 * s:
		on *= _rng.randf_range(0.0, 0.4)
	_light.light_energy = on


func _drop_things(t: float) -> void:
	# books come off the shelf a few at a time
	for b in _books:
		if b.has_meta("fallen") or t < float(b.get_meta("drop_at", 99.0)):
			continue
		b.set_meta("fallen", true)
		_fall(b, Vector3(-_rng.randf_range(0.7, 1.5), _rng.randf_range(0.0, 0.6), _rng.randf_range(-0.3, 0.3)),
			Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-3, 3), _rng.randf_range(-6, 6)), 0.035, true)
	if not _mug_fallen and t >= MUG_DROP and _mug:
		_mug_fallen = true
		_fall(_mug, Vector3(0.1, 1.2, 1.4), Vector3(4.0, 0.0, 3.0), 0.05, true)
	if not _lamp_fallen and t >= LAMP_DROP and _lamp:
		_lamp_fallen = true
		_lamp_bulb.material_override = _mat(Color(0.35, 0.33, 0.3))
		_lamp.rotation = Vector3.ZERO
		_fall(_lamp, Vector3(0.0, -0.5, 0.0), Vector3.ZERO, 0.8)
		crashed.emit()


func _drive_person(t: float) -> void:
	if _npc == null:
		return
	if aware:
		if t >= 0.6 and _npc.pose == RoomNpc.Pose.SIT:
			# chair shoved back, down under the desk facing the room
			_push_chair(Vector3(-0.8, 0.0, 0.5), 0.6)
			_npc.duck_under(HIDE_AT, -PI * 0.5, DUCK_FROM)
		return
	var pose := _npc.pose
	if pose == RoomNpc.Pose.SIT:
		if t >= 0.5:
			_push_chair(Vector3(0.25, 0.0, 0.6), 0.0)
			_knock_chair_over()
			_npc.panic()
	elif pose == RoomNpc.Pose.PANIC:
		if _npc.pose_t >= 1.3:
			_npc.run_to(Vector3(-HALF_X + 0.45, 0.0, (WIN_Z0 + WIN_Z1) * 0.5))
	elif pose == RoomNpc.Pose.RUN:
		if _npc.position.x <= -HALF_X + 0.5:
			var mid := (WIN_Z0 + WIN_Z1) * 0.5
			_npc.climb_out(Vector3(-HALF_X - 0.1, SILL - 0.25, mid), Vector3(-2.6, 1.6, 0.0), GROUND)


func _push_chair(by: Vector3, turn: float) -> void:
	if _chair == null:
		return
	var t := create_tween().set_parallel()
	t.tween_property(_chair, "position", _chair.position + by, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_chair, "rotation:y", _chair.rotation.y + turn, 0.4)


func _knock_chair_over() -> void:
	if _chair == null:
		return
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(_chair, "rotation:x", 1.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_jumped() -> void:
	if _jumped:
		return
	_jumped = true
	if _glass:
		var at := _glass.position
		_glass.visible = false
		for k in 16:
			var shard := _box(_m, Vector3(0.015, _rng.randf_range(0.08, 0.22), _rng.randf_range(0.06, 0.2)),
				at + Vector3(0, _rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.65, 0.65)), _glass_mat(), false)
			_fall(shard, Vector3(-_rng.randf_range(1.5, 3.5), _rng.randf_range(-0.5, 1.5), _rng.randf_range(-0.8, 0.8)),
				Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-9, 9), _rng.randf_range(-9, 9)), GROUND + 0.01)
	shattered.emit()


# ================================================================ falling things

## Drop `n` with velocity `v` and spin `w` until it reaches `floor_y`. `flat`:
## it lands lying on its side (books, the mug); otherwise as it is.
func _fall(n: Node3D, v: Vector3, w: Vector3, floor_y: float, flat := false) -> void:
	_falling.append({"n": n, "v": v, "w": w, "floor": floor_y, "flat": flat})


func _update_falling(delta: float) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		var n: Node3D = f.n
		if not is_instance_valid(n):
			_falling.remove_at(i)
			continue
		f.v.y -= 9.8 * delta
		n.position += f.v * delta
		n.rotation += f.w * delta
		if n.position.y <= f.floor:
			n.position.y = f.floor
			if f.flat:
				n.rotation = Vector3(PI * 0.5 * (1.0 if n.rotation.x >= 0.0 else -1.0), n.rotation.y, 0.0)
			elif n == _lamp:
				n.rotation = Vector3(0.0, n.rotation.y, 0.35)   # lands tipped on its shade
			_falling.remove_at(i)


# ================================================================ the person

func _build_person() -> void:
	_npc = RoomNpc.new()
	_npc.name = "Person"
	_npc.make(female)
	_m.add_child(_npc)
	_npc.sit_at(CHAIR + Vector3(0.0, 0.0, -0.02), 0.0)
	_npc.jumped.connect(_on_jumped)


# ================================================================ the room

func _build_room() -> void:
	var room := _group(_m, "Room")
	# floor boards
	for k in 11:
		var x := -HALF_X + (k + 0.5) * (HALF_X * 2.0 / 11.0)
		_box(room, Vector3(HALF_X * 2.0 / 11.0, 0.1, HALF_Z * 2.0), Vector3(x, -0.1, 0), _mat(FLOOR_A if k % 2 == 0 else FLOOR_B))
	_box(room, Vector3(HALF_X * 2.0, 0.12, HALF_Z * 2.0), Vector3(0, CEIL, 0), _mat(CEILING))
	# walls (back with the desk, the door wall on the right, the front behind the camera)
	_box(room, Vector3(HALF_X * 2.0, CEIL, 0.12), Vector3(0, 0, -HALF_Z - 0.06), _mat(WALL))
	_box(room, Vector3(HALF_X * 2.0, CEIL, 0.12), Vector3(0, 0, HALF_Z + 0.06), _mat(WALL))
	_box(room, Vector3(0.12, CEIL, HALF_Z * 2.0), Vector3(HALF_X + 0.06, 0, 0), _mat(WALL))
	# the window wall's inside face, around the opening (the outside is the facade)
	var x_in := -HALF_X + 0.005
	_box(room, Vector3(0.01, SILL, HALF_Z * 2.0), Vector3(x_in, 0, 0), _mat(WALL))
	_box(room, Vector3(0.01, CEIL - WIN_TOP, HALF_Z * 2.0), Vector3(x_in, WIN_TOP, 0), _mat(WALL))
	_box(room, Vector3(0.01, WIN_TOP - SILL, WIN_Z0 + HALF_Z), Vector3(x_in, SILL, (-HALF_Z + WIN_Z0) * 0.5), _mat(WALL))
	_box(room, Vector3(0.01, WIN_TOP - SILL, HALF_Z - WIN_Z1), Vector3(x_in, SILL, (WIN_Z1 + HALF_Z) * 0.5), _mat(WALL))
	# skirting boards
	_box(room, Vector3(HALF_X * 2.0, 0.09, 0.02), Vector3(0, 0, -HALF_Z + 0.01), _mat(TRIM))
	_box(room, Vector3(0.02, 0.09, HALF_Z * 2.0), Vector3(HALF_X - 0.01, 0, 0), _mat(TRIM))
	_box(room, Vector3(0.02, 0.09, HALF_Z * 2.0), Vector3(-HALF_X + 0.02, 0, 0), _mat(TRIM))

	_build_window(room)
	_build_desk(room)
	_build_chair(room)
	_build_shelf(room)
	_build_lamp(room)
	_build_wall_things(room)

	_light = OmniLight3D.new()
	_light.name = "RoomLight"
	_light.position = Vector3(0.2, CEIL - 0.6, -0.3) * S
	_light.omni_range = 6.0 * S
	_light.omni_attenuation = 1.2
	_light.light_color = Color(1.0, 0.9, 0.74)
	_light.light_energy = _light_energy
	_light.shadow_enabled = true
	add_child(_light)


func _build_window(room: Node3D) -> void:
	var w := WIN_Z1 - WIN_Z0
	var h := WIN_TOP - SILL
	var mid := (WIN_Z0 + WIN_Z1) * 0.5
	var frame := _mat(TRIM)
	var x := -HALF_X - 0.1
	_box(room, Vector3(0.24, 0.05, w + 0.12), Vector3(x + 0.04, SILL - 0.05, mid), frame)   # sill
	_box(room, Vector3(0.2, 0.06, w + 0.12), Vector3(x, WIN_TOP, mid), frame)
	_box(room, Vector3(0.2, h, 0.06), Vector3(x, SILL, WIN_Z0 - 0.03), frame)
	_box(room, Vector3(0.2, h, 0.06), Vector3(x, SILL, WIN_Z1 + 0.03), frame)
	_glass = _box(room, Vector3(0.02, h, w), Vector3(x, SILL, mid), _glass_mat(), false)
	# a curtain each side
	for z in [WIN_Z0 - 0.14, WIN_Z1 + 0.14]:
		_box(room, Vector3(0.06, h + 0.35, 0.22), Vector3(-HALF_X + 0.06, SILL - 0.1, z), _mat(PALETTE[7].darkened(0.1)))


func _build_desk(room: Node3D) -> void:
	var g := _group(room, "Desk", Vector3(DESK_X, 0, -HALF_Z + DESK_D * 0.5 + 0.02))
	var top := _mat(WOOD)
	_box(g, Vector3(DESK_W, 0.04, DESK_D), Vector3(0, DESK_H - 0.04, 0), top)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(g, Vector3(0.05, DESK_H - 0.04, 0.05),
				Vector3(sx * (DESK_W * 0.5 - 0.05), 0, sz * (DESK_D * 0.5 - 0.05)), _mat(WOOD_DARK))
	_box(g, Vector3(DESK_W - 0.1, 0.42, 0.02), Vector3(0, 0.3, -DESK_D * 0.5 + 0.04), _mat(WOOD_DARK))   # modesty panel
	# monitor, keyboard, papers, a plant, lunch
	_monitor = _group(g, "Monitor", Vector3(-0.15, DESK_H, -0.18))
	_box(_monitor, Vector3(0.22, 0.02, 0.16), Vector3.ZERO, _mat(METAL))
	_box(_monitor, Vector3(0.04, 0.18, 0.03), Vector3(0, 0.02, 0), _mat(METAL))
	_box(_monitor, Vector3(0.58, 0.36, 0.035), Vector3(0, 0.17, 0.0), _mat(METAL))
	_box(_monitor, Vector3(0.54, 0.32, 0.005), Vector3(0, 0.19, 0.019), _mat(Color(0.32, 0.55, 0.82), 0.7), false)
	# keyboard and mouse in front of her seat (CHAIR.x)
	var kx := CHAIR.x - DESK_X
	_box(g, Vector3(0.44, 0.02, 0.14), Vector3(kx, DESK_H, 0.2), _mat(Color(0.22, 0.23, 0.26)))
	_box(g, Vector3(0.07, 0.02, 0.1), Vector3(kx + 0.33, DESK_H, 0.2), _mat(Color(0.22, 0.23, 0.26)))
	for k in 4:
		var p := _box(g, Vector3(0.21, 0.006, 0.29), Vector3(-0.56, DESK_H + k * 0.007, -0.05), _mat(Color(0.98, 0.97, 0.93)))
		p.rotation.y = _rng.randf_range(-0.2, 0.2)
	_cyl(g, 0.06, 0.05, 0.1, Vector3(0.55, DESK_H, -0.2), _mat(PALETTE[6]))
	for k in 5:
		_sphere(g, 0.06, Vector3(0.55 + _rng.randf_range(-0.04, 0.04), DESK_H + 0.14 + k * 0.03, -0.2 + _rng.randf_range(-0.04, 0.04)),
			_mat(PALETTE[0] if k % 2 == 0 else PALETTE[1]))
	# lunch box and the mug that goes over
	_box(g, Vector3(0.2, 0.06, 0.14), Vector3(0.3, DESK_H, 0.12), _mat(PALETTE[2]))
	# the mug lives in room space (it falls off)
	_mug = _group(room, "Mug", g.position + Vector3(0.5, DESK_H, 0.05))
	_cyl(_mug, 0.04, 0.04, 0.1, Vector3.ZERO, _mat(PALETTE[7]))
	_cyl(_mug, 0.034, 0.034, 0.005, Vector3(0, 0.092, 0), _mat(Color(0.25, 0.14, 0.08)))


func _build_chair(room: Node3D) -> void:
	_chair = _group(room, "Chair", CHAIR)
	var dark := _mat(METAL)
	for k in 5:
		var leg := _box(_chair, Vector3(0.04, 0.03, 0.3), Vector3(0, 0.04, 0), dark)
		leg.rotation.y = k * TAU / 5.0
		leg.position += Vector3(sin(k * TAU / 5.0), 0, cos(k * TAU / 5.0)) * 0.15
	_cyl(_chair, 0.025, 0.025, 0.36, Vector3(0, 0.07, 0), dark)
	var seat := _mat(PALETTE[8].darkened(0.2))
	_box(_chair, Vector3(0.48, 0.07, 0.46), Vector3(0, 0.42, 0), seat)
	_box(_chair, Vector3(0.44, 0.52, 0.07), Vector3(0, 0.5, 0.25), seat).rotation.x = 0.08


func _build_shelf(room: Node3D) -> void:
	var depth := 0.32
	var x := HALF_X - depth * 0.5
	var z0 := -1.5
	var z1 := -0.3
	var h := 1.9
	var g := _group(room, "Shelf")
	var wood := _mat(WOOD_DARK)
	_box(g, Vector3(depth, h, 0.03), Vector3(x, 0, z0), wood)
	_box(g, Vector3(depth, h, 0.03), Vector3(x, 0, z1), wood)
	_box(g, Vector3(0.02, h, z1 - z0), Vector3(HALF_X - 0.01, 0, (z0 + z1) * 0.5), wood)
	var levels := [0.05, 0.5, 0.95, 1.4, 1.87]
	for y in levels:
		_box(g, Vector3(depth, 0.03, z1 - z0), Vector3(x, y, (z0 + z1) * 0.5), wood)
	# books along each shelf; the upper ones fall
	for li in 4:
		var y: float = levels[li] + 0.03
		var z := z0 + 0.03
		while z < z1 - 0.08:
			var bw := _rng.randf_range(0.03, 0.06)
			var bh := _rng.randf_range(0.24, 0.36)
			var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
			var b := _group(room, "Book", Vector3(x + _rng.randf_range(-0.02, 0.02), y, z + bw * 0.5))
			_box(b, Vector3(0.22, bh, bw), Vector3.ZERO, _mat(col.darkened(_rng.randf_range(0.0, 0.3))))
			if li >= 1 and _rng.randf() < 0.45:
				b.set_meta("drop_at", _rng.randf_range(0.9, 4.5))
			_books.append(b)
			z += bw + 0.004


func _build_lamp(room: Node3D) -> void:
	# over her seat: it comes down where she sat, clear of her way out
	_lamp = _group(room, "Lamp", Vector3(CHAIR.x - 0.25, CEIL, CHAIR.z - 0.1))
	_cyl(_lamp, 0.07, 0.07, 0.03, Vector3(0, -0.03, 0), _mat(TRIM))
	_cyl(_lamp, 0.005, 0.005, 0.55, Vector3(0, -0.58, 0), _mat(METAL))
	var shade := _cyl(_lamp, 0.06, 0.24, 0.2, Vector3(0, -0.78, 0), _mat(PALETTE[2]))
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_bulb = _sphere(_lamp, 0.05, Vector3(0, -0.76, 0), _mat(Color(1.0, 0.92, 0.7), 4.0), false)


func _build_wall_things(room: Node3D) -> void:
	# poster left of the desk: the awareness campaign's, or a landscape
	_picture = _group(room, "Picture", Vector3(-1.05, 1.95, -HALF_Z + 0.015))
	var w := 0.62
	var h := 0.82
	_box(_picture, Vector3(w + 0.05, h + 0.05, 0.02), Vector3(0, -h - 0.025, 0), _mat(WOOD_DARK))
	if aware:
		_box(_picture, Vector3(w, h, 0.005), Vector3(0, -h, 0.012), _mat(PALETTE[2]))
		var f: Font = load(FONT) if ResourceLoader.exists(FONT) else null
		var lines := ["DROP", "COVER", "HOLD ON"]
		for k in 3:
			var l := Label3D.new()
			l.text = lines[k]
			if f:
				l.font = f
			l.font_size = 64
			l.pixel_size = 0.0018
			l.modulate = Color(0.12, 0.12, 0.16)
			l.outline_size = 0
			l.shaded = true
			l.position = Vector3(0, -0.2 - k * 0.15, 0.017)
			_picture.add_child(l)
		# a little figure under a table
		_box(_picture, Vector3(0.34, 0.025, 0.004), Vector3(0, -0.66, 0.017), _mat(Color(0.12, 0.12, 0.16)))
		for sx in [-1.0, 1.0]:
			_box(_picture, Vector3(0.02, 0.1, 0.004), Vector3(sx * 0.15, -0.76, 0.017), _mat(Color(0.12, 0.12, 0.16)))
		_sphere(_picture, 0.03, Vector3(-0.02, -0.71, 0.017), _mat(PALETTE[6]), false)
	else:
		_box(_picture, Vector3(w, h, 0.005), Vector3(0, -h, 0.012), _mat(Color(0.7, 0.82, 0.92)))
		_box(_picture, Vector3(w, h * 0.4, 0.006), Vector3(0, -h, 0.013), _mat(PALETTE[0]))
		_box(_picture, Vector3(w * 0.6, h * 0.25, 0.007), Vector3(0.1, -h + h * 0.3, 0.013), _mat(PALETTE[1]))
		_sphere(_picture, 0.06, Vector3(-0.15, -0.22, 0.016), _mat(Color(1.0, 0.9, 0.55)), false)
	# clock over the desk, stopped at 2:32
	var clock := _group(room, "Clock", Vector3(DESK_X, 2.2, -HALF_Z + 0.01))
	var face := _cyl(clock, 0.17, 0.17, 0.03, Vector3.ZERO, _mat(TRIM))
	face.rotation.x = PI * 0.5
	var rim := _cyl(clock, 0.18, 0.18, 0.025, Vector3(0, 0, -0.003), _mat(METAL))
	rim.rotation.x = PI * 0.5
	var hours := (2.0 + 32.0 / 60.0) / 12.0 * TAU
	var minutes := 32.0 / 60.0 * TAU
	for hand in [[hours, 0.09, 0.012], [minutes, 0.14, 0.008]]:
		var pivot := _group(clock, "Hand", Vector3(0, 0, 0.035))
		pivot.rotation.z = -float(hand[0])
		_box(pivot, Vector3(float(hand[2]), float(hand[1]), 0.005), Vector3.ZERO, _mat(METAL))
	# plant in the corner by the window
	_cyl(room, 0.16, 0.12, 0.34, Vector3(-1.85, 0, -1.45), _mat(PALETTE[5]))
	for k in 7:
		_sphere(room, _rng.randf_range(0.12, 0.17), Vector3(-1.85 + _rng.randf_range(-0.1, 0.1), 0.45 + k * 0.08,
			-1.45 + _rng.randf_range(-0.1, 0.1)), _mat(PALETTE[0] if k % 2 else PALETTE[1]))
	# the door, near the camera on the right
	_box(room, Vector3(0.05, 2.05, 0.92), Vector3(HALF_X - 0.02, 0, 1.15), _mat(WOOD))
	_box(room, Vector3(0.06, 2.12, 1.02), Vector3(HALF_X - 0.01, 0, 1.15), _mat(TRIM))
	_sphere(room, 0.03, Vector3(HALF_X - 0.06, 1.0, 0.78), _mat(METAL), false)


# ================================================================ outside

func _build_outside() -> void:
	var g := _group(_m, "Outside")
	var top := GROUND + FLOOR_H * 4.0
	var x := -HALF_X - 0.2   # outer face of the facade
	var fac := _mat(FACADE)
	# our building's facade, with the hole for our window
	var mid := (WIN_Z0 + WIN_Z1) * 0.5
	_box(g, Vector3(0.2, SILL - GROUND, 18.0), Vector3(x + 0.1, GROUND, 0), fac)
	_box(g, Vector3(0.2, top - WIN_TOP, 18.0), Vector3(x + 0.1, WIN_TOP, 0), fac)
	_box(g, Vector3(0.2, WIN_TOP - SILL, WIN_Z0 + 9.0), Vector3(x + 0.1, SILL, (-9.0 + WIN_Z0) * 0.5), fac)
	_box(g, Vector3(0.2, WIN_TOP - SILL, 9.0 - WIN_Z1), Vector3(x + 0.1, SILL, (WIN_Z1 + 9.0) * 0.5), fac)
	_box(g, Vector3(10.0, 0.3, 18.4), Vector3(x + 5.0, top, 0), _mat(FACADE.darkened(0.25)))   # roof
	for sz in [-1.0, 1.0]:
		_box(g, Vector3(10.0, top - GROUND, 0.2), Vector3(x + 5.0, GROUND, sz * 9.1), fac)
	# floor bands and the other windows on our facade
	for f in 5:
		_box(g, Vector3(0.08, 0.12, 18.0), Vector3(x - 0.04, GROUND + f * FLOOR_H - 0.06, 0), _mat(TRIM))
	_windows(g, x, -1.0, -9.0, 9.0, mid, top)
	# street: pavement, kerb, road, the far pavement
	_box(g, Vector3(4.2, 0.15, 90.0), Vector3(x - 2.1, GROUND - 0.15, 0), _mat(PAVEMENT))
	_box(g, Vector3(0.2, 0.17, 90.0), Vector3(x - 4.2, GROUND - 0.17, 0), _mat(PAVEMENT.darkened(0.15)))
	_box(g, Vector3(6.6, 0.1, 90.0), Vector3(x - 7.5, GROUND - 0.25, 0), _mat(ROAD))
	for k in 12:
		_box(g, Vector3(0.15, 0.01, 1.8), Vector3(x - 7.5, GROUND - 0.15, -40.0 + k * 7.5), _mat(Color(0.95, 0.92, 0.75)))
	_box(g, Vector3(3.5, 0.15, 90.0), Vector3(x - 12.55, GROUND - 0.15, 0), _mat(PAVEMENT))
	_box(g, Vector3(60.0, 0.1, 90.0), Vector3(x - 44.3, GROUND - 0.2, 0), _mat(PAVEMENT.darkened(0.1)))
	# neighbours on our side, and the row across the street
	var spans := [[-42.0, -27.0, 5], [-27.0, -9.2, 3], [9.2, 24.0, 5], [24.0, 42.0, 2]]
	for i in spans.size():
		var s: Array = spans[i]
		var h := GROUND + FLOOR_H * float(s[2])
		var c: Color = PALETTE[(i * 3 + 1) % PALETTE.size()]
		_box(g, Vector3(10.0, h - GROUND, float(s[1]) - float(s[0]) - 0.2), Vector3(x + 5.0, GROUND, (float(s[0]) + float(s[1])) * 0.5), _mat(c))
		_windows(g, x, -1.0, float(s[0]) + 0.6, float(s[1]) - 0.6, 999.0, h)
	var fx := x - 14.3   # face of the buildings across the street
	var across := [[-42.0, -20.0, 4], [-20.0, -4.0, 5], [-4.0, 14.0, 3], [14.0, 42.0, 6]]
	for i in across.size():
		var s: Array = across[i]
		var h := GROUND + FLOOR_H * float(s[2])
		var c: Color = PALETTE[(i * 2 + 7) % PALETTE.size()]
		_box(g, Vector3(12.0, h - GROUND, float(s[1]) - float(s[0]) - 0.2), Vector3(fx - 6.0, GROUND, (float(s[0]) + float(s[1])) * 0.5), _mat(c))
		_windows(g, fx, 1.0, float(s[0]) + 0.6, float(s[1]) - 0.6, 999.0, h)
	# a couple of trees and a lamp post on our pavement
	for z in [-6.0, 7.5]:
		_cyl(g, 0.12, 0.15, 2.2, Vector3(x - 3.4, GROUND, z), _mat(WOOD_DARK))
		_sphere(g, 1.1, Vector3(x - 3.4, GROUND + 2.9, z), _mat(PALETTE[1]))
		_sphere(g, 0.8, Vector3(x - 3.1, GROUND + 3.6, z + 0.3), _mat(PALETTE[0]))
	_cyl(g, 0.07, 0.07, 4.2, Vector3(x - 3.9, GROUND, -9.5), _mat(METAL))
	_box(g, Vector3(0.9, 0.08, 0.16), Vector3(x - 3.5, GROUND + 4.2, -9.5), _mat(METAL))


## Dark glass windows on a facade at `fx` facing `out` (-1: -X, +1: +X), one
## per bay between z0 and z1 and per floor up to `top`. Skips our own window
## (bay centred on `skip_z` on our floor).
func _windows(g: Node3D, fx: float, out: float, z0: float, z1: float, skip_z: float, top: float) -> void:
	var glass := _mat(WINDOW_DARK, 0.0, 0.25)
	var sill := _mat(TRIM)
	var bay := 2.2
	var n := int(floor((z1 - z0) / bay))
	if n <= 0:
		return
	var start := (z0 + z1) * 0.5 - (n - 1) * bay * 0.5
	if skip_z < 900.0:
		start = skip_z - floorf((skip_z - z0 - bay * 0.5) / bay) * bay
		n = int(floor((z1 - start) / bay)) + 1
	var floors := int(round((top - GROUND) / FLOOR_H))
	for f in floors:
		var y := GROUND + f * FLOOR_H + SILL
		for b in n:
			var z := start + b * bay
			var half := (WIN_Z1 - WIN_Z0) * 0.5
			if z - half < z0 or z + half > z1:
				continue
			if absf(z - skip_z) < 0.1 and absf(y - SILL) < 0.1:
				continue
			_box(g, Vector3(0.04, WIN_TOP - SILL, WIN_Z1 - WIN_Z0), Vector3(fx + out * 0.02, y, z), glass, false)
			_box(g, Vector3(0.12, 0.05, WIN_Z1 - WIN_Z0 + 0.1), Vector3(fx + out * 0.06, y - 0.05, z), sill, false)


# ================================================================ helpers

func _mat(c: Color, emit := 0.0, rough := 0.85) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), emit, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _glass_mat() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = GLASS
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = m
	return m


func _group(parent: Node, n: String, pos := Vector3.ZERO) -> Node3D:
	var g := Node3D.new()
	g.name = n
	g.position = pos
	parent.add_child(g)
	return g


## Box whose BOTTOM sits at pos.y.
func _box(parent: Node, size: Vector3, pos: Vector3, m: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Upright cylinder whose BOTTOM sits at pos.y.
func _cyl(parent: Node, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos + Vector3(0, h * 0.5, 0)
	parent.add_child(mi)
	return mi


func _sphere(parent: Node, r: float, pos: Vector3, m: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
