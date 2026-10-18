class_name CityEarthquake
extends Node3D
## City-wide earthquake.
##
## Drop this node into a scene, point `buildings_root` at the node that holds
## your districts (e.g. City/Districts) and call start_quake().
##
## What happens
##  * a seismic shock ring + wall of dust rolls out from the epicenter
##  * every building sways/jolts when the wave reaches it (stiffer buildings less)
##  * street props wobble, weak ones end up leaning
##  * fault-line fissures tear open across the ground
##  * a dusty haze settles over the city, the camera rumbles
##  * buildings near the epicenter / with low "structural_integrity" metadata
##    get a full BuildingQuake (damaged or razed), a few others evacuate.
##
## Buildings are any direct child of a node named "Buildings", or any node with
## "structural_integrity" metadata. Set metadata "quake_outcome" on a building
## ("none", "damaged", "razed") to force what happens to it.
## reset() restores everything.

signal quake_started(magnitude: float)
signal quake_finished

@export var buildings_root: Node3D
@export_range(3.0, 9.5, 0.1) var magnitude := 7.0
## Epicenter in world space (used when epicenter_node is empty and random_epicenter is off).
@export var epicenter := Vector3.ZERO
@export var epicenter_node: Node3D
@export var random_epicenter := false
@export var duration := 9.0
## World units per second the shock wave travels.
@export var wave_speed := 9.0

@export_group("Destruction")
@export var max_razed := 3
@export var max_damaged := 7
## Undamaged buildings that still get people running out / windows popping.
@export var max_evacuations := 6
@export_range(0, 30) var people_per_building := 6
@export var people_scale := 1.3

@export_group("Effects")
@export var shake_camera := true
@export var shock_ring := true
@export var dust_haze := true
@export var ground_fissures := true
@export var wobble_props := true
@export var auto_start := false

const FISSURE := "res://Models/Custom/fissure.glb"
const WAVE_SHADER := preload("res://Earthquake/quake_wave.gdshader")

var is_running := false
var building_quakes: Array[BuildingQuake] = []

var _run := 0
var _t := 0.0
var _strength := 0.0
var _epi := Vector3.ZERO
var _reach := 10.0
var _ground_y := 0.0
var _fx: Node3D
var _noise := FastNoiseLite.new()
var _shakers: Array = []      # [{node, orig, delay, amp, tall, lean}]
var _wave_mat: ShaderMaterial
var _ring_pm: ParticleProcessMaterial
var _ring_emitter: GPUParticles3D
var _env: Environment
var _env_backup := {}
var _tweens: Array[Tween] = []
var _next_kick := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	if auto_start:
		start_quake.call_deferred()


## Starts the earthquake. mag < 0 uses `magnitude`.
func start_quake(mag := -1.0) -> void:
	if buildings_root == null:
		push_warning("CityEarthquake: buildings_root not set")
		return
	reset()
	_run += 1
	var run := _run
	if mag > 0.0:
		magnitude = mag
	_strength = clampf((magnitude - 4.0) / 5.0, 0.05, 1.2)
	is_running = true
	_t = 0.0
	_next_kick = 0.8

	_fx = Node3D.new()
	_fx.name = "CityQuakeFX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D()

	var buildings := find_buildings()
	var bounds := _bounds_of(buildings)
	_ground_y = _median_base(buildings, bounds.position.y)
	if epicenter_node != null:
		_epi = epicenter_node.global_position
	elif random_epicenter:
		_epi = bounds.position + Vector3(randf() * bounds.size.x, 0, randf() * bounds.size.z)
	else:
		_epi = epicenter
	_epi.y = _ground_y
	var c := bounds.get_center()
	_reach = Vector2(bounds.size.x, bounds.size.z).length() * 0.5 + Vector2(_epi.x - c.x, _epi.z - c.z).length()

	_plan_buildings(buildings)
	if wobble_props:
		_plan_props()
	if shock_ring:
		_make_shock_ring(bounds)
	if dust_haze:
		_haze_in()
	if ground_fissures and magnitude >= 5.5:
		_make_fault_line(buildings)
	if shake_camera:
		QuakeCameraShake.rumble(self, 0.2 + 0.4 * _strength, duration)
		QuakeCameraShake.kick(self, 0.3 + 0.4 * _strength)
	quake_started.emit(magnitude)

	await get_tree().create_timer(duration + _reach / wave_speed, false).timeout
	if run != _run:
		return
	_end_quake()


