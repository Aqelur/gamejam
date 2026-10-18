extends Node3D
## The last thing the ending shows (earthquake_ending.gd, after the summary):
## everyone who died, laid out in rows in Central Park, each under a black
## blanket. The camera starts on one of them and pulls back, 4, 9, 16...
## until all of them lie there.
##
## The park is cleared for this: everything in the city is hidden, and the
## bodies lie on a plain green lawn. They lie vertically on screen (head away
## from the camera, feet towards it), side by side in rows. Round the bodies
## runs a gravel path with benches and lamps, and the empty grass beyond is
## filled with trees and bushes (_decorate).
## If there are more dead than fit, the rows close up and the bodies get
## smaller until they all do. The bodies are one MultiMesh, so thousands cost
## almost nothing.
##
##   setup(city, total) -> false if there's no Central Park
##   settle(from, to, k)  bodies from..to (0-based, `to` excluded) are laid down,
##                        k 0..1 (the blanket settles over them)
##   frame(n) -> [eye, look]   world-space camera for the first n bodies

const PARK := "Districts/EvacuationPark/CentralPark"
## The first body; the rows grow outward from here.
const START := Vector2(5.0, -8.6)
## Where bodies may go (park units): a big open square round START.
const AREA := Rect2(-13.0, -26.6, 36.0, 36.0)
## One body's spot: across it (x), along it (z, head to -z).
const CELL := Vector2(0.13, 0.27)
const LAWN_Y := 0.07
const BLANKET := Color(0.035, 0.035, 0.042)
const GRASS := Color(0.33, 0.55, 0.24)
## How far the plain green field reaches, park units.
const FIELD_SIZE := 600.0
const TREE_ROUND := preload("res://Models/Custom/tree_round.glb")
const TREE_CONE := preload("res://Models/Custom/tree_cone.glb")
const BENCH := preload("res://Models/Custom/bench.glb")
const LAMP := preload("res://Models/Custom/streetlight.glb")
const GRAVEL := Color(0.74, 0.69, 0.58)
const BUSH := Color(0.2, 0.42, 0.17)
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
	_clear_city(city)
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
	_decorate(_bounds[count - 1])

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


# ================================================================ the field

## Hide the whole city (trees, buildings, paths, people...) so nothing but the
## green field and the bodies is seen. Lights and the sky are left alone. The
## scene reloads after the ending, so nothing needs putting back.
func _clear_city(city: Node3D) -> void:
	for g in city.find_children("*", "GeometryInstance3D", true, false):
		if is_ancestor_of(g):
			continue
		(g as GeometryInstance3D).visible = false


## One big flat plane of plain green grass under everything.
func _add_field() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_SIZE, FIELD_SIZE)
	var m := StandardMaterial3D.new()
	m.albedo_color = GRASS
	m.roughness = 1.0
	m.metallic_specular = 0.0
	plane.material = m
	var mi := MeshInstance3D.new()
	mi.name = "GreenField"
	mi.mesh = plane
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(START.x, LAWN_Y, START.y)
	_rig.add_child(mi)


# ================================================================ the park round them

## Fill the empty grass round the bodies (`full`, their bounds): a gravel path
## close round them with benches and lamps facing in, then trees and bushes out
## to well past the edge of the picture. All MultiMeshes, so it stays cheap.
func _decorate(full: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var edge := full.grow(0.35 + 0.15 * _size)

	# --- the path: four gravel strips just round the bodies
	var path := edge.grow(0.15)
	var w := 0.22
	var strips: Array[Rect2] = [
		Rect2(path.position.x - w * 0.5, path.position.y - w * 0.5, path.size.x + w, w),
		Rect2(path.position.x - w * 0.5, path.end.y - w * 0.5, path.size.x + w, w),
		Rect2(path.position.x - w * 0.5, path.position.y + w * 0.5, w, path.size.y - w),
		Rect2(path.end.x - w * 0.5, path.position.y + w * 0.5, w, path.size.y - w)]
	var gravel := StandardMaterial3D.new()
	gravel.albedo_color = GRAVEL
	gravel.roughness = 1.0
	for st in strips:
		var box := BoxMesh.new()
		box.size = Vector3(st.size.x, 0.006, st.size.y)
		box.material = gravel
		var mi := MeshInstance3D.new()
		mi.name = "Path"
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var c := st.get_center()
		mi.position = Vector3(c.x, LAWN_Y + 0.003, c.y)
		_rig.add_child(mi)

	# --- benches and lamps along the outside of the path, facing the bodies
	var benches: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var line := path.grow(0.28)
	var perimeter := 2.0 * (line.size.x + line.size.y)
	var step := maxf(1.6, perimeter / 90.0)
	# [start, end, the way the bench faces]
	var sides := [
		[line.position, Vector2(line.end.x, line.position.y), Vector2(0, 1)],               # north
		[Vector2(line.position.x, line.end.y), line.end, Vector2(0, -1)],                   # south
		[line.position, Vector2(line.position.x, line.end.y), Vector2(1, 0)],               # west
		[Vector2(line.end.x, line.position.y), line.end, Vector2(-1, 0)]]                   # east
	for side in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var face: Vector2 = side[2]
		var yaw := atan2(face.x, face.y)
		var n := maxi(1, floori(a.distance_to(b) / step))
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, LAWN_Y, q.y))
			if k == 0 or k == n:
				continue   # the corners get lamps below
			if k % 2 == 0:
				lamps.append(xf)
			else:
				benches.append(xf)
	for corner in [line.position, Vector2(line.end.x, line.position.y), Vector2(line.position.x, line.end.y), line.end]:
		lamps.append(Transform3D(Basis.IDENTITY, Vector3(corner.x, LAWN_Y, corner.y)))

	# --- trees and bushes on all the empty grass beyond
	var keep_out := line.grow(0.45)
	var reach := maxf(7.0, maxf(full.size.x, full.size.y) * 0.9)
	var outer := line.grow(reach)
	var cell := maxf(0.55, reach / 22.0)
	var round_trees: Array[Transform3D] = []
	var cone_trees: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var x := outer.position.x
	while x < outer.end.x:
		var z := outer.position.y
		while z < outer.end.y:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)) * cell
			z += cell
			if keep_out.has_point(p):
				continue
			var roll := rng.randf()
			if roll < 0.5:
				var sc := rng.randf_range(0.85, 1.4)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
					.scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.1), sc)), Vector3(p.x, LAWN_Y, p.y))
				if rng.randf() < 0.6:
					round_trees.append(xf)
				else:
					cone_trees.append(xf)
			elif roll < 0.72:
				# a little clump of one to three bushes
				for b in rng.randi_range(1, 3):
					var o := p + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
					var sc := rng.randf_range(0.7, 1.25)
					bushes.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
						.scaled(Vector3(sc, sc * rng.randf_range(0.7, 0.95), sc)), Vector3(o.x, LAWN_Y, o.y)))
		x += cell

	_scatter(TREE_ROUND, round_trees, "TreesRound")
	_scatter(TREE_CONE, cone_trees, "TreesCone")
	_scatter(BENCH, benches, "Benches")
	_scatter(LAMP, lamps, "Lamps")
	_scatter_mesh(_bush_mesh(), null, Transform3D.IDENTITY, bushes, "Bushes")


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


## A low, round, low-poly bush.
func _bush_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.2
	sphere.radial_segments = 8
	sphere.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = BUSH
	m.roughness = 1.0
	sphere.material = m
	return sphere


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
