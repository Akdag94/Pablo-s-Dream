class_name GameState
extends RefCounted

## Owns the run: which phase we are in, how many leaves are banked, and what
## the player still has to do before the airship can lift.

signal leaves_changed(amount: int)
signal phase_changed(phase: Phase)
signal objective_updated
signal run_finished(summary: Dictionary)

enum Phase {
	RESTORE,    ## Clean the soil, bring back water, get something growing.
	CULTIVATE,  ## Build the required spread of distinct biomes.
	WILDLIFE,   ## Wait for animals to find the place liveable.
	RECLAIM,    ## Take every structure back and fly out.
	DONE,
}

## Leaves you start with, enough for a turbine and a couple of purifiers.
const STARTING_LEAVES := 20

## Phase 1 clears when this share of the land is alive.
const RESTORE_TARGET := 0.28
## Phase 2 clears when this many distinct biomes each hit their minimum size.
const REQUIRED_BIOMES := 3
const BIOME_MIN_TILES := 12
## Phase 3 clears when this many species have settled.
const REQUIRED_SPECIES := 4

var world: World
var wildlife: WildlifeSystem
var pablo: Pablo

var leaves: int = STARTING_LEAVES
var phase: Phase = Phase.RESTORE

## Leaves are paid out for new growth, so we only score tiles once.
var _scored_tiles: Dictionary = {}

## Ticks between the standing ecosystem paying out. Without this, income stops
## dead once the map stops changing and a stalled run can never recover.
const YIELD_INTERVAL := 20
## Leaves per this many points of standing biome, each payout.
const YIELD_DIVISOR := 40

var _yield_tick := 0


func _init(p_world: World) -> void:
	world = p_world
	wildlife = WildlifeSystem.new(world)
	pablo = Pablo.new(world)
	world.simulated.connect(_on_world_simulated)


# ------------------------------------------------------------------- economy

func can_afford(def: BuildingDef) -> bool:
	return leaves >= def.cost


func spend(amount: int) -> void:
	leaves = maxi(0, leaves - amount)
	leaves_changed.emit(leaves)


func earn(amount: int) -> void:
	leaves += amount
	leaves_changed.emit(leaves)


## Pay out for tiles that came alive since the last tick.
func _collect_new_growth() -> void:
	var gained := 0
	for t in world.all_tiles():
		if not t.has_life():
			continue
		var key := t.axial
		var previous: int = _scored_tiles.get(key, 0)
		var current := t.score()
		if current > previous:
			gained += current - previous
			_scored_tiles[key] = current
	if gained > 0:
		earn(gained)


# ------------------------------------------------------------- build actions

func try_place(def: BuildingDef, axial: Vector2i) -> bool:
	if def.tier > _max_unlocked_tier():
		return false
	if not can_afford(def):
		return false

	var tile := world.get_tile(axial)
	if tile == null or not tile.is_empty() or not def.can_sit_on(tile.terrain):
		return false

	if def.requires_water_adjacency and not _touches_water(axial):
		return false

	var b := Building.new(def, axial)
	if not world.place_building(b):
		return false

	spend(def.cost)
	return true


## Refund most of the cost so experimenting is cheap but not free.
func try_remove(axial: Vector2i) -> bool:
	var b = world.building_at(axial)
	if b == null:
		return false
	var refund := int(floor(b.def.cost * 0.7))
	if not world.remove_building(axial):
		return false
	earn(refund)
	return true


func _touches_water(axial: Vector2i) -> bool:
	for n in world.neighbors_of(axial):
		if TileTypes.is_water(n.terrain):
			return true
	return false


func _max_unlocked_tier() -> int:
	match phase:
		Phase.RESTORE: return BuildingDef.Tier.RESTORE
		# Wildlife arrives on its own — you keep the same tools while you wait.
		Phase.CULTIVATE, Phase.WILDLIFE: return BuildingDef.Tier.CULTIVATE
		_: return BuildingDef.Tier.RECLAIM


# -------------------------------------------------------------- progression

func _on_world_simulated() -> void:
	_collect_new_growth()
	_collect_standing_yield()
	_check_phase_advance()
	objective_updated.emit()


