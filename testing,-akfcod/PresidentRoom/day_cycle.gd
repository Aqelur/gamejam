extends Node
## Days at the desk, real proposals, and the end-of-day look at the city.
##
## Created by president_room.gd at runtime (never in the editor).
##
## A day is `room.proposals_per_day` proposals (4). The real proposals in
## PresidentRoom/proposals/*.tres (proposal_data.gd) are dealt first: every
## `start` one that hasn't been on the desk yet, plus any that an earlier
## choice unlocked. They come in a random order every game (the `first` one
## still opens it), but the ones that change the city (a caption, action,
## cutscene or city_target) are guaranteed a slot before the ending: each day
## keeps enough room for them and the stat-only proposals only get the spare
## slots. Proposals another one `requires` are dealt as early as possible so
## the follow-up still gets a day. The rest of the day is filled with the old
## placeholder papers. Stamping a real proposal changes the four stats on the
## plaque.
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
## the stage is gone again by the next morning. REPAIR / NEGLECT choices (the
## Minister of Urban Planning's) go to the Old Quarter (old_quarter_works.gd):
## approved, builders fix every crumbling building up like the rest of the
## city and it stays that way; denied, the camera stands in its empty street
## while tumbleweeds roll past. DRILL / NO_DRILL choices (the Chief
## Seismologist's town-wide drill) go to Central Park (central_park_drill.gd):
## approved, the noon sirens wail and the whole town gathers at the fountain
## plaza, more still streaming in down the promenade; denied, the plaza is
## empty but for one or two people while tumbleweeds roll across. Either way
## the caption is read aloud, and the park is back to normal the next day.
## A choice that unlocks another proposal puts it on the desk straight after,
## the same day (the day grows by one paper if it has to). A CRACKS choice
## (the Contractor's cheap concrete) swings the camera round behind the
## hospital once it has gone up and cracks spread over its back wall
## (hospital_cracks.gd); they stay there for the rest of the game.
## A TRAINING choice (the foreign rescue team's offer) goes to the fire station
## (fire_training.gd): two hose teams spray arcs of water across the apron
## while the visiting instructor looks on; gone again the next day. A
## proposal with `requires` set only turns up once that other proposal has
## been approved on an earlier day (the training needs the fire station).
## A TENTS choice (the Head of Disaster Agency's shelter camp) goes to
## Central Park's east lawn (park_tents.gd): evacuation signs spring up at
## every park gate and rows of tents pop up around an EMERGENCY SHELTER gate
## while the caption is read aloud; they stay for the rest of the game.
##
## THE ENDING. After the evening of day `room.ending_after_day` there is no
## next morning: the screen goes black, "14:32", and the big earthquake hits
## (_play_ending, earthquake_ending.gd). The ending cuts between places in the
## city at the same moment, clock ticking, each one showing what the player's
## choices did there and adding up the dead and the damage; then a summary
## card on black. Places so far: the Old Quarter (old_quarter_quake.gd), then
## the same streets twenty minutes later (police_rescue.gd): people are still
## alive under the rubble, and with the police station built its patrol cars
## go street to street dropping off officers who dig them out (and keep the
## looters away); without one only a few neighbours dig by hand. Then one
## office across town (room_quake.gd): with People's Awareness 50 or more the
## worker at the desk drops under it, covers and holds on, and crawls out
## unhurt; below that they panic and jump out of the window. Then
## Main Street, where a gas main bursts and a row of buildings catches fire
## (quake_fire.gd): with the fire station built its trucks come and put it out,
## without one the fire spreads down the row. Last, Central Park, the
## evacuation point (central_park_quake.gd): with the drill the town gathers
## there safely, without it the park stays nearly empty; with the shelter
## tents they have somewhere to sleep, without them, where will they stay?
## After everything, the hospital (hospital_quake.gd), where everyone hurt in
## the other places is brought: without one, the injured lie on its empty
## lot; with a sound one, ambulances pull into the emergency bay; with the
## Contractor's cracked one, the cracks tear wider and it holds if
## Infrastructure is 50 or more, and below that it comes down into rubble.
## room.test_ending skips the desk and plays it straight away.
##
## THE WALKOUT. If a stamp leaves Money at 0 the day ends there and then (the
## rest of its papers are dropped). Its evening plays as usual, but there is
## no next morning and no earthquake: nobody was paid for the week, and
## the town's emergency workers walk out (_play_walkout, walkout.gd). Every
## service that was built (hospital, fire station, police station) goes dark
## and gets a CLOSED sign on its door, then the president's state car slips
## out of the palace alone and quietly leaves town along the back street.
## Then a card on black with what happened, and the closing lines in
## menu/walkout_outro.tscn. room.test_walkout skips the desk and plays it straight away.
##
## THE CONTRACTOR'S TOWN. If a stamp leaves Bureaucracy at 0 (and Money is
## not also gone, which plays the walkout instead) the day ends there and
## then, the same way. Its evening plays as usual, but there is no next
## morning and no earthquake: nobody is left to enforce the rules, and the
## Contractor takes over (_play_contractor, contractor_town.gd). The camera
## drifts slowly over the town while construction fences and "COMING SOON:
## 12 FLOORS" boards grow up one by one around the empty lots, round Central
## Park and along Main Street; nobody is shown. Then a card on black with
## what happened and a tip, and a click starts the game again.
## room.test_contractor skips the desk and plays it straight away.

signal day_started(day: int)
signal day_ended(day: int)

const ProposalData := preload("res://PresidentRoom/proposal_data.gd")
const EndCutscene := preload("res://PresidentRoom/end_cutscene.gd")
const BeachConcert := preload("res://PresidentRoom/beach_concert.gd")
const OldQuarterWorks := preload("res://PresidentRoom/old_quarter_works.gd")
const CentralParkDrill := preload("res://PresidentRoom/central_park_drill.gd")
const HospitalCracks := preload("res://PresidentRoom/hospital_cracks.gd")
const FireTraining := preload("res://PresidentRoom/fire_training.gd")
const ParkTents := preload("res://PresidentRoom/park_tents.gd")
const OldQuarterQuake := preload("res://PresidentRoom/old_quarter_quake.gd")
const QuakeFire := preload("res://PresidentRoom/quake_fire.gd")
const CentralParkQuake := preload("res://PresidentRoom/central_park_quake.gd")
const PoliceRescue := preload("res://PresidentRoom/police_rescue.gd")
const RoomQuake := preload("res://PresidentRoom/room_quake.gd")
const HospitalQuake := preload("res://PresidentRoom/hospital_quake.gd")
const EarthquakeEnding := preload("res://PresidentRoom/earthquake_ending.gd")
const RainStorm := preload("res://PresidentRoom/rain_storm.gd")
const Walkout := preload("res://PresidentRoom/walkout.gd")
const ContractorTown := preload("res://PresidentRoom/contractor_town.gd")
const StreetWitness := preload("res://PresidentRoom/street_witness.gd")
const ClearShot := preload("res://PresidentRoom/clear_shot.gd")
const PROPOSALS_DIR := "res://PresidentRoom/proposals"
const CITY_SCENE := "res://City/city.tscn"
const TITLE_SCENE := "res://menu/title_screen.tscn"
const WALKOUT_OUTRO := "res://menu/walkout_outro.tscn"
const FONT_BOLD := "res://PresidentRoom/fonts/Montserrat-Bold.ttf"
const FONT_BLACK := "res://PresidentRoom/fonts/Montserrat-ExtraBold.ttf"
const SKY_FLASH := Color(0.93, 0.96, 1.0)
const GOLD := Color(1.0, 0.82, 0.36)
## Text-to-speech speed for the evening narration (1.0 = normal).
const TTS_RATE := 1.3
## Ending cards and captions sit longer than the evening. A left click passes
## the current shot; an earthquake shot speeds up instead of cutting off early,
## so the toll afterwards still matches what happened.
const ENDING_PACE := 1.45
const ENDING_LINGER := 1.05
## Ending glides that cross more than GLIDE_ARC_FROM city units arc up by
## GLIDE_ARC of the distance (at most GLIDE_ARC_MAX), over the buildings.
const GLIDE_ARC_FROM := 60.0
const GLIDE_ARC := 0.2
const GLIDE_ARC_MAX := 140.0
const ENDING_HURRY := 4.0
## Longest a building takes to rise during the evening showcase (seconds).
const EVENING_BUILD_TIME := 4.0
const QUIET_DAY := "A quiet day. Nothing you signed today changed the city."
## Soft typewriter tick under the captions. Short, so a gap keeps it from stacking.
const TYPE_CLICK := "res://PresidentRoom/audio/click.wav"
const TYPE_CLICK_DB := -8.0
const TYPE_CLICK_GAP := 0.048
## Quiet chord while the camera leaves the desk for the window.
const DAY_TRANSITION := "res://PresidentRoom/audio/day_transition.wav"
const DAY_TRANSITION_DB := -4.0

var room                     # president_room.gd (untyped: it is a @tool script)
var day := 1
## The real proposal on the paper right now, or null for a placeholder.
var current: Resource = null
## True while the end-of-day sequence is playing.
var busy := false

