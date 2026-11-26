class_name WorldConfig
extends RefCounted
## How the planet is laid out: its size, its layers and where ores appear.
## "Depth" below means blocks below SURFACE_Y (the average ground height).

## Fixed seed so everyone gets the same planet. Set to 0 for a random one each run.
const SEED := 1337

## World size in blocks (x, y, z). Chunks are 16 blocks, so keep these multiples of 16.
const WORLD_SIZE := Vector3i(96, 80, 96)

## Average ground height and how much the hills vary around it.
const SURFACE_Y := 64
const HILL_HEIGHT := 5.0
const HILL_FREQUENCY := 0.025

## Layers, measured down from the local ground.
const DIRT_DEPTH := 4
## Below this depth, stone turns into harder, more valuable basalt.
const BASALT_DEPTH := 28
## The bottom rows of the world are unbreakable core.
const CORE_ROWS := 2

## Ores. They replace stone and basalt inside noise "veins".
## Weight controls how often an ore wins inside a vein at a given depth.
const ORES := [
	{"id": Blocks.COAL,     "min_depth": 3,  "max_depth": 40, "weight": 6.0},
	{"id": Blocks.IRON,     "min_depth": 10, "max_depth": 64, "weight": 4.0},
	{"id": Blocks.GOLD,     "min_depth": 24, "max_depth": 64, "weight": 2.0},
	{"id": Blocks.SAPPHIRE, "min_depth": 36, "max_depth": 64, "weight": 1.6},
	{"id": Blocks.RUBY,     "min_depth": 46, "max_depth": 64, "weight": 1.2},
]
## Vein noise threshold near the surface and at the bottom. Lower = more ore.
const ORE_THRESHOLD_TOP := 0.66
const ORE_THRESHOLD_BOTTOM := 0.52
const ORE_FREQUENCY := 0.13

## Trees
const TREE_ATTEMPTS := 90

## The flat, unbreakable base floor in the middle of the map (a disc this many blocks across from the middle).
const BASE_RADIUS := 6
const FLAT_RADIUS := 10.0
