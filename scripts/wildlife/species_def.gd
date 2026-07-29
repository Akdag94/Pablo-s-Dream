class_name SpeciesDef
extends RefCounted

## What a species needs before it will settle somewhere.
##
## A species does not get placed by the player. It arrives on its own once
## some patch of the world can support it — which means the player's job is to
## build the conditions, not the animal.

var id: String
var display_name: String
var description: String

## How far from a candidate hex we look when counting habitat.
var habitat_radius: int = 3

## Biome -> minimum tiles required within habitat_radius.
var biome_needs: Dictionary = {}
## Terrain -> minimum tiles required within habitat_radius.
var terrain_needs: Dictionary = {}

var min_temperature: float = -100.0
var max_temperature: float = 100.0

## Shy species refuse to settle while machinery is still standing nearby.
var needs_solitude: bool = false
## Some species only arrive once another species already lives here.
var needs_companion: String = ""

var color: Color = Color.WHITE


func _init(p: Dictionary) -> void:
	id = p.get("id", "")
	display_name = p.get("name", id)
	description = p.get("description", "")
	habitat_radius = p.get("radius", 3)
	biome_needs = p.get("biomes", {})
	terrain_needs = p.get("terrain", {})
	min_temperature = p.get("min_temp", -100.0)
	max_temperature = p.get("max_temp", 100.0)
	needs_solitude = p.get("solitude", false)
	needs_companion = p.get("companion", "")
	color = p.get("color", Color.WHITE)


## Human-readable requirement list, for the UI.
func requirement_lines() -> Array[String]:
	var out: Array[String] = []
	for biome in biome_needs:
		out.append("%d × %s" % [biome_needs[biome], _biome_name(biome)])
	for terrain in terrain_needs:
		out.append("%d × %s" % [terrain_needs[terrain], _terrain_name(terrain)])
	if min_temperature > -100.0:
		out.append("at least %.0f°C" % min_temperature)
	if max_temperature < 100.0:
		out.append("at most %.0f°C" % max_temperature)
	if needs_solitude:
		out.append("no machinery nearby")
	if not needs_companion.is_empty():
		out.append("%s already settled" % needs_companion)
	return out


static func _biome_name(b: int) -> String:
	return TileTypes.Biome.keys()[b].capitalize()


static func _terrain_name(t: int) -> String:
	return TileTypes.Terrain.keys()[t].capitalize()
