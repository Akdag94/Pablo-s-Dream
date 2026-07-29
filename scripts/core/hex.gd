class_name Hex
extends RefCounted

## Pointy-top hexagon math on an axial (q, r) coordinate system.
## Reference layout: width = sqrt(3) * size, height = 2 * size.

const SQRT3 := 1.7320508075688772

## The six axial neighbour offsets, starting east and going counter-clockwise.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbor(axial: Vector2i, dir: int) -> Vector2i:
	return axial + DIRECTIONS[dir]


static func neighbors(axial: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(axial + d)
	return out


## Axial -> pixel centre.
static func to_pixel(axial: Vector2i, size: float) -> Vector2:
	return Vector2(
		size * SQRT3 * (axial.x + axial.y * 0.5),
		size * 1.5 * axial.y
	)


## Pixel -> nearest axial cell.
static func from_pixel(point: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * point.x - point.y / 3.0) / size
	var r := (2.0 / 3.0 * point.y) / size
	return _round_axial(q, r)


## Distance in hex steps between two axial cells.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dq + dr) + abs(dr)) / 2.0)


## Every cell within `radius` steps of `center`, including the centre itself.
static func in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var lo := maxi(-radius, -dq - radius)
		var hi := mini(radius, -dq + radius)
		for dr in range(lo, hi + 1):
			out.append(center + Vector2i(dq, dr))
	return out


## The six corner points of a cell, for drawing.
static func corners(center_px: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := PI / 180.0 * (60.0 * i - 30.0)
		pts.append(center_px + Vector2(size * cos(angle), size * sin(angle)))
	return pts


static func _round_axial(q: float, r: float) -> Vector2i:
	# Convert to cube, round, then fix up the largest-drift component.
	var s := -q - r
	var rq := roundi(q)
	var rr := roundi(r)
	var rs := roundi(s)

	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)

	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs

	return Vector2i(rq, rr)
