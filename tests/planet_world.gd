extends SceneTree
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 25:
			push_error(message)

func compare_worlds(a: GeneratedPlanet, b: GeneratedPlanet) -> void:
	check(a.generation_fingerprint == b.generation_fingerprint, "Same recipe, same fingerprint")
	check(a.regions.size() == b.regions.size(), "Same region count")
	for i in range(a.cell_world_data.size()):
		var x: PlanetWorldCellData = a.get_cell(i)
		var y: PlanetWorldCellData = b.get_cell(i)
		check(x.scalar_values() == y.scalar_values() and x.effective_moisture == y.effective_moisture and x.biome_weights == y.biome_weights and x.dominant_biome == y.dominant_biome and x.region_id == y.region_id, "Exact repeated fields, hydrology-adjusted weights, dominant biome and regions")
		check(x.hydrology.downstream_cell_id == y.hydrology.downstream_cell_id and x.hydrology.flow_accumulation == y.hydrology.flow_accumulation and x.hydrology.lake_id == y.hydrology.lake_id, "Exact repeated hydrology")
	for i in range(a.regions.size()):
		check(a.regions[i].cell_ids == b.regions[i].cell_ids and a.regions[i].center_direction.is_equal_approx(b.regions[i].center_direction), "Exact region membership and stable center")

func test_world(world: GeneratedPlanet) -> void:
	check(world.validate().is_empty(), "World validation passes")
	check(world.calculate_fingerprint() == world.generation_fingerprint, "World fingerprint matches canonical data")
	var mixed: int = 0
	for cell: PlanetWorldCellData in world.cell_world_data:
		for value: float in cell.scalar_values():
			check(is_finite(value) and value >= 0.0 and value <= 1.0, "Finite normalized scalar")
		var total: float = 0.0
		var meaningful: int = 0
		var maximum: int = 0
		for i in range(cell.biome_weights.size()):
			var weight: float = cell.biome_weights[i]
			check(is_finite(weight) and weight >= 0.0, "Finite nonnegative biome weight")
			total += weight
			meaningful += int(weight > 0.10)
			if weight > cell.biome_weights[maximum]:
				maximum = i
		check(absf(total - 1.0) < 0.000001, "Normalized weights")
		check(cell.dominant_biome == world.config.biomes[maximum].biome_id, "Dominant maximizes weight")
		mixed += int(meaningful > 1)
		var direction: Vector3 = world.grid_reference.get_cell(cell.cell_id).center_direction
		var direct: PlanetWorldCellData = world.sample_fields(direction)
		for i in range(5):
			check(absf(cell.scalar_values()[i] - direct.scalar_values()[i]) < 0.000001, "Cell data is cached continuous sample")
		check(cell.base_moisture == direct.moisture and cell.effective_moisture >= cell.base_moisture, "Hydrology preserves base moisture and only adds moisture")
	check(mixed > world.cell_world_data.size() / 4, "Many samples contain meaningful mixed biome membership")
	var covered: Dictionary = {}
	for region: PlanetRegionData in world.regions:
		check(region.cell_count >= mini(world.config.minimum_region_size, world.cell_world_data.size()), "Cleanup meets effective minimum size")
		var members: Dictionary = {}
		var height: float = 0.0
		var moisture: float = 0.0
		for id: int in region.cell_ids:
			check(not covered.has(id) and world.get_cell(id).region_id == region.id, "Exactly one region per cell")
			covered[id] = true
			members[id] = true
			height += world.get_cell(id).height
			moisture += world.get_cell(id).effective_moisture
		var queue: Array[int] = [region.cell_ids[0]]
		var visited: Dictionary = {queue[0]: true}
		var cursor: int = 0
		while cursor < queue.size():
			for neighbor: int in world.grid_reference.get_neighbors(queue[cursor]):
				if members.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
			cursor += 1
		check(visited.size() == region.cell_count, "Every region connected, including pentagons")
		check(absf(height / region.cell_count - region.average_height) < 0.000001 and absf(moisture / region.cell_count - region.average_moisture) < 0.000001, "Region averages match source samples")
		check(region.center_direction.is_normalized(), "Finite normalized region center")
	check(covered.size() == world.cell_world_data.size(), "Regions cover the globe")

