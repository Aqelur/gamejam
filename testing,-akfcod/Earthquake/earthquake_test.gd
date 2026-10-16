extends Node3D
## Test bench for the earthquake VFX.
##
## earthquake_test.tscn       - a small sandbox block of buildings (safe to wreck)
## earthquake_city_test.tscn  - loads City/city.tscn at runtime and runs the
##                              effects on the real city. The city scene file is
##                              never modified; Reset / reload puts it all back.
##
## Keys: 1 undamaged, 2 damaged, 3 razed, 4 auto, C city-wide quake,
##       Tab / Shift+Tab next / previous building, F focus camera, O overview, R reset,
##       F5 reload scene. Right mouse + WASD/QE to fly (Shift = fast).

@export var use_real_city := false
@export var city_scene_path := "res://City/city.tscn"

const WEATHERING := preload("res://City/weathering.gd")
const FLY_CAMERA := preload("res://City/fly_camera.gd")
const GLB := "res://Models/GLB format/%s.glb"

var city_quake: CityEarthquake
var buildings: Array[Node3D] = []
var target_index := 0
var _quakes := {}           # building -> BuildingQuake
var _camera: Camera3D
var _marker: Label3D
var _intensity := 1.0
var _people := 10
var _magnitude := 7.0
var _epi_at_target := true

var _option: OptionButton
var _info: Label
var _status: Label
var _int_label: Label
var _ppl_label: Label
var _mag_label: Label


func _ready() -> void:
	var root: Node3D
	if use_real_city:
		var scene: PackedScene = load(city_scene_path)
		var city := scene.instantiate()
		add_child(city)
		root = city.get_node_or_null("Districts")
		_camera = get_viewport().get_camera_3d()
		_magnitude = 7.5
	else:
		_build_sandbox()
		root = get_node("Districts")
	city_quake = CityEarthquake.new()
	city_quake.name = "CityEarthquake"
	city_quake.buildings_root = root
	if use_real_city:
		city_quake.people_scale = 1.6
	add_child(city_quake)
	buildings = city_quake.find_buildings()
	buildings.sort_custom(func(a: Node3D, b: Node3D) -> bool: return str(a.get_path()) < str(b.get_path()))
	_marker = Label3D.new()
	_marker.text = "▼"
	_marker.font_size = 96
	_marker.outline_size = 18
	_marker.modulate = Color(1.0, 0.85, 0.2)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.pixel_size = 0.004
	add_child(_marker)
	_build_ui()
	if use_real_city:
		var zone := get_node_or_null("City/HazardZones/EarthquakeZone")
		if zone is Node3D:
			for i in buildings.size():
				if buildings[i].get_parent().get_parent().name == &"OldQuarter":
					target_index = i
					break
	_select(target_index)
	if use_real_city:
		overview_camera()


func _process(_delta: float) -> void:
	var b := _target()
	if b != null and _marker != null:
		var bb := _bounds(b)
		var bob := sin(Time.get_ticks_msec() * 0.005) * 0.08
		_marker.global_position = Vector3(bb.get_center().x, bb.end.y + 0.45 + bob, bb.get_center().z)
		_marker.visible = b.is_visible_in_tree()


# ------------------------------------------------------------------ actions

func quake_target(outcome: int) -> void:
	var b := _target()
	if b == null:
		return
	var bq: BuildingQuake = _quakes.get(b)
	if bq == null or not is_instance_valid(bq):
		bq = BuildingQuake.new()
		bq.name = "BuildingQuake_%s" % b.name
		bq.building = b
		add_child(bq)
		_quakes[b] = bq
		bq.finished.connect(func(o: int) -> void: _set_status("%s: %s - finished" % [b.name, _outcome_name(o)]))
	if use_real_city:
		bq.people_scale = 1.3
	bq.intensity = _intensity
	bq.people_count = _people
	bq.trigger(outcome)
	_set_status("%s: %s" % [b.name, _outcome_name(bq.resolved_outcome)])


