@tool
extends Control

## Giriş ekranı. Start gece brifingine geçer, Quit oyunu kapatır.

const GAME_SCENE := "res://menu/story_intro.tscn"
const StampPress := preload("res://menu/stamp_press.gd")
const STAMP_SOUND := preload("res://menu/audio/stamp.wav")

@export var title_text := "Mayor's Call":
	set(value):
		title_text = value
		if is_node_ready():
			%TitleLabel.text = value

@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton

var _stamping := false


func _ready() -> void:
	%TitleLabel.text = title_text
	resized.connect(_place_motes)
	_place_motes()
	if Engine.is_editor_hint():
		return
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	for button: Button in [_start_button, _quit_button]:
		button.gui_input.connect(_on_button_input.bind(button))
	_play_intro()
	_play_music()
	_start_button.grab_focus.call_deferred()


func _place_motes() -> void:
	%Motes.position = size / 2.0
	%Motes.emission_rect_extents = size / 2.0


func _play_intro() -> void:
	var parts: Array[Control] = [%TitleLabel, %Buttons]
	var tween := create_tween().set_parallel()
	for i in parts.size():
		parts[i].modulate.a = 0.0
		tween.tween_property(parts[i], "modulate:a", 1.0, 0.6).set_delay(0.15 + i * 0.25)


# Menü açık kaldığı sürece döner; sahne değişince düğümle birlikte susar.
func _play_music() -> void:
	var stream := %Music.stream as AudioStreamMP3
	if stream:
		stream.loop = true
	%Music.play()


# Fare oynatılınca altındaki düğme klavye seçimini de alır, iki seçim ayrışmaz.
# Açılışta imleç bir düğmenin üstünde duruyorsa Start'ın seçimini çalmaz.
func _on_button_input(event: InputEvent, button: Button) -> void:
	var motion := event as InputEventMouseMotion
	if motion and motion.relative != Vector2.ZERO and not button.has_focus():
		button.grab_focus()


func _on_start_pressed() -> void:
	if await _stamp(_start_button, Color(0.12, 0.46, 0.16), Color(0.16, 0.55, 0.2)):
		var fade := ColorRect.new()
		fade.color = Color(0, 0, 0, 0)
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(fade)
		var tween := create_tween()
		tween.tween_property(fade, "color:a", 1.0, 0.45)
		tween.parallel().tween_property(%Music, "volume_db", -40.0, 0.45)
		await tween.finished
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	if await _stamp(_quit_button, Color(0.55, 0.08, 0.06), Color(0.62, 0.07, 0.05)):
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()


# Damga düğmeye iner; değdiği anda ekran sarsılır ve kısa bir duraklamadan sonra true döner.
# Animasyon sürerken gelen ikinci basış false alır.
func _stamp(button: Button, rubber: Color, ink: Color) -> bool:
	if _stamping:
		return false
	_stamping = true
	var stamp := StampPress.new()
	stamp.rubber = rubber
	stamp.ink = ink
	add_child(stamp)
	stamp.global_position = button.global_position + button.size / 2.0
	stamp.landed.connect(_shake)
	stamp.landed.connect(_play_stamp_sound)
	await stamp.play()
	await get_tree().create_timer(0.12).timeout
	return true


# Kökte çalar ki kart masasına geçince kesilmesin; bitince kendini siler.
func _play_stamp_sound() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = STAMP_SOUND
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


func _shake() -> void:
	var tween := create_tween()
	for offset: Vector2 in [Vector2(0, 7), Vector2(-5, -4), Vector2(3, 2), Vector2.ZERO]:
		tween.tween_property(self, "position", offset, 0.03)
