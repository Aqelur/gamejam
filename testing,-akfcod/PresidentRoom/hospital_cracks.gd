extends Node3D
## Cracks in a building that was put up with too little concrete, for the
## Contractor's proposal (proposals/contractor_hospital.tres, action CRACKS).
##
## day_cycle.gd adds this under the building's node in the city (the Buildable
## hospital), calls setup(building) and then grow() once the camera has swung
## round behind it. A few cracks creep up the back wall and one splits the
## ground behind the building, each with a small puff of grit. They stay for
## the rest of the game (the city is kept between days), and the building's
## "structural_integrity" meta drops for the earthquake.
##
## The cracks are Decals (Forward+ / Mobile renderer) with textures drawn here
## at runtime, so there are no image files to import. Everything is in the
## building's local units, like buildable.gd, so it works at any scale.
##
## In the earthquake ending (hospital_quake.gd) widen() tears them open:
## every crack grows wider and longer while grit pours out, and new ones split
## open beside them. If the building comes down they are hidden with it.

## Wall cracks as (across the back wall 0..1, up the wall 0..1).
const WALL_SPOTS := [Vector2(0.2, 0.12), Vector2(0.58, 0.38), Vector2(0.84, 0.16)]
## Where new cracks split open when the quake widens them.
const EXTRA_SPOTS := [Vector2(0.4, 0.2), Vector2(0.7, 0.6), Vector2(0.08, 0.42), Vector2(0.94, 0.5)]
const TEX := 160                 # crack texture size in pixels
const FRAMES := 12               # growth steps per crack
const GROW_TIME := 1.7           # seconds for one crack to reach full length
const STAGGER := 0.55            # seconds between one crack starting and the next
const INK := Color(0.06, 0.05, 0.045, 0.96)
const GRIT := Color(0.62, 0.6, 0.56)
## structural_integrity the building is left with (Downtown is 1.0).
const INTEGRITY := 0.35

var _rng := RandomNumberGenerator.new()
var _cracks: Array[Dictionary] = []   # {"decal": Decal, "frames": Array, "at": Vector3}
# the back wall, measured by setup() (building-local)
var _fp := AABB()
var _h := 1.5
var _back := 0.0
var _depth := 0.5
var _sz := 1.0


func _init() -> void:
	name = "Cracks"
	_rng.seed = 7311


## Lay out the (still invisible) cracks on `building`'s back wall and the
## ground behind it. Call after adding this node as a child of `building`.
func setup(building: Node3D) -> void:
	var fp := AABB(Vector3(-1.5, 0.0, -1.5), Vector3(3.0, 1.5, 3.0))
	var f = building.get("_footprint")        # measured by buildable.gd
	if f is AABB and f.size.x > 0.1:
		fp = f
	var h := fp.end.y
	var hv = building.get("_height")
	if typeof(hv) == TYPE_FLOAT:
		h = maxf(h, hv)
	var w := fp.size.x
	var back := fp.position.z                 # buildings face +z (day_cycle.gd _fly_to)
	var sz := clampf(minf(w, h) * 0.42, 0.55, 1.7)
	# up the back wall: the box reaches a little way in, so a back wall that
	# is set in from the footprint still catches it; only faces looking out
	# the back take the decal (normal_fade)
	var depth := maxf(fp.size.z * 0.45, 0.5)
	_fp = fp
	_h = h
	_back = back
	_depth = depth
	_sz = sz

	for s in WALL_SPOTS:
		_cracks.append(_wall_crack(s, 1.0))

	# one across the ground behind it
	var g := sz * 1.5
	var gpos := Vector3(fp.get_center().x + w * 0.12, 0.0, back - g * 0.45)
	var gd := _decal(Vector3(g, 0.6, g), gpos, Basis.IDENTITY)
	_cracks.append({"decal": gd, "frames": _crack_frames(), "at": gpos})

	building.set_meta("structural_integrity",
		minf(float(building.get_meta("structural_integrity", 1.0)), INTEGRITY))


