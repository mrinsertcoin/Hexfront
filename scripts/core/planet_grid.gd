class_name PlanetGrid
extends RefCounted
## Deterministic icosphere vertex dual. No scene nodes or gameplay state.
const GRID_GENERATION_VERSION: int = 1
const MAX_SUBDIVISION: int = 5
var grid_generation_version: int = GRID_GENERATION_VERSION
var subdivision_level: int
var planet_radius: float
var cells: Array[PlanetCell] = []
var adjacency: Array[Array] = []
var fingerprint: String
var _vertices: PackedVector3Array = []
var _faces: Array[Vector3i] = []
var _distance_cache: Dictionary[int, PackedInt32Array] = {}
var _spatial_nodes: Array[Vector3i] = [] # cell, left, right; balanced k-d tree
var _spatial_root: int = -1

class Traversal extends RefCounted:
	var parents: Dictionary[int, int] = {}
	var costs: Dictionary[int, int] = {}
	var order: Array[int] = []

func _init(level: int = 3, radius: float = 12.0) -> void:
	assert(level >= 0 and level <= MAX_SUBDIVISION, "Subdivision must be 0..5")
	assert(is_finite(radius) and radius > 0.0, "Radius must be positive and finite")
	subdivision_level = level
	planet_radius = radius
	_generate()

func contains(id: int) -> bool:
	return id >= 0 and id < cells.size()

func get_cell(id: int) -> PlanetCell:
	return cells[id] if contains(id) else null

func get_cell_count() -> int:
	return cells.size()

func get_neighbors(id: int) -> Array[int]:
	return cells[id].neighbor_ids if contains(id) else []

func are_neighbors(a: int, b: int) -> bool:
	return contains(a) and cells[a].neighbor_ids.has(b)

func neighbor_across_edge(cell_id: int,edge_index: int) -> int:
	if not contains(cell_id): return -1
	var cell:=cells[cell_id]
	if edge_index<0 or edge_index>=cell.polygon_vertices.size(): return -1
	var a: Vector3=cell.polygon_vertices[edge_index].normalized()
	var b: Vector3=cell.polygon_vertices[(edge_index+1)%cell.polygon_vertices.size()].normalized()
	for neighbor_id: int in cell.neighbor_ids:
		var shared:=0
		for vertex: Vector3 in cells[neighbor_id].polygon_vertices:
			var direction:=vertex.normalized()
			if direction.is_equal_approx(a) or direction.is_equal_approx(b): shared+=1
		if shared==2: return neighbor_id
	return -1

func sample_position(direction: Vector3, height_offset: float = 0.0) -> Vector3:
	# Single continuous sampling boundary for future direction-based elevation.
	return direction.normalized() * (planet_radius + height_offset)

func breadth_first(start: int, limit: int = -1, blocked: Dictionary = {},blocked_edges: Dictionary = {}) -> Traversal:
	var result := Traversal.new()
	if not contains(start):
		return result
	result.parents[start] = start
	result.costs[start] = 0
	result.order.append(start)
	var cursor: int = 0
	while cursor < result.order.size():
		var current: int = result.order[cursor]
		cursor += 1
		if limit >= 0 and result.costs[current] >= limit:
			continue
		for neighbor: int in get_neighbors(current):
			if blocked_edges.has(Vector2i(current,neighbor)): continue
			if result.parents.has(neighbor) or blocked.has(neighbor):
				continue
			result.parents[neighbor] = current
			result.costs[neighbor] = result.costs[current] + 1
			result.order.append(neighbor)
	return result

func get_cells_within_distance(start: int, distance_limit: int) -> Array[int]:
	return breadth_first(start, maxi(0, distance_limit)).order

func find_path(start: int, target: int, limit: int = -1, blocked: Dictionary = {}) -> Array[int]:
	if not contains(target) or blocked.has(target):
		return []
	return reconstruct_path(breadth_first(start, limit, blocked).parents, start, target)

func get_graph_distance(a: int, b: int) -> int:
	return distance(a, b)

func distance(a: int, b: int) -> int:
	if not contains(a) or not contains(b):
		return 2147483647
	if _distance_cache.has(b):
		return _distance_cache[b][a]
	if not _distance_cache.has(a):
		var traversal: Traversal = breadth_first(a)
		var distances := PackedInt32Array()
		distances.resize(cells.size())
		for id: int in traversal.order:
			distances[id] = traversal.costs[id]
		# Bounded cache; no all-pairs allocation at large resolutions.
		if _distance_cache.size() >= 128:
			_distance_cache.erase(_distance_cache.keys()[0])
		_distance_cache[a] = distances
	return _distance_cache[a][b]

static func reconstruct_path(parents: Dictionary[int, int], start: int, target: int) -> Array[int]:
	var path: Array[int] = []
	if not parents.has(target):
		return path
	var current: int = target
	while current != start:
		path.append(current)
		current = parents[current]
	path.append(start)
	path.reverse()
	return path

func find_cell(direction: Vector3) -> int:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return -1
	var point: Vector3 = direction.normalized()
	var best: int = int(_nearest_cell(_spatial_root,point,0,Vector2(-INF,0)).y)
	# Centroid duals are not exact Voronoi cells: verify actual polygon ownership.
	if cells[best].contains_direction(point):
		return best
	for id: int in get_neighbors(best):
		if cells[id].contains_direction(point):
			return id
	for cell: PlanetCell in cells:
		if cell.contains_direction(point):
			return cell.id
	return -1

