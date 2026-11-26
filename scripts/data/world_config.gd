class_name WorldConfig
extends RefCounted
## How the planet is laid out: its size, its layers and where ores appear.
## Everything here is in meters. "Depth" means meters below SURFACE_Y.

## Fixed seed so everyone gets the same planet. Set to 0 for a random one each run.
const SEED := 1337

## Size of one voxel in meters. Smaller = smoother terrain, but slower to build and dig.
## 0.5 means 8 voxels per cubic meter.
const VOXEL_SIZE := 0.5

## World size in meters (x, y, z).
const WORLD_SIZE := Vector3(80, 96, 80)

## Average ground height and how much the hills vary around it.
const SURFACE_Y := 80.0
const HILL_HEIGHT := 6.0
const HILL_FREQUENCY := 0.02
## Small bumps on top of the hills.
const BUMP_HEIGHT := 0.6
const BUMP_FREQUENCY := 0.15

## Layers, measured down from the local ground.
const GRASS_DEPTH := 0.6
const DIRT_DEPTH := 3.0
## Below this depth, stone turns into harder, more valuable basalt...
const BASALT_DEPTH := 21.0
## ...and below this, basalt turns into glowing-hot magma rock.
const MAGMA_DEPTH := 48.0
## The bottom of the world is unbreakable core, this thick.
const CORE_DEPTH := 1.5

## Ores. They replace stone and basalt inside noise "veins".
## Weight controls how often an ore wins inside a vein at a given depth.
const ORES := [
	{"id": Blocks.COAL,     "min_depth": 2,  "max_depth": 30, "weight": 6.0},
	{"id": Blocks.IRON,      "min_depth": 8,  "max_depth": 50, "weight": 4.0},
	{"id": Blocks.GOLD,      "min_depth": 18, "max_depth": 60, "weight": 2.0},
	{"id": Blocks.SAPPHIRE,  "min_depth": 27, "max_depth": 70, "weight": 1.6},
	{"id": Blocks.RUBY,      "min_depth": 34, "max_depth": 80, "weight": 1.2},
	{"id": Blocks.EMERALD,   "min_depth": 44, "max_depth": 80, "weight": 1.0},
	{"id": Blocks.DIAMOND,   "min_depth": 54, "max_depth": 80, "weight": 0.8},
	{"id": Blocks.STARSTONE, "min_depth": 66, "max_depth": 80, "weight": 0.6},
]
## Vein noise threshold near the surface and at the bottom. Lower = more ore.
const ORE_THRESHOLD_TOP := 0.66
const ORE_THRESHOLD_BOTTOM := 0.55
## Vein size: higher frequency = smaller, more scattered veins.
const ORE_FREQUENCY := 0.16

## Caves. Winding tunnels everywhere below CAVE_START_DEPTH (under the local
## ground), plus big open caverns that get more common deeper down.
const CAVE_START_DEPTH := 7.0
const TUNNEL_FREQUENCY := 0.028
## Tunnel width: bigger = wider tunnels.
const TUNNEL_WIDTH := 0.085
const CAVERN_FREQUENCY := 0.02
## Noise above this opens a cavern. Lower = more and bigger caverns.
const CAVERN_THRESHOLD_TOP := 0.62
const CAVERN_THRESHOLD_BOTTOM := 0.42

## Trees and boulders scattered on the surface.
const TREE_COUNT := 70
const BOULDER_COUNT := 40

## The flat, unbreakable base floor in the middle of the map (radius in meters).
const BASE_RADIUS := 6.0
const FLAT_RADIUS := 10.0
