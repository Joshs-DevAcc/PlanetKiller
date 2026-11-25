# Planet Killer

An incremental voxel mining game. You start on the surface with a pickaxe and a
backpack. Every block can be mined, deeper layers pay more, and the long-term goal
is to strip the whole planet down to its core.

![Prototype screenshot](docs/screenshot.png)

## Play it

1. Install **Godot 4.3** or newer 4.x (the standard build, not .NET): https://godotengine.org/download
2. Open Godot, click **Import**, and pick the `project.godot` file in this folder.
3. Press **F5** (or the ▶ button at the top right) to play.

The first open takes a few seconds while Godot imports the project.
If your computer's graphics are old and the game won't start, go to
**Project > Project Settings > Rendering > Renderer** and switch to *Compatibility*.

### Controls

| Key | Action |
| --- | --- |
| W A S D | Move |
| Mouse | Look |
| Space | Jump |
| Shift | Sprint |
| Hold left click | Mine the outlined block |
| R | Teleport back to base |
| Esc | Free the mouse (click to grab it again) |

### The loop

Mine blocks to fill your backpack (40 blocks to start). When it's full, go back to the
glowing green **SELL** pad at the base (press R to teleport there) and step on it to
sell everything. Your money shows at the top left.

| Layer | Found | Value |
| --- | --- | --- |
| Grass, leaves | Surface | $0 (not kept) |
| Dirt | Top 4 blocks | $1 |
| Wood | Trees | $2 |
| Stone | Down to 28m | $4 |
| Basalt | Below 28m, harder | $6 |
| Coal | 3m to 40m | $8 |
| Iron | 10m and deeper | $15 |
| Gold | 24m and deeper | $30 |
| Sapphire | 36m and deeper | $60 |
| Ruby | 46m and deeper | $100 |
| Core | Bottom of the world | Unbreakable (for now) |

## Tuning the game

Most numbers live in two files, so you can change them without touching game code:

- `scripts/data/blocks.gd`: every block's name, sell value, how long it takes to mine and its color.
- `scripts/data/world_config.gd`: world size, seed, hill height, layer depths, which ores appear at which depths and how rare they are.
- `scripts/game_state.gd`: starting backpack size, pickaxe power and reach.

## How it's built

- `scripts/voxel_world.gd` holds the planet as one byte per block and draws it in 16×16×16 chunks.
  Mining a block rebuilds only that chunk's mesh and collision.
- `scripts/player.gd` is the first-person miner. Mining uses a grid raycast, so the outlined block is exactly what you hit.
- `scripts/sell_pad.gd` is the sell zone, `scripts/hud.gd` the on-screen text, `scripts/main.gd` builds the scene.

Everything is plain GDScript with no plugins, so the project opens in a stock Godot install.
The world is 96×80×96 blocks for now. Going much bigger (a real planet with caves) will
mean moving the terrain to the Voxel Tools engine module or threaded chunk loading, which
is planned for a later step.

## Tests

A headless smoke test generates the world, checks every layer and ore exists, mines a
column of blocks, sells them and checks the money:

```
godot --headless --path . -s res://tests/smoke_test.gd
```

`tests/screenshot.gd` saves screenshots without a person at the keyboard (needs a display or `xvfb-run`).

## Roadmap

1. **Core loop** (this): walk, mine, fill the backpack, sell at base.
2. **Economy:** shop for pickaxe and backpack upgrades, tuned layer values.
3. **Underground:** caves, monsters, weapons.
4. **Base building:** place blocks, base upgrades.
5. **Vehicles:** drill tank, then a ship for carving big chunks.
6. **Automation:** mining robots and factories.
