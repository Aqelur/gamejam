extends Node3D
## The Influencer's one-night concert on the beach (influencer_concert.tres).
##
## Built entirely in code by day_cycle.gd when that proposal is approved, shown
## at the end of the day, and taken down again (close()) when the screen goes
## black. Nothing is added to City/city.tscn, and the parasols and towels it
## stands on are only hidden while it is up.
##
## Everything you can see is built in "tile" units (one road tile = 1) under
## `rig`, which is scaled up to city size, so the dancers are the same little
## folk as the builders and the quake people. Lights, beams and lasers live
## under `_light_root` in world units instead, because light ranges ignore
## node scale.
##
## The music is made on the fly (AudioStreamGenerator): a 124 BPM house loop
## in A minor. Everything on stage and in the crowd moves to its beat.
##
##   start(first)     music starts (INTRO, or BUILD for a quick show)
##   nightfall(t)     sky, sun and ambient light go to night, glow goes up
##   queue_part(p)    BUILD / DROP / OUTRO, switched on the next bar
##   duck(on)         music quieter while the narrator speaks
##   crowd_shot(), wide_shot()   camera spots for day_cycle.gd
##   fade_out(t), close()        music off, daylight back, props back, freed

signal part_changed(part: int)

enum Part { OFF, INTRO, BUILD, DROP, OUTRO }

const TILE := 26.926893
const BPM := 124.0
const MIX_RATE := 22050.0
const LATENCY := 0.2
const STEP_SAMPLES := MIX_RATE * 60.0 / BPM / 4.0   # one 16th note
## Middle of the stage (world X/Z): flat sand between the promenade and the sea.
const SPOT := Vector2(-30.0, 515.0)
const LAND_Y := -1.94
const PALETTE := [Color(1.0, 0.16, 0.6), Color(0.15, 0.5, 1.0), Color(0.62, 0.18, 1.0),
	Color(0.08, 0.95, 0.72), Color(1.0, 0.6, 0.08)]
## Am  F  C  G, one chord per bar: [root Hz, minor]
const CHORDS := [[110.0, true], [87.307, false], [130.813, false], [97.999, false]]
const ARP := [0, 1, 2, 3, 2, 1, 2, 3]
const CROWD := 72

const SHIRTS := [Color(0.95, 0.2, 0.35), Color(0.2, 0.45, 0.9), Color(0.98, 0.85, 0.2),
	Color(0.2, 0.75, 0.45), Color(0.95, 0.5, 0.15), Color(0.62, 0.3, 0.85), Color(0.97, 0.97, 0.97),
	Color(0.1, 0.75, 0.8), Color(0.95, 0.45, 0.7), Color(0.12, 0.12, 0.14)]
const PANTS := [Color(0.15, 0.17, 0.25), Color(0.25, 0.22, 0.2), Color(0.35, 0.38, 0.45),
	Color(0.12, 0.12, 0.13), Color(0.55, 0.75, 0.9), Color(0.85, 0.8, 0.65)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.82, 0.6, 0.45), Color(0.6, 0.42, 0.3), Color(0.4, 0.27, 0.19)]
const HAIR := [Color(0.1, 0.07, 0.05), Color(0.3, 0.18, 0.08), Color(0.85, 0.7, 0.35),
	Color(0.55, 0.2, 0.1), Color(0.9, 0.35, 0.6), Color(0.15, 0.15, 0.17)]

const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float beat = 0.0;
uniform float mode = 0.0;
uniform float level = 1.0;
uniform vec3 col_a : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 col_b : source_color = vec3(0.2, 0.6, 1.0);
const vec2 CELLS = vec2(26.0, 11.0);

void fragment() {
	vec2 g = UV * CELLS;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float led = step(0.14, f.x) * step(f.x, 0.86) * step(0.14, f.y) * step(f.y, 0.86);
	vec2 c = (cell + 0.5) / CELLS;
	float h = 1.0 - c.y;
	float pulse = pow(1.0 - fract(beat), 3.0);
	float v;
	vec3 col;
	if (mode < 0.5) {
		v = 0.3 + 0.3 * sin(c.x * 6.0 - beat * 0.8 + h * 3.0);
		col = mix(col_a, col_b, 0.5 + 0.5 * sin(c.x * 3.0 + beat * 0.25));
	} else if (mode < 1.5) {
		float bar = 0.12 + 0.8 * abs(sin(cell.x * 1.37 + floor(beat * 2.0) * 0.9)) * (0.6 + 0.4 * pulse);
		v = step(h, bar);
		col = mix(col_b, col_a, h / max(bar, 0.01));
	} else {
		float d = length((c - 0.5) * vec2(2.4, 1.0));
		float ring = fract(d * 2.0 - beat);
		v = smoothstep(0.7, 1.0, ring) + pulse * 0.5;
		col = mix(col_a, col_b, step(0.5, fract(beat * 0.5)));
	}
	ALBEDO = col * v * led * level * 2.4 + vec3(0.015);
}
"""

## Additive light shaft, brightest at the lamp, soft at the edges.
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0);
uniform float strength = 0.2;

void fragment() {
	float along = pow(clamp(UV.y, 0.0, 1.0), 1.6);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	ALBEDO = color;
	ALPHA = clamp(strength * along * edge, 0.0, 1.0);
}
"""


