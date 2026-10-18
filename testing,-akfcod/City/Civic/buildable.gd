class_name Buildable
extends Node3D
## Turns a civic building (hospital / police station / fire station) into
## something the player has to build.
##
## Put this script on the building's instance in the city scene. At start the
## building is hidden and the block is an empty dirt lot with a floating
## "BUILD ..." sign. Left-click the lot (or call build() from your own code /
## UI) and the building rises out of the ground in a few pulses while dust
## pours out around its base, little builders in hard hats hammer, dig, carry
## planks and point at it, and the three construction sounds play together.
## When it tops out the workers cheer and leave, the dust settles and the
## vehicles / trees around the building pop in.
##
## Everything is in the building's local units (builder.gd lots are ~ +-2.7),
## so it works at any scale the building is placed at.

signal construction_started(building: Buildable)
signal construction_finished(building: Buildable)

enum Stage { UNBUILT, BUILDING, BUILT }

## Skip the construction and show the finished building straight away.
@export var start_built := false
## Left-click on the empty lot starts construction. Turn off if your own UI calls build().
@export var click_to_build := true
## Name on the sign. Empty = the building's "label" metadata or node name.
@export var display_name := ""
@export_range(2.0, 60.0, 0.5) var build_time := 8.0
## How many pulses the building rises in (like floors going up).
@export_range(1, 12) var rise_steps := 6
@export_range(0, 20) var worker_count := 8
@export var worker_scale := 1.0
@export_range(0.0, 3.0, 0.1) var dust_amount := 1.0
## Half size of the lot in the building's local units.
@export var lot_half_size := 2.75
## Seconds after the scene starts to begin building on its own (-1 = wait for a click / build()).
@export var auto_build_delay := -1.0

@export_group("Sound")
@export var jackhammer_sound: AudioStream = preload("res://City/400991__inspectorj__construction-jackhammer-excavator-a.wav")
@export var hammering_sound: AudioStream = preload("res://City/406048__inspectorj__hammering-nails-close-a.wav")
@export var metal_sound: AudioStream = preload("res://City/168822__debsound__metal-06.wav")
## Jingle played once when construction is done.
@export var complete_sound: AudioStream = preload("res://City/winfretless.ogg")
@export_range(-40.0, 12.0) var jackhammer_db := -9.0
@export_range(-40.0, 12.0) var hammering_db := -1.0
@export_range(-40.0, 12.0) var metal_db := 2.0
@export_range(-40.0, 12.0) var complete_db := 0.0
## 3D sound that gets quieter with distance. Off = same volume wherever the camera is.
@export var positional_sound := true
## How far the sound carries, in building-lot units.
@export var sound_range := 6.0

const GROUND := 0.012
const DIRT_DUST := Color(0.8, 0.71, 0.58)
const CONE := "res://Models/Custom/traffic_cone.glb"
## Root children whose name starts with one of these pop in at the end instead of rising.
const PROP_PREFIXES := ["Ambulance", "PatrolCar", "Engine", "Tree", "Bench", "Cone", "Barrier",
	"Hydrant", "HSign", "Flag"]
# Loop regions (seconds) that skip the quiet starts/ends of the recordings.
const JACK_LOOP := Vector2(1.0, 15.3)
const HAMMER_LOOP := Vector2(0.35, 3.1)

var stage := Stage.UNBUILT
## 0..1 while building.
var progress := 0.0

var _rise: Node3D
var _props: Array[Node3D] = []
var _prop_scale := {}
var _footprint := AABB()
var _height := 1.0
var _lot: Node3D
var _dirt: MeshInstance3D
var _fx: Node3D
var _sign: Label3D
var _sub_sign: Label3D
var _hover := false
var _t := 0.0
var _last_step := 0
var _next_clank := 0.0
var _edge_dust: Array[GPUParticles3D] = []
var _workers: Array[ConstructionWorker] = []
var _jack
var _hammer
var _metal
var _rng := RandomNumberGenerator.new()
var _mats := {}


