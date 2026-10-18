extends Node3D
## THE WALKOUT: what happens when Money hits 0. Played by day_cycle.gd
## (_play_walkout) instead of the next morning, and instead of the earthquake
## if it was the last day. The game ends here.
##
## Nobody was paid for the week. One week later:
##   1. Every emergency service that was built (hospital, fire station, police
##      station, in that order) shuts: its lights flicker and go out, the
##      light bars on the vehicles out front go dark, and a red CLOSED sign
##      swings down over its door. Nobody is shown. Services never built are
##      simply skipped (and with none built, so is this whole step).
##   2. One car, the president's own state car, slips out of the palace on
##      its own (the motorcade stays parked), lifts the boom at the side gate,
##      turns the other way onto the gray road and drives straight along it.
##      No sirens, no sound.
##   3. A card on black: TEXT. The closing lines follow in menu/walkout_outro.tscn.
##
## day_cycle.gd drives it:
##   setup(city, font_bold, font_black)
##   settle_buildings()          wait for a service still going up to finish
##   closed_places()             the built services, in order (Dictionaries)
##   place_shot(p), kicker(p)    camera [eye, look, creep] / kicker text
##   close(p), close_now(p)      lights out + CLOSED sign (animated / at once)
##   prepare_car(), car_shot(), car_kicker()
##   drive(cam)                  the car sets off; the camera follows it
##   is_away()                   it is out of town
##   stop_car()
##   show_card(ui)

const TEXT := "Nobody had been paid for the week. One week later the firefighters, the paramedics and the search-and-rescue volunteers left their badges on your desk and walked out together. With the big one on its way, there was no one left who knew how to pull people from the rubble. An angry crowd was storming city hall, and you left through the back door."

const BUILDINGS := "Districts/CivicCenter/Buildings"
const PALACE := "Districts/CivicCenter/Buildings/PresidentPalace"
const ROADS := "Roads"
const TILE := 26.926893

## The services that shut, in order. `sign` is where the CLOSED sign hangs
## (building-local: top edge of the sign, on the front of the door or the
## canopy over it), `w` its width.
const PLACES := [
	{"id": "hospital", "node": "Hospital", "title": "HOSPITAL", "time": "21:58",
		"sign": Vector3(0.0, 0.53, 1.512), "w": 0.42},
	{"id": "fire", "node": "FireStation", "title": "FIRE STATION", "time": "22:01",
		"sign": Vector3(0.75, 0.56, 0.245), "w": 0.44},
	{"id": "police", "node": "PoliceStation", "title": "POLICE STATION", "time": "22:03",
		"sign": Vector3(0.0, 0.9, 0.70), "w": 0.40},
]

## The state car's way out (palace-local x, z): along the portico apron past
## the motorcade, out of the right-hand drive gate once the boom is up, then
## one right turn onto the gray road (z = 4 is its centre line). The straight
## run continues up that road.
const GROUNDS_PATH := [Vector2(2.05, 1.80), Vector2(2.40, 2.20), Vector2(2.30, 2.75),
	Vector2(2.30, 3.40), Vector2(2.70, 3.75), Vector2(3.50, 3.95), Vector2(4.60, 4.00)]
const CAR_Y := 0.04             # palace-local height of the drive
const OUTSIDE_Z := 3.7          # palace-local z where the car is past the fence
const ROAD_Z := 4.00            # palace-local z of the gray road's centre line
const GROUNDS_SPEED := 1.4      # tiles / second inside the grounds and through the turn
const ROAD_SPEED := 3.6         # tiles / second once it is on the road
const ACCEL := 1.6              # tiles / second^2
## How far the straight run continues, in tiles, after the turn onto the road.
const OUT_TILES := 16
## is_away() once the straight run has covered this many tiles.
const AWAY_TILES := 8.0

const GOLD := Color(1.0, 0.82, 0.36)
const SOFT := Color(0.86, 0.88, 0.94)
const SIGN_RED := Color(0.78, 0.07, 0.07)

var tile := TILE

var _city: Node3D
var _font_bold: Font
var _font_black: Font
var _places: Array[Dictionary] = []
var _dark_mats := {}   # lit material -> its unlit copy

# the car
var _palace: Node3D
var _src_car: Node3D
var _car: Node3D
var _path: Array = []          # world points
var _slow_until := 0           # path index where the straight run (and full speed) starts
var _last_road := 0            # path index where the turn onto the road is done
var _i := 1
var _v := 0.0
var _past_road := 0.0          # tiles driven after the turn onto the road
var _driving := false
var _cam: Camera3D
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _boom: Node3D
var _boom_up := false
var _road_y := -0.7273283

