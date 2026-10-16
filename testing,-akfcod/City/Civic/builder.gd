extends SceneTree
## Generates the civic building scenes (hospital, police station, fire station)
## and the central park. Run headless:
##   godot --headless --path . -s res://City/Civic/builder.gd
## Each building faces local +Z, footprint fits a 6x6 city block (lot ~ +-2.7).

var _mats := {}
var _root: Node3D

const TREE_ROUND := "res://Models/Custom/tree_round.glb"
const TREE_CONE := "res://Models/Custom/tree_cone.glb"
const BENCH := "res://Models/Custom/bench.glb"
const STREETLIGHT := "res://Models/Custom/streetlight.glb"
const PLANTER := "res://Models/Custom/planter.glb"
const GRASS := "res://Models/Custom/grass.glb"
const SIDEWALK := "res://Models/Custom/sidewalk.glb"
const SIGN_EVAC := "res://Models/Custom/sign_evacuation.glb"
const CONE := "res://Models/Custom/traffic_cone.glb"
const BARRIER := "res://Models/Custom/barrier_striped.glb"

func _init() -> void:
	_save(build_hospital(), "res://City/Civic/hospital.tscn")
	_save(build_police(), "res://City/Civic/police_station.tscn")
	_save(build_fire(), "res://City/Civic/fire_station.tscn")
	_save(build_park(), "res://City/Civic/central_park.tscn")
	quit()

# ---------------------------------------------------------------- helpers

func _save(root: Node3D, path: String) -> void:
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s" % path)
	ResourceSaver.save(ps, path)
	print("saved ", path)
	root.free()
	_mats.clear()

func _own(n: Node) -> void:
	n.owner = _root
	for c in n.get_children():
		_own(c)

