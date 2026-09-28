class_name PlanetFieldSampler
extends RefCounted
## Stateless queries over reusable explicitly configured 3D samplers.
var config: PlanetGenerationConfig
var noises: Dictionary[String, FastNoiseLite] = {}

static func derive_seed(world_seed: int, channel: String) -> int:
	# Versioned SHA-256 UTF-8 protocol, first 32 bits masked to positive signed int.
	# Does not use Variant.hash(), RNG sequence position or process identity.
	var digest: String = ("hexfront-seed-v1|%d|%s" % [world_seed, channel]).sha256_text()
	return digest.substr(0, 8).hex_to_int() & 0x7fffffff

func _init(recipe: PlanetGenerationConfig) -> void:
	config = recipe
	_add("height", config.height_frequencies.x)
	_add("height_regional", config.height_frequencies.y)
	_add("height_detail", config.height_frequencies.z)
	for axis: String in ["x", "y", "z"]:
		_add("height_warp/" + axis, config.height_warp_frequency)
	_add("temperature", config.temperature_frequency)
	_add("moisture", config.moisture_frequencies.x)
	_add("moisture_detail", config.moisture_frequencies.y)
	_add("fertility", config.fertility_frequency)
	_add("roughness", config.roughness_frequency)
	for biome: BiomeDefinition in config.biomes:
		_add("biome_variation/" + biome.biome_id, config.biome_variation_frequency)

func _add(channel: String, frequency: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = derive_seed(config.world_seed, channel)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = 1
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	noise.fractal_weighted_strength = 0.0
	noise.offset = Vector3.ZERO
	noise.domain_warp_enabled = false # Warp is an explicit independent vector field below.
	noises[channel] = noise

static func normalize_direction(direction: Vector3) -> Vector3:
	if not direction.is_finite() or direction == Vector3.ZERO:
		return Vector3.UP # Documented deterministic fallback for invalid directions.
	var scale: float = maxf(absf(direction.x), maxf(absf(direction.y), absf(direction.z)))
	return (direction / scale).normalized() # Avoid overflow for large finite inputs.

func _noise(channel: String, point: Vector3) -> float:
	return noises[channel].get_noise_3dv(point)

func sample_height(direction: Vector3) -> float:
	var p: Vector3 = normalize_direction(direction)
	if config.height_warp_strength > 0.0:
		p += Vector3(_noise("height_warp/x", p), _noise("height_warp/y", p), _noise("height_warp/z", p)) * config.height_warp_strength
	var weights: Vector3 = config.height_weights
	var value: float = (_noise("height", p) * weights.x + _noise("height_regional", p) * weights.y + _noise("height_detail", p) * weights.z) / (weights.x + weights.y + weights.z)
	return clampf(0.5 + value * 0.5 * config.height_contrast + config.height_bias, 0.0, 1.0)

func _temperature(p: Vector3, height: float) -> float:
	var latitude: float = 1.0 - pow(absf(p.y), config.latitude_exponent)
	return clampf(config.temperature_bias + latitude * config.latitude_influence +
		_noise("temperature", p) * config.temperature_noise_influence - height * config.elevation_cooling, 0.0, 1.0)

func sample_temperature(direction: Vector3) -> float:
	var p: Vector3 = normalize_direction(direction)
	return _temperature(p, sample_height(p))

func sample_moisture(direction: Vector3) -> float:
	var p: Vector3 = normalize_direction(direction)
	var value: float = lerpf(_noise("moisture", p), _noise("moisture_detail", p), config.moisture_detail_weight)
	return clampf(0.5 + value * 0.5 * config.moisture_contrast + config.moisture_bias, 0.0, 1.0)

func sample_terrain_roughness(direction: Vector3) -> float:
	var p: Vector3 = normalize_direction(direction)
	var base: float = 0.5 + 0.5 * _noise("roughness", p) * config.roughness_contrast
	return clampf(lerpf(base, absf(_noise("height_detail", p)), config.roughness_detail_weight), 0.0, 1.0)

func _fertility(p: Vector3, fields: PlanetWorldCellData) -> float:
	var warmth: float = clampf(1.0 - absf(fields.temperature - config.fertility_optimal_temperature) / config.fertility_temperature_width, 0.0, 1.0)
	var total: float = config.fertility_moisture_weight + config.fertility_temperature_weight + config.fertility_smoothness_weight + config.fertility_noise_weight
	var value: float = (fields.moisture * config.fertility_moisture_weight + warmth * config.fertility_temperature_weight +
		(1.0 - fields.terrain_roughness) * config.fertility_smoothness_weight +
		(0.5 + 0.5 * _noise("fertility", p)) * config.fertility_noise_weight) / total
	return clampf(value - fields.height * config.fertility_highland_penalty, 0.0, 1.0)

func sample_fields(direction: Vector3) -> PlanetWorldCellData:
	var p: Vector3 = normalize_direction(direction)
	var fields := PlanetWorldCellData.new()
	fields.height = sample_height(p)
	fields.temperature = _temperature(p, fields.height)
	fields.moisture = sample_moisture(p)
	fields.base_moisture = fields.moisture
	fields.effective_moisture = fields.moisture
	fields.terrain_roughness = sample_terrain_roughness(p)
	fields.fertility = _fertility(p, fields)
	return fields

func sample_fertility(direction: Vector3) -> float:
	return sample_fields(direction).fertility

func biome_weights(direction: Vector3, fields: PlanetWorldCellData) -> PackedFloat64Array:
	var p: Vector3 = normalize_direction(direction)
	var scores := PackedFloat64Array()
	var total: float = 0.0
	var values: PackedFloat64Array = fields.scalar_values()
	values[2] = fields.effective_moisture
	for biome: BiomeDefinition in config.biomes:
		var score: float = biome.score(values)
		score *= 1.0 + _noise("biome_variation/" + biome.biome_id, p) * config.biome_variation_strength
		score = maxf(0.0, score)
		scores.append(score)
		total += score
	if total <= 0.0:
		scores.fill(0.0)
		scores[0] = 1.0 # Deterministic fallback in declared biome order.
	else:
		for i in range(scores.size()):
			scores[i] /= total
	return scores

func sample_biome_weights(direction: Vector3) -> PackedFloat64Array:
	return biome_weights(direction, sample_fields(direction))

func dominant_biome(weights: PackedFloat64Array) -> String:
	var best: int = 0
	for i in range(1, weights.size()):
		if weights[i] > weights[best]:
			best = i
	return config.biomes[best].biome_id # First configured biome wins an exact tie.
