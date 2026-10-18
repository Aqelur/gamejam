extends "res://PresidentRoom/central_park_drill.gd"
## Central Park when the big one hits: the third place shown in the
## earthquake ending (earthquake_ending.gd, played by day_cycle.gd).
##
## Built on central_park_drill.gd (same townspeople, crowd, marshals and
## sounds). Central Park is the town's evacuation point, so nothing falls
## here; what matters is who comes, and where they sleep tonight:
##
##   seismologist_drill  approved: the town has walked here before. Minutes
##                       after the quake the fountain plaza is packed, more
##                       still streaming in, marshals waving them on.
##                       denied: nobody knows where to go. The plaza is almost
##                       empty, a few lost people wander about, and the rest of
##                       the town is still out in the streets under cracked
##                       walls (STRANDED_DEATH: aftershocks and falling bits).
##   agency_park_tents   approved (the ShelterCamp is up under the park): the
##                       camera goes on to the east lawn; with the drill the
##                       tents are filling up, without it they stand empty.
##                       denied: everyone is safe for now, but where will they
##                       stay? A night in the open costs a few (NIGHT_DEATH).
##   People's Awareness  a few more find their own way here (SAFE_*_AWARE).
##
## The tally's footnote (its "note") sums up the night ahead.
##
## day_cycle.gd drives it:
##   prepare(city, ending) -> false if there's no Central Park
##   start_calm()          lunchtime: a few people on the benches and lawns
##   quake()               everyone drops and covers, trees and lamps sway
##   skip_ahead()          LATER: the crowd (or nobody), and the camp
##   camp_shot()           camera spot over the tents (when `tents`)

const Drill := preload("res://PresidentRoom/central_park_drill.gd")
const EarthquakeEnding := preload("res://PresidentRoom/earthquake_ending.gd")

## Proposal ids that change what happens here.
const DRILL_ID := "seismologist_drill"
const TENTS_ID := "agency_park_tents"

## People from the blocks around the park who should come here.
const EVACUEES := 3200
## Share of them who make it to the park: drilled, or not, plus more with
## awareness (at 100).
const SAFE_DRILLED := 0.82
const SAFE_DRILLED_AWARE := 0.15
const SAFE_UNDRILLED := 0.08
const SAFE_UNDRILLED_AWARE := 0.3
## Share of the ones left out in the streets who die (aftershocks, falling
## glass and masonry).
const STRANDED_DEATH := 0.03
## Share of everyone who dies from a night in the open with no shelter.
const NIGHT_DEATH := 0.005
## Cracked paths, a split fountain basin, toppled lamps.
const PARK_DAMAGE := 1.4e6

## Seconds the ground shakes here.
const SHAKE_TIME := 6.0
## How long after the quake the second half is set (shown on the clock).
const LATER := 18 * 60
## People in the park at lunchtime (plus two on benches).
const PARK_GOERS := 12
## People at the tents (with the drill), and still walking in through the gate.
const CAMP_PEOPLE := 26
const CAMP_ARRIVALS := 8

var drilled := false
## The shelter camp is up (approved, and ShelterCamp is under the park).
var tents := false

## The totals, ready after prepare().
var residents := 0
var gathered := 0
var stranded := 0
var dead := 0
var damage := 0.0

var _camp: Node3D
var _sway: Array[Dictionary] = []
var _sway_t := -1.0
var _wobble := FastNoiseLite.new()


## Find the park and work out the toll from the choices. `ending` is the
## earthquake_ending.gd. Call after adding this node to the city.
func prepare(city: Node3D, ending) -> bool:
	if not setup(city):
		return false
	_rng.seed = 1432
	_wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wobble.frequency = 1.0
	drilled = ending.approved(DRILL_ID)
	_camp = _park.get_node_or_null("ShelterCamp") as Node3D
	tents = ending.approved(TENTS_ID) and _camp != null

	var aware := clampf(ending.stat("awareness") / 100.0, 0.0, 1.0)
	var share := (SAFE_DRILLED + SAFE_DRILLED_AWARE * aware) if drilled \
		else (SAFE_UNDRILLED + SAFE_UNDRILLED_AWARE * aware)
	residents = EVACUEES
	gathered = clampi(roundi(EVACUEES * share), 0, EVACUEES)
	stranded = EVACUEES - gathered
	dead = roundi(stranded * STRANDED_DEATH * _rng.randf_range(0.9, 1.1))
	if not tents:
		dead += roundi(EVACUEES * NIGHT_DEATH * _rng.randf_range(0.9, 1.1))
	damage = PARK_DAMAGE * _rng.randf_range(0.9, 1.1)

	# what sways when it shakes
	for group_name in ["Trees", "Lamps"]:
		var g := _park.get_node_or_null(group_name)
		if g == null:
			continue
		for c in g.get_children():
			var n := c as Node3D
			if n:
				_sway.append({"node": weakref(n), "orig": n.transform, "seed": _rng.randf() * 100.0,
					"tall": group_name == "Trees"})
	return true


