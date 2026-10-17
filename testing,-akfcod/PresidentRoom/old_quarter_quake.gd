extends Node3D
## The Old Quarter when the big one hits: the first place shown in the
## earthquake ending (earthquake_ending.gd, played by day_cycle.gd).
##
## Created inside the city by day_cycle.gd. setup() works out, building by
## building, what the quake does to the quarter from the choices made during
## the game, before anything moves:
##
##   structural_integrity  every building's metadata in City/city.tscn (0.13 to
##                         0.48 here). Approving the Minister of Urban
##                         Planning's timber bracing (old_quarter_works.gd)
##                         raises it to 0.9.
##   interior_inspectors   approved: inspectors checked the work, a little
##                         sturdier (INSPECTORS_BONUS).
##   Infrastructure stat   a little sturdier above 50, a little weaker below
##                         (INFRA_BONUS at 100).
##   People's Awareness    people who know what to do when it shakes survive
##                         more often (PREPARED_SAVES).
##   seismologist_drill    approved: counts as extra awareness (DRILL_BONUS).
##   agency_rescue_training approved: rescue crews dig more people out of the
##                         rubble (RESCUE_SAVES).
##
## Each building then gets one BuildingQuake outcome (Earthquake folder):
##   score = INTENSITY * (1.15 - integrity) +- 0.08
##   above 0.55 RAZED, above 0.25 DAMAGED, else it stands (UNDAMAGED).
## Unbraced, every old building scores well above 0.55: the quarter crumbles
## to dust and almost everyone inside dies. Braced, they score around 0.25:
## some crack and lean, most stand, and the other choices tip the balance.
##
## People caught per building = residents * DEATH_RATE[outcome], lowered by
## awareness and rescue crews. Of those, TRAPPED_SHARE[outcome] are not dead
## yet: they are buried alive under the rubble (`trapped`). Whether they get
## dug out is decided later, by police_rescue.gd (with a police station, patrol
## cars bring officers to dig; without one there aren't enough hands). The rest
## die at once (`dead`). Damage = building value * DAMAGE_SHARE[outcome].
## All of it is fixed by setup() (seeded), so the numbers on screen always
## match what the player sees.
##
## The Earthquake folder's effects are made for one-unit-per-tile scenes; the
## city is 27 times bigger. So BuildingQuake only moves, breaks and drops the
## buildings here, and this script adds the dust, glass, debris, rubble and
## people itself, scaled up to the city.

const EarthquakeEnding := preload("res://PresidentRoom/earthquake_ending.gd")
const DISTRICT := "Districts/OldQuarter"
const FAULT := "HazardZones/EarthquakeZone"
const RUBBLE_PILE := "res://Models/Custom/rubble_pile.glb"
const RUBBLE_SMALL := "res://Models/Custom/rubble_small.glb"

## Proposal ids that change what happens here.
const BRACING_ID := "urban_timber_bracing"
const INSPECTORS_ID := "interior_inspectors"
const DRILL_ID := "seismologist_drill"
const RESCUE_ID := "agency_rescue_training"

## How hard the quake hits the quarter (it sits right on the fault line).
const INTENSITY := 1.05
## Extra integrity when the inspectors were kept on.
const INSPECTORS_BONUS := 0.06
## Extra integrity at Infrastructure 100 (and that much less at 0).
const INFRA_BONUS := 0.08
## Outcome thresholds (same as BuildingQuake's AUTO).
const RAZE_SCORE := 0.55
const DAMAGE_SCORE := 0.25

## Indexed by BuildingQuake.Outcome: [AUTO, UNDAMAGED, DAMAGED, RAZED].
## Share of the people inside who die.
const DEATH_RATE := [0.0, 0.01, 0.12, 0.92]
## Share of those deaths avoided by a fully aware population.
const PREPARED_SAVES := [0.0, 0.7, 0.6, 0.12]
## Share of those deaths avoided by trained rescue crews.
const RESCUE_SAVES := [0.0, 0.0, 0.25, 0.1]
## Share of the people caught who are still alive under the rubble (the rest
## die at once). Their fate is played out in police_rescue.gd.
const TRAPPED_SHARE := [0.0, 0.0, 0.6, 0.4]
## Share of the building's value lost.
const DAMAGE_SHARE := [0.0, 0.05, 0.4, 1.0]
## The seismologist's drill counts as this much extra awareness (0..1).
const DRILL_BONUS := 0.25

