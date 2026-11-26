class_name VoxelWorld
extends Node3D
## The destructible planet, as smooth voxel terrain.
##
## Every grid point stores a density (0-255, solid at 128 and above) and a
## material (a block id from Blocks). The surface is drawn with "surface nets":
## one vertex per grid cell the surface passes through, joined into quads.
## That gives smooth, rounded ground instead of cubes. Digging lowers density
## inside a sphere, then rebuilds the 16x16x16 chunks it touched.

const CHUNK := 16
const ISO := 128
## How quickly density ramps from air to solid across a surface. Higher = sharper.
const DENSITY_SLOPE := 100.0

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

var size: Vector3i
var density := PackedByteArray()
var material := PackedByteArray()
## Middle of the top of the base floor, in world units.
var base_position := Vector3.ZERO
## How long the last full build took, for the curious.
var last_build_ms := 0

var _chunk_counts: Vector3i
var _chunks := {} # Vector3i -> {"mesh": MeshInstance3D, "shape": CollisionShape3D}
var _material: StandardMaterial3D
var _heights := PackedFloat32Array()
var _block_colors: Array[Color] = []
var _hardness: Array[float] = []
## Per axis: cell offsets around an edge, and whether that order needs flipping.
var _edge_cells := []
var _edge_flip := []


func _init() -> void:
	_build_edge_tables()
	for d in Blocks.DEFS:
		_block_colors.append(d["color"])
		_hardness.append(d["hardness"])
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.92
	_material.metallic_specular = 0.2
	# A soft noise texture projected from all sides adds rocky detail.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.color_ramp = Gradient.new()
	tex.color_ramp.set_color(0, Color(0.72, 0.72, 0.72))
	tex.color_ramp.set_color(1, Color(1.0, 1.0, 1.0))
	_material.albedo_texture = tex
	_material.uv1_triplanar = true
	_material.uv1_scale = Vector3(0.35, 0.35, 0.35)


# --- Public API -------------------------------------------------------------------

func generate(seed_value: int) -> void:
	size = WorldConfig.WORLD_SIZE
	var n := size.x * size.y * size.z
	density = PackedByteArray()
	density.resize(n)
	density.fill(0)
	material = PackedByteArray()
	material.resize(n)
	material.fill(Blocks.AIR)
	_generate_terrain(seed_value)
	_generate_trees(seed_value)
	_generate_base()
	_seal_edges()
	var started := Time.get_ticks_msec()
	_build_all_chunks()
	last_build_ms = Time.get_ticks_msec() - started


func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z


func get_density(p: Vector3i) -> int:
	if not in_bounds(p):
		return 0
	return density[_index(p.x, p.y, p.z)]


func get_material(p: Vector3i) -> int:
	if not in_bounds(p):
		return Blocks.AIR
	return material[_index(p.x, p.y, p.z)]


func is_solid(p: Vector3i) -> bool:
	return get_density(p) >= ISO


## Ground height (where the surface is) of the column at (x, z) when generated.
func surface_height(x: int, z: int) -> float:
	return _heights[x + z * size.x]


## The material at a point on the surface, e.g. where a ray hit.
## Looks at the grid points around it and picks the most solid one.
func material_at(world_pos: Vector3) -> int:
	var base := Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z))
	var best := -1
	var best_id := Blocks.AIR
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var p := base + Vector3i(dx, dy, dz)
				if not in_bounds(p):
					continue
				var i := _index(p.x, p.y, p.z)
				if density[i] < ISO:
					continue
				# Prefer solid points close to the hit.
				var score := density[i] - int((Vector3(p) - world_pos).length() * 200.0)
				if score > best:
					best = score
					best_id = material[i]
	return best_id


## Carves a sphere out of the world. Unbreakable materials are left alone.
## Returns how much of each material was removed, in blocks (material id -> float).
func dig(center: Vector3, radius: float) -> Dictionary:
	var removed := {}
	var lo := Vector3i(floori(center.x - radius - 1), floori(center.y - radius - 1), floori(center.z - radius - 1))
	var hi := Vector3i(ceili(center.x + radius + 1), ceili(center.y + radius + 1), ceili(center.z + radius + 1))
	lo = lo.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	hi = hi.clamp(Vector3i.ZERO, size - Vector3i.ONE)
	var changed := false
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var i := _index(x, y, z)
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
					# Only the solid part counts toward what you collect.
					var amount := (minf(old, 255.0) - maxf(target, 0.0)) / 255.0
					removed[id] = removed.get(id, 0.0) + amount
	if changed:
		_rebuild_region(lo, hi)
	return removed