## One concert-goer (or the star, or the DJ). Built by _person(), moved by dance().
class Person extends Node3D:
	const HOP := 0
	const PUMP := 1
	const SWAY := 2
	const PHONE := 3
	const SPIN := 4
	const STAR := 5
	const DJ := 6

	var move := HOP
	var lag := 0.0
	var base_yaw := 0.0
	var home := Vector3.ZERO
	var body: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D

	func dance(beat: float, energy: float, drop: bool, t: float) -> void:
		var b := beat - lag
		var pulse := pow(1.0 - fposmod(b, 1.0), 3.0)
		var hop := absf(sin(b * PI))
		var e := energy
		var y := 0.0
		var yaw := base_yaw
		var tilt := Vector3.ZERO
		var al := Vector3(0, 0, -0.12)
		var ar := Vector3(0, 0, 0.12)
		var ll := 0.0
		var lr := 0.0
		var nod := -0.18 * pulse * e
		var m := move
		if drop and (m == SWAY or m == SPIN) and int(b / 8.0) % 2 == 0:
			m = HOP   # the drop gets everyone jumping
		match m:
			HOP:
				y = hop * 0.024 * e
				al = Vector3(0, 0, -2.75 * e)
				ar = Vector3(0, 0, 2.75 * e)
				ll = hop * 0.45 * e
				lr = hop * 0.45 * e
			PUMP:
				y = -0.005 * pulse * e + (hop * 0.015 if drop else 0.0)
				ar = Vector3((1.8 + 0.7 * pulse) * minf(e * 1.4, 1.0), 0, 0.15)
				al = Vector3(0.3 * e, 0, -0.25)
			SWAY:
				var s := sin(b * PI * 0.5)
				tilt.z = s * 0.16 * e
				y = -0.004 * pulse
				al = Vector3(0, 0, -(1.9 + 0.5 * s) * e)
				ar = Vector3(0, 0, (1.9 - 0.5 * s) * e)
				ll = s * 0.2 * e
				lr = -s * 0.2 * e
			PHONE:
				y = -0.004 * pulse * e
				ar = Vector3(2.45, 0, 0.1)
				al = Vector3(0.25 * e, 0, -0.2 - 0.3 * pulse * e)
				nod *= 0.5
			SPIN:
				var k := clampf(fposmod(b, 4.0) - 3.0, 0.0, 1.0)
				yaw += smoothstep(0.0, 1.0, k) * TAU * (1.0 if e > 0.5 else 0.0)
				al = Vector3(0, 0, -1.45 * e)
				ar = Vector3(0, 0, 1.45 * e)
				y = hop * 0.01 * e
			STAR:
				position.x = home.x + sin(t * 0.35) * 0.62
				y = hop * 0.03 if drop else -0.005 * pulse
				ar = Vector3(2.35, 0, -0.35)   # mic at the mouth
				if drop:
					al = Vector3(0, 0, -2.85)
				else:
					al = Vector3(1.4 + 0.6 * pulse, 0, 0.25 + 0.25 * sin(b * PI * 0.5))
				yaw += sin(t * 0.5) * 0.35
				ll = hop * 0.4 if drop else 0.0
				lr = ll
			DJ:
				var scratch := sin(t * 9.0) * 0.12
				ar = Vector3(1.25 + scratch, 0, 0.1)
				al = Vector3(1.25, 0, -0.1)
				if drop and fposmod(b, 16.0) < 4.0:
					al = Vector3(0, 0, -2.8)
				nod = -0.3 * pulse
				y = -0.004 * pulse
		rotation.y = yaw
		body.position.y = y
		body.rotation = tilt
		arm_l.rotation = al
		arm_r.rotation = ar
		leg_l.rotation.x = ll
		leg_r.rotation.x = -lr if m == SWAY else lr
		head.rotation.x = nod


var rig: Node3D
var part: int = Part.OFF
var beat := 0.0
var energy := 0.0

var _city: Node3D
var _light_root: Node3D
var _hidden: Array[Node3D] = []
var _env: Environment
var _sun: DirectionalLight3D
var _day := {}
var _night: Tween
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _last_bar := -1

var _mats := {}
var _meshes := {}
var _spots: Array[SpotLight3D] = []
var _aims: Array[Vector3] = []
var _beams: Array[ShaderMaterial] = []
var _follow: SpotLight3D
var _washes: Array[OmniLight3D] = []
var _crowd_light: OmniLight3D
var _strobe: OmniLight3D
var _lasers: Node3D
var _laser_mat: ShaderMaterial
var _screen: ShaderMaterial
var _strip: StandardMaterial3D
var _woofers: Array[Node3D] = []
var _sparks: Array[CPUParticles3D] = []
var _confetti: Array[CPUParticles3D] = []
var _people: Array[Person] = []
var _star: Person
var _firework_in := 0.5
var _drop_beat := 0.0