## People living in a building one tile wide, deep and tall.
const RESIDENTS_PER_TILE := 18.0
## What a building is worth per resident (money damage).
const VALUE_PER_RESIDENT := 50000.0

## Seconds every building shakes.
const SHAKE_TIME := 7.0
## The shock wave crosses this many tiles a second.
const WAVE_TILES := 6.0
## Buildings nearest the street shot that break apart in pieces; the others
## just drop (fewer physics bodies).
const FULL_DETAIL := 28
## Most little people on screen at once.
const PEOPLE_CAP := 140
## Most fissures torn in the ground.
const CRACKS := 5
## A person's size in tiles (QuakePerson is built 0.17 units tall).
const PEOPLE_SCALE := 1.1
## Scales every particle count.
const QUALITY := 1.0
## Particle sizes in tiles (speeds always scale by a whole tile). Below 1 so
## a hundred buildings' worth of dust doesn't white the whole screen out.
const DUST_SIZE := 0.55
const GLASS_SIZE := 0.3
const DEBRIS_SIZE := 0.5
## Dust opacity (0..1): the ring and blast clouds, and the lingering haze.
const DUST_ALPHA := 0.6
const HAZE_ALPHA := 0.4
## Share of the damaged buildings near the camera that smoke afterwards.
const SMOKE_SHARE := 0.3

var tile := 26.926893
var ground_y := -0.7273283
## Centre of the quarter at street level.
var focus := Vector3.ZERO
var braced := false

## The totals, ready after setup().
var residents := 0
var dead := 0
## Still alive under the rubble when the shaking stops (police_rescue.gd).
var trapped := 0
var damage := 0.0
var razed := 0
var damaged := 0
var standing := 0

var _works                      # old_quarter_works.gd: the camera spots
var _plan: Array[Dictionary] = []
var _props: Array[Dictionary] = []
var _fx: Node3D
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _people := 0
var _finished := 0
var _t := -1.0                  # seconds since start(), -1 before
var _epi := Vector3.ZERO


func _init() -> void:
	_rng.seed = 1432
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	set_process(false)


## Work out the whole quake for the quarter. `works` is day_cycle's
## old_quarter_works.gd (already set up in this city), `ending` the
## earthquake_ending.gd with the choices. Returns false without an Old Quarter.
func setup(city: Node3D, works, ending) -> bool:
	_works = works
	var district := city.get_node_or_null(DISTRICT) as Node3D
	if district == null or works == null:
		return false
	var root := district.get_node_or_null("Buildings")
	if root == null:
		return false
	focus = works.focus
	ground_y = works.focus.y
	tile = works._tile
	braced = ending.approved(BRACING_ID)
	_epi = _epicenter(city)

	var bonus := 0.0
	if ending.approved(INSPECTORS_ID):
		bonus += INSPECTORS_BONUS
	bonus += (ending.stat("infrastructure") - 50.0) / 50.0 * INFRA_BONUS
	var aware := clampf(ending.stat("awareness") / 100.0 + (DRILL_BONUS if ending.approved(DRILL_ID) else 0.0), 0.0, 1.0)
	var rescue: bool = ending.approved(RESCUE_ID)

	var wave := WAVE_TILES * tile
	for c in root.get_children():
		var b := c as Node3D
		if b == null or not b.visible:
			continue
		var box := _box_of(b)
		if box.size == Vector3.ZERO:
			continue
		var integrity := float(b.get_meta("structural_integrity", 0.85)) + bonus
		var score := INTENSITY * (1.15 - integrity) + _rng.randf_range(-0.08, 0.08)
		var o := BuildingQuake.Outcome.UNDAMAGED
		if score > RAZE_SCORE:
			o = BuildingQuake.Outcome.RAZED
		elif score > DAMAGE_SCORE:
			o = BuildingQuake.Outcome.DAMAGED
		# from the building's own size, so leaning or straightened makes no difference
		var dims := _local_size(b)
		var volume := dims.x * dims.y * dims.z / pow(tile, 3.0)
		var people := clampi(roundi(volume * RESIDENTS_PER_TILE * _rng.randf_range(0.8, 1.2)), 4, 90)
		var rate: float = DEATH_RATE[o] * (1.0 - PREPARED_SAVES[o] * aware)
		if rescue:
			rate *= 1.0 - RESCUE_SAVES[o]
		var caught := clampi(roundi(people * rate * _rng.randf_range(0.92, 1.08)), 0, people)
		var buried := roundi(caught * TRAPPED_SHARE[o])
		var deaths := caught - buried
		var value := people * VALUE_PER_RESIDENT
		var c2 := box.get_center()
		_plan.append({
			"b": b, "box": box, "outcome": o, "residents": people, "dead": deaths, "trapped": buried,
			"loss": value * DAMAGE_SHARE[o],
			"delay": _flat(c2).distance_to(_flat(_epi)) / wave + _rng.randf_range(0.0, 0.25),
			"full": false, "crack": false,
		})
		residents += people
		dead += deaths
		trapped += buried
		damage += value * DAMAGE_SHARE[o]
		if o == BuildingQuake.Outcome.RAZED:
			razed += 1
		elif o == BuildingQuake.Outcome.DAMAGED:
			damaged += 1
		else:
			standing += 1
	if _plan.is_empty():
		return false

	# the buildings round the crossroads (where the camera is) break apart in
	# pieces; the ones near the fault tear the ground open
	var by_focus := _plan.duplicate()
	by_focus.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _flat(a.box.get_center()).distance_to(_flat(focus)) < _flat(b.box.get_center()).distance_to(_flat(focus)))
	for i in mini(FULL_DETAIL, by_focus.size()):
		by_focus[i].full = true
	var by_fault := _plan.duplicate()
	by_fault.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.delay < b.delay)
	var n := 0
	for e in by_fault:
		if n >= CRACKS:
			break
		if e.outcome != BuildingQuake.Outcome.UNDAMAGED:
			e.crack = true
			n += 1

	var props := district.get_node_or_null("Props")
	if props:
		for p in props.get_children():
			var pn := p as Node3D
			if pn == null:
				continue
			var tall := String(pn.name).begins_with("streetlight") or String(pn.name).begins_with("power_pole") \
				or String(pn.name).begins_with("tree")
			var lean := Basis()
			if tall and _rng.randf() < (0.35 if braced else 0.7):
				var axis := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
				lean = Basis(axis, deg_to_rad(_rng.randf_range(8.0, 24.0)))
			_props.append({"node": pn, "orig": pn.transform, "lean": lean, "seed": _rng.randf() * 100.0,
				"delay": _flat(pn.global_position).distance_to(_flat(_epi)) / wave, "tall": tall})
	return true


