class_name WildlifeSystem
extends RefCounted

## Watches the world and lets species settle when somewhere can support them.
##
## Evaluation is deliberately not run every tick — it scans every hex as a
## candidate home, which is cheap but not free, and animals arriving once a
## second would feel frantic rather than earned.

signal species_settled(species_id: String, axial: Vector2i)
signal species_lost(species_id: String)

## Sim ticks between habitat surveys.
const SURVEY_INTERVAL := 6

var world: World
## species_id -> Vector2i home
var settled: Dictionary = {}

var _ticks := 0


func _init(p_world: World) -> void:
	world = p_world
	world.simulated.connect(_on_simulated)


func _on_simulated() -> void:
	_ticks += 1
	if _ticks % SURVEY_INTERVAL != 0:
		return
	survey()


## Re-check every species: newcomers arrive, and anything whose habitat was
## destroyed leaves again.
func survey() -> void:
	for id in Bestiary.ids():
		var def: SpeciesDef = Bestiary.get_species(id)

		if settled.has(id):
			# Still viable where it lives?
			if not _suits(def, settled[id]):
				settled.erase(id)
				species_lost.emit(id)
			continue

		# Untyped: find_home returns either a Vector2i or null.
		var home = find_home(def)
		if home != null:
			settled[id] = home
			species_settled.emit(id, home)


func count() -> int:
	return settled.size()


func is_settled(id: String) -> bool:
	return settled.has(id)


## Best hex this species could call home, or null if nowhere works yet.
func find_home(def: SpeciesDef):
	if not def.needs_companion.is_empty() and not settled.has(def.needs_companion):
		return null

	for t in world.all_tiles():
		# Animals settle on land they can stand on, or in the water they swim in.
		if t.terrain == TileTypes.Terrain.CLIFF:
			continue
		if _suits(def, t.axial):
			return t.axial
	return null


## Does the neighbourhood around `axial` meet every requirement?
func _suits(def: SpeciesDef, axial: Vector2i) -> bool:
	if not world.has(axial):
		return false

	var biome_counts := {}
	var terrain_counts := {}
	var temp_sum := 0.0
	var n := 0

	for t in world.tiles_in_radius(axial, def.habitat_radius):
		biome_counts[t.biome] = biome_counts.get(t.biome, 0) + 1
		terrain_counts[t.terrain] = terrain_counts.get(t.terrain, 0) + 1
		temp_sum += t.temperature
		n += 1

		if def.needs_solitude and not t.is_empty():
			return false

	if n == 0:
		return false

	for biome in def.biome_needs:
		if biome_counts.get(biome, 0) < def.biome_needs[biome]:
			return false

	for terrain in def.terrain_needs:
		if terrain_counts.get(terrain, 0) < def.terrain_needs[terrain]:
			return false

	var avg_temp := temp_sum / float(n)
	if avg_temp < def.min_temperature or avg_temp > def.max_temperature:
		return false

	return true


## How close a species is to being able to settle, 0..1. Drives the UI hints.
func best_progress(def: SpeciesDef) -> float:
	if settled.has(def.id):
		return 1.0

	var best := 0.0
	for t in world.all_tiles():
		if t.terrain == TileTypes.Terrain.CLIFF:
			continue
		var score := _progress_at(def, t.axial)
		best = maxf(best, score)
		if is_equal_approx(best, 1.0):
			break
	return best


func _progress_at(def: SpeciesDef, axial: Vector2i) -> float:
	var biome_counts := {}
	var terrain_counts := {}
	for t in world.tiles_in_radius(axial, def.habitat_radius):
		biome_counts[t.biome] = biome_counts.get(t.biome, 0) + 1
		terrain_counts[t.terrain] = terrain_counts.get(t.terrain, 0) + 1

	var ratios: Array[float] = []
	for biome in def.biome_needs:
		var have: float = biome_counts.get(biome, 0)
		ratios.append(minf(1.0, have / float(def.biome_needs[biome])))
	for terrain in def.terrain_needs:
		var have: float = terrain_counts.get(terrain, 0)
		ratios.append(minf(1.0, have / float(def.terrain_needs[terrain])))

	if ratios.is_empty():
		return 0.0

	# The habitat is only as good as its scarcest requirement.
	var lowest := 1.0
	for r in ratios:
		lowest = minf(lowest, r)
	return lowest


## Species sorted by how close they are — the UI shows the near-misses first.
func nearest_candidates(limit: int = 3) -> Array:
	var rows := []
	for id in Bestiary.ids():
		if settled.has(id):
			continue
		var def: SpeciesDef = Bestiary.get_species(id)
		rows.append({"def": def, "progress": best_progress(def)})
	rows.sort_custom(func(a, b): return a.progress > b.progress)
	return rows.slice(0, limit)
