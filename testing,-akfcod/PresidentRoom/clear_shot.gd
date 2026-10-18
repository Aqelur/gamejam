extends RefCounted
## Keeps buildings (and lamp posts, trees...) out of the way of the ending's
## camera shots.
##
## Every place in the ending (old_quarter_works.gd, police_rescue.gd,
## quake_fire.gd, central_park_drill.gd, park_tents.gd, hospital_quake.gd,
## room_quake.gd) hands day_cycle.gd a shot as [eye, look, creep]. Those
## spots are worked out from where things are, not from what stands around
## them, so now and then something sits right between the camera and what it
## is meant to show (the rescue pile behind a row of houses, the hospital's
## forecourt behind a skyscraper, a lamp post down the middle of the park...).
##
##   fix(cam, shot, tile, subjects)
##                          the same shot if nothing is in the way; otherwise
##                          the camera swung round the look point (and, if it
##                          has to, raised or brought closer) to the spot with
##                          a clear view that changes the shot least, creep
##                          turned with it. `subjects`: nodes the shot is of
##                          (the burning row, the hospital); their walls are
##                          never in the way
##
## "In the way" is tested from the eye, from halfway along the creep and from
## its end, with rays to a small patch round the look point:
##   - buildings, through the city's collision (they are StaticBody3D). The
##     building the look point is on or in is the subject, not in the way, and
##     so is any wall just in front of the look point (SUBJECT_DEPTH); the
##     ground, people, debris and anything else that moves are ignored.
##   - props near the lens (lamp posts, trees, poles, signs: tall, thin and
##     with no collision), through their bounding boxes.
## A building filling much of the near part of the picture (a roof right under
## the lens) spoils the shot as well.

## Rays aimed at a patch round the look point, this many tiles across.
const PATCH := 0.6
## A shot is clear if at most this share of those rays is stopped.
const CLEAR := 0.2
## Anything within this many tiles of the look point is part of what's shown.
const SUBJECT_REACH := 0.35
## A wall less than this many tiles in front of the point a ray is aimed at
## is the face of what's shown (the look point often sits just behind it),
## not something in the way.
const SUBJECT_DEPTH := 0.8
## Close up: a building (or a prop by the lens) filling more than this share
## of the picture nearer than FOREGROUND_DEPTH of the way to the look point (a
## roof right under the lens, a tower across a quarter of the frame, a lamp
## post down the middle) spoils the shot too.
const FOREGROUND := 0.14
const FOREGROUND_DEPTH := 0.6
## Props count when they stand within this many tiles of the lens, are at
## least PROP_TALL tiles high and at most PROP_THIN tiles across.
const PROP_NEAR := 1.5
const PROP_TALL := 0.2
const PROP_THIN := 0.8
## Turns tried round the look point (degrees), lifts and distances (a share
## of the original).
const YAWS := [0.0, 8.0, -8.0, 14.0, -14.0, 20.0, -20.0, 30.0, -30.0, 40.0, -40.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]
const LIFTS := [0.0, 12.0, 24.0, 36.0]
const REACH := [1.0, 0.8, 0.65]
## Never steeper than this (degrees below the horizon).
const MAX_PITCH := 72.0


