extends Node3D
## The Old Quarter at the end of the day, for the Minister of Urban Planning's
## timber-bracing proposal (proposals/urban_timber_bracing.tres).
##
## Created by day_cycle.gd inside the city the first time it's needed and kept
## for the rest of the game, so the repairs stay done.
##
##   REPAIR   builders are already at work round the crossroads when the camera
##            arrives. Then a wave of repairs rolls out from the middle of the
##            quarter: every leaning, cracked, mossy building straightens up,
##            gets cleaned and freshly painted like the rest of the city, the
##            rubble, planks, scaffolds, braces, barriers and wrecked cars are
##            cleared, broken street lights stand back up and dead trees grow
##            green again. Afterwards the buildings count as sound for the
##            earthquake (structural_integrity) and are weathered like Downtown.
##            In the earthquake ending (old_quarter_quake.gd) that is the
##            difference between the quarter standing and crumbling to dust.
##   NEGLECT  nobody comes. Street-level view down the empty main street while
##            dust blows along and a couple of tumbleweeds roll past.

const DISTRICT := "Districts/OldQuarter"
const REF_BUILDINGS := "Districts/Downtown/Buildings"
const STREETLIGHT := "res://Models/Custom/streetlight.glb"
const TREE := "res://Models/Custom/tree_round.glb"
const HAMMERING := "res://City/406048__inspectorj__hammering-nails-close-a.wav"
const METAL := "res://City/168822__debsound__metal-06.wav"
const COMPLETE := "res://City/winfretless.ogg"
const HAMMER_LOOP := Vector2(0.35, 3.1)
## Props cleared away once the quarter is fixed up (node name prefixes).
const CLUTTER := ["rubble", "debris", "scaffold", "wood_brace", "barrier", "car_wrecked",
	"fence_broken", "sign_warning"]
## Props replaced by a healthy version: prefix -> scene.
const SWAPS := {"streetlight_broken": STREETLIGHT, "tree_dead": TREE}
## structural_integrity a building gets once it is braced (Downtown is 1.0).
const REPAIRED_INTEGRITY := 0.9
## Facade paint strength after the repair (the city default).
const PAINT := 0.9
## Seconds the builders hammer before the first building is done.
const LEAD_IN := 1.2
## Seconds for the repair wave to reach the far edge of the quarter.
const WAVE_TIME := 6.5
## Seconds one building takes to straighten up and get cleaned.
const POP_TIME := 1.1
const DUST := Color(0.86, 0.81, 0.72)
const SAND := Color(0.82, 0.72, 0.55, 0.55)

var repaired := false
## The crossroads in the middle of the quarter (ground level).
var focus := Vector3.ZERO

var _city: Node3D
var _district: Node3D
var _weather: Node3D            # weathering.gd on OldQuarter/Buildings
var _props: Node3D
var _buildings: Array[Node3D] = []
var _boxes: Array[AABB] = []    # world AABB of each building, before the repair
var _tile := 26.926893          # one city tile (the scale every model is placed at)
var _ground_y := -0.7273283     # where Downtown's buildings stand
var _street_axis := Vector3.RIGHT
var _street_sign := 1.0         # which way along the street the camera sits
var _street_y := 0.0            # top of the road surface
var _site: Node3D               # scaled to one tile, the builders live here
var _workers: Array = []
var _transients: Array[Node] = []
var _rng := RandomNumberGenerator.new()
var _hammer: AudioStreamPlayer
var _metal: AudioStreamPlayer
var _last_clank := -1.0
var _clock := 0.0


func _init() -> void:
	_rng.seed = 1906
	set_process(false)


## Find the quarter in `city` (City/city.tscn instance). Call after adding this
## node to the city. Returns false when the city has no Old Quarter.
func setup(city: Node3D) -> bool:
	_city = city
	_district = city.get_node_or_null(DISTRICT) as Node3D
	if _district == null:
		return false
	_weather = _district.get_node_or_null("Buildings") as Node3D
	_props = _district.get_node_or_null("Props") as Node3D
	if _weather == null:
		return false
	for c in _weather.get_children():
		if c is Node3D:
			_buildings.append(c)
			_boxes.append(_box_of(c))
	if _buildings.is_empty():
		return false
	_tile = absf(_buildings[0].global_basis.get_scale().y)
	var ref := city.get_node_or_null(REF_BUILDINGS)
	if ref and ref.get_child_count() > 0 and ref.get_child(0) is Node3D:
		_ground_y = (ref.get_child(0) as Node3D).global_position.y
	var all := _boxes[0]
	for b in _boxes:
		all = all.merge(b)
	focus = Vector3(all.get_center().x, _ground_y, all.get_center().z)
	_street_y = _ground_y
	_find_street(all)

	_site = Node3D.new()
	_site.name = "Site"
	add_child(_site)
	_site.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * _tile), Vector3(0, _ground_y + 0.05, 0))
	return true


