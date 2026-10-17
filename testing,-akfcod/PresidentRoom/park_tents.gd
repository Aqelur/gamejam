extends Node3D
## Shelter tents and evacuation signs in Central Park, for the Head of
## Disaster Agency's proposal (proposals/agency_park_tents.tres, action TENTS).
##
## day_cycle.gd adds this under Central Park in the city, calls setup(park)
## and then raise() once the camera is over the east lawn: evacuation signs
## spring up at every park gate, a green EMERGENCY SHELTER gate goes up over
## the diagonal path and rows of tents pop up on both sides of it, each with a
## puff of dust, with supply crates stacked by the gate. Everything stays for
## the rest of the game (the city is kept between days), ready for the night
## the big one hits.
##
## Everything is in the park's own units (one unit = one city tile), like
## central_park_drill.gd. Tents only go where nothing is in the way: trees,
## benches, lamps, flower beds, the bandstand, the pond and the paths. The
## drill crowd gathers at the fountain plaza, well away from the camp.

const PARK := "Districts/EvacuationPark/CentralPark"
const TENT := preload("res://Models/Custom/tent.glb")
const SIGN := preload("res://Models/Custom/sign_evacuation.glb")
const CRATES := preload("res://Models/Custom/supply_crates.glb")
const FONT := "res://PresidentRoom/fonts/Montserrat-ExtraBold.ttf"

## The east lawn the camp fills, x/z in park units.
const CAMP := Rect2(18.2, -8.6, 5.7, 3.9)
## The path the camp is laid out along; its gate goes over it.
const MAIN_PATH := "Paths/DiagSE"
## Paths whose ends at the edge of the park get an evacuation sign.
const GATE_PATHS := ["Promenade", "CrossWalk", "DiagNW", "DiagNE", "DiagSW", "DiagSE"]
const LAWN_Y := 0.07          # top of the grass
const PAVING_Y := 0.085       # top of the paths
const SIGN_Y := 0.04          # where the plaza's own evacuation signs stand
const TENT_SCALE := 0.72
const TENT_R := 0.22          # room a tent needs around its centre
const STEP := Vector2(0.62, 0.76)   # tent grid spacing (across, between rows)
const SIGN_R := 0.14
const POP_GAP := 0.07         # seconds between one tent popping up and the next
const DUST := Color(0.78, 0.74, 0.6, 0.5)
const SHELTER_GREEN := Color(0.08, 0.5, 0.3)

## True once everything is up (raise() finished or finish() was called).
var done := false

var _park: Node3D
var _tile := 26.926893
var _rng := RandomNumberGenerator.new()
var _circles: Array[Vector3] = []     # x, z, radius
var _ellipses: Array[Vector4] = []    # x, z, radius x, radius z
var _boxes: Array[Dictionary] = []    # {"o": Vector2, "ax": Vector2, "half": Vector2}
## Everything that pops up, in order: {"node": Node3D, "scale": Vector3, "dust": bool}
var _items: Array[Dictionary] = []
var _tweens: Array[Tween] = []
var _font: Font
var _mats := {}


func _init() -> void:
	name = "ShelterCamp"
	_rng.seed = 2300   # the night the big one hits


## Lay out the camp (still hidden) in `park` (the CentralPark node). Call
## after adding this node as a child of `park`.
func setup(park: Node3D) -> void:
	_park = park
	transform = Transform3D.IDENTITY
	_tile = absf(park.global_basis.get_scale().x)
	if ResourceLoader.exists(FONT):
		_font = load(FONT) as Font
	_collect_obstacles()
	_place_signs()
	_place_gate()
	_place_tents()
	for it in _items:
		(it.node as Node3D).scale = Vector3.ONE * 0.001
		(it.node as Node3D).visible = false


## [camera position, look at, slow creep] in world space: high over the
## park's corner, looking in through the shelter gate and up the path between
## the rows of tents, creeping slowly in.
func shot() -> Array:
	var gate := get_node_or_null("ShelterGate") as Node3D
	if gate == null:
		var c := _camp_centre()
		return [to_global(c + Vector3(-2.1, 2.3, 3.1)), to_global(c + Vector3(0.25, 0.05, -0.25)),
			global_basis * Vector3(0.35, -0.3, -0.5)]
	var inward := Vector3(sin(gate.rotation.y), 0.0, cos(gate.rotation.y))   # up the path
	return [to_global(gate.position - inward * 1.9 + Vector3.UP * 1.75),
		to_global(gate.position + inward * 1.5 + Vector3.UP * 0.05),
		global_basis * (inward * 0.5 + Vector3.DOWN * 0.3)]


