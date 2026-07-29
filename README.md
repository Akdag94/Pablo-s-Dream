# Pablo's Dream

An ecosystem restoration game. You arrive on dead ground, rebuild a living
landscape with machines, and then take every machine back with you when you
leave. The win condition is an empty map that is fully alive.

Built with **Godot 4.4**, targeting desktop and mobile.

---

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build —
   GDScript only, no C# needed).
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5**.

There are two scenes:

| Scene | What it is |
|---|---|
| `scenes/Main3D.tscn` | the real game — 3D, touch controls, shaders |
| `scenes/Main.tscn` | flat-colour 2D prototype, kept for reading the simulation while tuning |

**Controls (both mouse and touch):**

| Action | Mouse | Touch |
|---|---|---|
| Select a hex | left click | tap |
| Place | press **Yerleştir** | press **Yerleştir** |
| Sell a building | — | long press |
| Pan | drag / middle drag | one-finger drag |
| Orbit | right drag | two-finger drag |
| Zoom | wheel | pinch |

Placement is deliberately two-step: tapping only moves the cursor, and a
separate button commits. On a phone the finger covers the tile it is touching,
so immediate placement costs the player buildings they did not mean to buy.

## Tests

```bash
godot --headless --script res://tests/headless_run.gd     # full phase chain
godot --headless --script res://tests/save_roundtrip.gd   # save/load fidelity
```

The first one plays a whole run with a crude bot and asserts every phase is
reachable, the machines can all be reclaimed, and the land survives their
removal. It has caught six real balance bugs so far — it is the reason the
biome bands are tuned the way they are.

## Building for iOS and Android

`codemagic.yaml` drives CI. iOS builds need macOS and Xcode, which Windows
cannot do, so the pipeline runs on a Codemagic mac runner.

**One manual step is required first**, because export presets carry signing
identities and cannot be safely generated blind: open the project in Godot →
**Project → Export**, add an **iOS** preset and an **Android** preset, and fill
in the bundle identifier and team id. The preset *names* must be exactly `iOS`
and `Android` — `codemagic.yaml` refers to them by name.

Then in Codemagic: connect the repo, add the App Store Connect integration,
and create an environment group `godot` holding `GODOT_VERSION=4.7.1`.

---

## How the game works

### The loop

Everything on the map is a hex with four environmental values — **terrain**,
**fertility**, **moisture**, and **temperature**. You never paint biomes
directly. You place machines that push those values around, and the biome layer
settles into whatever those conditions support. Grass appears where soil is
clean and slightly damp; push moisture higher and the same tile becomes
wetland; push fertility higher instead and it becomes forest.

That indirection is the whole game: you are gardening the *inputs*.

### The three phases

| Phase | Goal | What unlocks |
|---|---|---|
| **1 — Restore** | Get 28% of the land alive | Turbine, Purifier, Pump, Irrigator, Excavator, Kiln |
| **2 — Cultivate** | Establish 3 distinct biomes of 12+ tiles each | Marsh Seeder, Arboretum, Apiary, Solar Lens, Condenser, Rain Caller |
| **3 — Wildlife** | 4 species settle on their own | (no new tools — you keep shaping) |
| **4 — Reclaim** | Remove every structure, then launch | Reclaim Silo, Airship |

Phase 4 is the twist and the reason the economy works the way it does: the
machines that got you here are litter, and the map is only finished when they
are gone.

### Wildlife

You never place an animal. Each species has habitat requirements — so many
wetland hexes, so much standing water, a temperature band, sometimes solitude
from machinery, sometimes another species already present. Every few ticks the
world is surveyed, and anything that can live somewhere moves in. Destroy the
habitat and it leaves again.

This keeps the player's job consistent all the way through: you are always
shaping conditions, never placing outcomes. The HUD lists the three species
closest to arriving, with a percentage, so there is always a next thing to aim
at.

### Pablo

Pablo lives on the island from the first moment, before anything grows. He
wanders further and rests less as the world comes back — waiting, then
curious, then happy, then finally *home* once the land is alive and every
machine is gone.

`scripts/game/pablo.gd` holds only his position, heading, and mood in hex
space. It exposes both `pixel_position()` for the 2D prototype and
`world_position_3d()` / `heading()` for the 3D view, so dropping in a real
model changes nothing about how he behaves.

He is the reason the game ends the way it does. You build the place, you take
every trace of yourself away, and he stays.

### Economy

Living tiles pay **leaves**, once each, when they first come alive. Leaves buy
buildings. So growth funds growth, and a badly placed purifier is a real loss.
Selling refunds 70%; the reclaim silo refunds 50% on the way out.

