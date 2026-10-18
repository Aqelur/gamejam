extends Node3D
## THE CONTRACTOR'S TOWN: what happens when Bureaucracy hits 0. Played by
## day_cycle.gd (_play_contractor) instead of the next morning, and instead
## of the earthquake if it was the last day. The game ends here.
##
## Nobody is left to enforce the rules, so the Contractor stops asking:
##   1. The camera drifts slowly over the town. Construction fences and
##      "COMING SOON: 12 FLOORS" boards pop up one after another, each one
##      growing from nothing: first around the empty lots (the civic lots
##      nothing was built on, and any vacant block in the street grid), then
##      all the way round Central Park, then along Main Street. Nobody is
##      shown.
##   2. A card on black: TEXT, then TIP. Click to start again.
##
## Everything is placed at run time from what is in the city (lots, hedges,
## buildings, roads), in city tiles, so nothing in City/ needs changing.
##
## day_cycle.gd drives it:
##   setup(city, font_bold, font_black)   finds the sites, builds the (hidden) fences
##   has_sites()                 anything to show at all
##   start_shot()                camera [eye, look] where the flight starts
##   fly(cam)                    off it goes; things pop up as the camera nears them
##   kicker_changed(text)        the flight reached the next part of town
##   is_done()                   everything is up and the camera has arrived
##   finish()                    stop and put everything up at once (skip)
##   show_card(ui), show_tip(), wait_restart()

signal kicker_changed(text: String)

const TEXT := "With no one left to enforce the rules, the contractor stopped asking for your signature. His fences went up around every empty lot, then around the park. His signs promised twelve-story towers, built fast and built cheap. None of them would ever see an inspector. You were still the mayor, but he was running the town."
const TIP := "When rules stop being enforced, building safety is the first thing to go. Make sure your home was built with a permit and passed an inspection."

const PARK := "Districts/EvacuationPark/CentralPark"
const PARK_HEDGES := "Districts/EvacuationPark/CentralPark/Hedges"
const MAIN_STREET := "Districts/MainStreet/Buildings"
const ROADS := "Roads"
const CITY_GROUND := "Ground/CityGround"
const TILE := 26.926893

## Central Park's main lawn (park units = city tiles): its middle and the two
## ends of its long axis, which the camera flies between.
const PARK_CENTRE := Vector3(10.5, 0.0, -9.25)
const PARK_ENDS := [Vector3(-1.5, 0.0, -9.25), Vector3(22.5, 0.0, -9.25)]

## Vacant blocks in the street grid that get fenced, at most.
const MAX_VACANT := 3
## Main Street buildings that get a fence and a board in front.
const MAIN_STREET_SITES := 5
## Sizes in city tiles.
const FENCE_H := 0.13
const POST_GAP := 0.25
const RUN_MAX := 2.4            # longest stretch of fence that pops up as one piece
const SIGN_W := 0.6
const SIGN_H := 0.22
const SIGN_TOP := 0.4
## Camera: where it sits relative to what it looks at, how far (tiles), how
## fast the look point travels (tiles / second) and the longest the flight
## may take (it speeds up to fit).
const CAM_DIR := Vector3(0.32, 0.8, 0.52)
const CAM_DIST := 6.0
const SPEED := 1.7
const MAX_TIME := 34.0
## Things pop up when the camera is this many tiles from reaching them.
const LEAD := 2.4
## Gap between two things popping up from the same spot (seconds).
const POP_GAP := 0.12

const HOARDING := Color(0.14, 0.28, 0.44)
const BAND := Color(1.0, 0.76, 0.1)
const POST := Color(0.82, 0.83, 0.8)
const SIGN_YELLOW := Color(1.0, 0.82, 0.16)
const SIGN_RED := Color(0.78, 0.1, 0.08)
const INK := Color(0.08, 0.08, 0.1)
const DUST := Color(0.8, 0.72, 0.58, 0.5)
const GOLD := Color(1.0, 0.82, 0.36)
const SOFT := Color(0.86, 0.88, 0.94)

