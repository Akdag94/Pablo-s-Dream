class_name GestureRecognizer
extends RefCounted

## Turns raw touch and mouse events into game-level gestures.
##
## Kept separate from the camera and the build cursor on purpose: on a phone
## the same finger-down can start a pan, a pinch, or a tap, and only this
## class should have to care which. Everything downstream just listens for
## `tapped` or `panned`.

signal tapped(position: Vector2)
signal long_pressed(position: Vector2)
signal panned(delta: Vector2)
signal pinched(delta: float)
signal orbited(delta: Vector2)

## Movement beyond this many pixels means the finger is dragging, not tapping.
const TAP_SLOP := 12.0
## A press held longer than this becomes a long press instead of a tap.
const LONG_PRESS_TIME := 0.55
## Pinch distance change is scaled by this before becoming zoom.
const PINCH_SCALE := 0.05

var _touches: Dictionary = {}          ## index -> current position
var _touch_starts: Dictionary = {}     ## index -> position when it went down
var _press_time: float = 0.0
var _moved_beyond_slop := false
var _long_press_sent := false
var _last_pinch_distance := 0.0
## True once a second finger lands, so lifting back to one finger does not
## suddenly resume panning mid-pinch.
var _multi_touch_active := false

# Desktop equivalents.
var _mouse_panning := false
var _mouse_orbiting := false


## Feed every input event through here.
func handle(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)


## Call every frame so long presses can fire without further input.
func update(delta: float) -> void:
	if _touches.size() != 1 or _moved_beyond_slop or _long_press_sent:
		return
	_press_time += delta
	if _press_time >= LONG_PRESS_TIME:
		_long_press_sent = true
		long_pressed.emit(_touches.values()[0])


# ---------------------------------------------------------------- touchscreen

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		_touch_starts[event.index] = event.position

		if _touches.size() == 1:
			_press_time = 0.0
			_moved_beyond_slop = false
			_long_press_sent = false
		else:
			_multi_touch_active = true
			_last_pinch_distance = 0.0
		return

	# Released. A single finger that never moved far and was not held is a tap.
	var was_single := _touches.size() == 1
	_touches.erase(event.index)
	_touch_starts.erase(event.index)

	if was_single and not _moved_beyond_slop and not _long_press_sent \
			and not _multi_touch_active:
		tapped.emit(event.position)

	if _touches.is_empty():
		_multi_touch_active = false
		_last_pinch_distance = 0.0


func _on_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	var start: Vector2 = _touch_starts.get(event.index, event.position)
	if event.position.distance_to(start) > TAP_SLOP:
		_moved_beyond_slop = true

	match _touches.size():
		1:
			if not _multi_touch_active:
				panned.emit(event.relative)
		2:
			_handle_two_finger(event)


## Two fingers: the change in spread is zoom, the shared motion is orbit.
func _handle_two_finger(event: InputEventScreenDrag) -> void:
	var points: Array = _touches.values()
	var spread: float = points[0].distance_to(points[1])

	if _last_pinch_distance > 0.0:
		var change := _last_pinch_distance - spread
		if absf(change) > 1.0:
			pinched.emit(change * PINCH_SCALE)
		else:
			# Fingers holding their spread while moving together is an orbit.
			orbited.emit(event.relative * 0.5)
	_last_pinch_distance = spread


# -------------------------------------------------------------------- desktop

func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			pinched.emit(-3.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			pinched.emit(3.0)
		MOUSE_BUTTON_MIDDLE:
			_mouse_panning = event.pressed
		MOUSE_BUTTON_RIGHT:
			_mouse_orbiting = event.pressed
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_touch_starts[-1] = event.position
				_moved_beyond_slop = false
			else:
				var start: Vector2 = _touch_starts.get(-1, event.position)
				if event.position.distance_to(start) <= TAP_SLOP:
					tapped.emit(event.position)
				_touch_starts.erase(-1)


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mouse_panning:
		panned.emit(event.relative)
	elif _mouse_orbiting:
		orbited.emit(event.relative)
	elif _touch_starts.has(-1):
		var start: Vector2 = _touch_starts[-1]
		if event.position.distance_to(start) > TAP_SLOP:
			_moved_beyond_slop = true
			panned.emit(event.relative)
