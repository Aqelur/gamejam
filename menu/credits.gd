extends Control

## Kapanış satırlarının müziği sürer. "A GAME PRESENTED BY" söner, kısa bir boşluk kalır.
## Logo 39.2'de bir anda belirir; outro.wav içindeki vuruş o ana gömülüdür.
## Tıklama başlık ekranını açar.

const TITLE_SCENE := "res://menu/title_screen.tscn"
const BED_NAME := "OutroBed"
const CURTAIN_AT := 34.3
const TITLE_AT := 34.8
const TITLE_OUT_AT := 38.1
const LOGO_AT := 39.2
const FALLBACK_START := 33.9

@onready var _title: Label = %Title
@onready var _logo: TextureRect = %Logo
@onready var _hint: Label = %Hint
@onready var _fade: ColorRect = %Fade
@onready var _music: AudioStreamPlayer = %Music

var _bed: AudioStreamPlayer
var _waiting := false
var _fallback := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 1)
	_title.modulate.a = 0.0
	_logo.visible = false
	_logo.modulate.a = 0.0
	_hint.modulate.a = 0.0
	var carried := get_tree().root.get_node_or_null(BED_NAME) as AudioStreamPlayer
	if carried != null and carried.playing:
		_bed = carried
		_music.stop()
	else:
		_bed = _music
		_bed.volume_db = -4.0
		if _bed.stream != null:
			_bed.play(FALLBACK_START)
		else:
			_fallback = FALLBACK_START
	_play()


func _clock() -> float:
	if _bed != null and _bed.playing:
		return _bed.get_playback_position()
	return _fallback


func _until(mark: float) -> void:
	while _clock() + 0.02 < mark:
		await get_tree().process_frame
		if _bed == null or not _bed.playing:
			_fallback += get_process_delta_time()


func _play() -> void:
	await _until(CURTAIN_AT)
	if _clock() < TITLE_AT:
		var open := create_tween()
		open.tween_property(_fade, "color:a", 0.0, minf(0.5, TITLE_AT - _clock()))
		await open.finished
	else:
		_fade.color.a = 0.0
	await _until(TITLE_AT)
	if _clock() < TITLE_OUT_AT:
		var words := create_tween()
		words.tween_property(_title, "modulate:a", 1.0, 1.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await words.finished
		await _until(TITLE_OUT_AT)
		if _clock() < LOGO_AT - 0.9:
			var words_out := create_tween()
			words_out.tween_property(_title, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			await words_out.finished
	_title.visible = false
	await _until(LOGO_AT)
	_fade.color.a = 0.0
	_show_logo()
	_waiting = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var hint := create_tween()
	hint.tween_interval(1.6)
	hint.tween_property(_hint, "modulate:a", 0.7, 0.9)
	while _waiting:
		await get_tree().process_frame
	hint.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var close := create_tween()
	close.tween_property(_fade, "color:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _bed != null and _bed.playing:
		close.parallel().tween_property(_bed, "volume_db", -40.0, 0.8)
	await close.finished
	if _bed != null and is_instance_valid(_bed):
		_bed.stop()
		if _bed.get_parent() == get_tree().root:
			_bed.queue_free()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _show_logo() -> void:
	_logo.visible = true
	_logo.modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not _waiting or event.is_echo():
		return
	if not event.is_action_pressed("action") and not event.is_action_pressed("jump") and not event.is_action_pressed("ui_accept"):
		return
	_waiting = false
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if not _waiting or click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	_waiting = false
	accept_event()
