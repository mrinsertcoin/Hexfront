class_name BiomeMaterialDefinition
extends Resource
## Visual-only biome layer backed by authored PBR texture sets.
@export var biome_id: String = "Grassland"
@export var primary: TerrainTextureSet
@export var secondary: Array[TerrainTextureSet] = []
@export var tint: Color = Color.WHITE
@export var texture_world_scale: float = 2.0
@export var detail_world_scale: float = 1.35
@export var detail_strength: float = 0.2
@export var normal_strength: float = 0.32
@export var roughness_multiplier: float = 1.0

static func defaults() -> Array[BiomeMaterialDefinition]:
	var result: Array[BiomeMaterialDefinition] = []
	result.append(_biome("Grassland", "terrain_grass_lush", [], 2.0, 1.4, 0.0, 0.28, Color("#f4f8ed")))
	result.append(_biome("Forest", "terrain_forest_leaf_litter", [
		["terrain_forest_moss", 0.55], ["terrain_forest_woody_debris", 0.30],
		["overlay_forest_scattered_leaves", 0.15],
	], 2.1, 1.35, 0.24, 0.30, Color("#edf3e8")))
	result.append(_biome("Dryland", "terrain_dry_sand", [
		["terrain_dry_stony_soil", 1.0],
	], 2.3, 1.45, 0.24, 0.25, Color("#fff6e2")))
	result.append(_biome("Rocky", "terrain_rock_layered_stone", [
		["terrain_rock_coarse_gravel", 0.75], ["terrain_rock_pebble_gravel", 0.25],
	], 2.8, 1.25, 0.32, 0.38, Color("#f2f2ef")))
	result.append(_biome("Wetland", "terrain_wet_mud_stones", [
		["terrain_forest_moss", 0.72], ["terrain_rock_pebble_gravel", 0.28],
	], 1.9, 1.25, 0.22, 0.30, Color("#e8f0e7")))
	return result

static func _biome(id: String, primary_id: String, details: Array, scale: float,
		detail_scale: float, detail_amount: float, normals: float, color: Color) -> BiomeMaterialDefinition:
	var layer := BiomeMaterialDefinition.new()
	layer.biome_id = id
	layer.primary = TerrainTextureSet.from_folder(primary_id)
	for entry: Array in details:
		layer.secondary.append(TerrainTextureSet.from_folder(entry[0], entry[1]))
	layer.texture_world_scale = scale
	layer.detail_world_scale = detail_scale
	layer.detail_strength = detail_amount
	layer.normal_strength = normals
	layer.tint = color
	return layer
