extends Node3D
## Fire crew training on the fire station apron, the evening the foreign
## rescue team's offer is signed (proposals/agency_rescue_training.tres).
##
## Created by day_cycle.gd inside the city for one evening and freed again
## when the view goes back to the office (nothing here is permanent).
##
## Two hose teams (nozzleman + backup) stand at either end of the apron, their
## lines run back to the hydrants. The visiting instructor (orange jacket,
## white helmet, clipboard) blows the whistle and the nozzles open one after
## the other: two arcs of water cross high over the apron and splash down,
## sweeping slowly from side to side, while two trainees watch from the bay
## doors. Water hiss and a pump rumbling underneath.
##
## Everything is placed in the station's own units (one unit = one city tile,
## the station is 4 wide, front toward +z), under `rig`, which has the
## station's transform. Particles live directly under this node in world
## units, so their speeds and gravity aren't scaled by the station.

const MIX_RATE := 22050
const GROUND_Y := 0.02          # top of the apron
## Water arcs, station units: how high above the nozzle, how far it lands.
const ARC_HEIGHT := 0.8
const ARC_RANGE := 2.6
const WATER_G := 3.0            # station units / s^2 (slow, reads well)
const COAT := Color(0.13, 0.16, 0.25)
const PANTS := Color(0.12, 0.13, 0.18)
const BAND := Color(0.85, 0.95, 0.2)
const HELMET := Color(0.82, 0.1, 0.08)
const ORANGE := Color(1.0, 0.45, 0.08)
const HOSE := Color(0.88, 0.84, 0.7)
const BRASS := Color(0.8, 0.62, 0.25)
const WATER := Color(0.78, 0.9, 1.0)
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]


## One firefighter. Built by _person(), moved every frame by tick().
class Crew extends Node3D:
	const STAND := 0
	const NOZZLE := 1     # both hands on the nozzle, leaning into it
	const BACKUP := 2     # behind the nozzleman, holding the line low
	const INSTRUCT := 3   # clipboard in one hand, pointing with the other
	const WATCH := 4      # arms folded

	var mode := STAND
	var phase := 0.0
	var yaw := 0.0
	## Extra turn on top of yaw (the nozzleman follows the sweep of his stream).
	var aim := 0.0
	var body: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D

	func face(p: Vector3) -> void:
		var d := p - position
		d.y = 0.0
		if d.length() > 0.0001:
			yaw = atan2(-d.x, -d.z)

	func forward() -> Vector3:
		return Vector3(-sin(yaw), 0.0, -cos(yaw))

	func tick(dt: float, t: float) -> void:
		var k := t + phase
		var al := Vector3(0, 0, -0.1)
		var ar := Vector3(0, 0, 0.1)
		var ll := 0.0
		var lr := 0.0
		var y := 0.0
		var tilt := Vector3.ZERO
		var nod := 0.0
		var turn := 0.0
		match mode:
			STAND:
				turn = sin(k * 0.4) * 0.35
				tilt.z = sin(k * 0.7) * 0.02
			NOZZLE:
				# feet apart, leaning into the push of the water
				ll = -0.3
				lr = 0.25
				tilt.x = -0.14 + sin(k * 9.0) * 0.008
				al = Vector3(1.35, 0, 0.32)
				ar = Vector3(1.45, 0, -0.18)
				nod = -0.15
				y = -0.003
			BACKUP:
				ll = -0.45
				lr = 0.35
				tilt.x = -0.22
				al = Vector3(1.0, 0, 0.25)
				ar = Vector3(1.05, 0, -0.25)
				nod = -0.2
				y = -0.006
			INSTRUCT:
				al = Vector3(0.95, 0, 0.35)   # clipboard up
				var point := maxf(0.0, sin(k * 0.55))
				ar = Vector3(0.2 + 1.3 * point, 0, 0.1 - 0.25 * point)
				turn = sin(k * 0.55) * 0.5
				nod = 0.15 * (1.0 - point)       # reading the clipboard between calls
			WATCH:
				al = Vector3(1.1, 0, 0.75)
				ar = Vector3(1.0, 0, -0.75)
				turn = sin(k * 0.5) * 0.25
				tilt.z = sin(k * 0.6) * 0.02
		rotation.y = lerp_angle(rotation.y, yaw + aim, 1.0 - exp(-7.0 * dt))
		body.position.y = y
		body.rotation = tilt
		head.rotation = Vector3(nod, turn, 0.0)
		arm_l.rotation = al
		arm_r.rotation = ar
		leg_l.rotation.x = ll
		leg_r.rotation.x = lr


