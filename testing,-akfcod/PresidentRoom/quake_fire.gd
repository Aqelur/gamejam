extends Node3D
## Main Street when the big one hits: the second place shown in the
## earthquake ending (earthquake_ending.gd, played by day_cycle.gd).
##
## The quake snaps a gas main under the east side of Main Street, where a
## row of old buildings stand shoulder to shoulder along the road. The gas
## catches, the weakest of them (lowest structural_integrity) goes up in
## flames and the fire takes the one next door. What happens after that
## depends on one choice:
##
##   agency_fire_station   approved: the fire station was built, and its two
##                         trucks come down the road with sirens and lights,
##                         raise their ladders and put the fire out. Only the
##                         buildings already burning are damaged, the crews
##                         pull people out, and the narration counts the lives
##                         and money they saved.
##                         denied: nobody comes. The fire jumps from roof to
##                         roof until the whole row (CLUSTER buildings) is
##                         burning, and stays charred and smoking.
##   agency_rescue_training approved: the trucks arrive sooner, the fire is out
##                         faster, fewer die (TRAINED_*).
##   People's Awareness    people who know to get out survive more often
##   seismologist_drill    (PREPARED_SAVES, DRILL_BONUS), as in the Old Quarter.
##
## Deaths per burning building = residents * DEATH_RATE (higher for the first
## one, where the gas went up), lowered by awareness and by the crews. Damage =
## building value * a share (BURN_LOSS left to burn, CREW_LOSS put out). The
## no-fire-station numbers are always worked out too, so the narration can say
## what the crews saved. All fixed by setup() (seeded), before anything burns.
##
## Everything is in city units (one tile = 26.9): the fire, smoke, sparks,
## water and the trucks (copies of the fire station's parked Engine3) are all
## made here at that scale. The fire itself is textured flame tongues (a
## flipbook drawn in code): a white-yellow core, an orange body and a ragged
## red rim, rising out of the windows and off the roof. Sparks streak up on
## the heat and crackle out in bursts. The fire is heard through
## FIRE_SFX (looped, louder the harder it burns); sirens and water are
## generated on the fly.
##
## day_cycle.gd drives it:
##   setup(city, ending)   -> false if there's no Main Street
##   start()               the quake: buildings shake, gas main bursts (signal
##                         `burst`), the first building catches, then the next
##   skip_ahead()          minutes later: the fires are fully going
##   call_crews()          the trucks roll in and put it out (fire_force)
##   let_it_burn()         the fire spreads down the row (no fire_force)
##   is_done()             the crews are done / the whole row is alight
##   quiet()               fade the sound out (before the next place)

signal burst

const EarthquakeEnding := preload("res://PresidentRoom/earthquake_ending.gd")
const DISTRICT := "Districts/MainStreet/Buildings"
const ROADS := "Roads"
const STATION := "Districts/CivicCenter/Buildings/FireStation"

## Proposal ids that change what happens here.
const STATION_ID := "agency_fire_station"
const TRAINING_ID := "agency_rescue_training"
const DRILL_ID := "seismologist_drill"

## Most buildings in the row the fire can take (the first one and its
## nearest neighbours within CLUSTER_REACH tiles).
const CLUSTER := 5
const CLUSTER_REACH := 2.8
## Buildings already burning when the trucks get there.
const CAUGHT := 2

## People in a building one tile wide, deep and tall (lunchtime: flats over
## busy shops and cafes, so a little fuller than the Old Quarter).
const RESIDENTS_PER_TILE := 24.0
const MIN_RESIDENTS := 6
const MAX_RESIDENTS := 160
const VALUE_PER_RESIDENT := 50000.0
## Share of the people inside who die if nobody comes: where the gas went up
## (blast plus stairs cut off at once: almost nobody), and where the fire
## spread to (old timber row, packed at lunchtime, smoke fills the stairwells
## long before the flames arrive and there are no ladders to reach the upper
## floors). A gutted building with no fire service leaves few survivors.
const DEATH_RATE_FIRST := 0.95
const DEATH_RATE_SPREAD := 0.88
## Share of those deaths avoided by a fully aware population (knowing to get
## low and out helps a little, but not when the only stairwell is burning).
const PREPARED_SAVES := 0.15
const DRILL_BONUS := 0.25
## Share of the deaths avoided by fire crews pulling people out.
const CREW_SAVES := 0.6
const TRAINED_SAVES := 0.75
## Share of a building's value lost: burned out, or put out by the crews.
const BURN_LOSS := 0.95
const CREW_LOSS := 0.4
const TRAINED_LOSS := 0.28

## Seconds the buildings shake.
const SHAKE_TIME := 4.4
## Seconds after start() that the gas main bursts.
const BURST_TIME := 1.6
## Seconds after the burst that the fire takes the next building.
const NEXT_DOOR := 2.6
## Seconds between the fire taking one building and the next (left alone).
const SPREAD_TIME := 2.3
## Seconds the trucks take to drive in (trained crews are quicker off the mark).
const DRIVE_TIME := 4.6
const TRAINED_DRIVE_TIME := 3.6
## Seconds of water it takes to put a building out.
const DOUSE_TIME := 5.0
const TRAINED_DOUSE_TIME := 3.2
## Water jets: station units / s^2 (slow so the arc reads), launch speed.
const WATER_G := 3.0
const JET_SPEED := 3.2
## How long after the quake the second half is set (shown on the clock).
const LATER := 6 * 60 + 20

## Scales every particle count.
const QUALITY := 1.0
const FLAME_HOT := Color(1.0, 0.98, 0.86)
const FLAME_YELLOW := Color(1.0, 0.84, 0.22)
const FLAME := Color(1.0, 0.5, 0.07)
const FLAME_DEEP := Color(0.78, 0.1, 0.015)
const SMOKE := Color(0.13, 0.12, 0.12, 0.8)
const STEAM := Color(0.92, 0.93, 0.95, 0.65)
const WATER := Color(0.78, 0.9, 1.0)
const MIX_RATE := 22050.0
## The fire's sound, looped. Its volume follows how hard the fire is burning.
const FIRE_SFX := "res://PresidentRoom/fire sound.wav"
const FIRE_SFX_DB := 0.0
## Flame flipbook: frames across and down, size of one frame in pixels.
const FLAME_FRAMES := 4
const FLAME_FRAME_W := 56
const FLAME_FRAME_H := 120
## The fire shows through a few windows that shatter one after another (lowest
## first, so it climbs the building), not over the whole building.
const WINDOWS_MIN := 3
const WINDOWS_MAX := 6
## Seconds between one window going and the next (a little random).
const WINDOW_GAP := 2.6
## Size of a window opening and height of one floor, in tiles.
const WINDOW_W := 0.13
const WINDOW_H := 0.17
const FLOOR_H := 0.22
## Share of the windows on the street side (the side the camera sees).
const STREET_SHARE := 0.7

var tile := 26.926893
var ground_y := -0.7273283
## True when the fire station was built: the trucks come.
var fire_force := false
var trained := false

## The totals, ready after setup().
var residents := 0
var dead := 0
var damage := 0.0
var burned := 0
## What it would have been with nobody coming (= the totals without fire_force).
var alone_dead := 0
var alone_damage := 0.0

var _city: Node3D
var _row: Array[Dictionary] = []   # the fire's buildings, nearest the first one first
var _others: Array[Node3D] = []    # the rest of Main Street (they only shake)
var _fx: Node3D
var _road: Array[Vector3] = []     # the truck route, ending where the first truck parks
var _park_out := Vector3.RIGHT     # from the fire toward the road
var _centre := Vector3.ZERO        # middle of the buildings that catch first
var _trucks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _t := 0.0
var _spreading := false
var _next_spread := 0.0
var _crews_out := false
var _crews_done := false
var _flame_mesh: QuadMesh
var _spark_mesh: QuadMesh
var _water_mesh: QuadMesh
var _glass_mesh: BoxMesh
static var _hole_tex_cache: GradientTexture2D
static var _flame_tex_cache: ImageTexture
static var _spark_tex_cache: ImageTexture

# sound
var _player: AudioStreamPlayer
var _fire_player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _volume := 1.0
var _siren := 0.0          # 0..1
var _siren_phase := 0.0
var _siren_t := 0.0
var _water_level := 0.0    # 0..1
var _fire_level := 0.0     # 0..1, how loud the fire is
var _brown := 0.0
var _low := 0.0
var _pop := 0.0
var _hp := 0.0
var _last_white := 0.0


func _init() -> void:
	_rng.seed = 7311
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	set_process(false)


