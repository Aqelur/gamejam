extends Node2D

## Menü düğmesine yukarıdan inen lastik damga. Kağıda değdiği an `landed` yayar ve kalkmaz.

signal landed

const DROP_HEIGHT := 170.0
const WOOD := Color(0.45, 0.28, 0.14)
const WOOD_LIGHT := Color(0.6, 0.4, 0.22)

var rubber := Color(0.55, 0.08, 0.06)
var ink := Color(0.62, 0.07, 0.05)

var _lift := 1.0
var _squash := 0.0
var _ink := 0.0


func play() -> void:
	var drop := create_tween()
	drop.tween_method(_set_lift, 1.0, 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await drop.finished
	landed.emit()
	var hit := create_tween().set_parallel()
	hit.tween_method(_set_squash, 1.0, 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hit.tween_method(_set_ink, 0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT)


func _set_lift(value: float) -> void:
	_lift = value
	queue_redraw()


func _set_squash(value: float) -> void:
	_squash = value
	queue_redraw()


func _set_ink(value: float) -> void:
	_ink = value
	queue_redraw()


func _draw() -> void:
	var shadow_alpha := 0.4 * (1.0 - _lift * 0.7)
	draw_set_transform(Vector2(0.0, 4.0), 0.0, Vector2(1.0 - _lift * 0.35, 0.22))
	draw_circle(Vector2.ZERO, 92.0, Color(0, 0, 0, shadow_alpha))

	if _ink > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, 95.0 + _ink * 70.0, 0.0, TAU, 48, Color(ink, 0.55 * (1.0 - _ink)), 6.0 * (1.0 - _ink) + 1.0)
		draw_set_transform(Vector2.ZERO)
		for i in 10:
			var angle := TAU * i / 10.0 + 0.3
			var dot := Vector2(cos(angle) * (90.0 + _ink * 45.0), sin(angle) * (16.0 + _ink * 14.0))
			draw_circle(dot, 4.0 * (1.0 - _ink) + 1.0, Color(ink, 0.8 * (1.0 - _ink)))

	var grow := 1.0 + _lift * 0.5
	var body_scale := Vector2(grow * (1.0 + _squash * 0.1), grow * (1.0 - _squash * 0.14))
	draw_set_transform(Vector2(0.0, -_lift * DROP_HEIGHT), 0.0, body_scale)
	draw_rect(Rect2(-80.0, -14.0, 160.0, 14.0), rubber)
	draw_rect(Rect2(-86.0, -46.0, 172.0, 32.0), WOOD)
	draw_rect(Rect2(-86.0, -46.0, 172.0, 5.0), WOOD_LIGHT)
	draw_rect(Rect2(-14.0, -84.0, 28.0, 40.0), WOOD)
	draw_circle(Vector2(0.0, -102.0), 28.0, WOOD)
	draw_circle(Vector2(-8.0, -110.0), 9.0, WOOD_LIGHT)
	draw_set_transform(Vector2.ZERO)
