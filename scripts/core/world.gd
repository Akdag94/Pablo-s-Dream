class_name World
extends RefCounted

## The hex grid plus the environmental simulation that runs over it.
##
## The simulation is deliberately deterministic and cheap: every tick we
## recompute power, let moisture diffuse, then let biomes settle. Nothing
## here depends on frame rate, so a tick can be stepped manually in tests.

signal tile_changed(axial: Vector2i)
signal simulated

const MOISTURE_DIFFUSION := 0.22
## Dry ground pulls water back out of the soil. High enough that irrigation
## has to be maintained rather than applied once and forgotten.
const MOISTURE_DECAY := 0.06
## How much clean runoff living land feeds into the sea beside it.
const COASTAL_RUNOFF := 0.03

var radius: int
var tiles: Dictionary = {}          ## Vector2i -> Tile
var buildings: Dictionary = {}      ## Vector2i -> Building

## Same tiles as above, as a typed list. Built once — cells are never added or
## removed after generation — so iteration stays allocation-free and typed.
var _tile_list: Array[Tile] = []

var _rng := RandomNumberGenerator.new()


func _init(p_radius: int = 14, seed_value: int = 0) -> void:
	radius = p_radius
	_rng.seed = seed_value if seed_value != 0 else randi()
	_build_grid()
	_generate_terrain()


# ---------------------------------------------------------------- grid access

func has(axial: Vector2i) -> bool:
	return tiles.has(axial)


func get_tile(axial: Vector2i) -> Tile:
	return tiles.get(axial)


func all_tiles() -> Array[Tile]:
	return _tile_list


func neighbors_of(axial: Vector2i) -> Array[Tile]:
	var out: Array[Tile] = []
	for n in Grid.neighbors(axial):
		var t: Tile = tiles.get(n)
		if t != null:
			out.append(t)
	return out