## One hose team's stream of water.
class Stream:
	var nozzleman: Crew
	var origin := Vector3.ZERO        # world, at the nozzle tip
	var dir := Vector3.ZERO           # world, horizontal, unit
	var vx := 0.0                     # station units / s
	var vy := 0.0
	var water: GPUParticles3D
	var mist: GPUParticles3D
	var puddle: MeshInstance3D
	var sweep_phase := 0.0
	var on := false


var rig: Node3D

var _station: Node3D
var _tile := 26.926893
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _crew: Array[Crew] = []
var _streams: Array[Stream] = []
var _mats := {}
var _meshes := {}
var _players: Array[AudioStreamPlayer] = []
var _hiss: AudioStreamPlayer
var _pump: AudioStreamPlayer
var _water_mesh: QuadMesh

static var _hiss_wav: AudioStreamWAV
static var _pump_wav: AudioStreamWAV
static var _whistle_wav: AudioStreamWAV


func _init() -> void:
	_rng.seed = 112
	set_process(false)


## `station` is the fire station node in the city (its Buildable). Call after
## adding this node to the city.
func setup(station: Node3D) -> void:
	_station = station
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	rig.global_transform = station.global_transform
	_tile = absf(station.global_basis.get_scale().x)
	_place_crew()


# ================================================================ camera spot

## [position, look at, slow creep] in world space: a low 3/4 view from the
## front right, the bay doors behind and both arcs crossing over the apron.
func shot() -> Array:
	return [rig.to_global(Vector3(1.4, 1.05, 4.9)), rig.to_global(Vector3(-0.55, 0.38, 1.9)),
		rig.global_basis * Vector3(-0.7, -0.08, -0.25)]


# ================================================================ the crews

func _place_crew() -> void:
	# hose team A: left end, line back to the left hydrant, spraying to the right
	var a_noz := _person(Vector3(-2.0, GROUND_Y, 2.22), COAT, HELMET, 1.0)
	a_noz.face(a_noz.position + Vector3(1, 0, 0))
	a_noz.mode = Crew.NOZZLE
	var a_back := _person(Vector3(-2.24, GROUND_Y, 2.27), COAT, HELMET, 0.97)
	a_back.face(a_noz.position)
	a_back.mode = Crew.BACKUP
	# hose team B: right end, line back to the right hydrant, spraying to the left
	var b_noz := _person(Vector3(1.0, GROUND_Y, 2.22), COAT, HELMET, 1.02)
	b_noz.face(b_noz.position + Vector3(-1, 0, 0))
	b_noz.mode = Crew.NOZZLE
	var b_back := _person(Vector3(1.24, GROUND_Y, 2.27), COAT, HELMET, 0.98)
	b_back.face(b_noz.position)
	b_back.mode = Crew.BACKUP

	# the visiting instructor, between the bays and the third engine
	var boss := _person(Vector3(-0.1, GROUND_Y, 1.2), ORANGE, Color(0.96, 0.96, 0.94), 1.03)
	boss.face(Vector3(-0.5, 0, 2.3))
	boss.mode = Crew.INSTRUCT
	_clipboard(boss)
	# two trainees waiting their turn by the first bay
	var w1 := _person(Vector3(-1.3, GROUND_Y, 0.95), COAT, HELMET, 1.0)
	w1.face(Vector3(-0.6, 0, 2.3))
	w1.mode = Crew.WATCH
	var w2 := _person(Vector3(-1.08, GROUND_Y, 1.06), COAT, HELMET, 0.96)
	w2.face(Vector3(-0.4, 0, 2.3))
	w2.mode = Crew.WATCH
	for c in _crew:
		c.rotation.y = c.yaw

	# the lines: hydrant -> backup -> nozzle
	_hose([Vector3(-2.6, GROUND_Y, 2.55), Vector3(-2.55, GROUND_Y, 2.42), Vector3(-2.42, GROUND_Y, 2.4),
		Vector3(-2.3, GROUND_Y + 0.05, 2.3), Vector3(-2.05, GROUND_Y + 0.09, 2.24)])
	_hose([Vector3(2.6, GROUND_Y, 2.55), Vector3(2.3, GROUND_Y, 2.62), Vector3(1.85, GROUND_Y, 2.5),
		Vector3(1.5, GROUND_Y, 2.38), Vector3(1.3, GROUND_Y + 0.05, 2.3), Vector3(1.05, GROUND_Y + 0.09, 2.24)])

	_streams.append(_stream(a_noz, 0.0))
	_streams.append(_stream(b_noz, 1.7))


