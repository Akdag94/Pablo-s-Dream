class_name LevelDef
extends RefCounted

## Static description of one region: the map it generates, the climate it starts
## under, and what the player has to achieve there.
##
## Everything here is data. Two levels differing only in `base_temperature`
## already play differently, because the biome settling rules read temperature
## and the player has to spend on lenses or condensers to move it.
##
## The seed is part of the definition on purpose. A region that generates a
## different island every time cannot be balanced and cannot be learned — and
## "it went too fast" is not a report anyone can act on when the map was never
## the same twice.

var id: String

## Fixed generation seed. Never 0 — that is World's "surprise me" value.
var seed_value: int = 1
## Half-width of the square map, in tiles.
var radius: int = 14

# ------------------------------------------------------------------- climate

## Degrees every land tile starts at, before any machine touches it.
var base_temperature: float = 14.0
## Elevation below which ground is ocean. Raise it to drown the map, lower it
## to expose more buildable land.
var sea_level: float = -0.45
## Added to every elevation sample. Positive lifts the whole region into rock
## and cliff; negative flattens and floods it.
var elevation_bias: float = 0.0
## Share of the interior that generates as dry riverbed, 0..1. These are the
## channels a pump can turn back into running water, so this is really a knob
## for how generous the region is with water.
var river_density: float = 0.05

# ---------------------------------------------------------------- objectives

var starting_leaves: int = 20
## Share of the land that must be alive to clear phase 1.
var restore_target: float = 0.28
## How many distinct biomes phase 2 wants, and how big each has to be.
var required_biomes: int = 3
var biome_min_tiles: int = 12
## How many species have to settle before the airship can be built.
var required_species: int = 4


func _init(p: Dictionary) -> void:
	id = p.get("id", "")
	seed_value = p.get("seed", 1)
	radius = p.get("radius", 14)

	base_temperature = p.get("temperature", 14.0)
	sea_level = p.get("sea_level", -0.45)
	elevation_bias = p.get("elevation_bias", 0.0)
	river_density = p.get("river_density", 0.05)

	starting_leaves = p.get("starting_leaves", 20)
	restore_target = p.get("restore_target", 0.28)
	required_biomes = p.get("required_biomes", 3)
	biome_min_tiles = p.get("biome_min_tiles", 12)
	required_species = p.get("required_species", 4)


## Localised region name.
func name_text() -> String:
	return tr("LEVEL_" + id.to_upper())


## Localised one-line briefing — what makes this region awkward.
func brief_text() -> String:
	return tr("LEVEL_" + id.to_upper() + "_BRIEF")
