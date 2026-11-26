class_name VoxelWorld
extends Node3D
## The destructible planet, as smooth voxel terrain.
##
## The world is a 3D grid of points, WorldConfig.VOXEL_SIZE meters apart. Every
## point stores a density (0-255, solid at 128 and above) and a material (a block
## id from Blocks). The surface is drawn with "surface nets": one vertex per grid
## cell the surface passes through, joined into quads, which gives smooth ground.
##
## The grid is split into chunks of 16x16x16 points. Chunk meshes are built on
## background threads, so digging never freezes the game while they rebuild.
##
## Public functions take and return positions in meters (world space).
## Internally everything works in grid units: meters / VOXEL_SIZE.

const CHUNK := 16
const ISO := 128
## How quickly density ramps from air to solid across a surface, per grid step.
const DENSITY_SLOPE := 64.0
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")

const CORNERS: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
]
## The 12 cube edges as pairs of corner indices.
const EDGES := [
	[0, 1], [2, 3], [4, 5], [6, 7],
	[0, 2], [1, 3], [4, 6], [5, 7],
	[0, 4], [1, 5], [2, 6], [3, 7],
]

## Grid size in points.
var size: Vector3i
var voxel_size := WorldConfig.VOXEL_SIZE
var density := PackedByteArray()
var material := PackedByteArray()
## Middle of the top of the base floor, in meters.
var base_position := Vector3.ZERO
## How long the last full build took, for the curious.
var last_generate_ms := 0
var last_build_ms := 0

var _chunk_counts: Vector3i
var _chunks := {} # Vector3i -> {"mesh": MeshInstance3D, "shape": CollisionShape3D, "version": int}
var _material: ShaderMaterial
var _heights := PackedFloat32Array() # grid units, per (x, z) column
# Worker threads read these, so they are packed arrays (plain Arrays are not
# safe to share between threads).
var _block_colors := PackedColorArray()
var _edge_a := PackedInt32Array()
var _edge_b := PackedInt32Array()
var _corner_f := PackedVector3Array()
var _hardness: PackedFloat32Array = PackedFloat32Array()
var _is_ore: PackedByteArray = PackedByteArray()
var _corner_offsets := PackedInt32Array()
var _edge_cells := PackedInt32Array() # per axis, 4 cells x (dx, dy, dz)
var _edge_flip := PackedByteArray()
var _mutex := Mutex.new()
var _finished := [] # mesh results from worker threads, waiting to be applied
var _gen_results := []


func _init() -> void:
	_build_edge_tables()
	for e in EDGES:
		_edge_a.append(e[0])
		_edge_b.append(e[1])
	for k in 8:
		_corner_f.append(Vector3(CORNERS[k]))
	for d in Blocks.DEFS:
		_block_colors.append(d["color"])
		_hardness.append(d["hardness"])
		_is_ore.append(0)
	for ore in WorldConfig.ORES:
		_is_ore[ore["id"]] = 1
	_material = ShaderMaterial.new()
	_material.shader = TERRAIN_SHADER


# --- Public API -------------------------------------------------------------------

func generate(seed_value: int) -> void:
	var started := Time.get_ticks_msec()
	var s := WorldConfig.WORLD_SIZE / voxel_size
	size = Vector3i(roundi(s.x), roundi(s.y), roundi(s.z))
	_corner_offsets.clear()
	for k in 8:
		var o: Vector3i = CORNERS[k]
		_corner_offsets.append(_index(o.x, o.y, o.z))
	_generate_terrain(seed_value)
	_generate_decorations(seed_value)
	_generate_base()
	_seal_edges()
	last_generate_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	_build_all_chunks()
	last_build_ms = Time.get_ticks_msec() - started


## World size in meters.
func world_size() -> Vector3:
	return Vector3(size) * voxel_size


func get_density(p: Vector3i) -> int:
	if not _in_grid(p):
		return 0
	return density[_index(p.x, p.y, p.z)]


func get_material(p: Vector3i) -> int:
	if not _in_grid(p):
		return Blocks.AIR
	return material[_index(p.x, p.y, p.z)]