func mat(color: Color, emit := 0.0, rough := 0.85, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [color.to_html(), emit, rough, metal, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

func group(parent: Node, name: String, pos := Vector3.ZERO, rot_y := 0.0) -> Node3D:
	var g := Node3D.new()
	g.name = name
	g.position = pos
	g.rotation_degrees.y = rot_y
	parent.add_child(g)
	g.owner = _root
	return g

## Box whose BOTTOM sits at pos.y (easier stacking).
func box(parent: Node, name: String, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	mi.rotation_degrees = rot
	parent.add_child(mi)
	mi.owner = _root
	return mi

func cyl(parent: Node, name: String, r: float, h: float, pos: Vector3, m: Material, segs := 24, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = r if r_top < 0.0 else r_top
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos + Vector3(0, h * 0.5, 0)
	parent.add_child(mi)
	mi.owner = _root
	return mi

func label(parent: Node, name: String, text: String, pos: Vector3, px: float, color: Color, outline := Color.BLACK, rot := Vector3.ZERO, outline_size := 8) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.position = pos
	l.rotation_degrees = rot
	l.pixel_size = px
	l.font_size = 64
	l.outline_size = outline_size
	l.modulate = color
	l.outline_modulate = outline
	l.shaded = false
	l.double_sided = false
	l.uppercase = true
	parent.add_child(l)
	l.owner = _root
	return l

func inst(parent: Node, path: String, name: String, pos: Vector3, rot_y := 0.0, s := 1.0) -> Node3D:
	var n: Node3D = load(path).instantiate()
	n.name = name
	n.position = pos
	n.rotation_degrees.y = rot_y
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	n.owner = _root
	return n

func collider(parent: Node, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	parent.add_child(sb)
	sb.owner = _root
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos + Vector3(0, size.y * 0.5, 0)
	sb.add_child(cs)
	cs.owner = _root

## Red/any colour plus-sign cross standing up, facing +Z, centred at pos.
func cross_upright(parent: Node, name: String, pos: Vector3, s: float, m: Material, backing: Material = null) -> void:
	var g := group(parent, name, pos)
	if backing:
		box(g, "Backing", Vector3(s * 1.25, s * 1.25, 0.03), Vector3(0, -s * 0.625, -0.015), backing)
	box(g, "V", Vector3(s * 0.32, s, 0.04), Vector3(0, -s * 0.5, 0.01), m)
	box(g, "H", Vector3(s, s * 0.32, 0.04), Vector3(0, -s * 0.16, 0.01), m)

## Flat cross lying on a roof, centred at pos.
func cross_flat(parent: Node, name: String, pos: Vector3, s: float, m: Material, backing: Material = null) -> void:
	var g := group(parent, name, pos)
	if backing:
		box(g, "Backing", Vector3(s * 1.3, 0.02, s * 1.3), Vector3.ZERO, backing)
	box(g, "A", Vector3(s * 0.32, 0.03, s), Vector3(0, 0.01, 0), m)
	box(g, "B", Vector3(s, 0.03, s * 0.32), Vector3(0, 0.01, 0), m)

## Horizontal window band wrapping a box of (w, d) centred at (cx, cz).
func window_band(parent: Node, name: String, w: float, d: float, cx: float, cz: float, y: float, h: float, m: Material) -> void:
	var g := group(parent, name)
	var t := 0.02
	box(g, "F", Vector3(w * 0.92, h, t), Vector3(cx, y, cz + d * 0.5 + t * 0.5), m)
	box(g, "B", Vector3(w * 0.92, h, t), Vector3(cx, y, cz - d * 0.5 - t * 0.5), m)
	box(g, "L", Vector3(t, h, d * 0.88), Vector3(cx - w * 0.5 - t * 0.5, y, cz), m)
	box(g, "R", Vector3(t, h, d * 0.88), Vector3(cx + w * 0.5 + t * 0.5, y, cz), m)

## Vertical mullions across a facade so the bands read as windows.
func mullions(parent: Node, name: String, w: float, z_face: float, cx: float, y0: float, h: float, step: float, m: Material) -> void:
	var g := group(parent, name)
	var n := int(w / step)
	for i in range(1, n):
		var x := cx - w * 0.5 + i * step
		box(g, "M%d" % i, Vector3(0.025, h, 0.03), Vector3(x, y0, z_face), m)

func light_bar(parent: Node, pos: Vector3, width: float, a: Color, b: Color) -> void:
	var g := group(parent, "LightBar", pos)
	box(g, "Base", Vector3(width, 0.02, 0.06), Vector3.ZERO, mat(Color(0.15, 0.15, 0.15)))
	box(g, "L1", Vector3(width * 0.48, 0.035, 0.055), Vector3(-width * 0.25, 0.02, 0), mat(a, 3.0, 0.3))
	box(g, "L2", Vector3(width * 0.48, 0.035, 0.055), Vector3(width * 0.25, 0.02, 0), mat(b, 3.0, 0.3))

func wheels(parent: Node, half_w: float, front_z: float, back_z: float) -> void:
	var tyre := mat(Color(0.08, 0.08, 0.08))
	for zz in [front_z, back_z]:
		for xx in [-half_w, half_w]:
			var w := cyl(parent, "Wheel", 0.05, 0.04, Vector3(xx, 0.0, zz), tyre, 12)
			w.rotation_degrees.z = 90
			w.position.y = 0.05

# ---------------------------------------------------------------- vehicles

func ambulance(parent: Node, name: String, pos: Vector3, rot_y: float) -> void:
	var g := group(parent, name, pos, rot_y)
	var white := mat(Color(0.97, 0.97, 0.97), 0.0, 0.4)
	var red := mat(Color(0.86, 0.1, 0.1), 0.0, 0.5)
	var glass := mat(Color(0.2, 0.3, 0.4), 0.0, 0.1)
	box(g, "Box", Vector3(0.28, 0.26, 0.36), Vector3(0, 0.04, -0.07), white)
	box(g, "Cab", Vector3(0.28, 0.18, 0.16), Vector3(0, 0.04, 0.19), white)
	box(g, "Windshield", Vector3(0.24, 0.08, 0.01), Vector3(0, 0.13, 0.275), glass)
	box(g, "Stripe", Vector3(0.29, 0.04, 0.53), Vector3(0, 0.11, 0.01), red)
	cross_upright(g, "CrossL", Vector3(-0.142, 0.27, -0.07), 0.12, red)
	g.get_node("CrossL").rotation_degrees.y = -90
	cross_upright(g, "CrossR", Vector3(0.142, 0.27, -0.07), 0.12, red)
	g.get_node("CrossR").rotation_degrees.y = 90
	cross_flat(g, "RoofCross", Vector3(0, 0.30, -0.08), 0.16, red)
	light_bar(g, Vector3(0, 0.22, 0.2), 0.22, Color(1, 0.1, 0.1), Color(0.2, 0.4, 1))
	wheels(g, 0.14, 0.17, -0.17)

func police_car(parent: Node, name: String, pos: Vector3, rot_y: float) -> void:
	var g := group(parent, name, pos, rot_y)
	var black := mat(Color(0.07, 0.08, 0.12), 0.0, 0.35)
	var white := mat(Color(0.97, 0.97, 0.97), 0.0, 0.35)
	var glass := mat(Color(0.25, 0.35, 0.45), 0.0, 0.1)
	box(g, "Body", Vector3(0.26, 0.1, 0.48), Vector3(0, 0.04, 0), black)
	box(g, "Doors", Vector3(0.265, 0.09, 0.2), Vector3(0, 0.045, 0.0), white)
	box(g, "Cabin", Vector3(0.22, 0.08, 0.24), Vector3(0, 0.14, -0.02), glass)
	box(g, "Roof", Vector3(0.22, 0.015, 0.2), Vector3(0, 0.22, -0.02), white)
	light_bar(g, Vector3(0, 0.235, -0.02), 0.2, Color(1, 0.1, 0.1), Color(0.1, 0.3, 1))
	wheels(g, 0.13, 0.15, -0.15)

func fire_truck(parent: Node, name: String, pos: Vector3, rot_y: float) -> void:
	var g := group(parent, name, pos, rot_y)
	var red := mat(Color(0.82, 0.07, 0.06), 0.0, 0.4)
	var white := mat(Color(0.97, 0.97, 0.97), 0.0, 0.5)
	var chrome := mat(Color(0.8, 0.8, 0.82), 0.0, 0.25, 0.8)
	var glass := mat(Color(0.2, 0.3, 0.4), 0.0, 0.1)
	box(g, "Body", Vector3(0.32, 0.26, 0.62), Vector3(0, 0.05, -0.12), red)
	box(g, "Cab", Vector3(0.32, 0.26, 0.2), Vector3(0, 0.05, 0.3), red)
	box(g, "Windshield", Vector3(0.28, 0.1, 0.01), Vector3(0, 0.18, 0.405), glass)
	box(g, "Stripe", Vector3(0.33, 0.03, 0.84), Vector3(0, 0.12, 0.0), white)
	box(g, "Shutters", Vector3(0.325, 0.12, 0.5), Vector3(0, 0.15, -0.12), mat(Color(0.75, 0.75, 0.78), 0.0, 0.3, 0.6))
	# ladder
	var lad := group(g, "Ladder", Vector3(0, 0.33, -0.1))
	box(lad, "RailL", Vector3(0.02, 0.025, 0.75), Vector3(-0.07, 0, 0.0), chrome)
	box(lad, "RailR", Vector3(0.02, 0.025, 0.75), Vector3(0.07, 0, 0.0), chrome)
	for i in 9:
		box(lad, "Rung%d" % i, Vector3(0.14, 0.012, 0.012), Vector3(0, 0.005, -0.34 + i * 0.085), chrome)
	light_bar(g, Vector3(0, 0.31, 0.32), 0.26, Color(1, 0.1, 0.1), Color(1, 0.1, 0.1))
	wheels(g, 0.16, 0.28, -0.3)

# ---------------------------------------------------------------- hospital

func build_hospital() -> Node3D:
	_root = Node3D.new()
	_root.name = "Hospital"
	_root.set_meta("building_type", "hospital")
	_root.set_meta("label", "City General Hospital")
	_root.set_meta("structural_integrity", 1.0)
	_root.set_meta("services", "emergency, trauma, shelter")
	var white := mat(Color(0.96, 0.97, 0.98), 0.0, 0.6)
	var offwhite := mat(Color(0.86, 0.9, 0.93), 0.0, 0.7)
	var glass := mat(Color(0.32, 0.55, 0.8), 0.08, 0.08, 0.3)
	var red := mat(Color(0.9, 0.06, 0.08), 1.2, 0.4)
	var red_dull := mat(Color(0.85, 0.08, 0.1), 0.0, 0.5)
	var asphalt := mat(Color(0.2, 0.21, 0.23))
	var paint := mat(Color(0.95, 0.95, 0.95), 0.0, 0.9)
	var yellow := mat(Color(1.0, 0.8, 0.1), 0.0, 0.8)
	var grey := mat(Color(0.55, 0.57, 0.6))

	# forecourt / drop-off
	box(_root, "Forecourt", Vector3(5.4, 0.02, 1.5), Vector3(0, 0.0, 1.85), asphalt)
	for i in 6:
		box(_root, "Line%d" % i, Vector3(0.03, 0.022, 0.5), Vector3(-2.4 + i * 0.4, 0.0, 2.25), paint)

	# Main wing (4 floors) — long low block
	var main := group(_root, "MainWing")
	box(main, "Mass", Vector3(5.0, 1.6, 2.2), Vector3(0, 0, -0.35), white)
	for f in 4:
		window_band(main, "Floor%d" % f, 5.0, 2.2, 0, -0.35, 0.15 + f * 0.38, 0.2, glass)
	mullions(main, "Mullions", 5.0, 0.77, 0, 0.12, 1.4, 0.32, white)
	box(main, "Cornice", Vector3(5.1, 0.06, 2.3), Vector3(0, 1.6, -0.35), offwhite)
	box(main, "BaseTrim", Vector3(5.06, 0.1, 2.26), Vector3(0, 0, -0.35), offwhite)
	collider(main, Vector3(5.0, 1.6, 2.2), Vector3(0, 0, -0.35))

	# Central tower (8 floors) with helipad
	var tower := group(_root, "Tower")
	box(tower, "Mass", Vector3(1.8, 3.2, 1.7), Vector3(0, 0, -0.6), white)
	for f in 4:
		window_band(tower, "Floor%d" % f, 1.8, 1.7, 0, -0.6, 1.75 + f * 0.36, 0.2, glass)
	box(tower, "Roof", Vector3(1.9, 0.06, 1.8), Vector3(0, 3.2, -0.6), offwhite)
	collider(tower, Vector3(1.8, 3.2, 1.7), Vector3(0, 0, -0.6))
	# Red-cross panel on the tower face — the main "this is a hospital" read
	cross_upright(tower, "FacadeCross", Vector3(0, 3.05, 0.27), 0.95, red, white)
	# Side crosses too, so it reads from every street
	var sl := group(tower, "SideCrossL", Vector3(-0.92, 0, -0.6), -90)
	cross_upright(sl, "Cross", Vector3(0, 3.0, 0), 0.75, red, white)
	var sr := group(tower, "SideCrossR", Vector3(0.92, 0, -0.6), 90)
	cross_upright(sr, "Cross", Vector3(0, 3.0, 0), 0.75, red, white)
	var sb := group(tower, "BackCross", Vector3(0, 0, -1.47), 180)
	cross_upright(sb, "Cross", Vector3(0, 3.05, 0), 0.95, red, white)
	# Helipad
	var pad := group(tower, "Helipad", Vector3(0, 3.26, -0.6))
	cyl(pad, "Deck", 0.82, 0.04, Vector3.ZERO, mat(Color(0.25, 0.3, 0.28)), 32)
	cyl(pad, "Ring", 0.7, 0.045, Vector3.ZERO, paint, 32)
	cyl(pad, "Inner", 0.62, 0.05, Vector3.ZERO, mat(Color(0.25, 0.3, 0.28)), 32)
	label(pad, "H", "H", Vector3(0, 0.06, 0), 0.016, Color.WHITE, Color.WHITE, Vector3(-90, 0, 0), 2)
	for a in 8:
		var ang := a * TAU / 8.0
		cyl(pad, "Lamp%d" % a, 0.03, 0.05, Vector3(cos(ang) * 0.78, 0, sin(ang) * 0.78), mat(Color(0.2, 1, 0.3), 3.0), 8)

	# Big rooftop cross on main wing so it reads from the overview camera
	cross_flat(main, "RoofCrossL", Vector3(-1.75, 1.66, -0.35), 1.1, red_dull, white)
	cross_flat(main, "RoofCrossR", Vector3(1.75, 1.66, -0.35), 1.1, red_dull, white)

	# Sign over the main entrance
	box(_root, "SignBoard", Vector3(2.6, 0.34, 0.06), Vector3(0, 1.62, 0.8), white)
	label(_root, "HospitalSign", "HOSPITAL", Vector3(0, 1.79, 0.84), 0.0062, Color(0.85, 0.05, 0.07), Color.WHITE, Vector3.ZERO, 4)

	# Entrance canopy with red stripe
	var can := group(_root, "EntranceCanopy")
	box(can, "Roof", Vector3(1.6, 0.06, 0.75), Vector3(0, 0.55, 1.12), white)
	box(can, "Stripe", Vector3(1.62, 0.04, 0.77), Vector3(0, 0.53, 1.12), red_dull)
	for x in [-0.7, 0.7]:
		box(can, "Post", Vector3(0.05, 0.53, 0.05), Vector3(x, 0, 1.45), white)
	box(can, "Doors", Vector3(0.8, 0.4, 0.02), Vector3(0, 0, 0.765), glass)

	# Emergency bay on the right with ambulances
	var er := group(_root, "Emergency", Vector3(1.85, 0, 1.1))
	box(er, "Canopy", Vector3(1.4, 0.05, 0.9), Vector3(0, 0.62, 0.1), white)
	box(er, "CanopyEdge", Vector3(1.42, 0.12, 0.04), Vector3(0, 0.56, 0.55), red_dull)
	label(er, "ERSign", "EMERGENCY", Vector3(0, 0.62, 0.575), 0.0028, Color.WHITE, Color(0.6, 0, 0), Vector3.ZERO, 6)
	for x in [-0.65, 0.65]:
		box(er, "Post", Vector3(0.05, 0.6, 0.05), Vector3(x, 0, 0.5), white)
	ambulance(er, "Ambulance1", Vector3(-0.35, 0, 0.15), 0)
	ambulance(er, "Ambulance2", Vector3(0.35, 0, 0.15), 0)
	box(er, "BayMark", Vector3(1.3, 0.024, 0.04), Vector3(0, 0, 0.5), yellow)

	# Ambulance parked on forecourt, left side
	ambulance(_root, "Ambulance3", Vector3(-2.0, 0, 1.75), 90)

	# Blue "H" road sign at the corner
	var hs := group(_root, "HSign", Vector3(-2.5, 0, 2.55))
	cyl(hs, "Pole", 0.02, 0.55, Vector3.ZERO, grey, 8)
	box(hs, "Plate", Vector3(0.28, 0.28, 0.02), Vector3(0, 0.5, 0.02), mat(Color(0.1, 0.35, 0.8)))
	label(hs, "H", "H", Vector3(0, 0.64, 0.035), 0.004, Color.WHITE, Color.WHITE, Vector3.ZERO, 2)

	# Healing garden at the back
	inst(_root, TREE_ROUND, "Tree1", Vector3(-2.3, 0, -2.2))
	inst(_root, TREE_ROUND, "Tree2", Vector3(2.3, 0, -2.2))
	inst(_root, TREE_CONE, "Tree3", Vector3(-2.4, 0, 1.0))
	inst(_root, BENCH, "Bench1", Vector3(-1.2, 0, -2.25), 0)
	inst(_root, BENCH, "Bench2", Vector3(1.2, 0, -2.25), 0)
	return _root

# ---------------------------------------------------------------- police

func build_police() -> Node3D:
	_root = Node3D.new()
	_root.name = "PoliceStation"
	_root.set_meta("building_type", "police")
	_root.set_meta("label", "Police Station")
	_root.set_meta("structural_integrity", 1.0)
	var stone := mat(Color(0.82, 0.83, 0.86), 0.0, 0.8)
	var navy := mat(Color(0.07, 0.16, 0.42), 0.0, 0.6)
	var navy_glow := mat(Color(0.12, 0.3, 0.95), 2.5, 0.3)
	var glass := mat(Color(0.3, 0.45, 0.65), 0.15, 0.1, 0.3)
	var white := mat(Color(0.96, 0.96, 0.97), 0.0, 0.6)
	var gold := mat(Color(0.95, 0.75, 0.2), 0.4, 0.3, 0.8)
	var asphalt := mat(Color(0.2, 0.21, 0.23))
	var paint := mat(Color(0.95, 0.95, 0.95), 0.0, 0.9)
	var grey := mat(Color(0.5, 0.52, 0.55), 0.0, 0.5, 0.5)
	var check_b := mat(Color(0.07, 0.16, 0.42))

	# Main building: 3 floors, navy base + top band (police colours)
	var b := group(_root, "Main")
	box(b, "Mass", Vector3(4.2, 1.25, 1.9), Vector3(0, 0, -0.75), stone)
	box(b, "BaseBand", Vector3(4.24, 0.3, 1.94), Vector3(0, 0, -0.75), navy)
	box(b, "TopBand", Vector3(4.26, 0.16, 1.96), Vector3(0, 1.17, -0.75), navy)
	# Checkerboard (Battenburg/Sillitoe) stripe — instantly reads "police"
	var chk := group(b, "Checker")
	var n := 28
	for i in n:
		var m := check_b if i % 2 == 0 else white
		var w := 4.24 / n
		box(chk, "F%d" % i, Vector3(w, 0.1, 0.02), Vector3(-2.12 + w * (i + 0.5), 1.04, 0.215), m)
		box(chk, "B%d" % i, Vector3(w, 0.1, 0.02), Vector3(-2.12 + w * (i + 0.5), 1.04, -1.715), m)
	for f in 2:
		window_band(b, "Floor%d" % f, 4.2, 1.9, 0, -0.75, 0.38 + f * 0.33, 0.2, glass)
	mullions(b, "Mullions", 4.2, 0.215, 0, 0.36, 0.6, 0.3, stone)
	collider(b, Vector3(4.2, 1.25, 1.9), Vector3(0, 0, -0.75))

	# Entrance pavilion with columns
	var e := group(_root, "Entrance", Vector3(0, 0, 0.2))
	box(e, "Steps", Vector3(1.5, 0.06, 0.5), Vector3(0, 0, 0.25), stone)
	box(e, "Roof", Vector3(1.5, 0.1, 0.55), Vector3(0, 0.9, 0.22), navy)
	for x in [-0.6, -0.2, 0.2, 0.6]:
		cyl(e, "Column", 0.045, 0.85, Vector3(x, 0.05, 0.45), white, 12)
	box(e, "Doors", Vector3(0.6, 0.5, 0.02), Vector3(0, 0.05, 0.02), glass)
	# Big sign
	box(e, "SignPanel", Vector3(1.9, 0.3, 0.05), Vector3(0, 1.32, 0.0), navy)
	label(e, "PoliceSign", "POLICE", Vector3(0, 1.47, 0.03), 0.0062, Color.WHITE, Color(0.05, 0.1, 0.3), Vector3.ZERO, 4)
	# Classic blue police lamp over the door
	var lamp := group(e, "BlueLamp", Vector3(0, 0.98, 0.42))
	box(lamp, "Lamp", Vector3(0.16, 0.18, 0.16), Vector3.ZERO, navy_glow)
	box(lamp, "Cap", Vector3(0.2, 0.03, 0.2), Vector3(0, 0.18, 0), navy)
	var ol := OmniLight3D.new()
	ol.name = "Glow"
	ol.light_color = Color(0.3, 0.45, 1)
	ol.light_energy = 1.5
	ol.omni_range = 1.4
	ol.position = Vector3(0, 0.1, 0.15)
	lamp.add_child(ol)
	ol.owner = _root
	# Gold badge on the facade
	var badge := cyl(b, "Badge", 0.26, 0.04, Vector3(1.45, 0.62, 0.22), gold, 6)
	badge.rotation_degrees.x = 90
	var badge2 := cyl(b, "Badge2", 0.26, 0.04, Vector3(-1.45, 0.62, 0.22), gold, 6)
	badge2.rotation_degrees.x = 90

	# Roof: radio mast + flag
	var mast := group(_root, "RadioMast", Vector3(1.4, 1.33, -1.1))
	for i in 3:
		cyl(mast, "Seg%d" % i, 0.05 - i * 0.012, 0.6, Vector3(0, i * 0.6, 0), grey, 6)
	cyl(mast, "Beacon", 0.04, 0.06, Vector3(0, 1.8, 0), mat(Color(1, 0.1, 0.1), 4.0), 8)
	box(mast, "Dish", Vector3(0.22, 0.22, 0.03), Vector3(0, 0.9, 0.08), white)
	var flag := group(_root, "Flag", Vector3(-1.6, 0, 1.6))
	cyl(flag, "Pole", 0.02, 1.6, Vector3.ZERO, grey, 8)
	box(flag, "Cloth", Vector3(0.45, 0.28, 0.01), Vector3(0.24, 1.28, 0), navy)
	box(flag, "ClothStripe", Vector3(0.45, 0.06, 0.012), Vector3(0.24, 1.39, 0), white)
	# Roof POLICE lettering for the overhead camera
	label(_root, "RoofText", "POLICE", Vector3(0, 1.34, -0.75), 0.011, Color.WHITE, Color(0.05, 0.1, 0.3), Vector3(-90, 0, 0), 4)

	# Car park with patrol cars
	box(_root, "CarPark", Vector3(5.4, 0.02, 1.7), Vector3(0, 0, 1.75), asphalt)
	for i in 7:
		box(_root, "Bay%d" % i, Vector3(0.03, 0.022, 0.6), Vector3(-2.4 + i * 0.5, 0, 2.2), paint)
	police_car(_root, "PatrolCar1", Vector3(-2.15, 0, 2.15), 180)
	police_car(_root, "PatrolCar2", Vector3(-1.65, 0, 2.15), 180)
	police_car(_root, "PatrolCar3", Vector3(1.85, 0, 2.15), 180)
	police_car(_root, "PatrolCar4", Vector3(1.0, 0, 1.3), 90)
	# Barriers
	inst(_root, BARRIER, "Barrier1", Vector3(2.45, 0, 1.2), 90)
	inst(_root, CONE, "Cone1", Vector3(2.4, 0, 2.55))
	inst(_root, CONE, "Cone2", Vector3(2.1, 0, 2.55))
	inst(_root, TREE_ROUND, "Tree1", Vector3(-2.4, 0, -2.3))
	inst(_root, TREE_ROUND, "Tree2", Vector3(2.4, 0, -2.3))
	return _root

# ---------------------------------------------------------------- fire

func build_fire() -> Node3D:
	_root = Node3D.new()
	_root.name = "FireStation"
	_root.set_meta("building_type", "fire")
	_root.set_meta("label", "Fire Station No. 1")
	_root.set_meta("structural_integrity", 1.0)
	var brick := mat(Color(0.72, 0.2, 0.14), 0.0, 0.9)
	var red := mat(Color(0.85, 0.07, 0.05), 0.0, 0.5)
	var white := mat(Color(0.96, 0.95, 0.92), 0.0, 0.6)
	var dark := mat(Color(0.1, 0.1, 0.12))
	var shutter := mat(Color(0.82, 0.82, 0.85), 0.0, 0.4, 0.5)
	var glass := mat(Color(0.3, 0.45, 0.6), 0.15, 0.1, 0.3)
	var concrete := mat(Color(0.72, 0.72, 0.7))
	var yellow := mat(Color(1.0, 0.8, 0.1), 0.0, 0.8)
	var gold := mat(Color(0.95, 0.75, 0.2), 0.4, 0.3, 0.8)

	var b := group(_root, "Main", Vector3(-0.5, 0, 0))
	box(b, "Mass", Vector3(4.0, 1.25, 2.2), Vector3(0, 0, -0.9), brick)
	box(b, "Parapet", Vector3(4.08, 0.1, 2.28), Vector3(0, 1.25, -0.9), white)
	box(b, "RoofDeck", Vector3(3.85, 0.012, 2.05), Vector3(0, 1.35, -0.9), mat(Color(0.3, 0.3, 0.33)))
	box(b, "Lintel", Vector3(4.04, 0.08, 2.24), Vector3(0, 0.72, -0.9), white)
	collider(b, Vector3(4.0, 1.25, 2.2), Vector3(0, 0, -0.9))
	# Three big engine-bay doors: two open (dark inside, truck visible), one closed
	for i in 3:
		var x := -1.25 + i * 1.25
		box(b, "DoorFrame%d" % i, Vector3(1.05, 0.7, 0.03), Vector3(x, 0, 0.2), white)
		if i == 2:
			box(b, "Door%d" % i, Vector3(0.9, 0.62, 0.035), Vector3(x, 0, 0.205), shutter)
			for k in 6:
				box(b, "Slat%d_%d" % [i, k], Vector3(0.9, 0.01, 0.04), Vector3(x, 0.08 + k * 0.1, 0.205), mat(Color(0.6, 0.6, 0.64)))
		else:
			box(b, "Door%d" % i, Vector3(0.9, 0.62, 0.035), Vector3(x, 0, 0.205), dark)
		label(b, "BayNo%d" % i, str(i + 1), Vector3(x, 0.66, 0.225), 0.0022, Color(0.85, 0.07, 0.05), Color.WHITE, Vector3.ZERO, 6)
	# Upper-floor windows
	for i in 8:
		box(b, "Win%d" % i, Vector3(0.28, 0.24, 0.02), Vector3(-1.75 + i * 0.5, 0.86, 0.21), glass)
	# Sign
	box(b, "SignBoard", Vector3(3.2, 0.3, 0.05), Vector3(0, 1.35, 0.17), red)
	label(b, "FireSign", "FIRE STATION", Vector3(0, 1.5, 0.2), 0.0058, Color.WHITE, Color(0.4, 0, 0), Vector3.ZERO, 4)
	# Emblem (gold badge with red cross) between sign and roof edge
	var em := group(b, "Emblem", Vector3(1.75, 0.95, 0.24))
	var d := cyl(em, "Disc", 0.2, 0.03, Vector3.ZERO, gold, 8)
	d.rotation_degrees.x = 90
	label(em, "No", "1", Vector3(0, 0, 0.03), 0.004, Color(0.75, 0.05, 0.03), Color.WHITE, Vector3.ZERO, 4)
	# Roof text for overhead camera
	label(b, "RoofText", "FIRE", Vector3(0, 1.36, -0.95), 0.014, Color.WHITE, Color(0.5, 0, 0), Vector3(-90, 0, 0), 4)
	# Siren on roof
	var siren := group(b, "Siren", Vector3(-1.5, 1.35, -1.5))
	cyl(siren, "Post", 0.03, 0.3, Vector3.ZERO, white, 8)
	cyl(siren, "Horn", 0.08, 0.12, Vector3(0, 0.3, 0), red, 12)

	# Engines inside the open bays (poking out)
	fire_truck(b, "Engine1", Vector3(-1.25, 0, 0.05), 0)
	fire_truck(b, "Engine2", Vector3(0.0, 0, 0.3), 0)

	# Hose-drying / training tower (tall, very fire-station)
	var t := group(_root, "HoseTower", Vector3(2.15, 0, -1.4))
	box(t, "Mass", Vector3(0.8, 2.9, 0.8), Vector3.ZERO, brick)
	box(t, "Cap", Vector3(0.95, 0.12, 0.95), Vector3(0, 2.9, 0), white)
	box(t, "Roof", Vector3(0.7, 0.25, 0.7), Vector3(0, 3.02, 0), red)
	for k in 4:
		box(t, "Win%d" % k, Vector3(0.22, 0.25, 0.02), Vector3(0, 0.6 + k * 0.45, 0.41), glass)
		box(t, "Band%d" % k, Vector3(0.82, 0.04, 0.82), Vector3(0, 0.45 + k * 0.45, 0), white)
	cyl(t, "Beacon", 0.06, 0.08, Vector3(0, 3.27, 0), mat(Color(1, 0.15, 0.05), 4.0), 10)
	collider(t, Vector3(0.8, 2.9, 0.8), Vector3.ZERO)
	label(t, "TowerSign", "FIRE", Vector3(0, 2.62, 0.42), 0.0042, Color.WHITE, Color(0.4, 0, 0), Vector3.ZERO, 4)

	# Apron in front of the bays with yellow keep-clear hatching
	box(_root, "Apron", Vector3(4.0, 0.02, 2.3), Vector3(-0.5, 0, 1.35), concrete)
	box(_root, "KeepClear", Vector3(3.8, 0.024, 0.06), Vector3(-0.5, 0, 2.45), yellow)
	for i in 10:
		box(_root, "Hatch%d" % i, Vector3(0.05, 0.024, 0.45), Vector3(-2.3 + i * 0.4, 0, 2.2), yellow, Vector3(0, 35, 0))
	label(_root, "KeepClearText", "KEEP CLEAR", Vector3(-0.5, 0.03, 1.85), 0.004, Color(1, 0.8, 0.1), Color(0.3, 0.2, 0), Vector3(-90, 0, 0), 2)
	# Third engine parked on the apron
	fire_truck(_root, "Engine3", Vector3(1.6, 0, 1.2), 0)
	# Hydrants
	for p in [Vector3(-2.6, 0, 2.55), Vector3(2.6, 0, 2.55)]:
		var h := group(_root, "Hydrant", p)
		cyl(h, "Body", 0.05, 0.16, Vector3.ZERO, red, 10)
		cyl(h, "Top", 0.055, 0.04, Vector3(0, 0.16, 0), white, 10)
	inst(_root, TREE_CONE, "Tree1", Vector3(-2.5, 0, -2.4))
	return _root

# ---------------------------------------------------------------- park

const PARK_MIN := Vector2(-3.5, -14.5)   # north lawn (world x,z)
const PARK_MAX := Vector2(24.5, -4.0)
const LOBE_MIN := Vector2(4.0, -4.5)     # old tent block + former road strip
const LOBE_MAX := Vector2(10.0, 3.0)
const POND_C := Vector2(13.5, -9.6)
const POND_R := Vector2(3.6, 2.0)
const PLAZA_C := Vector2(7.0, 0.0)

var _paths: Array = []   # [Vector2 a, Vector2 b, width]

func _in_park(p: Vector2) -> bool:
	var inside_lawn := p.x > PARK_MIN.x + 0.4 and p.x < PARK_MAX.x - 0.4 and p.y > PARK_MIN.y + 0.4 and p.y < PARK_MAX.y - 0.3
	var inside_lobe := p.x > LOBE_MIN.x + 0.4 and p.x < LOBE_MAX.x - 0.4 and p.y > LOBE_MIN.y and p.y < LOBE_MAX.y - 0.4
	return inside_lawn or inside_lobe

func _in_pond(p: Vector2, margin := 0.0) -> bool:
	var q := (p - POND_C) / (POND_R + Vector2(margin, margin))
	return q.length() < 1.0

func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _near_path(p: Vector2, margin: float) -> bool:
	for s in _paths:
		if _dist_seg(p, s[0], s[1]) < s[2] * 0.5 + margin:
			return true
	return false

func path(parent: Node, name: String, a: Vector2, b: Vector2, w: float, m: Material) -> void:
	_paths.append([a, b, w])
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	var ang := rad_to_deg(atan2(b.x - a.x, b.y - a.y))
	box(parent, name, Vector3(w, 0.012, len + w), Vector3(mid.x, 0.075, mid.y), m, Vector3(0, ang, 0))

func build_park() -> Node3D:
	_root = Node3D.new()
	_root.name = "CentralPark"
	_root.set_meta("label", "Central Park")
	_root.set_meta("description", "Large green park - open ground away from tall buildings, doubles as the evacuation assembly point.")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var gravel := mat(Color(0.86, 0.78, 0.62), 0.0, 1.0)
	var stone := mat(Color(0.78, 0.76, 0.72), 0.0, 0.9)
	var hedge := mat(Color(0.16, 0.45, 0.2), 0.0, 1.0)
	var lawn_dark := mat(Color(0.3, 0.62, 0.25), 0.0, 1.0)
	var water := mat(Color(0.25, 0.55, 0.85), 0.2, 0.05, 0.2, 0.85)
	var white := mat(Color(0.95, 0.95, 0.93), 0.0, 0.6)
	var roof_green := mat(Color(0.2, 0.45, 0.35), 0.0, 0.7)
	var wood := mat(Color(0.55, 0.36, 0.2), 0.0, 0.9)

	var ground := group(_root, "Ground")
	# Curb/sidewalk base + lawn (same recipe as the city blocks)
	var c := (PARK_MIN + PARK_MAX) * 0.5
	var sz := PARK_MAX - PARK_MIN
	var sw := inst(ground, SIDEWALK, "LawnSidewalk", Vector3(c.x, 0, c.y))
	sw.scale = Vector3(sz.x + 1.0, 1, sz.y + 1.0)
	var g1 := inst(ground, GRASS, "Lawn", Vector3(c.x, 0.04, c.y))
	g1.scale = Vector3(sz.x, 1, sz.y)
	var lc := (LOBE_MIN + LOBE_MAX) * 0.5
	var lz := LOBE_MAX - LOBE_MIN
	var sw2 := inst(ground, SIDEWALK, "LobeSidewalk", Vector3(lc.x, 0, lc.y))
	sw2.scale = Vector3(lz.x + 1.0, 1, lz.y + 0.5)
	var g2 := inst(ground, GRASS, "LobeLawn", Vector3(lc.x, 0.04, lc.y))
	g2.scale = Vector3(lz.x, 1, lz.y)
	# A few darker mown patches for variety
	for i in 5:
		var p := Vector2(rng.randf_range(-1.5, 22.0), rng.randf_range(-13.5, -5.5))
		if _in_pond(p, 1.0):
			continue
		var patch := cyl(ground, "Mown%d" % i, 1.0, 0.005, Vector3(p.x, 0.068, p.y), lawn_dark, 20)
		patch.scale = Vector3(rng.randf_range(1.0, 1.8), 1, rng.randf_range(0.8, 1.4))

	# Pond with stone rim and a little island
	var pond := group(_root, "Pond")
	var rim := cyl(pond, "Rim", 1.0, 0.06, Vector3(POND_C.x, 0.04, POND_C.y), stone, 40)
	rim.scale = Vector3(POND_R.x + 0.15, 1, POND_R.y + 0.15)
	var wat := cyl(pond, "Water", 1.0, 0.065, Vector3(POND_C.x, 0.042, POND_C.y), water, 40)
	wat.scale = Vector3(POND_R.x, 1, POND_R.y)
	var isl := cyl(pond, "Island", 1.0, 0.09, Vector3(POND_C.x + 1.4, 0.04, POND_C.y - 0.3), lawn_dark, 16)
	isl.scale = Vector3(0.6, 1, 0.45)
	inst(pond, TREE_ROUND, "IslandTree", Vector3(POND_C.x + 1.4, 0.12, POND_C.y - 0.3))
	# Footbridge to the island-ish, and a jetty
	box(pond, "Jetty", Vector3(0.35, 0.03, 0.9), Vector3(POND_C.x - 1.8, 0.1, POND_C.y + 1.6), wood)

	# Paths — promenade from the plaza north, loop round the pond, diagonals
	var paths := group(_root, "Paths")
	path(paths, "Promenade", Vector2(7.0, 2.7), Vector2(7.0, -13.8), 0.5, gravel)
	path(paths, "CrossWalk", Vector2(-3.0, -9.0), Vector2(24.0, -9.0), 0.4, gravel)
	path(paths, "DiagNW", Vector2(-3.0, -14.0), Vector2(7.0, -6.0), 0.35, gravel)
	path(paths, "DiagNE", Vector2(24.0, -14.0), Vector2(17.6, -10.5), 0.35, gravel)
	path(paths, "DiagSW", Vector2(-3.0, -4.3), Vector2(7.0, -9.0), 0.35, gravel)
	path(paths, "DiagSE", Vector2(24.0, -4.3), Vector2(17.6, -8.6), 0.35, gravel)
	# loop around pond (polygon)
	var loop_pts: Array[Vector2] = []
	for i in 14:
		var a := i * TAU / 14.0
		loop_pts.append(POND_C + Vector2(cos(a) * (POND_R.x + 0.7), sin(a) * (POND_R.y + 0.65)))
	for i in 14:
		path(paths, "Loop%d" % i, loop_pts[i], loop_pts[(i + 1) % 14], 0.35, gravel)

	# Fountain plaza where the tent camp used to be
	var plaza := group(_root, "FountainPlaza", Vector3(PLAZA_C.x, 0, PLAZA_C.y))
	cyl(plaza, "Paving", 1.6, 0.03, Vector3(0, 0.06, 0), stone, 40)
	cyl(plaza, "PavingRing", 1.62, 0.025, Vector3(0, 0.055, 0), gravel, 40)
	cyl(plaza, "Basin", 0.75, 0.14, Vector3(0, 0.08, 0), white, 32)
	cyl(plaza, "BasinWater", 0.68, 0.145, Vector3(0, 0.081, 0), water, 32)
	cyl(plaza, "Column", 0.1, 0.35, Vector3(0, 0.2, 0), white, 16)
	cyl(plaza, "Bowl", 0.3, 0.06, Vector3(0, 0.55, 0), white, 24, 0.2)
	cyl(plaza, "Spout", 0.08, 0.22, Vector3(0, 0.6, 0), mat(Color(0.6, 0.85, 1.0), 0.6, 0.05, 0.0, 0.7), 12, 0.02)
	_paths.append([PLAZA_C, PLAZA_C, 3.4])
	for i in 6:
		var a := i * TAU / 6.0 + 0.5
		inst(plaza, BENCH, "Bench%d" % i, Vector3(cos(a) * 1.35, 0.07, sin(a) * 1.35), -rad_to_deg(a) - 90)
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4
		inst(plaza, PLANTER, "Planter%d" % i, Vector3(cos(a) * 1.75, 0.07, sin(a) * 1.75))
	# keep it marked as the evacuation assembly point
	var ev1 := inst(plaza, SIGN_EVAC, "EvacSign1", Vector3(-1.9, 0.04, 1.6), 0)
	ev1.set_meta("label", "Evacuation Assembly Point")
	var ev2 := inst(plaza, SIGN_EVAC, "EvacSign2", Vector3(1.9, 0.04, -1.9), 180)
	ev2.set_meta("label", "Evacuation Assembly Point")

	# Bandstand / gazebo on the west lawn
	var gz := group(_root, "Bandstand", Vector3(1.5, 0, -11.0))
	_paths.append([Vector2(1.5, -11.0), Vector2(1.5, -11.0), 2.4])
	cyl(gz, "Base", 0.9, 0.12, Vector3(0, 0.04, 0), white, 8)
	for i in 8:
		var a := i * TAU / 8.0
		cyl(gz, "Post%d" % i, 0.03, 0.55, Vector3(cos(a) * 0.78, 0.16, sin(a) * 0.78), white, 8)
	cyl(gz, "Roof", 1.0, 0.4, Vector3(0, 0.7, 0), roof_green, 8, 0.05)
	cyl(gz, "Finial", 0.03, 0.15, Vector3(0, 1.1, 0), mat(Color(0.95, 0.75, 0.2), 0.3, 0.3, 0.8), 8)
	collider(gz, Vector3(1.6, 1.1, 1.6), Vector3(0, 0, 0))

	# Playground-ish open meadow east: flower beds
	var flowers := group(_root, "FlowerBeds")
	var fcols := [Color(0.95, 0.3, 0.45), Color(1.0, 0.8, 0.2), Color(0.6, 0.4, 0.95), Color(1, 0.55, 0.2)]
	var fb_pts := [Vector2(20.5, -6.0), Vector2(22.0, -12.5), Vector2(3.5, -6.0), Vector2(10.0, -5.5), Vector2(-1.5, -7.0), Vector2(19.0, -13.0)]
	for i in fb_pts.size():
		var p: Vector2 = fb_pts[i]
		cyl(flowers, "Soil%d" % i, 0.55, 0.05, Vector3(p.x, 0.06, p.y), wood, 20)
		cyl(flowers, "Bloom%d" % i, 0.48, 0.1, Vector3(p.x, 0.07, p.y), mat(fcols[i % fcols.size()], 0.15, 1.0), 20)
		_paths.append([p, p, 1.3])

	# Hedge border with gaps at the entrances
	var hedges := group(_root, "Hedges")
	var hh := 0.28
	var hw := 0.22
	var x0 := PARK_MIN.x + 0.15
	var x1 := PARK_MAX.x - 0.15
	var z0 := PARK_MIN.y + 0.15
	var z1 := PARK_MAX.y - 0.15
	# north edge — gaps at x=-3 (diag), 7 (promenade), 24
	_hedge_run(hedges, "N", Vector2(x0 + 0.8, z0), Vector2(6.4, z0), hw, hh, hedge)
	_hedge_run(hedges, "N2", Vector2(7.6, z0), Vector2(x1 - 0.8, z0), hw, hh, hedge)
	# west / east edges — gap at z=-9 (cross path)
	_hedge_run(hedges, "W", Vector2(x0, z0 + 0.8), Vector2(x0, -9.5), hw, hh, hedge)
	_hedge_run(hedges, "W2", Vector2(x0, -8.5), Vector2(x0, z1 - 0.8), hw, hh, hedge)
	_hedge_run(hedges, "E", Vector2(x1, z0 + 0.8), Vector2(x1, -9.5), hw, hh, hedge)
	_hedge_run(hedges, "E2", Vector2(x1, -8.5), Vector2(x1, z1 - 0.8), hw, hh, hedge)
	# south edge (along the road) — leave the lobe open
	_hedge_run(hedges, "S", Vector2(x0 + 0.8, z1), Vector2(3.6, z1), hw, hh, hedge)
	_hedge_run(hedges, "S2", Vector2(10.4, z1), Vector2(x1 - 0.8, z1), hw, hh, hedge)

	# Streetlights along the promenade and cross path
	var lights := group(_root, "Lamps")
	var li := 0
	for zz in [-1.9, -5.0, -7.5, -11.0, -13.3]:
		inst(lights, STREETLIGHT, "Lamp%d" % li, Vector3(6.6, 0.07, zz), 90); li += 1
		inst(lights, STREETLIGHT, "Lamp%d" % li, Vector3(7.4, 0.07, zz), -90); li += 1
	for xx in [-1.0, 3.5, 20.0, 23.0]:
		inst(lights, STREETLIGHT, "Lamp%d" % li, Vector3(xx, 0.07, -9.4), 0); li += 1

	# Benches along paths
	var benches := group(_root, "Benches")
	var bi := 0
	for zz in [-3.5, -6.2, -12.2]:
		inst(benches, BENCH, "Bench%d" % bi, Vector3(6.45, 0.07, zz), 90); bi += 1
		inst(benches, BENCH, "Bench%d" % bi, Vector3(7.55, 0.07, zz), -90); bi += 1
	for xx in [0.0, 4.5, 21.5]:
		inst(benches, BENCH, "Bench%d" % bi, Vector3(xx, 0.07, -8.55), 180); bi += 1
	for i in range(0, 14, 2):
		var p: Vector2 = loop_pts[i] + (loop_pts[i] - POND_C).normalized() * 0.42
		var a := rad_to_deg(atan2(POND_C.x - p.x, POND_C.y - p.y))
		inst(benches, BENCH, "PondBench%d" % i, Vector3(p.x, 0.07, p.y), a); bi += 1

	# Lots of trees — scattered with rejection so they avoid paths/pond/plaza
	var trees := group(_root, "Trees")
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 150 and tries < 8000:
		tries += 1
		var p := Vector2(rng.randf_range(PARK_MIN.x, PARK_MAX.x), rng.randf_range(PARK_MIN.y, LOBE_MAX.y))
		if not _in_park(p) or _in_pond(p, 0.95) or _near_path(p, 0.32):
			continue
		var ok := true
		for q in placed:
			if q.distance_to(p) < 0.62:
				ok = false
				break
		if not ok:
			continue
		# leave an open meadow in the east for gatherings
		if p.x > 18.0 and p.x < 23.0 and p.y > -8.0 and p.y < -5.0:
			continue
		placed.append(p)
		var cone := rng.randf() < 0.3
		var s := rng.randf_range(0.9, 1.45)
		inst(trees, TREE_CONE if cone else TREE_ROUND, "Tree%d" % placed.size(), Vector3(p.x, 0.07, p.y), rng.randf_range(0, 360), s)
	print("park trees: ", placed.size())
	return _root

func _hedge_run(parent: Node, name: String, a: Vector2, b: Vector2, w: float, h: float, m: Material) -> void:
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	var ang := rad_to_deg(atan2(b.x - a.x, b.y - a.y))
	box(parent, name, Vector3(w, h, len), Vector3(mid.x, 0.07, mid.y), m, Vector3(0, ang, 0))