var tile := TILE

var _city: Node3D
var _font_bold: Font
var _font_black: Font
var _mats := {}

## Everything that pops up: {"node": Node3D, "s": float (route distance), "shown": bool}
var _items: Array[Dictionary] = []
## The parts of town, in flight order: {"kicker": String, "s": float}
var _parts: Array[Dictionary] = []
var _part := -1
## The flight: points the camera looks at, and the distance along it to each.
var _route: Array[Vector3] = []
var _route_s: Array[float] = []
var _length := 0.0
var _speed := SPEED

var _flying := false
var _progress := 0.0
var _hold := 0.0
var _cam: Camera3D
var _look := Vector3.ZERO
var _next_pop := 0.0

# looked up once in setup()
var _road := {}                 # Vector2i -> world point (road tile centre)
var _road_origin := Vector3.ZERO
var _flat: Array[AABB] = []     # ground, sidewalks, roads: what things stand on
var _ground_y := -1.94

# the card
var _ui: CanvasLayer
var _card: ColorRect
var _card_rows: VBoxContainer
var _tip_rows: Array[Control] = []


func _ready() -> void:
	set_process(false)


func setup(city: Node3D, font_bold: Font, font_black: Font) -> void:
	_city = city
	_font_bold = font_bold
	_font_black = font_black
	if _city == null:
		return   # no city: only the card
	var park := _city.get_node_or_null(PARK) as Node3D
	if park:
		tile = absf(park.global_basis.get_scale().x)
	_index_roads()
	_index_ground()

	var lots := _lot_sites()
	var park_sites := _park_sites()
	var main := _main_street_sites()

	# the flight: lots first (finishing near the park), then along the park,
	# then down Main Street
	var park_mid := park.to_global(PARK_CENTRE) if park else Vector3.ZERO
	var order: Array[Dictionary] = []
	if not lots.is_empty():
		var start := lots[0]
		for l in lots:
			if _flat_dist(l.at, park_mid) > _flat_dist(start.at, park_mid):
				start = l
		order.append_array(_greedy(lots, start.at))
		for s in order:
			_add_waypoint(s.at)
		_parts.append({"kicker": "EMPTY LOTS", "first": order[0]})
	if park and not park_sites.is_empty():
		var a := park.to_global(PARK_ENDS[0])
		var b := park.to_global(PARK_ENDS[1])
		if not _route.is_empty() and _flat_dist(_route.back(), b) < _flat_dist(_route.back(), a):
			var t := a
			a = b
			b = t
		var entry := {"at": a, "items": []}
		_parts.append({"kicker": "CENTRAL PARK", "first": entry})
		_add_waypoint(a)
		_add_waypoint(b)
		order.append(entry)
		order.append_array(park_sites)
	if not main.is_empty():
		var from: Vector3 = _route.back() if not _route.is_empty() else main[0].at
		var ms := _greedy(main, from)
		_parts.append({"kicker": "MAIN STREET", "first": ms[0]})
		for s in ms:
			_add_waypoint(s.at)
		order.append_array(ms)

	# every fence and board gets the route distance where it should pop up
	for site in order:
		var stagger := 0.0
		for n: Node3D in site.items:
			_items.append({"node": n, "s": _project(n.global_position) + stagger, "shown": false})
			stagger += 0.05
	_items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.s < y.s)
	for p in _parts:
		p.s = _project((p.first as Dictionary).at)
		p.erase("first")
	_speed = maxf(SPEED, (_length + LEAD) / MAX_TIME)


func has_sites() -> bool:
	return not _items.is_empty()


func _add_waypoint(p: Vector3) -> void:
	if not _route.is_empty():
		var d := _flat_dist(_route.back(), p)
		if d < 0.05 * tile:
			return
		_length += d
	_route.append(p)
	_route_s.append(_length)