func _ready() -> void:
	add_to_group("buildable")
	_rng.seed = hash(name)
	_rise = Node3D.new()
	_rise.name = "Rise"
	add_child(_rise)
	for c in get_children():
		if c == _rise or not c is Node3D:
			continue
		var n3 := c as Node3D
		if _is_prop(n3):
			_props.append(n3)
			_prop_scale[n3] = n3.scale
		else:
			n3.reparent(_rise)
	_measure()
	if start_built:
		_set_built()
		return
	_rise.visible = false
	_rise.process_mode = Node.PROCESS_MODE_DISABLED
	for p in _props:
		p.visible = false
		p.process_mode = Node.PROCESS_MODE_DISABLED
	set_meta("built", false)
	_make_lot()
	if auto_build_delay >= 0.0:
		get_tree().create_timer(auto_build_delay).timeout.connect(build)


## Start construction (does nothing if it's already built or being built).
func build() -> void:
	if stage != Stage.UNBUILT:
		return
	stage = Stage.BUILDING
	_t = 0.0
	_last_step = 0
	_next_clank = 0.6
	_rise.visible = true
	_rise.process_mode = Node.PROCESS_MODE_INHERIT
	_rise.position = Vector3(0, -(_height + 0.03), 0)

	_fx = Node3D.new()
	_fx.name = "ConstructionFX"
	add_child(_fx)
	_sub_sign.visible = false
	_sign.modulate = Color(1, 0.85, 0.2)
	_sign.scale = Vector3.ONE
	_sign.text = "UNDER CONSTRUCTION\n0%"

	_start_dust()
	_spawn_workers()
	_start_sound()
	# ground breaking puff
	for i in 6:
		_puff(_edge_point(0.1), 0.55, 14)
	construction_started.emit(self)


func is_built() -> bool:
	return stage == Stage.BUILT


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	match stage:
		Stage.UNBUILT:
			if _sign:
				var bob := sin(Time.get_ticks_msec() * 0.0025) * 0.06
				_sign.position.y = _sign_y() + bob
				_sub_sign.position.y = _sign.position.y - 0.42
				var hov := click_to_build and _mouse_over_lot(get_viewport().get_mouse_position())
				if hov != _hover:
					_hover = hov
					var s := 1.18 if hov else 1.0
					create_tween().tween_property(_sign, "scale", Vector3.ONE * s, 0.12)
					_sign.modulate = Color(1, 0.95, 0.4) if hov else Color.WHITE
		Stage.BUILDING:
			_update_build(delta)


func _update_build(delta: float) -> void:
	_t += delta
	var raw := clampf(_t / build_time, 0.0, 1.0)
	# rise in pulses: each step eases up, then holds for a moment
	var k := raw * rise_steps
	var step := floorf(k)
	var f := smoothstep(0.3, 1.0, k - step)
	progress = 1.0 if raw >= 1.0 else (step + f) / rise_steps
	var y := lerpf(-(_height + 0.03), 0.0, progress)
	var j := 0.0
	if f > 0.0 and f < 1.0:
		j = 0.007
	_rise.position = Vector3(sin(_t * 41.0) * j, y, cos(_t * 37.0) * j)

	if int(step) != _last_step:
		_last_step = int(step)
		_step_burst()
	_next_clank -= delta
	if _next_clank <= 0.0:
		_next_clank = _rng.randf_range(0.6, 1.6)
		_clank()
	_loop_sound(_jack, JACK_LOOP)
	_loop_sound(_hammer, HAMMER_LOOP)
	_sign.text = "UNDER CONSTRUCTION\n%d%%" % int(progress * 100.0)
	# keep the sign floating just above the top of the rising building
	_sign.position.y = maxf(_sign_y(), _height + _rise.position.y + 0.4)
	if raw >= 1.0:
		_finish()


func _step_burst() -> void:
	for i in 3:
		_puff(_edge_point(0.05), 0.5, 12)
		_dirt_chunks(_edge_point(0.0), 8)
	_clank(1.0)


