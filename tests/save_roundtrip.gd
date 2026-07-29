extends SceneTree

## Verifies that saving a run and loading it back gives an identical world.
##
##   godot --headless --script res://tests/save_roundtrip.gd

var failures: Array[String] = []


func _init() -> void:
	print("— save/load roundtrip —\n")

	var state := _build_played_state()
	print("before  %d hexes, %d buildings, %d leaves, phase %s" % [
		state.world.all_tiles().size(),
		state.world.count_buildings(),
		state.leaves,
		GameState.Phase.keys()[state.phase],
	])

	_check(SaveGame.save(state), "save returned false")

	var loaded = SaveGame.load_run()
	_check(loaded != null, "load returned null")

	if loaded != null:
		_compare(state, loaded)
		print("after   %d hexes, %d buildings, %d leaves, phase %s" % [
			loaded.world.all_tiles().size(),
			loaded.world.count_buildings(),
			loaded.leaves,
			GameState.Phase.keys()[loaded.phase],
		])

	SaveGame.delete()

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


## Play far enough that there is real state worth persisting.
func _build_played_state() -> GameState:
	var world := World.new(10, 777)
	var state := GameState.new(world)

	var placed := 0
	for t in world.all_tiles():
		if placed >= 12:
			break
		var def: BuildingDef = Catalog.get_def("turbine" if placed % 4 == 0 else "purifier")
		if state.try_place(def, t.axial):
			placed += 1

	for i in 60:
		world.simulate()

	state.pablo.update(0.5)
	return state


func _compare(before: GameState, after: GameState) -> void:
	_check(before.leaves == after.leaves,
		"leaves differ: %d vs %d" % [before.leaves, after.leaves])
	_check(before.phase == after.phase,
		"phase differs: %s vs %s" % [before.phase, after.phase])
	_check(before.world.count_buildings() == after.world.count_buildings(),
		"building count differs: %d vs %d" % [
			before.world.count_buildings(), after.world.count_buildings()])
	_check(before.wildlife.settled.size() == after.wildlife.settled.size(),
		"settled species differ")

	var mismatched := 0
	for t in before.world.all_tiles():
		var other := after.world.get_tile(t.axial)
		if other == null:
			mismatched += 1
			continue
		if t.terrain != other.terrain or t.biome != other.biome:
			mismatched += 1
		elif absf(t.fertility - other.fertility) > 0.002:
			mismatched += 1
		elif absf(t.moisture - other.moisture) > 0.002:
			mismatched += 1
	_check(mismatched == 0, "%d tiles did not survive the roundtrip" % mismatched)

	# Loading must not re-pay for growth that was already banked.
	var leaves_before := after.leaves
	after.world.simulate()
	var gained := after.leaves - leaves_before
	_check(gained < 50, "loading re-paid %d leaves of existing growth" % gained)
