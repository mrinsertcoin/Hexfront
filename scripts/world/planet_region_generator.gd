class_name PlanetRegionGenerator
extends RefCounted
## Farthest-point seed placement, multi-source graph growth, connected merges.
static func generate(grid: PlanetGrid, config: PlanetGenerationConfig,
		cells: Array[PlanetWorldCellData]) -> Array[PlanetRegionData]:
	var seeds: Array[int] = _choose_seeds(grid, config)
	_grow(grid, cells, seeds)
	_cleanup(grid, cells, mini(config.minimum_region_size, cells.size()))
	return _aggregate(grid, cells, config)

static func _choose_seeds(grid: PlanetGrid, config: PlanetGenerationConfig) -> Array[int]:
	var count: int = grid.get_cell_count()
	var wanted: int = mini(config.region_count, count)
	var ranks := PackedInt64Array()
	var nearest := PackedInt32Array()
	nearest.resize(count)
	nearest.fill(2147483647)
	var seed: int = PlanetFieldSampler.derive_seed(config.world_seed, "regions")
	for id in range(count):
		ranks.append(PlanetFieldSampler.derive_seed(seed, "candidate:%d" % id))
	var result: Array[int] = []
	for region in range(wanted):
		var best: int = -1
		for id in range(count):
			if nearest[id] == 0:
				continue
			if best == -1 or nearest[id] > nearest[best] or (nearest[id] == nearest[best] and ranks[id] < ranks[best]):
				best = id
		result.append(best)
		var traversal: PlanetGrid.Traversal = grid.breadth_first(best)
		for id: int in traversal.order:
			nearest[id] = mini(nearest[id], traversal.costs[id])
	return result

static func _grow(grid: PlanetGrid, cells: Array[PlanetWorldCellData], seeds: Array[int]) -> void:
	var queue: Array[int] = []
	for id in range(seeds.size()):
		cells[seeds[id]].region_id = id
		queue.append(seeds[id])
	var cursor: int = 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		for neighbor: int in grid.get_neighbors(current):
			if cells[neighbor].region_id == -1:
				cells[neighbor].region_id = cells[current].region_id
				queue.append(neighbor)

static func _cleanup(grid: PlanetGrid, cells: Array[PlanetWorldCellData], minimum: int) -> void:
	var members: Dictionary[int, Array] = {}
	for cell: PlanetWorldCellData in cells:
		if not members.has(cell.region_id):
			members[cell.region_id] = []
		members[cell.region_id].append(cell.cell_id)
	while members.size() > 1:
		var ids: Array[int] = []
		ids.assign(members.keys())
		ids.sort()
		var source: int = -1
		for id: int in ids:
			if members[id].size() < minimum and (source == -1 or members[id].size() < members[source].size()):
				source = id
		if source == -1:
			break
		var borders: Dictionary[int, int] = {}
		for cell: int in members[source]:
			for neighbor: int in grid.get_neighbors(cell):
				var other: int = cells[neighbor].region_id
				if other != source:
					borders[other] = borders.get(other, 0) + 1
		var target: int = -1
		# Explicit order: most shared edges, larger neighbor, lowest old ID.
		for id: int in ids:
			if not borders.has(id):
				continue
			if target == -1 or borders[id] > borders[target] or (borders[id] == borders[target] and members[id].size() > members[target].size()):
				target = id
		assert(target != -1, "Connected globe guarantees adjacent merge target")
		for cell: int in members[source]:
			cells[cell].region_id = target
			members[target].append(cell)
		members.erase(source)
	var surviving: Array = members.keys()
	surviving.sort()
	for cell: PlanetWorldCellData in cells:
		cell.region_id = surviving.find(cell.region_id)

static func _aggregate(grid: PlanetGrid, cells: Array[PlanetWorldCellData], config: PlanetGenerationConfig) -> Array[PlanetRegionData]:
	var result: Array[PlanetRegionData] = []
	for cell: PlanetWorldCellData in cells:
		while result.size() <= cell.region_id:
			var region := PlanetRegionData.new()
			region.id = result.size()
			result.append(region)
		result[cell.region_id].cell_ids.append(cell.cell_id)
	for region: PlanetRegionData in result:
		var weights := PackedFloat64Array()
		weights.resize(config.biomes.size())
		var direction := Vector3.ZERO
		for id: int in region.cell_ids:
			var cell: PlanetWorldCellData = cells[id]
			direction += grid.get_cell(id).up
			region.average_height += cell.height
			region.average_temperature += cell.temperature
			region.average_moisture += cell.effective_moisture
			region.average_fertility += cell.fertility
			region.average_roughness += cell.terrain_roughness
			for i in range(weights.size()):
				weights[i] += cell.biome_weights[i]
		region.center_direction = direction.normalized() if direction.length_squared() > 0.000001 else grid.get_cell(region.cell_ids[0]).up
		region.average_height /= region.cell_count
		region.average_temperature /= region.cell_count
		region.average_moisture /= region.cell_count
		region.average_fertility /= region.cell_count
		region.average_roughness /= region.cell_count
		var best: int = 0
		for i in range(1, weights.size()):
			if weights[i] > weights[best]:
				best = i
		region.dominant_biome = config.biomes[best].biome_id
	return result
