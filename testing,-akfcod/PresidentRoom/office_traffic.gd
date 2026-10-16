extends Node3D
## Visitor traffic for the president's office.
##
## Every few seconds someone appears out of sight in the hallway (behind the
## main door) or the anteroom (behind the side door), walks up, waits for the
## door to swing open, comes in, does a job and leaves through one of the
## doors again. Created by president_room.gd at runtime; everything here is in
## the room's own coordinates (this node sits at the room's origin).
##
## Jobs and where they happen:
##   BRIEF   stand in front of the desk and talk to the president (aides, staffers, generals)
##   SERVE   the steward brings a coffee to the desk, or collects the empty cup
##   GUARD   a Secret Service agent stands watch just inside the door they used
##   BROWSE  look along a bookcase, reaching for a book now and then
##   WARM    warm hands at the fireplace
##   ADMIRE  study a painting, chin in hand

const Visitor := preload("res://PresidentRoom/office_visitor.gd")
const Role := Visitor.Role
const Act := Visitor.Act

## Desk numbers from president_room.gd (DESK_TOP, DESK_Z).
const DESK_TOP := 0.78
const DESK_Z := 0.35
const DOOR_SPEED := 1.25        # door swings fully open in ~0.8 s

var room                     # president_room.gd (untyped: it is a @tool script with its own members)
var visitors: Array = []     # office_visitor.gd instances
## The coffee cup sitting on the desk, if a steward has left one.
var desk_cup: Node3D = null

var _spawn_t := 2.0
var _next_id := 0
var _doors := {}     # door name -> {"centre": Vector3, "hold": float}
var _nodes := {}     # waypoint name -> Vector3
var _edges := {}     # waypoint name -> Array of names
var _spots: Array[Dictionary] = []
var _entries := {}   # door name -> {"spawns": [Vector3], "near": Vector3, "sill": Vector3, "inside": String}


func setup(p_room) -> void:
	room = p_room
	for door_name: String in room.doors:
		var node: Node3D = room.doors[door_name].node
		_doors[door_name] = {"centre": to_local(node.global_position), "hold": 0.0}

	# Walkways through the furniture (x, z). Sofas sit at x = +-2.25 between
	# z = -4.2 and -2.2, the coffee table at z = -2.45, the desk from z = -0.2.
	_nodes = {
		"A": Vector3(0.0, 0, -4.75),     # just inside the main door
		"B": Vector3(3.75, 0, -4.4),     # just inside the side door
		"N": Vector3(0.0, 0, -3.75),     # between the door and the coffee table
		"M1": Vector3(1.22, 0, -2.5),    # between the coffee table and the right sofa
		"M2": Vector3(-1.22, 0, -2.5),
		"S1": Vector3(1.2, 0, -1.35),    # south of the sofas
		"S2": Vector3(-1.2, 0, -1.35),
		"R1": Vector3(3.25, 0, -3.2),    # aisle between the right sofa and the wall
		"R2": Vector3(3.3, 0, -1.5),
		"E1": Vector3(2.75, 0, -0.45),   # beside the globe
		"L1": Vector3(-3.3, 0, -2.4),    # aisle between the left sofa and the fireplace
		"L2": Vector3(-3.25, 0, -1.35),
	}
	for e in [["A", "N"], ["N", "M1"], ["N", "M2"], ["M1", "S1"], ["M2", "S2"], ["S1", "S2"],
			["B", "R1"], ["R1", "R2"], ["R2", "S1"], ["R2", "E1"], ["S1", "E1"], ["S2", "L2"], ["L2", "L1"]]:
		_link(e[0], e[1])

	# Places to do a job. "face": point to turn toward (null = the president).
	_spots = [
		_spot("desk_l", [Act.BRIEF, Act.SERVE], Vector3(-0.5, 0, -0.72), null, ["S2"]),
		_spot("desk_r", [Act.BRIEF], Vector3(0.5, 0, -0.72), null, ["S1"]),
		_spot("books_l", [Act.BROWSE], Vector3(-2.75, 0, -4.55), Vector3(-2.75, 0, -7.0), ["A"]),
		_spot("books_r", [Act.BROWSE], Vector3(2.75, 0, -4.55), Vector3(2.75, 0, -7.0), ["A", "B"]),
		_spot("fire", [Act.WARM, Act.ADMIRE], Vector3(-3.35, 0, -3.7), Vector3(-6.0, 0, -3.7), ["L1"]),
		_spot("cabinet", [Act.ADMIRE], Vector3(3.55, 0, 0.95), Vector3(6.0, 0, 0.95), ["E1"]),
		_spot("guard_main", [Act.GUARD], Vector3(1.25, 0, -5.1), Vector3(0.4, 0, -2.0), ["A"], "MainDoor"),
		_spot("guard_side", [Act.GUARD], Vector3(3.9, 0, -3.55), Vector3(1.5, 0, -2.6), ["B"], "SideDoor"),
	]

	# How to get from out of sight to just inside each door.
	_entries = {
		"MainDoor": {"spawns": [Vector3(-5.5, 0, -6.95), Vector3(5.5, 0, -6.95)],
			"near": Vector3(0.0, 0, -6.6), "sill": Vector3(0.0, 0, -5.6), "inside": "A"},
		"SideDoor": {"spawns": [Vector3(6.95, 0, -0.2), Vector3(6.6, 0, -0.1)],
			"near": Vector3(5.6, 0, -4.4), "sill": Vector3(4.6, 0, -4.4), "inside": "B"},
	}
	_spawn_t = randf_range(1.0, 2.5)


