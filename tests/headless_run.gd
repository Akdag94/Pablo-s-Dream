extends SceneTree

## Headless smoke test: play every shipping region roughly the way a player
## would, and assert the whole phase chain can actually be reached in each one.
##
##   godot --headless --script res://tests/headless_run.gd
##
## Running all of them matters more than it looks. A region is only a handful of
## numbers different from the last, and it is easy to write one whose objectives
## cannot be met at all — four biomes on a map too cold to grow shrub, say. The
## bot finding that out is much cheaper than the player finding it out.

const MAX_TICKS := 4000

## The band the bot tries to keep the land in, and the dials it reads to decide.
## These are not game rules — they are what a competent player would aim for,
## given that shrub needs 19 degrees and dry ground while forest drowns above
## 0.70 moisture.
const WET_ENOUGH := 0.50
const WARM_ENOUGH := 19.0
const COOL_ENOUGH := 23.0

var failures: Array[String] = []
var _turn := 0

## level id -> tick each phase was reached on, for comparing pacing between
## regions and between tuning passes.
var _pacing: Dictionary = {}


func _init() -> void:
	print("— Pablo's Dream · headless run —")

	for level in Levels.in_order():
		print("\n==================== %s ====================" % level.id)
		print("  seed %d · radius %d · %.0f C · target %d%% · %d biomes · %d species" % [
			level.seed_value, level.radius, level.base_temperature,
			int(level.restore_target * 100.0), level.required_biomes,
			level.required_species,
		])

		var world := World.new(level)
		var state := GameState.new(world)

		_check(world.level.id == level.id, "%s: world did not keep its level" % level.id)
		_check(state.leaves == level.starting_leaves,
			"%s: did not start with the level's leaves" % level.id)

		_report_generation(world)
		_play(world, state)

	_report_pacing()

	print("\n— result —")
	if failures.is_empty():
		print("OK  all checks passed")
	else:
		for f in failures:
			print("FAIL  " + f)

	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## Side-by-side pacing, so "it goes too fast" becomes a number that can be
## compared against the next tuning pass.
func _report_pacing() -> void:
	print("\n==================== pacing ====================")
	print("  %-10s %8s %8s %8s" % ["level", "→cult", "→wild", "→recl"])
	for id in _pacing:
		var p: Dictionary = _pacing[id]
		print("  %-10s %8s %8s %8s" % [
			id,
			p.get("CULTIVATE", "—"), p.get("WILDLIFE", "—"), p.get("RECLAIM", "—"),
		])


func _report_generation(world: World) -> void:
	var counts := {}
	for t in world.all_tiles():
		counts[t.terrain] = counts.get(t.terrain, 0) + 1

	var id := world.level.id
	print("world: %d tiles" % world.all_tiles().size())
	for terrain in counts:
		print("  %-10s %d" % [TileTypes.Terrain.keys()[terrain], counts[terrain]])

	# A region can be shaped however it likes, but it has to give the player
	# something to stand on and somewhere for water to come from.
	_check(world.all_tiles().size() > 400, "%s: grid looks too small" % id)
	_check(counts.get(TileTypes.Terrain.OCEAN, 0) > 0, "%s: no ocean generated" % id)
	_check(counts.get(TileTypes.Terrain.WASTELAND, 0) > 40,
		"%s: too little buildable land to play" % id)
	_check(counts.get(TileTypes.Terrain.RIVERBED, 0) > 0,
		"%s: no riverbed, so fresh water is unreachable" % id)
	_check(world.restored_fraction() == 0.0, "%s: world did not start dead" % id)


## Greedily place whatever is affordable and legal, then let the sim run.
func _play(world: World, state: GameState) -> void:
	var id := world.level.id
	var tick := 0
	var last_phase := state.phase
	_pacing[id] = {}
	print("\nphase RESTORE")

	while tick < MAX_TICKS and state.phase != GameState.Phase.RECLAIM:
		_take_turn(world, state)
		world.simulate()
		tick += 1

		if state.phase != last_phase:
			last_phase = state.phase
			_pacing[id][GameState.Phase.keys()[state.phase]] = tick
			print("  tick %-5d → %s   (%d%% alive, %d leaves, %d species)" % [
				tick,
				GameState.Phase.keys()[state.phase],
				int(world.restored_fraction() * 100.0),
				state.leaves,
				state.wildlife.count(),
			])

	print("\nstopped at tick %d in phase %s" % [
		tick, GameState.Phase.keys()[state.phase]
	])
	print("  restored   %d%%" % int(world.restored_fraction() * 100.0))
	print("  leaves     %d" % state.leaves)
	print("  buildings  %d" % world.count_buildings())
	print("  biomes     %s" % _biome_summary(world))
	print("  fresh water %d tiles" % _count_terrain(world, TileTypes.Terrain.WATER))
	print("  avg temp   %.1f C" % _average_temperature(world))
	print("  built      %s" % _building_summary(world))
	print("  wildlife   %s" % str(state.wildlife.settled.keys()))
	print("  pablo      %s at %s" % [state.pablo.mood_name(), state.pablo.position])

	_check(world.restored_fraction() > 0.0, "%s: nothing ever came alive" % id)
	_check(state.phase != GameState.Phase.RESTORE,
		"%s: never cleared phase 1 in %d ticks" % [id, MAX_TICKS])
	_check(state.wildlife.count() > 0, "%s: no species ever settled" % id)
	_check(state.phase == GameState.Phase.RECLAIM,
		"%s: never reached the reclaim phase in %d ticks" % [id, MAX_TICKS])

	if state.phase == GameState.Phase.RECLAIM:
		_verify_reclaim(world, state)


