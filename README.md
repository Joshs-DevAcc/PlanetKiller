# Planet Killer

An incremental voxel mining game. You start on the surface with a pickaxe and a
backpack. Every block can be mined, deeper layers pay more, and the long-term goal
is to strip the whole planet down to its core.

![The base, with the shop and sell pad](docs/screenshot.png)

| Monsters in the caves | Craters in the hills | The shop |
| --- | --- | --- |
| ![Monsters in a cave](docs/screenshot_cave.png) | ![Craters dug into the hills](docs/screenshot_pit.png) | ![The shop menu](docs/screenshot_shop.png) |

## Play it

1. Install **Godot 4.3** or newer 4.x (the standard build, not .NET): https://godotengine.org/download
2. Open Godot, click **Import**, and pick the `project.godot` file in this folder.
3. Press **F5** (or the ▶ button at the top right) to play.

The first open takes a few seconds while Godot imports the project, and each launch shows a
short loading screen while the planet is built.
If your computer's graphics are old and the game won't start, go to
**Project > Project Settings > Rendering > Renderer** and switch to *Compatibility*.

### Controls

| Key | Action |
| --- | --- |
| W A S D | Move |
| Mouse | Look |
| Space | Jump |
| Shift | Sprint |
| Hold left click | Swing your tool. Each dig scoops a round chunk out of the ground |
| Hold right click | Shoot your blaster |
| E | Open the shop (stand at the counter) |
| R | Teleport back to base |
| Esc | Free the mouse (click to grab it again) |

### The loop

Dig to fill your backpack (40 blocks to start). The glowing bubble shows how big a chunk
your next dig takes out. Harder materials need more hits before the chunk comes out.
When your backpack is full, go back to the green **SELL** pad at the base (press R to
teleport there) and step on it to sell everything. Then spend your money at the **SHOP**:

| Upgrade | Levels |
| --- | --- |
| Mining tool | Rusty, Iron and Steel Pickaxe, then Hand Drill and Power Drill |
| Dig size | Radius 1.3, 1.7, 2.2, 2.8, 3.5 blocks |
| Backpack | 40, 80, 160, 320, 640 blocks |
| Weapon | Pebble Blaster, Ion Blaster, Plasma Rifle, Arc Cannon |
| Armor | 100, 150, 225, 350, 500 health |

### Underground

Below about 7m the rock is full of winding tunnels and big caverns, and it gets darker
the deeper you go (your headlamp brightens to help). From 10m down, monsters come out of
the dark: **Gloomlings** first, then **Rock Gnashers** from 25m and **Magma Crawlers** from 46m.
They drift through caves and burrow through rock toward you. Shoot them with right click for
a cash reward. Your health shows at the top left. It comes back slowly when you avoid damage
and quickly at the base. Long falls hurt too. If you're knocked out you wake up at the base,
but you lose what's in your backpack.

Ores show up as colored flecks in the rock. "Block" below means one cubic meter.

| Layer | Found | Value per block |
| --- | --- | --- |
| Grass, leaves | Surface | $0 (not kept) |
| Dirt | Top 3m | $1 |
| Wood | Trees | $2 |
| Stone | Down to 21m | $4 |
| Basalt | 21m to 48m, harder | $6 |
| Magma Rock | Below 48m, harder still | $10 |
| Coal | 2m to 30m | $8 |
| Iron | 8m and deeper | $15 |
| Gold | 18m and deeper | $30 |
| Sapphire | 27m and deeper | $60 |
| Ruby | 34m and deeper | $100 |
| Emerald | 44m and deeper | $160 |
| Diamond | 54m and deeper | $300 |
| Starstone | 66m and deeper | $600 |
| Core | Bottom of the world | Unbreakable (for now) |

## Tuning the game

Most numbers live in two files, so you can change them without touching game code:

- `scripts/data/blocks.gd`: every material's name, sell value, hardness and color.
- `scripts/data/upgrades.gd`: shop prices and what each tool, dig size, backpack, weapon and armor level gives you.
- `scripts/data/monsters.gd`: monster kinds, their depths, health, speed, damage and rewards, and how often they spawn.
- `scripts/data/world_config.gd`: world size, voxel size, seed, hills, layer depths, which ores appear at which depths and how rare they are, trees and boulders.
- `scripts/game_state.gd`: money, backpack and upgrade levels, plus how far you can reach.

## How it's built

- `scripts/voxel_world.gd` stores a density and a material for every grid point (every 0.5m by
  default) and draws the surface with *surface nets*, which gives smooth, rounded terrain instead of
  cubes. It is split into 16×16×16 chunks. Chunks are built on background threads, at startup and
  after every dig, so digging doesn't stutter.
- `scripts/monster.gd` is one creature and `scripts/monster_spawner.gd` decides when and where they appear.
- `shaders/terrain.gdshader` gives the terrain its rock and soil detail and draws ores as flecks.
- `scripts/player.gd` is the first-person miner: movement, the tool models, swing and drill
  animations, camera bob and shake, and digging.
- `scripts/shop.gd` is the shop counter and menu, `scripts/sell_pad.gd` the sell zone,
  `scripts/hud.gd` the on-screen text, `scripts/main.gd` builds the scene.

Everything is plain GDScript with no plugins, so the project opens in a stock Godot install.
The world is 80×96×80 meters (160×192×160 voxels) for now. Going much bigger (a real planet with caves) will
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

1. **Core loop:** walk, dig smooth terrain, fill the backpack, sell at base. Done.
2. **Economy:** shop for tool, dig size and backpack upgrades. Started; values still need tuning.
3. **Underground:** caves, monsters, weapons, health. Done (first pass).
4. **Base building:** place blocks, base upgrades.
5. **Vehicles:** drill tank, then a ship for carving big chunks.
6. **Automation:** mining robots and factories.
