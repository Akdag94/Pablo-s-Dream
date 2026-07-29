extends Node3D

## The hex highlight and footprint preview under the player's selection.
##
## On a phone the finger covers the tile it is touching, so placement is never
## immediate: tapping only moves this cursor, and a separate confirm button
## commits. This node is what makes that intermediate state visible.

const TILE_SIZE := 1.0
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


## A square outline, built as four thin bars so it reads as a border rather
## than a filled tile.
func _ring_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	var outer := TILE_SIZE * 0.5
	var inner := TILE_SIZE * 0.5 - TILE_SIZE * 0.07

	# Four quads forming a frame, each written as two triangles.
	var edges := [
		[Vector2(-outer, -outer), Vector2(outer, -inner)],
		[Vector2(-outer, inner), Vector2(outer, outer)],
		[Vector2(-outer, -inner), Vector2(-inner, inner)],
		[Vector2(inner, -inner), Vector2(outer, inner)],
	]

	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var corners := [
			Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, a.y),
			Vector3(b.x, 0.0, b.y), Vector3(a.x, 0.0, b.y),
		]
		for index in [0, 1, 2, 0, 2, 3]:
			verts.append(corners[index])
			normals.append(Vector3.UP)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _disc_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(TILE_SIZE * 0.94, 0.02, TILE_SIZE * 0.94)
	return m


## Move the cursor onto a hex and preview `def`'s area of effect there.
func move_to(axial: Vector2i, def: BuildingDef, valid: bool) -> void:
	_axial = axial
	_valid = valid

	var tile := world.get_tile(axial)
	if tile == null:
		clear()
		return

	var flat := Grid.to_pixel(axial, TILE_SIZE)
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
	for a in Grid.in_radius(center, radius):
		if world.has(a):
			cells.append(a)

	var mm := _footprint.multimesh
	mm.instance_count = cells.size()
	var tint := Color(0.5, 1.0, 0.55) if valid else Color(1.0, 0.45, 0.42)

	for i in cells.size():
		var tile := world.get_tile(cells[i])
		var flat := Grid.to_pixel(cells[i], TILE_SIZE)
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


func _tile_top(tile: Tile) -> float:
	return TerrainHeight.of(tile)