## Work out the whole fire from the choices made during the game. `ending` is
## the earthquake_ending.gd. Returns false without a Main Street.
func setup(city: Node3D, ending) -> bool:
	_city = city
	var root := city.get_node_or_null(DISTRICT)
	if root == null:
		return false
	fire_force = ending.approved(STATION_ID)
	trained = fire_force and ending.approved(TRAINING_ID)
	var aware := clampf(ending.stat("awareness") / 100.0 + (DRILL_BONUS if ending.approved(DRILL_ID) else 0.0), 0.0, 1.0)

	# every building on Main Street; the weakest one is where the gas goes up
	var all: Array[Dictionary] = []
	var first: Dictionary = {}
	for c in root.get_children():
		var b := c as Node3D
		if b == null or not b.visible:
			continue
		var box := _box_of(b)
		if box.size == Vector3.ZERO:
			continue
		var e := {"b": b, "box": box, "integrity": float(b.get_meta("structural_integrity", 0.85))}
		all.append(e)
		if first.is_empty() or e.integrity < first.integrity:
			first = e
	if first.is_empty():
		return false
	ground_y = (first.box as AABB).position.y

	# the row: the first building and its nearest neighbours
	var c0 := _flat((first.box as AABB).get_center())
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _flat(a.box.get_center()).distance_to(c0) < _flat(b.box.get_center()).distance_to(c0))
	for e in all:
		var d := _flat(e.box.get_center()).distance_to(c0)
		if _row.size() < CLUSTER and (e == first or d <= CLUSTER_REACH * tile):
			_row.append(e)
		else:
			_others.append(e.b)

	# who lives there, and what the fire costs either way
	for i in _row.size():
		var e: Dictionary = _row[i]
		var dims := _local_size(e.b)
		var volume := dims.x * dims.y * dims.z / pow(tile, 3.0)
		var people := clampi(roundi(volume * RESIDENTS_PER_TILE * _rng.randf_range(0.8, 1.2)), MIN_RESIDENTS, MAX_RESIDENTS)
		var value := people * VALUE_PER_RESIDENT
		var rate := (DEATH_RATE_FIRST if i == 0 else DEATH_RATE_SPREAD) * (1.0 - PREPARED_SAVES * aware)
		var luck := _rng.randf_range(0.9, 1.1)
		var alone := clampi(roundi(people * rate * luck), 0, people)
		e.residents = people
		e.alone_dead = alone
		e.alone_loss = value * BURN_LOSS
		alone_dead += alone
		alone_damage += value * BURN_LOSS
		residents += people
		if fire_force:
			if i < CAUGHT:
				var saves := TRAINED_SAVES if trained else CREW_SAVES
				e.dead = clampi(roundi(people * rate * (1.0 - saves) * luck), 0, people)
				e.loss = value * (TRAINED_LOSS if trained else CREW_LOSS)
				e.burns = true
			else:
				e.dead = 0
				e.loss = 0.0
				e.burns = false
		else:
			e.dead = alone
			e.loss = value * BURN_LOSS
			e.burns = true
		dead += int(e.dead)
		damage += float(e.loss)
		if e.burns:
			burned += 1
		e.heat = 0.0        # 0..1, how hard it's burning
		e.target = 0.0      # what heat is heading for
		e.char = 0.0        # 0..1, how black the walls are
		e.douse = 0.0       # 0..1, water on it right now
		e.lit = false
		e.out = false

	# the middle of what burns first, and the road the trucks come down
	var n := mini(CAUGHT, _row.size())
	for i in n:
		_centre += (_row[i].box as AABB).get_center()
	_centre /= float(n)
	_centre.y = ground_y
	_plan_road(city)
	# draw the flame and spark textures now, not as the gas goes up
	_flame_quad()
	_spark_quad()
	return true


## How many of the row burned (0..1).
func burned_share() -> float:
	return float(burned) / maxf(1.0, float(_row.size()))


func saved_lives() -> int:
	return maxi(0, alone_dead - dead)


func saved_money() -> float:
	return maxf(0.0, alone_damage - damage)


# ================================================================ lines

## Read before the quake hits.
func intro_line() -> String:
	return "Same moment, *Main Street*. %s people in the old row." \
		% EarthquakeEnding.thousands(residents)


## Read once the shaking stops and the fire has taken hold.
func fire_line() -> String:
	return "A gas main snaps. *Fire* takes the corner, then the next building."


## Read as the second half starts, minutes later.
func later_line() -> String:
	if fire_force:
		if trained:
			return "Sirens. The trained crews from the *fire station* reach Main Street."
		return "Sirens. Two trucks from the *fire station* reach Main Street."
	return "No *fire station*. The fire jumps from roof to roof."


## Read once it's over.
func headline() -> String:
	if fire_force:
		return "The *firefighters* held it to %d buildings and saved about %s lives." \
			% [burned, EarthquakeEnding.thousands(saved_lives())]
	return "The fire gutted %d buildings. %s people never got out." \
		% [burned, EarthquakeEnding.thousands(dead)]


## The result for earthquake_ending.gd. `note` is printed under the toll.
func result() -> Dictionary:
	var note := ""
	if fire_force:
		note = "FIRE CREWS SAVED ~%s LIVES  ·  %s" % [EarthquakeEnding.thousands(saved_lives()),
			EarthquakeEnding.money_text(saved_money()).to_upper()]
	else:
		note = "NO FIRE STATION  ·  %d BUILDINGS BURNED OUT" % burned
	return {"place": "Main Street", "residents": residents, "dead": dead, "damage": damage,
		"burned": burned, "note": note}


# ================================================================ shots

## What the shots are of: the row that can burn (for clear_shot.gd, so its
## own walls never count as being in the way).
func subjects() -> Array:
	var out: Array = []
	for e in _row:
		out.append(e.b)
	return out


## Down on the road beside the row: [eye, look, creep] for day_cycle's _glide.
func street_shot() -> Array:
	var side := _park_out.cross(Vector3.UP)
	var park: Vector3 = _road.back() if not _road.is_empty() else _centre + _park_out * 1.5 * tile
	var eye := park + _park_out * 1.0 * tile + side * 2.2 * tile + Vector3.UP * 0.35 * tile
	var look := _centre + Vector3.UP * 0.55 * tile - side * 0.3 * tile
	return [eye, look, -side * 0.5 * tile]


## Up over the road, the burning buildings and the road the trucks come down.
func wide_shot() -> Array:
	var side := _park_out.cross(Vector3.UP)
	if not _road.is_empty():
		var along := _flat3(_road[0] - _road.back()).normalized()
		if along != Vector3.ZERO and along.dot(side) < 0.0:
			side = -side   # sit on the side the trucks come from
	var back := 3.8 if fire_force else 5.2
	var up := 2.6 if fire_force else 3.8
	var eye := _centre + _park_out * back * tile + side * 2.4 * tile + Vector3.UP * up * tile
	var look := _centre + _park_out * 0.8 * tile + Vector3.UP * 0.4 * tile
	return [eye, look, side * 0.6 * tile]


# ================================================================ the quake

## The quake: Main Street shakes, the gas main bursts BURST_TIME in, the first
## building catches and the fire takes the next one NEXT_DOOR later.
func start() -> void:
	_fx = Node3D.new()
	_fx.name = "FireFX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D()
	# the street the broken glass lands on
	var ground := QuakeFX.particle_floor(_fx, _centre, ground_y, 24.0 * tile)
	ground.size = Vector3(24.0 * tile, 0.5 * tile, 24.0 * tile)
	ground.global_position = Vector3(_centre.x, ground_y - 0.25 * tile, _centre.z)
	_start_sound()
	for i in _row.size():
		_shake(_row[i].b, BuildingQuake.Outcome.DAMAGED if i == 0 else BuildingQuake.Outcome.UNDAMAGED)
	for b in _others:
		_shake(b, BuildingQuake.Outcome.UNDAMAGED)
	_t = 0.0
	set_process(true)
	_burst_later()


func _shake(b: Node3D, outcome: int) -> void:
	var bq := BuildingQuake.new()
	bq.name = "Quake_%s" % b.name
	bq.building = b
	bq.intensity = 0.7
	bq.duration = SHAKE_TIME
	bq.glass = false
	bq.dust = false
	bq.debris = false
	bq.people = false
	bq.smoke = false
	bq.leave_rubble = false
	bq.shake_camera = false
	bq.break_off_parts = false
	bq.ground_crack = false
	add_child(bq)
	bq.trigger(outcome, _rng.randf_range(0.0, 0.3))