## True if the point (meters) is open air, e.g. inside a cave.
func is_air(world_pos: Vector3) -> bool:
	var g := world_pos / voxel_size
	return get_density(Vector3i(roundi(g.x), roundi(g.y), roundi(g.z))) < ISO


## Ground height in meters of the generated terrain at (x, z) meters.
func surface_height(x: float, z: float) -> float:
	var gx := clampi(roundi(x / voxel_size), 0, size.x - 1)
	var gz := clampi(roundi(z / voxel_size), 0, size.z - 1)
	return _heights[gx + gz * size.x] * voxel_size


## The material at a point on the surface (meters), e.g. where a ray hit.
## Looks at the grid points around it and picks the most solid, closest one.
func material_at(world_pos: Vector3) -> int:
	var g := world_pos / voxel_size
	var base := Vector3i(floori(g.x), floori(g.y), floori(g.z))
	var best := -100000
	var best_id := Blocks.AIR
	for dy in range(-1, 3):
		for dz in range(-1, 3):
			for dx in range(-1, 3):
				var p := base + Vector3i(dx, dy, dz)
				if not _in_grid(p):
					continue
				var i := _index(p.x, p.y, p.z)
				if density[i] < ISO:
					continue
				var score := density[i] - int((Vector3(p) - g).length() * 200.0)
				if score > best:
					best = score
					best_id = material[i]
	return best_id


## Carves a sphere (center and radius in meters) out of the world.
## Unbreakable materials are left alone.
## Returns how much of each material was removed, in cubic meters (id -> float).
func dig(center_m: Vector3, radius_m: float) -> Dictionary:
	var center := center_m / voxel_size
	var radius := radius_m / voxel_size
	var removed := {}
	var lo := Vector3i(floori(center.x - radius - 1), floori(center.y - radius - 1), floori(center.z - radius - 1))
	var hi := Vector3i(ceili(center.x + radius + 1), ceili(center.y + radius + 1), ceili(center.z + radius + 1))
	lo = lo.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	hi = hi.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	var cell_volume := voxel_size * voxel_size * voxel_size
	var changed := false
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			var row := _index(0, y, z)
			for x in range(lo.x, hi.x + 1):
				var i := row + x
				var old := density[i]
				if old == 0:
					continue
				var id := material[i]
				if _hardness[id] < 0.0:
					continue
				var dist := Vector3(x, y, z).distance_to(center)
				# Density of "outside the sphere": air at the middle, ramping up past the edge.
				var target := clampi(int(ISO + (dist - radius) * DENSITY_SLOPE), 0, 255)
				if target < old:
					density[i] = target
					changed = true
					removed[id] = removed.get(id, 0.0) + (old - target) / 255.0 * cell_volume
	if changed:
		_rebuild_region(lo, hi)
	return removed


## True while some chunks are still being rebuilt in the background.
func is_busy() -> bool:
	_mutex.lock()
	var busy := false
	for c in _chunks:
		if _chunks[c]["pending"]:
			busy = true
			break
	_mutex.unlock()
	return busy


func _process(_delta: float) -> void:
	_apply_finished()


# --- Generation -------------------------------------------------------------------

func _generate_terrain(seed_value: int) -> void:
	var sx := size.x
	var sz := size.z
	_heights.resize(sx * sz)
	var noises := _make_noises(seed_value)
	# Heights first (cheap), then fill each z slice of the grid on worker threads.
	var center := Vector2(sx, sz) * 0.5
	var flat_r := WorldConfig.FLAT_RADIUS / voxel_size
	for z in sz:
		for x in sx:
			var m := Vector2(x, z) * voxel_size
			var h := WorldConfig.SURFACE_Y
			h += noises["hills"].get_noise_2d(m.x, m.y) * WorldConfig.HILL_HEIGHT
			h += noises["bumps"].get_noise_2d(m.x, m.y) * WorldConfig.BUMP_HEIGHT
			# Flatten the ground around the base.
			var flat := clampf((Vector2(x, z).distance_to(center) - flat_r) / (10.0 / voxel_size), 0.0, 1.0)
			h = lerpf(WorldConfig.SURFACE_Y, h, smoothstep(0.0, 1.0, flat))
			_heights[x + z * sx] = clampf(h / voxel_size, 4.0, size.y - 24.0)

	_gen_results.clear()
	_gen_results.resize(sz)
	var ore_table := _build_ore_table()
	var task := WorkerThreadPool.add_group_task(_generate_slice.bind(noises["veins"], noises["layers"], noises["tunnel_a"], noises["tunnel_b"], noises["caverns"], ore_table), sz, -1, true, "terrain")
	WorkerThreadPool.wait_for_group_task_completion(task)
	density = PackedByteArray()
	material = PackedByteArray()
	for z in sz:
		density.append_array(_gen_results[z][0])
		material.append_array(_gen_results[z][1])
	_gen_results.clear()


