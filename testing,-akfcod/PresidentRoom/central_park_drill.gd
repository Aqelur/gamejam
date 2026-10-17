extends Node3D
## Central Park on the Sunday of the Chief Seismologist's town-wide drill
## (proposals/seismologist_drill.tres).
##
## Created by day_cycle.gd inside the city for one evening and freed again
## when the view goes back to the office (nothing here is permanent).
##
##   DRILL     the noon sirens wail over the town and everyone walks to the
##             fountain plaza, the evacuation assembly point. The plaza is
##             packed, more people keep streaming in down the promenade and
##             marshals in hi-vis vests wave them in. Crowd murmur under it.
##   NO_DRILL  nobody comes. The plaza is empty but for an old man dozing on a
##             bench and one passer-by on the promenade, while the wind blows
##             dust across and a few tumbleweeds roll past.
##
## Everything is placed in the park's own units (one unit = one city tile),
## under `rig`, which has the park's transform.

const PARK := "Districts/EvacuationPark/CentralPark"
## Centre of the fountain plaza, in park units.
const PLAZA := Vector3(7.0, 0.0, 0.0)
const PAVING_Y := 0.085      # top of the plaza paving and the paths
const LAWN_Y := 0.07         # top of the grass
const PLAZA_R := 1.55        # paving edge (a little inside it)
const BASIN_R := 0.86        # keep clear of the fountain basin
## The lawn around the plaza ("lobe"), x/z ranges in park units.
const LOBE := Rect2(4.15, -4.4, 5.7, 7.45)
const CROWD := 170           # already gathered when the camera gets there
const ARRIVALS := 34         # still walking in
const SPACING := 0.068       # closest two people stand
const MIX_RATE := 22050
const SAND := Color(0.82, 0.72, 0.55, 0.55)
const VEST := Color(1.0, 0.82, 0.05)
const SHIRTS := [Color(0.95, 0.2, 0.35), Color(0.2, 0.45, 0.9), Color(0.98, 0.85, 0.2),
	Color(0.25, 0.75, 0.45), Color(0.95, 0.95, 0.95), Color(0.62, 0.25, 0.85), Color(0.15, 0.75, 0.8),
	Color(0.95, 0.55, 0.15), Color(0.35, 0.35, 0.4), Color(0.6, 0.15, 0.15)]
const PANTS := [Color(0.15, 0.17, 0.25), Color(0.25, 0.22, 0.2), Color(0.35, 0.38, 0.45),
	Color(0.12, 0.12, 0.13), Color(0.45, 0.4, 0.3)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.3, 0.18, 0.08), Color(0.85, 0.7, 0.35),
	Color(0.55, 0.55, 0.55), Color(0.6, 0.25, 0.1)]


