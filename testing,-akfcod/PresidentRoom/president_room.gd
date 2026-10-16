@tool
class_name PresidentRoom
extends Node3D
## The president's office: the room the player sits in while playing.
##
## Self-contained: everything lives in this folder and nothing else in the
## project is touched or needed. The whole room is built from code out of
## boxes, cylinders and Label3D, the same way City/Civic/builder.gd builds the
## civic buildings, with the same flat-colour materials and city palette.
##
## Use it: instance president_room.tscn (or add a PresidentRoom node) and run.
## F6 on president_room.tscn shows it on its own.
##
## Layout (1 unit = 1 metre, room centred on X):
##   The player sits in the desk chair at EYE, looking toward -Z.
##   In front: the desk with a paper on it, then the rug with the seal,
##   two sofas, the main double door, bookcases and the fireplace.
##   Behind (turn around): three tall windows with curtains and two flags.
##
## Hold the right mouse button and move the mouse to look around from the chair.
##
## Visitors: while the game runs, aides, Secret Service agents, generals,
## staffers and a steward come in through the main door and the side door,
## do something (brief the president, stand guard, browse the books, warm up
## at the fire, look at a painting, bring coffee) and leave again. The doors
## swing open for them; a hallway lies behind the main door and an anteroom
## behind the side door. See office_traffic.gd and office_visitor.gd.
##
## Hooks for combining later:
##   camera            the seated first-person Camera3D
##   paper             the paper Node3D on the desk (top surface at y = 0)
##   set_paper_text()  show a directive on the paper
##   use_own_environment = false  when the main scene already has a WorldEnvironment
##   traffic           the visitor director (null in the editor or when visitors are off)
##   set_door_open()   swing a door ("MainDoor" / "SideDoor") between 0 (shut) and 1 (open)

@export var use_own_environment := true:
	set(v):
		use_own_environment = v
		_queue_rebuild()
## Heading printed at the top of the paper.
@export var paper_title := "DIRECTIVE":
	set(v):
		paper_title = v
		_queue_rebuild()
## Body text on the paper. Empty shows placeholder lines instead.
@export_multiline var paper_text := "":
	set(v):
		paper_text = v
		_queue_rebuild()

@export_group("Seated look")
@export var mouse_look := true
@export var mouse_sensitivity := 0.2
## How far the head can turn left/right from the desk (degrees).
@export var max_yaw := 170.0
@export var base_pitch := -24.0
@export var max_pitch_up := 40.0
@export var max_pitch_down := 30.0
@export var fov := 62.0

@export_group("Visitors")
## People walk in through the doors, do something and leave (only while the game runs).
@export var visitors_enabled := true
## Most visitors in the room (and its doorways) at once.
@export_range(1, 6) var max_visitors := 3
## Seconds between one visitor arriving and the next (random in this range).
@export var visitor_interval := Vector2(5.0, 11.0)

# ---------------------------------------------------------------- layout

const W := 9.0            # room width (x from -4.5 to 4.5)
const Z_FRONT := -5.5     # wall the player faces (main door)
const Z_BACK := 2.8       # wall behind the player (windows)
const H := 3.8            # ceiling height
const ZC := (Z_FRONT + Z_BACK) * 0.5
const DEPTH := Z_BACK - Z_FRONT
const DESK_Z := 0.35      # desk centre
const DESK_TOP := 0.78    # desk writing surface height
const EYE := Vector3(0.0, 1.22, 1.38)
## The chair back is on its own render layer and the seated camera skips it,
## so turning around shows the windows instead of the inside of the chair.
const CHAIR_BACK_LAYER := 1 << 19

# ---------------------------------------------------------------- colours
# Flat colours like the civic buildings, plus the city palette (weathering.gd).

const WALL := Color(0.94, 0.88, 0.71)
const TRIM := Color(0.96, 0.95, 0.91)
const TRIM_SHADE := Color(0.88, 0.86, 0.8)
const WOOD := Color(0.38, 0.21, 0.12)
const WOOD_DARK := Color(0.22, 0.12, 0.07)
const WOOD_LIGHT := Color(0.5, 0.3, 0.17)
const FLOOR_A := Color(0.56, 0.37, 0.21)
const FLOOR_B := Color(0.5, 0.32, 0.18)
const GOLD := Color(0.95, 0.75, 0.2)
const NAVY := Color(0.07, 0.16, 0.42)
const CURTAIN := Color(0.63, 0.14, 0.16)
const CURTAIN_FOLD := Color(0.5, 0.1, 0.12)
const LEATHER := Color(0.3, 0.12, 0.09)
const SOFA := Color(0.84, 0.75, 0.55)
const SOFA_CUSHION := Color(0.9, 0.82, 0.62)
const MARBLE := Color(0.9, 0.89, 0.86)
const MARBLE_DARK := Color(0.2, 0.2, 0.22)
const PAPER := Color(0.98, 0.97, 0.93)
const INK := Color(0.1, 0.1, 0.14)
const SKY := Color(0.62, 0.78, 0.95)
const HEDGE := Color(0.38, 0.6, 0.34)

const PALETTE := [
	Color8(97, 203, 140),   # mint green
	Color8(33, 141, 109),   # deep green
	Color8(255, 192, 68),   # sunflower yellow
	Color8(255, 154, 50),   # amber
	Color8(254, 127, 68),   # orange
	Color8(245, 104, 67),   # coral
	Color8(208, 83, 80),    # brick red
	Color8(102, 148, 217),  # sky blue
	Color8(90, 95, 200),    # indigo
]

# ---------------------------------------------------------------- state

var camera: Camera3D
var paper: Node3D
var traffic: Node3D
## Door name -> {"leaves": [hinge Node3D], "signs": [+1/-1], "node": door Node3D, "amount": 0..1}
var doors := {}

var _built: Node3D
var _mats := {}
var _yaw := 0.0
var _pitch := 0.0
var _fire_light: OmniLight3D
var _fire_flames: Array[Node3D] = []
var _t := 0.0
var _rebuild_queued := false


func _ready() -> void:
	_rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if _built and is_instance_valid(_built):
		remove_child(_built)
		_built.free()
	_mats.clear()
	_fire_flames.clear()
	doors.clear()
	traffic = null
	# Built nodes get no owner, so they are never written into the .tscn.
	_built = Node3D.new()
	_built.name = "Built"
	add_child(_built)

	if use_own_environment:
		_build_environment()
	_build_floor()
	_build_ceiling()
	_build_walls()
	_build_windows()
	_build_flags()
	_build_front_door()
	_build_bookcases()
	_build_fireplace()
	_build_side_wall_details()
	_build_rug()
	_build_sofas()
	_build_coffee_table()
	_build_chandelier()
	_build_desk()
	_build_desk_items()
	_build_paper()
	_build_chair()
	_build_lights()
	_build_halls()
	_build_camera()
	if visitors_enabled and not Engine.is_editor_hint():
		var t = (load("res://PresidentRoom/office_traffic.gd") as GDScript).new()
		t.name = "Visitors"
		_built.add_child(t)
		t.setup(self)
		traffic = t


# ---------------------------------------------------------------- public

## Swing a door: 0 = shut, 1 = wide open (into the room).
func set_door_open(door_name: String, amount: float) -> void:
	if not doors.has(door_name):
		return
	var d: Dictionary = doors[door_name]
	d.amount = clampf(amount, 0.0, 1.0)
	var a := deg_to_rad(DOOR_SWING) * smoothstep(0.0, 1.0, d.amount)
	for i in d.leaves.size():
		(d.leaves[i] as Node3D).rotation.y = a * float(d.signs[i])


func door_amount(door_name: String) -> float:
	return doors[door_name].amount if doors.has(door_name) else 0.0


func set_paper_text(text: String, title := "") -> void:
	paper_text = text
	if title != "":
		paper_title = title


func reset_view() -> void:
	_yaw = 0.0
	_pitch = base_pitch
	if camera:
		camera.rotation_degrees = Vector3(_pitch, _yaw, 0.0)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not mouse_look or camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw = clampf(_yaw - event.relative.x * mouse_sensitivity, -max_yaw, max_yaw)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
			base_pitch - max_pitch_down, base_pitch + max_pitch_up)
		camera.rotation_degrees = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _fire_light == null:
		return
	_t += delta
	var f := 0.5 + 0.5 * sin(_t * 9.0) * sin(_t * 3.7 + 1.3)
	_fire_light.light_energy = 1.0 + 0.45 * f
	for i in _fire_flames.size():
		var fl := _fire_flames[i]
		fl.scale.y = 0.85 + 0.3 * absf(sin(_t * (6.0 + i * 1.7) + i))


# ---------------------------------------------------------------- helpers
# Same conventions as City/Civic/builder.gd.

func mat(color: Color, emit := 0.0, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), emit, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func gold() -> StandardMaterial3D:
	return mat(GOLD, 0.0, 0.35, 0.5)


func group(parent: Node, n: String, pos := Vector3.ZERO, rot_y := 0.0) -> Node3D:
	var g := Node3D.new()
	g.name = n
	g.position = pos
	g.rotation_degrees.y = rot_y
	parent.add_child(g)
	return g