## Undo everything: buildings, props, environment, effects.
func reset() -> void:
	_run += 1
	is_running = false
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for bq in building_quakes:
		if is_instance_valid(bq):
			bq.reset()
			bq.queue_free()
	building_quakes.clear()
	for s in _shakers:
		var n := (s.node as WeakRef).get_ref() as Node3D
		if n:
			n.transform = s.orig
	_shakers.clear()
	if _fx != null and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null
	_ring_emitter = null
	_wave_mat = null
	_restore_env()
	if shake_camera:
		QuakeCameraShake.stop(self)


func find_buildings() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if buildings_root == null:
		return out
	for n in buildings_root.find_children("*", "Node3D", true, false):
		var is_b := n.has_meta("structural_integrity") or (n.get_parent() != null and n.get_parent().name == &"Buildings")
		if not is_b:
			continue
		if n.find_children("*", "MeshInstance3D", true, false).is_empty() and not n is MeshInstance3D:
			continue
		var nested := false
		for o in out:
			if o.is_ancestor_of(n):
				nested = true
				break
		if not nested:
			out.append(n)
	return out


func find_props() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if buildings_root == null:
		return out
	for n in buildings_root.find_children("*", "Node3D", true, false):
		if n.get_parent() != null and n.get_parent().name == &"Props":
			out.append(n)
	return out


# ------------------------------------------------------------------ planning

func _plan_buildings(buildings: Array[Node3D]) -> void:
	var scored := []
	for b in buildings:
		var p := b.global_position
		var d := Vector2(p.x - _epi.x, p.z - _epi.z).length()
		var local := _strength * (1.0 - 0.6 * clampf(d / maxf(_reach, 0.01), 0.0, 1.0))
		var integrity := float(b.get_meta("structural_integrity", 0.85))
		var score := local * (1.15 - integrity) + randf_range(-0.08, 0.08)
		var forced := str(b.get_meta("quake_outcome", ""))
		if forced == "razed" or forced == "destroyed":
			score = 10.0
		elif forced == "damaged":
			score = 5.0
		elif forced == "none" or forced == "undamaged":
			score = -1.0
		scored.append({"b": b, "score": score, "local": local, "delay": d / wave_speed, "integrity": integrity, "forced": forced})
	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.score > y.score)
	var razed := 0
	var damaged := 0
	var evac := 0
	for e in scored:
		var b: Node3D = e.b
		var o := -1
		if e.score > 0.55 and (razed < max_razed or e.forced == "razed"):
			o = BuildingQuake.Outcome.RAZED
			razed += 1
		elif e.score > 0.25 and (damaged < max_damaged or e.forced == "damaged"):
			o = BuildingQuake.Outcome.DAMAGED
			damaged += 1
		elif e.score > 0.05 and evac < max_evacuations and e.forced == "":
			o = BuildingQuake.Outcome.UNDAMAGED
			evac += 1
		if o >= 0:
			var bq := BuildingQuake.new()
			bq.name = "Quake_%s" % b.name
			bq.building = b
			bq.intensity = clampf(e.local * 1.4, 0.4, 1.5)
			bq.duration = duration * 0.8
			bq.people_count = people_per_building if o != BuildingQuake.Outcome.UNDAMAGED else maxi(1, people_per_building / 2)
			bq.people_scale = people_scale
			bq.particle_quality = 0.55 if o == BuildingQuake.Outcome.UNDAMAGED else 0.75
			bq.shake_camera = false
			add_child(bq)
			building_quakes.append(bq)
			bq.trigger(o, e.delay)
		else:
			_add_shaker(b, e.delay, clampf(e.local * (1.25 - e.integrity) * 1.6, 0.05, 1.0), false)


func _plan_props() -> void:
	for p in find_props():
		var d := Vector2(p.global_position.x - _epi.x, p.global_position.z - _epi.z).length()
		var local := _strength * (1.0 - 0.6 * clampf(d / maxf(_reach, 0.01), 0.0, 1.0))
		_add_shaker(p, d / wave_speed, clampf(local * 1.3, 0.1, 1.2), true)


