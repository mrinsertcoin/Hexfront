class_name HydrologySettings
extends Resource

const VERSION: int = 1
@export var enabled: bool = true
@export var generation_version: int = VERSION
@export_range(0.0, 1.0) var runoff_base: float = 0.25
@export_range(0.0, 2.0) var moisture_runoff_influence: float = 0.75
@export_range(0.0, 1.0) var stream_threshold: float = 0.006
@export_range(0.0, 1.0) var river_threshold: float = 0.020
@export_range(0.0, 1.0) var major_river_threshold: float = 0.060
@export var lake_min_cells: int = 2
@export var lake_max_cells: int = 12
@export_range(0.0, 1.0) var lake_min_catchment: float = 0.004
@export_range(0.0, 1.0) var lake_min_depth: float = 0.012
@export var wetland_radius: int = 2
@export_range(0.0, 1.0) var river_moisture_strength: float = 0.16
@export_range(0.0, 1.0) var lake_moisture_strength: float = 0.28
@export_range(0.0, 1.0) var ocean_moisture_strength: float = 0.32
@export var enable_oceans: bool = false
@export_range(0.0, 1.0) var sea_level: float = 0.40

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			result[property.name] = get(property.name)
	return result

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if generation_version != VERSION:
		errors.append("Unsupported hydrology generation version")
	if runoff_base <= 0 or moisture_runoff_influence < 0:
		errors.append("Runoff settings must be positive")
	if not (stream_threshold > 0 and stream_threshold < river_threshold and river_threshold < major_river_threshold):
		errors.append("River thresholds must be strictly increasing")
	if lake_min_cells < 1 or lake_max_cells < lake_min_cells:
		errors.append("Invalid lake size limits")
	if wetland_radius < 0:
		errors.append("Wetland radius must be nonnegative")
	return errors
