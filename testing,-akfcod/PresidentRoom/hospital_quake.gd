extends "res://PresidentRoom/old_quarter_quake.gd"
## The hospital when the big one hits: the last place shown in the earthquake
## ending (earthquake_ending.gd, played by day_cycle.gd), after everything
## else, because this is where everyone hurt in the other places ends up.
##
## Built on old_quarter_quake.gd: the same BuildingQuake shaking, dust, glass,
## rubble and runners, here for one building (the hospital's "Rise", the part
## buildable.gd raises, so the lot, cracks and parked props stay put).
##
## What happens comes from two proposals and one stat:
##
##   health_hospital      denied: there is no hospital, only the empty lot.
##                        Half an hour later the injured are laid out on the
##                        bare dirt where it should be, neighbours kneeling by
##                        them, a few waving for help that isn't coming.
##   contractor_hospital  denied (or never offered): the hospital was built
##                        properly. It sways and holds, and half an hour later
##                        ambulances pull into the emergency bay with sirens and
##                        lights, stretchers lined up at the doors.
##                        approved (cheap concrete, hospital_cracks.gd): the
##                        camera is behind it, on the cracks. Then:
##   Infrastructure stat  COLLAPSE_BELOW (50) or more: the cracks tear wider
##                        up the back wall but it does not break; the ER stays
##                        open, a bit more crowded. Below it: the cracks split
##                        open and the hospital comes down into rubble on its
##                        own patients, and the injured have nowhere to go.
##   People's Awareness   people who know first aid save a few of the injured
##                        when there is no hospital to take them to
##                        (FIRST_AID_SAVES).
##
## The injured come from the rest of the ending: INJURED_BASE plus
## INJURED_PER_DEAD for every death counted so far (so it must be added to the
## ending after the other places). Everything is fixed by prepare() (seeded),
## before anything moves, so the numbers on screen match what you see.
##
## day_cycle.gd drives it:
##   prepare(city, ending) -> false if there's no Hospital node in the city
##   calm_shot() / quake_shot() / later_shot()   [eye, look, creep] for _glide
##   quake()                the ground goes (signal `fell` if it comes down)
##   skip_ahead()           LATER: the injured, the triage, the rubble
##   arrive()               the ambulances roll in (when there's an ER open)
##   is_done() / arrived()  the shaking is over / the ambulances have parked
##   quiet()                fade the sirens out (before the summary)

signal fell

const HospitalCracks := preload("res://PresidentRoom/hospital_cracks.gd")
const HOSPITAL := "Districts/CivicCenter/Buildings/Hospital"

## Proposal ids that change what happens here.
const HOSPITAL_ID := "health_hospital"
const CRACKS_ID := "contractor_hospital"

## With the cracked hospital, Infrastructure below this and it comes down.
const COLLAPSE_BELOW := 50.0

enum Mode { NONE, SOUND, HOLDS, COLLAPSES }

## Hurt people brought here from all over the city: a base number plus this
## many for every death in the places before (clamped).
const INJURED_BASE := 420.0
const INJURED_PER_DEAD := 2.0
const INJURED_MIN := 250
const INJURED_MAX := 6000
## Patients and staff inside the hospital at lunchtime.
const INSIDE := 230
## Share of the injured who die: with nowhere to go, treated in a sound
## hospital, treated in a cracked one (wards closed, corridors full).
const UNTREATED_DEATH := 0.3
const TREATED_DEATH := 0.025
const CRACKED_DEATH := 0.07
## Share of the untreated deaths avoided by a fully aware population.
const FIRST_AID_SAVES := 0.3
## Share of the people inside who die when it comes down.
const INSIDE_DEATH := 0.95
## What the hospital is worth, and the share lost: shaken, cracked, gone.
const HOSPITAL_VALUE := 120.0e6
const SOUND_LOSS := 0.03
const CRACKED_LOSS := 0.35
## How long after the quake the second half is set (shown on the clock).
const LATER := 35 * 60
## Ambulances that come in, and how long the first takes down the road.
const AMBULANCES := 2
const DRIVE_TIME := 6.0
## The road in front of the hospital and where the ambulances park
## (hospital-local units: +z is the front, +x the emergency bay side).
const ROAD_Z := 3.55
const PARK_SPOTS := [Vector3(1.3, 0.012, 2.3), Vector3(2.3, 0.012, 2.35)]
## A person's size in hospital-local units (QuakePerson is 0.17 units tall).
const PERSON := 1.1
const BLANKETS := [Color(0.85, 0.68, 0.22), Color(0.55, 0.58, 0.62), Color(0.62, 0.22, 0.2),
	Color(0.3, 0.4, 0.6)]
