extends Node3D
## The last thing the ending shows (earthquake_ending.gd, after the summary):
## everyone who died, laid out in rows on the grass of Central Park, each under
## a black blanket. The camera starts on one of them and pulls back, 4, 9, 16...
## until all of them lie there.
##
## Everything is in the park's own units (one unit = one city tile), like
## central_park_drill.gd and park_tents.gd. The rows start on the west lawn and
## grow outward in squares, around the trees, benches, lamps, the pond, the
## fountain and the bandstand (the paths are fine). If there are more dead than
## fit, the rows close up and the bodies get smaller until they all do.
## The bodies are one MultiMesh, so thousands cost almost nothing.
##
##   setup(city, total) -> false if there's no Central Park
##   settle(from, to, k)  bodies from..to (0-based, `to` excluded) are laid down,
##                        k 0..1 (the blanket settles over them)
##   frame(n) -> [eye, look]   world-space camera for the first n bodies

const PARK := "Districts/EvacuationPark/CentralPark"
## Where bodies may go: the main park, and the lawn round the fountain.
const AREAS: Array[Rect2] = [Rect2(-2.7, -13.6, 26.4, 8.95), Rect2(4.25, -4.6, 5.5, 7.55)]
## The first body, on the west lawn; the rows grow outward from here.
const START := Vector2(5.0, -8.6)
## One body's spot: along it (head west), across it.
const CELL := Vector2(0.27, 0.13)
const LAWN_Y := 0.07
const PAVING_Y := 0.085
const PLAZA := Vector2(7.0, 0.0)
const PLAZA_R := 1.62
const BASIN_R := 0.95
const BLANKET := Color(0.035, 0.035, 0.042)
## Body size in park units, before any shrinking.
const LENGTH := 0.2
const WIDTH := 0.092

## How many bodies are laid out (the total, unless the park is too small).
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
var _circles: Array[Vector3] = []     # x, z, radius
var _ellipses: Array[Vector4] = []    # x, z, radius x, radius z
var _hedges: Array[Dictionary] = []   # {"o", "ax", "half"}
var _paths: Array[Dictionary] = []


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
	_collect_obstacles()
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

	_bounds.resize(count)
	var r := Rect2()
	for i in count:
		var s := _spots[i]
		var half := Vector2(LENGTH, WIDTH) * 0.5 * _size
		var b := Rect2(Vector2(s.x, s.z) - half, half * 2.0)
		r = b if i == 0 else r.merge(b)
		_bounds[i] = r

	_base.resize(count)
	for i in count:
		var s := _spots[i]
		var grown := _size * (_rng.randf_range(0.66, 0.74) if _rng.randf() < 0.07 else _rng.randf_range(0.93, 1.05))
		var basis := Basis(Vector3.UP, _rng.randf_range(-0.05, 0.05)).scaled(Vector3.ONE * grown)
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
	var centre := a.get_center().lerp(b.get_center(), k)
	var size := a.size.lerp(b.size, k)
	var half := maxf(size.x / aspect, size.y * 1.35) * 0.5 + 0.05 * _size
	var dist := maxf(0.42 * _size, half / tan(deg_to_rad(fov_deg) * 0.5) * 1.12)
	var t := clampf(log(dist / (0.42 * _size)) / log(60.0), 0.0, 1.0)
	var pitch := deg_to_rad(lerpf(28.0, 64.0, t))
	var yaw := deg_to_rad(lerpf(-24.0, -8.0, t))   # from the south, a little east
	var look := Vector3(centre.x, LAWN_Y + 0.01, centre.y)
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return [_rig.to_global(look + dir * dist), _rig.to_global(look)]


# ================================================================ layout

## Every free spot on a grid through START, nearest first (in squares).
func _lay_out() -> void:
	_spots.clear()
	var found: Array[Vector4] = []   # x, y, z, sort key
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for area in AREAS:
		lo = lo.min(area.position)
		hi = hi.max(area.end)
	var i0 := floori((lo.x - START.x) / _cell.x)
	var i1 := ceili((hi.x - START.x) / _cell.x)
	var j0 := floori((lo.y - START.y) / _cell.y)
	var j1 := ceili((hi.y - START.y) / _cell.y)
	var reach := LENGTH * 0.42 * _size
	var r := WIDTH * 0.4 * _size
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := START + Vector2(i * _cell.x, j * _cell.y)
			if not _inside(p, reach):
				continue
			if not (_clear(p, r) and _clear(p + Vector2(reach, 0), r) and _clear(p - Vector2(reach, 0), r)):
				continue
			var y := PAVING_Y if _on_paving(p) else LAWN_Y
			var d := p - START
			# square rings in the world (a little wider than deep, for the
			# screen), then row by row inside a ring
			found.append(Vector4(p.x, y, p.y, maxf(absf(d.x), absf(d.y) * 1.25)))
	found.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		if absf(a.w - b.w) > 0.00001:
			return a.w < b.w
		if absf(a.z - b.z) > 0.00001:
			return a.z < b.z
		return a.x < b.x)
	for f in found:
		_spots.append(Vector3(f.x, f.y, f.z))