# ---- music state
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _gen_part: int = Part.OFF
var _queued := -1
var _changes: Array = []   # [time in seconds, part]
var _n := 0
var _step := -1
var _gain := 0.0
var _duck := 1.0
var _duck_to := 1.0
var _build_n := 0
var _kick_env := 0.0
var _kick_pitch := 0.0
var _kick_ph := 0.0
var _clap_env := 0.0
var _clap_vol := 1.0
var _clap_lp := 0.0
var _hat_env := 0.0
var _hat_vol := 1.0
var _last_noise := 0.0
var _bass_ph := 0.0
var _bass_env := 0.0
var _bass_lp := 0.0
var _bass_f := 55.0
var _pad_ph := PackedFloat32Array([0.0, 0.33, 0.66])
var _pad_f := PackedFloat32Array([220.0, 261.6, 329.6])
var _pad_lp := 0.0
var _arp_ph := 0.0
var _arp_env := 0.0
var _arp_f := 440.0
var _riser_lp := 0.0
var _crash_env := 0.0
var _boom_env := 0.0
var _boom_lp := 0.0
var _k_kick := exp(-7.5 / MIX_RATE)
var _k_kpitch := exp(-38.0 / MIX_RATE)
var _k_clap := exp(-20.0 / MIX_RATE)
var _k_hat := exp(-55.0 / MIX_RATE)
var _k_bass := exp(-5.0 / MIX_RATE)
var _k_arp := exp(-11.0 / MIX_RATE)
var _k_crash := exp(-1.6 / MIX_RATE)
var _k_boom := exp(-4.0 / MIX_RATE)


func _init() -> void:
	set_process(false)
	_rng.seed = 2207


# ================================================================ set up

## Build the whole show on the beach of `city` (City/city.tscn instance).
func setup(city: Node3D) -> void:
	_city = city
	var ground := LAND_Y
	var terrain := city.get_node_or_null("Beach/Terrain")
	if terrain and terrain.has_method("height_at"):
		ground = terrain.height_at(SPOT.x, SPOT.y)
	var origin := Vector3(SPOT.x, ground, SPOT.y)

	# the stage backs onto the sea, the crowd faces it from the promenade side
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	rig.position = origin
	rig.rotation.y = PI
	rig.scale = Vector3.ONE * TILE

	_light_root = Node3D.new()
	_light_root.name = "Lights"
	add_child(_light_root)
	_light_root.transform = Transform3D(Basis(Vector3.UP, PI), origin)

	var we := city.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		_day = {
			"bg": _env.background_energy_multiplier,
			"ambient": _env.ambient_light_energy,
			"glow": _env.glow_intensity,
			"glow_thr": _env.glow_hdr_threshold,
			"glow_on": _env.glow_enabled,
		}
	_sun = city.get_node_or_null("Sun") as DirectionalLight3D
	if _sun:
		_day["sun"] = _sun.light_energy
		_day["sun_col"] = _sun.light_color

	_hide_props()
	_build_stage()
	_build_lights()
	_build_fx()
	_build_crowd()


## Parasols and towels that would poke through the stage or the crowd.
func _hide_props() -> void:
	for group in ["Beach/Parasols", "Beach/Towels"]:
		var g := _city.get_node_or_null(group)
		if g == null:
			continue
		for c in g.get_children():
			var n := c as Node3D
			if n == null or not n.visible:
				continue
			var p := rig.to_local(n.global_position)
			if absf(p.x) < 2.3 and p.z > -1.0 and p.z < 3.2:
				n.visible = false
				_hidden.append(n)