const MIX_RATE := 22050.0
## The rest of the city on screen shakes with it (it's the same ground): every
## building and street prop within this many tiles of the hospital.
const NEIGHBOUR_TILES := 22.0
## How hard the neighbours shake (BuildingQuake's `_shake` scale: an undamaged
## building at the main shock is about 0.9), near the hospital and at the edge.
const NEIGHBOUR_SHAKE_NEAR := 1.0
const NEIGHBOUR_SHAKE_FAR := 0.6
## Longest the wave takes to reach the furthest neighbour (seconds).
const NEIGHBOUR_MAX_DELAY := 1.1
const DISTRICTS := "Districts"

var mode := Mode.NONE
var built := false
var cracked := false
var infra := 50.0

## The totals, ready after prepare() (residents, dead, damage from the parent).
var injured := 0
var inside := 0
var inside_dead := 0
var injured_dead := 0
## Deaths among the injured with no hospital at all (to count what it saved).
var alone_dead := 0

var _hosp: Node3D
var _rise: Node3D
var _cracks: Node3D
var _scene: Node3D            # the later scene, in hospital-local units
var _vans: Array[Dictionary] = []
var _parked := 0
var _mats := {}
var _city: Node3D
## The buildings and props round the hospital that shake with it:
## [{node, orig (global), size, tall, prop, delay, power, seed}].
var _neighbours: Array[Dictionary] = []
var _neighbours_live := false

# sound: the ambulances' two-tone siren
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _volume := 1.0
var _siren := 0.0
var _siren_t := 0.0
var _siren_phase := 0.0


## Find the hospital and work out the toll from the choices. `ending` is the
## earthquake_ending.gd (with the other places' results already in it).
func prepare(city: Node3D, ending) -> bool:
	_city = city
	_hosp = city.get_node_or_null(HOSPITAL) as Node3D
	if _hosp == null:
		return false
	_rng.seed = 2207
	tile = absf(_hosp.global_basis.get_scale().x)
	ground_y = _hosp.global_position.y
	focus = _hosp.global_position
	infra = ending.stat("infrastructure")
	var aware := clampf(ending.stat("awareness") / 100.0, 0.0, 1.0)

	if _hosp.has_method("is_built"):
		built = _hosp.is_built()
	else:
		built = _hosp.visible
	_rise = _hosp.get_node_or_null("Rise") as Node3D
	if _rise == null:
		_rise = _hosp
	_cracks = _hosp.get_node_or_null("Cracks") as Node3D
	cracked = built and (ending.approved(CRACKS_ID) or _cracks != null)
	if cracked and _cracks == null:
		_cracks = HospitalCracks.new()
		_hosp.add_child(_cracks)
		_cracks.setup(_hosp)
		_cracks.show_now()
	_collect_blockers(city)
	if not built:
		mode = Mode.NONE
	elif not cracked:
		mode = Mode.SOUND
	elif infra < COLLAPSE_BELOW:
		mode = Mode.COLLAPSES
	else:
		mode = Mode.HOLDS

	injured = clampi(roundi((INJURED_BASE + INJURED_PER_DEAD * ending.total_dead()) * _rng.randf_range(0.95, 1.05)),
		INJURED_MIN, INJURED_MAX)
	inside = INSIDE if built else 0
	alone_dead = roundi(injured * UNTREATED_DEATH * (1.0 - FIRST_AID_SAVES * aware) * _rng.randf_range(0.95, 1.05))
	match mode:
		Mode.NONE:
			injured_dead = alone_dead
			damage = 0.0
		Mode.SOUND:
			injured_dead = roundi(injured * TREATED_DEATH)
			damage = HOSPITAL_VALUE * SOUND_LOSS
		Mode.HOLDS:
			injured_dead = roundi(injured * CRACKED_DEATH)
			damage = HOSPITAL_VALUE * CRACKED_LOSS
		Mode.COLLAPSES:
			inside_dead = roundi(inside * INSIDE_DEATH)   # exactly 95% (600 inside -> 570 dead)
			injured_dead = alone_dead   # nowhere left to take them
			damage = HOSPITAL_VALUE
	dead = inside_dead + injured_dead
	residents = injured + inside

	if built:
		var o := BuildingQuake.Outcome.UNDAMAGED
		if mode == Mode.COLLAPSES:
			o = BuildingQuake.Outcome.RAZED
			razed = 1
		else:
			standing = 1
		_plan.append({
			"b": _rise, "box": _tall_box(_rise), "outcome": o, "residents": inside, "dead": inside_dead,
			"trapped": 0, "loss": damage, "delay": 0.3, "full": true,
			# no BuildingQuake fissure: its model is scaled past the building
			# and reads as a long black road. The ground split is drawn by
			# hospital_cracks.gd instead, inside the hospital's footprint.
			"crack": false,
		})
	return true


