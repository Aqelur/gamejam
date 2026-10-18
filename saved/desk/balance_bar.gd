class_name DeskBalanceBar
extends Control

## İkonlar yan yana durur. Her ikon alttan değeri kadar dolar, 50 iken yarısı doludur.
## Denge ortadadır, 0 da 100 de kötüdür.

@export var icons: Array[Texture2D] = []
@export var icon_size := Vector2(40.0, 40.0)
@export var icon_spacing := 120.0
@export var strip_color := Color(0.17, 0.1, 0.05)
@export var edge_color := Color(0.09, 0.05, 0.02)
@export var edge_width := 3.0
@export var empty_tint := Color(0.35, 0.35, 0.35)

var _values := PackedFloat32Array()


func set_value(index: int, value: float) -> void:
	if _values.size() < icons.size():
		_values.resize(icons.size())
	_values[index] = clampf(value, 0.0, 100.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), strip_color)
	draw_rect(Rect2(0.0, size.y - edge_width, size.x, edge_width), edge_color)
	var first_x := size.x / 2.0 - icon_spacing * (icons.size() - 1) / 2.0
	var center_y := (size.y - edge_width) / 2.0
	for i in icons.size():
		var value := _values[i] if i < _values.size() else 0.0
		_draw_icon(icons[i], Vector2(first_x + icon_spacing * i, center_y), value)


func _draw_icon(texture: Texture2D, center: Vector2, value: float) -> void:
	var tex_size := texture.get_size()
	var fit := minf(icon_size.x / tex_size.x, icon_size.y / tex_size.y)
	var rect := Rect2(center - tex_size * fit / 2.0, tex_size * fit)
	draw_texture_rect(texture, rect, false, empty_tint)

	var empty := 1.0 - value / 100.0
	var src := Rect2(0.0, tex_size.y * empty, tex_size.x, tex_size.y * (1.0 - empty))
	var dst := Rect2(rect.position.x, rect.position.y + rect.size.y * empty, rect.size.x, rect.size.y * (1.0 - empty))
	draw_texture_rect_region(texture, dst, src)
