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

const HEX_RADIUS := 1.0
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

@export var map_radius: int = 14
@export var sim_interval: float = 0.35

var world: World
var state: GameState
var quality: Quality

var _land: MultiMeshInstance3D
var _water: MultiMeshInstance3D
var _land_tiles: Array[Tile] = []
var _water_tiles: Array[Tile] = []
var _dirty := true
var _sim_accum := 0.0


func _ready() -> void:
	quality = Quality.detect()

	world = World.new(map_radius)
	state = GameState.new(world)
	world.tile_changed.connect(func(_a): _dirty = true)

	_build_batches()
	_apply_environment()
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
	# Split once: a hex only moves between the two batches if its terrain
	# changes between wet and dry, which _refresh_instances handles by
	# rebuilding both lists.
	_land = _make_batch(_hex_prism_mesh(), _land_material())
	_water = _make_batch(_hex_prism_mesh(), _water_material())
	add_child(_land)
	add_child(_water)
	_refresh_instances()


func _make_batch(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


## A six-sided prism, flat-topped in the XZ plane.
func _hex_prism_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = HEX_RADIUS
	m.bottom_radius = HEX_RADIUS
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 1
	return m


## Procedural ground. Grain, clumping and normal detail are generated in the
## shader, so there are no texture files to download or to look wrong on one
## device and right on another.
func _land_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")

	# Fine detail costs fill rate, so the weakest tier gets a calmer surface.
	match quality.tier:
		Quality.Tier.LOW:
			mat.set_shader_parameter("detail_scale", 4.0)
			mat.set_shader_parameter("detail_strength", 0.20)
			mat.set_shader_parameter("normal_strength", 0.5)
		Quality.Tier.MEDIUM:
			mat.set_shader_parameter("detail_scale", 5.5)
			mat.set_shader_parameter("detail_strength", 0.26)
			mat.set_shader_parameter("normal_strength", 0.7)
		Quality.Tier.HIGH:
			mat.set_shader_parameter("detail_scale", 6.5)
			mat.set_shader_parameter("detail_strength", 0.32)
			mat.set_shader_parameter("normal_strength", 0.9)
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

	_fill_batch(_land, _land_tiles)
	_fill_batch(_water, _water_tiles)


func _fill_batch(node: MultiMeshInstance3D, tiles: Array[Tile]) -> void:
	var mm := node.multimesh
	mm.instance_count = tiles.size()

	for i in tiles.size():
		var t := tiles[i]
		var height: float = TERRAIN_HEIGHT.get(t.terrain, 0.2) * HEIGHT_SCALE
		var flat := Hex.to_pixel(t.axial, HEX_RADIUS)

		# The prism is centred on its own origin, so shift it down by half its
		# height to keep every tile sitting on the same base plane.
		var basis := Basis().scaled(Vector3(1.0, maxf(absf(height), 0.05), 1.0))
		var origin := Vector3(flat.x, height * 0.5, flat.y)

		mm.set_instance_transform(i, Transform3D(basis, origin))
		mm.set_instance_color(i, _tile_color(t))


func _tile_color(t: Tile) -> Color:
	var col := TileTypes.color_for(t.terrain, t.biome)
	if not t.has_life() and not TileTypes.is_water(t.terrain):
		col = col.darkened(0.30 * (1.0 - t.fertility))
	return col


# --------------------------------------------------------------- environment

func _apply_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.89)
	sun.shadow_enabled = quality.shadows
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.52, 0.78)
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.85)
	sky_mat.ground_bottom_color = Color(0.22, 0.24, 0.26)
	sky_mat.ground_horizon_color = Color(0.66, 0.68, 0.68)
	sky.sky_material = sky_mat
	env.sky = sky

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
	var axial := Hex.from_pixel(Vector2(hit.x, hit.z), HEX_RADIUS)
	if not world.has(axial):
		return null
	return axial
