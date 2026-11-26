class_name Monsters
extends RefCounted
## The creatures that live underground. They never appear above MIN_DEPTH.
## Each kind lives in a depth band; deeper kinds are tougher and pay more.

## No monsters spawn while you are shallower than this (meters below sea level).
const MIN_DEPTH := 10.0
## Most monsters alive at once, and seconds between spawn attempts.
const MAX_ALIVE := 6
const SPAWN_INTERVAL := 4.0
## Monsters spawn this far from you (meters) and vanish if you get far away.
const SPAWN_DISTANCE_MIN := 12.0
const SPAWN_DISTANCE_MAX := 22.0
const DESPAWN_DISTANCE := 45.0

## speed in m/s, damage per bite, bites per second, reward in $ when killed.
## Monsters drift through open caves and burrow (slowly) through rock.
const KINDS := [
	{"name": "Gloomling",     "min_depth": 10, "max_depth": 40, "health": 30.0,  "speed": 2.6, "damage": 8.0,  "bite_rate": 1.0, "reward": 12,
		"size": 0.45, "color": Color(0.25, 0.22, 0.35), "eye": Color(0.6, 1.0, 0.7)},
	{"name": "Rock Gnasher",  "min_depth": 25, "max_depth": 60, "health": 90.0,  "speed": 2.2, "damage": 15.0, "bite_rate": 0.8, "reward": 40,
		"size": 0.7,  "color": Color(0.35, 0.33, 0.3), "eye": Color(1.0, 0.75, 0.2)},
	{"name": "Magma Crawler", "min_depth": 46, "max_depth": 80, "health": 220.0, "speed": 3.0, "damage": 25.0, "bite_rate": 1.0, "reward": 120,
		"size": 0.8,  "color": Color(0.45, 0.1, 0.05), "eye": Color(1.0, 0.5, 0.1)},
]