var _catalog: Array[Resource] = []
var _used := {}         # id -> true once it has been on the desk
var _unlocked := {}     # id -> true
var _approved := {}     # id -> true once it has been approved
var _deck: Array = []   # ProposalData or null (placeholder), in order
var _decided := 0
var _day_length := 1    # papers today: proposals_per_day, plus any follow-ups
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
var _old_quarter = null   # old_quarter_works.gd, made the first time it's needed
var _drill = null   # central_park_drill.gd while it is up
var _training = null   # fire_training.gd while it is up
var _ending: EarthquakeEnding = null   # while the ending plays
var _rain: RainStorm = null   # rain_storm.gd: rain and thunder over the ending
var _walkout = null   # walkout.gd while it plays
## Money hit 0: the day ends now and the walkout replaces the next morning.
var bankrupt := false
var _contractor = null   # contractor_town.gd while it plays
## Bureaucracy hit 0: the day ends now and the Contractor's town replaces the
## next morning (unless Money hit 0 too: then it's the walkout).
var lawless := false
var _oq_quake = null   # old_quarter_quake.gd once it has played (the rescue needs its rubble)
## Left-click while an evening event is on screen skips to the next one.
## _watching: an event (or the opening bird's-eye shot) is playing and can be
## skipped. _skip: the player clicked; every wait in the event returns at once
## until the next event starts.
var _watching := false
var _skip := false
var _voice: AudioStreamPlayer   # the narration recording playing right now
var _click: AudioStreamPlayer
var _click_stream: AudioStream
var _typing := false
var _click_heard := 0
var _click_gap := 0.0
## The earthquake ending. _hold_open: a left click passes the shot on screen.
## _advance: that click has landed and the current shot should let go.
var _in_ending := false
var _hold_open := false
var _advance := false
var _type_tween: Tween
## The player is the man in the street. Clicks must not skip the shot.
var _on_foot: StreetWitness


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _on_foot and is_instance_valid(_on_foot):
		if event is InputEventMouseMotion:
			_on_foot.add_look((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
		return
	var click := false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		click = button.pressed and button.button_index == MOUSE_BUTTON_LEFT
	if _in_ending:
		var key := event.is_action_pressed("action") or event.is_action_pressed("jump") \
				or event.is_action_pressed("ui_accept")
		if _hold_open and not _advance and (click or key):
			_advance = true
			get_viewport().set_input_as_handled()
		return
	if not _watching or _skip or not click:
		return
	_skip = true
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Start (true) or finish (false) a skippable stretch of the evening.
func _watch(on: bool) -> void:
	if on:
		_skip = false
		_watching = true
		return
	_watching = false
	if _skip:
		# cut the narration short; _skip stays set so anything still waiting
		# from the skipped event lets go too, until the next event starts
		if is_instance_valid(_voice):
			_voice.stop()
		if _tts_checked and _tts_voice != "":
			DisplayServer.tts_stop()


## Wait `time` seconds, or stop early when the player skips.
func _wait(time: float) -> void:
	var left := time
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()


## Wait for a tween to finish, or stop early when the player skips.
func _until_tween(t: Tween) -> void:
	while not _skip and t and t.is_valid() and t.is_running():
		await get_tree().process_frame


## Run a coroutine and wait for it, or stop waiting early when the player
## skips (it carries on by itself in the background).
func _until_done(job: Callable) -> void:
	var st := {"done": false}
	var runner := func() -> void:
		await job.call()
		st.done = true
	runner.call()
	while not st.done and not _skip:
		await get_tree().process_frame


## The ending is on screen. A left click can pass the shot; no prompt is shown.
func _arm_ending() -> void:
	_in_ending = true
	_hold_open = true
	_advance = false


## The click that passed the previous shot does not pass this one too.
func _next_beat() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_advance = false


func ending_next_beat() -> void:
	_next_beat()


func ending_hold(seconds: float) -> void:
	await _ending_wait(seconds)


func ending_clicked() -> bool:
	return _advance


## A reading pause. `paced` stretches it; a click ends it now.
func _ending_wait(seconds: float, paced := true) -> void:
	var left := seconds * (ENDING_PACE if paced else 1.0)
	while left > 0.0 and not _advance and is_inside_tree():
		await get_tree().process_frame
		left -= get_process_delta_time()


## Watch a quake shot for `seconds` of its own clock. A click runs the clock
## faster until that time has passed, then the next caption still gets read.
func _ending_watch(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and is_inside_tree():
		if _advance and Engine.time_scale == 1.0:
			Engine.time_scale = ENDING_HURRY
		await get_tree().process_frame
		left -= get_process_delta_time()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0


func _hurry_ending() -> void:
	if _advance and Engine.time_scale == 1.0:
		Engine.time_scale = ENDING_HURRY


func _until_tween_ending(t: Tween) -> void:
	while t and t.is_valid() and t.is_running() and not _advance and is_inside_tree():
		await get_tree().process_frame
	if _advance and t and t.is_valid():
		var guard := 0
		while t.is_running() and guard < 40:
			if not t.custom_step(2.0):
				break
			guard += 1


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
	# a new order every game; the `first` proposal still opens it
	_catalog.shuffle()
	var firsts: Array[Resource] = []
	for p in _catalog:
		if p.first:
			firsts.append(p)
	for p in firsts:
		_catalog.erase(p)
	for i in range(firsts.size() - 1, -1, -1):
		_catalog.push_front(firsts[i])


## True when a proposal shows something in the city at the end of the day (a
## caption, a city action, a cutscene or a city_target). The rest only move
## the stats.
static func _changes_city(p: Resource) -> bool:
	if p.city_target != "":
		return true
	for approved in [true, false]:
		if int(p.action(approved)) != 0 or int(p.cutscene(approved)) != 0 \
				or p.caption(approved) != "":
			return true
	return false


## True when a proposal that is still to come `requires` this one.
func _is_required(p: Resource) -> bool:
	for q in _catalog:
		if q.requires == p.id and not _used.has(q.id):
			return true
	return false


## Put together today's papers.
func _deal() -> void:
	_deck.clear()
	_today.clear()
	_decided = 0
	var n: int = maxi(1, room.proposals_per_day)
	_day_length = n

	var city_now: Array[Resource] = []   # city-changing, can turn up today
	var stats_now: Array[Resource] = []  # stat-only, can turn up today
	var city_left := 0                   # city-changing still to come, today or later
	for p in _catalog:
		if _used.has(p.id) or not (p.start or _unlocked.has(p.id)):
			continue
		var ready: bool = p.requires == "" or _approved.has(p.requires)
		# e.g. no fire station yet, no fire crew training; it can still come
		# later as long as the fire station hasn't been turned down
		var possible: bool = ready or not _used.has(p.requires)
		var city := _changes_city(p)
		if city and possible:
			city_left += 1
		if not ready:
			continue
		if city:
			city_now.append(p)
		else:
			stats_now.append(p)

	# the opening proposal first, then the ones a later proposal needs
	var front: Array[Resource] = []
	for p in city_now:
		if p.first or _is_required(p):
			front.append(p)
	for p in front:
		city_now.erase(p)
	front.sort_custom(func(a: Resource, b: Resource) -> bool: return a.first and not b.first)
	front.append_array(city_now)
	city_now = front

	# leave enough slots on the remaining days for every city-changing proposal
	var days_left: int
	if room.ending_after_day > 0:
		days_left = maxi(1, room.ending_after_day - day + 1)
	else:
		days_left = maxi(1, ceili(float(city_left + stats_now.size()) / n))
	var spare: int = maxi(0, days_left * n - city_left)
	var stat_slots: int = clampi(ceili(float(spare) / days_left), 0, n)

	for p in city_now:
		if _deck.size() >= n - stat_slots:
			break
		_deck.append(p)
	for p in stats_now:
		if _deck.size() >= n:
			break
		_deck.append(p)
	for p in city_now:   # stat-only ran out: fill up with more city ones
		if _deck.size() >= n:
			break
		if not _deck.has(p):
			_deck.append(p)

	# mix today's papers, the opening proposal stays on top
	var opener: Resource = null
	for p in _deck:
		if p.first:
			opener = p
	if opener:
		_deck.erase(opener)
	_deck.shuffle()
	if opener:
		_deck.push_front(opener)
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


## Money gauge is empty and approving this paper would spend money.
## The green stamp must not land until a later stamp brings Money back above 0.
func approve_blocked() -> bool:
	if current == null:
		return false
	var fx: Array[int] = current.effects(true)
	const MONEY := 1
	if fx.size() <= MONEY:
		return false
	return fx[MONEY] < 0 and room.get_stat(MONEY) <= 0.0


## Apply the stamp. Returns true when that was the last proposal of the day.
func on_stamped(approved: bool) -> bool:
	if approved and approve_blocked():
		return false
	if current:
		var fx: Array[int] = current.effects(approved)
		for i in fx.size():
			if fx[i] != 0:
				room.set_stat(i, room.get_stat(i) + fx[i])
		if approved:
			_approved[current.id] = true
		var u: String = current.unlocks(approved)
		if u != "":
			_unlocked[u] = true
			_follow_up(u)
		_today.append({"data": current, "approved": approved})
		current = null
	_decided += 1
	if room.get_stat(1) <= 0.0:
		bankrupt = true   # nobody can be paid: no more papers today
	if room.get_stat(3) <= 0.0:
		lawless = true    # nobody enforces the rules: no more papers today
	return bankrupt or lawless or _decided >= _day_length


## Put the proposal `id` that was just unlocked on the desk next. It takes the
## place of a placeholder paper if there is one, else the day gets one longer.
func _follow_up(id: String) -> void:
	if _used.has(id):
		return
	for p in _catalog:
		if p.id != id:
			continue
		var i := _deck.find(p)
		if i >= 0:
			_deck.remove_at(i)   # was coming later today anyway: bring it forward
		else:
			var spare := _deck.rfind(null)
			if spare >= 0:
				_deck.remove_at(spare)
			else:
				_day_length += 1
		_deck.push_front(p)
		return


# ================================================================ end of the day

func end_day() -> void:
	if busy:
		return
	busy = true
	_skip = false
	day_ended.emit(day)
	room.lock_camera(true)
	var cam: Camera3D = room.camera

	# 1. turn to the window on the left
	_play_day_transition()
	var win: Vector3 = room.left_window_centre()
	var normal: Vector3 = room.left_window_normal()
	var eye := cam.global_position
	await _move_cam(cam, Transform3D(Basis.looking_at(win - eye, Vector3.UP), eye), 0.9,
		Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	await get_tree().create_timer(0.1).timeout

	# 2. push into the glass, and flash white as the view goes through it
	var into := Transform3D(Basis.looking_at(-normal, Vector3.UP), win + normal * 0.22)
	var push := _move_cam(cam, into, 1.1, Tween.TRANS_CUBIC, Tween.EASE_IN, 38.0)
	_fade.color = Color(SKY_FLASH, 0.0)
	var f := create_tween()
	f.tween_interval(0.7)
	f.tween_property(_fade, "color:a", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
	_drift(_bird, bird_target, 4.0)
	_kicker.text = "END OF DAY %d" % _shown_day()
	_set_caption("")
	_caption_box.modulate.a = 1.0
	_show_kicker()
	var out := create_tween()
	out.tween_property(_fade, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_watch(true)   # a click here jumps straight to the first change
	await _wait(1.0)
	_watch(false)

	# 4. each change made today, one after another (click to skip to the next)
	var shown := 0
	for entry in _evening_order():
		var data: Resource = entry.data
		var approved: bool = entry.approved
		var act: int = data.action(approved)
		var play: Callable
		if act == ProposalData.CityAction.CONCERT:
			play = _play_concert.bind(data, approved)
		elif act == ProposalData.CityAction.REPAIR or act == ProposalData.CityAction.NEGLECT:
			play = _play_old_quarter.bind(data, approved)
		elif act == ProposalData.CityAction.DRILL or act == ProposalData.CityAction.NO_DRILL:
			play = _play_drill.bind(data, approved)
		elif act == ProposalData.CityAction.CRACKS:
			play = _play_cracks.bind(data, approved)
		elif act == ProposalData.CityAction.TRAINING:
			play = _play_training.bind(data, approved)
		elif act == ProposalData.CityAction.TENTS:
			play = _play_tents.bind(data, approved)
		elif data.cutscene(approved) != ProposalData.Cutscene.NONE:
			play = _play_cutscene.bind(data, approved)
		else:
			if data.city_target == "":
				continue
			if act == ProposalData.CityAction.NONE and data.caption(approved) == "":
				continue   # nothing to see (e.g. the Contractor turned away)
			var node := _city.get_node_or_null(NodePath(data.city_target)) as Node3D
			if node == null:
				push_warning("DayCycle: city target '%s' of %s not found in %s" % [data.city_target, data.id, CITY_SCENE])
				continue
			play = _play_target.bind(data, approved, node)
		if shown > 0:
			await _hide_caption()
		shown += 1
		_watch(true)
		await play.call()
		_watch(false)
	const MONEY := 1
	var broke: bool = room.get_stat(MONEY) <= 0.0
	if shown == 0 and not broke:
		_type_caption(QUIET_DAY)
		_watch(true)
		await _wait(2.5)
		_watch(false)

	# Money at 0 ends the run: walkout, not the next morning and not the quake.
	# Bureaucracy at 0 ends it as the Contractor's town, unless the money is gone too.
	if bankrupt or broke:
		await _play_walkout()
		return
	if lawless:
		await _play_contractor()
		return
	if room.ending_after_day > 0 and day >= room.ending_after_day:
		await _play_ending()
		return
	await _back_to_office()


## A plain change at a spot in the city: fly there, show the caption and, for
## a BUILD, watch it go up.
func _play_target(data: Resource, approved: bool, node: Node3D) -> void:
	await _fly_to(node)
	_type_caption(data.caption(approved))
	if data.action(approved) == ProposalData.CityAction.BUILD and node.has_method("build") \
			and not node.is_built():
		node.set("build_time", minf(float(node.get("build_time")), EVENING_BUILD_TIME))
		node.build()
		var limit := float(node.get("build_time")) + 3.0
		var waited := 0.0
		while not node.is_built() and waited < limit and not _skip:
			await get_tree().process_frame
			waited += get_process_delta_time()
		await _wait(1.6)   # cheer, sign, jingle
	else:
		await _wait(2.8)


## Desk days stay 1, 2, 3. The screen counts them a week apart: 1, 8, 15.
func _shown_day() -> int:
	return 1 + (day - 1) * 7


func _back_to_office() -> void:
	# fade to black, back at the desk, next day
	_fade.color = Color(0, 0, 0, _fade.color.a)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.5)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, 0.4)
	_fade_out_evening(0.5)
	await t.finished
	_clear_evening()
	if _city:
		_show_city(false)
	room.lock_camera(false)
	day += 1
	_deal()
	_day_label.text = "DAY %d" % _shown_day()
	_day_label.modulate.a = 0.0
	_day_label.visible = true
	var d := create_tween()
	d.tween_property(_day_label, "modulate:a", 1.0, 0.35)
	d.tween_interval(0.6)
	d.tween_property(_fade, "color:a", 0.0, 0.6)
	d.parallel().tween_property(_day_label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	await d.finished
	_day_label.visible = false
	busy = false
	day_started.emit(day)


func _fade_out_evening(time: float) -> void:
	if _concert:
		_concert.fade_out(time)
	if _drill:
		_drill.fade_out(time)
	if _training:
		_training.fade_out(time)


## Tonight's one-off scenes go away; what was built stays.
func _clear_evening() -> void:
	if _drill:
		_drill.close()   # everyone goes home
		_drill = null
	if _training:
		_training.close()   # hoses rolled up, crews back inside
		_training = null
	if _concert:
		_concert.close()   # the stage comes down overnight
		_concert = null
	if _old_quarter:
		_old_quarter.clear_transients()   # builders go home, tumbleweeds gone
	_kill(_orbit)


# ================================================================ the ending

## Testing: skip the desk and play the ending now, as if `approved_ids` had
## been approved (president_room.gd test_ending / test_approved).
func start_ending_now(approved_ids: Array) -> void:
	if busy:
		return
	busy = true
	if await _skip_to_city(approved_ids):
		await _play_ending()


## Testing: skip the desk and play the walkout now, with Money at 0 and
## `approved_ids` approved (president_room.gd test_walkout / test_approved).
func start_walkout_now(approved_ids: Array) -> void:
	if busy:
		return
	busy = true
	room.set_stat(1, 0.0, false)
	bankrupt = true
	if await _skip_to_city(approved_ids):
		await _play_walkout()


## Testing: skip the desk and play the Contractor's town now, with
## Bureaucracy at 0 and `approved_ids` approved (president_room.gd
## test_contractor / test_approved).
func start_contractor_now(approved_ids: Array) -> void:
	if busy:
		return
	busy = true
	room.set_stat(3, 0.0, false)
	lawless = true
	if await _skip_to_city(approved_ids):
		await _play_contractor()


## For the test shortcuts: straight to the city on black, with what earlier
## evenings would have done to it for `approved_ids`. False if there's no city.
func _skip_to_city(approved_ids: Array) -> bool:
	room.lock_camera(true)
	for id in approved_ids:
		_approved[String(id)] = true
		_used[String(id)] = true
	_fade.color = Color(0, 0, 0, 1)
	if not _ensure_city():
		_fade.color = Color(0, 0, 0, 0)
		room.lock_camera(false)
		busy = false
		return false
	_show_city(true)
	# what earlier evenings would have done to the city
	if _approved.has(OldQuarterQuake.BRACING_ID):
		var q = _ensure_old_quarter()
		if q and not q.repaired:
			q.repair_now()
			await get_tree().create_timer(OldQuarterWorks.POP_TIME + 0.3).timeout
	if _approved.has(QuakeFire.STATION_ID):
		var station := _city.get_node_or_null(QuakeFire.STATION)
		if station and station.has_method("build") and not station.is_built():
			station.set("build_time", 2.0)
			station.build()
			var waited := 0.0
			while not station.is_built() and waited < 6.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
	if _approved.has(PoliceRescue.POLICE_ID):
		var police := _city.get_node_or_null(PoliceRescue.STATION)
		if police and police.has_method("build") and not police.is_built():
			police.set("build_time", 2.0)
			police.build()
			var waited := 0.0
			while not police.is_built() and waited < 6.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
	if _approved.has(HospitalQuake.HOSPITAL_ID):
		var hosp := _city.get_node_or_null(HospitalQuake.HOSPITAL) as Node3D
		if hosp and hosp.has_method("build") and not hosp.is_built():
			hosp.set("build_time", 2.0)
			hosp.build()
			var waited := 0.0
			while not hosp.is_built() and waited < 6.0:
				await get_tree().process_frame
				waited += get_process_delta_time()
		if hosp and _approved.has(HospitalQuake.CRACKS_ID) and hosp.get_node_or_null("Cracks") == null:
			var cracks = HospitalCracks.new()
			hosp.add_child(cracks)
			cracks.setup(hosp)
			cracks.show_now()   # as if they had spread on an earlier evening
	if _approved.has(CentralParkQuake.TENTS_ID):
		var park := _city.get_node_or_null(ParkTents.PARK) as Node3D
		if park and park.get_node_or_null("ShelterCamp") == null:
			var camp = ParkTents.new()
			park.add_child(camp)
			camp.setup(park)
			camp.finish()   # already standing, as if put up on an earlier evening
	return true


## What the player did, for earthquake_ending.gd.
func _ending_choices() -> Dictionary:
	return {
		"approved": _approved.duplicate(),
		"awareness": room.get_stat(0),
		"money": room.get_stat(1),
		"infrastructure": room.get_stat(2),
		"bureaucracy": room.get_stat(3),
	}


## The big one. Black screen, the time, then the quake seen in one place after
## another (same moment, the clock rewinding each time), each with its toll,
## then everything added up. Captions and cards stay up longer than the
## evening. A left click passes the shot on screen; a quake shot runs
## faster instead of stopping halfway. The closing lines follow the summary.
func _play_ending() -> void:
	_watch(false)
	_arm_ending()
	# 1. out to black, tonight's scenes cleared away
	_fade.color = Color(0, 0, 0, _fade.color.a)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 1.05)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, 0.6)
	_fade_out_evening(0.8)
	await _until_tween_ending(t)
	_clear_evening()
	_set_caption("")
	_kicker.text = ""
	if not _ensure_city():
		_in_ending = false
		_hold_open = false
		await _back_to_office()
		return
	_show_city(true)
	# dark sky, rain and thunder for the whole ending (set while still black)
	_rain = RainStorm.new()
	_rain.name = "RainStorm"
	_city.add_child(_rain)
	_rain.setup(_city, _city_cam)

	# Launch with `-- street` for the calm street, or `-- run` for the quake run.
	var args := OS.get_cmdline_user_args()
	var street := args.has("street") or args.has("run")
	# 2. the time, on black
	if not street:
		_next_beat()
		_day_label.text = "THE NEXT DAY\n14:32"
		_day_label.modulate.a = 0.0
		_day_label.visible = true
		var d_in := create_tween()
		d_in.tween_property(_day_label, "modulate:a", 1.0, 0.8)
		await _until_tween_ending(d_in)
		await _ending_wait(2.0)
		var d_out := create_tween()
		d_out.tween_property(_day_label, "modulate:a", 0.0, 0.65)
		await _until_tween_ending(d_out)
		_day_label.visible = false

	_ending = EarthquakeEnding.new()
	_ending.name = "EarthquakeEnding"
	add_child(_ending)
	var tile := 26.926893
	var q = _ensure_old_quarter()
	if q:
		tile = q._tile
	_ending.setup(_ending_choices(), _ui, _kicker, _city_cam, tile, _font_bold, _font_black)

	# 3. one place after another, all at the same moment. Each takes the
	# ending, shows its place and adds its toll. Add the next places here
	# (before the hospital: it counts the injured from the places before it).
	var places: Array[Callable] = [_play_quake_old_quarter, _play_quake_rescue, _play_quake_room, _play_quake_fire,
		_play_quake_park, _play_quake_hospital]
	# Launch with `-- fire`, `-- street` or `-- run` to open that shot on its own.
	if OS.get_cmdline_user_args().has("fire"):
		places = [_play_quake_fire]
	elif street:
		places = [_play_quake_old_quarter]
	for play in places:
		await play.call(_ending)

	# 4. everything added up, then the dead laid out in Central Park; the
	# closing lines follow on their own
	_kill(_orbit)
	_ending.set_city(_city, _fade)
	await _ending.show_summary()


# ================================================================ the walkout

## Money is gone. One week later, every service that was built shuts its
## doors, then the president's car slips out of town; a card on black says
## what happened, then the closing lines in menu/walkout_outro.tscn.
## See walkout.gd.
func _play_walkout() -> void:
	_watch(false)
	# 1. out to black, tonight's scenes cleared away
	_fade.color = Color(0, 0, 0, _fade.color.a)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.8)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, 0.5)
	_fade_out_evening(0.6)
	await t.finished
	_clear_evening()
	_set_caption("")
	_kicker.text = ""
	if _ensure_city():
		_show_city(true)
		_walkout = Walkout.new()
		_walkout.name = "Walkout"
		_city.add_child(_walkout)
		_walkout.setup(_city, _font_bold, _font_black)
		await _walkout.settle_buildings()

		# 2. the time, on black
		_day_label.text = "ONE WEEK LATER"
		_day_label.modulate.a = 0.0
		_day_label.visible = true
		var d := create_tween()
		d.tween_property(_day_label, "modulate:a", 1.0, 0.6)
		d.tween_interval(1.4)
		d.tween_property(_day_label, "modulate:a", 0.0, 0.5)
		await d.finished
		_day_label.visible = false

		# 3. each service that was built goes dark and shuts its doors
		for place in _walkout.closed_places():
			var shot: Array = _walkout.place_shot(place)
			_kill(_orbit)
			_city_cam.look_at_from_position(shot[0], shot[1], Vector3.UP)
			_glide(shot[0], shot[1], 0.05, shot[2])
			_kicker.text = _walkout.kicker(place)
			_caption_box.modulate.a = 1.0
			_show_kicker()
			_fade_in(0.7)
			_watch(true)
			await _wait(1.4)
			await _until_done(_walkout.close.bind(place))
			await _wait(1.8)
			_watch(false)
			_walkout.close_now(place)
			await _cut_to_black(0.5)

		# 4. one car leaves the palace, alone, and quietly leaves town
		if _walkout.prepare_car():
			var start: Array = _walkout.car_shot()
			_kill(_orbit)
			_city_cam.look_at_from_position(start[0], start[1], Vector3.UP)
			_kicker.text = _walkout.car_kicker()
			_caption_box.modulate.a = 1.0
			_show_kicker()
			_fade_in(0.8)
			_watch(true)
			await _wait(1.2)
			_walkout.drive(_city_cam)
			while not _walkout.is_away() and not _skip:
				await get_tree().process_frame
			_watch(false)
			var out := create_tween()
			out.tween_property(_fade, "color:a", 1.0, 1.4)
			out.parallel().tween_property(_caption_box, "modulate:a", 0.0, 1.0)
			await out.finished
			_walkout.stop_car()
	else:
		_walkout = Walkout.new()
		_walkout.name = "Walkout"
		add_child(_walkout)
		_walkout.setup(null, _font_bold, _font_black)

	# 5. what happened. A click skips the writing. Then the closing lines.
	_kill(_orbit)
	_kicker.text = ""
	_watch(true)
	await _until_done(_walkout.show_card.bind(_ui))
	_walkout.reveal_card()
	await _narrate(Walkout.TEXT, null)
	_watch(false)
	_skip = false
	await _open_walkout_outro()


## The closing lines in menu/walkout_outro.tscn. That scene already opens on
## black for the same beat as the earthquake outro, so the card is not faded
## out first: doing both left the screen empty twice.
func _open_walkout_outro() -> void:
	if is_instance_valid(_voice):
		_voice.stop()
	if _tts_checked and _tts_voice != "":
		DisplayServer.tts_stop()
	get_tree().change_scene_to_file(WALKOUT_OUTRO)


# ================================================================ the contractor's town

## Bureaucracy is gone. The weeks after, the camera drifts slowly over the
## town while the Contractor's fences and COMING SOON boards grow up one by
## one; a card on black says what happened and what to learn from it. The
## game ends here: a click starts the scene again. See contractor_town.gd.
func _play_contractor() -> void:
	_watch(false)
	# 1. out to black, tonight's scenes cleared away
	_fade.color = Color(0, 0, 0, _fade.color.a)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.8)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, 0.5)
	_fade_out_evening(0.6)
	await t.finished
	_clear_evening()
	_set_caption("")
	_kicker.text = ""
	_contractor = ContractorTown.new()
	_contractor.name = "ContractorTown"
	if _ensure_city():
		_show_city(true)
		_city.add_child(_contractor)
		_contractor.setup(_city, _font_bold, _font_black)
	else:
		add_child(_contractor)
		_contractor.setup(null, _font_bold, _font_black)

	if _contractor.has_sites():
		# 2. the time, on black
		_day_label.text = "THE WEEKS THAT FOLLOWED"
		_day_label.modulate.a = 0.0
		_day_label.visible = true
		var d := create_tween()
		d.tween_property(_day_label, "modulate:a", 1.0, 0.6)
		d.tween_interval(1.4)
		d.tween_property(_day_label, "modulate:a", 0.0, 0.5)
		await d.finished
		_day_label.visible = false

		# 3. slowly over the town; fences and boards grow up as it passes
		var start: Array = _contractor.start_shot()
		_kill(_orbit)
		_city_cam.look_at_from_position(start[0], start[1], Vector3.UP)
		var on_part := func(text: String) -> void:
			_kicker.text = text
			_caption_box.modulate.a = 1.0
			_show_kicker()
		_contractor.kicker_changed.connect(on_part)
		_fade_in(0.8)
		_watch(true)
		_contractor.fly(_city_cam)
		while not _contractor.is_done() and not _skip:
			await get_tree().process_frame
		_watch(false)
		_contractor.finish()
		_contractor.kicker_changed.disconnect(on_part)
		var out := create_tween()
		out.tween_property(_fade, "color:a", 1.0, 1.4)
		out.parallel().tween_property(_caption_box, "modulate:a", 0.0, 1.0)
		await out.finished

	# 4. what happened, and what to take from it; a click starts again
	_kill(_orbit)
	_kicker.text = ""
	await _contractor.show_card(_ui)
	_skip = false
	await _narrate(ContractorTown.TEXT, null)
	await _contractor.show_tip()
	await _contractor.wait_restart()