func _build_stage() -> void:
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var deck := _mat(Color(0.16, 0.16, 0.18), 0.0, 0.6)
	var metal := _mat(Color(0.7, 0.72, 0.75), 0.0, 0.35, 0.8)

	# deck, with a glowing strip along the front edge
	_box(rig, Vector3(2.7, 0.1, 1.15), Vector3(0, 0.05, -0.05), deck)
	_box(rig, Vector3(2.72, 0.09, 0.02), Vector3(0, 0.045, 0.53), dark)
	_strip = _mat(Color(1, 0.2, 0.6), 3.0)
	_box(rig, Vector3(2.72, 0.012, 0.024), Vector3(0, 0.1, 0.535), _strip)
	# steps at the side
	for i in 3:
		_box(rig, Vector3(0.22, 0.033 * (i + 1), 0.08), Vector3(1.5, 0.0165 * (i + 1), 0.35 - i * 0.08), deck)

	# LED wall
	_box(rig, Vector3(2.38, 1.04, 0.05), Vector3(0, 0.62, -0.58), dark)
	_screen = ShaderMaterial.new()
	_screen.shader = _shader(SCREEN_SHADER)
	var q := QuadMesh.new()
	q.size = Vector2(2.26, 0.94)
	var scr := MeshInstance3D.new()
	scr.mesh = q
	scr.material_override = _screen
	scr.position = Vector3(0, 0.62, -0.552)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(scr)

	var title := Label3D.new()
	title.text = "THE INFLUENCER"
	title.font_size = 96
	title.outline_size = 18
	title.pixel_size = 0.0019
	title.modulate = Color(2.4, 0.8, 1.8)
	title.outline_modulate = Color(0.08, 0.0, 0.12)
	title.shaded = false
	title.position = Vector3(0, 1.22, -0.56)
	rig.add_child(title)
	var sub := Label3D.new()
	sub.text = "ONE EPIC NIGHT  •  LIVE ON THE BEACH"
	sub.font_size = 48
	sub.outline_size = 10
	sub.pixel_size = 0.0016
	sub.modulate = Color(1.8, 1.6, 0.8)
	sub.shaded = false
	sub.position = Vector3(0, 0.13, 0.555)
	rig.add_child(sub)

	# truss: two towers and a top beam the moving heads hang from
	for x in [-1.38, 1.38]:
		_box(rig, Vector3(0.07, 1.42, 0.07), Vector3(x, 0.71, 0.36), metal)
		_box(rig, Vector3(0.16, 0.02, 0.16), Vector3(x, 0.01, 0.36), dark)
	_box(rig, Vector3(2.84, 0.07, 0.07), Vector3(0, 1.4, 0.36), metal)
	_box(rig, Vector3(2.84, 0.02, 0.02), Vector3(0, 1.35, 0.36), metal)

	# speaker stacks either side
	for side in [-1.0, 1.0]:
		for level in 3:
			var cab := Vector3(side * 1.62, 0.13 + level * 0.25, 0.3)
			_box(rig, Vector3(0.34, 0.24, 0.26), cab, dark)
			var w := Node3D.new()
			w.position = cab + Vector3(0, 0, 0.131)
			rig.add_child(w)
			var cone := _mat(Color(0.22, 0.22, 0.24), 0.0, 0.4)
			var c := _cyl(w, 0.085, 0.085, 0.006, Vector3.ZERO, cone)
			c.rotation.x = PI * 0.5
			var cap := _cyl(w, 0.03, 0.03, 0.01, Vector3(0, 0, 0.003), _mat(Color(0.4, 0.4, 0.42), 0.0, 0.3, 0.6))
			cap.rotation.x = PI * 0.5
			_woofers.append(w)

	# DJ booth
	_box(rig, Vector3(0.56, 0.17, 0.2), Vector3(0.62, 0.185, -0.2), dark)
	_box(rig, Vector3(0.5, 0.02, 0.006), Vector3(0.62, 0.2, -0.098), _strip)
	_box(rig, Vector3(0.12, 0.008, 0.09), Vector3(0.5, 0.274, -0.21), _mat(Color(0.3, 0.3, 0.32)))
	_box(rig, Vector3(0.12, 0.008, 0.09), Vector3(0.74, 0.274, -0.21), _mat(Color(0.3, 0.3, 0.32)))
	var laptop := _box(rig, Vector3(0.08, 0.055, 0.004), Vector3(0.62, 0.3, -0.24), _mat(Color(0.85, 0.9, 1.0), 1.5))
	laptop.rotation.x = -0.3
	var dj := _person(rig, Vector3(0.62, 0.1, -0.36), Vector3(0.62, 0.1, 2.0), Person.DJ,
		Color(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.12), SKIN[1], HAIR[0], false)
	_box(dj.head, Vector3(0.042, 0.012, 0.012), Vector3(0, 0.038, 0.0), _mat(Color(0.95, 0.2, 0.5)))

	# the Influencer: gold jacket, pink trousers, shades and a mic
	_star = _person(rig, Vector3(-0.1, 0.1, 0.18), Vector3(-0.1, 0.1, 2.0), Person.STAR,
		Color(1.0, 0.78, 0.25), Color(1.0, 0.35, 0.7), SKIN[0], Color(0.98, 0.9, 0.55), false)
	_star.scale = Vector3.ONE * 1.35
	_star.home = _star.position
	var gold := _mat(Color(1.0, 0.78, 0.25), 0.4, 0.25, 0.9)
	for mi in _star.body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.material_override == _mat(Color(1.0, 0.78, 0.25)):
			m.material_override = gold
	_box(_star.head, Vector3(0.036, 0.008, 0.004), Vector3(0, 0.02, -0.017), _mat(Color(0.02, 0.02, 0.03), 0.0, 0.1))
	_cyl(_star.arm_r, 0.004, 0.003, 0.03, Vector3(0, -0.066, -0.008), _mat(Color(0.1, 0.1, 0.1)))
	_sphere(_star.arm_r, 0.0065, Vector3(0, -0.05, -0.008), _mat(Color(0.5, 0.5, 0.52), 0.0, 0.3, 0.8))

	# crowd barrier
	_box(rig, Vector3(2.9, 0.05, 0.012), Vector3(0, 0.045, 0.74), _mat(Color(0.75, 0.76, 0.78), 0.0, 0.4, 0.6))
	for i in 9:
		_box(rig, Vector3(0.012, 0.07, 0.04), Vector3(-1.44 + i * 0.36, 0.035, 0.74), dark)


func _build_lights() -> void:
	# moving heads on the truss, each with a visible shaft of light
	for i in 6:
		var x := -1.1 + i * 0.44
		_box(rig, Vector3(0.07, 0.05, 0.07), Vector3(x, 1.33, 0.36), _mat(Color(0.12, 0.12, 0.13)))
		var sp := _spot(Vector3(x, 1.28, 0.36), 14.0, 13.0 * TILE)
		var mat := _beam(sp, 10.0 * TILE, 0.12)
		_spots.append(sp)
		_beams.append(mat)
		_aims.append(Vector3(x * 1.2, 0.0, 1.8))
	# follow spot on the star, from the front of house
	_follow = _spot(Vector3(0.0, 1.6, 3.4), 7.0, 8.0 * TILE)
	_follow.light_color = Color(1.0, 0.95, 0.88)
	_follow.light_energy = 0.0
	_beam(_follow, 4.5 * TILE, 0.05)

	for x in [-0.8, 0.8]:
		var w := OmniLight3D.new()
		w.position = Vector3(x, 0.55, 0.65) * TILE
		w.omni_range = 3.2 * TILE
		w.light_energy = 0.0
		_light_root.add_child(w)
		_washes.append(w)
	_crowd_light = OmniLight3D.new()
	_crowd_light.position = Vector3(0, 1.3, 1.9) * TILE
	_crowd_light.omni_range = 3.4 * TILE
	_crowd_light.light_energy = 0.0
	_light_root.add_child(_crowd_light)
	_strobe = OmniLight3D.new()
	_strobe.position = Vector3(0, 1.6, 0.6) * TILE
	_strobe.omni_range = 6.0 * TILE
	_strobe.light_energy = 0.0
	_light_root.add_child(_strobe)

	# laser fan from the top of the LED wall, only during the drop
	_lasers = Node3D.new()
	_lasers.position = Vector3(0, 1.1, -0.5) * TILE
	_light_root.add_child(_lasers)
	_laser_mat = ShaderMaterial.new()
	_laser_mat.shader = _shader(BEAM_SHADER)
	_laser_mat.set_shader_parameter("color", Color(0.25, 1.0, 0.45))
	_laser_mat.set_shader_parameter("strength", 1.2)
	for i in 9:
		var pivot := Node3D.new()
		pivot.rotation = Vector3(0.12 + 0.05 * absf(i - 4), PI + (i - 4) * 0.17, 0)
		_lasers.add_child(pivot)
		var l := 11.0 * TILE
		var cm := CylinderMesh.new()
		cm.top_radius = 0.9
		cm.bottom_radius = 0.18
		cm.height = l
		cm.radial_segments = 6
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _laser_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.x = -PI * 0.5
		mi.position.z = -l * 0.5
		pivot.add_child(mi)
	_lasers.visible = false