## Seconds from start() until the last building has done what it's going to do.
func settle_time() -> float:
	var last := 0.0
	for e in _plan:
		last = maxf(last, e.delay)
	return last + SHAKE_TIME + 0.8


## How much of the quarter came down (0..1).
func razed_share() -> float:
	return float(razed) / maxf(1.0, float(_plan.size()))


## Read before the quake hits.
func intro_line() -> String:
	if braced:
		return "Lunchtime in the *Old Quarter*. %s people are at home behind its freshly braced brick walls." % EarthquakeEnding.thousands(residents)
	return "Lunchtime in the *Old Quarter*. %s people are at home behind its old brick walls." % EarthquakeEnding.thousands(residents)


## Read once the dust settles.
func headline() -> String:
	var total := maxf(1.0, float(_plan.size()))
	if razed_share() >= 0.6:
		if braced:
			return "The braces weren't enough. The *Old Quarter* came down in seconds, and most of its people with it."
		return "Nobody ever braced the *Old Quarter*. Its old bricks gave way in seconds, and the whole quarter crumbled to dust with its people inside."
	if razed_share() >= 0.25:
		return "Half the *Old Quarter* is rubble. Where the old walls held, people crawled out into the dust."
	if standing / total >= 0.7:
		return "The *timber braces* held. The Old Quarter shook hard, but its buildings are still standing and its people are out in the street."
	return "The *timber braces* held the walls up. The old buildings cracked and leaned, but most of their people made it out."


## The result for earthquake_ending.gd. The note leads into the rescue
## (police_rescue.gd): how many are still alive under the rubble.
func result() -> Dictionary:
	var note := ""
	if trapped > 0:
		note = "~%s STILL ALIVE UNDER THE RUBBLE" % EarthquakeEnding.thousands(trapped)
	return {"place": "Old Quarter", "residents": residents, "dead": dead, "damage": damage,
		"razed": razed, "damaged": damaged, "standing": standing, "trapped": trapped, "note": note}


## The buildings that trapped people: [{b, box, outcome, residents, trapped}],
## for police_rescue.gd.
func trapped_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _plan:
		if int(e.trapped) > 0:
			out.append(e)
	return out


