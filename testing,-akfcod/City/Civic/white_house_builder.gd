extends SceneTree
## Generates the presidential residence (White House style) for the civic
## centre, next to the hospital. Same toolkit and units as builder.gd.
## Run headless:
##   godot --headless --path . -s res://City/Civic/white_house_builder.gd
## Faces local +Z (toward the park). Lot is 11 x 7 local units: it fills the
## corner between the hospital road and the park (see city.tscn PresidentHouse).

var _mats := {}
var _root: Node3D

const TREE_ROUND := "res://Models/Custom/tree_round.glb"
const TREE_CONE := "res://Models/Custom/tree_cone.glb"
const BENCH := "res://Models/Custom/bench.glb"
const STREETLIGHT := "res://Models/Custom/streetlight.glb"
const PLANTER := "res://Models/Custom/planter.glb"
const GRASS := "res://Models/Custom/grass.glb"

func _init() -> void:
	_save(build_white_house(), "res://City/Civic/president_palace.tscn")
	quit()

# ---------------------------------------------------------------- helpers (same as builder.gd)

func _save(root: Node3D, path: String) -> void:
	var ps := PackedScene.new()
	if ps.pack(root) != OK:
		push_error("pack failed %s" % path)
	ResourceSaver.save(ps, path)
	print("saved ", path)
	root.free()
	_mats.clear()

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

## Box whose BOTTOM sits at pos.y.
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