func saved_lives() -> int:
	return maxi(0, alone_dead - dead)


# ================================================================ words

func intro_line() -> String:
	match mode:
		Mode.NONE:
			return "The *Civic Center*, at the same moment. Where the city's hospital should stand, there is only an empty lot."
		Mode.SOUND:
			return "The *Civic Center*, at the same moment. Inside the new *hospital*, %s patients and staff are having an ordinary afternoon." \
				% EarthquakeEnding.thousands(inside)
	return "The *Civic Center*, at the same moment. The *cracks* are still there, up the back of the new hospital. %s patients and staff are inside." \
		% EarthquakeEnding.thousands(inside)


## Read once the shaking stops.
func shake_line() -> String:
	match mode:
		Mode.NONE:
			return "The ground heaves under the empty lot. There is nothing here to fall down, and nothing here to help."
		Mode.SOUND:
			return "The *hospital* sways and its windows burst, but the concrete was poured in full. It holds, and the lights stay on."
		Mode.HOLDS:
			return "The *cracks* tear wider up the back wall and dust pours out of them. But it holds. The rest of the city was built strong enough to carry it, just."
	return "The *cracks* split wide open. The cheap concrete gives way, and the *hospital* comes down on its own patients."


## Read as the second half starts, half an hour later.
func later_line() -> String:
	match mode:
		Mode.NONE:
			return "Half an hour later the injured start arriving, carried on doors and in the backs of cars. %s of them, brought to where the hospital should have been." \
				% EarthquakeEnding.thousands(injured)
		Mode.SOUND:
			return "Half an hour later, the sirens. Ambulance after ambulance swings into the *emergency bay*, and the doctors are already waiting at the doors."
		Mode.HOLDS:
			return "Half an hour later the ambulances come anyway. The cracked wing is shut, the corridors are full, but the *emergency room* is still open."
	return "Half an hour later the injured start arriving from all over the city, %s of them, to a pile of rubble where the *hospital* used to be." \
		% EarthquakeEnding.thousands(injured)


## Read with the tally.
func headline() -> String:
	match mode:
		Mode.NONE:
			return "%s people are hurt and there is nowhere to take them. Neighbours do what they can on the bare ground. %s of them don't make it." \
				% [EarthquakeEnding.thousands(injured), EarthquakeEnding.thousands(dead)]
		Mode.SOUND:
			return "The *hospital* takes in %s injured tonight. Without it, about %s more of them would have died." \
				% [EarthquakeEnding.thousands(injured), EarthquakeEnding.thousands(saved_lives())]
		Mode.HOLDS:
			return "Somehow the cracked *hospital* stood, and it treated %s injured tonight. It won't survive the next one." \
				% EarthquakeEnding.thousands(injured)
	return "%s patients and staff died when the cheap concrete gave way, and the %s injured from across the city had nowhere left to go." \
		% [EarthquakeEnding.thousands(inside_dead), EarthquakeEnding.thousands(injured)]


## The footnote under the toll.
func note() -> String:
	match mode:
		Mode.NONE:
			return "NO HOSPITAL  ·  %s INJURED WITH NOWHERE TO GO" % EarthquakeEnding.thousands(injured)
		Mode.SOUND:
			return "THE HOSPITAL SAVED ~%s LIVES" % EarthquakeEnding.thousands(saved_lives())
		Mode.HOLDS:
			return "THE CRACKS HELD, FOR NOW  ·  INFRASTRUCTURE %d/100" % roundi(infra)
	return "THE CHEAP CONCRETE GAVE WAY  ·  INFRASTRUCTURE %d/100" % roundi(infra)


## The result for earthquake_ending.gd.
func result() -> Dictionary:
	return {"place": "Hospital", "residents": residents, "dead": dead, "damage": damage,
		"of": "injured" if inside == 0 else "patients and injured", "note": note(),
		"injured": injured, "collapsed": mode == Mode.COLLAPSES}


# ================================================================ camera

## Lunchtime: from behind when it's cracked (on the cracks), else the front.
func calm_shot() -> Array:
	if cracked:
		return _back_shot(6.8, 4.4)
	return _shot(Vector3(4.8, 2.4, 8.4), Vector3(0.0, 0.9 if built else 0.3, 0.2), Vector3(-1.4, 0.0, 0.0))


## Pulled up and back while it shakes.
func quake_shot() -> Array:
	if cracked:
		return _back_shot(8.6, 5.4)
	return _shot(Vector3(6.4, 3.4, 10.4), Vector3(0.0, 0.8, 0.0), Vector3(-1.0, 0.0, 0.0))