# ================================================================ words

func intro_line() -> String:
	return "Lunchtime in *Central Park*. A few office workers are eating on the benches by the fountain."


func shake_line() -> String:
	return "Out in the open, with nothing to fall on them, the people in the park are fine. But where does everyone else go now?"


func later_line() -> String:
	if drilled:
		return "They go where they went on Sunday. Just like in the *drill*, the town walks to *Central Park*: %s people, shaken but alive, and the marshals know exactly what to do." \
			% EarthquakeEnding.thousands(gathered)
	return "*Central Park* is the town's evacuation point, but nobody ever practised getting here. Only %s people came. The rest are still out in the streets, under cracked walls, waiting for the aftershocks." \
		% EarthquakeEnding.thousands(gathered)


## Read with the tally: the night ahead.
func headline() -> String:
	if drilled and tents:
		return "On the east lawn the *shelter tents* are filling up. Blankets, water and food are coming out of the crates. Nobody is going home tonight, but everyone has somewhere to sleep."
	if drilled:
		return "They're safe, for now. But many of their homes are cracked or gone, night is coming, and there isn't a single tent in the park. Where will they stay?"
	if tents:
		return "On the east lawn, rows of *shelter tents* stand ready, supplies stacked by the gate. Almost nobody came to use them."
	return "No crowd, no tents, no plan. Tonight the town sleeps wherever it ends up."


## The footnote under the toll.
func note() -> String:
	if drilled and tents:
		return "Tents and supplies for everyone. Enough for a while... hopefully."
	if drilled:
		return "Safe for now. But where will they stay?"
	if tents:
		return "%d tents ready. Hardly anyone knew to come." % _tent_nodes().size()
	return "%s people out in the streets tonight, with nowhere to go." % EarthquakeEnding.thousands(stranded)


## The result for earthquake_ending.gd.
func result() -> Dictionary:
	return {"place": "Central Park", "residents": residents, "dead": dead, "damage": damage,
		"note": note(), "gathered": gathered}


# ================================================================ camera

## [position, look at, creep] over the shelter camp (only when `tents`).
func camp_shot() -> Array:
	if _camp and _camp.has_method("shot"):
		return _camp.shot()
	return drill_shot()


# ================================================================ 1. lunchtime

