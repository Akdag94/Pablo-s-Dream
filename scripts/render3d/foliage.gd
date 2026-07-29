extends Node3D

## Scatters vegetation across living tiles.
##
## Two things changed here after comparing against the reference. The plants are
## real models from the Kenney nature kit instead of cones and prisms — a cone
## standing on end reads as a cone at every camera distance — and there are
## several times as many of them, because a living tile in the reference is
## covered thickly enough that the ground barely shows through. Six sprigs per
## tile left it looking mown.
##
## Density still follows fertility, so growth is something you watch happen
## rather than something that pops in finished. Every model gets one MultiMesh
## batch, which keeps the whole island at a couple of dozen draw calls no matter
## how green it gets.

const TILE_SIZE := 1.0
## Rebuilding every batch is cheap but not free; only do it a few times a
## second even if the world changes constantly.
const REBUILD_INTERVAL := 0.6

## Real models from the Kenney nature kit (CC0), which was already in the repo.
const KIT := "res://assets/foliage/kenney_nature_kit/Models/GLTF format/"

## Biome -> the models scattered on it, and how many per tile at full fertility.
##
## Grass carries the highest count because it is a carpet; forest the lowest
## because each model is large and they overlap anyway.
const PLANTING := {
	TileTypes.Biome.GRASS: {
		"models": ["grass.glb", "grass_large.glb", "grass_leafs.glb",
			"flower_yellowA.glb", "flower_redA.glb", "flower_purpleA.glb"],
		"per_tile": 30,
	},
	TileTypes.Biome.SHRUB: {
		"models": ["plant_bush.glb", "plant_bushSmall.glb", "plant_bushDetailed.glb",
			"rock_smallA.glb", "grass.glb"],
		"per_tile": 16,
	},
	TileTypes.Biome.WETLAND: {
		"models": ["grass_leafsLarge.glb", "plant_flatTall.glb", "grass_large.glb"],
		"per_tile": 22,
	},
	TileTypes.Biome.MANGROVE: {
		"models": ["tree_palmDetailedShort.glb", "tree_palmShort.glb",
			"tree_palmBend.glb", "grass_leafsLarge.glb"],
		"per_tile": 8,
	},
	TileTypes.Biome.FOREST: {
		"models": ["tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineRoundA.glb",
			"tree_default.glb", "tree_oak.glb", "plant_bush.glb"],
		"per_tile": 10,
	},
	TileTypes.Biome.BEACH: {
		"models": ["rock_smallFlatA.glb", "rock_smallFlatB.glb", "grass.glb",
			"plant_bushSmall.glb"],
		"per_tile": 9,
	},
}

## Tallest a scattered plant may stand, in tile widths. Kenney's models are
## authored around a 1-unit grid, which is far too big beside a 1-unit tile, so
## every mesh is measured and rescaled to the figure for its biome.
const TARGET_HEIGHT := {
	TileTypes.Biome.GRASS: 0.16,
	TileTypes.Biome.SHRUB: 0.22,
	TileTypes.Biome.WETLAND: 0.30,
	TileTypes.Biome.MANGROVE: 0.85,
	TileTypes.Biome.FOREST: 0.95,
	TileTypes.Biome.BEACH: 0.14,
}

@export var world_view_path: NodePath

var world: World
var quality: Quality

## Biome -> Array[MultiMeshInstance3D], one entry per model variant.
var _batches: Dictionary = {}
var _dirty := true
var _accum := 0.0


func _ready() -> void:
	var view := get_node(world_view_path)
	world = view.world
	quality = view.quality

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


# -------------------------------------------------------------------- batches

func _build_batches() -> void:
	for biome in PLANTING:
		var spec: Dictionary = PLANTING[biome]
		var files: Array = spec["models"]
		# Split the per-tile budget across this biome's variants.
		var share := maxf(1.0, float(spec["per_tile"]) / float(files.size()))
		for index in files.size():
			var node := _make_batch(biome, String(files[index]), share, index)
			if node != null:
				if not _batches.has(biome):
					_batches[biome] = []
				_batches[biome].append(node)
	_rebuild()


## One batch for one model. Returns null when the kit is missing, in which case
## that variant simply does not grow rather than bringing the scene down.
func _make_batch(biome: TileTypes.Biome, file: String, share: float,
		index: int) -> MultiMeshInstance3D:
	var path := KIT + file
	if not ResourceLoader.exists(path):
		push_warning("Foliage model missing: %s" % path)
		return null

	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	var source := _first_mesh_instance(root)
	if source == null:
		root.free()
		push_warning("No mesh inside %s" % path)
		return null

	var mesh: Mesh = _recoloured(source.mesh, biome)
	root.free()

	var target: float = TARGET_HEIGHT.get(biome, 0.2)
	var span := mesh.get_aabb().size.y
	var fit := target / span if span > 0.001 else 1.0

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if quality.tier == Quality.Tier.HIGH \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("share", share)
	node.set_meta("fit", fit)
	# Offsets the scatter so two variants on the same tile do not stack up.
	node.set_meta("variant", index)
	add_child(node)
	return node