func tiles_in_radius(center: Vector2i, r: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for a in Grid.in_radius(center, r):
		var t: Tile = tiles.get(a)
		if t != null:
			out.append(t)
	return out


func count_biome(biome: TileTypes.Biome) -> int:
	var n := 0
	for t in tiles.values():
		if t.biome == biome:
			n += 1
	return n


func count_biome_near(center: Vector2i, r: int, biome: TileTypes.Biome) -> int:
	var n := 0
	for t in tiles_in_radius(center, r):
		if t.biome == biome:
			n += 1
	return n


## Total leaves currently standing on the map.
func total_score() -> int:
	var n := 0
	for t in tiles.values():
		n += t.score()
	return n


## Fraction of non-ocean land that has been brought back to life, 0..1.
func restored_fraction() -> float:
	var land := 0
	var alive := 0
	for t in all_tiles():
		if t.terrain == TileTypes.Terrain.OCEAN or t.terrain == TileTypes.Terrain.CLIFF:
			continue
		# Sand turns to beach on its own next to water, so counting it would
		# hand the player progress they did not earn.
		if t.terrain == TileTypes.Terrain.SAND:
			continue
		land += 1
		if t.has_life():
			alive += 1
	return 0.0 if land == 0 else float(alive) / float(land)


# ------------------------------------------------------------- world creation

func _build_grid() -> void:
	for a in Grid.in_radius(Vector2i.ZERO, radius):
		var t := Tile.new(a)
		tiles[a] = t
		_tile_list.append(t)


func _generate_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.09
	noise.fractal_octaves = 3

	var detail := FastNoiseLite.new()
	detail.seed = _rng.randi()
	detail.frequency = 0.2

	for a in tiles:
		var t: Tile = tiles[a]
		var dist := float(Grid.distance(a, Vector2i.ZERO)) / float(radius)
		var h := noise.get_noise_2d(a.x * 10.0, a.y * 10.0)

		# Push the rim of the map down into ocean so every island reads as one.
		# The exponent keeps the falloff concentrated at the very edge — a
		# gentler curve drowned most of the buildable land.
		var elevation := h - pow(dist, 3.0) * 0.9

		if elevation < -0.45:
			t.terrain = TileTypes.Terrain.OCEAN
		elif elevation < -0.30:
			t.terrain = TileTypes.Terrain.SAND
		elif elevation > 0.42:
			t.terrain = TileTypes.Terrain.CLIFF
		elif elevation > 0.24:
			t.terrain = TileTypes.Terrain.ROCK
		else:
			t.terrain = TileTypes.Terrain.WASTELAND

		# Dry channels wandering through the interior, ready to be re-watered.
		var d := detail.get_noise_2d(a.x * 10.0, a.y * 10.0)
		if t.terrain == TileTypes.Terrain.WASTELAND and absf(d) < 0.05:
			t.terrain = TileTypes.Terrain.RIVERBED

		t.fertility = 0.0
		t.moisture = 1.0 if TileTypes.is_water(t.terrain) else 0.0
		t.temperature = 14.0


# ------------------------------------------------------------------ mutations

func set_terrain(axial: Vector2i, terrain: TileTypes.Terrain) -> void:
	var t: Tile = tiles.get(axial)
	if t == null or t.terrain == terrain:
		return
	t.terrain = terrain
	if TileTypes.is_water(terrain):
		t.moisture = 1.0
		t.biome = TileTypes.Biome.NONE
	tile_changed.emit(axial)


func set_biome(axial: Vector2i, biome: TileTypes.Biome) -> void:
	var t: Tile = tiles.get(axial)
	if t == null or t.biome == biome:
		return
	t.biome = biome
	tile_changed.emit(axial)


func add_fertility(axial: Vector2i, amount: float) -> void:
	var t: Tile = tiles.get(axial)
	if t == null:
		return
	t.fertility = clampf(t.fertility + amount, 0.0, 1.0)


func add_moisture(axial: Vector2i, amount: float) -> void:
	var t: Tile = tiles.get(axial)
	if t == null:
		return
	t.moisture = clampf(t.moisture + amount, 0.0, 1.0)


func shift_temperature(axial: Vector2i, delta: float) -> void:
	var t: Tile = tiles.get(axial)
	if t == null:
		return
	t.temperature = clampf(t.temperature + delta, -30.0, 45.0)


# ----------------------------------------------------------------- simulation

## Advance the world one step. Call this on a fixed timer, not per frame.
func simulate() -> void:
	_recompute_power()
	_run_building_effects()
	_diffuse_moisture()
	_coastal_runoff()
	_settle_biomes()
	simulated.emit()


## Healthy land feeds the sea beside it, which is what lets reefs return.
## Nothing the player builds touches the ocean directly — they have to fix the
## coast and let it drain.
func _coastal_runoff() -> void:
	for t in all_tiles():
		if t.terrain != TileTypes.Terrain.OCEAN:
			continue
		var living_neighbours := 0
		for n in neighbors_of(t.axial):
			if n.has_life() and not TileTypes.is_water(n.terrain):
				living_neighbours += 1
		if living_neighbours > 0:
			t.fertility = clampf(
				t.fertility + COASTAL_RUNOFF * living_neighbours, 0.0, 1.0)
		else:
			t.fertility = maxf(0.0, t.fertility - COASTAL_RUNOFF)


func _recompute_power() -> void:
	for t in tiles.values():
		t.powered = false
	for b in buildings.values():
		if not b.def.provides_power:
			continue
		for t in tiles_in_radius(b.axial, b.def.power_radius):
			t.powered = true


func _run_building_effects() -> void:
	for b in buildings.values():
		if b.def.needs_power and not tiles[b.axial].powered:
			b.active = false
			continue
		b.active = true
		b.apply(self)


func _diffuse_moisture() -> void:
	# Snapshot first so diffusion does not depend on iteration order.
	var next := {}
	for a in tiles:
		var t: Tile = tiles[a]
		if TileTypes.is_water(t.terrain):
			next[a] = 1.0
			continue
		var wettest := t.moisture
		for n in neighbors_of(a):
			wettest = maxf(wettest, n.moisture)
		var target := wettest * MOISTURE_DIFFUSION + t.moisture * (1.0 - MOISTURE_DIFFUSION)
		next[a] = clampf(target - MOISTURE_DECAY, 0.0, 1.0)

	for a in next:
		tiles[a].moisture = next[a]


## Promote or demote each tile's living layer based on its local conditions.
func _settle_biomes() -> void:
	for a in tiles:
		var t: Tile = tiles[a]
		var want := _desired_biome(t)
		if want != t.biome:
			t.biome = want
			tile_changed.emit(a)


## Which living layer the current conditions support.
##
## Each biome occupies a *band*, not a threshold. Over-watering forest pushes
## it back to wetland rather than upgrading it, so the player has to hold
## conditions steady instead of running every value to maximum. That tension
## is the game — without it the optimal play is to spam every building.
func _desired_biome(t: Tile) -> TileTypes.Biome:
	if TileTypes.is_water(t.terrain):
		# Reefs come back in warm shallows fed by clean runoff from the land.
		if t.terrain == TileTypes.Terrain.OCEAN and t.fertility >= 0.45 \
				and t.temperature >= 18.0:
			return TileTypes.Biome.REEF
		return TileTypes.Biome.NONE

	if t.terrain == TileTypes.Terrain.CLIFF:
		return TileTypes.Biome.NONE

	# Sand beside water becomes beach regardless of fertility.
	if t.terrain == TileTypes.Terrain.SAND:
		for n in neighbors_of(t.axial):
			if TileTypes.is_water(n.terrain):
				return TileTypes.Biome.BEACH
		return TileTypes.Biome.NONE

	if t.fertility < 0.25:
		return TileTypes.Biome.NONE

	# Wetland is a *place*, not just a moisture level — it has to border open
	# water. Otherwise irrigators alone would turn the whole island to marsh.
	var touches_fresh := false
	var touches_salt := false
	for n in neighbors_of(t.axial):
		if n.terrain == TileTypes.Terrain.OCEAN:
			touches_salt = true
		elif n.terrain == TileTypes.Terrain.WATER:
			touches_fresh = true

	if t.moisture >= 0.70 and (touches_fresh or touches_salt):
		# Fresh water wins where both meet. On an island almost everything
		# touches the sea somewhere, and without this every marsh on the map
		# turned to mangrove.
		if touches_salt and not touches_fresh:
			return TileTypes.Biome.MANGROVE
		return TileTypes.Biome.WETLAND

	# Forest wants rich soil and *moderate* water. Too wet and it drowns back
	# to open ground; that upper bound is what makes over-irrigating a mistake.
	if t.fertility >= 0.70 and t.moisture >= 0.30 and t.moisture < 0.70:
		return TileTypes.Biome.FOREST

	# Warm and dry favours hardy scrub over lawn.
	if t.moisture < 0.25 and t.temperature >= 19.0:
		return TileTypes.Biome.SHRUB

	return TileTypes.Biome.GRASS


# ------------------------------------------------------------------ buildings

func place_building(b) -> bool:
	var t: Tile = tiles.get(b.axial)
	if t == null or not t.can_build():
		return false
	buildings[b.axial] = b
	t.building_id = b.def.id
	b.on_placed(self)
	tile_changed.emit(b.axial)
	return true


func remove_building(axial: Vector2i) -> bool:
	var b = buildings.get(axial)
	if b == null:
		return false
	b.on_removed(self)
	buildings.erase(axial)
	tiles[axial].building_id = ""
	tile_changed.emit(axial)
	return true


func building_at(axial: Vector2i):
	return buildings.get(axial)


func count_buildings() -> int:
	return buildings.size()
