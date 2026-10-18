extends Control
## A little hand-drawn 2D scene for the end of the day. day_cycle.gd plays it
## instead of the city fly-over when the choice made on a proposal has a
## `cutscene` (proposal_data.gd), while the caption is read aloud.
##
##   NEWS_BROADCAST  an old TV in a living room showing the evening news. The
##                   anchor is a Pac-Man head in a suit; his mouth flaps while
##                   `talking` is true (= while the narration plays). When the
##                   set comes on, the breaking-news bed and the anchor's
##                   gibberish play together until the set goes off.
##   CALM_CITY       a cartoon panel: sunny skyline, a tour bus, money popping
##                   out of the buildings... and under the ground the fault
##                   line, fast asleep. Near the end it opens one eye.
##
## Everything is drawn in code, no assets. day_cycle.gd does:
##   setup(kind, ...) -> await intro() -> talking = true -> (narration)
##   -> talking = false -> wake_up() -> await outro()

enum Kind { NONE, NEWS_BROADCAST, CALM_CITY }

## "Breaking News" by Monume, Pixabay 547918.
## https://pixabay.com/music/electro-breaking-news-547918/
const NEWS_BED := "res://PresidentRoom/audio/monume-breaking-news-547918.mp3"
## "mamie_gibberish_1" by mamie.wilhelm, Freesound, CC0.
const ANCHOR_VOICE := "res://PresidentRoom/audio/mamie_gibberish_1.mp3"
const NEWS_BED_DB := -8.0
const ANCHOR_DB := -3.0

const YELLOW := Color(1.0, 0.86, 0.12)
const INK := Color(0.07, 0.06, 0.1)

var kind := Kind.NEWS_BROADCAST
## True while the narration is playing (the anchor talks).
var talking := false
## Roughly how long the narration lasts, in seconds. In CALM_CITY the fault
## opens its eye at 60% of it.
var expected := 8.0
var channel := "CH 7"
var headline := "CHIEF SEISMOLOGIST: \"THE BIG ONE IS COMING\""
var ticker := "LIVE: SEISMOLOGIST WARNS THE FAULT UNDER THE CITY IS WAKING UP   •   NO DATE, BUT \"THE BIG ONE IS COMING\"   •   PACK AN EMERGENCY KIT: WATER, TORCH, FIRST AID   •   KNOW YOUR NEAREST OPEN SPACE   •   HOUSE PRICES SLIP AFTER THE ANNOUNCEMENT   •   HOTELS REPORT CANCELLATIONS   •   "

var _font: Font
var _font_bold: Font
var _t := 0.0
var _talk_t := 0.0
var _power := 0.0          # TV switched on (0..1); also the panel pop for the city
var _mouth := 0.0
var _mouth_target := 0.0
var _mouth_timer := 0.0
var _awake := 0.0          # CALM_CITY: the fault's eye, 0 shut .. 1 open
var _waking := false
var _screen: Control       # the TV screen / cartoon panel, clipped
var _bed: AudioStreamPlayer
var _anchor: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _buildings: Array = []  # {x, w, h, color, windows}
var _coins: Array = []      # {x, y, age}
var _coin_timer := 0.0


func setup(p_kind: int, font: Font, font_bold: Font, p_expected := 8.0) -> void:
	kind = p_kind as Kind
	_font = font
	_font_bold = font_bold
	expected = maxf(p_expected, 2.0)
	name = "EndCutscene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.clip_contents = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_screen.draw.connect(_draw_screen)
	_rng.seed = 7
	_make_skyline()
	_rng.randomize()
	_layout()


