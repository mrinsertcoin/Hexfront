extends SceneTree
var failures: int = 0
var checks: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 30: push_error(message)

func controlled_cells(grid: PlanetGrid, root: int = 0) -> Array[PlanetWorldCellData]:
	var traversal = grid.breadth_first(root)
	var result: Array[PlanetWorldCellData] = []
	var max_distance: int = 1
	for id: int in traversal.order: max_distance = maxi(max_distance, traversal.costs[id])
	for id in range(grid.get_cell_count()):
		var cell := PlanetWorldCellData.new()
		cell.cell_id = id
		cell.height = float(traversal.costs[id]) / max_distance
		cell.moisture = 0.4
		cell.base_moisture = 0.4
		cell.effective_moisture = 0.4
		cell.temperature = 0.5
		cell.fertility = 0.5
		cell.terrain_roughness = 0.2
		result.append(cell)
	return result

func validate_network(grid: PlanetGrid, hydro: PlanetHydrology) -> void:
	for cell: HydrologyCellData in hydro.cells:
		if cell.downstream_cell_id >= 0:
			check(cell.downstream_cell_id != cell.cell_id and grid.get_neighbors(cell.cell_id).has(cell.downstream_cell_id), "Downstream is a distinct graph neighbor")
		var seen: Dictionary = {}
		var cursor: int = cell.cell_id
		while cursor >= 0 and not seen.has(cursor):
			seen[cursor] = true
			cursor = hydro.cells[cursor].downstream_cell_id
		check(cursor < 0, "Every flow path terminates without a cycle")
		check(is_finite(cell.flow_accumulation) and cell.flow_accumulation >= cell.runoff_input, "Accumulation includes local runoff")
	for lake: LakeData in hydro.lakes:
		check(lake.cell_ids.size() >= 1 and lake.cell_ids.size() <= hydro._settings.lake_max_cells, "Lake obeys maximum size")
		var allowed: Dictionary = {}
		for id: int in lake.cell_ids: allowed[id] = true
		var blocked: Dictionary = {}
		for id in range(grid.get_cell_count()):
			if not allowed.has(id): blocked[id] = true
		check(grid.breadth_first(lake.cell_ids[0], -1, blocked).order.size() == lake.cell_ids.size(), "Lake cells are connected")
		check(lake.terminal == (lake.outflow_cell_id < 0), "Lake outlet matches terminal status")

func _run() -> void:
	var settings := HydrologySettings.new()
	check(settings.validate().is_empty(), "Default hydrology config valid")
	var grid := PlanetGrid.new(0)
	var fields := controlled_cells(grid)
	var hydro := PlanetHydrology.generate(grid, fields, settings)
	validate_network(grid, hydro)
	for id in range(1, grid.get_cell_count()):
		check(fields[hydro.cells[id].raw_downstream_cell_id].height < fields[id].height, "Controlled slope raw flow goes downhill")
	check(hydro.cells[0].downstream_cell_id < 0, "Closed globe has intentional terminal sink")
	check(not hydro.lakes.is_empty() and hydro.lakes[-1].terminal, "No-ocean globe creates terminal lake")
	# Two graph branches contribute exactly once at their confluence/root.
	var expected_total: float = 0.0
	for cell: HydrologyCellData in hydro.cells: expected_total += cell.runoff_input
	check(absf(hydro.cells[0].flow_accumulation - expected_total) < 0.000001, "Confluence accumulation includes every branch exactly once")
	# Raw basins expose deterministic spill crossings.
	for basin: DrainageBasinData in hydro.basins:
		if hydro.basins.size() > 1:
			check(basin.spill_inside_cell_id >= 0 and grid.get_neighbors(basin.spill_inside_cell_id).has(basin.spill_outside_cell_id), "Basin spill is a boundary edge")
	var repeat := PlanetHydrology.generate(grid, controlled_cells(grid), settings)
	for id in range(grid.get_cell_count()):
		check(hydro.cells[id].downstream_cell_id == repeat.cells[id].downstream_cell_id and hydro.cells[id].flow_accumulation == repeat.cells[id].flow_accumulation and hydro.cells[id].lake_id == repeat.cells[id].lake_id, "Controlled hydrology deterministic")
	# Maximum-size policy rejects/breaches large depressions; it never emits an oversized lake.
	settings = settings.duplicate(true)
	settings.lake_max_cells = 2
	settings.lake_min_depth = 0.00001
	var limited := PlanetHydrology.generate(PlanetGrid.new(2), controlled_cells(PlanetGrid.new(2)), settings)
	for lake: LakeData in limited.lakes: check(lake.cell_ids.size() <= 2, "Oversized depression does not become a giant lake")
	# Ocean sinks are explicit and work without an external map edge.
	settings = HydrologySettings.new()
	settings.enable_oceans = true
	settings.sea_level = 0.2
	var ocean := PlanetHydrology.generate(grid, controlled_cells(grid), settings)
	var oceans: int = 0
	for cell: HydrologyCellData in ocean.cells: oceans += int(cell.surface_water_type == HydrologyCellData.SurfaceWater.OCEAN)
	check(oceans > 0 and ocean.lakes.filter(func(l: LakeData) -> bool: return l.terminal).is_empty(), "Enabled oceans are terminal sinks")
	# Real worlds cover pentagons, size scaling, moisture/biome integration, and seed determinism.
	var recipe := PlanetGenerationConfig.new()
	var world3 := GeneratedPlanet.generate(PlanetGrid.new(3), recipe, false)
	var world3b := GeneratedPlanet.generate(PlanetGrid.new(3), recipe, false)
	check(world3.generation_fingerprint == world3b.generation_fingerprint, "Same seed reproduces complete hydrology fingerprint")
	validate_network(world3.grid_reference, world3.hydrology)
	var influenced: int = 0
	var wetland_changed: int = 0
	for id in range(world3.cell_world_data.size()):
		var cell: PlanetWorldCellData = world3.get_cell(id)
		influenced += int(cell.effective_moisture > cell.base_moisture)
		wetland_changed += int(cell.hydrology.wetland_potential > 0 and cell.biome_weights[4] > 0)
		if world3.grid_reference.get_neighbors(id).size() == 5:
			check(cell.hydrology.downstream_cell_id < 0 or world3.grid_reference.get_neighbors(id).has(cell.hydrology.downstream_cell_id), "Pentagon flow uses actual neighbors")
	check(influenced > 0 and wetland_changed > 0, "Hydrology moisture feeds effective moisture and wetland biome weights")
	recipe.world_seed += 1
	var changed := GeneratedPlanet.generate(PlanetGrid.new(3), recipe, false)
	check(changed.generation_fingerprint != world3.generation_fingerprint, "Different seed changes hydrology world")
	var world4 := GeneratedPlanet.generate(PlanetGrid.new(4), PlanetGenerationConfig.new(), false)
	validate_network(world4.grid_reference, world4.hydrology)
	var density3: float = float(world3.hydrology.river_segments.size()) / world3.cell_world_data.size()
	var density4: float = float(world4.hydrology.river_segments.size()) / world4.cell_world_data.size()
	check(density3 > 0.01 and density4 > 0.01 and maxf(density3, density4) / minf(density3, density4) < 2.5, "Normalized thresholds scale across planet sizes")
	print("Hydrology checks complete: ", checks, "; failures=", failures, "; density3=", density3, "; density4=", density4)
	quit(0 if failures == 0 else 1)
