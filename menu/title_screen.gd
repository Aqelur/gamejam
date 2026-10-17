@tool
extends Control

## Giriş ekranı. Start kart masasına geçer, Quit oyunu kapatır.

const GAME_SCENE := "res://cards/card_table.tscn"

@export var title_text := "Mayor's Call: Disaster":
	set(value):
		title_text = value
		if is_node_ready():
			%TitleLabel.text = value

@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	%TitleLabel.text = title_text
	resized.connect(_place_embers)
	_place_embers()
	if Engine.is_editor_hint():
		return
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	for button: Button in [_start_button, _quit_button]:
		button.gui_input.connect(_on_button_input.bind(button))
		button.focus_entered.connect(_scale_button.bind(button, 1.15))
		button.focus_exited.connect(_scale_button.bind(button, 1.0))
		button.resized.connect(func() -> void: button.pivot_offset = button.size / 2.0)
	_play_intro()
	_start_button.grab_focus.call_deferred()


func _place_embers() -> void:
	%Embers.position = Vector2(size.x / 2.0, size.y + 15.0)
	%Embers.emission_rect_extents = Vector2(size.x / 2.0, 10.0)


func _play_intro() -> void:
	var parts: Array[Control] = [%TitleLabel, %Buttons]
	var tween := create_tween().set_parallel()
	for i in parts.size():
		parts[i].modulate.a = 0.0
		tween.tween_property(parts[i], "modulate:a", 1.0, 0.6).set_delay(0.15 + i * 0.25)


# Fare oynatılınca altındaki düğme klavye seçimini de alır, iki seçim ayrışmaz.
# Açılışta imleç bir düğmenin üstünde duruyorsa Start'ın seçimini çalmaz.
func _on_button_input(event: InputEvent, button: Button) -> void:
	var motion := event as InputEventMouseMotion
	if motion and motion.relative != Vector2.ZERO and not button.has_focus():
		button.grab_focus()


func _scale_button(button: Button, target: float) -> void:
	create_tween().tween_property(button, "scale", Vector2.ONE * target, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
