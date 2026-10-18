class_name CardData
extends Resource

## Etki sırası: x Awareness, y Money, z Infrastructure, w Bureaucracy.

@export var id: String = ""
@export var character_name: String = ""
@export var image: Texture2D
@export_multiline var text: String = ""
@export var left_choice: String = "DENIED"
@export var right_choice: String = "APPROVED"
@export var denied_effect := Vector4i.ZERO
@export var approved_effect := Vector4i.ZERO