func _stream(noz: Crew, sweep: float) -> Stream:
	var s := Stream.new()
	s.nozzleman = noz
	s.sweep_phase = sweep
	var tip := noz.position + noz.forward() * 0.085 * noz.scale.x + Vector3.UP * 0.104 * noz.scale.y
	s.origin = rig.to_global(tip)
	s.dir = (rig.global_basis * noz.forward()).normalized()
	s.dir.y = 0.0
	s.dir = s.dir.normalized()
	# a parabola that tops out ARC_HEIGHT above the nozzle and lands ARC_RANGE away
	var h0 := tip.y - GROUND_Y
	s.vy = sqrt(2.0 * WATER_G * ARC_HEIGHT)
	var flight := (s.vy + sqrt(s.vy * s.vy + 2.0 * WATER_G * h0)) / WATER_G
	s.vx = ARC_RANGE / flight
	# brass nozzle in his hands
	var n := _cyl(noz.body, 0.006, 0.01, 0.05, Vector3(0, 0.104, -0.06), _mat(BRASS, 0.0, 0.4))
	n.rotation.x = -PI * 0.5
	return s


## Open the nozzle: the jet, the mist where it lands and a spreading wet patch.
func _open(s: Stream) -> void:
	if s.on:
		return
	s.on = true
	var flight := (s.vy + sqrt(s.vy * s.vy + 2.0 * WATER_G * (rig.to_local(s.origin).y - GROUND_Y))) / WATER_G
	var pm := ParticleProcessMaterial.new()
	pm.direction = _launch(s, 0.0)
	pm.spread = 1.8
	var speed := Vector2(s.vx, s.vy).length() * _tile
	pm.initial_velocity_min = speed * 0.97
	pm.initial_velocity_max = speed * 1.02
	pm.gravity = Vector3(0, -WATER_G * _tile, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.scale_curve = QuakeFX.curve([Vector2(0, 0.45), Vector2(0.5, 1.2), Vector2(1, 1.9)])
	pm.color = Color(WATER, 0.85)
	pm.color_ramp = QuakeFX.ramp([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)],
		[0.0, 0.5, 0.92, 1.0])
	s.water = QuakeFX.emitter(self, Transform3D(Basis(), s.origin), _water_quad(), 320, flight, pm, false, 0.0)
	s.water.visibility_aabb = AABB(Vector3(-160, -40, -160), Vector3(320, 120, 320))
	s.water.fixed_fps = 0   # smooth jet

	# spray and mist where it comes down
	var land := s.origin + s.dir * ARC_RANGE * _tile
	land.y = rig.to_global(Vector3(0, GROUND_Y, 0)).y
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mm.emission_sphere_radius = 0.12 * _tile
	mm.direction = Vector3.UP
	mm.spread = 55.0
	mm.initial_velocity_min = 0.15 * _tile
	mm.initial_velocity_max = 0.4 * _tile
	mm.gravity = Vector3(0, -0.25 * _tile, 0)
	mm.scale_min = 2.5
	mm.scale_max = 5.0
	mm.scale_curve = QuakeFX.curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1, 1.6)])
	mm.angle_max = 360.0
	mm.color = Color(0.92, 0.96, 1.0, 0.6)
	mm.color_ramp = QuakeFX.fade_ramp(0.55)
	s.mist = QuakeFX.emitter(self, Transform3D(Basis(), land), QuakeFX.dust_mesh(), 60, 1.4, mm, false, 0.0)
	s.mist.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 60, 120))

	# the apron darkens where the water lands
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.002
	disc.radial_segments = 28
	disc.rings = 1
	var wet := StandardMaterial3D.new()
	wet.albedo_color = Color(0.12, 0.16, 0.22, 0.45)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.08
	wet.metallic_specular = 0.9
	s.puddle = MeshInstance3D.new()
	s.puddle.mesh = disc
	s.puddle.material_override = wet
	s.puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(s.puddle)
	var lp := rig.to_local(land)
	s.puddle.position = Vector3(lp.x, GROUND_Y + 0.004, lp.z)
	s.puddle.scale = Vector3(0.01, 1.0, 0.01)
	var t := create_tween()
	t.tween_interval(flight)
	t.tween_property(s.puddle, "scale", Vector3(0.42, 1.0, 0.3), 4.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Launch direction of the jet, world space, with the nozzle `sweep` radians
## to the side.
func _launch(s: Stream, sweep: float) -> Vector3:
	var h := s.dir.rotated(Vector3.UP, sweep)
	return (h * s.vx + Vector3.UP * s.vy).normalized()


# ================================================================ show

## Whistle, then the two nozzles open one after the other.
func start() -> void:
	_player(_whistle_stream(), -8.0, false)
	_pump = _player(_pump_stream(), -60.0)
	_hiss = _player(_hiss_stream(), -60.0)
	var t := create_tween()
	t.tween_property(_pump, "volume_db", -16.0, 1.0)
	t.parallel().tween_property(_hiss, "volume_db", -9.0, 1.8).set_delay(0.9)
	# tweens belong to this node, so they stop with it if the evening is skipped
	var go := create_tween()
	for i in _streams.size():
		go.tween_interval(0.9 if i == 0 else 0.6)
		go.tween_callback(_open.bind(_streams[i]))
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	for c in _crew:
		c.tick(delta, _time)
	# the nozzlemen sweep their streams slowly from side to side
	for s in _streams:
		var sweep := sin(_time * 0.55 + s.sweep_phase) * deg_to_rad(7.0)
		s.nozzleman.aim = sweep
		if s.on and is_instance_valid(s.water):
			var pm := s.water.process_material as ParticleProcessMaterial
			pm.direction = _launch(s, sweep)
			if is_instance_valid(s.mist):
				var land := s.origin + s.dir.rotated(Vector3.UP, sweep) * ARC_RANGE * _tile
				s.mist.global_position = Vector3(land.x, s.mist.global_position.y, land.z)


## Quieter water and pump while the narrator talks.
func duck(on: bool) -> void:
	for p in [_hiss, _pump]:
		if p and is_instance_valid(p):
			var base := -9.0 if p == _hiss else -16.0
			var t := create_tween()
			t.tween_property(p, "volume_db", base - (12.0 if on else 0.0), 0.6)


func fade_out(time: float) -> void:
	for p in _players:
		if is_instance_valid(p):
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, time)


