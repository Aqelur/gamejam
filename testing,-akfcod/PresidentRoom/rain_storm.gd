extends Node3D
## Rain and thunder over the city for the earthquake ending: a dark, wet,
## solemn afternoon. Made by day_cycle.gd (_play_ending) and added to the city.
##
##   setup(city, cam)     darkens the city at once (do it while the screen is
##                        black), starts the rain around `cam` and the sound
##   set_indoors(on)      inside a room: no drops, rain muffled (room_quake.gd)
##
## Cheap to run on purpose:
##   * the drops are ONE GPUParticles3D of thin unshaded quads (AMOUNT of them)
##     that follows the camera, so there's no rain in the rest of the city
##   * the sun's shadows are switched off (overcast sky; this also saves time)
##   * lightning only changes a few light and sky numbers, the sky is never
##     rebuilt
##   * the sound is the project's own "Thunder, Very Close, Rain, 01.wav": its
##     rain-only tail loops as the rain bed, and the whole clip is replayed now
##     and then as a thunderclap, with the flash timed to the crack in it

const SFX := "res://Thunder, Very Close, Rain, 01.wav"

## How many drops at once. Lower it for weak PCs (500 still reads as rain).
const AMOUNT := 1100
## The box of rain around the camera (world units, the city is ~10 per metre).
const HALF_W := 70.0
const DROP_SPEED := 170.0
const FALL := 100.0                       # how far a drop falls before it goes
const DROP_SIZE := Vector2(0.22, 6.5)
const DROP_COLOR := Color(0.72, 0.78, 0.88, 0.2)

## In the sound file (seconds): rain only, used as the looping bed.
const BED_FROM := 8.3
const BED_TO := 12.3
## In the sound file: where a thunder replay starts, and its two cracks.
const THUNDER_FROM := 0.85
const CRACKS := [1.08, 1.47]
## Seconds between thunderclaps (the clip rings for ~11 s).
const THUNDER_GAP := Vector2(13.0, 24.0)
const FIRST_THUNDER := 5.5

const BED_DB := 7.0
const THUNDER_DB := -1.0
const INDOOR_DB := -11.0                  # how much quieter it is inside

## The overcast look.
const SKY_TOP := Color(0.09, 0.1, 0.12)
const SKY_HORIZON := Color(0.2, 0.22, 0.25)
const GROUND_BOTTOM := Color(0.06, 0.065, 0.075)
const GROUND_HORIZON := Color(0.2, 0.22, 0.25)
const SUN_ENERGY := 0.32
const SUN_COLOR := Color(0.68, 0.75, 0.88)
const FOG_COLOR := Color(0.17, 0.19, 0.22)
const FOG_DENSITY := 0.0011

var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _drops: GPUParticles3D
var _bed: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _indoors := false
var _vol := 0.0                           # 0..1 fade in of the sound
var _next_thunder := FIRST_THUNDER
var _flashes: Array[float] = []           # seconds until each pending flicker
var _flash := 0.0
var _base := {}


func setup(city: Node3D, cam: Camera3D) -> void:
	_cam = cam
	_darken(city)
	_build_drops()
	_build_sound()
	_follow()
	_drops.restart()


func set_indoors(on: bool) -> void:
	_indoors = on
	if _drops:
		_drops.visible = not on
		_drops.emitting = not on
		if not on:
			_follow()
			_drops.restart()


func _process(delta: float) -> void:
	_follow()

	# sound fades in, quieter indoors
	_vol = minf(1.0, _vol + delta / 2.5)
	var muffle := INDOOR_DB if _indoors else 0.0
	var fade := linear_to_db(maxf(_vol, 0.0001))
	if _bed:
		_bed.volume_db = BED_DB + muffle + fade
	if _thunder:
		_thunder.volume_db = THUNDER_DB + muffle * 0.6 + fade

	# thunder
	_next_thunder -= delta
	if _next_thunder <= 0.0:
		_strike()
		_next_thunder = randf_range(THUNDER_GAP.x, THUNDER_GAP.y)

	# lightning: pending flickers, then a quick decay
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i] -= delta
		if _flashes[i] <= 0.0:
			_flash = maxf(_flash, randf_range(0.75, 1.0))
			_flashes.remove_at(i)
	_flash = maxf(0.0, _flash - delta * 5.0)
	_apply_flash()


# ================================================================ look