func _add_shaker(n: Node3D, delay: float, amp: float, is_prop: bool) -> void:
	var tall := 1.0
	var bb := _node_bounds(n)
	if bb.size.length() > 0.0:
		tall = clampf(bb.size.y / maxf(maxf(bb.size.x, bb.size.z), 0.01), 0.5, 4.0)
	var lean := Basis()
	# weak props end up leaning permanently (streetlights, trees, signs)
	if is_prop and amp > 0.6 and randf() < 0.6:
		var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		lean = Basis(axis, deg_to_rad(randf_range(8.0, 22.0)))
	_shakers.append({"node": weakref(n), "orig": n.transform, "delay": delay, "amp": amp, "tall": tall,
			"lean": lean, "prop": is_prop, "seed": randf() * 100.0, "debris": false, "puffed": false})


# ------------------------------------------------------------------ effects

func _make_shock_ring(bounds: AABB) -> void:
	var size := maxf(bounds.size.x, bounds.size.z) * 2.0 + _reach * 2.0
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	plane.mesh = pm
	_wave_mat = ShaderMaterial.new()
	_wave_mat.shader = WAVE_SHADER
	_wave_mat.set_shader_parameter("center", _epi)
	_wave_mat.set_shader_parameter("width", 1.6 + 1.6 * _strength)
	_wave_mat.set_shader_parameter("strength", 0.0)
	plane.material_override = _wave_mat
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(plane)
	plane.global_position = Vector3(_epi.x, _ground_y + 0.1, _epi.z)

	# a wall of dust riding on the wave front
	_ring_pm = ParticleProcessMaterial.new()
	_ring_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_ring_pm.emission_ring_axis = Vector3.UP
	_ring_pm.emission_ring_radius = 0.1
	_ring_pm.emission_ring_inner_radius = 0.0
	_ring_pm.emission_ring_height = 0.05
	_ring_pm.direction = Vector3.UP
	_ring_pm.spread = 25.0
	_ring_pm.initial_velocity_min = 0.3
	_ring_pm.initial_velocity_max = 0.9
	_ring_pm.radial_velocity_min = 0.3
	_ring_pm.radial_velocity_max = 1.0
	_ring_pm.damping_min = 0.6
	_ring_pm.damping_max = 1.0
	_ring_pm.gravity = Vector3(0, -0.1, 0)
	_ring_pm.scale_min = 0.9
	_ring_pm.scale_max = 2.0
	_ring_pm.scale_curve = QuakeFX.curve([Vector2(0, 0.4), Vector2(0.4, 1.0), Vector2(1, 1.5)])
	_ring_pm.angle_max = 360.0
	_ring_pm.color = QuakeFX.DUST_COLOR
	_ring_pm.color_ramp = QuakeFX.fade_ramp(0.7)
	_ring_pm.lifetime_randomness = 0.3
	_ring_emitter = QuakeFX.emitter(_fx, Transform3D(Basis(), Vector3(_epi.x, _ground_y + 0.05, _epi.z)),
			QuakeFX.dust_mesh(), int(400 + 400 * _strength), 2.6, _ring_pm, false, 0.0)
	# a punch of dust at the epicenter
	QuakeFX.dust(_fx, _epi + Vector3.UP * 0.1, 1.2, 80, 1.6 + 1.4 * _strength, 6.0, 1.8, 2.5, QuakeFX.DUST_COLOR, true)


func _make_fault_line(buildings: Array[Node3D]) -> void:
	if not ResourceLoader.exists(FISSURE):
		return
	var scene: PackedScene = load(FISSURE)
	var footprints: Array[AABB] = []
	for b in buildings:
		footprints.append(_node_bounds_world(b).grow(0.25))
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var count := int(4 + 6 * _strength)
	var spacing := 1.6
	var run := _run
	for i in count:
		var along := (i - count * 0.5) * spacing + randf_range(-0.4, 0.4)
		var side := Vector3(dir.z, 0, -dir.x) * randf_range(-0.5, 0.5)
		var p := _epi + dir * along + side
		var blocked := false
		for fp in footprints:
			if fp.has_point(Vector3(p.x, fp.get_center().y, p.z)):
				blocked = true
				break
		if blocked:
			continue
		var delay := absf(along) / wave_speed + 0.3
		_open_fissure(scene, p, dir, delay, run)


