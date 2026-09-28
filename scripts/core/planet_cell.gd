class_name PlanetCell
extends RefCounted
## Immutable after generation. Future world fields belong in separate ID-keyed data.
var id: int
var center_direction: Vector3
var center_world_position: Vector3
var neighbor_ids: Array[int] = []
var polygon_vertices: PackedVector3Array = []
var boundary_normals: PackedVector3Array = []
var is_pentagon: bool
var up: Vector3
var forward: Vector3
var right: Vector3

static func tangent_basis(normal: Vector3, heading: Vector3 = Vector3.ZERO) -> Basis:
	var radial: Vector3 = normal.normalized()
	var tangent: Vector3 = heading - radial * heading.dot(radial)
	if tangent.length_squared() < 0.000001:
		# Choose the least aligned Cartesian axis; no privileged gameplay poles.
		var axis: Vector3 = Vector3.RIGHT
		if absf(radial.y) < absf(radial.x):
			axis = Vector3.UP
		if absf(radial.z) < absf(radial.dot(axis)):
			axis = Vector3.BACK
		tangent = axis - radial * axis.dot(radial)
	var front: Vector3 = tangent.normalized()
	return Basis(front.cross(radial).normalized(), radial, -front)

func contains_direction(direction: Vector3) -> bool:
	for normal: Vector3 in boundary_normals:
		if normal.dot(direction) < -0.000001:
			return false
	return true