## Nearest-neighbour order through `sites`, starting nearest to `from`.
func _greedy(sites: Array[Dictionary], from: Vector3) -> Array[Dictionary]:
	var left := sites.duplicate()
	var out: Array[Dictionary] = []
	var at := from
	while not left.is_empty():
		var best := 0
		for i in left.size():
			if _flat_dist(left[i].at, at) < _flat_dist(left[best].at, at):
				best = i
		var s: Dictionary = left[best]
		left.remove_at(best)
		out.append(s)
		at = s.at
	return out


## Distance along the route to the point on it nearest `p`.
func _project(p: Vector3) -> float:
	if _route.size() < 2:
		return 0.0
	var best_s := 0.0
	var best_d := INF
	for i in _route.size() - 1:
		var a := _flat3(_route[i])
		var b := _flat3(_route[i + 1])
		var ab := b - a
		var k := clampf((_flat3(p) - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := (a + ab * k).distance_to(_flat3(p))
		if d < best_d - 0.001:
			best_d = d
			best_s = lerpf(_route_s[i], _route_s[i + 1], k)
	return best_s


func _route_point(s: float) -> Vector3:
	if _route.is_empty():
		return Vector3.ZERO
	if s <= 0.0 or _route.size() == 1:
		return _route[0]
	for i in _route.size() - 1:
		if s <= _route_s[i + 1]:
			var span := maxf(_route_s[i + 1] - _route_s[i], 0.0001)
			return _route[i].lerp(_route[i + 1], (s - _route_s[i]) / span)
	return _route.back()


# ================================================================ the flight

## [eye, look]: above the first stop, looking down at it.
func start_shot() -> Array:
	var look := _route_point(0.0)
	return [look + CAM_DIR.normalized() * CAM_DIST * tile, look]


func fly(cam: Camera3D) -> void:
	_cam = cam
	_look = _route_point(0.0)
	_progress = -LEAD * 0.6 * tile   # a moment to settle before the first one
	_hold = 0.0
	_next_pop = 0.0
	_flying = true
	set_process(true)


func is_done() -> bool:
	return not _flying


## Stop flying and put everything up at once (the player clicked past it).
func finish() -> void:
	_flying = false
	set_process(false)
	for it in _items:
		if not it.shown:
			it.shown = true
			var n: Node3D = it.node
			n.visible = true
			n.scale = Vector3.ONE


func _process(delta: float) -> void:
	if not _flying:
		return
	_progress = minf(_progress + _speed * tile * delta, _length)
	var want := _route_point(maxf(_progress, 0.0))
	_look = _look.lerp(want, 1.0 - exp(-delta * 1.4))
	if _cam:
		_cam.look_at_from_position(_look + CAM_DIR.normalized() * CAM_DIST * tile, _look, Vector3.UP)
	# the next part of town
	while _part + 1 < _parts.size() and _progress >= float(_parts[_part + 1].s) - LEAD * tile:
		_part += 1
		kicker_changed.emit(String(_parts[_part].kicker))
	# pop up whatever the camera is about to reach, one at a time
	_next_pop -= delta
	var all_up := true
	for it in _items:
		if it.shown:
			continue
		all_up = false
		if _next_pop > 0.0 or float(it.s) > _progress + LEAD * tile:
			break
		it.shown = true
		_pop(it.node)
		_next_pop = POP_GAP
		break
	if all_up and _progress >= _length:
		_hold += delta
		if _hold > 1.8:
			_flying = false
			set_process(false)


## Grow from nothing, a little past full size and back, with a puff of dust.
func _pop(n: Node3D) -> void:
	n.visible = true
	n.scale = Vector3.ONE * 0.001
	var t := create_tween()
	t.tween_property(n, "scale", Vector3.ONE * 1.1, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_puff(n.global_position, float(n.get_meta("width", 0.5)))


func _puff(at: Vector3, width: float) -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = at + Vector3.UP * 0.02 * tile
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 14
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(width * 0.5, 0.01, 0.06) * tile
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.08 * tile
	p.initial_velocity_max = 0.2 * tile
	p.gravity = Vector3(0, -0.05 * tile, 0)
	p.damping_min = 0.1 * tile
	p.damping_max = 0.2 * tile
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.07 * tile
	var m := StandardMaterial3D.new()
	m.albedo_color = DUST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


# ================================================================ the sites

## Lots: every civic lot nothing was built on, then vacant blocks in the grid.
func _lot_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taken: Array[Rect2] = []
	for n in _city.find_children("*", "Node3D", true, false):
		if not n.has_method("is_built") or n.is_built() or n.get("lot_half_size") == null:
			continue
		if int(n.get("stage") if n.get("stage") != null else 0) != 0:
			continue   # going up already
		var b := n as Node3D
		var s := absf(b.global_basis.get_scale().x)
		var half := float(b.get("lot_half_size")) * s * 0.97
		var y := b.global_position.y + 0.012 * s
		var ax := _flat3(b.global_basis.x).normalized()
		var az := _flat3(b.global_basis.z).normalized()
		var c := Vector3(b.global_position.x, y, b.global_position.z)
		out.append(_fence_square(c, ax, az, half, half, az))
		taken.append(Rect2(c.x - half * 1.2, c.z - half * 1.2, half * 2.4, half * 2.4))
	for v in _vacant_cells(taken):
		out.append(v)
	return out


## Blocks in the street grid with streets on two opposite sides (or three
## sides) and nothing at all standing on them, spread out, at most MAX_VACANT.
func _vacant_cells(taken: Array[Rect2]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _road.size() < 4:
		return out
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for k: Vector2i in _road:
		lo = Vector2i(mini(lo.x, k.x), mini(lo.y, k.y))
		hi = Vector2i(maxi(hi.x, k.x), maxi(hi.y, k.y))
	var occupied := _occupied_cells()
	var free: Array[Vector2i] = []
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var k := Vector2i(x, z)
			if _road.has(k) or occupied.has(k):
				continue
			var l := _road.has(k + Vector2i(-1, 0))
			var r := _road.has(k + Vector2i(1, 0))
			var u := _road.has(k + Vector2i(0, -1))
			var d := _road.has(k + Vector2i(0, 1))
			var sides := int(l) + int(r) + int(u) + int(d)
			if not ((l and r) or (u and d) or sides >= 3):
				continue
			var c := _cell_centre(k)
			var cell := Rect2(c.x - tile * 0.46, c.z - tile * 0.46, tile * 0.92, tile * 0.92)
			var blocked := false
			for t in taken:
				if t.intersects(cell):
					blocked = true
					break
			if not blocked:
				free.append(k)
	# spread them out: each pick as far as possible from the ones before
	var picks: Array[Vector2i] = []
	while picks.size() < MAX_VACANT and not free.is_empty():
		var best := 0
		if not picks.is_empty():
			var best_d := -1.0
			for i in free.size():
				var dmin := INF
				for p in picks:
					dmin = minf(dmin, Vector2(free[i] - p).length())
				if dmin > best_d:
					best_d = dmin
					best = i
		picks.append(free[best])
		free.remove_at(best)
	for k in picks:
		var c := _cell_centre(k)
		c.y = _ground_at(c)
		var face := Vector3.BACK
		for dir in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
			if _road.has(k + dir):
				face = Vector3(dir.x, 0, dir.y)
				break
		var half := tile * 0.42
		out.append(_fence_square(c, Vector3.RIGHT, Vector3.BACK, half, half, face))
	return out


## Fences outside every hedge round Central Park, plus a board on the
## longest stretch of each long side.
func _park_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var park := _city.get_node_or_null(PARK) as Node3D
	var hedges := _city.get_node_or_null(PARK_HEDGES)
	if park == null or hedges == null:
		return out
	var mid := park.to_global(PARK_CENTRE)
	var lines: Array[Dictionary] = []
	for h in hedges.get_children():
		var mi := h as MeshInstance3D
		if mi == null:
			continue
		var bb := mi.global_transform * mi.get_aabb()
		var along_x := bb.size.x >= bb.size.z
		var length := bb.size.x if along_x else bb.size.z
		var thick := bb.size.z if along_x else bb.size.x
		var c := bb.get_center()
		var out_dir := Vector3(0, 0, signf(c.z - mid.z)) if along_x else Vector3(signf(c.x - mid.x), 0, 0)
		if out_dir == Vector3.ZERO:
			continue
		var on := c + out_dir * (thick * 0.5 + 0.17 * tile)
		on.y = _ground_at(on)
		lines.append({"c": on, "along": Vector3.RIGHT if along_x else Vector3.BACK,
			"length": length * 0.97, "out": out_dir})
	# go round the park: sort by angle about its middle
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return atan2((a.c as Vector3).z - mid.z, (a.c as Vector3).x - mid.x) \
			< atan2((b.c as Vector3).z - mid.z, (b.c as Vector3).x - mid.x))
	var best_ns := {}   # out.z sign -> line with the longest length
	for ln in lines:
		var o: Vector3 = ln.out
		if absf(o.z) > 0.5:
			var key := int(signf(o.z))
			if not best_ns.has(key) or float(ln.length) > float(best_ns[key].length):
				best_ns[key] = ln
	for ln in lines:
		var items: Array[Node3D] = []
		items.append_array(_fence_line(ln.c, ln.along, ln.length, ln.out))
		if best_ns.values().has(ln):
			items.append(_sign((ln.c as Vector3) + (ln.out as Vector3) * 0.05 * tile, ln.out))
		out.append({"at": ln.c, "items": items})
	return out


## A fence and a board in front of a few Main Street buildings, on the side
## that faces the street.
func _main_street_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := _city.get_node_or_null(MAIN_STREET)
	if root == null or _road.is_empty():
		return out
	var cands: Array[Dictionary] = []
	for b in root.get_children():
		if not b is Node3D:
			continue
		var bb := _visual_bounds(b as Node3D)
		if bb.size == Vector3.ZERO:
			continue
		cands.append({"bb": bb, "at": bb.get_center()})
	# spread out along the street
	var picks: Array[Dictionary] = []
	while picks.size() < MAIN_STREET_SITES and not cands.is_empty():
		var best := 0
		if not picks.is_empty():
			var best_d := -1.0
			for i in cands.size():
				var dmin := INF
				for p in picks:
					dmin = minf(dmin, _flat_dist(cands[i].at, p.at))
				if dmin > best_d:
					best_d = dmin
					best = i
		picks.append(cands[best])
		cands.remove_at(best)
	for p in picks:
		var bb: AABB = p.bb
		var c := bb.get_center()
		var road: Vector3 = _road[_nearest_road(c)]
		var to := _flat3(road - c)
		var face := Vector3(signf(to.x), 0, 0) if absf(to.x) >= absf(to.z) else Vector3(0, 0, signf(to.z))
		if face == Vector3.ZERO:
			face = Vector3.BACK
		var along := Vector3(absf(face.z), 0, absf(face.x))
		var half_depth := absf((bb.size * 0.5).dot(face))
		var half_width := absf((bb.size * 0.5).dot(along))
		var front := c.dot(face) + half_depth
		var road_edge := road.dot(face) - tile * 0.5
		var gap := road_edge - front
		var off := clampf(gap * 0.5, 0.035 * tile, 0.2 * tile) if gap > 0.0 else 0.035 * tile
		var at := c + face * (half_depth + off)
		at.y = _ground_at(at)
		var items: Array[Node3D] = []
		items.append_array(_fence_line(at, along, half_width * 2.0 * 0.92, face))
		items.append(_sign(at + face * 0.05 * tile, face))
		out.append({"at": at, "items": items})
	return out


## A square of fence round `c` (half sizes along ax and az), with a board in
## front of the side facing `face`.
func _fence_square(c: Vector3, ax: Vector3, az: Vector3, hx: float, hz: float, face: Vector3) -> Dictionary:
	var items: Array[Node3D] = []
	var sides := [[az, ax, hz, hx], [ax, az, hx, hz], [-az, ax, hz, hx], [-ax, az, hx, hz]]
	# start with the side facing the street, so the board comes up early
	var first := 0
	for i in sides.size():
		if (sides[i][0] as Vector3).dot(face) > (sides[first][0] as Vector3).dot(face):
			first = i
	for j in sides.size():
		var sd: Array = sides[(first + j) % sides.size()]
		var n: Vector3 = sd[0]
		var along: Vector3 = sd[1]
		var at := c + n * float(sd[2])
		at.y = c.y
		items.append_array(_fence_line(at, along, float(sd[3]) * 2.0, n))
		if j == 0:
			items.append(_sign(at + n * 0.05 * tile, n))
	return {"at": c, "items": items}


# ================================================================ building it

## A straight fence centred on `at`, `length` long along `along`, its outer
## face toward `out`, split into stretches that each pop up on their own.
func _fence_line(at: Vector3, along: Vector3, length: float, out: Vector3) -> Array[Node3D]:
	var runs: Array[Node3D] = []
	var count := maxi(1, ceili(length / (RUN_MAX * tile)))
	var each := length / count
	for i in count:
		var c := at + along * (-length * 0.5 + each * (i + 0.5))
		c.y = at.y
		runs.append(_fence_run(c, each, out))
	return runs


func _fence_run(c: Vector3, length: float, out: Vector3) -> Node3D:
	var run := Node3D.new()
	run.name = "ContractorFence"
	add_child(run)
	# local x along the fence, local +z out toward `out`
	var z := _flat3(out).normalized()
	if z == Vector3.ZERO:
		z = Vector3.BACK
	run.global_transform = Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), c)
	var t := tile
	var h := FENCE_H * t
	_box(run, Vector3(length, h * 0.84, 0.012 * t), Vector3(0, h * 0.46, 0), _mat(HOARDING, 0.85))
	_box(run, Vector3(length + 0.004 * t, h * 0.15, 0.016 * t), Vector3(0, h * 0.9, 0), _mat(BAND, 0.6))
	var posts := maxi(2, roundi(length / (POST_GAP * t)) + 1)
	for i in posts:
		var px := lerpf(-length * 0.5, length * 0.5, float(i) / (posts - 1))
		_box(run, Vector3(0.016 * t, h * 1.02, 0.022 * t), Vector3(px, h * 0.51, 0), _mat(POST, 0.5))
	run.set_meta("width", length / t)
	run.visible = false
	return run


## "COMING SOON: 12 FLOORS" on a yellow board on two posts, facing `out`
## (lettered on both sides, so it reads from wherever the camera is).
func _sign(at: Vector3, out: Vector3) -> Node3D:
	var s := Node3D.new()
	s.name = "ComingSoon"
	add_child(s)
	var z := _flat3(out).normalized()
	if z == Vector3.ZERO:
		z = Vector3.BACK
	s.global_transform = Transform3D(Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z), at)
	var t := tile
	var w := SIGN_W * t
	var hb := SIGN_H * t
	var top := SIGN_TOP * t
	var cy := top - hb * 0.5
	var dark := _mat(Color(0.2, 0.2, 0.22), 0.6)
	for px in [-w * 0.36, w * 0.36]:
		_box(s, Vector3(0.02 * t, top, 0.02 * t), Vector3(px, top * 0.5, -0.016 * t), dark)
	_box(s, Vector3(w + 0.02 * t, hb + 0.02 * t, 0.012 * t), Vector3(0, cy, 0), _mat(Color(0.96, 0.96, 0.94), 0.6))
	_box(s, Vector3(w, hb, 0.018 * t), Vector3(0, cy, 0), _mat(SIGN_YELLOW, 0.5))
	_box(s, Vector3(w, hb * 0.07, 0.02 * t), Vector3(0, cy + hb * 0.42, 0), _mat(SIGN_RED, 0.5))
	for back in [false, true]:
		var face := Node3D.new()
		s.add_child(face)
		face.position = Vector3(0, cy, (-0.0105 if back else 0.0105) * t)
		face.rotation.y = PI if back else 0.0
		var top_line := _text3d("COMING SOON:", w * 0.62, hb * 0.2, SIGN_RED)
		top_line.position = Vector3(0, hb * 0.17, 0)
		face.add_child(top_line)
		var big := _text3d("12 FLOORS", w * 0.86, hb * 0.38, INK)
		big.position = Vector3(0, -hb * 0.17, 0)
		face.add_child(big)
	s.set_meta("width", SIGN_W)
	s.visible = false
	return s


