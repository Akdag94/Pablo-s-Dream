class_name TerrainHeight
extends RefCounted

## Where the top of a tile sits, in world units. The single answer to that
## question.
##
## There used to be three copies of a terrain-to-height table — in the world
## renderer, the build cursor and the foliage scatterer — each mapping the seven
## terrain types to seven fixed heights. That is what produced the "one tile
## high, the next one low" look: height came from what a cell *was* rather than
## from where it *stood*, so a rock beside a wasteland beside a riverbed became
## a staircase with no landscape under it.
##
## Now height comes from the tile's own quantised elevation, which the world
## generates as a couple of broad steps. Terrain type no longer affects it at
## all, except that water is flat.

## The sea surface, and the base every plateau is measured up from.
const SEA_Y := 0.0

## How tall one land step stands. The reference reads as a low shelf and a
## plateau roughly a third of a tile's width apart — enough to cast a wall,
## little enough that the island still reads as ground rather than as towers.
const STEP_HEIGHT := 0.34

## Riverbeds sit slightly under the shelf they cut through, so a dry channel is
## visibly a channel before any water reaches it.
const CHANNEL_DROP := 0.10


## Top surface of a tile.
static func of(tile: Tile) -> float:
	if tile == null:
		return SEA_Y
	if TileTypes.is_water(tile.terrain):
		return SEA_Y
	var y := SEA_Y + tile.elevation * STEP_HEIGHT
	if tile.terrain == TileTypes.Terrain.RIVERBED:
		y -= CHANNEL_DROP
	return y


## Thickness of the block drawn under a tile. Land is drawn as a box whose sides
## become the plateau wall, so it has to reach below the lowest neighbour or the
## wall shows daylight underneath.
static func thickness(tile: Tile) -> float:
	return maxf(0.08, of(tile) - (SEA_Y - STEP_HEIGHT))