## Fade in from black on the city camera, wherever it now is.
func _fade_in(time := 0.6) -> void:
	var dur := time * (ENDING_PACE if _in_ending else 1.0)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Cut to black between places.
func _cut_to_black(time := 0.5) -> void:
	var dur := time * (ENDING_PACE if _in_ending else 1.0)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, dur)
	t.parallel().tween_property(_caption_box, "modulate:a", 0.0, dur * 0.8)
	if _in_ending:
		await _until_tween_ending(t)
		if _advance:
			_fade.color.a = 1.0
			_caption_box.modulate.a = 0.0
	else:
		await t.finished


## The Old Quarter: down in its main street at lunchtime, then the ground goes.
## For a few seconds the camera is a person standing in the street: they walk
## and look while the buildings fall and people run. Then that same camera
## rises over the quarter (old_quarter_quake.gd): unbraced, it crumbles to
## dust with nearly everyone inside; braced, it shakes and mostly stands.
## Then the toll counts up on screen.
func _play_quake_old_quarter(ending: EarthquakeEnding) -> void:
	var works = _ensure_old_quarter()
	var oq = OldQuarterQuake.new()
	oq.name = "OldQuarterQuake"
	_city.add_child(oq)
	if works == null or not oq.setup(_city, works, ending):
		push_warning("DayCycle: no Old Quarter in %s, skipping it in the ending" % CITY_SCENE)
		oq.queue_free()
		return
	_oq_quake = oq

	# `-- run` drops into the street as the quake hits, so the run can be tried.
	if not OS.get_cmdline_user_args().has("run"):
		# 1. a calm street
		_next_beat()
		var low: Array = works.street_shot()
		_kill(_orbit)
		_city_cam.look_at_from_position(low[0], low[1], Vector3.UP)
		_glide(low[0], low[1], 0.05, low[2])
		ending.begin_place("Old Quarter", 0.0)
		_caption_box.modulate.a = 1.0
		_show_kicker()
		_fade_in(0.8)
		await _ending_wait(0.8)
		var intro: String = oq.intro_line()
		_type_caption(intro)
		ending.rumble(0.08, 3.0)   # a faint tremor first
		await _narrate(intro.replace("*", ""), null)
		await _ending_wait(ENDING_LINGER)

	# 2. a man in the street watches the walls fall and the people run,
	#    then this same camera rises over the quarter
	_next_beat()
	await _hide_caption()
	ending.kick(0.8)
	ending.rumble(1.0, OldQuarterQuake.SHAKE_TIME)
	oq.start()
	var eye: Array = works.witness_shot()
	if OS.get_cmdline_user_args().has("run"):
		_kill(_orbit)
		ending.begin_place("Old Quarter", 0.0)
		_caption_box.modulate.a = 0.0
		_city_cam.look_at_from_position(eye[0], eye[1], Vector3.UP)
		_fade_in(0.35)
	else:
		_glide(eye[0], eye[1], 0.55)
	await _walk_the_street(eye[0], eye[1], float(works._street_y), float(works._tile))

	var wide: Array = _clear(works.district_shot())
	_glide(wide[0], wide[1], 3.2, wide[2])
	var crash := 0.0
	var left: float = oq.settle_time() - 1.2
	while left > 0.0 and not oq.is_done():
		_hurry_ending()
		await get_tree().process_frame
		var dt := get_process_delta_time()
		left -= dt
		crash -= dt
		if crash <= 0.0 and oq.razed > 0:
			ending.kick(randf_range(0.15, 0.35) * (0.4 + oq.razed_share()))
			crash = randf_range(0.35, 0.9)
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0

	# 3. the dust settles: what happened, and what it cost
	_next_beat()
	var line: String = oq.headline()
	_type_caption(line)
	var r: Dictionary = oq.result()
	ending.add_result(r)
	ending.show_tally(r)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(1.8)
	_next_beat()
	ending.hide_tally()
	await _cut_to_black(0.6)
	ending.end_place()