func _make_noises(seed_value: int) -> Dictionary:
	var hills := FastNoiseLite.new()
	hills.seed = seed_value
	hills.frequency = WorldConfig.HILL_FREQUENCY
	hills.fractal_octaves = 4
	hills.domain_warp_enabled = true
	hills.domain_warp_amplitude = 8.0
	var bumps := FastNoiseLite.new()
	bumps.seed = seed_value + 3
	bumps.frequency = WorldConfig.BUMP_FREQUENCY
	bumps.fractal_octaves = 2
	var veins := FastNoiseLite.new()
	veins.seed = seed_value + 101
	veins.frequency = WorldConfig.ORE_FREQUENCY
	veins.fractal_type = FastNoiseLite.FRACTAL_NONE
	var layers := FastNoiseLite.new()
	layers.seed = seed_value + 55
	layers.frequency = 0.05
	var tunnel_a := FastNoiseLite.new()
	tunnel_a.seed = seed_value + 201
	tunnel_a.frequency = WorldConfig.TUNNEL_FREQUENCY
	tunnel_a.fractal_type = FastNoiseLite.FRACTAL_NONE
	var tunnel_b := FastNoiseLite.new()
	tunnel_b.seed = seed_value + 202
	tunnel_b.frequency = WorldConfig.TUNNEL_FREQUENCY
	tunnel_b.fractal_type = FastNoiseLite.FRACTAL_NONE
	var caverns := FastNoiseLite.new()
	caverns.seed = seed_value + 203
	caverns.frequency = WorldConfig.CAVERN_FREQUENCY
	caverns.fractal_octaves = 2
	return {"hills": hills, "bumps": bumps, "veins": veins, "layers": layers,
		"tunnel_a": tunnel_a, "tunnel_b": tunnel_b, "caverns": caverns}