func _open_fissure(scene: PackedScene, p: Vector3, dir: Vector3, delay: float, run: int) -> void:
	await get_tree().create_timer(delay, false).timeout
	if run != _run or _fx == null:
		return
	var f: Node3D = scene.instantiate()
	_fx.add_child(f)
	f.global_position = Vector3(p.x, _ground_y + 0.004, p.z)
	f.rotation.y = atan2(dir.x, dir.z) + randf_range(-0.3, 0.3)
	var s := randf_range(0.9, 1.5) * (0.7 + 0.5 * _strength)
	f.scale = Vector3(s * 0.05, s, s * 0.6)
	var tw := _tw()
	tw.tween_property(f, "scale", Vector3(s, s, s), 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	QuakeFX.dust(_fx, f.global_position + Vector3.UP * 0.05, 0.4, 24, 0.6, 3.0, 0.6, 0.6)
	QuakeFX.debris(_fx, f.global_position, Vector3.UP, 18, 1.4, 35,
			[Color(0.35, 0.33, 0.3), Color(0.5, 0.47, 0.42)], 0.3, 3.0)
	if shake_camera:
		QuakeCameraShake.kick(self, 0.2)


func _haze_in() -> void:
	var envs := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if envs.is_empty():
		return
	var we: WorldEnvironment = envs[0]
	_env = we.environment
	if _env == null:
		return
	_env_backup = {
		"fog_enabled": _env.fog_enabled,
		"fog_light_color": _env.fog_light_color,
		"fog_density": _env.fog_density,
		"fog_sky_affect": _env.fog_sky_affect,
		"fog_light_energy": _env.fog_light_energy,
	}
	var base := _env.fog_density if _env.fog_enabled else 0.0
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.74, 0.67, 0.56)
	_env.fog_light_energy = 1.0
	_env.fog_sky_affect = 0.4
	_env.fog_density = base
	var tw := _tw()
	tw.tween_property(_env, "fog_density", base + 0.006 + 0.016 * _strength, duration * 0.6).set_delay(1.0)


func _haze_out() -> void:
	if _env == null or _env_backup.is_empty():
		return
	var target: float = _env_backup.fog_density if _env_backup.fog_enabled else 0.0
	var tw := _tw()
	tw.tween_property(_env, "fog_density", target, 12.0)
	tw.tween_callback(_restore_env)


func _restore_env() -> void:
	if _env != null and not _env_backup.is_empty():
		for k in _env_backup:
			_env.set(k, _env_backup[k])
	_env_backup = {}
	_env = null


