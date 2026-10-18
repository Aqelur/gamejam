class_name AdvisorOffer
extends Control

signal closed(hired: bool)

@onready var _portrait: TextureRect = %Portrait
@onready var _says: Label = %Says
@onready var _effects: Label = %Effects
@onready var _price: Label = %Price
@onready var _warning: Label = %Warning
@onready var _hire: Button = %HireButton
@onready var _pass: Button = %PassButton


func _ready() -> void:
	_hire.pressed.connect(_close.bind(true))
	_pass.pressed.connect(_close.bind(false))


func open(advisor: AdvisorData, price: int, surcharged: bool, affordable: bool) -> void:
	_portrait.texture = advisor.portrait
	_says.text = "\"%s\"" % advisor.says
	_effects.text = advisor.effects_text
	_price.text = "Cost: %d Money" % price
	if surcharged:
		_price.text += "  (Word got around that the treasury is full.)"
	_warning.visible = not affordable
	_hire.disabled = not affordable
	show()


func _close(hired: bool) -> void:
	hide()
	closed.emit(hired)