## Flat lettering about `width` wide (and no taller than `height`).
func _text3d(text: String, width: float, height: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if _font_black:
		l.font = _font_black
	l.font_size = 96
	l.outline_size = 0
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.no_depth_test = false
	var px_w := 96.0 * 0.74 * text.length()
	var px_h := 96.0 * 0.95
	if _font_black:
		var size := _font_black.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 96)
		px_w = size.x
		px_h = maxf(size.y * 0.8, 1.0)
	l.pixel_size = minf(width / maxf(px_w, 1.0), height / px_h)
	return l


# ================================================================ the town

func _index_roads() -> void:
	_road.clear()
	var roads := _city.get_node_or_null(ROADS)
	if roads == null:
		return
	var first := true
	for r in roads.get_children():
		if not r is Node3D:
			continue
		var nm := String(r.name)
		if not (nm.begins_with("road") or nm.begins_with("civic_")):
			continue   # (the parked cars live in Roads too)
		var p := (r as Node3D).global_position
		if first:
			_road_origin = p
			first = false
		_road[_key(p)] = p


func _key(p: Vector3) -> Vector2i:
	return Vector2i(roundi((p.x - _road_origin.x) / tile), roundi((p.z - _road_origin.z) / tile))


func _cell_centre(k: Vector2i) -> Vector3:
	return Vector3(_road_origin.x + k.x * tile, _road_origin.y, _road_origin.z + k.y * tile)