func _build_fx() -> void:
	# cold-spark fountains along the stage front
	for x in [-0.95, -0.32, 0.32, 0.95]:
		var p := _particles(rig, Vector3(x, 0.1, 0.5), 70, 0.9, Color(3.0, 2.1, 0.9), 0.014)
		p.direction = Vector3.UP
		p.spread = 7.0
		p.initial_velocity_min = 0.65
		p.initial_velocity_max = 0.9
		p.gravity = Vector3(0, -0.7, 0)
		p.emitting = false
		_sparks.append(p)
	# confetti cannons
	for x in [-1.2, 1.2]:
		var c := _particles(rig, Vector3(x, 0.14, 0.5), 160, 3.6, Color.WHITE, 0.018)
		c.one_shot = true
		c.explosiveness = 0.85
		c.direction = Vector3(-x * 0.15, 1.0, 0.35)
		c.spread = 28.0
		c.initial_velocity_min = 1.3
		c.initial_velocity_max = 1.8
		c.gravity = Vector3(0, -0.45, 0)
		c.damping_min = 0.5
		c.damping_max = 0.9
		c.angular_velocity_min = -400.0
		c.angular_velocity_max = 400.0
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1.6, 0.3, 0.8), Color(0.3, 0.8, 1.6), Color(1.6, 1.3, 0.2),
			Color(0.3, 1.5, 0.6), Color(1.5, 1.5, 1.5)])
		c.color_initial_ramp = g
		c.emitting = false
		_confetti.append(c)


func _build_crowd() -> void:
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < CROWD and tries < 4000:
		tries += 1
		var p := Vector3(_rng.randf_range(-1.75, 1.75), 0.0, _rng.randf_range(0.86, 2.8))
		# denser at the front and in the middle
		var keep := (1.0 - (p.z - 0.86) / 1.94 * 0.55) * (1.0 - pow(absf(p.x) / 1.75, 3.0) * 0.6)
		if _rng.randf() > keep:
			continue
		var ok := true
		for s in spots:
			if Vector2(s.x - p.x, s.z - p.z).length() < 0.075:
				ok = false
				break
		if ok:
			spots.append(p)
	for p in spots:
		var r := _rng.randf()
		var mv := Person.HOP
		if r < 0.24:
			mv = Person.PUMP
		elif r < 0.5:
			mv = Person.SWAY
		elif r < 0.7:
			mv = Person.PHONE
		elif r < 0.78:
			mv = Person.SPIN
		var face := Vector3(_rng.randf_range(-0.4, 0.4), 0, 0)
		var who := _person(rig, p, face, mv, _pick(SHIRTS), _pick(PANTS), _pick(SKIN), _pick(HAIR),
			mv == Person.PHONE or _rng.randf() < 0.12)
		who.scale = Vector3.ONE * _rng.randf_range(0.9, 1.08)
		who.lag = _rng.randf_range(0.0, 0.07)
		who.base_yaw += _rng.randf_range(-0.2, 0.2)


# ================================================================ show

## Music on, starting with `first` (INTRO, or BUILD to go straight for the drop).
func start(first := Part.INTRO) -> void:
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = LATENCY
	_player.stream = gen
	_player.volume_db = -5.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_queued = first
	set_process(true)
	_fill()


## BUILD, DROP or OUTRO from the next bar on.
func queue_part(p: int) -> void:
	_queued = p


## Quieter music while the narrator talks.
func duck(on: bool) -> void:
	_duck_to = 0.55 if on else 1.0


## Night falls over `time` seconds: sky, sun and ambient go dark, glow goes up.
func nightfall(time: float) -> void:
	if _night and _night.is_valid():
		_night.kill()
	_night = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _env:
		_env.glow_enabled = true
		_night.tween_property(_env, "background_energy_multiplier", 0.07, time)
		_night.tween_property(_env, "ambient_light_energy", 0.14, time)
		_night.tween_property(_env, "glow_intensity", 1.0, time)
		_night.tween_property(_env, "glow_hdr_threshold", 0.85, time)
	if _sun:
		_night.tween_property(_sun, "light_energy", 0.05, time)
		_night.tween_property(_sun, "light_color", Color(0.55, 0.65, 1.0), time)


