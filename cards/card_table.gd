extends Control

## Çubuk sırası: 0 Awareness, 1 Money, 2 Infrastructure, 3 Bureaucracy.

const MONEY := 1

@export var first_card: CardData
@export var cards: Array[CardData] = []
@export var advisors: Array[AdvisorData] = []
@export var bar_start_value := 50
@export var cards_per_day := 4
@export var quake_day_min := 7
@export var quake_day_max := 9
@export var offer_days: Array[int] = [3, 5]
## Danışman parası ödendikten sonra Money bunun altına düşemez.
@export var min_money_after_hire := 20
@export var rich_money := 80
@export var rich_surcharge := 5

var _values: Array[int] = []
var _deck: Array[CardData] = []
var _current: CardData
var _day := 0
var _cards_today := 0
var _quake_day := 0
## Deprem günü kaçıncı karttan sonra geleceği.
var _quake_after := 0
var _offered: Array[AdvisorData] = []
var _hired: Array[AdvisorData] = []
var _screen_done: Callable

@onready var _card: SwipeCard = %Card
@onready var _text_label: Label = %TextLabel
@onready var _note_label: Label = %NoteLabel
@onready var _name_label: Label = %NameLabel
@onready var _balance: BalanceBar = %BalanceStrip
@onready var _day_screen: Control = %DayScreen
@onready var _day_label: Label = %DayLabel
@onready var _day_hint: Label = %DayHint
@onready var _offer: AdvisorOffer = %AdvisorOffer
@onready var _shelf: Container = %AdvisorShelf


func _ready() -> void:
	randomize()
	for i in _balance.icons.size():
		_values.append(bar_start_value)
		_balance.set_value(i, bar_start_value)
	_quake_day = randi_range(quake_day_min, quake_day_max)
	_quake_after = randi_range(1, cards_per_day - 1)
	if first_card:
		_deck.append(first_card)
	_refill_deck()
	_card.swiped.connect(_on_card_swiped)
	_offer.closed.connect(_on_offer_closed)
	_day_screen.gui_input.connect(_on_day_screen_input)
	_offer.hide()
	_hide_card()
	_start_day()


func _unhandled_input(event: InputEvent) -> void:
	if _day_screen.visible and (event.is_action_pressed("action") or event.is_action_pressed("jump")):
		_close_day_screen()


func _start_day() -> void:
	_day += 1
	_cards_today = 0
	_show_screen("Day %d" % _day, _begin_day)


func _begin_day() -> void:
	if _day in offer_days:
		var left := advisors.filter(func(a: AdvisorData) -> bool: return not (a in _offered))
		if not left.is_empty():
			var advisor: AdvisorData = left.pick_random()
			_offered.append(advisor)
			var price := _price_of(advisor)
			_offer.set_meta("advisor", advisor)
			_offer.set_meta("price", price)
			_offer.open(advisor, price, price != advisor.price, _values[MONEY] - price >= min_money_after_hire)
			return
	_begin_cards()


func _price_of(advisor: AdvisorData) -> int:
	if _values[MONEY] >= rich_money:
		return advisor.price + rich_surcharge
	return advisor.price


func _on_offer_closed(hired: bool) -> void:
	if hired:
		var advisor: AdvisorData = _offer.get_meta("advisor")
		_apply(Vector4i(0, -int(_offer.get_meta("price")), 0, 0))
		_hired.append(advisor)
		_add_to_shelf(advisor)
	_begin_cards()


func _add_to_shelf(advisor: AdvisorData) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150.0, 0.0)
	var picture := TextureRect.new()
	picture.texture = advisor.portrait
	picture.custom_minimum_size = Vector2(150.0, 200.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(picture)
	if advisor.id == "usumezsoy":
		var hint := Label.new()
		hint.text = "\"Not on day %d.\nI am sure of it.\"" % _safe_day()
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 16)
		hint.add_theme_color_override("font_color", Color(0.96, 0.85, 0.55))
		box.add_child(hint)
	_shelf.add_child(box)


## Deprem günü olabilecek ama olmayan, henüz geçmemiş bir gün.
func _safe_day() -> int:
	var days: Array[int] = []
	for d in range(quake_day_min, quake_day_max + 1):
		if d != _quake_day and d >= _day:
			days.append(d)
	if days.is_empty():
		return _quake_day - 1
	return days.pick_random()


func _begin_cards() -> void:
	_card.show()
	_card.set_process_unhandled_input(true)
	_next_card()


func _next_card() -> void:
	if _day == _quake_day and _cards_today == _quake_after:
		_hide_card()
		_show_screen("EARTHQUAKE", get_tree().reload_current_scene, "Click to play again")
		return
	if _cards_today >= cards_per_day:
		_hide_card()
		_start_day()
		return
	if _deck.is_empty():
		_refill_deck()
	_current = _deck.pop_front()
	_text_label.text = _current.text
	_name_label.text = _current.character_name
	var notes: PackedStringArray = []
	for advisor in _hired:
		var note := advisor.card_note(_current)
		if note != "":
			notes.append(note)
	_note_label.text = "\n".join(notes)
	_card.show_data(_current)


func _refill_deck() -> void:
	var fresh := cards.duplicate()
	fresh.shuffle()
	if fresh.size() > 1 and fresh[0] == _current:
		fresh.push_back(fresh.pop_front())
	_deck.append_array(fresh)


func _on_card_swiped(side: int) -> void:
	var approved := side > 0
	var effect := _current.approved_effect if approved else _current.denied_effect
	for advisor in _hired:
		effect = advisor.modify(_current, approved, effect)
	_apply(effect)
	_cards_today += 1
	_next_card()


func _apply(effect: Vector4i) -> void:
	for i in _values.size():
		_values[i] = clampi(_values[i] + effect[i], 0, 100)
		_balance.set_value(i, _values[i])


func _hide_card() -> void:
	_card.hide()
	_card.set_process_unhandled_input(false)
	_text_label.text = ""
	_note_label.text = ""
	_name_label.text = ""


func _show_screen(title: String, on_done: Callable, hint := "Click to continue") -> void:
	_day_label.text = title
	_day_hint.text = hint
	_screen_done = on_done
	_day_screen.show()


func _on_day_screen_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close_day_screen()


func _close_day_screen() -> void:
	_day_screen.hide()
	_screen_done.call()