func _burst_later() -> void:
	await get_tree().create_timer(BURST_TIME, false).timeout
	if not is_inside_tree() or _row.is_empty():
		return
	# the gas main goes up in the street in front of the first building
	var box: AABB = _row[0].box
	var p := _face_point(box, _park_out, 0.0) + _park_out * 0.25 * tile
	p.y = ground_y + 0.1 * tile
	_fireball(p)
	burst.emit()
	_ignite(0, 0.75)
	_runners(_row[0], 3)
	await get_tree().create_timer(NEXT_DOOR, false).timeout
	if is_inside_tree() and _row.size() > 1 and CAUGHT > 1:
		_ignite(1, 0.6)
		_runners(_row[1], 3)


## Minutes later (the cut to the second half): what has caught is now fully
## alight, the walls already scorched.
func skip_ahead() -> void:
	for i in mini(CAUGHT, _row.size()):
		if not _row[i].lit:
			_ignite(i, 1.0)
		# by now every window the fire was going to take has gone
		for w in _row[i].windows:
			if not w.broken:
				_break_window(_row[i], w, false)
		_update_crackle(_row[i])
		_row[i].target = 1.0
		_row[i].heat = maxf(_row[i].heat, 0.85)
		_row[i].char = maxf(_row[i].char, 0.35)


## No fire station: the fire takes the rest of the row, one building at a time.
func let_it_burn() -> void:
	_spreading = true
	_next_spread = _t + SPREAD_TIME * 0.6


## The trucks come down the road, sirens wailing, park, raise their ladders
## and put the fire out.
func call_crews() -> void:
	if _crews_out:
		return
	_crews_out = true
	_crews_done = false
	_siren = 1.0
	var burning: Array[Dictionary] = []
	for e in _row:
		if e.lit:
			burning.append(e)
	if burning.is_empty() or _road.size() < 2:
		_crews_done = true
		return
	var drive := TRAINED_DRIVE_TIME if trained else DRIVE_TIME
	for k in 2:
		var truck := _make_truck()
		if truck == null:
			continue
		var t := {"node": truck, "target": burning[k % burning.size()], "jet": null, "mist": null,
			"steam": null, "ladder": truck.get_node_or_null("Ladder"), "lights": [], "v": Vector3.ZERO,
			"origin": Vector3.ZERO, "aim": Vector3.ZERO, "sway": _rng.randf() * 10.0}
		_flashers(t)
		_trucks.append(t)
		# the second truck stops a length behind the first
		var path := _road.duplicate()
		if k == 1:
			var back: Vector3 = (path[path.size() - 2] - path.back()).normalized()
			path[path.size() - 1] = path.back() + back * 1.25 * tile
		_drive(t, path, drive + k * 1.2)


## The crews are done / the whole row is burning.
func is_done() -> bool:
	if fire_force:
		return _crews_done
	for e in _row:
		if not e.lit or e.heat < 0.8:
			return false
	return true


## Fade the sound out (the place is over).
func quiet(time := 1.2) -> void:
	var t := create_tween()
	t.tween_property(self, "_volume", 0.0, time)


# ================================================================ fire

## Set building `i` alight, starting at `heat`.
func _ignite(i: int, heat: float) -> void:
	var e: Dictionary = _row[i]
	if e.lit:
		return
	e.lit = true
	e.target = 1.0
	e.heat = heat * 0.5
	var box: AABB = e.box
	var c := box.get_center()
	# a few windows that will shatter one by one, flames pouring out of each,
	# and the fire breaking through the roof
	e.age = 0.0         # seconds since it caught
	e.windows = _pick_windows(box)
	e.roof = _roof_flames(box)
	e.core = _core_flames(box)
	e.sparks = _sparks(box)
	e.crackle = _crackle(box)
	e.pop = 0.0         # 0..1, a burst of sparks right now
	e.smoke = _smoke(Vector3(c.x, box.end.y + 0.1 * tile, c.z), Vector3(box.size.x * 0.35, 0.05 * tile, box.size.z * 0.35),
		SMOKE, 90, 9.0, 1.1, 1.0)
	e.steam = _smoke(Vector3(c.x, box.end.y - box.size.y * 0.2, c.z), Vector3(box.size.x * 0.5, box.size.y * 0.25, box.size.z * 0.5),
		STEAM, 70, 4.0, 0.8, 0.7)
	(e.steam as GPUParticles3D).amount_ratio = 0.0
	# a soft glow on the street (each burning window adds its own small light)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.18)
	light.omni_range = maxf(box.size.x, box.size.z) * 0.5 + 2.0 * tile
	light.omni_attenuation = 1.6
	light.light_energy = 0.0
	light.shadow_enabled = false
	_fx.add_child(light)
	light.global_position = _face_point(box, _park_out, 0.55) + _park_out * 1.2 * tile
	e.light = light
	e.mat = _char_material(e.b)
	# the first window blows out as it catches
	if not (e.windows as Array).is_empty():
		_break_window(e, e.windows[0], true)
		_update_crackle(e)


func _process(delta: float) -> void:
	_t += delta
	var total := 0.0
	for i in _row.size():
		var e: Dictionary = _row[i]
		if not e.lit:
			continue
		# heat climbs toward its target; water drives it down
		var douse_time := TRAINED_DOUSE_TIME if trained else DOUSE_TIME
		if e.douse > 0.0:
			e.target = 0.0
			e.heat = move_toward(e.heat, 0.0, delta / douse_time * e.douse)
		else:
			e.heat = move_toward(e.heat, e.target, delta * 0.17)
		if e.heat > 0.05:
			e.char = minf(0.85 if not fire_force else 0.6, e.char + delta * 0.035 * e.heat)
		if e.heat <= 0.0 and e.douse > 0.0 and not e.out:
			e.out = true
		total += e.heat
		var flick := 0.75 + 0.25 * _noise.get_noise_2d(_t * 9.0, i * 31.0) + 0.15 * _noise.get_noise_2d(_t * 23.0, i * 7.0)
		# the next window gives way as the fire climbs (not once the water is on it)
		e.age += delta
		var broke := false
		for w in e.windows:
			if not w.broken and e.age >= w.at and e.heat > 0.15 and e.douse <= 0.0:
				_break_window(e, w, true)
				broke = true
		if broke:
			_update_crackle(e)
		var k := 0
		for w in e.windows:
			k += 1
			if not w.broken:
				continue
			var wf := clampf(flick + 0.2 * _noise.get_noise_2d(_t * 13.0, i * 17.0 + k * 5.0), 0.5, 1.2)
			(w.flames as GPUParticles3D).amount_ratio = clampf(e.heat * 1.15, 0.0, 1.0)
			(w.core as GPUParticles3D).amount_ratio = clampf(e.heat * 1.3 - 0.2, 0.0, 1.0) * clampf(wf, 0.6, 1.0)
			(w.smoke as GPUParticles3D).amount_ratio = clampf(maxf(e.heat, e.char * 0.4), 0.0, 1.0)
			(w.light as OmniLight3D).light_energy = 3.0 * e.heat * wf
			(w.glow as StandardMaterial3D).emission_energy_multiplier = 4.0 * e.heat * wf
		(e.roof as GPUParticles3D).amount_ratio = clampf(e.heat * 1.2 - 0.2, 0.0, 1.0)
		(e.core as GPUParticles3D).amount_ratio = clampf(e.heat * 1.3 - 0.3, 0.0, 1.0) * clampf(flick, 0.6, 1.0)
		(e.sparks as GPUParticles3D).amount_ratio = clampf(e.heat * (0.55 + 0.45 * flick), 0.0, 1.0)
		# every so often something gives way inside and a burst of sparks pops out
		if e.heat > 0.3 and _rng.randf() < delta * 1.6 * e.heat:
			e.pop = 1.0
		e.pop = maxf(0.0, e.pop - delta * 2.5)
		(e.crackle as GPUParticles3D).amount_ratio = clampf(e.heat * (0.08 + 0.92 * e.pop), 0.0, 1.0)
		# smoke keeps going thinly after the flames die; steam while water hits
		(e.smoke as GPUParticles3D).amount_ratio = clampf(maxf(e.heat, e.char * 0.45), 0.0, 1.0)
		(e.steam as GPUParticles3D).amount_ratio = clampf(e.douse * (0.3 + e.heat), 0.0, 1.0)
		(e.light as OmniLight3D).light_energy = 2.5 * e.heat * flick
		# the walls only scorch a little; the fire shows through the windows
		var m: StandardMaterial3D = e.mat
		m.albedo_color.a = clampf(e.char * 0.5, 0.0, 0.4)

	# left alone, the fire takes the next building down the row
	if _spreading and _t >= _next_spread:
		for i in _row.size():
			if not _row[i].lit:
				_ignite(i, 0.5)
				_runners(_row[i], 2)
				break
		_next_spread = _t + SPREAD_TIME * _rng.randf_range(0.8, 1.2)

	# the trucks' jets
	var water := 0.0
	for t in _trucks:
		_tick_truck(t, delta)
		if t.jet != null:
			water += 0.5
	_water_level = move_toward(_water_level, clampf(water, 0.0, 1.0), delta * 1.5)
	if _crews_out and not _crews_done:
		var all_out := true
		for e in _row:
			if e.lit and e.heat > 0.0:
				all_out = false
		if all_out and _t > 2.0:
			_crews_done = true
			_shut_off()
	_fire_level = clampf(total / 2.0, 0.0, 1.0)
	_feed_sound()


