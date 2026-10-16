class_name CrumpledPaper
extends Polygon2D

## Kâğıdın ekrandaki görüntüsünü bir ızgaraya gerer. amount 0'dan 1'e çıktıkça
## kenarlar içe katlanır, yüzey kırışır ve ızgara top olur.

const LIGHT_DIR := Vector3(-0.45, -0.6, 0.66)

@export var grid := Vector2i(16, 9)
@export var ball_radius := 58.0
@export var wrinkle_depth := 26.0
@export var stretch_passes := 8

var amount := 0.0:
	set(value):
		amount = value
		_rebuild()

var _rest := PackedVector2Array()
var _uv_rest := PackedVector2Array()
var _target := PackedVector2Array()
var _wrinkle := PackedVector2Array()
var _height := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _cells: Array[Vector2i] = []
var _edges: Array[Vector2i] = []
var _edge_rest := PackedFloat32Array()


func capture(paper: Control) -> void:
	var size := paper.size
	var half := size / 2.0
	global_position = paper.get_global_transform() * half
	rotation = paper.rotation

	var tex_size := size
	var shot := paper.get_viewport().get_texture().get_image()
	var to_pixels := paper.get_viewport().get_final_transform() * paper.get_global_transform_with_canvas()
	var region := Rect2i(Rect2(to_pixels.origin, to_pixels.basis_xform(size)))
	if shot and not shot.is_empty():
		region = region.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		if region.has_area():
			texture = ImageTexture.create_from_image(shot.get_region(region))
			tex_size = Vector2(region.size)
	if texture == null:
		color = (paper.get_theme_stylebox("panel") as StyleBoxFlat).bg_color

	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.012
	var corner := half.length()
	for y in grid.y + 1:
		for x in grid.x + 1:
			var p := Vector2(x * size.x / grid.x, y * size.y / grid.y) - half
			var d := p.length() / corner
			_rest.append(p)
			_uv_rest.append((p + half) / size * tex_size)
			# Kenarlar yalnız çevreye değil, topun her yerine katlanır; yoksa orta açıkta kalır.
			var angle := p.angle() + noise.get_noise_2d(p.x, p.y + 500.0) * 2.5
			var spread := clampf(0.5 + noise.get_noise_2d(p.x + 2000.0, p.y) * 1.2, 0.0, 1.0)
			var radius := lerpf(sqrt(spread), pow(d, 0.35), 0.35) * randf_range(0.9, 1.0)
			_target.append(Vector2.from_angle(angle) * ball_radius * radius)
			_wrinkle.append(Vector2(noise.get_noise_2d(p.x, p.y), noise.get_noise_2d(p.x + 1000.0, p.y)) * wrinkle_depth)
			_height.append(noise.get_noise_2d(p.x - 1000.0, p.y) + randf_range(-0.4, 0.4))
			# Kenarlar önce katlanır, orta en son.
			_delay.append((1.0 - d) * 0.45)

	var cols := grid.x + 1
	for y in grid.y + 1:
		for x in grid.x + 1:
			var a := y * cols + x
			if x < grid.x:
				_edges.append(Vector2i(a, a + 1))
			if y < grid.y:
				_edges.append(Vector2i(a, a + cols))
			if x < grid.x and y < grid.y:
				_edges.append(Vector2i(a, a + cols + 1))
	for edge in _edges:
		_edge_rest.append(_rest[edge.x].distance_to(_rest[edge.y]))

	for y in grid.y:
		for x in grid.x:
			_cells.append(Vector2i(x, y))
	# Dıştaki parçalar ortanın üstüne katlanır, o yüzden sonra çizilir.
	var center := Vector2(grid) / 2.0
	_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5) - center).length() < (Vector2(b) + Vector2(0.5, 0.5) - center).length())
	_rebuild()


func _rebuild() -> void:
	if _rest.is_empty():
		return
	var count := _rest.size()
	var pos := PackedVector2Array()
	var z := PackedFloat32Array()
	pos.resize(count)
	z.resize(count)
	for i in count:
		var t := clampf((amount - _delay[i]) / (1.0 - _delay[i]), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		pos[i] = _rest[i].lerp(_target[i], t) + _wrinkle[i] * (sin(PI * t) + 0.15 * t)
		z[i] = _height[i] * wrinkle_depth * t

	# Kâğıt esnemez: hiçbir kenar ilk boyundan uzun olamaz, yoksa üstündeki yazı büyür.
	for _pass in stretch_passes:
		for e in _edges.size():
			var i := _edges[e].x
			var j := _edges[e].y
			var delta := pos[j] - pos[i]
			var length := delta.length()
			if length > _edge_rest[e]:
				var fix := delta * (0.5 * (1.0 - _edge_rest[e] / length))
				pos[i] += fix
				pos[j] -= fix

	var cols := grid.x + 1
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var tris: Array[PackedInt32Array] = []
	for cell in _cells:
		var a := cell.y * cols + cell.x
		for tri in [[a, a + 1, a + cols + 1], [a, a + cols + 1, a + cols]]:
			var p0 := Vector3(pos[tri[0]].x, pos[tri[0]].y, z[tri[0]])
			var p1 := Vector3(pos[tri[1]].x, pos[tri[1]].y, z[tri[1]])
			var p2 := Vector3(pos[tri[2]].x, pos[tri[2]].y, z[tri[2]])
			var normal := (p1 - p0).cross(p2 - p0)
			normal = normal.normalized() if normal.length() > 0.001 else Vector3.BACK
			if normal.z < 0.0:
				normal = -normal
			# Düz kâğıt tam parlak kalır, eğilen yüzler ışığa göre açılır ya da kararır.
			var light := clampf(1.0 + (normal.dot(LIGHT_DIR) - LIGHT_DIR.z) * 1.1, 0.55, 1.1)
			var start := points.size()
			for i in tri:
				points.append(pos[i])
				uvs.append(_uv_rest[i])
				colors.append(Color(light, light, light))
			tris.append(PackedInt32Array([start, start + 1, start + 2]))
	polygon = points
	uv = uvs
	vertex_colors = colors
	polygons = tris
