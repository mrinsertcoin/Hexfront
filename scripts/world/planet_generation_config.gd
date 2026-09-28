class_name PlanetGenerationConfig
extends Resource
## Serialization-friendly generation recipe. Independent from topology and gameplay.
const VERSION: int = 1
@export var world_seed: int = 48293617
@export var world_generation_version: int = VERSION

@export_group("Height")
@export var height_frequencies: Vector3 = Vector3(1.35, 3.8, 11.0)
@export var height_weights: Vector3 = Vector3(0.6, 0.3, 0.1)
@export var height_contrast: float = 1.5
@export var height_bias: float = 0.0
@export var height_warp_frequency: float = 1.7
@export var height_warp_strength: float = 0.08
@export_range(0.0, 1.0) var sea_level: float = 0.40 # Concept only; no water cells.

@export_group("Temperature")
@export var latitude_influence: float = 0.8
@export var latitude_exponent: float = 1.4
@export var temperature_noise_influence: float = 0.18
@export var temperature_frequency: float = 2.2
@export var elevation_cooling: float = 0.18
@export var temperature_bias: float = 0.18

@export_group("Moisture")
@export var moisture_frequencies: Vector2 = Vector2(1.6, 4.5)
@export var moisture_detail_weight: float = 0.2
@export var moisture_contrast: float = 1.7
@export var moisture_bias: float = 0.0

@export_group("Terrain roughness")
@export var roughness_frequency: float = 3.8
@export var roughness_contrast: float = 1.25
@export var roughness_detail_weight: float = 0.25

@export_group("Fertility")
@export var fertility_frequency: float = 3.0
@export var fertility_optimal_temperature: float = 0.6
@export var fertility_temperature_width: float = 0.6
@export var fertility_moisture_weight: float = 0.40
@export var fertility_temperature_weight: float = 0.25
@export var fertility_smoothness_weight: float = 0.20
@export var fertility_noise_weight: float = 0.15
@export var fertility_highland_penalty: float = 0.10

@export_group("Biomes")
@export var biomes: Array[BiomeDefinition] = BiomeDefinition.defaults()
@export var biome_variation_frequency: float = 4.0
@export var biome_variation_strength: float = 0.05

@export_group("Hydrology")
@export var hydrology: HydrologySettings = HydrologySettings.new()

@export_group("Regions")
@export var region_count: int = 14
@export var minimum_region_size: int = 12

func to_dict() -> Dictionary:
	var result: Dictionary = {}
	# Exported script values only; exclude Resource identity/path/editor metadata.
	for property: Dictionary in get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (property.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = get(property.name)
		if value is Vector3:
			value = [value.x, value.y, value.z]
		elif value is Vector2:
			value = [value.x, value.y]
		elif property.name == "biomes":
			value = []
			for biome: BiomeDefinition in biomes:
				value.append(biome.to_dict() if biome != null else {})
		elif property.name == "hydrology":
			value = hydrology.to_dict() if hydrology != null else {}
		# JSON numbers cannot preserve every 64-bit integer seed; encode as decimal text.
		elif property.name == "world_seed":
			value = str(world_seed)
		result[property.name] = value
	return result

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if world_generation_version != VERSION:
		errors.append("Unsupported world generation version")
	for key: String in to_dict():
		var value: Variant = get(key)
		if value is float and not is_finite(value):
			errors.append(key + " must be finite")
	if not height_frequencies.is_finite() or minf(height_frequencies.x, minf(height_frequencies.y, height_frequencies.z)) <= 0:
		errors.append("Height frequencies must be positive and finite")
	if not height_weights.is_finite() or minf(height_weights.x, minf(height_weights.y, height_weights.z)) < 0 or height_weights.x + height_weights.y + height_weights.z <= 0:
		errors.append("Height weights must be nonnegative with positive total")
	if not moisture_frequencies.is_finite() or minf(moisture_frequencies.x, moisture_frequencies.y) <= 0:
		errors.append("Moisture frequencies must be positive and finite")
	for key: String in ["height_contrast", "height_warp_frequency", "temperature_frequency", "latitude_exponent",
		"moisture_contrast", "roughness_frequency", "roughness_contrast", "fertility_frequency",
		"fertility_temperature_width", "biome_variation_frequency"]:
		if float(get(key)) <= 0:
			errors.append(key + " must be positive")
	for key: String in ["sea_level", "height_warp_strength", "moisture_detail_weight", "roughness_detail_weight", "biome_variation_strength", "fertility_optimal_temperature"]:
		if float(get(key)) < 0 or float(get(key)) > 1:
			errors.append(key + " must be in [0, 1]")
	for key: String in ["latitude_influence", "temperature_noise_influence", "elevation_cooling", "fertility_moisture_weight",
		"fertility_temperature_weight", "fertility_smoothness_weight", "fertility_noise_weight", "fertility_highland_penalty"]:
		if float(get(key)) < 0:
			errors.append(key + " must be nonnegative")
	if fertility_moisture_weight + fertility_temperature_weight + fertility_smoothness_weight + fertility_noise_weight <= 0:
		errors.append("Fertility weights require a positive total")
	if region_count < 1 or minimum_region_size < 1:
		errors.append("Region count and minimum size must be positive")
	if hydrology == null:
		errors.append("Hydrology settings are required")
	else:
		errors.append_array(hydrology.validate())
	var ids: Dictionary = {}
	if biomes.is_empty():
		errors.append("At least one biome is required")
	for biome: BiomeDefinition in biomes:
		if biome == null:
			errors.append("Null biome")
			continue
		if biome.biome_id.is_empty() or ids.has(biome.biome_id):
			errors.append("Biome IDs must be unique and nonempty")
		ids[biome.biome_id] = true
		if biome.centers.size() != 5 or biome.widths.size() != 5 or biome.influences.size() != 5:
			errors.append("Biome preferences require five values")
			continue
		if not is_finite(biome.prior) or biome.prior < 0:
			errors.append("Biome prior must be finite and nonnegative")
		for i in range(5):
			if not is_finite(biome.centers[i]) or biome.centers[i] < 0 or biome.centers[i] > 1 or not is_finite(biome.widths[i]) or biome.widths[i] <= 0 or not is_finite(biome.influences[i]) or biome.influences[i] < 0:
				errors.append("Invalid biome preference")
	return errors