## One townsperson. Built by _person(), moved every frame by tick().
class Townie extends Node3D:
	const STAND := 0
	const WALK := 1
	const WAVE := 2      # marshal waving people in
	const MEGAPHONE := 3 # marshal with the megaphone
	const CHAT := 4
	const SIT := 5       # dozing on a bench
	const PHONE := 6     # strolling, eyes on the phone

	var mode := STAND
	## What it does once the walk is over.
	var then_mode := STAND
	var speed := 0.2                       # park units per second
	var path: Array[Vector3] = []          # park units
	var look_at_end := Vector3.ZERO        # faces this once it has arrived
	var phase := 0.0
	var stride := 0.0
	var yaw := 0.0
	var body: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D

	func face(p: Vector3) -> void:
		var d := p - position
		d.y = 0.0
		if d.length() > 0.0001:
			yaw = atan2(-d.x, -d.z)

	func tick(dt: float, t: float) -> void:
		var k := t + phase
		var al := Vector3(0, 0, -0.1)
		var ar := Vector3(0, 0, 0.1)
		var ll := 0.0
		var lr := 0.0
		var y := 0.0
		var tilt := Vector3.ZERO
		var nod := 0.0
		var turn := 0.0
		if mode == WALK or mode == PHONE:
			if path.is_empty():
				if mode == WALK:
					mode = then_mode
					if look_at_end != Vector3.ZERO:
						face(look_at_end)
			else:
				var to := path[0] - position
				var step := speed * dt
				if to.length() <= step:
					position = path[0]
					path.pop_front()
				else:
					position += to.normalized() * step
					var flat := Vector3(to.x, 0.0, to.z)
					if flat.length() > 0.0001:
						yaw = atan2(-flat.x, -flat.z)
				stride += dt * speed / 0.05 * PI
				var s := sin(stride)
				ll = s * 0.55
				lr = -s * 0.55
				al = Vector3(-s * 0.45, 0, -0.08)
				ar = Vector3(s * 0.45, 0, 0.08)
				y = absf(cos(stride)) * 0.004
				if mode == PHONE:
					ar = Vector3(1.25, 0, 0.15)   # phone up in front of the face
					nod = 0.35
		match mode:
			STAND:
				tilt.z = sin(k * 0.7) * 0.025
				turn = sin(k * 0.37) * 0.45
				al = Vector3(0.05 * sin(k * 0.5), 0, -0.1)
				ar = Vector3(-0.05 * sin(k * 0.5), 0, 0.1)
			CHAT:
				turn = sin(k * 0.6) * 0.3
				nod = sin(k * 2.3) * 0.12
				ar = Vector3(0.7 + 0.35 * sin(k * 3.1), 0, 0.2)
				al = Vector3(0.15, 0, -0.12)
			WAVE:
				var w := sin(k * 5.0)
				al = Vector3(0, 0, -2.55 - 0.35 * w)
				ar = Vector3(0, 0, 2.55 - 0.35 * w)
				y = absf(w) * 0.002
			MEGAPHONE:
				ar = Vector3(1.55, 0, 0.12)
				al = Vector3(0, 0, -2.4 - 0.4 * sin(k * 4.0))
				turn = sin(k * 0.45) * 0.5
			SIT:
				ll = 1.3
				lr = 1.3
				al = Vector3(0.65, 0, -0.08)
				ar = Vector3(0.65, 0, 0.08)
				tilt.x = 0.12
				nod = 0.3 + 0.06 * sin(k * 0.8)   # dozing
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-7.0 * dt))
		body.position.y = y
		body.rotation = tilt
		head.rotation = Vector3(nod, turn, 0.0)
		arm_l.rotation = al
		arm_r.rotation = ar
		leg_l.rotation.x = ll
		leg_r.rotation.x = lr


var rig: Node3D

var _city: Node3D
var _park: Node3D
var _tile := 26.926893
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _people: Array[Townie] = []
## Things people must not stand in, park units: [x, z, radius, is_tree].
var _obstacles: Array[Vector4] = []
var _mats := {}
var _meshes := {}
var _players: Array[AudioStreamPlayer] = []
var _siren: AudioStreamPlayer
var _murmur: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _ducked := false

static var _siren_wav: AudioStreamWAV
static var _murmur_wav: AudioStreamWAV
static var _wind_wav: AudioStreamWAV


func _init() -> void:
	_rng.seed = 1200   # noon
	set_process(false)


## Find Central Park in `city` (City/city.tscn instance). Call after adding
## this node to the city. Returns false when the city has no park.
func setup(city: Node3D) -> bool:
	_city = city
	_park = city.get_node_or_null(PARK) as Node3D
	if _park == null:
		return false
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	rig.global_transform = _park.global_transform
	_tile = absf(_park.global_basis.get_scale().x)
	_collect("Trees", 0.17, true)
	_collect("Benches", 0.2, false)
	_collect("Lamps", 0.06, false)
	var plaza := _park.get_node_or_null("FountainPlaza")
	if plaza:
		for c in plaza.get_children():
			var n := c as Node3D
			if n == null:
				continue
			var s := String(n.name)
			var r := 0.0
			if s.begins_with("Bench"):
				r = 0.2
			elif s.begins_with("Planter"):
				r = 0.13
			elif s.begins_with("EvacSign"):
				r = 0.12
			if r > 0.0:
				var p := rig.to_local(n.global_position)
				_obstacles.append(Vector4(p.x, p.z, r, 0.0))
	return true


func _collect(group_name: String, radius: float, tree: bool) -> void:
	var g := _park.get_node_or_null(group_name)
	if g == null:
		return
	for c in g.get_children():
		var n := c as Node3D
		if n == null:
			continue
		var p := rig.to_local(n.global_position)
		_obstacles.append(Vector4(p.x, p.z, radius * absf(n.scale.x), 1.0 if tree else 0.0))


