extends Node3D

## Draws the hex world as real 3D geometry.
##
## Land and water are two MultiMeshInstance3D batches — one draw call each,
## regardless of map size — with per-instance colour and height. Terrain type
## drives elevation, so the island has actual relief rather than a painted
## suggestion of it.
##
## This reads the same World that the 2D prototype does. Nothing in core/,
## buildings/, wildlife/ or game/ knows this file exists.

signal tile_picked(axial: Vector2i)

const TILE_SIZE := 1.0
## Vertical exaggeration. Real elevations are tiny next to a hex's width, and
## flat-looking terrain reads as a board game rather than a landscape.
const HEIGHT_SCALE := 1.0

## Metres of elevation per terrain type.
const TERRAIN_HEIGHT := {
	TileTypes.Terrain.OCEAN: -0.55,
	TileTypes.Terrain.WATER: -0.15,
	TileTypes.Terrain.RIVERBED: -0.12,
	TileTypes.Terrain.SAND: 0.05,
	TileTypes.Terrain.WASTELAND: 0.20,
	TileTypes.Terrain.ROCK: 0.55,
	TileTypes.Terrain.CLIFF: 1.15,
}

## Which region to play. Map size and climate come with it — see `levels.gd`.
@export var level_id: String = "home"
@export var sim_interval: float = 0.35

var world: World
var state: GameState
var quality: Quality

var _textures: TerrainTextures
var _land: MultiMeshInstance3D
var _water: MultiMeshInstance3D
var _land_tiles: Array[Tile] = []
var _water_tiles: Array[Tile] = []
var _dirty := true
var _sim_accum := 0.0


func _ready() -> void:
	quality = Quality.detect()

	world = World.new(Levels.resolve(level_id))
	state = GameState.new(world)
	world.tile_changed.connect(func(_a): _dirty = true)

	_build_batches()
	_apply_environment()
	state.phase_changed.connect(set_sky_for_phase)

	# Ambience is weather as much as the sky is: both say what the world feels
	# like right now, and both change on the same signal.
	state.phase_changed.connect(Audio.set_ambience_for_phase)
	Audio.set_ambience_for_phase(state.phase)

	set_process(true)


func _process(delta: float) -> void:
	state.update_pablo(delta)

	_sim_accum += delta
	if _sim_accum >= sim_interval:
		_sim_accum = 0.0
		world.simulate()

	if _dirty:
		_dirty = false
		_refresh_instances()


# ------------------------------------------------------------------ geometry

func _build_batches() -> void:
	# Load the ground textures once and share them across both materials.
	_textures = TerrainTextures.new()
	_textures.build()

	# Split once: a tile only moves between the two batches if its terrain
	# changes between wet and dry, which _refresh_instances handles by
	# rebuilding both lists.
	_land = _make_batch(_tile_mesh(), _land_material())
	_water = _make_batch(_water_mesh(), _water_material())
	# Waves push the surface up past the tile it belongs to, so let the water
	# draw without writing depth against itself.
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_land)
	add_child(_water)
	_refresh_instances()