func _finish() -> void:
	stage = Stage.BUILT
	progress = 1.0
	_rise.position = Vector3.ZERO
	# settle: stop the steady dust, one last big ring of it
	for e in _edge_dust:
		e.emitting = false
	_edge_dust.clear()
	for i in 10:
		_puff(_edge_point(0.15), 0.7, 16)
	# props pop in one by one
	var tw := create_tween().set_parallel(true)
	var i := 0
	for p in _props:
		var s0: Vector3 = _prop_scale[p]
		p.visible = true
		p.process_mode = Node.PROCESS_MODE_INHERIT
		p.scale = s0 * 0.01
		tw.tween_property(p, "scale", s0, 0.45).set_delay(0.15 + i * 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	# the dirt lot sinks away under the finished forecourt
	if _lot:
		for c in _lot.get_children():
			if c != _dirt and c != _sign and c != _sub_sign and c is Node3D:
				tw.tween_property(c, "scale", Vector3.ONE * 0.01, 0.3).set_delay(_rng.randf_range(0.0, 0.3))
		tw.tween_property(_dirt, "position:y", -0.12, 0.6).set_delay(0.2)
	# sign
	_sign.text = "%s OPEN!" % _title()
	_sign.modulate = Color(0.45, 1.0, 0.45)
	tw.tween_property(_sign, "scale", Vector3.ONE * 1.25, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sign, "position:y", _sign.position.y + 0.6, 2.2).set_delay(0.6)
	tw.tween_property(_sign, "modulate:a", 0.0, 0.8).set_delay(2.0)
	# workers cheer, then head off
	for w in _workers:
		w.cheer()
	get_tree().create_timer(1.8).timeout.connect(_workers_leave)
	# sound: fade the loops, one final clang, then the "done" jingle
	_clank(3.0)
	_play_complete_sound()
	for pl in [_jack, _hammer]:
		if pl:
			tw.tween_property(pl, "volume_db", -50.0, 0.9)
	get_tree().create_timer(5.0).timeout.connect(_cleanup)
	set_meta("built", true)
	construction_finished.emit(self)


func _workers_leave() -> void:
	var c := _footprint.get_center()
	for w in _workers:
		if not is_instance_valid(w):
			continue
		w.leave(Vector3(c.x, 0, c.z))
		var tw := w.create_tween()
		tw.tween_interval(_rng.randf_range(0.8, 1.6))
		tw.tween_property(w, "scale", Vector3.ONE * 0.01, 0.35)
		tw.tween_callback(w.queue_free)
	_workers.clear()


func _cleanup() -> void:
	if is_instance_valid(_fx):
		_fx.queue_free()
	# Drop the sign refs before the lot frees them. Callers (the quake ending)
	# still read these variables, and a freed Label3D there closes the game.
	_sign = null
	_sub_sign = null
	if is_instance_valid(_lot):
		_lot.queue_free()
	_jack = null
	_hammer = null
	_metal = null


func _set_built() -> void:
	stage = Stage.BUILT
	progress = 1.0
	set_meta("built", true)


# ------------------------------------------------------------------ setup

func _is_prop(n: Node) -> bool:
	for p in PROP_PREFIXES:
		if String(n.name).begins_with(p):
			return true
	return false


## Footprint of the solid parts (for dust + where workers stand) and total height.
func _measure() -> void:
	var inv := global_transform.affine_inverse()
	var first := true
	_height = 0.5
	for g in _rise.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		var bb: AABB = (inv * gi.global_transform) * gi.get_aabb()
		_height = maxf(_height, bb.end.y)
		if bb.size.y < 0.12:
			continue
		if first:
			_footprint = bb
			first = false
		else:
			_footprint = _footprint.merge(bb)
	if first:
		_footprint = AABB(Vector3(-1.5, 0, -1.5), Vector3(3, 1, 3))
	var L := lot_half_size - 0.1
	var lo := Vector3(maxf(_footprint.position.x, -L), 0.0, maxf(_footprint.position.z, -L))
	var hi := Vector3(minf(_footprint.end.x, L), _footprint.end.y, minf(_footprint.end.z, L))
	_footprint = AABB(lo, hi - lo)


func _title() -> String:
	if display_name != "":
		return display_name.to_upper()
	if has_meta("label"):
		var l := String(get_meta("label")).to_upper()
		# "City General Hospital" -> keep it short on the sign
		for k in ["HOSPITAL", "POLICE STATION", "FIRE STATION"]:
			if l.contains(k):
				return k
		return l
	return String(name).capitalize().to_upper()


func _sign_y() -> float:
	return 1.4


func _make_lot() -> void:
	var L := lot_half_size
	_lot = Node3D.new()
	_lot.name = "ConstructionLot"
	add_child(_lot)
	# dirt slab — thick enough to hide the building while it's still underground
	_dirt = MeshInstance3D.new()
	_dirt.name = "Dirt"
	var bm := BoxMesh.new()
	bm.size = Vector3(L * 2.0, 0.09, L * 2.0)
	_dirt.mesh = bm
	_dirt.material_override = _mat(Color(0.47, 0.35, 0.24), 1.0)
	_dirt.position.y = GROUND - 0.045
	_lot.add_child(_dirt)
	# a few darker tyre-track patches
	for i in 4:
		var p := _lot_point(0.4)
		_box(_lot, Vector3(_rng.randf_range(0.6, 1.4), 0.004, 0.12), Vector3(p.x, GROUND, p.z),
				_mat(Color(0.38, 0.28, 0.19), 1.0), _rng.randf_range(0, 180))
	# chalk outline + corner stakes where the building will go
	var fp := _footprint
	var chalk := _mat(Color(0.95, 0.95, 0.9), 0.9)
	var c := fp.get_center()
	_box(_lot, Vector3(fp.size.x, 0.004, 0.03), Vector3(c.x, GROUND, fp.position.z), chalk)
	_box(_lot, Vector3(fp.size.x, 0.004, 0.03), Vector3(c.x, GROUND, fp.end.z), chalk)
	_box(_lot, Vector3(0.03, 0.004, fp.size.z), Vector3(fp.position.x, GROUND, c.z), chalk)
	_box(_lot, Vector3(0.03, 0.004, fp.size.z), Vector3(fp.end.x, GROUND, c.z), chalk)
	for x in [fp.position.x, fp.end.x]:
		for z in [fp.position.z, fp.end.z]:
			_box(_lot, Vector3(0.025, 0.14, 0.025), Vector3(x, GROUND + 0.07, z), _mat(Color(0.62, 0.44, 0.26)))
			_box(_lot, Vector3(0.03, 0.03, 0.03), Vector3(x, GROUND + 0.15, z), _mat(Color(1, 0.4, 0.05), 0.85, 0.4))
	# dirt piles
	var placed := 0
	for tries in 40:
		if placed >= 3:
			break
		var p := _lot_point(0.4)
		if fp.grow(0.35).has_point(Vector3(p.x, 0.5, p.z)):
			continue
		var mound := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.3
		sm.is_hemisphere = true
		sm.radial_segments = 12
		sm.rings = 4
		mound.mesh = sm
		mound.material_override = _mat(Color(0.42, 0.31, 0.21), 1.0)
		mound.position = Vector3(p.x, GROUND - 0.01, p.z)
		mound.scale = Vector3(_rng.randf_range(0.7, 1.2), _rng.randf_range(0.5, 0.9), _rng.randf_range(0.7, 1.2))
		_lot.add_child(mound)
		placed += 1
	# stack of planks
	var sp := Vector3(-L + 0.45, GROUND, L - 0.3)
	for k in 4:
		_box(_lot, Vector3(0.7, 0.025, 0.07), sp + Vector3(0, k * 0.026, (k % 2) * 0.075 - 0.04),
				_mat(Color(0.66, 0.48, 0.28) if k % 2 == 0 else Color(0.58, 0.41, 0.24)))
	# cones on the corners
	if ResourceLoader.exists(CONE):
		var cone: PackedScene = load(CONE)
		for x in [-L + 0.15, L - 0.15]:
			for z in [-L + 0.15, L - 0.15]:
				var n: Node3D = cone.instantiate()
				n.position = Vector3(x, GROUND, z)
				_lot.add_child(n)
	# floating sign
	_sign = _label("BUILD %s" % _title(), 0.008, Color.WHITE)
	_sign.position.y = _sign_y()
	_sub_sign = _label("click to build" if click_to_build else "not built yet", 0.0042, Color(1, 1, 1, 0.85))
	_sub_sign.position.y = _sign_y() - 0.42


func _label(text: String, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = px
	l.font_size = 64
	l.outline_size = 14
	l.modulate = col
	l.outline_modulate = Color(0.12, 0.08, 0.02)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var c := _footprint.get_center()
	l.position = Vector3(c.x, 0, c.z)
	_lot.add_child(l)
	return l


func _spawn_workers() -> void:
	var jobs := [ConstructionWorker.Job.SUPERVISE, ConstructionWorker.Job.HAMMER, ConstructionWorker.Job.SHOVEL,
		ConstructionWorker.Job.CARRY, ConstructionWorker.Job.HAMMER, ConstructionWorker.Job.CARRY,
		ConstructionWorker.Job.SHOVEL, ConstructionWorker.Job.HAMMER]
	var c := _footprint.get_center()
	for i in worker_count:
		var w := ConstructionWorker.new()
		w.scale = Vector3.ONE * worker_scale
		_fx.add_child(w)
		w.pick_point = _work_point
		w.start(jobs[i % jobs.size()], _lot_edge_point(), _work_point(), GROUND, Vector3(c.x, 0, c.z))
		w.dug.connect(_on_dug)
		_workers.append(w)


func _on_dug(w: ConstructionWorker) -> void:
	if stage != Stage.BUILDING:
		return
	var fwd := Vector3(-sin(w._yaw), 0, -cos(w._yaw)) * 0.06 * worker_scale
	_puff(w.position + fwd + Vector3.UP * 0.02, 0.12, 4, 0.35)


# ------------------------------------------------------------------ points

## Random spot just outside the building footprint, inside the lot.
func _work_point() -> Vector3:
	var L := lot_half_size - 0.15
	var g := _footprint.grow(0.18)
	var p := _rect_point(g, _rng.randf_range(0.0, 0.25))
	return Vector3(clampf(p.x, -L, L), GROUND, clampf(p.z, -L, L))


## Random spot on the footprint outline (pushed out by `out`).
func _edge_point(out: float) -> Vector3:
	var p := _rect_point(_footprint, out)
	return Vector3(p.x, GROUND + 0.02, p.z)


func _rect_point(r: AABB, out: float) -> Vector3:
	var w := r.size.x
	var d := r.size.z
	var u := _rng.randf() * 2.0 * (w + d)
	var x: float
	var z: float
	if u < w:
		x = r.position.x + u; z = r.end.z + out
	elif u < w + d:
		x = r.end.x + out; z = r.end.z - (u - w)
	elif u < 2.0 * w + d:
		x = r.end.x - (u - w - d); z = r.position.z - out
	else:
		x = r.position.x - out; z = r.position.z + (u - 2.0 * w - d)
	return Vector3(x, 0, z)


func _lot_point(margin: float) -> Vector3:
	var L := lot_half_size - margin
	return Vector3(_rng.randf_range(-L, L), GROUND, _rng.randf_range(-L, L))


func _lot_edge_point() -> Vector3:
	var L := lot_half_size - 0.1
	var a := _rng.randf_range(-L, L)
	var side := _rng.randi() % 4
	if side == 0:
		return Vector3(a, GROUND, L)
	if side == 1:
		return Vector3(a, GROUND, -L)
	if side == 2:
		return Vector3(L, GROUND, a)
	return Vector3(-L, GROUND, a)


func _mouse_over_lot(screen_pos: Vector2) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var inv := global_transform.affine_inverse()
	var o := inv * cam.project_ray_origin(screen_pos)
	var d := inv.basis * cam.project_ray_normal(screen_pos)
	var L := lot_half_size
	var box := AABB(Vector3(-L, -0.05, -L), Vector3(L * 2.0, _sign_y() + 0.4, L * 2.0))
	return box.intersects_ray(o, d) != null


func _unhandled_input(event: InputEvent) -> void:
	if stage != Stage.UNBUILT or not click_to_build:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _mouse_over_lot(event.position):
			get_viewport().set_input_as_handled()
			build()


# ------------------------------------------------------------------ dust

## Steady dust pouring out of the ground along each side of the footprint.
func _start_dust() -> void:
	if dust_amount <= 0.0:
		return
	var fp := _footprint
	var c := fp.get_center()
	var hx := fp.size.x * 0.5
	var hz := fp.size.z * 0.5
	var sides := [
		[Vector3(c.x, GROUND, fp.end.z), Vector3(hx, 0.02, 0.04), Vector3(0, 0, 1), fp.size.x],
		[Vector3(c.x, GROUND, fp.position.z), Vector3(hx, 0.02, 0.04), Vector3(0, 0, -1), fp.size.x],
		[Vector3(fp.end.x, GROUND, c.z), Vector3(0.04, 0.02, hz), Vector3(1, 0, 0), fp.size.z],
		[Vector3(fp.position.x, GROUND, c.z), Vector3(0.04, 0.02, hz), Vector3(-1, 0, 0), fp.size.z],
	]
	for s in sides:
		var n: Vector3 = s[2]
		var amount := int(clampf(s[3] * 14.0 * dust_amount, 6, 120))
		var e := _dust(s[0], s[1], n + Vector3.UP * 1.1, amount, 2.6, 0.45, 0.55, false, 0.0, DIRT_DUST)
		_edge_dust.append(e)


func _puff(pos: Vector3, size: float, amount: int, speed := 0.6) -> void:
	if dust_amount <= 0.0 or not is_instance_valid(_fx):
		return
	_dust(pos, Vector3.ONE * size * 0.3, Vector3.UP, maxi(2, int(amount * dust_amount)), 2.2, size, speed, true, 0.9, DIRT_DUST)


func _dust(pos: Vector3, extents: Vector3, dir: Vector3, amount: int, life: float, size: float,
		speed: float, one_shot: bool, explosiveness: float, color: Color) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = dir.normalized()
	pm.spread = 35.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.radial_velocity_min = speed * 0.2
	pm.radial_velocity_max = speed * 0.5
	pm.gravity = Vector3(0, -0.04, 0)
	pm.damping_min = speed * 0.6
	pm.damping_max = speed * 1.0 + 0.1
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.2
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.35), Vector2(0.3, 0.9), Vector2(1, 1.6)])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.color = color
	pm.color_initial_ramp = QuakeFX.ramp([color.darkened(0.15), color.lightened(0.1)], [0.0, 1.0])
	pm.color_ramp = QuakeFX.fade_ramp(0.8)
	pm.lifetime_randomness = 0.35
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.07
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = explosiveness
	p.draw_pass_1 = QuakeFX.dust_mesh()
	p.process_material = pm
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-5, -1, -5), Vector3(10, 8, 10))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(p)
	p.position = pos
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