## Triangular prism (gable / pediment) whose BOTTOM sits at pos.y; ridge runs along local Z.
func prism(parent: Node, name: String, size: Vector3, pos: Vector3, m: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	mi.rotation_degrees.y = rot_y
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

## Flat strip between two ground points (paths, driveways, fences).
func strip(parent: Node, name: String, a: Vector2, b: Vector2, w: float, h: float, y: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var mi := box(parent, name, Vector3(w, h, d.length() + w * 0.5), Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5), m)
	mi.rotation.y = atan2(d.x, d.y)
	return mi

## Polyline arc of strips (driveways / lawn rings). Angles in radians, 0 = +X.
func arc(parent: Node, name: String, c: Vector2, r: Vector2, a0: float, a1: float, segs: int, w: float, h: float, y: float, m: Material) -> void:
	var g := group(parent, name)
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		strip(g, "S%d" % i, c + Vector2(cos(t0) * r.x, sin(t0) * r.y), c + Vector2(cos(t1) * r.x, sin(t1) * r.y), w, h, y, m)

## Five-point star lying flat, centred at pos, pointing toward -Z (towards the back).
func star_flat(parent: Node, name: String, pos: Vector3, r: float, m: Material) -> void:
	var g := group(parent, name, pos)
	cyl(g, "Core", r * 0.42, 0.014, Vector3(0, -0.001, 0), m, 5).rotation_degrees.y = 18
	var L := r * 0.7
	for i in 5:
		var arm := group(g, "Arm%d" % i, Vector3.ZERO, i * 72.0)
		# PrismMesh apex is +Y; tipping it -90 deg on X lays it flat with the tip toward -Z
		var mi := MeshInstance3D.new()
		mi.name = "Point"
		var pm := PrismMesh.new()
		pm.size = Vector3(r * 0.46, L, 0.012)
		mi.mesh = pm
		mi.material_override = m
		mi.rotation_degrees.x = -90
		mi.position = Vector3(0, 0.006, -(r - L * 0.5))
		arm.add_child(mi)
		mi.owner = _root

## Facade window grid on a wall facing +Z (rot_y rotates the whole grid).
func windows(parent: Node, name: String, centre: Vector3, rot_y: float, cols: int, span: float, rows: Array, w: float, h: float, glass: Material, frame: Material) -> void:
	var g := group(parent, name, centre, rot_y)
	for r in rows.size():
		for c in cols:
			var x := -span * 0.5 + (span / maxi(cols - 1, 1)) * c
			box(g, "Fr%d_%d" % [r, c], Vector3(w + 0.03, h + 0.03, 0.012), Vector3(x, rows[r] - 0.015, 0.0), frame)
			box(g, "Gl%d_%d" % [r, c], Vector3(w, h, 0.02), Vector3(x, rows[r], 0.004), glass)
			# little pediment cap over the upper-floor windows
			if r == rows.size() - 1:
				box(g, "Cap%d_%d" % [r, c], Vector3(w + 0.05, 0.02, 0.025), Vector3(x, rows[r] + h + 0.01, 0.006), frame)

## Row of round columns along X.
func colonnade(parent: Node, name: String, centre: Vector3, count: int, span: float, r: float, h: float, m: Material, cap: Material) -> void:
	var g := group(parent, name, centre)
	for i in count:
		var x := -span * 0.5 + (span / maxi(count - 1, 1)) * i
		cyl(g, "Col%d" % i, r, h, Vector3(x, 0, 0), m, 12)
		box(g, "Cap%d" % i, Vector3(r * 2.6, 0.025, r * 2.6), Vector3(x, h - 0.025, 0), cap)
		box(g, "Base%d" % i, Vector3(r * 2.6, 0.02, r * 2.6), Vector3(x, 0, 0), cap)

## Balustrade (low rail with little posts) around a w x d rectangle at height y.
func balustrade(parent: Node, name: String, w: float, d: float, c: Vector3, h: float, m: Material) -> void:
	var g := group(parent, name, c)
	var t := 0.03
	box(g, "F", Vector3(w, h, t), Vector3(0, 0, d * 0.5 - t * 0.5), m)
	box(g, "B", Vector3(w, h, t), Vector3(0, 0, -d * 0.5 + t * 0.5), m)
	box(g, "L", Vector3(t, h, d), Vector3(-w * 0.5 + t * 0.5, 0, 0), m)
	box(g, "R", Vector3(t, h, d), Vector3(w * 0.5 - t * 0.5, 0, 0), m)
	var n := int(w / 0.18)
	for i in range(n + 1):
		var x := -w * 0.5 + w * i / n
		box(g, "PF%d" % i, Vector3(0.045, h + 0.02, 0.045), Vector3(x, 0, d * 0.5 - t * 0.5), m)
		box(g, "PB%d" % i, Vector3(0.045, h + 0.02, 0.045), Vector3(x, 0, -d * 0.5 + t * 0.5), m)

func suv(parent: Node, name: String, pos: Vector3, rot_y: float, long := false) -> void:
	var g := group(parent, name, pos, rot_y)
	var black := mat(Color(0.05, 0.055, 0.07), 0.0, 0.25, 0.4)
	var glass := mat(Color(0.12, 0.16, 0.22), 0.0, 0.08, 0.3)
	var chrome := mat(Color(0.8, 0.8, 0.82), 0.0, 0.25, 0.8)
	var l := 0.62 if long else 0.46
	box(g, "Body", Vector3(0.26, 0.11, l), Vector3(0, 0.04, 0), black)
	box(g, "Cabin", Vector3(0.23, 0.09, l * 0.6), Vector3(0, 0.15, -l * 0.04), glass)
	box(g, "Roof", Vector3(0.235, 0.015, l * 0.56), Vector3(0, 0.24, -l * 0.04), black)
	box(g, "Grille", Vector3(0.2, 0.05, 0.01), Vector3(0, 0.07, l * 0.5), chrome)
	if long:
		# little flags on the front wings of the state car
		for x in [-0.11, 0.11]:
			cyl(g, "FlagPole", 0.006, 0.09, Vector3(x, 0.15, l * 0.42), chrome, 6)
			box(g, "Flag", Vector3(0.006, 0.035, 0.05), Vector3(x, 0.2, l * 0.39), mat(Color(0.1, 0.18, 0.5), 0.2))
	var tyre := mat(Color(0.08, 0.08, 0.08))
	for zz in [l * 0.33, -l * 0.33]:
		for xx in [-0.13, 0.13]:
			var w := cyl(g, "Wheel", 0.05, 0.04, Vector3(xx, 0.0, zz), tyre, 12)
			w.rotation_degrees.z = 90
			w.position.y = 0.05

func helicopter(parent: Node, name: String, pos: Vector3, rot_y: float) -> void:
	var g := group(parent, name, pos, rot_y)
	var green := mat(Color(0.14, 0.24, 0.16), 0.0, 0.45)
	var white := mat(Color(0.96, 0.96, 0.95), 0.0, 0.4)
	var glass := mat(Color(0.15, 0.22, 0.3), 0.0, 0.08, 0.3)
	var dark := mat(Color(0.1, 0.1, 0.11), 0.0, 0.5)
	# skids
	for x in [-0.11, 0.11]:
		box(g, "Skid", Vector3(0.02, 0.02, 0.5), Vector3(x, 0.0, 0.02), dark)
		for z in [-0.12, 0.15]:
			box(g, "Strut", Vector3(0.015, 0.07, 0.015), Vector3(x, 0.02, z), dark)
	box(g, "Body", Vector3(0.22, 0.16, 0.52), Vector3(0, 0.08, 0.02), green)
	box(g, "Top", Vector3(0.2, 0.05, 0.42), Vector3(0, 0.24, 0.0), white)
	box(g, "Nose", Vector3(0.18, 0.11, 0.1), Vector3(0, 0.09, 0.32), glass)
	box(g, "Tail", Vector3(0.06, 0.06, 0.55), Vector3(0, 0.18, -0.5), green)
	box(g, "Fin", Vector3(0.015, 0.16, 0.1), Vector3(0, 0.2, -0.76), white)
	box(g, "TailRotor", Vector3(0.012, 0.16, 0.025), Vector3(0.03, 0.2, -0.76), dark)
	cyl(g, "Mast", 0.025, 0.05, Vector3(0, 0.29, 0.0), dark, 8)
	var rotor := group(g, "Rotor", Vector3(0, 0.34, 0.0), 20)
	for i in 2:
		box(rotor, "Blade%d" % i, Vector3(0.035, 0.008, 0.78), Vector3.ZERO, dark, Vector3(0, i * 90.0, 0))
	cyl(rotor, "Hub", 0.035, 0.02, Vector3(0, 0, 0), white, 10)

# ---------------------------------------------------------------- the residence

func build_white_house() -> Node3D:
	_root = Node3D.new()
	_root.name = "PresidentPalace"
	_root.set_meta("building_type", "presidential_residence")
	_root.set_meta("label", "Presidential Palace")
	_root.set_meta("structural_integrity", 1.0)
	_root.set_meta("services", "government, crisis command")

	var white := mat(Color(0.97, 0.97, 0.95), 0.0, 0.55)
	var stone := mat(Color(0.86, 0.85, 0.8), 0.0, 0.75)
	var cream := mat(Color(0.93, 0.92, 0.87), 0.0, 0.6)
	var roof := mat(Color(0.72, 0.74, 0.77), 0.0, 0.7)
	var roof_dark := mat(Color(0.52, 0.55, 0.6), 0.0, 0.7)
	var glass := mat(Color(0.2, 0.3, 0.42), 0.15, 0.1, 0.3)
	var glass_warm := mat(Color(1.0, 0.82, 0.5), 0.6, 0.3)
	var gravel := mat(Color(0.9, 0.86, 0.78), 0.0, 1.0)
	var paving := mat(Color(0.8, 0.79, 0.75), 0.0, 0.9)
	var lawn_light := mat(Color(0.42, 0.74, 0.32), 0.0, 1.0)
	var lawn_dark := mat(Color(0.33, 0.64, 0.27), 0.0, 1.0)
	var hedge := mat(Color(0.14, 0.42, 0.2), 0.0, 1.0)
	var iron := mat(Color(0.08, 0.08, 0.1), 0.0, 0.4, 0.6)
	var gold := mat(Color(0.98, 0.76, 0.22), 0.5, 0.3, 0.8)
	var navy := mat(Color(0.07, 0.12, 0.32), 0.0, 0.5)
	var water := mat(Color(0.25, 0.6, 0.9), 0.25, 0.05, 0.2, 0.85)
	var red := mat(Color(0.82, 0.1, 0.12), 0.0, 0.5)
	var tarmac := mat(Color(0.22, 0.24, 0.24))

	# Lot is 11 x 7 local units (296 x 188 world) — it fills the corner under the
	# park exactly. Front (+Z) faces the park.
	const LX := 5.3   # grass half-size along X
	const LZ := 3.3   # grass half-size along Z
	const FX := 5.18  # fence
	const FZ := 3.18

	# ------------------------------------------------ grounds
	var grounds := group(_root, "Grounds")
	var lawn := inst(grounds, GRASS, "Lawn", Vector3(0, 0.0, 0))
	lawn.scale = Vector3(LX * 2.0, 1, LZ * 2.0)
	box(grounds, "LightMow", Vector3(LX * 2.0 - 0.1, 0.002, LZ * 2.0 - 0.1), Vector3(0, 0.032, 0), lawn_light)
	# Mowing stripes — they read really nicely from the overview camera
	var stripes := group(grounds, "MowStripes")
	var sw := 0.53
	var n_str := int(LX * 2.0 / sw)
	for i in n_str:
		if i % 2 == 1:
			box(stripes, "Stripe%d" % i, Vector3(sw, 0.002, LZ * 2.0 - 0.1), Vector3(-LX + sw * (i + 0.5), 0.034, 0), lawn_dark)

	# Iron perimeter fence with stone piers; drive gates at x = +-2.3, footgate at 0
	var fence := group(grounds, "Fence")
	var fh := 0.16
	var gate := 0.26
	strip(fence, "Back", Vector2(-FX, -FZ), Vector2(FX, -FZ), 0.02, fh, 0.03, iron)
	strip(fence, "Left", Vector2(-FX, -FZ), Vector2(-FX, FZ), 0.02, fh, 0.03, iron)
	strip(fence, "Right", Vector2(FX, -FZ), Vector2(FX, FZ), 0.02, fh, 0.03, iron)
	var front_cuts := [-FX, -2.3 - gate, -2.3 + gate, -0.18, 0.18, 2.3 - gate, 2.3 + gate, FX]
	for i in range(0, front_cuts.size(), 2):
		strip(fence, "Front%d" % i, Vector2(front_cuts[i], FZ), Vector2(front_cuts[i + 1], FZ), 0.02, fh, 0.03, iron)
	var lamp_mat := mat(Color(1, 0.88, 0.6), 2.0)
	for i in front_cuts.size():
		box(fence, "PierF%d" % i, Vector3(0.08, 0.24, 0.08), Vector3(front_cuts[i], 0.03, FZ), stone)
		cyl(fence, "LampF%d" % i, 0.028, 0.045, Vector3(front_cuts[i], 0.27, FZ), lamp_mat, 8)
	for i in 15:
		var t := -FX + i * FX * 2.0 / 14.0
		box(fence, "PierB%d" % i, Vector3(0.08, 0.24, 0.08), Vector3(t, 0.03, -FZ), stone)
	for i in 9:
		var t := -FZ + i * FZ * 2.0 / 8.0
		box(fence, "PierL%d" % i, Vector3(0.08, 0.24, 0.08), Vector3(-FX, 0.03, t), stone)
		box(fence, "PierR%d" % i, Vector3(0.08, 0.24, 0.08), Vector3(FX, 0.03, t), stone)
	# Guard booths just inside the drive gates
	for s in [-1, 1]:
		var gb := group(grounds, "GuardBooth%s" % ("L" if s < 0 else "R"), Vector3(s * (2.3 + gate + 0.25), 0, FZ - 0.25))
		box(gb, "Hut", Vector3(0.22, 0.24, 0.22), Vector3(0, 0.03, 0), white)
		box(gb, "Win", Vector3(0.23, 0.08, 0.23), Vector3(0, 0.16, 0), glass)
		box(gb, "Roof", Vector3(0.29, 0.03, 0.29), Vector3(0, 0.27, 0), roof_dark)
		box(gb, "Boom", Vector3(0.42, 0.02, 0.02), Vector3(-s * 0.32, 0.12, 0.12), red)

	# ------------------------------------------------ north drive (horseshoe) facing the park
	var drive := group(_root, "NorthDrive")
	var arc_c := Vector2(0, FZ)
	var arc_r := Vector2(2.3, 1.45)
	arc(drive, "Arc", arc_c, arc_r, PI, TAU, 24, 0.36, 0.01, 0.031, gravel)
	strip(drive, "GateL", Vector2(-2.3, FZ + 0.15), Vector2(-2.3, FZ - 0.1), 0.36, 0.01, 0.031, gravel)
	strip(drive, "GateR", Vector2(2.3, FZ + 0.15), Vector2(2.3, FZ - 0.1), 0.36, 0.01, 0.031, gravel)
	box(drive, "PorticoApron", Vector3(1.9, 0.01, 0.34), Vector3(0, 0.031, 1.78), gravel)
	strip(drive, "FootPath", Vector2(0, FZ + 0.15), Vector2(0, 2.95), 0.2, 0.01, 0.031, paving)
	var nf := group(drive, "NorthFountain", Vector3(0, 0.03, 2.62))
	cyl(nf, "Paving", 0.5, 0.012, Vector3.ZERO, paving, 32)
	cyl(nf, "Rim", 0.38, 0.05, Vector3.ZERO, stone, 32)
	cyl(nf, "Water", 0.34, 0.055, Vector3.ZERO, water, 32)
	cyl(nf, "Column", 0.05, 0.12, Vector3(0, 0.03, 0), white, 12)
	cyl(nf, "Jet", 0.05, 0.2, Vector3(0, 0.1, 0), mat(Color(0.7, 0.9, 1.0), 0.6, 0.05, 0.0, 0.7), 10, 0.01)
	# red / white / blue flower beds inside the horseshoe
	var bed_cols := [Color(0.9, 0.12, 0.15), Color(0.97, 0.97, 0.97), Color(0.2, 0.35, 0.85)]
	for i in 3:
		for s in [-1, 1]:
			cyl(drive, "Bed%d%s" % [i, "L" if s < 0 else "R"], 0.15, 0.045, Vector3(s * (0.85 + i * 0.36), 0.03, 2.5 + i * 0.12), mat(bed_cols[i], 0.1, 1.0), 16)

	# ------------------------------------------------ the palace itself, scaled up to suit the big lot
	var palace := group(_root, "Palace")
	palace.scale = Vector3.ONE * 1.45

	# ------------------------------------------------ main residence
	var house := group(palace, "Residence")
	var hw := 2.5     # width (X)
	var hd := 1.1     # depth (Z)
	var hz := 0.1     # centre Z
	var hh := 0.62    # wall height
	var plinth := 0.08
	box(house, "Plinth", Vector3(hw + 0.08, plinth, hd + 0.08), Vector3(0, 0, hz), stone)
	box(house, "Mass", Vector3(hw, hh, hd), Vector3(0, plinth, hz), white)
	box(house, "StringCourse", Vector3(hw + 0.02, 0.025, hd + 0.02), Vector3(0, plinth + 0.27, hz), cream)
	box(house, "Cornice", Vector3(hw + 0.08, 0.04, hd + 0.08), Vector3(0, plinth + hh, hz), cream)
	collider(house, Vector3(hw, hh + plinth, hd), Vector3(0, 0, hz))
	# windows — two floors on front/back, ends too
	var rows := [plinth + 0.07, plinth + 0.36]
	windows(house, "WinFront", Vector3(0, 0, hz + hd * 0.5 + 0.006), 0, 11, hw - 0.25, rows, 0.09, 0.17, glass, white)
	windows(house, "WinBack", Vector3(0, 0, hz - hd * 0.5 - 0.006), 180, 11, hw - 0.25, rows, 0.09, 0.17, glass, white)
	windows(house, "WinLeft", Vector3(-hw * 0.5 - 0.006, 0, hz), -90, 3, hd - 0.35, rows, 0.09, 0.17, glass, white)
	windows(house, "WinRight", Vector3(hw * 0.5 + 0.006, 0, hz), 90, 3, hd - 0.35, rows, 0.09, 0.17, glass, white)
	# warm light behind the front door
	box(house, "FrontDoor", Vector3(0.14, 0.22, 0.02), Vector3(0, plinth, hz + hd * 0.5 + 0.004), glass_warm)

	# Roof: balustraded flat deck with a low hipped roof in the middle + chimneys
	var rtop := plinth + hh + 0.04
	var rf := group(house, "Roof")
	box(rf, "Deck", Vector3(hw + 0.02, 0.02, hd + 0.02), Vector3(0, rtop, hz), roof)
	balustrade(rf, "Balustrade", hw + 0.06, hd + 0.06, Vector3(0, rtop, hz), 0.07, white)
	# low hipped roof panels either side of the central seal
	for s in [-1, 1]:
		prism(rf, "Hip%s" % ("L" if s < 0 else "R"), Vector3(hd - 0.3, 0.12, 0.55), Vector3(s * 0.85, rtop + 0.02, hz), roof_dark, 90)
	for i in 4:
		var cx: float = [-1.05, -0.5, 0.5, 1.05][i]
		for s in [-1, 1]:
			box(rf, "Chimney%d%s" % [i, "F" if s > 0 else "B"], Vector3(0.09, 0.14, 0.06), Vector3(cx, rtop, hz + s * (hd * 0.5 - 0.1)), white)
	# Presidential seal on the roof deck (navy disc, gold ring, gold star) — the "from above" read
	var seal := group(rf, "Seal", Vector3(0, rtop + 0.022, hz))
	# layers stepped well apart so they don't z-fight from the high overview camera
	cyl(seal, "Ring", 0.36, 0.012, Vector3.ZERO, gold, 40)
	cyl(seal, "Disc", 0.31, 0.012, Vector3(0, 0.008, 0), navy, 40)
	cyl(seal, "InnerRing", 0.25, 0.012, Vector3(0, 0.016, 0), gold, 40)
	cyl(seal, "InnerDisc", 0.225, 0.012, Vector3(0, 0.024, 0), navy, 40)
	star_flat(seal, "Star", Vector3(0, 0.038, 0), 0.2, gold)
	for i in 12:
		var a := i * TAU / 12.0
		cyl(seal, "Dot%d" % i, 0.016, 0.02, Vector3(cos(a) * 0.28, 0.008, sin(a) * 0.28), mat(Color(1, 1, 1), 0.6), 6)
	# Flag on the roof above the north portico
	var flag := group(rf, "Flag", Vector3(0, rtop, hz + hd * 0.5 - 0.12))
	cyl(flag, "Pole", 0.012, 0.55, Vector3.ZERO, white, 8)
	cyl(flag, "Finial", 0.022, 0.03, Vector3(0, 0.55, 0), gold, 8)
	var cloth := group(flag, "Cloth", Vector3(0, 0.36, 0), -25)
	for i in 5:
		box(cloth, "Stripe%d" % i, Vector3(0.36, 0.036, 0.008), Vector3(0.19, i * 0.036, 0), red if i % 2 == 0 else white)
	box(cloth, "Canton", Vector3(0.15, 0.108, 0.01), Vector3(0.085, 0.072, 0), navy)
	box(cloth, "CantonStar", Vector3(0.04, 0.04, 0.012), Vector3(0.085, 0.106, 0), white, Vector3(0, 0, 45))

	# ------------------------------------------------ north portico (front, square, pediment)
	var np := group(palace, "NorthPortico", Vector3(0, 0, hz + hd * 0.5))
	box(np, "Steps1", Vector3(1.0, 0.03, 0.48), Vector3(0, 0, 0.2), stone)
	box(np, "Steps2", Vector3(0.94, 0.03, 0.44), Vector3(0, 0.03, 0.19), stone)
	box(np, "Floor", Vector3(0.88, 0.03, 0.4), Vector3(0, 0.06, 0.18), cream)
	colonnade(np, "FrontCols", Vector3(0, 0.08, 0.34), 4, 0.72, 0.035, hh - 0.04, white, cream)
	colonnade(np, "BackCols", Vector3(0, 0.08, 0.14), 4, 0.72, 0.03, hh - 0.04, white, cream)
	box(np, "Entablature", Vector3(0.94, 0.07, 0.44), Vector3(0, plinth + hh - 0.04, 0.2), cream)
	prism(np, "Pediment", Vector3(0.98, 0.2, 0.46), Vector3(0, plinth + hh + 0.03, 0.2), white)
	# Pediment roof slopes (grey) so it pops from above
	prism(np, "PedimentRoof", Vector3(1.03, 0.22, 0.42), Vector3(0, plinth + hh + 0.03, 0.18), roof_dark)
	box(np, "Lantern", Vector3(0.05, 0.06, 0.05), Vector3(0, plinth + hh - 0.14, 0.26), mat(Color(1, 0.88, 0.6), 2.5))

	# ------------------------------------------------ south portico (back, semicircular)
	var sp := group(palace, "SouthPortico", Vector3(0, 0, hz - hd * 0.5))
	cyl(sp, "Steps", 0.56, 0.03, Vector3(0, 0, 0), stone, 32)
	cyl(sp, "Floor", 0.5, 0.06, Vector3(0, 0, 0), cream, 32)
	for i in 6:
		var a := PI + PI * (i + 0.5) / 6.0  # back half only
		cyl(sp, "Col%d" % i, 0.035, hh - 0.02, Vector3(cos(a) * 0.43, 0.06, sin(a) * 0.43), white, 12)
	# second floor balcony + roof cap
	cyl(sp, "Balcony", 0.49, 0.03, Vector3(0, plinth + 0.3, 0), cream, 32)
	cyl(sp, "Roof", 0.5, 0.05, Vector3(0, plinth + hh - 0.01, 0), cream, 32)
	cyl(sp, "RoofTop", 0.46, 0.02, Vector3(0, plinth + hh + 0.04, 0), roof, 32)
	# the front half of these discs sits inside the house mass, so only the bow shows

	# ------------------------------------------------ wings: colonnades + East / West Wing
	var wings := group(palace, "Wings")
	for s in [-1, 1]:
		var side := "W" if s < 0 else "E"
		# low colonnaded terrace linking to the wing
		var cx: float = s * (hw * 0.5 + 0.35)
		box(wings, "Terrace%s" % side, Vector3(0.7, 0.28, 0.42), Vector3(cx, 0, hz - 0.12), white)
		box(wings, "TerraceRoof%s" % side, Vector3(0.74, 0.03, 0.46), Vector3(cx, 0.28, hz - 0.12), roof)
		colonnade(wings, "TerraceCols%s" % side, Vector3(cx, 0, hz - 0.12 - 0.24), 5, 0.6, 0.02, 0.28, white, cream)
		# the wing building
		var wx: float = s * (hw * 0.5 + 0.95)
		box(wings, "Wing%s" % side, Vector3(0.55, 0.36, 0.95), Vector3(wx, 0, hz - 0.05), white)
		box(wings, "WingCornice%s" % side, Vector3(0.59, 0.03, 0.99), Vector3(wx, 0.36, hz - 0.05), cream)
		box(wings, "WingRoof%s" % side, Vector3(0.53, 0.02, 0.93), Vector3(wx, 0.39, hz - 0.05), roof)
		prism(wings, "WingHip%s" % side, Vector3(0.38, 0.1, 0.7), Vector3(wx, 0.41, hz - 0.05), roof_dark)
		windows(wings, "WingWin%s" % side, Vector3(wx, 0, hz - 0.05 + 0.481), 0, 3, 0.36, [0.1], 0.07, 0.14, glass, white)
		windows(wings, "WingWinSide%s" % side, Vector3(wx + s * 0.281, 0, hz - 0.05), s * 90, 4, 0.7, [0.1], 0.07, 0.14, glass, white)
		collider(wings, Vector3(0.55, 0.36, 0.95), Vector3(wx, 0, hz - 0.05))
		# porch on the wing entrance
		box(wings, "WingPorch%s" % side, Vector3(0.3, 0.03, 0.12), Vector3(wx, 0.24, hz + 0.48), white)
		for px in [-0.12, 0.12]:
			box(wings, "WingPorchPost%s" % side, Vector3(0.025, 0.24, 0.025), Vector3(wx + px, 0, hz + 0.53), white)
	# Oval Office bump on the West Wing's south side
	var oval := cyl(wings, "OvalOffice", 0.22, 0.34, Vector3(-(hw * 0.5 + 0.95), 0, hz - 0.58), white, 28)
	oval.scale = Vector3(1.0, 1.0, 0.75)
	var oval_roof := cyl(wings, "OvalOfficeRoof", 0.235, 0.03, Vector3(-(hw * 0.5 + 0.95), 0.34, hz - 0.58), cream, 28)
	oval_roof.scale = Vector3(1.0, 1.0, 0.75)
	for i in 5:
		var a := PI * 0.15 + PI * 0.7 * i / 4.0
		box(wings, "OvalWin%d" % i, Vector3(0.06, 0.14, 0.02), Vector3(-(hw * 0.5 + 0.95) + cos(a) * 0.222, 0.1, hz - 0.58 - sin(a) * 0.168), glass).rotation.y = -a + PI * 0.5
	# Rose Garden (between West Wing and residence, south side)
	var rg := group(palace, "RoseGarden", Vector3(-(hw * 0.5 + 0.3), 0.03, hz - 0.85))
	box(rg, "Lawn", Vector3(0.6, 0.006, 0.4), Vector3.ZERO, lawn_light)
	for i in 6:
		cyl(rg, "Rose%d" % i, 0.05, 0.05, Vector3(-0.24 + (i % 3) * 0.24, 0.0, -0.15 if i < 3 else 0.15), mat(Color(0.92, 0.2, 0.35), 0.15, 1.0), 10)
	box(rg, "HedgeN", Vector3(0.64, 0.06, 0.04), Vector3(0, 0, 0.22), hedge)
	box(rg, "HedgeS", Vector3(0.64, 0.06, 0.04), Vector3(0, 0, -0.22), hedge)


	# ------------------------------------------------ south lawn: ellipse, fountain
	var sl := group(_root, "SouthLawn")
	var ell_c := Vector2(0, -2.3)
	arc(sl, "Ellipse", ell_c, Vector2(2.3, 0.56), 0.0, TAU, 40, 0.1, 0.008, 0.031, paving)
	strip(sl, "PorticoPath", Vector2(0, -1.45), Vector2(0, ell_c.y + 0.56), 0.18, 0.008, 0.031, paving)
	var sf := group(sl, "SouthFountain", Vector3(ell_c.x, 0.03, ell_c.y))
	cyl(sf, "Rim", 0.4, 0.05, Vector3.ZERO, stone, 32)
	cyl(sf, "Water", 0.36, 0.055, Vector3.ZERO, water, 32)
	cyl(sf, "Column", 0.05, 0.12, Vector3(0, 0.03, 0), white, 12)
	cyl(sf, "Jet", 0.06, 0.22, Vector3(0, 0.1, 0), mat(Color(0.7, 0.9, 1.0), 0.6, 0.05, 0.0, 0.7), 10, 0.01)
	arc(sl, "HedgeRing", ell_c, Vector2(2.7, 0.76), PI * 0.6, PI * 2.4, 40, 0.08, 0.09, 0.03, hedge)
	for s in [-1, 1]:
		inst(sl, BENCH, "Bench%s" % ("L" if s < 0 else "R"), Vector3(s * 1.2, 0.03, ell_c.y), 90 * s, 0.8)

	# ------------------------------------------------ west side: helipad + helicopter
	var hp := group(_root, "Helipad", Vector3(-4.35, 0.03, -1.75))
	cyl(hp, "Deck", 0.62, 0.012, Vector3.ZERO, tarmac, 36)
	cyl(hp, "Ring", 0.54, 0.014, Vector3.ZERO, white, 36)
	cyl(hp, "Inner", 0.49, 0.016, Vector3.ZERO, tarmac, 36)
	label(hp, "H", "H", Vector3(0, 0.02, 0), 0.012, Color.WHITE, Color.WHITE, Vector3(-90, 0, 0), 2)
	for a in 10:
		var ang := a * TAU / 10.0
		cyl(hp, "Lamp%d" % a, 0.02, 0.03, Vector3(cos(ang) * 0.59, 0, sin(ang) * 0.59), mat(Color(0.2, 1, 0.3), 3.0), 8)
	helicopter(_root, "Helicopter", Vector3(-4.35, 0.045, -1.78), -30)
	strip(_root, "HeliPath", Vector2(-3.73, -1.75), Vector2(-2.9, -1.3), 0.14, 0.008, 0.031, paving)

	# ------------------------------------------------ east side: tennis court
	var tc := group(_root, "TennisCourt", Vector3(4.35, 0.03, -1.75))
	box(tc, "Apron", Vector3(1.0, 0.01, 1.55), Vector3.ZERO, mat(Color(0.75, 0.32, 0.25), 0.0, 0.9))
	box(tc, "Court", Vector3(0.72, 0.012, 1.27), Vector3.ZERO, mat(Color(0.22, 0.45, 0.7), 0.0, 0.9))
	var line := mat(Color(0.97, 0.97, 0.97), 0.0, 0.8)
	for x in [-0.36, 0.36, -0.27, 0.27]:
		box(tc, "SideLine", Vector3(0.012, 0.014, 1.27), Vector3(x, 0, 0), line)
	for z in [-0.635, 0.635, -0.34, 0.34]:
		box(tc, "BaseLine", Vector3(0.72 if abs(z) > 0.5 else 0.54, 0.014, 0.012), Vector3(0, 0, z), line)
	box(tc, "CentreLine", Vector3(0.012, 0.014, 0.68), Vector3(0, 0, 0), line)
	box(tc, "Net", Vector3(0.82, 0.05, 0.01), Vector3(0, 0.01, 0), mat(Color(0.1, 0.1, 0.1), 0.0, 0.6))

	# ------------------------------------------------ side parterre gardens (hedge squares + flowers)
	for s in [-1, 1]:
		var pg := group(_root, "Parterre%s" % ("W" if s < 0 else "E"), Vector3(s * 4.35, 0.03, 0.45))
		box(pg, "Gravel", Vector3(1.3, 0.008, 1.3), Vector3.ZERO, gravel)
		for ix in 2:
			for iz in 2:
				var c := Vector3(-0.3 + ix * 0.6, 0, -0.3 + iz * 0.6)
				box(pg, "HedgeA%d%d" % [ix, iz], Vector3(0.5, 0.07, 0.06), c + Vector3(0, 0, 0.22), hedge)
				box(pg, "HedgeB%d%d" % [ix, iz], Vector3(0.5, 0.07, 0.06), c + Vector3(0, 0, -0.22), hedge)
				box(pg, "HedgeC%d%d" % [ix, iz], Vector3(0.06, 0.07, 0.5), c + Vector3(0.22, 0, 0), hedge)
				box(pg, "HedgeD%d%d" % [ix, iz], Vector3(0.06, 0.07, 0.5), c + Vector3(-0.22, 0, 0), hedge)
				cyl(pg, "Bloom%d%d" % [ix, iz], 0.15, 0.05, c, mat(bed_cols[(ix + iz + (1 if s > 0 else 0)) % 3], 0.1, 1.0), 14)
		inst(pg, PLANTER, "Urn", Vector3(0, 0, 0), 0, 0.55)

	# ------------------------------------------------ motorcade on the drive in front of the portico
	suv(_root, "StateCar", Vector3(0.35, 0.04, 1.85), 90, true)
	suv(_root, "Escort1", Vector3(-0.5, 0.04, 1.85), 90)
	suv(_root, "Escort2", Vector3(1.75, 0.04, 2.2), 40)
	suv(_root, "Escort3", Vector3(-1.75, 0.04, 2.2), -40)

	# ------------------------------------------------ trees, lamps, planters
	var trees := group(_root, "Trees")
	var tree_pts := []
	for i in 9:   # back avenue
		var x := -4.9 + i * 1.225
		if abs(x) > 2.9:
			tree_pts.append([TREE_ROUND if i % 2 == 0 else TREE_CONE, Vector3(x, 0.03, -2.95)])
	for x in [-4.95, -3.75, 3.75, 4.95]:   # front corners
		tree_pts.append([TREE_ROUND, Vector3(x, 0.03, 2.9)])
		tree_pts.append([TREE_CONE, Vector3(x, 0.03, 1.95)])
	for z in [-0.75, 1.3]:   # side rows
		tree_pts.append([TREE_ROUND, Vector3(-4.95, 0.03, z)])
		tree_pts.append([TREE_ROUND, Vector3(4.95, 0.03, z)])
	for x in [-3.15, 3.15]:   # flank the wings
		tree_pts.append([TREE_CONE, Vector3(x, 0.03, 1.35)])
		tree_pts.append([TREE_ROUND, Vector3(x, 0.03, -2.0)])
	for i in tree_pts.size():
		inst(trees, tree_pts[i][0], "Tree%d" % i, tree_pts[i][1], i * 37.0, 1.25)
	for i in 4:
		var x: float = [-1.4, -0.7, 0.7, 1.4][i]
		inst(_root, PLANTER, "Planter%d" % i, Vector3(x, 0.03, 1.6), 0, 0.55)
	var lamp_pts := [Vector3(-3.2, 0.03, 2.5), Vector3(3.2, 0.03, 2.5), Vector3(-1.4, 0.03, 1.55), Vector3(1.4, 0.03, 1.55),
		Vector3(-0.35, 0.03, -1.55), Vector3(0.35, 0.03, -1.55)]
	for i in lamp_pts.size():
		inst(_root, STREETLIGHT, "Lamp%d" % i, lamp_pts[i], 0, 0.7)

	# Name plate facing the park (small, so the roof seal stays the main read)
	box(_root, "NameStone", Vector3(1.2, 0.14, 0.06), Vector3(1.15, 0.03, FZ + 0.12), stone)
	label(_root, "NameSign", "PRESIDENTIAL PALACE", Vector3(1.15, 0.11, FZ + 0.155), 0.0032, Color(0.75, 0.6, 0.15), Color(0.1, 0.1, 0.1), Vector3.ZERO, 4)
	return _root
