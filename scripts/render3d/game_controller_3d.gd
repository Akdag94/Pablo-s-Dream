extends Node3D

## Wires gestures to the camera, the build cursor and the game state.
##
## Nothing else listens to raw input in the 3D scene. Having one owner for the
## gesture stream is what keeps a pan from also placing a building.

signal selection_changed(axial: Vector2i, valid: bool)
signal placement_result(ok: bool)

@export var world_view_path: NodePath
@export var camera_rig_path: NodePath

var world: World
var state: GameState
var selected_def: BuildingDef

var _view: Node3D
var _rig: Node3D
var _cursor: Node3D
var _gestures: GestureRecognizer


func _ready() -> void:
	_view = get_node(world_view_path)
	_rig = get_node(camera_rig_path)
	world = _view.world
	state = _view.state

	_cursor = preload("res://scripts/render3d/build_cursor.gd").new()
	add_child(_cursor)
	_cursor.setup(world)

	_gestures = GestureRecognizer.new()
	_gestures.tapped.connect(_on_tapped)
	_gestures.long_pressed.connect(_on_long_pressed)
	_gestures.panned.connect(func(d): _rig.pan(d))
	_gestures.pinched.connect(func(d): _rig.zoom(d))
	_gestures.orbited.connect(func(d): _rig.orbit(d))

	set_process(true)


func _process(delta: float) -> void:
	_gestures.update(delta)


func _unhandled_input(event: InputEvent) -> void:
	_gestures.handle(event)


# ------------------------------------------------------------------- gestures

## A tap only moves the cursor. Placement waits for an explicit confirm, so a
## finger landing slightly off never costs the player a building.
func _on_tapped(screen_pos: Vector2) -> void:
	var axial = _view.pick_tile(_rig.camera, screen_pos)
	if axial == null:
		_cursor.clear()
		selection_changed.emit(Vector2i.ZERO, false)
		return

	var valid := _can_place_at(axial)
	_cursor.move_to(axial, selected_def, valid)
	Audio.play("select")
	selection_changed.emit(axial, valid)


## Holding a building offers to sell it, without a menu in the way.
func _on_long_pressed(screen_pos: Vector2) -> void:
	var axial = _view.pick_tile(_rig.camera, screen_pos)
	if axial == null:
		return
	if world.building_at(axial) == null:
		return
	if state.try_remove(axial):
		_cursor.clear()
		Audio.play("sell", _view.tile_center(axial))
		placement_result.emit(true)


# ------------------------------------------------------------------- building

func select_building(def: BuildingDef) -> void:
	selected_def = def
	if _cursor.has_selection():
		var axial: Vector2i = _cursor.current_axial()
		_cursor.move_to(axial, def, _can_place_at(axial))


## Commit whatever the cursor is currently sitting on.
func confirm_placement() -> bool:
	if selected_def == null or not _cursor.has_selection():
		return false

	var axial: Vector2i = _cursor.current_axial()
	var ok := state.try_place(selected_def, axial)
	Audio.play("place" if ok else "denied", _view.tile_center(axial))
	placement_result.emit(ok)

	if ok:
		# Keep the tool selected — players place these in runs, not one at a
		# time — but move the cursor off so the next tap picks a fresh Grid.
		_cursor.clear()
	return ok


func can_confirm() -> bool:
	return selected_def != null and _cursor.has_selection() and _cursor.is_valid()


func _can_place_at(axial: Vector2i) -> bool:
	if selected_def == null:
		return false

	var tile := world.get_tile(axial)
	if tile == null or not tile.is_empty() or not selected_def.can_sit_on(tile.terrain):
		return false
	if selected_def.tier > state._max_unlocked_tier():
		return false
	if not state.can_afford(selected_def):
		return false

	if selected_def.requires_water_adjacency:
		for n in world.neighbors_of(axial):
			if TileTypes.is_water(n.terrain):
				return true
		return false

	return true