# the card
var _ui: CanvasLayer
var _card: ColorRect
var _card_rows: VBoxContainer
var _card_tween: Tween


func _ready() -> void:
	set_process(false)


func setup(city: Node3D, font_bold: Font, font_black: Font) -> void:
	_city = city
	_font_bold = font_bold
	_font_black = font_black
	_places.clear()
	if _city == null:
		return   # no city: only the card
	_set_night()
	for p in PLACES:
		var n := _city.get_node_or_null(BUILDINGS + "/" + String(p.node)) as Node3D
		if n == null:
			continue
		var e: Dictionary = p.duplicate()
		e.building = n
		e.done = false
		e.tweens = []
		_places.append(e)


## Dark air over the city, with a little moonlight. The environment is a copy,
## so the shared city stays daylight for every other scene.
func _set_night() -> void:
	var we := _city.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment.duplicate() as Environment
		if env.sky:
			env.sky = env.sky.duplicate() as Sky
			var psm := env.sky.sky_material as ProceduralSkyMaterial
			if psm:
				psm = psm.duplicate() as ProceduralSkyMaterial
				psm.sky_top_color = Color(0.012, 0.016, 0.04)
				psm.sky_horizon_color = Color(0.09, 0.11, 0.18)
				psm.sky_energy_multiplier = 0.45
				psm.ground_bottom_color = Color(0.008, 0.01, 0.02)
				psm.ground_horizon_color = Color(0.05, 0.06, 0.1)
				psm.ground_energy_multiplier = 0.25
				psm.sun_angle_max = 8.0
				env.sky.sky_material = psm
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.42, 0.48, 0.68)
		env.ambient_light_energy = 0.16
		env.background_energy_multiplier = 0.16
		env.fog_enabled = true
		env.fog_light_color = Color(0.03, 0.04, 0.07)
		env.fog_light_energy = 0.4
		env.fog_density = 0.0018
		env.fog_sky_affect = 0.55
		env.adjustment_enabled = true
		env.adjustment_brightness = 0.82
		env.adjustment_saturation = 0.78
		env.adjustment_contrast = 1.05
		we.environment = env
	var sun := _city.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_color = Color(0.74, 0.8, 0.96)
		sun.light_energy = 0.32
		sun.shadow_enabled = true
		sun.rotation_degrees = Vector3(-58.0, 32.0, 0.0)


func _is_built(n: Node) -> bool:
	if n.has_method("is_built"):
		return n.is_built()
	return bool(n.get_meta("built", true))


## A service that was still going up when the day ended (the evening was
## skipped): let it finish first.
func settle_buildings() -> void:
	for e in _places:
		var n: Node3D = e.building
		if int(n.get("stage") if n.get("stage") != null else 0) != 1:
			continue
		var limit := float(n.get("build_time")) + 3.0
		while not _is_built(n) and limit > 0.0:
			await get_tree().process_frame
			limit -= get_process_delta_time()


func closed_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _places:
		if _is_built(e.building):
			out.append(e)
	return out


func kicker(e: Dictionary) -> String:
	return "%s   ·   %s" % [e.time, e.title]


## [eye, look, creep]: in front of the building, a little to one side, the
## door (and the sign) in the middle, the vehicles out front in view.
func place_shot(e: Dictionary) -> Array:
	var b: Node3D = e.building
	var s := b.global_basis.get_scale().x
	var front := b.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.BACK
	var side := front.cross(Vector3.UP).normalized()
	var door := b.to_global(e.sign as Vector3)
	var look := door + Vector3.DOWN * 0.08 * s
	var eye := door + (front * 0.93 + side * 0.36).normalized() * 4.4 * s + Vector3.UP * 2.3 * s
	return [eye, look, (look - eye) * 0.16]


# ================================================================ lights out

