extends Node3D

## Scatters vegetation across living tiles.
##
## Density follows each hex's fertility, so growth is something you watch
## happen rather than something that pops in fully formed. Every biome gets
## one MultiMesh batch, which keeps the whole island at a handful of draw
## calls no matter how green it gets.

const TILE_SIZE := 1.0
## Rebuilding every batch is cheap but not free; only do it a few times a
## second even if the world changes constantly.
const REBUILD_INTERVAL := 0.6

@export var world_view_path: NodePath

var world: World
var quality: Quality

## Biome -> MultiMeshInstance3D
var _batches: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _dirty := true
var _accum := 0.0


func _ready() -> void:
	var view := get_node(world_view_path)
	world = view.world
	quality = view.quality

	# Deterministic scatter: the same tile always grows the same clump, so
	# plants do not jump around when the batch is rebuilt.
	_rng.seed = 20260729

	_build_batches()
	world.tile_changed.connect(func(_a): _dirty = true)
	set_process(true)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_accum += delta
	if _accum < REBUILD_INTERVAL:
		return
	_accum = 0.0
	_dirty = false
	_rebuild()


func _build_batches() -> void:
	_add_batch(TileTypes.Biome.GRASS, _blade_mesh(), Color("6f9c48"), 0.9)
	_add_batch(TileTypes.Biome.SHRUB, _bush_mesh(), Color("8d8a4c"), 0.7)
	_add_batch(TileTypes.Biome.WETLAND, _reed_mesh(), Color("4f8a5e"), 1.0)
	_add_batch(TileTypes.Biome.MANGROVE, _tree_mesh(0.7), Color("3d6b52"), 0.5)
	_add_batch(TileTypes.Biome.FOREST, _tree_mesh(1.0), Color("2f5f34"), 0.45)
	_rebuild()


func _add_batch(biome: TileTypes.Biome, mesh: Mesh, tint: Color, density: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.roughness = 0.85
	# Foliage lit from both sides stops looking like flat cardboard.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if quality.tier == Quality.Tier.HIGH \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("density", density)
	add_child(node)

	_batches[biome] = node


func _rebuild() -> void:
	for biome in _batches:
		_fill(biome, _batches[biome])


func _fill(biome: TileTypes.Biome, node: MultiMeshInstance3D) -> void:
	var density: float = node.get_meta("density", 1.0)
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	# Reset per rebuild so the same tile draws the same clump every time.
	var scatter := RandomNumberGenerator.new()

	for t in world.all_tiles():
		if t.biome != biome:
			continue

		# Fertility drives how full the clump is: a tile that just came alive
		# gets a sprig, a mature one gets a thicket.
		var count := int(round(quality.foliage_per_tile * density * clampf(t.fertility, 0.2, 1.0)))
		if count <= 0:
			continue

		scatter.seed = hash(t.axial)
		var center := Grid.to_pixel(t.axial, TILE_SIZE)
		var top := _tile_top(t)

		for i in count:
			var angle := scatter.randf() * TAU
			var radius := sqrt(scatter.randf()) * TILE_SIZE * 0.78
			var pos := Vector3(
				center.x + cos(angle) * radius,
				top,
				center.y + sin(angle) * radius)

			var scale := scatter.randf_range(0.7, 1.25)
			var basis := Basis(Vector3.UP, scatter.randf() * TAU).scaled(
				Vector3(scale, scale * scatter.randf_range(0.85, 1.3), scale))

			transforms.append(Transform3D(basis, pos))
			# Slight per-plant colour drift so a field is not one flat green.
			colors.append(Color(1, 1, 1).lerp(
				Color(scatter.randf_range(0.8, 1.1), 1.0, scatter.randf_range(0.8, 1.05)),
				0.5))

	var mm := node.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])


# -------------------------------------------------------------------- meshes

func _blade_mesh() -> Mesh:
	var m := PrismMesh.new()
	m.size = Vector3(0.09, 0.30, 0.02)
	return m


func _bush_mesh() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.14
	m.height = 0.20
	m.radial_segments = 6
	m.rings = 3
	return m


func _reed_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.012
	m.bottom_radius = 0.03
	m.height = 0.42
	m.radial_segments = 4
	m.rings = 1
	return m


func _tree_mesh(scale: float) -> Mesh:
	# A cone reads as a canopy at this camera distance and costs 8 triangles.
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.24 * scale
	m.height = 0.75 * scale
	m.radial_segments = 6
	m.rings = 1
	return m


func _tile_top(t: Tile) -> float:
	var heights := {
		TileTypes.Terrain.OCEAN: -0.55,
		TileTypes.Terrain.WATER: -0.15,
		TileTypes.Terrain.RIVERBED: -0.12,
		TileTypes.Terrain.SAND: 0.05,
		TileTypes.Terrain.WASTELAND: 0.20,
		TileTypes.Terrain.ROCK: 0.55,
		TileTypes.Terrain.CLIFF: 1.15,
	}
	return heights.get(t.terrain, 0.2)