# ================================================================ the quake

## Shake the whole quarter: the wave rolls out from the fault, each building
## does what setup() decided, the props jolt and the weak ones are left leaning.
func start() -> void:
	_fx = Node3D.new()
	_fx.name = "QuakeFX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D()
	var size := 1.0
	for e in _plan:
		size = maxf(size, _flat(e.box.get_center()).distance_to(_flat(focus)))
	QuakeFX.particle_floor(_fx, focus, ground_y, size * 2.5 + tile * 4.0)
	for e in _plan:
		var bq := BuildingQuake.new()
		bq.name = "Quake_%s" % e.b.name
		bq.building = e.b
		bq.intensity = INTENSITY
		bq.duration = SHAKE_TIME
		# the folder's own particles and people are sized for small scenes:
		# they're made here instead, scaled to the city
		bq.glass = false
		bq.dust = false
		bq.debris = false
		bq.people = false
		bq.smoke = false
		bq.leave_rubble = false
		bq.shake_camera = false
		bq.break_off_parts = e.full
		bq.ground_crack = e.crack
		add_child(bq)
		bq.started.connect(_on_started.bind(e))
		bq.main_shock.connect(_on_main_shock.bind(e))
		bq.part_broke.connect(_on_part_broke)
		bq.collapsed.connect(_on_collapsed.bind(e))
		bq.finished.connect(func(_o: int) -> void: _finished += 1)
		e.bq = bq
		bq.trigger(e.outcome, e.delay)
	_t = 0.0
	set_process(true)


## True once every building has finished.
func is_done() -> bool:
	return _t >= 0.0 and _finished >= _plan.size()


func _process(delta: float) -> void:
	_t += delta
	for s in _props:
		var n: Node3D = s.node
		if not is_instance_valid(n):
			continue
		var lt: float = _t - s.delay
		if lt < 0.0:
			continue
		var orig: Transform3D = s.orig
		var lean_b := Basis().slerp(Basis((s.lean as Basis).get_rotation_quaternion()), clampf(lt / 1.5, 0.0, 1.0))
		var env := clampf(lt / 0.4, 0.0, 1.0) * (1.0 - clampf((lt - SHAKE_TIME * 0.6) / (SHAKE_TIME * 0.4), 0.0, 1.0))
		var sd: float = s.seed
		var f := 10.0
		var rot := deg_to_rad(5.0 if s.tall else 2.0) * env
		var sway := Basis.from_euler(Vector3(_noise.get_noise_2d(lt * f * 0.5, sd) * rot, 0.0,
			_noise.get_noise_2d(lt * f * 0.5, sd + 40.0) * rot))
		var off := Vector3(_noise.get_noise_2d(lt * f, sd + 80.0), 0.0, _noise.get_noise_2d(sd + 80.0, lt * f)) \
			* 0.03 * tile * env
		var xf := orig
		xf.basis = sway * lean_b * orig.basis
		xf.origin = orig.origin + off
		n.transform = xf
	if _t > settle_time() + 2.0:
		set_process(false)


# ================================================================ per building

## The shaking reaches the building: dust lifts off the street round it.
func _on_started(_outcome: int, e: Dictionary) -> void:
	var box: AABB = e.box
	var c := box.get_center()
	var r := maxf(box.size.x, box.size.z) * 0.6
	_dust(Vector3(c.x, ground_y + 0.05 * tile, c.z), r, _q(10 if e.full else 5), 0.35, 2.5, 0.25, 0.6, true)
	_spawn_runners(e)


