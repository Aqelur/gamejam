extends Node3D
## (Was park_shrouds.gd; moved here so an open editor tab of the old file
## can't save over it.)
## The last thing the ending shows (earthquake_ending.gd, after the summary):
## everyone who died, laid out in rows in Central Park, each under a black
## blanket. The camera starts on one of them and pulls back, 4, 9, 16...
## until all of them lie there.
##
## Central Park is cleared for this (its trees, paths, pond... are hidden) and
## the bodies lie on its lawn, now plain green; the wrecked city stays round it. They lie vertically on screen (head away
## from the camera, feet towards it), side by side in rows. Round the bodies
## is laid out a memorial (_decorate): kerb, walkway, candles and flowers,
## wreaths, a granite wall with an inscription and an obelisk, benches, lamps,
## an avenue of cypresses and a wood beyond.
## If there are more dead than fit, the rows close up and the bodies get
## smaller until they all do. The bodies are one MultiMesh, so thousands cost
## almost nothing.
##
##   setup(city, total) -> false if there's no Central Park
##   settle(from, to, k)  bodies from..to (0-based, `to` excluded) are laid down,
##                        k 0..1 (the blanket settles over them)
##   frame(n) -> [eye, look]   world-space camera for the first n bodies
##   frame_all() -> [eye, look]  the whole memorial
##   frame_city() -> [eye, look] high over the park and the wrecked city

const PARK := "Districts/EvacuationPark/CentralPark"
## The first body; the rows grow outward from here.
const START := Vector2(10.5, -9.0)
## Where bodies may go (park units): the middle of the main lawn, leaving room
## all round for the memorial, so none of it reaches the streets.
const AREA := Rect2(-1.65, -11.7, 24.3, 5.4)
## The park's lawns (central_park.tscn: Ground/Lawn and Ground/LobeLawn) and,
## a little wider, the sidewalks round them.
const LAWNS: Array[Rect2] = [Rect2(-3.5, -14.5, 28.0, 10.5), Rect2(4.0, -4.5, 6.0, 7.5)]
const PARK_EDGE: Array[Rect2] = [Rect2(-4.0, -15.0, 29.0, 11.5), Rect2(3.5, -4.75, 7.0, 8.0)]
## One body's spot: across it (x), along it (z, head to -z).
const CELL := Vector2(0.13, 0.27)
const LAWN_Y := 0.07
const BLANKET := Color(0.035, 0.035, 0.042)
const GRASS := Color(0.33, 0.55, 0.24)
const TREE_ROUND := preload("res://Models/Custom/tree_round.glb")
const TREE_CONE := preload("res://Models/Custom/tree_cone.glb")
const BENCH := preload("res://Models/Custom/bench.glb")
const LAMP := preload("res://Models/Custom/streetlight.glb")
const BUSH := Color(0.2, 0.42, 0.17)
const LEAF := Color(0.13, 0.32, 0.12)
const HEDGE := Color(0.14, 0.33, 0.13)
const MOWN := Color(0.38, 0.62, 0.27)
const PAVING := Color(0.8, 0.77, 0.7)
const KERB := Color(0.62, 0.6, 0.56)
const KERB_DARK := Color(0.36, 0.35, 0.33)
const GRANITE := Color(0.07, 0.07, 0.08)
## Body size in park units, before any shrinking.
const LENGTH := 0.2
const WIDTH := 0.092

## How many bodies are laid out (the total, unless the area is too small).
var count := 0

var _park: Node3D
var _rig: Node3D
var _mm: MultiMesh
var _rng := RandomNumberGenerator.new()
var _cell := CELL
var _size := 1.0
## Spots, park units: x, ground y, z. Nearest the start first.
var _spots: Array[Vector3] = []
var _base: Array[Transform3D] = []
## Bounds of the first i+1 bodies.
var _bounds: Array[Rect2] = []
## The whole memorial, park units, for the last wide shot (frame_all).
var _memorial := Rect2()


