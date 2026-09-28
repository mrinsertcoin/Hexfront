class_name PlanetClimateInterpolator
extends RefCounted
## Piecewise-linear interpolation over the primal spherical triangles, never
## nearest-cell labels. Neighbor triangles share identical endpoint values.
var _grid: PlanetGrid
var _values: PackedVector2Array = []
var _incident: Array[Array] = []
var _inverse: Array[Basis] = []
var _hint: int = 0

func _init(planet: GeneratedPlanet) -> void:
	_grid = planet.grid_reference
	for cell: PlanetWorldCellData in planet.cell_world_data:
		_values.append(Vector2(cell.hydrology.hydrology_moisture_bonus, cell.hydrology.wetland_potential) if cell.hydrology != null else Vector2.ZERO)
		_incident.append([])
	for index in range(_grid._faces.size()):
		var f: Vector3i = _grid._faces[index]
		_inverse.append(Basis(_grid.cells[f.x].up, _grid.cells[f.y].up, _grid.cells[f.z].up).inverse())
		for id: int in [f.x, f.y, f.z]: _incident[id].append(index)

func sample(direction: Vector3) -> Vector2:
	var p: Vector3 = PlanetFieldSampler.normalize_direction(direction)
	# Walk the convex sphere graph to a local nearest vertex; the hint changes
	# speed only, never interpolation values or tie-breaking.
	while true:
		var best: int = _hint
		var score: float = _grid.cells[best].up.dot(p)
		for n: int in _grid.get_neighbors(_hint):
			var candidate: float = _grid.cells[n].up.dot(p)
			if candidate > score + 0.00000001 or (candidate == score and n < best):
				best = n
				score = candidate
		if best == _hint: break
		_hint = best
	var faces: Array = _incident[_hint]
	for index: int in faces:
		var weights: Vector3 = _inverse[index] * p
		if minf(weights.x, minf(weights.y, weights.z)) >= -0.000001:
			weights = weights.max(Vector3.ZERO)
			weights /= weights.x + weights.y + weights.z
			var f: Vector3i = _grid._faces[index]
			return _values[f.x] * weights.x + _values[f.y] * weights.y + _values[f.z] * weights.z
	return _values[_hint]
