extends Control

## Çubuk sırası: 0 Awareness, 1 Money, 2 Infrastructure, 3 Bureaucracy.

const MONEY := 1

@export var first_card: CardData
@export var cards: Array[CardData] = []
## Havuzda ayrıca duran yeni kartlar. Bir kartın takip kartı olanlar buradan güne yazılmaz.
@export var extra_cards: Array[CardData] = []
@export var advisors: Array[AdvisorData] = []
@export var bar_start_value := 50
@export var calendar_days: Array[int] = [1, 8, 15, 22]
@export var base_per_day := 5
@export var offer_days: Array[int] = [8, 15]
## Danışman parası ödendikten sonra Money bunun altına düşemez.
@export var min_money_after_hire := 20
@export var rich_money := 80
@export var rich_surcharge := 5

var _values: Array[int] = []
var _deck: Array[CardData] = []
var _day_queues: Array = []
var _day_index := 0
var _current: CardData
var _day := 0
var _quake_day := 0
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
	_build_days()
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
	if _day_index >= calendar_days.size():
		_hide_card()
		_show_screen("EARTHQUAKE", get_tree().reload_current_scene, "Click to play again")
		return
	_day = calendar_days[_day_index]
	_deck = _day_queues[_day_index]
	_day_index += 1
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


## Deprem günü olmayan, henüz geçmemiş bir takvim günü.
func _safe_day() -> int:
	var days: Array[int] = []
	for d in calendar_days:
		if d != _quake_day and d >= _day:
			days.append(d)
	if days.is_empty():
		return calendar_days[0]
	return days.pick_random()


func _begin_cards() -> void:
	_card.show()
	_card.set_process_unhandled_input(true)
	_next_card()


func _next_card() -> void:
	if _deck.is_empty():
		_hide_card()
		_start_day()
		return
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


## Her güne 5 eski kart. Yeni kartlar günlere eşit bölünür; takip kartı olanlar havuza girmez.
func _build_days() -> void:
	var base: Array[CardData] = []
	base.assign(cards)
	base.shuffle()
	var extras := _starter_extras()
	extras.shuffle()
	var buckets: Array = []
	for _day_i in calendar_days.size():
		buckets.append([] as Array[CardData])
	for i in extras.size():
		(buckets[i % calendar_days.size()] as Array[CardData]).append(extras[i])
	_day_queues.clear()
	var cursor := 0
	for day_i in calendar_days.size():
		var queue: Array[CardData] = []
		var need := base_per_day
		if day_i == 0 and first_card:
			queue.append(first_card)
			need -= 1
		while need > 0 and cursor < base.size():
			queue.append(base[cursor])
			cursor += 1
			need -= 1
		for extra in buckets[day_i] as Array[CardData]:
			var slot := queue.size()
			if day_i == 0 and first_card and not queue.is_empty():
				slot = randi_range(1, queue.size())
			queue.insert(slot, extra)
		_day_queues.append(queue)
	_quake_day = calendar_days[calendar_days.size() - 1]


## Yeni listedeki, başka bir kartın devamı olmayan kartlar.
func _starter_extras() -> Array[CardData]:
	var followed: Array[CardData] = []
	for card in extra_cards:
		if card.denied_follow and card.denied_follow not in followed:
			followed.append(card.denied_follow)
		if card.approved_follow and card.approved_follow not in followed:
			followed.append(card.approved_follow)
	var starters: Array[CardData] = []
	for card in extra_cards:
		if card in followed:
			continue
		starters.append(card)
	return starters


func _on_card_swiped(side: int) -> void:
	var approved := side > 0
	var effect := _current.approved_effect if approved else _current.denied_effect
	for advisor in _hired:
		effect = advisor.modify(_current, approved, effect)
	_apply(effect)
	_queue_follow(_current.approved_follow if approved else _current.denied_follow)
	_next_card()


func _queue_follow(follow: CardData) -> void:
	if follow == null:
		return
	_deck.insert(mini(2, _deck.size()), follow)


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