func _init() -> void:
	name = "ParkShrouds"
	_rng.seed = 1432


func setup(city: Node3D, total: int) -> bool:
	_park = city.get_node_or_null(PARK) as Node3D
	if _park == null or total <= 0:
		return false
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_rig.global_transform = _park.global_transform
	_clear_park(city)
	_add_field()
	# close the rows up until everyone fits
	for attempt in 8:
		_lay_out()
		if _spots.size() >= total:
			break
		var shrink := sqrt(float(_spots.size()) / float(total)) * 0.96
		_cell *= shrink
		_size *= shrink
	count = mini(total, _spots.size())
	_spots.resize(count)

	# lying vertically: the body's length runs along z
	var half := Vector2(WIDTH, LENGTH) * 0.5 * _size
	_bounds.resize(count)
	var r := Rect2()
	for i in count:
		var s := _spots[i]
		var b := Rect2(Vector2(s.x, s.z) - half, half * 2.0)
		r = b if i == 0 else r.merge(b)
		_bounds[i] = r
	_decorate(_bounds[count - 1], total)

	_base.resize(count)
	for i in count:
		var s := _spots[i]
		var grown := _size * (_rng.randf_range(0.66, 0.74) if _rng.randf() < 0.07 else _rng.randf_range(0.93, 1.05))
		# turned 90 degrees: the mesh's head (-x) points to -z, away from the camera
		var basis := Basis(Vector3.UP, -PI * 0.5 + _rng.randf_range(-0.05, 0.05)).scaled(Vector3.ONE * grown)
		_base[i] = Transform3D(basis, Vector3(s.x, s.y + 0.0015, s.z))

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _blanket_mesh()
	_mm.instance_count = count
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bodies"
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rig.add_child(mmi)
	return true


## Lay down bodies from..to (to excluded) as far as k (0..1): the blanket
## sinks over the body. Everything before `from` lies still.
func settle(from: int, to: int, k: float) -> void:
	to = mini(to, count)
	from = clampi(from, 0, to)
	var e := 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)
	for i in range(from, to):
		var xf := _base[i]
		xf.basis = xf.basis * Basis.from_scale(Vector3(lerpf(0.75, 1.0, e), maxf(e, 0.01), lerpf(0.9, 1.0, e)))
		xf.origin.y += (1.0 - e) * 0.03 * _size
		_mm.set_instance_transform(i, xf)
	_mm.visible_instance_count = to


## [eye, look] in world space to frame the first `n` bodies (fractions blend
## between one count and the next): low and close for one, higher and more
## from above the more there are.
func frame(n: float, aspect := 16.0 / 9.0, fov_deg := 48.0) -> Array:
	var lo := clampi(floori(n), 1, count)
	var hi := clampi(ceili(n), 1, count)
	var k := clampf(n - floorf(n), 0.0, 1.0)
	var a := _bounds[lo - 1]
	var b := _bounds[hi - 1]
	return _frame_rect(a.get_center().lerp(b.get_center(), k), a.size.lerp(b.size, k), aspect, fov_deg)


## [eye, look] for the last shot: the whole memorial, wall and trees and all.
## Lower and closer than the overhead pull-back, so it reads as a place.
func frame_all(aspect := 16.0 / 9.0, fov_deg := 48.0) -> Array:
	return _frame_rect(_memorial.get_center(), _memorial.size * 0.82, aspect, fov_deg, 42.0, -14.0)


## [eye, look] for the very end: high over the park and the wrecked city round it.
func frame_city(aspect := 16.0 / 9.0, fov_deg := 48.0) -> Array:
	# the whole town (park units): the park in the north, the districts south of it
	return _frame_rect(Vector2(13.0, 1.0), Vector2(36.0, 22.0), aspect, fov_deg, 52.0, -10.0)