# ================================================================ camera spots
# All as [position, look at, slow creep] in world space.

## High 3/4 view from the south over the packed plaza and the promenade.
func drill_shot() -> Array:
	return [rig.to_global(PLAZA + Vector3(1.4, 2.6, 4.2)), rig.to_global(PLAZA + Vector3(0.0, 0.15, -0.9)),
		rig.global_basis * Vector3(-0.5, -0.45, -0.8)]


## Low, close to the empty plaza from the promenade end, looking across it
## at the old man on his bench.
func empty_shot() -> Array:
	return [rig.to_global(PLAZA + Vector3(-0.3, 0.55, -2.9)), rig.to_global(PLAZA + Vector3(0.0, 0.16, 0.7)),
		rig.global_basis * Vector3(-0.2, -0.05, 0.35)]


## The empty shot's spot but high above it, so the camera can drop straight in.
func empty_drop_shot() -> Array:
	var s := empty_shot()
	return [rig.to_global(PLAZA + Vector3(-0.5, 2.9, -3.6)), s[1], Vector3.ZERO]


# ================================================================ approved

## Sirens, the gathered crowd, the marshals and the people still walking in.
func start_drill() -> void:
	# marshals first, so nobody is put where they stand
	var marshals := [
		[PLAZA + Vector3(0.28, PAVING_Y, -1.42), PLAZA + Vector3(0.1, 0, -4.0), Townie.WAVE],
		[PLAZA + Vector3(-0.3, PAVING_Y, 1.45), PLAZA + Vector3(0, 0, 4.0), Townie.WAVE],
		[PLAZA + Vector3(0.5, PAVING_Y, 0.82), PLAZA + Vector3(0.5, 0, 3.0), Townie.MEGAPHONE],
		[PLAZA + Vector3(-1.62, PAVING_Y, 1.2), PLAZA, Townie.WAVE],
	]
	for m in marshals:
		var w := _person(m[0], Color(0.2, 0.3, 0.55), Color(0.2, 0.22, 0.3), _pick(SKIN), _pick(HAIR), 1.0, true)
		w.face(m[1])
		w.rotation.y = w.yaw
		w.mode = m[2]
		if w.mode == Townie.MEGAPHONE:
			_megaphone(w)
		_obstacles.append(Vector4(m[0].x, m[0].z, 0.1, 0.0))

	var spots := _crowd_spots(CROWD + ARRIVALS)
	# the spots nearest the two aisles are kept for the people walking in
	var north: Array[Vector3] = []
	var south: Array[Vector3] = []
	var gathered: Array[Vector3] = []
	for p in spots:
		var rel := p - PLAZA
		if rel.z < 0.1 and north.size() < int(ARRIVALS * 0.75) and _rng.randf() < 0.3:
			north.append(p)
		elif rel.z > 0.3 and south.size() < int(ARRIVALS * 0.25) and _rng.randf() < 0.3:
			south.append(p)
		else:
			gathered.append(p)

	for p in gathered:
		var child := _rng.randf() < 0.12
		var w := _person(p, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR),
			_rng.randf_range(0.66, 0.74) if child else _rng.randf_range(0.92, 1.08), false)
		# most face the fountain and the megaphone, some turn to talk
		var look := PLAZA + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
		w.mode = Townie.CHAT if _rng.randf() < 0.3 else Townie.STAND
		if w.mode == Townie.CHAT:
			look = p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		w.face(look)
		w.rotation.y = w.yaw

	_walk_in(north, -1.0)
	_walk_in(south, 1.0)

	_siren = _player(_siren_stream(), -6.0)
	_murmur = _player(_noise_stream(true), -60.0)
	var t := create_tween()
	t.tween_property(_murmur, "volume_db", -10.0, 2.5)
	set_process(true)