## Turns all chunk meshes back on after a bulk change to the arrays.
func rebuild_all() -> void:
	_build_all_chunks()


# --- Generation -------------------------------------------------------------------

func _generate_terrain(seed_value: int) -> void:
	var hills := FastNoiseLite.new()
	hills.seed = seed_value
	hills.frequency = WorldConfig.HILL_FREQUENCY
	hills.fractal_octaves = 3

	var veins := FastNoiseLite.new()
	veins.seed = seed_value + 101
	veins.frequency = WorldConfig.ORE_FREQUENCY
	veins.fractal_type = FastNoiseLite.FRACTAL_NONE

	var ore_table := _build_ore_table()
	var center := Vector2(size.x / 2.0, size.z / 2.0)
	var sx := size.x
	var sxz := size.x * size.z
	_heights.resize(sxz)

	for z in size.z:
		for x in size.x:
			var h := WorldConfig.SURFACE_Y + hills.get_noise_2d(x, z) * WorldConfig.HILL_HEIGHT
			# Flatten the ground around the base.
			var flat := clampf((Vector2(x, z).distance_to(center) - WorldConfig.FLAT_RADIUS) / 8.0, 0.0, 1.0)
			h = clampf(lerpf(WorldConfig.SURFACE_Y, h, flat), WorldConfig.CORE_ROWS + 2, size.y - 14)
			_heights[x + z * sx] = h
			var top := mini(ceili(h) + 1, size.y - 1)
			for y in top + 1:
				var d := clampi(int(ISO + (h - y) * DENSITY_SLOPE), 0, 255)
				if d == 0:
					continue
				var id: int
				var below_ground := h - y
				var depth := WorldConfig.SURFACE_Y - y
				if y < WorldConfig.CORE_ROWS:
					id = Blocks.CORE
					d = 255
				elif below_ground < 1.6:
					id = Blocks.GRASS
				elif below_ground <= WorldConfig.DIRT_DEPTH:
					id = Blocks.DIRT
				else:
					id = Blocks.STONE if depth < WorldConfig.BASALT_DEPTH else Blocks.BASALT
					var di := clampi(depth, 0, ore_table.size() - 1)
					var t := clampf(float(depth) / WorldConfig.SURFACE_Y, 0.0, 1.0)
					var threshold := lerpf(WorldConfig.ORE_THRESHOLD_TOP, WorldConfig.ORE_THRESHOLD_BOTTOM, t)
					if not ore_table[di].is_empty() and veins.get_noise_3d(x, y, z) > threshold:
						id = _pick_ore(ore_table[di], x, y, z)
				var i := x + z * sx + y * sxz
				density[i] = d
				material[i] = id


## For each depth, the ores allowed there with cumulative weights.
func _build_ore_table() -> Array:
	var table := []
	for depth in WorldConfig.SURFACE_Y + 1:
		var entries := []
		var total := 0.0
		for ore in WorldConfig.ORES:
			if depth >= ore["min_depth"] and depth <= ore["max_depth"]:
				total += ore["weight"]
				entries.append([ore["id"], total])
		for e in entries:
			e[1] /= total
		table.append(entries)
	return table


func _pick_ore(entries: Array, x: int, y: int, z: int) -> int:
	# Same choice across a 4x4x4 cell, so a vein is mostly one ore.
	var r := _hash01(x >> 2, y >> 2, z >> 2)
	for e in entries:
		if r <= e[1]:
			return e[0]
	return entries[-1][0]


