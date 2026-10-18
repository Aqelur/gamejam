extends Node3D
## Visitor traffic for the president's office.
##
## Two kinds of people come in, out of sight in the hallway (behind the main
## door) or the anteroom (behind the side door). They walk up, wait for the
## door to swing open, come in, do their job and leave through a door again.
## Created by president_room.gd at runtime; everything here is in the room's
## own coordinates (this node sits at the room's origin).
##
##   PROPOSER  an aide, staffer or general brings a proposal. One at a time:
##             they stand in front of the desk, the proposal appears on the
##             paper, and they wait there until the player stamps it. Then they
##             react (bow for APPROVED, head shake for DENIED) and leave, and a
##             while later the next one comes.
##   STEWARD   now and then brings a coffee to the desk, or collects the cup.

signal proposer_arrived(visitor: Node3D)

const Visitor := preload("res://PresidentRoom/office_visitor.gd")
const Role := Visitor.Role
const Act := Visitor.Act

## Desk numbers from president_room.gd (DESK_TOP, DESK_Z).
const DESK_TOP := 0.78
const DESK_Z := 0.35
const DOOR_SPEED := 2.5         # door swings fully open in ~0.4 s
const DOOR_OPEN := "res://assets/audio/office/door_open.wav"
const DOOR_CLOSE := "res://assets/audio/office/door_close.wav"
const DOOR_OPEN_DB := -8.0
const DOOR_CLOSE_DB := -4.0
## Seconds after a stamp before the same proposer hands over the next paper
## (the stamped one is off the desk by then, see proposal_desk.gd).
const NEXT_PAPER_DELAY := 1.5

var room                     # president_room.gd (untyped: it is a @tool script with its own members)
var visitors: Array = []     # office_visitor.gd instances
## The coffee cup sitting on the desk, if a steward has left one.
var desk_cup: Node3D = null

var _next_id := 0
## The person whose proposal is (or soon will be) on the paper.
var proposer: Node3D = null
var _proposer_t := 1.5     # seconds until the next proposer sets off
## No new proposer sets off while true (the day is over, see day_cycle.gd).
var paused := false
var _coffee_t := 20.0      # seconds until the steward may come again
var _doors := {}     # door name -> {"centre": Vector3, "hold": float}
static var _door_open: AudioStream
static var _door_close: AudioStream
static var _door_sounds_loaded := false
var _door_players: Array[AudioStreamPlayer3D] = []
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
	# The proposer stands across the desk, a little right of centre so the
	# nameplate and desk flags don't hide them; the steward serves from the left.
	_spots = [
		_spot("propose", [Act.BRIEF], Vector3(0.3, 0, -0.75), null, ["S1", "S2"]),
		_spot("serve", [Act.SERVE], Vector3(-0.6, 0, -0.72), null, ["S2"]),
	]

	# How to get from out of sight to just inside each door.
	_entries = {
		"MainDoor": {"spawns": [Vector3(-5.5, 0, -6.95), Vector3(5.5, 0, -6.95)],
			"near": Vector3(0.0, 0, -6.6), "sill": Vector3(0.0, 0, -5.6), "inside": "A"},
		"SideDoor": {"spawns": [Vector3(6.95, 0, -0.2), Vector3(6.6, 0, -0.1)],
			"near": Vector3(5.6, 0, -4.4), "sill": Vector3(4.6, 0, -4.4), "inside": "B"},
	}
	_proposer_t = randf_range(1.0, 2.0)
	_coffee_t = randf_range(room.coffee_interval.x, room.coffee_interval.y) * 0.6


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


## The office camera stays the listener while the city viewport covers the
## screen, so a door one-shot would be heard over the map and the endings.
func _hearing_office() -> bool:
	if room == null or room.day_cycle == null:
		return true
	var box: CanvasItem = room.day_cycle.get("_city_box")
	return box == null or not box.visible


func _play_door(opening: bool, at: Vector3) -> void:
	if not _hearing_office():
		return
	if not _door_sounds_loaded:
		_door_sounds_loaded = true
		if ResourceLoader.exists(DOOR_OPEN):
			_door_open = load(DOOR_OPEN) as AudioStream
		if ResourceLoader.exists(DOOR_CLOSE):
			_door_close = load(DOOR_CLOSE) as AudioStream
	var stream := _door_open if opening else _door_close
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = DOOR_OPEN_DB if opening else DOOR_CLOSE_DB
	p.unit_size = 3.5
	p.max_distance = 14.0
	p.position = at
	p.finished.connect(_forget_door.bind(p))
	add_child(p)
	_door_players.append(p)
	p.play()


