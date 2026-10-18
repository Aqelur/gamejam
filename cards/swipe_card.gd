class_name SwipeCard
extends Panel

## Kart yalnız yatay sürüklenir ve sürükledikçe eğilir. Ekran kenarını geçemez.
## Bırakınca eşik geçildiyse o yöne uçar, geçilmediyse ortaya döner.
signal swiped(side: int)

@export var max_tilt_degrees := 12.0
## Kartın ortadan en çok kaç piksel kayabileceği. Ekran darsa kenar daha erken durdurur.
@export var max_drag := 140.0
## max_drag yolunun oranı.
@export_range(0.1, 1.0) var swipe_threshold := 0.6
## swipe_threshold değerinden büyük olmalı; yoksa tuşla kart uçmaz.
@export_range(0.1, 1.0) var key_lean := 0.8
@export var edge_margin := 16.0
@export var key_lean_duration := 0.12
@export var return_duration := 0.25
@export var fly_duration := 0.3
@export var enter_duration := 0.3

var _left_choice := ""
var _right_choice := ""
var _rest := Vector2.ZERO
var _offset := 0.0
var _grab_x := 0.0
var _dragging := false
var _key_side := 0.0
var _busy := false
var _tween: Tween

@onready var _image: TextureRect = $Image
@onready var _choice_band: Control = $ChoiceBand
@onready var _choice_label: Label = $ChoiceBand/ChoiceLabel


func _ready() -> void:
	_rest = position
	_set_offset(0.0)


func show_data(data: CardData) -> void:
	_image.texture = data.image
	_left_choice = data.left_choice
	_right_choice = data.right_choice
	_dragging = false
	_key_side = 0.0
	_busy = true
	_set_offset(0.0)
	scale = Vector2(0.85, 0.85)
	modulate.a = 0.0
	var appear := _new_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	appear.tween_property(self, "scale", Vector2.ONE, enter_duration)
	appear.tween_property(self, "modulate:a", 1.0, enter_duration)
	await appear.finished
	_busy = false


func _gui_input(event: InputEvent) -> void:
	if _busy or _key_side != 0.0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_stop_tween()
			_dragging = true
			_grab_x = get_global_mouse_position().x - _offset
		elif _dragging:
			_dragging = false
			_release()
	elif event is InputEventMouseMotion and _dragging:
		_set_offset(get_global_mouse_position().x - _grab_x)


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _dragging:
		return
	if _key_side == 0.0:
		if event.is_action_pressed("move_left"):
			_lean(-1.0)
		elif event.is_action_pressed("move_right"):
			_lean(1.0)
	elif event.is_action_released("move_left" if _key_side < 0.0 else "move_right"):
		_let_go_key()


## Tuşa basılınca kart o yana eğilir ve seçenek görünür; tuş bırakılınca uçar.
func _lean(side: float) -> void:
	_key_side = side
	_new_tween().tween_method(_set_offset, _offset, side * _limit(side) * key_lean, key_lean_duration)


func _let_go_key() -> void:
	_key_side = 0.0
	_busy = true
	if _tween and _tween.is_running():
		await _tween.finished
	_busy = false
	_release()


func _release() -> void:
	var ratio := _ratio()
	if absf(ratio) >= swipe_threshold:
		_fly_out(signf(ratio))
	else:
		_new_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_method(_set_offset, _offset, 0.0, return_duration)


func _fly_out(side: float) -> void:
	_busy = true
	var distance := get_viewport_rect().size.x + size.x
	var fly := _new_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.tween_property(self, "position:x", _rest.x + side * distance, fly_duration)
	fly.tween_property(self, "rotation", deg_to_rad(max_tilt_degrees * 2.5) * side, fly_duration)
	await fly.finished
	swiped.emit(int(side))


func _set_offset(value: float) -> void:
	_offset = clampf(value, -_limit(-1.0), _limit(1.0))
	var ratio := _ratio()
	position.x = _rest.x + _offset
	rotation = deg_to_rad(max_tilt_degrees) * ratio
	_choice_label.text = _left_choice if _offset < 0.0 else _right_choice
	_choice_band.modulate.a = clampf(absf(ratio) / swipe_threshold, 0.0, 1.0)


func _ratio() -> float:
	var limit := _limit(signf(_offset))
	return _offset / limit if limit > 0.0 else 0.0


## En çok eğikken bile kartın dönmüş kutusu ekranın içinde kalır.
func _limit(side: float) -> float:
	var tilt := deg_to_rad(max_tilt_degrees)
	var half_width := (size.x * cos(tilt) + size.y * sin(tilt)) / 2.0
	var center_x := get_parent_control().global_position.x + _rest.x + size.x / 2.0
	var edge := get_viewport_rect().size.x - edge_margin if side > 0.0 else edge_margin
	return clampf(absf(edge - center_x) - half_width, 0.0, max_drag)


func _new_tween() -> Tween:
	_stop_tween()
	_tween = create_tween()
	return _tween


func _stop_tween() -> void:
	if _tween:
		_tween.kill()