static func fix(cam: Camera3D, shot: Array, tile: float, subjects: Array = []) -> Array:
	if cam == null or not cam.is_inside_tree() or shot.size() < 2:
		return shot
	var eye: Vector3 = shot[0]
	var look: Vector3 = shot[1]
	var creep: Vector3 = shot[2] if shot.size() > 2 else Vector3.ZERO
	var space := cam.get_world_3d().direct_space_state
	var d := eye - look
	var dist := d.length()
	if space == null or dist < 0.01:
		return shot
	var subject := _subject(space, look, tile)
	for n in subjects:
		_collect(n as Node, subject)
	var ctx := {
		"space": space, "subject": subject, "tile": tile, "fov": cam.fov,
		"props": _props(cam.get_parent(), look, dist + creep.length() + PROP_NEAR * tile, tile, subjects),
	}
	if _ok(_score(ctx, eye, look, creep)):
		return shot

	# every spot round the look point, then the clear one that changes the
	# shot least (and leaves the least in front of the lens); if none is
	# clear, the least blocked
	var yaw0 := atan2(d.x, d.z)
	var pitch0 := asin(clampf(d.y / dist, -1.0, 1.0))
	var best: Array = shot
	var best_cost := INF
	for reach: float in REACH:
		for lift: float in LIFTS:
			var pitch := minf(pitch0 + deg_to_rad(lift), deg_to_rad(MAX_PITCH))
			if lift > 0.0 and pitch <= pitch0:
				continue
			for yaw_deg: float in YAWS:
				var yaw := yaw0 + deg_to_rad(yaw_deg)
				var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				var e := look + dir * dist * reach
				var c := creep.rotated(Vector3.UP, deg_to_rad(yaw_deg)) * reach
				var s := _score(ctx, e, look, c)
				var cost := s.x * 2.0 + s.y + absf(yaw_deg) / 180.0 * 0.4 + lift / 36.0 * 0.25 + (1.0 - reach) * 0.8
				if not _ok(s):
					cost += 10.0
				if cost < best_cost:
					best_cost = cost
					best = [e, look, c]
	return best


static func _ok(s: Vector2) -> bool:
	return s.x <= CLEAR and s.y <= FOREGROUND


## How blocked the shot is: x the view of `look` (0..1), y the picture close
## up (0..1); the worst of the start of the shot, halfway along its creep and
## the end. Inside a building is (1, 1).
static func _score(ctx: Dictionary, eye: Vector3, look: Vector3, creep: Vector3) -> Vector2:
	var worst := Vector2.ZERO
	for k: float in [0.0, 0.5, 1.0]:
		var e := eye + creep * k
		if _inside(ctx, e):
			return Vector2.ONE
		worst.x = maxf(worst.x, _blocked(ctx, e, look))
		worst.y = maxf(worst.y, _foreground(ctx, e, look))
	return worst


## Share of the rays from `eye` to a patch round `look` that something stops.
static func _blocked(ctx: Dictionary, eye: Vector3, look: Vector3) -> float:
	var tile: float = ctx.tile
	var fwd := look - eye
	var dist := fwd.length()
	if dist < 0.01:
		return 0.0
	var b := _frame(fwd)
	# the patch grows a little with distance, like what the shot takes in
	var r := PATCH * 0.5 * tile * clampf(dist / (4.0 * tile), 0.6, 2.0)
	var points: Array[Vector3] = [look]
	for x: float in [-1.0, 0.0, 1.0]:
		for y: float in [0.0, 1.0]:
			if x == 0.0 and y == 0.0:
				continue
			points.append(look + b.x * x * r + b.y * y * r)
	var near := _near(ctx, eye)
	var stopped := 0
	for p in points:
		var to := p - (p - eye).normalized() * SUBJECT_DEPTH * tile
		if (to - eye).dot(p - eye) <= 0.0:
			continue
		if _hit(ctx, eye, to) or _hit_prop(near, eye, to):
			stopped += 1
	return float(stopped) / float(points.size())


## Share of the picture (a 5 x 3 grid of rays) stopped by a building, or a
## prop by the lens, in the near part of the view, before FOREGROUND_DEPTH of
## the way to `look`.
static func _foreground(ctx: Dictionary, eye: Vector3, look: Vector3) -> float:
	var fwd := look - eye
	var dist := fwd.length()
	if dist < 0.01:
		return 0.0
	var b := _frame(fwd)
	fwd /= dist
	var half := tan(deg_to_rad(float(ctx.fov)) * 0.5)
	var near := _near(ctx, eye)
	var stopped := 0
	var total := 0
	for x: float in [-0.7, -0.35, 0.0, 0.35, 0.7]:
		for y: float in [-0.8, -0.3, 0.3]:
			var dir := (fwd + b.x * x * half * 16.0 / 9.0 + b.y * y * half).normalized()
			total += 1
			var to := eye + dir * dist * FOREGROUND_DEPTH
			if _hit(ctx, eye, to) or _hit_prop(near, eye, to):
				stopped += 1
	return float(stopped) / float(total)