## The main jolt: glass bursts out, dust and bits of facade fly.
func _on_main_shock(e: Dictionary) -> void:
	var box: AABB = e.box
	var c := box.get_center()
	var power := 0.5 if e.outcome == BuildingQuake.Outcome.UNDAMAGED else 1.0
	_dust(Vector3(c.x, ground_y + 0.05 * tile, c.z), maxf(box.size.x, box.size.z) * 0.65,
		_q(int((12 + 20 * power) * (1.0 if e.full else 0.5))), 0.5 + 0.3 * power, 3.5, 0.35, 0.9 + power, true)
	if e.full:
		for f in _faces(box):
			var n: Vector3 = f[1]
			var area: float = f[2] * f[3] / (tile * tile)
			var g := QuakeFX.glass(_fx, Transform3D(QuakeFX.facing(n), f[0] + n * 0.03 * tile + Vector3.UP * f[3] * 0.1),
				Vector2(f[2] * 0.9, f[3] * 0.85), _q(int((14 + 30 * area) * power)), 1.0 + 1.2 * power)
			_grow(g, GLASS_SIZE)
	if e.outcome != BuildingQuake.Outcome.UNDAMAGED:
		_grow(QuakeFX.debris(_fx, Vector3(c.x, box.end.y, c.z), Vector3.UP, _q(16 if e.full else 8), 1.5, 70,
			[Color(0.75, 0.66, 0.55), Color(0.6, 0.58, 0.55), Color(0.4, 0.38, 0.36)], box.size.x * 0.4))
	if e.outcome == BuildingQuake.Outcome.DAMAGED:
		_spawn_jumpers(e)
		_smoke(e)
	elif e.outcome == BuildingQuake.Outcome.RAZED:
		_collapse_dust(e)


## A piece came off (BuildingQuake made it a RigidBody3D): throw it like the
## big heavy thing it is in this city, and puff dust where it lands.
func _on_part_broke(chunk: RigidBody3D) -> void:
	chunk.gravity_scale = 3.0
	chunk.linear_velocity *= tile * 0.3
	chunk.body_entered.connect(_on_chunk_hit.bind(chunk))
	var h := tile * 0.25
	_dust(chunk.global_position, h * 0.6, _q(10), 0.4, 2.5, 0.3, 0.6)
	_grow(QuakeFX.debris(_fx, chunk.global_position, Vector3.UP, _q(12), 1.4, 45,
		[Color(0.75, 0.66, 0.55), Color(0.55, 0.53, 0.5)], h * 0.5))


func _on_chunk_hit(_other: Node, chunk: RigidBody3D) -> void:
	if not is_instance_valid(chunk) or chunk.has_meta("landed"):
		return
	if chunk.global_position.y > ground_y + 0.6 * tile:
		return
	chunk.set_meta("landed", true)
	var p := chunk.global_position
	p.y = ground_y + 0.05 * tile
	_dust(p, 0.15 * tile, _q(12), 0.45, 3.0, 0.3, 1.0, true)


## A RAZED building pancakes: a blast of dust rolls out along the ground and
## a column of it goes up while the floors come down.
func _collapse_dust(e: Dictionary) -> void:
	# BuildingQuake starts dropping the building about 1.3 s after the jolt
	# (0.85 s when it has no pieces to break off first)
	await get_tree().create_timer(1.25 if e.full else 0.8, false).timeout
	if not is_inside_tree():
		return
	var box: AABB = e.box
	var c := box.get_center()
	var foot := maxf(box.size.x, box.size.z)
	_dust(Vector3(c.x, ground_y + 0.05 * tile, c.z), foot * 0.55, _q(26 if e.full else 12),
		0.9 + foot / tile * 0.25, 6.0, 0.5, 2.6, true)
	var col := _dust(Vector3(c.x, ground_y + 0.2 * tile, c.z), foot * 0.45, _q(40 if e.full else 16),
		0.8 + foot / tile * 0.2, 5.0, 1.6, 0.6, false, false, 0.0)
	var pm := col.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box.size.x * 0.5, 0.15 * tile, box.size.z * 0.5)
	_grow(QuakeFX.debris(_fx, Vector3(c.x, ground_y + 0.15 * tile, c.z), Vector3.UP, _q(30 if e.full else 14), 2.2, 80,
		[Color(0.75, 0.66, 0.55), Color(0.62, 0.6, 0.57), Color(0.45, 0.43, 0.4), Color(0.3, 0.29, 0.28)], foot * 0.4, 7.0))
	await get_tree().create_timer(2.0, false).timeout
	if is_instance_valid(col):
		col.emitting = false


## The building is gone: a lingering cloud and a pile of rubble where it stood.
func _on_collapsed(e: Dictionary) -> void:
	var box: AABB = e.box
	var c := box.get_center()
	var foot := maxf(box.size.x, box.size.z)
	_dust(Vector3(c.x, ground_y + 0.3 * tile, c.z), foot * 0.7, _q(14 if e.full else 6),
		1.4 + foot / tile * 0.35, 7.0, 0.35, 1.2, false, true, 0.9, Color(QuakeFX.DUST_COLOR, HAZE_ALPHA))
	_rubble(c, box.size)


