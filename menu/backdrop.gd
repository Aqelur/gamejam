@tool
extends Control

## Giriş ekranının arka plan görseli. Yavaşça bir yandan öbür yana kayar, fareye göre hafifçe
## oynar. Arada bir sarsıntı geçer. Görsele göre noktalar verilir: dumanın çıktığı yerler,
## sarsıntıda dibinden toz kalkan binalar, tozun döküldüğü tavan.

@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var tint := Color(0.82, 0.72, 0.62)
## Görselin ekranı kaplamasının üstüne ne kadar büyütüleceği. Fare ve sarsıntı payı buradan gelir.
@export var overscale := 1.06
## Bir uçtan öbür uca gidip gelme süresi, saniye.
@export var pan_period := 70.0
@export var mouse_parallax := 22.0

@export_group("Points")
## Görsel üzerinde 0-1 arası noktalar.
@export var smoke_points := PackedVector2Array()
## Sarsıntıda çöker gibi olan binalar: aynı sıradaki tepe ve taban noktası.
@export var building_tops := PackedVector2Array()
@export var building_bases := PackedVector2Array()
## Sarsıntıda tozun ve sıva parçalarının döküldüğü bölge. Boyutu sıfırsa dökülmez.
@export var ceiling_area := Rect2()
## Dökülen parçaların düştüğü zemin, görselin yüksekliğine oranla en az ve en çok.
@export var floor_range := Vector2(0.75, 0.98)

@export_group("Effects")
@export var smoke_color := Color(0.42, 0.37, 0.34, 0.5)
@export var dust_color := Color(0.6, 0.5, 0.38, 0.7)
@export var debris_color := Color(0.22, 0.16, 0.12)
@export var quake_interval := Vector2(5.0, 9.0)
@export var quake_duration := 0.9
@export var quake_strength := 8.0
## Sarsıntıda ışığın en fazla ne kadar kararacağı, 0 ise titremez.
@export_range(0.0, 1.0) var light_flicker := 0.0

const COLLAPSE_TIME := 1.5


class Puff:
	var position: Vector2
	var velocity: Vector2
	var age := 0.0
	var life := 4.0
	var start_size := 14.0
	var end_size := 60.0
	var color := Color.WHITE
	var debris := false
	var floor_y := INF


var _blob: GradientTexture2D
var _puffs: Array[Puff] = []
var _time := 0.0
var _parallax := Vector2.ZERO
var _shake := Vector2.ZERO
var _brightness := 1.0
var _quake_left := 0.0
var _next_quake := 0.0
var _next_smoke := PackedFloat32Array()
# Çökmekte olan binaların sırası ve kalan süresi.
var _collapsing := {}


func _ready() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_blob = GradientTexture2D.new()
	_blob.gradient = gradient
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	_next_smoke.resize(smoke_points.size())
	_next_quake = randf_range(2.0, quake_interval.x)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta

	if size.x > 0.0 and size.y > 0.0:
		var mouse := get_local_mouse_position() / size - Vector2(0.5, 0.5)
		var target := -mouse.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * mouse_parallax
		_parallax = _parallax.lerp(target, 1.0 - exp(-4.0 * delta))

	_next_quake -= delta
	if _next_quake <= 0.0:
		_next_quake = randf_range(quake_interval.x, quake_interval.y)
		_quake_left = quake_duration
		_start_collapses()

	if _quake_left > 0.0:
		_quake_left = maxf(_quake_left - delta, 0.0)
		var power := quake_strength * _quake_left / quake_duration
		_shake = Vector2(randf_range(-power, power), randf_range(-power, power) * 0.5)
		if randf() < 0.25:
			_brightness = 1.0 - randf() * light_flicker
	else:
		_shake = Vector2.ZERO
	_brightness = move_toward(_brightness, 1.0, delta * 1.5)

	var draw_size := _draw_size()
	_emit_smoke(delta, draw_size)
	_emit_collapses(delta, draw_size)
	if _quake_left > 0.0:
		_emit_ceiling(draw_size)
	_update_puffs(delta)
	queue_redraw()


func _draw_size() -> Vector2:
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return Vector2.ZERO
	var tex := texture.get_size()
	return tex * maxf(size.x / tex.x, size.y / tex.y) * overscale


func _image_origin(draw_size: Vector2) -> Vector2:
	var extra := draw_size - size
	var swing := 0.5 + 0.5 * sin(_time * TAU / pan_period) if pan_period > 0.0 else 0.5
	return Vector2(-extra.x * swing, -extra.y * 0.5) + _parallax + _shake


