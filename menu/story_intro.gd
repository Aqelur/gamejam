extends Control

## Start damgasından sonra, başkan odasından önce.
## Her satır yazılır, Click to continue bekler. Son tıklama masayı açar.
## Masa yazılar akarken kurulur; tıklayınca arada boş bir geçiş ekranı kalmaz.

const NEXT_SCENE := "res://PresidentRoom/president_room.tscn"
const CHARS_PER_SECOND := 26.0

const LINES: PackedStringArray = [
	"Last time, they were still shouting. The sirens never stopped.",
	"You're the mayor.",
	"Experts came after. A threat too big for a small name. They call it the big one. The day? They don't have that.",
	"Until then this office is a mess. People pile in. Papers hit the desk. Someone is always yelling.",
	"Green stamp. Red stamp. APPROVED or DENIED. The town holds, or history repeats itself, on which one you pick.",
	"And that's the mayor's call.",
]

const SIREN_DB := -6.0
const SCREAM_DB := -10.0
const CROWD_DB := -16.0
const CROWD_BUS := &"StoryCrowd"

@onready var _body: Label = %Body
@onready var _hint: Label = %Hint
@onready var _fade: ColorRect = %Fade
@onready var _music: AudioStreamPlayer = %Music
@onready var _siren: AudioStreamPlayer = %Siren
@onready var _scream: AudioStreamPlayer = %Scream
@onready var _crowd: AudioStreamPlayer = %Crowd

var _room: Node
var _index := 0
var _shown := false
var _leaving := false
var _reveal: Tween
var _music_in: Tween
var _street_out: Tween
var _ducked: Array[Dictionary] = []
var _mute_master_again := false


func _ready() -> void:
	_fade.color = Color(0, 0, 0, 1)
	_hint.modulate.a = 0.0
	%SkipButton.pressed.connect(_leave)
	_warm_desk()
	_lift_master_mute()
	_play_street()
	_show_line(0)
	var open := create_tween()
	open.tween_property(_fade, "color:a", 0.0, 0.65)


func _process(_delta: float) -> void:
	_hold_tutorial()


## İlk satır sokaktır: siren önde, çığlık onun arkasında, kalabalık daha da altta ve boğuk.
func _play_street() -> void:
	if _scream.stream == null:
		_scream.stream = load("res://assets/audio/emergency/crowd_screaming.wav")
	_loop_mp3(_siren)
	_loop_wav(_scream)
	_loop_wav(_crowd)
	_muffle_crowd()
	_scream.bus = &"Master"
	_siren.volume_db = SIREN_DB
	_scream.volume_db = SCREAM_DB
	_crowd.volume_db = CROWD_DB
	_siren.play()
	_scream.play()
	_crowd.play()


## İkinci satırda sokak çekilir. Skip ve son tıklama aynı sesleri keser.
func _pull_street() -> void:
	_fade_street(1.8)


func _cut_street() -> void:
	_fade_street(0.3)