# ================================================================ camera spots

## High 3/4 view over the whole quarter: [position, look at, slow creep].
func district_shot() -> Array:
	var dir := Vector3(0.38, 0.0, 0.92).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var pos := focus + dir * 7.5 * _tile + Vector3.UP * 4.8 * _tile
	return [pos, focus + Vector3.UP * 0.4 * _tile, side * 1.4 * _tile]


## Standing in the main street, looking down it past the crossroads.
func street_shot() -> Array:
	var c := _street_axis * _street_sign
	var side := c.cross(Vector3.UP).normalized()
	var base := Vector3(focus.x, _street_y, focus.z)
	var pos := base + c * 2.2 * _tile + side * 0.25 * _tile + Vector3.UP * 0.32 * _tile
	var look := base - c * 1.5 * _tile + Vector3.UP * 0.12 * _tile
	return [pos, look, -c * 0.3 * _tile]


## The same spot at a person's eye height, looking down the street at the
## people running and the walls coming down.
func witness_shot() -> Array:
	var s := street_shot()
	var pos: Vector3 = s[0]
	var look: Vector3 = s[1]
	pos.y = _street_y + 0.155 * _tile
	look.y = _street_y + 0.22 * _tile
	return [pos, look, Vector3.ZERO]


## The street shot's spot, but high above it, so the camera can come straight
## down into the street without clipping roofs.
func street_drop_shot() -> Array:
	var s := street_shot()
	return [s[0] + Vector3.UP * 3.5 * _tile, s[1], Vector3.ZERO]


# ================================================================ approved

## Builders and hammering, so the site is busy before the camera gets there.
func prepare() -> void:
	if repaired or not _workers.is_empty():
		return
	_spawn_workers()
	_start_sound()


## The repair wave. Returns when every building is done.
func repair() -> void:
	if repaired:
		return
	repaired = true
	prepare()
	var c := _flat(focus)
	var far := 1.0
	for b in _boxes:
		far = maxf(far, _flat(b.get_center()).distance_to(c))
	for i in _buildings.size():
		var d := _flat(_boxes[i].get_center()).distance_to(c)
		_after(LEAD_IN + d / far * WAVE_TIME, _fix_building.bind(i))
	if _props:
		for p in _props.get_children():
			var n := p as Node3D
			if n == null:
				continue
			var d := _flat(n.global_position).distance_to(c)
			var at := LEAD_IN + minf(d / far, 1.0) * WAVE_TIME + 0.25
			if _starts_with_any(n.name, CLUTTER):
				_after(at, _clear_prop.bind(n))
			else:
				for prefix in SWAPS:
					if String(n.name).begins_with(prefix):
						_after(at, _swap_prop.bind(n, SWAPS[prefix]))
						break
	await get_tree().create_timer(LEAD_IN + WAVE_TIME + POP_TIME + 0.2).timeout
	_settle()


## The whole repair at once, no builders and no wave: every building rights
## itself and is cleaned (over POP_TIME), the clutter goes, the broken lamps
## and dead trees are replaced. For testing the earthquake ending straight
## away with the bracing already approved (day_cycle.gd start_ending_now).
func repair_now() -> void:
	if repaired:
		return
	repaired = true
	for i in _buildings.size():
		_fix_building(i)
	if _props:
		for p in _props.get_children():
			var n := p as Node3D
			if n == null:
				continue
			if _starts_with_any(n.name, CLUTTER):
				n.queue_free()
				continue
			for prefix in SWAPS:
				if String(n.name).begins_with(prefix):
					_swap_prop(n, SWAPS[prefix])
					break
	_settle()


## Everyone downs tools and cheers, the jingle plays, then they head home.
func celebrate() -> void:
	_stop_sound()
	var home := _site.to_local(focus)
	for w in _workers:
		if is_instance_valid(w):
			w.cheer()
	var jingle := _stream(COMPLETE)
	if jingle:
		var p := AudioStreamPlayer.new()
		p.stream = jingle
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	await get_tree().create_timer(2.0).timeout
	for w in _workers:
		if is_instance_valid(w):
			w.leave(home)


