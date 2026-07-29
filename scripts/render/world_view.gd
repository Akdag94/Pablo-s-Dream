extends Node2D

## Draws the hex world and turns pointer input into build actions.
##
## Rendering is intentionally flat-colour for now: the whole point is that the
## simulation is legible while it is being tuned. Sprites drop in later without
## touching anything in scripts/core.

signal tile_hovered(axial: Vector2i)
signal build_attempted(axial: Vector2i, ok: bool)

const HEX_SIZE := 26.0
const SIM_INTERVAL := 0.35

@export var map_radius: int = 14

var world: World
var state: GameState
var selected_def: BuildingDef

var _hover: Vector2i = Vector2i(9999, 9999)
var _sim_accum := 0.0
var _camera_offset := Vector2.ZERO
var _dragging := false
var _drag_moved := false


func _ready() -> void:
	world = World.new(map_radius)
	state = GameState.new(world)
	world.tile_changed.connect(func(_a): queue_redraw())
	state.phase_changed.connect(func(_p): queue_redraw())
	_center_camera()
	set_process(true)


func _center_camera() -> void:
	var vp := get_viewport_rect().size
	_camera_offset = vp * 0.5


func _process(delta: float) -> void:
	# Pablo moves on real time; the world simulates on a fixed beat.
	state.update_pablo(delta)

	_sim_accum += delta
	if _sim_accum >= SIM_INTERVAL:
		_sim_accum = 0.0
		world.simulate()

	queue_redraw()


# ----------------------------------------------------------------- rendering

func _draw() -> void:
	for t in world.all_tiles():
		_draw_tile(t)
	for b in world.buildings.values():
		_draw_building(b)
	_draw_wildlife()
	_draw_pablo()
	_draw_hover()


func _draw_wildlife() -> void:
	for id in state.wildlife.settled:
		var def: SpeciesDef = Bestiary.get_species(id)
		var axial: Vector2i = state.wildlife.settled[id]
		var center := Hex.to_pixel(axial, HEX_SIZE) + _camera_offset
		# A small diamond, so animals never read as buildings.
		var r := HEX_SIZE * 0.30
		var pts := PackedVector2Array([
			center + Vector2(0, -r), center + Vector2(r, 0),
			center + Vector2(0, r), center + Vector2(-r, 0),
		])
		draw_colored_polygon(pts, def.color)


func _draw_pablo() -> void:
	var p: Pablo = state.pablo
	var center := p.pixel_position(HEX_SIZE) + _camera_offset

	# Placeholder marker. The 3D view drives a model from the same coordinates.
	draw_circle(center, HEX_SIZE * 0.28, Color("fff3d6"))
	draw_arc(center, HEX_SIZE * 0.28, 0.0, TAU, 24, Color(0.2, 0.15, 0.1, 0.7), 2.0)
	# A short tick showing which way he is heading.
	draw_line(center, center + p.facing * HEX_SIZE * 0.45, Color("fff3d6"), 2.0)


func _draw_tile(t: Tile) -> void:
	var center := Hex.to_pixel(t.axial, HEX_SIZE) + _camera_offset
	var pts := Hex.corners(center, HEX_SIZE - 1.0)
	var col := TileTypes.color_for(t.terrain, t.biome)

	# Dry, poisoned ground reads darker so progress is visible at a glance.
	if not t.has_life() and not TileTypes.is_water(t.terrain):
		col = col.darkened(0.25 * (1.0 - t.fertility))

	draw_colored_polygon(pts, col)

	# Faint blue wash showing where moisture has reached.
	if t.moisture > 0.05 and not TileTypes.is_water(t.terrain):
		draw_colored_polygon(pts, Color(0.35, 0.6, 0.85, t.moisture * 0.20))

	# Power coverage is drawn as a thin outline rather than a fill.
	if t.powered:
		draw_polyline(_closed(pts), Color(1, 0.95, 0.6, 0.30), 1.5)


func _draw_building(b: Building) -> void:
	var center := Hex.to_pixel(b.axial, HEX_SIZE) + _camera_offset
	var r := HEX_SIZE * 0.45
	var col: Color = b.def.color
	if not b.active and b.def.needs_power:
		col = col.darkened(0.5)
	draw_circle(center, r, col)
	draw_arc(center, r, 0.0, TAU, 20, Color(0, 0, 0, 0.35), 1.5)


func _draw_hover() -> void:
	if not world.has(_hover):
		return
	var center := Hex.to_pixel(_hover, HEX_SIZE) + _camera_offset
	var pts := Hex.corners(center, HEX_SIZE - 1.0)
	draw_polyline(_closed(pts), Color(1, 1, 1, 0.8), 2.0)

	if selected_def == null:
		return

	# Preview the footprint of whatever is selected.
	var ok := _placement_ok(_hover)
	var tint := Color(0.5, 1.0, 0.5, 0.18) if ok else Color(1.0, 0.4, 0.4, 0.18)
	var r: int = maxi(selected_def.effect_radius, selected_def.power_radius)
	for a in Hex.in_radius(_hover, r):
		if not world.has(a):
			continue
		var c := Hex.to_pixel(a, HEX_SIZE) + _camera_offset
		draw_colored_polygon(Hex.corners(c, HEX_SIZE - 1.0), tint)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _placement_ok(axial: Vector2i) -> bool:
	if selected_def == null:
		return false
	var t := world.get_tile(axial)
	if t == null or not t.is_empty() or not selected_def.can_sit_on(t.terrain):
		return false
	if not state.can_afford(selected_def):
		return false
	if selected_def.requires_water_adjacency:
		var touching := false
		for n in world.neighbors_of(axial):
			if TileTypes.is_water(n.terrain):
				touching = true
				break
		if not touching:
			return false
	return true


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_camera_offset += event.relative
			_drag_moved = true
			queue_redraw()
		else:
			_update_hover(event.position)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
			else:
				_dragging = false
				# A click that did not pan the camera is a build action.
				if not _drag_moved:
					_update_hover(event.position)
					_try_build(_hover)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_update_hover(event.position)
			state.try_remove(_hover)
			queue_redraw()


func _update_hover(screen_pos: Vector2) -> void:
	var axial := Hex.from_pixel(screen_pos - _camera_offset, HEX_SIZE)
	if axial != _hover:
		_hover = axial
		tile_hovered.emit(axial)
		queue_redraw()


func _try_build(axial: Vector2i) -> void:
	if selected_def == null:
		return
	var ok := state.try_place(selected_def, axial)
	build_attempted.emit(axial, ok)
	queue_redraw()


func select_building(def: BuildingDef) -> void:
	selected_def = def
	queue_redraw()
