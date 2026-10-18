extends Node3D
## The Old Quarter twenty minutes after the big one: who gets dug out of the
## rubble. Played by day_cycle.gd straight after the Old Quarter itself
## (old_quarter_quake.gd), in the same streets, with the same rubble.
##
## When the quarter came down, some of the people caught inside were not
## killed outright: they are alive under the rubble (old_quarter_quake.gd
## `trapped`). What happens to them depends on one choice:
##
##   interior_police   approved: the police station was built. Its patrol cars
##                     (copies of the station's PatrolCar1..4) come into the
##                     quarter with sirens and flashing lights and go street to
##                     street. At every pile they stop and drop off officers,
##                     who climb on and dig while the car moves on to the next
##                     one. People come up out of the rubble alive. Officers on
##                     the streets also keep the looters away.
##                     denied: nobody comes. A few neighbours dig at one or two
##                     piles with their bare hands, people stand on the rubble
##                     waving for help, and looters run out of the broken shops
##                     with whatever they can carry.
##   People's Awareness  neighbours who know what to do dig more people out
##                     (AWARE_SAVES; only without police).
##
## Deaths = trapped * (POLICE_LOSS with police, ALONE_LOSS without). Damage =
## looting: each building's value * LOOT_SHARE (* LOOT_RUBBLE if it fell). The
## no-police numbers are always worked out too, so the narration can say what
## the officers saved. All fixed by setup() (seeded), before anything moves.
##
## day_cycle.gd drives it:
##   setup(city, oq, ending)  -> false if nobody was trapped (nothing to show)
##   start()                  the cars roll in / the neighbours dig
##   is_done()                the cars have done their rounds / it's over
##   wide_shot(), site_shot() camera spots for day_cycle's _glide
##   later_line(), work_line(), headline(), result()
##   quiet()                  fade the sound out (before the next place)

const EarthquakeEnding := preload("res://PresidentRoom/earthquake_ending.gd")
const Rescuer := preload("res://PresidentRoom/rescuer.gd")
const ROADS := "Roads"
const STATION := "Districts/CivicCenter/Buildings/PoliceStation"
const CARS := ["PatrolCar1", "PatrolCar2", "PatrolCar3", "PatrolCar4"]

## Proposal ids that change what happens here.
const POLICE_ID := "interior_police"

## Share of the trapped who die: with officers digging, and without.
const POLICE_LOSS := 0.22
const ALONE_LOSS := 0.82
## Share of ALONE_LOSS avoided by a fully aware population (neighbours who
## know to listen for voices and dig carefully).
const AWARE_SAVES := 0.15
## Share of each building's value lost to looting (what was left in the rubble
## of a fallen one counts for less).
const LOOT_SHARE_POLICE := 0.004
const LOOT_SHARE_ALONE := 0.035
const LOOT_RUBBLE := 0.5
const VALUE_PER_RESIDENT := 50000.0

## How long after the quake this is set (shown on the clock).
const LATER := 20 * 60 + 40
## Piles shown (the nearest to the crossroads, the rest happen off screen).
const MAX_SITES := 8
## Patrol cars that come (at most the station's four).
const MAX_CARS := 4
## Road tiles of the way in that are shown before the first pile.
const ENTRY_TILES := 7
## Patrol car speed in tiles a second, and how long it waits at a pile.
const CAR_SPEED := 3.2
const DROP_TIME := 0.9
## Traffic (tiles): cars keep LANE right of the road's centre line, stay
## CAR_GAP behind a moving car (CAR_PARKED_GAP behind a parked one while they
## wait to go round it), and count as in each other's way within CAR_WIDTH
## side to side.
const LANE := 0.2
const CAR_GAP := 0.75
const CAR_PARKED_GAP := 0.9
const CAR_WIDTH := 0.3
## Officers dropped at each pile.
const CREW := 2
## Seconds of digging before the first person comes up, and between people.
const DIG_FIRST := 2.6
const DIG_NEXT := 1.6
## Without police: piles neighbours dig at, how slowly, and looters.
const NEIGHBOUR_SITES := 2
const NEIGHBOUR_FIRST := 7.5
const LOOTERS := 5
## Longest the place plays (seconds).
const MAX_TIME := 18.0
const PEOPLE_SCALE := 1.1
const MIX_RATE := 22050.0

var tile := 26.926893
var ground_y := -0.7273283
var police := false

## The totals, ready after setup().
var trapped := 0
var dead := 0
var saved := 0
var damage := 0.0
## What it would have been with no police (= the totals without police).
var alone_dead := 0
var alone_damage := 0.0

