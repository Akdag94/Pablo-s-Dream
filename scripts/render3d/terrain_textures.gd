class_name TerrainTextures
extends RefCounted

## Packs the ground texture sets into Texture2DArrays.
##
## The whole island is one MultiMesh draw call, so every tile has to be able to
## reach every texture from the same material. A texture array does that: the
## shader indexes a layer per instance instead of the renderer swapping
## materials, which would break the batch.
##
## Layer order below IS the contract with terrain.gdshader — the numbers are
## written into instance custom data.

const ROOT := "res://assets/terrain/"

## Layer index -> folder name. Order matters and must not be reshuffled.
const LAYERS := [
	"wasteland",      # 0
	"wasteland_dry",  # 1
	"grass",          # 2
	"forest",         # 3
	"wetland",        # 4
	"rock",           # 5
	"sand",           # 6
	"riverbed",       # 7
]

## Which layer each biome draws with.
const BIOME_LAYER := {
	TileTypes.Biome.NONE: 0,
	TileTypes.Biome.GRASS: 2,
	TileTypes.Biome.SHRUB: 1,
	TileTypes.Biome.WETLAND: 4,
	TileTypes.Biome.FOREST: 3,
	TileTypes.Biome.MANGROVE: 4,
	TileTypes.Biome.BEACH: 6,
	TileTypes.Biome.REEF: 6,
}

## Bare ground falls back to terrain when nothing grows there yet.
const TERRAIN_LAYER := {
	TileTypes.Terrain.WASTELAND: 0,
	TileTypes.Terrain.ROCK: 5,
	TileTypes.Terrain.CLIFF: 5,
	TileTypes.Terrain.SAND: 6,
	TileTypes.Terrain.RIVERBED: 7,
	TileTypes.Terrain.WATER: 7,
	TileTypes.Terrain.OCEAN: 7,
}

var albedo: Texture2DArray
var normal: Texture2DArray
var orm: Texture2DArray
var loaded := false


## Build all three arrays. Returns false if the texture files are not present,
## in which case the shader falls back to its procedural surface.
func build() -> bool:
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var orm_images: Array[Image] = []

	for folder in LAYERS:
		var color := _find(folder, "_Color")
		var norm := _find(folder, "_NormalGL")
		var rough := _find(folder, "_Roughness")
		var ao := _find(folder, "_AmbientOcclusion")

		if color == null or norm == null:
			push_warning("Terrain textures missing for '%s' — using procedural ground" % folder)
			return false

		albedo_images.append(color)
		normal_images.append(norm)
		# Pack roughness and occlusion into one texture rather than sampling
		# two: the fetch count is what costs on mobile, not the memory.
		orm_images.append(_pack_orm(rough, ao, color.get_size()))

	albedo = _make_array(albedo_images)
	normal = _make_array(normal_images)
	orm = _make_array(orm_images)
	loaded = true
	return true


## ambientCG names files after the material, so glob rather than guess.
func _find(folder: String, suffix: String) -> Image:
	var dir_path := ROOT + folder
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return null

	for file in dir.get_files():
		# Godot appends .import to source files it has ingested; ignore those.
		if file.ends_with(".import"):
			continue
		if suffix in file:
			var tex := load(dir_path + "/" + file)
			if tex is Texture2D:
				return tex.get_image()
	return null


## Roughness into red, ambient occlusion into green. Blue is left free.
func _pack_orm(rough: Image, ao: Image, size: Vector2i) -> Image:
	var out := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)

	var r := rough
	if r != null and r.get_size() != size:
		r = r.duplicate()
		r.resize(size.x, size.y)

	var a := ao
	if a != null and a.get_size() != size:
		a = a.duplicate()
		a.resize(size.x, size.y)

	for y in size.y:
		for x in size.x:
			var roughness := r.get_pixel(x, y).r if r != null else 0.9
			var occlusion := a.get_pixel(x, y).r if a != null else 1.0
			out.set_pixel(x, y, Color(roughness, occlusion, 0.0))
	return out


func _make_array(images: Array[Image]) -> Texture2DArray:
	# Every layer must share one size and format, so normalise to the first.
	var size := images[0].get_size()
	var format := images[0].get_format()

	var normalised: Array[Image] = []
	for img in images:
		var copy := img.duplicate() as Image
		if copy.get_size() != size:
			copy.resize(size.x, size.y)
		if copy.get_format() != format:
			copy.convert(format)
		copy.generate_mipmaps()
		normalised.append(copy)

	var array := Texture2DArray.new()
	array.create_from_images(normalised)
	return array


## Which layer this tile should draw with.
static func layer_for(tile: Tile) -> int:
	if tile.has_life() and BIOME_LAYER.has(tile.biome):
		return BIOME_LAYER[tile.biome]
	return TERRAIN_LAYER.get(tile.terrain, 0)