## A quiet lunchtime: two on the benches, a few chatting, strolling, on
## their phones, and a light breeze.
func start_calm() -> void:
	_sit("FountainPlaza/Bench3", Color(0.3, 0.35, 0.55))
	_sit("FountainPlaza/Bench1", _pick(SHIRTS))
	var spots := _crowd_spots(PARK_GOERS * 4)
	var n := 0
	for i in range(0, spots.size(), 4):
		if n >= PARK_GOERS:
			break
		n += 1
		var p := spots[i]
		var w := _person(p, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR), _rng.randf_range(0.92, 1.08), false)
		var r := _rng.randf()
		if r < 0.35:
			w.mode = Drill.Townie.PHONE
			w.speed = _rng.randf_range(0.06, 0.1)
			var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
			var route: Array[Vector3] = [p + dir * 0.7]
			w.path = route
			w.face(route[0])
		elif r < 0.7:
			w.mode = Drill.Townie.CHAT
			w.face(p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
		else:
			w.mode = Drill.Townie.STAND
			w.face(PLAZA)
		w.rotation.y = w.yaw
	_wind = _player(_noise_stream(false), -18.0)
	set_process(true)


## Someone sitting on a bench of the fountain plaza.
func _sit(bench_path: String, shirt: Color) -> void:
	var bench := _park.get_node_or_null(bench_path) as Node3D
	if bench == null:
		return
	var bp := rig.to_local(bench.global_position)
	var fwd := rig.global_basis.inverse() * bench.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var w := _person(Vector3(bp.x, bp.y + 0.08 - 0.066, bp.z) + fwd * 0.004,
		shirt, _pick(PANTS), _pick(SKIN), _pick(HAIR), 1.0, false)
	w.yaw = atan2(-fwd.x, -fwd.z)
	w.rotation.y = w.yaw
	w.mode = Drill.Townie.SIT


# ================================================================ 2. the quake

## Everyone drops and covers, the trees and lamps sway, dust lifts off the
## paths. After SHAKE_TIME they get up and look around.
func quake() -> void:
	for p in _people:
		if p.mode != Drill.Townie.SIT:
			p.path.clear()
			p.mode = Drill.Townie.CROUCH
	_sway_t = 0.0
	var dust := QuakeFX.dust(self, rig.to_global(PLAZA + Vector3(0, PAVING_Y, 0)), 1.6 * _tile, 30,
		0.3 * _tile, 3.0, 0.03 * _tile, 0.2 * _tile, Color(0.82, 0.76, 0.62, 0.35), true)
	if dust:
		dust.visibility_aabb = AABB(Vector3(-4, -1, -4) * _tile, Vector3(8, 3, 8) * _tile)
	await get_tree().create_timer(SHAKE_TIME, false).timeout
	if not is_inside_tree():
		return
	for p in _people:
		if p.mode == Drill.Townie.CROUCH:
			p.mode = Drill.Townie.STAND


func _process(delta: float) -> void:
	super(delta)
	if _sway_t < 0.0:
		return
	_sway_t += delta
	var env := clampf(_sway_t / 0.4, 0.0, 1.0) \
		* (1.0 - clampf((_sway_t - SHAKE_TIME * 0.6) / (SHAKE_TIME * 0.4), 0.0, 1.0))
	for s in _sway:
		var n := (s.node as WeakRef).get_ref() as Node3D
		if n == null:
			continue
		var sd: float = s.seed
		var rot := deg_to_rad(6.0 if s.tall else 3.0) * env
		var b := Basis.from_euler(Vector3(_wobble.get_noise_2d(_sway_t * 5.0, sd) * rot, 0.0,
			_wobble.get_noise_2d(_sway_t * 5.0, sd + 40.0) * rot))
		var xf: Transform3D = s.orig
		xf.basis = b * xf.basis
		n.transform = xf
	if _sway_t > SHAKE_TIME:
		_restore_sway()


func _restore_sway() -> void:
	_sway_t = -1.0
	for s in _sway:
		var n := (s.node as WeakRef).get_ref() as Node3D
		if n:
			n.transform = s.orig


# ================================================================ 3. later

## LATER minutes on: the town gathered at the plaza (drill) or a few lost
## souls (no drill), and people at the tents if there are any.
func skip_ahead() -> void:
	_restore_sway()
	_clear_people()
	if drilled:
		start_drill()   # sirens, the packed plaza, marshals, people still walking in
	else:
		_start_lost()
	if tents:
		_fill_camp()
	set_process(true)


func _clear_people() -> void:
	for p in _people:
		if is_instance_valid(p):
			p.queue_free()
	_people.clear()
	for pl in _players:
		if is_instance_valid(pl):
			pl.stop()
			pl.queue_free()
	_players.clear()
	_siren = null
	_murmur = null
	_wind = null


## Nobody knows where to go: a handful standing about the plaza, looking
## around, and a few drifting off again down the promenade.
func _start_lost() -> void:
	var spots := _crowd_spots(40)
	for i in mini(6, spots.size()):
		var p := spots[i * 6 % spots.size()]
		var w := _person(p, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR), _rng.randf_range(0.92, 1.08), false)
		w.mode = Drill.Townie.PHONE if i % 3 == 0 else Drill.Townie.STAND
		w.face(p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
		w.rotation.y = w.yaw
	for i in 3:
		var side := -1.0 if i % 2 == 0 else 1.0
		var lane := _rng.randf_range(-0.12, 0.12)
		var w := _person(PLAZA + Vector3(lane, PAVING_Y, side * 1.2), _pick(SHIRTS), _pick(PANTS),
			_pick(SKIN), _pick(HAIR), 1.0, false)
		w.mode = Drill.Townie.WALK
		w.then_mode = Drill.Townie.STAND
		w.speed = _rng.randf_range(0.1, 0.14)
		var route: Array[Vector3] = [PLAZA + Vector3(lane, PAVING_Y, side * 3.4)]
		w.path = route
		w.face(route[0])
		w.rotation.y = w.yaw
	_wind = _player(_noise_stream(false), -8.0)


## People at the tents: with the drill, families by every tent near the gate,
## more coming in through it and a marshal waving them on; without it, just
## a couple by the first tents.
func _fill_camp() -> void:
	var list := _tent_nodes()
	var n := mini(CAMP_PEOPLE if drilled else 2, list.size())
	for i in n:
		var tent: Node3D = list[i]
		var tp := rig.to_local(tent.global_position)
		var front := 1.0 if cos(tent.rotation.y) >= 0.0 else -1.0
		for k in (2 if drilled and _rng.randf() < 0.5 else 1):
			var child := drilled and k == 1 and _rng.randf() < 0.6
			var p := tp + Vector3(_rng.randf_range(-0.16, 0.16), 0.0, front * _rng.randf_range(0.26, 0.32))
			p.y = LAWN_Y
			var w := _person(p, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR),
				_rng.randf_range(0.66, 0.74) if child else _rng.randf_range(0.92, 1.08), false)
			w.mode = Drill.Townie.CHAT if _rng.randf() < 0.4 else Drill.Townie.STAND
			w.face(tp if _rng.randf() < 0.5 else p + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
			w.rotation.y = w.yaw
	if not drilled:
		return
	var gate := _camp.get_node_or_null("ShelterGate") as Node3D
	if gate == null:
		return
	var gp := rig.to_local(gate.global_position)
	var inward := rig.global_basis.inverse() * (gate.global_basis * Vector3.BACK)
	inward.y = 0.0
	inward = inward.normalized()
	var across := Vector3(-inward.z, 0.0, inward.x)
	# a marshal just outside the gate, waving people in
	var m := _person(Vector3(gp.x, PAVING_Y, gp.z) - inward * 0.25 + across * 0.22,
		Color(0.2, 0.3, 0.55), Color(0.2, 0.22, 0.3), _pick(SKIN), _pick(HAIR), 1.0, true)
	m.mode = Drill.Townie.WAVE
	m.face(Vector3(gp.x, 0, gp.z) - inward * 3.0)
	m.rotation.y = m.yaw
	# still walking in up the path, each to a tent
	for i in mini(CAMP_ARRIVALS, list.size()):
		var lane := (0.05 + _rng.randf_range(0.0, 0.05)) * (1.0 if i % 2 == 0 else -1.0)
		var start := Vector3(gp.x, PAVING_Y, gp.z) - inward * (0.5 + i * 0.22) + across * lane
		var tent: Node3D = list[(i * 3) % list.size()]
		var tp := rig.to_local(tent.global_position)
		var front := 1.0 if cos(tent.rotation.y) >= 0.0 else -1.0
		var child := _rng.randf() < 0.2
		var w := _person(start, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR),
			_rng.randf_range(0.66, 0.74) if child else _rng.randf_range(0.92, 1.08), false)
		w.mode = Drill.Townie.WALK
		w.then_mode = Drill.Townie.STAND
		w.speed = _rng.randf_range(0.14, 0.2)
		var route: Array[Vector3] = [Vector3(gp.x, PAVING_Y, gp.z) + inward * 0.35 + across * lane,
			Vector3(tp.x + _rng.randf_range(-0.12, 0.12), LAWN_Y, tp.z + front * 0.36)]
		w.path = route
		w.look_at_end = tp
		w.face(route[0])
		w.rotation.y = w.yaw


## The camp's tents, nearest the gate first (park_tents.gd names them that way).
func _tent_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _camp == null:
		return out
	for c in _camp.get_children():
		if String(c.name).begins_with("Tent") and c is Node3D and (c as Node3D).visible:
			out.append(c as Node3D)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return String(a.name).trim_prefix("Tent").to_int() < String(b.name).trim_prefix("Tent").to_int())
	return out