func city_wide() -> void:
	reset_all()
	var b := _target()
	city_quake.magnitude = _magnitude
	city_quake.people_per_building = maxi(2, _people / 2)
	if _epi_at_target and b != null:
		city_quake.epicenter_node = null
		city_quake.epicenter = b.global_position
	elif use_real_city and get_node_or_null("City/HazardZones/EarthquakeZone") != null:
		city_quake.epicenter_node = get_node("City/HazardZones/EarthquakeZone")
	else:
		city_quake.epicenter_node = null
		city_quake.epicenter = Vector3.ZERO
	city_quake.start_quake(_magnitude)
	_set_status("City-wide quake  M%.1f" % _magnitude)


func reset_all() -> void:
	if city_quake != null:
		city_quake.reset()
	for k in _quakes:
		var bq: BuildingQuake = _quakes[k]
		if is_instance_valid(bq):
			bq.reset()
	_set_status("Reset")


func focus_camera() -> void:
	var b := _target()
	if b == null or _camera == null:
		return
	var bb := _bounds(b)
	var c := bb.get_center()
	var dist := maxf(bb.size.y, 1.4) * 1.6 + 2.6
	var dir := Vector3(0.12, 0.42, 1.0).normalized()
	if use_real_city:
		dir = Vector3(0.35, 0.75, 1.0).normalized()
		dist *= 1.3
	_camera.global_position = c + dir * dist
	_camera.look_at(c, Vector3.UP)
	# nudge the building right of centre so the panel doesn't cover it
	_camera.look_at(c - _camera.global_transform.basis.x * dist * 0.16, Vector3.UP)
	_camera.set("_yaw", _camera.rotation_degrees.y)
	_camera.set("_pitch", _camera.rotation_degrees.x)


## Frames the whole city / sandbox.
func overview_camera() -> void:
	if _camera == null or buildings.is_empty():
		return
	var all := _bounds(buildings[0])
	for b in buildings:
		all = all.merge(_bounds(b))
	var c := all.get_center()
	var ext := maxf(all.size.x, all.size.z)
	_camera.global_position = c + Vector3(-0.3, 0.75, 1.0).normalized() * ext * 1.05
	_camera.look_at(c, Vector3.UP)
	_camera.look_at(c - _camera.global_transform.basis.x * ext * 0.15, Vector3.UP)
	_camera.set("_yaw", _camera.rotation_degrees.y)
	_camera.set("_pitch", _camera.rotation_degrees.x)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1: quake_target(BuildingQuake.Outcome.UNDAMAGED)
		KEY_2: quake_target(BuildingQuake.Outcome.DAMAGED)
		KEY_3: quake_target(BuildingQuake.Outcome.RAZED)
		KEY_4: quake_target(BuildingQuake.Outcome.AUTO)
		KEY_C: city_wide()
		KEY_R: reset_all()
		KEY_F: focus_camera()
		KEY_O: overview_camera()
		KEY_F5: get_tree().reload_current_scene()
		KEY_TAB: _select(target_index + (-1 if event.shift_pressed else 1))


# ------------------------------------------------------------------ selection

func _target() -> Node3D:
	if buildings.is_empty():
		return null
	return buildings[clampi(target_index, 0, buildings.size() - 1)]


func _select(i: int) -> void:
	if buildings.is_empty():
		return
	target_index = posmod(i, buildings.size())
	if _option != null and _option.selected != target_index:
		_option.select(target_index)
	var b := _target()
	var integ := float(b.get_meta("structural_integrity", 0.85))
	var forced := str(b.get_meta("quake_outcome", ""))
	_info.text = "structural_integrity: %.2f%s" % [integ, ("   quake_outcome: " + forced) if forced != "" else ""]


# ------------------------------------------------------------------ sandbox