## People coming down the promenade (side -1 = from the north end, +1 = from
## the south end) to their spot on the plaza.
func _walk_in(targets: Array[Vector3], side: float) -> void:
	targets.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var m := PLAZA + Vector3(0, 0, side * 1.05)
		return Vector2(a.x - m.x, a.z - m.z).length() < Vector2(b.x - m.x, b.z - m.z).length())
	var reach := 3.3 if side < 0.0 else 1.5   # how far up the promenade the queue goes
	for i in targets.size():
		var lane := (0.07 + _rng.randf_range(0.0, 0.1)) * (1.0 if i % 2 == 0 else -1.0)
		var along := 1.75 + (float(i) + _rng.randf_range(-0.3, 0.3)) / maxf(targets.size(), 1.0) * reach
		var start := PLAZA + Vector3(lane, PAVING_Y, side * along)
		var mouth := PLAZA + Vector3(lane * 0.6, PAVING_Y, side * 1.05)
		var child := _rng.randf() < 0.15
		var w := _person(start, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR),
			_rng.randf_range(0.66, 0.74) if child else _rng.randf_range(0.92, 1.08), false)
		w.face(mouth)
		w.rotation.y = w.yaw
		w.mode = Townie.WALK
		w.then_mode = Townie.CHAT if _rng.randf() < 0.3 else Townie.STAND
		w.speed = _rng.randf_range(0.17, 0.24) * (1.15 if child else 1.0)
		var route: Array[Vector3] = [mouth, targets[i]]
		w.path = route
		w.look_at_end = PLAZA


## Quieter siren and crowd while the narrator talks.
func duck(on: bool) -> void:
	_ducked = on
	for p in [_siren, _murmur, _wind]:
		if p and is_instance_valid(p):
			var base := -6.0 if p == _siren else (-10.0 if p == _murmur else -8.0)
			var t := create_tween()
			t.tween_property(p, "volume_db", base - (14.0 if on else 0.0), 0.6)


# ================================================================ denied

## The empty park: an old man dozing on a bench, one passer-by, wind, dust and
## tumbleweeds. Returns how long, from now, the last tumbleweed takes to pass.
func start_empty() -> float:
	# the bench on the near side of the fountain, seen side-on from the camera
	var bench := _park.get_node_or_null("FountainPlaza/Bench3") as Node3D
	if bench == null:
		bench = _park.get_node_or_null("FountainPlaza/Bench1") as Node3D
	if bench:
		var bp := rig.to_local(bench.global_position)
		var fwd := rig.global_basis.inverse() * bench.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var old := _person(Vector3(bp.x, bp.y + 0.08 - 0.066, bp.z) + fwd * 0.004,
			Color(0.45, 0.4, 0.32), Color(0.3, 0.28, 0.26), SKIN[0], Color(0.82, 0.82, 0.8), 1.0, false)
		old.yaw = atan2(-fwd.x, -fwd.z)
		old.rotation.y = old.yaw
		old.mode = Townie.SIT
	# one passer-by wandering up the promenade, eyes on the phone
	var walker := _person(PLAZA + Vector3(0.12, PAVING_Y, -1.1), _pick(SHIRTS), _pick(PANTS),
		_pick(SKIN), _pick(HAIR), 1.0, false)
	walker.mode = Townie.PHONE
	walker.speed = 0.09
	var route: Array[Vector3] = [PLAZA + Vector3(0.16, PAVING_Y, -2.2)]
	walker.path = route
	walker.face(walker.path[0])
	walker.rotation.y = walker.yaw

	_wind = _player(_noise_stream(false), -8.0)
	var lanes := _tumbleweed_lanes()
	var gust := rig.global_basis.x.normalized()
	_wind_dust(rig.to_global(PLAZA + Vector3(0, PAVING_Y, lanes[0])), gust)
	var longest := 0.0
	var delays := [3.6, 5.0, 6.6]
	for i in 3:
		var z: float = lanes[i % lanes.size()] + _rng.randf_range(-0.04, 0.04)
		var r := _rng.randf_range(0.06, 0.08) * _tile
		var time := 6.2 + i * 0.6 + _rng.randf_range(-0.3, 0.3)
		var from := rig.to_global(PLAZA + Vector3(-3.0, PAVING_Y, z))
		var to := rig.to_global(PLAZA + Vector3(3.0, PAVING_Y, z + _rng.randf_range(-0.1, 0.1)))
		var tw := _tumbleweed(r)
		add_child(tw)
		tw.global_position = from + Vector3.UP * r
		tw.scale = Vector3.ONE * 0.01
		_roll(tw, from, to, r, time, delays[i])
		longest = maxf(longest, delays[i] + time)
	set_process(true)
	return longest


