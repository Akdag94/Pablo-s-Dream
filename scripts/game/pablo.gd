class_name Pablo
extends RefCounted

## Pablo. He lives here.
##
## This is a pure state machine over hex coordinates — it holds a position, a
## destination, and a mood, and knows nothing about how he is drawn. The 2D
## prototype renders him as a dot; the 3D view drives a model from exactly the
## same numbers. Nothing below changes when the model arrives.

signal arrived(axial: Vector2i)
signal mood_changed(mood: Mood)

## How content he is, which follows how alive the world is around him.
enum Mood {
	WAITING,   ## Nothing grows yet. He stays near where he started.
	CURIOUS,   ## Green is appearing. He starts ranging further.
	HAPPY,     ## The place is alive. He wanders freely.
	HOME,      ## The machines are gone. This is his now.
}

## Hexes per second.
const WALK_SPEED := 1.6
## Seconds he pauses on arrival before choosing somewhere new.
const REST_MIN := 1.0
const REST_MAX := 3.5

var world: World
var mood: Mood = Mood.WAITING

## Current interpolated position in hex space (fractional, for smooth motion).
var position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT

var _from: Vector2i = Vector2i.ZERO
var _to: Vector2i = Vector2i.ZERO
var _travel: float = 0.0
var _rest: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(p_world: World) -> void:
	world = p_world
	_rng.randomize()
	_from = _find_start()
	_to = _from
	position = Vector2(_from)


## Start him somewhere on solid ground near the middle of the map.
func _find_start() -> Vector2i:
	for r in range(0, world.radius):
		for a in Hex.in_radius(Vector2i.ZERO, r):
			var t := world.get_tile(a)
			if t != null and not TileTypes.is_water(t.terrain) \
					and t.terrain != TileTypes.Terrain.CLIFF:
				return a
	return Vector2i.ZERO


func update(delta: float) -> void:
	_refresh_mood()

	if _rest > 0.0:
		_rest -= delta
		return

	if _from == _to:
		_choose_destination()
		return

	_travel += delta * WALK_SPEED
	var t := clampf(_travel, 0.0, 1.0)
	var a := Vector2(_from)
	var b := Vector2(_to)
	position = a.lerp(b, t)

	var d := b - a
	if d.length_squared() > 0.0:
		facing = d.normalized()

	if t >= 1.0:
		_from = _to
		_travel = 0.0
		_rest = _rng.randf_range(REST_MIN, REST_MAX)
		arrived.emit(_to)


## Pick somewhere to walk to, preferring the liveliest ground in range.
func _choose_destination() -> void:
	var range_steps := _wander_range()
	var candidates: Array[Tile] = []

	for t in world.tiles_in_radius(_from, range_steps):
		if TileTypes.is_water(t.terrain) or t.terrain == TileTypes.Terrain.CLIFF:
			continue
		if t.axial == _from:
			continue
		candidates.append(t)

	if candidates.is_empty():
		_rest = 1.0
		return

	# Weight the choice toward living tiles so he drifts into the good parts.
	var best: Tile = null
	var best_weight := -1.0
	for t in candidates:
		var weight := float(t.score()) + _rng.randf() * 2.0
		if weight > best_weight:
			best_weight = weight
			best = t

	_to = best.axial
	_travel = 0.0


func _wander_range() -> int:
	match mood:
		Mood.WAITING: return 2
		Mood.CURIOUS: return 4
		Mood.HAPPY: return 6
		Mood.HOME: return 8
	return 3


func _refresh_mood() -> void:
	var alive := world.restored_fraction()
	var machines := world.count_buildings()

	var next := mood
	if alive >= 0.5 and machines == 0:
		next = Mood.HOME
	elif alive >= 0.4:
		next = Mood.HAPPY
	elif alive >= 0.12:
		next = Mood.CURIOUS
	else:
		next = Mood.WAITING

	if next != mood:
		mood = next
		mood_changed.emit(mood)


## Pixel position for the 2D view.
func pixel_position(hex_size: float) -> Vector2:
	# Interpolate in pixel space so motion between hexes stays straight.
	var a := Hex.to_pixel(_from, hex_size)
	var b := Hex.to_pixel(_to, hex_size)
	var t := clampf(_travel, 0.0, 1.0)
	return a.lerp(b, t)


## World-space position for the 3D view, on the ground plane.
func world_position_3d(hex_size: float) -> Vector3:
	var p := pixel_position(hex_size)
	return Vector3(p.x, 0.0, p.y)


## Heading in radians, for orienting a model.
func heading() -> float:
	return atan2(facing.y, facing.x)


func mood_name() -> String:
	return Mood.keys()[mood].capitalize()
