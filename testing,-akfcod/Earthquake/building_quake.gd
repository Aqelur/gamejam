class_name BuildingQuake
extends Node3D
## Earthquake VFX focused on ONE building.
##
## Point `building` at any Node3D that contains the building's meshes (a Kenney
## building instance, a civic building scene, ...) and call trigger().
##
## Outcomes
##   UNDAMAGED - shakes hard, a few windows pop, dust sifts off the roof, people
##               evacuate. The building ends exactly as it started.
##   DAMAGED   - windows blow out, chunks of the building break off and fall,
##               cracks spread, it ends up leaning and smoking. People jump out.
##   RAZED     - everything above, then the building pancakes into the ground in
##               a huge dust cloud and leaves a rubble pile.
##   AUTO      - picks from the building's "structural_integrity" metadata and
##               `intensity` (metadata "quake_outcome" = "none"/"damaged"/"razed"
##               forces one).
##
## reset() puts the building back exactly how it was (transform, materials,
## collisions) and removes every effect, so you can trigger it again and again.

enum Outcome { AUTO, UNDAMAGED, DAMAGED, RAZED }

signal started(outcome: int)
signal main_shock
signal part_broke(chunk: RigidBody3D)
signal collapsed
signal finished(outcome: int)

const QUAKE_SHADER := preload("res://Earthquake/quake_building.gdshader")
const PAINT_SHADER := preload("res://City/building_paint.gdshader")
const WEATHER_SHADER := preload("res://City/weathering.gdshader")
const RUBBLE_PILE := "res://Models/Custom/rubble_pile.glb"
const RUBBLE_SMALL := "res://Models/Custom/rubble_small.glb"
const PLANKS := "res://Models/Custom/debris_planks.glb"
const FISSURE := "res://Models/Custom/fissure.glb"
const MAX_CUTS := 6

@export var building: Node3D
@export var outcome: Outcome = Outcome.AUTO
## How violent the shaking is. Also feeds the AUTO outcome.
@export_range(0.1, 2.0, 0.05) var intensity := 1.0
## Seconds of shaking.
@export var duration := 7.0
@export var auto_start := false

@export_group("Effects")
@export var glass := true
@export var dust := true
@export var debris := true
@export var people := true
@export_range(0, 40) var people_count := 10
@export var people_scale := 1.0
@export var break_off_parts := true
@export var leave_rubble := true
@export var ground_crack := true
@export var smoke := true
@export var shake_camera := true
## Scales particle counts (CityEarthquake lowers this when many buildings go at once).
@export_range(0.1, 2.0, 0.05) var particle_quality := 1.0

var resolved_outcome: Outcome = Outcome.UNDAMAGED
var is_running := false

var _run := 0
var _dirty := false
var _captured := false
var _t := 0.0
var _shake := 0.0
var _tilt := Basis()
var _sink := 0.0
var _fx: Node3D
var _noise := FastNoiseLite.new()

var _orig_xform := Transform3D()
var _orig_visible := true
var _meshes: Array = []         # [{mi, override, surf:[...], to_cut, qmats:[...]}]
var _qmats: Array[ShaderMaterial] = []
var _colliders: Array = []      # [[shape, disabled]]
var _bodies: Array[CollisionObject3D] = []
var _labels: Array = []         # [[label, visible]]
var _aabb := AABB()             # building-local bounds of all meshes
var _ground_y := 0.0
var _cuts: Array = []           # [{c: Vector3, h: Vector3}] in building-local space
var _broken := 0
var _chunks: Array[RigidBody3D] = []
var _paint := Color(0.75, 0.72, 0.68)
var _tweens: Array[Tween] = []


## One-liner for gameplay code:
##   BuildingQuake.play(some_building, BuildingQuake.Outcome.DAMAGED)
## Creates a BuildingQuake under the current scene, triggers it and returns it
## (keep the reference if you want to reset() it later).
static func play(target: Node3D, what: Outcome = Outcome.AUTO, power := 1.0, delay := 0.0) -> BuildingQuake:
	var bq := BuildingQuake.new()
	bq.name = "BuildingQuake_%s" % target.name
	bq.building = target
	bq.intensity = power
	var host: Node = target.get_tree().current_scene
	if host == null:
		host = target.get_tree().root
	host.add_child(bq)
	bq.trigger(what, delay)
	return bq


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	if auto_start:
		trigger.call_deferred()


## Starts the quake. force_outcome: one of Outcome (or -1 to use `outcome`).
## delay: seconds before the shaking reaches this building.
func trigger(force_outcome: int = -1, delay := 0.0) -> void:
	if building == null or not is_instance_valid(building):
		push_warning("BuildingQuake: no building assigned")
		return
	if _dirty:
		reset()
	_run += 1
	var run := _run
	_dirty = true
	is_running = true
	resolved_outcome = _resolve(force_outcome if force_outcome >= 0 else int(outcome))
	if delay > 0.0:
		await _wait(delay)
		if run != _run:
			return
	_capture()
	started.emit(resolved_outcome)
	_t = 0.0
	match resolved_outcome:
		Outcome.UNDAMAGED:
			await _seq_undamaged(run)
		Outcome.DAMAGED:
			await _seq_damaged(run)
		Outcome.RAZED:
			await _seq_razed(run)
	if run != _run:
		return
	is_running = false
	finished.emit(resolved_outcome)