# ================================================================ trucks

## A copy of the fire station's parked engine (one tile = one station unit),
## or a plain red truck if there is no station in the city.
func _make_truck() -> Node3D:
	var src: Node3D = null
	var station := _city.get_node_or_null(STATION)
	if station:
		for path in ["Engine3", "Rise/Main/Engine1", "Main/Engine1"]:
			src = station.get_node_or_null(path) as Node3D
			if src:
				break
	var truck: Node3D
	if src:
		truck = src.duplicate() as Node3D
		truck.visible = true
		truck.process_mode = Node.PROCESS_MODE_INHERIT
		for n in truck.find_children("*", "Node3D", true, false):
			(n as Node3D).visible = true
	else:
		truck = _plain_truck()
	truck.name = "FireTruck"
	_fx.add_child(truck)
	truck.global_transform = Transform3D(Basis().scaled(Vector3.ONE * tile), _road[0])
	return truck


func _plain_truck() -> Node3D:
	var t := Node3D.new()
	var red := _mat(Color(0.78, 0.07, 0.05), 0.5)
	_box(t, Vector3(0.36, 0.26, 0.62), Vector3(0, 0.18, -0.12), red)
	_box(t, Vector3(0.36, 0.24, 0.22), Vector3(0, 0.17, 0.3), red)
	_box(t, Vector3(0.3, 0.1, 0.02), Vector3(0, 0.23, 0.41), _mat(Color(0.2, 0.3, 0.4), 0.1))
	_box(t, Vector3(0.37, 0.03, 0.64), Vector3(0, 0.135, -0.12), _mat(Color(0.95, 0.95, 0.9), 0.6))
	var ladder := Node3D.new()
	ladder.name = "Ladder"
	ladder.position = Vector3(0, 0.33, -0.1)
	t.add_child(ladder)
	_box(ladder, Vector3(0.12, 0.03, 0.6), Vector3(0, 0, 0), _mat(Color(0.8, 0.8, 0.8), 0.4))
	for x in [-0.16, 0.16]:
		for z in [0.28, -0.3]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.05
			cm.height = 0.05
			w.mesh = cm
			w.material_override = _mat(Color(0.08, 0.08, 0.08), 0.9)
			w.rotation.z = PI * 0.5
			w.position = Vector3(x, 0.05, z)
			t.add_child(w)
	return t


## Red and white lights on the cab roof, flashing in turn.
func _flashers(t: Dictionary) -> void:
	var truck: Node3D = t.node
	for k in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.1, 0.08) if k == 0 else Color(0.85, 0.9, 1.0)
		l.omni_range = 1.4 * tile
		l.light_energy = 0.0
		l.shadow_enabled = false
		truck.add_child(l)
		l.position = Vector3(-0.08 if k == 0 else 0.08, 0.4, 0.32)
		t.lights.append(l)


## Drive along `path` (world points) in `time` seconds, slowing to a stop.
func _drive(t: Dictionary, path: Array, time: float) -> void:
	var truck: Node3D = t.node
	var lengths: Array[float] = [0.0]
	for i in range(1, path.size()):
		lengths.append(lengths[i - 1] + (path[i] as Vector3).distance_to(path[i - 1]))
	var total: float = lengths.back()
	if total <= 0.0:
		return
	t.driving = true
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		if not is_instance_valid(truck):
			return
		var s := k * total
		var i := 1
		while i < path.size() - 1 and lengths[i] < s:
			i += 1
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var seg := maxf(0.001, lengths[i] - lengths[i - 1])
		var p := a.lerp(b, clampf((s - lengths[i - 1]) / seg, 0.0, 1.0))
		var dir := _flat3(b - a).normalized()
		var want := Basis.looking_at(-dir, Vector3.UP)
		var cur := truck.global_basis.orthonormalized()
		var rot := cur.slerp(want, 0.2) if k > 0.0 else want
		truck.global_transform = Transform3D(rot.scaled(Vector3.ONE * tile), p), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_parked.bind(t))


## Parked: ladder up toward the fire, then the water comes on.
func _parked(t: Dictionary) -> void:
	t.driving = false
	var truck: Node3D = t.node
	if not is_instance_valid(truck):
		return
	var e: Dictionary = t.target
	var box: AABB = e.box
	t.aim = _face_point(box, _park_out, 0.62) + Vector3.UP * 0.05 * tile
	var ladder: Node3D = t.ladder
	if ladder:
		var tw := create_tween()
		tw.tween_property(ladder, "rotation:x", deg_to_rad(28.0), 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished
	else:
		await get_tree().create_timer(1.0, false).timeout
	if not is_inside_tree() or not is_instance_valid(truck):
		return
	t.origin = truck.global_position + Vector3.UP * 0.5 * tile
	_open_jet(t)


## The deck gun opens: an arc of water onto the fire, mist where it lands.
func _open_jet(t: Dictionary) -> void:
	var d: Vector3 = t.aim - t.origin
	var g := Vector3(0, -WATER_G * tile, 0)
	var flight := clampf(_flat(d).length() / (JET_SPEED * tile), 0.6, 2.2)
	var v := (d - 0.5 * g * flight * flight) / flight
	t.v = v
	var pm := ParticleProcessMaterial.new()
	pm.direction = v.normalized()
	pm.spread = 1.6
	pm.initial_velocity_min = v.length() * 0.97
	pm.initial_velocity_max = v.length() * 1.03
	pm.gravity = g
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.45), Vector2(0.5, 1.2), Vector2(1, 2.0)])
	pm.color = Color(WATER, 0.85)
	pm.color_ramp = QuakeFX.ramp([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)],
		[0.0, 0.5, 0.92, 1.0])
	var jet := QuakeFX.emitter(_fx, Transform3D(Basis(), t.origin), _water_quad(), _q(360), flight * 1.05, pm, false, 0.0)
	jet.visibility_aabb = AABB(Vector3(-12, -6, -12) * tile, Vector3(24, 16, 24) * tile)
	jet.fixed_fps = 0
	t.jet = jet
	# spray where it hits the wall
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mm.emission_sphere_radius = 0.15 * tile
	mm.direction = _park_out + Vector3.UP
	mm.spread = 60.0
	mm.initial_velocity_min = 0.15 * tile
	mm.initial_velocity_max = 0.45 * tile
	mm.gravity = Vector3(0, -0.3 * tile, 0)
	mm.scale_min = 0.25 * tile
	mm.scale_max = 0.5 * tile
	mm.scale_curve = QuakeFX.curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1, 1.6)])
	mm.angle_max = 360.0
	mm.color = Color(0.92, 0.96, 1.0, 0.55)
	mm.color_ramp = QuakeFX.fade_ramp(0.55)
	var mist := QuakeFX.emitter(_fx, Transform3D(Basis(), t.aim), QuakeFX.dust_mesh(), _q(60), 1.4, mm, false, 0.0)
	mist.visibility_aabb = AABB(Vector3(-4, -3, -4) * tile, Vector3(8, 8, 8) * tile)
	t.mist = mist
	_douse_later(t, flight)


func _douse_later(t: Dictionary, flight: float) -> void:
	await get_tree().create_timer(flight, false).timeout
	if is_inside_tree() and t.jet != null:
		var e: Dictionary = t.target
		e.douse = minf(1.0, e.douse + 0.6)
		# once this one is out, swing the jet onto the next fire still burning
		while is_inside_tree() and t.jet != null and e.heat > 0.0:
			await get_tree().process_frame
		e.douse = maxf(0.0, e.douse - 0.6)
		if not is_inside_tree() or t.jet == null:
			return
		for other in _row:
			if other.lit and other.heat > 0.0:
				t.target = other
				t.aim = _face_point(other.box, _park_out, 0.62)
				_retarget(t)
				return


func _retarget(t: Dictionary) -> void:
	if t.jet != null:
		(t.jet as GPUParticles3D).emitting = false
		(t.jet as Node).get_tree().create_timer(3.0, false).timeout.connect((t.jet as Node).queue_free)
		t.jet = null
	if t.mist != null:
		(t.mist as GPUParticles3D).emitting = false
		(t.mist as Node).get_tree().create_timer(2.0, false).timeout.connect((t.mist as Node).queue_free)
		t.mist = null
	_open_jet(t)