func _inside(p: Vector2, reach: float) -> bool:
	for area in AREAS:
		if area.grow_individual(-reach, -0.06, -reach, -0.06).has_point(p):
			return true
	return false


func _on_paving(p: Vector2) -> bool:
	if p.distance_to(PLAZA) < PLAZA_R:
		return true
	for b in _paths:
		if _in_box(p, b, 0.0):
			return true
	return false


# ================================================================ what's in the way

func _collect_obstacles() -> void:
	# trees: just round the trunk (the branches are overhead)
	var trees := _park.get_node_or_null("Trees")
	if trees:
		for c in trees.get_children():
			var n := c as Node3D
			if n == null:
				continue
			var p := _rig.to_local(n.global_position)
			var bb := _local_bounds(n)
			var r := 0.06 if bb.size == Vector3.ZERO else clampf(maxf(bb.size.x, bb.size.z) * 0.18, 0.045, 0.11)
			_circles.append(Vector3(p.x, p.z, r))
	# benches, lamps, planters, signs, the shelter camp: as wide as they are
	for group_name in ["Benches", "Lamps", "FountainPlaza", "ShelterCamp"]:
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
	_circles.append(Vector3(PLAZA.x, PLAZA.y, BASIN_R))
	# the pond, the bandstand and the flower beds: discs
	for group_name in ["Pond", "Bandstand", "FlowerBeds"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var cm := (mi as MeshInstance3D).mesh as CylinderMesh
			if cm == null:
				continue
			var xf := _rig.global_transform.affine_inverse() * (mi as Node3D).global_transform
			var rad := maxf(cm.top_radius, cm.bottom_radius)
			_ellipses.append(Vector4(xf.origin.x, xf.origin.z, rad * xf.basis.x.length(), rad * xf.basis.z.length()))
		# anything else in them (the bandstand's posts and roof)
		var bb := _local_bounds(g as Node3D)
		if group_name == "Bandstand" and bb.size != Vector3.ZERO:
			var mid := bb.get_center()
			_circles.append(Vector3(mid.x, mid.z, maxf(bb.size.x, bb.size.z) * 0.5))
	for group_name in ["Hedges", "Paths"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for c in g.get_children():
			var b := _box_of(c)
			if b.is_empty():
				continue
			if group_name == "Hedges":
				_hedges.append(b)
			else:
				_paths.append(b)


func _clear(p: Vector2, r: float) -> bool:
	for c in _circles:
		if Vector2(c.x, c.y).distance_to(p) < c.z + r:
			return false
	for e in _ellipses:
		var dx := (p.x - e.x) / (e.z + r)
		var dz := (p.y - e.y) / (e.w + r)
		if dx * dx + dz * dz < 1.0:
			return false
	for b in _hedges:
		if _in_box(p, b, r):
			return false
	return true


func _in_box(p: Vector2, b: Dictionary, r: float) -> bool:
	var d: Vector2 = p - b.o
	var ax: Vector2 = b.ax
	return absf(d.dot(ax)) < b.half.x + r and absf(d.dot(Vector2(-ax.y, ax.x))) < b.half.y + r


## A flat box mesh as {"o": centre, "ax": along its length, "half": (half
## length, half width)}, x/z in park units. Empty if it isn't one.
func _box_of(n: Node) -> Dictionary:
	var mi := n as MeshInstance3D
	if mi == null or not mi.mesh is BoxMesh:
		return {}
	var size := (mi.mesh as BoxMesh).size
	var xf := _rig.global_transform.affine_inverse() * mi.global_transform
	var along := Vector2(xf.basis.z.x, xf.basis.z.z)
	var side := Vector2(xf.basis.x.x, xf.basis.x.z)
	return {"o": Vector2(xf.origin.x, xf.origin.z), "ax": along.normalized(),
		"half": Vector2(size.z * 0.5 * along.length(), size.x * 0.5 * side.length())}


func _local_bounds(n: Node3D) -> AABB:
	var inv := _rig.global_transform.affine_inverse()
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
