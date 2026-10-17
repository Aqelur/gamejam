extends Node3D
## Stamping a proposal at the desk.
##
## A proposal arrives on the paper. The player picks up one of the two stamps
## and hits the paper with it: APPROVED (green, left) or DENIED (red, right).
## The ink mark stays on the paper, the paper goes off the desk (approved
## slides left, denied is swept off to the right), and the next proposal can
## come in.
##
## Picking up a stamp: press the left mouse button on it and drag it over the
## paper, then let go. Or click it once, move over the paper and click again.
## Letting go anywhere else puts the stamp back.
##
## president_room.gd builds the stamps and the paper (so they show in the
## editor too) and creates this node at runtime only. Everything here is in the
## room's own coordinates; this node sits at the room's origin.

## A stamp hit the paper. The proposal is decided.
signal stamped(approved: bool)
## The stamp being held moved over the paper (1 = APPROVED, 0 = DENIED) or
## off it / was put down (-1). The room shows which stats it would touch.
signal aim_changed(choice: int)

const DESK_TOP := 0.78
## Height the held stamp floats at, above the desk.
const HOLD_Y := DESK_TOP + 0.09
## Where a held stamp may go (x, z), so it can't be dragged off the desk.
const REACH := Rect2(-1.05, 0.0, 2.1, 0.86)
const INK_APPROVED := Color(0.13, 0.52, 0.27)
const INK_DENIED := Color(0.78, 0.13, 0.13)

var room                     # president_room.gd (untyped: it is a @tool script)
## True while a proposal is on the paper, waiting for a stamp.
var has_proposal := false

var _held: Node3D = null
var _hover: Node3D = null
var _click_mode := false     # picked up with a click (not a drag): the next click stamps
var _press_pos := Vector2.ZERO
var _busy := false           # a stamp is slamming down or flying home
var _paper_tween: Tween
var _shake_tween: Tween
var _aim := -1


func setup(p_room) -> void:
	room = p_room
	for s: Node3D in room.stamps:
		s.set_meta("home", s.position)
	room.paper.visible = false


# ================================================================ proposals

## Slide a proposal onto the desk from the visitor's side.
func present() -> void:
	has_proposal = true
	var paper: Node3D = room.paper
	var home: Vector3 = room.paper_home
	_kill(_paper_tween)
	paper.visible = true
	paper.position = home + Vector3(0.05, 0.03, -0.75)
	paper.rotation_degrees = Vector3(0, 12.0, 0)
	_paper_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_paper_tween.tween_property(paper, "position", home, 0.55)
	_paper_tween.tween_property(paper, "rotation_degrees", Vector3(0, room.PAPER_YAW, 0), 0.55)


## Take the stamped paper off the desk.
func _remove_paper(approved: bool) -> void:
	var paper: Node3D = room.paper
	_kill(_paper_tween)
	_paper_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if approved:
		# filed: slides left, off the pad and out of view
		_paper_tween.tween_property(paper, "position", paper.position + Vector3(-0.85, 0.0, -0.2), 0.5)
		_paper_tween.tween_property(paper, "rotation_degrees:y", paper.rotation_degrees.y + 8.0, 0.5)
	else:
		# rejected: swept off to the right with a spin
		_paper_tween.tween_property(paper, "position", paper.position + Vector3(0.95, 0.05, -0.1), 0.45)
		_paper_tween.tween_property(paper, "rotation_degrees:y", paper.rotation_degrees.y - 70.0, 0.45)
	_paper_tween.chain().tween_callback(func() -> void: paper.visible = false)


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if room == null or room.camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _busy:
			return
		if event.pressed:
			_press_pos = event.position
			if _held:
				# second click of click-to-pick-up
				_drop()
			else:
				var s := _stamp_under(event.position)
				if s:
					_pick_up(s)
			get_viewport().set_input_as_handled()
		elif _held and not _click_mode:
			if event.position.distance_to(_press_pos) < 8.0:
				_click_mode = true   # it was a click: keep holding until the next click
			else:
				_drop()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if room == null or room.camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	if _held and not _busy:
		var p = _desk_point(mouse, HOLD_Y)
		if p != null:
			var target := Vector3(clampf(p.x, REACH.position.x, REACH.end.x), HOLD_Y,
				clampf(p.z, REACH.position.y, REACH.end.y))
			_held.position = _held.position.lerp(target, 0.45)
			# lean a little toward where it is heading
			var lean: Vector3 = target - _held.position
			_held.rotation = Vector3(clampf(lean.z * 6.0, -0.25, 0.25), 0.0, clampf(-lean.x * 6.0, -0.25, 0.25))
		var over: bool = has_proposal and room.paper.visible \
			and _over_paper(Vector3(_held.position.x, 0, _held.position.z))
		_set_aim((1 if _held.get_meta("approved") else 0) if over else -1)
		return
	_set_aim(-1)
	# hover: the stamp under the mouse lifts a little
	var hover: Node3D = null
	if not _busy and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		hover = _stamp_under(mouse)
	if hover != _hover:
		_hover = hover
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hover else Input.CURSOR_ARROW)
	if not _busy:
		for s: Node3D in room.stamps:
			var home: Vector3 = s.get_meta("home")
			var lift := 0.025 if s == _hover else 0.0
			s.position = s.position.lerp(home + Vector3(0, lift, 0), 0.3)
			s.rotation = s.rotation.lerp(Vector3.ZERO, 0.3)


func _pick_up(s: Node3D) -> void:
	_held = s
	_click_mode = false
	_hover = null
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)