## The jet sweeps a little across the fire; the lights flash.
func _tick_truck(t: Dictionary, _delta: float) -> void:
	var k := 0
	for l in t.lights:
		var on := fmod(_t * 2.6 + k * 0.5, 1.0) < 0.5
		(l as OmniLight3D).light_energy = (5.0 if on else 0.0) * (1.0 if _crews_out else 0.0)
		k += 1
	if t.jet != null and is_instance_valid(t.jet):
		var pm := (t.jet as GPUParticles3D).process_material as ParticleProcessMaterial
		var sweep := sin(_t * 0.7 + float(t.sway)) * 0.06
		pm.direction = (t.v as Vector3).rotated(Vector3.UP, sweep).normalized()


## Every fire is out: the jets close, the sirens stop.
func _shut_off() -> void:
	_siren = 0.0
	for t in _trucks:
		if t.jet != null and is_instance_valid(t.jet):
			(t.jet as GPUParticles3D).emitting = false
		if t.mist != null and is_instance_valid(t.mist):
			(t.mist as GPUParticles3D).emitting = false
		t.jet = null
		t.mist = null
		if t.ladder:
			create_tween().tween_property(t.ladder, "rotation:x", 0.0, 2.0).set_delay(1.5)


# ================================================================ particles

# ---------------------------------------------------------------- windows

## The windows the fire will break, on a floor/column grid so they line up like
## real windows. Mostly on the street side, sometimes round the corner. The
## first is low on the street side (nearest the gas); the rest go in order of
## height, so the fire is seen climbing the building.
## Each: {pos, n, at (seconds after catching), broken}.
func _pick_windows(box: AABB) -> Array:
	var faces := _faces(box)
	var street := _best_face(box)
	var sn: Vector3 = faces[street][1]
	var sides: Array[int] = []
	for i in faces.size():
		if absf((faces[i][1] as Vector3).dot(sn)) < 0.1:
			sides.append(i)
	var floors := maxi(2, roundi(box.size.y / (FLOOR_H * tile)))
	var want := _rng.randi_range(WINDOWS_MIN, WINDOWS_MAX)
	var picked: Array = []
	var used := {}
	var tries := 0
	while picked.size() < want and tries < 80:
		tries += 1
		var fi := street
		if picked.size() > 0 and not sides.is_empty() and _rng.randf() > STREET_SHARE:
			fi = sides[_rng.randi() % sides.size()]
		var f: Array = faces[fi]
		var n: Vector3 = f[1]
		var side := Vector3(n.z, 0, -n.x)
		var half_w: float = f[2]
		var cols := maxi(2, roundi(half_w * 2.0 / (0.3 * tile)))
		var col := _rng.randi_range(0, cols - 1)
		# the first one low down, where the gas went up
		var fl := _rng.randi_range(0, mini(1, floors - 1)) if picked.is_empty() else _rng.randi_range(0, floors - 1)
		var key := "%d:%d:%d" % [fi, col, fl]
		if used.has(key):
			continue
		used[key] = true
		var across := ((float(col) + 0.5) / float(cols) * 2.0 - 1.0) * half_w * 0.8
		var p: Vector3 = f[0] + side * across
		p.y = box.position.y + box.size.y * (float(fl) + 0.55) / float(floors)
		picked.append({"pos": p + n * 0.015 * tile, "n": n, "y": p.y, "broken": false, "at": 0.0})
	if picked.is_empty():
		return picked
	var first: Dictionary = picked.pop_front()
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	picked.push_front(first)
	var at := 0.0
	for w in picked:
		w.at = at
		at += WINDOW_GAP * _rng.randf_range(0.6, 1.4)
	return picked


## A window gives way: the glass blows out (`burst`), and from then on the
## opening glows and flames pour out of it and curl up the wall.
func _break_window(e: Dictionary, w: Dictionary, burst: bool) -> void:
	if w.broken:
		return
	w.broken = true
	var pos: Vector3 = w.pos
	var n: Vector3 = w.n
	var face := QuakeFX.facing(n)   # +Z out of the wall, +Y up
	# the opening: burnt black, lit from inside by the fire
	var hole := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(WINDOW_W, WINDOW_H) * tile
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.03, 0.02, 0.018)
	gm.roughness = 1.0
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.5, 0.14)
	gm.emission_texture = _hole_texture()
	gm.emission_energy_multiplier = 0.0
	q.material = gm
	hole.mesh = q
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(hole)
	hole.global_transform = Transform3D(face, pos + n * 0.004 * tile)
	w.glow = gm
	# flames out of the window, bending up the wall above it
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(WINDOW_W * 0.38, WINDOW_H * 0.3, 0.01) * tile
	pm.direction = Vector3(0, 0.45, 1)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.25 * tile
	pm.initial_velocity_max = 0.55 * tile
	pm.gravity = Vector3(0, 0.95, 0) * tile
	pm.damping_min = 0.25 * tile
	pm.damping_max = 0.45 * tile
	_flame_look(pm, 0.16, 0.34)
	var fl := QuakeFX.emitter(_fx, Transform3D(face, pos + n * 0.02 * tile + Vector3.DOWN * WINDOW_H * 0.15 * tile),
		_flame_quad(), _q(80), 0.85, pm, false, 0.0)
	fl.amount_ratio = 0.0
	fl.visibility_aabb = AABB(Vector3(-2, -1, -2) * tile, Vector3(4, 4, 4) * tile)
	w.flames = fl
	# the white-yellow heart of it, right in the opening
	var cm := ParticleProcessMaterial.new()
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	cm.emission_box_extents = Vector3(WINDOW_W * 0.3, WINDOW_H * 0.2, 0.01) * tile
	cm.direction = Vector3(0, 0.3, 1)
	cm.spread = 12.0
	cm.initial_velocity_min = 0.12 * tile
	cm.initial_velocity_max = 0.3 * tile
	cm.gravity = Vector3(0, 0.6, 0) * tile
	cm.damping_min = 0.3 * tile
	cm.damping_max = 0.5 * tile
	_flame_look(cm, 0.08, 0.15, true)
	var core := QuakeFX.emitter(_fx, Transform3D(face, pos + n * 0.02 * tile + Vector3.DOWN * WINDOW_H * 0.2 * tile),
		_flame_quad(), _q(36), 0.5, cm, false, 0.0)
	core.amount_ratio = 0.0
	core.visibility_aabb = AABB(Vector3(-2, -1, -2) * tile, Vector3(4, 4, 4) * tile)
	w.core = core
	# black smoke rolling out of the top of the window
	w.smoke = _smoke(pos + n * 0.08 * tile + Vector3.UP * WINDOW_H * 0.6 * tile, Vector3(WINDOW_W * 0.3, 0.02, 0.05) * tile,
		SMOKE, _q(28), 4.5, 0.35, 0.6)
	# its own small light, so the wall around it glows (and nothing else)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.52, 0.2)
	l.omni_range = 0.9 * tile
	l.omni_attenuation = 1.3
	l.light_energy = 0.0
	l.shadow_enabled = false
	_fx.add_child(l)
	l.global_position = pos + n * 0.3 * tile
	w.light = l
	if burst:
		_shatter(pos, n)


## Glass blown out of a window, a puff of flame behind it and a flash.
func _shatter(pos: Vector3, n: Vector3) -> void:
	var face := QuakeFX.facing(n)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(WINDOW_W * 0.45, WINDOW_H * 0.45, 0.01) * tile
	pm.direction = Vector3(0, 0.3, 1)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5 * tile
	pm.initial_velocity_max = 1.4 * tile
	pm.gravity = Vector3(0, -3.0, 0) * tile
	pm.damping_min = 0.05 * tile
	pm.damping_max = 0.2 * tile
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.scale_curve = QuakeFX.curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0)], 1.0)
	pm.particle_flag_rotate_y = true
	pm.angle_max = 360.0
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.color_initial_ramp = QuakeFX.ramp([Color(0.75, 0.9, 1.0), Color(0.95, 1.0, 1.0), Color(1.0, 0.8, 0.55)], [0.0, 0.5, 1.0])
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.25
	pm.collision_friction = 0.6
	pm.lifetime_randomness = 0.3
	var g := QuakeFX.emitter(_fx, Transform3D(face, pos + n * 0.03 * tile), _glass_quad(), _q(45), 2.4, pm, true, 0.95)
	g.collision_base_size = 0.02 * tile
	g.visibility_aabb = AABB(Vector3(-4, -8, -4) * tile, Vector3(8, 10, 8) * tile)
	# the fire gulps the fresh air: a tongue of flame bursts out
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(WINDOW_W * 0.35, WINDOW_H * 0.3, 0.01) * tile
	fm.direction = Vector3(0, 0.25, 1)
	fm.spread = 30.0
	fm.initial_velocity_min = 0.6 * tile
	fm.initial_velocity_max = 1.3 * tile
	fm.gravity = Vector3(0, 0.8, 0) * tile
	fm.damping_min = 1.0 * tile
	fm.damping_max = 1.6 * tile
	_flame_look(fm, 0.2, 0.42)
	var puff := QuakeFX.emitter(_fx, Transform3D(face, pos + n * 0.03 * tile), _flame_quad(), _q(40), 0.9, fm, true, 0.9)
	puff.visibility_aabb = AABB(Vector3(-3, -2, -3) * tile, Vector3(6, 6, 6) * tile)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.omni_range = 1.8 * tile
	flash.light_energy = 8.0
	flash.shadow_enabled = false
	_fx.add_child(flash)
	flash.global_position = pos + n * 0.4 * tile
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)