## The building's lights flicker and go out, then the CLOSED sign swings down.
func close(e: Dictionary) -> void:
	if e.done:
		return
	if not e.has("lit"):
		e.lit = _collect_lit(e.building)
	# flicker: off, on, off, a last weak try, off for good
	for step in [[false, 0.12], [true, 0.07], [false, 0.16], [true, 0.05], [false, 0.0]]:
		if e.done:
			return
		_set_lit(e.lit, step[0])
		if step[1] > 0.0:
			await get_tree().create_timer(step[1]).timeout
	await get_tree().create_timer(0.55).timeout
	if e.done:
		return
	var board := _closed_sign(e)
	board.rotation_degrees.x = -88.0
	var t := create_tween()
	t.tween_property(board, "rotation_degrees:x", 0.0, 1.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	e.tweens.append(t)
	await t.finished
	e.done = true


## Straight to the end state (when the player clicks past it).
func close_now(e: Dictionary) -> void:
	if e.done:
		return
	e.done = true
	for t in e.tweens:
		if t and (t as Tween).is_valid():
			(t as Tween).kill()
	if not e.has("lit"):
		e.lit = _collect_lit(e.building)
	_set_lit(e.lit, false)
	var board := _closed_sign(e)
	board.rotation_degrees.x = 0.0


## Everything that glows on the building and its vehicles: emissive
## materials (windows, crosses, light bars, beacons, lamps), lights and the
## lettering on the signs.
func _collect_lit(root: Node3D) -> Dictionary:
	var mats: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.material_override as BaseMaterial3D
		if m == null or not m.emission_enabled:
			continue
		if not _dark_mats.has(m):
			var off := m.duplicate() as BaseMaterial3D
			off.emission_enabled = false
			var c := m.albedo_color
			off.albedo_color = Color(c.r * 0.38, c.g * 0.38, c.b * 0.4, c.a)
			_dark_mats[m] = off
		mats.append([mi, m, _dark_mats[m]])
	var lights: Array = []
	for n in root.find_children("*", "Light3D", true, false):
		lights.append([n, (n as Light3D).light_energy])
	var labels: Array = []
	for n in root.find_children("*", "Label3D", true, false):
		if n.get_parent() and n.get_parent().name == "ClosedSign":
			continue
		labels.append([n, (n as Label3D).modulate])
	return {"mats": mats, "lights": lights, "labels": labels}


func _set_lit(lit: Dictionary, on: bool) -> void:
	for m in lit.mats:
		if is_instance_valid(m[0]):
			(m[0] as MeshInstance3D).material_override = m[1] if on else m[2]
	for l in lit.lights:
		if is_instance_valid(l[0]):
			(l[0] as Light3D).light_energy = float(l[1]) if on else 0.0
	for l in lit.labels:
		if is_instance_valid(l[0]):
			var c: Color = l[1]
			(l[0] as Label3D).modulate = c if on else Color(c.r * 0.5, c.g * 0.5, c.b * 0.52, c.a)


## A red CLOSED board hung on two cords, its top edge at the place's `sign`
## point (building-local units, so it scales with the building). The node
## is the hinge along the top, so tilting it swings the board.
func _closed_sign(e: Dictionary) -> Node3D:
	var b: Node3D = e.building
	var old := b.get_node_or_null("ClosedSign") as Node3D
	if old:
		return old
	var w: float = e.w
	var h := w * 0.36
	var hinge := Node3D.new()
	hinge.name = "ClosedSign"
	b.add_child(hinge)
	hinge.position = e.sign
	hinge.rotation_degrees.z = -3.0
	var cord := _mat(Color(0.1, 0.1, 0.1), 0.8)
	var drop := 0.025
	for x in [-w * 0.32, w * 0.32]:
		_box(hinge, Vector3(0.006, drop, 0.006), Vector3(x, -drop * 0.5, 0.004), cord)
	var c := Vector3(0, -drop - h * 0.5, 0.008)
	_box(hinge, Vector3(w + 0.022, h + 0.022, 0.008), c + Vector3(0, 0, -0.004), _mat(Color(0.97, 0.97, 0.95), 0.6))
	_box(hinge, Vector3(w, h, 0.012), c, _mat(SIGN_RED, 0.5))
	var l := Label3D.new()
	l.name = "Text"
	l.text = "CLOSED"
	l.font = _font_black
	l.font_size = 64
	l.outline_size = 0
	l.modulate = Color.WHITE
	l.shaded = false
	l.double_sided = false
	l.pixel_size = w * 0.8 / 290.0
	l.position = c + Vector3(0, 0, 0.0075)
	hinge.add_child(l)
	return hinge


# ================================================================ the car

## The president's car and its way out of town. False if there's no palace.
func prepare_car() -> bool:
	_palace = _city.get_node_or_null(PALACE) as Node3D
	if _palace == null:
		return false
	tile = _palace.global_basis.get_scale().x
	_road_y = _palace.global_position.y
	_src_car = _palace.get_node_or_null("StateCar") as Node3D
	if _src_car:
		_car = _src_car.duplicate() as Node3D
		_src_car.visible = false
	else:
		_car = _plain_car()
	_car.name = "PresidentsCar"
	add_child(_car)
	var start := _palace.to_global(Vector3(0.35, CAR_Y, 1.80))
	var start_dir := _palace.global_basis.x.normalized()
	if _src_car:
		start = _src_car.global_position
		start_dir = _src_car.global_basis.z
	_put_car(start, start_dir)
	_boom = _palace.get_node_or_null("Grounds/GuardBoothR/Boom") as Node3D

	# 1. out of the right-hand gate, then the other way: a right turn onto
	# the gray road in front of the palace.
	_path = [start]
	var street_y := _street_y()
	for p in GROUNDS_PATH:
		var q := _palace.to_global(Vector3(p.x, CAR_Y, p.y))
		if p.y >= OUTSIDE_Z:
			q.y = street_y
			q = _on_road(q)
		_path.append(q)
	_slow_until = _path.size() - 1
	_last_road = _slow_until

	# 2. straight on, up the centre of that road.
	var away := _palace.global_basis.x
	away.y = 0.0
	away = away.normalized()
	var end: Vector3 = _path.back()
	for k in range(1, OUT_TILES + 1):
		var q := end + away * tile * float(k)
		q.y = street_y
		_path.append(_on_road(q))
	return true


## Height of the gray road surface. The mesh sits a little above its node.
func _street_y() -> float:
	var roads := _city.get_node_or_null(ROADS)
	if roads:
		for r in roads.get_children():
			var nm := String(r.name)
			if r is Node3D and (nm.begins_with("road_straight") or nm.begins_with("civic_road")):
				return (r as Node3D).global_position.y + 0.003 * tile
	return _road_y


## Keep the car on the grey road's centre line once it has reached it.
## Palace local z = ROAD_Z is that line; short of it, the car is still
## coming out of the gate.
func _on_road(q: Vector3) -> Vector3:
	var local := _palace.to_local(q)
	if local.z < ROAD_Z - 0.05:
		return q
	local.z = ROAD_Z
	var snapped := _palace.to_global(Vector3(local.x, 0.0, local.z))
	snapped.y = q.y
	return snapped


func car_kicker() -> String:
	return "22:09   ·   PRESIDENTIAL PALACE"


## [eye, look]: above the park, looking across the drive at the palace and
## the car still parked in front of it.
func car_shot() -> Array:
	var at: Vector3 = _car.global_position if _car else Vector3.ZERO
	var front := _palace.global_basis.z if _palace else Vector3.BACK
	front.y = 0.0
	front = front.normalized()
	var side := front.cross(Vector3.UP).normalized()
	var eye := at + front * 4.6 * tile - side * 1.6 * tile + Vector3.UP * 3.4 * tile
	return [eye, at + side * 0.4 * tile]


## Off it goes; `cam` follows it from behind and above.
func drive(cam: Camera3D) -> void:
	_cam = cam
	if _cam:
		_eye = _cam.global_position
		_look = _eye - _cam.global_basis.z * _eye.distance_to(_car.global_position)
	_i = 1
	_v = 0.0
	_past_road = 0.0
	_driving = true
	set_process(true)


func is_away() -> bool:
	return not _driving or _past_road >= AWAY_TILES


func stop_car() -> void:
	_driving = false
	set_process(false)


func _process(delta: float) -> void:
	if not _driving or _car == null:
		return
	var vmax := GROUNDS_SPEED if _i <= _slow_until else ROAD_SPEED
	if _v < vmax * tile:
		_v = minf(_v + ACCEL * tile * delta, vmax * tile)
	else:
		_v = move_toward(_v, vmax * tile, ACCEL * tile * delta)
	var step := _v * delta
	var p := _car.global_position
	var dir := Vector3.ZERO
	while step > 0.0 and _i < _path.size():
		var to: Vector3 = _path[_i] - p
		if to.length() <= step:
			step -= to.length()
			p = _path[_i]
			_i += 1
		else:
			p += to.normalized() * step
			step = 0.0
		if to.length() > 0.001:
			dir = to
	if _i > _last_road:
		_past_road = _flat3(p - _path[_last_road]).length() / tile
	if _i >= _path.size():
		_driving = false
	var flat := _flat3(dir)
	if flat.length() > 0.001:
		var want := Basis.looking_at(-flat.normalized(), Vector3.UP)
		var cur := _car.global_basis.orthonormalized()
		_car.global_transform = Transform3D(cur.slerp(want, clampf(delta * 6.0, 0.0, 1.0)).scaled(Vector3.ONE * tile), p)
	else:
		_car.global_position = p
	# the guard's gone: the boom goes up as the car comes to the gate
	if _boom and not _boom_up and _i >= 2:
		_raise_boom()
	if _cam:
		_follow(delta)


func _follow(delta: float) -> void:
	var fwd := _car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.FORWARD
	var left := Vector3.UP.cross(fwd).normalized()
	var at := _car.global_position
	var want_eye := at - fwd * 4.4 * tile + left * 1.3 * tile + Vector3.UP * 3.6 * tile
	var want_look := at + fwd * 1.4 * tile
	_eye = _eye.lerp(want_eye, 1.0 - exp(-delta * 1.6))
	_look = _look.lerp(want_look, 1.0 - exp(-delta * 2.6))
	_cam.look_at_from_position(_eye, _look, Vector3.UP)


## Lift the barrier at the side gate, hinged at the booth end.
func _raise_boom() -> void:
	_boom_up = true
	var half := 0.21
	var mi := _boom as MeshInstance3D
	if mi and mi.mesh is BoxMesh:
		half = (mi.mesh as BoxMesh).size.x * 0.5
	var p0 := _boom.position
	var hinge := p0 + Vector3(half, 0, 0)
	var t := create_tween()
	t.tween_method(func(a: float) -> void:
		_boom.rotation.z = -a
		_boom.position = hinge + Vector3(-half * cos(a), half * sin(a), 0.0),
		0.0, deg_to_rad(80.0), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _put_car(at: Vector3, toward: Vector3) -> void:
	var d := _flat3(toward).normalized()
	var b := Basis.looking_at(-d, Vector3.UP) if d != Vector3.ZERO else Basis()
	_car.global_transform = Transform3D(b.scaled(Vector3.ONE * tile), at)


## A black saloon, in case the palace has no state car.
func _plain_car() -> Node3D:
	var t := Node3D.new()
	var black := _mat(Color(0.05, 0.055, 0.07), 0.25)
	_box(t, Vector3(0.26, 0.11, 0.62), Vector3(0, 0.095, 0), black)
	_box(t, Vector3(0.23, 0.09, 0.37), Vector3(0, 0.195, -0.02), _mat(Color(0.12, 0.16, 0.22), 0.08))
	_box(t, Vector3(0.235, 0.015, 0.35), Vector3(0, 0.247, -0.02), black)
	return t


# ================================================================ the card

## On black: the treasury is empty, WALKOUT, and what happened (TEXT).
## Returns once it has faded in.
func show_card(ui: CanvasLayer) -> void:
	_ui = ui
	_card = ColorRect.new()
	_card.name = "Walkout"
	_card.color = Color(0.02, 0.025, 0.05)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_card)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(centre)
	_card_rows = VBoxContainer.new()
	_card_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_rows.add_theme_constant_override("separation", 12)
	_card_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_card_rows)

	var head := _label("MONEY  ·  0", _spaced(_font_black, 6), 18, GOLD)
	var title := _label("WALKOUT", _spaced(_font_black, 10), 64, Color.WHITE)
	var rule := _rule()
	var body := _label(TEXT, _font_bold, 25, SOFT, 960.0)
	var rows: Array[Control] = [head, title, rule, body]
	for r in rows:
		r.modulate.a = 0.0
		_card_rows.add_child(r)

	_card.modulate.a = 0.0
	_card_tween = create_tween()
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.9)
	_card_tween.tween_property(head, "modulate:a", 1.0, 0.4)
	_card_tween.tween_property(title, "modulate:a", 1.0, 0.6)
	_card_tween.tween_property(rule, "modulate:a", 1.0, 0.3)
	_card_tween.tween_property(body, "modulate:a", 1.0, 1.0)
	await _card_tween.finished


## The paragraph is on screen. A click while it is still arriving cuts to this.
func reveal_card() -> void:
	_kill_card_tween()
	if _card:
		_card.modulate.a = 1.0
	if _card_rows == null:
		return
	for r in _card_rows.get_children():
		(r as CanvasItem).modulate.a = 1.0


func _kill_card_tween() -> void:
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = null


func _label(text: String, font: Font, px: int, color: Color, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, px / 7))
	l.add_theme_constant_override("line_spacing", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(72, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := CenterContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row


func _spaced(font: Font, spacing: int) -> Font:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = spacing
	return f


# ================================================================ helpers

func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _flat3(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