## Half an hour later: the front, the forecourt and the road the ambulances
## come down.
func later_shot() -> Array:
	if mode == Mode.SOUND or mode == Mode.HOLDS:
		return _shot(Vector3(5.4, 3.1, 8.6), Vector3(0.4, 0.3, 1.9), Vector3(-1.2, 0.0, 0.0))
	return _shot(Vector3(4.6, 3.4, 7.6), Vector3(0.0, 0.2, 0.9), Vector3(-1.2, 0.0, 0.0))


## The same 3/4 view of the back as the evening the cracks appeared
## (day_cycle.gd _swing_behind), `dist` out and `lift` up.
func _back_shot(dist: float, lift: float) -> Array:
	var dir := Vector3(-0.55, 0.0, -0.85).normalized()
	return _shot(dir * dist + Vector3.UP * lift, Vector3(0.0, 0.9, -0.6), Vector3(0.9, 0.0, -0.3))


## [eye, look, creep] in the world from hospital-local points.
func _shot(eye: Vector3, look: Vector3, creep: Vector3) -> Array:
	return [_hosp.to_global(eye), _hosp.to_global(look), _hosp.global_basis * creep]


# ================================================================ the quake

## The ground goes. With no hospital, dust lifts off the empty lot. Otherwise
## the hospital shakes (old_quarter_quake.gd start()); cracked, the cracks tear
## wider when the jolt hits, and if it's going to fall they split open first.
func quake() -> void:
	_hide_lot_sign()
	_shake_neighbours()
	if _plan.is_empty():
		_fx = Node3D.new()
		_fx.name = "QuakeFX"
		_fx.top_level = true
		add_child(_fx)
		_fx.global_transform = Transform3D()
		_dust(Vector3(focus.x, ground_y + 0.05 * tile, focus.z), 2.4 * tile, _q(26), 0.6, 4.0, 0.3, 1.2, true)
		_t = 0.0
		set_process(true)
		return
	start()
	var bq: BuildingQuake = _plan[0].bq
	if mode == Mode.HOLDS:
		bq.main_shock.connect(_on_hold_shock.bind(bq))
	elif mode == Mode.COLLAPSES:
		bq.started.connect(_on_fall_start)
		bq.main_shock.connect(_on_fall_shock)
		bq.collapsed.connect(_on_fell)


func is_done() -> bool:
	if _plan.is_empty():
		return _t >= SHAKE_TIME
	return super()


## Cracked but strong enough: the cracks rip wider and the walls crack all
## over (the quake shader), but nothing comes off.
func _on_hold_shock(bq: BuildingQuake) -> void:
	if _cracks:
		_cracks.widen(1.75, 3.5, 2)
	# after BuildingQuake's own small damage tween, so this one wins
	bq.call_deferred("_tween_damage", 0.55, 3.5)
	_wall_dust(0.6)


## Going to fall: the cracks split open fast, before the floors go.
func _on_fall_start(_outcome: int) -> void:
	if _cracks:
		_cracks.widen(2.4, 1.4, 4)
	_wall_dust(1.0)


## The jolt that brings it down: the ground under it splits (within its footprint).
func _on_fall_shock() -> void:
	if _cracks:
		_cracks.split_ground()


func _on_fell() -> void:
	if _cracks:
		_cracks.fallen()   # the wall cracks go with the walls; the ground split stays
	fell.emit()


## Dust pouring out of the back wall where it cracks.
func _wall_dust(power: float) -> void:
	if _fx == null:
		return
	var box: AABB = _plan[0].box
	var back := _hosp.global_basis.z.normalized() * -1.0
	var c := box.get_center()
	var p := c + back * (box.size.x * 0.5 if absf(back.x) > absf(back.z) else box.size.z * 0.5)
	p.y = box.position.y + box.size.y * 0.35
	_dust(p, maxf(box.size.x, box.size.z) * 0.35, _q(int(14 * power)), 0.5, 3.5, 0.2, 0.6 * power)


## No hospital: the floating "BUILD" sign would look silly in the ending, and a
## click must not start building it.
func _hide_lot_sign() -> void:
	if not is_instance_valid(_hosp):
		return
	if _hosp.get("click_to_build") != null:
		_hosp.set("click_to_build", false)
	for k in ["_sign", "_sub_sign"]:
		var s = _hosp.get(k)
		# Once the hospital is built, buildable.gd frees its "BUILD" sign but
		# keeps the variable pointing at it. Testing `is` on a freed object is a
		# script error that halts the whole ending, so check it's still alive.
		if not is_instance_valid(s):
			continue
		if s is Node3D:
			(s as Node3D).visible = false


func _process(delta: float) -> void:
	_t += delta
	if _neighbours_live:
		_update_neighbours()
	for v in _vans:
		var k := 0
		for l in v.lights:
			var on := fmod(_t * 3.2 + k * 0.5, 1.0) < 0.5
			(l as OmniLight3D).light_energy = (5.0 if on else 0.0) * float(v.flash)
			k += 1
	_feed_sound()