func _fix_building(i: int) -> void:
	var b := _buildings[i]
	if not is_instance_valid(b):
		return
	var xf := b.global_transform
	var s := xf.basis.get_scale().abs()
	var bx := xf.basis.x
	var q0 := xf.basis.orthonormalized().get_rotation_quaternion()
	var q1 := Quaternion(Vector3.UP, atan2(-bx.z, bx.x))   # same heading, standing straight
	var p0 := xf.origin
	var p1 := Vector3(p0.x, _ground_y, p0.z)                # back up out of the sunken ground

	var overlays: Array[ShaderMaterial] = []
	var paints: Array[ShaderMaterial] = []
	for m in b.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.material_overlay is ShaderMaterial and not overlays.has(mi.material_overlay):
			overlays.append(mi.material_overlay)
		if mi.material_override is ShaderMaterial and not paints.has(mi.material_override) \
				and (mi.material_override as ShaderMaterial).get_shader_parameter("paint_strength") != null:
			paints.append(mi.material_override)
	var start := {}
	for o in overlays:
		start[o] = [_param(o, "grime"), _param(o, "cracks"), _param(o, "moss")]
	for p in paints:
		start[p] = _param(p, "paint_strength")

	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		if not is_instance_valid(b):
			return
		var e := smoothstep(0.0, 1.0, k)
		var bump := 1.0 + 0.07 * sin(k * PI)   # a little stretch as it rights itself
		b.global_transform = Transform3D(Basis(q0.slerp(q1, e)).scaled(Vector3(s.x, s.y * bump, s.z)), p0.lerp(p1, e))
		for o in overlays:
			o.set_shader_parameter("grime", lerpf(start[o][0], 0.0, e))
			o.set_shader_parameter("cracks", lerpf(start[o][1], 0.0, e))
			o.set_shader_parameter("moss", lerpf(start[o][2], 0.0, e))
		for p in paints:
			p.set_shader_parameter("paint_strength", lerpf(start[p], PAINT, e)),
		0.0, 1.0, POP_TIME)
	var c := _boxes[i].get_center()
	QuakeFX.dust(self, Vector3(c.x, _ground_y + 0.6, c.z), _boxes[i].size.x * 0.45, 16, 7.0, 2.4, 3.0, 7.0, DUST, true)
	_clank()


