class_name TerrainRenderConfig
extends Resource
## World-space visual settings. Independent from gameplay subdivision and seed.
@export_range(2, 6) var terrain_subdivision_level: int = 5
@export_range(0.0, 4.0) var terrain_height_scale: float = 1.25
@export_range(0.0, 1.0) var height_center: float = 0.0
@export_range(0.1, 3.0) var height_contrast: float = 1.0
@export_range(0.1, 3.0) var height_exponent: float = 1.25
@export var normal_maps_enabled: bool = true
@export_range(0.0, 1.0) var slope_rock_strength: float = 0.65
@export_range(0.0, 1.0) var wetness_strength: float = 0.35
# Authored sources remain 2K. Runtime arrays retain 512 at High and 256 at
# Medium to keep first-match packing and four arrays practical on RX 590.
@export var texture_resolution: int = 512
@export var river_min_width: float = 0.035
@export var river_max_width: float = 0.16
@export var water_offset: float = 0.035
@export var river_sample_spacing: float = 0.075
@export var materials: Array[BiomeMaterialDefinition] = BiomeMaterialDefinition.defaults()

func mapped_height(height: float) -> float:
	return (pow(clampf(height, 0.0, 1.0), height_exponent) - height_center) * height_contrast * terrain_height_scale

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if terrain_subdivision_level<2 or terrain_subdivision_level>6: errors.append("Visual subdivision must be 2..6")
	if texture_resolution<4 or texture_resolution>2048: errors.append("Texture resolution must be 4..2048")
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and get(property.name) is float:
			if not is_finite(get(property.name)): errors.append("Nonfinite renderer setting: "+property.name)
	if terrain_height_scale<0 or height_contrast<=0 or height_exponent<=0: errors.append("Invalid height remapping")
	if river_sample_spacing<=0 or river_min_width<=0 or river_max_width<river_min_width: errors.append("Invalid river geometry settings")
	if water_offset<=0: errors.append("Water offset must be positive")
	return errors