# ================================================================ the neighbours

## The ground moves under the whole Civic Center, not just the hospital: every
## building and street prop around it (the police and fire stations, the
## palace, the high-rises across the road, streetlights...) shakes with the
## same ground motion, the wave reaching the far ones a moment later. They only
## shake (nothing breaks, nothing changes in the toll) and are put back exactly
## where they were once it's over.
func _shake_neighbours() -> void:
	_neighbours.clear()
	var districts := _city.get_node_or_null(DISTRICTS) if _city else null
	if districts == null:
		return
	_noise.seed = GROUND_SEED
	var here := _flat(_hosp.global_position)
	var reach := NEIGHBOUR_TILES * tile
	for d in districts.get_children():
		for group in ["Buildings", "Props"]:
			var root := d.get_node_or_null(group)
			if root == null:
				continue
			for c in root.get_children():
				var n := c as Node3D
				if n == null or n == _hosp or not n.is_visible_in_tree():
					continue
				# a civic lot (buildable.gd): only the building that's gone up
				# on it shakes, not the flat lot, and nothing if it was never built
				if n.has_method("is_built"):
					if not n.is_built():
						continue
					var rise := n.get_node_or_null("Rise") as Node3D
					if rise:
						n = rise
				var dist := _flat(n.global_position).distance_to(here)
				if dist > reach:
					continue
				var box := _box_of(n)
				if box.size == Vector3.ZERO:
					continue
				var k := clampf(dist / reach, 0.0, 1.0)
				var size := maxf(box.size.x, box.size.z)
				_neighbours.append({
					"node": n, "orig": n.global_transform, "size": size,
					"tall": clampf(box.size.y / maxf(size, 0.01), 0.5, 3.0),
					"prop": group == "Props",
					"delay": 0.3 + k * NEIGHBOUR_MAX_DELAY + _rng.randf_range(0.0, 0.15),
					"power": lerpf(NEIGHBOUR_SHAKE_NEAR, NEIGHBOUR_SHAKE_FAR, k),
					"seed": _rng.randf() * 100.0,
				})
	_neighbours_live = not _neighbours.is_empty()


## One frame of the neighbours' shaking (the same motion BuildingQuake gives
## the hospital: a jitter along the ground and a sway that grows with height).
func _update_neighbours() -> void:
	var any := false
	for s in _neighbours:
		var n: Node3D = s.node
		if not is_instance_valid(n):
			continue
		var orig: Transform3D = s.orig
		var lt: float = _t - float(s.delay)
		var dur: float = SHAKE_TIME - float(s.delay)
		if lt < 0.0:
			any = true
			continue
		if lt >= dur:
			n.global_transform = orig
			continue
		any = true
		# in, a jolt with the main shock, then dying away
		var env := clampf(lt / 0.8, 0.0, 1.0) * (1.0 - clampf((lt - dur * 0.6) / (dur * 0.4), 0.0, 1.0))
		env *= 1.0 + 0.5 * exp(-pow((lt - 1.5) / 0.5, 2.0))
		var sh: float = env * float(s.power)
		var sd: float = float(s.seed) * 0.02
		var off: Vector3
		var rot: float
		if s.prop:
			off = Vector3(_noise.get_noise_2d(lt * 10.0, sd + 80.0), 0.0, _noise.get_noise_2d(sd + 80.0, lt * 10.0)) \
				* 0.03 * tile * sh
			rot = deg_to_rad(5.0) * sh
		else:
			off = Vector3(_noise.get_noise_2d(lt * 9.0, sd), _noise.get_noise_2d(lt * 9.0, sd + 40.0) * 0.25,
				_noise.get_noise_2d(sd, lt * 9.0)) * 0.035 * float(s.size) * sh
			rot = deg_to_rad(1.6) * float(s.tall) * sh
		var sway := Basis.from_euler(Vector3(_noise.get_noise_2d(lt * 4.0, sd + 90.0) * rot, 0.0,
			_noise.get_noise_2d(lt * 4.0, sd + 130.0) * rot))
		n.global_transform = Transform3D(sway * orig.basis, orig.origin + off)
	if not any:
		_neighbours_live = false


## Everything back where it stood (the shaking's over, or we cut away).
func _settle_neighbours() -> void:
	for s in _neighbours:
		if is_instance_valid(s.node):
			(s.node as Node3D).global_transform = s.orig
	_neighbours_live = false


func _exit_tree() -> void:
	_settle_neighbours()


# ================================================================ later