## TV switches on / the panel pops in.
func intro() -> void:
	if kind == Kind.NEWS_BROADCAST:
		_start_news_audio()
	var t := create_tween()
	t.tween_property(self, "_power", 1.0, 0.7 if kind == Kind.NEWS_BROADCAST else 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished


## TV switches off.
func outro() -> void:
	if kind != Kind.NEWS_BROADCAST:
		return
	var t := create_tween()
	t.tween_property(self, "_power", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade_news_audio(t)
	await t.finished
	_stop_news_audio()


func _exit_tree() -> void:
	_stop_news_audio()


## News bed and the anchor's gibberish at once, both loud enough to hear.
func _start_news_audio() -> void:
	_bed = _news_player(NEWS_BED, NEWS_BED_DB, false)
	_anchor = _news_player(ANCHOR_VOICE, ANCHOR_DB, true)


func _fade_news_audio(t: Tween) -> void:
	for p in [_bed, _anchor]:
		if p and is_instance_valid(p):
			t.parallel().tween_property(p, "volume_db", -40.0, 0.45)


func _stop_news_audio() -> void:
	for p in [_bed, _anchor]:
		if p and is_instance_valid(p):
			p.stop()
			p.queue_free()
	_bed = null
	_anchor = null


func _news_player(path: String, db: float, loop: bool) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	if loop and stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	return p


## CALM_CITY: open the fault's eye now, if it hasn't opened yet.
func wake_up() -> void:
	_waking = true


func _process(delta: float) -> void:
	_t += delta
	if talking or _talk_t > 0.0:
		_talk_t += delta
	# mouth: random chomps while talking, a slight smile otherwise
	if talking:
		_mouth_timer -= delta
		if _mouth_timer <= 0.0:
			_mouth_target = _rng.randf_range(0.55, 1.0) if _mouth_target < 0.35 else _rng.randf_range(0.0, 0.22)
			_mouth_timer = _rng.randf_range(0.06, 0.15)
	else:
		_mouth_target = 0.12
	_mouth = lerpf(_mouth, _mouth_target, 1.0 - exp(-delta * 30.0))
	# the fault wakes up
	if kind == Kind.CALM_CITY:
		if _talk_t > expected * 0.6:
			_waking = true
		if _waking:
			_awake = move_toward(_awake, 1.0, delta * 2.2)
		_coin_timer -= delta
		if _coin_timer <= 0.0 and not _buildings.is_empty():
			var b: Dictionary = _buildings[_rng.randi() % _buildings.size()]
			_coins.append({"x": b.x + b.w * 0.5, "y": 0.56 - b.h, "age": 0.0})
			_coin_timer = _rng.randf_range(0.25, 0.6)
		for c in _coins:
			c.age += delta
		_coins = _coins.filter(func(c: Dictionary) -> bool: return c.age < 1.6)
	_layout()
	queue_redraw()
	_screen.queue_redraw()


# ================================================================ layout

## The scene sits in the top ~2/3 of the screen; the caption goes underneath.
func _area() -> Rect2:
	var top := size.y * 0.06
	var bottom := size.y * 0.68
	return Rect2(Vector2(0, top), Vector2(size.x, bottom - top))


func _tv_rect() -> Rect2:
	var a := _area()
	var th := a.size.y * 0.86
	var tw := th * 1.5
	if tw > size.x * 0.88:
		tw = size.x * 0.88
		th = tw / 1.5
	return Rect2(Vector2((size.x - tw) * 0.5, a.end.y - th), Vector2(tw, th))


func _layout() -> void:
	if _screen == null:
		return
	var r: Rect2
	if kind == Kind.NEWS_BROADCAST:
		var tv := _tv_rect()
		var b := tv.size.y * 0.085
		r = Rect2(tv.position + Vector2(b, b), Vector2(tv.size.x * 0.8 - b * 1.5, tv.size.y - b * 2.0))
	else:
		var a := _area()
		var ph := a.size.y
		var pw := minf(ph * 1.7, size.x * 0.9)
		ph = minf(ph, pw / 1.45)
		r = Rect2(Vector2((size.x - pw) * 0.5, a.position.y + (a.size.y - ph) * 0.5), Vector2(pw, ph))
		# pop in
		var k := 0.9 + 0.1 * _power
		r = Rect2(r.get_center() - r.size * k * 0.5, r.size * k)
	_screen.position = r.position.round()
	_screen.size = r.size.round()


func _make_skyline() -> void:
	_buildings.clear()
	var x := 0.0
	var palette := [Color(0.98, 0.62, 0.55), Color(0.55, 0.78, 0.98), Color(0.98, 0.85, 0.5),
		Color(0.7, 0.9, 0.62), Color(0.85, 0.7, 0.98), Color(0.98, 0.72, 0.85), Color(0.6, 0.88, 0.88)]
	while x < 1.0:
		var w := _rng.randf_range(0.06, 0.11)
		_buildings.append({"x": x, "w": w, "h": _rng.randf_range(0.14, 0.36),
			"color": palette[_rng.randi() % palette.size()], "seed": _rng.randi()})
		x += w + _rng.randf_range(0.0, 0.015)


# ================================================================ drawing: outside

func _draw() -> void:
	if kind == Kind.NEWS_BROADCAST:
		_draw_living_room()
	elif kind == Kind.CALM_CITY:
		_draw_panel_frame()


func _draw_living_room() -> void:
	var tv := _tv_rect()
	var floor_y := tv.end.y + tv.size.y * 0.06
	# wall
	_vgrad(self, Rect2(Vector2.ZERO, Vector2(size.x, floor_y)), Color(0.36, 0.24, 0.22), Color(0.2, 0.13, 0.13))
	var sx := 0.0
	while sx < size.x:
		draw_rect(Rect2(sx, 0, 18, floor_y), Color(1, 1, 1, 0.03))
		sx += 46.0
	# glow of the screen on the wall
	if _power > 0.05:
		var c := tv.get_center()
		for i in 5:
			draw_circle(c, tv.size.x * (0.5 + i * 0.08), Color(0.35, 0.6, 1.0, 0.025 * _power), true, -1.0, true)
	# floor
	_vgrad(self, Rect2(0, floor_y, size.x, size.y - floor_y), Color(0.2, 0.12, 0.08), Color(0.08, 0.05, 0.04))
	var py := floor_y + 10.0
	var gap := 14.0
	while py < size.y:
		draw_line(Vector2(0, py), Vector2(size.x, py), Color(0, 0, 0, 0.22), 2.0)
		gap *= 1.35
		py += gap
	# legs
	var leg := tv.size.y * 0.05
	for side in [0.16, 0.84]:
		var lx: float = tv.position.x + tv.size.x * side
		draw_line(Vector2(lx, tv.end.y - 4), Vector2(lx + (lx - tv.get_center().x) * 0.08, floor_y + leg * 0.4),
			Color(0.12, 0.07, 0.04), 8.0, true)
	draw_rect(Rect2(tv.position.x + 20, floor_y + leg * 0.2, tv.size.x - 40, 8), Color(0, 0, 0, 0.35))
	# antennas
	var base := Vector2(tv.position.x + tv.size.x * 0.42, tv.position.y + 4)
	for dir in [Vector2(-0.55, -1.0), Vector2(0.7, -1.0)]:
		var tip: Vector2 = base + (dir as Vector2).normalized() * tv.size.y * 0.42
		draw_line(base, tip, Color(0.75, 0.75, 0.8), 4.0, true)
		draw_circle(tip, 6.0, Color(0.85, 0.85, 0.9), true, -1.0, true)
	draw_circle(base, tv.size.y * 0.06, Color(0.15, 0.1, 0.08), true, -1.0, true)
	# cabinet
	_rrect(self, tv, Color(0.5, 0.3, 0.15), tv.size.y * 0.07, 5, Color(0.18, 0.1, 0.05))
	for i in 7:
		var gy := tv.position.y + tv.size.y * (0.12 + i * 0.13)
		draw_line(Vector2(tv.position.x + 14, gy), Vector2(tv.end.x - 14, gy + 3), Color(0.3, 0.17, 0.08, 0.25), 2.0)
	# bezel
	var scr := Rect2(_screen.position, _screen.size)
	_rrect(self, scr.grow(tv.size.y * 0.035), Color(0.08, 0.07, 0.07), tv.size.y * 0.05)
	# knobs and speaker
	var kx := (scr.end.x + tv.end.x) * 0.5
	var kr := tv.size.y * 0.075
	for i in 2:
		var kc := Vector2(kx, tv.position.y + tv.size.y * (0.22 + i * 0.25))
		draw_circle(kc, kr, Color(0.14, 0.12, 0.1), true, -1.0, true)
		draw_circle(kc, kr * 0.78, Color(0.78, 0.74, 0.66), true, -1.0, true)
		var a := -PI * 0.5 + (0.6 if i == 0 else -0.9)
		draw_line(kc, kc + Vector2.from_angle(a) * kr * 0.7, Color(0.15, 0.1, 0.08), 3.0, true)
	var gy0 := tv.position.y + tv.size.y * 0.66
	for i in 6:
		var y := gy0 + i * tv.size.y * 0.035
		draw_line(Vector2(kx - kr, y), Vector2(kx + kr, y), Color(0.12, 0.07, 0.04), 3.0)
	# power light
	draw_circle(Vector2(kx, tv.end.y - tv.size.y * 0.1), 4.0,
		Color(1.0, 0.25, 0.2).lerp(Color(0.3, 0.08, 0.06), 1.0 - _power), true, -1.0, true)


func _draw_panel_frame() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.15))
	var d := -size.y
	while d < size.x:
		draw_line(Vector2(d, 0), Vector2(d + size.y, size.y), Color(1, 1, 1, 0.025), 14.0)
		d += 48.0
	var r := Rect2(_screen.position, _screen.size)
	draw_rect(Rect2(r.position + Vector2(10, 12), r.size), Color(0, 0, 0, 0.45))
	draw_rect(r.grow(9), Color(0.98, 0.96, 0.9))
	draw_rect(r.grow(4), INK)