## Camera spots, as [position, look at, slow creep] in world space.
func crowd_shot() -> Array:
	return [rig.to_global(Vector3(0.95, 0.2, 3.05)), rig.to_global(Vector3(-0.1, 0.42, 0.0)),
		(rig.to_global(Vector3(0.55, 0.18, 2.2)) - rig.to_global(Vector3(0.95, 0.2, 3.05)))]


func wide_shot() -> Array:
	return [rig.to_global(Vector3(-3.2, 2.4, 7.2)), rig.to_global(Vector3(0.0, 0.9, -0.4)),
		(rig.to_global(Vector3(-4.2, 2.8, 8.4)) - rig.to_global(Vector3(-3.2, 2.4, 7.2)))]


func fade_out(time: float) -> void:
	_duck_to = 0.0
	if _player:
		var t := create_tween()
		t.tween_property(_player, "volume_db", -60.0, time)


## Take it all down again: music off, daylight back, props back, freed.
func close() -> void:
	set_process(false)
	if _night and _night.is_valid():
		_night.kill()
	if _player:
		_player.stop()
	if _env and not _day.is_empty():
		_env.background_energy_multiplier = _day.bg
		_env.ambient_light_energy = _day.ambient
		_env.glow_intensity = _day.glow
		_env.glow_hdr_threshold = _day.glow_thr
		_env.glow_enabled = _day.glow_on
	if _sun and _day.has("sun"):
		_sun.light_energy = _day.sun
		_sun.light_color = _day.sun_col
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	_fill()
	var played := maxf(0.0, _n / MIX_RATE - LATENCY)
	beat = played * BPM / 60.0
	while not _changes.is_empty() and float(_changes[0][0]) <= played:
		var p: int = _changes.pop_front()[1]
		_enter(p)
	var want: float = [0.0, 0.35, 0.72, 1.0, 0.25][part]
	energy = move_toward(energy, want, delta * 1.6)
	var drop := part == Part.DROP
	var bar := int(beat / 4.0)
	if bar != _last_bar:
		_last_bar = bar
		if drop and bar % 4 == 0 and beat - _drop_beat > 2.0:
			for c in _confetti:
				c.restart()
	_animate_lights(delta)
	for who in _people:
		who.dance(beat, energy, drop, _time)
	for i in _sparks.size():
		_sparks[i].emitting = drop and fposmod(beat, 8.0) < 3.5
	if drop:
		_firework_in -= delta
		if _firework_in <= 0.0:
			_firework_in = _rng.randf_range(0.45, 1.1)
			_firework()


func _enter(p: int) -> void:
	part = p
	match p:
		Part.DROP:
			_drop_beat = beat
			_lasers.visible = true
			for c in _confetti:
				c.restart()
			_firework_in = 0.0
		Part.OUTRO:
			_lasers.visible = false
	part_changed.emit(p)


func _animate_lights(delta: float) -> void:
	var e := energy
	var drop := part == Part.DROP
	var pulse := pow(1.0 - fposmod(beat, 1.0), 3.0)
	var bar := int(beat / 4.0)
	var ca: Color = PALETTE[bar % PALETTE.size()]
	var cb: Color = PALETTE[(bar + 2) % PALETTE.size()]

	for i in _spots.size():
		var sp := _spots[i]
		var tgt := Vector3(sin(_time * (0.45 + 0.5 * e) + i * 1.1) * (0.6 + 1.3 * e), 0.0,
			1.8 + cos(_time * 0.6 + i * 0.7) * 0.85)
		if drop and (int(beat / 4.0) + i) % 3 == 0:
			tgt = Vector3(tgt.x * 1.6, 6.0, -0.5 + tgt.z * 0.4)   # some shoot up into the sky
		_aims[i] = _aims[i].lerp(tgt, minf(delta * (2.0 + 4.0 * e), 1.0))
		var at := rig.to_global(_aims[i])
		if not sp.global_position.is_equal_approx(at):
			sp.look_at(at, Vector3.UP)
		var c := ca if i % 2 == 0 else cb
		sp.light_color = c
		var k := (0.35 + 0.65 * e) * (0.55 + 0.45 * pulse)
		if drop and fposmod(beat * 2.0 + i * 0.5, 2.0) < 0.15:
			k *= 1.6
		sp.light_energy = 55.0 * k
		_beams[i].set_shader_parameter("color", c)
		_beams[i].set_shader_parameter("strength", 0.16 * k)

	_follow.light_energy = lerpf(_follow.light_energy, 70.0 if part != Part.OFF else 0.0, delta * 1.5)
	var star_at := _star.global_position + Vector3.UP * 0.12 * TILE
	if not _follow.global_position.is_equal_approx(star_at):
		_follow.look_at(star_at, Vector3.UP)

	for i in _washes.size():
		_washes[i].light_color = cb if i == 0 else ca
		_washes[i].light_energy = (10.0 + 30.0 * pulse) * (0.3 + 0.7 * e)
	_crowd_light.light_color = ca.lerp(Color.WHITE, 0.4)
	_crowd_light.light_energy = 8.0 + 14.0 * pulse * e

	# strobe on the first bar of the drop and the last beat of every 8 bars
	var since := beat - _drop_beat
	var strobing := drop and (since < 4.0 or fposmod(beat, 32.0) > 31.0)
	_strobe.light_energy = 140.0 if strobing and fposmod(beat * 4.0, 1.0) < 0.3 else 0.0

	if _lasers.visible:
		_lasers.rotation = Vector3(sin(_time * 0.8) * 0.25, sin(_time * 0.55) * 0.5, sin(_time * 0.3) * 0.15)
		_laser_mat.set_shader_parameter("color", Color(0.25, 1.0, 0.45) if bar % 2 == 0 else Color(0.3, 0.6, 1.0))
		_laser_mat.set_shader_parameter("strength", 0.6 + 0.8 * pulse)

	_screen.set_shader_parameter("beat", beat)
	_screen.set_shader_parameter("mode", 2.0 if drop else (1.0 if part == Part.BUILD else 0.0))
	_screen.set_shader_parameter("level", 0.6 + 0.4 * e)
	_screen.set_shader_parameter("col_a", ca)
	_screen.set_shader_parameter("col_b", cb)
	_strip.emission = ca
	_strip.emission_energy_multiplier = 2.0 + 5.0 * pulse * e
	for w in _woofers:
		w.scale = Vector3.ONE * (1.0 + 0.14 * pulse * e)