## Half an hour on: lay out what's there now.
func skip_ahead() -> void:
	_hide_lot_sign()
	_settle_neighbours()
	_scene = Node3D.new()
	_scene.name = "Later"
	_scene.top_level = true
	add_child(_scene)
	_scene.global_transform = _hosp.global_transform
	if _t < 0.0:
		_t = 0.0
	set_process(true)
	match mode:
		Mode.NONE:
			_lay_out(Rect2(-2.3, -1.6, 4.6, 4.1), 18)
		Mode.SOUND:
			_triage(false)
		Mode.HOLDS:
			_triage(true)
		Mode.COLLAPSES:
			_lay_out(Rect2(-2.5, 2.05, 5.0, 1.05), 16)


## The ambulances roll in (only when there's an emergency room to go to).
func arrive() -> void:
	if mode != Mode.SOUND and mode != Mode.HOLDS:
		return
	_start_sound()
	_siren = 1.0
	for k in AMBULANCES:
		var van := _make_ambulance()
		var p: Vector3 = PARK_SPOTS[k % PARK_SPOTS.size()]
		var path: Array[Vector3] = [Vector3(-8.5 - k * 1.6, 0.012, ROAD_Z), Vector3(p.x - 0.9, 0.012, ROAD_Z), p]
		var v := {"node": van, "lights": [], "flash": 1.0}
		_van_lights(v)
		_vans.append(v)
		_drive(v, path, DRIVE_TIME + k * 1.3)


## True once every ambulance has parked (or there are none).
func arrived() -> bool:
	return _parked >= _vans.size()


## Fade the sirens out (the place is over).
func quiet(time := 1.2) -> void:
	var t := create_tween()
	t.tween_property(self, "_volume", 0.0, time)


## Stretchers lined up at the main doors with medics beside them. Cracked:
## more of them, and the overflow lying on blankets across the forecourt.
func _triage(crowded: bool) -> void:
	var n := 6 if crowded else 4
	for i in n:
		var x := -0.95 + i * (1.9 / maxf(1.0, n - 1.0))
		var at := Vector3(x, 0.012, 1.75 + (0.08 if i % 2 == 0 else 0.0))
		_stretcher(at, PI + _rng.randf_range(-0.15, 0.15))
		if i % 2 == 0:
			_medic(at + Vector3(0.11, 0.0, 0.05), at)
	if crowded:
		_lay_out(Rect2(-2.4, 2.15, 2.8, 0.55), 8, false)


## The injured brought here, sitting up on the ground in `area`
## (hospital-local x/z), most with a blanket round their shoulders, people
## kneeling by them, and (`helpless`) a few standing waving for help that
## isn't coming. (They used to be laid flat, which read as people stuck
## sideways in the ground.)
func _lay_out(area: Rect2, count: int, helpless := true) -> void:
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < count and tries < count * 30:
		tries += 1
		var p := Vector3(area.position.x + _rng.randf() * area.size.x, 0.012,
			area.position.y + _rng.randf() * area.size.y)
		var ok := true
		for q in spots:
			if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < 0.3:
				ok = false
				break
		if ok:
			spots.append(p)
	for i in spots.size():
		var p: Vector3 = spots[i]
		# facing out, roughly towards the road (+z), each a little different
		var yaw := _rng.randf_range(-0.7, 0.7)
		_sitting(p, yaw, BLANKETS[i % BLANKETS.size()] if _rng.randf() < 0.7 else Color.TRANSPARENT)
		if i % 3 == 1:
			_kneeler(p + Vector3(sin(yaw), 0.0, cos(yaw)) * 0.13, p)
	if not helpless:
		return
	for i in 4:
		var p := Vector3(area.position.x + area.size.x * (0.15 + 0.23 * i), 0.012, area.end.y + 0.12)
		_waver(p, Vector3(_rng.randf_range(-0.4, 0.4), 0.0, 1.0))


# ================================================================ people

## Someone lying on their back, head along `yaw` (hospital-local), centred on
## `at`, `lift` above it (on a stretcher); under a blanket unless it's clear.
func _lying(at: Vector3, yaw: float, blanket: Color, lift: float) -> Node3D:
	var p := QuakePerson.new()
	p.set_process(false)
	_scene.add_child(p)
	var head := Vector3(sin(yaw), 0.0, cos(yaw))
	var b := (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)).scaled(Vector3.ONE * PERSON)
	p.transform = Transform3D(b, at - head * 0.085 * PERSON + Vector3.UP * (lift + 0.021 * PERSON))
	if blanket.a > 0.0:
		var m := _block(_scene, Vector3(0.075, 0.012, 0.12) * PERSON,
			at - head * 0.025 * PERSON + Vector3.UP * (lift + 0.043 * PERSON), _mat(blanket))
		m.rotation.y = yaw
	return p


