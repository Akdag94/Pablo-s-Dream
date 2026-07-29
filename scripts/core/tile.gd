class_name Tile
extends RefCounted

## One square cell of the world.

var axial: Vector2i

var terrain: TileTypes.Terrain = TileTypes.Terrain.WASTELAND
var biome: TileTypes.Biome = TileTypes.Biome.NONE

## How high this ground stands: 0.0 at the waterline, 1.0 at the highest point
## on the map. Continuous on purpose — deriving height from `terrain` instead
## gave every cell one of seven fixed levels, which read as a checkerboard of
## random steps rather than as a landscape. No game rule reads this; it exists
## so the renderer has a smooth surface to follow.
var elevation: float = 0.0

## 0.0 = poisoned, 1.0 = rich loam. Scrubbers raise this.
var fertility: float = 0.0
## 0.0 = bone dry, 1.0 = saturated. Diffuses outward from water.
var moisture: float = 0.0
## Degrees celsius. Shifted by climate buildings, gates some biomes.
var temperature: float = 14.0

## Id of the building standing here, or an empty string.
var building_id: String = ""
## Whether a turbine's supply radius currently reaches this cell.
var powered: bool = false


func _init(p_axial: Vector2i) -> void:
	axial = p_axial


func is_empty() -> bool:
	return building_id.is_empty()


func has_life() -> bool:
	return biome != TileTypes.Biome.NONE


func can_build() -> bool:
	return is_empty() and TileTypes.is_buildable(terrain)


## Leaves earned by this cell in its current state.
func score() -> int:
	return TileTypes.biome_value(biome)


func duplicate_state() -> Dictionary:
	return {
		"terrain": terrain,
		"biome": biome,
		"fertility": fertility,
		"moisture": moisture,
		"temperature": temperature,
	}