## Little clods of dirt kicked up when the building pushes up a step.
func _dirt_chunks(pos: Vector3, amount: int) -> void:
	if not is_instance_valid(_fx):
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, -4.0, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	pm.scale_curve = QuakeFX.curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0)], 1.0)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.particle_flag_rotate_y = true
	pm.color_initial_ramp = QuakeFX.ramp([Color(0.36, 0.26, 0.17), Color(0.5, 0.38, 0.26), Color(0.6, 0.58, 0.55)], [0.0, 0.6, 1.0])
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.draw_pass_1 = QuakeFX.debris_mesh()
	p.process_material = pm
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(p)
	p.position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ sound

func _start_sound() -> void:
	_jack = _player(jackhammer_sound, jackhammer_db, 1)
	_hammer = _player(hammering_sound, hammering_db, 1)
	_metal = _player(metal_sound, metal_db, 4)
	if _jack:
		_jack.pitch_scale = _rng.randf_range(0.95, 1.05)
		_jack.play(_rng.randf_range(JACK_LOOP.x, JACK_LOOP.x + 5.0))
	if _hammer:
		_hammer.play(HAMMER_LOOP.x)


func _player(stream: AudioStream, db: float, polyphony: int) -> Node:
	if stream == null:
		return null
	var pl
	if positional_sound:
		var p3 := AudioStreamPlayer3D.new()
		var s := global_basis.get_scale().x
		p3.unit_size = sound_range * s
		p3.max_db = 6.0
		p3.panning_strength = 0.6
		p3.position = _footprint.get_center()
		pl = p3
	else:
		pl = AudioStreamPlayer.new()
	pl.stream = stream
	pl.volume_db = db
	pl.max_polyphony = polyphony
	_fx.add_child(pl)
	return pl


## One-shot "construction done" jingle. Not positional, and parented to the building
## (not _fx) so _cleanup() can't cut it off.
func _play_complete_sound() -> void:
	if complete_sound == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = complete_sound
	pl.volume_db = complete_db
	add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()


## Keep a recording looping over its loud part while we're building.
func _loop_sound(pl, region: Vector2) -> void:
	if pl == null or not is_instance_valid(pl):
		return
	var length: float = pl.stream.get_length()
	var end := minf(region.y, length - 0.05) if length > 0.0 else region.y
	if not pl.playing or pl.get_playback_position() >= end:
		pl.play(region.x)


func _clank(boost := 0.0) -> void:
	if _metal == null or not is_instance_valid(_metal):
		return
	_metal.pitch_scale = _rng.randf_range(0.8, 1.2)
	_metal.volume_db = metal_db + boost + _rng.randf_range(-3.0, 0.0)
	_metal.play()


# ------------------------------------------------------------------ meshes

func _box(parent: Node, size: Vector3, pos: Vector3, m: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	mi.rotation_degrees.y = rot_y
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough := 0.85, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), rough, emit]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[key] = m
	return _mats[key]