func _spot(n: String, acts: Array, pos: Vector3, face: Variant, links: Array, door := "") -> Dictionary:
	return {"name": n, "acts": acts, "pos": pos, "face": face, "links": links, "door": door, "taken": null}


func _link(a: String, b: String) -> void:
	if not _edges.has(a):
		_edges[a] = []
	if not _edges.has(b):
		_edges[b] = []
	_edges[a].append(b)
	_edges[b].append(a)


# ================================================================ queries used by visitors

func camera_pos() -> Vector3:
	if room and room.camera:
		return to_local(room.camera.global_position)
	return Vector3(0, 1.22, 1.38)


func door_amount(door_name: String) -> float:
	return room.door_amount(door_name)


func door_centre(door_name: String) -> Vector3:
	return _doors[door_name].centre if _doors.has(door_name) else Vector3.ZERO


## Someone close in front, so wait a moment. When two people walk toward each
## other, the newer one gives way.
func is_blocked(v, dir: Vector3) -> bool:
	for o in visitors:
		if o == v or o.state == Visitor.State.GONE:
			continue
		var d: Vector3 = o.position - v.position
		d.y = 0.0
		var dist := d.length()
		if dist > 0.75 or dist < 0.001:
			continue
		if dir.dot(d / dist) < 0.55:
			continue
		if o.is_walking():
			var same_way: bool = o.heading().dot(dir) > 0.3
			if not same_way and v.id < o.id:
				continue
		return true
	return false


## Where a coffee cup sits on the desk (global transform).
func cup_spot() -> Transform3D:
	return global_transform * Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.62, DESK_TOP, DESK_Z - 0.4))


func cup_parent() -> Node3D:
	return self


# ================================================================ update

func _process(delta: float) -> void:
	# doors open for anyone about to walk through them, then close behind
	for door_name: String in _doors:
		var d: Dictionary = _doors[door_name]
		var want := false
		for v in visitors:
			if v.wants_door(door_name, d.centre):
				want = true
				break
			# never shut on someone standing in the doorway
			var p: Vector3 = v.position
			if v.state == Visitor.State.WALK and Vector2(p.x - d.centre.x, p.z - d.centre.z).length() < 0.95:
				want = true
				break
		if want:
			d.hold = 0.6
		else:
			d.hold = maxf(0.0, d.hold - delta)
		var target := 1.0 if d.hold > 0.0 else 0.0
		var amount := move_toward(room.door_amount(door_name), target, delta * DOOR_SPEED)
		room.set_door_open(door_name, amount)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(room.visitor_interval.x, room.visitor_interval.y)
		if visitors.size() < room.max_visitors:
			_spawn()


# ================================================================ spawning

func _count(role: int) -> int:
	var n := 0
	for v in visitors:
		if v.role == role:
			n += 1
	return n


func _spawn() -> void:
	# who comes in (weights), limited to one agent, one general, one steward
	var roles := [Role.AIDE, Role.AIDE, Role.AIDE, Role.STAFFER, Role.STAFFER, Role.STAFFER,
		Role.AGENT, Role.AGENT, Role.GENERAL, Role.STEWARD, Role.STEWARD, Role.STEWARD]
	roles.shuffle()
	for role: int in roles:
		if role in [Role.AGENT, Role.GENERAL, Role.STEWARD] and _count(role) > 0:
			continue
		var acts: Array = _acts_for(role)
		acts.shuffle()
		for act: int in acts:
			var door: String = ["MainDoor", "SideDoor"].pick_random()
			var spot := _free_spot(act, door)
			if spot.is_empty() and act == Act.GUARD:
				door = "SideDoor" if door == "MainDoor" else "MainDoor"
				spot = _free_spot(act, door)
			if spot.is_empty():
				continue
			_send_in(role, act, door, spot)
			return


