@tool
class_name MountainRange
extends Node3D
## Low-poly mountain ranges wrapping the city on three sides so the town sits
## in a bay that opens to the sea. Faces are coloured per height/steepness from
## the city palette (grass, forest, rock, snow) and the foothills get trees.
## Everything is rebuilt when a setting changes, so it can be shaped in the editor.

## The flat valley the city sits in. West/east edges near the city...
@export var valley_west := -450.0:
	set(v): valley_west = v; _queue()
@export var valley_east := 615.0:
	set(v): valley_east = v; _queue()
@export var valley_north := -695.0:
	set(v): valley_north = v; _queue()
## ...and how far the valley opens out towards the coast.
@export var coast_west := -805.0:
	set(v): coast_west = v; _queue()
@export var coast_east := 835.0:
	set(v): coast_east = v; _queue()
## Z where the valley starts widening, and where it is fully open.
@export var widen_from := -60.0:
	set(v): widen_from = v; _queue()
@export var widen_to := 240.0:
	set(v): widen_to = v; _queue()
## Z where the side ranges start dipping into the sea (headlands).
@export var headland_z := 330.0:
	set(v): headland_z = v; _queue()
@export var headland_end_z := 980.0:
	set(v): headland_end_z = v; _queue()

@export var peak_height := 400.0:
	set(v): peak_height = v; _queue()
@export var snow_line := 340.0:
	set(v): snow_line = v; _queue()
@export var ground_y := -1.94:
	set(v): ground_y = v; _queue()
@export var water_y := -12.6:
	set(v): water_y = v; _queue()
@export var extent := Vector4(-6200.0, -6600.0, 6200.0, 1250.0): # x0, z0, x1, z1
	set(v): extent = v; _queue()
@export var cell_size := 58.0:
	set(v): cell_size = max(v, 8.0); _queue()
@export var noise_seed := 3:
	set(v): noise_seed = v; _queue()

@export_group("Trees")
@export var tree_count := 1400:
	set(v): tree_count = v; _queue()
@export var tree_scene: PackedScene:
	set(v): tree_scene = v; _queue()
@export var tree_scene_alt: PackedScene:
	set(v): tree_scene_alt = v; _queue()
@export var tree_scale := 26.93:
	set(v): tree_scale = v; _queue()

@export_group("Look")
@export var material: Material:
	set(v): material = v; _queue()
@export var grass_color := Color8(97, 203, 140)
@export var forest_color := Color8(33, 141, 109)
@export var rock_color := Color8(134, 139, 161)
@export var rock_dark_color := Color8(102, 106, 130)
@export var snow_color := Color8(250, 250, 252)
@export var shore_color := Color8(212, 165, 115)

var _mesh_instance: MeshInstance3D
var _trees: Array[MultiMeshInstance3D] = []
var _pending := false
var _ridge := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

func _ready() -> void:
	_build()

func _queue() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_build.call_deferred()

func _setup_noise() -> void:
	_ridge.seed = noise_seed
	_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	_ridge.frequency = 0.0016
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_hills.seed = noise_seed + 11
	_hills.frequency = 0.0007
	_hills.fractal_octaves = 2
	_detail.seed = noise_seed + 23
	_detail.frequency = 0.012
	_detail.fractal_octaves = 1

## How far (world units) a point is outside the valley; <= 0 means in the valley.
func valley_distance(x: float, z: float) -> float:
	var t := smoothstep(widen_from, widen_to, z)
	var w := lerpf(valley_west, coast_west, t)
	var e := lerpf(valley_east, coast_east, t)
	var dx := maxf(w - x, x - e)
	var dz := valley_north - z
	if dx > 0.0 and dz > 0.0:
		return Vector2(dx, dz).length()
	return maxf(dx, dz)

func height_at(x: float, z: float) -> float:
	var d := valley_distance(x, z)
	# Ragged coastline: the headlands reach further out to sea in places.
	var zc := z - 170.0 * _hills.get_noise_2d(x * 1.7, 50.0) - 60.0 * sin(x / 230.0)
	var sink := smoothstep(headland_z, headland_end_z, zc) if absf(x) > 900.0 else smoothstep(headland_z, headland_end_z, z)
	if d <= 0.0:
		return ground_y - sink * 45.0
	var ridge := (_ridge.get_noise_2d(x, z) + 1.0) * 0.5          # 0..1, sharp crests
	var hills := (_hills.get_noise_2d(x, z) + 1.0) * 0.5
	var foot := smoothstep(0.0, 150.0, d) * (30.0 + 30.0 * hills)
	var crest := smoothstep(70.0, 650.0, d) * peak_height * (0.35 + 0.75 * ridge * ridge) * (0.7 + 0.5 * hills)
	var outer := smoothstep(900.0, 3200.0, d) * peak_height * 0.3 * (0.6 + 0.4 * ridge)
	var h := foot + crest + outer + _detail.get_noise_2d(x, z) * 9.0 * smoothstep(0.0, 80.0, d)
	# The two side ranges run down into the sea as headlands.
	h = h * (1.0 - sink) - sink * 45.0
	return ground_y + h