## Restores the building and removes all effects.
func reset() -> void:
	_run += 1
	is_running = false
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	if _fx != null and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null
	_chunks.clear()
	if building != null and is_instance_valid(building) and _captured:
		building.transform = _orig_xform
		building.visible = _orig_visible
		for e in _meshes:
			var mi: MeshInstance3D = e.mi
			if not is_instance_valid(mi):
				continue
			mi.material_override = e.override
			var surf: Array = e.surf
			for s in surf.size():
				mi.set_surface_override_material(s, surf[s])
		for c in _colliders:
			if is_instance_valid(c[0]):
				c[0].set_deferred("disabled", c[1])
		for l in _labels:
			if is_instance_valid(l[0]):
				l[0].visible = l[1]
	_meshes.clear()
	_qmats.clear()
	_colliders.clear()
	_bodies.clear()
	_labels.clear()
	_cuts.clear()
	_broken = 0
	_shake = 0.0
	_sink = 0.0
	_tilt = Basis()
	_dirty = false
	_captured = false


# ================================================================== sequences

func _seq_undamaged(run: int) -> void:
	_rumble_start(0.55)
	_spawn_people(int(people_count * 0.7), 0.0, 0.5, duration * 0.7)
	await _wait(0.9)
	if run != _run: return
	_main_shock(0.5)
	_tween_damage(0.15, 1.5)
	# a few more windows give way while it keeps shaking
	for i in 3:
		await _wait((duration - 0.9) / 4.0)
		if run != _run: return
		_glass_pop_random(2)
		if shake_camera:
			QuakeCameraShake.kick(self, 0.15)
	await _wait((duration - 0.9) / 4.0)
	if run != _run: return
	await _settle(run)


func _seq_damaged(run: int) -> void:
	_plan_damage_cuts()
	_rumble_start(0.8)
	_spawn_people(int(people_count * 0.55), int(people_count * 0.45), 0.4, duration * 0.6)
	await _wait(0.9)
	if run != _run: return
	_main_shock(1.0)
	_tween_damage(0.8, 3.0)
	if ground_crack:
		_spawn_fissure(0.75)
	# lean over permanently
	var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var lean := deg_to_rad(randf_range(2.5, 4.5) * clampf(intensity, 0.5, 1.5))
	var tw := _tw()
	tw.tween_method(func(a: float) -> void: _tilt = Basis(axis, a), 0.0, lean, 3.0).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "_sink", -_aabb.size.y * 0.025, 3.0)
	# parts break off one after another
	var gap := 0.75
	for i in _cuts.size():
		await _wait(0.35 if i == 0 else gap)
		if run != _run: return
		_break_part(i, false)
		_glass_pop_random(2)
	await _wait(maxf(0.5, duration - 1.25 - gap * _cuts.size()))
	if run != _run: return
	await _settle(run)


func _seq_razed(run: int) -> void:
	_plan_raze_cuts()
	_rumble_start(1.0)
	_spawn_people(int(people_count * 0.4), int(people_count * 0.6), 0.3, 1.9)
	await _wait(0.9)
	if run != _run: return
	_main_shock(1.0)
	_tween_damage(1.0, 1.4)
	if ground_crack:
		_spawn_fissure(1.0)
	await _wait(0.6)
	if run != _run: return
	_glass_pop_random(3)
	# the top breaks apart
	for i in _cuts.size():
		_break_part(i, true)
		await _wait(0.12)
		if run != _run: return
	await _wait(0.25)
	if run != _run: return
	await _collapse(run)
	if run != _run: return
	await _wait(maxf(0.5, duration - 4.5))
	if run != _run: return
	_shake = 0.0
	_freeze_chunks()


# ================================================================== phases

func _rumble_start(level: float) -> void:
	var tw := _tw()
	tw.tween_property(self, "_shake", level * intensity, 0.8).from(0.0)
	if shake_camera:
		QuakeCameraShake.rumble(self, 0.18 + 0.25 * level * intensity, duration)
	if dust:
		var b := _world_bounds()
		var r := maxf(b.size.x, b.size.z) * 0.6
		QuakeFX.dust(_fx, Vector3(b.get_center().x, _ground_y + 0.03, b.get_center().z), r,
				_q(30), 0.35, 2.5, 0.25, 0.6, QuakeFX.DUST_COLOR, true)
		_roof_sift(level)