## Large W A S D keys and a mouse, shown with the street hint, then freed.
func _move_hint() -> Control:
	var root := Control.new()
	root.name = "MoveHint"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = -48
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 72)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	var keys := VBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 10)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(keys)
	var top := CenterContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_keycap("W"))
	keys.add_child(top)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_child(bottom)
	for letter in ["A", "S", "D"]:
		bottom.add_child(_keycap(letter))

	row.add_child(_mouse_icon())
	return root


func _keycap(letter: String) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(104, 104)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	box.border_color = GOLD
	box.set_border_width_all(4)
	box.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = letter
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font_black)
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)
	return panel


func _mouse_icon() -> Control:
	var mouse := Panel.new()
	mouse.custom_minimum_size = Vector2(92, 140)
	mouse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	body.border_color = GOLD
	body.set_border_width_all(4)
	body.corner_radius_top_left = 42
	body.corner_radius_top_right = 42
	body.corner_radius_bottom_left = 36
	body.corner_radius_bottom_right = 36
	mouse.add_theme_stylebox_override("panel", body)
	var split := ColorRect.new()
	split.color = GOLD
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.position = Vector2(44, 16)
	split.size = Vector2(4, 52)
	mouse.add_child(split)
	var wheel := Panel.new()
	wheel.custom_minimum_size = Vector2(16, 28)
	wheel.position = Vector2(38, 62)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wheel_box := StyleBoxFlat.new()
	wheel_box.bg_color = GOLD
	wheel_box.set_corner_radius_all(6)
	wheel.add_theme_stylebox_override("panel", wheel_box)
	mouse.add_child(wheel)
	return mouse


