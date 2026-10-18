class_name DeskStamp
extends TextureRect

## Bırakıldığında yayılır. Kâğıda basılıp basılmadığına masa karar verir.
signal dropped(stamp: DeskStamp)

@export var stamp_text := "DAMGA"
@export var ink_color := Color(0.2, 0.2, 0.2)
@export var return_duration := 0.2
@export var hover_lift := 12.0
@export var hover_duration := 0.12

var _home := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _dragging := false
var _returning := false
var _hovered := false
var _tween: Tween

@onready var _label: Label = $Label


func _ready() -> void:
	_home = position
	_label.add_theme_color_override("font_color", ink_color)
	_label.text = stamp_text


func _process(_delta: float) -> void:
	if _dragging or _returning:
		return
	# Alan yükselmiş hâli de kapsar; yoksa alt kenarda damga inip kalkar.
	var area := Rect2(_home - Vector2(0, hover_lift), size + Vector2(0, hover_lift))
	var hover := area.has_point(get_parent().get_local_mouse_position()) \
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if hover != _hovered:
		_set_hovered(hover)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _tween:
				_tween.kill()
			_dragging = true
			_returning = false
			_hovered = false
			_grab_offset = get_global_mouse_position() - global_position
			move_to_front()
		elif _dragging:
			_dragging = false
			dropped.emit(self)
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _grab_offset


func return_home() -> void:
	_returning = true
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", _home, return_duration)
	_tween.finished.connect(func() -> void: _returning = false)


func _set_hovered(value: bool) -> void:
	_hovered = value
	if _tween:
		_tween.kill()
	var target := _home - Vector2(0, hover_lift) if value else _home
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target, hover_duration)
