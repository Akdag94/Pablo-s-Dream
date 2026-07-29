# Asset sourcing list

Everything the game still needs from outside the codebase, with exactly where
to look and what to search for.

**Licence rule for this project:** only take **CC0** or **CC-BY**. Avoid
anything marked NonCommercial (NC) or "editorial use only" — the App Store
build is a commercial release, and NC assets make it unshippable. CC0 needs no
credit; CC-BY needs a line in the credits screen.

Drop everything into `assets/` following the folder names below. The code
already looks for these paths, or they are wired by dragging into an exported
field — noted per item.

---

## 1. Pablo — the one thing only you can choose

| What | Format | Where it goes |
|---|---|---|
| Pablo's model | `.glb` (preferred) or `.fbx` | `assets/pablo/pablo.glb` |

Then in `scenes/Main3D.tscn`, select the **PabloView** node and drag the model
into the **Model Scene** field. That is the only wiring step.

If it has animations, name the clips `idle` and `walk` — those are the names
`pablo_view.gd` looks for. If they are named something else, tell me and I
will change the mapping instead.

**If you have photos rather than a model**, these turn photos into a 3D model:
- **Kiri Engine** (phone app, free tier) — photoscan from a video walkaround
- **Polycam** (phone app) — same idea, better cleanup tools
- **RealityCapture** (desktop, free under a revenue threshold) — highest quality

A photoscan will come out as `.obj` or `.glb` with a texture. Send it to me and
I will set up the material and scale it correctly.

---

## 2. Ground textures (optional — replaces procedural detail)

The terrain shader currently generates its own surface detail, so the game
works with none of these. Adding real photoscanned PBR sets is what pushes it
from "clean" to "photoreal".