## Fills one z slice of the grid. Runs on a worker thread.
func _generate_slice(z: int, veins: FastNoiseLite, layers: FastNoiseLite, tunnel_a: FastNoiseLite,
		tunnel_b: FastNoiseLite, caverns: FastNoiseLite, ore_table: PackedFloat32Array) -> void:
	var sx := size.x
	var sy := size.y
	var dens := PackedByteArray()
	dens.resize(sx * sy)
	var mats := PackedByteArray()
	mats.resize(sx * sy)
	var vs := voxel_size
	var core_top := WorldConfig.CORE_DEPTH / vs
	var surface_g := WorldConfig.SURFACE_Y / vs
	var ore_stride := 1 + WorldConfig.ORES.size() * 2
	var ore_rows := ore_table.size() / ore_stride
	var cave_start := WorldConfig.CAVE_START_DEPTH
	for x in sx:
		var h := _heights[x + z * sx]
		# Steep hillsides: scale by the slope so the density is a true distance to
		# the surface. Without this, cliffs come out jagged.
		var hx := _heights[mini(x + 1, sx - 1) + z * sx] - _heights[maxi(x - 1, 0) + z * sx]
		var hz := _heights[x + mini(z + 1, size.z - 1) * sx] - _heights[x + maxi(z - 1, 0) * sx]
		var slope_scale := 1.0 / sqrt(1.0 + (hx * hx + hz * hz) * 0.25)
		var top := mini(ceili(h) + 2, sy - 1)
		# Wavy layer boundaries so strata aren't perfectly flat.
		var wobble := layers.get_noise_2d(x * vs, z * vs) * 1.5
		for y in top + 1:
			var d := clampi(int(ISO + (h - y) * slope_scale * DENSITY_SLOPE), 0, 255)
			if d == 0:
				continue
			var below := (h - y) * vs # meters under the local ground
			var depth := (surface_g - y) * vs + wobble # meters under sea level
			var id: int
			if y < core_top:
				id = Blocks.CORE
				d = 255
			elif below < WorldConfig.GRASS_DEPTH:
				id = Blocks.GRASS
			elif below < WorldConfig.DIRT_DEPTH + wobble * 0.5:
				id = Blocks.DIRT
			else:
				if depth < WorldConfig.BASALT_DEPTH:
					id = Blocks.STONE
				elif depth < WorldConfig.MAGMA_DEPTH:
					id = Blocks.BASALT
				else:
					id = Blocks.MAGMA_ROCK
				var di := clampi(int(depth), 0, ore_rows - 1)
				if ore_table[di * ore_stride] > 0.0:
					var t := clampf(depth / WorldConfig.SURFACE_Y, 0.0, 1.0)
					var threshold := lerpf(WorldConfig.ORE_THRESHOLD_TOP, WorldConfig.ORE_THRESHOLD_BOTTOM, t)
					if veins.get_noise_3d(x * vs, y * vs, z * vs) > threshold:
						id = _pick_ore(ore_table, di * ore_stride, x * vs, y * vs, z * vs)
			# Caves: carve tunnels and caverns out of the rock.
			if below > cave_start * 0.6 and y >= core_top:
				var mx := x * vs
				var my := y * vs
				var mz := z * vs
				# Squash the tunnel noise vertically so tunnels run more sideways.
				var tunnel := maxf(absf(tunnel_a.get_noise_3d(mx, my * 1.5, mz)), absf(tunnel_b.get_noise_3d(mx, my * 1.5, mz)))
				var sdf := (tunnel - WorldConfig.TUNNEL_WIDTH) * 18.0
				var t := clampf(depth / WorldConfig.SURFACE_Y, 0.0, 1.0)
				var cavern_threshold := lerpf(WorldConfig.CAVERN_THRESHOLD_TOP, WorldConfig.CAVERN_THRESHOLD_BOTTOM, t)
				sdf = minf(sdf, (cavern_threshold - caverns.get_noise_3d(mx, my * 1.3, mz)) * 25.0)
				# Keep a solid roof under the surface and a floor above the core.
				sdf += maxf(cave_start - below, 0.0) * 1.5
				sdf += maxf(4.0 - (my - WorldConfig.CORE_DEPTH), 0.0) * 1.5
				d = mini(d, clampi(int(ISO + sdf / vs * DENSITY_SLOPE), 0, 255))
			var i := x + y * sx
			dens[i] = d
			mats[i] = id
	_mutex.lock()
	_gen_results[z] = [dens, mats]
	_mutex.unlock()


## For each meter of depth, the ores allowed there with cumulative weights.
## Packed as rows of [count, id, cumulative weight, id, cumulative weight, ...]
## so worker threads can read it safely.
func _build_ore_table() -> PackedFloat32Array:
	var stride := 1 + WorldConfig.ORES.size() * 2
	var table := PackedFloat32Array()
	for depth in int(WorldConfig.SURFACE_Y) + 1:
		var row := PackedFloat32Array()
		row.resize(stride)
		var total := 0.0
		var n := 0
		for ore in WorldConfig.ORES:
			if depth >= ore["min_depth"] and depth <= ore["max_depth"]:
				total += ore["weight"]
				row[1 + n * 2] = ore["id"]
				row[2 + n * 2] = total
				n += 1
		for k in n:
			row[2 + k * 2] /= total
		row[0] = n
		table.append_array(row)
	return table


func _pick_ore(table: PackedFloat32Array, row: int, x: float, y: float, z: float) -> int:
	# Same choice across a 2m cell, so a vein is mostly one ore.
	var r := _hash01(floori(x * 0.5), floori(y * 0.5), floori(z * 0.5))
	var n := int(table[row])
	for k in n:
		if r <= table[row + 2 + k * 2]:
			return int(table[row + 1 + k * 2])
	return int(table[row + 1 + (n - 1) * 2])