## Someone hurt, sitting up on the ground at `at`, legs out in front, facing
## along `yaw` (0 = +z, hospital-local), hunched over, holding an arm; a
## blanket round their shoulders unless it's clear.
func _sitting(at: Vector3, yaw: float, blanket: Color) -> QuakePerson:
	var p := QuakePerson.new()
	p.set_process(false)
	_scene.add_child(p)
	# QuakePerson faces -z: turn it round to face +z, then by `yaw`
	p.transform = Transform3D(Basis(Vector3.UP, yaw + PI).scaled(Vector3.ONE * PERSON), at)
	var rig = p.get("_rig")
	if rig is Node3D:
		var lean := 0.12   # a little back, weight on the hands
		(rig as Node3D).position.y = -0.056
		(rig as Node3D).rotation = Vector3(lean, 0.0, 0.0)
		for k in ["_leg_l", "_leg_r"]:
			var leg = p.get(k)
			if leg is Node3D:
				# straight out in front, flat on the ground
				(leg as Node3D).rotation = Vector3(PI * 0.5 - lean, 0.0, (0.08 if k == "_leg_l" else -0.08))
		var arm_l = p.get("_arm_l")
		var arm_r = p.get("_arm_r")
		if arm_l is Node3D:
			(arm_l as Node3D).rotation = Vector3(0.55, 0.0, 0.15)
		if arm_r is Node3D:
			# hugging the hurt arm
			(arm_r as Node3D).rotation = Vector3(1.25, 0.0, -0.45)
		if blanket.a > 0.0:
			_block(rig as Node3D, Vector3(0.05, 0.05, 0.04), Vector3(0.0, 0.106, 0.002), _mat(blanket))
	return p


## A wheeled stretcher with someone on it, along `yaw`.
func _stretcher(at: Vector3, yaw: float) -> void:
	var s := Node3D.new()
	_scene.add_child(s)
	s.position = at
	s.rotation.y = yaw
	var white := _mat(Color(0.92, 0.93, 0.95))
	var steel := _mat(Color(0.55, 0.57, 0.6))
	_block(s, Vector3(0.085, 0.012, 0.22) * PERSON, Vector3(0, 0.055, 0) * PERSON, white)
	for z in [-0.08, 0.08]:
		_block(s, Vector3(0.07, 0.05, 0.01) * PERSON, Vector3(0, 0.026, z) * PERSON, steel)
	_lying(at, yaw, Color(0.75, 0.82, 0.9), 0.062 * PERSON)


## A medic (white vest) standing by `at`, looking at `look`.
func _medic(at: Vector3, look: Vector3) -> void:
	var p := _standing(at, look)
	_block(p, Vector3(0.046, 0.052, 0.044), Vector3(0, 0.1, 0), _mat(Color(0.95, 0.96, 0.97)))
	_block(p, Vector3(0.022, 0.006, 0.046), Vector3(0, 0.11, 0), _mat(Color(0.85, 0.1, 0.1)))


## Someone bent over the person lying at `look`, tending to them.
func _kneeler(at: Vector3, look: Vector3) -> void:
	var p := _standing(at, look)
	var rig = p.get("_rig")
	if rig is Node3D:
		(rig as Node3D).rotation.x = -0.75
		(rig as Node3D).position.y = -0.03


func _standing(at: Vector3, look: Vector3) -> QuakePerson:
	var p := QuakePerson.new()
	p.set_process(false)
	_scene.add_child(p)
	var d := look - at
	d.y = 0.0
	var yaw := atan2(-d.x, -d.z) if d.length() > 0.001 else 0.0
	p.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * PERSON), at)
	return p


## Someone standing at the edge, waving both arms over their head (QuakePerson
## PANIC), facing `toward`.
func _waver(at: Vector3, toward: Vector3) -> void:
	var p := QuakePerson.new()
	_scene.add_child(p)
	p.scale = Vector3.ONE * PERSON
	p.position = at
	p.ground_y = at.y
	p._set_dir(-toward)   # PANIC turns round to face the other way
	p._enter(QuakePerson.State.PANIC)


# ================================================================ ambulances

## A copy of the ambulance parked by the hospital (hospital-local units), or a
## plain white van if there isn't one.
func _make_ambulance() -> Node3D:
	var src := _hosp.get_node_or_null("Ambulance3") as Node3D
	if src == null and _rise:
		src = _rise.get_node_or_null("Emergency/Ambulance1") as Node3D
	var van: Node3D
	if src:
		van = src.duplicate() as Node3D
		van.process_mode = Node.PROCESS_MODE_INHERIT
		for n in van.find_children("*", "Node3D", true, false):
			(n as Node3D).visible = true
		van.visible = true
		van.scale = Vector3.ONE
	else:
		van = Node3D.new()
		_block(van, Vector3(0.24, 0.2, 0.36), Vector3(0, 0.17, -0.07), _mat(Color(0.95, 0.95, 0.95)))
		_block(van, Vector3(0.24, 0.16, 0.16), Vector3(0, 0.13, 0.19), _mat(Color(0.95, 0.95, 0.95)))
		_block(van, Vector3(0.245, 0.03, 0.52), Vector3(0, 0.13, 0.0), _mat(Color(0.85, 0.12, 0.1)))
	van.name = "Ambulance"
	_scene.add_child(van)
	return van