var _city: Node3D
var _oq                          # old_quarter_quake.gd
var _focus := Vector3.ZERO
var _sites: Array[Dictionary] = []
var _standing: Array[Dictionary] = []
var _fx: Node3D
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _started := false
var _cars: Array[Dictionary] = []
var _road := {}                  # Vector2i -> world position of the road tile
var _road_origin := Vector3.ZERO
var _entry := Vector2i.ZERO      # where the cars come in from
var _have_roads := false
var _rescues_left := 0
var _parked := {}                # road tile -> cars already stopped there

# sound
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _volume := 1.0
var _siren := 0.0
var _siren_t := 0.0
var _siren_phase := 0.0
var _brown := 0.0
var _low := 0.0


func _init() -> void:
	_rng.seed = 9110
	set_process(false)


## Work out the rescue from the choices made during the game. `oq` is the
## old_quarter_quake.gd that just played, `ending` the earthquake_ending.gd.
## Returns false when nobody was trapped.
func setup(city: Node3D, oq, ending) -> bool:
	_city = city
	_oq = oq
	if oq == null or int(oq.trapped) <= 0:
		return false
	tile = oq.tile
	ground_y = oq.ground_y
	_focus = oq.focus
	police = ending.approved(POLICE_ID)
	var aware := clampf(ending.stat("awareness") / 100.0, 0.0, 1.0)
	_index_roads()

	# the piles, nearest the crossroads and the road first
	var all: Array[Dictionary] = oq.trapped_sites()
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _site_score(a) < _site_score(b))
	var alone_rate := ALONE_LOSS * (1.0 - AWARE_SAVES * aware)
	for e in all:
		var n := int(e.trapped)
		var luck := _rng.randf_range(0.9, 1.1)
		var lost_alone := clampi(roundi(n * alone_rate * luck), 0, n)
		var lost := clampi(roundi(n * POLICE_LOSS * luck), 0, n) if police else lost_alone
		trapped += n
		dead += lost
		alone_dead += lost_alone
		if _sites.size() < MAX_SITES:
			var box: AABB = e.box
			var c := box.get_center()
			c.y = ground_y
			_sites.append({"box": box, "centre": c, "trapped": n, "saved": n - lost,
				"road": _nearest_road(c), "taken": false})
	saved = trapped - dead

	# looting: shops left open and rubble picked over, with nobody on the streets
	for c in oq._plan:
		var fell := int(c.outcome) == BuildingQuake.Outcome.RAZED
		var value := int(c.residents) * VALUE_PER_RESIDENT * (LOOT_RUBBLE if fell else 1.0)
		alone_damage += value * LOOT_SHARE_ALONE
		damage += value * (LOOT_SHARE_POLICE if police else LOOT_SHARE_ALONE)
		_standing.append(c)
	# looters come out of the nearest buildings, standing ones first
	_standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(a.outcome) == BuildingQuake.Outcome.RAZED
		var rb := int(b.outcome) == BuildingQuake.Outcome.RAZED
		if ra != rb:
			return rb
		return _flat(a.box.get_center()).distance_to(_flat(_focus)) < _flat(b.box.get_center()).distance_to(_flat(_focus)))
	_standing.resize(mini(_standing.size(), 24))
	return not _sites.is_empty()


func saved_lives() -> int:
	return maxi(0, alone_dead - dead)


func saved_money() -> float:
	return maxf(0.0, alone_damage - damage)


# ================================================================ lines

## Read as the place starts.
func later_line() -> String:
	if police:
		return "Twenty minutes later, back in the *Old Quarter*. %s people are still alive under the rubble, and the sirens are already coming." \
			% EarthquakeEnding.thousands(trapped)
	return "Twenty minutes later, back in the *Old Quarter*. %s people are still alive under the rubble, calling for help. No sirens are coming." \
		% EarthquakeEnding.thousands(trapped)


## Read while the digging goes on.
func work_line() -> String:
	if police:
		return "Patrol cars from the new *police station* go street to street. At every pile they drop off officers, who climb on and dig with their bare hands."
	return "There is no *police station*, and nobody to send. A few neighbours dig with their bare hands while looters slip into the broken shops."


## Read once it's over.
func headline() -> String:
	if police:
		return "The *police* got there in time. Officers pulled %s out of the rubble alive, about %s more than anyone else could have." \
			% [_people(saved), EarthquakeEnding.thousands(saved_lives())]
	if saved <= 0:
		return "Without a *police station* there weren't enough hands. Nobody was dug out alive: %s died under the rubble waiting for help." \
			% _people(dead)
	return "Without a *police station* there weren't enough hands. Only %s dug out alive, and %s died under the rubble waiting for help." \
		% [_people(saved) + (" was" if saved == 1 else " were"), EarthquakeEnding.thousands(dead)]