## Training's over: sound off, freed.
func close() -> void:
	set_process(false)
	for p in _players:
		if is_instance_valid(p):
			p.stop()
	queue_free()


# ================================================================ people & props

func _person(pos: Vector3, coat: Color, helmet: Color, size: float) -> Crew:
	var p := Crew.new()
	p.position = pos
	p.scale = Vector3.ONE * size
	p.phase = _rng.randf() * TAU
	rig.add_child(p)
	p.body = Node3D.new()
	p.add_child(p.body)
	var cm := _mat(coat)
	var pm := _mat(PANTS)
	var band := _mat(BAND, 0.5)
	var boot := _mat(Color(0.06, 0.06, 0.07))
	p.leg_l = _limb(p.body, Vector3(-0.012, 0.068, 0), Vector3(0.019, 0.068, 0.022), pm)
	p.leg_r = _limb(p.body, Vector3(0.012, 0.068, 0), Vector3(0.019, 0.068, 0.022), pm)
	_box(p.leg_l, Vector3(0.021, 0.004, 0.024), Vector3(0, -0.045, 0), band)
	_box(p.leg_r, Vector3(0.021, 0.004, 0.024), Vector3(0, -0.045, 0), band)
	_box(p.leg_l, Vector3(0.021, 0.016, 0.028), Vector3(0, -0.061, -0.003), boot)
	_box(p.leg_r, Vector3(0.021, 0.016, 0.028), Vector3(0, -0.061, -0.003), boot)
	# turnout coat, a bit longer and bulkier than a shirt, with reflective bands
	_box(p.body, Vector3(0.054, 0.074, 0.032), Vector3(0, 0.097, 0), cm)
	_box(p.body, Vector3(0.056, 0.006, 0.034), Vector3(0, 0.072, 0), band)
	_box(p.body, Vector3(0.056, 0.006, 0.034), Vector3(0, 0.112, 0), band)
	# air tank on the back of the crews (not the instructor)
	if coat == COAT:
		_cyl(p.body, 0.009, 0.009, 0.05, Vector3(0, 0.104, 0.022), _mat(Color(0.75, 0.76, 0.78), 0.0, 0.3))
	p.head = Node3D.new()
	p.head.position = Vector3(0, 0.134, 0)
	p.body.add_child(p.head)
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	_box(p.head, Vector3(0.032, 0.033, 0.03), Vector3(0, 0.018, 0), _mat(skin))
	# helmet: dome and a brim that sticks out further at the back
	var hm := _mat(helmet, 0.0, 0.35)
	_box(p.head, Vector3(0.037, 0.016, 0.036), Vector3(0, 0.042, 0.001), hm)
	_box(p.head, Vector3(0.046, 0.004, 0.05), Vector3(0, 0.034, 0.005), hm)
	_box(p.head, Vector3(0.01, 0.006, 0.006), Vector3(0, 0.044, -0.02), _mat(Color(0.95, 0.85, 0.3), 0.3))
	p.arm_l = _limb(p.body, Vector3(-0.035, 0.127, 0), Vector3(0.015, 0.058, 0.016), cm)
	p.arm_r = _limb(p.body, Vector3(0.035, 0.127, 0), Vector3(0.015, 0.058, 0.016), cm)
	_box(p.arm_l, Vector3(0.016, 0.004, 0.017), Vector3(0, -0.045, 0), band)
	_box(p.arm_r, Vector3(0.016, 0.004, 0.017), Vector3(0, -0.045, 0), band)
	var glove := _mat(Color(0.2, 0.17, 0.12))
	_box(p.arm_l, Vector3(0.014, 0.011, 0.014), Vector3(0, -0.063, 0), glove)
	_box(p.arm_r, Vector3(0.014, 0.011, 0.014), Vector3(0, -0.063, 0), glove)
	_crew.append(p)
	return p


