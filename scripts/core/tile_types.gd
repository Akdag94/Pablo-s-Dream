class_name TileTypes
extends RefCounted

## Enumerations and lookup tables describing what a single hex can be.

## Bedrock / ground material. Changes rarely, and only via terraforming.
enum Terrain {
	WASTELAND,   ## Dead, poisoned ground. The starting state.
	ROCK,        ## Bare stone. Can be excavated or built on.
	CLIFF,       ## Raised stone. Blocks most construction.
	SAND,        ## Dry loose ground, becomes beach next to water.
	RIVERBED,    ## Carved channel. Fills with water when fed.
	WATER,       ## Fresh water.
	OCEAN,       ## Salt water. Map edge, cannot be terraformed away.
}

## The living layer that grows on top of the terrain. This is what scores.
enum Biome {
	NONE,
	GRASS,       ## Baseline greenery, the gateway to everything else.
	SHRUB,       ## Dry hardy scrub. Wants warmth and poor soil.
	WETLAND,     ## Saturated greenery. Wants standing water nearby.
	FOREST,      ## Mature trees. Wants rich soil and pollination.
	MANGROVE,    ## Wetland that meets salt water.
	BEACH,       ## Sand that meets water.
	REEF,        ## Ocean shallows brought back to life.
}

## Terrain a building may legally occupy.
const BUILDABLE_TERRAIN: Array[Terrain] = [
	Terrain.WASTELAND, Terrain.ROCK, Terrain.SAND, Terrain.RIVERBED,
]

## Biome tiles are worth this many leaves each when scored.
const BIOME_VALUE := {
	Biome.NONE: 0,
	Biome.GRASS: 1,
	Biome.SHRUB: 2,
	Biome.WETLAND: 2,
	Biome.FOREST: 3,
	Biome.MANGROVE: 3,
	Biome.BEACH: 1,
	Biome.REEF: 3,
}

## Flat colours for the prototype renderer. Replaced by art later.
const TERRAIN_COLOR := {
	Terrain.WASTELAND: Color("6b5d4f"),
	Terrain.ROCK: Color("857b70"),
	Terrain.CLIFF: Color("5c554e"),
	Terrain.SAND: Color("d8c89a"),
	Terrain.RIVERBED: Color("7a6a55"),
	Terrain.WATER: Color("4a90b8"),
	Terrain.OCEAN: Color("2e6b91"),
}

const BIOME_COLOR := {
	Biome.GRASS: Color("7fae52"),
	Biome.SHRUB: Color("a8a054"),
	Biome.WETLAND: Color("5f9e6e"),
	Biome.FOREST: Color("3f7a42"),
	Biome.MANGROVE: Color("4a7a5e"),
	Biome.BEACH: Color("e5d6a8"),
	Biome.REEF: Color("58a89a"),
}


static func is_water(terrain: Terrain) -> bool:
	return terrain == Terrain.WATER or terrain == Terrain.OCEAN


static func is_buildable(terrain: Terrain) -> bool:
	return terrain in BUILDABLE_TERRAIN


static func biome_value(biome: Biome) -> int:
	return BIOME_VALUE.get(biome, 0)


static func color_for(terrain: Terrain, biome: Biome) -> Color:
	if biome != Biome.NONE and BIOME_COLOR.has(biome):
		return BIOME_COLOR[biome]
	return TERRAIN_COLOR.get(terrain, Color.MAGENTA)