func _rubble(center: Vector3, size: Vector3) -> void:
	if ResourceLoader.exists(RUBBLE_PILE):
		var pile := (load(RUBBLE_PILE) as PackedScene).instantiate() as Node3D
		_fx.add_child(pile)
		var pb := _box_of(pile)
		pb.size = pb.size.max(Vector3.ONE * 0.001)
		var sx := size.x * 1.1 / pb.size.x
		var sz := size.z * 1.1 / pb.size.z
		var sy := minf(sx, sz) * 0.75
		pile.scale = Vector3(sx, sy, sz)
		pile.rotation.y = _rng.randf() * TAU
		var low := pb.position.y - pile.global_position.y
		pile.global_position = Vector3(center.x, ground_y - pb.size.y * sy, center.z)
		var t := create_tween()
		t.tween_property(pile, "global_position:y", ground_y - low * sy, 0.8) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if ResourceLoader.exists(RUBBLE_SMALL):
		for i in 2:
			var r := (load(RUBBLE_SMALL) as PackedScene).instantiate() as Node3D
			_fx.add_child(r)
			var ang := _rng.randf() * TAU
			var dist := maxf(size.x, size.z) * _rng.randf_range(0.55, 0.8)
			r.scale = Vector3.ONE * tile * _rng.randf_range(0.6, 0.9)
			r.global_position = Vector3(center.x + cos(ang) * dist, ground_y, center.z + sin(ang) * dist)
			r.rotation.y = _rng.randf() * TAU


## A few DAMAGED buildings smoke thinly from where they broke (one in
## SMOKE_SHARE, only those near the camera, so the view stays clear).
func _smoke(e: Dictionary) -> void:
	if not e.full or _rng.randf() > SMOKE_SHARE:
		return
	var box: AABB = e.box
	var p := Vector3(box.get_center().x, box.end.y - box.size.y * 0.15, box.get_center().z)
	var s := _dust(p, 0.05 * tile, _q(8), 0.3, 4.0, 0.3, 0.05, false, false, 0.0,
		Color(QuakeFX.DARK_DUST_COLOR, 0.45))
	var pm := s.process_material as ParticleProcessMaterial
	pm.scale_min *= 0.5
	pm.scale_max *= 0.5
	pm.gravity = Vector3(0.05, 0.08, 0.0) * tile
	pm.spread = 12.0
	await get_tree().create_timer(SHAKE_TIME, false).timeout
	if is_instance_valid(s):
		s.emitting = false


# ================================================================ people

## The ones who get out of the door in time run into the street. How many
## are shown follows how many survive (one little figure stands for a few).
func _spawn_runners(e: Dictionary) -> void:
	var alive: int = e.residents - e.dead - e.trapped
	var each := 3 if e.outcome == BuildingQuake.Outcome.UNDAMAGED else 6
	var n := mini(ceili(alive / float(each)), 4 if e.full else 2)
	if e.outcome == BuildingQuake.Outcome.RAZED:
		n = mini(n, 1 if _rng.randf() < 0.5 else 0)
	for i in n:
		if _people >= PEOPLE_CAP:
			return
		_people += 1
		_runner_later(e, _rng.randf_range(0.3, 2.2))


func _runner_later(e: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree() or not is_instance_valid(e.b) or not e.b.visible:
		return
	var f: Array = _faces(e.box).pick_random()
	var n: Vector3 = f[1]
	var side: Vector3 = Vector3(n.z, 0, -n.x) * _rng.randf_range(-0.7, 0.7) * float(f[2])
	var p := QuakePerson.new()
	p.scale = Vector3.ONE * PEOPLE_SCALE * tile
	_fx.add_child(p)
	p.start_run(f[0] + side + n * 0.06 * tile, n.rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6)), ground_y)
	p.run_speed *= tile


## People leap from the windows of a DAMAGED building.
func _spawn_jumpers(e: Dictionary) -> void:
	if not e.full:
		return
	for i in _rng.randi_range(1, 2):
		if _people >= PEOPLE_CAP:
			return
		_people += 1
		_jumper_later(e, 0.4 + _rng.randf() * 2.5)


