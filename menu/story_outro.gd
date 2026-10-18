extends Control

## Kefenlerden sonra. Satır bütün halinde yavaşça gelir, durur, söner.
## Müzik burada başlar. Kredi sahnesine taşınır; vuruş logo anına gömülüdür.

const CREDITS_SCENE := "res://menu/credits.tscn"
const TITLE_SCENE := "res://menu/title_screen.tscn"
const BED_NAME := "OutroBed"

const OPEN := 0.85
const CURTAIN := 0.45
const LINE_IN := 1.15
const LINE_OUT := 1.0
const GAP := 0.75
const SECONDS_PER_WORD := 0.3
const TAIL := 0.15
const CLOSE := 0.55

const LINES: PackedStringArray = [
	"They did not have to die.",
	"The right preparations can prevent most of the damage.",
	"In this game, you can always try again.",
	"In real life, there is no second chance.",
	"This was Mayor's Call.",
]

@onready var _body: Label = %Body
@onready var _fade: ColorRect = %Fade
@onready var _music: AudioStreamPlayer = %Music


func _ready() -> void:
	_fade.color = Color(0, 0, 0, 1)
	_body.modulate.a = 0.0
	_music.volume_db = -4.0
	if _music.stream != null:
		_music.play()
	_play()


func _play() -> void:
	await get_tree().create_timer(OPEN).timeout
	var curtain := create_tween()
	curtain.tween_property(_fade, "color:a", 0.0, CURTAIN)
	await curtain.finished
	for index in LINES.size():
		await _show_line(index)
		if index + 1 < LINES.size():
			await _clear_line()
	await get_tree().create_timer(TAIL).timeout
	var close := create_tween()
	close.tween_property(_fade, "color:a", 1.0, CLOSE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await close.finished
	if ResourceLoader.exists(CREDITS_SCENE):
		_carry_music()
		get_tree().change_scene_to_file(CREDITS_SCENE)
	else:
		_music.stop()
		get_tree().set_meta(StoryIntro.REPLAY_META, true)
		get_tree().change_scene_to_file(TITLE_SCENE)


func _show_line(index: int) -> void:
	_body.text = LINES[index]
	_body.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(_body, "modulate:a", 1.0, LINE_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fade_in.finished
	await get_tree().create_timer(_read_time(LINES[index])).timeout


func _read_time(line: String) -> float:
	return float(line.split(" ", false).size()) * SECONDS_PER_WORD


func _clear_line() -> void:
	var fade_out := create_tween()
	fade_out.tween_property(_body, "modulate:a", 0.0, LINE_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await fade_out.finished
	await get_tree().create_timer(GAP).timeout


func _carry_music() -> void:
	if _music.stream == null:
		return
	var old := get_tree().root.get_node_or_null(BED_NAME)
	if old:
		old.free()
	var bed := _music
	remove_child(bed)
	bed.name = BED_NAME
	get_tree().root.add_child(bed)
