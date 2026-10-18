extends CanvasLayer
## First-play tutorial at the desk, before the first visitor walks in.
##
## The view swoops over the paper so the gauge plaque and both stamps are on
## screen. Each step is a short card at the top; what it talks about is cut out
## of a dark veil and ringed in gold with a bouncing arrow. Click (or
## ui_accept) for the next step, "Skip" ends it at once. Stamps can't be picked
## up meanwhile. The building steps fade over to the city (day_cycle.gd's
## evening view) and fly to where each one would go, then fade back.
##
## Created by president_room.gd at runtime when the tutorial hasn't been seen
## yet (a flag file in user://). Emits finished when done or skipped.

signal finished

const SEEN_FILE := "user://tutorial_seen"
const FONT_BOLD := "res://PresidentRoom/fonts/Montserrat-Bold.ttf"
const FONT_BLACK := "res://PresidentRoom/fonts/Montserrat-ExtraBold.ttf"
const GOLD := Color(1.0, 0.82, 0.36)
const GREEN := Color(0.3, 0.85, 0.45)
const RED := Color(1.0, 0.36, 0.3)
## Same hues as the green APPROVED and red DENIED stamps.
const STAMP_GREEN := Color(0.2, 0.62, 0.42)
const STAMP_RED := Color(0.82, 0.22, 0.2)
const INK := Color(0.1, 0.07, 0.04, 0.96)
## Seconds between replays of the change arrows in the arrows step.
const ARROW_REPEAT := 2.9
## One click cut from the menu strip. Master is muted then, so the click
## briefly opens it while every other player is held quiet.
const STEP_CUE := "res://PresidentRoom/audio/menu_step.wav"
const STEP_CUE_DB := -2.0
## Gold ring sits this far outside the target, and breathes by RING_PULSE.
const RING_PAD := 8.0
const RING_PULSE := 5.0
## Keep the ring and its arrow this far inside the screen.
const SCREEN_MARGIN := 16.0
## Arrow shaft above (or below) the ring, including the bob.
const ARROW_REACH := 76.0
## Clear gap between two rings so their rounded corners never cross.
const RING_GAP := 10.0

## Targets: "gauge0".."gauge3" (Stat order), "plaque" (all four), "approve", "deny".
## hints: crystals to light (Stat order). arrows: play the change arrows.
## extra: "buildings" or "protect", a box under the text.
const STEPS := [
	{"title": "Welcome, Mayor!",
	"text": "This is your office. People bring ideas to your desk.\nStamp each one APPROVED or DENIED."},
	{"title": "People's Awareness", "focus": ["gauge0"],
	"text": "How much your people know about the coming earthquake."},
	{"title": "Money", "focus": ["gauge1"],
	"text": "The city's wallet.\nBuilding things costs money."},
	{"title": "Infrastructure", "focus": ["gauge2"],
	"text": "How strong your buildings, roads and pipes are."},
	{"title": "Bureaucracy", "focus": ["gauge3"],
	"text": "Paperwork and rules.\nA little helps. Too much slows everything."},
	{"title": "Keep them in the middle", "focus": ["plaque"],
	"text": "Not too high. Not too low.\nThe middle is where you want them."},
	{"title": "Green stamp = APPROVED", "focus": ["approve"],
	"text": "Pick it up and press it on the paper to APPROVE an idea."},
	{"title": "Red stamp = DENIED", "focus": ["deny"],
	"text": "Press it on the paper to DENY an idea."},
	{"title": "Glowing dots", "focus": ["gauge1", "gauge2"], "hints": [0, 1, 1, 0],
	"text": "Before you stamp, glowing dots mark the bars this choice will effect.\nThe bigger the dot, the bigger the impact."},
	{"title": "Then watch the arrows", "focus": ["gauge1", "gauge2"], "arrows": true,
	"text": "After you stamp:\nGreen arrow up = it went up.\nRed arrow down = it went down."},
	{"title": "Emergency services", "place": "civic", "city": true,
	"text": "Hospital, police station and fire dept.\nThese empty lots are waiting."},
	{"title": "Old houses", "place": "OldQuarter", "city": true,
	"text": "These streets can be braced."},
	{"title": "Park tents", "place": "Park", "city": true,
	"text": "Shelter can go here."},
	{"title": "Earthquake drill", "place": "Park", "city": true,
	"text": "Everyone can learn to meet here."},
	{"title": "When the quake comes", "extra": "protect",
	"text": "The places you just saw stay empty until you approve them."},
	{"title": "Good luck, Mayor!",
	"text": "At night you will see it go up — or stay empty."},
]