## Crackle sparks pop out of the broken windows only.
func _update_crackle(e: Dictionary) -> void:
	var p := e.get("crackle") as GPUParticles3D
	if p == null:
		return
	var c := (e.box as AABB).get_center()
	var pts := PackedVector3Array()
	for w in e.windows:
		if w.broken:
			pts.append((w.pos as Vector3) + (w.n as Vector3) * 0.05 * tile - c)
	if pts.is_empty():
		pts.append(Vector3(0, (e.box as AABB).size.y * 0.5, 0))   # out of the roof
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_point_texture = _points_texture(pts)
	pm.emission_point_count = pts.size()


## A burnt window opening, brightest in the middle where the fire shows.
static func _hole_texture() -> GradientTexture2D:
	if _hole_tex_cache != null:
		return _hole_tex_cache
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.8))
	g.set_color(1, Color(0.12, 0.05, 0.02))
	g.add_point(0.55, Color(0.85, 0.5, 0.25))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.62)
	t.fill_to = Vector2(1.05, 0.62)
	t.width = 32
	t.height = 32
	_hole_tex_cache = t
	return t


## A small shard of window glass.
func _glass_quad() -> BoxMesh:
	if _glass_mesh != null:
		return _glass_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.94, 1.0, 0.85)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.85
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.65, 0.35)
	m.emission_energy_multiplier = 0.6
	_glass_mesh = BoxMesh.new()
	_glass_mesh.size = Vector3(0.03, 0.045, 0.004) * tile
	_glass_mesh.material = m
	return _glass_mesh


## A wall of flame along the roof.
func _roof_flames(box: AABB) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box.size.x * 0.42, 0.05 * tile, box.size.z * 0.42)
	pm.direction = Vector3.UP
	pm.spread = 16.0
	pm.initial_velocity_min = 0.75 * tile
	pm.initial_velocity_max = 1.55 * tile
	pm.radial_velocity_min = 0.05 * tile
	pm.radial_velocity_max = 0.22 * tile
	pm.gravity = Vector3(0.04, 0.28, 0.02) * tile
	pm.damping_min = 0.045 * tile
	pm.damping_max = 0.1 * tile
	_flame_look(pm, 0.75, 1.25)
	var c := box.get_center()
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), Vector3(c.x, box.end.y - 0.05 * tile, c.z)), _flame_quad(),
		_q(130), 1.25, pm, false, 0.0)
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-5, -3, -5) * tile, Vector3(10, 10, 10) * tile)
	return p


## The white-hot heart of the fire, low on the roof under the big flames.
func _core_flames(box: AABB) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box.size.x * 0.32, 0.03 * tile, box.size.z * 0.32)
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.3 * tile
	pm.initial_velocity_max = 0.7 * tile
	pm.gravity = Vector3(0, 0.16, 0) * tile
	pm.damping_min = 0.07 * tile
	pm.damping_max = 0.14 * tile
	_flame_look(pm, 0.34, 0.62, true)
	var c := box.get_center()
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), Vector3(c.x, box.end.y - 0.04 * tile, c.z)), _flame_quad(),
		_q(70), 0.7, pm, false, 0.0)
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-5, -3, -5) * tile, Vector3(10, 10, 10) * tile)
	return p


## Sparks streaking up out of the fire, swirling on the hot air as they climb.
func _sparks(box: AABB) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(box.size.x * 0.4, 0.05 * tile, box.size.z * 0.4)
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 1.0 * tile
	pm.initial_velocity_max = 2.4 * tile
	pm.gravity = Vector3(0.2, 0.3, 0.06) * tile
	pm.damping_min = 0.25 * tile
	pm.damping_max = 0.6 * tile
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.scale_curve = QuakeFX.curve([Vector2(0, 1.0), Vector2(0.7, 0.8), Vector2(1, 0.2)])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.0
	pm.turbulence_noise_scale = 1.1 * tile
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.4
	_spark_look(pm)
	pm.lifetime_randomness = 0.6
	var c := box.get_center()
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), Vector3(c.x, box.end.y, c.z)),
		_spark_quad(), _q(170), 2.6, pm, false, 0.0)
	_align_sparks(p)
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-8, -3, -8) * tile, Vector3(16, 16, 16) * tile)
	return p


## Crackle: sparks popping out of the windows in bursts, arcing and falling.
## _process drives the bursts through amount_ratio.
func _crackle(box: AABB) -> GPUParticles3D:
	var c := box.get_center()
	# filled in with the broken windows by _update_crackle
	var pts := PackedVector3Array([Vector3(0, box.size.y * 0.5, 0)])
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	pm.emission_point_texture = _points_texture(pts)
	pm.emission_point_count = pts.size()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 1.4 * tile
	pm.initial_velocity_max = 3.4 * tile
	pm.gravity = Vector3(0, -2.4, 0) * tile
	pm.damping_min = 0.3 * tile
	pm.damping_max = 0.6 * tile
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.scale_curve = QuakeFX.curve([Vector2(0, 1.0), Vector2(1, 0.25)])
	_spark_look(pm)
	pm.lifetime_randomness = 0.5
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), c), _spark_quad(), _q(240), 1.1, pm, false, 0.0)
	_align_sparks(p)
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-8, -6, -8) * tile, Vector3(16, 14, 16) * tile)
	return p


## A shower of sparks thrown out in every direction (the gas going up).
func _spark_burst(pos: Vector3, power := 1.0) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1 * tile * power
	pm.direction = Vector3.UP
	pm.spread = 110.0
	pm.initial_velocity_min = 2.0 * tile * power
	pm.initial_velocity_max = 5.0 * tile * power
	pm.gravity = Vector3(0, -2.6, 0) * tile
	pm.damping_min = 0.5 * tile
	pm.damping_max = 1.0 * tile
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.scale_curve = QuakeFX.curve([Vector2(0, 1.0), Vector2(1, 0.2)])
	_spark_look(pm)
	pm.lifetime_randomness = 0.6
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), pos), _spark_quad(), _q(int(160 * power)), 1.6, pm, true, 0.92)
	_align_sparks(p)
	p.visibility_aabb = AABB(Vector3(-8, -6, -8) * tile, Vector3(16, 14, 16) * tile)


## Spark colour: white-hot as it leaves the fire, cooling through orange to red.
func _spark_look(pm: ParticleProcessMaterial) -> void:
	pm.color = Color.WHITE
	pm.color_initial_ramp = QuakeFX.ramp([Color(1, 1, 1), Color(1, 0.85, 0.6), Color(1, 0.7, 0.45)], [0.0, 0.6, 1.0])
	pm.color_ramp = QuakeFX.ramp(
		[Color(1, 0.97, 0.85, 1), Color(1, 0.75, 0.3, 1), Color(1, 0.42, 0.08, 0.9), Color(0.7, 0.12, 0.02, 0)],
		[0.0, 0.25, 0.65, 1.0])


## Sparks are streaks that point the way they fly.
func _align_sparks(p: GPUParticles3D) -> void:
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.fixed_fps = 0


## A column of smoke (or steam) billowing up and drifting off on the wind.
func _smoke(pos: Vector3, extents: Vector3, color: Color, amount: int, life: float, size: float, rise: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.5 * rise * tile
	pm.initial_velocity_max = 1.1 * rise * tile
	pm.gravity = Vector3(0.28, 0.12, 0.1) * tile
	pm.damping_min = 0.15 * tile
	pm.damping_max = 0.3 * tile
	pm.scale_min = 0.6 * size * tile
	pm.scale_max = 1.1 * size * tile
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.4), Vector2(0.35, 1.3), Vector2(1, 3.2)], 4.0)
	pm.angle_max = 360.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.color = color
	pm.color_initial_ramp = QuakeFX.ramp([color.darkened(0.15), color.lightened(0.1)], [0.0, 1.0])
	pm.color_ramp = QuakeFX.fade_ramp(color.a)
	pm.lifetime_randomness = 0.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 3.0 * tile
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.07
	var p := QuakeFX.emitter(_fx, Transform3D(Basis(), pos), QuakeFX.dust_mesh(), _q(amount), life, pm, false, 0.0)
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-10, -3, -10) * tile, Vector3(20, 22, 20) * tile)
	return p