func _frame_rect(centre: Vector2, size: Vector2, aspect: float, fov_deg: float,
		pitch_deg := -1.0, yaw_deg := 0.0) -> Array:
	var half := maxf(size.x / aspect, size.y * 1.35) * 0.5 + 0.05 * _size
	var dist := maxf(0.42 * _size, half / tan(deg_to_rad(fov_deg) * 0.5) * 1.12)
	var t := clampf(log(dist / (0.42 * _size)) / log(60.0), 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(28.0, 64.0, t))
	var yaw := deg_to_rad(lerpf(-24.0, -8.0, t))   # from the south, a little east
	if pitch_deg > 0.0:
		pitch = deg_to_rad(pitch_deg)
		yaw = deg_to_rad(yaw_deg)
	var look := Vector3(centre.x, LAWN_Y + 0.01, centre.y)
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return [_rig.to_global(look + dir * dist), _rig.to_global(look)]


# ================================================================ the field

## Clear Central Park for the memorial: everything in it (trees, paths, pond,
## fountain, bandstand, benches, tents, people, debris) is hidden, except the
## sidewalks round its edge. Anything else in the city lying inside the park
## goes too. The rest of the city, wrecked as it is, stays. The scene reloads
## after the ending, so nothing needs putting back.
func _clear_park(city: Node3D) -> void:
	var keep: Array[Node] = []
	for n in ["Ground/LawnSidewalk", "Ground/LobeSidewalk"]:
		var k := _park.get_node_or_null(n)
		if k:
			keep.append(k)
	var inv := _rig.global_transform.affine_inverse()
	for g in city.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if is_ancestor_of(gi) or not gi.visible:
			continue
		var kept := false
		for k in keep:
			if k == gi or k.is_ancestor_of(gi):
				kept = true
				break
		if kept:
			continue
		if _park.is_ancestor_of(gi):
			gi.visible = false
			continue
		# not the park's own: hide it only if it's a small thing standing in the park
		var bb: AABB = inv * gi.global_transform * gi.get_aabb()
		if bb.size.x > 8.0 or bb.size.z > 8.0:
			continue
		var c := Vector2(bb.get_center().x, bb.get_center().z)
		for r in PARK_EDGE:
			if r.has_point(c):
				gi.visible = false
				break


## Plain green grass over the park's lawns.
func _add_field() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = GRASS
	m.roughness = 1.0
	m.metallic_specular = 0.0
	for r in LAWNS:
		var plane := PlaneMesh.new()
		plane.size = r.size
		plane.material = m
		var mi := MeshInstance3D.new()
		mi.name = "GreenField"
		mi.mesh = plane
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.get_center().x, LAWN_Y, r.get_center().y)
		_rig.add_child(mi)


# ================================================================ the memorial

