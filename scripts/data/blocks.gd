class_name Blocks
extends RefCounted
## Every block type in the game, in one table.
##
## This is the file to edit when tuning the economy:
##   value    = money paid per block at the sell pad
##   hardness = how tough it is to dig. Higher takes more hits; see Upgrades.MINING_RATE.
##              A negative hardness means the block cannot be mined.
##   collect  = false means the block is destroyed instead of going in the backpack
##   color    = base color used when drawing the block
##
## Block ids are the index into DEFS, so add new blocks at the end
## and give them a matching constant below.

const AIR := 0
const GRASS := 1
const DIRT := 2
const WOOD := 3
const LEAVES := 4
const STONE := 5
const BASALT := 6
const COAL := 7
const IRON := 8
const GOLD := 9
const SAPPHIRE := 10
const RUBY := 11
const CORE := 12
const BASE_FLOOR := 13
const MAGMA_ROCK := 14
const EMERALD := 15
const DIAMOND := 16
const STARSTONE := 17

const DEFS := [
	{"name": "Air",        "value": 0,   "hardness": 0.0,  "collect": false, "color": Color(0, 0, 0)},
	{"name": "Grass",      "value": 0,   "hardness": 0.3,  "collect": false, "color": Color(0.3, 0.54, 0.2)},
	{"name": "Dirt",       "value": 1,   "hardness": 0.45, "collect": true,  "color": Color(0.47, 0.32, 0.2)},
	{"name": "Wood",       "value": 2,   "hardness": 0.7,  "collect": true,  "color": Color(0.45, 0.3, 0.16)},
	{"name": "Leaves",     "value": 0,   "hardness": 0.15, "collect": false, "color": Color(0.2, 0.42, 0.18)},
	{"name": "Stone",      "value": 4,   "hardness": 0.9,  "collect": true,  "color": Color(0.52, 0.52, 0.54)},
	{"name": "Basalt",     "value": 6,   "hardness": 1.4,  "collect": true,  "color": Color(0.27, 0.27, 0.31)},
	{"name": "Coal",       "value": 8,   "hardness": 1.0,  "collect": true,  "color": Color(0.12, 0.12, 0.13)},
	{"name": "Iron",       "value": 15,  "hardness": 1.4,  "collect": true,  "color": Color(0.72, 0.42, 0.26)},
	{"name": "Gold",       "value": 30,  "hardness": 1.7,  "collect": true,  "color": Color(0.98, 0.8, 0.2)},
	{"name": "Sapphire",   "value": 60,  "hardness": 2.2,  "collect": true,  "color": Color(0.18, 0.4, 0.95)},
	{"name": "Ruby",       "value": 100, "hardness": 2.8,  "collect": true,  "color": Color(0.9, 0.12, 0.2)},
	{"name": "Core",       "value": 0,   "hardness": -1.0, "collect": false, "color": Color(0.35, 0.08, 0.05)},
	{"name": "Base Floor", "value": 0,   "hardness": -1.0, "collect": false, "color": Color(0.32, 0.3, 0.3)},
	{"name": "Magma Rock", "value": 10,  "hardness": 2.0,  "collect": true,  "color": Color(0.3, 0.14, 0.1)},
	{"name": "Emerald",    "value": 160, "hardness": 3.2,  "collect": true,  "color": Color(0.1, 0.8, 0.4)},
	{"name": "Diamond",    "value": 300, "hardness": 4.0,  "collect": true,  "color": Color(0.75, 0.95, 1.0)},
	{"name": "Starstone",  "value": 600, "hardness": 5.0,  "collect": true,  "color": Color(0.75, 0.4, 1.0)},
]


static func def(id: int) -> Dictionary:
	return DEFS[id]


static func block_name(id: int) -> String:
	return DEFS[id]["name"]


static func value(id: int) -> int:
	return DEFS[id]["value"]


static func hardness(id: int) -> float:
	return DEFS[id]["hardness"]


static func is_collectable(id: int) -> bool:
	return DEFS[id]["collect"]


static func color(id: int) -> Color:
	return DEFS[id]["color"]