func _generate_trees(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var center := Vector2(size.x / 2.0, size.z / 2.0)
	for i in WorldConfig.TREE_ATTEMPTS:
		var x := rng.randi_range(4, size.x - 5)
		var z := rng.randi_range(4, size.z - 5)
		if Vector2(x, z).distance_to(center) < WorldConfig.FLAT_RADIUS + 4.0:
			continue
		var ground := surface_height(x, z)
		var trunk := rng.randf_range(4.0, 6.5)
		var top := ground + trunk
		if top + 4 >= size.y:
			continue
		var base := Vector3(x, ground - 1.0, z)
		_add_capsule(base, Vector3(x, top, z), 0.55, Blocks.WOOD)
		var canopy := rng.randf_range(1.9, 2.6)
		_add_sphere(Vector3(x, top + 0.6, z), canopy, Blocks.LEAVES)
		_add_sphere(Vector3(x + rng.randf_range(-1, 1), top - 0.4, z + rng.randf_range(-1, 1)), canopy * 0.8, Blocks.LEAVES)


## Adds solid material in a sphere (keeps whatever is denser already).
func _add_sphere(c: Vector3, r: float, id: int) -> void:
	_add_shape(c - Vector3.ONE * (r + 1), c + Vector3.ONE * (r + 1), id,
		func(p: Vector3) -> float: return r - p.distance_to(c))


func _add_capsule(a: Vector3, b: Vector3, r: float, id: int) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * (r + 1)
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * (r + 1)
	_add_shape(lo, hi, id, func(p: Vector3) -> float:
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		return r - p.distance_to(a + ab * t))


## inside(p) returns how far inside the shape p is (negative = outside).
func _add_shape(lo_f: Vector3, hi_f: Vector3, id: int, inside: Callable) -> void:
	var lo := Vector3i(floori(lo_f.x), floori(lo_f.y), floori(lo_f.z)).clamp(Vector3i.ZERO, size - Vector3i.ONE)
	var hi := Vector3i(ceili(hi_f.x), ceili(hi_f.y), ceili(hi_f.z)).clamp(Vector3i.ZERO, size - Vector3i.ONE)
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var d := clampi(int(ISO + inside.call(Vector3(x, y, z)) * DENSITY_SLOPE), 0, 255)
				var i := _index(x, y, z)
				if d > density[i]:
					if density[i] < ISO:
						material[i] = id
					density[i] = d


func _generate_base() -> void:
	var cx := size.x / 2
	var cz := size.z / 2
	var h := float(WorldConfig.SURFACE_Y)
	var r := WorldConfig.BASE_RADIUS
	# A flat, unbreakable slab a few blocks thick.
	for y in range(int(h) - 3, int(h) + 2):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var i := _index(cx + dx, y, cz + dz)
				density[i] = clampi(int(ISO + (h - y) * DENSITY_SLOPE), 0, 255)
				material[i] = Blocks.BASE_FLOOR if density[i] > 0 else Blocks.AIR
	base_position = Vector3(cx, h, cz)


## Makes the outer walls and ceiling air so the world's edges are closed off.
func _seal_edges() -> void:
	for y in size.y:
		for z in size.z:
			for x in size.x:
				if x == 0 or z == 0 or x == size.x - 1 or z == size.z - 1 or y == size.y - 1:
					density[_index(x, y, z)] = 0


# --- Meshing ----------------------------------------------------------------------

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
	_edge_cells = cells
	_edge_flip = []
	for a in 3:
		var c: Array = cells[a]
		var p0 := Vector3(c[0]) + Vector3(0.5, 0.5, 0.5)
		var p1 := Vector3(c[1]) + Vector3(0.5, 0.5, 0.5)
		var p2 := Vector3(c[2]) + Vector3(0.5, 0.5, 0.5)
		_edge_flip.append((p1 - p0).cross(p2 - p0).dot(axes[a]) > 0.0)


func _build_all_chunks() -> void:
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	_chunk_counts = Vector3i(ceili(size.x / float(CHUNK)), ceili(size.y / float(CHUNK)), ceili(size.z / float(CHUNK)))
	for cy in _chunk_counts.y:
		for cz in _chunk_counts.z:
			for cx in _chunk_counts.x:
				var c := Vector3i(cx, cy, cz)
				var mesh := MeshInstance3D.new()
				mesh.name = "Chunk_%d_%d_%d" % [cx, cy, cz]
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				body.add_child(shape)
				mesh.add_child(body)
				add_child(mesh)
				_chunks[c] = {"mesh": mesh, "shape": shape}
				_rebuild_chunk(c)


## Rebuilds every chunk whose mesh depends on grid points in [lo, hi].
func _rebuild_region(lo: Vector3i, hi: Vector3i) -> void:
	var c_lo := (lo - Vector3i.ONE).clamp(Vector3i.ZERO, size) / CHUNK
	var c_hi := (hi + Vector3i.ONE).clamp(Vector3i.ZERO, size) / CHUNK
	for cy in range(c_lo.y, c_hi.y + 1):
		for cz in range(c_lo.z, c_hi.z + 1):
			for cx in range(c_lo.x, c_hi.x + 1):
				_rebuild_chunk(Vector3i(cx, cy, cz))


func _rebuild_chunk(c: Vector3i) -> void:
	if not _chunks.has(c):
		return
	var sx := size.x
	var sy := size.y
	var sz := size.z
	var sxz := sx * sz
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
		_set_chunk_mesh(c, PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array())
		return
	var lx := cx1 - cx0
	var lz := cz1 - cz0
	var lxz := lx * lz
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(lx * (cy1 - cy0) * lz)
	cell_vertex.fill(-1)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corner_offsets := PackedInt32Array()
	for k in 8:
		var o: Vector3i = CORNERS[k]
		corner_offsets.append(o.x + o.z * sx + o.y * sxz)
	var d := PackedInt32Array()
	d.resize(8)

	# Pass 1: one vertex per cell the surface passes through.
	for y in range(cy0, cy1):
		for z in range(cz0, cz1):
			for x in range(cx0, cx1):
				var base := x + z * sx + y * sxz
				var mask := 0
				for k in 8:
					var v := density[base + corner_offsets[k]]
					d[k] = v
					if v >= ISO:
						mask |= 1 << k
				if mask == 0 or mask == 255:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e in EDGES:
					var a: int = e[0]
					var b: int = e[1]
					if ((mask >> a) & 1) != ((mask >> b) & 1):
						var t := (ISO - 0.5 - d[a]) / float(d[b] - d[a])
						sum += Vector3(CORNERS[a]).lerp(Vector3(CORNERS[b]), t)
						count += 1
				var pos := Vector3(x, y, z) + sum / count
				var grad := Vector3(
					(d[1] + d[3] + d[5] + d[7]) - (d[0] + d[2] + d[4] + d[6]),
					(d[2] + d[3] + d[6] + d[7]) - (d[0] + d[1] + d[4] + d[5]),
					(d[4] + d[5] + d[6] + d[7]) - (d[0] + d[1] + d[2] + d[3]))
				var normal := -grad.normalized() if grad.length_squared() > 0.0 else Vector3.UP
				# Color from the most solid corner's material.
				var best := 0
				for k in range(1, 8):
					if d[k] > d[best]:
						best = k
				var id := material[base + corner_offsets[best]]
				var shade := 0.9 + 0.2 * _hash01(x, y, z)
				var col := _block_colors[id] * shade
				col.a = 1.0
				cell_vertex[(x - cx0) + (z - cz0) * lx + (y - cy0) * lxz] = verts.size()
				verts.append(pos)
				normals.append(normal)
				colors.append(col)

	# Pass 2: a quad for every grid edge owned by this chunk that crosses the surface.
	for y in range(y0, mini(y0 + CHUNK, sy)):
		for z in range(z0, mini(z0 + CHUNK, sz)):
			for x in range(x0, mini(x0 + CHUNK, sx)):
				var i := x + z * sx + y * sxz
				var solid := density[i] >= ISO
				for a in 3:
					var nx := x + (1 if a == 0 else 0)
					var ny := y + (1 if a == 1 else 0)
					var nz := z + (1 if a == 2 else 0)
					if nx >= sx or ny >= sy or nz >= sz:
						continue
					if (density[nx + nz * sx + ny * sxz] >= ISO) == solid:
						continue
					var quad := PackedInt32Array()
					var ok := true
					for off in _edge_cells[a]:
						var qx: int = x + off.x
						var qy: int = y + off.y
						var qz: int = z + off.z
						if qx < cx0 or qy < cy0 or qz < cz0 or qx >= cx1 or qy >= cy1 or qz >= cz1:
							ok = false
							break
						var vi := cell_vertex[(qx - cx0) + (qz - cz0) * lx + (qy - cy0) * lxz]
						if vi < 0:
							ok = false
							break
						quad.append(vi)
					if not ok:
						continue
					# Solid on the near side means the surface faces +axis.
					if _edge_flip[a] == solid:
						indices.append_array([quad[0], quad[3], quad[2], quad[0], quad[2], quad[1]])
					else:
						indices.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])

	_set_chunk_mesh(c, verts, normals, colors, indices)


func _set_chunk_mesh(c: Vector3i, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var entry: Dictionary = _chunks[c]
	var mi: MeshInstance3D = entry["mesh"]
	var cs: CollisionShape3D = entry["shape"]
	if indices.is_empty():
		mi.mesh = null
		cs.shape = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	mi.mesh = mesh
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for k in indices.size():
		faces[k] = verts[indices[k]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape


# --- Helpers ----------------------------------------------------------------------

func _index(x: int, y: int, z: int) -> int:
	return x + z * size.x + y * size.x * size.z


## Cheap, stable pseudo-random number in [0, 1] for a grid position.
static func _hash01(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
