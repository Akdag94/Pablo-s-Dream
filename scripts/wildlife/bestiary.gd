class_name Bestiary
extends RefCounted

## Every species that can find its way to the island, and what it needs.
##
## Like Catalog, this file is pure tuning — add a dictionary entry and the
## species exists everywhere in the game.

const B := TileTypes.Biome
const TR := TileTypes.Terrain

static var _species: Dictionary = {}


static func all() -> Dictionary:
	if _species.is_empty():
		_build()
	return _species


static func get_species(id: String) -> SpeciesDef:
	return all().get(id)


static func ids() -> Array:
	return all().keys()


static func _add(p: Dictionary) -> void:
	var s := SpeciesDef.new(p)
	_species[s.id] = s


static func _build() -> void:
	_add({
		"id": "frog",
		"name": "Frog",
		"description": "The first thing to return. Wants shallow water with something green around it.",
		"radius": 3,
		"biomes": {B.WETLAND: 10, B.GRASS: 4},
		"color": Color("6fbf5a"),
	})
	_add({
		"id": "deer",
		"name": "Deer",
		"description": "Needs open meadow, and a lot of it.",
		"radius": 4,
		"biomes": {B.GRASS: 20},
		"color": Color("c08a52"),
	})
	_add({
		"id": "heron",
		"name": "Heron",
		"description": "Stalks the edge where standing water meets reed.",
		"radius": 4,
		"biomes": {B.WETLAND: 12},
		"terrain": {TR.WATER: 5},
		"color": Color("b8c4cc"),
	})
	_add({
		"id": "beaver",
		"name": "Beaver",
		"description": "Wants running water with timber standing beside it.",
		"radius": 4,
		"biomes": {B.FOREST: 10},
		"terrain": {TR.WATER: 8},
		"color": Color("8a6242"),
	})
	_add({
		"id": "fox",
		"name": "Fox",
		"description": "Lives on the seam between meadow and treeline. Follows the deer.",
		"radius": 4,
		"biomes": {B.GRASS: 12, B.FOREST: 8},
		"companion": "deer",
		"color": Color("d97b3c"),
	})
	_add({
		"id": "songbird",
		"name": "Songbird",
		"description": "Deep forest only, and only once the machines have gone quiet.",
		"radius": 3,
		"biomes": {B.FOREST: 16},
		"solitude": true,
		"color": Color("e8c547"),
	})
	_add({
		"id": "tortoise",
		"name": "Tortoise",
		"description": "Warm sand, close to the water's edge.",
		"radius": 3,
		"biomes": {B.BEACH: 8},
		"min_temp": 18.0,
		"color": Color("9c8f5f"),
	})
	_add({
		"id": "butterflies",
		"name": "Butterflies",
		"description": "Dry warm scrub in bloom.",
		"radius": 3,
		"biomes": {B.SHRUB: 12},
		"min_temp": 20.0,
		"color": Color("e07ab8"),
	})
	_add({
		"id": "otter",
		"name": "Otter",
		"description": "Clean water with cover on the bank.",
		"radius": 4,
		"biomes": {B.FOREST: 8, B.WETLAND: 6},
		"terrain": {TR.WATER: 10},
		"color": Color("7a5c3e"),
	})
	_add({
		"id": "reef_fish",
		"name": "Reef Fish",
		"description": "Warm shallows that have come back to life.",
		"radius": 3,
		"biomes": {B.REEF: 10},
		"min_temp": 18.0,
		"color": Color("4fc4c4"),
	})