## The man in the street. A short hint, then walk and look, then hand the
## camera back where it is.
func _walk_the_street(eye: Vector3, look: Vector3, ground_y: float, tile: float) -> void:
	_kill(_orbit)
	Engine.time_scale = 1.0
	_next_beat()
	_caption_box.modulate.a = 1.0
	var hint := _move_hint()
	_ui.add_child(hint)
	hint.modulate.a = 0.0
	var hint_in := create_tween()
	hint_in.tween_property(hint, "modulate:a", 1.0, 0.25)
	_type_caption("WASD to move. Mouse to look.")
	await _ending_wait(2.2, false)
	await _hide_caption()
	if is_instance_valid(hint):
		var hint_out := create_tween()
		hint_out.tween_property(hint, "modulate:a", 0.0, 0.2)
		await hint_out.finished
		hint.queue_free()
	if not is_inside_tree():
		return
	var man: StreetWitness = StreetWitness.new()
	man.name = "StreetWitness"
	_on_foot = man
	man.setup(_city, _city_cam, eye, look, ground_y, tile)
	var was := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var left := StreetWitness.SECONDS
	while left > 0.0 and is_instance_valid(man) and is_inside_tree():
		Engine.time_scale = 1.0
		await get_tree().process_frame
		left -= get_process_delta_time()
	Input.mouse_mode = was
	if is_instance_valid(man):
		man.finish()
	_on_foot = null
	Engine.time_scale = 1.0


## Back in the Old Quarter twenty minutes later (police_rescue.gd), among the
## rubble the quake just left. People are still alive under it. With the
## police station built, patrol cars come down the streets with sirens and
## lights, stop at pile after pile and drop off officers who dig people out;
## without one only a few neighbours dig by hand, people wave from the rubble
## and looters run off with boxes. Then the toll of those who were trapped.
func _play_quake_rescue(ending: EarthquakeEnding) -> void:
	var pr = PoliceRescue.new()
	pr.name = "PoliceRescue"
	_city.add_child(pr)
	if _oq_quake == null or not pr.setup(_city, _oq_quake, ending):
		pr.queue_free()   # nobody trapped (or no Old Quarter): nothing to show
		return

	# 1. high over the ruins, the clock twenty minutes on
	_next_beat()
	var wide: Array = _clear(pr.wide_shot())
	_kill(_orbit)
	_city_cam.look_at_from_position(wide[0], wide[1], Vector3.UP)
	_glide(wide[0], wide[1], 0.05, wide[2])
	ending.begin_place("Old Quarter", PoliceRescue.LATER)
	_caption_box.modulate.a = 1.0
	_show_kicker()
	_fade_in(0.8)
	pr.start()
	await _ending_wait(0.7)
	var line: String = pr.later_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)

	# 2. down by the nearest pile while the digging goes on
	_next_beat()
	await _hide_caption()
	var close: Array = _clear(pr.site_shot())
	_glide(close[0], close[1], 2.4, close[2])
	await _ending_watch(1.4)
	_next_beat()
	line = pr.work_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)
	while not pr.is_done():
		_hurry_ending()
		await get_tree().process_frame
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	await _ending_wait(0.9)

	# 3. how many came out alive
	_next_beat()
	await _hide_caption()
	line = pr.headline()
	_type_caption(line)
	var r: Dictionary = pr.result()
	ending.add_result(r)
	ending.show_tally(r)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(1.8)
	_next_beat()
	ending.hide_tally()
	pr.quiet(0.6)
	await _cut_to_black(0.6)
	ending.end_place()


## One office across town at the same moment (room_quake.gd): a worker at
## their desk on the third floor. With People's Awareness 50 or more they drop
## under the desk, cover and hold on while the books and the ceiling lamp come
## down, and crawl out unhurt once it stops. Below that they panic, run for the
## window and jump; cut to the street, where they lie on the pavement under a
## building that never fell. Narration only: it adds nothing to the toll.
func _play_quake_room(ending: EarthquakeEnding) -> void:
	var rq = RoomQuake.new()
	rq.name = "RoomQuake"
	_city.add_child(rq)
	if not rq.setup(ending):
		rq.queue_free()
		return
	rq.shattered.connect(func() -> void: ending.kick(0.35))
	rq.crashed.connect(func() -> void: ending.kick(0.45))
	if _rain:
		_rain.set_indoors(true)   # inside the office: no drops, rain muffled

	# 1. lunchtime at the desk
	_next_beat()
	var calm: Array = rq.calm_shot()
	_kill(_orbit)
	_city_cam.look_at_from_position(calm[0], calm[1], Vector3.UP)
	_glide(calm[0], calm[1], 0.05, calm[2])
	ending.begin_place("Office Block", 0.0)
	_caption_box.modulate.a = 1.0
	_show_kicker()
	_fade_in(0.8)
	await _ending_wait(0.8)
	var line: String = rq.intro_line()
	_type_caption(line)
	ending.rumble(0.08, 3.0)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)

	# 2. the ground goes: under the desk, or up and running
	_next_beat()
	await _hide_caption()
	ending.kick(0.8)
	ending.rumble(1.0, RoomQuake.SHAKE_TIME)
	rq.quake()
	var shot: Array = rq.quake_shot()
	_glide(shot[0], shot[1], 1.6, shot[2])
	await _ending_watch(1.2)
	_next_beat()
	line = rq.react_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)
	var left: float = RoomQuake.SHAKE_TIME + 4.0
	while left > 0.0 and not rq.is_done():
		_hurry_ending()
		await get_tree().process_frame
		left -= get_process_delta_time()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	await _ending_wait(0.6)

	# 3. afterwards: out from under the desk, or down on the pavement
	_next_beat()
	await _hide_caption()
	if rq.aware:
		rq.recover()
		var after: Array = rq.after_shot()
		_glide(after[0], after[1], 1.8, after[2])
	else:
		await _cut_to_black(0.5)
		if _rain:
			_rain.set_indoors(false)   # down on the street: out in the rain
		var street: Array = _clear(rq.street_shot())
		_kill(_orbit)
		_city_cam.look_at_from_position(street[0], street[1], Vector3.UP)
		_glide(street[0], street[1], 0.05, street[2])
		_caption_box.modulate.a = 1.0
		_fade_in(0.6)
	await _ending_wait(0.8)
	line = rq.after_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(1.8)
	_next_beat()
	await _cut_to_black(0.6)
	if _rain:
		_rain.set_indoors(false)
	ending.end_place()
	rq.queue_free()