## A clipboard in the instructor's left hand.
func _clipboard(p: Crew) -> void:
	var board := _box(p.arm_l, Vector3(0.026, 0.002, 0.034), Vector3(0.004, -0.068, -0.012),
		_mat(Color(0.45, 0.32, 0.18)))
	board.rotation.x = 0.35
	_box(board, Vector3(0.022, 0.001, 0.028), Vector3(0, 0.0015, 0.001), _mat(Color(0.97, 0.97, 0.95)))


## A fire hose lying along `points` (station units), as a chain of tubes.
func _hose(points: Array) -> void:
	var m := _mat(HOSE)
	var r := 0.0055
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		a.y += r
		b.y += r
		var seg_len := a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var seg := _cyl(rig, r, r, seg_len + r, (a + b) * 0.5, m)
		var d := (b - a) / seg_len
		# the cylinder runs along +y: point that along the segment
		var ax := Vector3.UP.cross(d)
		if ax.length() > 0.0001:
			seg.basis = Basis(ax.normalized(), Vector3.UP.angle_to(d))
	# couplings at the hydrant end
	var c: Vector3 = points[0]
	_cyl(rig, r * 1.6, r * 1.6, 0.012, c + Vector3.UP * (r + 0.02), _mat(BRASS, 0.0, 0.4))