## Where the "place" steps look in the city (city.tscn paths).
const CIVIC := "Districts/CivicCenter/Buildings/"
const OLD_QUARTER := "Districts/OldQuarter"
const PARK := "Districts/EvacuationPark/CentralPark"

const DIM_SHADER := """
shader_type canvas_item;
uniform vec2 screen_size = vec2(1152.0, 648.0);
uniform vec4 hole0;
uniform vec4 hole1;
uniform vec4 hole2;
uniform vec4 hole3;
uniform int hole_count = 0;
uniform float dim = 0.62;
uniform float radius = 14.0;

float cut(vec2 p, vec4 h) {
	vec2 c = h.xy + h.zw * 0.5;
	vec2 q = abs(p - c) - h.zw * 0.5 + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	return smoothstep(-2.0, 8.0, d);
}

void fragment() {
	vec2 p = UV * screen_size;
	float a = dim;
	if (hole_count > 0) a *= cut(p, hole0);
	if (hole_count > 1) a *= cut(p, hole1);
	if (hole_count > 2) a *= cut(p, hole2);
	if (hole_count > 3) a *= cut(p, hole3);
	COLOR = vec4(0.02, 0.02, 0.04, a);
}
"""

var room                     # president_room.gd (untyped: it is a @tool script)
var _step := -1
var _rects: Array[Rect2] = []
## Parallel to _rects: arrow sits under the ring when there is no room above.
var _arrow_below: Array[bool] = []
var _t := 0.0
var _step_t := 0.0
var _arrow_t := 0.0
var _done := false
## True while fading between the desk and the city (clicks wait).
var _busy := false
var _in_city := false
## The city building whose "BUILD ..." sign is showing.
var _sign_node: Node = null
## Master was muted by us, so room and city sounds stay out until this ends.
var _held_audio := false
var _bus_was_muted := false
var _cue: AudioStreamPlayer
var _cue_stream: AudioStream
var _cue_gen := 0

var _root: Control
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _marks: Control
var _card: PanelContainer
var _count: Label
var _title: RichTextLabel
var _body: RichTextLabel
var _extra: VBoxContainer
var _hint: Label
var _font_bold: Font
var _font_black: Font


static func already_seen() -> bool:
	return FileAccess.file_exists(SEEN_FILE)


func setup(p_room) -> void:
	room = p_room
	layer = 60
	_set_world_audio(false)
	if room.desk:
		room.desk.process_mode = Node.PROCESS_MODE_DISABLED
	_build_ui()
	room.focus_paper(true)
	_root.modulate.a = 0.0
	await get_tree().create_timer(0.7).timeout
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.3)
	_show_step(0)


# ================================================================ steps

## "place" steps show the city (the evening view of day_cycle.gd) instead of
## the desk; going between the two fades through black.
func _show_step(i: int) -> void:
	_busy = true
	var s: Dictionary = STEPS[i]
	var want_city: bool = s.has("place") and room.day_cycle != null
	if want_city != _in_city:
		await _fade(1.0)
		if _done:
			return
		if want_city:
			want_city = _open_city()
		else:
			_close_city()
		_set_card(i)
		await _fade(0.0)
		if _done:
			return
	else:
		_set_card(i)
	if want_city:
		await _look_at_place(s.place)
	if _done:
		return
	_busy = false