## Main Street: the same moment across town (quake_fire.gd). Down on the road
## by an old row of buildings, the ground goes, a gas main bursts and the
## corner building catches, then the one next door. Cut to minutes later: with
## the fire station built, its two trucks come down the road with sirens and
## lights and put it out (the narration counts what they saved); without one
## nobody comes and the fire takes the whole row. Then the toll.
func _play_quake_fire(ending: EarthquakeEnding) -> void:
	var mf = QuakeFire.new()
	mf.name = "QuakeFire"
	_city.add_child(mf)
	if not mf.setup(_city, ending):
		push_warning("DayCycle: no Main Street in %s, skipping the fire in the ending" % CITY_SCENE)
		mf.queue_free()
		return
	mf.burst.connect(func() -> void: ending.kick(0.7))

	# 1. a busy street at lunchtime
	_next_beat()
	var low: Array = _clear(mf.street_shot(), mf.subjects())
	_kill(_orbit)
	_city_cam.look_at_from_position(low[0], low[1], Vector3.UP)
	_glide(low[0], low[1], 0.05, low[2])
	ending.begin_place("Main Street", 0.0)
	_caption_box.modulate.a = 1.0
	_show_kicker()
	_fade_in(0.8)
	await _ending_wait(0.8)
	var intro: String = mf.intro_line()
	_type_caption(intro)
	ending.rumble(0.08, 3.0)
	await _narrate(intro.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)

	# 2. the ground goes; the gas main bursts and the fire takes hold
	_next_beat()
	await _hide_caption()
	ending.kick(0.8)
	ending.rumble(1.0, QuakeFire.SHAKE_TIME)
	mf.start()
	await _ending_watch(QuakeFire.SHAKE_TIME + 0.4)
	_next_beat()
	var line: String = mf.fire_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(0.75)

	# 3. minutes later: the trucks come, or nobody does
	_next_beat()
	await _cut_to_black(0.5)
	mf.skip_ahead()
	var wide: Array = _clear(mf.wide_shot(), mf.subjects())
	_kill(_orbit)
	_city_cam.look_at_from_position(wide[0], wide[1], Vector3.UP)
	_glide(wide[0], wide[1], 0.05, wide[2])
	ending.begin_place("Main Street", QuakeFire.LATER)
	_caption_box.modulate.a = 1.0
	_fade_in(0.6)
	await _ending_wait(0.6)
	if mf.fire_force:
		mf.call_crews()
	else:
		mf.let_it_burn()
	line = mf.later_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)
	var left := 16.0
	while left > 0.0 and not mf.is_done():
		_hurry_ending()
		await get_tree().process_frame
		left -= get_process_delta_time()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	await _ending_wait(0.8)

	# 4. what it cost (and what the crews saved)
	_next_beat()
	await _hide_caption()
	line = mf.headline()
	_type_caption(line)
	var r: Dictionary = mf.result()
	ending.add_result(r)
	ending.show_tally(r)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(1.8)
	_next_beat()
	ending.hide_tally()
	mf.quiet(0.6)
	await _cut_to_black(0.6)
	ending.end_place()


## Central Park, the evacuation point (central_park_quake.gd). Lunchtime, a
## few people by the fountain; the ground goes and they drop and cover, safe
## out in the open. Cut to minutes later: with the drill the whole town has
## walked here and the plaza is packed; without it hardly anyone came. Then
## the night ahead: the camera goes on to the shelter tents if they were put
## up (filling up, or standing empty), and the toll's footnote says whether
## there is enough to last, or where everyone will stay.
func _play_quake_park(ending: EarthquakeEnding) -> void:
	# the rain belongs to the quake and the fire only: it stops here (still black)
	if _rain:
		_rain.stop()
	var pq = CentralParkQuake.new()
	pq.name = "CentralParkQuake"
	_city.add_child(pq)
	if not pq.prepare(_city, ending):
		push_warning("DayCycle: no %s in %s, skipping it in the ending" % [CentralParkQuake.PARK, CITY_SCENE])
		pq.queue_free()
		return

	# 1. a quiet lunchtime by the fountain
	_next_beat()
	pq.start_calm()
	var low: Array = _clear(pq.empty_shot())
	_kill(_orbit)
	_city_cam.look_at_from_position(low[0], low[1], Vector3.UP)
	_glide(low[0], low[1], 0.05, low[2])
	ending.begin_place("Central Park", 0.0)
	_caption_box.modulate.a = 1.0
	_show_kicker()
	_fade_in(0.8)
	await _ending_wait(0.8)
	var line: String = pq.intro_line()
	_type_caption(line)
	ending.rumble(0.08, 3.0)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)

	# 2. the ground goes: everyone drops and covers, nothing falls on them
	_next_beat()
	await _hide_caption()
	ending.kick(0.8)
	ending.rumble(1.0, CentralParkQuake.SHAKE_TIME)
	pq.quake()
	await _ending_watch(CentralParkQuake.SHAKE_TIME + 0.4)
	_next_beat()
	line = pq.shake_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(0.9)

	# 3. minutes later: the town is here, or it isn't
	_next_beat()
	await _cut_to_black(0.5)
	pq.skip_ahead()
	var wide: Array = _clear(pq.drill_shot())
	_kill(_orbit)
	_city_cam.look_at_from_position(wide[0], wide[1], Vector3.UP)
	_glide(wide[0], wide[1], 0.05, wide[2])
	ending.begin_place("Central Park", CentralParkQuake.LATER)
	_caption_box.modulate.a = 1.0
	_fade_in(0.6)
	await _ending_wait(0.6)
	pq.duck(true)
	line = pq.later_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	pq.duck(false)
	await _ending_wait(1.15)

	# 4. the night ahead: over to the tents if there are any, then the toll
	_next_beat()
	await _hide_caption()
	if pq.tents:
		var shot: Array = _clear(pq.camp_shot())
		await _glide(shot[0], shot[1], 2.2, shot[2])
	line = pq.headline()
	_type_caption(line)
	var r: Dictionary = pq.result()
	ending.add_result(r)
	ending.show_tally(r)
	pq.duck(true)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(2.2)
	_next_beat()
	ending.hide_tally()
	pq.fade_out(0.6)
	await _cut_to_black(0.6)
	pq.close()
	ending.end_place()


## The hospital, last (hospital_quake.gd), where the injured from everywhere
## else are brought. Lunchtime: the empty lot, or the hospital (from behind,
## on the cracks, if the Contractor skimped). The ground goes: nothing to fall,
## or it sways and holds, or the cracks tear wider and it holds (Infrastructure
## 50+), or they split open and it comes down. Cut to half an hour later: the
## injured laid out on the lot or by the rubble with nowhere to go, or the
## ambulances pulling into the emergency bay. Then the toll.
func _play_quake_hospital(ending: EarthquakeEnding) -> void:
	var hq = HospitalQuake.new()
	hq.name = "HospitalQuake"
	_city.add_child(hq)
	if not hq.prepare(_city, ending):
		push_warning("DayCycle: no %s in %s, skipping the hospital in the ending" % [HospitalQuake.HOSPITAL, CITY_SCENE])
		hq.queue_free()
		return
	hq.fell.connect(func() -> void: ending.kick(0.9))

	# 1. lunchtime at the Civic Center
	_next_beat()
	var calm: Array = _clear(hq.calm_shot(), hq.subjects())
	_kill(_orbit)
	_city_cam.look_at_from_position(calm[0], calm[1], Vector3.UP)
	_glide(calm[0], calm[1], 0.05, calm[2])
	ending.begin_place("Civic Center", 0.0)
	_caption_box.modulate.a = 1.0
	_show_kicker()
	_fade_in(0.8)
	await _ending_wait(0.8)
	var line: String = hq.intro_line()
	_type_caption(line)
	ending.rumble(0.08, 3.0)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)

	# 2. the ground goes; the camera pulls back to watch it hold, or fall
	_next_beat()
	await _hide_caption()
	ending.kick(0.8)
	ending.rumble(1.0, OldQuarterQuake.SHAKE_TIME)
	hq.quake()
	await _ending_watch(1.0)
	var wide: Array = _clear(hq.quake_shot(), hq.subjects())
	_glide(wide[0], wide[1], 3.2, wide[2])
	var left: float = hq.settle_time()
	while left > 0.0 and not hq.is_done():
		_hurry_ending()
		await get_tree().process_frame
		left -= get_process_delta_time()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_next_beat()
	line = hq.shake_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(0.9)

	# 3. half an hour later: the injured, and somewhere to take them or not
	_next_beat()
	await _cut_to_black(0.5)
	hq.skip_ahead()
	var later: Array = _clear(hq.later_shot(), hq.subjects())
	_kill(_orbit)
	_city_cam.look_at_from_position(later[0], later[1], Vector3.UP)
	_glide(later[0], later[1], 0.05, later[2])
	ending.begin_place("Civic Center", HospitalQuake.LATER)
	_caption_box.modulate.a = 1.0
	_fade_in(0.6)
	await _ending_wait(0.6)
	hq.arrive()
	line = hq.later_line()
	_type_caption(line)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(ENDING_LINGER)
	var wait := 10.0
	while wait > 0.0 and not hq.arrived():
		_hurry_ending()
		await get_tree().process_frame
		wait -= get_process_delta_time()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	await _ending_wait(0.95)

	# 4. what it cost
	_next_beat()
	await _hide_caption()
	line = hq.headline()
	_type_caption(line)
	var r: Dictionary = hq.result()
	ending.add_result(r)
	ending.show_tally(r)
	await _narrate(line.replace("*", ""), null)
	await _ending_wait(2.2)
	_next_beat()
	ending.hide_tally()
	hq.quiet(0.6)
	await _cut_to_black(0.6)
	ending.end_place()


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


## The Influencer's night on the beach, kept short (about 7 seconds): night
## falls while the camera flies in on a quick build-up, the drop hits about
## two seconds in (lasers, confetti, fireworks) and the camera cranes back.
## The caption is read out once over the whole thing.
func _play_concert(data: Resource, approved: bool) -> void:
	var text: String = data.caption(approved).replace("|", " ").strip_edges()
	_concert = BeachConcert.new()
	_concert.name = "BeachConcert"
	_city.add_child(_concert)
	_concert.setup(_city)
	_concert.start(BeachConcert.Part.BUILD)
	_concert.queue_part(BeachConcert.Part.DROP)   # on the next bar, ~2 s in
	_concert.nightfall(1.2)
	_type_caption(text)
	_concert_talk(text.replace("*", ""), data.voice(approved))
	await _fly_to(_concert.rig, 1.4)
	var wide: Array = _concert.wide_shot()
	_glide(wide[0], wide[1], 4.5, wide[2])
	var waited := 0.0
	while (waited < 3.5 or _talking) and waited < 5.0 and not _skip:
		await get_tree().process_frame
		waited += get_process_delta_time()