func test_continuity(world: GeneratedPlanet) -> void:
	for field: String in ["height", "moisture"]:
		var near_total: float = 0.0
		var near_count: int = 0
		var far_total: float = 0.0
		for cell: PlanetCell in world.grid_reference.cells:
			var value: float = world.get_cell(cell.id).get(field)
			for neighbor: int in cell.neighbor_ids:
				near_total += absf(value - float(world.get_cell(neighbor).get(field)))
				near_count += 1
			var opposite: int = world.grid_reference.find_cell(-cell.up)
			far_total += absf(value - float(world.get_cell(opposite).get(field)))
		var near_mean: float = near_total / near_count
		var far_mean: float = far_total / world.cell_world_data.size()
		print("Continuity ", field, " neighbor_difference=", near_mean, " distant_difference=", far_mean)
		check(near_mean < far_mean * 0.8, "Neighbor fields statistically smoother than distant pairs")
	for i in range(30):
		var y: float = -0.95 + i * 1.9 / 29.0
		var a := Vector3(-1.0, y, -0.000001)
		var b := Vector3(-1.0, y, 0.000001)
		var left: PlanetWorldCellData = world.sample_fields(a)
		var right: PlanetWorldCellData = world.sample_fields(b)
		for field in range(5):
			check(absf(left.scalar_values()[field] - right.scalar_values()[field]) < 0.0001, "Continuous across conventional +/-180 longitude boundary")
		for biome in range(left.biome_weights.size()):
			check(absf(left.biome_weights[biome] - right.biome_weights[biome]) < 0.0001, "Biome blend has no longitude seam")
	for direction: Vector3 in [Vector3(0.3, 0.2, 0.7), Vector3.UP, Vector3.DOWN, Vector3.ZERO, Vector3(INF, 0, 0)]:
		var a: PlanetWorldCellData = world.sample_fields(direction)
		var b: PlanetWorldCellData = world.sample_fields(direction)
		check(a.scalar_values() == b.scalar_values() and a.biome_weights == b.biome_weights, "Repeated arbitrary/invalid direction sampling deterministic")
		check(is_finite(world.sample_height(direction)), "Invalid input has finite fallback")
	var direction := Vector3(0.3, 0.2, 0.7)
	check(world.sample_fields(direction).scalar_values() == world.sample_fields(direction * 8).scalar_values(), "Direction magnitude does not affect fields")
	var point: PlanetWorldCellData = world.sample_fields(direction)
	check(point.height == world.sample_height(direction) and point.temperature == world.sample_temperature(direction) and point.moisture == world.sample_moisture(direction) and point.fertility == world.sample_fertility(direction) and point.terrain_roughness == world.sample_terrain_roughness(direction) and point.biome_weights == world.sample_biome_weights(direction), "All continuous public APIs agree")