static func _people(n: int) -> String:
	return "1 person" if n == 1 else "%s people" % EarthquakeEnding.thousands(n)


## The result for earthquake_ending.gd. `note` is printed under the toll,
## `of` replaces "people" after the dead ("DEAD · of 240 trapped").
func result() -> Dictionary:
	var note := ""
	if police:
		note = "OFFICERS SAVED ~%s LIVES  ·  LOOTING STOPPED" % EarthquakeEnding.thousands(saved_lives())
	else:
		note = "NO POLICE STATION  ·  %s DUG OUT ALIVE  ·  SHOPS LOOTED" % EarthquakeEnding.thousands(saved)
	return {"place": "Under the Rubble", "residents": trapped, "dead": dead, "damage": damage,
		"of": "trapped", "damage_label": "LOOTED", "note": note}


# ================================================================ shots

## High over the quarter, looking down the way the cars come in.
func wide_shot() -> Array:
	var c := _sites_centre()
	var from := _flat3(_entry_pos() - c).normalized()
	if from == Vector3.ZERO:
		from = Vector3(0.38, 0.0, 0.92).normalized()
	var side := from.cross(Vector3.UP).normalized()
	var eye := c + from * 5.0 * tile + side * 2.5 * tile + Vector3.UP * 4.2 * tile
	return [eye, c + Vector3.UP * 0.2 * tile, -side * 0.8 * tile]


## Down by the busiest pile, from the road side.
func site_shot() -> Array:
	var s: Dictionary = _sites[0]
	var road: Vector3 = _road_pos(s.road) if _have_roads else s.centre + Vector3.RIGHT * 2.0 * tile
	var out := _flat3(road - s.centre).normalized()
	if out == Vector3.ZERO:
		out = Vector3.RIGHT
	var side := out.cross(Vector3.UP).normalized()
	var eye: Vector3 = s.centre + out * 2.6 * tile + side * 1.6 * tile + Vector3.UP * 1.5 * tile
	return [eye, s.centre + Vector3.UP * 0.15 * tile, side * 0.5 * tile]


# ================================================================ play

## The cars roll in (police), or the neighbours start digging (no police).
## People wave for help from every pile nobody has reached yet.
func start() -> void:
	_fx = Node3D.new()
	_fx.name = "RescueFX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D()
	_start_sound()
	_started = true
	_t = 0.0
	set_process(true)
	for s in _sites:
		s.wavers = []
		for i in (2 if int(s.trapped) > 6 else 1):
			s.wavers.append(_waver(s))
	if police:
		_send_cars()
	else:
		_neighbours()
		_looters()


func is_done() -> bool:
	if not _started:
		return false
	if _t >= MAX_TIME:
		return true
	if not police:
		return _t >= NEIGHBOUR_FIRST + 5.0
	for c in _cars:
		if not c.done:
			return false
	return _rescues_left <= 0


func quiet(time := 1.2) -> void:
	var t := create_tween()
	t.tween_property(self, "_volume", 0.0, time)


func _process(delta: float) -> void:
	_t += delta
	var driving := false
	for c in _cars:
		_tick_lights(c)
		if c.driving:
			driving = true
	# sirens while a car is on the move; quieter once they've all stopped
	var want := 1.0 if driving else (0.25 if police and not _cars.is_empty() else 0.0)
	_siren = move_toward(_siren, want, delta * 0.8)
	_feed_sound()


# ================================================================ police

## Share the piles out between the cars (each takes the nearest one left from
## where it is), then send them in, a few seconds apart.
func _send_cars() -> void:
	var n := mini(MAX_CARS, _sites.size())
	var rounds: Array = []
	for k in n:
		rounds.append([])
	# round-robin by distance from the way in, so every car gets a near one first
	var order := _sites.duplicate()
	var entry := _entry_pos()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _flat(a.centre).distance_to(_flat(entry)) < _flat(b.centre).distance_to(_flat(entry)))
	for i in order.size():
		(rounds[i % n] as Array).append(order[i])
	_rescues_left = order.size()
	for k in n:
		var car := _make_car(k)
		var c := {"node": car, "lights": [], "driving": false, "done": false, "key": _entry, "seed": _rng.randf() * 10.0}
		_flashers(c)
		_cars.append(c)
		_patrol(c, rounds[k], k * 1.1)


