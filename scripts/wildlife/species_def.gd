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


## Localised display name.
func name_text() -> String:
	return tr(display_name)


## Localised one-line description.
func description_text() -> String:
	return tr(description)


## Human-readable requirement list, for the UI.
func requirement_lines() -> Array[String]:
	var out: Array[String] = []
	for biome in biome_needs:
		out.append("%d × %s" % [biome_needs[biome], TileTypes.biome_name(biome)])
	for terrain in terrain_needs:
		out.append("%d × %s" % [terrain_needs[terrain], TileTypes.terrain_name(terrain)])
	if min_temperature > -100.0:
		out.append(tr("REQ_TEMP_MIN").format([min_temperature], "{0}"))
	if max_temperature < 100.0:
		out.append(tr("REQ_TEMP_MAX").format([max_temperature], "{0}"))
	if needs_solitude:
		out.append(tr("REQ_SOLITUDE"))
	if not needs_companion.is_empty():
		var companion: SpeciesDef = Bestiary.get_species(needs_companion)
		var label := companion.name_text() if companion != null else needs_companion
		out.append(tr("REQ_COMPANION").format([label], "{0}"))
	return out
