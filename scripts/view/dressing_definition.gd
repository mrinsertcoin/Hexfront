class_name DressingDefinition
extends Resource
## Continuous-field rule for a composed environmental cluster.

enum Category { VEGETATION, ROCK, DEBRIS }
enum DetailBand { TACTICAL, REGIONAL, STRATEGIC }

@export var definition_id: String
@export var category: Category = Category.VEGETATION
@export var mesh_variants: Array[DressingMeshVariant] = []
@export var biome_affinity: PackedFloat32Array = [1,0,0,0,0]
@export_range(0.0, 1.0) var base_density: float = 0.1
@export_range(-1.0, 1.0) var moisture_response: float = 0.0
@export_range(-1.0, 1.0) var fertility_response: float = 0.0
@export_range(-1.0, 1.0) var roughness_response: float = 0.0
@export_range(-1.0, 1.0) var wetland_response: float = 0.0
@export_range(-1.0, 1.0) var height_response: float = 0.0
@export_range(0.0, 85.0) var max_slope_degrees: float = 45.0
@export_range(0.1, 8.0) var cluster_frequency: float = 1.5
@export_range(0.0, 1.0) var cluster_strength: float = 0.8
@export_range(1, 20) var minimum_cluster_instances: int = 2
@export_range(1, 20) var maximum_cluster_instances: int = 5
@export_range(0.1, 5.0) var cluster_radius: float = 2.0
@export var minimum_scale: float = 0.8
@export var maximum_scale: float = 1.2
@export var surface_offset: float = 0.015
@export var exclude_lakes: bool = true
@export var exclude_rivers: bool = true

static func create(id: String, group: Category, affinities: PackedFloat32Array,
		density: float, max_slope: float, min_count: int, max_count: int,
		radius: float, variants: Array[DressingMeshVariant]) -> DressingDefinition:
	var result:=DressingDefinition.new()
	result.definition_id=id; result.category=group; result.biome_affinity=affinities
	result.base_density=density; result.max_slope_degrees=max_slope
	result.minimum_cluster_instances=min_count; result.maximum_cluster_instances=max_count
	result.cluster_radius=radius; result.mesh_variants=variants
	return result

func validate() -> String:
	if definition_id.is_empty() or biome_affinity.size()!=5 or mesh_variants.is_empty(): return "Invalid cluster definition: "+definition_id
	if maximum_cluster_instances<minimum_cluster_instances or minimum_scale<=0 or maximum_scale<minimum_scale: return "Invalid cluster bounds: "+definition_id
	var ids:={}
	for variant: DressingMeshVariant in mesh_variants:
		if variant==null: return "Null authored variant in "+definition_id
		var error:=variant.validate()
		if not error.is_empty(): return error
		if ids.has(variant.variant_id): return "Duplicate authored variant: "+variant.variant_id
		ids[variant.variant_id]=true
	return ""
