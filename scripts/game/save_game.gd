class_name SaveGame
extends RefCounted

## Serialises a run to JSON under user:// and reads it back.
##
## Tile terrain and biome are derived state most of the time, but not always —
## excavators and kilns permanently reshape the ground — so the full grid is
## written rather than replayed from a seed.

const SAVE_PATH := "user://save.json"
const FORMAT_VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func save(state: GameState) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open %s for writing" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(_serialise(state), "\t"))
	file.close()
	return true


## Returns a fully restored GameState, or null if there is nothing valid to load.
static func load_run():
	if not exists():
		return null

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file is not valid JSON")
		return null
	if parsed.get("version", 0) != FORMAT_VERSION:
		push_warning("Save file version mismatch — ignoring it")
		return null

	return _deserialise(parsed)


# ------------------------------------------------------------------ writing

static func _serialise(state: GameState) -> Dictionary:
	var world := state.world

	var tiles := []
	for t in world.all_tiles():
		tiles.append({
			"q": t.axial.x,
			"r": t.axial.y,
			"t": int(t.terrain),
			"b": int(t.biome),
			"f": snappedf(t.fertility, 0.001),
			"m": snappedf(t.moisture, 0.001),
			"c": snappedf(t.temperature, 0.01),
		})

	var buildings := []
	for b in world.buildings.values():
		buildings.append({"id": b.def.id, "q": b.axial.x, "r": b.axial.y})

	var settled := {}
	for id in state.wildlife.settled:
		var a: Vector2i = state.wildlife.settled[id]
		settled[id] = [a.x, a.y]

	return {
		"version": FORMAT_VERSION,
		"radius": world.radius,
		"leaves": state.leaves,
		"phase": int(state.phase),
		"tiles": tiles,
		"buildings": buildings,
		"wildlife": settled,
		"pablo": {
			"q": state.pablo.position.x,
			"r": state.pablo.position.y,
			"mood": int(state.pablo.mood),
		},
	}


# ------------------------------------------------------------------ reading

static func _deserialise(data: Dictionary):
	var radius := int(data.get("radius", 14))
	var world := World.new(radius)
	var state := GameState.new(world)

	for entry in data.get("tiles", []):
		var axial := Vector2i(int(entry["q"]), int(entry["r"]))
		var t := world.get_tile(axial)
		if t == null:
			continue
		t.terrain = int(entry["t"]) as TileTypes.Terrain
		t.biome = int(entry["b"]) as TileTypes.Biome
		t.fertility = float(entry["f"])
		t.moisture = float(entry["m"])
		t.temperature = float(entry["c"])

	for entry in data.get("buildings", []):
		var def := Catalog.get_def(String(entry["id"]))
		if def == null:
			continue
		var axial := Vector2i(int(entry["q"]), int(entry["r"]))
		# Bypass GameState.try_place: cost was already paid when it was built,
		# and one-shot terraforming must not fire a second time on load.
		var b := Building.new(def, axial)
		var tile := world.get_tile(axial)
		if tile == null:
			continue
		world.buildings[axial] = b
		tile.building_id = def.id

	var wildlife: Dictionary = data.get("wildlife", {})
	for id in wildlife:
		var pair: Array = wildlife[id]
		state.wildlife.settled[id] = Vector2i(int(pair[0]), int(pair[1]))

	state.leaves = int(data.get("leaves", GameState.STARTING_LEAVES))
	state.phase = int(data.get("phase", 0)) as GameState.Phase

	var pablo_data: Dictionary = data.get("pablo", {})
	if not pablo_data.is_empty():
		state.pablo.teleport_to(
			Vector2(float(pablo_data.get("q", 0.0)), float(pablo_data.get("r", 0.0))),
			int(pablo_data.get("mood", 0)) as Pablo.Mood
		)

	# Growth already paid out before saving must not pay out again on load.
	state.reset_growth_ledger()

	return state
