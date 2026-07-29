class_name Building
extends RefCounted

## A placed instance of a BuildingDef.

var def: BuildingDef
var axial: Vector2i
var active: bool = false
## Set once the reclaim phase has hauled this building away.
var reclaimed: bool = false


func _init(p_def: BuildingDef, p_axial: Vector2i) -> void:
	def = p_def
	axial = p_axial


func on_placed(world: World) -> void:
	match def.effect:
		BuildingDef.Effect.EXCAVATE:
			# Terraforming is a one-shot action, not a continuous effect.
			for t in world.tiles_in_radius(axial, def.effect_radius):
				if t.terrain == TileTypes.Terrain.WASTELAND or t.terrain == TileTypes.Terrain.ROCK:
					world.set_terrain(t.axial, TileTypes.Terrain.RIVERBED)
		BuildingDef.Effect.UPLIFT:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				if t.terrain == TileTypes.Terrain.WASTELAND:
					world.set_terrain(t.axial, TileTypes.Terrain.ROCK)
				elif t.terrain == TileTypes.Terrain.ROCK:
					world.set_terrain(t.axial, TileTypes.Terrain.CLIFF)


func on_removed(_world: World) -> void:
	active = false


## Continuous effect, applied once per simulation tick while powered.
func apply(world: World) -> void:
	match def.effect:
		BuildingDef.Effect.PURIFY:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				if not TileTypes.is_water(t.terrain):
					world.add_fertility(t.axial, def.effect_strength)

		BuildingDef.Effect.IRRIGATE:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				world.add_moisture(t.axial, def.effect_strength)

		BuildingDef.Effect.FLOOD:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				if t.terrain == TileTypes.Terrain.RIVERBED:
					world.set_terrain(t.axial, TileTypes.Terrain.WATER)

		BuildingDef.Effect.WARM:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				world.shift_temperature(t.axial, def.effect_strength)

		BuildingDef.Effect.COOL:
			for t in world.tiles_in_radius(axial, def.effect_radius):
				world.shift_temperature(t.axial, -def.effect_strength)

		BuildingDef.Effect.POLLINATE:
			# Only helps ground that is already alive — rewards sequencing.
			for t in world.tiles_in_radius(axial, def.effect_radius):
				if t.has_life():
					world.add_fertility(t.axial, def.effect_strength)

		BuildingDef.Effect.RECLAIM:
			pass  # Driven by GameState during the exit phase.


## Buildings inside a silo's radius that still need hauling away.
func reclaim_targets(world: World) -> Array:
	var out: Array = []
	if def.effect != BuildingDef.Effect.RECLAIM:
		return out
	for a in Hex.in_radius(axial, def.effect_radius):
		var b = world.building_at(a)
		if b != null and b != self and not b.reclaimed:
			out.append(b)
	return out