func _generate_decorations(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var ws := world_size()
	var center := Vector2(ws.x, ws.z) * 0.5
	var lumpy := FastNoiseLite.new()
	lumpy.seed = seed_value + 9
	lumpy.frequency = 0.6

	for i in WorldConfig.BOULDER_COUNT:
		var x := rng.randf_range(4.0, ws.x - 4.0)
		var z := rng.randf_range(4.0, ws.z - 4.0)
		if Vector2(x, z).distance_to(center) < WorldConfig.FLAT_RADIUS + 2.0:
			continue
		var r := rng.randf_range(0.6, 1.6)
		var c := Vector3(x, surface_height(x, z) + r * 0.2, z)
		_add_shape(c - Vector3.ONE * (r + 1), c + Vector3.ONE * (r + 1), Blocks.STONE, func(p: Vector3) -> float:
			var q := (p - c) * Vector3(1.0, 1.4, 1.0)
			return r - q.length() + lumpy.get_noise_3dv(p) * 0.35)

	for i in WorldConfig.TREE_COUNT:
		var x := rng.randf_range(4.0, ws.x - 4.0)
		var z := rng.randf_range(4.0, ws.z - 4.0)
		if Vector2(x, z).distance_to(center) < WorldConfig.FLAT_RADIUS + 3.0:
			continue
		var ground := surface_height(x, z)
		var height := rng.randf_range(3.5, 6.0)
		var top := Vector3(x + rng.randf_range(-0.4, 0.4), ground + height, z + rng.randf_range(-0.4, 0.4))
		var base := Vector3(x, ground - 0.8, z)
		# Trunk: a tapered capsule.
		_add_shape(Vector3(minf(base.x, top.x), base.y, minf(base.z, top.z)) - Vector3.ONE * 1.5,
			Vector3(maxf(base.x, top.x), top.y, maxf(base.z, top.z)) + Vector3.ONE * 1.5, Blocks.WOOD,
			func(p: Vector3) -> float:
				var ab := top - base
				var t := clampf((p - base).dot(ab) / ab.length_squared(), 0.0, 1.0)
				return lerpf(0.45, 0.22, t) - p.distance_to(base + ab * t))
		# Canopy: a few overlapping, lumpy blobs.
		var blobs := rng.randi_range(3, 5)
		for b in blobs:
			var off := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.6, 1.0), rng.randf_range(-1.2, 1.2))
			var bc := top + off
			var br := rng.randf_range(1.3, 2.0)
			_add_shape(bc - Vector3.ONE * (br + 1), bc + Vector3.ONE * (br + 1), Blocks.LEAVES, func(p: Vector3) -> float:
				return br - p.distance_to(bc) + lumpy.get_noise_3dv(p) * 0.5)


## Adds solid material where inside(p) > 0 (p and the result in meters),
## keeping whatever is denser already.
func _add_shape(lo_m: Vector3, hi_m: Vector3, id: int, inside: Callable) -> void:
	var lo_g := lo_m / voxel_size
	var hi_g := hi_m / voxel_size
	var lo := Vector3i(floori(lo_g.x), floori(lo_g.y), floori(lo_g.z)).clamp(Vector3i.ZERO, size - Vector3i.ONE)
	var hi := Vector3i(ceili(hi_g.x), ceili(hi_g.y), ceili(hi_g.z)).clamp(Vector3i.ZERO, size - Vector3i.ONE)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var sdf: float = inside.call(Vector3(x, y, z) * voxel_size)
				var d := clampi(int(ISO + sdf / voxel_size * DENSITY_SLOPE), 0, 255)
				var i := _index(x, y, z)
				if d > density[i]:
					if density[i] < ISO:
						material[i] = id
					density[i] = d


func _generate_base() -> void:
	var c := Vector2(size.x, size.z) * 0.5
	var h := WorldConfig.SURFACE_Y / voxel_size
	var r := WorldConfig.BASE_RADIUS / voxel_size
	# A flat, unbreakable slab a couple of meters thick.
	for z in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			var edge := r - Vector2(x, z).distance_to(c)
			if edge < 0.0:
				continue
			for y in range(int(h - 4.0 / voxel_size), int(h) + 3):
				var i := _index(x, y, z)
				var d := clampi(int(ISO + minf(h - y, edge) * DENSITY_SLOPE), 0, 255)
				density[i] = d
				material[i] = Blocks.BASE_FLOOR if d > 0 else Blocks.AIR
	base_position = Vector3(c.x, h, c.y) * voxel_size


