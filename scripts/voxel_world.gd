class_name VoxelWorld
extends Node3D
## The destructible planet: a grid of blocks stored in one byte array,
## drawn and collided in 16x16x16 chunks. Editing a block rebuilds only
## the chunk it sits in (plus a neighbor when it is on a chunk edge).

const CHUNK := 16

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
## Fake lighting per face so blocks read well even in shadow.
const FACE_SHADE := [0.82, 0.82, 1.0, 0.6, 0.9, 0.9]

var size: Vector3i
var data := PackedByteArray()
## Position of the middle of the top of the base pad, in world units.
var base_position := Vector3.ZERO

var _chunk_counts: Vector3i
var _chunks := {} # Vector3i -> {"mesh": MeshInstance3D, "shape": CollisionShape3D}
var _faces := [] # FACE_CORNERS triangulated with the winding Godot expects
var _material: StandardMaterial3D
var _heights := PackedInt32Array()


func _init() -> void:
	_build_face_table()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	_material.metallic_specular = 0.0


# --- Public API ---------------------------------------------------------------

func generate(seed_value: int) -> void:
	size = WorldConfig.WORLD_SIZE
	data = PackedByteArray()
	data.resize(size.x * size.y * size.z)
	data.fill(Blocks.AIR)
	_generate_terrain(seed_value)
	_generate_trees(seed_value)
	_generate_base()
	_build_all_chunks()


func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z


func get_block(p: Vector3i) -> int:
	if not in_bounds(p):
		return Blocks.AIR
	return data[_index(p.x, p.y, p.z)]


func set_block(p: Vector3i, id: int) -> void:
	if not in_bounds(p):
		return
	data[_index(p.x, p.y, p.z)] = id
	var c := Vector3i(p.x / CHUNK, p.y / CHUNK, p.z / CHUNK)
	_rebuild_chunk(c)
	# Blocks on a chunk edge also change the neighboring chunk's visible faces.
	var local := p - c * CHUNK
	if local.x == 0: _rebuild_chunk(c + Vector3i(-1, 0, 0))
	if local.x == CHUNK - 1: _rebuild_chunk(c + Vector3i(1, 0, 0))
	if local.y == 0: _rebuild_chunk(c + Vector3i(0, -1, 0))
	if local.y == CHUNK - 1: _rebuild_chunk(c + Vector3i(0, 1, 0))
	if local.z == 0: _rebuild_chunk(c + Vector3i(0, 0, -1))
	if local.z == CHUNK - 1: _rebuild_chunk(c + Vector3i(0, 0, 1))


## Height of the top solid block of the terrain column at (x, z) when generated.
func surface_height(x: int, z: int) -> int:
	return _heights[x + z * size.x]


## Steps through the grid along a ray (Amanatides & Woo).
## Returns {"hit": bool, "pos": Vector3i, "normal": Vector3i, "id": int}.
func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var dir := direction.normalized()
	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if dir[axis] > 0.0:
			t_delta[axis] = 1.0 / dir[axis]
			t_max[axis] = (floor(origin[axis]) + 1.0 - origin[axis]) * t_delta[axis]
		elif dir[axis] < 0.0:
			t_delta[axis] = -1.0 / dir[axis]
			t_max[axis] = (origin[axis] - floor(origin[axis])) * t_delta[axis]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		var id := get_block(pos)
		if id != Blocks.AIR:
			return {"hit": true, "pos": pos, "normal": normal, "id": id}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			pos.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			pos.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {"hit": false}