func _water_quad() -> QuadMesh:
	if _water_mesh:
		return _water_mesh
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	_water_mesh = QuadMesh.new()
	_water_mesh.size = Vector2.ONE * 0.032 * _tile
	_water_mesh.material = m
	return _water_mesh


# ================================================================ sound

func _player(stream: AudioStream, db: float, keep := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	if keep:
		_players.append(p)
	else:
		p.finished.connect(p.queue_free)
	return p


## Two short blasts on the instructor's whistle (pea whistle trill).
func _whistle_stream() -> AudioStreamWAV:
	if _whistle_wav:
		return _whistle_wav
	var blasts := [[0.0, 0.22], [0.32, 0.75]]
	var n := int(MIX_RATE * 0.8)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := 0.0
		for b in blasts:
			if t >= b[0] and t < b[1]:
				env = minf(1.0, minf((t - b[0]) * 60.0, (b[1] - t) * 40.0))
		var f := 2900.0 + 180.0 * sin(TAU * 28.0 * t)   # the pea rattling
		ph += TAU * f / MIX_RATE
		var s := (0.6 * sin(ph) + 0.12 * sin(2.0 * ph)) * env * (0.85 + 0.15 * sin(TAU * 28.0 * t))
		data.encode_s16(i * 2, int(clampf(s * 0.7, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	_whistle_wav = wav
	return wav


## Hiss of the jets: bright filtered noise, cross-faded at the seam so it loops.
func _hiss_stream() -> AudioStreamWAV:
	if _hiss_wav:
		return _hiss_wav
	_hiss_wav = _loop(func(t: float, w: float, st: Dictionary) -> float:
		st.lp = st.lp + (w - st.lp) * 0.55
		st.lo = st.lo + (w - st.lo) * 0.04
		var flutter := 0.85 + 0.15 * sin(TAU * t * 1.5) * sin(TAU * t * 0.5 + 1.0)
		return ((st.lp - st.lo) * 0.55 + st.lo * 0.6) * flutter, 3.0, 19)
	return _hiss_wav


## The engine's pump: a low throb under the water.
func _pump_stream() -> AudioStreamWAV:
	if _pump_wav:
		return _pump_wav
	_pump_wav = _loop(func(t: float, w: float, st: Dictionary) -> float:
		st.lp = st.lp + (w - st.lp) * 0.015
		var hum := sin(TAU * 46.0 * t) * 0.35 + sin(TAU * 92.0 * t) * 0.15
		return (hum * (0.8 + 0.2 * sin(TAU * 8.0 * t)) + st.lp * 2.5) * 0.7, 2.0, 5)
	return _pump_wav


func _loop(gen: Callable, seconds: float, noise_seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var n := int(MIX_RATE * seconds)
	var fade := int(MIX_RATE * 0.4)
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var st := {"lp": 0.0, "lo": 0.0}
	for i in n + fade:
		buf[i] = gen.call(float(i) / MIX_RATE, rng.randf_range(-1.0, 1.0), st)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := buf[i]
		if i < fade:
			var k := float(i) / fade
			s = buf[i] * k + buf[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


# ================================================================ building blocks

func _limb(parent: Node3D, pivot: Vector3, size: Vector3, m: Material) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box(p, size, Vector3(0, -size.y * 0.5, 0), m)
	return p


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "b%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _mesh(parent, _meshes[key], pos, m)


func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var key := "c%s_%s_%s" % [r_top, r_bottom, h]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bottom
		cm.height = h
		cm.radial_segments = 10
		cm.rings = 1
		_meshes[key] = cm
	return _mesh(parent, _meshes[key], pos, m)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c, emit, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9 if metal == 0.0 else 0.45
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m