func _acts_for(role: int) -> Array:
	if role == Role.AIDE:
		return [Act.BRIEF, Act.BRIEF, Act.BROWSE, Act.ADMIRE]
	if role == Role.STAFFER:
		return [Act.BRIEF, Act.BROWSE, Act.ADMIRE, Act.WARM]
	if role == Role.AGENT:
		return [Act.GUARD]
	if role == Role.STEWARD:
		return [Act.SERVE]
	return [Act.BRIEF]


func _free_spot(act: int, door: String) -> Dictionary:
	var options: Array[Dictionary] = []
	for s in _spots:
		if s.taken != null or not (act in s.acts):
			continue
		if s.door != "" and s.door != door:
			continue
		options.append(s)
	return options.pick_random() if not options.is_empty() else {}


func _send_in(role: int, act: int, door: String, spot: Dictionary) -> void:
	var female_chance := 0.25 if role == Role.GENERAL else (0.35 if role == Role.AGENT else 0.5)
	var v := Visitor.new()
	v.name = "Visitor%d" % _next_id
	v.build(role, randf() < female_chance)
	v.id = _next_id
	_next_id += 1
	v.traffic = self
	v.act = act
	v.face_camera = spot.face == null
	v.face_point = spot.face if spot.face != null else Vector3.ZERO
	if act == Act.BRIEF:
		v.act_time = randf_range(7.0, 11.0)
	elif act == Act.GUARD:
		v.act_time = randf_range(14.0, 22.0)
	elif act == Act.SERVE:
		v.act_time = 4.6
	else:
		v.act_time = randf_range(6.0, 11.0)
	if act == Act.SERVE:
		v.face_camera = false
		v.face_point = Vector3(spot.pos.x, 0, 2.0)   # face the desk
		v.bring_cup(desk_cup == null)
	spot.taken = v
	v.set_meta("spot", spot)
	add_child(v)
	visitors.append(v)
	v.finished.connect(_on_finished)

	var e: Dictionary = _entries[door]
	var pts: Array[Vector3] = [(e.spawns as Array).pick_random(), e.near, e.sill, _nodes[e.inside]]
	var doors: Array[String] = ["", "", door, door]
	for n in _route(e.inside, spot.links):
		pts.append(_nodes[n])
		doors.append("")
	pts.append(spot.pos)
	doors.append("")
	v.begin(pts, doors)


## A visitor finished their job: free the spot and walk them out.
func visitor_done(v) -> void:
	var spot: Dictionary = v.get_meta("spot", {})
	spot.taken = null
	# agents and stewards leave the way they came, others pick either door
	var door: String = ["MainDoor", "SideDoor"].pick_random()
	if spot.door != "":
		door = spot.door
	var e: Dictionary = _entries[door]
	var pts: Array[Vector3] = []
	var doors: Array[String] = []
	# route from the spot's nearest link to the inside of the door
	var best: Array = []
	var best_len := INF
	for l: String in spot.links:
		var r := _route(l, [e.inside])
		r.push_front(l)
		var length: float = spot.pos.distance_to(_nodes[l]) + _route_length(r)
		if length < best_len:
			best_len = length
			best = r
	for n: String in best:
		pts.append(_nodes[n])
		doors.append("")
	if pts.is_empty() or pts[-1] != _nodes[e.inside]:
		pts.append(_nodes[e.inside])
		doors.append("")
	pts.append_array([e.sill, e.near, (e.spawns as Array).pick_random()])
	doors.append_array([door, door, ""])
	# the inside point leads straight into the door
	doors[pts.size() - 4] = door
	v.leave(pts, doors)


func _on_finished(v) -> void:
	visitors.erase(v)
	var spot: Dictionary = v.get_meta("spot", {})
	if spot.get("taken") == v:
		spot.taken = null
	v.queue_free()


# ================================================================ routes

## Shortest chain of waypoint names from `from` (exclusive) to the best of
## `goals` (inclusive). Dijkstra on a dozen nodes.
func _route(from: String, goals: Array) -> Array:
	if from in goals:
		return []
	var dist := {from: 0.0}
	var prev := {}
	var open: Array[String] = [from]
	var done := {}
	while not open.is_empty():
		open.sort_custom(func(a: String, b: String) -> bool: return dist[a] < dist[b])
		var cur: String = open.pop_front()
		if done.has(cur):
			continue
		done[cur] = true
		if cur in goals:
			var out := []
			var n := cur
			while n != from:
				out.push_front(n)
				n = prev[n]
			return out
		for nb: String in _edges.get(cur, []):
			var nd: float = dist[cur] + (_nodes[cur] as Vector3).distance_to(_nodes[nb])
			if not dist.has(nb) or nd < dist[nb]:
				dist[nb] = nd
				prev[nb] = cur
				open.append(nb)
	return []


func _route_length(names: Array) -> float:
	var total := 0.0
	for i in range(1, names.size()):
		total += (_nodes[names[i - 1]] as Vector3).distance_to(_nodes[names[i]])
	return total