func _main_shock(power: float) -> void:
	main_shock.emit()
	_shake = clampf((0.6 + 0.6 * power) * intensity, 0.0, 2.0)
	if shake_camera:
		QuakeCameraShake.kick(self, 0.35 + 0.4 * power)
	if glass:
		_glass_burst(power)
	if dust:
		var b := _world_bounds()
		var c := b.get_center()
		var r := maxf(b.size.x, b.size.z) * 0.65
		QuakeFX.dust(_fx, Vector3(c.x, _ground_y + 0.04, c.z), r, _q(int(20 + 40 * power)), 0.5 + 0.3 * power,
				3.5, 0.35, 0.9 + power, QuakeFX.DUST_COLOR, true)
	if debris and power > 0.5:
		var b := _world_bounds()
		QuakeFX.debris(_fx, Vector3(b.get_center().x, b.end.y, b.get_center().z), Vector3.UP, _q(20), 1.5, 70,
				[_paint, Color(0.6, 0.58, 0.55), Color(0.4, 0.38, 0.36)], b.size.x * 0.4)


func _settle(run: int) -> void:
	var tw := _tw()
	tw.tween_property(self, "_shake", 0.0, 1.2)
	await tw.finished
	if run != _run: return
	if resolved_outcome == Outcome.UNDAMAGED:
		_tilt = Basis()
		_sink = 0.0
		_apply_transform(Vector3.ZERO, Basis())
	_freeze_chunks()


func _collapse(run: int) -> void:
	var h := _aabb.size.y
	var b := _world_bounds()
	var c := b.get_center()
	var foot := maxf(b.size.x, b.size.z)
	for col in _colliders:
		if is_instance_valid(col[0]):
			col[0].set_deferred("disabled", true)
	for l in _labels:
		if is_instance_valid(l[0]):
			l[0].visible = false
	if shake_camera:
		QuakeCameraShake.kick(self, 0.9)
	var fall_time := clampf(1.2 + h * 0.35, 1.4, 3.0)
	var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var lean := deg_to_rad(randf_range(5.0, 11.0))
	var tw := _tw()
	tw.tween_property(self, "_sink", -h * 1.02, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(a: float) -> void: _tilt = Basis(axis, a), 0.0, lean, fall_time)
	if dust:
		# blast of dust rolling out along the ground
		QuakeFX.dust(_fx, Vector3(c.x, _ground_y + 0.05, c.z), foot * 0.55, _q(90), 0.9 + foot * 0.25, 6.0,
				0.5, 2.6, QuakeFX.DUST_COLOR, true)
		# column pushed up as the floors pancake
		var col_e := QuakeFX.dust(_fx, Vector3(c.x, _ground_y + 0.2, c.z), foot * 0.45, _q(200), 0.8 + foot * 0.2, 5.0,
				1.6, 0.6, QuakeFX.DUST_COLOR.darkened(0.05), false, true, 0.0)
		var cpm: ParticleProcessMaterial = col_e.process_material
		cpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		cpm.emission_box_extents = Vector3(b.size.x * 0.5, 0.15, b.size.z * 0.5)
		# emitting for the length of the fall
		var stop_tw := _tw()
		stop_tw.tween_interval(fall_time)
		stop_tw.tween_callback(func() -> void:
			if is_instance_valid(col_e):
				col_e.emitting = false)
	if debris:
		QuakeFX.debris(_fx, Vector3(c.x, _ground_y + 0.15, c.z), Vector3.UP, _q(70), 2.2, 80,
				[_paint, Color(0.62, 0.6, 0.57), Color(0.45, 0.43, 0.4), Color(0.3, 0.29, 0.28)], foot * 0.4, 7.0)
	# keep smashing debris out while it falls
	var pulses := 4
	for i in pulses:
		await _wait(fall_time / pulses)
		if run != _run: return
		if debris:
			var side := Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1))
			QuakeFX.debris(_fx, Vector3(c.x, _ground_y + 0.1, c.z), side, _q(25), 1.8, 50,
					[_paint, Color(0.55, 0.53, 0.5)], foot * 0.45)
		if shake_camera:
			QuakeCameraShake.kick(self, 0.25)
	if run != _run: return
	building.visible = false
	collapsed.emit()
	if shake_camera:
		QuakeCameraShake.kick(self, 0.6)
	if dust:
		# the big lingering cloud
		QuakeFX.dust(_fx, Vector3(c.x, _ground_y + 0.3, c.z), foot * 0.7, _q(70), 1.4 + foot * 0.35, 10.0,
				0.35, 1.2, QuakeFX.DUST_COLOR, false, true, 0.9)
	if leave_rubble:
		_spawn_rubble(c, b.size)


# ================================================================== shaking

