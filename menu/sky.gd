@tool
extends Control

## Gökyüzü: üst yarıda yanıp sönen yıldızlar, yavaşça süzülen yumuşak bulutlar.

@export var star_count := 80
@export var star_color := Color(1.0, 0.93, 0.8, 0.85)
@export var cloud_count := 6
@export var cloud_color := Color(0.62, 0.45, 0.3, 0.14)
@export var cloud_speed := 9.0
@export var layout_seed := 3

var _rng := RandomNumberGenerator.new()
# Yıldız: x ve y ekranın oranı, z yarıçap. Yanında yanıp sönme evresi ve hızı.
var _stars := PackedVector3Array()
var _star_twinkle := PackedVector2Array()
# Bulut: x piksel, y ekranın oranı, z genişlik, w hız çarpanı.
var _clouds: Array[Vector4] = []
var _blob: GradientTexture2D
var _time := 0.0


func _ready() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_blob = GradientTexture2D.new()
	_blob.gradient = gradient
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	resized.connect(_build)
	_build()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	var wrap_width := size.x + 900.0
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.x = fposmod(cloud.x + cloud_speed * cloud.w * delta + 450.0, wrap_width) - 450.0
		_clouds[i] = cloud
	queue_redraw()


func _build() -> void:
	_rng.seed = layout_seed
	_stars.clear()
	_star_twinkle.clear()
	for i in star_count:
		var y := pow(_rng.randf(), 1.6) * 0.5
		_stars.append(Vector3(_rng.randf(), y, _rng.randf_range(0.7, 1.8)))
		_star_twinkle.append(Vector2(_rng.randf() * TAU, _rng.randf_range(0.8, 2.6)))
	_clouds.clear()
	for i in cloud_count:
		var x := _rng.randf_range(-300.0, size.x + 300.0)
		_clouds.append(Vector4(x, _rng.randf_range(0.08, 0.5), _rng.randf_range(320.0, 640.0), _rng.randf_range(0.5, 1.5)))
	queue_redraw()


func _draw() -> void:
	for i in _stars.size():
		var star := _stars[i]
		var twinkle := _star_twinkle[i]
		var glow := 0.55 + 0.45 * sin(_time * twinkle.y + twinkle.x)
		var color := Color(star_color, star_color.a * glow)
		draw_circle(Vector2(star.x * size.x, star.y * size.y), star.z, color)
	for cloud in _clouds:
		var center := Vector2(cloud.x, cloud.y * size.y)
		var w := cloud.z
		_draw_blob(center, Vector2(w, w * 0.22))
		_draw_blob(center + Vector2(-w * 0.22, w * 0.03), Vector2(w * 0.55, w * 0.18))
		_draw_blob(center + Vector2(w * 0.2, -w * 0.04), Vector2(w * 0.5, w * 0.2))


func _draw_blob(center: Vector2, blob_size: Vector2) -> void:
	draw_texture_rect(_blob, Rect2(center - blob_size / 2.0, blob_size), false, cloud_color)