func _build_sandbox() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.66)
	sky_mat.ground_bottom_color = Color(0.4, 0.42, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	# ground with collision so debris and chunks land on it
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(200, 0.5, 200)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.42, 0.44, 0.4)
	gmat.roughness = 1.0
	ground.material_override = gmat
	ground.position = Vector3(0, -0.25, 0)
	add_child(ground)
	var gb := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = gm.size
	gs.shape = gbox
	gb.add_child(gs)
	ground.add_child(gb)
	# a paved strip in front of the test row
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(14, 0.02, 2.2)
	strip.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.3, 0.3, 0.32)
	strip.material_override = smat
	strip.position = Vector3(0, 0.0, 2.1)
	add_child(strip)

	var districts := Node3D.new()
	districts.name = "Districts"
	add_child(districts)
	var sandbox := Node3D.new()
	sandbox.name = "Sandbox"
	districts.add_child(sandbox)

	var b_root := Node3D.new()
	b_root.name = "Buildings"
	b_root.set_script(WEATHERING)
	b_root.set("grime", 0.15)
	b_root.set("cracks", 0.05)
	# test row: [model, x, integrity]
	var row := [
		["building-skyscraper-a", -4.4, 0.95],
		["building-m", -2.2, 0.75],
		["building-h", 0.0, 0.5],
		["building-skyscraper-d", 2.2, 0.62],
		["building-c", 4.4, 0.35],
	]
	for r in row:
		_add_building(b_root, r[0], Vector3(r[1], 0.04, 0.0), r[2], 0.0)
	# a small block behind for the city-wide test
	var block := ["building-a", "building-e", "building-skyscraper-b", "building-g", "building-k",
		"building-skyscraper-c", "building-b", "building-j", "building-n", "building-d", "building-f", "building-l"]
	var i := 0
	for z in [-3.2, -5.6, -8.0]:
		for x in [-3.3, -1.1, 1.1, 3.3]:
			_add_building(b_root, block[i % block.size()], Vector3(x, 0.04, z), randf_range(0.35, 0.95), PI if randf() < 0.5 else 0.0)
			i += 1
	sandbox.add_child(b_root)

	var props := Node3D.new()
	props.name = "Props"
	sandbox.add_child(props)
	for x in [-5.5, -3.3, -1.1, 1.1, 3.3, 5.5]:
		_add_prop(props, "res://Models/Custom/streetlight.glb", Vector3(x, 0.04, 1.3))
	for x in [-6.5, 6.5, -6.5, 6.5]:
		_add_prop(props, "res://Models/Custom/tree_round.glb", Vector3(x, 0.04, randf_range(-6, 0)))
	_add_prop(props, "res://Models/Custom/car.glb", Vector3(-1.4, 0.04, 2.3))
	_add_prop(props, "res://Models/Custom/bench.glb", Vector3(1.6, 0.04, 1.2))

	_camera = Camera3D.new()
	_camera.set_script(FLY_CAMERA)
	_camera.fov = 55.0
	_camera.far = 300.0
	add_child(_camera)
	_camera.current = true
	_camera.global_position = Vector3(0.6, 3.2, 8.5)
	_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	_camera.set("_yaw", _camera.rotation_degrees.y)
	_camera.set("_pitch", _camera.rotation_degrees.x)


func _add_building(parent: Node3D, model: String, pos: Vector3, integrity: float, yaw: float) -> void:
	var path := GLB % model
	if not ResourceLoader.exists(path):
		return
	var b: Node3D = (load(path) as PackedScene).instantiate()
	b.name = model
	b.position = pos
	b.rotation.y = yaw
	b.set_meta("structural_integrity", snappedf(integrity, 0.01))
	parent.add_child(b)
	# box collider like the city buildings have
	var bb := _bounds_local(b)
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bb.size
	cs.shape = box
	cs.position = bb.get_center()
	body.add_child(cs)
	b.add_child(body)