func _patrol(c: Dictionary, sites: Array, delay: float) -> void:
	var car: Node3D = c.node
	car.visible = false
	await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree():
		return
	var first := true
	for s in sites:
		var path := _route(c.key, s.road)
		if first:
			# only the last stretch of the way in is shown
			if path.size() > ENTRY_TILES + 1:
				path = path.slice(path.size() - ENTRY_TILES - 1)
			first = false
			# don't pop into view on top of a car that's already there
			var wait := 4.0
			while wait > 0.0 and not _spot_free(c, path[0], 1.0 * tile):
				await get_tree().process_frame
				wait -= get_process_delta_time()
			if not is_inside_tree():
				return
			car.visible = true
			_put_car(c, path[0], path[1] if path.size() > 1 else path[0] + Vector3.LEFT)
		# a car already stopped at this pile: pull up behind it
		var n: int = _parked.get(s.road, 0)
		_parked[s.road] = n + 1
		if n > 0 and path.size() >= 2:
			var back: Vector3 = _flat3(path[path.size() - 2] - path.back()).normalized()
			if back == Vector3.ZERO:
				back = Vector3.RIGHT
			path[path.size() - 1] = path.back() + back * 0.55 * tile * n
		await _drive(c, path)
		if not is_inside_tree():
			return
		c.key = s.road
		_drop_crew(c, s)
		await get_tree().create_timer(DROP_TIME, false).timeout
		if not is_inside_tree():
			return
	c.done = true


## Drive along `path` (road tile centres, world points) at CAR_SPEED, braking
## into the last tile. The car keeps to the right-hand lane (LANE off the
## centre line), so cars going opposite ways pass each other. It slows and
## queues behind a car ahead going its way, and swings out round a car that is
## parked (or stuck) in its lane once the other lane is clear, instead of
## driving through it.
func _drive(c: Dictionary, path: Array) -> void:
	if path.size() < 2 or not is_instance_valid(c.node):
		return
	var car: Node3D = c.node
	c.driving = true
	var top := CAR_SPEED * tile
	var lane := LANE * tile
	var i := 1
	var p: Vector3 = c.get("track", path[0])
	while i < path.size() and is_inside_tree() and is_instance_valid(car):
		await get_tree().process_frame
		var dt := get_process_delta_time()
		var to: Vector3 = _flat3((path[i] as Vector3) - p)
		var dist := to.length()
		var dir: Vector3 = to / dist if dist > 0.001 else (c.heading as Vector3)
		c.heading = dir
		# the lane follows the road round corners, turning with the car
		var seg_right := dir.cross(Vector3.UP).normalized()
		var r: Vector3 = c.right
		r = r.rotated(Vector3.UP, clampf(r.signed_angle_to(seg_right, Vector3.UP), -dt * 4.0, dt * 4.0))
		c.right = r
		var left_total := dist
		for k in range(i, path.size() - 1):
			left_total += _flat((path[k + 1] as Vector3) - (path[k] as Vector3)).length()
		var want := top * clampf(left_total / (1.2 * tile), 0.25, 1.0)

		# --- traffic
		var lat_target := lane
		var ghost: float = c.get("ghost", 0.0)
		var limit := INF      # how far it may go before it has to stop
		if ghost > 0.0:
			c.ghost = ghost - dt
		else:
			var passing = c.get("passing")
			if passing != null:
				# still beside the car it is going round?
				var rel := _flat3((passing.node as Node3D).global_position - car.global_position)
				if rel.dot(dir) < -0.6 * tile or rel.length() > 3.0 * tile:
					c.passing = null
					passing = null
			if passing != null:
				lat_target = -lane
			var ahead := _car_ahead(c, p, dir, r, lat_target)
			var o = ahead.car
			var d: float = ahead.d
			# a car parked just past the end of our run (we pull up behind it)
			if o != null and d > left_total + 0.3 * tile:
				o = null
			if o != null:
				var same_way: bool = o.driving and (o.heading as Vector3).dot(dir) > 0.5 and o.get("passing") == null
				var oncoming: bool = o.driving and (o.heading as Vector3).dot(dir) < -0.5
				if same_way:
					# follow it at a distance
					limit = d - CAR_GAP * tile
					want = minf(want, top * clampf((d - CAR_GAP * tile) / (1.2 * tile), 0.0, 1.0))
				elif oncoming:
					# it's in our lane (going round something): tuck in and let it by
					lat_target = lane + 0.12 * tile
					limit = d - CAR_GAP * tile
					want = minf(want, top * 0.3)
				elif passing == null and d < 3.0 * tile and _lane_clear(c, p, dir, r, -lane, d + 1.4 * tile):
					# parked in our lane: swing out round it
					c.passing = o
					lat_target = -lane
				else:
					# wait behind it until the other lane is clear
					limit = d - CAR_PARKED_GAP * tile
					want = minf(want, top * clampf((d - CAR_PARKED_GAP * tile) / (1.2 * tile), 0.0, 1.0))
			if float(c.v) < 0.05 * tile and want < 0.05 * tile:
				c.stuck = float(c.get("stuck", 0.0)) + dt
				if c.stuck > 3.0:
					# never sit there for good: squeeze by
					c.ghost = 1.5
					c.stuck = 0.0
			else:
				c.stuck = 0.0

		# --- speed, then along the road
		c.v = move_toward(float(c.v), want, (8.0 if want < float(c.v) else 3.0) * tile * dt)
		var step: float = minf(float(c.v) * dt, maxf(0.0, limit))
		while step > 0.0 and i < path.size():
			var seg: Vector3 = _flat3((path[i] as Vector3) - p)
			if seg.length() <= step:
				step -= seg.length()
				p = Vector3((path[i] as Vector3).x, p.y, (path[i] as Vector3).z)
				i += 1
			else:
				p += seg.normalized() * step
				step = 0.0
		c.track = p
		# change lanes while rolling (a little even when stopped, to get round)
		c.lat = move_toward(float(c.lat), lat_target, (float(c.v) * 0.6 + 0.25 * tile) * dt)

		var at := p + r * float(c.lat)
		at.y = (path[mini(i, path.size() - 1)] as Vector3).y
		var move := _flat3(at - car.global_position)
		var rot := car.global_basis.orthonormalized()
		if move.length() > 0.0005 * tile:
			var face := Basis.looking_at(-move.normalized(), Vector3.UP)
			rot = rot.slerp(face, clampf(dt * 8.0, 0.0, 1.0))
		car.global_transform = Transform3D(rot.scaled(Vector3.ONE * tile), at)
	c.v = 0.0
	c.passing = null
	c.driving = false


