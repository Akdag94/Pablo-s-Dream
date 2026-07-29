extends Node3D

## The hex highlight and footprint preview under the player's selection.
##
## On a phone the finger covers the tile it is touching, so placement is never
## immediate: tapping only moves this cursor, and a separate confirm button
## commits. This node is what makes that intermediate state visible.

const HEX_RADIUS := 1.0
## Lifted slightly so the ring never z-fights with the tile top.
const HOVER_OFFSET := 0.06

var world: World

var _ring: MeshInstance3D
var _footprint: MultiMeshInstance3D
var _material: StandardMaterial3D
var _footprint_material: StandardMaterial3D

var _axial: Vector2i = Vector2i(9999, 9999)
var _valid := false


func setup(p_world: World) -> void:
	world = p_world

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1, 1, 1, 0.85)
	_material.no_depth_test = true

	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh()
	_ring.material_override = _material
	_ring.visible = false
	add_child(_ring)

	_footprint_material = StandardMaterial3D.new()
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.albedo_color = Color(1, 1, 1, 0.18)
	_footprint_material.vertex_color_use_as_albedo = true

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _disc_mesh()

	_footprint = MultiMeshInstance3D.new()
	_footprint.multimesh = mm
	_footprint.material_override = _footprint_material
	_footprint.visible = false
	add_child(_footprint)


## A flat hexagonal ring, drawn as a thin torus of six segments.
func _ring_mesh() -> Mesh:
	var m := TorusMesh.new()
	m.inner_radius = HEX_RADIUS * 0.86
	m.outer_radius = HEX_RADIUS * 0.98
	m.rings = 6
	m.ring_segments = 6
	return m


func _disc_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = HEX_RADIUS * 0.92
	m.bottom_radius = HEX_RADIUS * 0.92
	m.height = 0.02
	m.radial_segments = 6
	m.rings = 1
	return m


## Move the cursor onto a hex and preview `def`'s area of effect there.
func move_to(axial: Vector2i, def: BuildingDef, valid: bool) -> void:
	_axial = axial
	_valid = valid

	var tile := world.get_tile(axial)
	if tile == null:
		clear()
		return

	var flat := Hex.to_pixel(axial, HEX_RADIUS)
	var height := _tile_top(tile)

	_ring.visible = true
	_ring.position = Vector3(flat.x, height + HOVER_OFFSET, flat.y)
	_material.albedo_color = Color(0.55, 1.0, 0.6, 0.9) if valid \
		else Color(1.0, 0.45, 0.42, 0.9)

	_show_footprint(axial, def, valid)


func _show_footprint(center: Vector2i, def: BuildingDef, valid: bool) -> void:
	if def == null:
		_footprint.visible = false
		return

	var radius: int = maxi(def.effect_radius, def.power_radius)
	var cells: Array[Vector2i] = []
	for a in Hex.in_radius(center, radius):
		if world.has(a):
			cells.append(a)

	var mm := _footprint.multimesh
	mm.instance_count = cells.size()
	var tint := Color(0.5, 1.0, 0.55) if valid else Color(1.0, 0.45, 0.42)

	for i in cells.size():
		var tile := world.get_tile(cells[i])
		var flat := Hex.to_pixel(cells[i], HEX_RADIUS)
		var origin := Vector3(flat.x, _tile_top(tile) + HOVER_OFFSET * 0.5, flat.y)
		mm.set_instance_transform(i, Transform3D(Basis(), origin))
		mm.set_instance_color(i, tint)

	_footprint.visible = true


func clear() -> void:
	_axial = Vector2i(9999, 9999)
	_ring.visible = false
	_footprint.visible = false


func current_axial() -> Vector2i:
	return _axial


func has_selection() -> bool:
	return world != null and world.has(_axial)


func is_valid() -> bool:
	return _valid


## Top surface height of a tile, matching WorldView3D's elevation table.
func _tile_top(tile: Tile) -> float:
	if tile == null:
		return 0.0
	var heights: Dictionary = {
		TileTypes.Terrain.OCEAN: -0.55,
		TileTypes.Terrain.WATER: -0.15,
		TileTypes.Terrain.RIVERBED: -0.12,
		TileTypes.Terrain.SAND: 0.05,
		TileTypes.Terrain.WASTELAND: 0.20,
		TileTypes.Terrain.ROCK: 0.55,
		TileTypes.Terrain.CLIFF: 1.15,
	}
	return heights.get(tile.terrain, 0.2)