func _build() -> void:
	_pending = false
	_setup_noise()
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)

	var x0 := extent.x
	var z0 := extent.y
	var x1 := extent.z
	var z1 := extent.w
	var nx := int(ceil((x1 - x0) / cell_size))
	var nz := int(ceil((z1 - z0) / cell_size))
	var dx := (x1 - x0) / nx
	var dz := (z1 - z0) / nz
	var pts := PackedVector3Array()
	pts.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := x0 + i * dx
			var z := z0 + j * dz
			# Jitter the grid (not on the valley floor) for a hand-made, faceted look.
			if valley_distance(x, z) > dx and i > 0 and i < nx and j > 0 and j < nz:
				x += (_hash(x, z) - 0.5) * dx * 0.55
				z += (_hash(z, x) - 0.5) * dz * 0.55
			pts[j * (nx + 1) + i] = Vector3(x, height_at(x, z), z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drowned := water_y - 45.0
	for j in nz:
		for i in nx:
			var a := pts[j * (nx + 1) + i]
			var b := pts[j * (nx + 1) + i + 1]
			var c := pts[(j + 1) * (nx + 1) + i]
			var e := pts[(j + 1) * (nx + 1) + i + 1]
			var top := maxf(maxf(a.y, b.y), maxf(c.y, e.y))
			var in_valley := maxf(maxf(valley_distance(a.x, a.z), valley_distance(b.x, b.z)), maxf(valley_distance(c.x, c.z), valley_distance(e.x, e.z)))
			if in_valley <= 0.0:
				continue # valley floor: the city ground / beach is already there
			if top < drowned:
				continue
			# Alternate the diagonal for a less regular triangulation.
			if (i + j) % 2 == 0:
				_tri(st, a, b, e)
				_tri(st, a, e, c)
			else:
				_tri(st, a, b, c)
				_tri(st, b, e, c)
	var mesh := st.commit()
	if material:
		mesh.surface_set_material(0, material)
	_mesh_instance.mesh = mesh
	_build_trees()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	if n.y < 0.0:
		var t := b; b = c; c = t
		n = -n
	var col := _face_color((a + b + c) / 3.0, n)
	st.set_color(col.srgb_to_linear())
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _face_color(p: Vector3, n: Vector3) -> Color:
	var steep := 1.0 - n.y
	var h := p.y - ground_y
	var jitter := (_hash(p.x, p.z) - 0.5) * 0.06
	var snow := snow_line + (_hash(p.z, p.x) - 0.5) * 60.0
	var col: Color
	if p.y < water_y + 1.5:
		col = shore_color
	elif h > snow and steep < 0.55:
		col = snow_color
	elif h > snow * 0.55 or steep > 0.5:
		col = rock_color if _hash(p.x * 0.7, p.z * 1.3) > 0.4 else rock_dark_color
	elif h > 28.0 + _detail.get_noise_2d(p.x, p.z) * 18.0:
		col = forest_color
	else:
		col = grass_color
	return col.lightened(jitter) if jitter > 0.0 else col.darkened(-jitter)

func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)

# ------------------------------------------------------------------ trees

func _mesh_from(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var inst := scene.instantiate()
	var found: Mesh = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	if found == null and inst is MeshInstance3D:
		found = inst.mesh
	inst.free()
	return found

func _build_trees() -> void:
	for t in _trees:
		t.queue_free()
	_trees.clear()
	var meshes: Array[Mesh] = []
	for s in [tree_scene, tree_scene_alt]:
		var m := _mesh_from(s)
		if m:
			meshes.append(m)
	if meshes.is_empty() or tree_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed * 7919
	var lists: Array = []
	for m in meshes:
		lists.append([])
	var tries := 0
	var placed := 0
	while placed < tree_count and tries < tree_count * 40:
		tries += 1
		# Sample near the valley so trees cluster on the foothills facing the city.
		var x := rng.randf_range(coast_west - 900.0, coast_east + 900.0)
		var z := rng.randf_range(valley_north - 900.0, headland_end_z)
		var d := valley_distance(x, z)
		if d < 12.0 or d > 700.0:
			continue
		var y := height_at(x, z)
		var h := y - ground_y
		if h < 3.0 or h > snow_line * 0.5 or y < water_y + 2.0:
			continue
		# Skip steep spots.
		var gx := height_at(x + 6.0, z) - y
		var gz := height_at(x, z + 6.0) - y
		if Vector2(gx, gz).length() > 5.5:
			continue
		# Denser forest lower down.
		if rng.randf() > 1.15 - h / (snow_line * 0.5):
			continue
		var s := tree_scale * rng.randf_range(0.9, 1.7)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		var which := 0 if meshes.size() == 1 or rng.randf() < 0.7 else 1
		lists[which].append(Transform3D(basis, Vector3(x, y - 0.5, z)))
		placed += 1
	for k in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = lists[k].size()
		for i in lists[k].size():
			mm.set_instance_transform(i, lists[k][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees%d" % k
		mmi.multimesh = mm
		add_child(mmi, false, Node.INTERNAL_MODE_FRONT)
		_trees.append(mmi)