## Blue and red lights on the cab roof, flashing in turn.
func _van_lights(v: Dictionary) -> void:
	for k in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(0.2, 0.4, 1.0) if k == 0 else Color(1.0, 0.15, 0.1)
		l.omni_range = 1.3 * tile
		l.light_energy = 0.0
		l.shadow_enabled = false
		(v.node as Node3D).add_child(l)
		l.position = Vector3(-0.06 if k == 0 else 0.06, 0.27, 0.2)
		v.lights.append(l)


## Drive along `path` (hospital-local points) in `time` seconds, slowing to a
## stop, nose first (the model faces +z), then unload.
func _drive(v: Dictionary, path: Array[Vector3], time: float) -> void:
	var van: Node3D = v.node
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		lengths.append(lengths[i - 1] + path[i].distance_to(path[i - 1]))
	var total: float = lengths.back()
	van.position = path[0]
	van.basis = Basis.looking_at(-(path[1] - path[0]).normalized(), Vector3.UP)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		if not is_instance_valid(van):
			return
		var s := k * total
		var i := 1
		while i < path.size() - 1 and lengths[i] < s:
			i += 1
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var seg := maxf(0.001, lengths[i] - lengths[i - 1])
		van.position = a.lerp(b, clampf((s - lengths[i - 1]) / seg, 0.0, 1.0))
		var dir := b - a
		dir.y = 0.0
		if dir.length() > 0.001:
			var want := Basis.looking_at(-dir.normalized(), Vector3.UP)
			van.basis = van.basis.orthonormalized().slerp(want, 0.15), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_unload.bind(v))


## Parked: two medics wheel a stretcher out of the back.
func _unload(v: Dictionary) -> void:
	_parked += 1
	if _parked >= _vans.size():
		var t := create_tween()
		t.tween_interval(1.5)
		t.tween_property(self, "_siren", 0.0, 1.0)
	if not is_instance_valid(v.node):
		return
	var van: Node3D = v.node
	var rear := van.position - van.basis.z.normalized() * 0.4
	var group := Node3D.new()
	_scene.add_child(group)
	group.position = rear
	var keep := _scene
	_scene = group   # build the stretcher and medics inside the moving group
	_stretcher(Vector3.ZERO, 0.0)
	_medic(Vector3(0.0, 0.0, -0.16 * PERSON), Vector3.ZERO)
	_medic(Vector3(0.0, 0.0, 0.16 * PERSON), Vector3.ZERO)
	_scene = keep
	var out := -van.basis.z.normalized()
	out.y = 0.0
	group.rotation.y = atan2(out.x, out.z)
	group.scale = Vector3.ONE * 0.01
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(group, "scale", Vector3.ONE, 0.25)
	tw.tween_property(group, "position", rear + out * 0.3, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ================================================================ sound

func _start_sound() -> void:
	if _player:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.name = "Sirens"
	_player.stream = gen
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## A two-tone ambulance siren (hi-lo), a little rough so it sounds far off.
func _feed_sound() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	var dt := 1.0 / MIX_RATE
	for i in n:
		var s := 0.0
		if _siren > 0.0:
			_siren_t += dt
			var f := 960.0 if fmod(_siren_t, 1.1) < 0.55 else 770.0
			_siren_phase = fmod(_siren_phase + f * dt, 1.0)
			s = (sin(_siren_phase * TAU) * 0.65 + sin(_siren_phase * TAU * 3.0) * 0.15) * 0.18 * _siren
		_pb.push_frame(Vector2.ONE * clampf(s * _volume, -1.0, 1.0))


# ================================================================ helpers

## World box of the parts of `n` that stand up (not the flat forecourt and
## markings), so the dust and rubble cover the building, not the whole lot.
func _tall_box(n: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for v in n.find_children("*", "MeshInstance3D", true, false):
		var gi := v as MeshInstance3D
		if gi.mesh == null or not gi.is_visible_in_tree():
			continue
		var b: AABB = gi.global_transform * gi.get_aabb()
		if b.size.y < 0.12 * tile:
			continue
		bb = b if first else bb.merge(b)
		first = false
	return _box_of(n) if first else bb


func _block(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	_mats[c] = m
	return m