## The nearest visible car ahead of `c` (on the road at `p`, heading `dir`) in
## the strip `lat` off the centre line: {car, d (how far ahead)}.
func _car_ahead(c: Dictionary, p: Vector3, dir: Vector3, right: Vector3, lat: float) -> Dictionary:
	var me := p + right * lat
	var best := INF
	var who = null
	for o in _cars:
		if o == c or not is_instance_valid(o.node) or not (o.node as Node3D).visible:
			continue
		var rel := _flat3((o.node as Node3D).global_position - me)
		var along := rel.dot(dir)
		if along <= 0.05 * tile or along >= best:
			continue
		if absf(rel.dot(right)) < CAR_WIDTH * tile:
			best = along
			who = o
	return {"car": who, "d": best}


## True if nothing is in the lane `lat` off the centre line from just behind
## the car to `reach` ahead of it.
func _lane_clear(c: Dictionary, p: Vector3, dir: Vector3, right: Vector3, lat: float, reach: float) -> bool:
	var me := p + right * lat
	for o in _cars:
		if o == c or not is_instance_valid(o.node) or not (o.node as Node3D).visible:
			continue
		var rel := _flat3((o.node as Node3D).global_position - me)
		var along := rel.dot(dir)
		if along > -0.7 * tile and along < reach and absf(rel.dot(right)) < CAR_WIDTH * tile:
			return false
	return true


## Two officers hop out and go to the pile; the car moves on.
func _drop_crew(c: Dictionary, s: Dictionary) -> void:
	var car: Node3D = c.node
	var side := car.global_basis.x.normalized()
	for k in CREW:
		var r = Rescuer.new(true)
		r.scale = Vector3.ONE * PEOPLE_SCALE * tile
		_fx.add_child(r)
		var at := car.global_position + side * (0.22 if k == 0 else -0.22) * tile
		r.place(at, ground_y, s.centre - at)
		r.walk_speed = 1.1 * tile
		r.walk_to(_edge_point(s, at, k))
		r.arrived.connect(_on_officer_arrived.bind(s), CONNECT_ONE_SHOT)
	_dust_at(car.global_position, 0.12, 4)


func _on_officer_arrived(r: Node3D, s: Dictionary) -> void:
	r.dig(s.centre - r.global_position)
	if s.taken:
		return
	s.taken = true
	_dig_out(s, DIG_FIRST, DIG_NEXT, true)


# ================================================================ no police

## A couple of neighbours digging by hand at the nearest piles, slowly.
func _neighbours() -> void:
	for i in mini(NEIGHBOUR_SITES, _sites.size()):
		var s: Dictionary = _sites[i]
		s.taken = true
		for k in 2:
			var r = Rescuer.new(false)
			r.scale = Vector3.ONE * PEOPLE_SCALE * tile
			_fx.add_child(r)
			var at := _edge_point(s, s.centre + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 3.0 * tile, k)
			r.place(at, ground_y, s.centre - at)
			r.effort = 0.6
			r.dig(s.centre - at)
		# they reach one, maybe, before the cut
		if i == 0 and int(s.saved) > 0:
			_dig_out(s, NEIGHBOUR_FIRST, 0.0, false, 1)