func _end_quake() -> void:
	is_running = false
	if _ring_emitter != null and is_instance_valid(_ring_emitter):
		_ring_emitter.emitting = false
	# leave props leaning, put buildings back upright
	for s in _shakers:
		var n := (s.node as WeakRef).get_ref() as Node3D
		if n:
			var xf: Transform3D = s.orig
			xf.basis = s.lean * xf.basis
			n.transform = xf
	_haze_out()
	quake_finished.emit()


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not is_running:
		return
	_t += delta
	var front := _t * wave_speed
	if _wave_mat != null:
		_wave_mat.set_shader_parameter("radius", front)
		var fade := 1.0 - clampf((front - _reach) / 4.0, 0.0, 1.0)
		_wave_mat.set_shader_parameter("strength", clampf(_t * 3.0, 0.0, 1.0) * fade * (0.6 + 0.4 * _strength))
	if _ring_pm != null:
		_ring_pm.emission_ring_radius = front
		_ring_pm.emission_ring_inner_radius = maxf(0.0, front - 0.6)
		if _ring_emitter != null and is_instance_valid(_ring_emitter) and front > _reach + 2.0:
			_ring_emitter.emitting = false
	if shake_camera and _t > _next_kick and _t < duration:
		QuakeCameraShake.kick(self, randf_range(0.1, 0.3) * (0.5 + _strength))
		_next_kick = _t + randf_range(0.5, 1.4)

	for s in _shakers:
		var n := (s.node as WeakRef).get_ref() as Node3D
		if n == null:
			continue
		var lt: float = _t - s.delay
		if lt < 0.0:
			continue
		var env := _envelope(lt)
		var amp: float = s.amp * env
		var orig: Transform3D = s.orig
		var sd: float = s.seed
		var lean_k := clampf(lt / 1.5, 0.0, 1.0)
		var lean_b: Basis = Basis().slerp(Basis(s.lean.get_rotation_quaternion()), lean_k)
		if amp <= 0.001:
			var xf0 := orig
			xf0.basis = lean_b * orig.basis
			n.transform = xf0
			continue
		var f := 10.0 if s.prop else 8.0
		var tall: float = s.tall
		var off := Vector3(_noise.get_noise_2d(lt * f, sd), 0.0, _noise.get_noise_2d(sd, lt * f)) * 0.04 * amp
		var rot_amt := deg_to_rad(4.0 if s.prop else 1.4) * amp * tall
		var sway := Basis.from_euler(Vector3(_noise.get_noise_2d(lt * f * 0.5, sd + 30.0) * rot_amt, 0.0,
				_noise.get_noise_2d(lt * f * 0.5, sd + 60.0) * rot_amt))
		# the wave front visibly lifts everything as it rolls through
		off.y += exp(-pow((lt - 0.12) * 5.0, 2.0)) * (0.06 + 0.1 * _strength) * (0.4 if s.prop else 1.0)
		var xf := orig
		xf.basis = sway * lean_b * orig.basis
		xf.origin = orig.origin + off
		n.transform = xf
		# dust kicked up at the base when the wave arrives
		if not s.puffed and not s.prop and _fx != null:
			s.puffed = true
			var fb := _node_bounds_world(n)
			var fr := maxf(fb.size.x, fb.size.z) * 0.6
			QuakeFX.dust(_fx, Vector3(fb.get_center().x, _ground_y + 0.05, fb.get_center().z), fr, 6,
					0.5 + fr * 0.6, 2.2, 0.35, 0.9, QuakeFX.DUST_COLOR, true)
		# loose bits rain off the shakiest buildings once
		if not s.prop and not s.debris and amp > 0.45 and lt > 0.6 and _fx != null:
			s.debris = true
			var bb := _node_bounds_world(n)
			QuakeFX.debris(_fx, Vector3(bb.get_center().x, bb.end.y, bb.get_center().z), Vector3.UP, 10, 0.8, 80,
					[Color(0.6, 0.58, 0.55), Color(0.4, 0.38, 0.36)], bb.size.x * 0.4, 3.0)
			QuakeFX.dust(_fx, Vector3(bb.get_center().x, bb.end.y, bb.get_center().z), bb.size.x * 0.4, 8, 0.3, 2.0, 0.1, 0.3)


func _envelope(t: float) -> float:
	var attack := clampf(t / 0.5, 0.0, 1.0)
	var release := 1.0 - clampf((t - duration * 0.65) / (duration * 0.35), 0.0, 1.0)
	# the wave front hits hardest, then it keeps rolling
	var hit := 1.0 + 0.6 * exp(-t * 2.0)
	return attack * release * hit


# ------------------------------------------------------------------ helpers

func _bounds_of(nodes: Array[Node3D]) -> AABB:
	var out := AABB()
	var first := true
	for n in nodes:
		var b := _node_bounds_world(n)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	if first:
		out = AABB(global_position - Vector3(5, 0, 5), Vector3(10, 1, 10))
	return out


## Typical street level: the median of the buildings' bottoms (robust to
## bridges / river banks that dip below the streets).
func _median_base(nodes: Array[Node3D], fallback: float) -> float:
	var ys: Array[float] = []
	for n in nodes:
		var b := _node_bounds_world(n)
		if b.size != Vector3.ZERO:
			ys.append(b.position.y)
	if ys.is_empty():
		return fallback
	ys.sort()
	return ys[ys.size() / 2]


func _node_bounds_world(n: Node3D) -> AABB:
	return n.global_transform * _node_bounds(n)


func _node_bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for m in list:
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _tw() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw
