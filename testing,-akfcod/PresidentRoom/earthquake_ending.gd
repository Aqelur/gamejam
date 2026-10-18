extends Node
## The earthquake that ends the game: what every place shown in the ending
## shares. Created by day_cycle.gd (_play_ending) once the last day is over.
##
## The ending tells one moment in several places, like cutting between
## cameras: each place (old_quarter_quake.gd and its rescue,
## police_rescue.gd, then quake_fire.gd, then central_park_quake.gd, and last
## hospital_quake.gd, where the injured from all of them end up) is shown in
## turn with the quake clock ticking in the corner of the caption, starting
## again from about 14:32:00 each time, so they read as happening at once.
## Each place adds its toll (dead, damage) and shows it on a card; at the end
## the summary adds them all up.
##
##   choices     what the player did, from day_cycle.gd:
##               {"approved": {id: true}, "awareness", "money", "infrastructure",
##               "bureaucracy"} (stats 0..100)
##   approved(id), stat(name)   read them
##   begin_place(name, at)      the clock in the kicker: "14:32:04  ·  OLD QUARTER"
##   rumble(level, seconds)     sustained ground shake: city camera + low roar
##   kick(amount)               a sudden jolt on top
##   add_result(r)              {place, residents, dead, damage}, and an
##                              optional "note" line printed under the toll,
##                              "of" (word after "DEAD · of N", default
##                              "people") and "damage_label" (default "DAMAGE")
##   show_tally(r)/hide_tally() the card counting up one place's toll
##   show_summary()             the final card on black, then what the number
##                              means (see _show_weight); click to play again
##   set_city(city, fade)       the city and day_cycle.gd's black fade, so the
##                              end can lay the dead out in Central Park

## When the quake hits, in seconds after midnight.
const ParkShrouds := preload("res://PresidentRoom/park_memorial.gd")

const QUAKE_TIME := 14 * 3600 + 32 * 60
const MAGNITUDE := 7.4
## The recording under the roar. Quieter, and it loops: the clip is short
## and the ending visits several places.
const QUAKE_BED := "res://PresidentRoom/audio/quake_background.mp3"
const QUAKE_BED_DB := -10.0
const GOLD := Color(1.0, 0.82, 0.36)
## Reading beats in the closing cards. day_cycle.gd stretches the waits again.
const PACE := 1.45
const RED := Color(0.96, 0.36, 0.3)
const SOFT := Color(0.86, 0.88, 0.94)

var choices := {}
var results: Array[Dictionary] = []

var _ui: CanvasLayer
var _kicker: Label
var _cam: Camera3D
var _tile := 26.926893
var _font_bold: Font
var _font_black: Font
var _place := ""
var _clock := -1.0
var _shake := 0.0
var _shake_left := 0.0
var _trauma := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _tally: Control
var _count_tween: Tween
var _player: AudioStreamPlayer
var _bed: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _brown := 0.0
var _low := 0.0
var _crack := 0.0
var _city: Node3D
var _fade: ColorRect


func setup(p_choices: Dictionary, ui: CanvasLayer, kicker: Label, cam: Camera3D, tile: float,
		font_bold: Font, font_black: Font) -> void:
	choices = p_choices
	_ui = ui
	_kicker = kicker
	_cam = cam
	_tile = tile
	_font_bold = font_bold
	_font_black = font_black
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_start_sound()


## The city (City/city.tscn) and the black fade over it, for the very end.
func set_city(city: Node3D, fade: ColorRect) -> void:
	_city = city
	_fade = fade


func approved(id: String) -> bool:
	return choices.get("approved", {}).has(id)


## "awareness", "money", "infrastructure" or "bureaucracy", 0..100.
func stat(stat_name: String) -> float:
	return float(choices.get(stat_name, 50.0))


## Show `place_name` with the quake clock in the kicker, starting `at` seconds
## after the quake hit. Every place starts near 0: same moment, elsewhere.
func begin_place(place_name: String, at := 0.0) -> void:
	_place = place_name.to_upper()
	_clock = at
	_update_kicker()


func end_place() -> void:
	_clock = -1.0


func add_result(r: Dictionary) -> void:
	results.append(r)