## Looters run out of the standing shops with boxes in their arms.
func _looters() -> void:
	for i in mini(LOOTERS, _standing.size()):
		_looter_later(_standing[i], 1.0 + i * 1.4 + _rng.randf() * 0.8)


func _looter_later(e: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree():
		return
	var box: AABB = e.box
	var f: Array = _faces(box).pick_random()
	var n: Vector3 = f[1]
	var side := Vector3(n.z, 0, -n.x) * _rng.randf_range(-0.6, 0.6) * float(f[2])
	var at: Vector3 = f[0] + side + n * 0.06 * tile
	at.y = ground_y
	# out of the shop and off down the street or alley, not through the walls
	# (old_quarter_quake.gd knows where the buildings are)
	var route: Array[Vector3] = []
	if _oq and _oq.has_method("_escape_route"):
		for k in 6:
			f = _faces(box).pick_random()
			n = f[1]
			side = Vector3(n.z, 0, -n.x) * _rng.randf_range(-0.6, 0.6) * float(f[2])
			at = f[0] + side + n * 0.08 * tile
			at.y = ground_y
			if _oq._free_run(at, n, e.b) > 0.0:
				route = _oq._escape_route(at, n, e.b, 5.0, 9.0)
				if not route.is_empty():
					break
		if route.is_empty():
			return
	var p := QuakePerson.new()
	p.scale = Vector3.ONE * PEOPLE_SCALE * tile
	_fx.add_child(p)
	var toward: Vector3 = route[0] - at if not route.is_empty() else n.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
	p.start_run(at, toward, ground_y)
	p.run_speed = _rng.randf_range(0.7, 0.95) * tile
	p.run_time = 12.0
	if not route.is_empty():
		p.wobble = 0.06
		p.route = route
	# the loot: a cardboard box held in front
	var loot := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.03, 0.03)
	loot.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.5, 0.3)
	m.roughness = 0.95
	loot.material_override = m
	loot.position = Vector3(0, 0.1, -0.028)
	p.get_child(0).add_child(loot)


# ================================================================ people

## Someone on the pile waving for help (until they're reached).
func _waver(s: Dictionary) -> Node3D:
	var r = Rescuer.new(false)
	r.scale = Vector3.ONE * PEOPLE_SCALE * tile
	_fx.add_child(r)
	var box: AABB = s.box
	var a := _rng.randf() * TAU
	var at: Vector3 = s.centre + Vector3(cos(a), 0, sin(a)) * (minf(box.size.x, box.size.z) * 0.5 + 0.08 * tile)
	r.place(at, ground_y, Vector3(cos(a), 0, sin(a)))
	r.wave()
	return r


## People come up out of the pile one by one, alive, and walk away from it.
## How many figures stands for how many were saved there.
func _dig_out(s: Dictionary, first: float, gap: float, count_down: bool, most := 3) -> void:
	var figures := clampi(ceili(float(s.saved) / 3.0), 0, most)
	await get_tree().create_timer(first, false).timeout
	for i in figures:
		if not is_inside_tree():
			return
		var box: AABB = s.box
		var a := _rng.randf() * TAU
		var at: Vector3 = s.centre + Vector3(cos(a), 0, sin(a)) * minf(box.size.x, box.size.z) * 0.25
		_dust_at(at, 0.18, 8)
		var p := QuakePerson.new()
		p.scale = Vector3.ONE * PEOPLE_SCALE * tile
		_fx.add_child(p)
		var road: Vector3 = _road_pos(s.road) if _have_roads else s.centre + Vector3.RIGHT * 2.0 * tile
		p.start_run(at, road - at, ground_y)
		p.run_speed = _rng.randf_range(0.35, 0.5) * tile
		p.run_time = _rng.randf_range(2.0, 3.0)
		# once someone is out, the people waving there stop and help
		for w in s.get("wavers", []):
			if is_instance_valid(w):
				w.dig(s.centre - (w as Node3D).global_position)
		if i < figures - 1:
			await get_tree().create_timer(gap, false).timeout
	if count_down:
		_rescues_left -= 1


func _dust_at(p: Vector3, radius_tiles: float, amount: int) -> void:
	if _oq and _oq.has_method("_dust"):
		_oq._dust(Vector3(p.x, ground_y + 0.05 * tile, p.z), radius_tiles * tile, amount, 0.3, 2.0, 0.2, 0.4, true)