# --- Generation ---------------------------------------------------------------

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
	var sxz := size.x * size.z
	_heights.resize(sxz)

	for z in size.z:
		for x in size.x:
			var h := WorldConfig.SURFACE_Y + hills.get_noise_2d(x, z) * WorldConfig.HILL_HEIGHT
			# Flatten the ground around the base.
			var flat := clampf((Vector2(x + 0.5, z + 0.5).distance_to(center) - WorldConfig.FLAT_RADIUS) / 8.0, 0.0, 1.0)
			var height := clampi(roundi(lerpf(WorldConfig.SURFACE_Y, h, flat)), WorldConfig.CORE_ROWS + 1, size.y - 12)
			_heights[x + z * size.x] = height
			for y in height + 1:
				var id: int
				var below_ground := height - y
				var depth := WorldConfig.SURFACE_Y - y
				if y < WorldConfig.CORE_ROWS:
					id = Blocks.CORE
				elif below_ground == 0:
					id = Blocks.GRASS
				elif below_ground <= WorldConfig.DIRT_DEPTH:
					id = Blocks.DIRT
				else:
					id = Blocks.STONE if depth < WorldConfig.BASALT_DEPTH else Blocks.BASALT
					var d := clampi(depth, 0, ore_table.size() - 1)
					var t := clampf(float(depth) / WorldConfig.SURFACE_Y, 0.0, 1.0)
					var threshold := lerpf(WorldConfig.ORE_THRESHOLD_TOP, WorldConfig.ORE_THRESHOLD_BOTTOM, t)
					if not ore_table[d].is_empty() and veins.get_noise_3d(x, y, z) > threshold:
						id = _pick_ore(ore_table[d], x, y, z)
				data[x + z * size.x + y * sxz] = id


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
		var x := rng.randi_range(3, size.x - 4)
		var z := rng.randi_range(3, size.z - 4)
		if Vector2(x, z).distance_to(center) < WorldConfig.FLAT_RADIUS + 4.0:
			continue
		var ground := surface_height(x, z)
		if get_block(Vector3i(x, ground, z)) != Blocks.GRASS:
			continue
		var trunk := rng.randi_range(4, 6)
		var top := ground + trunk
		if top + 2 >= size.y:
			continue
		for dy in range(-2, 2):
			var r := 2 if dy < 0 else 1
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if absi(dx) == r and absi(dz) == r and rng.randf() < 0.6:
						continue
					var p := Vector3i(x + dx, top + dy, z + dz)
					if get_block(p) == Blocks.AIR and in_bounds(p):
						data[_index(p.x, p.y, p.z)] = Blocks.LEAVES
		for y in range(ground + 1, top + 1):
			data[_index(x, y, z)] = Blocks.WOOD


func _generate_base() -> void:
	var cx := size.x / 2
	var cz := size.z / 2
	var y := surface_height(cx, cz)
	for dx in range(-WorldConfig.BASE_RADIUS, WorldConfig.BASE_RADIUS):
		for dz in range(-WorldConfig.BASE_RADIUS, WorldConfig.BASE_RADIUS):
			data[_index(cx + dx, y, cz + dz)] = Blocks.BASE_FLOOR
	base_position = Vector3(cx, y + 1, cz)


# --- Meshing ------------------------------------------------------------------

func _build_face_table() -> void:
	# Godot treats clockwise triangles as front faces. Fix each quad's order
	# so its triangles face outward along the face normal.
	_faces.clear()
	for f in 6:
		var c: Array = FACE_CORNERS[f].duplicate()
		var n := Vector3(DIRS[f])
		if (c[1] - c[0]).cross(c[2] - c[0]).dot(n) > 0.0:
			c.reverse()
		_faces.append([c[0], c[1], c[2], c[0], c[2], c[3]])


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


func _rebuild_chunk(c: Vector3i) -> void:
	if not _chunks.has(c):
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var sx := size.x
	var sy := size.y
	var sz := size.z
	var sxz := sx * sz
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	var z0 := c.z * CHUNK
	var block_colors := []
	for d in Blocks.DEFS:
		block_colors.append(d["color"])

	for y in range(y0, mini(y0 + CHUNK, sy)):
		for z in range(z0, mini(z0 + CHUNK, sz)):
			for x in range(x0, mini(x0 + CHUNK, sx)):
				var id := data[x + z * sx + y * sxz]
				if id == Blocks.AIR:
					continue
				var jitter := 0.9 + 0.2 * _hash01(x, y, z)
				var p := Vector3(x, y, z)
				for f in 6:
					var d: Vector3i = DIRS[f]
					var nx := x + d.x
					var ny := y + d.y
					var nz := z + d.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < sx and ny < sy and nz < sz:
						if data[nx + nz * sx + ny * sxz] != Blocks.AIR:
							continue
					elif ny < 0:
						continue
					var col: Color = block_colors[id] * (FACE_SHADE[f] * jitter)
					col.a = 1.0
					var n := Vector3(d)
					for corner in _faces[f]:
						verts.append(p + corner)
						normals.append(n)
						colors.append(col)

	var entry: Dictionary = _chunks[c]
	var mi: MeshInstance3D = entry["mesh"]
	var cs: CollisionShape3D = entry["shape"]
	if verts.is_empty():
		mi.mesh = null
		cs.shape = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	mi.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	cs.shape = shape


# --- Helpers ------------------------------------------------------------------

func _index(x: int, y: int, z: int) -> int:
	return x + z * size.x + y * size.x * size.z


## Cheap, stable pseudo-random number in [0, 1] for a grid position.
static func _hash01(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0