func _darken(city: Node3D) -> void:
	var we := city.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		# our own copy, so "play again" gets the sunny city back
		_env = we.environment.duplicate() as Environment
		if _env.sky:
			_env.sky = _env.sky.duplicate() as Sky
			var psm := _env.sky.sky_material as ProceduralSkyMaterial
			if psm:
				psm = psm.duplicate() as ProceduralSkyMaterial
				psm.sky_top_color = SKY_TOP
				psm.sky_horizon_color = SKY_HORIZON
				psm.ground_bottom_color = GROUND_BOTTOM
				psm.ground_horizon_color = GROUND_HORIZON
				_env.sky.sky_material = psm
		_env.fog_enabled = true
		_env.fog_light_color = FOG_COLOR
		_env.fog_light_energy = 1.0
		_env.fog_density = FOG_DENSITY
		_env.fog_sky_affect = 0.6
		_env.adjustment_enabled = true
		_env.adjustment_saturation = 0.55
		_env.adjustment_brightness = 0.88
		_env.adjustment_contrast = 1.06
		_env.ambient_light_energy = 0.7
		we.environment = _env
		_base["bg"] = _env.background_energy_multiplier
		_base["ambient"] = _env.ambient_light_energy
	_sun = city.get_node_or_null("Sun") as DirectionalLight3D
	if _sun:
		_sun.light_energy = SUN_ENERGY
		_sun.light_color = SUN_COLOR
		_sun.shadow_enabled = false                       # overcast: no hard shadows
		_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # no sun disc in the sky
		_base["sun"] = SUN_ENERGY


func _apply_flash() -> void:
	var f := _flash * _flash
	if _sun:
		_sun.light_energy = _base.get("sun", SUN_ENERGY) + 3.2 * f
		_sun.light_color = SUN_COLOR.lerp(Color(0.86, 0.9, 1.0), clampf(f * 2.0, 0.0, 1.0))
	if _env:
		_env.background_energy_multiplier = _base.get("bg", 1.0) * (1.0 + 4.0 * f)
		_env.ambient_light_energy = _base.get("ambient", 0.7) * (1.0 + 3.0 * f)


# ================================================================ drops

func _build_drops() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(HALF_W, 1.0, HALF_W)
	pm.direction = Vector3(0.1, -1.0, 0.04)
	pm.spread = 2.0
	pm.initial_velocity_min = DROP_SPEED * 0.9
	pm.initial_velocity_max = DROP_SPEED * 1.1
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.2

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = DROP_COLOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	# drops right in front of the lens fade out instead of blocking the view
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 2.0
	m.distance_fade_max_distance = 22.0

	var q := QuadMesh.new()
	q.size = DROP_SIZE
	q.material = m

	_drops = GPUParticles3D.new()
	_drops.name = "Drops"
	_drops.amount = AMOUNT
	_drops.lifetime = FALL / DROP_SPEED
	_drops.preprocess = _drops.lifetime
	_drops.local_coords = false
	_drops.process_material = pm
	_drops.draw_pass_1 = q
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.visibility_aabb = AABB(Vector3(-HALF_W - 20.0, -FALL - 20.0, -HALF_W - 20.0),
		Vector3(2.0 * HALF_W + 40.0, FALL + 30.0, 2.0 * HALF_W + 40.0))
	add_child(_drops)


## The rain box sits just above the camera, a little ahead of where it looks.
func _follow() -> void:
	if _drops == null or not is_instance_valid(_cam):
		return
	var ahead := -_cam.global_basis.z
	ahead.y = 0.0
	if ahead.length_squared() > 0.0001:
		ahead = ahead.normalized() * HALF_W * 0.4
	_drops.global_position = _cam.global_position + ahead + Vector3(0.0, FALL * 0.45, 0.0)


# ================================================================ sound

func _build_sound() -> void:
	if not ResourceLoader.exists(SFX):
		push_warning("RainStorm: missing %s" % SFX)
		return
	var stream := load(SFX) as AudioStream

	_bed = AudioStreamPlayer.new()
	_bed.name = "RainBed"
	var wav := stream as AudioStreamWAV
	if wav:
		var bed := wav.duplicate() as AudioStreamWAV
		var rate := float(bed.mix_rate)
		bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bed.loop_begin = int(BED_FROM * rate)
		bed.loop_end = int(BED_TO * rate)
		_bed.stream = bed
	else:
		_bed.stream = stream
		_bed.finished.connect(func() -> void: _bed.play(BED_FROM))
	_bed.volume_db = -80.0
	add_child(_bed)
	_bed.play(BED_FROM)

	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	_thunder.stream = stream
	_thunder.volume_db = -80.0
	add_child(_thunder)


## A thunderclap: the clip from just before its crack, a little higher or
## lower each time so it doesn't sound the same twice, with the lightning
## flickers landing a moment before each crack.
func _strike() -> void:
	var pitch := randf_range(0.9, 1.06)
	if _thunder:
		_thunder.pitch_scale = pitch
		_thunder.play(THUNDER_FROM)
	_flashes.clear()
	for c: float in CRACKS:
		_flashes.append(maxf(0.0, (c - THUNDER_FROM) / pitch - 0.12))
	_flashes.append((CRACKS[0] - THUNDER_FROM) / pitch + 0.1)   # after-flicker
