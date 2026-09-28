extends SceneTree
var failures: int = 0
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20:
			push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for level in range(6):
		var started: int = Time.get_ticks_usec()
		var grid := PlanetGrid.new(level)
		var generation_ms: float = (Time.get_ticks_usec() - started) / 1000.0
		var count: int = 10 * int(pow(4, level)) + 2
		check(grid.get_cell_count() == count, "Exact V=10*4^n+2")
		var pentagons: int = 0
		var edges: int = 0
		for cell: PlanetCell in grid.cells:
			var degree: int = cell.neighbor_ids.size()
			pentagons += int(cell.is_pentagon)
			edges += degree
			check(degree == (5 if cell.is_pentagon else 6), "Degree 5 or 6")
			check(cell.polygon_vertices.size() == degree, "One polygon corner per incident triangle")
			check(cell.center_direction.is_normalized() and cell.center_world_position.is_equal_approx(cell.up * grid.planet_radius), "Unit direction and world center")
			check(absf(cell.forward.dot(cell.up)) < 0.00001 and absf(cell.right.dot(cell.up)) < 0.00001, "Tangent frame orthogonal")
			check(PlanetCell.tangent_basis(cell.up).determinant() > 0.999, "Right handed frame")
			var unique: Dictionary = {}
			for neighbor: int in cell.neighbor_ids:
				check(grid.contains(neighbor) and neighbor != cell.id and not unique.has(neighbor), "Valid unique adjacency")
				check(grid.are_neighbors(neighbor, cell.id), "Symmetric adjacency")
				unique[neighbor] = true
			for index in range(degree):
				var a: Vector3 = cell.polygon_vertices[index]
				var b: Vector3 = cell.polygon_vertices[(index + 1) % degree]
				check(a.is_finite() and absf(a.length() - grid.planet_radius) < 0.0001 and a.distance_to(b) > 0.00001, "Finite distinct spherical corners")
				check(a.cross(b).dot(cell.up) > 0.0, "CCW winding and center inside spherical polygon")
		check(pentagons == 12, "Exactly 12 pentagons")
		check(count - edges / 2 + 20 * int(pow(4, level)) == 2, "Euler characteristic V-E+F=2")
		check(grid.breadth_first(count - 1).order.size() == count, "Entire graph connected")
		var repeat := PlanetGrid.new(level, 27.0)
		check(repeat.fingerprint == grid.fingerprint, "Stable topology and IDs, independent of radius")
		var state := GameState.new(grid)
		var occupied: Dictionary = {}
		for entity: RefCounted in state.units.values() + state.structures.values():
			check(grid.contains(entity.cell_id) and not occupied.has(entity.cell_id), "Distinct starting entities at every subdivision")
			occupied[entity.cell_id] = true
		check(grid.distance(state.structures[100].cell_id, state.structures[101].cell_id) >= 3, "Separated starting headquarters")
		for id in range(count):
			check(repeat.cells[id].neighbor_ids == grid.cells[id].neighbor_ids and repeat.cells[id].center_direction == grid.cells[id].center_direction, "Repeated generation exact IDs and directions")
		started = Time.get_ticks_usec()
		for i in range(200):
			var id: int = (i * 37) % count
			check(grid.find_cell(grid.cells[id].center_direction) == id, "Center lookup round trip")
			var point: Vector3 = grid.cells[id].center_direction.lerp(grid.cells[id].polygon_vertices[0].normalized(), 0.9).normalized()
			check(grid.find_cell(point) == id, "Lookup respects actual dual polygon interior")
		var lookup_us: float = (Time.get_ticks_usec() - started) / 400.0
		print("Topology n=", level, " cells=", count, " pentagons=", pentagons, " generation_ms=", generation_ms, " lookup_us=", lookup_us, " fingerprint=", grid.fingerprint)
	check(PlanetGrid.new(1).get_cells_within_distance(0, 1).size() == 6, "Pentagon range includes five neighbors plus source")
	print("Planet topology checks complete: ", checks, "; failures=", failures)
	quit(0 if failures == 0 else 1)
