extends Node
## The earthquake that ends the game: what every place shown in the ending
## shares. Created by day_cycle.gd (_play_ending) once the last day is over.
##
## The ending tells one moment in several places, like cutting between
## cameras: each place (old_quarter_quake.gd first; more to come) is shown in
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
##   add_result(r)              {place, residents, dead, damage}
##   show_tally(r)/hide_tally() the card counting up one place's toll
##   show_summary()             the final card on black; click to play again

## When the quake hits, in seconds after midnight.
const QUAKE_TIME := 14 * 3600 + 32 * 60
const MAGNITUDE := 7.4
const GOLD := Color(1.0, 0.82, 0.36)
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
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _brown := 0.0
var _low := 0.0
var _crack := 0.0
var _clicked := false


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
		var amp := 0.06 * _tile * s
		_cam.h_offset = _noise.get_noise_2d(_t * 22.0, 0.0) * amp
		_cam.v_offset = _noise.get_noise_2d(0.0, _t * 22.0) * amp
	_feed_sound(s)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_clicked = true


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
	dead_col.add_child(_label("DEAD  ·  of %s people" % thousands(int(r.residents)), _spaced(_font_bold, 2), 18, SOFT))
	var cost_col := _column(row)
	var cost_n := _label(money_text(0.0), _font_black, 64, SOFT)
	cost_col.add_child(cost_n)
	cost_col.add_child(_label("DAMAGE", _spaced(_font_bold, 2), 18, SOFT))
	box.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(box, "modulate:a", 1.0, 0.35)
	t.tween_method(func(k: float) -> void:
		dead_n.text = thousands(roundi(float(r.dead) * k))
		cost_n.text = money_text(float(r.damage) * k), 0.0, 1.0, 1.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_tally() -> void:
	if _tally and is_instance_valid(_tally):
		var old := _tally
		var t := create_tween()
		t.tween_property(old, "modulate:a", 0.0, 0.3)
		t.tween_callback(old.queue_free)
	_tally = null


## The last word: everything added up on black. Returns when the player
## clicks (after which the scene starts again).
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
	var again := _label("Click to start again", _font_bold, 18, Color(1, 1, 1, 0.6))
	lines.append(again)
	for l in lines:
		l.modulate.a = 0.0
		v.add_child(l)

	bg.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(bg, "modulate:a", 1.0, 0.8)
	for l in lines:
		if l == again:
			t.tween_interval(1.0)
		t.tween_property(l, "modulate:a", 1.0, 0.35)
		if l == dead_n:
			t.tween_method(func(k: float) -> void:
				dead_n.text = thousands(roundi(total_dead() * k))
				cost_n.text = money_text(total_damage() * k), 0.0, 1.0, 2.2) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	var pulse := create_tween().set_loops()
	pulse.tween_property(again, "modulate:a", 0.35, 0.8)
	pulse.tween_property(again, "modulate:a", 1.0, 0.8)
	_clicked = false
	while not _clicked:
		await get_tree().process_frame
	pulse.kill()
	get_tree().reload_current_scene()


# ================================================================ sound

## A deep roar made on the fly (brown noise, low-passed), loud while the
## ground shakes, with a crackle on every jolt. No sound files needed.
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