# ================================================================ drawing: screen

func _draw_screen() -> void:
	var s := _screen.size
	if s.x < 16.0 or s.y < 16.0:
		return
	if kind == Kind.NEWS_BROADCAST:
		_screen.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.03))
		if _power <= 0.001:
			return
		# switching on/off: the picture opens from a bright horizontal line
		var k := clampf(_power * 1.15, 0.0, 1.0)
		var ky := maxf(ease(k, 0.4), 0.004)
		_screen.draw_set_transform(Vector2(0, s.y * 0.5 * (1.0 - ky)), 0.0, Vector2(1, ky))
		_draw_news(s)
		_screen.draw_set_transform(Vector2.ZERO)
		var glow := clampf(1.0 - _power, 0.0, 1.0)
		if glow > 0.0:
			_screen.draw_rect(Rect2(0, s.y * 0.5 * (1.0 - ky), s.x, s.y * ky), Color(0.9, 0.95, 1.0, glow))
		_draw_crt(s)
	elif kind == Kind.CALM_CITY:
		var shake := Vector2.ZERO
		if _awake > 0.0:
			shake = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 3.0 * _awake
		_screen.draw_set_transform(shake)
		_draw_city(s)
		_screen.draw_set_transform(Vector2.ZERO)


func _draw_news(s: Vector2) -> void:
	var ci := _screen
	var u := s.y   # unit: screen height
	# studio
	_vgrad(ci, Rect2(Vector2.ZERO, s), Color(0.07, 0.2, 0.46), Color(0.02, 0.07, 0.2))
	for i in 7:
		var x := s.x * (i / 6.0) + sin(_t * 0.3 + i) * 10.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 20, 0), Vector2(x + 30, 0),
			Vector2(x + 90, s.y), Vector2(x + 10, s.y)]), Color(0.5, 0.75, 1.0, 0.04))
	# globe behind the anchor
	var gc := Vector2(s.x * 0.3, u * 0.4)
	var gr := u * 0.34
	ci.draw_circle(gc, gr, Color(0.35, 0.6, 1.0, 0.1), true, -1.0, true)
	ci.draw_arc(gc, gr, 0, TAU, 64, Color(0.6, 0.8, 1.0, 0.25), 2.0, true)
	for i in range(-1, 2):
		var ly := i * gr * 0.5
		var lw := sqrt(gr * gr - ly * ly)
		ci.draw_line(gc + Vector2(-lw, ly), gc + Vector2(lw, ly), Color(0.6, 0.8, 1.0, 0.15), 2.0)
	var spin := fmod(_t * 0.25, 1.0)
	for i in 3:
		var w := absf(cos((spin + i / 3.0) * PI)) * gr
		_ellipse_outline(ci, gc, Vector2(maxf(w, 1.0), gr), Color(0.6, 0.8, 1.0, 0.18))
	# seismograph monitor
	var mon := Rect2(s.x * 0.6, u * 0.1, s.x * 0.34, u * 0.42)
	_rrect(ci, mon, Color(0.02, 0.05, 0.12, 0.92), 10, 3, Color(0.45, 0.7, 1.0, 0.7))
	_text(ci, _font_bold, "FAULT ACTIVITY", mon.position + Vector2(mon.size.x * 0.07, u * 0.075), u * 0.045, Color(0.7, 0.85, 1.0))
	var pts := PackedVector2Array()
	var mid := mon.position.y + mon.size.y * 0.6
	var n := 70
	for i in n:
		var fx := float(i) / (n - 1)
		var ph := fx * 14.0 - _t * 6.0
		var amp := (0.15 + 0.85 * pow(absf(sin(ph * 0.21)), 6.0)) * mon.size.y * 0.25
		pts.append(Vector2(mon.position.x + mon.size.x * (0.05 + 0.9 * fx),
			mid + sin(ph * 3.1) * amp * (0.6 + 0.4 * sin(ph * 7.3))))
	ci.draw_polyline(pts, Color(1.0, 0.3, 0.25), 3.0, true)
	# the anchor
	var cx := s.x * 0.3
	var bob := sin(_t * 9.0) * u * 0.006 if talking else sin(_t * 1.6) * u * 0.003
	var desk_y := u * 0.64
	# suit
	var sh_y := u * 0.47 + bob
	ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - u * 0.1, sh_y), Vector2(cx + u * 0.1, sh_y),
		Vector2(cx + u * 0.2, desk_y), Vector2(cx - u * 0.2, desk_y)]), Color(0.17, 0.18, 0.24))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - u * 0.045, sh_y), Vector2(cx + u * 0.045, sh_y),
		Vector2(cx, sh_y + u * 0.12)]), Color(0.96, 0.96, 0.98))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - u * 0.014, sh_y + u * 0.01), Vector2(cx + u * 0.014, sh_y + u * 0.01),
		Vector2(cx + u * 0.02, sh_y + u * 0.1), Vector2(cx, sh_y + u * 0.125), Vector2(cx - u * 0.02, sh_y + u * 0.1)]),
		Color(0.85, 0.12, 0.15))
	ci.draw_circle(Vector2(cx + u * 0.075, sh_y + u * 0.07), u * 0.011, Color(0.1, 0.1, 0.1), true, -1.0, true)  # lapel mic
	# Pac-Man head
	var hc := Vector2(cx, u * 0.33 + bob)
	var hr := u * 0.15
	var half := lerpf(0.06, 0.78, _mouth)
	var head := PackedVector2Array([hc])
	var steps := 48
	for i in steps + 1:
		head.append(hc + Vector2.from_angle(lerpf(half, TAU - half, float(i) / steps)) * hr)
	ci.draw_colored_polygon(head, YELLOW)
	var rim := head.duplicate()
	rim.append(hc)
	ci.draw_polyline(rim, Color(0.55, 0.38, 0.0), 3.0, true)
	var eye := hc + Vector2(hr * 0.12, -hr * 0.5)
	ci.draw_circle(eye, hr * 0.12, INK, true, -1.0, true)
	ci.draw_circle(eye + Vector2(hr * 0.035, -hr * 0.04), hr * 0.04, Color.WHITE, true, -1.0, true)
	ci.draw_line(eye + Vector2(-hr * 0.17, -hr * 0.2), eye + Vector2(hr * 0.15, -hr * 0.24), INK, 4.0, true)
	# desk
	_vgrad(ci, Rect2(0, desk_y, s.x, u * 0.1), Color(0.75, 0.82, 0.92), Color(0.45, 0.52, 0.65))
	ci.draw_rect(Rect2(0, desk_y, s.x, 3), Color(1, 1, 1, 0.7))
	ci.draw_rect(Rect2(cx + u * 0.12, desk_y - u * 0.035, u * 0.12, u * 0.035), Color(0.95, 0.95, 0.9))  # papers
	# logo + LIVE
	var lg := Rect2(s.x * 0.03, u * 0.05, u * 0.24, u * 0.12)
	_rrect(ci, lg, Color(0.85, 0.1, 0.12), 6)
	_text(ci, _font, channel, lg.position + Vector2(0, lg.size.y * 0.72), lg.size.y * 0.55, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, lg.size.x)
	var live := Rect2(lg.end.x + u * 0.02, lg.position.y + lg.size.y * 0.2, u * 0.16, lg.size.y * 0.6)
	_rrect(ci, live, Color(0, 0, 0, 0.55), 4)
	if fmod(_t, 1.0) < 0.6:
		ci.draw_circle(live.position + Vector2(live.size.y * 0.5, live.size.y * 0.5), live.size.y * 0.22,
			Color(1, 0.2, 0.2), true, -1.0, true)
	_text(ci, _font, "LIVE", live.position + Vector2(live.size.y * 0.95, live.size.y * 0.75), live.size.y * 0.6, Color.WHITE)
	# lower third
	var lt_y := u * 0.74
	var lt_h := u * 0.12
	var tag_w := s.x * 0.28
	var slide := clampf((_t - 0.8) * 2.0, 0.0, 1.0)
	var off := (1.0 - ease(slide, 0.3)) * -s.x
	ci.draw_rect(Rect2(off, lt_y, s.x, lt_h), Color(0.97, 0.97, 0.95))
	ci.draw_rect(Rect2(off, lt_y, tag_w, lt_h), Color(0.85, 0.1, 0.12))
	_text(ci, _font, "BREAKING", Vector2(off, lt_y + lt_h * 0.68), lt_h * 0.42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, tag_w)
	var hs := _fit(_font_bold, headline, s.x - tag_w - u * 0.06, lt_h * 0.4)
	_text(ci, _font_bold, headline, Vector2(off + tag_w + u * 0.03, lt_y + lt_h * 0.66), hs, INK)
	# ticker
	var tk_y := lt_y + lt_h
	var tk_h := s.y - tk_y
	ci.draw_rect(Rect2(0, tk_y, s.x, tk_h), Color(0.03, 0.08, 0.22))
	var fs := tk_h * 0.55
	var tw := _font_bold.get_string_size(ticker, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	if tw > 1.0:
		var x := -fmod(_t * s.x * 0.14, tw)
		while x < s.x:
			_text(ci, _font_bold, ticker, Vector2(x, tk_y + tk_h * 0.72), fs, YELLOW)
			x += tw


## Scanlines, flicker and a bit of glare on the glass.
func _draw_crt(s: Vector2) -> void:
	var ci := _screen
	var y := 0.0
	while y < s.y:
		ci.draw_rect(Rect2(0, y, s.x, 1), Color(0, 0, 0, 0.13))
		y += 3.0
	var roll := fmod(_t * 0.35, 1.3) * s.y - s.y * 0.15
	ci.draw_rect(Rect2(0, roll, s.x, s.y * 0.08), Color(1, 1, 1, 0.025))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x * 0.45, 0), Vector2(0, s.y * 0.55)]),
		Color(1, 1, 1, 0.05))
	ci.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.012 * (1.0 + sin(_t * 47.0))))