## Pop everything up: the signs, the gate and crates, then the tents in a wave
## outward from the gate. Returns when the last tent has landed.
func raise() -> void:
	var tw := create_tween().set_parallel(true)
	_tweens.append(tw)
	for it in _items:
		var n: Node3D = it.node
		var full: Vector3 = it.scale
		var d: float = it.delay
		tw.tween_callback(func() -> void:
			n.visible = true
			if it.dust:
				_puff(n.global_position)).set_delay(d)
		tw.tween_property(n, "scale", full * 1.12, 0.22).set_delay(d) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "scale", full, 0.14).set_delay(d + 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	done = true


## Jump straight to the end (the player skipped): everything up, no dust.
func finish() -> void:
	for tw in _tweens:
		if tw and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for it in _items:
		(it.node as Node3D).visible = true
		(it.node as Node3D).scale = it.scale
	done = true


# ================================================================ layout

func _place_signs() -> void:
	var ends: Array[Vector2] = []
	var delay := 0.0
	for path_name in GATE_PATHS:
		var b := _path_box(path_name)
		if b.is_empty():
			continue
		for side in [1.0, -1.0]:
			var end: Vector2 = b.o + b.ax * b.half.x * side
			if not _at_edge(end):
				continue
			var dupe := false
			for e in ends:
				if e.distance_to(end) < 1.0:
					dupe = true
					break
			if dupe:
				continue
			ends.append(end)
			var inward: Vector2 = -b.ax * side   # into the park
			var across := Vector2(-inward.y, inward.x)
			for s in [1.0, -1.0]:
				var p: Vector2 = end + inward * 0.45 + across * s * (b.half.y + 0.18)
				if not _clear(p, SIGN_R):
					continue
				var post := SIGN.instantiate() as Node3D
				post.name = "EvacSign%d" % ends.size()
				add_child(post)
				post.position = Vector3(p.x, SIGN_Y, p.y)
				post.rotation.y = atan2(-inward.x, -inward.y)   # faces people coming in
				_circles.append(Vector3(p.x, p.y, SIGN_R))
				_add(post, delay, false)
				delay += 0.09
				break


## The EMERGENCY SHELTER gate over the main path, a little in from its
## south end, with crates stacked by it and an evacuation sign either side.
func _place_gate() -> void:
	var b := _path_box(MAIN_PATH)
	if b.is_empty():
		return
	var ax: Vector2 = b.ax
	var south: float = 1.0 if ax.y > 0.0 else -1.0
	var inward := -ax * south                # from the south end up the path
	var at: Vector2 = b.o + ax * b.half.x * south + inward * 1.6
	var across := Vector2(-inward.y, inward.x)
	var half_w: float = b.half.y + 0.12

	var gate := Node3D.new()
	gate.name = "ShelterGate"
	add_child(gate)
	gate.position = Vector3(at.x, PAVING_Y, at.y)
	gate.rotation.y = atan2(inward.x, inward.y)   # local z up the path, the board across it
	var post := _mat(Color(0.92, 0.92, 0.9))
	for s in [-1.0, 1.0]:
		_box(gate, Vector3(0.03, 0.44, 0.03), Vector3(s * half_w, 0.22, 0), post)
	var green := _mat(SHELTER_GREEN, 0.25)
	_box(gate, Vector3(half_w * 2.0 + 0.1, 0.13, 0.016), Vector3(0, 0.4, 0), green)
	_box(gate, Vector3(half_w * 2.0 + 0.12, 0.012, 0.02), Vector3(0, 0.47, 0), post)
	_box(gate, Vector3(half_w * 2.0 + 0.12, 0.012, 0.02), Vector3(0, 0.33, 0), post)
	for face in [0.0, PI]:
		var l := Label3D.new()
		l.text = "EMERGENCY SHELTER"
		if _font:
			l.font = _font
		l.font_size = 64
		l.pixel_size = 0.00072 * (half_w * 2.0 + 0.1) / 0.69
		l.outline_size = 0
		l.modulate = Color(1, 1, 1)
		l.double_sided = false
		l.shaded = false
		l.rotation.y = face
		l.position = Vector3(0, 0.4, 0.0095 if face == 0.0 else -0.0095)
		gate.add_child(l)
	for s in [-1.0, 1.0]:
		var p: Vector2 = at + across * s * (half_w + 0.07)
		_circles.append(Vector3(p.x, p.y, 0.06))
	_add(gate, 0.75, true)

	# crates on the lawn either side of the gate
	var spots := [across * (half_w + 0.38) - inward * 0.15, -across * (half_w + 0.38) - inward * 0.1,
		across * (half_w + 0.42) + inward * 0.32]
	var delay := 0.95
	for i in spots.size():
		var p: Vector2 = at + spots[i]
		if not _clear(p, 0.16):
			continue
		var c := CRATES.instantiate() as Node3D
		c.name = "Crates%d" % i
		add_child(c)
		c.position = Vector3(p.x, LAWN_Y, p.y)
		c.rotation.y = gate.rotation.y + _rng.randf_range(-0.3, 0.3)
		c.scale = Vector3.ONE * 0.8
		_circles.append(Vector3(p.x, p.y, 0.18))
		_add(c, delay, true)
		delay += 0.12

	# evacuation signs flanking the gate, facing the people coming in
	for s in [-1.0, 1.0]:
		var p := Vector2.INF
		for back in [0.2, 0.45, 0.7, 0.0]:
			for out in [0.3, 0.45, 0.6]:
				var q: Vector2 = at - inward * back + across * s * (half_w + out)
				if p == Vector2.INF and _clear(q, SIGN_R):
					p = q
		if p == Vector2.INF:
			continue
		var flank := SIGN.instantiate() as Node3D
		flank.name = "EvacSignGate%d" % (0 if s < 0.0 else 1)
		add_child(flank)
		flank.position = Vector3(p.x, SIGN_Y, p.y)
		flank.rotation.y = atan2(-inward.x, -inward.y)
		_circles.append(Vector3(p.x, p.y, SIGN_R))
		_add(flank, 0.85, false)


## Rows of tents over CAMP, staggered, nudged a little where something is in
## the way, popping up in a wave outward from the gate.
func _place_tents() -> void:
	var gate := get_node_or_null("ShelterGate") as Node3D
	var origin := Vector2(gate.position.x, gate.position.z) if gate else CAMP.get_center()
	var nudges := [Vector2.ZERO, Vector2(0.12, 0), Vector2(-0.12, 0), Vector2(0, 0.12),
		Vector2(0, -0.12), Vector2(0.12, 0.12), Vector2(-0.12, -0.12), Vector2(0.12, -0.12),
		Vector2(-0.12, 0.12)]
	var spots: Array[Vector3] = []   # x, z, row
	var row := 0
	var z := CAMP.position.y + TENT_R
	while z <= CAMP.end.y - TENT_R:
		var x := CAMP.position.x + TENT_R + (STEP.x * 0.5 if row % 2 == 1 else 0.0)
		while x <= CAMP.end.x - TENT_R:
			for n in nudges:
				var p: Vector2 = Vector2(x, z) + n
				if not CAMP.grow(0.05).has_point(p) or not _clear(p, TENT_R):
					continue
				var ok := true
				for s in spots:
					if Vector2(s.x, s.y).distance_to(p) < STEP.x * 0.85:
						ok = false
						break
				if ok:
					spots.append(Vector3(p.x, p.y, row))
					break
			x += STEP.x
		z += STEP.y
		row += 1
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Vector2(a.x, a.y).distance_to(origin) < Vector2(b.x, b.y).distance_to(origin))
	var delay := 1.3
	for i in spots.size():
		var s := spots[i]
		var tent := TENT.instantiate() as Node3D
		tent.name = "Tent%d" % i
		add_child(tent)
		tent.position = Vector3(s.x, LAWN_Y, s.y)
		# neighbouring rows face each other across the gap between them
		tent.rotation.y = (0.0 if int(s.z) % 2 == 0 else PI) + _rng.randf_range(-0.08, 0.08)
		_circles.append(Vector3(s.x, s.y, TENT_R))
		_add(tent, delay, true, TENT_SCALE)
		delay += POP_GAP