func _nearest_road(p: Vector3) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for k in _road:
		var d := _flat_dist(_road[k], p)
		if d < best_d:
			best_d = d
			best = k
	return best


## What things stand on: the city ground, every district's sidewalks and
## lawns, and the road tiles.
func _index_ground() -> void:
	_flat.clear()
	var g := _city.get_node_or_null(CITY_GROUND) as MeshInstance3D
	if g:
		_ground_y = (g.global_transform * g.get_aabb()).end.y
	for n in _city.find_children("*", "VisualInstance3D", true, false):
		var v := n as VisualInstance3D
		if v == g or not _under_ground_or_road(v):
			continue
		var bb := v.global_transform * v.get_aabb()
		if bb.size.y < 0.25 * tile:
			_flat.append(bb)


func _under_ground_or_road(n: Node) -> bool:
	var p := n.get_parent()
	var child := n
	while p and p != _city:
		if p.name == &"Ground":
			return true
		if p.name == &"Roads":
			var nm := String(child.name)
			return nm.begins_with("road") or nm.begins_with("civic_")
		child = p
		p = p.get_parent()
	return false


func _ground_at(p: Vector3) -> float:
	var y := _ground_y
	for bb in _flat:
		if p.x >= bb.position.x and p.x <= bb.end.x and p.z >= bb.position.z and p.z <= bb.end.z:
			y = maxf(y, bb.end.y)
	return y