## Makes the outer walls and ceiling air so the world's edges are closed off.
func _seal_edges() -> void:
	var sx := size.x
	var sy := size.y
	var sz := size.z
	for z in sz:
		for y in sy:
			density[_index(0, y, z)] = 0
			density[_index(sx - 1, y, z)] = 0
		for x in sx:
			density[_index(x, sy - 1, z)] = 0
	for y in sy:
		for x in sx:
			density[_index(x, y, 0)] = 0
			density[_index(x, y, sz - 1)] = 0


# --- Chunks -----------------------------------------------------------------------

func _build_edge_tables() -> void:
	# For a grid edge from point p to p + axis, these are the 4 cells around it,
	# listed in a loop. Godot draws clockwise triangles as front faces, so work out
	# per axis whether the loop has to be reversed to face along +axis.
	var cells := [
		[Vector3i(0, -1, -1), Vector3i(0, 0, -1), Vector3i(0, 0, 0), Vector3i(0, -1, 0)],
		[Vector3i(-1, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 0, 0), Vector3i(0, 0, -1)],
		[Vector3i(-1, -1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 0), Vector3i(-1, 0, 0)],
	]
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	_edge_cells.clear()
	_edge_flip.clear()
	for a in 3:
		var c: Array = cells[a]
		for k in 4:
			_edge_cells.append_array([c[k].x, c[k].y, c[k].z])
		var p0 := Vector3(c[0])
		var p1 := Vector3(c[1])
		var p2 := Vector3(c[2])
		_edge_flip.append(1 if (p1 - p0).cross(p2 - p0).dot(axes[a]) > 0.0 else 0)


func _build_all_chunks() -> void:
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	_chunk_counts = Vector3i(ceili(size.x / float(CHUNK)), ceili(size.y / float(CHUNK)), ceili(size.z / float(CHUNK)))
	var list: Array[Vector3i] = []
	for cz in _chunk_counts.z:
		for cy in _chunk_counts.y:
			for cx in _chunk_counts.x:
				var c := Vector3i(cx, cy, cz)
				var mesh := MeshInstance3D.new()
				mesh.name = "Chunk_%d_%d_%d" % [cx, cy, cz]
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				body.add_child(shape)
				mesh.add_child(body)
				add_child(mesh)
				_chunks[c] = {"mesh": mesh, "shape": shape, "version": 1, "pending": true}
				list.append(c)
	# Build every chunk in parallel and wait for all of them.
	var dens := density
	var mats := material
	var task := WorkerThreadPool.add_group_task(
		func(i: int) -> void: _mesh_job(list[i], 1, dens, mats), list.size(), -1, true, "chunks")
	WorkerThreadPool.wait_for_group_task_completion(task)
	_apply_finished()


## Queues background rebuilds for every chunk whose mesh uses grid points in [lo, hi].
func _rebuild_region(lo: Vector3i, hi: Vector3i) -> void:
	var c_lo := (lo - Vector3i.ONE).clamp(Vector3i.ZERO, size) / CHUNK
	var c_hi := (hi + Vector3i.ONE).clamp(Vector3i.ZERO, size) / CHUNK
	var dens := density
	var mats := material
	for cz in range(c_lo.z, c_hi.z + 1):
		for cy in range(c_lo.y, c_hi.y + 1):
			for cx in range(c_lo.x, c_hi.x + 1):
				var c := Vector3i(cx, cy, cz)
				if not _chunks.has(c):
					continue
				_mutex.lock()
				var entry: Dictionary = _chunks[c]
				entry["version"] += 1
				entry["pending"] = true
				var version: int = entry["version"]
				_mutex.unlock()
				WorkerThreadPool.add_task(_mesh_job.bind(c, version, dens, mats), true, "chunk")


## Builds one chunk's mesh data. Runs on a worker thread.
func _mesh_job(c: Vector3i, version: int, dens: PackedByteArray, mats: PackedByteArray) -> void:
	var data := _mesh_chunk(c, dens, mats)
	data["chunk"] = c
	data["version"] = version
	_mutex.lock()
	_finished.append(data)
	_mutex.unlock()