## Where on the pile's edge a rescuer stands, from the side `from` is on
## (spread a little so two don't stand in each other).
func _edge_point(s: Dictionary, from: Vector3, k: int) -> Vector3:
	var box: AABB = s.box
	var c: Vector3 = s.centre
	var d := _flat3(from - c)
	if d.length() < 0.001:
		d = Vector3.RIGHT
	d = d.normalized().rotated(Vector3.UP, (k - 0.5) * 0.7)
	var r := minf(box.size.x, box.size.z) * 0.5 + 0.05 * tile
	return c + d * r


# ================================================================ cars

## A copy of one of the station's patrol cars, or a plain one.
func _make_car(k: int) -> Node3D:
	var src: Node3D = null
	var station := _city.get_node_or_null(STATION)
	if station:
		src = station.get_node_or_null(CARS[k % CARS.size()]) as Node3D
	var car: Node3D
	if src:
		car = src.duplicate() as Node3D
		car.process_mode = Node.PROCESS_MODE_INHERIT
		for n in car.find_children("*", "Node3D", true, false):
			(n as Node3D).visible = true
	else:
		car = _plain_car()
	car.name = "PatrolCar"
	_fx.add_child(car)
	car.global_transform = Transform3D(Basis().scaled(Vector3.ONE * tile), _entry_pos())
	return car


## Put the car on the road at `at` (centre line), in its lane, facing `toward`.
func _put_car(c: Dictionary, at: Vector3, toward: Vector3) -> void:
	var car: Node3D = c.node
	var d := _flat3(toward - at).normalized()
	if d == Vector3.ZERO:
		d = Vector3.FORWARD
	var b := Basis.looking_at(-d, Vector3.UP)
	c.track = at
	c.heading = d
	c.right = d.cross(Vector3.UP).normalized()
	c.lat = LANE * tile
	c.v = 0.0
	car.global_transform = Transform3D(b.scaled(Vector3.ONE * tile), at + (c.right as Vector3) * float(c.lat))


## True if no other car on screen is within `r` of `at`.
func _spot_free(c: Dictionary, at: Vector3, r: float) -> bool:
	for o in _cars:
		if o == c or not is_instance_valid(o.node) or not (o.node as Node3D).visible:
			continue
		if _flat((o.node as Node3D).global_position).distance_to(_flat(at)) < r:
			return false
	return true


func _plain_car() -> Node3D:
	var t := Node3D.new()
	_box(t, Vector3(0.24, 0.09, 0.42), Vector3(0, 0.09, 0), _mat(Color(0.95, 0.95, 0.97), 0.5))
	_box(t, Vector3(0.245, 0.04, 0.2), Vector3(0, 0.09, 0), _mat(Color(0.1, 0.16, 0.4), 0.5))
	_box(t, Vector3(0.2, 0.08, 0.22), Vector3(0, 0.17, -0.02), _mat(Color(0.2, 0.3, 0.4), 0.15))
	var bar := Node3D.new()
	bar.name = "LightBar"
	bar.position = Vector3(0, 0.235, -0.02)
	t.add_child(bar)
	for x in [-0.05, 0.05]:
		var l := _box(bar, Vector3(0.05, 0.025, 0.04), Vector3(x, 0.0375, 0), _mat(Color(0.5, 0.5, 0.5), 0.4))
		l.name = "L1" if x < 0.0 else "L2"
	return t


## Red and blue lights on the light bar, flashing in turn.
func _flashers(c: Dictionary) -> void:
	var car: Node3D = c.node
	var bar := car.get_node_or_null("LightBar") as Node3D
	var red := _glow(Color(1.0, 0.12, 0.1))
	var blue := _glow(Color(0.15, 0.35, 1.0))
	c.glow = [red, blue]
	c.lamps = []
	c.lamp_off = []
	for k in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.15, 0.1) if k == 0 else Color(0.2, 0.4, 1.0)
		l.omni_range = 1.3 * tile
		l.light_energy = 0.0
		l.shadow_enabled = false
		(bar if bar else car).add_child(l)
		l.position = Vector3(-0.05 if k == 0 else 0.05, 0.06 if bar else 0.3, 0)
		c.lights.append(l)
		if bar:
			var lamp := bar.get_node_or_null("L%d" % (k + 1)) as MeshInstance3D
			if lamp:
				c.lamps.append(lamp)
				c.lamp_off.append(lamp.material_override)


