@tool
class_name BikePath
extends Node3D
## Narrow bike lanes drawn as flat ribbons with a dashed centre line.
## Each route is a list of XZ points; edit them in the inspector to reroute.

@export var routes: Array[PackedVector2Array] = []:
	set(v): routes = v; _queue()
@export var width := 9.0:
	set(v): width = v; _queue()
## Height of the lane surface (just above the ground it runs over).
@export var surface_y := -1.86:
	set(v): surface_y = v; _queue()
@export var dash_length := 5.0:
	set(v): dash_length = v; _queue()
@export var dash_gap := 5.0:
	set(v): dash_gap = v; _queue()
@export var dash_width := 0.7:
	set(v): dash_width = v; _queue()
@export var lane_material: Material:
	set(v): lane_material = v; _queue()
@export var line_material: Material:
	set(v): line_material = v; _queue()
## Edge kerb thickness (0 = none).
@export var kerb_width := 0.9:
	set(v): kerb_width = v; _queue()
@export var kerb_material: Material:
	set(v): kerb_material = v; _queue()

var _mi: MeshInstance3D
var _pending := false

func _ready() -> void:
	_build()

func _queue() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_build.call_deferred()

func _build() -> void:
	_pending = false
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "Mesh"
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi, false, Node.INTERNAL_MODE_FRONT)
	var mesh := ArrayMesh.new()
	var lane := SurfaceTool.new()
	var line := SurfaceTool.new()
	var kerb := SurfaceTool.new()
	for st in [lane, line, kerb]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
	for r in routes:
		if r.size() < 2:
			continue
		_ribbon(lane, r, -width * 0.5, width * 0.5, surface_y)
		if kerb_width > 0.0:
			_ribbon(kerb, r, -width * 0.5 - kerb_width, -width * 0.5, surface_y + 0.02)
			_ribbon(kerb, r, width * 0.5, width * 0.5 + kerb_width, surface_y + 0.02)
		_dashes(line, r)
	for pair in [[lane, lane_material], [kerb, kerb_material], [line, line_material]]:
		var arrays: Array = (pair[0] as SurfaceTool).commit_to_arrays()
		if arrays[Mesh.ARRAY_VERTEX] == null or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if pair[1]:
			mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	_mi.mesh = mesh

## Side vector (to the right of travel) at point i, averaged at corners.
func _side(r: PackedVector2Array, i: int) -> Vector2:
	var d := Vector2.ZERO
	if i > 0: d += (r[i] - r[i - 1]).normalized()
	if i < r.size() - 1: d += (r[i + 1] - r[i]).normalized()
	d = d.normalized()
	return Vector2(-d.y, d.x)

func _ribbon(st: SurfaceTool, r: PackedVector2Array, off_a: float, off_b: float, y: float) -> void:
	for i in r.size() - 1:
		var s0 := _side(r, i)
		var s1 := _side(r, i + 1)
		var a0 := r[i] + s0 * off_a
		var b0 := r[i] + s0 * off_b
		var a1 := r[i + 1] + s1 * off_a
		var b1 := r[i + 1] + s1 * off_b
		_quad(st, Vector3(a0.x, y, a0.y), Vector3(b0.x, y, b0.y), Vector3(b1.x, y, b1.y), Vector3(a1.x, y, a1.y))

func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	# Make sure the face points up whichever way the route runs.
	var n := (p2 - p0).cross(p1 - p0)
	if n.y >= 0.0:
		for p in [p0, p1, p2, p0, p2, p3]: st.add_vertex(p)
	else:
		for p in [p0, p2, p1, p0, p3, p2]: st.add_vertex(p)

func _dashes(st: SurfaceTool, r: PackedVector2Array) -> void:
	var y := surface_y + 0.03
	var carry := 0.0 # distance into the current dash/gap cycle
	var period := dash_length + dash_gap
	for i in r.size() - 1:
		var a := r[i]
		var b := r[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var dir := (b - a) / seg
		var side := Vector2(-dir.y, dir.x) * dash_width * 0.5
		var t := -carry
		while t < seg:
			var t0 := maxf(t, 0.0)
			var t1 := minf(t + dash_length, seg)
			if t1 > t0:
				var p0 := a + dir * t0
				var p1 := a + dir * t1
				_quad(st, Vector3(p0.x - side.x, y, p0.y - side.y), Vector3(p0.x + side.x, y, p0.y + side.y),
					Vector3(p1.x + side.x, y, p1.y + side.y), Vector3(p1.x - side.x, y, p1.y - side.y))
			t += period
		carry = fposmod(carry + seg, period)