func _clear_prop(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var s0 := n.scale
	var t := create_tween()
	t.tween_property(n, "scale", s0 * 0.01, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(n.queue_free)
	QuakeFX.dust(self, n.global_position + Vector3.UP * 1.5, 3.0, 8, 4.5, 1.8, 2.0, 3.0, DUST)


func _swap_prop(n: Node3D, path: String) -> void:
	if not is_instance_valid(n):
		return
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	if packed == null:
		_clear_prop(n)
		return
	var xf := n.global_transform
	var s := xf.basis.get_scale().abs()
	var bx := xf.basis.x
	var fresh := packed.instantiate() as Node3D
	fresh.name = String(n.name).replace("_broken", "").replace("_dead", "_round")
	_props.add_child(fresh)
	var goal := Transform3D(Basis(Vector3.UP, atan2(-bx.z, bx.x)).scaled(s),
		Vector3(xf.origin.x, _ground_y, xf.origin.z))
	fresh.global_transform = goal
	var full := fresh.scale
	fresh.scale = full * 0.01
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(fresh, "scale", full, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_clear_prop(n)


## Make the repair permanent: the weathering script would otherwise put the
## old grime back the next time it repaints, and the quake reads the metadata.
func _settle() -> void:
	for b in _buildings:
		if not is_instance_valid(b):
			continue
		for key in ["grime", "cracks", "paint_strength"]:
			if b.has_meta(key):
				b.remove_meta(key)
		b.set_meta("structural_integrity", maxf(float(b.get_meta("structural_integrity", 0.0)), REPAIRED_INTEGRITY))
	_weather.set("moss", 0.0)
	_weather.set("cracks", 0.0)
	_weather.set("grime", 0.0)
	_weather.set("paint_strength", PAINT)
	_district.set_meta("risk_level", "low")
	_district.set_meta("description", "Old buildings braced with timber and repaired. As sound as the rest of the city.")


# ================================================================ builders

func _spawn_workers() -> void:
	var c := _flat(focus)
	var order: Array = range(_buildings.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _flat(_boxes[a].get_center()).distance_to(c) < _flat(_boxes[b].get_center()).distance_to(c))
	var jobs := [ConstructionWorker.Job.HAMMER, ConstructionWorker.Job.CARRY, ConstructionWorker.Job.SUPERVISE, ConstructionWorker.Job.HAMMER,
		ConstructionWorker.Job.SHOVEL, ConstructionWorker.Job.CARRY, ConstructionWorker.Job.HAMMER]
	var n := 0
	for i in order.slice(0, 14):
		if _flat(_boxes[i].get_center()).distance_to(c) > 5.0 * _tile:
			break
		var look := _site.to_local(_boxes[i].get_center())
		look.y = 0.0
		for k in 2:
			var w := ConstructionWorker.new()
			w.scale = Vector3.ONE * 1.3
			_site.add_child(w)
			w.pick_point = _work_point.bind(i)
			w.start(jobs[n % jobs.size()], _work_point(i, 0.3), _work_point(i), 0.0, look)
			_workers.append(w)
			_transients.append(w)
			n += 1


## A random spot just outside building `i`, in the site's (one tile) units.
func _work_point(i: int, out := 0.08) -> Vector3:
	var r := _boxes[i].grow(out * _tile)
	var u := _rng.randf() * 2.0 * (r.size.x + r.size.z)
	var x: float
	var z: float
	if u < r.size.x:
		x = r.position.x + u; z = r.end.z
	elif u < r.size.x + r.size.z:
		x = r.end.x; z = r.end.z - (u - r.size.x)
	elif u < 2.0 * r.size.x + r.size.z:
		x = r.end.x - (u - r.size.x - r.size.z); z = r.position.z
	else:
		x = r.position.x; z = r.position.z + (u - 2.0 * r.size.x - r.size.z)
	var p := _site.to_local(Vector3(x, _ground_y, z))
	return Vector3(p.x, 0.0, p.z)


# ================================================================ denied

## Dust blowing down the empty street and tumbleweeds rolling past the camera.
## Returns how long the last one takes to roll by, in seconds.
func tumbleweeds(count := 2) -> float:
	var c := _street_axis * _street_sign        # toward the camera
	var side := c.cross(Vector3.UP).normalized()
	var base := Vector3(focus.x, _street_y, focus.z)
	_wind_dust(base, c, side)
	var longest := 0.0
	for i in count:
		var r := _rng.randf_range(0.06, 0.08) * _tile
		var delay := i * 1.5 + _rng.randf_range(0.0, 0.3)
		var time := 6.0 + i * 0.8 + _rng.randf_range(-0.3, 0.3)
		var lane := (-0.12 + 0.2 * i + _rng.randf_range(-0.04, 0.04)) * _tile
		var from := base - c * 3.5 * _tile + side * lane
		var to := base + c * 3.6 * _tile + side * (lane + _rng.randf_range(-0.1, 0.1) * _tile)
		var tw := _tumbleweed(r)
		add_child(tw)
		_transients.append(tw)
		tw.global_position = from + Vector3.UP * r
		_roll(tw, from, to, r, time, delay)
		longest = maxf(longest, delay + time)
	return longest


func _roll(tw: Node3D, from: Vector3, to: Vector3, r: float, time: float, delay: float) -> void:
	var ball := tw.get_child(0) as Node3D
	var dir := (to - from).normalized()
	var axis := Vector3.UP.cross(dir).normalized()
	var dist := from.distance_to(to)
	var hops := maxf(3.0, dist / (r * 9.0))
	var spin0 := ball.basis
	var state := {"last": 0.0}
	var t := create_tween()
	var weed: WeakRef = weakref(tw)
	var ball_ref: WeakRef = weakref(ball)
	tw.tree_exiting.connect(t.kill)
	t.tween_interval(delay)
	t.tween_method(_roll_step.bind(weed, ball_ref, from, to, axis, r, hops, dist, spin0, state),
		0.0, 1.0, time)
	t.tween_property(tw, "scale", Vector3.ONE * 0.01, 0.3)


func _roll_step(k: float, weed: WeakRef, ball_ref: WeakRef, from: Vector3, to: Vector3, axis: Vector3,
		r: float, hops: float, dist: float, spin0: Basis, state: Dictionary) -> void:
	var tw := weed.get_ref() as Node3D
	var ball := ball_ref.get_ref() as Node3D
	if tw == null or ball == null:
		return
	var g := clampf(k + 0.025 * sin(k * 11.0), 0.0, 1.0)
	var h := g * hops
	var hop := absf(sin(h * PI)) * r * (0.8 + 0.5 * sin(h * 1.7))
	var pos := from.lerp(to, g) + axis * sin(g * 6.0) * r * 0.8
	tw.global_position = pos + Vector3.UP * (r + hop)
	ball.basis = Basis(axis, g * dist / r) * spin0
	if floorf(h) != floorf(state.last):
		QuakeFX.dust(self, pos + Vector3.UP * 0.3, r * 0.4, 5, r * 0.9, 1.3, r * 0.6, r * 1.1, SAND)
	state.last = h


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


## Low sandy dust drifting down the street on the wind.
func _wind_dust(base: Vector3, dir: Vector3, side: Vector3) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var along := dir.abs() * 3.5 * _tile
	var across := side.abs() * 0.45 * _tile
	pm.emission_box_extents = along + across + Vector3(0, 0.4, 0)
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
	_transients.append(p)


# ================================================================ clean up

## Builders, tumbleweeds, dust and sound go; the repairs themselves stay.
func clear_transients() -> void:
	_stop_sound()
	for n in _transients:
		if is_instance_valid(n):
			n.queue_free()
	_transients.clear()
	_workers.clear()


# ================================================================ sound

func _start_sound() -> void:
	var s := _stream(HAMMERING)
	if s:
		_hammer = AudioStreamPlayer.new()
		_hammer.stream = s
		_hammer.volume_db = -4.0
		add_child(_hammer)
		_hammer.play(HAMMER_LOOP.x)
		set_process(true)
	var m := _stream(METAL)
	if m:
		_metal = AudioStreamPlayer.new()
		_metal.stream = m
		_metal.max_polyphony = 4
		add_child(_metal)


func _stop_sound() -> void:
	set_process(false)
	for p in [_hammer, _metal]:
		if p and is_instance_valid(p):
			p.queue_free()
	_hammer = null
	_metal = null


func _clank() -> void:
	if _metal == null or _clock - _last_clank < 0.12:
		return
	_last_clank = _clock
	_metal.pitch_scale = _rng.randf_range(0.8, 1.2)
	_metal.volume_db = _rng.randf_range(-6.0, 0.0)
	_metal.play()


func _process(delta: float) -> void:
	_clock += delta
	# keep the hammering looping over its busy part
	if _hammer and (not _hammer.playing or _hammer.get_playback_position() >= HAMMER_LOOP.y):
		_hammer.play(HAMMER_LOOP.x)


func _stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


# ================================================================ helpers

## The main street: the road tile nearest the middle of the quarter, and which
## way the longer run of road goes through it.
func _find_street(all: AABB) -> void:
	var roads := _city.get_node_or_null("Roads")
	if roads == null:
		return
	var area := all.grow(_tile)
	var tiles: Array[Vector3] = []
	for r in roads.get_children():
		if not r is Node3D:
			continue
		var bb := _box_of(r)
		var p: Vector3 = bb.get_center() if bb.size != Vector3.ZERO else (r as Node3D).global_position
		if p.x > area.position.x and p.x < area.end.x and p.z > area.position.z and p.z < area.end.z:
			tiles.append(Vector3(p.x, bb.end.y if bb.size != Vector3.ZERO else p.y, p.z))
	if tiles.is_empty():
		return
	var c := _flat(focus)
	var best := tiles[0]
	for t in tiles:
		if _flat(t).distance_to(c) < _flat(best).distance_to(c):
			best = t
	var along_x := 0
	var along_z := 0
	for t in tiles:
		if absf(t.z - best.z) < _tile * 0.3:
			along_x += 1
		if absf(t.x - best.x) < _tile * 0.3:
			along_z += 1
	_street_axis = Vector3.RIGHT if along_x >= along_z else Vector3.BACK
	# the camera stands on the side with more street (and buildings) behind it
	var plus := 0
	var minus := 0
	for t in tiles:
		var on_line := absf((t - best).dot(_street_axis.cross(Vector3.UP))) < _tile * 0.3
		if on_line:
			var d := (t - best).dot(_street_axis)
			if d > 1.0:
				plus += 1
			elif d < -1.0:
				minus += 1
	_street_sign = 1.0 if plus >= minus else -1.0
	focus = Vector3(best.x, _ground_y, best.z)
	_street_y = best.y


func _box_of(n: Node) -> AABB:
	var bb := AABB()
	var first := true
	if n is VisualInstance3D:
		bb = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
		first = false
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


func _after(seconds: float, what: Callable) -> void:
	var t := create_tween()
	t.tween_interval(seconds)
	t.tween_callback(what)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _starts_with_any(node_name: StringName, prefixes: Array) -> bool:
	var s := String(node_name)
	for p in prefixes:
		if s.begins_with(p):
			return true
	return false


func _param(m: ShaderMaterial, key: String) -> float:
	var v = m.get_shader_parameter(key)
	return float(v) if v != null else 0.0


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m