## Ground shake at `level` (0..1) for `seconds`, then it dies away.
func rumble(level: float, seconds: float) -> void:
	_shake = maxf(_shake, clampf(level, 0.0, 1.0))
	_shake_left = maxf(_shake_left, seconds)


func kick(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func total_dead() -> int:
	var n := 0
	for r in results:
		n += int(r.dead)
	return n


func total_damage() -> float:
	var m := 0.0
	for r in results:
		m += float(r.damage)
	return m


func _process(delta: float) -> void:
	_t += delta
	if _clock >= 0.0:
		_clock += delta
		_update_kicker()
	_trauma = maxf(0.0, _trauma - delta * 0.8)
	_shake_left -= delta
	if _shake_left <= 0.0:
		_shake = move_toward(_shake, 0.0, delta * 0.35)
	var s := clampf(maxf(_shake, _trauma * _trauma), 0.0, 1.0)
	if is_instance_valid(_cam):
		# h/v offset moves the picture by world units, so the same offset
		# that rocks a street-level shot is almost nothing from high up. Grow
		# it with the camera's height so wide shots still visibly shake.
		var reach := clampf(_cam.global_position.y / (2.0 * _tile), 1.0, 3.0)
		var amp := 0.06 * _tile * s * reach
		# fast jitter plus a slower roll of the ground underneath
		_cam.h_offset = (0.75 * _noise.get_noise_2d(_t * 22.0, 0.0) + 0.45 * _noise.get_noise_2d(_t * 4.5, 50.0)) * amp
		_cam.v_offset = (0.75 * _noise.get_noise_2d(0.0, _t * 22.0) + 0.45 * _noise.get_noise_2d(50.0, _t * 4.5)) * amp
	_feed_sound(s)


func _exit_tree() -> void:
	if is_instance_valid(_cam):
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _update_kicker() -> void:
	if _kicker == null:
		return
	var t := QUAKE_TIME + int(maxf(_clock, 0.0))
	_kicker.text = "%02d:%02d:%02d   ·   %s" % [t / 3600, (t / 60) % 60, t % 60, _place]


# ================================================================ cards

## A card at the top of the screen counting up one place's toll.
func show_tally(r: Dictionary) -> void:
	hide_tally()
	var box := VBoxContainer.new()
	box.name = "Tally"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.2
	box.anchor_right = 0.8
	box.anchor_top = 0.06
	box.anchor_bottom = 0.06
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 2)
	_ui.add_child(box)
	_tally = box
	box.add_child(_label(String(r.place).to_upper(), _spaced(_font_black, 5), 18, GOLD))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 70)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var dead_col := _column(row)
	var dead_n := _label("0", _font_black, 64, RED)
	dead_col.add_child(dead_n)
	dead_col.add_child(_label("DEAD  ·  of %s %s" % [thousands(int(r.residents)), String(r.get("of", "people"))],
		_spaced(_font_bold, 2), 18, SOFT))
	var cost_col := _column(row)
	var cost_n := _label(money_text(0.0), _font_black, 64, SOFT)
	cost_col.add_child(cost_n)
	cost_col.add_child(_label(String(r.get("damage_label", "DAMAGE")), _spaced(_font_bold, 2), 18, SOFT))
	if String(r.get("note", "")) != "":
		box.add_child(_label(String(r.note), _spaced(_font_bold, 2), 16, GOLD))
	box.modulate.a = 0.0
	var t := create_tween()
	_count_tween = t
	t.tween_property(box, "modulate:a", 1.0, 0.35)
	var dead_ref: WeakRef = weakref(dead_n)
	var cost_ref: WeakRef = weakref(cost_n)
	t.tween_method(_count_up.bind(dead_ref, cost_ref, int(r.dead), float(r.damage)),
		0.0, 1.0, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_tally() -> void:
	if _count_tween and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = null
	if _tally and is_instance_valid(_tally):
		var old := _tally
		var t := create_tween()
		t.tween_property(old, "modulate:a", 0.0, 0.3)
		t.tween_callback(old.queue_free)
	_tally = null


func _count_up(k: float, dead_ref: WeakRef, cost_ref: WeakRef, dead: int, damage: float) -> void:
	var dead_label := dead_ref.get_ref() as Label
	var cost_label := cost_ref.get_ref() as Label
	if dead_label == null or cost_label == null:
		return
	dead_label.text = thousands(roundi(float(dead) * k))
	cost_label.text = money_text(damage * k)


func _count_summary(k: float, dead_ref: WeakRef, cost_ref: WeakRef) -> void:
	var dead_label := dead_ref.get_ref() as Label
	var cost_label := cost_ref.get_ref() as Label
	if dead_label == null or cost_label == null:
		return
	dead_label.text = thousands(roundi(total_dead() * k))
	cost_label.text = money_text(total_damage() * k)


func _shot() -> void:
	var cycle := get_parent()
	if cycle and cycle.has_method("ending_next_beat"):
		cycle.ending_next_beat()


func _hold(seconds: float) -> void:
	var cycle := get_parent()
	if cycle and cycle.has_method("ending_hold"):
		await cycle.ending_hold(seconds)
		return
	await get_tree().create_timer(seconds).timeout


func _clicked() -> bool:
	var cycle := get_parent()
	return cycle != null and cycle.has_method("ending_clicked") and cycle.ending_clicked()


func _until_tween(t: Tween) -> void:
	while t != null and t.is_valid() and t.is_running() and not _clicked() and is_inside_tree():
		await get_tree().process_frame
	if _clicked() and t != null and t.is_valid():
		var guard := 0
		while t.is_running() and guard < 40:
			if not t.custom_step(2.0):
				break
			guard += 1


## The last word: everything added up on black, then the bodies in the park.
## When that picture is done, the screen goes quiet and the closing lines open.
func show_summary() -> void:
	hide_tally()
	end_place()
	var bg := ColorRect.new()
	bg.name = "Summary"
	bg.color = Color(0.02, 0.025, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(centre)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(v)
	var lines: Array[Control] = []
	lines.append(_label("14:32   ·   MAGNITUDE %.1f" % MAGNITUDE, _spaced(_font_black, 6), 18, GOLD))
	lines.append(_label("THE BIG ONE", _spaced(_font_black, 8), 46, Color.WHITE))
	var dead_n := _label("0", _font_black, 110, RED)
	lines.append(dead_n)
	lines.append(_label("PEOPLE DIED", _spaced(_font_bold, 4), 22, SOFT))
	var cost_n := _label(money_text(0.0), _font_black, 44, Color.WHITE)
	lines.append(cost_n)
	lines.append(_label("IN DAMAGE", _spaced(_font_bold, 4), 18, SOFT))
	var rule := ColorRect.new()
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(72, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_row := CenterContainer.new()
	rule_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_row.add_child(rule)
	lines.append(rule_row)
	for r in results:
		lines.append(_label("%s   —   %s dead of %s   ·   %s" % [String(r.place), thousands(int(r.dead)),
			thousands(int(r.residents)), money_text(float(r.damage))], _font_bold, 20, SOFT))
	for l in lines:
		l.modulate.a = 0.0
		v.add_child(l)

	bg.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(bg, "modulate:a", 1.0, 0.8 * PACE)
	for l in lines:
		t.tween_property(l, "modulate:a", 1.0, 0.4 * PACE)
		if l == dead_n:
			var dead_ref: WeakRef = weakref(dead_n)
			var cost_ref: WeakRef = weakref(cost_n)
			t.tween_method(_count_summary.bind(dead_ref, cost_ref),
				0.0, 1.0, 2.2 * PACE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shot()
	await _until_tween(t)

	# Then what the number means, body by body (skipped if nobody died).
	var total := total_dead()
	var cover: Control = bg
	if total > 0:
		await _hold(2.8)
		cover = await _show_weight(total, bg)
	else:
		await _hold(1.6)
	await _open_outro(cover)


## After the summary: "X. X is just a number, but what does it actually
## mean?" on black. Then Central Park, one body on the grass under a black
## blanket, and the camera pulls back as more are laid down beside it, 4, 9,
## 16... faster and faster until all `total` of them lie there
## (park_memorial.gd); then it tells the player whose fault it was, over
## the wrecked city and the memorial (_blame).
## Returns the overlay it built. `summary` (the card on black) is freed
## once the words cover it. The closing lines follow that picture.
func _show_weight(total: int, summary: Control) -> Control:
	var screen := ColorRect.new()
	screen.name = "Weight"
	screen.color = Color.BLACK
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(screen)
	screen.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(screen, "modulate:a", 1.0, 1.4 * PACE)
	_shot()
	await _until_tween(t)
	summary.queue_free()
	await _hold(0.7)

	# --- the words
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(centre)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 14)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(words)
	var big := _label(thousands(total) + ".", _font_black, 120, RED)
	var line1 := _label("%s is just a number," % thousands(total), _font_bold, 30, SOFT)
	var line2 := _label("but what does it actually mean?", _font_bold, 30, Color.WHITE)
	for l: Control in [big, line1, line2]:
		l.modulate.a = 0.0
		words.add_child(l)
	await _reveal_line(big, 0.7, 1.4)
	await _reveal_line(line1, 0.7, 1.1)
	await _reveal_line(line2, 0.9, 2.8)
	_shot()
	t = create_tween()
	t.tween_property(words, "modulate:a", 0.0, 1.0 * PACE)

	# meanwhile, behind the black: lay the park out
	var field: ParkShrouds = null
	if _city and is_instance_valid(_city) and is_instance_valid(_cam):
		field = ParkShrouds.new()
		_city.add_child(field)
		if not field.setup(_city, total):
			field.queue_free()
			field = null
	await _until_tween(t)
	centre.queue_free()

	# the counter, over everything
	var over := Control.new()
	over.name = "WeightCounter"
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(over)
	# a soft shade along the bottom so the number reads over the bright park
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0.01, 0.015, 0.03, 0.62))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_right = 1.0
	shade.anchor_top = 0.6
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(shade)
	var counter := VBoxContainer.new()
	counter.anchor_right = 1.0
	counter.anchor_top = 0.78
	counter.anchor_bottom = 0.88
	counter.grow_vertical = Control.GROW_DIRECTION_BOTH
	counter.alignment = BoxContainer.ALIGNMENT_CENTER
	counter.add_theme_constant_override("separation", 0)
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(counter)
	var count := _label("1", _font_black, 72, RED)
	var lost := _label("PEOPLE WHO TRUSTED YOU", _spaced(_font_bold, 6), 22, SOFT)
	count.modulate.a = 0.0
	lost.modulate.a = 0.0
	counter.add_child(count)
	counter.add_child(lost)

	if field == null:
		# no park to show: just the number
		count.text = thousands(total)
		_shot()
		t = create_tween()
		t.tween_property(count, "modulate:a", 1.0, 0.9 * PACE)
		t.tween_property(lost, "modulate:a", 1.0, 0.9 * PACE)
		await _until_tween(t)
		await _hold(2.4)
		return over

	# --- one body, alone on the grass
	_shot()
	await _hold(0.55)
	var aspect := 16.0 / 9.0
	var vs := _cam.get_viewport().get_visible_rect().size
	if vs.y > 0.0:
		aspect = vs.x / vs.y
	var fov := _cam.fov
	var place := func(n: float, creep: float) -> void:
		var f: Array = field.frame(n, aspect, fov)
		var eye: Vector3 = f[0]
		var look: Vector3 = f[1]
		_cam.look_at_from_position(eye.lerp(look, creep), look, Vector3.UP)
	field.settle(0, 1, 1.0)
	place.call(1.0, 0.0)
	if _fade and is_instance_valid(_fade):
		_fade.color.a = 0.0
	t = create_tween().set_parallel()
	t.tween_property(screen, "modulate:a", 0.0, 2.0 * PACE)
	t.tween_property(count, "modulate:a", 1.0, 2.0 * PACE).set_delay(0.7)
	t.tween_method(func(k: float) -> void: place.call(1.0, 0.12 * k), 0.0, 1.0, 4.6 * PACE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _until_tween(t)
	screen.queue_free()

	# --- then pull back: 4, 9, 16... each step quicker than the last
	_shot()
	var all := field.count
	var n := 1
	var step := 0
	while n * n < all and not _clicked():
		var m := n + 1
		if step >= 24:
			m += int(n * 0.05)
		var from_count := n * n
		var to_count := mini(m * m, all)
		var d := maxf(0.09, 2.15 * pow(0.86, step))
		var creep := 0.12 if step == 0 else 0.0
		t = create_tween()
		t.tween_method(func(k: float) -> void:
			field.settle(from_count, to_count, k)
			place.call(lerpf(float(from_count), float(to_count), k), creep * (1.0 - k))
			count.text = thousands(roundi(lerpf(float(from_count), float(to_count), k))), 0.0, 1.0, d) \
			.set_trans(Tween.TRANS_SINE if step < 6 else Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		await _until_tween(t)
		step += 1
		if _clicked() or m * m >= all:
			break
		n = m
		if step <= 3:
			await _hold(0.7 - step * 0.12)

	# --- all of them
	field.settle(0, all, 1.0)
	place.call(float(all), 0.0)
	count.text = thousands(total)
	await get_tree().create_timer(0.9).timeout
	t = create_tween()
	t.tween_property(lost, "modulate:a", 1.0, 1.2)
	t.tween_interval(2.4)
	await t.finished

	# --- and then what it was for
	await _blame(over, counter, total, field, aspect, fov)
	return over


## The last words, to the player, in order:
##   1. over the dead, darkened: "N people trusted you, Mayor." (and, only if
##      every safety proposal was signed, "You did what you could...")
##   2. the dark lifts and the camera rises slowly over the whole wrecked city
##   3. over the city: "You were the Mayor." / "This was your city."
##   4. the camera comes down onto the memorial round the dead
##   5. "They don't get another chance. You do."
func _blame(over: Control, counter: Control, total: int, field: ParkShrouds,
		aspect: float, fov: float) -> void:
	var dim := ColorRect.new()
	dim.name = "Blame"
	dim.color = Color(0.0, 0.0, 0.01, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.add_child(centre)
	var has_cam := field != null and is_instance_valid(_cam)

	# --- 1. over the dead
	var t := create_tween().set_parallel()
	t.tween_property(dim, "color:a", 0.78, 3.0)
	t.tween_property(counter, "modulate:a", 0.0, 2.0)
	await t.finished
	await _say(centre, [
		["%s people trusted you, Mayor." % thousands(total), Color.WHITE, 34]], true)
	if _all_safety_approved():
		await _say(centre, [["You did what you could.", SOFT, 26],
			["It was still not enough for them.", SOFT, 26]], true)

	# --- 2. the dark lifts and the camera rises slowly over the wrecked city
	if has_cam:
		var from_eye := _cam.global_position
		var from_look: Vector3 = field.frame(float(field.count), aspect, fov)[1]
		var high: Array = field.frame_city(aspect, fov)
		t = create_tween().set_parallel()
		t.tween_property(dim, "color:a", 0.0, 3.5)
		t.tween_method(func(k: float) -> void:
			_cam.look_at_from_position(from_eye.lerp(high[0], k), from_look.lerp(high[1], k), Vector3.UP), 0.0, 1.0, 12.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		await get_tree().create_timer(1.0).timeout

	# --- 3. over the city
	t = create_tween()
	t.tween_property(dim, "color:a", 0.35, 1.2)
	await t.finished
	var blame_box := await _say(centre, [
		["You were the Mayor.", Color.WHITE, 36],
		["This was your city.", RED, 44]], false)
	await get_tree().create_timer(2.0).timeout

	# --- 4. down onto the memorial
	t = create_tween().set_parallel()
	t.tween_property(blame_box, "modulate:a", 0.0, 1.6)
	t.tween_property(dim, "color:a", 0.0, 2.0).set_delay(0.4)
	if has_cam:
		var city_eye := _cam.global_position
		var city_look: Vector3 = field.frame_city(aspect, fov)[1]
		var mem: Array = field.frame_all(aspect, fov)
		t.tween_method(func(k: float) -> void:
			_cam.look_at_from_position(city_eye.lerp(mem[0], k), city_look.lerp(mem[1], k), Vector3.UP), 0.0, 1.0, 9.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	blame_box.queue_free()
	await get_tree().create_timer(1.2).timeout

	# --- 5. one quiet line under it all
	var after := _label("They don't get another chance. You do.", _font_bold, 26, Color.WHITE)
	after.anchor_right = 1.0
	after.anchor_top = 0.86
	after.anchor_bottom = 0.86
	after.grow_vertical = Control.GROW_DIRECTION_BOTH
	after.modulate.a = 0.0
	over.add_child(after)
	t = create_tween()
	t.tween_property(after, "modulate:a", 1.0, 1.4)
	t.tween_interval(1.4)
	await t.finished


## Lines in the middle of the screen, one after another: each [text, colour,
## size]. With `fade_out` they go again after a pause; otherwise they stay and
## the box is returned for the caller to clear.
func _say(centre: Control, specs: Array, fade_out: bool) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(box)
	var t := create_tween()
	for spec in specs:
		var l := _label(String(spec[0]), _font_black if int(spec[2]) >= 34 else _font_bold, int(spec[2]), spec[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1100
		l.modulate.a = 0.0
		box.add_child(l)
		t.tween_property(l, "modulate:a", 1.0, 1.1)
		t.tween_interval(0.9 + 0.035 * l.text.length())
	if fade_out:
		t.tween_interval(1.6)
		t.tween_property(box, "modulate:a", 0.0, 1.0)
	await t.finished
	if fade_out:
		box.queue_free()
	return box


## True if the player signed every proposal that would have saved lives.
func _all_safety_approved() -> bool:
	for id in ["seismologist_warning", "seismologist_drill", "urban_timber_bracing",
			"interior_inspectors", "health_hospital", "agency_fire_station",
			"agency_park_tents", "interior_police"]:
		if not approved(id):
			return false
	return true


func _reveal_line(line: CanvasItem, fade: float, hold: float) -> void:
	_shot()
	var t := create_tween()
	t.tween_property(line, "modulate:a", 1.0, fade * PACE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _until_tween(t)
	line.modulate.a = 1.0
	if _clicked():
		return
	await _hold(hold)


## Park (or the toll card) fades out, the quake bed goes with it, then the
## closing lines in menu/story_outro.tscn.
func _open_outro(cover: Control) -> void:
	_shot()
	var dur := 1.4 * PACE
	var t := create_tween()
	t.set_parallel(true)
	t.tween_interval(dur)
	if is_instance_valid(cover):
		t.tween_property(cover, "modulate:a", 0.0, dur)
	if is_instance_valid(_fade):
		t.tween_property(_fade, "color:a", 1.0, dur)
	if is_instance_valid(_player):
		t.tween_property(_player, "volume_db", -50.0, dur)
	if is_instance_valid(_bed):
		t.tween_property(_bed, "volume_db", -50.0, dur)
	await _until_tween(t)
	if is_instance_valid(cover):
		cover.modulate.a = 0.0
	if is_instance_valid(_fade):
		_fade.color.a = 1.0
	if is_instance_valid(_player):
		_player.stop()
	if is_instance_valid(_bed):
		_bed.stop()
	get_tree().change_scene_to_file("res://menu/story_outro.tscn")



# ================================================================ sound

## A deep roar made on the fly (brown noise, low-passed), loud while the
## ground shakes, with a crackle on every jolt. The recording plays under it.
func _start_sound() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.name = "QuakeRumble"
	_player.stream = gen
	_player.volume_db = -2.0
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_start_bed()


func _start_bed() -> void:
	if not ResourceLoader.exists(QUAKE_BED):
		return
	var stream := load(QUAKE_BED) as AudioStreamMP3
	if stream == null:
		return
	stream = stream.duplicate() as AudioStreamMP3
	stream.loop = true
	_bed = AudioStreamPlayer.new()
	_bed.name = "QuakeBed"
	_bed.stream = stream
	_bed.volume_db = QUAKE_BED_DB
	add_child(_bed)
	_bed.play()


func _feed_sound(level: float) -> void:
	if _pb == null:
		return
	_crack = maxf(_crack - get_process_delta_time() * 2.5, _trauma * _trauma)
	var n := _pb.get_frames_available()
	for i in n:
		var white := randf() * 2.0 - 1.0
		_brown = (_brown + 0.02 * white) / 1.02
		_low = lerpf(_low, _brown, 0.06)
		var s := _low * 7.0 * level + white * 0.12 * _crack * (0.5 + 0.5 * absf(_brown) * 8.0)
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))


# ================================================================ helpers

static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func money_text(amount: float) -> String:
	if amount >= 1.0e9:
		return "$%.2f billion" % (amount / 1.0e9)
	if amount >= 1.0e6:
		return "$%.1f million" % (amount / 1.0e6)
	return "$%s" % thousands(roundi(amount))


func _column(parent: Control) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _label(text: String, font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.1, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, px / 7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spaced(font: Font, spacing: int) -> Font:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = spacing
	return f
