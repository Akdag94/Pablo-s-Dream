extends Node3D

## Orbiting camera over the island, driven by mouse or touch.
##
## The rig itself is the pivot; the camera hangs off it at `distance`. Panning
## moves the pivot across the ground plane, so zooming always converges on
## whatever the player is looking at rather than the world origin.

const MIN_DISTANCE := 8.0
const MAX_DISTANCE := 70.0
const MIN_PITCH := 18.0
const MAX_PITCH := 78.0

const PAN_SPEED := 0.035
const ORBIT_SPEED := 0.4
const ZOOM_STEP := 3.0
const SMOOTHING := 10.0

@export var distance: float = 34.0
@export var pitch: float = 52.0
@export var yaw: float = 0.0

var camera: Camera3D

var _target_distance: float
var _target_pitch: float
var _target_yaw: float
var _target_origin: Vector3

var _panning := false
var _orbiting := false
## Active touch points, for pinch-zoom on mobile.
var _touches: Dictionary = {}
var _last_pinch_distance := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	add_child(camera)

	_target_distance = distance
	_target_pitch = pitch
	_target_yaw = yaw
	_target_origin = global_position

	_apply(1.0)
	set_process(true)


func _process(delta: float) -> void:
	_apply(clampf(delta * SMOOTHING, 0.0, 1.0))


func _apply(weight: float) -> void:
	distance = lerpf(distance, _target_distance, weight)
	pitch = lerpf(pitch, _target_pitch, weight)
	yaw = lerpf(yaw, _target_yaw, weight)
	global_position = global_position.lerp(_target_origin, weight)

	# Place the camera on a sphere around the pivot and aim it back at us.
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var offset := Vector3(
		sin(y) * cos(p),
		sin(p),
		cos(y) * cos(p)
	) * distance

	camera.position = offset
	camera.look_at(global_position, Vector3.UP)


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			zoom(-ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			zoom(ZOOM_STEP)
		MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		pan(event.relative)
	elif _orbiting:
		orbit(event.relative)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
		_last_pinch_distance = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	if _touches.size() == 1:
		pan(event.relative)
		return

	if _touches.size() >= 2:
		var points: Array = _touches.values()
		var spread: float = points[0].distance_to(points[1])
		if _last_pinch_distance > 0.0:
			zoom((_last_pinch_distance - spread) * 0.05)
		_last_pinch_distance = spread


# ------------------------------------------------------------------ movement

## Slide the pivot across the ground, in the direction the camera is facing.
func pan(screen_delta: Vector2) -> void:
	var scale := distance * PAN_SPEED
	var y := deg_to_rad(yaw)
	var right := Vector3(cos(y), 0.0, -sin(y))
	var forward := Vector3(sin(y), 0.0, cos(y))
	_target_origin += (-right * screen_delta.x + forward * screen_delta.y) * scale * 0.05


func orbit(screen_delta: Vector2) -> void:
	_target_yaw -= screen_delta.x * ORBIT_SPEED
	_target_pitch = clampf(
		_target_pitch - screen_delta.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)


func zoom(amount: float) -> void:
	_target_distance = clampf(_target_distance + amount, MIN_DISTANCE, MAX_DISTANCE)


## Ease the camera over to a point, used when following Pablo.
func focus_on(point: Vector3) -> void:
	_target_origin = point
