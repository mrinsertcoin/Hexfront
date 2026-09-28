class_name EntityView
extends MeshInstance3D
## Accepted cell paths drive displacement; in-place rig animation is independent.
signal movement_finished

var visual: UnitVisual
var moving: bool = false
var destination: Vector3
var _grid: PlanetGrid
var terrain_surface: TerrainSurfaceSampler
var _height: float
var _waypoints: PackedVector3Array = []
var _next_waypoint: int = 0
var _progress: float = 0.0
var _start_basis: Basis

func configure(wrapper: Node3D) -> void:
	visual = wrapper as UnitVisual
	if visual != null:
		visual.initialize_animation()
	set_process(false)

func sync_position(logical_position: Vector3) -> void:
	if moving and destination.is_equal_approx(logical_position):
		return
	cancel_movement()
	position = logical_position
	destination = logical_position
	basis = PlanetCell.tangent_basis(position.normalized(), -basis.z)

func play_path(path: Array[int], grid: PlanetGrid, height: float) -> void:
	cancel_movement()
	if path.size() < 2:
		return
	_grid = grid
	_height = height
	for id: int in path:
		# Use the same normalized direction as stationary placement so starting a
		# path cannot shift the model by a float-rounding step in height sampling.
		_waypoints.append(grid.get_cell(id).up)
	position = _surface_position(_waypoints[0], height)
	basis = PlanetCell.tangent_basis(_waypoints[0], -basis.z)
	destination = _surface_position(_waypoints[-1], height)
	_next_waypoint = 1
	_progress = 0.0
	_start_basis = basis
	moving = true
	if visual != null:
		visual.set_moving(true)
	set_process(true)

func _process(delta: float) -> void:
	advance_movement(delta)

func advance_movement(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0) * (maxf(0.1, visual.move_speed) if visual != null else 4.0)
	while moving and remaining > 0.0:
		var source: Vector3 = _waypoints[_next_waypoint - 1]
		var target: Vector3 = _waypoints[_next_waypoint]
		var length: float = source.angle_to(target) * (_grid.planet_radius + _height)
		var consumed: float = minf(remaining, length * (1.0 - _progress))
		_progress = minf(1.0, _progress + consumed / length)
		remaining -= consumed
		var radial: Vector3 = source.slerp(target, _progress).normalized()
		position = _surface_position(radial, _height)
		# Parallel transport the old heading and smoothly turn into this leg.
		var transport := Quaternion(source, radial)
		var old_forward: Vector3 = transport * -_start_basis.z
		var travel: Vector3 = source.cross(target).normalized().cross(radial)
		var turn: float = old_forward.signed_angle_to(travel, radial)
		var heading: Vector3 = old_forward.rotated(radial, turn * smoothstep(0.0, 0.4, _progress))
		basis = PlanetCell.tangent_basis(radial, heading)
		if _progress < 1.0:
			return
		_next_waypoint += 1
		_progress = 0.0
		_start_basis = basis
		if _next_waypoint == _waypoints.size():
			cancel_movement()
			movement_finished.emit()

func cancel_movement() -> void:
	moving = false
	_waypoints.clear()
	set_process(false)
	if visual != null:
		visual.set_moving(false)

func _surface_position(direction: Vector3, offset: float) -> Vector3:
	return terrain_surface.sample_position(direction, offset) if terrain_surface != null else _grid.sample_position(direction, offset)