## A crude autoplayer. It only extends the power grid when it has actually run
## out of powered ground, then spends on whatever it can reach.
func _take_turn(world: World, state: GameState) -> void:
	var order := ["purifier", "irrigator", "pump", "marsh_seeder",
		"arboretum", "apiary", "solar_lens", "condenser", "rain_caller"]

	# Rotate the starting point. Without this the bot places the cheapest
	# building forever and never gets round to pumps, so no fresh water is
	# ever created and half the bestiary is unreachable.
	_turn += 1
	var offset := _turn % order.size()
	order = order.slice(offset) + order.slice(0, offset)

	var climate := _climate(world)

	for id in order:
		var def: BuildingDef = Catalog.get_def(id)
		if def == null or not state.can_afford(def):
			continue
		if def.tier > state._max_unlocked_tier():
			continue
		if not _wants(def, climate):
			continue
		var spot = _find_spot(world, state, def)
		if spot != null:
			state.try_place(def, spot)
			return

	# Nothing could be placed — either we are broke, or there is no powered
	# ground left. Only the second case is worth another turbine.
	var turbine: BuildingDef = Catalog.get_def("turbine")
	if not state.can_afford(turbine):
		return
	var site = _find_unpowered_site(world)
	if site != null:
		state.try_place(turbine, site)


## The two dials a player watches, averaged over land only. Ocean sits at full
## moisture forever and would drown the reading.
func _climate(world: World) -> Dictionary:
	var moisture := 0.0
	var temperature := 0.0
	var n := 0
	for t in world.all_tiles():
		if TileTypes.is_water(t.terrain):
			continue
		moisture += t.moisture
		temperature += t.temperature
		n += 1
	if n == 0:
		return {"moisture": 0.0, "temperature": 0.0}
	return {"moisture": moisture / float(n), "temperature": temperature / float(n)}


## Would a player actually buy this right now?
##
## Watering a swamp or heating a map that is already hot is how a region locks
## itself out of shrub and forest — both want moisture held *below* a ceiling —
## and the bot used to do exactly that, then report the level as unwinnable.
## Pumps are deliberately not gated: they create water *terrain*, which is a
## separate resource that several species need and that no amount of rain
## substitutes for.
func _wants(def: BuildingDef, climate: Dictionary) -> bool:
	match def.effect:
		BuildingDef.Effect.IRRIGATE:
			return climate.moisture < WET_ENOUGH
		BuildingDef.Effect.WARM:
			return climate.temperature < WARM_ENOUGH
		BuildingDef.Effect.COOL:
			return climate.temperature > COOL_ENOUGH
	return true


## An empty buildable tile that no turbine currently reaches.
func _find_unpowered_site(world: World):
	for t in world.all_tiles():
		if not t.is_empty() or not TileTypes.is_buildable(t.terrain):
			continue
		if t.powered:
			continue
		# Prefer somewhere with dry land around it, not a lone spit of sand.
		var land := 0
		for n in world.neighbors_of(t.axial):
			if not TileTypes.is_water(n.terrain):
				land += 1
		if land >= 4:
			return t.axial
	return null


func _find_spot(world: World, state: GameState, def: BuildingDef):
	for t in world.all_tiles():
		if not t.is_empty() or not def.can_sit_on(t.terrain):
			continue
		if def.requires_water_adjacency:
			var touching := false
			for n in world.neighbors_of(t.axial):
				if TileTypes.is_water(n.terrain):
					touching = true
					break
			if not touching:
				continue
		# Powered buildings are useless outside a turbine's reach.
		if def.needs_power and not t.powered:
			continue
		return t.axial
	return null


func _verify_reclaim(world: World, state: GameState) -> void:
	print("\nphase RECLAIM")

	# Drop a silo next to everything, then haul it all away.
	var guard := 0
	while world.count_buildings() > 0 and guard < 400:
		guard += 1
		var silo: BuildingDef = Catalog.get_def("reclaim_silo")
		var spot = _find_spot(world, state, silo)
		if spot != null and state.can_afford(silo):
			state.try_place(silo, spot)
		if state.run_reclaim_step() == 0:
			# Nothing left in reach — clear the silos themselves.
			for b in world.buildings.values().duplicate():
				world.remove_building(b.axial)
		world.simulate()

	var id := world.level.id
	print("  buildings left  %d" % world.count_buildings())
	_check(world.count_buildings() == 0, "%s: could not clear every structure" % id)

	# The land must survive the machines leaving.
	var alive_after := world.restored_fraction()
	print("  still alive     %d%%" % int(alive_after * 100.0))
	_check(alive_after > 0.0, "%s: the world died once the machines were removed" % id)

	state.pablo.update(1.0)
	print("  pablo           %s" % state.pablo.mood_name())


func _building_summary(world: World) -> String:
	var counts := {}
	for b in world.buildings.values():
		counts[b.def.id] = counts.get(b.def.id, 0) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%s %d" % [id, counts[id]])
	return ", ".join(parts)


func _count_terrain(world: World, terrain: TileTypes.Terrain) -> int:
	var n := 0
	for t in world.all_tiles():
		if t.terrain == terrain:
			n += 1
	return n


func _average_temperature(world: World) -> float:
	var sum := 0.0
	var n := 0
	for t in world.all_tiles():
		if t.terrain == TileTypes.Terrain.OCEAN:
			continue
		sum += t.temperature
		n += 1
	return 0.0 if n == 0 else sum / float(n)


func _biome_summary(world: World) -> String:
	var counts := {}
	for t in world.all_tiles():
		if t.has_life():
			counts[t.biome] = counts.get(t.biome, 0) + 1
	var parts: Array[String] = []
	for b in counts:
		parts.append("%s %d" % [TileTypes.Biome.keys()[b], counts[b]])
	return ", ".join(parts)