## Box whose BOTTOM sits at pos.y (easier stacking).
func box(parent: Node, n: String, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## Upright cylinder whose BOTTOM sits at pos.y.
func cyl(parent: Node, n: String, r: float, h: float, pos: Vector3, m: Material, segs := 24, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
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
	return mi


## Flat disc standing up and facing +Z, centred at pos.
func disc(parent: Node, n: String, r: float, thick: float, pos: Vector3, m: Material, segs := 32) -> MeshInstance3D:
	var mi := cyl(parent, n, r, thick, Vector3.ZERO, m, segs)
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	return mi


func sph(parent: Node, n: String, r: float, pos: Vector3, m: Material, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(segs / 2, 4)
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func label(parent: Node, n: String, text: String, pos: Vector3, px: float, color: Color,
		outline := Color.BLACK, rot := Vector3.ZERO, outline_size := 8) -> Label3D:
	var l := Label3D.new()
	l.name = n
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
	return l


func no_shadow(mi: GeometryInstance3D) -> GeometryInstance3D:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Thin rectangular outline (picture moulding / frame) facing +Z.
## centre = middle of the rectangle.
func outline_rect(parent: Node, n: String, centre: Vector3, w: float, h: float, bar: float, depth: float, m: Material) -> Node3D:
	var g := group(parent, n, centre)
	box(g, "T", Vector3(w, bar, depth), Vector3(0, h * 0.5 - bar, 0), m)
	box(g, "B", Vector3(w, bar, depth), Vector3(0, -h * 0.5, 0), m)
	box(g, "L", Vector3(bar, h - bar * 2.0, depth), Vector3(-w * 0.5 + bar * 0.5, -h * 0.5 + bar, 0), m)
	box(g, "R", Vector3(bar, h - bar * 2.0, depth), Vector3(w * 0.5 - bar * 0.5, -h * 0.5 + bar, 0), m)
	return g


## A run of boxes along local X from -length/2 to length/2, skipping the
## cuts (Array of Vector2(start_x, end_x)). Bottom at y, centred on z.
func _strip(parent: Node, n: String, length: float, size_y: float, size_z: float, y: float, z: float,
		m: Material, cuts: Array) -> void:
	var sorted := cuts.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var x0 := -length * 0.5
	var segs: Array[Vector2] = []
	for c: Vector2 in sorted:
		if c.x > x0:
			segs.append(Vector2(x0, c.x))
		x0 = maxf(x0, c.y)
	if x0 < length * 0.5:
		segs.append(Vector2(x0, length * 0.5))
	for i in segs.size():
		var s := segs[i]
		var nm := n if segs.size() == 1 else "%s%d" % [n, i]
		box(parent, nm, Vector3(s.y - s.x, size_y, size_z), Vector3((s.x + s.y) * 0.5, y, z), m)


func _in_gaps(x: float, half: float, gaps: Array) -> bool:
	for gp: Vector2 in gaps:
		if absf(x - gp.x) < gp.y + half:
			return true
	return false


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.96, 0.91, 0.82)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_built.add_child(we)


# ---------------------------------------------------------------- shell

func _build_floor() -> void:
	var g := group(_built, "Floor")
	box(g, "Base", Vector3(W, 0.1, DEPTH), Vector3(0, -0.12, ZC), mat(WOOD_DARK))
	var plank := 0.3
	var n := roundi(W / plank)
	for i in n:
		var x := -W * 0.5 + plank * 0.5 + i * plank
		var c := FLOOR_A if i % 2 == 0 else FLOOR_B
		box(g, "Plank%d" % i, Vector3(plank - 0.006, 0.02, DEPTH), Vector3(x, -0.02, ZC), mat(c, 0.0, 0.55))


func _build_ceiling() -> void:
	var g := group(_built, "Ceiling")
	box(g, "Slab", Vector3(W, 0.1, DEPTH), Vector3(0, H, ZC), mat(TRIM, 0.0, 0.9))
	# shallow coffers
	var beam := mat(TRIM_SHADE, 0.0, 0.9)
	for x in [-1.5, 1.5]:
		box(g, "BeamZ", Vector3(0.22, 0.12, DEPTH), Vector3(x, H - 0.12, ZC), beam)
	for z in [-3.2, 0.6]:
		box(g, "BeamX", Vector3(W, 0.12, 0.22), Vector3(0, H - 0.12, z), beam)
	# medallion above the chandelier
	cyl(g, "Medallion", 0.5, 0.04, Vector3(0, H - 0.04, -2.0), mat(TRIM), 32)
	cyl(g, "MedallionRing", 0.32, 0.05, Vector3(0, H - 0.05, -2.0), gold(), 32)


## One wall. Built in local space along X, inner face at z = 0 facing local +Z.
## gaps: Array of Vector2(centre_x, half_width) where no panels are drawn.
## openings: Array of Vector3(centre_x, half_width, height) cut right through the
## wall (doorways). with_body = false leaves out the plaster body, for the far
## face of a wall that another wall already supplies.
func wall(n: String, length: float, pos: Vector3, rot_y: float, gaps: Array = [],
		openings: Array = [], with_body := true) -> Node3D:
	var g := group(_built, n, pos, rot_y)
	var cuts := []
	for o: Vector3 in openings:
		cuts.append(Vector2(o.x - o.y, o.x + o.y))
	if with_body:
		_strip(g, "Body", length, H, 0.2, 0.0, -0.1, mat(WALL, 0.0, 0.9), cuts)
		for i in openings.size():
			var o: Vector3 = openings[i]
			box(g, "Lintel%d" % i, Vector3(o.y * 2.0, H - o.z, 0.2), Vector3(o.x, o.z, -0.1), mat(WALL, 0.0, 0.9))
	_strip(g, "Wainscot", length, 1.0, 0.03, 0.0, 0.015, mat(TRIM, 0.0, 0.7), cuts)
	_strip(g, "ChairRail", length, 0.06, 0.06, 0.97, 0.03, mat(TRIM, 0.0, 0.6), cuts)
	_strip(g, "Baseboard", length, 0.16, 0.05, 0.0, 0.035, mat(WOOD_DARK, 0.0, 0.6), cuts)
	box(g, "Crown", Vector3(length, 0.16, 0.12), Vector3(0, H - 0.16, 0.06), mat(TRIM, 0.0, 0.7))
	box(g, "CrownStep", Vector3(length, 0.05, 0.18), Vector3(0, H - 0.21, 0.09), mat(TRIM, 0.0, 0.7))
	box(g, "CrownGold", Vector3(length, 0.025, 0.13), Vector3(0, H - 0.24, 0.065), gold())
	var step := 1.1
	var count := int(floor(length / step))
	var start := -count * step * 0.5 + step * 0.5
	for i in count:
		var x := start + i * step
		if _in_gaps(x, 0.45, gaps):
			continue
		box(g, "Panel%d" % i, Vector3(0.8, 0.6, 0.02), Vector3(x, 0.2, 0.04), mat(TRIM_SHADE, 0.0, 0.7))
		outline_rect(g, "Moulding%d" % i, Vector3(x, 2.2, 0.01), 0.8, 1.9, 0.035, 0.025, mat(TRIM, 0.0, 0.7))
	return g


var _front: Node3D
var _back: Node3D
var _left: Node3D
var _right: Node3D

# Local x on each wall, by world coordinate:
#   front (rot 0):    lx =  world x
#   back  (rot 180):  lx = -world x
#   left  (rot 90):   lx = ZC - world z
#   right (rot -90):  lx = world z - ZC

const WINDOW_XS := [-2.7, 0.0, 2.7]
const WINDOW_W := 1.3
const BOOKCASE_XS := [-2.75, 2.75]
const FIREPLACE_Z := -3.7
const SIDE_DOOR_Z := -4.4
const MAIN_DOOR_W := 1.7
const MAIN_DOOR_H := 2.7
const SIDE_DOOR_W := 1.0
const SIDE_DOOR_H := 2.5
## How far the door leaves swing open (degrees).
const DOOR_SWING := 92.0
## The doorway is this much wider/taller than the leaves; the jambs fill it.
const DOOR_REVEAL := 0.04

func _build_walls() -> void:
	var back_gaps := []
	for x in WINDOW_XS:
		back_gaps.append(Vector2(x, WINDOW_W * 0.5 + 0.45))
	var front_gaps := [Vector2(0, 1.0)]
	for x in BOOKCASE_XS:
		front_gaps.append(Vector2(x, 0.8))
	_front = wall("WallFront", W, Vector3(0, 0, Z_FRONT), 0.0, front_gaps,
		[Vector3(0.0, MAIN_DOOR_W * 0.5 + DOOR_REVEAL, MAIN_DOOR_H + DOOR_REVEAL)])
	_back = wall("WallBack", W, Vector3(0, 0, Z_BACK), 180.0, back_gaps)
	_left = wall("WallLeft", DEPTH, Vector3(-W * 0.5, 0, ZC), 90.0,
		[Vector2(ZC - FIREPLACE_Z, 1.0), Vector2(ZC - 0.0, 0.35)])
	_right = wall("WallRight", DEPTH, Vector3(W * 0.5, 0, ZC), -90.0,
		[Vector2(SIDE_DOOR_Z - ZC, 0.7), Vector2(-2.6 - ZC, 0.75)],
		[Vector3(SIDE_DOOR_Z - ZC, SIDE_DOOR_W * 0.5 + DOOR_REVEAL, SIDE_DOOR_H + DOOR_REVEAL)])


# ---------------------------------------------------------------- windows (behind the player)

func _build_windows() -> void:
	var sill_y := 1.0
	var h := 2.1
	var w: float = WINDOW_W
	var glass := mat(SKY, 1.1, 0.1)
	var hedge := mat(HEDGE, 0.5, 0.8)
	var white := mat(TRIM, 0.0, 0.6)
	for i in WINDOW_XS.size():
		var lx: float = WINDOW_XS[i]
		var g := group(_back, "Window%d" % i, Vector3(lx, 0, 0))
		no_shadow(box(g, "Glass", Vector3(w, h, 0.02), Vector3(0, sill_y, 0.012), glass))
		no_shadow(box(g, "Garden", Vector3(w, 0.55, 0.01), Vector3(0, sill_y, 0.024), hedge))
		# casing
		box(g, "CasingL", Vector3(0.12, h + 0.12, 0.07), Vector3(-w * 0.5 - 0.06, sill_y, 0.035), white)
		box(g, "CasingR", Vector3(0.12, h + 0.12, 0.07), Vector3(w * 0.5 + 0.06, sill_y, 0.035), white)
		box(g, "CasingTop", Vector3(w + 0.36, 0.14, 0.09), Vector3(0, sill_y + h, 0.045), white)
		box(g, "Sill", Vector3(w + 0.3, 0.06, 0.2), Vector3(0, sill_y - 0.04, 0.1), white)
		# muntins
		box(g, "MuntinV", Vector3(0.04, h, 0.03), Vector3(0, sill_y, 0.035), white)
		for r in 3:
			box(g, "MuntinH%d" % r, Vector3(w, 0.04, 0.03), Vector3(0, sill_y + h * (r + 1) / 4.0 - 0.02, 0.035), white)
		# curtains
		for side in [-1.0, 1.0]:
			var cx: float = side * (w * 0.5 + 0.26)
			var c := group(g, "Curtain%s" % ("L" if side < 0 else "R"), Vector3(cx, 0, 0.17))
			box(c, "Cloth", Vector3(0.42, 2.95, 0.08), Vector3(0, 0.5, 0), mat(CURTAIN, 0.0, 0.95))
			for f in 3:
				box(c, "Fold%d" % f, Vector3(0.05, 2.95, 0.1), Vector3(-0.14 + f * 0.14, 0.5, 0), mat(CURTAIN_FOLD, 0.0, 0.95))
			box(c, "Tieback", Vector3(0.46, 0.06, 0.13), Vector3(0, 1.3, 0), gold())
		box(g, "Valance", Vector3(w + 1.1, 0.34, 0.16), Vector3(0, 3.15, 0.18), mat(CURTAIN, 0.0, 0.95))
		box(g, "Fringe", Vector3(w + 1.12, 0.05, 0.17), Vector3(0, 3.12, 0.18), gold())


func _build_flags() -> void:
	# Two flags on stands between the windows, behind the desk chair.
	for i in 2:
		var x := -1.35 if i == 0 else 1.35
		var g := group(_built, "Flag%d" % i, Vector3(x, 0, Z_BACK - 0.4))
		cyl(g, "Base", 0.18, 0.06, Vector3.ZERO, gold(), 24, 0.14)
		cyl(g, "Pole", 0.02, 2.6, Vector3(0, 0.06, 0), mat(WOOD_DARK, 0.0, 0.5))
		sph(g, "Finial", 0.05, Vector3(0, 2.72, 0), gold())
		box(g, "Crossbar", Vector3(0.8, 0.025, 0.025), Vector3(0, 2.5, 0), gold())
		var cloth := group(g, "Cloth", Vector3(0, 0, -0.03))
		if i == 0:
			# national flag: indigo with a sunflower band and a white disc
			box(cloth, "Field", Vector3(0.76, 1.3, 0.015), Vector3(0, 1.2, 0), mat(PALETTE[8], 0.0, 0.95))
			box(cloth, "Band", Vector3(0.76, 0.3, 0.017), Vector3(0, 1.7, 0), mat(PALETTE[2], 0.0, 0.95))
			disc(cloth, "Disc", 0.14, 0.02, Vector3(0, 1.85, 0), mat(TRIM, 0.0, 0.95))
		else:
			# presidential standard: navy with a gold seal
			box(cloth, "Field", Vector3(0.76, 1.3, 0.015), Vector3(0, 1.2, 0), mat(NAVY, 0.0, 0.95))
			disc(cloth, "Seal", 0.18, 0.02, Vector3(0, 1.9, 0), gold())
			disc(cloth, "SealInner", 0.13, 0.024, Vector3(0, 1.9, 0), mat(NAVY, 0.0, 0.95))
		box(cloth, "Fringe", Vector3(0.78, 0.05, 0.02), Vector3(0, 1.17, 0), gold())


# ---------------------------------------------------------------- front wall (facing the player)

## A panelled door in a wall opening. The leaves hang on hinges and swing into
## the room (see set_door_open). A double door hinges on both outer edges; a
## single door hinges on its +X edge when hinge_right, otherwise on -X.
func door(parent: Node, n: String, lx: float, w: float, h: float, double := true, hinge_right := false) -> Node3D:
	var g := group(parent, n, Vector3(lx, 0, 0))
	var white := mat(TRIM, 0.0, 0.6)
	var shade := mat(TRIM_SHADE, 0.0, 0.6)
	var r := DOOR_REVEAL
	# casings on both faces of the wall, jambs lining the opening, a threshold
	for face in [1.0, -1.0]:
		var z0: float = 0.0 if face > 0.0 else -0.2
		box(g, "CasingL", Vector3(0.16, h + 0.1, 0.08), Vector3(-w * 0.5 - 0.08, 0, z0 + 0.04 * face), white)
		box(g, "CasingR", Vector3(0.16, h + 0.1, 0.08), Vector3(w * 0.5 + 0.08, 0, z0 + 0.04 * face), white)
		box(g, "Head", Vector3(w + 0.32, 0.2, 0.1), Vector3(0, h, z0 + 0.05 * face), white)
	box(g, "Cornice", Vector3(w + 0.6, 0.08, 0.16), Vector3(0, h + 0.2, 0.08), white)
	box(g, "JambL", Vector3(r, h + r, 0.2), Vector3(-w * 0.5 - r * 0.5, 0, -0.1), shade)
	box(g, "JambR", Vector3(r, h + r, 0.2), Vector3(w * 0.5 + r * 0.5, 0, -0.1), shade)
	box(g, "JambHead", Vector3(w + r * 2.0, r, 0.2), Vector3(0, h, -0.1), shade)
	box(g, "Threshold", Vector3(w + r * 2.0, 0.012, 0.26), Vector3(0, 0, -0.1), mat(WOOD_DARK, 0.0, 0.5))

	var leaves := 2 if double else 1
	var lw := w / leaves
	var hinges: Array[Node3D] = []
	var signs: Array[float] = []
	for i in leaves:
		# hinge on the outer edge; the leaf runs from it toward the middle
		var at_right := (i == 1) if double else hinge_right
		var hx := w * 0.5 if at_right else -w * 0.5
		var run := -1.0 if at_right else 1.0
		# the hinge line sits on the room face of the leaf (z = 0.05)
		var hinge := group(g, "Hinge%d" % i, Vector3(hx, 0, 0.05))
		hinges.append(hinge)
		signs.append(1.0 if at_right else -1.0)
		var cx := run * lw * 0.5
		box(hinge, "Leaf", Vector3(lw - 0.01, h - 0.005, 0.05), Vector3(cx, 0.003, -0.025), white)
		for side in [1.0, -1.0]:
			var face_z: float = 0.0 if side > 0.0 else -0.05
			var pz: float = face_z + 0.005 * side
			box(hinge, "PanelLow", Vector3(lw - 0.22, h * 0.32, 0.02), Vector3(cx, h * 0.08, pz), shade)
			box(hinge, "PanelHigh", Vector3(lw - 0.22, h * 0.42, 0.02), Vector3(cx, h * 0.48, pz), shade)
			# knob near the free edge, on both faces
			var kx := run * (lw - 0.1)
			sph(hinge, "Knob", 0.035, Vector3(kx, 1.05, face_z + 0.04 * side), gold(), 12)
			cyl(hinge, "Rose", 0.03, 0.01, Vector3.ZERO, gold(), 12).transform = \
				Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(kx, 1.05, face_z + 0.005 * side))
		for k in 3:
			box(hinge, "Butt%d" % k, Vector3(0.02, 0.09, 0.055), Vector3(0, 0.25 + k * (h - 0.6) * 0.5, -0.0275), gold())
		if double and i == 1:
			box(hinge, "Astragal", Vector3(0.014, h - 0.005, 0.06), Vector3(-lw + 0.005, 0.003, -0.025), mat(WOOD_DARK))
	doors[n] = {"leaves": hinges, "signs": signs, "node": g, "amount": 0.0}
	return g


func _build_front_door() -> void:
	var w := MAIN_DOOR_W
	var h := MAIN_DOOR_H
	var g := door(_front, "MainDoor", 0.0, w, h, true)
	# pediment
	var white := mat(TRIM, 0.0, 0.6)
	var half := (w + 0.6) * 0.5
	var rise := 0.3
	var glen := sqrt(half * half + rise * rise)
	var ang := rad_to_deg(atan2(rise, half))
	box(g, "GableL", Vector3(glen, 0.08, 0.14), Vector3(-half * 0.5, h + 0.28 + rise * 0.5 - 0.04, 0.08), white, Vector3(0, 0, ang))
	box(g, "GableR", Vector3(glen, 0.08, 0.14), Vector3(half * 0.5, h + 0.28 + rise * 0.5 - 0.04, 0.08), white, Vector3(0, 0, -ang))
	disc(g, "GableSeal", 0.1, 0.03, Vector3(0, h + 0.42, 0.1), gold())
	label(g, "Plaque", "OFFICE OF THE PRESIDENT", Vector3(0, h + 0.1, 0.105), 0.0013, GOLD, Color(0.25, 0.15, 0.05), Vector3.ZERO, 4)


func _build_bookcases() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1789
	var w := 1.5
	var h := 2.9
	var d := 0.42
	var white := mat(TRIM, 0.0, 0.7)
	var inside := mat(WOOD, 0.0, 0.8)
	var spines := []
	for c in PALETTE:
		spines.append((c as Color).darkened(0.35))
	spines.append_array([Color(0.35, 0.1, 0.08), Color(0.12, 0.2, 0.14), NAVY, Color(0.3, 0.2, 0.12)])
	for bi in BOOKCASE_XS.size():
		var g := group(_front, "Bookcase%d" % bi, Vector3(BOOKCASE_XS[bi], 0, 0))
		box(g, "Back", Vector3(w, h, 0.02), Vector3(0, 0, 0.01), inside)
		box(g, "SideL", Vector3(0.06, h, d), Vector3(-w * 0.5 + 0.03, 0, d * 0.5), white)
		box(g, "SideR", Vector3(0.06, h, d), Vector3(w * 0.5 - 0.03, 0, d * 0.5), white)
		box(g, "Top", Vector3(w + 0.1, 0.12, d + 0.06), Vector3(0, h, d * 0.5 + 0.03), white)
		box(g, "TopGold", Vector3(w + 0.1, 0.025, d + 0.065), Vector3(0, h - 0.025, d * 0.5 + 0.03), gold())
		# closed cabinet at the bottom
		box(g, "Cabinet", Vector3(w - 0.12, 0.9, d - 0.02), Vector3(0, 0, d * 0.5), white)
		for k in 2:
			var x := -w * 0.25 + k * w * 0.5 - 0.03 * (1 - 2 * k)
			box(g, "CabPanel%d" % k, Vector3(w * 0.5 - 0.22, 0.6, 0.02), Vector3(x, 0.15, d + 0.01), mat(TRIM_SHADE, 0.0, 0.7))
			sph(g, "CabKnob%d" % k, 0.025, Vector3(x * 0.25, 0.6, d + 0.03), gold(), 10)
		# shelves and books
		var shelf_ys := [0.9, 1.4, 1.9, 2.4]
		for s in shelf_ys.size():
			var y: float = shelf_ys[s]
			box(g, "Shelf%d" % s, Vector3(w - 0.12, 0.04, d - 0.04), Vector3(0, y, d * 0.5), white)
			var x := -w * 0.5 + 0.08
			var right := w * 0.5 - 0.08
			var bk := 0
			while x < right - 0.05:
				if rng.randf() < 0.07:
					x += rng.randf_range(0.08, 0.2)   # a gap
					continue
				var bw := rng.randf_range(0.03, 0.06)
				if x + bw > right:
					break
				var bh := rng.randf_range(0.28, 0.42)
				var col: Color = spines[rng.randi() % spines.size()]
				box(g, "Book%d_%d" % [s, bk], Vector3(bw, bh, rng.randf_range(0.22, 0.28)),
					Vector3(x + bw * 0.5, y + 0.04, d * 0.5 + 0.02), mat(col, 0.0, 0.8))
				x += bw + 0.004
				bk += 1


# ---------------------------------------------------------------- side walls

func painting(parent: Node, n: String, centre: Vector3, w: float, h: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var g := group(parent, n, centre)
	outline_rect(g, "Frame", Vector3(0, 0, 0.03), w + 0.16, h + 0.16, 0.09, 0.06, gold())
	box(g, "Sky", Vector3(w, h, 0.02), Vector3(0, -h * 0.5, 0.01), mat(Color(0.7, 0.82, 0.92), 0.0, 0.95))
	box(g, "SkyLow", Vector3(w, h * 0.3, 0.021), Vector3(0, -h * 0.15, 0.011), mat(Color(0.95, 0.86, 0.68), 0.0, 0.95))
	disc(g, "Sun", h * 0.09, 0.022, Vector3(w * rng.randf_range(-0.3, 0.3), h * 0.18, 0.012), mat(Color(1.0, 0.92, 0.6), 0.0, 0.9))
	var hill_cols := [PALETTE[0], PALETTE[1], Color(0.3, 0.5, 0.3)]
	for k in 3:
		var hw := w * rng.randf_range(0.7, 1.1)
		var hx := w * rng.randf_range(-0.3, 0.3)
		var hh := h * (0.42 - k * 0.1)
		var hill := box(g, "Hill%d" % k, Vector3(hw, hh, 0.022 + k * 0.002), Vector3(hx, -h * 0.5, 0.012 + k * 0.002),
			mat((hill_cols[k] as Color).darkened(0.1 * k), 0.0, 0.95), Vector3(0, 0, rng.randf_range(-8.0, 8.0)))
		# keep hills inside the frame
		hill.scale.x = minf(1.0, w / hw)
		hill.position.x = clampf(hx, -w * 0.5 + hw * hill.scale.x * 0.5, w * 0.5 - hw * hill.scale.x * 0.5)
	return g


func _build_fireplace() -> void:
	var lx := ZC - FIREPLACE_Z
	var g := group(_left, "Fireplace", Vector3(lx, 0, 0))
	var marble := mat(MARBLE, 0.0, 0.3)
	var dark := mat(MARBLE_DARK, 0.0, 0.5)
	box(g, "Hearth", Vector3(1.9, 0.05, 0.65), Vector3(0, 0, 0.32), dark)
	box(g, "JambL", Vector3(0.32, 1.0, 0.32), Vector3(-0.6, 0.05, 0.16), marble)
	box(g, "JambR", Vector3(0.32, 1.0, 0.32), Vector3(0.6, 0.05, 0.16), marble)
	box(g, "Lintel", Vector3(1.52, 0.22, 0.32), Vector3(0, 0.85, 0.16), marble)
	box(g, "Mantel", Vector3(1.95, 0.07, 0.42), Vector3(0, 1.07, 0.2), marble)
	box(g, "MantelGold", Vector3(1.96, 0.02, 0.43), Vector3(0, 1.05, 0.2), gold())
	box(g, "Firebox", Vector3(0.9, 0.8, 0.3), Vector3(0, 0.05, 0.02), mat(Color(0.08, 0.07, 0.07)))
	# logs and flames
	for k in 2:
		var lg := cyl(g, "Log%d" % k, 0.055, 0.7, Vector3.ZERO, mat(Color(0.3, 0.18, 0.1)), 10)
		lg.rotation_degrees.z = 90.0
		lg.rotation_degrees.y = -6.0 + k * 12.0
		lg.position = Vector3(0, 0.11 + k * 0.08, 0.17 - k * 0.03)
	var flame_cols := [Color(1.0, 0.45, 0.1), Color(1.0, 0.7, 0.2), Color(1.0, 0.55, 0.12)]
	for k in 3:
		var fg := group(g, "Flame%d" % k, Vector3(-0.2 + k * 0.2, 0.2, 0.18))
		no_shadow(box(fg, "F", Vector3(0.12, 0.28 - absf(k - 1) * 0.08, 0.04), Vector3.ZERO, mat(flame_cols[k], 3.0, 0.5)))
		_fire_flames.append(fg)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "FireLight"
	_fire_light.light_color = Color(1.0, 0.6, 0.3)
	_fire_light.light_energy = 1.2
	_fire_light.omni_range = 3.5
	_fire_light.position = Vector3(0, 0.45, 0.6)
	g.add_child(_fire_light)
	# mantel decor
	for side in [-1.0, 1.0]:
		cyl(g, "Candlestick", 0.035, 0.22, Vector3(side * 0.75, 1.14, 0.2), gold(), 12, 0.02)
		cyl(g, "Candle", 0.018, 0.1, Vector3(side * 0.75, 1.36, 0.2), mat(TRIM), 10)
	box(g, "Clock", Vector3(0.3, 0.26, 0.12), Vector3(0, 1.14, 0.2), mat(WOOD, 0.0, 0.5))
	disc(g, "ClockFace", 0.08, 0.01, Vector3(0, 1.27, 0.265), mat(TRIM))
	painting(g, "Painting", Vector3(0, 2.05, 0.0), 1.2, 0.85, 7)


func _build_side_wall_details() -> void:
	# left wall: tall case clock beside the desk
	var clx := ZC - 0.0
	var c := group(_left, "CaseClock", Vector3(clx, 0, 0))
	var wood := mat(WOOD, 0.0, 0.5)
	box(c, "Plinth", Vector3(0.56, 0.25, 0.34), Vector3(0, 0, 0.17), mat(WOOD_DARK, 0.0, 0.5))
	box(c, "Trunk", Vector3(0.44, 1.35, 0.28), Vector3(0, 0.25, 0.15), wood)
	box(c, "PendulumWindow", Vector3(0.22, 0.8, 0.02), Vector3(0, 0.5, 0.29), mat(Color(0.15, 0.12, 0.1), 0.0, 0.2))
	disc(c, "Pendulum", 0.06, 0.01, Vector3(0, 0.75, 0.305), gold())
	box(c, "Hood", Vector3(0.54, 0.5, 0.32), Vector3(0, 1.6, 0.16), wood)
	disc(c, "Face", 0.17, 0.01, Vector3(0, 1.85, 0.325), mat(TRIM))
	disc(c, "FaceRing", 0.19, 0.008, Vector3(0, 1.85, 0.321), gold())
	box(c, "HandH", Vector3(0.014, 0.09, 0.006), Vector3(0, 1.85, 0.333), mat(INK), Vector3(0, 0, -60))
	box(c, "HandM", Vector3(0.01, 0.13, 0.006), Vector3(0, 1.85, 0.336), mat(INK), Vector3(0, 0, 25))
	box(c, "Crest", Vector3(0.6, 0.08, 0.34), Vector3(0, 2.1, 0.17), mat(WOOD_DARK, 0.0, 0.5))
	sph(c, "Finial", 0.05, Vector3(0, 2.23, 0.17), gold())

	# right wall: side door, console table with painting, cabinet
	# hinged on the bookcase side, so from the chair you look past the open leaf
	door(_right, "SideDoor", SIDE_DOOR_Z - ZC, SIDE_DOOR_W, SIDE_DOOR_H, false, false)
	var tlx := -2.6 - ZC
	var t := group(_right, "Console", Vector3(tlx, 0, 0))
	box(t, "Top", Vector3(1.4, 0.05, 0.42), Vector3(0, 0.8, 0.22), mat(WOOD, 0.0, 0.4))
	box(t, "Apron", Vector3(1.3, 0.12, 0.36), Vector3(0, 0.68, 0.2), mat(WOOD, 0.0, 0.5))
	box(t, "ApronGold", Vector3(1.31, 0.02, 0.37), Vector3(0, 0.72, 0.2), gold())
	for x in [-0.6, 0.6]:
		box(t, "Leg", Vector3(0.06, 0.68, 0.06), Vector3(x, 0, 0.36), mat(WOOD, 0.0, 0.5))
		box(t, "LegBack", Vector3(0.06, 0.68, 0.06), Vector3(x, 0, 0.06), mat(WOOD, 0.0, 0.5))
	cyl(t, "Vase", 0.09, 0.32, Vector3(0, 0.85, 0.22), mat(PALETTE[7], 0.0, 0.3), 16, 0.06)
	for k in 7:
		var a := k * TAU / 7.0
		sph(t, "Flower%d" % k, 0.045, Vector3(cos(a) * 0.09, 1.25 + (k % 2) * 0.05, 0.22 + sin(a) * 0.09),
			mat(PALETTE[[2, 4, 5, 6, 0][k % 5]], 0.0, 0.9), 10)
	sph(t, "Greens", 0.12, Vector3(0, 1.2, 0.22), mat(PALETTE[1], 0.0, 0.9), 12)
	painting(t, "Painting", Vector3(0, 2.0, 0.0), 1.3, 0.95, 21)

	var cab := group(_right, "Cabinet", Vector3(2.3, 0, 0))
	box(cab, "Body", Vector3(1.2, 0.9, 0.45), Vector3(0, 0.06, 0.225), mat(WOOD, 0.0, 0.5))
	box(cab, "Plinth", Vector3(1.24, 0.06, 0.47), Vector3(0, 0, 0.235), mat(WOOD_DARK, 0.0, 0.5))
	box(cab, "Top", Vector3(1.26, 0.04, 0.49), Vector3(0, 0.96, 0.245), mat(WOOD_DARK, 0.0, 0.4))
	for k in 2:
		box(cab, "Door%d" % k, Vector3(0.5, 0.7, 0.02), Vector3(-0.28 + k * 0.56, 0.16, 0.455), mat(WOOD_LIGHT, 0.0, 0.5))
		sph(cab, "Knob%d" % k, 0.02, Vector3(-0.06 + k * 0.12, 0.55, 0.47), gold(), 10)
	painting(cab, "Painting", Vector3(0, 2.05, 0.0), 0.9, 0.7, 33)

	# globe beside the cabinet
	var gl := group(_built, "Globe", Vector3(3.55, 0, -0.3))
	cyl(gl, "Base", 0.22, 0.05, Vector3.ZERO, mat(WOOD_DARK, 0.0, 0.5), 20)
	cyl(gl, "Stem", 0.035, 0.55, Vector3(0, 0.05, 0), mat(WOOD, 0.0, 0.5), 12)
	var sphere_g := group(gl, "Ball", Vector3(0, 0.9, 0))
	sphere_g.rotation_degrees.z = 23.0
	sph(sphere_g, "Sea", 0.3, Vector3.ZERO, mat(PALETTE[7], 0.0, 0.6), 24)
	for k in 5:
		var a := k * 1.3
		var p := Vector3(cos(a) * 0.27, sin(k * 2.1) * 0.12, sin(a) * 0.27)
		var land := sph(sphere_g, "Land%d" % k, 0.1, p, mat(PALETTE[0], 0.0, 0.8), 10)
		land.scale = Vector3(1.0, 0.7, 1.0)
	var ring := MeshInstance3D.new()
	ring.name = "Meridian"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.345
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = gold()
	ring.rotation_degrees.x = 90.0
	sphere_g.add_child(ring)


# ---------------------------------------------------------------- centre of the room

func _build_rug() -> void:
	var g := group(_built, "Rug", Vector3(0, 0, -3.1))
	var rx := 3.0
	var rz := 2.25
	var layers := [
		[1.0, 0.010, GOLD],
		[0.97, 0.013, NAVY],
		[0.9, 0.015, GOLD],
		[0.885, 0.017, NAVY],
	]
	for i in layers.size():
		var s: float = layers[i][0]
		var c := cyl(g, "Layer%d" % i, 1.0, layers[i][1], Vector3.ZERO, mat(layers[i][2], 0.0, 0.95), 48)
		c.scale = Vector3(rx * s, 1.0, rz * s)
	# the seal, far enough out to be seen over the desk
	var seal := group(g, "Seal", Vector3(0, 0.017, -0.85))
	cyl(seal, "Outer", 0.72, 0.004, Vector3.ZERO, mat(GOLD, 0.0, 0.8), 40)
	cyl(seal, "Band", 0.64, 0.006, Vector3.ZERO, mat(TRIM, 0.0, 0.9), 40)
	cyl(seal, "Field", 0.54, 0.008, Vector3.ZERO, mat(NAVY, 0.0, 0.95), 40)
	for k in 5:
		box(seal, "Ray%d" % k, Vector3(0.8, 0.002, 0.07), Vector3(0, 0.008, 0), mat(GOLD, 0.0, 0.8), Vector3(0, k * 36.0, 0))
	cyl(seal, "Centre", 0.15, 0.012, Vector3.ZERO, mat(GOLD, 0.0, 0.8), 24)
	for k in 12:
		var a := k * TAU / 12.0
		cyl(seal, "Star%d" % k, 0.025, 0.009, Vector3(cos(a) * 0.59, 0, sin(a) * 0.59), mat(GOLD, 0.0, 0.8), 8)


func sofa(n: String, pos: Vector3, rot_y: float) -> void:
	var g := group(_built, n, pos, rot_y)
	var cloth := mat(SOFA, 0.0, 0.95)
	var cushion := mat(SOFA_CUSHION, 0.0, 0.95)
	var leg := mat(WOOD_DARK, 0.0, 0.5)
	for x in [-0.9, 0.9]:
		for z in [-0.34, 0.34]:
			cyl(g, "Leg", 0.03, 0.1, Vector3(x, 0, z), leg, 8, 0.022)
	box(g, "Base", Vector3(2.0, 0.28, 0.85), Vector3(0, 0.1, 0), cloth)
	box(g, "Back", Vector3(2.0, 0.55, 0.2), Vector3(0, 0.38, -0.33), cloth)
	box(g, "Piping", Vector3(2.01, 0.03, 0.21), Vector3(0, 0.92, -0.33), gold())
	for x in [-0.93, 0.93]:
		box(g, "Arm", Vector3(0.16, 0.34, 0.85), Vector3(x, 0.38, 0), cloth)
	for k in 3:
		var x := -0.58 + k * 0.58
		box(g, "Seat%d" % k, Vector3(0.56, 0.12, 0.62), Vector3(x, 0.38, 0.07), cushion)
		box(g, "BackCushion%d" % k, Vector3(0.54, 0.4, 0.13), Vector3(x, 0.48, -0.18), cushion, Vector3(-10, 0, 0))
	box(g, "Pillow", Vector3(0.32, 0.3, 0.1), Vector3(0.62, 0.5, -0.05), mat(PALETTE[6], 0.0, 0.95), Vector3(-15, -20, 0))


func _build_sofas() -> void:
	sofa("SofaLeft", Vector3(-2.25, 0, -3.2), 90.0)
	sofa("SofaRight", Vector3(2.25, 0, -3.2), -90.0)


func _build_coffee_table() -> void:
	var g := group(_built, "CoffeeTable", Vector3(0, 0, -2.45))
	box(g, "Top", Vector3(1.1, 0.05, 0.55), Vector3(0, 0.4, 0), mat(WOOD, 0.0, 0.35))
	box(g, "TopGold", Vector3(1.11, 0.015, 0.56), Vector3(0, 0.39, 0), gold())
	for x in [-0.48, 0.48]:
		for z in [-0.22, 0.22]:
			box(g, "Leg", Vector3(0.05, 0.39, 0.05), Vector3(x, 0, z), mat(WOOD_DARK, 0.0, 0.5))
	cyl(g, "Bowl", 0.14, 0.07, Vector3(0.15, 0.45, 0), mat(TRIM, 0.0, 0.3), 20, 0.17)
	for k in 4:
		sph(g, "Fruit%d" % k, 0.04, Vector3(0.1 + (k % 2) * 0.09, 0.53, -0.04 + (k / 2) * 0.08), mat(PALETTE[[3, 6, 0, 2][k]], 0.0, 0.6), 10)
	box(g, "Book", Vector3(0.28, 0.04, 0.2), Vector3(-0.3, 0.45, 0.02), mat(NAVY, 0.0, 0.8), Vector3(0, 12, 0))


func _build_chandelier() -> void:
	var g := group(_built, "Chandelier", Vector3(0, H, -2.0))
	cyl(g, "Rod", 0.015, 0.7, Vector3(0, -0.7, 0), gold(), 8)
	sph(g, "Body", 0.1, Vector3(0, -0.75, 0), gold())
	sph(g, "Drop", 0.05, Vector3(0, -0.88, 0), gold())
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.46
	tm.rings = 32
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = gold()
	ring.position = Vector3(0, -0.8, 0)
	g.add_child(ring)
	var bulb := mat(Color(1.0, 0.86, 0.6), 4.0, 0.3)
	for k in 8:
		var a := k * TAU / 8.0
		var p := Vector3(cos(a) * 0.44, -0.8, sin(a) * 0.44)
		box(g, "Arm%d" % k, Vector3(0.44, 0.015, 0.015), Vector3(cos(a) * 0.22, -0.79, sin(a) * 0.22), gold(), Vector3(0, -rad_to_deg(a), 0))
		cyl(g, "Cup%d" % k, 0.03, 0.03, p + Vector3(0, 0.01, 0), gold(), 10)
		cyl(g, "Candle%d" % k, 0.014, 0.08, p + Vector3(0, 0.04, 0), mat(TRIM), 8)
		no_shadow(sph(g, "Bulb%d" % k, 0.025, p + Vector3(0, 0.14, 0), bulb, 8))
	# the chandelier light sits inside it, so it must not shadow itself onto the ceiling
	for c in g.get_children():
		if c is GeometryInstance3D:
			no_shadow(c)


# ---------------------------------------------------------------- the desk

func _build_desk() -> void:
	var g := group(_built, "Desk", Vector3(0, 0, DESK_Z))
	var wood := mat(WOOD, 0.0, 0.45)
	var dark := mat(WOOD_DARK, 0.0, 0.5)
	var light := mat(WOOD_LIGHT, 0.0, 0.45)
	var top_h := 0.06
	var body_h := DESK_TOP - top_h
	box(g, "Top", Vector3(2.4, top_h, 1.1), Vector3(0, body_h, 0), wood)
	box(g, "TopGold", Vector3(2.43, 0.022, 1.13), Vector3(0, body_h - 0.005, 0), gold())
	for side in [-1.0, 1.0]:
		var px: float = side * 0.86
		var p := group(g, "Pedestal%s" % ("L" if side < 0 else "R"), Vector3(px, 0, 0))
		box(p, "Plinth", Vector3(0.66, 0.07, 1.04), Vector3.ZERO, dark)
		box(p, "Body", Vector3(0.6, body_h - 0.07, 1.0), Vector3(0, 0.07, 0), wood)
		# drawers on the player side (+Z)
		for k in 3:
			var y := 0.12 + k * 0.17
			box(p, "Drawer%d" % k, Vector3(0.5, 0.14, 0.02), Vector3(0, y, 0.505), light)
			box(p, "Pull%d" % k, Vector3(0.1, 0.02, 0.02), Vector3(0, y + 0.06, 0.525), gold())
		# carved panel on the visitor side (-Z)
		box(p, "Carving", Vector3(0.46, 0.46, 0.02), Vector3(0, 0.14, -0.505), light)
		outline_rect(p, "CarvingGold", Vector3(0, 0.37, -0.52), 0.46, 0.46, 0.02, 0.01, gold())
	# modesty panel with the seal, facing visitors
	box(g, "Modesty", Vector3(1.12, 0.56, 0.04), Vector3(0, 0.14, -0.42), wood)
	var seal := disc(g, "Seal", 0.16, 0.02, Vector3(0, 0.42, -0.45), gold())
	seal.rotation_degrees.x = 90.0
	disc(g, "SealInner", 0.11, 0.024, Vector3(0, 0.42, -0.45), mat(NAVY, 0.0, 0.8))
	# drawer above the knee hole
	box(g, "CentreDrawer", Vector3(1.0, 0.1, 0.02), Vector3(0, body_h - 0.12, 0.5), light)
	box(g, "CentrePull", Vector3(0.16, 0.02, 0.02), Vector3(0, body_h - 0.075, 0.52), gold())
	# collision so things can sit on / bump the desk once combined
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	g.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, DESK_TOP, 1.1)
	cs.shape = bs
	cs.position = Vector3(0, DESK_TOP * 0.5, 0)
	sb.add_child(cs)


func _build_desk_items() -> void:
	var g := group(_built, "DeskItems", Vector3(0, DESK_TOP, DESK_Z))
	# leather writing pad (the paper sits on it)
	box(g, "PadGold", Vector3(0.94, 0.004, 0.58), Vector3(0, 0, 0.22), gold())
	box(g, "Pad", Vector3(0.9, 0.006, 0.54), Vector3(0, 0, 0.22), mat(Color(0.12, 0.28, 0.2), 0.0, 0.7))

	# banker's lamp, left
	var lamp := group(g, "Lamp", Vector3(-0.92, 0, -0.32), 12.0)
	lamp.scale = Vector3.ONE * 0.85
	cyl(lamp, "Base", 0.1, 0.03, Vector3.ZERO, gold(), 20, 0.08)
	cyl(lamp, "Stem", 0.012, 0.36, Vector3(0, 0.03, 0), gold(), 8)
	box(lamp, "Arm", Vector3(0.012, 0.012, 0.12), Vector3(0, 0.38, 0.05), gold())
	box(lamp, "Shade", Vector3(0.36, 0.08, 0.14), Vector3(0, 0.36, 0.11), mat(PALETTE[1], 0.0, 0.25), Vector3(-12, 0, 0))
	no_shadow(box(lamp, "Glow", Vector3(0.32, 0.01, 0.1), Vector3(0, 0.355, 0.11), mat(Color(1.0, 0.9, 0.65), 3.0), Vector3(-12, 0, 0)))
	var lamp_light := OmniLight3D.new()
	lamp_light.name = "LampLight"
	lamp_light.light_color = Color(1.0, 0.88, 0.65)
	lamp_light.light_energy = 0.9
	lamp_light.omni_range = 2.2
	lamp_light.position = Vector3(0, 0.3, 0.14)
	lamp.add_child(lamp_light)

	# telephone, right
	var ph := group(g, "Phone", Vector3(0.92, 0, 0.15), -15.0)
	box(ph, "Base", Vector3(0.2, 0.06, 0.22), Vector3.ZERO, mat(Color(0.12, 0.12, 0.13), 0.0, 0.3))
	box(ph, "Keys", Vector3(0.12, 0.004, 0.1), Vector3(0, 0.06, 0.04), mat(TRIM, 0.0, 0.4), Vector3(-15, 0, 0))
	box(ph, "Handset", Vector3(0.22, 0.04, 0.06), Vector3(0, 0.07, -0.06), mat(Color(0.12, 0.12, 0.13), 0.0, 0.3))
	# in-tray with folders
	var tray := group(g, "InTray", Vector3(0.66, 0, -0.25), 6.0)
	box(tray, "Tray", Vector3(0.34, 0.012, 0.26), Vector3.ZERO, mat(WOOD_DARK, 0.0, 0.5))
	for k in 3:
		box(tray, "Folder%d" % k, Vector3(0.31, 0.012, 0.23), Vector3(0.005 * k, 0.012 + k * 0.012, 0.004 * k),
			mat([PALETTE[3], PALETTE[7], Color(0.85, 0.78, 0.6)][k], 0.0, 0.8), Vector3(0, k * 4.0 - 4.0, 0))
	# pen holder
	var pens := group(g, "PenHolder", Vector3(-0.62, 0, 0.3))
	cyl(pens, "Cup", 0.04, 0.11, Vector3.ZERO, mat(WOOD_DARK, 0.0, 0.4), 16)
	cyl(pens, "Rim", 0.042, 0.012, Vector3(0, 0.1, 0), gold(), 16)
	for k in 3:
		var pen := cyl(pens, "Pen%d" % k, 0.006, 0.15, Vector3.ZERO, mat([INK, GOLD, NAVY][k], 0.0, 0.3), 6)
		pen.position = Vector3(-0.012 + k * 0.012, 0.13, (k - 1) * 0.01)
		pen.rotation_degrees = Vector3((k - 1) * 8.0, 0, (k - 1) * -10.0)
	# nameplate facing visitors
	var plate := group(g, "Nameplate", Vector3(0, 0, -0.45))
	box(plate, "Block", Vector3(0.5, 0.07, 0.06), Vector3.ZERO, mat(WOOD_DARK, 0.0, 0.4))
	box(plate, "Brass", Vector3(0.46, 0.05, 0.004), Vector3(0, 0.01, -0.032), gold())
	label(plate, "Text", "THE PRESIDENT", Vector3(0, 0.035, -0.036), 0.00045, NAVY, NAVY, Vector3(0, 180, 0), 0)
	# small desk flags
	for k in 2:
		var x := -0.36 if k == 0 else 0.36
		var f := group(g, "DeskFlag%d" % k, Vector3(x, 0, -0.42))
		cyl(f, "Base", 0.035, 0.02, Vector3.ZERO, gold(), 12)
		cyl(f, "Pole", 0.004, 0.3, Vector3(0, 0.02, 0), gold(), 6)
		var col: Color = PALETTE[8] if k == 0 else NAVY
		box(f, "Flag", Vector3(0.002, 0.08, 0.12), Vector3(0, 0.22, -0.06), mat(col, 0.0, 0.9))


func _build_paper() -> void:
	# The paper lies on the pad, right in front of the player.
	paper = group(_built, "Paper", Vector3(0.0, DESK_TOP + 0.007, DESK_Z + 0.26), -3.0)
	var pw := 0.21
	var pd := 0.297
	box(paper, "Sheet", Vector3(pw, 0.002, pd), Vector3.ZERO, mat(PAPER, 0.0, 0.95))
	# Text faces up; its top edge points away from the player (-Z), so it reads
	# the right way round from the chair.
	var top := Vector3(-90, 0, 0)
	cyl(paper, "Emblem", 0.01, 0.0008, Vector3(0, 0.002, -pd * 0.5 + 0.025), gold(), 20)
	label(paper, "Title", paper_title, Vector3(0, 0.0045, -pd * 0.5 + 0.056), 0.00038, INK, INK, top, 0)
	box(paper, "Rule", Vector3(pw - 0.04, 0.0008, 0.0015), Vector3(0, 0.002, -pd * 0.5 + 0.08), mat(INK))
	if paper_text.strip_edges() != "":
		var body := label(paper, "Body", paper_text, Vector3(-pw * 0.5 + 0.02, 0.0045, -pd * 0.5 + 0.09), 0.00022, INK, INK, top, 0)
		body.uppercase = false
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.width = (pw - 0.04) / body.pixel_size
		body.font_size = 48
	else:
		# placeholder lines of text
		var line := mat(Color(0.55, 0.55, 0.58))
		var widths := [0.16, 0.17, 0.15, 0.17, 0.12, 0.17, 0.16, 0.09]
		for i in widths.size():
			var lw: float = widths[i]
			box(paper, "Line%d" % i, Vector3(lw, 0.0008, 0.004),
				Vector3(-pw * 0.5 + 0.02 + lw * 0.5, 0.002, -pd * 0.5 + 0.095 + i * 0.016), line)
	# signature line
	box(paper, "Signature", Vector3(0.07, 0.0008, 0.0012), Vector3(pw * 0.5 - 0.055, 0.002, pd * 0.5 - 0.03), mat(INK))


func _build_chair() -> void:
	# Behind the camera; mostly seen when looking down or turning around.
	var g := group(_built, "Chair", Vector3(0, 0, EYE.z + 0.15))
	var leather := mat(LEATHER, 0.0, 0.5)
	cyl(g, "Base", 0.3, 0.05, Vector3(0, 0.03, 0), mat(Color(0.12, 0.12, 0.13), 0.0, 0.4), 5)
	cyl(g, "Column", 0.035, 0.36, Vector3(0, 0.08, 0), mat(Color(0.15, 0.15, 0.16), 0.0, 0.3, 0.6), 10)
	box(g, "Seat", Vector3(0.62, 0.12, 0.58), Vector3(0, 0.44, 0), leather)
	var back := box(g, "Back", Vector3(0.62, 0.95, 0.14), Vector3(0, 0.52, 0.32), leather, Vector3(10, 0, 0))
	back.layers = CHAIR_BACK_LAYER
	for x in [-0.33, 0.33]:
		box(g, "Arm", Vector3(0.08, 0.06, 0.5), Vector3(x, 0.68, 0.02), leather)
		box(g, "ArmPost", Vector3(0.05, 0.16, 0.05), Vector3(x, 0.54, 0.12), mat(WOOD_DARK, 0.0, 0.5))
	for k in 12:
		var a := k * TAU / 12.0
		var stud := sph(g, "Stud%d" % k, 0.012, Vector3(cos(a) * 0.27, 1.0 + sin(a) * 0.38, 0.36), gold(), 6)
		stud.layers = CHAIR_BACK_LAYER


# ---------------------------------------------------------------- beyond the doors
# A cross hallway behind the main door and an anteroom behind the side door,
# so open doors show somewhere to come from. Visitors appear around the
# corners, out of sight of the chair.

const HALL_Z0 := Z_FRONT - 0.2    # hall side of the front wall
const HALL_Z1 := -8.3             # far wall of the hall
const HALL_X := 6.2               # hall runs from -HALL_X to HALL_X
const ANTE_X0 := W * 0.5 + 0.2    # anteroom side of the right wall
const ANTE_X1 := 7.7
const ANTE_Z0 := Z_FRONT
const ANTE_Z1 := 0.4

func _build_halls() -> void:
	var r := DOOR_REVEAL
	# ---- hallway behind the main door
	var hz := (HALL_Z0 + HALL_Z1) * 0.5
	var hd := HALL_Z0 - HALL_Z1
	var hall := group(_built, "Hallway")
	box(hall, "Floor", Vector3(HALL_X * 2.0, 0.1, hd), Vector3(0, -0.1, hz), mat(FLOOR_B, 0.0, 0.55))
	box(hall, "RunnerEdge", Vector3(HALL_X * 2.0 - 0.5, 0.008, 1.42), Vector3(0, 0, hz), gold())
	box(hall, "Runner", Vector3(HALL_X * 2.0 - 0.56, 0.012, 1.3), Vector3(0, 0, hz), mat(CURTAIN, 0.0, 0.95))
	box(hall, "RunnerToDoor", Vector3(1.3, 0.012, HALL_Z0 - hz), Vector3(0, 0, (HALL_Z0 + hz) * 0.5), mat(CURTAIN, 0.0, 0.95))
	box(hall, "Ceiling", Vector3(HALL_X * 2.0, 0.1, hd), Vector3(0, H, hz), mat(TRIM, 0.0, 0.9))
	# plaster beside the room's front wall, out to the hall ends
	box(hall, "FillW", Vector3(HALL_X - W * 0.5, H, 0.2), Vector3(-(HALL_X + W * 0.5) * 0.5, 0, Z_FRONT - 0.1), mat(WALL, 0.0, 0.9))
	box(hall, "FillE", Vector3(ANTE_X0 - W * 0.5, H, 0.2), Vector3((ANTE_X0 + W * 0.5) * 0.5, 0, Z_FRONT - 0.1), mat(WALL, 0.0, 0.9))
	wall("HallNear", HALL_X * 2.0, Vector3(0, 0, HALL_Z0), 180.0, [Vector2(0, 1.0)],
		[Vector3(0.0, MAIN_DOOR_W * 0.5 + r, MAIN_DOOR_H + r)], false)
	var far := wall("HallFar", HALL_X * 2.0, Vector3(0, 0, HALL_Z1), 0.0,
		[Vector2(0, 1.0), Vector2(-3.4, 0.7), Vector2(3.4, 0.7)])
	wall("HallEndW", hd, Vector3(-HALL_X, 0, hz), 90.0)
	wall("HallEndE", hd, Vector3(HALL_X, 0, hz), -90.0)
	# what you see through the main door: a painting over a console with flowers
	painting(far, "Painting", Vector3(0, 2.1, 0), 1.5, 1.0, 55)
	var con := group(far, "Console", Vector3.ZERO)
	box(con, "Top", Vector3(1.3, 0.05, 0.4), Vector3(0, 0.82, 0.2), mat(WOOD, 0.0, 0.4))
	box(con, "Apron", Vector3(1.2, 0.12, 0.34), Vector3(0, 0.7, 0.19), mat(WOOD, 0.0, 0.5))
	box(con, "ApronGold", Vector3(1.21, 0.02, 0.35), Vector3(0, 0.74, 0.19), gold())
	for x in [-0.55, 0.55]:
		box(con, "Leg", Vector3(0.06, 0.7, 0.06), Vector3(x, 0, 0.33), mat(WOOD, 0.0, 0.5))
	cyl(con, "Vase", 0.08, 0.3, Vector3(0, 0.87, 0.2), mat(TRIM, 0.0, 0.25), 16, 0.055)
	for k in 6:
		var a := k * TAU / 6.0
		sph(con, "Flower%d" % k, 0.05, Vector3(cos(a) * 0.09, 1.24 + (k % 2) * 0.05, 0.2 + sin(a) * 0.08),
			mat(PALETTE[[4, 2, 6, 7, 5, 3][k]], 0.0, 0.9), 10)
	sph(con, "Greens", 0.12, Vector3(0, 1.2, 0.2), mat(PALETTE[1], 0.0, 0.9), 12)
	for x in [-3.4, 3.4]:
		painting(far, "Painting", Vector3(x, 2.0, 0), 1.0, 0.75, 60 + int(x))
		# marble bust on a pedestal under each side painting
		var b := group(far, "Bust", Vector3(x, 0, 0.45))
		box(b, "Pedestal", Vector3(0.36, 1.0, 0.36), Vector3.ZERO, mat(MARBLE, 0.0, 0.3))
		box(b, "Cap", Vector3(0.42, 0.05, 0.42), Vector3(0, 1.0, 0), mat(MARBLE, 0.0, 0.3))
		box(b, "Shoulders", Vector3(0.34, 0.16, 0.18), Vector3(0, 1.05, 0), mat(MARBLE, 0.0, 0.3))
		cyl(b, "Neck", 0.05, 0.1, Vector3(0, 1.2, 0), mat(MARBLE, 0.0, 0.3), 12)
		sph(b, "Head", 0.1, Vector3(0, 1.38, 0), mat(MARBLE, 0.0, 0.3), 16).scale = Vector3(0.9, 1.1, 1.0)
	for x in [-1.6, 1.6, -5.0, 5.0]:
		_sconce(far, Vector3(x, 2.15, 0))
	var hl := group(hall, "Lights")
	for x in [-3.6, 0.0, 3.6]:
		var l := OmniLight3D.new()
		l.name = "HallLight"
		l.light_color = Color(1.0, 0.88, 0.7)
		l.light_energy = 1.1
		l.omni_range = 4.2
		l.position = Vector3(x, 3.0, hz)
		hl.add_child(l)
		cyl(hall, "CeilingLamp", 0.18, 0.05, Vector3(x, H - 0.05, hz), gold(), 20)
		no_shadow(sph(hall, "CeilingGlobe", 0.14, Vector3(x, H - 0.12, hz), mat(Color(1.0, 0.92, 0.75), 2.0, 0.3), 16))

	# ---- anteroom behind the side door
	var az := (ANTE_Z0 + ANTE_Z1) * 0.5
	var ad := ANTE_Z1 - ANTE_Z0
	var ax := (ANTE_X0 + ANTE_X1) * 0.5
	var aw := ANTE_X1 - ANTE_X0
	var ante := group(_built, "Anteroom")
	box(ante, "Floor", Vector3(aw, 0.1, ad), Vector3(ax, -0.1, az), mat(FLOOR_A, 0.0, 0.55))
	box(ante, "Rug", Vector3(aw - 0.8, 0.012, ad - 1.2), Vector3(ax, 0, az), mat(NAVY, 0.0, 0.95))
	box(ante, "RugEdge", Vector3(aw - 0.7, 0.008, ad - 1.1), Vector3(ax, 0, az), gold())
	box(ante, "Ceiling", Vector3(aw, 0.1, ad), Vector3(ax, H, az), mat(TRIM, 0.0, 0.9))
	wall("AnteWest", ad, Vector3(ANTE_X0, 0, az), 90.0, [Vector2(az - SIDE_DOOR_Z, 0.7)],
		[Vector3(az - SIDE_DOOR_Z, SIDE_DOOR_W * 0.5 + r, SIDE_DOOR_H + r)], false)
	var ae := wall("AnteEast", ad, Vector3(ANTE_X1, 0, az), -90.0, [Vector2(-0.4, 1.0)])
	var an := wall("AnteNorth", aw, Vector3(ax, 0, ANTE_Z0), 0.0, [Vector2(0, 1.0)])
	wall("AnteSouth", aw, Vector3(ax, 0, ANTE_Z1), 180.0)
	# north wall is what the chair sees through the side door
	painting(an, "Painting", Vector3(0, 2.0, 0), 1.1, 0.8, 77)
	_sconce(an, Vector3(-1.05, 2.1, 0))
	_sconce(an, Vector3(1.05, 2.1, 0))
	# east wall: waiting bench under a painting, potted palm in the corner
	painting(ae, "Painting", Vector3(-0.4, 2.0, 0), 1.2, 0.85, 88)
	var bench := group(ae, "Bench", Vector3(-0.4, 0, 0.3))
	box(bench, "Seat", Vector3(1.5, 0.1, 0.45), Vector3(0, 0.38, 0), mat(SOFA, 0.0, 0.95))
	box(bench, "Frame", Vector3(1.56, 0.06, 0.5), Vector3(0, 0.33, 0), mat(WOOD, 0.0, 0.5))
	box(bench, "Back", Vector3(1.5, 0.45, 0.08), Vector3(0, 0.45, -0.2), mat(SOFA, 0.0, 0.95))
	for x in [-0.72, 0.72]:
		for z in [-0.2, 0.2]:
			box(bench, "Leg", Vector3(0.05, 0.33, 0.05), Vector3(x, 0, z), mat(WOOD_DARK, 0.0, 0.5))
	var palm := group(ante, "Palm", Vector3(ANTE_X1 - 0.4, 0, ANTE_Z0 + 0.4))
	cyl(palm, "Pot", 0.2, 0.4, Vector3.ZERO, mat(PALETTE[6], 0.0, 0.6), 20, 0.24)
	cyl(palm, "Soil", 0.22, 0.02, Vector3(0, 0.38, 0), mat(WOOD_DARK), 20)
	cyl(palm, "Trunk", 0.03, 0.8, Vector3(0, 0.4, 0), mat(WOOD_LIGHT, 0.0, 0.8), 8, 0.02)
	for k in 7:
		var a := k * TAU / 7.0
		var leaf := box(palm, "Frond%d" % k, Vector3(0.5, 0.02, 0.12), Vector3(cos(a) * 0.22, 1.15, sin(a) * 0.22),
			mat(PALETTE[1], 0.0, 0.8), Vector3(0, -rad_to_deg(a), -25.0 - (k % 3) * 8.0))
		leaf.scale = Vector3(1.0 + (k % 2) * 0.2, 1, 1)
	var al := OmniLight3D.new()
	al.name = "AnteLight"
	al.light_color = Color(1.0, 0.9, 0.72)
	al.light_energy = 1.2
	al.omni_range = 5.5
	al.position = Vector3(ax, 3.0, az - 1.2)
	ante.add_child(al)
	cyl(ante, "CeilingLamp", 0.2, 0.05, Vector3(ax, H - 0.05, az - 1.2), gold(), 20)
	no_shadow(sph(ante, "CeilingGlobe", 0.15, Vector3(ax, H - 0.13, az - 1.2), mat(Color(1.0, 0.92, 0.75), 2.0, 0.3), 16))


## Wall sconce facing +Z: gold plate, arm and a glowing shade.
func _sconce(parent: Node, pos: Vector3) -> void:
	var g := group(parent, "Sconce", pos)
	box(g, "Plate", Vector3(0.1, 0.18, 0.02), Vector3(0, -0.09, 0.01), gold())
	box(g, "Arm", Vector3(0.025, 0.025, 0.14), Vector3(0, -0.02, 0.08), gold())
	cyl(g, "Cup", 0.04, 0.04, Vector3(0, 0.0, 0.15), gold(), 12)
	no_shadow(cyl(g, "Shade", 0.08, 0.14, Vector3(0, 0.04, 0.15), mat(Color(1.0, 0.9, 0.7), 1.6, 0.6), 16, 0.05))


# ---------------------------------------------------------------- lights and camera

func _build_lights() -> void:
	var lights := group(_built, "Lights")
	var main := OmniLight3D.new()
	main.name = "Chandelier"
	main.light_color = Color(1.0, 0.9, 0.75)
	main.light_energy = 1.6
	main.omni_range = 8.0
	main.shadow_enabled = true
	main.position = Vector3(0, H - 1.0, -2.0)
	lights.add_child(main)
	# daylight coming in through the windows behind the player
	for x in WINDOW_XS:
		var s := SpotLight3D.new()
		s.name = "Window"
		s.light_color = Color(0.86, 0.92, 1.0)
		s.light_energy = 1.6
		s.spot_range = 9.0
		s.spot_angle = 50.0
		s.position = Vector3(-x, 2.7, Z_BACK - 0.25)
		s.rotation_degrees.x = -30.0
		lights.add_child(s)
	# soft fill on the desk so the paper always reads
	var fill := OmniLight3D.new()
	fill.name = "DeskFill"
	fill.light_color = Color(1.0, 0.96, 0.9)
	fill.light_energy = 0.5
	fill.omni_range = 2.5
	fill.position = Vector3(0, 2.0, DESK_Z + 0.9)
	lights.add_child(fill)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "SeatedCamera"
	camera.position = EYE
	camera.fov = fov
	camera.near = 0.03
	camera.far = 60.0
	camera.cull_mask &= ~CHAIR_BACK_LAYER
	_built.add_child(camera)
	reset_view()
	if not Engine.is_editor_hint():
		camera.make_current()
