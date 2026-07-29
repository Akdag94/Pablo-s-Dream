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

## The region this world was generated from. Read for the map's shape and
## climate here, and for the objectives over in GameState.
var level: LevelDef

var radius: int
var tiles: Dictionary = {}          ## Vector2i -> Tile
var buildings: Dictionary = {}      ## Vector2i -> Building

## Same tiles as above, as a typed list. Built once — cells are never added or
## removed after generation — so iteration stays allocation-free and typed.
var _tile_list: Array[Tile] = []

var _rng := RandomNumberGenerator.new()


func _init(p_level: LevelDef = null) -> void:
	level = p_level if p_level != null else Levels.first()
	radius = level.radius
	_rng.seed = level.seed_value if level.seed_value != 0 else randi()
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


## Noise is sampled at tile coordinates, one step per tile.
##
## This used to sample at `a.x * 10.0`, which with a frequency of 0.09 put
## neighbouring tiles nearly a whole feature-width apart in noise space — so
## each cell drew an essentially unrelated height and the island came out as
## salt-and-pepper rather than as terrain. Mean height difference between
## touching tiles was 0.324 out of a ~1.4 range; sampled properly it is 0.122.
## Every "one tile high, the next one low" complaint traced back to that line.
const LAND_FREQUENCY := 0.055
## Rivers follow the zero crossing of a second, even smoother field, which
## gives one connected winding channel instead of scattered dots.
const RIVER_FREQUENCY := 0.045

## Ground above this stands as bare rock, and above the second as cliff. Read
## against elevation *after* the island falloff, so they mean "high ground here"
## rather than an absolute.
const ROCK_LINE := 0.30
const CLIFF_LINE := 0.52


func _generate_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = LAND_FREQUENCY
	noise.fractal_octaves = 4
	# Each octave contributes less than the default 0.5, so the big shapes stay
	# readable instead of being chewed up by fine detail.
	noise.fractal_gain = 0.38

	var rivers := FastNoiseLite.new()
	rivers.seed = _rng.randi()
	rivers.frequency = RIVER_FREQUENCY
	rivers.fractal_octaves = 2

	# Highest ground on the map, so elevation can be normalised to 0..1 above
	# the waterline for the renderer.
	var peak := level.sea_level

	for a in tiles:
		var t: Tile = tiles[a]
		var dist := float(Grid.distance(a, Vector2i.ZERO)) / float(radius)
		var h := noise.get_noise_2d(a.x, a.y)

		# Push the rim of the map down into ocean so every island reads as one.
		# The exponent keeps the falloff concentrated at the very edge — a
		# gentler curve drowned most of the buildable land.
		var height := h - pow(dist, 3.0) * 0.9 + level.elevation_bias

		# The shore band keeps its width relative to sea level, so raising the
		# water does not swallow the beach along with the shallows.
		var shore := level.sea_level + 0.15

		if height < level.sea_level:
			t.terrain = TileTypes.Terrain.OCEAN
		elif height < shore:
			t.terrain = TileTypes.Terrain.SAND
		elif height > CLIFF_LINE:
			t.terrain = TileTypes.Terrain.CLIFF
		elif height > ROCK_LINE:
			t.terrain = TileTypes.Terrain.ROCK
		else:
			t.terrain = TileTypes.Terrain.WASTELAND

		# Dry channels wandering through the interior, ready to be re-watered.
		# A river is the *valley* of the river field, and it only cuts through
		# ground low enough to hold water — so channels run down toward the sea
		# instead of striping across the peaks.
		var r := rivers.get_noise_2d(a.x, a.y)
		var carvable := t.terrain == TileTypes.Terrain.WASTELAND \
			or t.terrain == TileTypes.Terrain.ROCK
		if carvable and absf(r) < level.river_density and height < ROCK_LINE:
			t.terrain = TileTypes.Terrain.RIVERBED
			# Cut the bed below the ground it runs through, or the channel reads
			# as a stripe of paint rather than as something water would follow.
			height -= 0.06

		t.elevation = height
		peak = maxf(peak, height)

		t.fertility = 0.0
		t.moisture = 1.0 if TileTypes.is_water(t.terrain) else 0.0
		t.temperature = level.base_temperature

	_normalise_elevation(peak)