func _drop() -> void:
	var s := _held
	_held = null
	_click_mode = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	var spot := Vector3(s.position.x, 0, s.position.z)
	if has_proposal and room.paper.visible and _over_paper(spot):
		_slam(s, spot)
	else:
		_fly_home(s)


# ================================================================ stamping

func _slam(s: Node3D, spot: Vector3) -> void:
	_busy = true
	has_proposal = false
	var approved: bool = s.get_meta("approved")
	var paper_top: float = room.paper.global_position.y + 0.0045
	var down := Vector3(spot.x, to_local(Vector3(0, paper_top, 0)).y, spot.z)
	var t := create_tween()
	# wind up, then hit
	t.tween_property(s, "position", Vector3(spot.x, HOLD_Y + 0.05, spot.z), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(s, "rotation", Vector3.ZERO, 0.09)
	t.tween_property(s, "position", down, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		_ink(spot, approved)
		_shake()
		stamped.emit(approved))
	# press, lift, home
	t.tween_property(s, "position", down + Vector3(0, -0.002, 0), 0.12)
	t.tween_property(s, "position", Vector3(spot.x, HOLD_Y + 0.02, spot.z), 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "position", s.get_meta("home"), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: _busy = false)
	# let the ink be seen for a moment, then the paper goes
	get_tree().create_timer(0.9).timeout.connect(_remove_paper.bind(approved))


func _fly_home(s: Node3D) -> void:
	_busy = true
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "position", s.get_meta("home"), 0.25)
	t.parallel().tween_property(s, "rotation", Vector3.ZERO, 0.25)
	t.tween_callback(func() -> void: _busy = false)


## Leave the ink mark on the paper where the stamp came down.
func _ink(spot: Vector3, approved: bool) -> void:
	var paper: Node3D = room.paper
	var ink := INK_APPROVED if approved else INK_DENIED
	var text := "APPROVED" if approved else "DENIED"
	var mark := Node3D.new()
	mark.name = "StampMark"
	paper.add_child(mark)
	# where it came down, kept inside the sheet so the whole mark prints
	var local := paper.to_local(global_transform * spot)
	var room_half: Vector2 = room.PAPER_SIZE * 0.5 - room.STAMP_FACE * 0.5 - Vector2(0.012, 0.012)
	mark.position = Vector3(clampf(local.x, -room_half.x, room_half.x), 0.0045,
		clampf(local.z, -room_half.y, room_half.y))
	mark.rotation_degrees.y = randf_range(-9.0, 9.0)

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(ink, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# double border, like a rubber stamp
	var w: float = room.STAMP_FACE.x
	var d: float = room.STAMP_FACE.y
	for k in 2:
		var inset := 0.0 if k == 0 else 0.006
		var bar := 0.0035 if k == 0 else 0.0015
		var ww := w - inset * 2.0
		var dd := d - inset * 2.0
		for side in [-1.0, 1.0]:
			_flat_bar(mark, Vector3(ww, 0.0004, bar), Vector3(0, 0, side * (dd - bar) * 0.5), m)
			_flat_bar(mark, Vector3(bar, 0.0004, dd), Vector3(side * (ww - bar) * 0.5, 0, 0), m)
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 0
	l.pixel_size = (w - 0.03) / (64.0 * 0.62 * text.length())
	l.modulate = Color(ink, 0.9)
	l.shaded = false
	l.double_sided = false
	l.rotation_degrees.x = -90.0
	l.position.y = 0.0005
	mark.add_child(l)
	# a quick squash so it reads as a hit
	mark.scale = Vector3(1.12, 1.0, 1.12)
	create_tween().tween_property(mark, "scale", Vector3.ONE, 0.12)


func _flat_bar(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _shake() -> void:
	var cam: Camera3D = room.camera
	_kill(_shake_tween)
	_shake_tween = create_tween()
	_shake_tween.tween_property(cam, "v_offset", -0.006, 0.04)
	_shake_tween.tween_property(cam, "v_offset", 0.003, 0.06)
	_shake_tween.tween_property(cam, "v_offset", 0.0, 0.08)


# ================================================================ picking

## The stamp whose handle is under the screen point, or null.
func _stamp_under(screen: Vector2) -> Node3D:
	var cam: Camera3D = room.camera
	var best: Node3D = null
	var best_d := INF
	for s: Node3D in room.stamps:
		# test the whole stamp: from the rubber up to the knob
		for h in [0.02, 0.06, 0.1]:
			var p := s.global_position + Vector3(0, h, 0)
			if cam.is_position_behind(p):
				continue
			var c := cam.unproject_position(p)
			var r := c.distance_to(cam.unproject_position(p + cam.global_basis.x * 0.05))
			var d := c.distance_to(screen)
			if d < r and d < best_d:
				best_d = d
				best = s
	return best


## Where the mouse ray meets the horizontal plane at height y (room coords).
func _desk_point(screen: Vector2, y: float) -> Variant:
	var cam: Camera3D = room.camera
	var from := to_local(cam.project_ray_origin(screen))
	var dir := global_basis.inverse() * cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var k := (y - from.y) / dir.y
	if k < 0.0:
		return null
	return from + dir * k


func _over_paper(spot: Vector3) -> bool:
	var paper: Node3D = room.paper
	var local := paper.to_local(global_transform * spot)
	var half: Vector2 = room.PAPER_SIZE * 0.5 + Vector2(0.03, 0.03)
	return absf(local.x) < half.x and absf(local.z) < half.y


func _set_aim(choice: int) -> void:
	if choice != _aim:
		_aim = choice
		aim_changed.emit(choice)


func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()
