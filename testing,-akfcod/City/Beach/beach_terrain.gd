@tool
class_name BeachTerrain
extends Node3D
## Builds the low-poly beach on the south bank: a grassy strip along the river,
## dry sand, then a gentle slope down under the sea. Rebuilt whenever a setting
## changes, so the coastline can be shaped right in the editor.
##
## All distances are world units (one road tile = 26.93).

## Land footprint in X (matches the river / city slab).
@export var x_min := -793.0:
	set(v): x_min = v; _queue()
@export var x_max := 823.0:
	set(v): x_max = v; _queue()
## Northern edge, flush with the south riverbank.
@export var z_north := 389.0:
	set(v): z_north = v; _queue()
## Average Z of the waterline.
@export var shore_z := 650.0:
	set(v): shore_z = v; _queue()
## How much the coastline meanders in and out.
@export var shore_wiggle := 34.0:
	set(v): shore_wiggle = v; _queue()
## Rounding of the two seaward corners of the spit.
@export var corner_radius := 170.0:
	set(v): corner_radius = v; _queue()
## Width of the sloping part of the beach (dry flat sand -> waterline).
@export var slope_width := 105.0:
	set(v): slope_width = v; _queue()
## Height of the flat land (top of the city ground slab).
@export var land_y := -1.94:
	set(v): land_y = v; _queue()
## Sea level (same as the river surface).
@export var water_y := -12.6:
	set(v): water_y = v; _queue()
## How far the sea floor reaches before it ends (it fades into deep water).
@export var seabed_reach := 260.0:
	set(v): seabed_reach = v; _queue()
@export var cell_size := 13.5:
	set(v): cell_size = max(v, 2.0); _queue()
@export var material: Material:
	set(v): material = v; _queue()
@export var with_collision := true:
	set(v): with_collision = v; _queue()

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _pending := false

func _ready() -> void:
	_build()

func _queue() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_build.call_deferred()

## Waterline Z for a given X (gentle bays, shared with the prop layout).
func shore_at(x: float) -> float:
	return shore_z + shore_wiggle * sin(x / 260.0 + 0.6) + shore_wiggle * 0.45 * sin(x / 97.0 + 2.1)

## Signed distance to the coast in the XZ plane: > 0 on land, < 0 in the sea.
func coast_distance(x: float, z: float) -> float:
	var r := corner_radius
	var s := shore_at(x)
	var d_south := s - z
	var d_west := x - x_min
	var d_east := x_max - x
	var d := minf(d_south, minf(d_west, d_east))
	# Round the two seaward corners.
	if x < x_min + r or x > x_max - r:
		var cx := clampf(x, x_min + r, x_max - r)
		var cz := shore_at(cx) - r
		if z > cz:
			d = r - Vector2(x - cx, z - cz).length()
	return d

func height_at(x: float, z: float) -> float:
	var d := coast_distance(x, z)
	if d >= slope_width:
		return land_y
	if d >= 0.0:
		# Soft S-curve from the dry sand down to the waterline.
		var t := d / slope_width
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(water_y + 0.15, land_y, pow(t, 0.8))
	# Under water: shelf, then a steeper drop.
	var u := -d
	return water_y + 0.15 - u * 0.06 - maxf(u - 90.0, 0.0) * 0.12

func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)

func _build() -> void:
	_pending = false
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	var x0 := x_min - seabed_reach
	var x1 := x_max + seabed_reach
	var z1 := shore_z + shore_wiggle * 1.5 + seabed_reach
	var nx := int(ceil((x1 - x0) / cell_size))
	var nz := int(ceil((z1 - z_north) / cell_size))
	var dx := (x1 - x0) / nx
	var dz := (z1 - z_north) / nz

	# Height grid, skipping cells that are entirely deep sea.
	var pts: Array[Vector3] = []
	pts.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var x := x0 + i * dx
			var z := z_north + j * dz
			var y := height_at(x, z)
			# Faceted look on the slopes only; flat sand stays flat for props.
			if y < land_y - 0.05 and i > 0 and i < nx and j > 0:
				var jx := (_hash(x, z) - 0.5) * dx * 0.35
				var jz := (_hash(z, x) - 0.5) * dz * 0.35
				x += jx; z += jz
				y = height_at(x, z) + (_hash(x + 3.1, z) - 0.5) * 0.5
			pts[j * (nx + 1) + i] = Vector3(x, y, z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF) # flat shading
	var deep := water_y - 40.0
	for j in nz:
		for i in nx:
			var a := pts[j * (nx + 1) + i]
			var b := pts[j * (nx + 1) + i + 1]
			var c := pts[(j + 1) * (nx + 1) + i]
			var e := pts[(j + 1) * (nx + 1) + i + 1]
			if maxf(maxf(a.y, b.y), maxf(c.y, e.y)) < deep:
				continue
			_tri(st, a, b, e)
			_tri(st, a, e, c)
	# Skirt along the north edge: a solid bank under the land (like the old
	# slab), and a cut-away "glass tank" face of sea water beyond it.
	var bottom := land_y - 13.46
	for i in nx:
		var a := pts[i]
		var b := pts[i + 1]
		var ta := maxf(a.y, water_y)
		var tb := maxf(b.y, water_y)
		var ba := minf(bottom, a.y - 1.0)
		var bb := minf(bottom, b.y - 1.0)
		var a_top := Vector3(a.x, ta, a.z)
		var b_top := Vector3(b.x, tb, b.z)
		_tri(st, a_top, Vector3(b.x, bb, b.z), b_top)
		_tri(st, a_top, Vector3(a.x, ba, a.z), Vector3(b.x, bb, b.z))
	st.generate_normals()
	var mesh := st.commit()
	if material:
		mesh.surface_set_material(0, material)
	_mesh_instance.mesh = mesh

	if _body:
		_body.queue_free()
		_body = null
	if with_collision:
		_body = StaticBody3D.new()
		_body.name = "Collision"
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		_body.add_child(cs)
		add_child(_body, false, Node.INTERNAL_MODE_FRONT)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces are clockwise when seen from the outside.
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
