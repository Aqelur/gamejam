class_name QuakeFX
extends RefCounted
## Particle building blocks shared by BuildingQuake and CityEarthquake:
## dust clouds, glass shards, glints, concrete debris.
## Everything is created in code so there are no extra resources to manage.
## One-shot emitters free themselves when finished.

const DUST_SHADER := preload("res://Earthquake/quake_dust.gdshader")

const DUST_COLOR := Color(0.86, 0.81, 0.72)
const DARK_DUST_COLOR := Color(0.42, 0.4, 0.38)

static var _dust_mesh: QuadMesh
static var _glass_mesh: BoxMesh
static var _debris_mesh: BoxMesh
static var _spark_mesh: QuadMesh


# ------------------------------------------------------------------ meshes

static func dust_mesh() -> Mesh:
	if _dust_mesh == null:
		var m := ShaderMaterial.new()
		m.shader = DUST_SHADER
		_dust_mesh = QuadMesh.new()
		_dust_mesh.size = Vector2.ONE
		_dust_mesh.material = m
	return _dust_mesh


static func glass_mesh() -> Mesh:
	if _glass_mesh == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.82, 0.94, 1.0, 0.8)
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.85
		m.roughness = 0.04
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = Color(0.55, 0.78, 1.0)
		m.emission_energy_multiplier = 0.7
		_glass_mesh = BoxMesh.new()
		_glass_mesh.size = Vector3(0.035, 0.05, 0.004)
		_glass_mesh.material = m
	return _glass_mesh


static func debris_mesh() -> Mesh:
	if _debris_mesh == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		_debris_mesh = BoxMesh.new()
		_debris_mesh.size = Vector3(0.05, 0.035, 0.045)
		_debris_mesh.material = m
	return _debris_mesh


static func spark_mesh() -> Mesh:
	if _spark_mesh == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.6))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = t
		m.no_depth_test = false
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.08, 0.08)
		_spark_mesh.material = m
	return _spark_mesh


# ------------------------------------------------------------------ helpers

static func curve(points: Array, max_value := 2.0) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_value
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func fade_ramp(peak := 0.85) -> GradientTexture1D:
	return ramp(
		[Color(1, 1, 1, 0), Color(1, 1, 1, peak), Color(1, 1, 1, peak * 0.7), Color(1, 1, 1, 0)],
		[0.0, 0.1, 0.55, 1.0])


## Creates a GPUParticles3D at `xform` (global). One-shot emitters free themselves.
static func emitter(parent: Node, xform: Transform3D, mesh: Mesh, amount: int, lifetime: float,
		pm: ParticleProcessMaterial, one_shot := true, explosiveness := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = explosiveness
	p.draw_pass_1 = mesh
	p.process_material = pm
	p.local_coords = false
	p.collision_base_size = 0.02
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 50, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_transform = xform
	p.emitting = true
	if one_shot:
		p.finished.connect(p.queue_free)
	return p


# ------------------------------------------------------------------ effects

## Puffy dust cloud. ring=true emits from a ring on the ground and pushes outward.
static func dust(parent: Node, pos: Vector3, radius: float, amount: int, size: float, life: float,
		up_speed: float, out_speed: float, color := DUST_COLOR, ring := false, one_shot := true,
		explosiveness := 0.85) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	if ring:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = maxf(radius, 0.01)
		pm.emission_ring_inner_radius = radius * 0.6
		pm.emission_ring_height = 0.05
	else:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = maxf(radius, 0.01)
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = up_speed * 0.4
	pm.initial_velocity_max = up_speed
	pm.radial_velocity_min = out_speed * 0.5
	pm.radial_velocity_max = out_speed
	pm.gravity = Vector3(0, -0.12, 0)
	var damp := maxf(up_speed, out_speed) * 0.9 + 0.2
	pm.damping_min = damp * 0.7
	pm.damping_max = damp
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.2
	pm.scale_curve = curve([Vector2(0, 0.35), Vector2(0.3, 0.85), Vector2(1, 1.4)])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.color = color
	pm.color_initial_ramp = ramp([color.darkened(0.12), color.lightened(0.08)], [0.0, 1.0])
	pm.color_ramp = fade_ramp(color.a * 0.85)
	pm.lifetime_randomness = 0.35
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.08
	return emitter(parent, Transform3D(Basis(), pos), dust_mesh(), amount, life, pm, one_shot, explosiveness)


## Glass shards bursting out of a facade. `xform` basis: +Z = outward normal,
## extents = half size of the facade area (x = width, y = height).
static func glass(parent: Node, xform: Transform3D, extents: Vector2, amount: int, speed := 1.6,
		explosiveness := 0.92) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(extents.x, extents.y, 0.01)
	pm.direction = Vector3(0, 0.35, 1)
	pm.spread = 38.0
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -5.5, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.4
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.scale_curve = curve([Vector2(0, 1), Vector2(0.8, 1), Vector2(1, 0)], 1.0)
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -720.0
	pm.angular_velocity_max = 720.0
	pm.color_initial_ramp = ramp([Color(0.75, 0.9, 1.0), Color(0.95, 1.0, 1.0), Color(0.55, 0.75, 0.95)], [0.0, 0.5, 1.0])
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.25
	pm.collision_friction = 0.6
	pm.lifetime_randomness = 0.3
	var p := emitter(parent, xform, glass_mesh(), amount, 3.5, pm, true, explosiveness)
	# glints that catch the light as the glass breaks
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(extents.x, extents.y, 0.02)
	sp.direction = Vector3(0, 0.2, 1)
	sp.spread = 50.0
	sp.initial_velocity_min = speed * 0.2
	sp.initial_velocity_max = speed * 0.8
	sp.gravity = Vector3(0, -3.0, 0)
	sp.scale_min = 0.6
	sp.scale_max = 1.6
	sp.color = Color(0.8, 0.95, 1.0)
	sp.color_ramp = ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0])
	emitter(parent, xform, spark_mesh(), maxi(4, amount / 3), 0.5, sp, true, 1.0)
	return p


## Chunks of concrete/facade thrown from `pos`.
static func debris(parent: Node, pos: Vector3, dir: Vector3, amount: int, speed: float, spread_deg: float,
		colors: Array, radius := 0.1, life := 5.0) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radius, 0.01)
	pm.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	pm.spread = spread_deg
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.6
	pm.scale_curve = curve([Vector2(0, 1), Vector2(0.85, 1), Vector2(1, 0)], 1.0)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.particle_flag_rotate_y = true
	var offs: Array = []
	for i in colors.size():
		offs.append(float(i) / maxf(1.0, colors.size() - 1.0))
	pm.color_initial_ramp = ramp(colors, offs)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.2
	pm.collision_friction = 0.8
	pm.lifetime_randomness = 0.25
	return emitter(parent, Transform3D(Basis(), pos), debris_mesh(), amount, life, pm, true, 0.9)


## Invisible floor that GPU particles (glass, debris) land and bounce on.
static func particle_floor(parent: Node, center: Vector3, ground_y: float, size: float) -> GPUParticlesCollisionBox3D:
	var c := GPUParticlesCollisionBox3D.new()
	c.size = Vector3(size, 1.0, size)
	parent.add_child(c)
	c.global_position = Vector3(center.x, ground_y - 0.5, center.z)
	return c


## Basis whose +Z axis points along `normal`.
static func facing(normal: Vector3) -> Basis:
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(-n, up)
