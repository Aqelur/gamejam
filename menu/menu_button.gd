@tool
extends Button

## Menü düğmesi. Arkasında kenarlara doğru kaybolan bir şerit vardır. Seçilince şerit ısınır,
## üstünde ve altında altın çizgiler, yazının iki yanında küçük elmaslar belirir.

@export var strip_color := Color(0.06, 0.04, 0.025, 0.55)
@export var selected_strip_color := Color(0.32, 0.19, 0.07, 0.85)
@export var accent_color := Color(0.98, 0.8, 0.42)

static var _fade: GradientTexture2D

var _glow := 0.0
var _strip: Control


func _ready() -> void:
	if _fade == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.72, 1.0])
		gradient.colors = PackedColorArray([
			Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0),
		])
		_fade = GradientTexture2D.new()
		_fade.gradient = gradient
		_fade.width = 256
		_fade.height = 1
	# Şerit yazının arkasında kalsın diye ebeveynin arkasında çizilen ayrı bir düğümdür.
	_strip = Control.new()
	_strip.show_behind_parent = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.draw.connect(_draw_strip)
	add_child(_strip, false, Node.INTERNAL_MODE_FRONT)


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() else 0.0
	if is_equal_approx(_glow, target):
		return
	_glow = move_toward(_glow, target, delta * 6.0)
	queue_redraw()
	_strip.queue_redraw()


func _draw_strip() -> void:
	var g := smoothstep(0.0, 1.0, _glow)
	_strip.draw_texture_rect(_fade, Rect2(Vector2.ZERO, size), false, strip_color.lerp(selected_strip_color, g))
	if g <= 0.0:
		return
	var line := Color(accent_color, 0.8 * g)
	_strip.draw_texture_rect(_fade, Rect2(0.0, 0.0, size.x, 2.0), false, line)
	_strip.draw_texture_rect(_fade, Rect2(0.0, size.y - 2.0, size.x, 2.0), false, line)


func _draw() -> void:
	var g := smoothstep(0.0, 1.0, _glow)
	if g <= 0.0:
		return
	var font := get_theme_font("font")
	var half_text := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x / 2.0
	var gap := 26.0 + (1.0 - g) * 16.0
	for side in [-1.0, 1.0]:
		var center := Vector2(size.x / 2.0 + side * (half_text + gap), size.y / 2.0)
		_draw_diamond(center, 7.5, Color(0.1, 0.06, 0.03, g))
		_draw_diamond(center, 5.0, Color(accent_color, g))


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
	]), color)
