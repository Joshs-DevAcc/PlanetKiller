class_name Upgrades
extends RefCounted
## Everything the shop sells. Each list is a ladder of levels: level 0 is what
## you start with, and each later entry is one purchase. Edit costs and stats here.

## Mining tools. power = how fast it chews through material,
## hits_per_second = how often it strikes (pickaxe swings, or drill pulses).
const TOOLS := [
	{"name": "Rusty Pickaxe", "kind": "pickaxe", "power": 1.0, "hits_per_second": 2.0, "cost": 0,    "color": Color(0.55, 0.45, 0.38)},
	{"name": "Iron Pickaxe",  "kind": "pickaxe", "power": 1.7, "hits_per_second": 2.4, "cost": 80,   "color": Color(0.72, 0.72, 0.75)},
	{"name": "Steel Pickaxe", "kind": "pickaxe", "power": 2.8, "hits_per_second": 2.8, "cost": 350,  "color": Color(0.55, 0.65, 0.8)},
	{"name": "Hand Drill",    "kind": "drill",   "power": 4.5, "hits_per_second": 6.0, "cost": 1200, "color": Color(0.95, 0.75, 0.2)},
	{"name": "Power Drill",   "kind": "drill",   "power": 7.5, "hits_per_second": 8.0, "cost": 4000, "color": Color(0.9, 0.3, 0.25)},
]

## How big a hole each strike takes out of the world, as a sphere radius in blocks.
const DIG_SIZE := [
	{"radius": 1.3, "cost": 0},
	{"radius": 1.7, "cost": 60},
	{"radius": 2.2, "cost": 250},
	{"radius": 2.8, "cost": 900},
	{"radius": 3.5, "cost": 3000},
]

const BACKPACK := [
	{"capacity": 40,  "cost": 0},
	{"capacity": 80,  "cost": 100},
	{"capacity": 160, "cost": 400},
	{"capacity": 320, "cost": 1500},
	{"capacity": 640, "cost": 5000},
]

## Weapons, fired with right click. damage per shot, shots_per_second, range in meters.
const WEAPONS := [
	{"name": "Pebble Blaster", "damage": 10.0, "shots_per_second": 3.0, "range": 18.0, "cost": 0,    "color": Color(0.6, 0.55, 0.5)},
	{"name": "Ion Blaster",    "damage": 22.0, "shots_per_second": 4.0, "range": 24.0, "cost": 300,  "color": Color(0.3, 0.8, 1.0)},
	{"name": "Plasma Rifle",   "damage": 45.0, "shots_per_second": 5.0, "range": 30.0, "cost": 1500, "color": Color(0.5, 1.0, 0.4)},
	{"name": "Arc Cannon",     "damage": 90.0, "shots_per_second": 6.0, "range": 36.0, "cost": 5000, "color": Color(1.0, 0.45, 0.9)},
]

## Armor raises your max health.
const ARMOR := [
	{"name": "Work Clothes",  "health": 100, "cost": 0},
	{"name": "Leather Vest",  "health": 150, "cost": 200},
	{"name": "Miner's Plate", "health": 225, "cost": 800},
	{"name": "Deep Suit",     "health": 350, "cost": 2500},
	{"name": "Core Armor",    "health": 500, "cost": 7000},
]

## How much mining progress one second of hitting gives, before power and hardness.
## A dig completes at 1.0. progress per hit = MINING_RATE * power / (hardness * hits_per_second)
const MINING_RATE := 1.3
