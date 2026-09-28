class_name PlanetHydrology
extends RefCounted
## Deterministic graph hydrology. Priority flood uses ocean cells as roots when
## enabled; otherwise the global low point is the intentional closed-globe sink.

var cells: Array[HydrologyCellData] = []
var basins: Array[DrainageBasinData] = []
var lakes: Array[LakeData] = []
var river_segments: Array[RiverSegment] = []
var raw_sink_count: int = 0
var rejected_depression_count: int = 0
var terminal_cell_ids: PackedInt32Array = []
var _grid: PlanetGrid
var _world_cells: Array[PlanetWorldCellData]
var _settings: HydrologySettings
var _flood_order: PackedInt32Array = []

static func generate(grid: PlanetGrid, world_cells: Array[PlanetWorldCellData], settings: HydrologySettings) -> PlanetHydrology:
	var result := PlanetHydrology.new()
	result._grid = grid
	result._world_cells = world_cells
	result._settings = settings
	for id in range(grid.get_cell_count()):
		var data := HydrologyCellData.new()
		data.cell_id = id
		data.filled_height = world_cells[id].height
		data.runoff_input = settings.runoff_base + settings.moisture_runoff_influence * world_cells[id].base_moisture
		result.cells.append(data)
	result._raw_flow_and_basins()
	result._priority_flood()
	result._accumulate()
	result._create_lakes()
	result._classify_rivers()
	result._moisture_influence()
	return result

func _raw_flow_and_basins() -> void:
	var sink_for: PackedInt32Array = []
	sink_for.resize(cells.size())
	sink_for.fill(-1)
	for id in range(cells.size()):
		var best: int = -1
		var best_height: float = _world_cells[id].height
		for neighbor: int in _grid.get_neighbors(id):
			var h: float = _world_cells[neighbor].height
			if h < best_height - 0.000000001 or (is_equal_approx(h, best_height) and best >= 0 and neighbor < best):
				best = neighbor
				best_height = h
		cells[id].raw_downstream_cell_id = best
	var sinks: Array[int] = []
	for id in range(cells.size()):
		var cursor: int = id
		while cells[cursor].raw_downstream_cell_id >= 0:
			cursor = cells[cursor].raw_downstream_cell_id
		sink_for[id] = cursor
		if not sinks.has(cursor):
			sinks.append(cursor)
	sinks.sort()
	raw_sink_count = sinks.size()
	var basin_by_sink: Dictionary = {}
	for sink: int in sinks:
		var basin := DrainageBasinData.new()
		basin.id = basins.size()
		basin.sink_cell_id = sink
		basins.append(basin)
		basin_by_sink[sink] = basin.id
	for id in range(cells.size()):
		var basin_id: int = basin_by_sink[sink_for[id]]
		cells[id].basin_id = basin_id
		basins[basin_id].cell_ids.append(id)
	for basin: DrainageBasinData in basins:
		for id: int in basin.cell_ids:
			for neighbor: int in _grid.get_neighbors(id):
				if cells[neighbor].basin_id == basin.id:
					continue
				var spill: float = maxf(_world_cells[id].height, _world_cells[neighbor].height)
				var earlier: bool = id < basin.spill_inside_cell_id or (id == basin.spill_inside_cell_id and neighbor < basin.spill_outside_cell_id)
				if spill < basin.spill_height - 0.000000001 or (is_equal_approx(spill, basin.spill_height) and earlier):
					basin.spill_height = spill
					basin.spill_inside_cell_id = id
					basin.spill_outside_cell_id = neighbor

func _priority_flood() -> void:
	var roots: Array[int] = []
	if _settings.enable_oceans:
		for id in range(cells.size()):
			if _world_cells[id].height <= _settings.sea_level:
				roots.append(id)
	if roots.is_empty():
		var lowest: int = 0
		for id in range(1, cells.size()):
			if _world_cells[id].height < _world_cells[lowest].height or (is_equal_approx(_world_cells[id].height, _world_cells[lowest].height) and id < lowest):
				lowest = id
		roots.append(lowest)
	terminal_cell_ids = PackedInt32Array(roots)
	var visited := PackedByteArray()
	visited.resize(cells.size())
	var heap: Array[Array] = []
	for root: int in roots:
		visited[root] = 1
		cells[root].downstream_cell_id = -1
		_heap_push(heap, [_world_cells[root].height, root])
	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var id: int = entry[1]
		_flood_order.append(id)
		for neighbor: int in _grid.get_neighbors(id):
			if visited[neighbor]:
				continue
			visited[neighbor] = 1
			cells[neighbor].filled_height = maxf(_world_cells[neighbor].height, cells[id].filled_height)
			cells[neighbor].downstream_cell_id = id
			_heap_push(heap, [cells[neighbor].filled_height, neighbor])