func _draw_city(s: Vector2) -> void:
	var ci := _screen
	var g := s.y * 0.56          # ground line
	var road := s.y * 0.06
	# sky
	_vgrad(ci, Rect2(0, 0, s.x, g), Color(0.42, 0.72, 1.0), Color(0.8, 0.93, 1.0))
	# sun with sunglasses
	var sc := Vector2(s.x * 0.86, s.y * 0.18)
	var sr := s.y * 0.075
	for i in 12:
		var a := _t * 0.4 + i * TAU / 12.0
		ci.draw_line(sc + Vector2.from_angle(a) * sr * 1.2, sc + Vector2.from_angle(a) * sr * 1.65,
			Color(1.0, 0.8, 0.2), 5.0, true)
	ci.draw_circle(sc, sr, Color(1.0, 0.85, 0.25), true, -1.0, true)
	for side in [-1.0, 1.0]:
		ci.draw_circle(sc + Vector2(side * sr * 0.38, -sr * 0.12), sr * 0.28, INK, true, -1.0, true)
	ci.draw_line(sc + Vector2(-sr * 0.12, -sr * 0.15), sc + Vector2(sr * 0.12, -sr * 0.15), INK, 3.0)
	ci.draw_arc(sc + Vector2(0, sr * 0.15), sr * 0.42, 0.25, PI - 0.25, 16, INK, 3.0, true)
	# clouds
	for i in 3:
		var cx := fmod(s.x * (0.15 + i * 0.37) + _t * s.x * (0.012 + i * 0.006), s.x + 200.0) - 100.0
		var cy := s.y * (0.1 + i * 0.07)
		for b in [Vector3(0, 0, 1.0), Vector3(-0.9, 0.25, 0.7), Vector3(0.9, 0.25, 0.75), Vector3(0.3, -0.35, 0.8)]:
			ci.draw_circle(Vector2(cx + b.x * 30.0, cy + b.y * 30.0), 30.0 * b.z, Color(1, 1, 1, 0.95), true, -1.0, true)
	# skyline
	for bd in _buildings:
		var r := Rect2(bd.x * s.x, g - bd.h * s.y, bd.w * s.x, bd.h * s.y)
		ci.draw_rect(r, bd.color)
		ci.draw_rect(r, INK, false, 3.0)
		var wr := RandomNumberGenerator.new()
		wr.seed = bd.seed
		var ww := r.size.x / 5.0
		var wy := r.position.y + ww
		while wy < g - ww * 1.5:
			for col in 2:
				var lit := wr.randf() < 0.7
				ci.draw_rect(Rect2(r.position.x + ww * (1.0 + col * 2.0), wy, ww, ww * 1.1),
					Color(1.0, 0.95, 0.6) if lit else Color(0.3, 0.38, 0.55))
			wy += ww * 2.0
	# hot-air balloon
	var bp := Vector2(s.x * 0.12 + sin(_t * 0.5) * s.x * 0.02, s.y * 0.15 + sin(_t * 0.9) * s.y * 0.02)
	var br := s.y * 0.07
	ci.draw_line(bp + Vector2(-br * 0.6, br * 0.7), bp + Vector2(-br * 0.22, br * 1.45), INK, 2.0)
	ci.draw_line(bp + Vector2(br * 0.6, br * 0.7), bp + Vector2(br * 0.22, br * 1.45), INK, 2.0)
	ci.draw_circle(bp, br, Color(1.0, 0.38, 0.35), true, -1.0, true)
	_ellipse(ci, bp, Vector2(br * 0.45, br), Color(1.0, 0.95, 0.85))
	ci.draw_rect(Rect2(bp + Vector2(-br * 0.25, br * 1.42), Vector2(br * 0.5, br * 0.35)), Color(0.6, 0.38, 0.2))
	_text(ci, _font, "TOURS", bp + Vector2(-br, br * 0.12), br * 0.36, Color(0.75, 0.15, 0.15), HORIZONTAL_ALIGNMENT_CENTER, br * 2.0)
	# billboard on the tallest building
	var tall: Dictionary = _buildings[0]
	for bd in _buildings:
		if bd.h > tall.h and bd.x > 0.2 and bd.x < 0.75:
			tall = bd
	var bb := Rect2(tall.x * s.x + tall.w * s.x * 0.5 - s.y * 0.17, g - tall.h * s.y - s.y * 0.13, s.y * 0.34, s.y * 0.09)
	ci.draw_line(Vector2(bb.position.x + bb.size.x * 0.25, bb.end.y), Vector2(bb.position.x + bb.size.x * 0.25, bb.end.y + s.y * 0.04), INK, 3.0)
	ci.draw_line(Vector2(bb.position.x + bb.size.x * 0.75, bb.end.y), Vector2(bb.position.x + bb.size.x * 0.75, bb.end.y + s.y * 0.04), INK, 3.0)
	ci.draw_rect(bb, Color.WHITE)
	ci.draw_rect(bb, INK, false, 3.0)
	_text(ci, _font, "TOURISM +40%", bb.position + Vector2(0, bb.size.y * 0.68),
		_fit(_font, "TOURISM +40%", bb.size.x * 0.88, bb.size.y * 0.42),
		Color(0.1, 0.6, 0.25), HORIZONTAL_ALIGNMENT_CENTER, bb.size.x)
	# coins popping out of the buildings
	for c in _coins:
		var k: float = c.age / 1.6
		var p := Vector2(c.x * s.x, c.y * s.y - k * s.y * 0.14)
		var a := 1.0 - k * k
		var cr := s.y * 0.022 * (0.6 + 0.4 * minf(c.age * 6.0, 1.0))
		ci.draw_circle(p, cr, Color(1.0, 0.8, 0.15, a), true, -1.0, true)
		ci.draw_arc(p, cr, 0, TAU, 20, Color(0.6, 0.4, 0.0, a), 2.0, true)
		_text(ci, _font, "$", p + Vector2(-cr, cr * 0.5), cr * 1.4, Color(0.55, 0.35, 0.0, a), HORIZONTAL_ALIGNMENT_CENTER, cr * 2.0)
	# road + tour bus
	ci.draw_rect(Rect2(0, g, s.x, road), Color(0.35, 0.36, 0.4))
	var dx := 0.0
	while dx < s.x:
		ci.draw_rect(Rect2(dx, g + road * 0.45, 24, 3), Color(1, 1, 0.85))
		dx += 50.0
	var bw := s.y * 0.2
	var bh := s.y * 0.075
	var bx := fmod(_t * s.x * 0.09, s.x + bw * 2.0) - bw
	var bus := Rect2(bx, g + road * 0.5 - bh, bw, bh)
	_rrect(ci, bus, Color(1.0, 0.6, 0.15), 8, 3, INK)
	for i in 4:
		var wrect := Rect2(bus.position.x + bw * (0.08 + i * 0.22), bus.position.y + bh * 0.15, bw * 0.16, bh * 0.38)
		ci.draw_rect(wrect, Color(0.75, 0.92, 1.0))
		ci.draw_circle(wrect.get_center() + Vector2(0, bh * 0.05), bh * 0.09, Color(0.98, 0.78, 0.6), true, -1.0, true)
	for wx in [0.22, 0.78]:
		ci.draw_circle(Vector2(bus.position.x + bw * wx, bus.end.y), bh * 0.2, INK, true, -1.0, true)
	# soil
	var soil := g + road
	_vgrad(ci, Rect2(0, soil, s.x, s.y - soil), Color(0.55, 0.36, 0.2), Color(0.3, 0.18, 0.1))
	ci.draw_rect(Rect2(0, soil, s.x, 5), Color(0.35, 0.65, 0.3))
	for i in 3:
		var pts := PackedVector2Array()
		var ly := soil + (s.y - soil) * (0.22 + i * 0.3)
		for j in 21:
			var x := s.x * j / 20.0
			pts.append(Vector2(x, ly + sin(j * 1.3 + i) * 5.0))
		ci.draw_polyline(pts, Color(0, 0, 0, 0.12), 3.0, true)
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	for i in 18:
		ci.draw_circle(Vector2(rr.randf() * s.x, soil + 14.0 + rr.randf() * (s.y - soil - 20.0)),
			rr.randf_range(3.0, 8.0), Color(0.25, 0.16, 0.1, 0.6), true, -1.0, true)
	# the fault line
	var fy := soil + (s.y - soil) * 0.58
	var crack := PackedVector2Array()
	rr.seed = 5
	for j in 17:
		crack.append(Vector2(s.x * j / 16.0, fy + rr.randf_range(-1.0, 1.0) * (s.y - soil) * 0.14))
	var pulse := 0.5 + 0.5 * sin(_t * (2.0 + _awake * 10.0))
	var hot := Color(1.0, 0.55, 0.15).lerp(Color(1.0, 0.12, 0.08), _awake)
	ci.draw_polyline(crack, Color(hot, 0.25 + 0.25 * pulse), 16.0 + _awake * 8.0, true)
	ci.draw_polyline(crack, Color(0.1, 0.05, 0.03), 7.0, true)
	ci.draw_polyline(crack, Color(hot, 0.6 + 0.4 * pulse), 2.5, true)
	# its face
	var fc := Vector2(s.x * 0.5, fy - (s.y - soil) * 0.02)
	var er := s.y * 0.045
	var le := fc + Vector2(-er * 1.7, 0)
	var re := fc + Vector2(er * 1.7, 0)
	ci.draw_arc(le, er, 0.15, PI - 0.15, 12, INK, 4.0, true)          # always asleep
	if _awake <= 0.0:
		ci.draw_arc(re, er, 0.15, PI - 0.15, 12, INK, 4.0, true)
		var snore := 0.6 + 0.4 * sin(_t * 2.2)
		ci.draw_circle(fc + Vector2(0, er * 1.6), er * 0.35 * snore, INK, true, -1.0, true)
		for i in 3:
			var k := fmod(_t * 0.45 + i / 3.0, 1.0)
			var zp := fc + Vector2(er * 2.5 + k * er * 4.0, -er - k * s.y * 0.16)
			_text(ci, _font, "Z", zp, er * (1.0 + k * 1.2), Color(1, 1, 1, 1.0 - k))
	else:
		var open := ease(_awake, 0.4)
		_ellipse(ci, re, Vector2(er * 1.15, er * 1.15 * open), Color.WHITE)
		ci.draw_circle(re + Vector2(er * 0.15, 0), er * 0.55 * open, Color(0.85, 0.08, 0.06), true, -1.0, true)
		ci.draw_circle(re + Vector2(er * 0.2, 0), er * 0.25 * open, INK, true, -1.0, true)
		ci.draw_line(re + Vector2(-er * 1.2, -er * 1.5), re + Vector2(er * 1.1, -er * 1.1), INK, 4.0, true)
		ci.draw_arc(fc + Vector2(0, er * 2.2), er * 0.8, PI + 0.4, TAU - 0.4, 10, INK, 4.0, true)
		for i in 3:
			var a := -0.5 + i * 0.5
			var rp := fc + Vector2(er * 6.0, 0)
			ci.draw_arc(rp, er * (1.0 + i * 0.7) * (1.0 + pulse * 0.15), a - 0.5, a + 0.5, 8,
				Color(1, 0.9, 0.7, 0.7 * open), 3.0, true)
			ci.draw_arc(fc - Vector2(er * 6.0, 0), er * (1.0 + i * 0.7) * (1.0 + pulse * 0.15), PI + a - 0.5, PI + a + 0.5, 8,
				Color(1, 0.9, 0.7, 0.7 * open), 3.0, true)


# ================================================================ helpers

func _vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _rrect(ci: CanvasItem, r: Rect2, c: Color, radius: float, border := 0, bc := Color.BLACK) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = bc
	ci.draw_style_box(sb, r)


func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, color: Color) -> void:
	if radii.y < 0.5 or radii.x < 0.5:
		return
	var pts := PackedVector2Array()
	for i in 32:
		pts.append(c + Vector2(cos(i * TAU / 32.0) * radii.x, sin(i * TAU / 32.0) * radii.y))
	ci.draw_colored_polygon(pts, color)


func _ellipse_outline(ci: CanvasItem, c: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(c + Vector2(cos(i * TAU / 32.0) * radii.x, sin(i * TAU / 32.0) * radii.y))
	ci.draw_polyline(pts, color, 2.0, true)


func _text(ci: CanvasItem, font: Font, text: String, pos: Vector2, px: float, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if font == null:
		font = ThemeDB.fallback_font
	ci.draw_string(font, pos, text, align, width, maxi(int(px), 6), color)


## Largest font size up to `px` that fits `text` into `width`.
func _fit(font: Font, text: String, width: float, px: float) -> float:
	if font == null:
		return px
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
	return px if w <= width or w <= 0.0 else maxf(px * width / w, 8.0)