func _set_card(i: int) -> void:
	_step = i
	_step_t = 0.0
	_arrow_t = ARROW_REPEAT
	var s: Dictionary = STEPS[i]
	_count.text = "%d / %d" % [i + 1, STEPS.size()]
	_title.text = _stamp_words(s.title)
	var city: bool = s.get("city", false)
	_title.add_theme_font_size_override("normal_font_size", 64 if city else 34)
	_body.text = _stamp_words(s.text)
	_body.add_theme_font_size_override("normal_font_size", 24 if city else 21)
	_body.visible = s.text != ""
	_hint.text = "Click to start" if i == STEPS.size() - 1 else "Click to continue"
	for c in _extra.get_children():
		c.queue_free()
	if s.get("extra", "") == "protect":
		_fill_protect()
	_extra.visible = s.has("extra")
	var over_city: bool = s.has("place")
	_dim.visible = not over_city
	_marks.visible = not over_city
	_dim_mat.set_shader_parameter("dim", 0.0 if over_city else 0.62)
	_place_card(city)
	room.show_stat_hints(s.get("hints", []))


## Desk steps sit at the top so the gauges stay clear. City steps sit at the
## bottom so the empty lots in the middle of the map stay in view.
func _place_card(city: bool) -> void:
	_card.set_anchors_preset(Control.PRESET_TOP_WIDE if not city else Control.PRESET_BOTTOM_WIDE)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -420.0
	_card.offset_right = 420.0
	if city:
		_card.offset_top = -214.0
		_card.offset_bottom = -16.0
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		_card.offset_top = 20.0
		_card.offset_bottom = 0.0
		_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH


# ================================================================ the city

func _open_city() -> bool:
	var dc = room.day_cycle
	if not dc._ensure_city():
		return false
	dc._show_city(true)
	dc._city_cam.global_transform = dc._bird
	room.lock_camera(true)
	_in_city = true
	return true


func _close_city() -> void:
	var dc = room.day_cycle
	_hide_sign()
	dc._kill(dc._orbit)
	if dc._city:
		dc._show_city(false)
	room.lock_camera(false)
	_in_city = false


## Fly the city camera to where this step looks. "civic" frames the hospital,
## police station and fire station together and lights all three signs.
func _look_at_place(place: String) -> void:
	var dc = room.day_cycle
	match place:
		"civic":
			var nodes: Array[Node3D] = []
			for lot_name in ["Hospital", "PoliceStation", "FireStation"]:
				var node := dc._city.get_node_or_null(CIVIC + lot_name) as Node3D
				if node:
					nodes.append(node)
			_lot_signs(nodes)
			await _frame_nodes(nodes)
		"OldQuarter":
			_lot_signs("")
			await _frame(dc._city.get_node_or_null(OLD_QUARTER))
		"Park":
			_lot_signs("")
			await _frame(dc._city.get_node_or_null(PARK))
		_:
			var node := dc._city.get_node_or_null(CIVIC + place) as Node3D
			_lot_signs(node)
			if node:
				await dc._fly_to(node, 1.4)


## Glide to a view of a whole area from the same side as the bird's-eye view.
func _frame(node: Node3D) -> void:
	if node == null:
		return
	await _frame_bounds(room.day_cycle._bounds(node))


## One shot of the hospital, police station and fire station. They stand in a
## line facing -X, so the camera sits in front of that line and all three
## read across the view at once.
func _frame_nodes(nodes: Array[Node3D]) -> void:
	var dc = room.day_cycle
	var bb := AABB()
	var first := true
	for node in nodes:
		var b: AABB = dc._bounds(node)
		if b.size == Vector3.ZERO:
			continue
		bb = b if first else bb.merge(b)
		first = false
	if first:
		return
	var centre := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	var span := maxf(bb.size.x, bb.size.z)
	var eye := centre + Vector3(-0.78, 0.48, 0.08).normalized() * span * 0.95
	await dc._glide(eye, centre + Vector3.UP * span * 0.04, 1.4, (centre - eye) * 0.04)


func _frame_bounds(bb: AABB) -> void:
	var dc = room.day_cycle
	if bb.size == Vector3.ZERO:
		return
	var centre := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	var extent := maxf(bb.size.x, bb.size.z)
	var eye := centre + Vector3(0.17, 0.79, 0.59).normalized() * extent * 1.15
	await dc._glide(eye, centre, 1.4, (centre - eye) * 0.06)


