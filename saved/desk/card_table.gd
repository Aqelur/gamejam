extends Control

const MARK_APPROVED: Texture2D = preload("res://saved/desk/images/stamp_approved.png")
const MARK_DENIED: Texture2D = preload("res://saved/desk/images/stamp_denied.png")

@export var cards: Array[DeskCardData] = []
@export var mark_hold_time := 0.45
@export var paper_exit_duration := 0.35
@export var paper_enter_duration := 0.25
@export var mark_max_tilt_degrees := 12.0
@export var crumple_duration := 0.7
@export var throw_duration := 0.55
@export var paper_ball_radius := 58.0
@export var bar_start_value := 50.0

var _index := 0
var _busy := false
var _paper_rest := Vector2.ZERO

@onready var _paper: Panel = %Paper
@onready var _text_label: Label = %TextLabel
@onready var _mark: TextureRect = %Mark
@onready var _person_image: TextureRect = %PersonImage
@onready var _name_label: Label = %NameLabel
@onready var _balance: DeskBalanceBar = %BalanceStrip


func _ready() -> void:
	for i in _balance.icons.size():
		_balance.set_value(i, bar_start_value)
	_paper_rest = _paper.position
	_mark.hide()
	for stamp: DeskStamp in [%AcceptStamp, %RejectStamp]:
		stamp.dropped.connect(_on_stamp_dropped)
	_show_card()


func _show_card() -> void:
	if cards.is_empty():
		_text_label.text = ""
		_name_label.text = ""
		_person_image.texture = null
		return
	var card := cards[_index]
	_text_label.text = card.text
	_name_label.text = card.character_name
	_person_image.texture = card.image


func _on_stamp_dropped(stamp: DeskStamp) -> void:
	var point := stamp.get_global_rect().get_center()
	stamp.return_home()
	if _busy or cards.is_empty() or not _paper.get_global_rect().has_point(point):
		return
	_busy = true
	_press_mark(stamp, point)
	await get_tree().create_timer(mark_hold_time).timeout
	await _next_record(stamp.stamp_text == "DENIED")
	_busy = false


func _press_mark(stamp: DeskStamp, point: Vector2) -> void:
	_mark.texture = MARK_APPROVED if stamp.stamp_text == "APPROVED" else MARK_DENIED
	_mark.modulate = Color(1, 1, 1, 0.92)
	var top_left := point - _paper.global_position - _mark.size / 2.0
	_mark.position = top_left.clamp(Vector2.ZERO, _paper.size - _mark.size)
	_mark.rotation = deg_to_rad(randf_range(-mark_max_tilt_degrees, mark_max_tilt_degrees))
	_mark.show()


## Kişi ve kâğıt aynı kayda aittir, birlikte çıkar ve birlikte gelir.
func _next_record(crumple: bool) -> void:
	if crumple:
		await _crumple_and_throw()
	else:
		await _slide_out()

	_index = (_index + 1) % cards.size()
	_show_card()
	_mark.hide()
	_paper.position = _paper_rest + Vector2(0.0, 40.0)
	_paper.rotation = 0.0
	_paper.scale = Vector2.ONE
	_paper.modulate = Color(1, 1, 1, 0)
	var appear := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	appear.tween_property(_paper, "position", _paper_rest, paper_enter_duration)
	appear.tween_property(_paper, "modulate:a", 1.0, paper_enter_duration)
	appear.tween_property(_person_image, "modulate:a", 1.0, paper_enter_duration)
	appear.tween_property(_name_label, "modulate:a", 1.0, paper_enter_duration)
	await appear.finished


func _slide_out() -> void:
	var out := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out.tween_property(_paper, "position", _paper_rest + Vector2(-900.0, -60.0), paper_exit_duration)
	out.tween_property(_paper, "rotation", deg_to_rad(-15.0), paper_exit_duration)
	out.tween_property(_paper, "modulate:a", 0.0, paper_exit_duration)
	out.tween_property(_person_image, "modulate:a", 0.0, paper_exit_duration)
	out.tween_property(_name_label, "modulate:a", 0.0, paper_exit_duration)
	await out.finished


## Kâğıt yerinde buruşup top olur, top kavis çizerek ekrandan atılır.
func _crumple_and_throw() -> void:
	var person := create_tween().set_parallel()
	person.tween_property(_person_image, "modulate:a", 0.0, crumple_duration + throw_duration)
	person.tween_property(_name_label, "modulate:a", 0.0, crumple_duration + throw_duration)

	var ball := DeskCrumpledPaper.new()
	ball.ball_radius = paper_ball_radius
	add_child(ball)
	ball.capture(_paper)
	create_tween().tween_property(_paper, "modulate:a", 0.0, 0.08)

	# Eller kâğıdı tek hamlede değil, birkaç sıkışta topak yapar.
	var squeezes: Array[float] = [0.3, 0.55, 0.8, 1.0]
	var step_time := crumple_duration / squeezes.size()
	var crumple := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in squeezes.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		crumple.tween_property(ball, "amount", squeezes[i], step_time)
		crumple.parallel().tween_property(ball, "rotation", deg_to_rad(randf_range(4.0, 12.0)) * side, step_time)
	await crumple.finished

	var start := ball.global_position
	var end := Vector2(get_viewport_rect().size.x + paper_ball_radius * 3.0, start.y + 140.0)
	var peak := Vector2(lerpf(start.x, end.x, 0.5), start.y - 260.0)
	var throw := create_tween().set_parallel()
	throw.tween_method(func(t: float) -> void:
		ball.global_position = start.lerp(peak, t).lerp(peak.lerp(end, t), t),
		0.0, 1.0, throw_duration)
	throw.tween_property(ball, "rotation", ball.rotation + TAU * 2.0, throw_duration)
	throw.tween_property(ball, "scale", Vector2(0.8, 0.8), throw_duration)
	await throw.finished
	ball.queue_free()