var _talking := false

## Read the concert caption out over the music (not awaited by the show).
func _concert_talk(spoken: String, voice: AudioStream) -> void:
	_talking = true
	_concert.duck(true)
	await _narrate(spoken, voice)
	if _concert:
		_concert.duck(false)
	_talking = false


## An ending shot ([eye, look, creep]) with any building that would stand
## between the camera and what it shows swung out of the way (clear_shot.gd).
## `subjects` are the nodes the shot is of: their own walls never count.
func _clear(shot: Array, subjects: Array = []) -> Array:
	var tile := 26.926893
	if _ending and is_instance_valid(_ending):
		tile = _ending._tile
	return ClearShot.fix(_city_cam, shot, tile, subjects)


## Glide the city camera to `to`, looking at `look`, then keep creeping along
## `creep` while the moment plays out. Returns when the glide is done.
func _glide(to: Vector3, look: Vector3, time: float, creep := Vector3.ZERO) -> void:
	_kill(_orbit)
	var p0 := _city_cam.global_position
	var l0 := p0 - _city_cam.global_basis.z * p0.distance_to(look)
	_orbit = create_tween()
	var dur := time * (ENDING_PACE if _in_ending else 1.0)
	# In the ending, a move from one spot to another flies over the roofs
	# rather than straight through whatever stands between them: it climbs
	# first when going up, and arcs higher the further it goes across.
	var lift := 0.0
	var rise := false
	if _in_ending and time > 0.2:
		var across := Vector2(to.x - p0.x, to.z - p0.z).length()
		if across > GLIDE_ARC_FROM:
			lift = clampf(across * GLIDE_ARC, 0.0, GLIDE_ARC_MAX)
		rise = to.y > p0.y + GLIDE_ARC_FROM * 0.3
	_orbit.tween_method(func(k: float) -> void:
		var p := p0.lerp(to, k)
		if rise:
			p.y = lerpf(p0.y, to.y, 1.0 - (1.0 - k) * (1.0 - k))
		p.y += lift * sin(PI * k)
		_city_cam.look_at_from_position(p, l0.lerp(look, k), Vector3.UP), 0.0, 1.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if creep != Vector3.ZERO:
		_orbit.tween_method(func(k: float) -> void:
			_city_cam.look_at_from_position(to + creep * k, look, Vector3.UP), 0.0, 1.0, 20.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _in_ending:
		var left := dur
		while left > 0.0 and is_inside_tree():
			await get_tree().process_frame
			left -= get_process_delta_time()
	else:
		await _wait(time)


# ================================================================ old quarter

## The Minister of Urban Planning's choice. Approved: fly over the Old Quarter
## while the builders brace and repair every building. Denied: drop into its
## empty main street and watch the tumbleweeds roll by.
func _play_old_quarter(data: Resource, approved: bool) -> void:
	var q = _ensure_old_quarter()
	if q == null:
		_type_caption(data.caption(approved))
		await _wait(2.8)
		return
	if data.action(approved) == ProposalData.CityAction.REPAIR and not q.repaired:
		var shot: Array = q.district_shot()
		q.prepare()   # the builders are already at it when we get there
		await _glide(shot[0], shot[1], 2.0, shot[2])
		_type_caption(data.caption(approved))
		await _until_done(q.repair)   # skipped: the repair finishes off-camera
		q.celebrate()
		await _wait(1.4)
	else:
		var high: Array = q.street_drop_shot()
		var low: Array = q.street_shot()
		await _glide(high[0], high[1], 1.5)
		await _glide(low[0], low[1], 1.2, low[2])
		_type_caption(data.caption(approved))
		q.tumbleweeds(2)   # they keep rolling; we don't wait for them to cross
		await _wait(3.2)


func _ensure_old_quarter():
	if _old_quarter == null and _city:
		var q = OldQuarterWorks.new()
		q.name = "OldQuarterWorks"
		_city.add_child(q)
		if not q.setup(_city):
			push_warning("DayCycle: no Districts/OldQuarter in %s" % CITY_SCENE)
			q.queue_free()
			return null
		_old_quarter = q
	return _old_quarter


# ================================================================ central park

## The Chief Seismologist's Sunday drill. Approved: the sirens go, the camera
## comes over the fountain plaza packed with the whole town (more still
## walking in, marshals waving them on) and the caption is read out over the
## crowd. Denied: drop down to the empty plaza, an old man dozing on a bench,
## one passer-by, and tumbleweeds rolling across while the caption is read.
func _play_drill(data: Resource, approved: bool) -> void:
	var text: String = data.caption(approved)
	var spoken := text.replace("*", "")
	_drill = CentralParkDrill.new()
	_drill.name = "CentralParkDrill"
	_city.add_child(_drill)
	if not _drill.setup(_city):
		push_warning("DayCycle: no %s in %s" % [CentralParkDrill.PARK, CITY_SCENE])
		_drill.queue_free()
		_drill = null
		_type_caption(text)
		await _narrate(spoken, data.voice(approved))
		return
	if data.action(approved) == ProposalData.CityAction.DRILL:
		_drill.start_drill()
		var shot: Array = _drill.drill_shot()
		await _glide(shot[0], shot[1], 2.0, shot[2])
		_drill.duck(true)
		_type_caption(text)
		await _narrate(spoken, data.voice(approved))
		_drill.duck(false)
		await _wait(0.5)
	else:
		var roll: float = _drill.start_empty()
		var high: Array = _drill.empty_drop_shot()
		var low: Array = _drill.empty_shot()
		var started := Time.get_ticks_msec()
		await _glide(high[0], high[1], 1.5)
		await _glide(low[0], low[1], 1.2, low[2])
		_type_caption(text)
		await _narrate(spoken, data.voice(approved))
		# let the last tumbleweed get across
		var left := roll - (Time.get_ticks_msec() - started) / 1000.0
		await _wait(clampf(left, 0.3, 1.0))


# ================================================================ fire training

## The foreign rescue team's free training. The fire station (city_target)
## goes up first if it hasn't yet, then the camera comes round the front where
## an instructor whistles and two hose teams open up, their arcs of water
## crossing over the apron, while the caption is read out over the hiss.
func _play_training(data: Resource, approved: bool) -> void:
	var text: String = data.caption(approved)
	var spoken := text.replace("*", "")
	var node := _city.get_node_or_null(NodePath(data.city_target)) as Node3D
	if node == null:
		push_warning("DayCycle: city target '%s' of %s not found in %s" % [data.city_target, data.id, CITY_SCENE])
		_type_caption(text)
		await _narrate(spoken, data.voice(approved))
		return
	if node.has_method("build") and not node.is_built():
		await _fly_to(node)
		node.set("build_time", minf(float(node.get("build_time")), EVENING_BUILD_TIME))
		node.build()
		var limit := float(node.get("build_time")) + 3.0
		var waited := 0.0
		while not node.is_built() and waited < limit and not _skip:
			await get_tree().process_frame
			waited += get_process_delta_time()
		await _wait(0.6)
	_training = FireTraining.new()
	_training.name = "FireTraining"
	_city.add_child(_training)
	_training.setup(node)
	_training.start()   # whistle, then the nozzles open one after the other
	var shot: Array = _training.shot()
	await _glide(shot[0], shot[1], 2.0, shot[2])
	_training.duck(true)
	_type_caption(text)
	await _narrate(spoken, data.voice(approved))
	_training.duck(false)
	await _wait(0.8)
	_training.silence()


# ================================================================ shelter tents

## The Head of Disaster Agency's shelter camp. The camera comes over Central
## Park's east lawn, and while the caption is read out evacuation signs spring
## up at the park gates and rows of tents pop up around the shelter gate. The
## camp stays (it lives under the park in the city); seen again on a later
## evening, it is simply there.
func _play_tents(data: Resource, approved: bool) -> void:
	var text: String = data.caption(approved)
	var spoken := text.replace("*", "")
	var park := _city.get_node_or_null(ParkTents.PARK) as Node3D
	if park == null:
		push_warning("DayCycle: no %s in %s" % [ParkTents.PARK, CITY_SCENE])
		_type_caption(text)
		await _narrate(spoken, data.voice(approved))
		return
	var camp = park.get_node_or_null("ShelterCamp")
	var fresh: bool = camp == null
	if fresh:
		camp = ParkTents.new()
		park.add_child(camp)
		camp.setup(park)
	var shot: Array = camp.shot()
	await _glide(shot[0], shot[1], 2.2, shot[2])
	_type_caption(text)
	if fresh:
		camp.raise()   # pops up while the caption is read
	await _narrate(spoken, data.voice(approved))
	while not camp.done and not _skip:
		await get_tree().process_frame
	if not camp.done:
		camp.finish()   # skipped: everything is up by the next evening
	await _wait(0.8)


# ================================================================ cracks

## The Contractor's cheap concrete. The building (city_target) goes up first
## if it hasn't yet, then the camera swings round behind it and a few cracks
## spread over its back wall and the ground behind it.
func _play_cracks(data: Resource, approved: bool) -> void:
	var node := _city.get_node_or_null(NodePath(data.city_target)) as Node3D
	if node == null:
		push_warning("DayCycle: city target '%s' of %s not found in %s" % [data.city_target, data.id, CITY_SCENE])
		_type_caption(data.caption(approved))
		await _wait(2.8)
		return
	if node.has_method("build") and not node.is_built():
		await _fly_to(node)
		node.set("build_time", minf(float(node.get("build_time")), EVENING_BUILD_TIME))
		node.build()
		var limit := float(node.get("build_time")) + 3.0
		var waited := 0.0
		while not node.is_built() and waited < limit and not _skip:
			await get_tree().process_frame
			waited += get_process_delta_time()
		await _wait(0.8)
	var cracks = node.get_node_or_null("Cracks")
	var fresh := cracks == null
	if fresh:
		cracks = HospitalCracks.new()
		node.add_child(cracks)
		cracks.setup(node)
	await _swing_behind(node, 2.0)
	await _wait(0.1)
	_type_caption(data.caption(approved))
	if fresh:
		await _until_done(cracks.grow)   # skipped: they finish spreading anyway
	await _wait(1.2)


## Circle round to a 3/4 view of the back of `node` (the same framing as
## _fly_to), going round the building rather than through it, then keep
## drifting slowly while the cracks show.
func _swing_behind(node: Node3D, time := 3.0) -> void:
	_kill(_orbit)
	var s := node.global_basis.get_scale().x
	var origin := node.global_position
	var front := node.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.FORWARD
	var side := front.cross(Vector3.UP).normalized()
	var focus := origin + Vector3.UP * 0.9 * s
	var dist := 6.8 * s
	var lift := 4.4 * s
	var dir1 := (-front * 0.85 + side * 0.55).normalized()

	var p0 := _city_cam.global_position
	var rel := p0 - origin
	var r0 := Vector2(rel.x, rel.z).length()
	var a0 := atan2(rel.x, rel.z)
	var a1 := atan2(dir1.x, dir1.z)
	var da := wrapf(a1 - a0, -PI, PI)
	var t0 := _ground_point(_city_cam.global_transform)
	_orbit = create_tween()   # kept in _orbit so the next shot can cut it off
	_orbit.tween_method(func(k: float) -> void:
		var a := a0 + da * k
		var r := lerpf(r0, dist, k)
		var pos := origin + Vector3(sin(a), 0.0, cos(a)) * r + Vector3.UP * lerpf(rel.y, lift, k)
		_city_cam.look_at_from_position(pos, t0.lerp(focus, minf(k * 2.5, 1.0)), Vector3.UP),
		0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _until_tween(_orbit)
	if _skip:
		return
	_orbit = create_tween()
	_orbit.tween_method(func(a: float) -> void:
		var d := dir1.rotated(Vector3.UP, a)
		_city_cam.look_at_from_position(origin + d * dist + Vector3.UP * lift, focus, Vector3.UP),
		0.0, deg_to_rad(-14.0), 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	f.tween_property(cs, "modulate:a", 1.0, 0.25)
	await _until_tween(f)
	await _until_done(cs.intro)
	await _wait(0.1)
	_type_caption(text)
	cs.talking = true
	await _narrate(spoken, data.voice(approved))
	cs.talking = false
	cs.wake_up()
	await _wait(0.6)
	if _skip:
		# skipped: drop the scene now; the caption fades with the next event
		_kill(f)
		cs.queue_free()
		return
	await _hide_caption()
	await cs.outro()
	var o := create_tween()
	o.tween_property(cs, "modulate:a", 0.0, 0.25)
	await o.finished
	cs.queue_free()


## About how long it takes to say `text`, in seconds.
func _speech_time(text: String) -> float:
	var words := text.split(" ", false).size()
	if _in_ending:
		return clampf(float(words) / 2.4, 2.8, 42.0)
	return clampf(float(words) / 3.4, 2.0, 30.0)


## Read `text` aloud: the recording if there is one, else text-to-speech
## (Project Settings > Audio > General > Text to Speech must be on), else
## just wait as long as reading it would take. Returns when it's done.
func _narrate(text: String, stream: AudioStream) -> void:
	if _skip or (_in_ending and _advance):
		return
	var limit := _speech_time(text) * 2.0 + 3.0
	var waited := 0.0
	if stream:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		add_child(p)
		p.play()
		_voice = p
		limit = maxf(stream.get_length(), 1.0) + 1.0
		while p.playing and waited < limit and not _skip and not (_in_ending and _advance):
			await get_tree().process_frame
			waited += get_process_delta_time()
		p.stop()
		p.queue_free()
		_voice = null
		return
	if _tts_ready():
		DisplayServer.tts_stop()
		var rate := 1.0 if _in_ending else TTS_RATE
		DisplayServer.tts_speak(text, _tts_voice, 80, 1.0, rate)
		var started := false
		while waited < limit:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if _skip or (_in_ending and _advance):
				DisplayServer.tts_stop()
				return
			if DisplayServer.tts_is_speaking():
				started = true
			elif started or waited > 1.5:
				break
		if started:
			return
		push_warning("DayCycle: text-to-speech didn't start, showing the caption only")
	var remain := maxf(_speech_time(text) - waited, 0.7 if _in_ending else 0.5)
	if _in_ending:
		await _until_advance(remain)
	else:
		await _wait(remain)


func _until_advance(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _advance and is_inside_tree():
		await get_tree().process_frame
		left -= get_process_delta_time()


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
func _fly_to(node: Node3D, time := 2.0) -> void:
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
	_orbit = create_tween()   # kept in _orbit so the next shot can cut it off
	_orbit.tween_method(func(k: float) -> void:
		var look_k := 1.0 - pow(1.0 - k, 2.2)      # turn toward it early
		var pos := p0.lerp(goal, k) + Vector3.UP * sin(k * PI) * 0.15 * p0.distance_to(goal)
		_city_cam.look_at_from_position(pos, t0.lerp(focus, look_k), Vector3.UP), 0.0, 1.0, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _until_tween(_orbit)
	if _skip:
		return
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
	_ensure_president_house()
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


const PRESIDENT_PALACE_SCENE := "res://City/Civic/president_palace.tscn"
const PRESIDENT_PALACE_GROUND := "res://Models/Custom/sidewalk.glb"
const PRESIDENT_PALACE_XFORM := Transform3D(Basis(Vector3(0, 0, 26.926893), Vector3(0, 26.926893, 0), Vector3(-26.926893, 0, 0)), Vector3(499.33502, -0.7273283, -502.0605))
const PRESIDENT_PALACE_GROUND_XFORM := Transform3D(Basis(Vector3(188.45, 0, 0), Vector3(0, 26.926893, 0), Vector3(0, 0, 296.19)), Vector3(499.33502, -1.804404, -502.0605))

## The presidential palace fills the corner under Central Park, facing the park.
## city.tscn places it too; this makes sure the game always shows the current
## version in the right spot, even if city.tscn was re-saved from an editor
## that still had an older copy open.
func _ensure_president_house() -> void:
	var buildings := _city.get_node_or_null("Districts/CivicCenter/Buildings")
	if buildings == null:
		return
	# drop the older version if an editor saved it back into city.tscn
	var old := buildings.get_node_or_null("PresidentHouse")
	if old:
		buildings.remove_child(old)
		old.free()
	var palace := buildings.get_node_or_null("PresidentPalace") as Node3D
	if palace == null:
		if not ResourceLoader.exists(PRESIDENT_PALACE_SCENE):
			push_warning("DayCycle: missing %s" % PRESIDENT_PALACE_SCENE)
			return
		palace = (load(PRESIDENT_PALACE_SCENE) as PackedScene).instantiate() as Node3D
		palace.name = "PresidentPalace"
		buildings.add_child(palace)
	palace.transform = PRESIDENT_PALACE_XFORM
	var ground := _city.get_node_or_null("Districts/CivicCenter/Ground")
	if ground == null:
		return
	var pad := ground.get_node_or_null("PresidentPalaceGround") as Node3D
	if pad == null:
		pad = ground.get_node_or_null("sidewalk4") as Node3D
	if pad == null and ResourceLoader.exists(PRESIDENT_PALACE_GROUND):
		pad = (load(PRESIDENT_PALACE_GROUND) as PackedScene).instantiate() as Node3D
		pad.name = "PresidentPalaceGround"
		ground.add_child(pad)
	if pad:
		pad.transform = PRESIDENT_PALACE_GROUND_XFORM


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
	_click_heard = 0
	_click_gap = 0.0
	_typing = true
	set_process(true)
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	var per := 0.04 if _in_ending else 0.028
	var type_time := 0.8
	if _in_ending:
		type_time = clampf(text.length() * per, 1.2, 4.2)
	else:
		type_time = clampf(text.length() * per, 0.8, 2.6)
	_type_tween = create_tween().set_parallel()
	_type_tween.tween_property(_caption, "modulate:a", 1.0, 0.5 if _in_ending else 0.35)
	_type_tween.tween_property(_caption, "visible_ratio", 1.0, type_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _typing or _caption == null:
		_typing = false
		set_process(false)
		return
	_click_gap = maxf(_click_gap - delta, 0.0)
	if _caption.visible_ratio >= 0.999:
		_typing = false
		set_process(false)
		return
	var shown := _caption.get_visible_characters()
	if shown < 0:
		shown = _caption.get_total_character_count()
	var plain := _caption.get_parsed_text()
	while _click_heard < shown:
		var ch := plain[_click_heard] if _click_heard < plain.length() else " "
		_click_heard += 1
		if _click_gap > 0.0 or not _click_letter(ch):
			continue
		_play_click()
		_click_gap = TYPE_CLICK_GAP
		break


## Letters and digits only, so spaces and punctuation stay quiet.
func _click_letter(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


func _play_day_transition() -> void:
	if not ResourceLoader.exists(DAY_TRANSITION):
		return
	var stream := load(DAY_TRANSITION) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = DAY_TRANSITION_DB
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_click() -> void:
	if _click_stream == null:
		if not ResourceLoader.exists(TYPE_CLICK):
			return
		_click_stream = load(TYPE_CLICK) as AudioStream
		if _click_stream == null:
			return
	if _click == null or not is_instance_valid(_click):
		_click = AudioStreamPlayer.new()
		_click.stream = _click_stream
		add_child(_click)
	_click.volume_db = TYPE_CLICK_DB
	_click.pitch_scale = randf_range(0.94, 1.06)
	_click.play()


func _hide_caption() -> void:
	_typing = false
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	var dur := 0.4 if _in_ending else 0.25
	var t := create_tween()
	t.tween_property(_caption, "modulate:a", 0.0, dur)
	if _in_ending:
		await _until_tween_ending(t)
		if _advance:
			_caption.modulate.a = 0.0
	else:
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