**Source: [ambientCG](https://ambientcg.com)** — everything there is CC0.
Download the **2K-JPG** or **4K-JPG** PBR package for each.

| Search on ambientCG | Use | Save as |
|---|---|---|
| `Ground037` | dead wasteland | `assets/terrain/wasteland/` |
| `Ground048` | dry cracked earth | `assets/terrain/wasteland_alt/` |
| `Grass004` | meadow | `assets/terrain/grass/` |
| `Ground042` | forest floor | `assets/terrain/forest/` |
| `Ground031` | marsh mud | `assets/terrain/wetland/` |
| `Rock030` | cliffs and stone | `assets/terrain/rock/` |
| `Ground054` | beach sand | `assets/terrain/sand/` |
| `Gravel022` | riverbed | `assets/terrain/riverbed/` |

Each download contains `_Color`, `_NormalGL`, `_Roughness`, `_AmbientOcclusion`
and `_Displacement` maps. Keep all of them — the shader can use every one, and
`_Displacement` is what drives real parallax depth instead of the procedural
approximation.

**Alternative source: [Poly Haven Textures](https://polyhaven.com/textures)**,
also fully CC0. Search terms there: `dry ground`, `forest floor`, `mud`,
`coast sand`, `rock face`.

---

## 3. Sky

**Source: [Poly Haven HDRIs](https://polyhaven.com/hdris)** — CC0. Download
**4K HDR**.

| Search | Use | Save as |
|---|---|---|
| `kloofendal` | clear daytime, good default | `assets/sky/day.hdr` |
| `belfast sunset` | the ending, after the airship leaves | `assets/sky/dusk.hdr` |
| `overcast soil` | the opening, dead world | `assets/sky/overcast.hdr` |

The scene builds a procedural sky right now. An HDRI replaces it and improves
every material at once, because image-based lighting is most of what makes PBR
look real.

---

## 4. Vegetation

Foliage is procedural geometry today (cones and blades). Real plant models are
a large visual upgrade.

**Source: [Quaternius](https://quaternius.com)** — CC0, low-poly, game-ready,
consistent style across packs. Best value for effort here.

| Pack name | Contains |
|---|---|
| `Ultimate Nature Pack` | trees, bushes, grass, rocks, logs |
| `Stylized Nature MegaKit` | more variety, same licence |

**Source: [Poly Haven Models](https://polyhaven.com/models)** — CC0,
photoscanned, far higher fidelity but heavier. Search: `tree stump`,
`rock`, `dead tree`.

**For real photoreal trees:** search **"Quixel Megascans"** — free with an
Epic account, but read the licence: it is free for use in Unreal Engine, and
using it in Godot is **not** covered. Do not use Megascans here.

Save to `assets/foliage/`.

---

## 5. Animals — 10 species

Search each name plus `low poly` on the sources below. Style consistency
matters more than individual quality; prefer one pack covering several.

Needed: **kurbağa (frog), geyik (deer), balıkçıl (heron), kunduz (beaver),
tilki (fox), ötücü kuş (songbird), kaplumbağa (tortoise), kelebek (butterfly),
su samuru (otter), resif balığı (reef fish)**.

| Source | Notes |
|---|---|
| [Quaternius Animals](https://quaternius.com) | CC0, several animal packs, one consistent style |
| [Kenney](https://kenney.nl/assets) | CC0, `Animal Pack` — very simple, very safe licence |
| [Sketchfab](https://sketchfab.com) | filter to **CC0** or **CC-BY**, then search each animal |

On Sketchfab you **must** set the licence filter before downloading — most
models there are not free to ship.

Save to `assets/wildlife/<species_id>.glb`, using the ids in
`scripts/wildlife/bestiary.gd`: `frog`, `deer`, `heron`, `beaver`, `fox`,
`songbird`, `tortoise`, `butterflies`, `otter`, `reef_fish`.

---

## 6. Buildings — 14 structures

Currently drawn as coloured shapes. Search terms, all needing a weathered
industrial look:

`wind turbine`, `water pump`, `industrial tank`, `excavator`, `greenhouse`,
`solar panel`, `radio tower`, `silo`, `airship` / `zeppelin`.

| Source | Notes |
|---|---|
| [Quaternius Sci-Fi / Industrial packs](https://quaternius.com) | CC0 |
| [Kenney Space Kit / Tower Defense Kit](https://kenney.nl/assets) | CC0, modular pieces |

Save to `assets/buildings/<building_id>.glb` using the ids in
`scripts/buildings/catalog.gd`.

---

## 7. Sound

| What | Source | Search |
|---|---|---|
| Ambience: wind, water, birds | [freesound.org](https://freesound.org) — filter to CC0 | `wind loop`, `river loop`, `forest birds` |
| Music | [Kevin MacLeod](https://incompetech.com) (CC-BY), [Free Music Archive](https://freemusicarchive.org) | `calm ambient`, `contemplative piano` |
| UI clicks | [Kenney Audio](https://kenney.nl/assets) — CC0 | `Interface Sounds` |

Save to `assets/audio/`.

Given what this game is about, quiet and sparse works better than a score that
fills every moment. The ending in particular should probably be near-silent.

---

## 8. Font

Turkish needs full **ı İ ğ Ğ ş Ş ç Ç ö Ö ü Ü** coverage — many game fonts
silently drop these and you get boxes.

| Font | Source | Licence |
|---|---|---|
| **Inter** | [Google Fonts](https://fonts.google.com/specimen/Inter) | OFL — full Turkish support |
| **Source Sans 3** | Google Fonts | OFL — full Turkish support |
| **Nunito** | Google Fonts | OFL — softer, warmer |

Save to `assets/fonts/`. Verify by typing `ığşçöü İĞŞÇÖÜ` in the label.

---

## 9. App Store submission assets

These are required by Apple and cannot be skipped.

| What | Spec |
|---|---|
| App icon | 1024×1024 PNG, no alpha, no rounded corners |
| iPhone screenshots | 6.7" (1290×2796) and 6.5" (1242×2688), 3–10 each |
| iPad screenshots | 12.9" (2048×2732), if you ship for iPad |
| Privacy policy URL | required even when collecting nothing |
| App description | Turkish and English |

I can generate the icon and take the screenshots once the visuals are final.

---

## Priority

If you only chase a few, get these in this order:

1. **Pablo's model** — nothing else in the list matters as much
2. **Font** — the game is Turkish and currently rendering with a default font
3. **HDRI sky** — one file, improves every surface at once
4. **Ground textures** — the real photoreal step
5. Everything else

Tell me which ones you have and I will wire them in. If you would rather not
hunt for any of it, say so and I will keep pushing the procedural side —
it will not reach photoscan fidelity, but it will stay consistent and it costs
nothing to ship.