## The gas going up: a ball of flame, a shower of sparks, a puff of black smoke.
func _fireball(pos: Vector3, power := 1.0) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12 * tile * power
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.8 * tile * power
	pm.initial_velocity_max = 2.2 * tile * power
	pm.gravity = Vector3(0, 0.8 * tile, 0)
	pm.damping_min = 1.0 * tile
	pm.damping_max = 1.6 * tile
	_flame_look(pm, 0.45 * power, 0.9 * power)
	var ball := QuakeFX.emitter(_fx, Transform3D(Basis(), pos), _flame_quad(), _q(int(90 * power)), 1.1, pm, true, 0.95)
	ball.visibility_aabb = AABB(Vector3(-5, -3, -5) * tile, Vector3(10, 10, 10) * tile)
	_spark_burst(pos + Vector3.UP * 0.1 * tile, power)
	var s := _smoke(pos + Vector3.UP * 0.3 * tile, Vector3.ONE * 0.2 * tile * power, Color(0.1, 0.09, 0.09, 0.85),
		int(30 * power), 4.0, 0.9 * power, 1.4)
	s.amount_ratio = 1.0
	s.one_shot = true
	s.explosiveness = 0.8
	s.finished.connect(s.queue_free)
	s.restart()
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.omni_range = 4.0 * tile * power
	flash.light_energy = 14.0 * power
	flash.shadow_enabled = false
	_fx.add_child(flash)
	flash.global_position = pos + Vector3.UP * 0.3 * tile
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)


## Flame size (in tiles) and colour over a flame particle's life. `hot` is the
## white-yellow heart of the fire. The texture already carries the flame
## colours, so the ramp only fades them in and cools them to red as they rise.
func _flame_look(pm: ParticleProcessMaterial, size_min: float, size_max: float, hot := false) -> void:
	pm.scale_min = size_min * tile
	pm.scale_max = size_max * tile
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.4), Vector2(0.18, 1.05), Vector2(0.55, 0.82), Vector2(1, 0.12)])
	# a little lean; the tongue itself points the way it is climbing
	pm.angle_min = -7.0
	pm.angle_max = 7.0
	pm.angular_velocity_min = -6.0
	pm.angular_velocity_max = 6.0
	pm.particle_flag_align_y = true
	# each flame plays the flipbook from its own frame, so they never move in step
	pm.anim_speed_min = 0.9
	pm.anim_speed_max = 1.7
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.color = Color.WHITE
	pm.color_initial_ramp = QuakeFX.ramp([Color(1, 1, 0.94), Color(1, 0.9, 0.72)], [0.0, 1.0])
	if hot:
		pm.color_ramp = QuakeFX.ramp(
			[Color(1, 1, 1, 0.0), Color(1, 1, 0.95, 1.0), Color(1, 0.9, 0.6, 0.85), Color(1, 0.55, 0.15, 0.0)],
			[0.0, 0.08, 0.42, 1.0])
	else:
		pm.color_ramp = QuakeFX.ramp(
			[Color(1, 1, 1, 0.0), Color(1, 0.97, 0.9, 1.0), Color(1, 0.82, 0.55, 0.9), Color(1, 0.42, 0.1, 0.4), Color(0.35, 0.04, 0.0, 0.0)],
			[0.0, 0.06, 0.32, 0.68, 1.0])
	pm.lifetime_randomness = 0.45
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 0.75 * tile
	pm.turbulence_noise_speed = Vector3(0.4, 2.2, 0.25)
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.2


## Flame tongues: an animated flipbook, drawn additively, faded where they
## touch the walls.
func _flame_quad() -> QuadMesh:
	if _flame_mesh != null:
		return _flame_mesh
	if _flame_tex_cache == null:
		_flame_tex_cache = _make_flame_texture()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = FLAME_FRAMES
	m.particles_anim_v_frames = FLAME_FRAMES
	m.particles_anim_loop = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _flame_tex_cache
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.12 * tile
	_flame_mesh = QuadMesh.new()
	# a fat tongue, grown up from where the particle is
	_flame_mesh.size = Vector2(1.35, 1.7)
	_flame_mesh.center_offset = Vector3(0, 0.64, 0)
	_flame_mesh.material = m
	return _flame_mesh


## A thin streak, bright at the head and fading down the tail.
func _spark_quad() -> QuadMesh:
	if _spark_mesh != null:
		return _spark_mesh
	if _spark_tex_cache == null:
		_spark_tex_cache = _make_spark_texture()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# the emitter turns each streak to face the camera along its flight
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _spark_tex_cache
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.014, 0.1) * tile
	_spark_mesh.center_offset = Vector3(0, -0.035 * tile, 0)   # the head leads, the tail trails
	_spark_mesh.material = m
	return _spark_mesh