## `all` = every empty lot. A Node3D = only that lot. An Array = those lots.
## Anything else = none.
func _lot_signs(which: Variant) -> void:
	var dc = room.day_cycle
	_sign_node = null
	if dc == null or dc._city == null:
		return
	var all: bool = which is String and which == "all"
	var many: Array = which if which is Array else []
	for n in dc._city.get_tree().get_nodes_in_group("buildable"):
		dc._signs(n, all or (which is Node and n == which) or (n in many))
	if which is Node:
		_sign_node = which


func _hide_sign() -> void:
	_lot_signs("")


## Fade the evening's black veil (under this card) in or out.
func _fade(alpha: float) -> void:
	var dc = room.day_cycle
	if dc == null:
		return
	var f: ColorRect = dc._fade
	f.color = Color(0, 0, 0, f.color.a)
	var t := create_tween()
	t.tween_property(f, "color:a", alpha, 0.35)
	await t.finished


func _advance() -> void:
	if _done or _busy or _step < 0 or _step_t < 0.25:
		return
	if _step + 1 >= STEPS.size():
		_finish()
	else:
		_play_step_cue()
		_show_step(_step + 1)


func _finish() -> void:
	if _done:
		return
	_done = true
	var f := FileAccess.open(SEEN_FILE, FileAccess.WRITE)
	if f:
		f.store_string("1")
	if _in_city or _busy:
		await _fade(1.0)
		if _in_city:
			_close_city()
		_fade(0.0)
	room.show_stat_hints([])
	if room.desk:
		room.desk.process_mode = Node.PROCESS_MODE_INHERIT
	room.focus_paper(false)
	var t := create_tween()
	t.tween_property(_root, "modulate:a", 0.0, 0.3)
	await t.finished
	_set_world_audio(true)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	_set_world_audio(true)


## Door, footsteps and the city stay silent while the card is up.
## `on` lets them through again.
func _set_world_audio(on: bool) -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	if on:
		if not _held_audio:
			return
		AudioServer.set_bus_mute(bus, _bus_was_muted)
		_held_audio = false
	elif not _held_audio:
		_bus_was_muted = AudioServer.is_bus_mute(bus)
		AudioServer.set_bus_mute(bus, true)
		_held_audio = true


func _play_step_cue() -> void:
	if _cue_stream == null:
		if not ResourceLoader.exists(STEP_CUE):
			return
		_cue_stream = load(STEP_CUE) as AudioStream
		if _cue_stream == null:
			return
	if _cue == null or not is_instance_valid(_cue):
		_cue = AudioStreamPlayer.new()
		_cue.stream = _cue_stream
		add_child(_cue)
	_cue.volume_db = STEP_CUE_DB
	var bus := AudioServer.get_bus_index(&"Master")
	var held: Array[Dictionary] = []
	_cue_gen += 1
	var gen := _cue_gen
	if _held_audio and bus >= 0:
		_quiet_players(get_tree().root, held)
		AudioServer.set_bus_mute(bus, false)
	_cue.finished.connect(_restore_after_cue.bind(bus, held, gen), CONNECT_ONE_SHOT)
	_cue.play()


