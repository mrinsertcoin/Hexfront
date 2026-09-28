class_name PlanetSurface
extends RefCounted
## Presentation geometry only. Logical polygon corners remain in PlanetGrid.
static func polygon_mesh(cell: PlanetCell, radius: float, terrain: TerrainSurfaceSampler = null) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(cell.polygon_vertices.size()):
		_triangle(surface, cell.up, cell.polygon_vertices[i].normalized(),
			cell.polygon_vertices[(i + 1) % cell.polygon_vertices.size()].normalized(), radius, terrain)
	return surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, radius: float, terrain: TerrainSurfaceSampler) -> void:
	if maxf(a.angle_to(b), maxf(b.angle_to(c), c.angle_to(a))) > (0.025 if terrain != null else 0.08):
		var ab: Vector3 = (a + b).normalized()
		var bc: Vector3 = (b + c).normalized()
		var ca: Vector3 = (c + a).normalized()
		_triangle(surface, a, ab, ca, radius, terrain)
		_triangle(surface, ab, b, bc, radius, terrain)
		_triangle(surface, ca, bc, c, radius, terrain)
		_triangle(surface, ab, bc, ca, radius, terrain)
		return
	# Godot front faces are clockwise; logical polygons are outward CCW.
	for vertex: Vector3 in [a, c, b]:
		surface.set_normal(vertex)
		surface.add_vertex(terrain.sample_position(vertex, radius - terrain.world.grid_reference.planet_radius) if terrain != null else vertex * radius)

static func debug_mesh(grid: PlanetGrid, centers: bool = false, pentagons: bool = false, terrain: TerrainSurfaceSampler = null) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	for cell: PlanetCell in grid.cells:
		if pentagons and not cell.is_pentagon:
			continue
		if centers:
			for axis: Vector3 in [cell.right, cell.forward]:
				surface.add_vertex(_position(grid, terrain, cell.up - axis * 0.008, 0.065))
				surface.add_vertex(_position(grid, terrain, cell.up + axis * 0.008, 0.065))
			continue
		for i in range(cell.polygon_vertices.size()):
			var a: Vector3 = cell.polygon_vertices[i].normalized()
			var b: Vector3 = cell.polygon_vertices[(i + 1) % cell.polygon_vertices.size()].normalized()
			var steps: int = maxi(1, ceili(a.angle_to(b) / 0.04))
			for step in range(steps):
				surface.add_vertex(_position(grid, terrain, a.slerp(b, float(step) / steps), 0.065))
				surface.add_vertex(_position(grid, terrain, a.slerp(b, float(step + 1) / steps), 0.065))
	return surface.commit()

static func _position(grid: PlanetGrid, terrain: TerrainSurfaceSampler, direction: Vector3, offset: float) -> Vector3:
	return terrain.sample_position(direction, offset) if terrain != null else grid.sample_position(direction, offset)