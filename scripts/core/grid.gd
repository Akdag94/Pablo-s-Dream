class_name Grid
extends RefCounted

## Square grid maths.
##
## Coordinates stay `Vector2i` and the API matches what the hex version
## exposed, so the renderers, the simulation and Pablo did not have to change
## shape when the tiling changed — only this file knows the cells are squares.

## Orthogonal neighbours, clockwise from east.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1),
]

## Diagonals, for the few rules that want a full 8-neighbourhood.
const DIAGONALS: Array[Vector2i] = [
	Vector2i(1, -1), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]


static func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	return cell + DIRECTIONS[dir]


## The four cells sharing an edge. Adjacency rules — water, salt, spread —
## all use this, so a tile only counts as touching water across an edge and
## not merely at a corner.
static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(cell + d)
	return out


## All eight surrounding cells, for scattering and visual blending.
static func surrounding(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(cell + d)
	for d in DIAGONALS:
		out.append(cell + d)
	return out


## Cell -> centre point, in world units.
static func to_pixel(cell: Vector2i, size: float) -> Vector2:
	return Vector2(cell.x * size, cell.y * size)


## Point -> the cell containing it.
static func from_pixel(point: Vector2, size: float) -> Vector2i:
	return Vector2i(roundi(point.x / size), roundi(point.y / size))


## Chebyshev distance: one step covers diagonals too, so a radius reads as a
## square block rather than a diamond. That matches how square tiles look.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Every cell within `radius` steps, including the centre.
static func in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			out.append(center + Vector2i(dx, dy))
	return out


## The four corners of a cell, for 2D drawing.
static func corners(center_px: Vector2, size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([
		center_px + Vector2(-h, -h),
		center_px + Vector2(h, -h),
		center_px + Vector2(h, h),
		center_px + Vector2(-h, h),
	])