func _jumper_later(e: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree() or not is_instance_valid(e.b) or not e.b.visible:
		return
	var box: AABB = e.box
	var f: Array = _faces(box).pick_random()
	var n: Vector3 = f[1]
	var pos: Vector3 = f[0] + Vector3(n.z, 0, -n.x) * _rng.randf_range(-0.7, 0.7) * f[2]
	pos.y = box.position.y + box.size.y * _rng.randf_range(0.3, 0.7)
	var g := QuakeFX.glass(_fx, Transform3D(QuakeFX.facing(n), pos + n * 0.03 * tile), Vector2(0.08, 0.08) * tile, _q(14), 1.4)
	_grow(g, GLASS_SIZE)
	var p := QuakePerson.new()
	p.scale = Vector3.ONE * PEOPLE_SCALE * tile
	_fx.add_child(p)
	var v := n * _rng.randf_range(0.6, 1.1) + Vector3.UP * _rng.randf_range(0.6, 1.2)
	p.start_jump(pos + n * 0.03 * tile, v * tile, ground_y)
	p.gravity *= tile
	p.landed.connect(_on_landed)


func _on_landed(p: QuakePerson) -> void:
	_dust(p.global_position + Vector3.UP * 0.02 * tile, 0.03 * tile, 6, 0.12, 1.2, 0.15, 0.3, true)
	# QuakePerson picks a new (small-scene) running speed as it gets back up
	await get_tree().create_timer(0.95, false).timeout
	if is_instance_valid(p):
		p.run_speed = _rng.randf_range(0.5, 0.8) * tile


# ================================================================ helpers

## QuakeFX.dust with the Earthquake folder's (small-scene) numbers for size and
## speeds; `radius` and `pos` are in the city's units.
func _dust(pos: Vector3, radius: float, amount: int, size: float, life: float, up: float, out: float,
		ring := false, one_shot := true, explosive := 0.85, color := Color(QuakeFX.DUST_COLOR, DUST_ALPHA)) -> GPUParticles3D:
	return _grow(QuakeFX.dust(_fx, pos, radius, amount, size, life, up, out, color, ring, one_shot, explosive), DUST_SIZE)


## Scale a QuakeFX emitter up to the city: particles, speeds and gravity all
## grow by one tile, so they fly the same way, just bigger.
func _grow(p: GPUParticles3D, size_tiles := DEBRIS_SIZE) -> GPUParticles3D:
	if p == null:
		return p
	var pm := p.process_material as ParticleProcessMaterial
	var k := tile
	pm.scale_min *= size_tiles * k
	pm.scale_max *= size_tiles * k
	pm.initial_velocity_min *= k
	pm.initial_velocity_max *= k
	pm.radial_velocity_min *= k
	pm.radial_velocity_max *= k
	pm.damping_min *= k
	pm.damping_max *= k
	pm.gravity *= k
	pm.turbulence_noise_scale *= k
	p.collision_base_size *= k
	p.visibility_aabb = AABB(Vector3(-6, -2, -6) * k, Vector3(12, 12, 12) * k)
	return p


## The four walls of a world box: [centre, outward normal, half width, half height].
func _faces(a: AABB) -> Array:
	var c := a.get_center()
	var hy := a.size.y * 0.5
	return [
		[Vector3(c.x, c.y, a.end.z), Vector3(0, 0, 1), a.size.x * 0.5, hy],
		[Vector3(c.x, c.y, a.position.z), Vector3(0, 0, -1), a.size.x * 0.5, hy],
		[Vector3(a.end.x, c.y, c.z), Vector3(1, 0, 0), a.size.z * 0.5, hy],
		[Vector3(a.position.x, c.y, c.z), Vector3(-1, 0, 0), a.size.z * 0.5, hy],
	]


## Where on the fault line the quake starts: the hazard zone nearest the quarter.
func _epicenter(city: Node3D) -> Vector3:
	var zone := city.get_node_or_null(FAULT)
	var best := focus
	var best_d := INF
	if zone:
		for s in zone.get_children():
			if s is Node3D:
				var p := (s as Node3D).global_position
				var d := _flat(p).distance_to(_flat(focus))
				if d < best_d:
					best_d = d
					best = Vector3(p.x, ground_y, p.z)
	return best


func _box_of(n: Node) -> AABB:
	var bb := AABB()
	var first := true
	if n is VisualInstance3D:
		bb = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
		first = false
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


## Size of a building in world units, measured upright in its own space.
func _local_size(n: Node3D) -> Vector3:
	var inv := n.global_transform.affine_inverse()
	var bb := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (inv * (v as VisualInstance3D).global_transform) * (v as VisualInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb.size * n.global_basis.get_scale().abs()


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _q(n: int) -> int:
	return maxi(1, int(n * QUALITY))