## Turn the grass round the bodies (`full`, their bounds) into a memorial:
##   - the bodies lie on a mown plot inside a low stone kerb
##   - a pale stone walkway runs all round, with candles and flowers along
##     its inner edge and standing wreaths at the corners
##   - a black granite wall with the names' inscription and a white obelisk
##     stand at the head (north) end, behind the bodies
##   - benches face the bodies from the outside of the walkway, lamps between
##   - a formal avenue of cypresses round it all, then a wood of round trees
##     and bushes out past the edge of the picture
## Everything repeated is a MultiMesh, so it stays cheap.
func _decorate(full: Rect2, total: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var plot := full.grow(0.22 + 0.1 * _size)     # the mown plot inside the kerb
	var kerb_w := 0.05
	var walk_w := 0.55
	var walk := plot.grow(kerb_w + walk_w)       # outer edge of the walkway

	# --- the plot, the kerb and the walkway
	_slab(plot, 0.002, MOWN, "Plot")
	for r in _frame_strips(plot.grow(kerb_w), kerb_w):
		_slab(r, 0.035, KERB, "Kerb")
	for r in _frame_strips(walk, walk_w):
		_slab(r, 0.008, PAVING, "Walkway")
	# a thin dark edge on the outside of the walkway
	for r in _frame_strips(walk.grow(0.03), 0.03):
		_slab(r, 0.012, KERB_DARK, "WalkEdge")

	# --- candles and flowers along the inner edge of the walkway
	var candles: Array[Transform3D] = []
	var flames: Array[Transform3D] = []
	var white_f: Array[Transform3D] = []
	var red_f: Array[Transform3D] = []
	var leaves: Array[Transform3D] = []
	var ring := plot.grow(kerb_w + 0.07)
	var gap := 0.16
	var pts := _around(ring, gap)
	for i in pts.size():
		var q: Vector2 = pts[i]
		if i % 3 == 0:
			# a small bunch of flowers: leaves and a few blooms
			leaves.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, 0.6, 1)),
				Vector3(q.x, LAWN_Y + 0.008, q.y)))
			for k in 4:
				var o := q + Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
				var xf := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)),
					Vector3(o.x, LAWN_Y + 0.04 + rng.randf() * 0.015, o.y))
				if rng.randf() < 0.65:
					white_f.append(xf)
				else:
					red_f.append(xf)
		else:
			var h := rng.randf_range(0.8, 1.25)
			candles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, h, 1)), Vector3(q.x, LAWN_Y + 0.008, q.y)))
			flames.append(Transform3D(Basis.IDENTITY, Vector3(q.x, LAWN_Y + 0.008 + 0.055 * h + 0.014, q.y)))
	_scatter_mesh(_candle_mesh(), null, Transform3D.IDENTITY, candles, "Candles")
	_scatter_mesh(_flame_mesh(), null, Transform3D.IDENTITY, flames, "Flames")
	_scatter_mesh(_ball(0.045, LEAF), null, Transform3D.IDENTITY, leaves, "FlowerLeaves")
	_scatter_mesh(_ball(0.02, Color(0.96, 0.95, 0.9)), null, Transform3D.IDENTITY, white_f, "WhiteFlowers")
	_scatter_mesh(_ball(0.02, Color(0.78, 0.08, 0.1)), null, Transform3D.IDENTITY, red_f, "RedFlowers")
	# a few warm lights so the candles glow (not one per candle: too many)
	var lights := _around(ring, maxf(1.6, 2.0 * (ring.size.x + ring.size.y) / 24.0))
	for q in lights:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.light_energy = 0.6
		l.omni_range = 0.6
		l.shadow_enabled = false
		l.position = Vector3(q.x, LAWN_Y + 0.12, q.y)
		_rig.add_child(l)

	# --- standing wreaths at the four corners of the walkway, facing in
	var wreaths: Array[Transform3D] = []
	var c_in := plot.grow(kerb_w + walk_w * 0.55)
	for c in [c_in.position, Vector2(c_in.end.x, c_in.position.y), Vector2(c_in.position.x, c_in.end.y), c_in.end]:
		var to_mid: Vector2 = full.get_center() - c
		var yaw := atan2(to_mid.x, to_mid.y)
		wreaths.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, LAWN_Y, c.y)))
	_wreaths(wreaths)

	# --- the wall and the obelisk at the head end (north, behind the bodies)
	var wall_len := clampf(full.size.x * 0.7, 2.2, 14.0)
	var wall_z := walk.position.y - 0.35
	var mid_x := full.get_center().x
	_block(Vector3(mid_x, LAWN_Y, wall_z - 0.02), Vector3(wall_len + 0.3, 0.05, 0.36), PAVING, "WallStep")
	_block(Vector3(mid_x, LAWN_Y + 0.05, wall_z), Vector3(wall_len, 0.36, 0.09), GRANITE, "MemorialWall", 0.25)
	_block(Vector3(mid_x, LAWN_Y + 0.41, wall_z), Vector3(wall_len + 0.04, 0.025, 0.11), KERB, "WallCap")
	var words := Label3D.new()
	words.name = "Inscription"
	words.text = "IN MEMORY OF THE %s\nWHO DIED AT 14:32" % _thousands(total)
	words.font_size = 64
	words.pixel_size = clampf(wall_len / 2.2, 1.0, 3.0) * 0.0018
	words.modulate = Color(0.93, 0.82, 0.55)
	words.outline_size = 0
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.shaded = false
	words.double_sided = false
	words.position = Vector3(mid_x, LAWN_Y + 0.24, wall_z + 0.047)
	_rig.add_child(words)
	# the obelisk, behind the wall's middle, on a stepped base
	var ob_z := wall_z - 0.55
	var ob_h := clampf(full.size.x * 0.12, 1.1, 3.0)
	_block(Vector3(mid_x, LAWN_Y, ob_z), Vector3(0.5, 0.06, 0.5), KERB, "ObeliskStep1")
	_block(Vector3(mid_x, LAWN_Y + 0.06, ob_z), Vector3(0.36, 0.08, 0.36), PAVING, "ObeliskStep2")
	var ob := CylinderMesh.new()
	ob.radial_segments = 4
	ob.rings = 1
	ob.bottom_radius = 0.14
	ob.top_radius = 0.07
	ob.height = ob_h
	ob.material = _mat(Color(0.92, 0.91, 0.87), 0.6)
	var obi := MeshInstance3D.new()
	obi.name = "Obelisk"
	obi.mesh = ob
	obi.rotation.y = PI * 0.25
	obi.position = Vector3(mid_x, LAWN_Y + 0.14 + ob_h * 0.5, ob_z)
	_rig.add_child(obi)
	var tip := CylinderMesh.new()
	tip.radial_segments = 4
	tip.rings = 1
	tip.bottom_radius = 0.07
	tip.top_radius = 0.0
	tip.height = 0.12
	tip.material = ob.material
	var tipi := MeshInstance3D.new()
	tipi.mesh = tip
	tipi.rotation.y = PI * 0.25
	tipi.position = Vector3(mid_x, LAWN_Y + 0.14 + ob_h + 0.06, ob_z)
	_rig.add_child(tipi)
	# the paved apron joining the walkway to the wall and the obelisk
	_slab(Rect2(mid_x - wall_len * 0.5 - 0.15, ob_z - 0.4, wall_len + 0.3, walk.position.y - (ob_z - 0.4)), 0.007, PAVING, "Apron")

	# --- benches facing in, lamps between them, outside the walkway
	var benches: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var line := walk.grow(0.17)
	var sides := [
		[Vector2(line.position.x, line.end.y), line.end, Vector2(0, -1)],                   # south
		[line.position, Vector2(line.position.x, line.end.y), Vector2(1, 0)],               # west
		[Vector2(line.end.x, line.position.y), line.end, Vector2(-1, 0)]]                   # east
	for side in sides:
		var a0: Vector2 = side[0]
		var a1: Vector2 = side[1]
		var face: Vector2 = side[2]
		var yaw := atan2(face.x, face.y)
		var n := maxi(2, roundi(a0.distance_to(a1) / 0.8))
		for k in range(1, n):
			var q := a0.lerp(a1, float(k) / n)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, LAWN_Y, q.y))
			if k % 2 == 0:
				lamps.append(xf)
			else:
				benches.append(xf)
	# lamps along the north side too, either side of the wall
	for k in [0.08, 0.92]:
		var q := Vector2(lerpf(line.position.x, line.end.x, k), line.position.y)
		lamps.append(Transform3D(Basis.IDENTITY, Vector3(q.x, LAWN_Y, q.y)))
	_scatter(BENCH, benches, "Benches")
	_scatter(LAMP, lamps, "Lamps")

	# --- the avenue: cypresses evenly round it all (kept back on the camera side)
	var avenue := line.grow(0.35)
	avenue.end.y += 0.4
	avenue.position.y -= 0.9   # room for the wall and obelisk
	var cypress: Array[Transform3D] = []
	for q in _around(avenue, 0.62):
		cypress.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.8, 1.25, 0.8)),
			Vector3(q.x, LAWN_Y, q.y)))
	_scatter(TREE_CONE, cypress, "Cypresses")
	# a low hedge just inside the avenue, broken where the walkway meets the wall
	var hedge := avenue.grow(-0.28)
	for r in _frame_strips(hedge, 0.12):
		if r.size.x > r.size.y and absf(r.get_center().y - hedge.position.y) < 0.2:
			# north side: two pieces, leaving the middle open to the wall
			var open := wall_len * 0.5 + 0.3
			var left := Rect2(r.position, Vector2(mid_x - open - r.position.x, r.size.y))
			var right := Rect2(Vector2(mid_x + open, r.position.y), Vector2(r.end.x - mid_x - open, r.size.y))
			for piece in [left, right]:
				if piece.size.x > 0.1:
					_block(Vector3(piece.get_center().x, LAWN_Y, piece.get_center().y), Vector3(piece.size.x, 0.13, piece.size.y), HEDGE, "Hedge")
		else:
			_block(Vector3(r.get_center().x, LAWN_Y, r.get_center().y), Vector3(r.size.x, 0.13, r.size.y), HEDGE, "Hedge")

	# --- the wood beyond: round trees and bushes on all the open grass
	var keep_out := avenue.grow(0.4)
	var cell := 0.6
	var round_trees: Array[Transform3D] = []
	var cone_trees: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var outer: Rect2 = LAWNS[0].merge(LAWNS[1])
	var x := outer.position.x
	while x < outer.end.x:
		var z := outer.position.y
		while z < outer.end.y:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42)) * cell
			z += cell
			# only on the park's own grass, clear of its edge and of the memorial
			if keep_out.has_point(p) or not _on_lawn(p, 0.3):
				continue
			var roll := rng.randf()
			# sparse, so the plain green lawn still shows between them
			if roll < 0.2:
				var sc := rng.randf_range(0.9, 1.4)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc)), Vector3(p.x, LAWN_Y, p.y))
				if rng.randf() < 0.75:
					round_trees.append(xf)
				else:
					cone_trees.append(xf)
			elif roll < 0.3:
				for k in rng.randi_range(1, 3):
					var o := p + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
					var sc := rng.randf_range(0.8, 1.4)
					bushes.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
						.scaled(Vector3(sc, sc * rng.randf_range(0.7, 0.95), sc)), Vector3(o.x, LAWN_Y, o.y)))
		x += cell
	_scatter(TREE_ROUND, round_trees, "TreesRound")
	_scatter(TREE_CONE, cone_trees, "TreesCone")
	_scatter_mesh(_ball(0.11, BUSH, 0.2), null, Transform3D.IDENTITY, bushes, "Bushes")

	# what the last, widest shot should take in
	_memorial = avenue.grow(0.3)
	_memorial.position.y = minf(_memorial.position.y, ob_z - 0.5)