## Two lines across the plaza (park z, relative to it) with the least in the
## way: benches, planters, signs and tree trunks.
func _tumbleweed_lanes() -> Array[float]:
	var best: Array = []
	for i in 13:
		var z := -1.2 + 0.2 * i
		if absf(z) < BASIN_R + 0.1:
			continue
		var clear := 99.0
		for o in _obstacles:
			var radius := o.z * (0.3 if o.w > 0.5 else 1.0)   # under a tree is fine, not through its trunk
			if absf(o.x - PLAZA.x) > 3.1:
				continue
			clear = minf(clear, absf(o.y - (PLAZA.z + z)) - radius)
		# the side toward the camera reads best
		best.append([clear + (0.05 if z < 0.0 else 0.0), z])
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[float] = []
	for b in best:
		if out.is_empty() or absf(float(b[1]) - out[0]) > 0.3:
			out.append(float(b[1]))
		if out.size() == 2:
			break
	if out.is_empty():
		out.append(1.0)
	return out


func _roll(tw: Node3D, from: Vector3, to: Vector3, r: float, time: float, delay: float) -> void:
	var ball := tw.get_child(0) as Node3D
	var dir := (to - from).normalized()
	var axis := Vector3.UP.cross(dir).normalized()
	var dist := from.distance_to(to)
	var hops := maxf(3.0, dist / (r * 9.0))
	var spin0 := ball.basis
	var state := {"last": 0.0}   # lambdas copy locals, so keep mutable state in a dictionary
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(tw, "scale", Vector3.ONE, 0.25)
	t.parallel().tween_method(func(k: float) -> void:
		if not is_instance_valid(tw):
			return
		var g := clampf(k + 0.025 * sin(k * 11.0), 0.0, 1.0)   # gusts
		var h := g * hops
		var hop := absf(sin(h * PI)) * r * (0.8 + 0.5 * sin(h * 1.7))
		var pos := from.lerp(to, g) + axis * sin(g * 6.0) * r * 0.8
		tw.global_position = pos + Vector3.UP * (r + hop)
		ball.basis = Basis(axis, g * dist / r) * spin0
		if floorf(h) != floorf(state.last):   # touched down
			QuakeFX.dust(self, pos + Vector3.UP * 0.3, r * 0.4, 5, r * 0.9, 1.3, r * 0.6, r * 1.1, SAND)
		state.last = h,
		0.0, 1.0, time)
	t.tween_property(tw, "scale", Vector3.ONE * 0.01, 0.3)


## A loose ball of dry twigs, `r` world units across the middle.
func _tumbleweed(r: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Tumbleweed"
	var ball := Node3D.new()
	root.add_child(ball)
	var dry := _mat(Color(0.74, 0.62, 0.42))
	var dark := _mat(Color(0.5, 0.39, 0.25))
	for i in 6:
		var ring := TorusMesh.new()
		ring.inner_radius = r * _rng.randf_range(0.78, 0.9)
		ring.outer_radius = ring.inner_radius + r * 0.06
		ring.rings = 16
		ring.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.material_override = dry if i % 2 == 0 else dark
		mi.basis = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		ball.add_child(mi)
	var twigs: Array[CylinderMesh] = []
	for i in 3:
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.018
		cm.bottom_radius = r * 0.03
		cm.height = r * (0.8 + 0.4 * i)
		cm.radial_segments = 4
		cm.rings = 1
		twigs.append(cm)
	for i in 48:
		var mi := MeshInstance3D.new()
		mi.mesh = twigs[i % twigs.size()]
		mi.material_override = dry if _rng.randf() < 0.65 else dark
		var p := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		mi.position = p.limit_length(1.0) * r * 0.6
		mi.basis = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))
		ball.add_child(mi)
	return root