## The cracks spread one after another. Returns when the last one is done.
func grow() -> void:
	for i in _cracks.size():
		_grow_one(_cracks[i], i * STAGGER)
	await get_tree().create_timer(STAGGER * (_cracks.size() - 1) + GROW_TIME + 0.2).timeout


## Show every crack fully grown straight away.
func show_now() -> void:
	for c in _cracks:
		var d: Decal = c.decal
		d.texture_albedo = c.frames[-1]
		d.visible = true


## The quake tears the cracks open: over `time` seconds every crack grows
## `factor` times wider and longer (its lines get thicker with it) while grit
## pours out of it, and `extra` new cracks split open on the back wall.
## Returns at once.
func widen(factor := 1.7, time := 3.0, extra := 2) -> void:
	for c in _cracks:
		var d: Decal = c.decal
		d.texture_albedo = c.frames[-1]
		d.visible = true
		var to := Vector3(d.size.x * factor, d.size.y, d.size.z * factor)
		var t := create_tween()
		t.tween_property(d, "size", to, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_puff(c.at, 34)
		_puff_later(c.at, time * 0.4)
	for i in mini(extra, EXTRA_SPOTS.size()):
		var c := _wall_crack(EXTRA_SPOTS[i], factor * 0.8)
		_cracks.append(c)
		_grow_one(c, time * 0.2 * (i + 1))


## The hospital is coming down: the ground under it splits open. One wide
## crack across the middle and two smaller ones beside it, all kept inside the
## building's own footprint so they never run out past the hospital. The wall
## cracks stay until fallen() (the walls are still up for a moment).
## Returns at once.
func split_ground(time := 1.2) -> void:
	var c := _fp.get_center()
	var w := _fp.size.x
	var d := _fp.size.z
	# small enough that, turned any way, they stay inside the footprint
	var small := minf(w, d) * 0.38
	var splits := [
		[Vector3(c.x, 0.0, c.z), Vector3(w * 0.9, 0.5, d * 0.9), 2.6],
		[Vector3(c.x - w * 0.22, 0.0, c.z + d * 0.2), Vector3(small, 0.5, small), 1.8],
		[Vector3(c.x + w * 0.22, 0.0, c.z - d * 0.2), Vector3(small, 0.5, small), 1.8],
	]
	for i in splits.size():
		var s: Array = splits[i]
		var dec := _decal(s[1], s[0], Basis(Vector3.UP, _rng.randf() * TAU) if i > 0 else Basis.IDENTITY)
		var crack := {"decal": dec, "frames": _crack_frames(s[2]), "at": s[0], "split": true}
		_cracks.append(crack)
		_grow_one(crack, time * 0.25 * i, time)


## The building is gone: hide the cracks that were on it, keep the ground split.
func fallen() -> void:
	for c in _cracks:
		if not c.get("split", false):
			(c.decal as Decal).visible = false


func _puff_later(at: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if is_inside_tree():
		_puff(at, 28)


## A (still invisible) crack on the back wall at `spot` (across 0..1, up 0..1).
func _wall_crack(spot: Vector2, size_k: float) -> Dictionary:
	var k := _sz * _rng.randf_range(0.85, 1.15) * size_k
	var pos := Vector3(_fp.position.x + _fp.size.x * spot.x, clampf(_h * spot.y + k * 0.5, k * 0.5, maxf(k * 0.5, _h - k * 0.3)),
		_back + _depth * 0.5 - 0.08)
	var d := _decal(Vector3(k, _depth, k), pos, Basis(Vector3.RIGHT, -PI * 0.5))
	return {"decal": d, "frames": _crack_frames(), "at": Vector3(pos.x, pos.y, _back)}


func _grow_one(c: Dictionary, delay: float, time := GROW_TIME) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var d: Decal = c.decal
	var frames: Array = c.frames
	d.texture_albedo = frames[0]
	d.visible = true
	_puff(c.at)
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		d.texture_albedo = frames[clampi(int(k * frames.size()), 0, frames.size() - 1)],
		0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _decal(size: Vector3, pos: Vector3, basis: Basis) -> Decal:
	var d := Decal.new()
	d.size = size
	d.transform = Transform3D(basis, pos)
	d.albedo_mix = 1.0
	d.normal_fade = 0.45
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.visible = false
	add_child(d)
	return d


# ---------------------------------------------------------------- textures

## A crack drawn in FRAMES steps: each frame is the crack a little longer.
## `thick` scales the line width (big ground splits are drawn wider).
func _crack_frames(thick := 1.0) -> Array:
	# segments: [from, to, t_from, t_to, width], t = order along the crack
	var segs: Array = []
	var start := Vector2(0.5, 0.5) + Vector2(_rng.randf_range(-0.06, 0.06), _rng.randf_range(-0.06, 0.06))
	var a := _rng.randf() * TAU
	_branch(segs, start, a, 0.0, 9, 1.0)
	_branch(segs, start, a + PI + _rng.randf_range(-0.5, 0.5), 0.0, 8, 0.95)
	var tmax := 1.0
	for s in segs:
		tmax = maxf(tmax, s[3])

	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(INK.r, INK.g, INK.b, 0.0))
	var done := {}     # segment index -> fraction already drawn
	var frames: Array = []
	for f in range(1, FRAMES + 1):
		var reveal := tmax * float(f) / FRAMES
		for i in segs.size():
			var s: Array = segs[i]
			if s[2] >= reveal:
				continue
			var k := clampf((reveal - s[2]) / (s[3] - s[2]), 0.0, 1.0)
			var k0: float = done.get(i, 0.0)
			if k <= k0:
				continue
			var p0: Vector2 = (s[0] as Vector2).lerp(s[1], k0) * TEX
			var p1: Vector2 = (s[0] as Vector2).lerp(s[1], k) * TEX
			_line(img, p0, p1, 1.9 * s[4] * thick)
			done[i] = k
		frames.append(ImageTexture.create_from_image(img))
	return frames


## One zig-zagging arm of the crack, forking now and then into thinner ones.
func _branch(segs: Array, p: Vector2, a: float, t: float, steps: int, width: float) -> void:
	for i in steps:
		a += _rng.randf_range(-0.65, 0.65)
		var q := p + Vector2(cos(a), sin(a)) * _rng.randf_range(0.035, 0.06)
		if q.x < 0.04 or q.x > 0.96 or q.y < 0.04 or q.y > 0.96:
			return
		segs.append([p, q, t, t + 1.0, width])
		p = q
		t += 1.0
		width = maxf(width * 0.9, 0.35)
		if steps > 3 and width > 0.45 and _rng.randf() < 0.3:
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			_branch(segs, p, a + side * _rng.randf_range(0.5, 1.1), t, int(steps * 0.5), width * 0.7)


func _line(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / 0.5))
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / n), r)


## A soft round dab of ink with a faint shadow round it; never lightens a pixel.
func _dot(img: Image, c: Vector2, r: float) -> void:
	var reach := r + 1.8
	for y in range(maxi(0, floori(c.y - reach)), mini(TEX, ceili(c.y + reach) + 1)):
		for x in range(maxi(0, floori(c.x - reach)), mini(TEX, ceili(c.x + reach) + 1)):
			var d := c.distance_to(Vector2(x + 0.5, y + 0.5))
			var al := maxf(clampf(r + 0.5 - d, 0.0, 1.0) * INK.a, clampf(reach - d, 0.0, 1.0) * 0.28)
			if al > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(INK.r, INK.g, INK.b, al))


# ---------------------------------------------------------------- grit

## A little puff of grit and dust where a crack opens.
func _puff(at: Vector3, amount := 16) -> void:
	var p := CPUParticles3D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = amount
	p.lifetime = 1.3
	p.direction = Vector3(0, 0.3, -1)
	p.spread = 55.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = 0.035
	m.height = 0.07
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(GRIT, 0.9))
	ramp.set_color(1, Color(GRIT, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
