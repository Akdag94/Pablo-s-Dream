class_name Catalog
extends RefCounted

## The full build menu for Pablo's Dream, grouped by phase.
##
## Tuning lives here and nowhere else — every number a designer would want to
## twiddle is in this one file.

const E := BuildingDef.Effect
const T := BuildingDef.Tier

static var _defs: Dictionary = {}


static func all() -> Dictionary:
	if _defs.is_empty():
		_build()
	return _defs


static func get_def(id: String) -> BuildingDef:
	return all().get(id)


static func by_tier(tier: BuildingDef.Tier) -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for d in all().values():
		if d.tier == tier:
			out.append(d)
	return out


static func _add(p: Dictionary) -> void:
	var d := BuildingDef.new(p)
	_defs[d.id] = d


static func _build() -> void:
	# ---------------------------------------------------- phase 1: restoration
	_add({
		"id": "turbine",
		"name": "Wind Turbine",
		"description": "Supplies power to everything nearby. Nothing else runs without it.",
		# Must cost something, or the map fills with free turbines.
		"tier": T.RESTORE, "cost": 5,
		"effect": E.POWER, "provides_power": true, "power_radius": 4,
		"needs_power": false,
		"color": Color("e8e4dc"),
	})
	_add({
		"id": "purifier",
		"name": "Soil Purifier",
		"description": "Draws poison out of the ground, leaving soil that can hold roots.",
		"tier": T.RESTORE, "cost": 3,
		"effect": E.PURIFY, "radius": 2, "strength": 0.06,
		"color": Color("c9a227"),
	})
	_add({
		"id": "pump",
		"name": "Water Pump",
		"description": "Fills dry channels around it. Must stand beside open water.",
		"tier": T.RESTORE, "cost": 4,
		"effect": E.FLOOD, "radius": 2,
		"requires_water": true,
		"color": Color("4aa3df"),
	})
	_add({
		"id": "irrigator",
		"name": "Irrigator",
		"description": "Spreads moisture into dry soil so greenery can take hold.",
		"tier": T.RESTORE, "cost": 4,
		"effect": E.IRRIGATE, "radius": 2, "strength": 0.08,
		"color": Color("6fc2b0"),
	})
	_add({
		"id": "excavator",
		"name": "Excavator",
		"description": "Carves the ground into a channel. One-shot, and it cannot be undone.",
		"tier": T.RESTORE, "cost": 5,
		"effect": E.EXCAVATE, "radius": 1,
		"color": Color("b5773a"),
	})
	_add({
		"id": "kiln",
		"name": "Stone Kiln",
		"description": "Raises bedrock into hills and cliffs, shaping where water will run.",
		"tier": T.RESTORE, "cost": 5,
		"effect": E.UPLIFT, "radius": 1,
		"color": Color("8b8178"),
	})

	# ----------------------------------------------------- phase 2: cultivation
	_add({
		"id": "marsh_seeder",
		"name": "Marsh Seeder",
		"description": "Floods soil past saturation, turning green into wetland.",
		"tier": T.CULTIVATE, "cost": 8,
		"effect": E.IRRIGATE, "radius": 2, "strength": 0.16,
		"color": Color("5f9e6e"),
	})
	_add({
		"id": "arboretum",
		"name": "Arboretum",
		"description": "Enriches soil enough for mature trees to establish.",
		"tier": T.CULTIVATE, "cost": 10,
		"effect": E.PURIFY, "radius": 2, "strength": 0.12,
		"color": Color("3f7a42"),
	})
	_add({
		"id": "apiary",
		"name": "Apiary",
		"description": "Pollinates living ground. Does nothing where nothing grows yet.",
		"tier": T.CULTIVATE, "cost": 8,
		"effect": E.POLLINATE, "radius": 3, "strength": 0.10,
		"color": Color("e0a83c"),
	})
	_add({
		"id": "solar_lens",
		"name": "Solar Lens",
		"description": "Warms the surrounding air. Opens up scrubland and reefs.",
		"tier": T.CULTIVATE, "cost": 9,
		"effect": E.WARM, "radius": 3, "strength": 0.5,
		"color": Color("e8743c"),
	})
	_add({
		"id": "condenser",
		"name": "Mist Condenser",
		"description": "Cools a wide area, holding back the heat where you need it cold.",
		"tier": T.CULTIVATE, "cost": 9,
		"effect": E.COOL, "radius": 3, "strength": 0.5,
		"color": Color("7fb8d8"),
	})
	_add({
		"id": "rain_caller",
		"name": "Rain Caller",
		"description": "Wide, gentle moisture over everything in reach.",
		"tier": T.CULTIVATE, "cost": 12,
		"effect": E.IRRIGATE, "radius": 4, "strength": 0.05,
		"color": Color("9fb8d8"),
	})

	# --------------------------------------------------------- phase 3: leaving
	_add({
		"id": "reclaim_silo",
		"name": "Reclaim Silo",
		"description": "Dismantles every structure in reach and stores the parts.",
		# Free on purpose. The last phase is a spatial puzzle, not an economic
		# one — being unable to afford to clean up would just be a dead end.
		"tier": T.RECLAIM, "cost": 0,
		"effect": E.RECLAIM, "radius": 3,
		"needs_power": false,
		"color": Color("d9d2c5"),
	})
	_add({
		"id": "airship",
		"name": "Airship",
		"description": "Your way out. It can only lift once every structure is gone.",
		"tier": T.RECLAIM, "cost": 0,
		"effect": E.AIRSHIP, "radius": 0,
		"needs_power": false,
		"color": Color("f2ede3"),
	})