func _quiet_players(node: Node, held: Array[Dictionary]) -> void:
	if node != _cue and (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		held.append({"player": node, "db": node.get("volume_db")})
		node.set("volume_db", -80.0)
	for child in node.get_children():
		_quiet_players(child, held)


func _restore_after_cue(bus: int, held: Array[Dictionary], gen: int) -> void:
	if gen != _cue_gen:
		return
	if _held_audio and bus >= 0:
		AudioServer.set_bus_mute(bus, true)
	for item in held:
		var player = item.player
		if is_instance_valid(player):
			player.set("volume_db", item.db)


func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _step < 0 or room == null or room.camera == null:
		return
	_t += delta
	_step_t += delta
	var s: Dictionary = STEPS[_step]
	if s.get("arrows", false):
		_arrow_t += delta
		if _arrow_t >= ARROW_REPEAT:
			_arrow_t = 0.0
			room._play_change_fx(1, -1.0)   # Money down
			room._play_change_fx(2, 1.0)    # Infrastructure up
	_rects.clear()
	for target: String in s.get("focus", []):
		var r := _target_rect(target)
		if r.has_area():
			_rects.append(r)
	_fit_highlights()
	_dim_mat.set_shader_parameter("screen_size", _dim.size)
	_dim_mat.set_shader_parameter("hole_count", mini(_rects.size(), 4))
	for k in mini(_rects.size(), 4):
		var r := _rects[k].grow(RING_PAD)
		_dim_mat.set_shader_parameter("hole%d" % k, Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	_marks.queue_redraw()


# ================================================================ where things are on screen

func _target_rect(target: String) -> Rect2:
	if target == "plaque":
		var all := Rect2()
		for k in 4:
			var r := _target_rect("gauge%d" % k)
			all = r if k == 0 else all.merge(r)
		return all
	var pts: Array[Vector3] = []
	if target.begins_with("gauge"):
		var g := room.get_node_or_null("Built/StatGauges/Gauge" + target.substr(5)) as Node3D
		if g == null:
			return Rect2()
		var hw: float = room.GAUGE_SIZE.x / 8.0
		var hd: float = room.GAUGE_SIZE.y * 0.5
		# the well, plus the space above it where the crystal and arrow float
		for x in [-hw, hw]:
			for z in [-hd - 0.03, hd]:
				for y in [0.0, room.HINT_Y + 0.015]:
					pts.append(g.global_transform * Vector3(x, y, z))
	else:
		var i := 0 if target == "approve" else 1
		if i >= room.stamps.size():
			return Rect2()
		var s: Node3D = room.stamps[i]
		# the stamp up to its knob and the ink pad under it
		for x in [-0.1, 0.1]:
			for z in [-0.045, 0.08]:
				for y in [-0.015, 0.13]:
					pts.append(s.global_transform * Vector3(x, y, z))
	var cam: Camera3D = room.camera
	var rect := Rect2()
	var first := true
	for p in pts:
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if first:
			rect = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(sp)
	return rect


func _draw_marks() -> void:
	var pulse := _pulse()
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = GOLD
	ring.set_border_width_all(4)
	ring.set_corner_radius_all(16)
	ring.anti_aliasing = true
	for i in _rects.size():
		var r: Rect2 = _rects[i]
		_marks.draw_style_box(ring, r.grow(RING_PAD + pulse * RING_PULSE))
		var below := i < _arrow_below.size() and _arrow_below[i]
		_draw_pointer(r, pulse, below, i)


func _pulse() -> float:
	return 0.5 + 0.5 * sin(_t * 5.0)


func _mark_view() -> Rect2:
	var s := _marks.size
	return Rect2(Vector2(SCREEN_MARGIN, SCREEN_MARGIN), s - Vector2(SCREEN_MARGIN, SCREEN_MARGIN) * 2.0)


## Pull every ring fully onto the screen, then split any pair that would cross.
func _fit_highlights() -> void:
	_arrow_below.clear()
	if _rects.is_empty():
		return
	var view := _mark_view()
	if view.size.x < 48.0 or view.size.y < 48.0:
		return
	var pad := RING_PAD + RING_PULSE
	var limit := view.grow(-pad)
	var fitted: Array[Rect2] = []
	for r in _rects:
		fitted.append(_clamp_rect_inside(r, limit))
	_rects = fitted
	for _pass in 2:
		for i in _rects.size():
			for j in range(i + 1, _rects.size()):
				_pull_apart(i, j, pad, limit)
	for r in _rects:
		var above := r.position.y - ARROW_REACH >= view.position.y
		var below := r.end.y + ARROW_REACH <= view.end.y
		_arrow_below.append(not above and below)


func _clamp_rect_inside(r: Rect2, limit: Rect2) -> Rect2:
	if limit.size.x < 8.0 or limit.size.y < 8.0:
		return r
	var hit := r.intersection(limit)
	if hit.has_area() and hit.size.x >= 8.0 and hit.size.y >= 8.0:
		return hit
	var out := r
	out.size.x = minf(maxf(out.size.x, 8.0), limit.size.x)
	out.size.y = minf(maxf(out.size.y, 8.0), limit.size.y)
	out.position.x = clampf(out.position.x, limit.position.x, limit.end.x - out.size.x)
	out.position.y = clampf(out.position.y, limit.position.y, limit.end.y - out.size.y)
	return out


func _pull_apart(i: int, j: int, pad: float, limit: Rect2) -> void:
	var a := _rects[i]
	var b := _rects[j]
	var overlap := a.grow(pad).intersection(b.grow(pad))
	if not overlap.has_area():
		return
	if overlap.size.x <= overlap.size.y:
		var push := (overlap.size.x + RING_GAP) * 0.5
		if a.get_center().x <= b.get_center().x:
			_rects[i] = _trim_edge(a, true, false, push, limit)
			_rects[j] = _trim_edge(b, true, true, push, limit)
		else:
			_rects[j] = _trim_edge(b, true, false, push, limit)
			_rects[i] = _trim_edge(a, true, true, push, limit)
	else:
		var push := (overlap.size.y + RING_GAP) * 0.5
		if a.get_center().y <= b.get_center().y:
			_rects[i] = _trim_edge(a, false, false, push, limit)
			_rects[j] = _trim_edge(b, false, true, push, limit)
		else:
			_rects[j] = _trim_edge(b, false, false, push, limit)
			_rects[i] = _trim_edge(a, false, true, push, limit)


## `horizontal` trims x. `from_start` trims the left or top edge; otherwise the far edge.
func _trim_edge(r: Rect2, horizontal: bool, from_start: bool, amount: float, limit: Rect2) -> Rect2:
	var slack := maxf((r.size.x if horizontal else r.size.y) - 12.0, 0.0)
	var keep := minf(amount, slack)
	if horizontal:
		if from_start:
			r.position.x += keep
		r.size.x -= keep
	else:
		if from_start:
			r.position.y += keep
		r.size.y -= keep
	return _clamp_rect_inside(r, limit)


func _draw_pointer(r: Rect2, pulse: float, below: bool, index: int) -> void:
	var view := _mark_view()
	var cx := clampf(r.get_center().x, view.position.x + 20.0, view.end.x - 20.0)
	var reach := 16.0 + pulse * 10.0
	if _pointer_hits(r, cx, reach, below, index) and not _pointer_hits(r, cx, reach, not below, index):
		below = not below
	var y_dir := 1.0 if below else -1.0
	var tip := Vector2(cx, (r.end.y + reach) if below else (r.position.y - reach))
	var arrow := PackedVector2Array([
		tip,
		tip + Vector2(-18, 24.0 * y_dir), tip + Vector2(-7, 24.0 * y_dir), tip + Vector2(-7, 50.0 * y_dir),
		tip + Vector2(7, 50.0 * y_dir), tip + Vector2(7, 24.0 * y_dir), tip + Vector2(18, 24.0 * y_dir)])
	arrow = _shift_poly_inside(arrow, view)
	var shadow := PackedVector2Array()
	for p in arrow:
		shadow.append(p + Vector2(2, 3))
	_marks.draw_colored_polygon(shadow, Color(0, 0, 0, 0.5))
	_marks.draw_colored_polygon(arrow, GOLD)


func _pointer_box(r: Rect2, cx: float, reach: float, below: bool) -> Rect2:
	var tip_y := (r.end.y + reach) if below else (r.position.y - reach)
	var top := tip_y if below else tip_y - 50.0
	return Rect2(Vector2(cx - 20.0, top), Vector2(40.0, 50.0))


## True when this arrow would leave the screen or cross another ring.
func _pointer_hits(r: Rect2, cx: float, reach: float, below: bool, index: int) -> bool:
	var box := _pointer_box(r, cx, reach, below)
	if not _mark_view().encloses(box):
		return true
	var pad := RING_PAD + RING_PULSE
	for i in _rects.size():
		if i == index:
			continue
		if box.intersects(_rects[i].grow(pad)):
			return true
	return false


func _shift_poly_inside(poly: PackedVector2Array, view: Rect2) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var d := Vector2.ZERO
	if bb.position.x < view.position.x:
		d.x = view.position.x - bb.position.x
	elif bb.end.x > view.end.x:
		d.x = view.end.x - bb.end.x
	if bb.position.y < view.position.y:
		d.y = view.position.y - bb.position.y
	elif bb.end.y > view.end.y:
		d.y = view.end.y - bb.end.y
	if d == Vector2.ZERO:
		return poly
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + d)
	return out


# ================================================================ ui

func _build_ui() -> void:
	_font_bold = load(FONT_BOLD) as Font if ResourceLoader.exists(FONT_BOLD) else ThemeDB.fallback_font
	_font_black = load(FONT_BLACK) as Font if ResourceLoader.exists(FONT_BLACK) else _font_bold

	_root = Control.new()
	_root.name = "TutorialRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = DIM_SHADER
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = sh
	_dim.material = _dim_mat
	_root.add_child(_dim)

	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_root.add_child(_marks)

	# the card with the words, at the top so the plaque at the bottom stays clear
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -420.0
	_card.offset_right = 420.0
	_card.offset_top = 20.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.add_theme_stylebox_override("panel", _box(INK, GOLD, 3, 18, 22))
	_root.add_child(_card)
	var card := _card
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	_count = _label(col, _font_bold, 14, Color(0.75, 0.68, 0.55))
	_title = _rich(col, _font_black, 34, GOLD)
	_body = _rich(col, _font_bold, 21, Color(1, 0.97, 0.9))
	_extra = VBoxContainer.new()
	_extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_extra)
	_hint = _label(col, _font_bold, 15, Color(0.75, 0.68, 0.55))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var skip := Button.new()
	skip.text = "Skip tutorial"
	skip.focus_mode = Control.FOCUS_NONE
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -180.0
	skip.offset_right = -20.0
	skip.offset_top = 20.0
	skip.offset_bottom = 60.0
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.add_theme_font_override("font", _font_bold)
	skip.add_theme_font_size_override("font_size", 16)
	skip.add_theme_stylebox_override("normal", _box(INK, Color(0.6, 0.5, 0.35), 2, 12, 8))
	skip.add_theme_stylebox_override("hover", _box(Color(0.2, 0.14, 0.08, 0.96), GOLD, 2, 12, 8))
	skip.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.14, 0.08, 0.96), GOLD, 2, 12, 8))
	skip.pressed.connect(_finish)
	_root.add_child(skip)