## Low sandy dust drifting across the plaza on the wind.
func _wind_dust(base: Vector3, dir: Vector3) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = dir.abs() * 3.0 * _tile + side.abs() * 0.9 * _tile + Vector3(0, 0.4, 0)
	pm.direction = (dir + Vector3.UP * 0.05).normalized()
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6 * _tile
	pm.initial_velocity_max = 1.1 * _tile
	pm.gravity = Vector3.ZERO
	pm.scale_min = 3.0
	pm.scale_max = 7.0
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.4), Vector2(0.4, 1.0), Vector2(1, 1.5)])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.color = SAND
	pm.color_ramp = QuakeFX.fade_ramp(0.45)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	var p := QuakeFX.emitter(self, Transform3D(Basis(), base + Vector3.UP * 1.2), QuakeFX.dust_mesh(),
		70, 3.2, pm, false, 0.0)
	p.visibility_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))
	p.preprocess = 2.0


# ================================================================ show

func _process(delta: float) -> void:
	_time += delta
	for p in _people:
		p.tick(delta, _time)


func fade_out(time: float) -> void:
	for p in _players:
		if is_instance_valid(p):
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, time)


## Everyone goes home: sound off, freed.
func close() -> void:
	set_process(false)
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	queue_free()


# ================================================================ placing people

## Random free spots on the plaza paving, spilling onto the lawn around it.
## Aisles from the promenade at both ends are left open.
func _crowd_spots(n: int) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < n and tries < 8000:
		tries += 1
		var on_paving := _rng.randf() < 0.8
		var r0 := BASIN_R if on_paving else PLAZA_R + 0.08
		var r1 := PLAZA_R if on_paving else 2.35
		var r := sqrt(_rng.randf_range(r0 * r0, r1 * r1))   # even over the area
		var a := _rng.randf() * TAU
		var p := PLAZA + Vector3(cos(a) * r, PAVING_Y if on_paving else LAWN_Y, sin(a) * r)
		if not on_paving and not LOBE.has_point(Vector2(p.x, p.z)):
			continue
		if absf(p.x - PLAZA.x) < 0.17 and absf(p.z - PLAZA.z) > BASIN_R + 0.05:
			continue   # aisle
		if not _clear(p):
			continue
		var ok := true
		for s in spots:
			if Vector2(s.x - p.x, s.z - p.z).length() < SPACING:
				ok = false
				break
		if ok:
			spots.append(p)
	return spots


func _clear(p: Vector3) -> bool:
	for o in _obstacles:
		if Vector2(o.x - p.x, o.y - p.z).length() < o.z:
			return false
	return true


func _person(pos: Vector3, shirt: Color, pants: Color, skin: Color, hair: Color, size: float,
		vest: bool) -> Townie:
	var p := Townie.new()
	p.position = pos
	p.scale = Vector3.ONE * size
	p.phase = _rng.randf() * TAU
	p.yaw = _rng.randf() * TAU
	rig.add_child(p)
	p.body = Node3D.new()
	p.add_child(p.body)
	var sm := _mat(shirt)
	p.leg_l = _limb(p.body, Vector3(-0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), _mat(pants))
	p.leg_r = _limb(p.body, Vector3(0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), _mat(pants))
	_box(p.body, Vector3(0.05, 0.064, 0.028), Vector3(0, 0.1, 0), sm)
	if vest:
		_box(p.body, Vector3(0.054, 0.05, 0.032), Vector3(0, 0.104, 0), _mat(VEST, 0.6))
		_box(p.body, Vector3(0.056, 0.006, 0.034), Vector3(0, 0.095, 0), _mat(Color(0.9, 0.92, 0.95), 1.2))
	p.head = Node3D.new()
	p.head.position = Vector3(0, 0.133, 0)
	p.body.add_child(p.head)
	_box(p.head, Vector3(0.033, 0.035, 0.031), Vector3(0, 0.019, 0), _mat(skin))
	_box(p.head, Vector3(0.036, 0.011, 0.034), Vector3(0, 0.039, 0.002), _mat(hair))
	p.arm_l = _limb(p.body, Vector3(-0.033, 0.127, 0), Vector3(0.013, 0.056, 0.014), sm)
	p.arm_r = _limb(p.body, Vector3(0.033, 0.127, 0), Vector3(0.013, 0.056, 0.014), sm)
	_box(p.arm_l, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.061, 0), _mat(skin))
	_box(p.arm_r, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.061, 0), _mat(skin))
	_people.append(p)
	return p