func _process(delta: float) -> void:
	if not _dirty or building == null or not is_instance_valid(building) or _meshes.is_empty():
		return
	_t += delta
	var s := _shake
	var offset := Vector3.ZERO
	var sway := Basis()
	if s > 0.0:
		var f := 9.0
		var size := maxf(_aabb.size.x, _aabb.size.z)
		offset = Vector3(_noise.get_noise_2d(_t * f, 0.0), _noise.get_noise_2d(_t * f, 40.0) * 0.25,
				_noise.get_noise_2d(0.0, _t * f)) * 0.035 * size * s
		var tall := clampf(_aabb.size.y / maxf(size, 0.01), 0.5, 3.0)
		var rx := _noise.get_noise_2d(_t * 4.0, 90.0) * deg_to_rad(1.6) * s * tall
		var rz := _noise.get_noise_2d(_t * 4.0, 130.0) * deg_to_rad(1.6) * s * tall
		sway = Basis.from_euler(Vector3(rx, 0.0, rz))
	_apply_transform(offset, sway)


func _apply_transform(offset: Vector3, sway: Basis) -> void:
	var xf := _orig_xform
	xf.basis = sway * _tilt * _orig_xform.basis
	xf.origin = _orig_xform.origin + offset + Vector3(0, _sink, 0)
	building.transform = xf


# ================================================================== setup

func _capture() -> void:
	_orig_xform = building.transform
	_orig_visible = building.visible
	_captured = true
	if _fx == null or not is_instance_valid(_fx):
		_fx = Node3D.new()
		_fx.name = "QuakeFX"
		_fx.top_level = true
		add_child(_fx)
		_fx.global_transform = Transform3D()
	var inv := building.global_transform.affine_inverse()
	var nodes: Array = building.find_children("*", "MeshInstance3D", true, false)
	if building is MeshInstance3D:
		nodes.push_front(building)
	var first := true
	for n in nodes:
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var to_cut: Transform3D = inv * mi.global_transform
		var box: AABB = to_cut * mi.get_aabb()
		_aabb = box if first else _aabb.merge(box)
		first = false
		_swap_material(mi, to_cut)
	for n in building.find_children("*", "CollisionShape3D", true, false):
		_colliders.append([n, n.disabled])
	for n in building.find_children("*", "CollisionObject3D", true, false):
		_bodies.append(n)
	if building is CollisionObject3D:
		_bodies.append(building)
	for n in building.find_children("*", "Label3D", true, false):
		_labels.append([n, n.visible])
	_ground_y = (building.global_transform * _aabb).position.y
	for m in _qmats:
		m.set_shader_parameter("clip_y", _ground_y - 0.005)
	var b := _world_bounds()
	QuakeFX.particle_floor(_fx, b.get_center(), _ground_y, maxf(b.size.x, b.size.z) * 10.0 + 6.0)


func _swap_material(mi: MeshInstance3D, to_cut: Transform3D) -> void:
	var e := {"mi": mi, "override": mi.material_override, "surf": [], "to_cut": to_cut, "qmats": []}
	var overlay := mi.material_overlay
	var count := mi.mesh.get_surface_count()
	var made := []
	for s in count:
		e.surf.append(mi.get_surface_override_material(s))
		var src := mi.get_active_material(s)
		var q := _make_qmat(src, overlay, to_cut)
		made.append(q)
	e.qmats = made
	_meshes.append(e)
	var any := false
	for q in made:
		if q != null:
			any = true
	if not any:
		return
	mi.material_override = null
	for s in count:
		if made[s] != null:
			mi.set_surface_override_material(s, made[s])