func _on_lawn(p: Vector2, margin: float) -> bool:
	for r in LAWNS:
		if r.grow(-margin).has_point(p):
			return true
	return false


## Rect `r` as four strips `w` wide just inside its edge.
func _frame_strips(r: Rect2, w: float) -> Array[Rect2]:
	return [Rect2(r.position.x, r.position.y, r.size.x, w),
		Rect2(r.position.x, r.end.y - w, r.size.x, w),
		Rect2(r.position.x, r.position.y + w, w, r.size.y - 2.0 * w),
		Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2.0 * w)]


## Points every `gap` (about) round the edge of `r`, corners included.
func _around(r: Rect2, gap: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var n := maxi(1, roundi(a.distance_to(b) / gap))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out


## A flat slab over rect `r` (x/z), `h` thick, sitting on the lawn.
func _slab(r: Rect2, h: float, color: Color, label: String) -> void:
	_block(Vector3(r.get_center().x, LAWN_Y, r.get_center().y), Vector3(r.size.x, h, r.size.y), color, label)


## A box `size` standing on `base` (its bottom centre).
func _block(base: Vector3, size: Vector3, color: Color, label: String, rough := 0.9) -> void:
	if size.x <= 0.0 or size.z <= 0.0:
		return
	var box := BoxMesh.new()
	box.size = size
	box.material = _mat(color, rough)
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = box
	mi.position = base + Vector3(0, size.y * 0.5, 0)
	_rig.add_child(mi)


func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


## Wreaths on little stands: a ring of leaves dotted with white and red flowers.
func _wreaths(xforms: Array[Transform3D]) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.07
	torus.outer_radius = 0.11
	torus.rings = 16
	torus.ring_segments = 6
	torus.material = _mat(LEAF)
	var upright := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.2, 0))
	_scatter_mesh(torus, null, upright, xforms, "Wreaths")
	var leg := CylinderMesh.new()
	leg.top_radius = 0.006
	leg.bottom_radius = 0.006
	leg.height = 0.2
	leg.radial_segments = 4
	leg.material = _mat(Color(0.3, 0.2, 0.12))
	for sx in [-0.06, 0.06]:
		_scatter_mesh(leg, null, Transform3D(Basis.IDENTITY, Vector3(sx, 0.1, -0.012)), xforms, "WreathStand")
	var blooms_w: Array[Transform3D] = []
	var blooms_r: Array[Transform3D] = []
	for xf in xforms:
		for k in 14:
			var a := TAU * k / 14.0
			var local := Vector3(cos(a) * 0.09, 0.2 + sin(a) * 0.09, 0.022)
			var b := xf * Transform3D(Basis.IDENTITY, local)
			if k % 3 == 0:
				blooms_r.append(b)
			else:
				blooms_w.append(b)
	_scatter_mesh(_ball(0.018, Color(0.96, 0.95, 0.9)), null, Transform3D.IDENTITY, blooms_w, "WreathWhite")
	_scatter_mesh(_ball(0.018, Color(0.78, 0.08, 0.1)), null, Transform3D.IDENTITY, blooms_r, "WreathRed")