## A living landscape keeps paying, slowly. Growth is still the main income —
## this only stops a saturated map from becoming unplayable.
func _collect_standing_yield() -> void:
	_yield_tick += 1
	if _yield_tick % YIELD_INTERVAL != 0:
		return
	var payout := int(floor(float(world.total_score()) / float(YIELD_DIVISOR)))
	if payout > 0:
		earn(payout)


func _check_phase_advance() -> void:
	match phase:
		Phase.RESTORE:
			if world.restored_fraction() >= RESTORE_TARGET:
				_set_phase(Phase.CULTIVATE)
		Phase.CULTIVATE:
			if established_biomes().size() >= REQUIRED_BIOMES:
				_set_phase(Phase.WILDLIFE)
		Phase.WILDLIFE:
			if wildlife.count() >= REQUIRED_SPECIES:
				_set_phase(Phase.RECLAIM)
		Phase.RECLAIM:
			pass  # Ends only when the player launches.
		Phase.DONE:
			pass


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


## Biomes that currently cover at least BIOME_MIN_TILES hexes.
func established_biomes() -> Array:
	var counts := {}
	for t in world.all_tiles():
		# Beach forms on its own wherever sand meets water, so it does not
		# count as something the player established.
		if t.has_life() and t.biome != TileTypes.Biome.BEACH:
			counts[t.biome] = counts.get(t.biome, 0) + 1
	var out := []
	for b in counts:
		if counts[b] >= BIOME_MIN_TILES:
			out.append(b)
	return out


# ------------------------------------------------------------------- leaving

## Run one pass of reclamation. Silos dismantle whatever is in reach.
func run_reclaim_step() -> int:
	var removed := 0
	for b in world.buildings.values().duplicate():
		if b.def.effect != BuildingDef.Effect.RECLAIM:
			continue
		for target in b.reclaim_targets(world):
			if target.def.effect == BuildingDef.Effect.AIRSHIP:
				continue
			world.remove_building(target.axial)
			earn(int(floor(target.def.cost * 0.5)))
			removed += 1
	return removed


## Every structure gone except the airship itself?
func ready_to_launch() -> bool:
	if phase != Phase.RECLAIM:
		return false
	var has_airship := false
	for b in world.buildings.values():
		if b.def.effect == BuildingDef.Effect.AIRSHIP:
			has_airship = true
		else:
			return false
	return has_airship


func launch() -> void:
	if not ready_to_launch():
		return
	for b in world.buildings.values().duplicate():
		world.remove_building(b.axial)
	_set_phase(Phase.DONE)
	run_finished.emit(build_summary())


func build_summary() -> Dictionary:
	var counts := {}
	for t in world.all_tiles():
		if t.has_life():
			counts[t.biome] = counts.get(t.biome, 0) + 1
	return {
		"restored": world.restored_fraction(),
		"leaves": leaves,
		"biomes": counts,
		"species": wildlife.settled.keys(),
		"total_score": world.total_score(),
	}


## Pablo keeps walking after the airship has gone — that is the point.
func update_pablo(delta: float) -> void:
	pablo.update(delta)


func objective_text() -> String:
	match phase:
		Phase.RESTORE:
			var pct := int(world.restored_fraction() * 100.0)
			var goal := int(RESTORE_TARGET * 100.0)
			return tr("OBJ_RESTORE").format([pct, goal])
		Phase.CULTIVATE:
			var n := established_biomes().size()
			return tr("OBJ_CULTIVATE").format([n, REQUIRED_BIOMES])
		Phase.WILDLIFE:
			return tr("OBJ_WILDLIFE").format([wildlife.count(), REQUIRED_SPECIES])
		Phase.RECLAIM:
			var left := 0
			for b in world.buildings.values():
				if b.def.effect != BuildingDef.Effect.AIRSHIP:
					left += 1
			if left == 0:
				return tr("OBJ_BOARD")
			return tr("OBJ_RECLAIM").format([left])
		Phase.DONE:
			return tr("OBJ_DONE")
	return ""
