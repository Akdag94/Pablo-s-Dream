extends SceneTree

## Headless smoke test: build a world, play it roughly the way a player would,
## and assert the whole phase chain can actually be reached.
##
##   godot --headless --script res://tests/headless_run.gd

const MAX_TICKS := 4000

var failures: Array[String] = []


func _init() -> void:
	print("— Pablo's Dream · headless run —\n")

	var world := World.new(14, 12345)
	var state := GameState.new(world)

	_report_generation(world)

	_play(world, state)

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


func _report_generation(world: World) -> void:
	var counts := {}
	for t in world.all_tiles():
		counts[t.terrain] = counts.get(t.terrain, 0) + 1

	print("world: %d hexes" % world.all_tiles().size())
	for terrain in counts:
		print("  %-10s %d" % [TileTypes.Terrain.keys()[terrain], counts[terrain]])

	_check(world.all_tiles().size() > 400, "grid looks too small")
	_check(counts.get(TileTypes.Terrain.OCEAN, 0) > 0, "no ocean generated")
	_check(counts.get(TileTypes.Terrain.WASTELAND, 0) > 0, "no buildable land generated")
	_check(world.restored_fraction() == 0.0, "world did not start dead")


## Greedily place whatever is affordable and legal, then let the sim run.
func _play(world: World, state: GameState) -> void:
	var tick := 0
	var last_phase := state.phase
	print("\nphase RESTORE")

	while tick < MAX_TICKS and state.phase != GameState.Phase.RECLAIM:
		_take_turn(world, state)
		world.simulate()
		tick += 1

		if state.phase != last_phase:
			last_phase = state.phase
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
	print("  wildlife   %s" % str(state.wildlife.settled.keys()))
	print("  pablo      %s at %s" % [state.pablo.mood_name(), state.pablo.position])

	_check(world.restored_fraction() > 0.0, "nothing ever came alive")
	_check(state.phase != GameState.Phase.RESTORE,
		"never cleared phase 1 in %d ticks" % MAX_TICKS)
	_check(state.wildlife.count() > 0, "no species ever settled")
	_check(state.phase == GameState.Phase.RECLAIM,
		"never reached the reclaim phase in %d ticks" % MAX_TICKS)

	if state.phase == GameState.Phase.RECLAIM:
		_verify_reclaim(world, state)


## A crude autoplayer. It only extends the power grid when it has actually run
## out of powered ground, then spends on whatever it can reach.
func _take_turn(world: World, state: GameState) -> void:
	var order := ["purifier", "irrigator", "pump", "marsh_seeder",
		"arboretum", "apiary", "solar_lens", "rain_caller"]

	for id in order:
		var def: BuildingDef = Catalog.get_def(id)
		if def == null or not state.can_afford(def):
			continue
		if def.tier > state._max_unlocked_tier():
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


## An empty buildable hex that no turbine currently reaches.
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

	print("  buildings left  %d" % world.count_buildings())
	_check(world.count_buildings() == 0, "could not clear every structure")

	# The land must survive the machines leaving.
	var alive_after := world.restored_fraction()
	print("  still alive     %d%%" % int(alive_after * 100.0))
	_check(alive_after > 0.0, "the world died once the machines were removed")

	state.pablo.update(1.0)
	print("  pablo           %s" % state.pablo.mood_name())


func _biome_summary(world: World) -> String:
	var counts := {}
	for t in world.all_tiles():
		if t.has_life():
			counts[t.biome] = counts.get(t.biome, 0) + 1
	var parts: Array[String] = []
	for b in counts:
		parts.append("%s %d" % [TileTypes.Biome.keys()[b], counts[b]])
	return ", ".join(parts)