## How many land steps the map is allowed. Two is what the reference uses: a
## low shelf and a plateau above it, each large and flat, joined by a wall.
## More than three and the island turns back into a staircase.
const LAND_STEPS := 2


## Rescale raw noise heights into 0..1 above the waterline, then quantise them
## into a couple of broad steps.
##
## The quantising is the point. A continuous heightfield gives rolling hills,
## which is not what this looks like — big flat plateaus meeting at a hard edge
## is. Because the noise is now spatially coherent, neighbouring tiles land on
## the same step almost always, so a wall appears only at a real boundary
## instead of between every pair of cells.
func _normalise_elevation(peak: float) -> void:
	var span := maxf(peak - level.sea_level, 0.001)
	for t in _tile_list:
		if TileTypes.is_water(t.terrain):
			# One flat sea. Ocean read as a field of separate boxes before this.
			t.elevation = 0.0
			continue
		var normalised := clampf((t.elevation - level.sea_level) / span, 0.0, 1.0)
		t.elevation = _step(normalised)


## Snap to the nearest of LAND_STEPS + 1 levels, 0.0 .. 1.0 inclusive.
func _step(value: float) -> float:
	return roundf(value * float(LAND_STEPS)) / float(LAND_STEPS)


## Terraforming has to move the ground with it, or an excavated channel sits at
## plateau height and a kiln's new rock stays flat.
func _elevation_after_terraforming(t: Tile, terrain: TileTypes.Terrain) -> float:
	var step := 1.0 / float(LAND_STEPS)
	match terrain:
		TileTypes.Terrain.WATER, TileTypes.Terrain.OCEAN:
			return 0.0
		TileTypes.Terrain.RIVERBED, TileTypes.Terrain.SAND:
			return maxf(0.0, t.elevation - step)
		TileTypes.Terrain.ROCK, TileTypes.Terrain.CLIFF:
			return minf(1.0, t.elevation + step)
	return t.elevation


# ------------------------------------------------------------------ mutations

func set_terrain(axial: Vector2i, terrain: TileTypes.Terrain) -> void:
	var t: Tile = tiles.get(axial)
	if t == null or t.terrain == terrain:
		return
	t.terrain = terrain
	t.elevation = _elevation_after_terraforming(t, terrain)
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


## Fertility at which bare ground first takes life, and at which green ground is
## established enough to specialise. The gap between them is the two-step: the
## player greens the land, then decides what it becomes.
const GREENERY_FERTILITY := 0.25
const SPECIALISE_FERTILITY := 0.42

## Below this, ground is too cold for meadow or scrub and answers with tundra
## and lichen instead.
const COLD_LINE := 8.0


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

	if t.fertility < GREENERY_FERTILITY:
		return TileTypes.Biome.NONE

	# The tier gate. Ground has to be green, and richer than the bare minimum,
	# before it can become anything in particular. A tile crossing the greenery
	# line this tick spends at least one tick as plain greenery.
	if not TileTypes.is_green(t.biome) or t.fertility < SPECIALISE_FERTILITY:
		return TileTypes.Biome.GREENERY

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
		# A marsh left to mature on rich fresh soil closes over into reeds.
		if touches_fresh and t.fertility >= 0.80:
			return TileTypes.Biome.REED_BED
		return TileTypes.Biome.WETLAND

	# Forest wants rich soil and *moderate* water. Too wet and it drowns back
	# to open ground; that upper bound is what makes over-irrigating a mistake.
	if t.fertility >= 0.70 and t.moisture >= 0.30 and t.moisture < 0.70:
		return TileTypes.Biome.FOREST

	# Cold ground cannot hold meadow or scrub at all. This is what gives a polar
	# region its own tier-two set instead of leaving it with two reachable
	# biomes and an impossible objective: stone answers with lichen, soil with
	# tundra, and both are only available while the map stays cold.
	if t.temperature < COLD_LINE:
		if t.terrain == TileTypes.Terrain.ROCK:
			return TileTypes.Biome.LICHEN
		return TileTypes.Biome.TUNDRA

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