func _make_qmat(src: Material, overlay: Material, to_cut: Transform3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = QUAKE_SHADER
	if src is ShaderMaterial and (src as ShaderMaterial).shader == PAINT_SHADER:
		var sm: ShaderMaterial = src
		for p in ["albedo_tex", "paint_color", "trim_color", "paint_strength", "trim_strength", "roughness_value"]:
			var v: Variant = sm.get_shader_parameter(p)
			if v != null:
				m.set_shader_parameter(p, v)
		if sm.get_shader_parameter("paint_strength") == null:
			m.set_shader_parameter("paint_strength", 0.9)
		if sm.get_shader_parameter("trim_strength") == null:
			m.set_shader_parameter("trim_strength", 0.55)
		var pc: Variant = sm.get_shader_parameter("paint_color")
		if pc is Color:
			_paint = pc
	elif src is BaseMaterial3D:
		var bm: BaseMaterial3D = src
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return null
		if bm.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", bm.albedo_texture)
		m.set_shader_parameter("albedo_tint", bm.albedo_color)
		m.set_shader_parameter("roughness_value", bm.roughness)
		if bm.emission_enabled:
			var em := bm.emission * bm.emission_energy_multiplier
			m.set_shader_parameter("emission_color", Vector3(em.r, em.g, em.b))
		if bm.albedo_texture == null and _paint == Color(0.75, 0.72, 0.68):
			_paint = bm.albedo_color
	elif src == null:
		pass
	else:
		return null
	if overlay is ShaderMaterial and (overlay as ShaderMaterial).shader == WEATHER_SHADER:
		var om: ShaderMaterial = overlay
		for p in ["grime", "cracks", "moss", "water_line", "ground_y", "seed"]:
			var v: Variant = om.get_shader_parameter(p)
			if v != null:
				m.set_shader_parameter(p, v)
	m.set_shader_parameter("mesh_to_cut", to_cut)
	m.set_shader_parameter("cut_to_world0", building.global_transform)
	m.set_shader_parameter("keep_index", -1)
	_qmats.append(m)
	return m


func _set_all(param: String, value: Variant) -> void:
	for m in _qmats:
		m.set_shader_parameter(param, value)


func _tween_damage(to: float, time: float) -> void:
	var from := 0.0
	if not _qmats.is_empty():
		var v: Variant = _qmats[0].get_shader_parameter("damage")
		if v != null:
			from = v
	var tw := _tw()
	tw.tween_method(func(v: float) -> void: _set_all("damage", v), from, to, time)


# ================================================================== breaking

## Damaged: a couple of top corners, a roof edge and a hole in a facade.
func _plan_damage_cuts() -> void:
	_cuts.clear()
	if not break_off_parts:
		return
	var a := _aabb
	var sx := 1.0 if randf() < 0.5 else -1.0
	var sz := 1.0 if randf() < 0.5 else -1.0
	var n := 2 if intensity < 0.9 else 3
	# top corner
	_add_corner_cut(sx, sz, randf_range(0.35, 0.5), randf_range(0.16, 0.28))
	# opposite top corner or roof edge
	if randf() < 0.5:
		_add_corner_cut(-sx, -sz, randf_range(0.3, 0.45), randf_range(0.12, 0.22))
	else:
		var hy := a.size.y * randf_range(0.07, 0.12)
		var top := a.end.y
		var along_x := randf() < 0.5
		var c := Vector3(a.get_center().x, top - hy + 0.02, a.get_center().z)
		var h := Vector3(a.size.x * 0.52, hy + 0.02, a.size.z * 0.14)
		if along_x:
			c.z = (a.end.z if sz > 0 else a.position.z) - sz * a.size.z * 0.1
		else:
			h = Vector3(a.size.x * 0.14, hy + 0.02, a.size.z * 0.52)
			c.x = (a.end.x if sx > 0 else a.position.x) - sx * a.size.x * 0.1
		_cuts.append({"c": c, "h": h})
	# chunk of facade from the middle (balcony / wall section)
	if n >= 3 and a.size.y > 1.0:
		var c := a.get_center()
		c.y = a.position.y + a.size.y * randf_range(0.45, 0.7)
		var h := Vector3(a.size.x * 0.18, a.size.y * 0.08, a.size.z * 0.12)
		if randf() < 0.5:
			c.x += randf_range(-0.2, 0.2) * a.size.x
			c.z = (a.end.z if -sz > 0 else a.position.z) + sz * a.size.z * 0.08
		else:
			c.z += randf_range(-0.2, 0.2) * a.size.z
			c.x = (a.end.x if -sx > 0 else a.position.x) + sx * a.size.x * 0.08
		_cuts.append({"c": c, "h": h})


func _add_corner_cut(sx: float, sz: float, frac_w: float, frac_h: float) -> void:
	var a := _aabb
	var hw := a.size.x * frac_w * 0.5
	var hd := a.size.z * frac_w * 0.5
	var hh := a.size.y * frac_h * 0.5
	var pad := 0.04
	var c := Vector3(
		(a.end.x - hw + pad) if sx > 0 else (a.position.x + hw - pad),
		a.end.y - hh + pad,
		(a.end.z - hd + pad) if sz > 0 else (a.position.z + hd - pad))
	_cuts.append({"c": c, "h": Vector3(hw + pad, hh + pad, hd + pad)})


## Razed: the top third splits into quarters that tumble off.
func _plan_raze_cuts() -> void:
	_cuts.clear()
	if not break_off_parts:
		return
	var a := _aabb
	var frac := 0.3 if a.size.y > 1.6 else 0.4
	var hh := a.size.y * frac * 0.5
	var cy := a.end.y - hh + 0.03
	var hx := a.size.x * 0.25 + 0.03
	var hz := a.size.z * 0.25 + 0.03
	var cx := a.get_center().x
	var cz := a.get_center().z
	var quads := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	quads.shuffle()
	var count := 4 if particle_quality >= 0.6 else 2
	if count == 2:
		# halves instead of quarters
		var along_x := randf() < 0.5
		for s in [-1.0, 1.0]:
			if along_x:
				_cuts.append({"c": Vector3(cx + s * a.size.x * 0.25, cy, cz), "h": Vector3(hx, hh + 0.03, a.size.z * 0.5 + 0.05)})
			else:
				_cuts.append({"c": Vector3(cx, cy, cz + s * a.size.z * 0.25), "h": Vector3(a.size.x * 0.5 + 0.05, hh + 0.03, hz)})
		return
	for q in quads:
		_cuts.append({"c": Vector3(cx + q.x * a.size.x * 0.25, cy, cz + q.y * a.size.z * 0.25), "h": Vector3(hx, hh + 0.03, hz)})


func _push_cut_uniforms() -> void:
	var centers := PackedVector3Array()
	var halves := PackedVector3Array()
	for i in MAX_CUTS:
		if i < _cuts.size():
			centers.append(_cuts[i].c)
			halves.append(_cuts[i].h)
		else:
			centers.append(Vector3.ZERO)
			halves.append(Vector3.ZERO)
	for m in _qmats:
		m.set_shader_parameter("cut_center", centers)
		m.set_shader_parameter("cut_half", halves)
		if int(m.get_shader_parameter("keep_index")) < 0:
			m.set_shader_parameter("cut_count", _broken)


func _break_part(i: int, razing: bool) -> void:
	if i >= _cuts.size() or i >= MAX_CUTS:
		return
	var cut: Dictionary = _cuts[i]
	var center: Vector3 = cut.c
	var half: Vector3 = cut.h
	_broken = i + 1
	var bxf := building.global_transform
	var scl := bxf.basis.get_scale()
	var body := RigidBody3D.new()
	body.name = "Chunk%d" % i
	_fx.add_child(body)
	body.global_transform = Transform3D(bxf.basis.orthonormalized(), bxf * center)
	var holder := Node3D.new()
	holder.transform = Transform3D(Basis.from_scale(scl), -center * scl)
	body.add_child(holder)
	var box := AABB(center - half * 1.3, half * 2.6)
	for e in _meshes:
		var mi: MeshInstance3D = e.mi
		var to_cut: Transform3D = e.to_cut
		if not is_instance_valid(mi) or not box.intersects(to_cut * mi.get_aabb()):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.transform = to_cut
		var qs: Array = e.qmats
		var has_any := false
		for s in qs.size():
			if qs[s] == null:
				continue
			var cm: ShaderMaterial = (qs[s] as ShaderMaterial).duplicate()
			cm.set_shader_parameter("keep_index", i)
			cm.set_shader_parameter("clip_y", -1000.0)
			_qmats.append(cm)
			copy.set_surface_override_material(s, cm)
			has_any = true
		if has_any:
			holder.add_child(copy)
		else:
			copy.free()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (half * 2.0 * scl * 0.8).max(Vector3(0.04, 0.04, 0.04))
	shape.shape = bs
	body.add_child(shape)
	body.mass = maxf(0.5, bs.size.x * bs.size.y * bs.size.z * 40.0)
	for b in _bodies:
		if is_instance_valid(b):
			body.add_collision_exception_with(b)
	for other in _chunks:
		if is_instance_valid(other):
			body.add_collision_exception_with(other)
	# throw it outward from the building's middle
	var mid := bxf * _aabb.get_center()
	var out := body.global_position - mid
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var speed := randf_range(0.6, 1.3) if razing else randf_range(0.35, 0.8)
	body.linear_velocity = out * speed + Vector3.UP * randf_range(0.2, 0.7)
	var spin_axis := out.cross(Vector3.UP).normalized()
	body.angular_velocity = -spin_axis * randf_range(1.5, 4.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	body.contact_monitor = true
	body.max_contacts_reported = 2
	body.body_entered.connect(_on_chunk_hit.bind(body))
	_chunks.append(body)
	_push_cut_uniforms()
	part_broke.emit(body)
	var wp := body.global_position
	if shake_camera:
		QuakeCameraShake.kick(self, 0.3)
	if dust:
		QuakeFX.dust(_fx, wp, half.length() * 0.6, _q(18), 0.35 + half.length() * 0.4, 3.0, 0.3, 0.6)
		# trail of dust while it falls
		var trail := QuakeFX.dust(body, wp, half.length() * 0.3, _q(24), 0.25 + half.length() * 0.3, 1.6,
				0.1, 0.15, QuakeFX.DUST_COLOR, false, false, 0.0)
		var tw := _tw()
		tw.tween_interval(1.8)
		tw.tween_callback(func() -> void:
			if is_instance_valid(trail):
				trail.emitting = false)
	if debris:
		QuakeFX.debris(_fx, wp, out + Vector3.UP * 0.5, _q(22), 1.4, 45, [_paint, Color(0.55, 0.53, 0.5)], half.length() * 0.5)
	if glass:
		var gx := Transform3D(QuakeFX.facing(out), wp)
		QuakeFX.glass(_fx, gx, Vector2(half.x, half.y), _q(30), 1.2)
	if smoke and not razing and resolved_outcome == Outcome.DAMAGED and i == 0:
		_start_smoke(wp)


func _on_chunk_hit(_other: Node, body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.has_meta("hit"):
		return
	if body.global_position.y > _ground_y + 0.6:
		return
	body.set_meta("hit", true)
	var p := body.global_position
	p.y = _ground_y + 0.05
	if dust:
		QuakeFX.dust(_fx, p, 0.15, _q(22), 0.45, 3.0, 0.3, 1.0, QuakeFX.DUST_COLOR, true)
	if debris:
		QuakeFX.debris(_fx, p, Vector3.UP, _q(16), 1.2, 70, [_paint, Color(0.5, 0.48, 0.45)], 0.08)
	if shake_camera:
		QuakeCameraShake.kick(self, 0.25)


func _freeze_chunks() -> void:
	for c in _chunks:
		if is_instance_valid(c) and c.linear_velocity.length() < 0.3:
			c.freeze = true


# ================================================================== glass / dust / props

func _faces() -> Array:
	# building-local faces: [center, normal, half_width, half_height]
	var a := _aabb
	var c := a.get_center()
	var hy := a.size.y * 0.5
	return [
		[Vector3(c.x, c.y, a.end.z), Vector3(0, 0, 1), a.size.x * 0.5, hy],
		[Vector3(c.x, c.y, a.position.z), Vector3(0, 0, -1), a.size.x * 0.5, hy],
		[Vector3(a.end.x, c.y, c.z), Vector3(1, 0, 0), a.size.z * 0.5, hy],
		[Vector3(a.position.x, c.y, c.z), Vector3(-1, 0, 0), a.size.z * 0.5, hy],
	]


func _glass_burst(power: float) -> void:
	var bxf := building.global_transform
	for f in _faces():
		var n: Vector3 = (bxf.basis * f[1]).normalized()
		var center: Vector3 = bxf * f[0] + n * 0.02
		# windows are on the upper ~85% of the facade
		center.y += f[3] * 0.1
		var area: float = f[2] * f[3]
		var amount := _q(int((25 + 70 * area) * power))
		QuakeFX.glass(_fx, Transform3D(QuakeFX.facing(n), center), Vector2(f[2] * 0.9, f[3] * 0.85), amount,
				1.0 + 1.2 * power)


func _glass_pop(world_pos: Vector3, normal: Vector3, amount: int) -> void:
	if not glass:
		return
	QuakeFX.glass(_fx, Transform3D(QuakeFX.facing(normal), world_pos + normal * 0.02), Vector2(0.08, 0.08), _q(amount), 1.4)


func _glass_pop_random(count: int) -> void:
	for i in count:
		var p := _facade_point(randf_range(0.3, 0.9))
		_glass_pop(p[0], p[1], 14)


## Random point on a random facade at height ratio h. Returns [pos, normal].
func _facade_point(h: float) -> Array:
	var f: Array = _faces().pick_random()
	var bxf := building.global_transform
	var n: Vector3 = (bxf.basis * f[1]).normalized()
	var side: Vector3 = Vector3(f[1].z, 0, -f[1].x) * randf_range(-0.8, 0.8) * f[2]
	var local: Vector3 = f[0] + side
	local.y = _aabb.position.y + _aabb.size.y * h
	return [bxf * local, n]


func _roof_sift(level: float) -> void:
	var b := _world_bounds()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(b.size.x * 0.55, 0.02, b.size.z * 0.55)
	pm.direction = Vector3.DOWN
	pm.spread = 15.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, -0.6, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.28
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.4), Vector2(1, 1.6)])
	pm.angle_max = 360.0
	pm.color = QuakeFX.DUST_COLOR
	pm.color_ramp = QuakeFX.fade_ramp(0.55)
	var e := QuakeFX.emitter(_fx, Transform3D(Basis(), Vector3(b.get_center().x, b.end.y, b.get_center().z)),
			QuakeFX.dust_mesh(), _q(int(30 * level) + 8), 2.5, pm, false, 0.0)
	var tw := _tw()
	tw.tween_interval(duration * 0.8)
	tw.tween_callback(func() -> void:
		if is_instance_valid(e):
			e.emitting = false)