## Leaf colour per biome, and the colour of whatever is holding the leaves up.
##
## The kit's own materials cannot be used. Measured: its glTF models carry no
## textures at all, and their albedo factors are placeholders — pale cyan for
## every leafy surface and pale peach for every trunk and rock. That is exactly
## the "ice crystal" ring that appeared along the coast the first time these
## models went in. So each surface is repainted here instead.
const LEAF_COLOUR := {
	TileTypes.Biome.GRASS: Color(0.42, 0.63, 0.22),
	TileTypes.Biome.SHRUB: Color(0.47, 0.45, 0.23),
	TileTypes.Biome.WETLAND: Color(0.25, 0.50, 0.31),
	TileTypes.Biome.MANGROVE: Color(0.21, 0.42, 0.28),
	TileTypes.Biome.FOREST: Color(0.17, 0.35, 0.21),
	TileTypes.Biome.BEACH: Color(0.52, 0.62, 0.34),
}

## Trunks, stems and stones. Beach gets grey because what is scattered there is
## pebbles, not wood.
const HARD_COLOUR := {
	TileTypes.Biome.BEACH: Color(0.46, 0.45, 0.43),
	TileTypes.Biome.SHRUB: Color(0.40, 0.36, 0.30),
}
const WOOD_COLOUR := Color(0.27, 0.19, 0.13)


## Copy a kit mesh and repaint every surface. Leafy surfaces are told apart from
## woody ones by the placeholder colour the kit shipped them with: its leaf
## surfaces are always cyan-dominant, its trunks always warm.
func _recoloured(source: Mesh, biome: TileTypes.Biome) -> Mesh:
	var out := ArrayMesh.new()
	var leaf: Color = LEAF_COLOUR.get(biome, Color(0.30, 0.50, 0.25))
	var hard: Color = HARD_COLOUR.get(biome, WOOD_COLOUR)

	for s in source.get_surface_count():
		out.add_surface_from_arrays(
			source.surface_get_primitive_type(s), source.surface_get_arrays(s))

		var is_leaf := true
		var existing = source.surface_get_material(s)
		if existing is BaseMaterial3D:
			var c: Color = existing.albedo_color
			is_leaf = c.b > c.r
		out.surface_set_material(s, _plant_material(leaf if is_leaf else hard, is_leaf))

	return out


func _plant_material(colour: Color, is_leaf: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.88
	if is_leaf:
		# Leaves lit from one side only read as flat cardboard from the other.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


# -------------------------------------------------------------------- filling

func _rebuild() -> void:
	for biome in _batches:
		for node in _batches[biome]:
			_fill(biome, node)


func _fill(biome: TileTypes.Biome, node: MultiMeshInstance3D) -> void:
	var share: float = node.get_meta("share", 1.0)
	var fit: float = node.get_meta("fit", 1.0)
	var variant: int = node.get_meta("variant", 0)

	var transforms: Array[Transform3D] = []
	var scatter := RandomNumberGenerator.new()

	for t in world.all_tiles():
		if t.biome != biome:
			continue

		# Fertility drives how full the clump is: a tile that just came alive
		# gets a sprig, a mature one gets a thicket. Beach never gets richer,
		# so it is scattered at a flat rate instead.
		var fullness := clampf(t.fertility, 0.25, 1.0)
		if biome == TileTypes.Biome.BEACH:
			fullness = 1.0
		var count := int(round(share * fullness * _budget()))
		if count <= 0:
			continue

		# Deterministic per tile and per variant, so plants do not jump around
		# when a batch is rebuilt and two variants do not land on each other.
		scatter.seed = hash(Vector3i(t.axial.x, t.axial.y, variant))
		var center := Grid.to_pixel(t.axial, TILE_SIZE)
		var top := TerrainHeight.of(t)

		for i in count:
			var angle := scatter.randf() * TAU
			var radius := sqrt(scatter.randf()) * TILE_SIZE * 0.46
			var pos := Vector3(
				center.x + cos(angle) * radius,
				top,
				center.y + sin(angle) * radius)

			var vary := scatter.randf_range(0.78, 1.28)
			var basis := Basis(Vector3.UP, scatter.randf() * TAU).scaled(
				Vector3(fit * vary, fit * vary * scatter.randf_range(0.9, 1.2),
					fit * vary))
			transforms.append(Transform3D(basis, pos))

	var mm := node.multimesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])


## Scales the whole planting budget with the device's foliage allowance, so a
## phone thins the scatter out instead of dropping species entirely.
func _budget() -> float:
	return clampf(float(quality.foliage_per_tile) / 6.0, 0.35, 1.0)