func _run() -> void:
	var recipe := PlanetGenerationConfig.new()
	check(recipe.validate().is_empty(), "Default config valid")
	check(recipe.to_dict().size() >= 30, "Canonical recipe includes exported settings")
	var grid := PlanetGrid.new(3)
	var original_topology: String = grid.fingerprint
	var world: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe)
	if world == null:
		quit(1)
		return
	test_world(world)
	test_continuity(world)
	compare_worlds(world, GeneratedPlanet.generate(grid, recipe, false))
	check(grid.fingerprint == original_topology, "World generation leaves topology unchanged")
	for level: int in [0, 1, 2, 4]:
		var other_grid := PlanetGrid.new(level)
		var generated: GeneratedPlanet = GeneratedPlanet.generate(other_grid, recipe, false)
		test_world(generated)
		compare_worlds(generated, GeneratedPlanet.generate(other_grid, recipe, false))
		print("World performance cells=", other_grid.get_cell_count(), " generation_ms=", generated.generation_ms, " regions=", generated.regions.size())
	for seed: int in [12345, -99, 9223372036854775807]:
		recipe.world_seed = seed
		var generated: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe, false)
		check(generated.generation_fingerprint != world.generation_fingerprint, "Different seed changes fingerprint")
		compare_worlds(generated, GeneratedPlanet.generate(grid, recipe, false))
		check(generated.get_cell(0).scalar_values() != world.get_cell(0).scalar_values(), "Different seed changes actual fields")
	# Resource serialization, full 64-bit seed preservation, and snapshot isolation.
	check(ResourceSaver.save(recipe, "user://8b_test_recipe.tres") == OK, "Recipe saves as a Resource")
	var loaded := load("user://8b_test_recipe.tres") as PlanetGenerationConfig
	check(loaded.to_dict() == recipe.to_dict() and loaded.world_seed == recipe.world_seed, "Recipe resource round trip")
	var snapshot: Dictionary = world.config.to_dict()
	recipe.biomes[0].centers[0] = 0.123
	check(world.config.to_dict() == snapshot, "Generated recipe deeply isolated from caller edits")
	# Independent channels: unrelated moisture tuning does not alter height or temperature.
	recipe = PlanetGenerationConfig.new()
	recipe.moisture_frequencies *= 1.8
	var changed: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe, false)
	for cell: PlanetWorldCellData in world.cell_world_data:
		check(cell.height == changed.get_cell(cell.cell_id).height and cell.temperature == changed.get_cell(cell.cell_id).temperature and cell.terrain_roughness == changed.get_cell(cell.cell_id).terrain_roughness, "Independent fields unaffected by moisture settings")
	check(changed.generation_fingerprint != world.generation_fingerprint, "Config changes affect world fingerprint")
	var seed_before: int = PlanetFieldSampler.derive_seed(12345, "height")
	check(seed_before == 1928025828, "SHA-256 seed protocol fixed test vector")
	PlanetFieldSampler.derive_seed(12345, "future_hydrology")
	check(seed_before == PlanetFieldSampler.derive_seed(12345, "height") and seed_before != PlanetFieldSampler.derive_seed(12345, "moisture"), "Channel seeds independent of call order")
	# Controlled climate tendency and elevation cooling.
	recipe = PlanetGenerationConfig.new()
	recipe.temperature_noise_influence = 0.0
	recipe.elevation_cooling = 0.0
	var warm: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe, false)
	recipe.elevation_cooling = 0.3
	var cool: GeneratedPlanet = GeneratedPlanet.generate(grid, recipe, false)
	var equator: float = 0.0
	var poles: float = 0.0
	for i in range(24):
		var angle: float = TAU * i / 24
		var p := Vector3(cos(angle), 0, sin(angle))
		equator += warm.sample_temperature(p)
		poles += warm.sample_temperature(Vector3(p.x * 0.1, 1.0 if i % 2 else -1.0, p.z * 0.1))
		check(cool.sample_temperature(p) < warm.sample_temperature(p), "Elevation cooling lowers temperature")
	check(equator / 24 > poles / 24 + 0.4, "Controlled equator warmer than poles")
	# Force cleanup of initially one-cell regions, including all pentagons.
	recipe = PlanetGenerationConfig.new()
	recipe.region_count = 162
	recipe.minimum_region_size = 11
	var cleaned: GeneratedPlanet = GeneratedPlanet.generate(PlanetGrid.new(2), recipe, false)
	check(cleaned.regions.size() < recipe.region_count, "Tiny regions merged")
	test_world(cleaned)
	compare_worlds(cleaned, GeneratedPlanet.generate(cleaned.grid_reference, recipe, false))
	# Deliberately zero compatibility has a deterministic valid fallback.
	recipe = PlanetGenerationConfig.new()
	for biome: BiomeDefinition in recipe.biomes:
		biome.prior = 0
	var fallback := PlanetFieldSampler.new(recipe)
	check(fallback.sample_biome_weights(Vector3.UP) == PackedFloat64Array([1,0,0,0,0]), "Zero-total biome fallback")
	recipe.height_weights = Vector3.ZERO
	check(not recipe.validate().is_empty(), "Reject zero-total height recipe")
	recipe = PlanetGenerationConfig.new()
	recipe.world_generation_version = 99
	check(not recipe.validate().is_empty(), "Unsupported version rejected")
	recipe = PlanetGenerationConfig.new()
	recipe.moisture_contrast = NAN
	check(not recipe.validate().is_empty(), "Nonfinite config rejected")
	# Validation detects corrupted generated values and region metadata.
	world.get_cell(0).moisture = NAN
	check(not world.validate().is_empty(), "Validation catches invalid fields")
	world.get_cell(0).moisture = world.sample_moisture(grid.get_cell(0).up)
	world.get_cell(0).region_id = -1
	check(not world.validate().is_empty(), "Validation catches missing region")
	print("Planet world checks complete: ", checks, "; failures=", failures)
	quit(0 if failures == 0 else 1)