func _build_spatial_index(ids: Array[int],axis: int=0) -> int:
	if ids.is_empty(): return -1
	ids.sort_custom(func(a: int,b: int) -> bool:
		var x: float=cells[a].up[axis]; var y: float=cells[b].up[axis]
		return x<y or (x==y and a<b))
	var middle:=ids.size()/2
	var node_index:=_spatial_nodes.size(); _spatial_nodes.append(Vector3i(ids[middle],-1,-1))
	var left:=_build_spatial_index(ids.slice(0,middle),(axis+1)%3)
	var right:=_build_spatial_index(ids.slice(middle+1),(axis+1)%3)
	_spatial_nodes[node_index]=Vector3i(ids[middle],left,right)
	return node_index

func _nearest_cell(index: int,point: Vector3,axis: int,best: Vector2) -> Vector2:
	if index<0: return best
	var node:=_spatial_nodes[index]; var direction:=cells[node.x].up
	var score:=point.dot(direction)
	if score>best.x or (score==best.x and node.x<int(best.y)): best=Vector2(score,node.x)
	var delta: float=point[axis]-direction[axis]
	best=_nearest_cell(node.y if delta<0 else node.z,point,(axis+1)%3,best)
	# Unit-sphere dot product equals 1-distance²/2. The small conservative
	# margin accommodates float normalization and preserves numeric ID ties.
	if delta*delta<=maxf(0.0,2.0-2.0*best.x)+0.000002:
		best=_nearest_cell(node.z if delta<0 else node.y,point,(axis+1)%3,best)
	return best

func _midpoint(a: int, b: int, cache: Dictionary[Vector2i, int]) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not cache.has(key):
		cache[key] = _vertices.size()
		_vertices.append((_vertices[a] + _vertices[b]).normalized())
	return cache[key]

func _generate() -> void:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	_vertices = PackedVector3Array([
		Vector3(-1,t,0), Vector3(1,t,0), Vector3(-1,-t,0), Vector3(1,-t,0),
		Vector3(0,-1,t), Vector3(0,1,t), Vector3(0,-1,-t), Vector3(0,1,-t),
		Vector3(t,0,-1), Vector3(t,0,1), Vector3(-t,0,-1), Vector3(-t,0,1)])
	for i in range(_vertices.size()):
		_vertices[i] = _vertices[i].normalized()
	_faces = [Vector3i(0,11,5), Vector3i(0,5,1), Vector3i(0,1,7), Vector3i(0,7,10), Vector3i(0,10,11),
		Vector3i(1,5,9), Vector3i(5,11,4), Vector3i(11,10,2), Vector3i(10,7,6), Vector3i(7,1,8),
		Vector3i(3,9,4), Vector3i(3,4,2), Vector3i(3,2,6), Vector3i(3,6,8), Vector3i(3,8,9),
		Vector3i(4,9,5), Vector3i(2,4,11), Vector3i(6,2,10), Vector3i(8,6,7), Vector3i(9,8,1)]
	for step in range(subdivision_level):
		var cache: Dictionary[Vector2i, int] = {}
		var next_faces: Array[Vector3i] = []
		for face: Vector3i in _faces:
			var a: int = _midpoint(face.x, face.y, cache)
			var b: int = _midpoint(face.y, face.z, cache)
			var c: int = _midpoint(face.z, face.x, cache)
			next_faces.append_array([Vector3i(face.x,a,c), Vector3i(face.y,b,a), Vector3i(face.z,c,b), Vector3i(a,b,c)])
		_faces = next_faces
	for id in range(_vertices.size()):
		var cell := PlanetCell.new()
		cell.id = id
		cell.center_direction = _vertices[id]
		cell.center_world_position = sample_position(_vertices[id])
		var frame: Basis = PlanetCell.tangent_basis(_vertices[id])
		cell.right = frame.x
		cell.up = frame.y
		cell.forward = -frame.z
		cells.append(cell)
	for face: Vector3i in _faces:
		var center: Vector3 = sample_position(_vertices[face.x] + _vertices[face.y] + _vertices[face.z])
		for id: int in [face.x, face.y, face.z]:
			cells[id].polygon_vertices.append(center)
			for other: int in [face.x, face.y, face.z]:
				if other != id and not cells[id].neighbor_ids.has(other):
					cells[id].neighbor_ids.append(other)
	for cell: PlanetCell in cells:
		cell.neighbor_ids.sort() # Explicit numeric order is the pathfinding tie break.
		adjacency.append(cell.neighbor_ids)
		cell.is_pentagon = cell.neighbor_ids.size() == 5
		var polygon: Array[Vector3] = []
		polygon.assign(cell.polygon_vertices)
		polygon.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2(a.dot(cell.forward), a.dot(cell.right)) < atan2(b.dot(cell.forward), b.dot(cell.right)))
		cell.polygon_vertices = PackedVector3Array(polygon)
		# CCW as viewed from outside; cross products point outward.
		for i in range(polygon.size()):
			cell.boundary_normals.append(polygon[i].cross(polygon[(i + 1) % polygon.size()]).normalized())
	var serialized: PackedStringArray = ["geodesic:%d:%d" % [grid_generation_version, subdivision_level]]
	for cell: PlanetCell in cells:
		var v: Vector3 = cell.center_direction
		serialized.append("%d:%d,%d,%d:%s" % [cell.id, roundi(v.x * 1000000), roundi(v.y * 1000000), roundi(v.z * 1000000), str(cell.neighbor_ids)])
	fingerprint = "|".join(serialized).sha256_text()
	var spatial_ids: Array[int]=[]
	for id in range(cells.size()): spatial_ids.append(id)
	_spatial_root=_build_spatial_index(spatial_ids)