func _add_prop(parent: Node3D, path: String, pos: Vector3) -> void:
	if not ResourceLoader.exists(path):
		return
	var p: Node3D = (load(path) as PackedScene).instantiate()
	p.position = pos
	p.rotation.y = randf() * TAU
	parent.add_child(p)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.82)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(330, 0)
	panel.add_child(v)

	var title := Label.new()
	title.text = "EARTHQUAKE VFX TEST" + ("  -  REAL CITY" if use_real_city else "  -  SANDBOX")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	v.add_child(title)

	v.add_child(_small("Target building  (Tab / Shift+Tab)"))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_button("<", func() -> void: _select(target_index - 1), 30))
	_option = OptionButton.new()
	_option.focus_mode = Control.FOCUS_NONE
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.clip_text = true
	for b in buildings:
		var label := b.name as String
		var p := b.get_parent()
		if p != null and p.get_parent() != null and p.get_parent().name != &"Sandbox":
			label = "%s / %s" % [p.get_parent().name, b.name]
		_option.add_item(label)
	_option.item_selected.connect(func(i: int) -> void: _select(i))
	row.add_child(_option)
	row.add_child(_button(">", func() -> void: _select(target_index + 1), 30))
	_info = _small("")
	v.add_child(_info)

	v.add_child(_small("Single building quake"))
	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	g.add_child(_button("1  Undamaged", func() -> void: quake_target(BuildingQuake.Outcome.UNDAMAGED)))
	g.add_child(_button("2  Damaged", func() -> void: quake_target(BuildingQuake.Outcome.DAMAGED)))
	g.add_child(_button("3  Razed", func() -> void: quake_target(BuildingQuake.Outcome.RAZED)))
	g.add_child(_button("4  Auto (integrity)", func() -> void: quake_target(BuildingQuake.Outcome.AUTO)))
	_int_label = _small("")
	v.add_child(_int_label)
	v.add_child(_slider(0.3, 1.8, 0.05, _intensity, func(x: float) -> void:
		_intensity = x
		_int_label.text = "Intensity: %.2f" % x))
	_ppl_label = _small("")
	v.add_child(_ppl_label)
	v.add_child(_slider(0, 30, 1, _people, func(x: float) -> void:
		_people = int(x)
		_ppl_label.text = "People: %d" % _people))

	v.add_child(HSeparator.new())
	v.add_child(_small("City-wide quake"))
	_mag_label = _small("")
	v.add_child(_mag_label)
	v.add_child(_slider(4.0, 9.5, 0.1, _magnitude, func(x: float) -> void:
		_magnitude = x
		_mag_label.text = "Magnitude: %.1f" % x))
	var epi := CheckBox.new()
	epi.text = "Epicenter at target building"
	epi.button_pressed = _epi_at_target
	epi.focus_mode = Control.FOCUS_NONE
	epi.toggled.connect(func(on: bool) -> void: _epi_at_target = on)
	v.add_child(epi)
	v.add_child(_button("C  Start city-wide quake", city_wide))

	v.add_child(HSeparator.new())
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	r2.add_child(_button("R  Reset all", reset_all))
	r2.add_child(_button("F  Focus target", focus_camera))
	r2.add_child(_button("O  Overview", overview_camera))
	var shake := CheckBox.new()
	shake.text = "Camera shake"
	shake.button_pressed = true
	shake.focus_mode = Control.FOCUS_NONE
	shake.toggled.connect(func(on: bool) -> void: QuakeCameraShake.enabled = on)
	v.add_child(shake)
	_status = _small("")
	_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	v.add_child(_status)
	v.add_child(_small("Right mouse + WASD / QE to fly, Shift = fast, F5 reload"))


func _button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if min_w == 0 else Control.SIZE_SHRINK_BEGIN
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	b.pressed.connect(cb)
	return b


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	return l


func _slider(lo: float, hi: float, step: float, value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	s.value = value
	cb.call(value)
	return s


func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t


func _outcome_name(o: int) -> String:
	return ["Auto", "Undamaged", "Damaged", "Razed"][clampi(o, 0, 3)]


func _bounds(n: Node3D) -> AABB:
	return n.global_transform * _bounds_local(n)


func _bounds_local(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse() if n.is_inside_tree() else Transform3D()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.mesh == null:
			continue
		var xf: Transform3D = (inv * mi.global_transform) if n.is_inside_tree() else _rel(n, mi)
		var bb: AABB = xf * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