func _firework() -> void:
	var at := Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(2.6, 4.2), _rng.randf_range(-3.6, -1.2))
	var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
	var p := _particles(rig, at, 90, 1.9, Color(col.r * 4.0, col.g * 4.0, col.b * 4.0), 0.05)
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.25
	p.gravity = Vector3(0, -0.35, 0)
	p.damping_min = 0.8
	p.damping_max = 1.0
	p.emitting = true
	var flash := OmniLight3D.new()
	flash.position = at * TILE
	flash.omni_range = 6.0 * TILE
	flash.light_color = col
	flash.light_energy = 90.0
	_light_root.add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(2.6).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		if is_instance_valid(flash):
			flash.queue_free())
	_boom_env = 1.0


# ================================================================ music

func _fill() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var target: float = [0.0, 0.75, 0.88, 1.0, 0.0][_gen_part]
	for i in frames:
		var step := int(_n / STEP_SAMPLES)
		if step != _step:
			_step = step
			_on_step(step)
			target = [0.0, 0.75, 0.88, 1.0, 0.0][_gen_part]
		_gain += (target - _gain) * (0.00004 if _gen_part == Part.OUTRO else 0.0004)
		_duck += (_duck_to - _duck) * 0.0003
		var s := _voice() * _gain * _duck
		s = s / (1.0 + absf(s))
		buf[i] = Vector2(s, s)
		_n += 1
	_playback.push_buffer(buf)


func _on_step(step: int) -> void:
	var in_bar := step % 16
	if in_bar == 0 and _queued >= 0:
		_gen_part = _queued
		_queued = -1
		_changes.append([_n / MIX_RATE, _gen_part])
		if _gen_part == Part.BUILD:
			_build_n = _n
		elif _gen_part == Part.DROP:
			_crash_env = 1.0
	var p := _gen_part
	if p == Part.OFF:
		return
	var chord: Array = CHORDS[(step / 16) % CHORDS.size()]
	var root: float = chord[0]
	var third := 3.0 if chord[1] else 4.0
	if in_bar == 0:
		_pad_f[0] = root * 2.0
		_pad_f[1] = root * 2.0 * pow(2.0, third / 12.0)
		_pad_f[2] = root * 2.0 * pow(2.0, 7.0 / 12.0)
	if p == Part.OUTRO:
		return
	var groove := p == Part.BUILD or p == Part.DROP
	if in_bar % 4 == 0 and not (p == Part.BUILD and _queued == Part.DROP and in_bar >= 8):
		_kick_env = 1.0
		_kick_pitch = 1.0
	if groove:
		if _queued == Part.DROP:
			# snare roll into the drop
			_clap_env = 1.0
			_clap_vol = 0.3 + 0.7 * in_bar / 15.0
		elif in_bar % 8 == 4:
			_clap_env = 1.0
			_clap_vol = 1.0
		if in_bar % 4 == 2:
			_hat_env = 1.0
			_hat_vol = 1.0
			_bass_env = 1.0
			_bass_f = root * 0.5
		elif p == Part.DROP and in_bar % 2 == 1:
			_hat_env = 1.0
			_hat_vol = 0.4
	if p == Part.DROP:
		var semis := [0.0, third, 7.0, 12.0]
		_arp_f = root * 4.0 * pow(2.0, float(semis[ARP[step % ARP.size()]]) / 12.0)
		_arp_env = 1.0