func _emit_smoke(delta: float, draw_size: Vector2) -> void:
	if _next_smoke.size() != smoke_points.size():
		_next_smoke.resize(smoke_points.size())
	for i in smoke_points.size():
		_next_smoke[i] -= delta
		if _next_smoke[i] > 0.0:
			continue
		_next_smoke[i] = randf_range(0.12, 0.22)
		_add_puff(smoke_points[i] * draw_size, Vector2(randf_range(8.0, 16.0), randf_range(-34.0, -22.0)),
			randf_range(4.5, 6.0), Vector2(16.0, 120.0), smoke_color)


func _start_collapses() -> void:
	var count := mini(building_tops.size(), building_bases.size())
	if count == 0:
		return
	var picks := 1 if randf() < 0.6 else 2
	for n in picks:
		_collapsing[randi() % count] = COLLAPSE_TIME


func _emit_collapses(delta: float, draw_size: Vector2) -> void:
	for i in _collapsing.keys():
		_collapsing[i] -= delta
		if _collapsing[i] <= 0.0:
			_collapsing.erase(i)
			continue
		var top := building_tops[i] * draw_size
		var base := building_bases[i] * draw_size
		var half_width := (base.y - top.y) * 0.18
		for n in 2:
			var at := Vector2(base.x + randf_range(-1.6, 1.6) * half_width, base.y - randf_range(0.0, 20.0))
			_add_puff(at, Vector2(randf_range(-30.0, 30.0), randf_range(-55.0, -20.0)),
				randf_range(2.0, 3.2), Vector2(30.0, 150.0), dust_color)
		if randf() < 0.7:
			var from := Vector2(top.x + randf_range(-1.0, 1.0) * half_width, lerpf(top.y, base.y, randf() * 0.6))
			var chunk := randf_range(3.0, 7.0)
			_add_puff(from, Vector2(randf_range(-50.0, 50.0), randf_range(-60.0, -10.0)), 1.4,
				Vector2(chunk, chunk), debris_color)
			_puffs.back().debris = true
			_puffs.back().floor_y = base.y


func _emit_ceiling(draw_size: Vector2) -> void:
	if not ceiling_area.has_area():
		return
	for n in 2:
		var at := (ceiling_area.position + ceiling_area.size * Vector2(randf(), randf())) * draw_size
		_add_puff(at, Vector2(randf_range(-10.0, 10.0), randf_range(25.0, 70.0)),
			randf_range(1.8, 2.8), Vector2(12.0, 80.0), dust_color)
	if randf() < 0.6:
		var at := (ceiling_area.position + ceiling_area.size * Vector2(randf(), randf())) * draw_size
		var chunk := randf_range(2.0, 5.0)
		_add_puff(at, Vector2(randf_range(-30.0, 30.0), randf_range(0.0, 40.0)), 2.5,
			Vector2(chunk, chunk), debris_color)
		_puffs.back().debris = true
		_puffs.back().floor_y = randf_range(floor_range.x, floor_range.y) * draw_size.y


func _add_puff(at: Vector2, velocity: Vector2, life: float, sizes: Vector2, color: Color) -> void:
	var puff := Puff.new()
	puff.position = at
	puff.velocity = velocity
	puff.life = life
	puff.start_size = sizes.x
	puff.end_size = sizes.y
	puff.color = color
	_puffs.append(puff)


func _update_puffs(delta: float) -> void:
	for i in range(_puffs.size() - 1, -1, -1):
		var puff := _puffs[i]
		puff.age += delta
		if puff.age >= puff.life or puff.position.y > puff.floor_y:
			_puffs.remove_at(i)
			continue
		puff.position += puff.velocity * delta
		if puff.debris:
			puff.velocity.y += 420.0 * delta
		else:
			puff.velocity.y *= 1.0 - 0.25 * delta


func _draw() -> void:
	var draw_size := _draw_size()
	if draw_size == Vector2.ZERO:
		return
	var origin := _image_origin(draw_size)
	var lit := Color(tint.r * _brightness, tint.g * _brightness, tint.b * _brightness, tint.a)
	draw_texture_rect(texture, Rect2(origin, draw_size), false, lit)
	for puff in _puffs:
		var center := origin + puff.position
		if puff.debris:
			draw_rect(Rect2(center, Vector2.ONE * puff.start_size), puff.color)
			continue
		var t := puff.age / puff.life
		var diameter := lerpf(puff.start_size, puff.end_size, t)
		var alpha := puff.color.a * minf(t * 6.0, 1.0) * (1.0 - t)
		var rect := Rect2(center - Vector2.ONE * diameter / 2.0, Vector2.ONE * diameter)
		draw_texture_rect(_blob, rect, false, Color(puff.color, alpha))