## Turns finished mesh data into meshes and collision. Main thread only.
func _apply_finished() -> void:
	_mutex.lock()
	var batch := _finished
	_finished = []
	_mutex.unlock()
	for data in batch:
		var c: Vector3i = data["chunk"]
		var entry: Dictionary = _chunks[c]
		if data["version"] != entry["version"]:
			continue # an even newer rebuild is on its way
		entry["pending"] = false
		_set_chunk_mesh(entry, data)


func _set_chunk_mesh(entry: Dictionary, data: Dictionary) -> void:
	var mi: MeshInstance3D = entry["mesh"]
	var cs: CollisionShape3D = entry["shape"]
	var indices: PackedInt32Array = data["indices"]
	if indices.is_empty():
		mi.mesh = null
		cs.shape = null
		return
	var verts: PackedVector3Array = data["verts"]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_CUSTOM0] = data["ore"]
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.surface_set_material(0, _material)
	mi.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(data["faces"])
	cs.shape = shape


## Surface nets for one chunk. Pure function of the arrays passed in, so it is
## safe to run on any thread.
func _mesh_chunk(c: Vector3i, dens: PackedByteArray, mats: PackedByteArray) -> Dictionary:
	var empty := {"indices": PackedInt32Array()}
	var sx := size.x
	var sy := size.y
	var sz := size.z
	var sxy := sx * sy
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	var z0 := c.z * CHUNK
	# Cells this chunk needs vertices for: its own, plus one row before on each axis.
	var cx0 := maxi(x0 - 1, 0)
	var cy0 := maxi(y0 - 1, 0)
	var cz0 := maxi(z0 - 1, 0)
	var cx1 := mini(x0 + CHUNK, sx - 1)
	var cy1 := mini(y0 + CHUNK, sy - 1)
	var cz1 := mini(z0 + CHUNK, sz - 1)
	if cx0 >= cx1 or cy0 >= cy1 or cz0 >= cz1:
		return empty

	# Quick exit for chunks that are all air or all solid.
	var first := dens[_index(cx0, cy0, cz0)] >= ISO
	var mixed := false
	for z in range(cz0, cz1 + 1):
		for y in range(cy0, cy1 + 1):
			var row := y * sx + z * sxy
			for x in range(cx0, cx1 + 1):
				if (dens[row + x] >= ISO) != first:
					mixed = true
					break
			if mixed: break
		if mixed: break
	if not mixed:
		return empty

	var lx := cx1 - cx0
	var ly := cy1 - cy0
	var lxy := lx * ly
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(lx * ly * (cz1 - cz0))
	cell_vertex.fill(-1)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var ore := PackedFloat32Array()
	var indices := PackedInt32Array()
	var co := _corner_offsets
	var ea := _edge_a
	var eb := _edge_b
	var cf := _corner_f
	var colors_tbl := _block_colors
	var is_ore := _is_ore
	var cells_tbl := _edge_cells
	var flip_tbl := _edge_flip
	var vs := voxel_size
	var d := PackedInt32Array()
	d.resize(8)
	var m := PackedInt32Array()
	m.resize(8)
	var grass_color := colors_tbl[Blocks.GRASS]
	var dirt_color := colors_tbl[Blocks.DIRT]
	var stone_color := colors_tbl[Blocks.STONE]

	# Pass 1: one vertex per cell the surface passes through.
	for z in range(cz0, cz1):
		for y in range(cy0, cy1):
			for x in range(cx0, cx1):
				var base := x + y * sx + z * sxy
				var mask := 0
				for k in 8:
					var v := dens[base + co[k]]
					d[k] = v
					if v >= ISO:
						mask |= 1 << k
				if mask == 0 or mask == 255:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e in 12:
					var a := ea[e]
					var b := eb[e]
					if ((mask >> a) & 1) != ((mask >> b) & 1):
						var t := (ISO - 0.5 - d[a]) / float(d[b] - d[a])
						sum += cf[a].lerp(cf[b], t)
						count += 1
				var pos := (Vector3(x, y, z) + sum / count) * vs
				var grad := Vector3(
					(d[1] + d[3] + d[5] + d[7]) - (d[0] + d[2] + d[4] + d[6]),
					(d[2] + d[3] + d[6] + d[7]) - (d[0] + d[1] + d[4] + d[5]),
					(d[4] + d[5] + d[6] + d[7]) - (d[0] + d[1] + d[2] + d[3]))
				var normal := -grad.normalized() if grad.length_squared() > 0.0 else Vector3.UP

				# Blend the rock colors of the solid corners; ores are tracked separately
				# so the shader can draw them as flecks in the rock.
				var host := Color(0, 0, 0)
				var host_w := 0.0
				var ore_w := 0.0
				var ore_best := 0
				var ore_id := 0
				var total_w := 0.0
				for k in 8:
					if d[k] < 60:
						continue
					var id := mats[base + co[k]]
					var w := float(d[k])
					total_w += w
					if is_ore[id] == 1:
						ore_w += w
						if d[k] > ore_best:
							ore_best = d[k]
							ore_id = id
					else:
						if id == Blocks.GRASS:
							# Grass only stays on fairly flat ground; slopes show dirt.
							host += dirt_color.lerp(grass_color, smoothstep(0.5, 0.75, normal.y)) * w
						else:
							host += colors_tbl[id] * w
						host_w += w
				host = host / host_w if host_w > 0.0 else stone_color
				host.a = 1.0
				var amount := ore_w / total_w if total_w > 0.0 else 0.0
				var oc := colors_tbl[ore_id] if ore_id != 0 else Color.BLACK

				cell_vertex[(x - cx0) + (y - cy0) * lx + (z - cz0) * lxy] = verts.size()
				verts.append(pos)
				normals.append(normal)
				colors.append(host)
				ore.append(oc.r * amount)
				ore.append(oc.g * amount)
				ore.append(oc.b * amount)
				ore.append(amount)

	# Pass 2: a quad for every grid edge owned by this chunk that crosses the surface.
	var faces := PackedVector3Array()
	for z in range(z0, mini(z0 + CHUNK, sz)):
		for y in range(y0, mini(y0 + CHUNK, sy)):
			for x in range(x0, mini(x0 + CHUNK, sx)):
				var i := x + y * sx + z * sxy
				var solid := dens[i] >= ISO
				for a in 3:
					var nx := x + (1 if a == 0 else 0)
					var ny := y + (1 if a == 1 else 0)
					var nz := z + (1 if a == 2 else 0)
					if nx >= sx or ny >= sy or nz >= sz:
						continue
					if (dens[nx + ny * sx + nz * sxy] >= ISO) == solid:
						continue
					var q := PackedInt32Array([0, 0, 0, 0])
					var ok := true
					for k in 4:
						var o := a * 12 + k * 3
						var qx := x + cells_tbl[o]
						var qy := y + cells_tbl[o + 1]
						var qz := z + cells_tbl[o + 2]
						if qx < cx0 or qy < cy0 or qz < cz0 or qx >= cx1 or qy >= cy1 or qz >= cz1:
							ok = false
							break
						var vi := cell_vertex[(qx - cx0) + (qy - cy0) * lx + (qz - cz0) * lxy]
						if vi < 0:
							ok = false
							break
						q[k] = vi
					if not ok:
						continue
					# Solid on the near side means the surface faces +axis.
					var tri: PackedInt32Array
					if (flip_tbl[a] == 1) == solid:
						tri = PackedInt32Array([q[0], q[3], q[2], q[0], q[2], q[1]])
					else:
						tri = PackedInt32Array([q[0], q[1], q[2], q[0], q[2], q[3]])
					indices.append_array(tri)
					for t in tri:
						faces.append(verts[t])

	return {"verts": verts, "normals": normals, "colors": colors, "ore": ore, "indices": indices, "faces": faces}


# --- Helpers ----------------------------------------------------------------------

func _in_grid(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z


## Grid layout: x fastest, then y, then z (so each z slice is one contiguous block).
func _index(x: int, y: int, z: int) -> int:
	return x + y * size.x + z * size.x * size.y


## Cheap, stable pseudo-random number in [0, 1] for a grid position.
static func _hash01(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