func _candle_mesh() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.016
	c.bottom_radius = 0.016
	c.height = 0.055
	c.radial_segments = 6
	c.rings = 1
	c.material = _mat(Color(0.95, 0.92, 0.82), 0.7)
	# the mesh's centre is its middle; move it so it stands on its base
	var st := SurfaceTool.new()
	st.append_from(c, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.0275, 0)))
	var m := st.commit()
	m.surface_set_material(0, c.material)
	return m


func _flame_mesh() -> Mesh:
	var f := SphereMesh.new()
	f.radius = 0.01
	f.height = 0.03
	f.radial_segments = 5
	f.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.62, 0.2)
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.material = m
	return f


func _ball(radius: float, color: Color, height := -1.0) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0 if height < 0.0 else height
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _mat(color, 1.0)
	return sphere


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


## One MultiMesh per mesh in `scene`, an instance of it at every `xforms`.
func _scatter(scene: PackedScene, xforms: Array[Transform3D], label: String) -> void:
	if xforms.is_empty() or scene == null:
		return
	var root := scene.instantiate()
	var parts: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		parts.append(root)
	for part in parts:
		var mi := part as MeshInstance3D
		if mi.mesh == null:
			continue
		# where the part sits inside the model
		var local := Transform3D.IDENTITY
		if mi != root:
			local = mi.transform
			var up := mi.get_parent()
			while up != null and up != root:
				if up is Node3D:
					local = (up as Node3D).transform * local
				up = up.get_parent()
		_scatter_mesh(mi.mesh, mi.material_override, local, xforms, label)
	root.free()


