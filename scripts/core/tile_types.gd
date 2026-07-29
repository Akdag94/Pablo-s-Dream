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
##
## Life arrives in two steps. Bare ground first turns to GREENERY — the tier-one
## gateway, worth almost nothing on its own — and only ground that is already
## green can specialise into one of the tier-two biomes below it. Nothing jumps
## from dead soil straight to forest.
##
## That ordering is the whole shape of the middle game: phase one is about
## getting *anything* to grow, and phase two is about deciding what. Without the
## gate both happened at once and phase two was over before it started.
enum Biome {
	NONE,
	GREENERY,    ## Tier 1. First life. The gateway to everything below.

	GRASS,       ## Tier 2. Open meadow. The default when nothing else fits.
	SHRUB,       ## Tier 2. Dry hardy scrub. Wants warmth and poor soil.
	WETLAND,     ## Tier 2. Saturated ground beside open fresh water.
	FOREST,      ## Tier 2. Mature trees. Wants rich soil and moderate water.
	MANGROVE,    ## Tier 2. Wetland that meets salt water.
	REED_BED,    ## Tier 2. Dense reeds. Needs a hydroponium over an irrigator.
	TUNDRA,      ## Tier 2. Cold, low, sparse. The polar answer to meadow.
	LICHEN,      ## Tier 2. Cold bare stone brought back to life.

	BEACH,       ## Forms on its own where sand meets water.
	REEF,        ## Forms on its own in warm, clean ocean shallows.
}

## Which step of the ladder each biome sits on.
##
## Tier 2 is what phase two counts. Beach and reef are deliberately tier 0
## alongside bare ground: they appear without the player asking, so letting them
## satisfy an objective would hand over progress nobody earned.
const BIOME_TIER := {
	Biome.NONE: 0,
	Biome.BEACH: 0,
	Biome.REEF: 0,
	Biome.GREENERY: 1,
	Biome.GRASS: 2,
	Biome.SHRUB: 2,
	Biome.WETLAND: 2,
	Biome.FOREST: 2,
	Biome.MANGROVE: 2,
	Biome.REED_BED: 2,
	Biome.TUNDRA: 2,
	Biome.LICHEN: 2,
}

## Terrain a building may legally occupy.
const BUILDABLE_TERRAIN: Array[Terrain] = [
	Terrain.WASTELAND, Terrain.ROCK, Terrain.SAND, Terrain.RIVERBED,
]

## Biome tiles are worth this many leaves each when scored. Tier one pays a
## token amount so early greening still funds the next purifier; the money is in
## specialising.
const BIOME_VALUE := {
	Biome.NONE: 0,
	Biome.GREENERY: 1,
	Biome.GRASS: 2,
	Biome.SHRUB: 2,
	Biome.TUNDRA: 2,
	Biome.LICHEN: 2,
	Biome.WETLAND: 3,
	Biome.REED_BED: 3,
	Biome.FOREST: 4,
	Biome.MANGROVE: 4,
	Biome.BEACH: 1,
	Biome.REEF: 4,
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
	Biome.GREENERY: Color("9cb86a"),
	Biome.GRASS: Color("7fae52"),
	Biome.SHRUB: Color("a8a054"),
	Biome.WETLAND: Color("5f9e6e"),
	Biome.FOREST: Color("3f7a42"),
	Biome.MANGROVE: Color("4a7a5e"),
	Biome.REED_BED: Color("6f9e58"),
	Biome.TUNDRA: Color("9aa886"),
	Biome.LICHEN: Color("8f9c7a"),
	Biome.BEACH: Color("e5d6a8"),
	Biome.REEF: Color("58a89a"),
}


static func is_water(terrain: Terrain) -> bool:
	return terrain == Terrain.WATER or terrain == Terrain.OCEAN


static func is_buildable(terrain: Terrain) -> bool:
	return terrain in BUILDABLE_TERRAIN


static func biome_value(biome: Biome) -> int:
	return BIOME_VALUE.get(biome, 0)


static func biome_tier(biome: Biome) -> int:
	return BIOME_TIER.get(biome, 0)


## Ground that has taken life and can therefore specialise. Beach and reef do
## not count: they are not something the player grew.
static func is_green(biome: Biome) -> bool:
	return biome_tier(biome) >= 1


## A biome the player had to deliberately create. This is what phase two counts.
static func is_specialised(biome: Biome) -> bool:
	return biome_tier(biome) >= 2


## Localised biome name, e.g. Biome.WETLAND -> "Sulak Alan".
static func biome_name(biome: int) -> String:
	return TranslationServer.translate("BIOME_" + Biome.keys()[biome])


## Localised terrain name, e.g. Terrain.RIVERBED -> "Kuru Yatak".
static func terrain_name(terrain: int) -> String:
	return TranslationServer.translate("TERRAIN_" + Terrain.keys()[terrain])


static func color_for(terrain: Terrain, biome: Biome) -> Color:
	if biome != Biome.NONE and BIOME_COLOR.has(biome):
		return BIOME_COLOR[biome]
	return TERRAIN_COLOR.get(terrain, Color.MAGENTA)