func _make_batch(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# x holds the texture layer this tile draws with.
	mm.use_custom_data = true
	mm.mesh = mesh

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


## A unit cube. Tiles are exactly one unit across so the ground stays
## continuous between them and world-space textures tile without seams.
func _tile_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(TILE_SIZE, 1.0, TILE_SIZE)
	return m


## Water is a subdivided plane, not a box: Gerstner displacement moves
## vertices, and a box has none between its corners for a wave to show in.
## Subdivision is the one thing this shader genuinely needs geometry for.
func _water_mesh() -> Mesh:
	var m := PlaneMesh.new()
	m.size = Vector2(TILE_SIZE, TILE_SIZE)
	var steps := 2 if quality.tier == Quality.Tier.LOW else 6
	m.subdivide_width = steps
	m.subdivide_depth = steps
	return m


## Procedural ground. Grain, clumping and normal detail are generated in the
## shader, so there are no texture files to download or to look wrong on one
## device and right on another.
func _land_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")

	# Real photoscanned ground when it is present, procedural when it is not.
	if _textures != null and _textures.loaded:
		mat.set_shader_parameter("use_textures", true)
		mat.set_shader_parameter("albedo_array", _textures.albedo)
		mat.set_shader_parameter("normal_array", _textures.normal)
		mat.set_shader_parameter("orm_array", _textures.orm)
		mat.set_shader_parameter("texture_tiling", 0.5)
		mat.set_shader_parameter("tint_strength", 0.30)
	else:
		mat.set_shader_parameter("use_textures", false)

	# Fine detail costs fill rate, so the weakest tier gets a calmer surface.
	match quality.tier:
		Quality.Tier.LOW:
			mat.set_shader_parameter("detail_scale", 4.0)
			mat.set_shader_parameter("detail_strength", 0.20)
			mat.set_shader_parameter("normal_strength", 0.5)
			# Ray-marching per pixel is the single most expensive thing here.
			mat.set_shader_parameter("parallax_enabled", false)
		Quality.Tier.MEDIUM:
			mat.set_shader_parameter("detail_scale", 5.5)
			mat.set_shader_parameter("detail_strength", 0.26)
			mat.set_shader_parameter("normal_strength", 0.7)
			mat.set_shader_parameter("parallax_enabled", true)
			mat.set_shader_parameter("parallax_steps", 10)
			mat.set_shader_parameter("parallax_depth", 0.03)
		Quality.Tier.HIGH:
			mat.set_shader_parameter("detail_scale", 6.5)
			mat.set_shader_parameter("detail_strength", 0.32)
			mat.set_shader_parameter("normal_strength", 0.9)
			mat.set_shader_parameter("parallax_enabled", true)
			mat.set_shader_parameter("parallax_steps", 18)
			mat.set_shader_parameter("parallax_depth", 0.05)
	return mat


func _water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_speed", 0.28)
	if quality.tier == Quality.Tier.LOW:
		# Screen reads are the expensive part of this shader on mobile.
		mat.set_shader_parameter("refraction_strength", 0.0)
		mat.set_shader_parameter("wave_scale", 2.5)
	return mat


## Rebuild both instance batches from the current world state.
func _refresh_instances() -> void:
	_land_tiles.clear()
	_water_tiles.clear()
	for t in world.all_tiles():
		if TileTypes.is_water(t.terrain):
			_water_tiles.append(t)
		else:
			_land_tiles.append(t)

	_fill_batch(_land, _land_tiles, false)
	_fill_batch(_water, _water_tiles, true)


func _fill_batch(node: MultiMeshInstance3D, tiles: Array[Tile], is_water: bool) -> void:
	var mm := node.multimesh
	mm.instance_count = tiles.size()

	for i in tiles.size():
		var t := tiles[i]
		var height: float = TERRAIN_HEIGHT.get(t.terrain, 0.2) * HEIGHT_SCALE
		var flat := Grid.to_pixel(t.axial, TILE_SIZE)

		var basis: Basis
		var origin: Vector3
		if is_water:
			# A flat plane sits directly at the surface height, unscaled.
			basis = Basis()
			origin = Vector3(flat.x, height, flat.y)
		else:
			# The box is centred on its own origin, so shift it down by half
			# its height to keep every tile on the same base plane.
			basis = Basis().scaled(Vector3(1.0, maxf(absf(height), 0.05), 1.0))
			origin = Vector3(flat.x, height * 0.5, flat.y)

		mm.set_instance_transform(i, Transform3D(basis, origin))
		mm.set_instance_color(i, _tile_color(t))
		# Custom data x is read by terrain.gdshader as the texture layer.
		mm.set_instance_custom_data(i, Color(TerrainTextures.layer_for(t), 0, 0, 0))


func _tile_color(t: Tile) -> Color:
	var col := TileTypes.color_for(t.terrain, t.biome)
	if not t.has_life() and not TileTypes.is_water(t.terrain):
		col = col.darkened(0.30 * (1.0 - t.fertility))
	return col


# --------------------------------------------------------------- environment

## Sky per phase. The world starts under heavy overcast and clears as it
## recovers, so the lighting itself tracks the player's progress.
const SKIES := {
	"overcast": "res://assets/sky/overcast.hdr",
	"day": "res://assets/sky/day.hdr",
	"dusk": "res://assets/sky/dusk.hdr",
}

var _sky: Sky
var _current_sky := ""


func _load_sky(which: String = "overcast") -> Sky:
	_sky = Sky.new()
	_sky.radiance_size = Sky.RADIANCE_SIZE_128 \
		if quality.tier == Quality.Tier.LOW else Sky.RADIANCE_SIZE_256
	_apply_sky(which)
	return _sky


func _apply_sky(which: String) -> void:
	if _current_sky == which or _sky == null:
		return
	var path: String = SKIES.get(which, SKIES["day"])
	if not ResourceLoader.exists(path):
		# No HDRI present — fall back to a generated sky rather than failing.
		var fallback := ProceduralSkyMaterial.new()
		fallback.sky_top_color = Color(0.35, 0.52, 0.78)
		fallback.sky_horizon_color = Color(0.78, 0.82, 0.85)
		_sky.sky_material = fallback
		_current_sky = which
		return

	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load(path)
	mat.energy_multiplier = 1.0
	_sky.sky_material = mat
	_current_sky = which


## Called as the run progresses so the sky opens up with the landscape.
func set_sky_for_phase(phase: int) -> void:
	match phase:
		GameState.Phase.RESTORE:
			_apply_sky("overcast")
		GameState.Phase.CULTIVATE, GameState.Phase.WILDLIFE:
			_apply_sky("day")
		_:
			_apply_sky("dusk")

func _apply_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.shadow_enabled = quality.shadows
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _load_sky()

	# Image-based lighting off the sky is what makes PBR materials read as
	# real rather than plastic.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	env.ssao_enabled = quality.ambient_occlusion
	env.ssr_enabled = quality.reflections

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_env.name = "WorldEnvironment"

	# Depth of field lives on the camera attributes, not the environment.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = quality.depth_of_field
	attributes.dof_blur_far_distance = 60.0
	attributes.dof_blur_far_transition = 20.0
	attributes.dof_blur_amount = 0.06
	world_env.camera_attributes = attributes

	add_child(world_env)


# --------------------------------------------------------------------- input

## Turn a screen position into the hex under it, by intersecting the camera
## ray with the ground plane.
func pick_tile(camera: Camera3D, screen_pos: Vector2):
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null

	var distance := -from.y / dir.y
	if distance < 0.0:
		return null

	var hit := from + dir * distance
	var axial := Grid.from_pixel(Vector2(hit.x, hit.z), TILE_SIZE)
	if not world.has(axial):
		return null
	return axial


## Centre of a tile's top surface in world space. Anything that needs to happen
## *at* a tile — a positional sound, later an effect — anchors here rather than
## re-deriving the elevation table.
func tile_center(axial: Vector2i) -> Vector3:
	var flat := Grid.to_pixel(axial, TILE_SIZE)
	var tile := world.get_tile(axial)
	var height := 0.2 * HEIGHT_SCALE
	if tile != null:
		height = TERRAIN_HEIGHT.get(tile.terrain, 0.2) * HEIGHT_SCALE
	return Vector3(flat.x, height, flat.y)
