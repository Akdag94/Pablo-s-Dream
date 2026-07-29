# Pablo's Dream

An ecosystem restoration game. You arrive on dead ground, rebuild a living
landscape with machines, and then take every machine back with you when you
leave. The win condition is an empty map that is fully alive.

Built with **Godot 4.7**, targeting iPhone first and desktop alongside it.

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
| Select a tile | left click | tap |
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

Everything on the map is a tile with four environmental values — **terrain**,
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
wetland tiles, so much standing water, a temperature band, sometimes solitude
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

`scripts/game/pablo.gd` holds only his position, heading, and mood in grid
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
    grid.gd         square grid maths — the only file that knows the shape
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
    save_game.gd    serialise and restore a run
  wildlife/
    species_def.gd  what one species needs
    bestiary.gd     >>> ALL SPECIES TUNING LIVES HERE <<<
    wildlife_system.gd  surveys the world, settles and un-settles species
  input/
    gesture_recognizer.gd  separates camera moves from game actions
  render/
    world_view.gd   flat-colour 2D renderer + pointer input
  render3d/
    world_view_3d.gd    the real renderer: two MultiMesh batches, sky, water
    terrain_textures.gd  the photoscanned PBR texture array
    camera_rig.gd        pan, orbit, zoom
    build_cursor.gd      selection ring and area-of-effect preview
    foliage.gd           fertility-driven scattering
    pablo_view.gd        his model and mood animation
    game_controller_3d.gd  the one owner of the gesture stream
    quality.gd           per-device render budget
  audio/
    sound_bank.gd   >>> ALL AUDIO TUNING LIVES HERE <<<
    audio_director.gd  pooled voices, buses, ambience
  ui/
    hud.gd          desktop prototype HUD
    hud_3d.gd       the touch-first HUD
shaders/
  terrain.gdshader  triplanar PBR blend with parallax occlusion
  water.gdshader    depth transparency, refraction, reflection
scenes/
  Main.tscn
  Main3D.tscn
```

The `core`, `buildings`, `wildlife` and `game` layers know nothing about
rendering or audio. You can step `world.simulate()` in a headless test and
assert on tile states.

**To rebalance the game, you only need to touch `catalog.gd`** — every cost,
radius, and strength is there.

---

## Current state

The whole run is playable end to end: square grid, procedural island
generation, moisture diffusion, fertility, temperature, the full biome
settling rule set, all 14 buildings, power coverage, the leaf economy, all
four phases, the wildlife survey, and the launch.

The 3D renderer is the real one — photoscanned PBR terrain, an HDRI sky per
phase, a water shader with refraction and reflection, fertility-driven
foliage, and touch controls with a confirm step. `scenes/Main.tscn` is the
flat-colour 2D prototype, kept because the simulation is easier to read in
solid colours while numbers are being tuned.

Known debt: the balance was tuned against hexagons, where every tile had six
neighbours. Squares have four for adjacency rules and eight for scattering, so
diffusion and coverage both behave differently now and the phase pacing has
not been re-tuned against them.

---

## Roadmap

**Done**
- [x] 3D view layer — `core/`, `buildings/`, `wildlife/` and `game/` were not
      touched, exactly as the architecture promised
- [x] Save/load with a roundtrip test
- [x] Touch controls: pinch-zoom, orbit, tap-to-select with a confirm step
- [x] Procedural terrain and water shaders with parallax occlusion
- [x] Turkish localisation with English alongside, in a font that carries the
      full Turkish set
- [x] Photoscanned CC0 ground textures through a texture array
- [x] HDRI skies that change with the phase
- [x] Sound: nine event cues wired, pooled voices, ambience layer waiting on
      files

**Next**
- [ ] Pablo's model — see `ASSETS.md`, the only wiring step is one field
- [ ] Ambience loops and music — see `ASSETS.md` §7, no code change needed
- [ ] Level definitions: hand-authored seeds and per-level objective sets
- [ ] Reclaim silos animating the haul-away rather than resolving instantly
- [ ] Second and third region with their own biome sets and climate rules

---

## Visual direction: realism

The target is photographic, not stylised. The architecture made that an
additive change, exactly as intended: adding `render3d/` did not touch a line
of `core/`, `buildings/`, `wildlife/` or `game/`, and the 2D prototype in
`render/` still runs off the same simulation.

What is in:

- **Forward+ renderer** with real PBR materials, an HDRI sky per phase for
  image-based lighting, SSAO, SSR and depth of field.
- **CC0 photoscanned textures** for the ground, from ambientCG, loaded into a
  texture array so all eight terrain types share one material.
- **Tiles as instanced meshes** via `MultiMeshInstance3D` — one draw call for
  all land and one for all water, regardless of map size, with terrain and
  biome driving blend weights rather than swapping meshes.
- **Vegetation** scattered per-tile with density driven by that tile's
  fertility and moisture, so growth is visible as it happens.
- **Water** as a real shader — depth-based transparency, refraction and
  screen-space reflection.

The honest constraint, unchanged: Forward+ with a full PBR pipeline is a
desktop-class renderer, and iOS needs care. `render3d/quality.gd` holds the
mitigation — full pipeline on desktop, reduced shadow, reflection and foliage
budgets on mobile. **This has not been profiled on a real device yet**, and
finding out at submission time that the frame budget does not hold is the
expensive version of that discovery.

What is still outside the code: Pablo's model, real building and animal
meshes, and the ambience loops. All CC0 or CC-BY, all listed in `ASSETS.md`.
That is a procurement task, not a coding one.

**Shipping**
- [x] Apple Developer account
- [x] CI pipeline written — `codemagic.yaml` builds the iOS export on a hosted
      macOS runner, because iOS builds need Xcode and this is a Windows machine
- [ ] Export presets — one manual pass in the Godot editor, named exactly `iOS`
      and `Android`; `codemagic.yaml` refers to them by name
- [ ] First TestFlight build, which is also the first real frame-rate reading
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