---

## Project layout

```
scripts/
  core/
    hex.gd          axial hex math (pointy-top)
    tile_types.gd   terrain + biome enums, values, colours
    tile.gd         one cell's state
    world.gd        the grid, procedural generation, the simulation tick
  buildings/
    building_def.gd  static description of a building type
    building.gd      a placed instance + its per-tick effect
    catalog.gd       >>> ALL TUNING LIVES HERE <<<
  game/
    game_state.gd   phases, leaves, objectives, launch condition
    pablo.gd        his position, heading and mood — render-agnostic
  wildlife/
    species_def.gd  what one species needs
    bestiary.gd     >>> ALL SPECIES TUNING LIVES HERE <<<
    wildlife_system.gd  surveys the world, settles and un-settles species
  render/
    world_view.gd   flat-colour hex renderer + pointer input
  ui/
    hud.gd          top bar, build bar, wildlife panel
scenes/
  Main.tscn
```

The `core` and `buildings` layers know nothing about rendering. You can step
`world.simulate()` in a headless test and assert on tile states.

**To rebalance the game, you only need to touch `catalog.gd`** — every cost,
radius, and strength is there.

---

## Current state

Working: hex grid, procedural island generation, moisture diffusion, fertility,
temperature, the full biome settling rule set, all 14 buildings, power
coverage, the leaf economy, all three phases, and the launch condition.

Rendering is flat colour on purpose — the simulation needs to be legible while
it is being tuned. Art slots in without touching `core`.

---

## Roadmap

**Done**
- [x] 3D view layer — `core/`, `buildings/`, `wildlife/` and `game/` were not
      touched, exactly as the architecture promised
- [x] Save/load with a roundtrip test
- [x] Touch controls: pinch-zoom, orbit, tap-to-select with a confirm step
- [x] Procedural terrain and water shaders with parallax occlusion
- [x] Turkish localisation with English alongside

**Next**
- [ ] Pablo's model — see `ASSETS.md`, the only wiring step is one field
- [ ] Real textures, sky and vegetation — see `ASSETS.md`
- [ ] Level definitions: hand-authored seeds and per-level objective sets
- [ ] Sound and ambient score
- [ ] Reclaim silos animating the haul-away rather than resolving instantly
- [ ] Second and third region with their own biome sets and climate rules

---

## Visual direction: realism

The target is photographic, not stylised. That is a rendering-pipeline
decision, and the architecture already supports it — nothing in `core/`,
`buildings/`, `wildlife/` or `game/` knows that the current renderer is
flat-coloured 2D. Swapping `render/` for a 3D view is an additive change.

The plan:

- **Godot 4 Forward+ renderer** with real PBR materials, an HDRI sky for
  image-based lighting, SSAO, SSR, and depth of field.
- **CC0 photoscanned textures** for terrain and foliage — Poly Haven and
  ambientCG both publish 4K PBR sets under CC0, which means no licensing
  restrictions and no attribution obligations.
- **Hex tiles as instanced 3D meshes** via `MultiMeshInstance3D`, with terrain
  and biome driving material blend weights rather than swapping meshes.
- **Vegetation** scattered per-tile with density driven by that tile's
  fertility and moisture, so growth is visible as it happens.
- **Water** as a real shader — depth-based transparency, refraction,
  screen-space reflection.

The honest constraint: Forward+ with a full PBR pipeline is a desktop-class
renderer, and iOS needs care. The mitigation is a quality tier — full pipeline
on desktop and recent devices, reduced shadow and reflection budgets on
mobile. This needs profiling on a real device early rather than late, because
finding out at submission time that the frame budget does not hold is the
expensive version of this discovery.

Assets themselves have to be sourced — CC0 libraries, licensed packs, or
commissioned work. That is a procurement task, not a coding one.

**Shipping**
- [ ] iOS export — **needs macOS + Xcode**, which Windows cannot do. Plan is
      Codemagic or a GitHub Actions macOS runner building the Godot iOS export.
- [ ] Apple Developer account ($99/yr)
- [ ] App Store assets: icon set, screenshots, privacy manifest

---

## A note on originality

This game shares a genre and a set of mechanics with Terra Nil, which is the
game that made me want to build it. Mechanics and systems are not
copyrightable, and this codebase is written from scratch — but the art,
naming, music, and visual identity here are original and must stay that way.
Apple's App Store guideline 4.1 rejects clones, so the surface of this game
needs to be its own thing. That is a design constraint from day one, not a
cleanup task before release.
