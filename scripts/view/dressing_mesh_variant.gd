class_name DressingMeshVariant
extends Resource
## A reviewed production asset with explicit tactical/regional/strategic meshes.

@export var variant_id: String
@export var scene_paths: PackedStringArray
@export var mesh_node_names: PackedStringArray
@export_range(0.01, 10.0) var relative_weight: float = 1.0
@export_range(0.01, 20.0) var scale_multiplier: float = 1.0
@export var category: int = 0
@export var maximum_detail_band: int = 2
@export var casts_shadow: bool = false
@export var material_tint: Color = Color.WHITE

static func create(id: String, folder: String, source_number: String, weight: float,
		scale: float, group: int, max_band: int, shadow: bool, tint: Color) -> DressingMeshVariant:
	var result:=DressingMeshVariant.new()
	result.variant_id=id
	for lod in range(3):
		result.scene_paths.append("%s/%s_lod%d.glb" % [folder,id,lod])
		result.mesh_node_names.append("candidate_%s_lod%d" % [source_number,lod])
	result.relative_weight=weight
	result.scale_multiplier=scale
	result.category=group
	result.maximum_detail_band=max_band
	result.casts_shadow=shadow
	result.material_tint=tint
	return result

func validate() -> String:
	if variant_id.is_empty() or scene_paths.size()!=3 or mesh_node_names.size()!=3:
		return "Authored mesh variants require an ID and three explicit LOD references"
	if relative_weight<=0 or scale_multiplier<=0 or maximum_detail_band<0 or maximum_detail_band>2:
		return "Invalid authored mesh variant: "+variant_id
	for path: String in scene_paths:
		if path.is_empty(): return "Missing authored LOD path: "+variant_id
	return ""
