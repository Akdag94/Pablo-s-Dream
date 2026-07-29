class_name Levels
extends RefCounted

## The regions the game ships with, in play order.
##
## >>> ALL LEVEL TUNING LIVES HERE <<< — the same rule `catalog.gd` follows for
## buildings and `bestiary.gd` for species. Nothing else decides how big a map
## is, what climate it starts under, or what clearing it takes.
##
## Climate does most of the work of making a region feel different, because the
## biome rules in `world.gd` are written against temperature and moisture rather
## than against a region name. A cold map cannot grow shrub or reef at all until
## the player heats it; a hot one grows them for free and struggles to hold
## forest together. Neither needed a new rule.

static var _defs: Dictionary = {}
static var _order: Array[String] = []


static func all() -> Dictionary:
	if _defs.is_empty():
		_build()
	return _defs


static func get_level(id: String) -> LevelDef:
	return all().get(id)


## Every level in play order.
static func in_order() -> Array[LevelDef]:
	if _defs.is_empty():
		_build()
	var out: Array[LevelDef] = []
	for id in _order:
		out.append(_defs[id])
	return out


## The opening region. Used wherever a level is not specified — a save from
## before levels existed, or a scene left on its default.
static func first() -> LevelDef:
	return in_order()[0]


## Look up a level, falling back to the first one and saying so. A bad id is a
## typo in a scene property or an old save, and neither should be fatal — but
## silently playing the wrong region would be worse than the warning.
static func resolve(id: String) -> LevelDef:
	var found := get_level(id)
	if found != null:
		return found
	if not id.is_empty():
		push_warning("Unknown level '%s' — falling back to '%s'" % [id, first().id])
	return first()


static func _add(p: Dictionary) -> void:
	var d := LevelDef.new(p)
	_defs[d.id] = d
	_order.append(d.id)


static func _build() -> void:
	# Pablo's island, and the one every rule was tuned against. Temperate,
	# generous with flat ground, one ring of ocean. The seed is the one the
	# headless test has always run on, so its numbers stay comparable.
	_add({
		"id": "home",
		"seed": 12345,
		"radius": 14,
		"temperature": 14.0,
	})

	# Hot, low and wet. Shrub and reef come back on their own here, so four
	# biomes is a fair ask — but forest needs moisture held *under* 0.70 and
	# this region keeps handing the player more water than it wants. The
	# difficulty is restraint, not scarcity.
	_add({
		"id": "delta",
		"seed": 48211,
		"radius": 14,
		"temperature": 24.0,
		"sea_level": -0.38,
		"elevation_bias": -0.06,
		"river_density": 0.09,
		"restore_target": 0.30,
		"required_biomes": 4,
		"biome_min_tiles": 10,
		"required_species": 5,
	})

	# Cold and stony. At 4 degrees shrub and reef are off the table entirely
	# until a solar lens has been running a while, so the reachable biome set
	# is smaller and every one of them has to be built deliberately. Less
	# buildable ground too, which is why the restore target comes down.
	_add({
		"id": "highland",
		"seed": 90317,
		"radius": 13,
		"temperature": 4.0,
		"sea_level": -0.52,
		"elevation_bias": 0.10,
		"river_density": 0.03,
		"starting_leaves": 24,
		"restore_target": 0.22,
		"required_biomes": 3,
		"biome_min_tiles": 10,
		"required_species": 3,
	})