func _add(n: Node3D, delay: float, dust: bool, size := -1.0) -> void:
	var full := n.scale if size < 0.0 else Vector3.ONE * size
	_items.append({"node": n, "scale": full, "delay": delay, "dust": dust})


func _camp_centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for it in _items:
		if String((it.node as Node).name).begins_with("Tent"):
			sum += (it.node as Node3D).position
			n += 1
	if n == 0:
		var c := CAMP.get_center()
		return Vector3(c.x, LAWN_Y, c.y)
	return sum / n


## A path end on the edge of the park (or of the lawn round the fountain).
func _at_edge(p: Vector2) -> bool:
	return p.x < -2.9 or p.x > 23.9 or p.y < -13.8 or p.y > -4.45


# ================================================================ what's in the way

func _collect_obstacles() -> void:
	# trees, benches, lamps, planters and signs: round, as wide as they are
	for group_name in ["Trees", "Benches", "Lamps", "FountainPlaza", "Pond"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for c in g.get_children():
			if c is MeshInstance3D or not c is Node3D:
				continue
			var bb := _local_bounds(c as Node3D)
			if bb.size == Vector3.ZERO:
				continue
			var mid := bb.get_center()
			_circles.append(Vector3(mid.x, mid.z, maxf(bb.size.x, bb.size.z) * 0.5))
	# the plaza, the pond, the bandstand and the flower beds: discs
	for group_name in ["FountainPlaza", "Pond", "Bandstand", "FlowerBeds"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var cm := (mi as MeshInstance3D).mesh as CylinderMesh
			if cm == null:
				continue
			var xf := global_transform.affine_inverse() * (mi as Node3D).global_transform
			var r := maxf(cm.top_radius, cm.bottom_radius)
			_ellipses.append(Vector4(xf.origin.x, xf.origin.z,
				r * xf.basis.x.length(), r * xf.basis.z.length()))
	# paths and hedges: boxes
	for group_name in ["Paths", "Hedges"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for c in g.get_children():
			var b := _box_of(c)
			if not b.is_empty():
				_boxes.append(b)


func _path_box(path_name: String) -> Dictionary:
	var n := _park.get_node_or_null(path_name if path_name.contains("/") else "Paths/" + path_name)
	return _box_of(n)


## A flat box mesh as {"o": centre, "ax": along its length, "half": (half
## length, half width)}, x/z in park units. Empty if it isn't one.
func _box_of(n: Node) -> Dictionary:
	var mi := n as MeshInstance3D
	if mi == null or not mi.mesh is BoxMesh:
		return {}
	var size := (mi.mesh as BoxMesh).size
	var xf := global_transform.affine_inverse() * mi.global_transform
	var along := Vector2(xf.basis.z.x, xf.basis.z.z)
	var side := Vector2(xf.basis.x.x, xf.basis.x.z)
	return {"o": Vector2(xf.origin.x, xf.origin.z), "ax": along.normalized(),
		"half": Vector2(size.z * 0.5 * along.length(), size.x * 0.5 * side.length())}


func _clear(p: Vector2, r: float) -> bool:
	for c in _circles:
		if Vector2(c.x, c.y).distance_to(p) < c.z + r:
			return false
	for e in _ellipses:
		var dx := (p.x - e.x) / (e.z + r)
		var dz := (p.y - e.y) / (e.w + r)
		if dx * dx + dz * dz < 1.0:
			return false
	for b in _boxes:
		var d: Vector2 = p - b.o
		var ax: Vector2 = b.ax
		if absf(d.dot(ax)) < b.half.x + r and absf(d.dot(Vector2(-ax.y, ax.x))) < b.half.y + r:
			return false
	return true


func _local_bounds(n: Node3D) -> AABB:
	var inv := global_transform.affine_inverse()
	var bb := AABB()
	var first := true
	var parts: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		parts.append(n)
	for v in parts:
		var vi := v as VisualInstance3D
		var b: AABB = inv * vi.global_transform * vi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


# ================================================================ bits

func _puff(at: Vector3) -> void:
	QuakeFX.dust(self, at + Vector3.UP * 0.02 * _tile, 0.09 * _tile, 6, 0.09 * _tile, 1.1,
		0.05 * _tile, 0.16 * _tile, DUST)


func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%s" % [c, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
