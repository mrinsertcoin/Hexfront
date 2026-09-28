class_name GeneratedPlanet
extends RefCounted
## Canonical generated data and continuous query API. Treat completed worlds as read-only.
## A new recipe produces a new object; neither rendering nor GameState generates noise.
var config: PlanetGenerationConfig
var grid_reference: PlanetGrid
var cell_world_data: Array[PlanetWorldCellData] = []
var regions: Array[PlanetRegionData] = []
var hydrology: PlanetHydrology
var generation_fingerprint: String
var generation_ms: float
var validation_errors: PackedStringArray = []
var _sampler: PlanetFieldSampler
var _climate_interpolator: PlanetClimateInterpolator

static func generate(grid: PlanetGrid, recipe: PlanetGenerationConfig, log_summary: bool = true) -> GeneratedPlanet:
	var errors: PackedStringArray = recipe.validate()
	if not errors.is_empty():
		push_error("Invalid planet generation config: " + "; ".join(errors))
		return null
	var started: int = Time.get_ticks_usec()
	var planet := GeneratedPlanet.new()
	planet.grid_reference = grid
	planet.config = recipe.duplicate(true) as PlanetGenerationConfig
	planet._sampler = PlanetFieldSampler.new(planet.config)
	planet._sample_cells()
	if planet.config.hydrology.enabled:
		planet.hydrology = PlanetHydrology.generate(grid, planet.cell_world_data, planet.config.hydrology)
		planet._apply_hydrology_climate()
	planet._calculate_biomes()
	planet._climate_interpolator = PlanetClimateInterpolator.new(planet)
	planet.regions = PlanetRegionGenerator.generate(grid, planet.config, planet.cell_world_data)
	planet.validation_errors = planet.validate(false)
	if not planet.validation_errors.is_empty():
		push_error("Invalid generated planet: " + "; ".join(planet.validation_errors))
		return null
	planet.generation_fingerprint = planet.calculate_fingerprint()
	planet.generation_ms = (Time.get_ticks_usec() - started) / 1000.0
	if log_summary:
		print(planet.summary())
	return planet

func get_cell(id: int) -> PlanetWorldCellData:
	return cell_world_data[id] if grid_reference.contains(id) else null

func _sample_cells() -> void:
	for cell: PlanetCell in grid_reference.cells:
		var data: PlanetWorldCellData = _sampler.sample_fields(cell.center_direction)
		data.cell_id = cell.id
		cell_world_data.append(data)

func _calculate_biomes() -> void:
	for cell: PlanetWorldCellData in cell_world_data:
		_update_biome_weights(grid_reference.get_cell(cell.cell_id).center_direction, cell)

func _update_biome_weights(direction: Vector3, cell: PlanetWorldCellData) -> void:
	cell.biome_weights = _sampler.biome_weights(direction, cell)
	if cell.hydrology != null and cell.hydrology.wetland_potential > 0.0:
		for i in range(config.biomes.size()):
			if config.biomes[i].biome_id == "Wetland":
				cell.biome_weights[i] *= 1.0 + 2.5 * cell.hydrology.wetland_potential
				var total: float = 0.0
				for weight: float in cell.biome_weights: total += weight
				for j in range(cell.biome_weights.size()): cell.biome_weights[j] /= total
	cell.dominant_biome = _sampler.dominant_biome(cell.biome_weights)

func _apply_hydrology_climate() -> void:
	for id in range(cell_world_data.size()):
		var cell: PlanetWorldCellData = cell_world_data[id]
		cell.hydrology = hydrology.cells[id]
		cell.effective_moisture = clampf(cell.base_moisture + cell.hydrology.hydrology_moisture_bonus, 0.0, 1.0)

func sample_height(direction: Vector3) -> float:
	return _sampler.sample_height(direction)

func sample_temperature(direction: Vector3) -> float:
	return _sampler.sample_temperature(direction)

func sample_moisture(direction: Vector3) -> float:
	return _sampler.sample_moisture(direction)

func sample_fertility(direction: Vector3) -> float:
	return _sampler.sample_fertility(direction)