func _tick_lights(c: Dictionary) -> void:
	if not is_instance_valid(c.node) or not (c.node as Node3D).visible:
		return
	var flip := fmod(_t * 3.2 + float(c.seed), 1.0) < 0.5
	for k in c.lights.size():
		var on := flip if k == 0 else not flip
		(c.lights[k] as OmniLight3D).light_energy = 6.0 if on else 0.0
	for k in c.lamps.size():
		var on := flip if k == 0 else not flip
		(c.lamps[k] as MeshInstance3D).material_override = c.glow[k] if on else c.lamp_off[k]


func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ================================================================ roads

## Every road tile on a grid, so the cars can find their way street to street.
func _index_roads() -> void:
	_road.clear()
	var roads := _city.get_node_or_null(ROADS)
	if roads == null:
		return
	var first := true
	for r in roads.get_children():
		if not (r is Node3D and String(r.name).begins_with("road")):
			continue
		var p := (r as Node3D).global_position
		if first:
			_road_origin = p
			first = false
		p.y = maxf(p.y, ground_y) + 0.01 * tile
		_road[_key(p)] = p
	_have_roads = _road.size() > 1
	# the cars come from the police station's side of town
	var station := _city.get_node_or_null(STATION) as Node3D
	var home := station.global_position if station else _focus + Vector3.RIGHT * 20.0 * tile
	_entry = _nearest_road(home)


func _key(p: Vector3) -> Vector2i:
	return Vector2i(roundi((p.x - _road_origin.x) / tile), roundi((p.z - _road_origin.z) / tile))


func _road_pos(k: Vector2i) -> Vector3:
	return _road.get(k, _focus)


func _entry_pos() -> Vector3:
	return _road_pos(_entry) if _have_roads else _focus + Vector3.RIGHT * 8.0 * tile


func _nearest_road(p: Vector3) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for k in _road:
		var d := _flat(_road[k]).distance_to(_flat(p))
		if d < best_d:
			best_d = d
			best = k
	return best


## The shortest way along the roads from one tile to another (world points).
func _route(from: Vector2i, to: Vector2i) -> Array:
	if not _have_roads:
		return [_entry_pos(), _focus]
	if from == to:
		return [_road_pos(from), _road_pos(to)]
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		if k == to:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if _road.has(n) and not prev.has(n):
				prev[n] = k
				queue.append(n)
	if not prev.has(to):
		return [_road_pos(from), _road_pos(to)]
	var out: Array = []
	var k := to
	while k != from:
		out.append(_road_pos(k))
		k = prev[k]
	out.append(_road_pos(from))
	out.reverse()
	return out


func _site_score(e: Dictionary) -> float:
	var c: Vector3 = (e.box as AABB).get_center()
	var to_road := 0.0
	if _have_roads:
		to_road = _flat(_road_pos(_nearest_road(c))).distance_to(_flat(c))
	return _flat(c).distance_to(_flat(_focus)) + to_road * 2.0


func _sites_centre() -> Vector3:
	var c := Vector3.ZERO
	var n := mini(4, _sites.size())
	for i in n:
		c += _sites[i].centre
	return c / float(maxi(1, n))


# ================================================================ sound

## Police sirens (a two-tone hi-lo) while the cars move; under it all a low
## wind over the ruins.
func _start_sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.name = "RescueSound"
	_player.stream = gen
	_player.volume_db = -5.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _feed_sound() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	var dt := 1.0 / MIX_RATE
	for i in n:
		var white := randf() * 2.0 - 1.0
		_brown = (_brown + 0.02 * white) / 1.02
		_low = lerpf(_low, _brown, 0.03)
		var s := _low * 2.5
		if _siren > 0.0:
			_siren_t += dt
			var f := 960.0 if fmod(_siren_t, 1.1) < 0.55 else 770.0
			_siren_phase = fmod(_siren_phase + f * dt, 1.0)
			var tone := sin(_siren_phase * TAU) * 0.6 + sin(_siren_phase * TAU * 3.0) * 0.12
			s += tone * 0.13 * _siren
		s = clampf(s * _volume, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))


# ================================================================ helpers

func _faces(a: AABB) -> Array:
	var c := a.get_center()
	var hy := a.size.y * 0.5
	return [
		[Vector3(c.x, c.y, a.end.z), Vector3(0, 0, 1), a.size.x * 0.5, hy],
		[Vector3(c.x, c.y, a.position.z), Vector3(0, 0, -1), a.size.x * 0.5, hy],
		[Vector3(a.end.x, c.y, c.z), Vector3(1, 0, 0), a.size.z * 0.5, hy],
		[Vector3(a.position.x, c.y, c.z), Vector3(-1, 0, 0), a.size.z * 0.5, hy],
	]


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
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _flat3(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