## The flame flipbook: FLAME_FRAMES x FLAME_FRAMES frames of one fat tongue
## of fire, with a shorter lobe beside it, like a big flame. White-hot at the
## root, yellow through the body, red at the rounded tip. The noise runs round
## a circle and a bright knot climbs the tongue, so the last frame leads back
## into the first.
static func _make_flame_texture() -> ImageTexture:
	var fw := FLAME_FRAME_W
	var fh := FLAME_FRAME_H
	var nf := FLAME_FRAMES
	var count := nf * nf
	var img := Image.create(fw * nf, fh * nf, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 4127
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var red := FLAME_DEEP
	var orange := FLAME
	var yellow := FLAME_YELLOW
	var white := FLAME_HOT
	for f in count:
		var ang := TAU * float(f) / float(count)
		var scroll := ang / TAU * 1.7
		var z := sin(ang)
		var x0 := (f % nf) * fw
		var y0 := floori(float(f) / float(nf)) * fh
		for py in fh:
			var y := 1.0 - (float(py) + 0.5) / float(fh)   # 0 at the base, 1 at the tip
			var n_sway := noise.get_noise_3d(1.7, y * 2.2 - scroll, z)
			var sway := n_sway * (0.02 + y * 0.22) + sin(ang) * 0.06 * y
			var height := 0.9 + 0.08 * sin(ang * 1.3)
			var yn := y / height
			var width := 0.78 * pow(clampf(1.0 - yn, 0.0, 1.0), 0.55)
			width = maxf(width * (0.9 + 0.1 * sin(yn * 4.0 + ang)), 0.04)
			var sway2 := sway + 0.34 * sin(ang + 1.1) + n_sway * y * 0.1
			var h2 := height * (0.62 + 0.12 * sin(ang * 2.0 + 0.6))
			var yn2 := y / h2
			var w2 := maxf(0.46 * pow(clampf(1.0 - yn2, 0.0, 1.0), 0.5), 0.04)
			var knot := exp(-pow((y - fposmod(scroll * 0.62, 1.0)) / 0.08, 2.0))
			for px in fw:
				var x := (float(px) + 0.5) / float(fw) * 2.0 - 1.0
				var n_edge := noise.get_noise_3d(x * 2.6 + 4.0, y * 5.0 - scroll * 1.5, z + 3.0)
				var dist := absf(x - sway) / width + n_edge * 0.16 * (0.12 + yn)
				var tongue := 0.0
				if yn < 1.0:
					tongue = smoothstep(0.0, 0.55, 1.0 - dist) * smoothstep(0.0, 0.04, y)
				var dist2 := absf(x - sway2) / w2 + n_edge * 0.14 * (0.15 + yn2)
				var lick := 0.0
				if yn2 < 1.0:
					lick = smoothstep(0.0, 0.5, 1.0 - dist2) * smoothstep(0.0, 0.04, y) * 0.9
				var body := clampf(maxf(tongue, lick), 0.0, 1.0) * (1.0 - smoothstep(0.9, 1.0, y))
				var core := 0.0
				if yn < 1.0:
					core = smoothstep(0.15, 0.75, 1.0 - dist) * (1.0 - clampf((yn - 0.02) / 0.9, 0.0, 1.0))
				core = clampf(core + knot * body * 0.35, 0.0, 1.0)
				var hot := smoothstep(0.45, 0.9, core) * (1.0 - smoothstep(0.02, 0.5, y))
				var col := red.lerp(orange, clampf(body * 1.4, 0.0, 1.0))
				col = col.lerp(yellow, clampf((core - 0.02) / 0.35, 0.0, 1.0))
				col = col.lerp(white, hot)
				var a := clampf(body * 0.62 + core * 0.32, 0.0, 0.9) * clampf(body * 2.2, 0.0, 1.0)
				col.a = a if a >= 0.02 else 0.0
				img.set_pixel(x0 + px, y0 + py, col)
	return ImageTexture.create_from_image(img)


## A spark streak: a hot round head at the top, a tail fading below it.
static func _make_spark_texture() -> ImageTexture:
	var w := 8
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py in h:
		var y := (float(py) + 0.5) / float(h)     # 0 at the head, 1 at the tail end
		for px in w:
			var x := (float(px) + 0.5) / float(w) * 2.0 - 1.0
			var across := exp(-x * x * 5.0)
			var along := pow(1.0 - y, 1.6)
			var head := exp(-pow((y - 0.06) / 0.07, 2.0)) * exp(-x * x * 3.0)
			var a := clampf(across * along * 0.85 + head, 0.0, 1.0)
			img.set_pixel(px, py, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A soft round additive quad (fire and sparks).
func _glow_quad(size: float, core: float) -> QuadMesh:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(core, Color(1, 1, 1, 0.65))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = m
	return q


func _water_quad() -> QuadMesh:
	if _water_mesh:
		return _water_mesh
	_water_mesh = _glow_quad(0.035 * tile, 0.4)
	var m := _water_mesh.material as StandardMaterial3D
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	return _water_mesh


func _points_texture(pts: PackedVector3Array) -> ImageTexture:
	var img := Image.create(maxi(1, pts.size()), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	return ImageTexture.create_from_image(img)


## Scorches the building a little as it burns (no orange glow: the fire shows
## only through its broken windows): a see-through layer over every mesh, on
## top of any overlay it has.
func _char_material(b: Node3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.035, 0.03, 0.028, 0.0)
	m.roughness = 1.0
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var old := mi.material_overlay
		if old == null:
			mi.material_overlay = m
		else:
			var copy := old.duplicate() as Material
			var last := copy
			while last.next_pass != null:
				last.next_pass = last.next_pass.duplicate()
				last = last.next_pass
			last.next_pass = m
			mi.material_overlay = copy
	return m


# ================================================================ people

## People run out of a building as it catches.
func _runners(e: Dictionary, n: int) -> void:
	for i in n:
		_runner_later(e, _rng.randf_range(0.2, 1.8))


func _runner_later(e: Dictionary, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	if not is_inside_tree():
		return
	var box: AABB = e.box
	var f: Array = _faces(box)[_best_face(box)]
	var n: Vector3 = f[1]
	var side: Vector3 = Vector3(n.z, 0, -n.x) * _rng.randf_range(-0.7, 0.7) * float(f[2])
	var p := QuakePerson.new()
	p.scale = Vector3.ONE * 1.1 * tile
	_fx.add_child(p)
	var at: Vector3 = f[0] + side + n * 0.06 * tile
	at.y = ground_y
	p.start_run(at, n.rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7)), ground_y)
	p.run_speed *= tile


# ================================================================ the road

## Find the road tile nearest the fire, then the straight run of road leading
## to it from the fire station's side: the trucks come down that.
func _plan_road(city: Node3D) -> void:
	var tiles: Array[Vector3] = []
	var roads := city.get_node_or_null(ROADS)
	if roads:
		for r in roads.get_children():
			if r is Node3D and String(r.name).begins_with("road"):
				tiles.append((r as Node3D).global_position)
	var near := _centre + Vector3.RIGHT * 1.5 * tile
	var best := INF
	for p in tiles:
		var d := _flat(p).distance_to(_flat(_centre))
		if d < best:
			best = d
			near = p
	_park_out = _flat3(near - _centre).normalized()
	if _park_out == Vector3.ZERO:
		_park_out = Vector3.RIGHT
	if tiles.is_empty():
		_road = [near + _park_out.cross(Vector3.UP) * 8.0 * tile, near]
		return
	var station := city.get_node_or_null(STATION) as Node3D
	var home := station.global_position if station else near + Vector3.RIGHT * 10.0 * tile
	var best_run: Array[Vector3] = []
	var best_score := -INF
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var run: Array[Vector3] = []
		var p := near
		for i in 9:
			var next := _road_at(tiles, p + dir * tile)
			if next == Vector3.INF:
				break
			p = next
			run.append(p)
		if run.size() < 2:
			continue
		var score: float = (dir as Vector3).dot(_flat3(home - near).normalized()) + run.size() * 0.08
		if score > best_score:
			best_score = score
			best_run = run
	_road = []
	if best_run.is_empty():
		_road = [near + _park_out.cross(Vector3.UP) * 8.0 * tile, near]
	else:
		best_run.reverse()
		_road.append_array(best_run)
		_road.append(near)
	for i in _road.size():
		_road[i].y = maxf(_road[i].y, ground_y) + 0.01 * tile


func _road_at(tiles: Array[Vector3], p: Vector3) -> Vector3:
	for q in tiles:
		if _flat(q).distance_to(_flat(p)) < 0.3 * tile:
			return q
	return Vector3.INF


# ================================================================ sound

## The fire (FIRE_SFX, looped), the sirens wailing, the hiss of water.
func _start_sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.name = "FireSound"
	_player.stream = gen
	_player.volume_db = -4.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	# the fire itself: the recording, silent until something catches
	var sfx := _fire_stream()
	if sfx:
		_fire_player = AudioStreamPlayer.new()
		_fire_player.name = "FireCrackle"
		_fire_player.stream = sfx
		_fire_player.volume_db = -80.0
		# The city is drawn in a SubViewport. A player parented in there
		# never reaches the speakers, so this one lives on the root.
		get_tree().root.add_child(_fire_player)
		_fire_player.play(randf() * sfx.get_length() * 0.5)


## FIRE_SFX set to loop, or null if it's missing (then the fire is generated).
func _fire_stream() -> AudioStream:
	if not ResourceLoader.exists(FIRE_SFX):
		push_warning("QuakeFire: %s not found, using the generated fire sound" % FIRE_SFX)
		return null
	var s := load(FIRE_SFX) as AudioStream
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = maxi(1, int(w.get_length() * w.mix_rate) - 1)
		return w
	if "loop" in s:
		s = s.duplicate() as AudioStream
		s.set("loop", true)
	return s


func _exit_tree() -> void:
	if _fire_player and is_instance_valid(_fire_player):
		_fire_player.stop()
		_fire_player.queue_free()
	_fire_player = null


func _feed_sound() -> void:
	if _fire_player:
		# loud as soon as it catches, roaring once the row is alight
		var level := sqrt(clampf(_fire_level, 0.0, 1.0)) * _volume
		_fire_player.volume_db = linear_to_db(maxf(level, 0.0001)) + FIRE_SFX_DB
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	var dt := 1.0 / MIX_RATE
	var fire := _fire_level
	for i in n:
		var white := randf() * 2.0 - 1.0
		var s := 0.0
		if _fire_player == null:
			# no recording: a low roar, with pops and crackles
			_brown = (_brown + 0.02 * white) / 1.02
			_low = lerpf(_low, _brown, 0.08)
			if randf() < 0.0009 * fire:
				_pop = randf_range(0.4, 1.0)
			_pop *= 0.996
			s = _low * 5.0 * fire + white * _pop * 0.5 * fire
		# siren: a wail sweeping up and down
		if _siren > 0.0:
			_siren_t += dt
			var f := 650.0 + 550.0 * (0.5 - 0.5 * cos(_siren_t * TAU / 3.6))
			_siren_phase = fmod(_siren_phase + f * dt, 1.0)
			var tone := sin(_siren_phase * TAU) * 0.7 + sin(_siren_phase * TAU * 2.0) * 0.2
			s += tone * 0.16 * _siren
		# water: a bright hiss
		_hp = 0.85 * (_hp + white - _last_white)
		_last_white = white
		s += _hp * 0.12 * _water_level
		s = clampf(s * _volume, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))


# ================================================================ helpers

## The face of `box` that looks most along `dir`: a point on it at `height`
## (0 = ground, 1 = roof).
func _face_point(box: AABB, dir: Vector3, height: float) -> Vector3:
	var f: Array = _faces(box)[_best_face(box, dir)]
	var p: Vector3 = f[0]
	p.y = box.position.y + box.size.y * height
	return p


func _best_face(box: AABB, dir := Vector3.ZERO) -> int:
	if dir == Vector3.ZERO:
		dir = _park_out
	var faces := _faces(box)
	var best := 0
	var best_d := -INF
	for i in faces.size():
		var d := (faces[i][1] as Vector3).dot(dir)
		if d > best_d:
			best_d = d
			best = i
	return best


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


func _box_of(n: Node) -> AABB:
	var bb := AABB()
	var first := true
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


func _q(n: int) -> int:
	return maxi(1, int(n * QUALITY))