func _voice() -> float:
	var s := 0.0
	if _kick_env > 0.0005:
		_kick_ph += TAU * (44.0 + 125.0 * _kick_pitch) / MIX_RATE
		s += sin(_kick_ph) * _kick_env * 0.95
		_kick_env *= _k_kick
		_kick_pitch *= _k_kpitch
	var side := 1.0 - 0.7 * _kick_env   # everything else pumps with the kick
	var noise := randf() * 2.0 - 1.0
	if _clap_env > 0.0005:
		_clap_lp += (noise - _clap_lp) * 0.45
		s += _clap_lp * _clap_env * 0.42 * _clap_vol
		_clap_env *= _k_clap
	if _hat_env > 0.0005:
		s += (noise - _last_noise) * _hat_env * 0.1 * _hat_vol
		_hat_env *= _k_hat
	_last_noise = noise
	if _bass_env > 0.0005:
		_bass_ph = fmod(_bass_ph + _bass_f / MIX_RATE, 1.0)
		_bass_lp += (_bass_ph * 2.0 - 1.0 - _bass_lp) * 0.07
		s += _bass_lp * _bass_env * 0.6 * side
		_bass_env *= _k_bass
	if _gen_part != Part.OFF:
		var pad := 0.0
		for j in 3:
			_pad_ph[j] = fmod(_pad_ph[j] + _pad_f[j] / MIX_RATE, 1.0)
			pad += _pad_ph[j] * 2.0 - 1.0
		var cut := 0.13 if _gen_part == Part.DROP else (0.07 if _gen_part == Part.BUILD else 0.035)
		_pad_lp += (pad - _pad_lp) * cut
		s += _pad_lp * 0.085 * side
	if _arp_env > 0.0005:
		_arp_ph = fmod(_arp_ph + _arp_f / MIX_RATE, 1.0)
		s += (1.0 if _arp_ph < 0.5 else -1.0) * _arp_env * 0.06 * side
		_arp_env *= _k_arp
	if _gen_part == Part.BUILD:
		var k := clampf(float(_n - _build_n) / (MIX_RATE * 2.0), 0.0, 1.0)
		_riser_lp += (noise - _riser_lp) * (0.03 + 0.5 * k)
		s += (noise - _riser_lp) * k * k * 0.14
	if _crash_env > 0.0005:
		s += noise * _crash_env * 0.22
		_crash_env *= _k_crash
	if _boom_env > 0.0005:
		_boom_lp += (noise - _boom_lp) * 0.02
		s += _boom_lp * _boom_env * 1.4
		_boom_env *= _k_boom
	return s


# ================================================================ building blocks

func _person(parent: Node3D, pos: Vector3, look: Vector3, mv: int, shirt: Color, pants: Color,
		skin: Color, hair: Color, phone: bool) -> Person:
	var p := Person.new()
	p.move = mv
	p.position = pos
	p.home = pos
	var d := look - pos
	d.y = 0.0
	if d.length() < 0.001:
		d = Vector3.BACK
	p.base_yaw = atan2(-d.x, -d.z)
	p.rotation.y = p.base_yaw
	parent.add_child(p)
	p.body = Node3D.new()
	p.add_child(p.body)
	var sm := _mat(shirt)
	p.leg_l = _limb(p.body, Vector3(-0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), _mat(pants))
	p.leg_r = _limb(p.body, Vector3(0.012, 0.068, 0), Vector3(0.017, 0.068, 0.02), _mat(pants))
	for leg in [p.leg_l, p.leg_r]:
		_box(leg, Vector3(0.019, 0.011, 0.026), Vector3(0, -0.063, -0.003), _mat(Color(0.95, 0.95, 0.95)))
	_box(p.body, Vector3(0.05, 0.064, 0.028), Vector3(0, 0.1, 0), sm)
	p.head = Node3D.new()
	p.head.position = Vector3(0, 0.133, 0)
	p.body.add_child(p.head)
	_box(p.head, Vector3(0.033, 0.035, 0.031), Vector3(0, 0.019, 0), _mat(skin))
	_box(p.head, Vector3(0.036, 0.011, 0.034), Vector3(0, 0.039, 0.002), _mat(hair))
	_box(p.head, Vector3(0.035, 0.02, 0.008), Vector3(0, 0.026, 0.015), _mat(hair))
	p.arm_l = _limb(p.body, Vector3(-0.033, 0.127, 0), Vector3(0.013, 0.056, 0.014), sm)
	p.arm_r = _limb(p.body, Vector3(0.033, 0.127, 0), Vector3(0.013, 0.056, 0.014), sm)
	_box(p.arm_l, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.061, 0), _mat(skin))
	_box(p.arm_r, Vector3(0.012, 0.01, 0.012), Vector3(0, -0.061, 0), _mat(skin))
	if phone:
		# phone torch, held up toward the stage
		_box(p.arm_r, Vector3(0.009, 0.016, 0.003), Vector3(0, -0.07, -0.006), _mat(Color(0.9, 0.95, 1.0), 6.0))
	_people.append(p)
	return p


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
		cm.radial_segments = 16
		cm.rings = 1
		_meshes[key] = cm
	return _mesh(parent, _meshes[key], pos, m)


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	return _mesh(parent, sm, pos, m)


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, emit := 0.0, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [c, emit, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


## A spot light hanging at `local` (tile units, stage frame).
func _spot(local: Vector3, angle: float, reach: float) -> SpotLight3D:
	var sp := SpotLight3D.new()
	sp.position = local * TILE
	sp.spot_angle = angle
	sp.spot_range = reach
	sp.spot_attenuation = 0.8
	sp.light_energy = 0.0
	sp.shadow_enabled = false
	_light_root.add_child(sp)
	sp.look_at(rig.to_global(Vector3(local.x, 0.0, 1.8)), Vector3.UP)
	return sp


## Visible shaft of light along the spot's -Z.
func _beam(sp: SpotLight3D, length: float, strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(BEAM_SHADER)
	mat.set_shader_parameter("strength", strength)
	var cm := CylinderMesh.new()
	cm.top_radius = length * tan(deg_to_rad(sp.spot_angle)) * 0.55
	cm.bottom_radius = 0.5
	cm.height = length
	cm.radial_segments = 18
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = -PI * 0.5
	mi.position.z = -length * 0.5
	sp.add_child(mi)
	return mat


func _particles(parent: Node3D, pos: Vector3, amount: int, life: float, col: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.local_coords = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size * 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	p.color = col
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


var _shaders := {}

func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


func _pick(list: Array) -> Color:
	return list[_rng.randi() % list.size()]
