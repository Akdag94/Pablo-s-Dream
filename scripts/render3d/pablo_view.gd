extends Node3D

## Drives Pablo's model from the state machine in scripts/game/pablo.gd.
##
## The logic node knows nothing about meshes; this node knows nothing about
## moods beyond how fast to walk. Drop a real model into `model_scene` and
## nothing below changes — if that model ships with an AnimationPlayer, the
## clip names in ANIMATIONS are the only thing to line up.

## Path to Pablo's model. Left empty until the real one is in the project, in
## which case a placeholder stands in so the scene is never broken.
@export var model_scene: PackedScene
@export var world_view_path: NodePath
## How quickly he turns to face where he is walking.
@export var turn_speed: float = 6.0

## Must match WorldView3D.HEX_RADIUS — both map hex space to metres.
const HEX_RADIUS := 1.0

const ANIMATIONS := {
	Pablo.Mood.WAITING: "idle",
	Pablo.Mood.CURIOUS: "walk",
	Pablo.Mood.HAPPY: "walk",
	Pablo.Mood.HOME: "walk",
}

var _pablo: Pablo
var _view: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _facing := 0.0


func _ready() -> void:
	_view = get_node(world_view_path)
	_pablo = _view.state.pablo

	_model = _spawn_model()
	add_child(_model)

	_anim = _find_animation_player(_model)
	_pablo.mood_changed.connect(_on_mood_changed)
	_on_mood_changed(_pablo.mood)

	set_process(true)


func _spawn_model() -> Node3D:
	if model_scene != null:
		var instance := model_scene.instantiate()
		if instance is Node3D:
			return instance
		push_warning("model_scene is not a Node3D — falling back to placeholder")
	return _placeholder()


## A simple capsule so the scene runs before the real model exists.
func _placeholder() -> Node3D:
	var holder := Node3D.new()

	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.85
	body.mesh = mesh
	body.position.y = 0.42

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("f6ead2")
	mat.roughness = 0.55
	body.material_override = mat

	holder.add_child(body)
	return holder


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _process(delta: float) -> void:
	var flat := _pablo.pixel_position(HEX_RADIUS)
	# Sit him on top of whatever tile he is standing on.
	position = Vector3(flat.x, _ground_height(), flat.y)

	# Ease the turn so he does not snap round on every waypoint.
	var target := -_pablo.heading()
	_facing = lerp_angle(_facing, target, clampf(delta * turn_speed, 0.0, 1.0))
	rotation.y = _facing


func _ground_height() -> float:
	var axial := Vector2i(
		roundi(_pablo.position.x), roundi(_pablo.position.y))
	var tile: Tile = _view.world.get_tile(axial)
	if tile == null:
		return 0.0
	var terrain_heights: Dictionary = _view.TERRAIN_HEIGHT
	return terrain_heights.get(tile.terrain, 0.2)


func _on_mood_changed(mood: int) -> void:
	if _anim == null:
		return
	var clip: String = ANIMATIONS.get(mood, "idle")
	if _anim.has_animation(clip):
		_anim.play(clip)