func _start_smoke(pos: Vector3) -> void:
	var e := QuakeFX.dust(_fx, pos, 0.08, _q(26), 0.5, 6.0, 0.35, 0.05, QuakeFX.DARK_DUST_COLOR, false, false, 0.0)
	var pm: ParticleProcessMaterial = e.process_material
	pm.gravity = Vector3(0.05, 0.08, 0.0)
	pm.spread = 12.0


func _spawn_rubble(center: Vector3, size: Vector3) -> void:
	var foot := Vector2(size.x, size.z)
	if ResourceLoader.exists(RUBBLE_PILE):
		var pile: Node3D = (load(RUBBLE_PILE) as PackedScene).instantiate()
		_fx.add_child(pile)
		var pb := _local_bounds(pile)
		var sx := foot.x * 1.15 / maxf(pb.size.x, 0.01)
		var sz := foot.y * 1.15 / maxf(pb.size.z, 0.01)
		var sy := clampf(minf(sx, sz) * 0.8, 0.2, 3.0)
		pile.scale = Vector3(sx, sy, sz)
		pile.rotation.y = randf() * TAU
		pile.global_position = Vector3(center.x, _ground_y - pb.size.y * sy, center.z)
		var tw := _tw()
		tw.tween_property(pile, "global_position:y", _ground_y - pb.position.y * sy, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in 4:
		var path: String = [RUBBLE_SMALL, RUBBLE_SMALL, PLANKS, RUBBLE_SMALL][i]
		if not ResourceLoader.exists(path):
			continue
		var r: Node3D = (load(path) as PackedScene).instantiate()
		_fx.add_child(r)
		var ang := randf() * TAU
		var dist := maxf(foot.x, foot.y) * randf_range(0.55, 0.85)
		r.global_position = Vector3(center.x + cos(ang) * dist, _ground_y, center.z + sin(ang) * dist)
		r.rotation.y = randf() * TAU
		r.scale = Vector3.ONE * randf_range(0.6, 1.0)


func _spawn_fissure(size: float) -> void:
	if not ResourceLoader.exists(FISSURE):
		return
	var f: Node3D = (load(FISSURE) as PackedScene).instantiate()
	_fx.add_child(f)
	var b := _world_bounds()
	var fb := _local_bounds(f)
	var want := maxf(b.size.x, b.size.z) * (1.4 + size * 0.8)
	var s := want / maxf(maxf(fb.size.x, fb.size.z), 0.01)
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * maxf(b.size.x, b.size.z) * 0.6
	f.global_position = Vector3(b.get_center().x, _ground_y + 0.005, b.get_center().z) + side
	f.rotation.y = randf() * TAU
	f.scale = Vector3(s * 0.1, s, s * 0.1)
	var tw := _tw()
	tw.tween_property(f, "scale", Vector3(s, s, s), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if dust:
		QuakeFX.dust(_fx, f.global_position, want * 0.3, _q(20), 0.35, 2.5, 0.4, 0.5)


# ================================================================== people

func _spawn_people(runners: int, jumpers: int, start: float, spread: float) -> void:
	if not people:
		return
	var run := _run
	for i in runners:
		_delayed_person(run, start + randf() * spread, false)
	for i in jumpers:
		_delayed_person(run, start + 0.5 + randf() * spread, true)


func _delayed_person(run: int, delay: float, jumper: bool) -> void:
	await _wait(delay)
	if run != _run or _fx == null or not is_instance_valid(_fx):
		return
	if not building.visible or (jumper and _sink < -0.05):
		return
	var p := QuakePerson.new()
	p.scale = Vector3.ONE * people_scale
	_fx.add_child(p)
	if jumper:
		var fp := _facade_point(randf_range(0.25, 0.85))
		var pos: Vector3 = fp[0]
		var n: Vector3 = fp[1]
		_glass_pop(pos + Vector3.UP * 0.05, n, 16)
		var v := n * randf_range(0.6, 1.1) + Vector3.UP * randf_range(0.6, 1.2)
		v += Vector3(n.z, 0, -n.x) * randf_range(-0.3, 0.3)
		p.start_jump(pos + n * 0.03, v, _ground_y)
		p.landed.connect(_on_person_landed)
	else:
		var fp := _facade_point(0.0)
		var n: Vector3 = fp[1]
		var dir := n.rotated(Vector3.UP, randf_range(-0.7, 0.7))
		p.start_run(fp[0] + n * 0.05, dir, _ground_y)


func _on_person_landed(p: QuakePerson) -> void:
	if dust and _fx != null and is_instance_valid(_fx):
		QuakeFX.dust(_fx, p.global_position + Vector3.UP * 0.02, 0.03, 6, 0.12, 1.2, 0.15, 0.3, QuakeFX.DUST_COLOR, true)


# ================================================================== helpers

func _resolve(o: int) -> Outcome:
	if o != Outcome.AUTO:
		return o as Outcome
	var forced: String = str(building.get_meta("quake_outcome", ""))
	match forced:
		"none", "undamaged":
			return Outcome.UNDAMAGED
		"damaged":
			return Outcome.DAMAGED
		"razed", "destroyed":
			return Outcome.RAZED
	var integrity: float = float(building.get_meta("structural_integrity", 0.85))
	var score := intensity * (1.15 - integrity) + randf_range(-0.08, 0.08)
	if score > 0.55:
		return Outcome.RAZED
	if score > 0.25:
		return Outcome.DAMAGED
	return Outcome.UNDAMAGED


func _world_bounds() -> AABB:
	return building.global_transform * _aabb


func _local_bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var bb: AABB = (inv * mi.global_transform) * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _q(n: int) -> int:
	return maxi(1, int(n * particle_quality))


func _tw() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(sec, 0.0), false).timeout