## Grid cells that something visible stands on (for finding empty blocks).
func _occupied_cells() -> Dictionary:
	var out := {}
	for n in _city.find_children("*", "VisualInstance3D", true, false):
		var v := n as VisualInstance3D
		if not v.is_visible_in_tree() or is_ancestor_of(v):
			continue
		if _under_ground_or_road(v) or String(v.name) == "CityGround":
			continue
		var bb := v.global_transform * v.get_aabb()
		if bb.size.y < 0.03 * tile or bb.end.y < _ground_y + 0.03 * tile:
			continue   # flat: a puddle, a crack, a patch of mud
		var a := _key(bb.position + Vector3(0.05, 0, 0.05) * tile)
		var b := _key(bb.end - Vector3(0.05, 0, 0.05) * tile)
		if (b.x - a.x + 1) * (b.y - a.y + 1) > 400:
			continue   # something huge (the sea, a backdrop), not a building
		for x in range(a.x, b.x + 1):
			for z in range(a.y, b.y + 1):
				out[Vector2i(x, z)] = true
	return out


func _visual_bounds(n: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


# ================================================================ the card

## On black: BUREAUCRACY 0, THE CONTRACTOR'S TOWN, and what happened (TEXT).
## Returns once it has faded in; show_tip() adds the tip under it.
func show_card(ui: CanvasLayer) -> void:
	_ui = ui
	_card = ColorRect.new()
	_card.name = "ContractorTown"
	_card.color = Color(0.02, 0.025, 0.05)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_card)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(centre)
	_card_rows = VBoxContainer.new()
	_card_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_rows.add_theme_constant_override("separation", 12)
	_card_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_card_rows)

	var head := _label("BUREAUCRACY  ·  0", _spaced(_font_black, 6), 18, GOLD)
	var title := _label("THE CONTRACTOR'S TOWN", _spaced(_font_black, 8), 48, Color.WHITE)
	var rule := _rule()
	var body := _label(TEXT, _font_bold, 25, SOFT, 960.0)
	var rows: Array[Control] = [head, title, rule, body]
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_head := _label("TIP", _spaced(_font_black, 6), 16, GOLD)
	var tip := _label(TIP, _font_bold, 21, Color(1, 1, 1, 0.92), 880.0)
	_tip_rows = [gap, tip_head, tip]
	for r in rows + _tip_rows:
		r.modulate.a = 0.0
		_card_rows.add_child(r)

	_card.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_card, "modulate:a", 1.0, 0.9)
	t.tween_property(head, "modulate:a", 1.0, 0.4)
	t.tween_property(title, "modulate:a", 1.0, 0.6)
	t.tween_property(rule, "modulate:a", 1.0, 0.3)
	t.tween_property(body, "modulate:a", 1.0, 1.0)
	await t.finished