## A red-and-white megaphone in the right hand, pointing out ahead.
func _megaphone(p: Townie) -> void:
	var horn := _cyl(p.arm_r, 0.016, 0.006, 0.04, Vector3(0, -0.07, -0.012), _mat(Color(0.92, 0.18, 0.15)))
	horn.rotation.x = -PI * 0.5
	var rim := _cyl(p.arm_r, 0.0165, 0.0165, 0.004, Vector3(0, -0.07, -0.032), _mat(Color(0.95, 0.95, 0.95)))
	rim.rotation.x = -PI * 0.5


# ================================================================ sound

func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	_players.append(p)
	return p


## Town sirens: two of them wailing up and down, one a little lower and
## out of step (left/right). Loops seamlessly every 4 seconds.
func _siren_stream() -> AudioStreamWAV:
	if _siren_wav:
		return _siren_wav
	var cycle := 4.0
	var n := int(MIX_RATE * cycle)
	var data := PackedByteArray()
	data.resize(n * 4)
	var ph := [0.0, 0.0]
	var base := [520.0, 504.4]       # means of 800 and 776 Hz: whole cycles per loop
	var spread := [560.0, 543.2]
	var lag := [0.0, 1.3]
	for i in n:
		var t := float(i) / MIX_RATE
		for c in 2:
			var w := 0.5 - 0.5 * cos(TAU * (t + lag[c]) / cycle)
			ph[c] += TAU * (base[c] + spread[c] * w) / MIX_RATE
			var p: float = ph[c]
			var s := 0.55 * sin(p) + 0.2 * sin(3.0 * p) + 0.08 * sin(5.0 * p)
			data.encode_s16(i * 4 + c * 2, int(clampf(s * 0.8, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = true
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_siren_wav = wav
	return wav


## Crowd murmur (`crowd` = true) or wind, made from filtered noise and
## cross-faded at the seam so it loops without a click.
func _noise_stream(crowd: bool) -> AudioStreamWAV:
	if crowd and _murmur_wav:
		return _murmur_wav
	if not crowd and _wind_wav:
		return _wind_wav
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if crowd else 31
	var seconds := 4.0
	var n := int(MIX_RATE * seconds)
	var fade := int(MIX_RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var lp1 := 0.0
	var lp2 := 0.0
	var env := 0.0
	var rates := PackedFloat32Array()
	var offs := PackedFloat32Array()
	for v in 7:
		rates.append(rng.randf_range(2.6, 5.5))
		offs.append(rng.randf() * TAU)
	for i in n + fade:
		var t := float(i) / MIX_RATE
		var w := rng.randf_range(-1.0, 1.0)
		var s := 0.0
		if crowd:
			lp1 += (w - lp1) * 0.22     # ~900 Hz
			lp2 += (w - lp2) * 0.07     # ~250 Hz
			if i % 32 == 0:   # the babble envelope changes slowly, no need every sample
				env = 0.0
				for v in 7:
					var syl := absf(sin(t * rates[v] * PI + offs[v]))
					env += syl * syl * (0.6 + 0.4 * sin(t * 0.7 + offs[v]))
			s = (lp1 - lp2) * env * 0.55
		else:
			lp1 += (w - lp1) * 0.02
			lp2 += (w - lp2) * 0.12
			var gust := 0.55 + 0.45 * sin(TAU * t / seconds * 2.0) * sin(TAU * t / seconds + 1.0)
			s = (lp1 * 3.2 + (lp2 - lp1) * 0.4 * gust) * gust
		buf[i] = s
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := buf[i]
		if i < fade:
			var k := float(i) / fade
			s = buf[i] * k + buf[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	if crowd:
		_murmur_wav = wav
	else:
		_wind_wav = wav
	return wav


# ================================================================ building blocks

func _limb(parent: Node3D, pivot: Vector3, size: Vector3, m: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box(p, size, Vector3(0, -size.y * 0.5, 0), m)
	return p


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "b%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _mesh(parent, _meshes[key], pos, m)


func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "c%s_%s_%s" % [r_top, r_bottom, h]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bottom
		cm.height = h
		cm.radial_segments = 12
		cm.rings = 1
		_meshes[key] = cm
	return _mesh(parent, _meshes[key], pos, m)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [c, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _pick(list: Array) -> Color:
	return list[_rng.randi() % list.size()]