func _fill_protect() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	_extra.add_child(row)
	_side(row, "APPROVE", "They are built\nbefore the quake.", GREEN)
	_side(row, "DENY", "They are still\nempty lots.", RED)


func _side(parent: Control, heading: String, line: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _box(color.darkened(0.75), color, 3, 14, 16))
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	_label(col, _font_black, 32, color).text = heading
	var body := _label(col, _font_bold, 26, Color(1, 0.97, 0.9))
	body.text = line
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## APPROVE / APPROVED in the stamp green, DENY / DENIED in the stamp red.
func _stamp_words(text: String) -> String:
	var out := text
	out = out.replace("APPROVED", "\u0001")
	out = out.replace("DENIED", "\u0002")
	out = out.replace("APPROVE", "[color=#%s]APPROVE[/color]" % STAMP_GREEN.to_html(false))
	out = out.replace("DENY", "[color=#%s]DENY[/color]" % STAMP_RED.to_html(false))
	out = out.replace("\u0001", "[color=#%s]APPROVED[/color]" % STAMP_GREEN.to_html(false))
	out = out.replace("\u0002", "[color=#%s]DENIED[/color]" % STAMP_RED.to_html(false))
	return out


func _rich(parent: Control, font: Font, px: int, color: Color) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("normal_font", font)
	l.add_theme_font_size_override("normal_font_size", px)
	l.add_theme_color_override("default_color", color)
	parent.add_child(l)
	return l


func _label(parent: Control, font: Font, px: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _box(bg: Color, border: Color, border_px: int, radius: int, margin: float) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_px)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(margin)
	st.anti_aliasing = true
	return st