func sample_terrain_roughness(direction: Vector3) -> float:
	return _sampler.sample_terrain_roughness(direction)

func sample_biome_weights(direction: Vector3) -> PackedFloat64Array:
	return sample_fields(direction).biome_weights

func sample_fields(direction: Vector3) -> PlanetWorldCellData:
	var data: PlanetWorldCellData = _sampler.sample_fields(direction)
	if _climate_interpolator != null and hydrology != null:
		var climate: Vector2 = _climate_interpolator.sample(direction)
		data.hydrology = HydrologyCellData.new()
		data.hydrology.hydrology_moisture_bonus = climate.x
		data.hydrology.wetland_potential = climate.y
		data.effective_moisture = clampf(data.base_moisture + climate.x, 0.0, 1.0)
	_update_biome_weights(direction, data)
	return data # Arbitrary points have no cell/region assignment.

func validate(require_fingerprint: bool = true) -> PackedStringArray:
	var errors := PackedStringArray()
	if cell_world_data.size() != grid_reference.get_cell_count():
		errors.append("Every topology cell must have world data")
		return errors
	for id in range(cell_world_data.size()):
		var cell: PlanetWorldCellData = cell_world_data[id]
		if cell == null or cell.cell_id != id:
			errors.append("Missing or misidentified world cell")
			continue
		for value: float in cell.scalar_values():
			if not is_finite(value) or value < 0.0 or value > 1.0:
				errors.append("Invalid normalized field")
		if not is_finite(cell.base_moisture) or not is_finite(cell.effective_moisture) or cell.base_moisture < 0 or cell.base_moisture > 1 or cell.effective_moisture < 0 or cell.effective_moisture > 1:
			errors.append("Invalid moisture decomposition")
		if config.hydrology.enabled and cell.hydrology == null:
			errors.append("Missing hydrology cell data")
		if cell.biome_weights.size() != config.biomes.size():
			errors.append("Missing biome weights")
		else:
			var total: float = 0.0
			for weight: float in cell.biome_weights:
				if not is_finite(weight) or weight < 0:
					errors.append("Invalid biome weight")
				total += weight
			if not is_finite(total) or absf(total - 1.0) > 0.000001:
				errors.append("Biome weights must sum to one")
			if cell.dominant_biome != _sampler.dominant_biome(cell.biome_weights):
				errors.append("Dominant biome must maximize weight")
		if cell.region_id < 0 or cell.region_id >= regions.size():
			errors.append("Invalid region membership")
	var covered: Dictionary = {}
	for index in range(regions.size()):
		var region: PlanetRegionData = regions[index]
		if region.id != index or region.cell_ids.is_empty():
			errors.append("Invalid or empty region")
			continue
		var allowed: Dictionary = {}
		for id: int in region.cell_ids:
			if not grid_reference.contains(id) or covered.has(id):
				errors.append("Region cells must be valid and unique")
				continue
			covered[id] = true
			allowed[id] = true
			if cell_world_data[id].region_id != region.id:
				errors.append("Region metadata disagrees with cell")
		var blocked: Dictionary = {}
		for id in range(cell_world_data.size()):
			if not allowed.has(id):
				blocked[id] = true
		if grid_reference.breadth_first(region.cell_ids[0], -1, blocked).order.size() != region.cell_count:
			errors.append("Disconnected region")
		if region.cell_count < mini(config.minimum_region_size, cell_world_data.size()):
			errors.append("Undersized region after cleanup")
	if covered.size() != cell_world_data.size():
		errors.append("Regions must partition the world")
	if config.hydrology.enabled and hydrology != null:
		for id in range(cell_world_data.size()):
			var downstream: int = hydrology.cells[id].downstream_cell_id
			if downstream == id or (downstream >= 0 and not grid_reference.get_neighbors(id).has(downstream)):
				errors.append("Hydrology downstream must be a distinct neighbor")
			var seen_flow: Dictionary = {}
			var cursor: int = id
			while cursor >= 0 and not seen_flow.has(cursor):
				seen_flow[cursor] = true
				cursor = hydrology.cells[cursor].downstream_cell_id
			if cursor >= 0:
				errors.append("Hydrology flow cycle")
		for lake: LakeData in hydrology.lakes:
			if lake.cell_ids.is_empty() or lake.cell_ids.size() > config.hydrology.lake_max_cells:
				errors.append("Invalid lake size")
				continue
			var allowed: Dictionary = {}
			for id: int in lake.cell_ids:
				allowed[id] = true
				if hydrology.cells[id].lake_id != lake.id:
					errors.append("Lake membership mismatch")
			var blocked: Dictionary = {}
			for id in range(cell_world_data.size()):
				if not allowed.has(id): blocked[id] = true
			if grid_reference.breadth_first(lake.cell_ids[0], -1, blocked).order.size() != lake.cell_ids.size():
				errors.append("Disconnected lake")
			if lake.terminal != (lake.outflow_cell_id < 0):
				errors.append("Lake terminal/outlet mismatch")
	if require_fingerprint and generation_fingerprint.length() != 64:
		errors.append("Missing generation fingerprint")
	return errors

