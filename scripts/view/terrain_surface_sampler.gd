class_name TerrainSurfaceSampler
extends RefCounted
## Shared presentation boundary used by terrain, movement, picking and overlays.
var world: GeneratedPlanet
var config: TerrainRenderConfig
var picking_mesh: TriangleMesh

func _init(planet: GeneratedPlanet, settings: TerrainRenderConfig) -> void:
	world = planet
	config = settings

func radius_at(direction: Vector3) -> float:
	return world.grid_reference.planet_radius + config.mapped_height(world.sample_height(direction))

func sample_position(direction: Vector3, offset: float = 0.0) -> Vector3:
	var p: Vector3 = PlanetFieldSampler.normalize_direction(direction)
	return p * (radius_at(p) + offset)

func sample_normal(direction: Vector3) -> Vector3:
	var p: Vector3 = direction.normalized()
	var basis: Basis = PlanetCell.tangent_basis(p)
	var epsilon: float = 0.001
	var a: Vector3 = sample_position(p + basis.x * epsilon) - sample_position(p - basis.x * epsilon)
	var b: Vector3 = sample_position(p + basis.z * epsilon) - sample_position(p - basis.z * epsilon)
	return b.cross(a).normalized()

func ray_hit(origin: Vector3, direction: Vector3) -> Vector3:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared()<0.000001: return Vector3.ZERO
	var ray: Vector3 = direction.normalized()
	if origin.length() <= radius_at(origin): return Vector3.ZERO
	if config.terrain_height_scale == 0.0:
		var b: float=origin.dot(ray)
		var discriminant: float=b*b-origin.length_squared()+world.grid_reference.planet_radius*world.grid_reference.planet_radius
		if discriminant<0 or -b-sqrt(discriminant)<0: return Vector3.ZERO
		return origin+ray*(-b-sqrt(discriminant))
	if picking_mesh == null: return Vector3.ZERO
	var frame: Basis=PlanetCell.tangent_basis(ray)
	var nearest: Vector3=Vector3.ZERO
	var distance: float=INF
	# Tiny subpixel footprint makes shared-edge hits robust; all queries use the
	# real cached render mesh, with no physics bodies or per-frame mesh rebuild.
	for x in range(-1,2):
		for y in range(-1,2):
			var probe: Vector3=(ray+(frame.x*x+frame.z*y)*0.000005).normalized()
			var hit: Dictionary=picking_mesh.intersect_ray(origin,probe)
			if not hit.is_empty() and origin.distance_squared_to(hit.position)<distance:
				nearest=hit.position; distance=origin.distance_squared_to(nearest)
	return nearest