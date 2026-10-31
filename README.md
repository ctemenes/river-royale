# River Royale

A battle royale where you play as a river. Eighty rivers spawn on one summit after a storm, carve downhill, swallow anything smaller, drink from springs, and race to be the biggest thing to hit the coast.

Godot 4.7, GDScript. Target: Steam (Windows, Linux, macOS), online multiplayer, 8 to 80 players with bot backfill.

## Run it

Clone with `git clone https://github.com/ctemenes/river-royale`, or double-click `sync.bat` in an existing clone to pull the latest and open Godot.

1. Install [Godot 4.x](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, Import, pick this folder's `project.godot`.
3. Press F5.

Controls: A / D or arrows steer across the slope. Tab toggles the overhead map. Gravity always wins eventually.

## Headless sim test

```
godot --headless --import              # once, builds the script class cache
godot --headless -s tests/sim_test.gd
```

Runs a full 80-bot match with no rendering, prints timings and the leaderboard, and checks that two matches from the same seed are identical. That determinism check is the contract the multiplayer server will rely on: keep `sim/` free of node access and unseeded randomness.

## Asset pipeline

`assets/manifest.json` lists every generated model with its download URL. The `fetch-assets` GitHub Action downloads anything missing into `assets/kit/` and commits it, so adding a model is one manifest line. `world/PropScatter.gd` places the kit by terrain rules.

## Layout

```
sim/        Pure simulation, no nodes. Runs on server and client identically.
  TerrainData.gd   Procedural island: noise, priority-flood depression fill,
                   distance to sea, steepest-descent flow field.
  RiverSim.gd      Rivers, bots, springs, absorption, ranking.
world/      Rendering of the sim.
  TerrainMesh.gd   Heightmap to mesh with vertex colours.
  RiverRenderer.gd Ribbon mesh per river along its path, head marker, label.
player/     CameraRig.gd chase camera + map view.
ui/         HUD.gd rank / km to sea / litres, event feed, end screen.
scenes/     Main.tscn single-player match.
tests/      Headless test scripts.
```

## Design pillars

- **Gravity is the opponent.** You steer across the slope, never against it. Every decision is "which valley".
- **Size is everything.** Rank is by volume. Bigger absorbs smaller, evenly matched rivers run side by side (within 20%).
- **The map is the match.** A fresh island every round from a shared seed. Reading the terrain from the summit is the skill.
- **Nobody waits.** Lobbies fill with bots after 30 seconds. 8 real players and 72 bots is a valid match.

## Roadmap

### Phase 1: 3D single player (this repo, now)
- [x] Deterministic island generation with guaranteed drainage
- [x] River sim ported from the web prototype (bots, springs, absorb, grace period)
- [x] Terrain mesh, river ribbons, chase camera, HUD, end screen
- [ ] Flowing water shader for ribbons (scrolling normals, foam edges, per-river tint)
- [ ] Terrain material: splat map by height/slope/rain, textures authored in Blender
- [ ] Blender asset kit: rocks, trees, summit snow, coast props scattered by rules
- [ ] Sound: water loop scaled by volume, absorb and spring stingers, DnB soundtrack
- [ ] Name entry, settings, pause
- [ ] Abilities to test: Surge (short speed burst), Dam (block a valley briefly), Split (fork to dodge)

### Phase 2: multiplayer
- Server-authoritative. A headless Godot build runs `RiverSim`; clients send steer (-1..1) at 20 Hz; server broadcasts river positions and volumes at 20 Hz; clients interpolate.
- Transport: Godot high-level multiplayer (ENet) first, then GodotSteam's networking so friends can join via Steam lobbies.
- Lobby: countdown, names, bot backfill, seed broadcast, everyone generates the same island locally.
- Reconnect: late joiners get seed + current river state.

### Phase 3: content and retention
- Biomes per island (alpine, volcanic, rainforest) changing rain and speed
- Progression: cosmetic river tints, foam styles, name plates
- Daily seeded island with a shared leaderboard

### Phase 4: Steam
- Steamworks via GodotSteam addon: lobbies, achievements, rich presence
- Steam Direct fee, store page, capsule art rendered from Blender
- Trailer: in-engine flyover plus Blender hero shots
- Next Fest demo build, then release

## Blender's role

Islands are procedural in-engine so every match is new and every client agrees. Blender makes everything on top of them: rock and tree kits, the summit, coastline props, water and foam material prototyping, UI 3D pieces, the trailer, and store art. Export as glTF into `assets/`. Godot can also open `.blend` files directly if Blender is installed and the path is set in Editor Settings.

## Third-party

- **Kenney Nature Kit** (CC0, kenney.nl): the prop kit under `assets/kenney/`. Credit not required, given gladly.
- **Waterways** by Kasper Arnklit Frandsen (MIT): `addons/waterways/`, river/lake/waterfall meshes with baked flow and foam maps. Used for hero water (lakes, waterfalls, the sea edge); the 80 player rivers stay on the runtime ribbon system because Waterways bakes per river in the editor.
- Higgsfield / Tripo generated props under `assets/kit/` (our own generations).

## Credit

Concept inspired by the "Playing as a River in a Battle Royale" concept trailer by bonkbureau ("making trailers for games I wish existed"). The mechanics, code, name, and art here are original.