func calculate_fingerprint() -> String:
	var lines: PackedStringArray = ["hexfront-world-v%d" % config.world_generation_version,
		grid_reference.fingerprint, JSON.stringify(config.to_dict(), "", true, true)]
	for cell: PlanetWorldCellData in cell_world_data:
		var values: PackedStringArray = [str(cell.cell_id), str(cell.region_id), cell.dominant_biome]
		for value: float in cell.scalar_values():
			values.append(str(roundi(value * 1000000.0)))
		for weight: float in cell.biome_weights:
			values.append(str(roundi(weight * 1000000.0)))
		if cell.hydrology != null:
			values.append_array([str(cell.hydrology.downstream_cell_id), str(cell.hydrology.basin_id),
				str(cell.hydrology.lake_id), str(cell.hydrology.river_class), str(roundi(cell.hydrology.flow_accumulation * 1000000.0)),
				str(roundi(cell.hydrology.hydrology_moisture_bonus * 1000000.0)), str(roundi(cell.effective_moisture * 1000000.0))])
		lines.append(",".join(values))
	return "\n".join(lines).sha256_text()

func summary() -> String:
	var lines: PackedStringArray = ["Generated Planet | Grid v%d | World v%d | Seed %d" % [
		grid_reference.grid_generation_version, config.world_generation_version, config.world_seed],
		"Cells %d | Regions %d | Generation %.2f ms" % [cell_world_data.size(), regions.size(), generation_ms]]
	for field: String in PlanetWorldCellData.FIELD_NAMES:
		var minimum: float = INF
		var maximum: float = -INF
		var total: float = 0.0
		for cell: PlanetWorldCellData in cell_world_data:
			var value: float = cell.get(field)
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
			total += value
		lines.append("%s min/avg/max %.3f / %.3f / %.3f" % [field, minimum, total / cell_world_data.size(), maximum])
	var distribution: PackedStringArray = []
	for biome: BiomeDefinition in config.biomes:
		var count: int = 0
		for cell: PlanetWorldCellData in cell_world_data:
			count += int(cell.dominant_biome == biome.biome_id)
		distribution.append("%s %.1f%%" % [biome.biome_id, 100.0 * count / cell_world_data.size()])
	lines.append("Dominant biomes: " + ", ".join(distribution))
	if hydrology != null:
		var classes: PackedInt32Array = [0, 0, 0, 0]
		for segment: RiverSegment in hydrology.river_segments: classes[segment.river_class] += 1
		var terminal_lakes: int = 0
		for lake: LakeData in hydrology.lakes: terminal_lakes += int(lake.terminal)
		lines.append("Hydrology | Basins %d | Raw sinks %d | Lakes %d (%d terminal)" % [hydrology.basins.size(), hydrology.raw_sink_count, hydrology.lakes.size(), terminal_lakes])
		lines.append("Segments | Streams %d | Rivers %d | Major %d | Rejected depressions %d" % [classes[1], classes[2], classes[3], hydrology.rejected_depression_count])
	lines.append("Fingerprint: " + generation_fingerprint)
	return "\n".join(lines)