## Right (x) and up (y) of a view along `fwd`.
static func _frame(fwd: Vector3) -> Basis:
	var right := fwd.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, right.cross(fwd.normalized()).normalized(), Vector3.ZERO)


## True if a building stands between `from` and `to`.
static func _hit(ctx: Dictionary, from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = ctx.space
	var skip: Array[RID] = (ctx.subject as Array[RID]).duplicate()
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = skip
		q.hit_back_faces = false
		var r := space.intersect_ray(q)
		if r.is_empty():
			return false
		if _solid(r.collider):
			return true
		skip.append(r.rid)
	return false


## The props close to `eye`.
static func _near(ctx: Dictionary, eye: Vector3) -> Array[AABB]:
	var out: Array[AABB] = []
	for a: AABB in ctx.props:
		if a.grow(PROP_NEAR * float(ctx.tile)).has_point(eye):
			out.append(a)
	return out


static func _hit_prop(props: Array[AABB], from: Vector3, to: Vector3) -> bool:
	for a in props:
		if a.intersects_segment(from, to) != null:
			return true
	return false


static func _inside(ctx: Dictionary, p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = ctx.space
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.exclude = ctx.subject
	for r in space.intersect_point(q, 8):
		if _solid(r.collider):
			return true
	return false


## Buildings: anything static that isn't the ground.
static func _solid(o: Object) -> bool:
	if not (o is StaticBody3D):
		return false
	var n := o as Node
	var p := n.get_parent()
	if p and (String(p.name).begins_with("CityGround") or String(p.name) == "Ground"):
		return false
	return not String(n.name).contains("Ground")


## What the shot is of: the colliders at or right round the look point.
static func _subject(space: PhysicsDirectSpaceState3D, look: Vector3, tile: float) -> Array[RID]:
	var out: Array[RID] = []
	var ball := SphereShape3D.new()
	ball.radius = SUBJECT_REACH * tile
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis(), look)
	for r in space.intersect_shape(q, 16):
		if _solid(r.collider):
			out.append(r.rid)
	return out


## The colliders of `n` and everything under it.
static func _collect(n: Node, out: Array[RID]) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is CollisionObject3D:
		out.append((n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_collect(c, out)


## Bounding boxes of the tall, thin things with no collision (lamp posts,
## trees, poles, signs) within `reach` of `look`, leaving out the subjects
## and anything too close to `look` to be in front of it.
static func _props(root: Node, look: Vector3, reach: float, tile: float, subjects: Array) -> Array[AABB]:
	var out: Array[AABB] = []
	if root == null:
		return out
	var area := AABB(look - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a := mi.global_transform * mi.get_aabb()
		if a.size.y < PROP_TALL * tile or maxf(a.size.x, a.size.z) > PROP_THIN * tile:
			continue
		if not area.intersects(a) or a.grow(SUBJECT_REACH * tile).has_point(look):
			continue
		if _under(mi, subjects) or _has_body(mi):
			continue
		# a box round a tree or a lamp is mostly air: keep its middle half
		var trim := Vector3(a.size.x * 0.25, 0.0, a.size.z * 0.25)
		out.append(AABB(a.position + trim, a.size - trim * 2.0))
	return out


static func _under(n: Node, subjects: Array) -> bool:
	for s in subjects:
		if s is Node and is_instance_valid(s) and (s == n or (s as Node).is_ancestor_of(n)):
			return true
	return false


## True if `n` is part of something with its own collision or that moves
## (a building, a person, a car): those are handled by the rays, or ignored.
static func _has_body(n: Node) -> bool:
	var p := n.get_parent()
	for i in 2:
		if p == null:
			return false
		if p is PhysicsBody3D:
			return true
		for c in p.get_children():
			if c is CollisionObject3D:
				return true
		p = p.get_parent()
	return false