func _accumulate() -> void:
	var total: float = 0.0
	for cell: HydrologyCellData in cells:
		cell.flow_accumulation = cell.runoff_input
		total += cell.runoff_input
	for index in range(_flood_order.size() - 1, -1, -1):
		var id: int = _flood_order[index]
		var downstream: int = cells[id].downstream_cell_id
		if downstream >= 0:
			cells[downstream].flow_accumulation += cells[id].flow_accumulation
	for cell: HydrologyCellData in cells:
		cell.normalized_accumulation = cell.flow_accumulation / total

func _create_lakes() -> void:
	var candidates: Dictionary = {}
	for id in range(cells.size()):
		if cells[id].filled_height - _world_cells[id].height >= _settings.lake_min_depth:
			candidates[id] = true
	var seen: Dictionary = {}
	for start: int in candidates:
		if seen.has(start):
			continue
		var component := PackedInt32Array()
		var queue: Array[int] = [start]
		seen[start] = true
		while not queue.is_empty():
			var id: int = queue.pop_front()
			component.append(id)
			for neighbor: int in _grid.get_neighbors(id):
				if candidates.has(neighbor) and not seen.has(neighbor):
					seen[neighbor] = true
					queue.append(neighbor)
		_add_lake_if_valid(component, false)
	if not _settings.enable_oceans:
		var root: int = terminal_cell_ids[0]
		if cells[root].lake_id < 0:
			var terminal_members := PackedInt32Array([root])
			var neighbors: PackedInt32Array = _grid.get_neighbors(root)
			var ordered: Array[int] = []
			for neighbor: int in neighbors: ordered.append(neighbor)
			ordered.sort_custom(func(a: int, b: int) -> bool:
				return _world_cells[a].height < _world_cells[b].height or (is_equal_approx(_world_cells[a].height, _world_cells[b].height) and a < b))
			for id: int in ordered:
				if terminal_members.size() >= _settings.lake_min_cells:
					break
				terminal_members.append(id)
			_add_lake(terminal_members, true)
	else:
		for id: int in terminal_cell_ids:
			cells[id].surface_water_type = HydrologyCellData.SurfaceWater.OCEAN

func _add_lake_if_valid(members: PackedInt32Array, terminal: bool) -> void:
	var catchment: float = 0.0
	for id: int in members:
		catchment = maxf(catchment, cells[id].normalized_accumulation)
	if members.size() < _settings.lake_min_cells or members.size() > _settings.lake_max_cells or catchment < _settings.lake_min_catchment:
		rejected_depression_count += 1
		return
	_add_lake(members, terminal)

func _add_lake(members: PackedInt32Array, terminal: bool) -> void:
	var lake := LakeData.new()
	lake.id = lakes.size()
	lake.cell_ids = members
	lake.terminal = terminal
	var member_set: Dictionary = {}
	for id: int in members:
		member_set[id] = true
		cells[id].surface_water_type = HydrologyCellData.SurfaceWater.LAKE
		cells[id].lake_id = lake.id
		lake.surface_height = maxf(lake.surface_height, cells[id].filled_height)
		lake.catchment_size = maxf(lake.catchment_size, cells[id].normalized_accumulation)
		lake.center_direction += _grid.get_cell(id).center_direction
	if not terminal:
		var best_pair: Array = [INF, 2147483647, 2147483647]
		for id: int in members:
			var downstream: int = cells[id].downstream_cell_id
			if downstream >= 0 and not member_set.has(downstream):
				var pair: Array = [cells[id].filled_height, id, downstream]
				if pair[0] < best_pair[0] or (is_equal_approx(pair[0], best_pair[0]) and (pair[1] < best_pair[1] or (pair[1] == best_pair[1] and pair[2] < best_pair[2]))):
					best_pair = pair
					lake.outflow_cell_id = downstream
	for id in range(cells.size()):
		if not member_set.has(id) and member_set.has(cells[id].downstream_cell_id):
			lake.inflow_cells.append(id)
	lake.center_direction = lake.center_direction.normalized()
	lakes.append(lake)