func _forget_door(p: AudioStreamPlayer3D) -> void:
	_door_players.erase(p)
	if is_instance_valid(p):
		p.queue_free()


## Cut a door sound that started in the office once the view has left.
func _silence_doors_outside() -> void:
	if _hearing_office() or _door_players.is_empty():
		return
	var playing := _door_players.duplicate()
	_door_players.clear()
	for p in playing:
		if is_instance_valid(p):
			p.stop()


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
	_silence_doors_outside()
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
		var was: float = room.door_amount(door_name)
		var amount := move_toward(was, target, delta * DOOR_SPEED)
		room.set_door_open(door_name, amount)
		if was <= 0.02 and amount > was:
			_play_door(true, d.centre)
		elif was >= 0.98 and amount < was:
			_play_door(false, d.centre)

	# the next proposer sets off once the last one has gone
	if proposer == null:
		if not paused:
			_proposer_t -= delta
			if _proposer_t <= 0.0:
				_send_proposer()
	elif proposer.state == Visitor.State.ACT and not proposer.get_meta("presented", false):
		proposer.set_meta("presented", true)
		proposer_arrived.emit(proposer)

	# coffee now and then — not while the tutorial (or the evening) is holding the office
	if not paused:
		_coffee_t -= delta
		if _coffee_t <= 0.0:
			_coffee_t = randf_range(room.coffee_interval.x, room.coffee_interval.y)
			if _count(Role.STEWARD) == 0:
				_send_steward()


# ================================================================ spawning

func _count(role: int) -> int:
	var n := 0
	for v in visitors:
		if v.role == role:
			n += 1
	return n


func _send_proposer() -> void:
	var spot := _free_spot(Act.BRIEF, "")
	if spot.is_empty():
		return
	var role: int = [Role.AIDE, Role.AIDE, Role.STAFFER, Role.STAFFER, Role.GENERAL].pick_random()
	proposer = _send_in(role, Act.BRIEF, ["MainDoor", "SideDoor"].pick_random(), spot)
	proposer.wait_for_decision = true
	proposer.act_time = 1.0e9   # set for real by decide()


func _send_steward() -> void:
	var spot := _free_spot(Act.SERVE, "")
	if spot.is_empty():
		return
	_send_in(Role.STEWARD, Act.SERVE, ["MainDoor", "SideDoor"].pick_random(), spot)


## The player stamped the proposal. With `more` the same proposer stays at
## the desk and hands over the next paper right away; otherwise they react and
## leave, and the next one comes after a pause.
func proposal_decided(approved: bool, more := false) -> void:
	if proposer == null:
		return
	if more:
		get_tree().create_timer(NEXT_PAPER_DELAY).timeout.connect(_hand_next.bind(proposer))
		return
	proposer.decide(approved)
	proposer = null
	_proposer_t = randf_range(room.proposer_interval.x, room.proposer_interval.y)


func _hand_next(v: Node3D) -> void:
	if v == proposer and is_instance_valid(v) and not paused:
		proposer_arrived.emit(v)


## Stop (true) or start again (false) sending proposers in.
func set_paused(on: bool) -> void:
	paused = on
	if not on:
		_proposer_t = randf_range(1.0, 2.0)


func _free_spot(act: int, door: String) -> Dictionary:
	var options: Array[Dictionary] = []
	for s in _spots:
		if s.taken != null or not (act in s.acts):
			continue
		if s.door != "" and s.door != door:
			continue
		options.append(s)
	return options.pick_random() if not options.is_empty() else {}


func _send_in(role: int, act: int, door: String, spot: Dictionary) -> Node3D:
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
	# a proposer waits for the stamp (see office_visitor.gd decide())
	v.act_time = 4.6 if act == Act.SERVE else randf_range(7.0, 11.0)
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
	return v


## A visitor finished their job: free the spot and walk them out.
func visitor_done(v) -> void:
	var spot: Dictionary = v.get_meta("spot", {})
	spot.taken = null
	# spots tied to a door send people out that way, others pick either door
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
	if v == proposer:
		proposer = null
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