func show_tip() -> void:
	var t := create_tween()
	t.tween_interval(0.6)
	for r in _tip_rows:
		t.tween_property(r, "modulate:a", 1.0, 0.6)
	await t.finished


## "Click to start again", then the game starts over.
func wait_restart() -> void:
	var again := _label("Click to start again", _font_bold, 18, Color(1, 1, 1, 0.6))
	again.modulate.a = 0.0
	_card_rows.add_child(again)
	await get_tree().create_timer(0.8).timeout
	var t := create_tween()
	t.tween_property(again, "modulate:a", 1.0, 0.5)
	await t.finished
	var pulse := create_tween().set_loops()
	pulse.tween_property(again, "modulate:a", 0.35, 0.8)
	pulse.tween_property(again, "modulate:a", 1.0, 0.8)
	# polled, so it works wherever this node lives (the city is in a SubViewport)
	var was_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	while true:
		await get_tree().process_frame
		var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if down and not was_down:
			break
		was_down = down
	pulse.kill()
	get_tree().set_meta(StoryIntro.REPLAY_META, true)
	get_tree().change_scene_to_file("res://menu/story_intro.tscn")


func _label(text: String, font: Font, px: int, color: Color, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, px / 7))
	l.add_theme_constant_override("line_spacing", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(72, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row


func _spaced(font: Font, spacing: int) -> Font:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = spacing
	return f


# ================================================================ helpers

func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var key := "%s/%s" % [c.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats[key] = m
	return m


func _flat3(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return _flat3(a - b).length()