func _classify_rivers() -> void:
	var max_order := PackedInt32Array()
	var max_count := PackedInt32Array()
	max_order.resize(cells.size())
	max_count.resize(cells.size())
	for index in range(_flood_order.size() - 1, -1, -1):
		var id: int = _flood_order[index]
		var order: int = 1 if max_order[id] == 0 else max_order[id] + int(max_count[id] >= 2)
		cells[id].stream_order = order
		var downstream: int = cells[id].downstream_cell_id
		if downstream >= 0:
			if order > max_order[downstream]:
				max_order[downstream] = order
				max_count[downstream] = 1
			elif order == max_order[downstream]:
				max_count[downstream] += 1
		var a: float = cells[id].normalized_accumulation
		if a >= _settings.major_river_threshold:
			cells[id].river_class = HydrologyCellData.RiverClass.MAJOR_RIVER
		elif a >= _settings.river_threshold:
			cells[id].river_class = HydrologyCellData.RiverClass.RIVER
		elif a >= _settings.stream_threshold:
			cells[id].river_class = HydrologyCellData.RiverClass.STREAM
		cells[id].river_width_factor = clampf(sqrt(a / _settings.major_river_threshold), 0.0, 1.0)
		if cells[id].river_class > 0 and downstream >= 0 and cells[id].surface_water_type != HydrologyCellData.SurfaceWater.OCEAN:
			var segment := RiverSegment.new()
			segment.from_cell_id = id
			segment.to_cell_id = downstream
			segment.accumulation = a
			segment.river_class = cells[id].river_class
			segment.stream_order = order
			segment.width_factor = cells[id].river_width_factor
			river_segments.append(segment)

func _moisture_influence() -> void:
	var strengths: Dictionary = {}
	for cell: HydrologyCellData in cells:
		if cell.surface_water_type == HydrologyCellData.SurfaceWater.LAKE:
			strengths[cell.cell_id] = _settings.lake_moisture_strength
		elif cell.surface_water_type == HydrologyCellData.SurfaceWater.OCEAN:
			strengths[cell.cell_id] = _settings.ocean_moisture_strength
		elif cell.river_class > 0:
			strengths[cell.cell_id] = _settings.river_moisture_strength * cell.river_width_factor
	for source: int in strengths:
		var visits = _grid.breadth_first(source, _settings.wetland_radius)
		for id: int in visits.order:
			var distance: int = visits.costs[id]
			var falloff: float = 1.0 - float(distance) / float(_settings.wetland_radius + 1)
			cells[id].hydrology_moisture_bonus = maxf(cells[id].hydrology_moisture_bonus, strengths[source] * falloff)
	for id in range(cells.size()):
		var slope: float = 0.0
		for neighbor: int in _grid.get_neighbors(id):
			slope = maxf(slope, absf(_world_cells[id].height - _world_cells[neighbor].height))
		var wet: float = clampf(_world_cells[id].base_moisture + cells[id].hydrology_moisture_bonus, 0.0, 1.0)
		cells[id].wetland_potential = clampf(wet * (1.0 - minf(1.0, slope * 5.0)) * (0.35 + 0.65 * cells[id].river_width_factor), 0.0, 1.0)

func _heap_push(heap: Array[Array], value: Array) -> void:
	heap.append(value)
	var index: int = heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) >> 1
		if not _entry_less(heap[index], heap[parent]): break
		var swap: Array = heap[parent]; heap[parent] = heap[index]; heap[index] = swap
		index = parent

func _heap_pop(heap: Array[Array]) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var index: int = 0
		while true:
			var left: int = index * 2 + 1
			if left >= heap.size(): break
			var right: int = left + 1
			var child: int = right if right < heap.size() and _entry_less(heap[right], heap[left]) else left
			if not _entry_less(heap[child], heap[index]): break
			var swap: Array = heap[index]; heap[index] = heap[child]; heap[child] = swap
			index = child
	return result

func _entry_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (is_equal_approx(a[0], b[0]) and a[1] < b[1])