func _scatter_mesh(mesh: Mesh, mat: Material, local: Transform3D, xforms: Array[Transform3D], label: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i] * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rig.add_child(mmi)


# ================================================================ layout

## Every spot on a grid through START, nearest first (in squares).
func _lay_out() -> void:
	_spots.clear()
	var found: Array[Vector4] = []   # x, y, z, sort key
	var i0 := floori((AREA.position.x - START.x) / _cell.x)
	var i1 := ceili((AREA.end.x - START.x) / _cell.x)
	var j0 := floori((AREA.position.y - START.y) / _cell.y)
	var j1 := ceili((AREA.end.y - START.y) / _cell.y)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := START + Vector2(i * _cell.x, j * _cell.y)
			var d := p - START
			# square rings in the world (a little wider than deep, for the
			# screen), then row by row inside a ring
			found.append(Vector4(p.x, LAWN_Y, p.y, maxf(absf(d.x), absf(d.y) * 1.25)))
	found.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		if absf(a.w - b.w) > 0.00001:
			return a.w < b.w
		if absf(a.z - b.z) > 0.00001:
			return a.z < b.z
		return a.x < b.x)
	for f in found:
		_spots.append(Vector3(f.x, f.y, f.z))


# ================================================================ the blanket

## A black blanket over someone lying on their back, head to -x: low-poly and
## flat-shaded like everything else in town. The shape under it shows the head,
## the shoulders and chest, the legs, and the feet pushing it up at the end.
func _blanket_mesh() -> ArrayMesh:
	# The body under the cloth, head (-x) to toes (+x). Each key is
	# [u, half width of the body there, height of the cloth there]; u runs a
	# little past 0 and 1 where the blanket slopes down to the grass.
	var body: Array[Vector3] = [
		Vector3(-0.07, 0.008, 0.0), Vector3(-0.025, 0.017, 0.013),
		Vector3(0.03, 0.022, 0.024), Vector3(0.09, 0.021, 0.023),    # head
		Vector3(0.14, 0.017, 0.014),                                 # neck
		Vector3(0.21, 0.035, 0.02), Vector3(0.33, 0.034, 0.022),     # shoulders, chest
		Vector3(0.46, 0.029, 0.017), Vector3(0.57, 0.032, 0.018),    # waist, hips
		Vector3(0.7, 0.027, 0.014), Vector3(0.8, 0.025, 0.016),      # thighs, knees
		Vector3(0.9, 0.021, 0.012),                                  # shins
		Vector3(0.97, 0.023, 0.028), Vector3(1.015, 0.021, 0.022),   # toes push it up
		Vector3(1.07, 0.012, 0.0)]
	var u0 := body[0].x
	var u1 := body[body.size() - 1].x
	var nx := 30
	var nz := 11
	var hang := 0.017    # how far the cloth falls past the body's sides
	var grid: Array[PackedVector3Array] = []
	for ix in nx:
		var u := lerpf(u0, u1, float(ix) / (nx - 1))
		var w := body[0].y
		var h := 0.0
		for k in body.size() - 1:
			var a := body[k]
			var b := body[k + 1]
			if u >= a.x and u <= b.x:
				var f := smoothstep(0.0, 1.0, (u - a.x) / (b.x - a.x))
				w = lerpf(a.y, b.y, f)
				h = lerpf(a.z, b.z, f)
		# the cloth's edge follows the body, so the blanket isn't a rectangle
		var edge := w + hang * clampf(h / 0.012, 0.35, 1.0)
		var row := PackedVector3Array()
		for iz in nz:
			var v := lerpf(-1.0, 1.0, float(iz) / (nz - 1))
			var f := clampf((absf(v) * edge - w * 0.45) / maxf(edge - w * 0.45, 0.001), 0.0, 1.0)
			var y := 0.0015 + h * (1.0 - f * f * (3.0 - 2.0 * f))
			# a few soft folds, like cloth
			if absf(v) < 0.99:
				y += 0.0009 * sin(ix * 1.3 + absf(v) * 4.0) * clampf(h / 0.012, 0.0, 1.0)
			row.append(Vector3((u - 0.5) * LENGTH * 0.87, y, v * edge * 0.9))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shaded
	for ix in nx - 1:
		for iz in nz - 1:
			var a := grid[ix][iz]
			var b := grid[ix + 1][iz]
			var c := grid[ix + 1][iz + 1]
			var d := grid[ix][iz + 1]
			for p in [a, c, b, a, d, c]:
				st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = BLANKET
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh
