extends Node
## Days at the desk, real proposals, and the end-of-day look at the city.
##
## Created by president_room.gd at runtime (never in the editor).
##
## A day is `room.proposals_per_day` proposals (4). The real proposals in
## PresidentRoom/proposals/*.tres (proposal_data.gd) are dealt first: every
## `start` one that hasn't been on the desk yet, plus any that an earlier
## choice unlocked. The rest of the day is filled with the old placeholder
## papers. Stamping a real proposal changes the four stats on the plaque.
##
## When the last proposal of the day is stamped the president turns to the
## window on the left, the view pushes into the glass, and after a white
## flash you are looking down at the city (City/city.tscn, shown in its own
## SubViewport so its sky and lights don't mix with the office). For each
## real proposal decided that day that has a `city_target`, the camera flies
## to that spot and a caption explains what changed, e.g. the hospital rises
## out of the ground with its builders. A choice can instead have a
## `cutscene` (end_cutscene.gd): a little 2D scene, e.g. the evening news on
## TV, shown over the city while its caption is read aloud (the choice's
## `voice` recording, or else the system text-to-speech voice). Then it fades
## back to the office and the next day starts. A CONCERT choice (the
## Influencer's) instead puts up a one-night show on the beach
## (beach_concert.gd): night falls, the camera goes down into the dancing
## crowd, the drop hits with fireworks, and the caption is read out line by
## line over the music. It is always the last thing shown that evening, and
## the stage is gone again by the next morning.

signal day_started(day: int)
signal day_ended(day: int)

const ProposalData := preload("res://PresidentRoom/proposal_data.gd")
const EndCutscene := preload("res://PresidentRoom/end_cutscene.gd")
const BeachConcert := preload("res://PresidentRoom/beach_concert.gd")
const PROPOSALS_DIR := "res://PresidentRoom/proposals"
const CITY_SCENE := "res://City/city.tscn"
const FONT_BOLD := "res://PresidentRoom/fonts/Montserrat-Bold.ttf"
const FONT_BLACK := "res://PresidentRoom/fonts/Montserrat-ExtraBold.ttf"
const SKY_FLASH := Color(0.93, 0.96, 1.0)
const GOLD := Color(1.0, 0.82, 0.36)
const QUIET_DAY := "A quiet day. Nothing you signed today changed the city."

var room                     # president_room.gd (untyped: it is a @tool script)
var day := 1
## The real proposal on the paper right now, or null for a placeholder.
var current: Resource = null
## True while the end-of-day sequence is playing.
var busy := false

var _catalog: Array[Resource] = []
var _used := {}         # id -> true once it has been on the desk
var _unlocked := {}     # id -> true
var _deck: Array = []   # ProposalData or null (placeholder), in order
var _decided := 0
var _today: Array[Dictionary] = []   # {"data": ProposalData, "approved": bool}

var _ui: CanvasLayer
var _fade: ColorRect
var _shade: TextureRect
var _city_box: SubViewportContainer
var _city_vp: SubViewport
var _city: Node3D
var _city_cam: Camera3D
var _bird := Transform3D.IDENTITY
var _caption_box: VBoxContainer
var _kicker: Label
var _bar: ColorRect
var _caption: RichTextLabel
var _day_label: Label
var _font_bold: Font
var _font_black: Font
var _city_requested := false
var _orbit: Tween
var _tts_voice := ""
var _tts_checked := false
var _concert = null   # beach_concert.gd while it is up


func setup(p_room) -> void:
	room = p_room
	_load_catalog()
	_deal()
	_build_ui()
	# start loading the city in the background so the window shot doesn't hitch
	if ResourceLoader.exists(CITY_SCENE):
		_city_requested = ResourceLoader.load_threaded_request(CITY_SCENE) == OK


# ================================================================ proposals

func _load_catalog() -> void:
	_catalog.clear()
	for f in DirAccess.get_files_at(PROPOSALS_DIR):
		var file := f.trim_suffix(".remap")   # exported builds rename resources
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var r := load(PROPOSALS_DIR + "/" + file)
		if r and r.get_script() == ProposalData and r.id != "":
			_catalog.append(r)
	# the `first` proposal opens the game, the rest go by id
	_catalog.sort_custom(func(a: Resource, b: Resource) -> bool:
		if a.first != b.first:
			return a.first
		return a.id < b.id)


## Put together today's papers.
func _deal() -> void:
	_deck.clear()
	_today.clear()
	_decided = 0
	var n: int = maxi(1, room.proposals_per_day)
	for p in _catalog:
		if _deck.size() >= n:
			break
		if _used.has(p.id):
			continue
		if p.start or _unlocked.has(p.id):
			_deck.append(p)
	while _deck.size() < n:
		_deck.append(null)


## The next paper of the day: a real proposal, or null for a placeholder.
func next_proposal() -> Resource:
	current = _deck.pop_front() if not _deck.is_empty() else null
	if current:
		_used[current.id] = true
	return current


## Stat changes the proposal on the paper would make (empty for a placeholder).
func effects_for(approved: bool) -> Array[int]:
	if current == null:
		return []
	return current.effects(approved)


## Apply the stamp. Returns true when that was the last proposal of the day.
func on_stamped(approved: bool) -> bool:
	if current:
		var fx: Array[int] = current.effects(approved)
		for i in fx.size():
			if fx[i] != 0:
				room.set_stat(i, room.get_stat(i) + fx[i])
		var u: String = current.unlocks(approved)
		if u != "":
			_unlocked[u] = true
		_today.append({"data": current, "approved": approved})
		current = null
	_decided += 1
	return _decided >= room.proposals_per_day


# ================================================================ end of the day

func end_day() -> void:
	if busy:
		return
	busy = true
	day_ended.emit(day)
	room.lock_camera(true)
	var cam: Camera3D = room.camera

	# 1. turn to the window on the left
	var win: Vector3 = room.left_window_centre()
	var normal: Vector3 = room.left_window_normal()
	var eye := cam.global_position
	await _move_cam(cam, Transform3D(Basis.looking_at(win - eye, Vector3.UP), eye), 1.5,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.35).timeout

	# 2. push into the glass, and flash white as the view goes through it
	var into := Transform3D(Basis.looking_at(-normal, Vector3.UP), win + normal * 0.22)
	var push := _move_cam(cam, into, 1.7, Tween.TRANS_CUBIC, Tween.EASE_IN, 38.0)
	_fade.color = Color(SKY_FLASH, 0.0)
	var f := create_tween()
	f.tween_interval(1.15)
	f.tween_property(_fade, "color:a", 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await push
	if f.is_running():
		await f.finished

	# 3. bird's-eye view of the city
	if not _ensure_city():
		await _back_to_office()
		return
	_show_city(true)
	_city_cam.global_transform = _bird
	var bird_target := _ground_point(_bird)
	_drift(_bird, bird_target, 7.0)
	_kicker.text = "END OF DAY %d" % day
	_set_caption("")
	_caption_box.modulate.a = 1.0
	_show_kicker()
	var out := create_tween()
	out.tween_property(_fade, "color:a", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(2.2).timeout

	# 4. each change made today, one after another
	var shown := 0
	for entry in _evening_order():
		var data: Resource = entry.data
		var approved: bool = entry.approved
		if data.action(approved) == ProposalData.CityAction.CONCERT:
			if shown > 0:
				await _hide_caption()
			shown += 1
			await _play_concert(data, approved)
			continue
		if data.cutscene(approved) != ProposalData.Cutscene.NONE:
			if shown > 0:
				await _hide_caption()
			shown += 1
			await _play_cutscene(data, approved)
			continue
		if data.city_target == "":
			continue
		var node := _city.get_node_or_null(NodePath(data.city_target)) as Node3D
		if node == null:
			push_warning("DayCycle: city target '%s' of %s not found in %s" % [data.city_target, data.id, CITY_SCENE])
			continue
		if shown > 0:
			await _hide_caption()
		shown += 1
		await _fly_to(node)
		_type_caption(data.caption(approved))
		if data.action(approved) == ProposalData.CityAction.BUILD and node.has_method("build") \
				and not node.is_built():
			node.build()
			var limit := float(node.get("build_time")) + 3.0
			var waited := 0.0
			while not node.is_built() and waited < limit:
				await get_tree().process_frame
				waited += get_process_delta_time()
			await get_tree().create_timer(3.2).timeout   # cheer, sign, jingle
		else:
			await get_tree().create_timer(5.0).timeout
	if shown == 0:
		_type_caption(QUIET_DAY)
		await get_tree().create_timer(4.0).timeout

	await _back_to_office()


func _back_to_office() -> void:
	# fade to black, back at the desk, next day
	_fade.color = Color(0, 0, 0, _fade.color.a)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.8)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, 0.6)
	if _concert:
		_concert.fade_out(0.8)
	await t.finished
	if _concert:
		_concert.close()   # the stage comes down overnight
		_concert = null
	_kill(_orbit)
	if _city:
		_show_city(false)
	room.lock_camera(false)
	day += 1
	_deal()
	_day_label.text = "DAY %d" % day
	_day_label.modulate.a = 0.0
	_day_label.visible = true
	var d := create_tween()
	d.tween_property(_day_label, "modulate:a", 1.0, 0.5)
	d.tween_interval(1.0)
	d.tween_property(_fade, "color:a", 0.0, 1.0)
	d.parallel().tween_property(_day_label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	await d.finished
	_day_label.visible = false
	busy = false
	day_started.emit(day)


# ================================================================ concert

## Today's decisions in the order they're shown: a concert is the finale.
func _evening_order() -> Array[Dictionary]:
	var order: Array[Dictionary] = []
	var shows: Array[Dictionary] = []
	for entry in _today:
		if entry.data.action(entry.approved) == ProposalData.CityAction.CONCERT:
			shows.append(entry)
		else:
			order.append(entry)
	order.append_array(shows)
	return order


## The Influencer's night on the beach. The caption is split on "|" into
## lines that are typed and read aloud one after another:
##   1. wide view of the stage while night falls and the intro plays
##   2. down in the crowd while the music builds
##   3. the drop: lasers, confetti, fireworks, camera cranes up and back
func _play_concert(data: Resource, approved: bool) -> void:
	var lines: PackedStringArray = data.caption(approved).split("|", false)
	var voice: AudioStream = data.voice(approved) if lines.size() <= 1 else null
	_concert = BeachConcert.new()
	_concert.name = "BeachConcert"
	_city.add_child(_concert)
	_concert.setup(_city)
	_concert.start()
	_concert.nightfall(5.0)
	await _fly_to(_concert.rig)
	await _concert_line(lines, 0, voice)

	_concert.queue_part(BeachConcert.Part.BUILD)
	var crowd: Array = _concert.crowd_shot()
	await _glide(crowd[0], crowd[1], 3.6, crowd[2])
	await _concert_line(lines, 1, null)

	_concert.queue_part(BeachConcert.Part.DROP)
	var waited := 0.0
	while _concert.part != BeachConcert.Part.DROP and waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var wide: Array = _concert.wide_shot()
	_glide(wide[0], wide[1], 9.0, wide[2])
	await get_tree().create_timer(3.0).timeout
	for i in range(2, maxi(lines.size(), 3)):
		await _concert_line(lines, i, null)
	await get_tree().create_timer(6.0).timeout
	_concert.queue_part(BeachConcert.Part.OUTRO)


## Type caption line `i` and read it out, with the music turned down.
func _concert_line(lines: PackedStringArray, i: int, voice: AudioStream) -> void:
	if i >= lines.size():
		await get_tree().create_timer(4.0).timeout   # just enjoy the show
		return
	var text := lines[i].strip_edges()
	_type_caption(text)
	_concert.duck(true)
	await _narrate(text.replace("*", ""), voice)
	_concert.duck(false)
	await get_tree().create_timer(1.4).timeout
	await _hide_caption()


## Glide the city camera to `to`, looking at `look`, then keep creeping along
## `creep` while the moment plays out. Returns when the glide is done.
func _glide(to: Vector3, look: Vector3, time: float, creep := Vector3.ZERO) -> void:
	_kill(_orbit)
	var p0 := _city_cam.global_position
	var l0 := p0 - _city_cam.global_basis.z * p0.distance_to(look)
	_orbit = create_tween()
	_orbit.tween_method(func(k: float) -> void:
		_city_cam.look_at_from_position(p0.lerp(to, k), l0.lerp(look, k), Vector3.UP), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if creep != Vector3.ZERO:
		_orbit.tween_method(func(k: float) -> void:
			_city_cam.look_at_from_position(to + creep * k, look, Vector3.UP), 0.0, 1.0, 20.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(time).timeout


# ================================================================ cutscenes

## Show the choice's 2D scene over the city and read its caption aloud.
func _play_cutscene(data: Resource, approved: bool) -> void:
	var text: String = data.caption(approved)
	var spoken := text.replace("*", "")
	var cs := EndCutscene.new()
	cs.setup(data.cutscene(approved), _font_black, _font_bold, _speech_time(spoken))
	_ui.add_child(cs)
	_ui.move_child(cs, _caption_box.get_index())   # under the caption
	cs.modulate.a = 0.0
	var f := create_tween()
	f.tween_property(cs, "modulate:a", 1.0, 0.5)
	await f.finished
	await cs.intro()
	await get_tree().create_timer(0.4).timeout
	_type_caption(text)
	cs.talking = true
	await _narrate(spoken, data.voice(approved))
	cs.talking = false
	cs.wake_up()
	await get_tree().create_timer(1.6).timeout
	await _hide_caption()
	await cs.outro()
	var o := create_tween()
	o.tween_property(cs, "modulate:a", 0.0, 0.5)
	await o.finished
	cs.queue_free()


## About how long it takes to say `text`, in seconds.
func _speech_time(text: String) -> float:
	return clampf(text.split(" ", false).size() / 2.6, 2.5, 30.0)


## Read `text` aloud: the recording if there is one, else text-to-speech
## (Project Settings > Audio > General > Text to Speech must be on), else
## just wait as long as reading it would take. Returns when it's done.
func _narrate(text: String, stream: AudioStream) -> void:
	var limit := _speech_time(text) * 2.0 + 3.0
	var waited := 0.0
	if stream:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		add_child(p)
		p.play()
		limit = maxf(stream.get_length(), 1.0) + 1.0
		while p.playing and waited < limit:
			await get_tree().process_frame
			waited += get_process_delta_time()
		p.queue_free()
		return
	if _tts_ready():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, _tts_voice, 80, 1.0, 0.95)
		var started := false
		while waited < limit:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if DisplayServer.tts_is_speaking():
				started = true
			elif started or waited > 1.5:
				break
		if started:
			return
		push_warning("DayCycle: text-to-speech didn't start, showing the caption only")
	await get_tree().create_timer(maxf(_speech_time(text) - waited, 0.5)).timeout


func _tts_ready() -> bool:
	if not _tts_checked:
		_tts_checked = true
		if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
			push_warning("DayCycle: turn on Project Settings > Audio > General > Text to Speech for narration")
			return false
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if voices.is_empty():
			push_warning("DayCycle: no English text-to-speech voice installed")
		else:
			_tts_voice = voices[0]
	return _tts_voice != ""


# ================================================================ camera

func _move_cam(cam: Camera3D, to: Transform3D, time: float, trans: Tween.TransitionType,
		easing: Tween.EaseType, fov_to := -1.0) -> Signal:
	var from := cam.global_transform
	var f0 := cam.fov
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		cam.global_transform = Transform3D(from.basis.slerp(to.basis, k), from.origin.lerp(to.origin, k))
		if fov_to > 0.0:
			cam.fov = lerpf(f0, fov_to, k), 0.0, 1.0, time).set_trans(trans).set_ease(easing)
	return t.finished


## Where the camera's view ray meets the ground.
func _ground_point(xf: Transform3D) -> Vector3:
	var dir := -xf.basis.z
	if dir.y > -0.01:
		return xf.origin + dir * 600.0
	return xf.origin + dir * (-xf.origin.y / dir.y)


## Slow push toward the ground point while the bird's-eye view holds.
func _drift(from: Transform3D, target: Vector3, time: float) -> void:
	_kill(_orbit)
	var p0 := from.origin
	var p1 := p0.lerp(target, 0.12)
	_orbit = create_tween()
	_orbit.tween_method(func(k: float) -> void:
		_city_cam.look_at_from_position(p0.lerp(p1, k), target, Vector3.UP), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Fly from wherever the city camera is to a 3/4 view of the node, then keep
## circling it slowly while the change plays out.
func _fly_to(node: Node3D) -> void:
	_kill(_orbit)
	_signs(node, true)
	var s := node.global_basis.get_scale().x
	var origin := node.global_position
	var front := node.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.FORWARD
	var side := front.cross(Vector3.UP).normalized()
	var focus := origin + Vector3.UP * 0.9 * s
	var dist := 6.8 * s
	var lift := 4.4 * s
	var dir0 := (front * 0.85 + side * 0.55).normalized()
	var goal := origin + dir0 * dist + Vector3.UP * lift

	var p0 := _city_cam.global_position
	var t0 := _ground_point(_city_cam.global_transform)
	var fly := create_tween()
	fly.tween_method(func(k: float) -> void:
		var look_k := 1.0 - pow(1.0 - k, 2.2)      # turn toward it early
		var pos := p0.lerp(goal, k) + Vector3.UP * sin(k * PI) * 0.15 * p0.distance_to(goal)
		_city_cam.look_at_from_position(pos, t0.lerp(focus, look_k), Vector3.UP), 0.0, 1.0, 3.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fly.finished
	# circle a little while we watch
	_orbit = create_tween()
	_orbit.tween_method(func(a: float) -> void:
		var d := dir0.rotated(Vector3.UP, a)
		_city_cam.look_at_from_position(origin + d * dist + Vector3.UP * lift, focus, Vector3.UP),
		0.0, deg_to_rad(-26.0), 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ================================================================ the city

func _ensure_city() -> bool:
	if _city:
		return true
	var packed: PackedScene = null
	if _city_requested:
		packed = ResourceLoader.load_threaded_get(CITY_SCENE) as PackedScene
	if packed == null and ResourceLoader.exists(CITY_SCENE):
		packed = load(CITY_SCENE) as PackedScene
	if packed == null:
		push_warning("DayCycle: could not load %s" % CITY_SCENE)
		return false
	_city = packed.instantiate() as Node3D
	# the city's own fly camera (and its debug hotkeys) stay out of this
	var fov := 48.0
	var ov := _city.get_node_or_null("OverviewCamera") as Camera3D
	if ov:
		fov = ov.fov
		_city.remove_child(ov)
		ov.free()
	# buildings are only built from here, never by clicking, and their sound
	# isn't positional (the camera is far above them)
	for n in _city.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc and sc.resource_path.ends_with("buildable.gd"):
			n.set("click_to_build", false)
			n.set("positional_sound", false)
	_city_cam = Camera3D.new()
	_city_cam.name = "DayCycleCamera"
	_city_cam.fov = fov
	_city_cam.near = 0.5
	_city_cam.far = 9000.0
	_city.add_child(_city_cam)
	_city_vp.add_child(_city)
	_city_cam.make_current()
	# bird's-eye view: high above the districts, from the beach side
	var bounds := _bounds(_city.get_node_or_null("Districts") as Node3D)
	var centre := Vector3(60, 0, -200)
	var extent := 1000.0
	if bounds.size != Vector3.ZERO:
		centre = Vector3(bounds.get_center().x, 0.0, bounds.get_center().z)
		extent = maxf(bounds.size.x, bounds.size.z)
	var eye := centre + Vector3(0.17, 0.79, 0.59) * extent
	_bird = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	# the floating "BUILD ..." signs only show for the place being looked at
	for n in _city.get_tree().get_nodes_in_group("buildable"):
		_signs(n, false)
	return true


func _bounds(n: Node3D) -> AABB:
	var bb := AABB()
	if n == null:
		return bb
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


## Show or hide a buildable's floating sign (Label3Ds on its construction lot).
func _signs(node: Node, on: bool) -> void:
	var lot := node.get_node_or_null("ConstructionLot")
	if lot:
		for l in lot.find_children("*", "Label3D", false, false):
			(l as Label3D).visible = on


func _show_city(on: bool) -> void:
	_city_box.visible = on
	_shade.visible = on
	_city_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_city.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


# ================================================================ overlay

func _build_ui() -> void:
	_font_bold = _load_font(FONT_BOLD)
	_font_black = _load_font(FONT_BLACK)

	_ui = CanvasLayer.new()
	_ui.name = "DayCycleUI"
	_ui.layer = 40
	add_child(_ui)

	_city_box = SubViewportContainer.new()
	_city_box.name = "City"
	_city_box.stretch = true
	_city_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_city_box.visible = false
	_ui.add_child(_city_box)
	_city_vp = SubViewport.new()
	_city_vp.name = "CityViewport"
	_city_vp.own_world_3d = true
	_city_vp.msaa_3d = Viewport.MSAA_2X
	_city_vp.audio_listener_enable_3d = true
	_city_vp.handle_input_locally = false
	_city_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_city_box.add_child(_city_vp)

	# darken the bottom of the city shot so the caption reads
	_shade = TextureRect.new()
	_shade.name = "Shade"
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.08, 0.0))
	grad.set_color(1, Color(0.02, 0.03, 0.08, 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	_shade.texture = gt
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.anchor_left = 0.0
	_shade.anchor_right = 1.0
	_shade.anchor_top = 0.55
	_shade.anchor_bottom = 1.0
	_shade.visible = false
	_ui.add_child(_shade)

	_caption_box = VBoxContainer.new()
	_caption_box.name = "Caption"
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.anchor_left = 0.1
	_caption_box.anchor_right = 0.9
	_caption_box.anchor_top = 0.6
	_caption_box.anchor_bottom = 0.93
	_caption_box.alignment = BoxContainer.ALIGNMENT_END
	_caption_box.add_theme_constant_override("separation", 10)
	_caption_box.modulate.a = 0.0
	_ui.add_child(_caption_box)

	_kicker = Label.new()
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kicker.add_theme_font_override("font", _spaced(_font_black, 5))
	_kicker.add_theme_font_size_override("font_size", 18)
	_kicker.add_theme_color_override("font_color", GOLD)
	_kicker.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 0.85))
	_kicker.add_theme_constant_override("outline_size", 5)
	_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.add_child(_kicker)

	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.add_child(bar_row)
	_bar = ColorRect.new()
	_bar.color = GOLD
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_bar)

	_caption = RichTextLabel.new()
	_caption.bbcode_enabled = true
	_caption.fit_content = true
	_caption.scroll_active = false
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("normal_font", _font_bold)
	_caption.add_theme_font_override("bold_font", _font_black)
	_caption.add_theme_font_size_override("normal_font_size", 34)
	_caption.add_theme_font_size_override("bold_font_size", 34)
	_caption.add_theme_color_override("default_color", Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.14, 0.92))
	_caption.add_theme_constant_override("outline_size", 9)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_caption.add_theme_constant_override("shadow_offset_x", 0)
	_caption.add_theme_constant_override("shadow_offset_y", 4)
	_caption.add_theme_constant_override("line_separation", 2)
	_caption_box.add_child(_caption)

	_day_label = Label.new()
	_day_label.name = "DayLabel"
	_day_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_override("font", _spaced(_font_black, 10))
	_day_label.add_theme_font_size_override("font_size", 64)
	_day_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_day_label.visible = false

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(SKY_FLASH, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	_ui.add_child(_day_label)   # above the fade, so it shows on black


func _show_kicker() -> void:
	_kicker.modulate.a = 0.0
	_bar.custom_minimum_size.x = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_kicker, "modulate:a", 1.0, 0.6)
	t.tween_property(_bar, "custom_minimum_size:x", 72.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_caption(text: String) -> void:
	_caption.text = "[center]%s[/center]" % _markup(text)
	_caption.visible_ratio = 1.0


## Type the caption in, letter by letter, rising into place.
func _type_caption(text: String) -> void:
	_set_caption(text)
	_caption.visible_ratio = 0.0
	_caption.modulate.a = 0.0
	_caption_box.modulate.a = 1.0
	var t := create_tween().set_parallel()
	t.tween_property(_caption, "modulate:a", 1.0, 0.35)
	t.tween_property(_caption, "visible_ratio", 1.0, clampf(text.length() * 0.028, 0.8, 2.6)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _hide_caption() -> void:
	var t := create_tween()
	t.tween_property(_caption, "modulate:a", 0.0, 0.4)
	await t.finished


## *word* in a caption is drawn heavier and in gold.
func _markup(text: String) -> String:
	var parts := text.replace("[", "[lb]").split("*")
	var out := ""
	for i in parts.size():
		if i % 2 == 1:
			out += "[b][color=#%s]%s[/color][/b]" % [GOLD.to_html(false), parts[i]]
		else:
			out += parts[i]
	return out


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	# not imported yet (the editor hasn't scanned the folder): read the file
	var ff := FontFile.new()
	if FileAccess.file_exists(path) and ff.load_dynamic_font(path) == OK:
		return ff
	push_warning("DayCycle: missing font %s" % path)
	return ThemeDB.fallback_font


func _spaced(font: Font, spacing: int) -> Font:
	var v := FontVariation.new()
	v.base_font = font
	v.spacing_glyph = spacing
	return v


func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()
