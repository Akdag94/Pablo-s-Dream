class_name BuildingDef
extends RefCounted

## Static description of a building type. One instance per type, shared by
## every placed copy of it. Everything here is data — no per-tile state.

enum Effect {
	NONE,
	POWER,          ## Supplies power to its radius.
	PURIFY,         ## Raises fertility.
	IRRIGATE,       ## Raises moisture.
	FLOOD,          ## Turns adjacent riverbed into water.
	EXCAVATE,       ## Carves ground down into riverbed.
	UPLIFT,         ## Raises ground into rock/cliff.
	WARM,           ## Raises temperature.
	COOL,           ## Lowers temperature.
	POLLINATE,      ## Boosts fertility where greenery already exists.
	RECLAIM,        ## Recycles neighbouring buildings during the exit phase.
	AIRSHIP,        ## The exit vehicle.
}

## Which phase this building belongs to. Gates the build menu.
enum Tier { RESTORE = 1, CULTIVATE = 2, RECLAIM = 3 }

var id: String
var display_name: String
var description: String
var tier: Tier = Tier.RESTORE
var cost: int = 0

var effect: Effect = Effect.NONE
var effect_radius: int = 1
var effect_strength: float = 0.0

var needs_power: bool = true
var provides_power: bool = false
var power_radius: int = 0

## Terrain this building may sit on. Empty means "use the global default".
var allowed_terrain: Array = []
## If true the building must be adjacent to water to function.
var requires_water_adjacency: bool = false

var color: Color = Color.WHITE


func _init(p: Dictionary) -> void:
	id = p.get("id", "")
	display_name = p.get("name", id)
	description = p.get("description", "")
	tier = p.get("tier", Tier.RESTORE)
	cost = p.get("cost", 0)
	effect = p.get("effect", Effect.NONE)
	effect_radius = p.get("radius", 1)
	effect_strength = p.get("strength", 0.0)
	needs_power = p.get("needs_power", true)
	provides_power = p.get("provides_power", false)
	power_radius = p.get("power_radius", 0)
	allowed_terrain = p.get("allowed_terrain", [])
	requires_water_adjacency = p.get("requires_water", false)
	color = p.get("color", Color.WHITE)


## Localised display name.
func name_text() -> String:
	return tr(display_name)


## Localised one-line description.
func description_text() -> String:
	return tr(description)


func can_sit_on(terrain: TileTypes.Terrain) -> bool:
	if allowed_terrain.is_empty():
		return TileTypes.is_buildable(terrain)
	return terrain in allowed_terrain