func _fade_street(seconds: float) -> void:
	if _street_out != null and is_instance_valid(_street_out):
		_street_out.kill()
	if not _siren.playing and not _scream.playing and not _crowd.playing:
		return
	_street_out = create_tween()
	_street_out.set_parallel(true)
	_street_out.tween_property(_siren, "volume_db", -40.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_street_out.tween_property(_scream, "volume_db", -40.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_street_out.tween_property(_crowd, "volume_db", -40.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_street_out.chain().tween_callback(_stop_street)


func _stop_street() -> void:
	_siren.stop()
	_scream.stop()
	_crowd.stop()


func _loop_mp3(player: AudioStreamPlayer) -> void:
	var mp3 := player.stream.duplicate() as AudioStreamMP3
	if mp3 == null:
		return
	mp3.loop = true
	player.stream = mp3


func _loop_wav(player: AudioStreamPlayer) -> void:
	var wav := player.stream.duplicate() as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	var frames := int(round(wav.get_length() * wav.mix_rate))
	if frames > 1:
		wav.loop_end = frames
	player.stream = wav


## Kalabalık ayrı kanaldan geçer; alçak geçiren süzgeç onu boğuk bırakır.
func _muffle_crowd() -> void:
	var idx := AudioServer.get_bus_index(CROWD_BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, CROWD_BUS)
		AudioServer.set_bus_send(idx, &"Master")
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = 700.0
		low.resonance = 0.25
		AudioServer.add_bus_effect(idx, low)
	_crowd.bus = CROWD_BUS


func _remove_crowd_bus() -> void:
	if is_instance_valid(_crowd):
		_crowd.bus = &"Master"
	var idx := AudioServer.get_bus_index(CROWD_BUS)
	if idx > 0:
		AudioServer.remove_bus(idx)


## Yazılar oyuncunun hızında aktığı için parça döner. İkinci satırda yükselir, sahneden çıkınca kısılır.
func _play_music() -> void:
	if _music.stream == null:
		return
	var wav := _music.stream.duplicate() as AudioStreamWAV
	if wav:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frames := int(round(wav.get_length() * wav.mix_rate))
		if frames > 1:
			wav.loop_end = frames
		_music.stream = wav
	_music.volume_db = -18.0
	_music.play()
	_music_in = create_tween()
	_music_in.tween_property(_music, "volume_db", -10.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Oda _ready'si ağır. Yazılar okunurken kurulsun ki son tıklamada gri bir ara kare çıkmasın.
func _warm_desk() -> void:
	var packed := load(NEXT_SCENE) as PackedScene
	if packed == null:
		return
	_room = packed.instantiate()
	_room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(_room)


## Öğretici kendi katmanında açılışın üstüne biner. Masa görünene kadar gizli kalsın.
func _hold_tutorial() -> void:
	if _room == null:
		return
	var root := _room.find_child("TutorialRoot", true, false) as CanvasItem
	if root == null:
		return
	root.hide()
	root.modulate.a = 0.0
	if root is Control:
		(root as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_line(index: int) -> void:
	_index = index
	_shown = false
	_hint.modulate.a = 0.0
	_body.text = LINES[index]
	_body.visible_characters = 0
	if _reveal != null and is_instance_valid(_reveal):
		_reveal.kill()
	var seconds := maxf(LINES[index].length() / CHARS_PER_SECOND, 0.8)
	_reveal = create_tween()
	_reveal.tween_property(_body, "visible_characters", LINES[index].length(), seconds)
	_reveal.finished.connect(_on_line_shown, CONNECT_ONE_SHOT)


func _on_line_shown() -> void:
	if _shown or _leaving:
		return
	_shown = true
	_hint.text = "Click to continue"
	var fade_in := create_tween()
	fade_in.tween_property(_hint, "modulate:a", 0.85, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not event.is_action_pressed("action") and not event.is_action_pressed("jump") and not event.is_action_pressed("ui_accept"):
		return
	_advance()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_advance()
	accept_event()


func _advance() -> void:
	if _leaving:
		return
	if not _shown:
		if _reveal != null and is_instance_valid(_reveal):
			_reveal.kill()
		_body.visible_characters = -1
		_on_line_shown()
		return
	if _index == 0:
		_pull_street()
		_play_music()
	if _index + 1 < LINES.size():
		_show_line(_index + 1)
	else:
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _reveal != null and is_instance_valid(_reveal):
		_reveal.kill()
	if _music_in != null and is_instance_valid(_music_in):
		_music_in.kill()
	_cut_street()
	var music_out := create_tween()
	music_out.tween_property(_music, "volume_db", -40.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _room != null and is_instance_valid(_room):
		_room.process_mode = Node.PROCESS_MODE_INHERIT
	var fade_out := create_tween()
	fade_out.tween_property(self, "modulate:a", 0.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished
	_restore_master_mute()
	if _room != null and is_instance_valid(_room):
		var root := _room.find_child("TutorialRoot", true, false) as CanvasItem
		if root:
			root.show()
			root.modulate.a = 1.0
			if root is Control:
				(root as Control).mouse_filter = Control.MOUSE_FILTER_STOP
		get_tree().current_scene = _room
		_room = null
		queue_free()
		return
	get_tree().change_scene_to_file(NEXT_SCENE)


func _exit_tree() -> void:
	_remove_crowd_bus()


## Master kapalıyken parça, siren, çığlık ve kalabalık duyulsun. Odanın kendi sesleri kısık kalsın.
func _lift_master_mute() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	_mute_master_again = AudioServer.is_bus_mute(bus)
	_duck_from(get_tree().root)
	AudioServer.set_bus_mute(bus, false)


func _duck_from(node: Node) -> void:
	if not _keeps_playing(node) and (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		_ducked.append({"player": node, "db": node.volume_db})
		node.volume_db = -80.0
	for child in node.get_children():
		_duck_from(child)


func _keeps_playing(node: Node) -> bool:
	return node == _music or node == _siren or node == _scream or node == _crowd


func _restore_master_mute() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus >= 0 and _mute_master_again:
		AudioServer.set_bus_mute(bus, true)
	for item in _ducked:
		var player := item.player as Node
		if is_instance_valid(player):
			player.volume_db = item.db
	_ducked.clear()
